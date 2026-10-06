package main

import "core:encoding/json"
import "core:fmt"
import "core:slice"
import "core:strconv"
import "core:strings"

import "jm:pg_query"
import "jm:pq"
import "jm:pq/testdb"

// Pg is a connection to the throwaway server the generator describes
// against, and what it has learnt about the types there.
Pg :: struct {
	conn:      ^pq.Conn,
	types:     map[pq.Oid]Pg_Type,
	// Every table and view outside the system schemas, by oid: how a result
	// column's source is matched against the relations a join makes nullable.
	relations: map[pq.Oid]string,
}

// Pg_Type is what a type oid maps to in generated code.
Pg_Type :: struct {
	kind:   Kind,
	mapped: bool,
	// The type's SQL name, for a message about one that does not map.
	name:   string,
	// The labels of an enum, in order; the data sets seed its first and
	// last.
	labels: []string,
	// An array, which the data sets seed empty.
	array:  bool,
	// The built-in type it is or stands for, which sets its literals in the
	// data sets; 0 for an enum or a type that does not map.
	base:   pq.Oid,
}

// builtin_kind maps the built-in types, whose oids are fixed in pg_type.dat.
// numeric, uuid, json and the date and time types read as their text, the
// only Odin type that holds every value of theirs exactly.
@(private = "file")
builtin_kind :: proc(oid: pq.Oid) -> (kind: Kind, ok: bool) {
	switch oid {
	case 16:
		return .Bool, true
	case 17:
		return .Bytes, true
	case 20, 26:
		return .I64, true // int8, oid
	case 21:
		return .I16, true
	case 23:
		return .I32, true
	case 700:
		return .F32, true
	case 701:
		return .F64, true
	case 18, 19, 25, 1042, 1043:
		return .String, true // "char", name, text, bpchar, varchar
	case 114, 142, 3802:
		return .String, true // json, xml, jsonb
	case 650, 774, 829, 869:
		return .String, true // cidr, macaddr8, macaddr, inet
	case 790, 1700, 2950:
		return .String, true // money, numeric, uuid
	case 1082, 1083, 1114, 1184, 1186, 1266:
		return .String, true // date, time, timestamp, timestamptz, interval, timetz
	case 1560, 1562:
		return .String, true // bit, varbit
	}
	return {}, false
}

// pg_open brings up the throwaway server, connects, and starts the
// transaction the schema runs in, which pg_close rolls back.
pg_open :: proc(schema: string, p: ^Problems) -> (pg: Pg, ok: bool) {
	if up, why := testdb.start(); !up {
		problem(
			p,
			SCHEMA_FILE,
			0,
			"postgres needs a server to describe the queries against: %s",
			why,
		)
		return {}, false
	}
	conn, err := pq.connect()
	if err != nil {
		problem(p, SCHEMA_FILE, 0, "connecting to the throwaway server: %s", pg_text(err))
		return {}, false
	}
	pg.conn = conn
	if !pg_run(&pg, "BEGIN", p) {
		pq.close(conn)
		return {}, false
	}
	if _, serr := pq.exec(conn, schema); serr != nil {
		f := serr.(pq.Fault)
		problem(p, SCHEMA_FILE, line_at(schema, f.position), "%s", pg_text(serr))
		pq.close(conn)
		return {}, false
	}
	if !pg_load_relations(&pg, p) {
		pq.close(conn)
		return {}, false
	}
	return pg, true
}

pg_close :: proc(pg: ^Pg) {
	_, _ = pq.exec(pg.conn, "ROLLBACK") // closing ends the transaction regardless
	pq.close(pg.conn)
}

// describe_all_postgres describes every query against the schema on the
// throwaway server, each inside a savepoint, so a query the server rejects
// does not fail the ones after it.
describe_all_postgres :: proc(schema: string, qs: []Query, p: ^Problems) -> (pg: Pg, ok: bool) {
	pg = pg_open(schema, p) or_return
	for &q in qs {
		if !pg_run(&pg, "SAVEPOINT q", p) {
			break
		}
		described := describe_postgres(&pg, &q, p)
		undo := described ? "RELEASE SAVEPOINT q" : "ROLLBACK TO SAVEPOINT q"
		if !pg_run(&pg, undo, p) {
			break
		}
	}
	return pg, true
}

// describe_postgres fills in q's parameters and fields, reporting what it
// cannot type. It returns false when the server refused the statement.
@(private = "file")
describe_postgres :: proc(pg: ^Pg, q: ^Query, p: ^Problems) -> bool {
	if q.kind == .Last_Id {
		problem(
			p,
			QUERIES_FILE,
			q.line,
			"%s: PostgreSQL has no last insert id: add RETURNING id and tag it :one",
			q.name,
		)
		return true
	}
	shape, ok := pg_shape(q, p)
	if !ok {
		return true
	}
	desc, err := pq.describe(pg.conn, shape.sql)
	if err != nil {
		f := err.(pq.Fault)
		problem(
			p,
			QUERIES_FILE,
			q.line + line_at(shape.sql, f.position) - 1,
			"%s: %s",
			q.name,
			pg_text(err),
		)
		return false
	}
	q.sql = shape.sql
	pg_params(pg, q, shape.names, desc.params, p)
	switch q.kind {
	case .One, .Many:
		if len(desc.columns) == 0 {
			problem(
				p,
				QUERIES_FILE,
				q.line,
				"%s returns no columns: tag it :exec or :rows",
				q.name,
			)
			return true
		}
	case .Exec, .Rows, .Last_Id:
		if len(desc.columns) > 0 {
			problem(p, QUERIES_FILE, q.line, "%s returns columns: tag it :one or :many", q.name)
		}
		return true
	}
	not_null, nerr := pq.not_null(pg.conn, desc)
	if nerr != nil {
		problem(p, QUERIES_FILE, q.line, "%s: reading NOT NULL: %s", q.name, pg_text(nerr))
		return false
	}
	fields: [dynamic]Field
	for col, i in desc.columns {
		f, fok := pg_field(pg, q, col, not_null[i], shape, p)
		if !fok {
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
	return true
}

// Pg_Shape is what the parse tree says about a query: its SQL with each
// @name rewritten to $n, the names in that order, and where a NULL can come
// from that a NOT NULL column's constraint does not rule out.
@(private = "file")
Pg_Shape :: struct {
	sql:      string,
	names:    []string,
	// Relations on the nullable side of an outer join, by name.
	outer:    map[string]bool,
	// Every column may be NULL, for this reason.
	anything: string,
}

// pg_shape parses q with PostgreSQL's grammar. A parameter is @name, which
// the grammar reads as the prefix operator @ before a name: so the tree says
// where each one is, and a @ inside a string, a comment or a dollar-quoted
// body is not one.
@(private = "file")
pg_shape :: proc(q: ^Query, p: ^Problems) -> (shape: Pg_Shape, ok: bool) {
	tree, err := pg_query.parse(q.sql)
	if err != nil {
		f := err.(pg_query.Fault)
		problem(
			p,
			QUERIES_FILE,
			q.line + line_at(q.sql, f.cursorpos) - 1,
			"%s: %s",
			q.name,
			f.message,
		)
		return {}, false
	}
	defer pg_query.destroy(&tree)
	if len(tree.stmts) != 1 {
		problem(
			p,
			QUERIES_FILE,
			q.line,
			"%s holds %d statements: give each its own -- name: line",
			q.name,
			len(tree.stmts),
		)
		return {}, false
	}
	root, jerr := json.parse_string(tree.text, .JSON, true)
	if jerr != .None {
		problem(p, QUERIES_FILE, q.line, "%s: the parse tree is not JSON", q.name)
		return {}, false
	}
	w := Pg_Walk {
		sql   = q.sql,
		ctes  = make(map[string]json.Value),
		outer = make(map[string]bool),
	}
	collect_ctes(&w, root)
	walk(&w, root, false)
	if w.positional {
		problem(p, QUERIES_FILE, q.line, "%s: name every parameter @name rather than $n", q.name)
		return {}, false
	}
	shape = rewrite(q.sql, w.sites[:])
	shape.outer = w.outer
	shape.anything = w.anything
	return shape, true
}

@(private = "file")
Pg_Site :: struct {
	at:   int,
	name: string,
}

@(private = "file")
Pg_Walk :: struct {
	sql:        string,
	sites:      [dynamic]Pg_Site,
	positional: bool,
	ctes:       map[string]json.Value,
	outer:      map[string]bool,
	anything:   string,
}

// collect_ctes records every WITH query by name, so a join that makes a CTE
// nullable makes the tables it reads nullable too.
@(private = "file")
collect_ctes :: proc(w: ^Pg_Walk, v: json.Value) {
	#partial switch x in v {
	case json.Object:
		if cte, is_cte := x["CommonTableExpr"].(json.Object); is_cte {
			if name, named := cte["ctename"].(json.String); named {
				w.ctes[string(name)] = cte["ctequery"]
			}
		}
		for _, child in x {
			collect_ctes(w, child)
		}
	case json.Array:
		for child in x {
			collect_ctes(w, child)
		}
	}
}

@(private = "file")
walk :: proc(w: ^Pg_Walk, v: json.Value, in_returning: bool) {
	#partial switch x in v {
	case json.Object:
		walk_node(w, x, in_returning)
		for key, child in x {
			walk(w, child, in_returning || key == "returningList")
		}
	case json.Array:
		for child in x {
			walk(w, child, in_returning)
		}
	}
}

@(private = "file")
walk_node :: proc(w: ^Pg_Walk, x: json.Object, in_returning: bool) {
	if expr, is_expr := x["A_Expr"].(json.Object); is_expr {
		if at, name, found := parameter_site(w.sql, expr); found {
			append(&w.sites, Pg_Site{at = at, name = name})
		}
	}
	if _, is_param := x["ParamRef"]; is_param {
		w.positional = true
	}
	if _, grouping := x["GroupingSet"]; grouping && w.anything == "" {
		w.anything = "GROUPING SETS, ROLLUP or CUBE fill a grouped column with NULL"
	}
	if join, is_join := x["JoinExpr"].(json.Object); is_join {
		kind, _ := join["jointype"].(json.String)
		switch kind {
		case "JOIN_LEFT":
			mark_outer(w, join["rarg"], 0)
		case "JOIN_RIGHT":
			mark_outer(w, join["larg"], 0)
		case "JOIN_FULL":
			mark_outer(w, join["larg"], 0)
			mark_outer(w, join["rarg"], 0)
		}
	}
	if ref, is_ref := x["ColumnRef"].(json.Object); is_ref && in_returning && w.anything == "" {
		fields, _ := ref["fields"].(json.Array)
		if len(fields) > 1 && string_node(fields[0]) == "old" {
			w.anything = "RETURNING old is NULL for a row the statement inserted"
		}
	}
}

// parameter_site reads an A_Expr that is the prefix operator @ written hard
// against a name, as `@id` is, and returns where it is and the name.
@(private = "file")
parameter_site :: proc(sql: string, expr: json.Object) -> (at: int, name: string, found: bool) {
	if _, has_left := expr["lexpr"]; has_left {
		return
	}
	names, _ := expr["name"].(json.Array)
	if len(names) != 1 || string_node(names[0]) != "@" {
		return
	}
	loc, _ := expr["location"].(json.Integer)
	at = int(loc)
	end := at + 1
	for end < len(sql) && is_name_byte(sql[end], end == at + 1) {
		end += 1
	}
	if end == at + 1 {
		return
	}
	return at, strings.to_lower(sql[at + 1:end]), true
}

@(private = "file")
is_name_byte :: proc(c: u8, first: bool) -> bool {
	letter := c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c >= 0x80
	return letter || (!first && c >= '0' && c <= '9')
}

// string_node reads {"String": {"sval": "x"}}.
@(private = "file")
string_node :: proc(v: json.Value) -> string {
	node, _ := v.(json.Object)
	s, _ := node["String"].(json.Object)
	sval, _ := s["sval"].(json.String)
	return string(sval)
}

// mark_outer records every relation under v as nullable, following a CTE
// by name into the query it stands for.
@(private = "file")
mark_outer :: proc(w: ^Pg_Walk, v: json.Value, depth: int) {
	if depth > len(w.ctes) + 1 {
		return
	}
	#partial switch x in v {
	case json.Object:
		if rv, is_rv := x["RangeVar"].(json.Object); is_rv {
			if name, named := rv["relname"].(json.String); named {
				w.outer[string(name)] = true
				if cte, is_cte := w.ctes[string(name)]; is_cte {
					mark_outer(w, cte, depth + 1)
				}
			}
		}
		for _, child in x {
			mark_outer(w, child, depth)
		}
	case json.Array:
		for child in x {
			mark_outer(w, child, depth)
		}
	}
}

// rewrite replaces each @name with $n, numbering names by first appearance,
// so a name used twice is one parameter.
@(private = "file")
rewrite :: proc(sql: string, sites: []Pg_Site) -> Pg_Shape {
	slice.sort_by(sites, proc(a, b: Pg_Site) -> bool {return a.at < b.at})
	names: [dynamic]string
	sb: strings.Builder
	last := 0
	for s in sites {
		n, found := slice.linear_search(names[:], s.name)
		if !found {
			append(&names, s.name)
			n = len(names) - 1
		}
		strings.write_string(&sb, sql[last:s.at])
		fmt.sbprintf(&sb, "$%d", n + 1)
		last = s.at + 1 + len(s.name)
	}
	strings.write_string(&sb, sql[last:])
	return Pg_Shape{sql = strings.to_string(sb), names = names[:]}
}

// pg_params types the parameters from the server's inference. A -- params:
// line, when there is one, must name each and agree on its type; it sets
// the order the proc takes them in and can let one be NULL.
@(private = "file")
pg_params :: proc(pg: ^Pg, q: ^Query, names: []string, oids: []pq.Oid, p: ^Problems) {
	params: [dynamic]Param
	for name, i in names {
		t := pg_type(pg, oids[i])
		if !t.mapped {
			problem(
				p,
				QUERIES_FILE,
				q.line,
				"%s: @%s is %s, which jm-sqlgen does not map: cast it, as @%s::text",
				q.name,
				name,
				t.name,
				name,
			)
			continue
		}
		append(&params, Param{name = name, type = {kind = t.kind}})
	}
	if len(q.annotations) == 0 {
		q.params = params[:]
		q.annotations = params[:]
		return
	}
	used := make([]bool, len(q.annotations))
	for &param in params {
		found := false
		for a, k in q.annotations {
			if a.name != param.name {
				continue
			}
			found, used[k] = true, true
			if a.type.kind != param.type.kind {
				problem(
					p,
					QUERIES_FILE,
					q.line,
					"%s: @%s is %s on the server, not %s",
					q.name,
					a.name,
					KIND_NAMES[param.type.kind],
					KIND_NAMES[a.type.kind],
				)
			}
			param.type.nullable = a.type.nullable
		}
		if !found {
			problem(
				p,
				QUERIES_FILE,
				q.line,
				"%s: -- params: does not name @%s",
				q.name,
				param.name,
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

// pg_field types one result column: as its annotation says when it has one,
// which must agree with the server's type, and otherwise as the server
// types it, NULL unless its source column is NOT NULL and nothing in the
// statement can make it NULL.
@(private = "file")
pg_field :: proc(
	pg: ^Pg,
	q: ^Query,
	col: pq.Column,
	not_null: bool,
	shape: Pg_Shape,
	p: ^Problems,
) -> (
	f: Field,
	ok: bool,
) {
	name, sep, annotation := strings.partition(col.name, ":")
	f.name = strings.trim_space(name)
	f.column = col.name
	if !is_identifier(f.name) {
		problem(
			p,
			QUERIES_FILE,
			q.line,
			"%s: column %q cannot name a field: alias it AS \"name\"",
			q.name,
			col.name,
		)
		return {}, false
	}
	t := pg_type(pg, col.type_oid)
	if !t.mapped {
		problem(
			p,
			QUERIES_FILE,
			q.line,
			"%s: %s is %s, which jm-sqlgen does not map: cast it, as ::text",
			q.name,
			f.name,
			t.name,
		)
		return {}, false
	}
	if sep != "" {
		a, valid := parse_type(annotation)
		switch {
		case !valid:
			problem(
				p,
				QUERIES_FILE,
				q.line,
				"%s: %s: %q is not a type: use i16, i32, i64, f32, f64, bool, string, []byte or Maybe(T)",
				q.name,
				f.name,
				strings.trim_space(annotation),
			)
			return {}, false
		case a.kind != t.kind:
			problem(
				p,
				QUERIES_FILE,
				q.line,
				"%s: %s is %s on the server, not %s",
				q.name,
				f.name,
				KIND_NAMES[t.kind],
				KIND_NAMES[a.kind],
			)
			return {}, false
		}
		f.type = a
		f.annotated = true
		return f, true
	}
	f.type = Type {
		kind     = t.kind,
		nullable = true,
	}
	relation := pg.relations[col.table_oid]
	switch {
	case col.table_oid == 0:
		f.why = "an expression, which PostgreSQL does not say is NOT NULL"
	case !not_null:
	case shape.anything != "":
		f.why = shape.anything
	case shape.outer[relation]:
		f.why = fmt.aprintf("%s is on the outer side of a join", relation)
	case:
		f.type.nullable = false
	}
	return f, true
}

// pg_type maps a type oid, asking the server about a type it does not know:
// an enum reads as its label, a domain as its base type.
pg_type :: proc(pg: ^Pg, oid: pq.Oid) -> Pg_Type {
	if t, known := pg.types[oid]; known {
		return t
	}
	t: Pg_Type
	if kind, builtin := builtin_kind(oid); builtin {
		t = Pg_Type {
			kind   = kind,
			mapped = true,
			base   = oid,
		}
	} else {
		t = pg_lookup(pg, oid)
	}
	if t.name == "" {
		t.name = fmt.aprintf("type %d", oid)
	}
	pg.types[oid] = t
	return t
}

@(private = "file")
pg_lookup :: proc(pg: ^Pg, oid: pq.Oid) -> (t: Pg_Type) {
	res, err := pq.exec(
		pg.conn,
		`SELECT typtype, typcategory, typbasetype::int8, format_type(oid, NULL)
		 FROM pg_type WHERE oid = $1::oid`,
		{fmt.tprint(oid)},
	)
	if err != nil || len(res.rows) != 1 {
		return
	}
	row := res.rows[0]
	t.name = row[3].? or_else ""
	t.array = (row[1].? or_else "") == "A"
	switch row[0].? or_else "" {
	case "e":
		t.kind, t.mapped = .String, true
		labels, lerr := pq.exec(
			pg.conn,
			`SELECT enumlabel FROM pg_enum WHERE enumtypid = $1::oid ORDER BY enumsortorder`,
			{fmt.tprint(oid)},
		)
		if lerr == nil {
			out := make([]string, len(labels.rows))
			for r, i in labels.rows {
				out[i] = r[0].? or_else ""
			}
			t.labels = out
		}
	case "d":
		base, _ := strconv.parse_u64(row[2].? or_else "")
		b := pg_type(pg, pq.Oid(base))
		t.kind, t.mapped, t.labels, t.array, t.base = b.kind, b.mapped, b.labels, b.array, b.base
	}
	return
}

@(private = "file")
pg_load_relations :: proc(pg: ^Pg, p: ^Problems) -> bool {
	res, err := pq.exec(
		pg.conn,
		`SELECT c.oid::int8, c.relname FROM pg_class c
		 JOIN pg_namespace n ON n.oid = c.relnamespace
		 WHERE c.relkind IN ('r', 'p', 'v', 'm', 'f')
		 AND n.nspname NOT IN ('pg_catalog', 'information_schema')`,
	)
	if err != nil {
		problem(p, SCHEMA_FILE, 0, "reading the tables: %s", pg_text(err))
		return false
	}
	for row in res.rows {
		oid, _ := strconv.parse_u64(row[0].? or_else "")
		pg.relations[pq.Oid(oid)] = row[1].? or_else ""
	}
	return true
}

@(private = "file")
pg_run :: proc(pg: ^Pg, sql: string, p: ^Problems) -> bool {
	if _, err := pq.exec(pg.conn, sql); err != nil {
		problem(p, SCHEMA_FILE, 0, "%s: %s", sql, pg_text(err))
		return false
	}
	return true
}

pg_text :: proc(err: pq.Error) -> string {
	f, _ := err.(pq.Fault)
	if f.hint != "" {
		return fmt.aprintf("%s (%s)", f.message, f.hint)
	}
	return f.message
}

// line_at is the 1-based line of text that position, a 1-based count of
// characters as PostgreSQL gives it, falls on; 1 when there is none.
line_at :: proc(text: string, position: int) -> int {
	line := 1
	n := 0
	for r in text {
		n += 1
		if n >= position {
			break
		}
		if r == '\n' {
			line += 1
		}
	}
	return line
}
