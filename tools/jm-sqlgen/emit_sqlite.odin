package main

import "core:fmt"
import "core:strings"

// emit_sqlite_code writes queries_gen.odin: a row struct and a proc per
// query over jm:sqlite3, and a check proc. The column readers and the shape
// check they call live in jm:sqlite3, so each generated file holds only what
// its own queries need.
emit_sqlite_code :: proc(
	pkg: string,
	queries: []Query,
	schema_text, queries_text: string,
) -> string {
	body: strings.Builder
	uses_fmt := false
	for q in queries {
		emit_query(&body, q)
		uses_fmt = uses_fmt || q.kind == .One
	}
	emit_check(&body, queries)

	sb: strings.Builder
	strings.write_string(&sb, GENERATED_HEADER)
	fmt.sbprintf(&sb, "\npackage %s\n\n", pkg)
	if uses_fmt {
		strings.write_string(&sb, "import \"core:fmt\"\n\n")
	}
	strings.write_string(&sb, "import \"jm:sqlite3\"\n\n")
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
emit_query :: proc(sb: ^strings.Builder, q: Query) {
	fmt.sbprintf(sb, "\n@(private = \"file\")\n%s :: ", sql_const(q))
	write_string_literal(sb, q.sql)
	strings.write_string(sb, "\n")
	if q.kind == .One || q.kind == .Many {
		emit_row(sb, q)
	}
	strings.write_byte(sb, '\n')
	if q.kind == .Many {
		emit_many(sb, q)
		return
	}
	write_doc(sb, q.doc)
	if len(q.doc) > 0 {
		strings.write_string(sb, "//\n")
	}
	fmt.sbprintf(sb, "// %s is %s in queries.sql.\n", q.name, QUERY_KIND_TAGS[q.kind])
	fmt.sbprintf(sb, "%s :: proc(\n\tdb: sqlite3.Db,\n", q.name)
	for param in q.annotations {
		fmt.sbprintf(sb, "\t%s: %s,\n", param.name, type_name(param.type))
	}
	strings.write_string(sb, "\tallocator := context.allocator,\n) -> ")
	row := fmt.aprintf("%s_Row", ada_case(q.name))
	switch q.kind {
	case .One:
		fmt.sbprintf(sb, "(\n\trow: %s,\n\tfound: bool,\n\terr: sqlite3.Error,\n) {{\n", row)
		emit_query_call(sb, "stmt :=", q)
		strings.write_string(sb, "\tif sqlite3.next(&stmt) {\n\t\tfound = true\n")
		emit_reads(sb, q, "row", "&stmt", "\t\t")
		fmt.sbprintf(sb, "\t\tif stmt.err == nil && sqlite3.next(&stmt) {{\n")
		fmt.sbprintf(sb, "\t\t\tstmt.err = sqlite3.Fault {{\n\t\t\t\tcode = .Misuse,\n")
		fmt.sbprintf(
			sb,
			"\t\t\t\ttext = fmt.aprint(\"%s is :one but returned a second row\", allocator = allocator),\n" +
			"\t\t\t}}\n\t\t}}\n\t}}\n",
			q.name,
		)
		strings.write_string(
			sb,
			"\tif err = sqlite3.finish(&stmt); err != nil {\n\t\treturn {}, false, err\n\t}\n\treturn\n}\n",
		)
	case .Many:
	// emit_many wrote it, above.
	case .Exec:
		strings.write_string(sb, "sqlite3.Error {\n")
		emit_query_call(sb, "stmt :=", q)
		strings.write_string(
			sb,
			"\tfor sqlite3.next(&stmt) {}\n\treturn sqlite3.finish(&stmt)\n}\n",
		)
	case .Rows, .Last_Id:
		strings.write_string(sb, "(\n\tn: i64,\n\terr: sqlite3.Error,\n) {\n")
		emit_query_call(sb, "stmt :=", q)
		strings.write_string(
			sb,
			"\tfor sqlite3.next(&stmt) {}\n\tsqlite3.finish(&stmt) or_return\n",
		)
		fmt.sbprintf(
			sb,
			"\treturn sqlite3.%s(db), nil\n}}\n",
			q.kind == .Rows ? "changes" : "last_id",
		)
	}
}


// emit_many writes a :many query's three ways in: name_open, name_next and
// name_close, the raw cursor; name, the cursor as a guard that closes at the
// end of its block; and name_all, every row in a slice.
@(private = "file")
emit_many :: proc(sb: ^strings.Builder, q: Query) {
	n := q.name
	row := fmt.aprintf("%s_Row", ada_case(n))
	rows := fmt.aprintf("%s_Rows", ada_case(n))
	owns := owns_memory(q)
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
	fmt.sbprintf(
		sb,
		"%s :: struct {{\n\tstmt: sqlite3.Stmt,\n\terr:  sqlite3.Error,\n}}\n\n",
		rows,
	)

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
		"%s :: proc(\n\trows: ^%s,\n\tdb: sqlite3.Db,\n" +
		"%s\tallocator := context.allocator,\n) -> bool {{\n",
		n,
		rows,
		params,
	)
	fmt.sbprintf(sb, "\topened, err := %s_open(db, %sallocator)\n", n, args)
	strings.write_string(sb, "\trows^ = opened\n\trows.err = err\n\treturn err == nil\n}\n\n")
	fmt.sbprintf(
		sb,
		"@(private = \"file\")\n%s_guard_close :: proc(\n\trows: ^%s,\n" +
		"\tdb: sqlite3.Db,\n%s\tallocator := context.allocator,\n) {{\n",
		n,
		rows,
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
		"%s_open :: proc(\n\tdb: sqlite3.Db,\n%s\tallocator := context.allocator,\n) -> (\n",
		n,
		params,
	)
	fmt.sbprintf(sb, "\trows: %s,\n\terr: sqlite3.Error,\n) {{\n", rows)
	emit_query_call(sb, "rows.stmt =", q)
	strings.write_string(sb, "\treturn\n}\n\n")

	fmt.sbprintf(sb, "// %s_next reads the next row; ok is false at the end or on a failure.\n", n)
	fmt.sbprintf(sb, "%s_next :: proc(rows: ^%s) -> (row: %s, ok: bool) {{\n", n, rows, row)
	strings.write_string(sb, "\tif !sqlite3.next(&rows.stmt) {\n\t\treturn\n\t}\n")
	emit_reads(sb, q, "row", "&rows.stmt", "\t")
	if owns {
		strings.write_string(sb, "\tif rows.stmt.err != nil {\n")
		fmt.sbprintf(
			sb,
			"\t\t%s_free_row(row, rows.stmt.allocator)\n\t\treturn {{}}, false\n\t}}\n",
			n,
		)
		strings.write_string(sb, "\treturn row, true\n}\n\n")
	} else {
		strings.write_string(sb, "\treturn row, rows.stmt.err == nil\n}\n\n")
	}

	fmt.sbprintf(sb, "// %s_close ends the cursor and returns what stopped it, which it also\n", n)
	strings.write_string(sb, "// keeps in rows.err. Closing twice is safe.\n")
	fmt.sbprintf(sb, "%s_close :: proc(rows: ^%s) -> sqlite3.Error {{\n", n, rows)
	strings.write_string(
		sb,
		"\tif err := sqlite3.finish(&rows.stmt); rows.err == nil {\n\t\trows.err = err\n\t}\n",
	)
	strings.write_string(sb, "\treturn rows.err\n}\n\n")

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
		"%s_all :: proc(\n\tdb: sqlite3.Db,\n%s\tallocator := context.allocator,\n) -> (\n",
		n,
		params,
	)
	fmt.sbprintf(sb, "\tall: []%s,\n\terr: sqlite3.Error,\n) {{\n", row)
	fmt.sbprintf(sb, "\trows := %s_open(db, %sallocator) or_return\n", n, args)
	fmt.sbprintf(sb, "\tout := make([dynamic]%s, allocator)\n", row)
	fmt.sbprintf(sb, "\tfor row in %s_next(&rows) {{\n\t\tappend(&out, row)\n\t}}\n", n)
	fmt.sbprintf(sb, "\tif err = %s_close(&rows); err != nil {{\n", n)
	fmt.sbprintf(sb, "\t\t%s_free(out[:], allocator)\n", n)
	strings.write_string(sb, "\t\treturn nil, err\n\t}\n\treturn out[:], nil\n}\n")
	emit_free(sb, q, row)
}

// owns_memory reports whether a row of q holds text or a blob, which the
// readers allocate.
@(private = "file")
owns_memory :: proc(q: Query) -> bool {
	for f in q.fields {
		if f.type.kind == .String || f.type.kind == .Bytes {
			return true
		}
	}
	return false
}

// emit_free writes name_free_row, which frees a row's text and blobs, and
// name_free, which frees a slice of rows as name_all returns it. Both exist
// for every :many, whether or not its rows hold anything to free, so a
// caller need not know which.
@(private = "file")
emit_free :: proc(sb: ^strings.Builder, q: Query, row: string) {
	n := q.name
	fmt.sbprintf(
		sb,
		"\n// %s_free_row frees the text and blobs of row, which are in allocator.\n",
		n,
	)
	fmt.sbprintf(sb, "%s_free_row :: proc(row: %s, allocator := context.allocator) {{\n", n, row)
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
	fmt.sbprintf(
		sb,
		"\n// %s_free frees all, as %s_all returns it, with every row's text and\n",
		n,
		n,
	)
	strings.write_string(sb, "// blobs.\n")
	fmt.sbprintf(sb, "%s_free :: proc(all: []%s, allocator := context.allocator) {{\n", n, row)
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
emit_query_call :: proc(sb: ^strings.Builder, lhs: string, q: Query) {
	fmt.sbprintf(sb, "\t%s sqlite3.query(\n\t\tdb,\n\t\t%s,\n", lhs, sql_const(q))
	for param in q.params {
		if param.type.nullable {
			fmt.sbprintf(sb, "\t\tsqlite3.nullable(%s),\n", param.name)
		} else {
			fmt.sbprintf(sb, "\t\t%s,\n", param.name)
		}
	}
	strings.write_string(sb, "\t\tallocator = allocator,\n\t) or_return\n")
}

@(private = "file")
emit_reads :: proc(sb: ^strings.Builder, q: Query, row, stmt, indent: string) {
	for f, i in q.fields {
		reader := f.type.nullable ? "read_exact_maybe" : "read_exact"
		fmt.sbprintf(
			sb,
			"%s%s.%s = sqlite3.%s(%s, %d, %s)\n",
			indent,
			row,
			f.name,
			reader,
			stmt,
			i,
			KIND_NAMES[f.type.kind],
		)
	}
}

@(private = "file")
emit_check :: proc(sb: ^strings.Builder, queries: []Query) {
	strings.write_string(
		sb,
		`
// check prepares every query against db and compares the parameters and
// columns each has there with those it was generated for, so a database
// whose schema has drifted from schema.sql fails when it is opened rather
// than when a query first runs.
check :: proc(db: sqlite3.Db, allocator := context.allocator) -> sqlite3.Error {
`,
	)
	for q in queries {
		fmt.sbprintf(
			sb,
			"\tsqlite3.check_statement(\n\t\tdb,\n\t\t%q,\n\t\t%s,\n",
			q.name,
			sql_const(q),
		)
		fmt.sbprintf(sb, "\t\t%d,\n\t\t{{", len(q.params))
		for f, i in q.fields {
			if i > 0 {
				strings.write_string(sb, ", ")
			}
			name := f.name
			if f.annotated {
				name = fmt.aprintf("%s: %s", f.name, type_name(f.type))
			}
			fmt.sbprintf(sb, "%q", name)
		}
		strings.write_string(sb, "},\n\t\tallocator,\n\t) or_return\n")
	}
	strings.write_string(sb, "\treturn nil\n}\n")
}

// emit_sqlite_test writes queries_gen_test.odin: every query run against
// every data set through the generated procs, failing on any error a
// constraint the set happens to break does not explain.
emit_sqlite_test :: proc(pkg: string, queries: []Query, sets: []Data_Set) -> string {
	sb: strings.Builder
	strings.write_string(&sb, GENERATED_HEADER)
	fmt.sbprintf(&sb, "\npackage %s\n\nimport \"core:testing\"\n\nimport \"jm:sqlite3\"\n", pkg)
	strings.write_string(
		&sb,
		`
@(private = "file")
Sqlgen_Set :: struct {
	name:   string,
	seed:   string,
	int_v:  i64,
	real_v: f64,
	text_v: string,
	blob_v: string,
	bool_v: bool,
	nulls:  bool,
}

// SQLGEN_SETS are the database states every query runs against: nothing at
// all, which empties aggregates and subqueries; every nullable column NULL;
// the extremes of each type; and each table alone, which leaves the other
// side of an outer join missing.
`,
	)
	for set in sets {
		for note in set.notes {
			write_comment(&sb, fmt.tprintf("%s: %s.", set.name, note))
		}
	}
	strings.write_string(&sb, "@(private = \"file\")\nSQLGEN_SETS := [?]Sqlgen_Set {\n")
	for set in sets {
		v := set.value
		fmt.sbprintf(&sb, "\t{{\n\t\tname = %q,\n\t\tseed = ", set.name)
		write_string_literal(&sb, set.seed)
		fmt.sbprintf(&sb, ",\n\t\tint_v = %d,\n\t\treal_v = %v,\n\t\ttext_v = ", v.int_v, v.real_v)
		write_string_literal(&sb, v.text_v)
		strings.write_string(&sb, ",\n\t\tblob_v = ")
		write_string_literal(&sb, v.blob_v)
		fmt.sbprintf(&sb, ",\n\t\tbool_v = %v,\n\t\tnulls = %v,\n\t}},\n", v.bool_v, set.nulls)
	}
	strings.write_string(&sb, "}\n")
	strings.write_string(
		&sb,
		`
// Each query runs in every data set through its generated proc, which
// checks every value it reads against the type it was generated with. check
// runs too, against the schema as SQLite holds it.
@(test)
sqlgen_queries_hold_their_types :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	for set in SQLGEN_SETS {
		db, err := sqlite3.open(sqlite3.MEMORY)
		if !testing.expectf(t, err == nil, "data set %s: open: %v", set.name, err) {
			return
		}
		defer sqlite3.close(&db)
		testing.expect_value(t, sqlite3.exec(db, #load("schema.sql", string)), nil)
		testing.expect_value(t, sqlite3.exec(db, set.seed), nil)
		testing.expect_value(t, check(db), nil)
		sqlgen_run(t, db, set)
	}
}

@(private = "file")
sqlgen_run :: proc(t: ^testing.T, db: sqlite3.Db, set: Sqlgen_Set) {
`,
	)
	for q in queries {
		emit_test_call(&sb, q)
	}
	strings.write_string(
		&sb,
		`}

@(private = "file")
sqlgen_maybe :: proc(v: $T, null: bool) -> Maybe(T) {
	if null {
		return nil
	}
	return v
}

@(private = "file")
sqlgen_begin :: proc(t: ^testing.T, db: sqlite3.Db) {
	testing.expect_value(t, sqlite3.exec(db, "SAVEPOINT sqlgen"), nil)
}

// sqlgen_end undoes what the query changed, and fails the test unless the
// query succeeded or a constraint the data set happens to break refused it.
// A STRICT column refusing a parameter's type is not such a constraint.
@(private = "file")
sqlgen_end :: proc(
	t: ^testing.T,
	db: sqlite3.Db,
	set: Sqlgen_Set,
	query: string,
	err: sqlite3.Error,
) {
	testing.expect_value(t, sqlite3.exec(db, "ROLLBACK TO sqlgen; RELEASE sqlgen"), nil)
	f, failed := err.(sqlite3.Fault)
	if !failed {
		return
	}
	broke_a_constraint := f.code == .Constraint && f.extended != sqlite3.CONSTRAINT_DATATYPE
	testing.expectf(t, broke_a_constraint, "data set %s: %s: %v: %s", set.name, query, f.code, f.text)
}
`,
	)
	return strings.to_string(sb)
}

@(private = "file")
emit_test_call :: proc(sb: ^strings.Builder, q: Query) {
	args: strings.Builder
	strings.write_string(&args, "db")
	for param in q.annotations {
		value: string
		switch param.type.kind {
		case .I64:
			value = "set.int_v"
		case .F64:
			value = "set.real_v"
		case .String:
			value = "set.text_v"
		case .Bytes:
			value = "transmute([]byte)set.blob_v"
		case .Bool:
			value = "set.bool_v"
		}
		if param.type.nullable {
			value = fmt.aprintf("sqlgen_maybe(%s, set.nulls)", value)
		}
		fmt.sbprintf(&args, ", %s", value)
	}
	call := strings.to_string(args)
	if q.kind == .Many {
		emit_test_many(sb, q, call)
		return
	}
	strings.write_string(sb, "\t{\n\t\tsqlgen_begin(t, db)\n")
	switch q.kind {
	case .One:
		fmt.sbprintf(sb, "\t\t_, _, err := %s(%s)\n", q.name, call)
	case .Many:
	// emit_test_many wrote it, above.
	case .Exec:
		fmt.sbprintf(sb, "\t\terr := %s(%s)\n", q.name, call)
	case .Rows, .Last_Id:
		fmt.sbprintf(sb, "\t\t_, err := %s(%s)\n", q.name, call)
	}
	fmt.sbprintf(sb, "\t\tsqlgen_end(t, db, set, %q, err)\n\t}}\n", q.name)
}

// emit_test_many runs a :many query each way it can be read: the raw cursor,
// the guard, and the slice, so each generated path meets every data set.
@(private = "file")
emit_test_many :: proc(sb: ^strings.Builder, q: Query, call: string) {
	n := q.name
	rest := call[len("db"):]
	fmt.sbprintf(sb, "\t{{\n\t\tsqlgen_begin(t, db)\n\t\trows, err := %s_open(%s)\n", n, call)
	fmt.sbprintf(sb, "\t\tif err == nil {{\n\t\t\tfor _ in %s_next(&rows) {{\n\t\t\t}}\n", n)
	fmt.sbprintf(sb, "\t\t\terr = %s_close(&rows)\n\t\t}}\n", n)
	fmt.sbprintf(sb, "\t\tsqlgen_end(t, db, set, \"%s_open\", err)\n\t}}\n", n)
	fmt.sbprintf(sb, "\t{{\n\t\tsqlgen_begin(t, db)\n\t\trows: %s_Rows\n", ada_case(n))
	fmt.sbprintf(
		sb,
		"\t\tif %s(&rows, db%s) {{\n\t\t\tfor _ in %s_next(&rows) {{\n\t\t\t}}\n\t\t}}\n",
		n,
		rest,
		n,
	)
	fmt.sbprintf(sb, "\t\tsqlgen_end(t, db, set, %q, rows.err)\n\t}}\n", n)
	fmt.sbprintf(sb, "\t{{\n\t\tsqlgen_begin(t, db)\n\t\t_, err := %s_all(%s)\n", n, call)
	fmt.sbprintf(sb, "\t\tsqlgen_end(t, db, set, \"%s_all\", err)\n\t}}\n", n)
}
