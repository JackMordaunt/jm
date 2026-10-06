package main

import "core:strings"

// read_engine reads the `-- engine: <name>` line that must open a schema or
// query file, before anything but blank lines.
read_engine :: proc(text, file: string, p: ^Problems) -> (engine: Engine, ok: bool) {
	rest := text
	n := 0
	for line in strings.split_lines_iterator(&rest) {
		n += 1
		s := strings.trim_space(line)
		if s == "" {
			continue
		}
		name, is_header := directive(s, "engine")
		if !is_header {
			break
		}
		for e_name, e in ENGINE_NAMES {
			if name == e_name {
				return e, true
			}
		}
		problem(p, file, n, "unknown engine %q: use sqlite or postgres", name)
		return {}, false
	}
	problem(p, file, 0, "the first line must say which database it is for: -- engine: sqlite")
	return {}, false
}

// read_queries splits queries.sql into its `-- name:` blocks. A block's
// comment lines directly under the name line are its doc comment, bar a
// `-- params:` line; the SQL runs to the next name line.
read_queries :: proc(text: string, p: ^Problems) -> []Query {
	queries: [dynamic]Query
	q: ^Query
	in_header := false
	doc: [dynamic]string
	body: strings.Builder
	rest := text
	n := 0
	for line in strings.split_lines_iterator(&rest) {
		n += 1
		s := strings.trim_space(strings.trim_right(line, "\r"))
		if value, is_name := directive(s, "name"); is_name {
			finish_query(q, &doc, &body, p)
			append(&queries, start_query(value, n, p))
			q = &queries[len(queries) - 1]
			in_header = true
			continue
		}
		if q == nil {
			if s != "" && !strings.has_prefix(s, "--") {
				problem(
					p,
					QUERIES_FILE,
					n,
					"SQL before the first -- name: line belongs to no query",
				)
			}
			continue
		}
		if in_header && strings.has_prefix(s, "--") {
			if value, is_params := directive(s, "params"); is_params {
				q.annotations = read_params(value, n, p)
			} else {
				append(&doc, strings.trim_space(s[2:]))
			}
			continue
		}
		if in_header && s == "" {
			continue
		}
		if in_header {
			in_header = false
			q.line = n
		}
		strings.write_string(&body, line)
		strings.write_byte(&body, '\n')
	}
	finish_query(q, &doc, &body, p)
	seen: map[string]int
	for query in queries {
		if first, dup := seen[query.name]; dup {
			problem(
				p,
				QUERIES_FILE,
				query.line,
				"%s is already the name of the query at line %d",
				query.name,
				first,
			)
		}
		seen[query.name] = query.line
	}
	for query in queries {
		if query.kind != .Many {
			continue
		}
		for suffix in MANY_SUFFIXES {
			name := strings.concatenate({query.name, suffix})
			if line, taken := seen[name]; taken {
				problem(
					p,
					QUERIES_FILE,
					line,
					"%s is a name the :many query %s generates: rename one",
					name,
					query.name,
				)
			}
		}
	}
	return queries[:]
}

// MANY_SUFFIXES are the names a :many query generates beyond its own.
@(private = "file")
MANY_SUFFIXES := [?]string {
	"_open",
	"_next",
	"_close",
	"_all",
	"_free",
	"_free_row",
	"_guard_close",
}

QUERIES_FILE :: "queries.sql"
SCHEMA_FILE  :: "schema.sql"

// RESERVED are names the generated code uses for itself, so neither a query
// nor a parameter may take them.
@(private = "file")
RESERVED := [?]string{"allocator", "check", "db", "err", "found", "row", "rows", "stmt"}

is_reserved :: proc(name: string) -> bool {
	if strings.has_prefix(name, "sqlgen_") {
		return true
	}
	for r in RESERVED {
		if name == r {
			return true
		}
	}
	return false
}

@(private = "file")
start_query :: proc(value: string, line: int, p: ^Problems) -> Query {
	q := Query {
		line = line,
	}
	fields := strings.fields(value)
	if len(fields) != 2 {
		problem(
			p,
			QUERIES_FILE,
			line,
			"write the name line as -- name: <name> <:one|:many|:exec|:rows|:last_id>",
		)
		return q
	}
	q.name = fields[0]
	if !is_identifier(q.name) || is_reserved(q.name) {
		problem(
			p,
			QUERIES_FILE,
			line,
			"%q cannot name a query: use a lower-case Odin identifier the generated code does not use",
			q.name,
		)
	}
	found := false
	for tag, k in QUERY_KIND_TAGS {
		if fields[1] == tag {
			q.kind = k
			found = true
		}
	}
	if !found {
		problem(
			p,
			QUERIES_FILE,
			line,
			"%s: unknown result %q: use :one, :many, :exec, :rows or :last_id",
			q.name,
			fields[1],
		)
	}
	return q
}

@(private = "file")
finish_query :: proc(q: ^Query, doc: ^[dynamic]string, body: ^strings.Builder, p: ^Problems) {
	if q == nil {
		return
	}
	q.doc = doc[:]
	doc^ = {}
	sql := strings.trim_space(strings.to_string(body^))
	sql = strings.trim_right_space(strings.trim_suffix(sql, ";"))
	q.sql = strings.clone(sql)
	strings.builder_reset(body)
	if q.sql == "" {
		problem(p, QUERIES_FILE, q.line, "%s has no SQL", q.name)
	}
}

// read_params reads `done: bool, id: i64, note: Maybe(string)`.
@(private = "file")
read_params :: proc(value: string, line: int, p: ^Problems) -> []Param {
	params: [dynamic]Param
	rest := value
	for item in strings.split_iterator(&rest, ",") {
		name, _, type_text := strings.partition(item, ":")
		name = strings.trim_space(name)
		t, ok := parse_type(type_text)
		switch {
		case !is_identifier(name) || is_reserved(name):
			problem(
				p,
				QUERIES_FILE,
				line,
				"%q cannot name a parameter: use an Odin identifier the generated code does not use",
				name,
			)
		case !ok:
			problem(
				p,
				QUERIES_FILE,
				line,
				"@%s: %q is not a type: use i64, f64, bool, string, []byte or Maybe(T)",
				name,
				strings.trim_space(type_text),
			)
		case:
			append(&params, Param{name = name, type = t})
		}
	}
	return params[:]
}

// directive reads `-- key: value` and returns the value.
@(private = "file")
directive :: proc(line, key: string) -> (value: string, ok: bool) {
	if !strings.has_prefix(line, "--") {
		return "", false
	}
	head, sep, tail := strings.partition(line[2:], ":")
	if sep == "" || strings.trim_space(head) != key {
		return "", false
	}
	return strings.trim_space(tail), true
}
