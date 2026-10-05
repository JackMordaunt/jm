package pq

import "core:c"
import "core:fmt"
import "core:mem"
import "core:strings"
import "core:unicode/utf8"

// Description is what the server says a statement takes and returns, without
// running it: the shape a code generator turns into typed parameters and row
// structs. describe fills it.
Description :: struct {
	// params[i] is the type of $(i+1), as pg_type.oid. The server infers a
	// parameter's type from where it stands — `id = $1` against a uuid column
	// is uuid — and a cast such as `$1::int` decides it outright.
	params:    []Oid,
	// The result columns, in order. Empty for a statement that returns no
	// rows, such as an UPDATE without RETURNING.
	columns:   []Column,
	allocator: mem.Allocator,
}

// Column is one result column of a described statement.
Column :: struct {
	name:         string,
	// The column's type, as pg_type.oid: 23 for int4, 2950 for uuid.
	type_oid:     Oid,
	// The type modifier, which is the type's own encoding of its declared
	// size: varchar(20) is 24 and numeric(10,2) is 655366. -1 when there is
	// none, as for most computed columns; a cast to varchar(5) keeps its 9.
	typmod:       int,
	// Where the column came from when it is a plain reference to a column of
	// a table or view: that relation's pg_class.oid and the column's 1-based
	// pg_attribute.attnum. Both are 0 for an expression or an aggregate.
	table_oid:    Oid,
	table_column: int,
}

// describe asks the server what sql takes and returns without running it,
// through libpq's prepare and describe. sql is exactly one statement, with $1,
// $2 and so on for its parameters.
//
// It prepares into the unnamed statement, which the session's next prepare,
// parameterised exec or plain exec replaces, so nothing is left behind to
// collide with or deallocate. A statement the server rejects — a syntax
// error, an unknown column, a schema the role may not use — comes back as a
// Fault with its SQLSTATE and position, as exec reports it.
//
// Privileges on tables and functions are checked when a statement runs, not
// when it is prepared, so describe succeeds for a table the role may not
// read. Inside a transaction block, a rejected statement fails the
// transaction as exec would.
describe :: proc(
	conn: ^Conn,
	sql: string,
	allocator := context.allocator,
) -> (
	desc: Description,
	err: Error,
) {
	if conn == nil || conn.raw == nil {
		return {}, refusal("the connection is closed", 0, allocator)
	}
	if i := strings.index_byte(sql, 0); i >= 0 {
		return {}, refusal(
			fmt.tprintf(
				"statement holds a NUL byte at offset %d, which libpq would read as its end",
				i,
			),
			utf8.rune_count_in_string(sql[:i]) + 1,
			allocator,
		)
	}
	text := strings.clone_to_cstring(sql, context.temp_allocator)
	prepared := PQprepare(conn.raw, "", text, 0, nil)
	if prepared == nil {
		return {}, Fault{message = clone_trimmed(PQerrorMessage(conn.raw), allocator)}
	}
	defer PQclear(prepared)
	if PQresultStatus(prepared) != .PGRES_COMMAND_OK {
		return {}, fault(conn, prepared, allocator)
	}

	described := PQdescribePrepared(conn.raw, "")
	if described == nil {
		return {}, Fault{message = clone_trimmed(PQerrorMessage(conn.raw), allocator)}
	}
	defer PQclear(described)
	if PQresultStatus(described) != .PGRES_COMMAND_OK {
		return {}, fault(conn, described, allocator)
	}
	return read_description(described, allocator), nil
}

// destroy_description frees everything in d and zeroes it. destroy is the
// name to call it by.
destroy_description :: proc(d: ^Description) {
	if d == nil {
		return
	}
	for col in d.columns {
		delete(col.name, d.allocator)
	}
	delete(d.columns, d.allocator)
	delete(d.params, d.allocator)
	d^ = {}
}

// not_null reports, for each column of desc, whether the table column it
// comes from is declared NOT NULL, from pg_attribute.attnotnull. A column
// with no source table — an expression, an aggregate — is false, and so is
// one read through a view, whose columns carry no constraint.
//
// true is the source column's constraint, not a promise about the result:
// the nullable side of an outer join can still produce NULL from a NOT NULL
// column. A generator that maps true to a plain type must look at the joins.
not_null :: proc(
	conn: ^Conn,
	desc: Description,
	allocator := context.allocator,
) -> (
	flags: []bool,
	err: Error,
) {
	tables := strings.builder_make(context.temp_allocator)
	attnums := strings.builder_make(context.temp_allocator)
	strings.write_byte(&tables, '{')
	strings.write_byte(&attnums, '{')
	for col, i in desc.columns {
		if i > 0 {
			strings.write_byte(&tables, ',')
			strings.write_byte(&attnums, ',')
		}
		fmt.sbprint(&tables, col.table_oid)
		fmt.sbprint(&attnums, col.table_column)
	}
	strings.write_byte(&tables, '}')
	strings.write_byte(&attnums, '}')

	// WITH ORDINALITY keeps the answer in column order, and the LEFT JOIN
	// keeps a row for a column with no source, which pg_attribute lacks.
	res := exec(
		conn,
		`SELECT coalesce(a.attnotnull, false)
		 FROM unnest($1::oid[], $2::int2[]) WITH ORDINALITY AS c(rel, num, ord)
		 LEFT JOIN pg_attribute a ON a.attrelid = c.rel AND a.attnum = c.num
		 ORDER BY c.ord`,
		{strings.to_string(tables), strings.to_string(attnums)},
		context.temp_allocator,
	) or_return
	defer destroy(&res)
	flags = make([]bool, len(res.rows), allocator)
	for row, i in res.rows {
		flags[i] = (row[0].? or_else "") == "t"
	}
	return flags, nil
}

// read_description clones a describe result's parameter types and columns
// out of libpq before the caller's PQclear frees them.
@(private)
read_description :: proc(res: ^PGresult, allocator: mem.Allocator) -> Description {
	desc := Description {
		allocator = allocator,
	}
	desc.params = make([]Oid, int(PQnparams(res)), allocator)
	for &p, i in desc.params {
		p = PQparamtype(res, c.int(i))
	}
	desc.columns = make([]Column, int(PQnfields(res)), allocator)
	for &col, i in desc.columns {
		f := c.int(i)
		col = Column {
			name         = strings.clone_from_cstring(PQfname(res, f), allocator),
			type_oid     = PQftype(res, f),
			typmod       = int(PQfmod(res, f)),
			table_oid    = PQftable(res, f),
			table_column = int(PQftablecol(res, f)),
		}
	}
	return desc
}
