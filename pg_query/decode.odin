package pg_query

import "core:encoding/json"
import "core:mem"
import "core:strings"

/*
The hand-written half of the node decoder: the field readers nodes.odin's
generated decoders call, and the one node whose JSON libpg_query writes by
hand rather than from the schema.

Every reader takes the field's absence as its zero value. That is not
laxness, it is the format: read the WRITE_ macros at the top of
`vendor/src/pg_query_outfuncs_json.c` and each one writes nothing when the C
field is zero, false, NULL or an empty list. So `"inh":true` is present and
`"inh":false` is not, and a decoder that insisted on every key would refuse
every tree.
*/

// bool_field reads a boolean, false when the key is absent.
@(private)
bool_field :: proc(o: json.Object, key: string) -> bool {
	v, has := o[key]
	if !has {
		return false
	}
	b, is_bool := v.(json.Boolean)
	return is_bool && bool(b)
}

// text_field reads a string into the caller's allocator, "" when absent.
@(private)
text_field :: proc(o: json.Object, key: string, allocator: mem.Allocator) -> string {
	v, has := o[key]
	if !has {
		return ""
	}
	s, is_string := v.(json.String)
	if !is_string {
		return ""
	}
	return strings.clone(string(s), allocator)
}

// borrowed_text is a string field read without cloning it, for a value that
// is looked at and thrown away rather than kept. It points into the json.Value
// the decode is walking, which is gone by the time parse returns, so nothing
// may hold on to it.
@(private)
borrowed_text_field :: proc(o: json.Object, key: string) -> string {
	v, has := o[key]
	if !has {
		return ""
	}
	s, is_string := v.(json.String)
	if !is_string {
		return ""
	}
	return string(s)
}

// char_field reads a C char. WRITE_CHAR_FIELD in
// vendor/src/pg_query_outfuncs_json.c writes it with %c inside quotes, so it
// arrives as a one-character string.
@(private)
char_field :: proc(o: json.Object, key: string) -> u8 {
	v, has := o[key]
	if !has {
		return 0
	}
	s, is_string := v.(json.String)
	if !is_string || len(s) == 0 {
		return 0
	}
	return s[0]
}

// int_field reads a whole number. The JSON writer emits integers as
// integers, but a float is accepted rather than dropped.
@(private)
int_field :: proc(o: json.Object, key: string) -> int {
	v, has := o[key]
	if !has {
		return 0
	}
	switch n in v {
	case json.Integer:
		return int(n)
	case json.Float:
		return int(n)
	case json.Null, json.Boolean, json.String, json.Array, json.Object:
	}
	return 0
}

// real_field reads a floating-point number.
@(private)
real_field :: proc(o: json.Object, key: string) -> f64 {
	v, has := o[key]
	if !has {
		return 0
	}
	switch n in v {
	case json.Float:
		return f64(n)
	case json.Integer:
		return f64(n)
	case json.Null, json.Boolean, json.String, json.Array, json.Object:
	}
	return 0
}

// object_field is the object under key, for a field holding a named node with
// no type wrapper around it.
@(private)
object_field :: proc(o: json.Object, key: string) -> (json.Object, bool) {
	v, has := o[key]
	if !has {
		return nil, false
	}
	sub, is_object := v.(json.Object)
	return sub, is_object
}

// node_field reads a field holding any node, which arrives wrapped in its
// type. A tag this build has no type for gives nil; decode_stmts is what
// turns that into a refusal, because it is the one place that can tell an
// absent field from an unreadable one.
@(private)
node_field :: proc(o: json.Object, key: string, allocator: mem.Allocator) -> Node {
	v, has := o[key]
	if !has {
		return nil
	}
	node, ok := decode_node(v, allocator)
	if !ok {
		record_unknown_tag(v)
		return nil
	}
	return node
}

// node_list reads a bare array of wrapped nodes. WRITE_LIST_FIELD in
// vendor/src/pg_query_outfuncs_json.c writes the brackets itself and calls
// _outNode per element, so a List field has no type wrapper of its own.
@(private)
node_list :: proc(o: json.Object, key: string, allocator: mem.Allocator) -> []Node {
	v, has := o[key]
	if !has {
		return nil
	}
	items, is_array := v.(json.Array)
	if !is_array {
		return nil
	}
	out := make([]Node, len(items), allocator)
	for item, i in items {
		node, ok := decode_node(item, allocator)
		if !ok {
			record_unknown_tag(item)
			continue
		}
		out[i] = node
	}
	return out
}

// int_list reads a Bitmapset. WRITE_BITMAPSET_FIELD in
// vendor/src/pg_query_outfuncs_json.c walks the members with bms_next_member
// and writes each as a bare integer.
@(private)
int_list :: proc(o: json.Object, key: string, allocator: mem.Allocator) -> []int {
	v, has := o[key]
	if !has {
		return nil
	}
	items, is_array := v.(json.Array)
	if !is_array {
		return nil
	}
	out := make([]int, len(items), allocator)
	for item, i in items {
		if n, is_int := item.(json.Integer); is_int {
			out[i] = int(n)
		}
	}
	return out
}

// A_Const is the one node libpg_query writes by hand: `_outAConst` in
// `vendor/src/pg_query_outfuncs_json.c` switches on the constant's type and
// writes it under ival, fval, boolval, sval or bsval, rather than under the
// schema's `val` wrapped in its own type name. The same function writes an
// empty boolval object for `false`, so the key's presence is what decides and
// not its contents.
@(private)
decode_A_Const :: proc(o: json.Object, allocator: mem.Allocator) -> ^A_Const {
	n := new(A_Const, allocator)
	n.isnull = bool_field(o, "isnull")
	n.location = int_field(o, "location")
	for key, kind in ([]string{"ival", "fval", "boolval", "sval", "bsval"}) {
		sub, has := object_field(o, key)
		if !has {
			continue
		}
		switch kind {
		case 0:
			n.val = decode_Integer(sub, allocator)
		case 1:
			n.val = decode_Float(sub, allocator)
		case 2:
			n.val = decode_Boolean(sub, allocator)
		case 3:
			n.val = decode_String(sub, allocator)
		case 4:
			n.val = decode_BitString(sub, allocator)
		}
		break
	}
	return n
}

// unknown is where a tag this build has no type for is recorded. A decoder
// runs deep inside a tree and cannot return an error from there, so it leaves
// the tag here and decode_stmts reads it afterwards.
//
// thread_local, and that is not decoration. libpg_query parses from several
// threads at once — jm:pg_query's own tests do — so a package global here
// would let one thread's unreadable node fail another thread's parse, and the
// two would race on the string as well. One per thread is exactly right: a
// parse begins and ends on the thread that started it.
@(private, thread_local)
unknown: struct {
	tag: string,
}

@(private)
record_unknown_tag :: proc(v: json.Value) {
	obj, is_object := v.(json.Object)
	if !is_object {
		unknown.tag = "<not an object>"
		return
	}
	for tag in obj {
		unknown.tag = tag
		return
	}
}

// decode_stmts turns the top level of a parse tree into typed statements. The
// elements of "stmts" are bare RawStmt objects rather than the single-key
// wrapper every node inside them arrives in, which is why this is here rather
// than generated.
//
// An unrecognised node type fails the whole parse. That is deliberate: the
// reason these types are generated from the schema at all is that a caller
// deciding whether a statement is safe must not be handed a tree with a hole
// where a node it could not name used to be.
@(private)
decode_stmts :: proc(
	root: json.Object,
	allocator: mem.Allocator,
) -> (
	stmts: []RawStmt,
	tag: string,
	ok: bool,
) {
	unknown.tag = ""
	list, is_array := root["stmts"].(json.Array)
	if !is_array {
		// A tree with no statements in it has no stmts key at all.
		return nil, "", true
	}
	out := make([]RawStmt, len(list), allocator)
	for item, i in list {
		obj, is_object := item.(json.Object)
		if !is_object {
			return nil, "<stmts holds something that is not a statement>", false
		}
		decoded := decode_RawStmt(obj, allocator)
		out[i] = decoded^
	}
	if unknown.tag != "" {
		return nil, unknown.tag, false
	}
	return out, "", true
}
