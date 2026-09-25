/*
gen writes pg_query/nodes.odin from the schema libpg_query ships beside its
sources.

	just pg_query-gen

`pg_query/vendor/srcdata/` is how upstream generates its own protobuf
definitions and its Go, Ruby and Python bindings: `struct_defs.json` names
every parse node and every field with its C type, `enum_defs.json` every
enumerated type and its members, and `typedefs.json` what the scalar aliases
resolve to. Generating from it means a PostgreSQL major that renames a field
breaks the Odin build the moment someone bumps the vendored tree, which is the
whole reason the nodes are typed rather than walked as JSON.

Four of the schema's sixteen sections hold what a *parse* tree can contain:
nodes/parsenodes, nodes/primnodes, nodes/value and nodes/pg_list. The rest
describe planner and executor nodes, which only exist in a tree the server has
already analysed. Nothing here asserts that; the tests do. A tag with no
struct for it fails the parse, `a_broad_corpus_parses` runs fifty statements
across the grammar through it, and the fuzz suite reports any case that meets
one.

Two shapes in the JSON are written by hand in libpg_query's
src/pg_query_outfuncs_json.c rather than generated from this schema, so they
are special-cased here and named in SPECIAL:

  - A_Const carries its value under whichever of ival, fval, boolval, sval or
    bsval matches the constant's type, and has a location field the schema
    does not list.
  - The top level of a parse tree is a bare RawStmt object rather than the
    single-key wrapper every other node arrives in.

Names are upstream's, not Odin's: UpdateStmt and targetList rather than
Update_Stmt and target_list. A generated mirror of someone else's schema is
easier to check against that schema when it spells things the same way, and
the JSON keys are these names.
*/
package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

// FILES are the schema's sections that describe parse-tree nodes, in the
// order their structs are emitted in.
FILES :: []string{"nodes/parsenodes", "nodes/primnodes", "nodes/value", "nodes/pg_list"}

// SPECIAL names the structs whose decoder is hand-written in decode.odin
// because libpg_query writes their JSON by hand. The generator emits their
// struct and their tag, and leaves the body alone.
SPECIAL :: []string{"A_Const"}

// KEYWORDS are the Odin words a field cannot be named after: the language's
// keywords and its built-in type names, because a field called string hides
// the type from every field declared after it in the same struct. Two collide
// today, CreateCastStmt.context and JsonValueExpr.string; the rest are here so
// the next PostgreSQL release cannot introduce one silently.
KEYWORDS :: []string {
	"string",
	"bool",
	"byte",
	"rune",
	"int",
	"uint",
	"uintptr",
	"rawptr",
	"any",
	"cstring",
	"typeid",
	"i8",
	"i16",
	"i32",
	"i64",
	"i128",
	"u8",
	"u16",
	"u32",
	"u64",
	"u128",
	"f16",
	"f32",
	"f64",
	"complex32",
	"complex64",
	"complex128",
	"quaternion128",
	"quaternion256",
	"import",
	"package",
	"foreign",
	"when",
	"for",
	"in",
	"not_in",
	"if",
	"else",
	"do",
	"switch",
	"case",
	"break",
	"continue",
	"fallthrough",
	"defer",
	"return",
	"proc",
	"struct",
	"union",
	"enum",
	"bit_set",
	"bit_field",
	"map",
	"matrix",
	"using",
	"transmute",
	"cast",
	"auto_cast",
	"distinct",
	"context",
	"where",
	"dynamic",
	"asm",
	"inline",
	"no_inline",
	"size_of",
	"align_of",
	"offset_of",
	"type_of",
	"type_info_of",
	"typeid_of",
	"or_else",
	"or_return",
	"or_continue",
	"or_break",
	"nil",
	"true",
	"false",
}

// Kind is how a field is read out of the JSON. It decides both the Odin type
// and the call the decoder makes.
Kind :: enum {
	// Not emitted by libpg_query's JSON writer: the NodeTag every node
	// starts with, the embedded Expr superclass, a raw Datum.
	Skip,
	Bool,
	Text,
	// A C char, written as a one-character JSON string.
	Char,
	Int,
	Unsigned,
	Unsigned64,
	Real,
	// A Node under a single-key wrapper.
	Node,
	// A bare array of Nodes.
	Node_List,
	// A Bitmapset, written as a bare array of integers.
	Int_List,
	// A named struct under its field name, with no wrapper.
	Specific,
	// An enumerated type, written as its C enumerator's name.
	Enumerated,
}

// Field is one field of one node, resolved.
Field :: struct {
	// The JSON key, which is also the C field name.
	key:   string,
	// What it is called in Odin: the key, unless the key is a keyword.
	name:  string,
	kind:  Kind,
	// The struct or enum the field names, for Specific and Enumerated.
	named: string,
	// Set for a field libpg_query writes that the schema does not list, so
	// the conformance table can leave it out. A_Const's location is the only
	// one: upstream writes that node's JSON by hand.
	extra: bool,
}

// Node_Def is one generated struct.
Node_Def :: struct {
	name:    string,
	section: string,
	fields:  []Field,
}

// Enum_Def is one generated enumerated type.
Enum_Def :: struct {
	name:    string,
	members: []string,
}

main :: proc() {
	if len(os.args) != 3 {
		fmt.eprintln("usage: gen <srcdata dir> <out file>")
		os.exit(2)
	}
	srcdata, out_path := os.args[1], os.args[2]

	structs := read_json(fmt.tprintf("%s/struct_defs.json", srcdata)).(json.Object)
	enums := read_json(fmt.tprintf("%s/enum_defs.json", srcdata)).(json.Object)
	typedefs := read_json(fmt.tprintf("%s/typedefs.json", srcdata)).(json.Array)

	known_structs := collect_struct_names(structs)
	known_enums := collect_enum_names(enums)
	scalars := collect_typedefs(typedefs)

	defs := resolve_nodes(structs, known_structs, known_enums, scalars)
	used := used_enums(defs)
	enum_defs := resolve_enums(enums, used)

	b := strings.builder_make()
	emit(&b, defs, enum_defs)
	if err := os.write_entire_file(out_path, transmute([]byte)strings.to_string(b)); err != nil {
		fmt.eprintfln("gen: %s: %v", out_path, err)
		os.exit(1)
	}
	fmt.printfln("%s: %d nodes, %d enums", out_path, len(defs), len(enum_defs))
}

// read_json reads one schema file, or gives up: a half-read schema would
// generate a file that compiles and is missing nodes.
read_json :: proc(path: string) -> json.Value {
	bytes, rerr := os.read_entire_file_from_path(path, context.allocator)
	if rerr != nil {
		fmt.eprintfln("gen: cannot read %s: %v", path, rerr)
		os.exit(1)
	}
	value, err := json.parse(bytes, .JSON, true)
	if err != .None {
		fmt.eprintfln("gen: %s: %v", path, err)
		os.exit(1)
	}
	return value
}

// collect_struct_names is every struct a field may point at, across the four
// sections that matter.
collect_struct_names :: proc(structs: json.Object) -> map[string]bool {
	out := make(map[string]bool)
	for section in FILES {
		entries, has := structs[section].(json.Object)
		if !has {
			fmt.eprintfln("gen: the schema has no section %s", section)
			os.exit(1)
		}
		for name in entries {
			out[name] = true
		}
	}
	return out
}

// collect_enum_names is every enumerated type in the schema, from every
// section: a parse node may name an enum defined beside the planner's.
collect_enum_names :: proc(enums: json.Object) -> map[string]bool {
	out := make(map[string]bool)
	for _, section in enums {
		entries, is_object := section.(json.Object)
		if !is_object {
			continue
		}
		for name in entries {
			out[name] = true
		}
	}
	return out
}

// collect_typedefs maps each scalar alias to what it is an alias for, so that
// ParseLoc resolves to int and Oid to unsigned int.
collect_typedefs :: proc(typedefs: json.Array) -> map[string]string {
	out := make(map[string]string)
	for entry in typedefs {
		e, _ := entry.(json.Object)
		name, _ := e["new_type_name"].(json.String)
		source, _ := e["source_type"].(json.String)
		out[name] = source
	}
	return out
}

// resolve_nodes turns the schema's structs into what the emitter needs,
// sorted so that two runs of the generator produce the same file.
resolve_nodes :: proc(
	structs: json.Object,
	known_structs: map[string]bool,
	known_enums: map[string]bool,
	scalars: map[string]string,
) -> []Node_Def {
	out := make([dynamic]Node_Def)
	for section in FILES {
		entries := structs[section].(json.Object)
		names := make([]string, len(entries), context.temp_allocator)
		i := 0
		for name in entries {
			names[i] = name
			i += 1
		}
		slice.sort(names)
		for name in names {
			entry, _ := entries[name].(json.Object)
			raw, _ := entry["fields"].(json.Array)
			fields := make([dynamic]Field)
			for f in raw {
				field, _ := f.(json.Object)
				key, has_key := field["name"].(json.String)
				c_type, has_type := field["c_type"].(json.String)
				if !has_key || !has_type {
					// A comment-only entry: the schema records those too.
					continue
				}
				resolved := classify(c_type, known_structs, known_enums, scalars)
				if resolved.kind == .Skip {
					continue
				}
				resolved.key = key
				resolved.name = odin_name(key)
				append(&fields, resolved)
			}
			for synthetic in extras(name) {
				append(&fields, synthetic)
			}
			append(&out, Node_Def{name = name, section = section, fields = fields[:]})
		}
	}
	return out[:]
}

// extras are the fields libpg_query's hand-written JSON writer emits that
// the schema does not list.
A_CONST_LOCATION := []Field{{key = "location", name = "location", kind = .Int, extra = true}}

extras :: proc(node: string) -> []Field {
	if node == "A_Const" {
		return A_CONST_LOCATION
	}
	return nil
}

// classify maps a C type onto how the field is read. An unknown type is
// skipped and named on stderr, so a PostgreSQL release that introduces one
// is noticed rather than silently dropped.
classify :: proc(
	c_type: string,
	known_structs: map[string]bool,
	known_enums: map[string]bool,
	scalars: map[string]string,
	depth := 0,
) -> Field {
	// The types libpg_query's JSON writer never emits.
	switch c_type {
	case "NodeTag", "Expr", "Datum", "Bitmapset":
		return {kind = .Skip}
	case "Node*", "Node", "Expr*":
		return {kind = .Node}
	case "List*", "[]Node":
		return {kind = .Node_List}
	case "Bitmapset*":
		return {kind = .Int_List}
	case "char*":
		return {kind = .Text}
	case "char":
		return {kind = .Char}
	case "bool":
		return {kind = .Bool}
	case "int", "int16", "int32", "long", "short", "signed int":
		return {kind = .Int}
	case "unsigned int", "uint8", "uint16", "uint32":
		return {kind = .Unsigned}
	// Two aliases typedefs.json does not carry. Both are in the vendored
	// tree: src/postgres/include/c.h line 515 makes bits32 a uint32, and
	// src/postgres/include/common/relpath.h line 25 makes RelFileNumber an
	// Oid, which is itself a uint32.
	case "bits32", "RelFileNumber":
		return {kind = .Unsigned}
	case "uint64", "unsigned long":
		return {kind = .Unsigned64}
	case "double", "float":
		return {kind = .Real}
	}

	bare := strings.trim_suffix(c_type, "*")
	if bare in known_structs {
		return {kind = .Specific, named = bare}
	}
	if bare in known_enums {
		return {kind = .Enumerated, named = bare}
	}
	// A scalar alias: resolve it and try again. The depth bound is for a
	// schema that ever describes a cycle.
	if source, is_alias := scalars[bare]; is_alias && depth < 8 {
		return classify(source, known_structs, known_enums, scalars, depth + 1)
	}
	fmt.eprintfln("gen: no mapping for C type %s, field skipped", c_type)
	return {kind = .Skip}
}

// odin_name is the JSON key, unless it is an Odin keyword.
odin_name :: proc(key: string) -> string {
	for word in KEYWORDS {
		if key == word {
			return strings.concatenate({key, "_"})
		}
	}
	return key
}

// used_enums is every enumerated type a generated struct names, so the
// emitter writes those and no others.
used_enums :: proc(defs: []Node_Def) -> map[string]bool {
	out := make(map[string]bool)
	for def in defs {
		for field in def.fields {
			if field.kind == .Enumerated {
				out[field.named] = true
			}
		}
	}
	return out
}

// resolve_enums collects the members of each enumerated type in use, sorted
// by name so the output is stable.
resolve_enums :: proc(enums: json.Object, used: map[string]bool) -> []Enum_Def {
	out := make([dynamic]Enum_Def)
	for _, section in enums {
		entries, is_object := section.(json.Object)
		if !is_object {
			continue
		}
		for name, entry in entries {
			if !(name in used) {
				continue
			}
			def, _ := entry.(json.Object)
			values, _ := def["values"].(json.Array)
			members := make([dynamic]string)
			for v in values {
				member, _ := v.(json.Object)
				if member_name, has := member["name"].(json.String); has {
					append(&members, member_name)
				}
			}
			append(&out, Enum_Def{name = name, members = members[:]})
		}
	}
	sorted := out[:]
	slice.sort_by(sorted, proc(a, b: Enum_Def) -> bool {return a.name < b.name})
	return sorted
}

// emit writes the whole of nodes.odin.
emit :: proc(b: ^strings.Builder, defs: []Node_Def, enums: []Enum_Def) {
	write_header(b, defs, enums)
	write_union(b, defs)
	write_enums(b, enums)
	write_structs(b, defs)
	write_dispatcher(b, defs)
	write_decoders(b, defs)
	write_schema_table(b, defs)
}

write_header :: proc(b: ^strings.Builder, defs: []Node_Def, enums: []Enum_Def) {
	fmt.sbprintf(
		b,
		`// Generated by pg_query/gen from pg_query/vendor/srcdata. Do not edit;
// run ` + "`just pg_query-gen`" + ` after changing the vendored parser.
//
// %d node types and %d enumerated types, read from the same schema
// libpg_query generates its own bindings from. The names are PostgreSQL's:
// UpdateStmt, targetList, AND_EXPR. decode.odin holds the hand-written parts
// and the helpers these decoders call.
package pg_query

import "core:encoding/json"
import "core:mem"

`,
		len(defs),
		len(enums),
	)
}

// write_union emits Node, the one type every field that holds "some node"
// has. The variants are pointers, so the union is two words whatever it
// holds and a tree costs one allocation per node.
write_union :: proc(b: ^strings.Builder, defs: []Node_Def) {
	strings.write_string(
		b,
		`// Node is any parse node. libpg_query writes one as a single-key object
// keyed by its type, which is what decode_node reads.
Node :: union {
`,
	)
	for def in defs {
		fmt.sbprintf(b, "\t^%s,\n", def.name)
	}
	strings.write_string(b, "}\n\n")
}

write_enums :: proc(b: ^strings.Builder, enums: []Enum_Def) {
	for def in enums {
		fmt.sbprintf(b, "%s :: enum {{\n", def.name)
		for member in def.members {
			fmt.sbprintf(b, "\t%s,\n", member)
		}
		strings.write_string(b, "}\n\n")
		fmt.sbprintf(
			b,
			"// parse_%s reads the enumerator's C name. An unknown one gives the zero\n// value; schema_conforms is what keeps the set of names honest.\n@(private)\nparse_%s :: proc(s: string) -> %s {{\n\tswitch s {{\n",
			def.name,
			def.name,
			def.name,
		)
		for member in def.members {
			fmt.sbprintf(b, "\tcase \"%s\":\n\t\treturn .%s\n", member, member)
		}
		fmt.sbprintf(b, "\t}}\n\treturn .%s\n}}\n\n", def.members[0])
	}
}

write_structs :: proc(b: ^strings.Builder, defs: []Node_Def) {
	for def in defs {
		fmt.sbprintf(b, "// %s is %s %s.\n", def.name, def.section, def.name)
		if len(def.fields) == 0 {
			fmt.sbprintf(b, "%s :: struct {{}}\n\n", def.name)
			continue
		}
		width := 0
		for field in def.fields {
			width = max(width, len(field.name))
		}
		fmt.sbprintf(b, "%s :: struct {{\n", def.name)
		for field in def.fields {
			pad := strings.repeat(" ", width - len(field.name), context.temp_allocator)
			fmt.sbprintf(b, "\t%s:%s %s,\n", field.name, pad, odin_type(field))
		}
		strings.write_string(b, "}\n\n")
		if is_special(def.name) {
			fmt.sbprintf(
				b,
				"// %s's JSON is written by hand upstream, so decode_%s is too; it is in\n// decode.odin.\n\n",
				def.name,
				def.name,
			)
		}
	}
}

// odin_type is the field's declared type.
odin_type :: proc(field: Field) -> string {
	switch field.kind {
	case .Bool:
		return "bool"
	case .Text:
		return "string"
	case .Char:
		return "u8"
	case .Int:
		return "int"
	case .Unsigned:
		return "u32"
	case .Unsigned64:
		return "u64"
	case .Real:
		return "f64"
	case .Node:
		return "Node"
	case .Node_List:
		return "[]Node"
	case .Int_List:
		return "[]int"
	case .Specific:
		return fmt.tprintf("^%s", field.named)
	case .Enumerated:
		return field.named
	case .Skip:
	}
	return "int"
}

// write_dispatcher emits the tag-to-variant switch. A tag this build does not
// know is a failure rather than a nil field: a gate that silently loses a
// node it cannot name is a gate that passes something it never read.
write_dispatcher :: proc(b: ^strings.Builder, defs: []Node_Def) {
	strings.write_string(
		b,
		`// decode_node reads one single-key node object. ok is false for a tag this
// build has no type for, which parse turns into a Fault.
decode_node :: proc(v: json.Value, allocator: mem.Allocator) -> (node: Node, ok: bool) {
	obj := v.(json.Object) or_return
	for tag, body in obj {
		inner := body.(json.Object) or_return
		switch tag {
`,
	)
	for def in defs {
		fmt.sbprintf(b, "\t\tcase \"%s\":\n\t\t\treturn decode_%s(inner, allocator), true\n", def.name, def.name)
	}
	strings.write_string(
		b,
		`		}
		return nil, false
	}
	// An empty object is how a NULL element of a list is written.
	return nil, true
}

`,
	)
}

write_decoders :: proc(b: ^strings.Builder, defs: []Node_Def) {
	for def in defs {
		if is_special(def.name) {
			continue
		}
		fmt.sbprintf(
			b,
			"@(private)\ndecode_%s :: proc(o: json.Object, allocator: mem.Allocator) -> ^%s {{\n\tn := new(%s, allocator)\n",
			def.name,
			def.name,
			def.name,
		)
		for field in def.fields {
			write_field_decode(b, field)
		}
		strings.write_string(b, "\treturn n\n}\n\n")
	}
}

write_field_decode :: proc(b: ^strings.Builder, field: Field) {
	switch field.kind {
	case .Bool:
		fmt.sbprintf(b, "\tn.%s = bool_field(o, \"%s\")\n", field.name, field.key)
	case .Text:
		fmt.sbprintf(b, "\tn.%s = text_field(o, \"%s\", allocator)\n", field.name, field.key)
	case .Char:
		fmt.sbprintf(b, "\tn.%s = char_field(o, \"%s\")\n", field.name, field.key)
	case .Int:
		fmt.sbprintf(b, "\tn.%s = int_field(o, \"%s\")\n", field.name, field.key)
	case .Unsigned:
		fmt.sbprintf(b, "\tn.%s = u32(int_field(o, \"%s\"))\n", field.name, field.key)
	case .Unsigned64:
		fmt.sbprintf(b, "\tn.%s = u64(int_field(o, \"%s\"))\n", field.name, field.key)
	case .Real:
		fmt.sbprintf(b, "\tn.%s = real_field(o, \"%s\")\n", field.name, field.key)
	case .Node:
		fmt.sbprintf(b, "\tn.%s = node_field(o, \"%s\", allocator)\n", field.name, field.key)
	case .Node_List:
		fmt.sbprintf(b, "\tn.%s = node_list(o, \"%s\", allocator)\n", field.name, field.key)
	case .Int_List:
		fmt.sbprintf(b, "\tn.%s = int_list(o, \"%s\", allocator)\n", field.name, field.key)
	case .Specific:
		fmt.sbprintf(
			b,
			"\tif sub, has := object_field(o, \"%s\"); has {{\n\t\tn.%s = decode_%s(sub, allocator)\n\t}}\n",
			field.key,
			field.name,
			field.named,
		)
	case .Enumerated:
		// An enum is read from the JSON string without cloning it: the name
		// is switched on and thrown away.
		fmt.sbprintf(
			b,
			"\tn.%s = parse_%s(borrowed_text_field(o, \"%s\"))\n",
			field.name,
			field.named,
			field.key,
		)
	case .Skip:
	}
}

// write_schema_table emits what the conformance test reads: every node and
// every field the Odin side names, so the test can hold it against the
// vendored schema rather than against a list someone keeps by hand.
write_schema_table :: proc(b: ^strings.Builder, defs: []Node_Def) {
	strings.write_string(
		b,
		`// SCHEMA is what this file claims the vendored parser's schema says.
// schema_conforms in pg_query_test.odin reads srcdata/struct_defs.json and
// holds it against this, so a PostgreSQL bump that renames a field fails at
// just test instead of at runtime.
SCHEMA :: []struct {
	node:    string,
	section: string,
	fields:  []string,
} {
`,
	)
	for def in defs {
		// Braces in an Odin format string are directives, so the literal
		// ones are written rather than formatted.
		strings.write_string(b, "\t{")
		fmt.sbprintf(b, "\"%s\", \"%s\", ", def.name, def.section)
		strings.write_string(b, "{")
		first := true
		for field in def.fields {
			if field.extra {
				continue
			}
			if !first {
				strings.write_string(b, ", ")
			}
			first = false
			fmt.sbprintf(b, "\"%s\"", field.key)
		}
		strings.write_string(b, "}},\n")
	}
	strings.write_string(b, "}\n")
}

is_special :: proc(name: string) -> bool {
	for s in SPECIAL {
		if s == name {
			return true
		}
	}
	return false
}
