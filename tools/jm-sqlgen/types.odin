package main

import "core:fmt"
import "core:strings"

// Engine is the database a schema and its queries are written for. Each
// engine prepares the statements itself and has its own emitter, since the
// generated code calls that engine's jm package.
Engine :: enum {
	Sqlite,
	Postgres,
}

ENGINE_NAMES := [Engine]string {
	.Sqlite   = "sqlite",
	.Postgres = "postgres",
}

// Kind is the Odin type a value takes in generated code.
Kind :: enum {
	I64,
	F64,
	Bool,
	String,
	Bytes,
}

KIND_NAMES := [Kind]string {
	.I64    = "i64",
	.F64    = "f64",
	.Bool   = "bool",
	.String = "string",
	.Bytes  = "[]byte",
}

// Type is a Kind and whether NULL is possible, which makes it Maybe(Kind).
Type :: struct {
	kind:     Kind,
	nullable: bool,
}

// Query_Kind is what a query hands back, as its `-- name:` line tags it.
Query_Kind :: enum {
	One, // the first row, if any; a second row is an error
	Many, // an iterator over the rows
	Exec, // nothing
	Rows, // how many rows the statement changed
	Last_Id, // the rowid the INSERT assigned
}

QUERY_KIND_TAGS := [Query_Kind]string {
	.One     = ":one",
	.Many    = ":many",
	.Exec    = ":exec",
	.Rows    = ":rows",
	.Last_Id = ":last_id",
}

// Param is one @name parameter and the type the generated proc takes it as.
Param :: struct {
	name: string,
	type: Type,
}

// Field is one result column as the row struct holds it.
Field :: struct {
	name:      string,
	type:      Type,
	// The author's annotation set the type, rather than the schema.
	annotated: bool,
	// Why the type is Maybe when the schema says NOT NULL: what in the
	// statement can produce a NULL the declaration does not rule out.
	why:       string,
}

// Query is one `-- name:` block of queries.sql, and once described, the
// parameters and fields the engine reported for it.
Query :: struct {
	name:        string,
	kind:        Query_Kind,
	line:        int,
	doc:         []string,
	sql:         string,
	// From the `-- params:` line, in the order written.
	annotations: []Param,
	// In the order the engine binds them.
	params:      []Param,
	fields:      []Field,
}

parse_type :: proc(text: string) -> (t: Type, ok: bool) {
	s := strings.trim_space(text)
	if strings.has_prefix(s, "Maybe(") && strings.has_suffix(s, ")") {
		s = strings.trim_space(s[len("Maybe("):len(s) - 1])
		t.nullable = true
	}
	for name, k in KIND_NAMES {
		if name == s {
			t.kind = k
			return t, true
		}
	}
	return {}, false
}

type_name :: proc(t: Type, allocator := context.allocator) -> string {
	if t.nullable {
		return fmt.aprintf("Maybe(%s)", KIND_NAMES[t.kind], allocator = allocator)
	}
	return KIND_NAMES[t.kind]
}

// Problems collects what is wrong with the input, each as file:line:
// message, so one run reports everything rather than the first.
Problems :: struct {
	list: [dynamic]string,
}

problem :: proc(p: ^Problems, file: string, line: int, format: string, args: ..any) {
	msg := fmt.aprintf(format, ..args)
	if line > 0 {
		append(&p.list, fmt.aprintf("%s:%d: %s", file, line, msg))
	} else {
		append(&p.list, fmt.aprintf("%s: %s", file, msg))
	}
}

// is_identifier reports whether s can name an Odin declaration or field and
// is not one of the words Odin keeps for itself.
is_identifier :: proc(s: string) -> bool {
	if len(s) == 0 {
		return false
	}
	for r, i in s {
		letter := r == '_' || (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z')
		digit := r >= '0' && r <= '9'
		if !letter && !(digit && i > 0) {
			return false
		}
	}
	for word in ODIN_WORDS {
		if s == word {
			return false
		}
	}
	return true
}

// ODIN_WORDS are Odin's keywords and the predeclared names a field or
// parameter would shadow.
@(private = "file")
ODIN_WORDS := [?]string {
	"align_of",
	"any",
	"auto_cast",
	"bit_field",
	"bit_set",
	"bool",
	"break",
	"byte",
	"case",
	"cast",
	"context",
	"continue",
	"cstring",
	"defer",
	"distinct",
	"do",
	"dynamic",
	"else",
	"enum",
	"f32",
	"f64",
	"fallthrough",
	"false",
	"for",
	"foreign",
	"i32",
	"i64",
	"if",
	"import",
	"in",
	"int",
	"len",
	"map",
	"matrix",
	"nil",
	"not_in",
	"offset_of",
	"or_break",
	"or_continue",
	"or_else",
	"or_return",
	"package",
	"proc",
	"return",
	"rune",
	"size_of",
	"string",
	"struct",
	"switch",
	"transmute",
	"true",
	"type_of",
	"typeid",
	"u8",
	"uint",
	"union",
	"using",
	"when",
	"where",
}
