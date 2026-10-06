package main

import "core:fmt"
import "core:strings"

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

// Seed_Value is which of the set values a column's literal holds.
Seed_Value :: enum {
	Base,
	Low,
	High,
}

// Seed_Table is a table as the data sets fill it: its name as SQL writes
// it, quoted, and the columns an INSERT gives values to.
Seed_Table :: struct {
	name:    string,
	// The name a set made of this table alone is called by.
	label:   string,
	columns: []Seed_Column,
}

// Seed_Column is one column and its value in each set, as an SQL literal of
// the column's own type.
Seed_Column :: struct {
	name:     string,
	not_null: bool,
	literal:  [Seed_Value]string,
}

// Seeder is how the data sets reach an engine: a fresh database with the
// schema in it for each set, an INSERT tried and undone, and an INSERT kept.
// Each returns why the engine refused, or "".
Seeder :: struct {
	user:   rawptr,
	start:  proc(user: rawptr) -> string,
	try:    proc(user: rawptr, sql: string) -> string,
	keep:   proc(user: rawptr, sql: string) -> string,
	finish: proc(user: rawptr),
}

// build_data_sets builds the sets and runs each against a fresh database
// with the schema, so the test that replays them cannot fail on its seed.
// A row its set's values break falls back, a column at a time, to the base
// values, and then to the base values with every nullable column NULL.
build_data_sets :: proc(tables: []Seed_Table, s: Seeder, p: ^Problems) -> []Data_Set {
	sets: [dynamic]Data_Set
	append(&sets, Data_Set{name = "empty", value = BASE})
	append(&sets, fill(tables, s, "nulls", .Base, true, p))
	append(&sets, fill(tables, s, "low", .Low, false, p))
	append(&sets, fill(tables, s, "high", .High, false, p))
	if len(tables) > 1 {
		for t in tables {
			name := fmt.aprintf("only_%s", t.label)
			append(&sets, fill({t}, s, name, .Base, true, p))
		}
	}
	return sets[:]
}

@(private = "file")
fill :: proc(
	tables: []Seed_Table,
	s: Seeder,
	name: string,
	v: Seed_Value,
	nulls: bool,
	p: ^Problems,
) -> Data_Set {
	values := [Seed_Value]Values {
		.Base = BASE,
		.Low  = LOW,
		.High = HIGH,
	}
	set := Data_Set {
		name  = name,
		value = values[v],
		nulls = nulls,
	}
	if why := s.start(s.user); why != "" {
		problem(p, SCHEMA_FILE, 0, "building data set %s: %s", name, why)
		return set
	}
	defer s.finish(s.user)
	seed: strings.Builder
	notes: [dynamic]string
	for t in tables {
		row, refused, ok := choose_row(s, t, v, nulls)
		if !ok {
			problem(
				p,
				SCHEMA_FILE,
				0,
				"data set %s: table %s refuses every row jm-sqlgen tries, such as %s",
				name,
				t.label,
				insert_sql(t, literals(t, v, nulls)),
			)
			continue
		}
		for r in refused {
			append(
				&notes,
				fmt.aprintf(
					"%s.%s holds the base value, since %s refused the set's own: %s",
					t.label,
					r.column,
					t.label,
					r.why,
				),
			)
		}
		sql := insert_sql(t, row)
		if why := s.keep(s.user, sql); why != "" {
			problem(p, SCHEMA_FILE, 0, "data set %s: %s: %s", name, sql, why)
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
	s: Seeder,
	t: Seed_Table,
	v: Seed_Value,
	nulls: bool,
) -> (
	row: []string,
	refused: []Refusal,
	ok: bool,
) {
	want := literals(t, v, nulls)
	if s.try(s.user, insert_sql(t, want)) == "" {
		return want, nil, true
	}
	row = literals(t, .Base, false)
	if s.try(s.user, insert_sql(t, row)) != "" {
		row = literals(t, .Base, true)
		if s.try(s.user, insert_sql(t, row)) != "" {
			return nil, nil, false
		}
	}
	out: [dynamic]Refusal
	for i in 0 ..< len(row) {
		if row[i] == want[i] {
			continue
		}
		kept := row[i]
		row[i] = want[i]
		if why := s.try(s.user, insert_sql(t, row)); why != "" {
			row[i] = kept
			append(&out, Refusal{column = t.columns[i].name, why = why})
		}
	}
	return row, out[:], true
}

// literals are the SQL values of a row of t: v's for each column, or NULL
// for a nullable one when nulls is set.
@(private = "file")
literals :: proc(t: Seed_Table, v: Seed_Value, nulls: bool) -> []string {
	out := make([]string, len(t.columns))
	for c, i in t.columns {
		out[i] = nulls && !c.not_null ? "NULL" : c.literal[v]
	}
	return out
}

@(private = "file")
insert_sql :: proc(t: Seed_Table, row: []string) -> string {
	sb: strings.Builder
	fmt.sbprintf(&sb, "INSERT INTO %s(", t.name)
	for c, i in t.columns {
		if i > 0 {
			strings.write_string(&sb, ", ")
		}
		write_quoted_name(&sb, c.name)
	}
	fmt.sbprintf(&sb, ")\nVALUES (%s);", strings.join(row, ", "))
	return strings.to_string(sb)
}

// write_quoted_name writes name as a double-quoted SQL identifier, which
// both engines read.
write_quoted_name :: proc(sb: ^strings.Builder, name: string) {
	strings.write_byte(sb, '"')
	for r in name {
		if r == '"' {
			strings.write_byte(sb, '"')
		}
		strings.write_rune(sb, r)
	}
	strings.write_byte(sb, '"')
}

// quoted_name is name as a double-quoted SQL identifier.
quoted_name :: proc(name: string) -> string {
	sb: strings.Builder
	write_quoted_name(&sb, name)
	return strings.to_string(sb)
}

// write_text_literal writes s as a single-quoted SQL string literal, which
// both engines read.
write_text_literal :: proc(sb: ^strings.Builder, s: string) {
	strings.write_byte(sb, '\'')
	for r in s {
		if r == '\'' {
			strings.write_byte(sb, '\'')
		}
		strings.write_rune(sb, r)
	}
	strings.write_byte(sb, '\'')
}
