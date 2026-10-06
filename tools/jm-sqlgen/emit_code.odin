package main

import "core:fmt"
import "core:strings"

// Driver is what the generated code needs to know about the jm package it
// calls. Everything else about a generated file is the same for every
// engine: its row structs, the signatures of its procs, the three ways in
// to a :many query, the free procs and check.
Driver :: struct {
	// The jm package the generated code calls, "sqlite3" or "pq", and its
	// import path.
	pkg:         string,
	import_path: string,
	// The connection's type: "sqlite3.Db".
	conn:        string,
	// The fields of a :many query's cursor struct, aligned, ending with err.
	cursor:      string,
	// open_into writes the statement that starts q into the cursor rows.
	open_into:   proc(sb: ^strings.Builder, q: Query),
	// one writes the body of a :one proc, which declares row, found and err.
	one:         proc(sb: ^strings.Builder, q: Query),
	// exec writes the body of an :exec proc, which returns an Error.
	exec:        proc(sb: ^strings.Builder, q: Query),
	// count writes the body of a :rows or :last_id proc, which declares n
	// and err.
	count:       proc(sb: ^strings.Builder, q: Query),
	// next writes the body of name_next, after the declaration of row and ok.
	next:        proc(sb: ^strings.Builder, q: Query),
	// close is the body of name_close, which sets rows.err and returns it.
	close:       string,
	// uses_fmt reports whether a query's procs format a message.
	uses_fmt:    proc(q: Query) -> bool,
}

// emit_code writes queries_gen.odin: a row struct and a proc per query over
// the driver's package, and a check proc. The column readers and the shape
// check they call live in that package, so each generated file holds only
// what its own queries need.
emit_code :: proc(
	d: Driver,
	pkg: string,
	queries: []Query,
	schema_text, queries_text: string,
) -> string {
	body: strings.Builder
	uses_fmt := false
	for q in queries {
		emit_query(&body, d, q)
		uses_fmt = uses_fmt || d.uses_fmt(q)
	}
	emit_check(&body, d, queries)

	sb: strings.Builder
	strings.write_string(&sb, GENERATED_HEADER)
	fmt.sbprintf(&sb, "\npackage %s\n\n", pkg)
	if uses_fmt {
		strings.write_string(&sb, "import \"core:fmt\"\n\n")
	}
	fmt.sbprintf(&sb, "import %q\n\n", d.import_path)
	strings.write_string(
		&sb,
		"// Editing either file without regenerating fails the build here.\n",
	)
	write_hash_guard(&sb, SCHEMA_FILE, schema_text)
	write_hash_guard(&sb, QUERIES_FILE, queries_text)
	strings.write_string(&sb, strings.to_string(body))
	return strings.to_string(sb)
}

@(private = "file")
emit_query :: proc(sb: ^strings.Builder, d: Driver, q: Query) {
	fmt.sbprintf(sb, "\n@(private = \"file\")\n%s :: ", sql_const(q))
	write_string_literal(sb, q.sql)
	strings.write_string(sb, "\n")
	if q.kind == .One || q.kind == .Many {
		emit_row(sb, q)
	}
	strings.write_byte(sb, '\n')
	if q.kind == .Many {
		emit_many(sb, d, q)
		return
	}
	write_doc(sb, q.doc)
	if len(q.doc) > 0 {
		strings.write_string(sb, "//\n")
	}
	fmt.sbprintf(sb, "// %s is %s in queries.sql.\n", q.name, QUERY_KIND_TAGS[q.kind])
	fmt.sbprintf(sb, "%s :: proc(\n\tdb: %s,\n%s", q.name, d.conn, param_list(q))
	strings.write_string(sb, "\tallocator := context.allocator,\n) -> ")
	switch q.kind {
	case .One:
		fmt.sbprintf(
			sb,
			"(\n\trow: %s_Row,\n\tfound: bool,\n\terr: %s.Error,\n) {{\n",
			ada_case(q.name),
			d.pkg,
		)
		d.one(sb, q)
		emit_free_row(sb, q)
	case .Many:
	// emit_many wrote it, above.
	case .Exec:
		fmt.sbprintf(sb, "%s.Error {{\n", d.pkg)
		d.exec(sb, q)
	case .Rows, .Last_Id:
		fmt.sbprintf(sb, "(\n\tn: i64,\n\terr: %s.Error,\n) {{\n", d.pkg)
		d.count(sb, q)
	}
}

// emit_many writes a :many query's three ways in: name_open, name_next and
// name_close, the raw cursor; name, the cursor as a guard that closes at the
// end of its block; and name_all, every row in a slice.
@(private = "file")
emit_many :: proc(sb: ^strings.Builder, d: Driver, q: Query) {
	n := q.name
	row := fmt.aprintf("%s_Row", ada_case(n))
	rows := fmt.aprintf("%s_Rows", ada_case(n))
	params := param_list(q)
	args := arg_list(q)

	fmt.sbprintf(
		sb,
		"// %s is a cursor over the rows of %s. err is what stopped it, once it\n",
		rows,
		n,
	)
	strings.write_string(
		sb,
		"// is closed: a failed start, a failed step, or a value of the wrong type.\n",
	)
	fmt.sbprintf(sb, "%s :: struct {{\n%s}}\n\n", rows, d.cursor)

	write_doc(sb, q.doc)
	if len(q.doc) > 0 {
		strings.write_string(sb, "//\n")
	}
	fmt.sbprintf(sb, "// %s is :many in queries.sql: %s_open as a guard. Written\n", n, n)
	fmt.sbprintf(
		sb,
		"// `if %s(&rows, db, ...) {{ for row in %s_next(&rows) {{ ... }} }}`, it closes\n",
		n,
		n,
	)
	strings.write_string(
		sb,
		"// the cursor at the end of the if and leaves what stopped it in rows.err,\n",
	)
	strings.write_string(
		sb,
		"// which a deferred close cannot return. It is false if the query cannot start.\n",
	)
	fmt.sbprintf(sb, "@(deferred_in = %s_guard_close)\n", n)
	fmt.sbprintf(
		sb,
		"%s :: proc(\n\trows: ^%s,\n\tdb: %s,\n" +
		"%s\tallocator := context.allocator,\n) -> bool {{\n",
		n,
		rows,
		d.conn,
		params,
	)
	fmt.sbprintf(sb, "\topened, err := %s_open(db, %sallocator)\n", n, args)
	strings.write_string(sb, "\trows^ = opened\n\trows.err = err\n\treturn err == nil\n}\n\n")
	fmt.sbprintf(
		sb,
		"@(private = \"file\")\n%s_guard_close :: proc(\n\trows: ^%s,\n" +
		"\tdb: %s,\n%s\tallocator := context.allocator,\n) {{\n",
		n,
		rows,
		d.conn,
		params,
	)
	fmt.sbprintf(sb, "\t%s_close(rows)\n}}\n\n", n)

	fmt.sbprintf(
		sb,
		"// %s_open starts %s: step the cursor with %s_next and end it with\n",
		n,
		n,
		n,
	)
	fmt.sbprintf(sb, "// %s_close. Text and blobs are allocated in allocator.\n", n)
	fmt.sbprintf(
		sb,
		"%s_open :: proc(\n\tdb: %s,\n%s\tallocator := context.allocator,\n) -> (\n",
		n,
		d.conn,
		params,
	)
	fmt.sbprintf(sb, "\trows: %s,\n\terr: %s.Error,\n) {{\n", rows, d.pkg)
	d.open_into(sb, q)
	strings.write_string(sb, "\treturn\n}\n\n")

	fmt.sbprintf(sb, "// %s_next reads the next row; ok is false at the end or on a failure.\n", n)
	fmt.sbprintf(sb, "%s_next :: proc(rows: ^%s) -> (row: %s, ok: bool) {{\n", n, rows, row)
	d.next(sb, q)

	fmt.sbprintf(sb, "// %s_close ends the cursor and returns what stopped it, which it also\n", n)
	strings.write_string(sb, "// keeps in rows.err. Closing twice is safe.\n")
	fmt.sbprintf(
		sb,
		"%s_close :: proc(rows: ^%s) -> %s.Error {{\n%s}}\n\n",
		n,
		rows,
		d.pkg,
		d.close,
	)

	fmt.sbprintf(
		sb,
		"// %s_all reads every row of %s into a slice in allocator, with their\n",
		n,
		n,
	)
	fmt.sbprintf(
		sb,
		"// text and blobs; free it with %s_free. On a failure it frees what it read.\n",
		n,
	)
	fmt.sbprintf(
		sb,
		"%s_all :: proc(\n\tdb: %s,\n%s\tallocator := context.allocator,\n) -> (\n",
		n,
		d.conn,
		params,
	)
	fmt.sbprintf(sb, "\tall: []%s,\n\terr: %s.Error,\n) {{\n", row, d.pkg)
	fmt.sbprintf(sb, "\trows := %s_open(db, %sallocator) or_return\n", n, args)
	fmt.sbprintf(sb, "\tout := make([dynamic]%s, allocator)\n", row)
	fmt.sbprintf(sb, "\tfor row in %s_next(&rows) {{\n\t\tappend(&out, row)\n\t}}\n", n)
	fmt.sbprintf(sb, "\tif err = %s_close(&rows); err != nil {{\n", n)
	fmt.sbprintf(sb, "\t\t%s_free(out[:], allocator)\n", n)
	strings.write_string(sb, "\t\treturn nil, err\n\t}\n\treturn out[:], nil\n}\n")
	emit_free_row(sb, q)
	emit_free_all(sb, q)
}

// owns_memory reports whether a row of q holds text or a blob, which the
// readers allocate.
owns_memory :: proc(q: Query) -> bool {
	for f in q.fields {
		if f.type.kind == .String || f.type.kind == .Bytes {
			return true
		}
	}
	return false
}

// emit_free_row writes name_free_row, which frees a row's text and blobs.
// Every :one and :many has one, whether or not its rows hold anything to
// free, so a caller need not know which.
@(private = "file")
emit_free_row :: proc(sb: ^strings.Builder, q: Query) {
	n := q.name
	fmt.sbprintf(
		sb,
		"\n// %s_free_row frees the text and blobs of row, which are in allocator.\n",
		n,
	)
	fmt.sbprintf(
		sb,
		"%s_free_row :: proc(row: %s_Row, allocator := context.allocator) {{\n",
		n,
		ada_case(n),
	)
	for f in q.fields {
		if f.type.kind != .String && f.type.kind != .Bytes {
			continue
		}
		if f.type.nullable {
			fmt.sbprintf(
				sb,
				"\tif v, ok := row.%s.?; ok {{\n\t\tdelete(v, allocator)\n\t}}\n",
				f.name,
			)
		} else {
			fmt.sbprintf(sb, "\tdelete(row.%s, allocator)\n", f.name)
		}
	}
	strings.write_string(sb, "}\n")
}

// emit_free_all writes name_free, which frees a slice of rows as name_all
// returns it.
@(private = "file")
emit_free_all :: proc(sb: ^strings.Builder, q: Query) {
	n := q.name
	fmt.sbprintf(
		sb,
		"\n// %s_free frees all, as %s_all returns it, with every row's text and\n",
		n,
		n,
	)
	strings.write_string(sb, "// blobs.\n")
	fmt.sbprintf(
		sb,
		"%s_free :: proc(all: []%s_Row, allocator := context.allocator) {{\n",
		n,
		ada_case(n),
	)
	if owns_memory(q) {
		fmt.sbprintf(sb, "\tfor row in all {{\n\t\t%s_free_row(row, allocator)\n\t}}\n", n)
	}
	strings.write_string(sb, "\tdelete(all, allocator)\n}\n")
}

// param_list is q's parameters as a proc's parameter lines, in the order the
// -- params: line declares them.
@(private = "file")
param_list :: proc(q: Query) -> string {
	sb: strings.Builder
	for param in q.annotations {
		fmt.sbprintf(&sb, "\t%s: %s,\n", param.name, type_name(param.type))
	}
	return strings.to_string(sb)
}

// arg_list is q's parameters as call arguments, each followed by ", ".
@(private = "file")
arg_list :: proc(q: Query) -> string {
	sb: strings.Builder
	for param in q.annotations {
		fmt.sbprintf(&sb, "%s, ", param.name)
	}
	return strings.to_string(sb)
}

@(private = "file")
emit_row :: proc(sb: ^strings.Builder, q: Query) {
	fmt.sbprintf(
		sb,
		"\n// %s_Row is a row of %s. Text and blob fields are allocated in the\n",
		ada_case(q.name),
		q.name,
	)
	strings.write_string(sb, "// allocator the query was given.\n")
	fmt.sbprintf(sb, "%s_Row :: struct {{\n", ada_case(q.name))
	width := 0
	for f in q.fields {
		width = max(width, len(f.name))
	}
	for f in q.fields {
		pad := strings.repeat(" ", width - len(f.name))
		fmt.sbprintf(sb, "\t%s: %s%s,", f.name, pad, type_name(f.type))
		switch {
		case f.annotated:
			strings.write_string(sb, " // annotated, not inferred")
		case f.why != "":
			fmt.sbprintf(sb, " // Maybe: %s", f.why)
		}
		strings.write_byte(sb, '\n')
	}
	strings.write_string(sb, "}\n")
}

@(private = "file")
emit_check :: proc(sb: ^strings.Builder, d: Driver, queries: []Query) {
	fmt.sbprintf(
		sb,
		`
// check prepares every query against db and compares the parameters and
// columns each has there with those it was generated for, so a database
// whose schema has drifted from schema.sql fails when it is opened rather
// than when a query first runs.
check :: proc(db: %s, allocator := context.allocator) -> %s.Error {{
`,
		d.conn,
		d.pkg,
	)
	for q in queries {
		fmt.sbprintf(
			sb,
			"\t%s.check_statement(\n\t\tdb,\n\t\t%q,\n\t\t%s,\n",
			d.pkg,
			q.name,
			sql_const(q),
		)
		fmt.sbprintf(sb, "\t\t%d,\n\t\t{{", len(q.params))
		for f, i in q.fields {
			if i > 0 {
				strings.write_string(sb, ", ")
			}
			fmt.sbprintf(sb, "%q", f.column)
		}
		strings.write_string(sb, "},\n\t\tallocator,\n\t) or_return\n")
	}
	strings.write_string(sb, "\treturn nil\n}\n")
}

// reader is the name of the jm read proc for a field: read_exact, or
// read_exact_maybe when the field may be NULL.
reader :: proc(f: Field) -> string {
	return f.type.nullable ? "read_exact_maybe" : "read_exact"
}
