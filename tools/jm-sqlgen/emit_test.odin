package main

import "core:fmt"
import "core:strings"

// Test_Driver is what the generated test needs to know about running
// against its engine. The data sets, the calls and the checks on them are
// the same for every engine.
Test_Driver :: struct {
	// The test file's imports.
	imports: string,
	// The @(test) proc: it brings up a database for each of SQLGEN_SETS,
	// with the schema and the set's seed in it, runs check and sqlgen_run.
	run:     string,
	// The connection's type, as sqlgen_run takes it.
	conn:    string,
	// sqlgen_begin and sqlgen_end, which put a query in a savepoint and say
	// which of its failures the data set explains.
	helpers: string,
}

// emit_test writes queries_gen_test.odin: every query run against every
// data set through the generated procs, failing on any error a constraint
// the set happens to break does not explain.
emit_test :: proc(d: Test_Driver, pkg: string, queries: []Query, sets: []Data_Set) -> string {
	sb: strings.Builder
	strings.write_string(&sb, GENERATED_HEADER)
	fmt.sbprintf(&sb, "\npackage %s\n\n%s", pkg, d.imports)
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
	strings.write_string(&sb, d.run)
	fmt.sbprintf(
		&sb,
		"\n@(private = \"file\")\nsqlgen_run :: proc(t: ^testing.T, db: %s, set: Sqlgen_Set) {{\n",
		d.conn,
	)
	for q in queries {
		emit_test_call(&sb, q)
	}
	strings.write_string(&sb, "}\n")
	strings.write_string(
		&sb,
		`
@(private = "file")
sqlgen_maybe :: proc(v: $T, null: bool) -> Maybe(T) {
	if null {
		return nil
	}
	return v
}

// sqlgen_int is the set's integer as T, held to T's range, so the extremes
// of the set are the extremes of each width.
@(private = "file")
sqlgen_int :: proc(set: Sqlgen_Set, $T: typeid) -> T {
	return T(clamp(set.int_v, i64(min(T)), i64(max(T))))
}

// sqlgen_real is the set's float as T, held to T's finite range.
@(private = "file")
sqlgen_real :: proc(set: Sqlgen_Set, $T: typeid) -> T {
	return T(clamp(set.real_v, -f64(max(T)), f64(max(T))))
}
`,
	)
	strings.write_string(&sb, d.helpers)
	return strings.to_string(sb)
}

@(private = "file")
emit_test_call :: proc(sb: ^strings.Builder, q: Query) {
	args: strings.Builder
	strings.write_string(&args, "db")
	for param in q.annotations {
		value: string
		switch param.type.kind {
		case .I16, .I32, .I64:
			value = fmt.aprintf("sqlgen_int(set, %s)", KIND_NAMES[param.type.kind])
		case .F32, .F64:
			value = fmt.aprintf("sqlgen_real(set, %s)", KIND_NAMES[param.type.kind])
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
