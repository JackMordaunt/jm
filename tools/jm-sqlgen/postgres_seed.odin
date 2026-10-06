package main

import "core:fmt"
import "core:strconv"
import "core:strings"

import "jm:pq"

// pg_seed_tables is every ordinary table the schema made, in name order, as
// the data sets fill it. An identity column that is GENERATED ALWAYS and a
// generated column take no value in an INSERT, so they are left out.
pg_seed_tables :: proc(pg: ^Pg, p: ^Problems) -> []Seed_Table {
	res, err := pq.exec(
		pg.conn,
		`SELECT n.nspname, c.relname, a.attname, a.atttypid::int8, a.attnotnull
		 FROM pg_class c
		 JOIN pg_namespace n ON n.oid = c.relnamespace
		 JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
		 WHERE c.relkind IN ('r', 'p') AND NOT c.relispartition
		 AND n.nspname NOT IN ('pg_catalog', 'information_schema')
		 AND n.nspname NOT LIKE 'pg\_%'
		 AND a.attidentity <> 'a' AND a.attgenerated = ''
		 ORDER BY n.nspname, c.relname, a.attnum`,
	)
	if err != nil {
		problem(p, SCHEMA_FILE, 0, "reading the tables to seed: %s", pg_text(err))
		return nil
	}
	tables: [dynamic]Seed_Table
	cols: [dynamic]Seed_Column
	current := ""
	for row in res.rows {
		schema, table := row[0].? or_else "", row[1].? or_else ""
		name := fmt.aprintf("%s.%s", quoted_name(schema), quoted_name(table))
		if name != current {
			if current != "" {
				tables[len(tables) - 1].columns = cols[:]
				cols = {}
			}
			append(&tables, Seed_Table{name = name, label = table})
			current = name
		}
		oid, _ := strconv.parse_u64(row[3].? or_else "")
		t := pg_type(pg, pq.Oid(oid))
		c := Seed_Column {
			name     = row[2].? or_else "",
			not_null = (row[4].? or_else "") == "t",
		}
		for v in Seed_Value {
			c.literal[v] = pg_literal(t, v)
		}
		append(&cols, c)
	}
	if current != "" {
		tables[len(tables) - 1].columns = cols[:]
	}
	return tables[:]
}

// pg_literal is a column's value in each set, as text the column's type
// reads: the set's own extreme where the type has one, a plain value where
// it does not, and DEFAULT for a type the sets know nothing about.
@(private = "file")
pg_literal :: proc(t: Pg_Type, v: Seed_Value) -> string {
	pick :: proc(v: Seed_Value, base, low, high: string) -> string {
		switch v {
		case .Base:
			return base
		case .Low:
			return low
		case .High:
			return high
		}
		return base
	}
	switch {
	case t.array:
		return "'{}'"
	case len(t.labels) > 0:
		return pg_quote(pick(v, t.labels[0], t.labels[0], t.labels[len(t.labels) - 1]))
	}
	switch t.base {
	case 16:
		return pick(v, "'t'", "'f'", "'t'")
	case 21:
		return pg_int(v, i64(min(i16)), i64(max(i16)))
	case 23:
		return pg_int(v, i64(min(i32)), i64(max(i32)))
	case 20, 26:
		return pg_int(v, min(i64), max(i64))
	case 700:
		return pick(v, "'1.5'", "'-1.5'", fmt.aprintf("'%v'", max(f32)))
	case 701, 1700, 790:
		return pick(v, "'1.5'", "'-1.5'", "'1e+300'")
	case 17:
		return pick(v, `'\x61'`, `'\x'`, `'\x00ff'`)
	case 18, 19, 25, 1042, 1043:
		return pg_quote(pick(v, BASE.text_v, LOW.text_v, HIGH.text_v))
	case 114, 3802:
		return pick(v, "'{}'", "'[]'", `'{"k": "zß€😀"}'`)
	case 142:
		return "'<a/>'"
	case 2950:
		return pick(
			v,
			"'00000000-0000-0000-0000-000000000001'",
			"'00000000-0000-0000-0000-000000000000'",
			"'ffffffff-ffff-ffff-ffff-ffffffffffff'",
		)
	case 1082:
		return pick(v, "'2000-01-01'", "'1970-01-01'", "'9999-12-31'")
	case 1083:
		return pick(v, "'12:00:00'", "'00:00:00'", "'23:59:59'")
	case 1266:
		return pick(v, "'12:00:00+00'", "'00:00:00+00'", "'23:59:59+00'")
	case 1114:
		return pick(v, "'2000-01-01 00:00:00'", "'1970-01-01 00:00:00'", "'9999-12-31 23:59:59'")
	case 1184:
		return pick(
			v,
			"'2000-01-01 00:00:00+00'",
			"'1970-01-01 00:00:00+00'",
			"'9999-12-31 23:59:59+00'",
		)
	case 1186:
		return pick(v, "'1 day'", "'0'", "'1000 years'")
	case 650, 869:
		return pick(v, "'127.0.0.1'", "'0.0.0.0'", "'255.255.255.255'")
	case 829:
		return "'08:00:2b:01:02:03'"
	case 774:
		return "'08:00:2b:01:02:03:04:05'"
	case 1560, 1562:
		return pick(v, "'1'", "'0'", "'1'")
	}
	return "DEFAULT"
}

@(private = "file")
pg_int :: proc(v: Seed_Value, low, high: i64) -> string {
	switch v {
	case .Base:
		return "'1'"
	case .Low:
		return fmt.aprintf("'%d'", low)
	case .High:
		return fmt.aprintf("'%d'", high)
	}
	return "'1'"
}

@(private = "file")
pg_quote :: proc(s: string) -> string {
	sb: strings.Builder
	write_text_literal(&sb, s)
	return strings.to_string(sb)
}

// Pg_Seeding is the server the data sets are built on, and the schema each
// starts from.
Pg_Seeding :: struct {
	pg:     ^Pg,
	schema: string,
}

// pg_seeder builds each data set in a transaction of its own on the
// throwaway server, with the schema run first, and tries a row inside a
// savepoint. The transaction is rolled back once the set is built.
pg_seeder :: proc(s: ^Pg_Seeding) -> Seeder {
	run :: proc(s: ^Pg_Seeding, sql: string) -> string {
		_, err := pq.exec(s.pg.conn, sql)
		return err == nil ? "" : pg_text(err)
	}
	start :: proc(user: rawptr) -> string {
		s := (^Pg_Seeding)(user)
		if why := run(s, "BEGIN"); why != "" {
			return why
		}
		if why := run(s, PG_NO_FOREIGN_KEYS); why != "" {
			return why
		}
		return run(s, s.schema)
	}
	try :: proc(user: rawptr, sql: string) -> string {
		s := (^Pg_Seeding)(user)
		if why := run(s, "SAVEPOINT seed"); why != "" {
			return why
		}
		why := run(s, sql)
		if rwhy := run(s, "ROLLBACK TO SAVEPOINT seed"); rwhy != "" {
			return rwhy
		}
		if rwhy := run(s, "RELEASE SAVEPOINT seed"); rwhy != "" {
			return rwhy
		}
		return why
	}
	keep :: proc(user: rawptr, sql: string) -> string {
		return run((^Pg_Seeding)(user), sql)
	}
	finish :: proc(user: rawptr) {
		run((^Pg_Seeding)(user), "ROLLBACK")
	}
	return Seeder{user = s, start = start, try = try, keep = keep, finish = finish}
}

// PG_NO_FOREIGN_KEYS stops the transaction checking foreign keys, which
// PostgreSQL implements as triggers that the replica role skips. A data set
// holds one row a table, or one table alone, so a child row has no parent
// to point at; SQLite does not check foreign keys unless asked, and the sets
// are the same for both. It needs a superuser, which the throwaway server's
// is.
PG_NO_FOREIGN_KEYS :: "SET LOCAL session_replication_role = replica"
