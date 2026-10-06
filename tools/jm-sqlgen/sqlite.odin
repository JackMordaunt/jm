package main

import "core:fmt"
import "core:strings"

import "jm:sqlite3"

// Catalog is what the schema declares, read back from SQLite after running
// it, so the generator sees the tables as the engine does.
Catalog :: struct {
	// By lower-case name, since SQLite's identifiers ignore case.
	tables: map[string]Table,
	views:  [dynamic]View,
	// rootpage to table name: how an EXPLAIN cursor is traced to a table.
	roots:  map[i64]string,
}

Table :: struct {
	name:    string,
	virtual: bool,
	columns: []Table_Column,
}

Table_Column :: struct {
	name:       string,
	// The declared type, upper-cased: INTEGER, INT, REAL, TEXT, BLOB or ANY
	// in a STRICT table, "" in a virtual one.
	decl:       string,
	not_null:   bool,
	// A generated or hidden column takes no value in an INSERT.
	insertable: bool,
}

View :: struct {
	name:     string,
	sql:      string,
	// The view's own SELECT, or one it reads, is compound.
	compound: bool,
}

// load_catalog reads every table, view and root page, and refuses a table
// that is not STRICT: outside STRICT, a column's declared type is advice
// that any value may ignore, so there is no type to generate.
load_catalog :: proc(db: sqlite3.Db, p: ^Problems) -> (cat: Catalog, ok: bool) {
	rows, err := sqlite3.query(
		db,
		`SELECT name, type, wr, strict FROM pragma_table_list WHERE schema = 'main' ORDER BY name`,
	)
	if err != nil {
		problem(p, SCHEMA_FILE, 0, "reading the tables: %s", fault_text(err))
		return {}, false
	}
	ok = true
	for sqlite3.next(&rows) {
		name := sqlite3.text(rows, 0)
		kind := sqlite3.text(rows, 1)
		without_rowid := sqlite3.boolean(rows, 2)
		strict := sqlite3.boolean(rows, 3)
		switch kind {
		case "table":
			if strings.has_prefix(name, "sqlite_") {
				continue
			}
			if !strict {
				problem(
					p,
					SCHEMA_FILE,
					0,
					"table %s is not STRICT: declare it CREATE TABLE ... STRICT so its column types hold",
					name,
				)
				ok = false
				continue
			}
			cat.tables[strings.to_lower(name)] = load_table(
				db,
				name,
				false,
				without_rowid,
				p,
			) or_continue
		case "virtual":
			cat.tables[strings.to_lower(name)] = load_table(db, name, true, false, p) or_continue
		}
	}
	if err = sqlite3.finish(&rows); err != nil {
		problem(p, SCHEMA_FILE, 0, "reading the tables: %s", fault_text(err))
		return {}, false
	}
	if verr := load_views(db, &cat); verr != nil {
		problem(p, SCHEMA_FILE, 0, "reading the views: %s", fault_text(verr))
		return {}, false
	}
	roots, rerr := sqlite3.query(
		db,
		`SELECT rootpage, tbl_name FROM sqlite_schema WHERE rootpage > 0`,
	)
	if rerr == nil {
		for sqlite3.next(&roots) {
			cat.roots[sqlite3.integer(roots, 0)] = sqlite3.text(roots, 1)
		}
		rerr = sqlite3.finish(&roots)
	}
	if rerr != nil {
		problem(p, SCHEMA_FILE, 0, "reading the root pages: %s", fault_text(rerr))
		return {}, false
	}
	return cat, ok
}

@(private = "file")
load_table :: proc(
	db: sqlite3.Db,
	name: string,
	virtual, without_rowid: bool,
	p: ^Problems,
) -> (
	t: Table,
	ok: bool,
) {
	rows, err := sqlite3.query(
		db,
		`SELECT name, upper(type), "notnull", pk, hidden FROM pragma_table_xinfo(?)`,
		name,
	)
	if err != nil {
		problem(p, SCHEMA_FILE, 0, "reading table %s: %s", name, fault_text(err))
		return {}, false
	}
	cols: [dynamic]Table_Column
	pk_cols := 0
	pk_at := -1
	for sqlite3.next(&rows) {
		col := Table_Column {
			name       = sqlite3.text(rows, 0),
			decl       = sqlite3.text(rows, 1),
			not_null   = sqlite3.boolean(rows, 2),
			insertable = sqlite3.integer(rows, 4) == 0,
		}
		if sqlite3.integer(rows, 3) > 0 {
			pk_cols += 1
			pk_at = len(cols)
			// A STRICT table refuses NULL in a PRIMARY KEY column.
			col.not_null = col.not_null || !virtual
		}
		append(&cols, col)
	}
	if err = sqlite3.finish(&rows); err != nil {
		problem(p, SCHEMA_FILE, 0, "reading table %s: %s", name, fault_text(err))
		return {}, false
	}
	// An INTEGER PRIMARY KEY is the rowid under another name, never NULL.
	if !virtual && !without_rowid && pk_cols == 1 && cols[pk_at].decl == "INTEGER" {
		cols[pk_at].not_null = true
	}
	return Table{name = name, virtual = virtual, columns = cols[:]}, true
}

// load_views marks each view compound when its SELECT is, or when it reads
// a compound view, until nothing changes.
@(private = "file")
load_views :: proc(db: sqlite3.Db, cat: ^Catalog) -> sqlite3.Error {
	rows := sqlite3.query(db, `SELECT name, sql FROM sqlite_schema WHERE type = 'view'`) or_return
	for sqlite3.next(&rows) {
		append(&cat.views, View{name = sqlite3.text(rows, 0), sql = sqlite3.text(rows, 1)})
	}
	sqlite3.finish(&rows) or_return
	for changed := true; changed; {
		changed = false
		for &v in cat.views {
			if v.compound {
				continue
			}
			words, _ := scan(v.sql)
			if is_compound(words) || reads_compound_view(cat^, words) {
				v.compound = true
				changed = true
			}
		}
	}
	return nil
}

reads_compound_view :: proc(cat: Catalog, words: []Word) -> bool {
	for v in cat.views {
		if v.compound && mentions(words, v.name) {
			return true
		}
	}
	return false
}

// Trust is what EXPLAIN shows about where a NULL can come from that the
// schema's NOT NULL does not rule out.
Trust :: struct {
	// No column's NOT NULL can be relied on, for the reason in why.
	anything: bool,
	why:      string,
	// Tables on the outer side of a join, by lower-case name.
	outer:    map[string]bool,
}

// trust_of reads the statement's bytecode. NOT NULL is relied on only when
// every opcode is one an ordinary read or write uses, so an opcode this
// list has not met makes every column Maybe rather than guessing. NullRow,
// which an outer join uses to fill a missing row with NULL, makes only its
// own table's columns Maybe when its cursor traces to a table.
trust_of :: proc(db: sqlite3.Db, cat: Catalog, sql: string) -> (tr: Trust, err: sqlite3.Error) {
	stmt := sqlite3.prepare(db, strings.concatenate({"EXPLAIN ", sql})) or_return
	// The tables each cursor reads. An automatic index is a cursor of its
	// own, filled from the cursors read before its first IdxInsert.
	cursors: map[i64][dynamic]string
	filling := i64(-1)
	for sqlite3.next(&stmt) {
		op := sqlite3.text(stmt, 1)
		p1 := sqlite3.integer(stmt, 2)
		switch op {
		case "OpenRead", "OpenWrite", "ReopenIdx":
			if table, known := cat.roots[sqlite3.integer(stmt, 3)]; known {
				cursors[p1] = make([dynamic]string)
				append(&cursors[p1], table)
			}
		case "OpenAutoindex":
			cursors[p1] = make([dynamic]string)
			filling = p1
		case "Column", "Rowid":
			if filling >= 0 && p1 != filling {
				append(&cursors[filling], ..cursors[p1][:])
			}
		case "IdxInsert":
			if p1 == filling {
				filling = -1
			}
		case "NullRow", "IfNullRow":
			tables, known := cursors[p1]
			if known && len(tables) > 0 {
				for table in tables {
					tr.outer[strings.to_lower(table)] = true
				}
			} else if !tr.anything {
				tr.anything = true
				tr.why = "a subquery fills missing rows with NULL"
			}
		case:
			if !tr.anything && !ordinary_opcode(op) {
				tr.anything = true
				tr.why = fmt.aprintf("the statement uses %s, which can produce NULL", op)
			}
		}
	}
	return tr, sqlite3.finish(&stmt)
}

// ordinary_opcode lists the opcodes of plain reads and writes, as EXPLAIN
// shows them in SQLite 3.53.4. Aggregates, subqueries (BeginSubrtn),
// materialized views (Gosub, Return) and coroutines (InitCoroutine, Yield)
// are left out on purpose: each can yield NULL for a column whose table
// says NOT NULL. Once alone is the one-time setup of an automatic index.
@(private = "file")
ordinary_opcode :: proc(op: string) -> bool {
	switch op {
	case "Add",
	     "Affinity",
	     "And",
	     "BitAnd",
	     "BitNot",
	     "BitOr",
	     "Blob",
	     "Cast",
	     "Close",
	     "CollSeq",
	     "Column",
	     "ColumnsUsed",
	     "Compare",
	     "Concat",
	     "Copy",
	     "Count",
	     "DecrJumpZero",
	     "DeferredSeek",
	     "Delete",
	     "Divide",
	     "ElseEq",
	     "Eq",
	     "Explain",
	     "FkCheck",
	     "FkCounter",
	     "FkIfZero",
	     "Filter",
	     "FilterAdd",
	     "Found",
	     "Function",
	     "Ge",
	     "Goto",
	     "Gt",
	     "Halt",
	     "HaltIfNull",
	     "IdxDelete",
	     "IdxGE",
	     "IdxGT",
	     "IdxInsert",
	     "IdxLE",
	     "IdxLT",
	     "IdxRowid",
	     "If",
	     "IfNot",
	     "IfPos",
	     "IfNoHope",
	     "IfNotOpen",
	     "Init",
	     "Insert",
	     "Int64",
	     "IntCopy",
	     "Integer",
	     "IsNull",
	     "IsTrue",
	     "IsType",
	     "Jump",
	     "Last",
	     "Le",
	     "Lt",
	     "MakeRecord",
	     "Multiply",
	     "MustBeInt",
	     "Ne",
	     "NewRowid",
	     "Next",
	     "NoConflict",
	     "Noop",
	     "Not",
	     "NotExists",
	     "NotFound",
	     "NotNull",
	     "Null",
	     "OffsetLimit",
	     "Once",
	     "OpenAutoindex",
	     "OpenEphemeral",
	     "OpenPseudo",
	     "Or",
	     "Permutation",
	     "Prev",
	     "Real",
	     "RealAffinity",
	     "Remainder",
	     "ResultRow",
	     "Rewind",
	     "Rowid",
	     "SCopy",
	     "SeekGE",
	     "SeekGT",
	     "SeekLE",
	     "SeekLT",
	     "SeekEnd",
	     "SeekHit",
	     "SeekRowid",
	     "SeekScan",
	     "Sequence",
	     "ShiftLeft",
	     "ShiftRight",
	     "SoftNull",
	     "SorterCompare",
	     "SorterData",
	     "SorterInsert",
	     "SorterNext",
	     "SorterOpen",
	     "SorterSort",
	     "String8",
	     "Subtract",
	     "Transaction",
	     "TypeCheck",
	     "VBegin",
	     "VColumn",
	     "VFilter",
	     "VNext",
	     "VOpen",
	     "VUpdate",
	     "Variable":
		return true
	}
	return false
}

// describe_all_sqlite runs the schema in a scratch database and describes
// every query against it.
describe_all_sqlite :: proc(
	schema: string,
	qs: []Query,
	p: ^Problems,
) -> (
	cat: Catalog,
	ok: bool,
) {
	db, err := sqlite3.open(sqlite3.MEMORY)
	if err != nil {
		problem(p, SCHEMA_FILE, 0, "opening a scratch database: %s", fault_text(err))
		return {}, false
	}
	defer sqlite3.close(&db)
	if err = sqlite3.exec(db, schema); err != nil {
		problem(p, SCHEMA_FILE, 0, "%s", fault_text(err))
		return {}, false
	}
	cat = load_catalog(db, p) or_return
	for &q in qs {
		describe_sqlite(db, cat, &q, p)
	}
	return cat, true
}

// describe_sqlite prepares q against db and fills in its parameters and
// fields, reporting what it cannot type.
describe_sqlite :: proc(db: sqlite3.Db, cat: Catalog, q: ^Query, p: ^Problems) {
	words, more := scan(q.sql)
	if more {
		problem(
			p,
			QUERIES_FILE,
			q.line,
			"%s holds more than one statement: give each its own -- name: line",
			q.name,
		)
		return
	}
	stmt, err := sqlite3.prepare(db, q.sql)
	if err != nil {
		problem(p, QUERIES_FILE, q.line, "%s: %s", q.name, fault_text(err))
		return
	}
	defer sqlite3.finish(&stmt)
	describe_params(stmt, q, p)
	ncols := sqlite3.column_count(stmt)
	switch q.kind {
	case .One, .Many:
		if ncols == 0 {
			problem(
				p,
				QUERIES_FILE,
				q.line,
				"%s returns no columns: tag it :exec, :rows or :last_id",
				q.name,
			)
		}
	case .Exec, .Rows, .Last_Id:
		if ncols > 0 {
			problem(p, QUERIES_FILE, q.line, "%s returns columns: tag it :one or :many", q.name)
		}
		if q.kind != .Exec && sqlite3.read_only(stmt) {
			problem(
				p,
				QUERIES_FILE,
				q.line,
				"%s changes nothing, so %s has nothing to report: tag it :exec",
				q.name,
				QUERY_KIND_TAGS[q.kind],
			)
		}
	}
	if ncols == 0 {
		return
	}
	compound := is_compound(words) || reads_compound_view(cat, words)
	tr, terr := trust_of(db, cat, q.sql)
	if terr != nil {
		problem(p, QUERIES_FILE, q.line, "%s: explaining it: %s", q.name, fault_text(terr))
		return
	}
	fields: [dynamic]Field
	for i in 0 ..< ncols {
		f, ok := describe_field(stmt, cat, i, compound, tr, q, p)
		if !ok {
			continue
		}
		for other in fields {
			if other.name == f.name {
				problem(
					p,
					QUERIES_FILE,
					q.line,
					"%s: two columns are named %s: alias one",
					q.name,
					f.name,
				)
			}
		}
		append(&fields, f)
	}
	q.fields = fields[:]
}

@(private = "file")
describe_params :: proc(stmt: sqlite3.Stmt, q: ^Query, p: ^Problems) {
	params: [dynamic]Param
	used := make([]bool, len(q.annotations))
	for i in 0 ..< sqlite3.parameter_count(stmt) {
		name := sqlite3.parameter_name(stmt, i)
		if !strings.has_prefix(name, "@") {
			problem(
				p,
				QUERIES_FILE,
				q.line,
				"%s: parameter %d is %q: name every parameter @name",
				q.name,
				i + 1,
				name == "" ? "?" : name,
			)
			continue
		}
		name = name[1:]
		found := false
		for a, k in q.annotations {
			if a.name == name {
				append(&params, a)
				used[k] = true
				found = true
			}
		}
		if !found {
			problem(
				p,
				QUERIES_FILE,
				q.line,
				"%s: @%s has no type: add it to the -- params: line",
				q.name,
				name,
			)
		}
	}
	for a, k in q.annotations {
		if !used[k] {
			problem(
				p,
				QUERIES_FILE,
				q.line,
				"%s: -- params: names %s, which the statement does not use",
				q.name,
				a.name,
			)
		}
	}
	q.params = params[:]
}

// describe_field types result column i: from its annotation when it has
// one, checked against the column it reads, and otherwise from the column it
// reads. An expression, or a column of a compound SELECT, has to be
// annotated, since SQLite does not say what it holds.
@(private = "file")
describe_field :: proc(
	stmt: sqlite3.Stmt,
	cat: Catalog,
	i: int,
	compound: bool,
	tr: Trust,
	q: ^Query,
	p: ^Problems,
) -> (
	f: Field,
	ok: bool,
) {
	sql_name := sqlite3.name(stmt, i)
	name, sep, annotation := strings.partition(sql_name, ":")
	f.name = strings.trim_space(name)
	if !is_identifier(f.name) {
		problem(
			p,
			QUERIES_FILE,
			q.line,
			"%s: column %d is %q, which cannot name a field: alias it AS \"name: type\"",
			q.name,
			i + 1,
			sql_name,
		)
		return {}, false
	}
	col, table, has_origin := origin_of(stmt, cat, i)
	inferred, why, typed := infer(col, table, has_origin && !compound, tr)
	if sep != "" {
		t, valid := parse_type(annotation)
		if !valid {
			problem(
				p,
				QUERIES_FILE,
				q.line,
				"%s: %s: %q is not a type: use i64, f64, bool, string, []byte or Maybe(T)",
				q.name,
				f.name,
				strings.trim_space(annotation),
			)
			return {}, false
		}
		if typed && !fits(t.kind, col.decl) {
			problem(
				p,
				QUERIES_FILE,
				q.line,
				"%s: %s reads %s.%s, declared %s, which cannot hold %s",
				q.name,
				f.name,
				table,
				col.name,
				col.decl,
				KIND_NAMES[t.kind],
			)
			return {}, false
		}
		f.type = t
		f.annotated = true
		return f, true
	}
	if !typed {
		switch {
		case compound:
			problem(
				p,
				QUERIES_FILE,
				q.line,
				"%s: %s comes from a compound SELECT, which SQLite types from its first " +
				"arm alone: annotate it AS \"%s: <type>\"",
				q.name,
				f.name,
				f.name,
			)
		case has_origin:
			problem(
				p,
				QUERIES_FILE,
				q.line,
				"%s: %s reads %s.%s, which declares no type jm-sqlgen maps: annotate it AS \"%s: <type>\"",
				q.name,
				f.name,
				table,
				col.name,
				f.name,
			)
		case:
			problem(
				p,
				QUERIES_FILE,
				q.line,
				"%s: %s is an expression, which SQLite does not type: annotate it AS \"%s: <type>\"",
				q.name,
				f.name,
				f.name,
			)
		}
		return {}, false
	}
	f.type = inferred
	f.why = why
	return f, true
}

// origin_of finds the table column result column i reads, if it reads one.
@(private = "file")
origin_of :: proc(
	stmt: sqlite3.Stmt,
	cat: Catalog,
	i: int,
) -> (
	col: Table_Column,
	table: string,
	ok: bool,
) {
	table_name, col_name := sqlite3.origin(stmt, i)
	if table_name == "" {
		return {}, "", false
	}
	t, known := cat.tables[strings.to_lower(table_name)]
	if !known {
		return {}, "", false
	}
	for c in t.columns {
		if strings.equal_fold(c.name, col_name) {
			return c, t.name, true
		}
	}
	// A table without an INTEGER PRIMARY KEY still has its rowid.
	if !t.virtual {
		for alias in ([]string{"rowid", "oid", "_rowid_"}) {
			if strings.equal_fold(col_name, alias) {
				return Table_Column{name = col_name, decl = "INTEGER", not_null = true},
					t.name,
					true
			}
		}
	}
	return {}, "", false
}

@(private = "file")
infer :: proc(
	col: Table_Column,
	table: string,
	usable: bool,
	tr: Trust,
) -> (
	t: Type,
	why: string,
	ok: bool,
) {
	if !usable {
		return {}, "", false
	}
	switch col.decl {
	case "INTEGER", "INT":
		t.kind = .I64
	case "REAL":
		t.kind = .F64
	case "TEXT":
		t.kind = .String
	case "BLOB":
		t.kind = .Bytes
	case:
		return {}, "", false
	}
	t.nullable = !col.not_null
	if !col.not_null {
		return t, "", true
	}
	switch {
	case tr.anything:
		t.nullable = true
		why = tr.why
	case tr.outer[strings.to_lower(table)]:
		t.nullable = true
		why = fmt.aprintf("%s is on the outer side of a join", table)
	}
	return t, why, true
}

// fits reports whether a column declared decl can hold a value of kind k:
// a bool is an INTEGER 0 or 1, and ANY holds anything.
@(private = "file")
fits :: proc(k: Kind, decl: string) -> bool {
	switch decl {
	case "INTEGER", "INT":
		return k == .I64 || k == .Bool
	case "REAL":
		return k == .F64
	case "TEXT":
		return k == .String
	case "BLOB":
		return k == .Bytes
	}
	return true
}

fault_text :: proc(err: sqlite3.Error) -> string {
	if f, is_fault := err.(sqlite3.Fault); is_fault {
		return f.text
	}
	return "unknown failure"
}
