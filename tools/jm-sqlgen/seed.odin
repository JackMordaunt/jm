package main

import "core:fmt"
import "core:slice"
import "core:strings"

import "jm:sqlite3"

// Data_Set is one database state the generated test runs every query
// against, and the parameter values it passes. The sets are chosen for
// where NULL and odd values come from: nothing at all, which empties
// aggregates and subqueries; every nullable column NULL; the extremes of
// each type; and one table alone, which leaves the other side of an outer
// join missing.
Data_Set :: struct {
	name:  string,
	// The INSERTs that fill it, one per line.
	seed:  string,
	value: Values,
	// Pass NULL for every Maybe parameter.
	nulls: bool,
	// Why a table's row differs from the set's own values, when a CHECK or
	// other constraint refused them.
	notes: []string,
}

// Values are the parameter and column values a set uses for each kind.
Values :: struct {
	int_v:  i64,
	real_v: f64,
	text_v: string,
	blob_v: string,
	bool_v: bool,
}

BASE :: Values{1, 1.5, "a", "a", true}
LOW  :: Values{min(i64), -1.5, "", "", false}
HIGH :: Values{max(i64), 1e300, "zß€😀", "\x00\xff", true}

// build_data_sets builds the sets and runs each against a fresh database
// with the schema, so the test that replays them cannot fail on its seed.
// A row its set's values break falls back to the base values, and then to
// the base values with every nullable column NULL.
build_data_sets :: proc(schema: string, cat: Catalog, p: ^Problems) -> []Data_Set {
	names, _ := slice.map_keys(cat.tables)
	slice.sort(names)
	sets: [dynamic]Data_Set
	append(&sets, Data_Set{name = "empty", value = BASE})
	append(&sets, fill(schema, cat, names, "nulls", BASE, true, p))
	append(&sets, fill(schema, cat, names, "low", LOW, false, p))
	append(&sets, fill(schema, cat, names, "high", HIGH, false, p))
	if len(names) > 1 {
		for n in names {
			set := fill(
				schema,
				cat,
				{n},
				fmt.aprintf("only_%s", cat.tables[n].name),
				BASE,
				true,
				p,
			)
			append(&sets, set)
		}
	}
	return sets[:]
}

@(private = "file")
fill :: proc(
	schema: string,
	cat: Catalog,
	tables: []string,
	name: string,
	v: Values,
	nulls: bool,
	p: ^Problems,
) -> Data_Set {
	set := Data_Set {
		name  = name,
		value = v,
		nulls = nulls,
	}
	db, err := sqlite3.open(sqlite3.MEMORY)
	if err == nil {
		err = sqlite3.exec(db, schema)
	}
	if err != nil {
		problem(p, SCHEMA_FILE, 0, "building data set %s: %s", name, fault_text(err))
		return set
	}
	defer sqlite3.close(&db)
	seed: strings.Builder
	notes: [dynamic]string
	for key in tables {
		t := cat.tables[key]
		row, refused, ok := choose_row(db, t, v, nulls)
		if !ok {
			problem(
				p,
				SCHEMA_FILE,
				0,
				"data set %s: table %s refuses every row jm-sqlgen tries, such as %s",
				name,
				t.name,
				insert_sql(t, literals(t, v, nulls)),
			)
			continue
		}
		for r in refused {
			append(
				&notes,
				fmt.aprintf(
					"%s.%s holds the base value, since %s refused the set's own: %s",
					t.name,
					r.column,
					t.name,
					r.why,
				),
			)
		}
		sql := insert_sql(t, row)
		if ierr := sqlite3.exec(db, sql); ierr != nil {
			problem(p, SCHEMA_FILE, 0, "data set %s: %s: %s", name, sql, fault_text(ierr))
			continue
		}
		strings.write_string(&seed, sql)
		strings.write_byte(&seed, '\n')
	}
	set.seed = strings.to_string(seed)
	set.notes = notes[:]
	return set
}

// Refusal is a column whose value from the set its table would not take.
@(private = "file")
Refusal :: struct {
	column: string,
	why:    string,
}

// choose_row finds the row nearest the set's own values that t accepts: the
// set's row whole if t takes it, and otherwise the base row with each of the
// set's values put back that t still takes, one column at a time, so a CHECK
// on one column costs the set that column's extreme alone.
@(private = "file")
choose_row :: proc(
	db: sqlite3.Db,
	t: Table,
	v: Values,
	nulls: bool,
) -> (
	row: []string,
	refused: []Refusal,
	ok: bool,
) {
	want := literals(t, v, nulls)
	if refusal(db, t, want) == "" {
		return want, nil, true
	}
	row = literals(t, BASE, false)
	if refusal(db, t, row) != "" {
		row = literals(t, BASE, true)
		if refusal(db, t, row) != "" {
			return nil, nil, false
		}
	}
	out: [dynamic]Refusal
	cols := insertable_columns(t)
	for i in 0 ..< len(row) {
		if row[i] == want[i] {
			continue
		}
		kept := row[i]
		row[i] = want[i]
		if why := refusal(db, t, row); why != "" {
			row[i] = kept
			append(&out, Refusal{column = cols[i].name, why = why})
		}
	}
	return row, out[:], true
}

// refusal is why t refuses row, or "" when it takes it. The row is tried
// inside a savepoint and rolled back either way.
@(private = "file")
refusal :: proc(db: sqlite3.Db, t: Table, row: []string) -> string {
	if err := sqlite3.exec(db, "SAVEPOINT seed"); err != nil {
		return fault_text(err)
	}
	err := sqlite3.exec(db, insert_sql(t, row))
	if rerr := sqlite3.exec(db, "ROLLBACK TO seed; RELEASE seed"); rerr != nil {
		return fault_text(rerr)
	}
	if err != nil {
		return fault_text(err)
	}
	return ""
}

@(private = "file")
insertable_columns :: proc(t: Table) -> []Table_Column {
	cols: [dynamic]Table_Column
	for c in t.columns {
		if c.insertable {
			append(&cols, c)
		}
	}
	return cols[:]
}

// literals are the SQL values of a row of t: v's for each column, or NULL
// for a nullable one when nulls is set.
@(private = "file")
literals :: proc(t: Table, v: Values, nulls: bool) -> []string {
	cols := insertable_columns(t)
	out := make([]string, len(cols))
	for c, i in cols {
		if nulls && !c.not_null {
			out[i] = "NULL"
			continue
		}
		sb: strings.Builder
		write_literal(&sb, c.decl, v)
		out[i] = strings.to_string(sb)
	}
	return out
}

@(private = "file")
insert_sql :: proc(t: Table, row: []string) -> string {
	sb: strings.Builder
	strings.write_string(&sb, "INSERT INTO ")
	write_name(&sb, t.name)
	strings.write_byte(&sb, '(')
	for c, i in insertable_columns(t) {
		if i > 0 {
			strings.write_string(&sb, ", ")
		}
		write_name(&sb, c.name)
	}
	fmt.sbprintf(&sb, ") VALUES (%s);", strings.join(row, ", "))
	return strings.to_string(sb)
}

@(private = "file")
write_literal :: proc(sb: ^strings.Builder, decl: string, v: Values) {
	switch decl {
	case "INTEGER", "INT":
		fmt.sbprintf(sb, "%d", v.int_v)
	case "REAL":
		fmt.sbprintf(sb, "%v", v.real_v)
	case "BLOB":
		strings.write_string(sb, "x'")
		for b in transmute([]byte)v.blob_v {
			fmt.sbprintf(sb, "%02x", b)
		}
		strings.write_byte(sb, '\'')
	case:
		strings.write_byte(sb, '\'')
		for r in v.text_v {
			if r == '\'' {
				strings.write_byte(sb, '\'')
			}
			strings.write_rune(sb, r)
		}
		strings.write_byte(sb, '\'')
	}
}

@(private = "file")
write_name :: proc(sb: ^strings.Builder, name: string) {
	strings.write_byte(sb, '"')
	for r in name {
		if r == '"' {
			strings.write_byte(sb, '"')
		}
		strings.write_rune(sb, r)
	}
	strings.write_byte(sb, '"')
}
