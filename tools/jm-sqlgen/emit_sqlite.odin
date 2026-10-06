package main

import "core:fmt"
import "core:strings"

// Readers records which typed column readers the queries use, so the file
// holds only those.
@(private = "file")
Readers :: struct {
	plain: bit_set[Kind],
	maybe: bit_set[Kind],
	value: bool, // a Maybe parameter needs converting to sqlite3.Value
}

// emit_sqlite_code writes queries_gen.odin: a row struct and a proc per
// query over jm:sqlite3, a check proc, and the readers they share.
emit_sqlite_code :: proc(
	pkg: string,
	queries: []Query,
	schema_text, queries_text: string,
) -> string {
	body: strings.Builder
	used: Readers
	for q in queries {
		emit_query(&body, q, &used)
	}
	emit_check(&body, queries)
	emit_readers(&body, used)

	sb: strings.Builder
	strings.write_string(&sb, GENERATED_HEADER)
	fmt.sbprintf(&sb, "\npackage %s\n\nimport \"core:fmt\"\n\nimport \"jm:sqlite3\"\n\n", pkg)
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
emit_query :: proc(sb: ^strings.Builder, q: Query, used: ^Readers) {
	fmt.sbprintf(sb, "\n@(private = \"file\")\n%s :: ", sql_const(q))
	write_string_literal(sb, q.sql)
	strings.write_string(sb, "\n")
	if q.kind == .One || q.kind == .Many {
		emit_row(sb, q)
	}
	strings.write_byte(sb, '\n')
	write_doc(sb, q.doc)
	if len(q.doc) > 0 {
		strings.write_string(sb, "//\n")
	}
	fmt.sbprintf(sb, "// %s is %s in queries.sql.\n", q.name, QUERY_KIND_TAGS[q.kind])
	fmt.sbprintf(sb, "%s :: proc(\n\tdb: sqlite3.Db,\n", q.name)
	for param in q.annotations {
		fmt.sbprintf(sb, "\t%s: %s,\n", param.name, type_name(param.type))
		used.value = used.value || param.type.nullable
	}
	strings.write_string(sb, "\tallocator := context.allocator,\n) -> ")
	row := fmt.aprintf("%s_Row", ada_case(q.name))
	switch q.kind {
	case .One:
		fmt.sbprintf(sb, "(\n\trow: %s,\n\tfound: bool,\n\terr: sqlite3.Error,\n) {{\n", row)
		emit_query_call(sb, "stmt :=", q)
		strings.write_string(sb, "\tif sqlite3.next(&stmt) {\n\t\tfound = true\n")
		emit_reads(sb, q, "row", "&stmt", "\t\t", used)
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
		rows := fmt.aprintf("%s_Rows", ada_case(q.name))
		fmt.sbprintf(sb, "(\n\trows: %s,\n\terr: sqlite3.Error,\n) {{\n", rows)
		emit_query_call(sb, "rows.stmt =", q)
		strings.write_string(sb, "\treturn\n}\n\n")
		fmt.sbprintf(
			sb,
			"// %s is the cursor %s returns: step it with %s_next and end it\n",
			rows,
			q.name,
			q.name,
		)
		fmt.sbprintf(sb, "// with %s_finish, which returns what stopped it.\n", q.name)
		fmt.sbprintf(sb, "%s :: struct {{\n\tstmt: sqlite3.Stmt,\n}}\n\n", rows)
		fmt.sbprintf(
			sb,
			"// %s_next reads the next row; ok is false at the end or on a failure.\n",
			q.name,
		)
		fmt.sbprintf(
			sb,
			"%s_next :: proc(rows: ^%s) -> (row: %s, ok: bool) {{\n",
			q.name,
			rows,
			row,
		)
		strings.write_string(sb, "\tif !sqlite3.next(&rows.stmt) {\n\t\treturn\n\t}\n")
		emit_reads(sb, q, "row", "&rows.stmt", "\t", used)
		strings.write_string(sb, "\treturn row, rows.stmt.err == nil\n}\n\n")
		fmt.sbprintf(
			sb,
			"%s_finish :: proc(rows: ^%s) -> sqlite3.Error {{\n\treturn sqlite3.finish(&rows.stmt)\n}}\n",
			q.name,
			rows,
		)
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
			fmt.sbprintf(sb, "\t\tsqlgen_value(%s),\n", param.name)
		} else {
			fmt.sbprintf(sb, "\t\t%s,\n", param.name)
		}
	}
	strings.write_string(sb, "\t\tallocator = allocator,\n\t) or_return\n")
}

@(private = "file")
emit_reads :: proc(sb: ^strings.Builder, q: Query, row, stmt, indent: string, used: ^Readers) {
	for f, i in q.fields {
		reader := f.type.kind == .Bytes ? "bytes" : KIND_NAMES[f.type.kind]
		if f.type.nullable {
			used.maybe += {f.type.kind}
			fmt.sbprintf(
				sb,
				"%s%s.%s = sqlgen_maybe_%s(%s, %d)\n",
				indent,
				row,
				f.name,
				reader,
				stmt,
				i,
			)
		} else {
			used.plain += {f.type.kind}
			fmt.sbprintf(sb, "%s%s.%s = sqlgen_%s(%s, %d)\n", indent, row, f.name, reader, stmt, i)
		}
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
		fmt.sbprintf(sb, "\tsqlgen_check(db, %q, %s, %d, {{", q.name, sql_const(q), len(q.params))
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
		strings.write_string(sb, "}, allocator) or_return\n")
	}
	strings.write_string(sb, "\treturn nil\n}\n")
	strings.write_string(
		sb,
		`
@(private = "file")
sqlgen_check :: proc(
	db: sqlite3.Db,
	name, sql: string,
	params: int,
	columns: []string,
	allocator := context.allocator,
) -> sqlite3.Error {
	stmt, err := sqlite3.prepare(db, sql, allocator)
	if f, failed := err.(sqlite3.Fault); failed {
		f.text = fmt.aprintf("%s: %s", name, f.text, allocator = allocator)
		return f
	}
	defer sqlite3.finish(&stmt)
	wrong := ""
	switch {
	case sqlite3.parameter_count(stmt) != params:
		wrong = fmt.aprintf("takes %d parameters", sqlite3.parameter_count(stmt), allocator = allocator)
	case sqlite3.column_count(stmt) != len(columns):
		wrong = fmt.aprintf("returns %d columns", sqlite3.column_count(stmt), allocator = allocator)
	case:
		for want, i in columns {
			if got := sqlite3.name(stmt, i); got != want {
				wrong = fmt.aprintf("names column %d %q", i + 1, got, allocator = allocator)
				break
			}
		}
	}
	if wrong == "" {
		return nil
	}
	return sqlite3.Fault {
		code = .Schema,
		text = fmt.aprintf(
			"%s %s, which is not what it was generated for",
			name,
			wrong,
			allocator = allocator,
		),
	}
}
`,
	)
}

@(private = "file")
emit_readers :: proc(sb: ^strings.Builder, used: Readers) {
	if used.value {
		strings.write_string(
			sb,
			`
@(private = "file")
sqlgen_value :: proc(v: Maybe($T)) -> sqlite3.Value {
	if x, ok := v.?; ok {
		return x
	}
	return nil
}
`,
		)
	}
	if used.plain == {} && used.maybe == {} {
		return
	}
	strings.write_string(
		sb,
		`
// sqlgen_expect fails the statement unless column col holds want, so a value
// of a type the generated code did not expect stops the read instead of
// converting silently.
@(private = "file")
sqlgen_expect :: proc(stmt: ^sqlite3.Stmt, col: int, want: sqlite3.Type) -> bool {
	got := sqlite3.type_of(stmt^, col)
	if got == want {
		return true
	}
	if stmt.err == nil {
		stmt.err = sqlite3.Fault {
			code = .Mismatch,
			text = fmt.aprintf(
				"column %s holds %v where jm-sqlgen generated %v",
				sqlite3.name(stmt^, col),
				got,
				want,
				allocator = stmt.allocator,
			),
		}
	}
	return false
}
`,
	)
	READERS := [Kind][2]string {
		.I64    = {
			"i64",
			"if sqlgen_expect(stmt, col, .Integer) {\n\t\tv = sqlite3.integer(stmt^, col)\n\t}",
		},
		.F64    = {
			"f64",
			"if sqlgen_expect(stmt, col, .Real) {\n\t\tv = sqlite3.real(stmt^, col)\n\t}",
		},
		.String = {
			"string",
			"if sqlgen_expect(stmt, col, .Text) {\n\t\tv = sqlite3.text(stmt^, col)\n\t}",
		},
		.Bytes  = {
			"[]byte",
			"if sqlgen_expect(stmt, col, .Blob) {\n\t\tv = sqlite3.blob(stmt^, col)\n\t}",
		},
		.Bool   = {
			"bool",
			`if !sqlgen_expect(stmt, col, .Integer) {
		return
	}
	switch n := sqlite3.integer(stmt^, col); n {
	case 0, 1:
		v = n == 1
	case:
		if stmt.err == nil {
			stmt.err = sqlite3.Fault {
				code = .Mismatch,
				text = fmt.aprintf(
					"column %s holds %d, which is not a bool",
					sqlite3.name(stmt^, col),
					n,
					allocator = stmt.allocator,
				),
			}
		}
	}`,
		},
	}
	for k in Kind {
		if k not_in used.plain && k not_in used.maybe {
			continue
		}
		name := k == .Bytes ? "bytes" : READERS[k][0]
		fmt.sbprintf(
			sb,
			"\n@(private = \"file\")\n" +
			"sqlgen_%s :: proc(stmt: ^sqlite3.Stmt, col: int) -> (v: %s) {{\n\t%s\n\treturn\n}}\n",
			name,
			READERS[k][0],
			READERS[k][1],
		)
		if k in used.maybe {
			fmt.sbprintf(
				sb,
				"\n@(private = \"file\")\n" +
				"sqlgen_maybe_%s :: proc(stmt: ^sqlite3.Stmt, col: int) -> (v: Maybe(%s)) {{\n",
				name,
				READERS[k][0],
			)
			fmt.sbprintf(
				sb,
				"\tif !sqlite3.is_null(stmt^, col) {{\n\t\tv = sqlgen_%s(stmt, col)\n\t}}\n\treturn\n}}\n",
				name,
			)
		}
	}
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
	strings.write_string(sb, "\t{\n\t\tsqlgen_begin(t, db)\n")
	switch q.kind {
	case .One:
		fmt.sbprintf(sb, "\t\t_, _, err := %s(%s)\n", q.name, call)
	case .Many:
		fmt.sbprintf(sb, "\t\trows, err := %s(%s)\n\t\tif err == nil {{\n", q.name, call)
		fmt.sbprintf(
			sb,
			"\t\t\tfor _ in %s_next(&rows) {{\n\t\t\t}}\n\t\t\terr = %s_finish(&rows)\n\t\t}}\n",
			q.name,
			q.name,
		)
	case .Exec:
		fmt.sbprintf(sb, "\t\terr := %s(%s)\n", q.name, call)
	case .Rows, .Last_Id:
		fmt.sbprintf(sb, "\t\t_, err := %s(%s)\n", q.name, call)
	}
	fmt.sbprintf(sb, "\t\tsqlgen_end(t, db, set, %q, err)\n\t}}\n", q.name)
}
