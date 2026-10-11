package game

import "base:runtime"
import "core:fmt"
import "core:reflect"
import "core:strings"

// The World as text, for an agent to read instead of pixels: every value
// on a line of its own under a path from the World down,
//
//	player.at = [12, 40]
//	player.state = Jumping
//	sparks.len = 2
//	sparks[0] = [3.5, 40]
//	shape.(Circle).radius = 4
//
// so a dump is grepped, a diff of two ticks names only what changed, and a
// watch says on which tick one value did. A fixed-capacity dynamic array
// shows its length and only its items in use. An array of plain values (a
// position, a grid of tiles) is one line; an array of structs is a line
// per field of each. An array of u8 that holds printable text and then
// only zeros is that text: a name. Any other is its numbers.
// The paths are the World's own field names, the same from tick to tick.

// dump_world is world as text, a line a value.
dump_world :: proc(world: ^$W, allocator := context.allocator) -> string {
	return dump_any(any{world, typeid_of(W)}, allocator)
}

// diff_world is what changed from before to after, a line a value,
// "path: before -> after", in the World's order: "" when nothing did. A
// value only one of them has (an item past the other's length) shows the
// other side as "-".
diff_world :: proc(before, after: ^$W, allocator := context.allocator) -> string {
	return diff_any(any{before, typeid_of(W)}, any{after, typeid_of(W)}, allocator)
}

// world_value is the value at path in world as dump_world writes it,
// false when world has no value there.
world_value :: proc(world: ^$W, path: string, allocator := context.allocator) -> (value: string, ok: bool) {
	return value_any(any{world, typeid_of(W)}, path, allocator)
}

// Watch follows a path in a World from tick to tick: watch_check says
// when what is at it, or under it, changes.
//
//	watch: game.Watch
//	game.watch_init(&watch, "player.grounded")
//	for ... { step(&world, input); if line, changed := game.watch_check(&watch, world, input.tick); changed { fmt.println(line) } }
Watch :: struct {
	path:   string, // borrowed: watch_init does not copy it
	last:   string, // what was there at the last check, as text; "" before the first
	seen:   bool,
	buffer: strings.Builder,
}

// watch_init readies watch to follow path, which it does not copy.
watch_init :: proc(watch: ^Watch, path: string, allocator := context.allocator) {
	watch^ = {
		path   = path,
		buffer = strings.builder_make(allocator),
	}
}

// watch_destroy frees what watch holds.
watch_destroy :: proc(watch: ^Watch) {
	delete(watch.last, watch.buffer.buf.allocator)
	strings.builder_destroy(&watch.buffer)
	watch^ = {}
}

// watch_check looks at world after tick and, when what is at the watched
// path changed since the last check, returns a line saying so: "tick 41
// player.grounded: true -> false", one change a line. The first check
// reports what is there; the line lives until the next check.
watch_check :: proc(watch: ^Watch, world: ^$W, tick: u64) -> (line: string, changed: bool) {
	return watch_check_any(watch, any{world, typeid_of(W)}, tick)
}

@(private)
watch_check_any :: proc(watch: ^Watch, world: any, tick: u64) -> (line: string, changed: bool) {
	allocator := watch.buffer.buf.allocator
	now := strings.builder_make(context.temp_allocator)
	for leaf in leaves_of(world, context.temp_allocator) {
		if under(leaf.path, watch.path) {
			fmt.sbprintfln(&now, "%s: %s", leaf.path, leaf.value)
		}
	}
	text := strings.to_string(now)
	if watch.seen && text == watch.last {
		return "", false
	}
	strings.builder_reset(&watch.buffer)
	if !watch.seen {
		for each in strings.split_lines(text, context.temp_allocator) {
			if each != "" {
				fmt.sbprintfln(&watch.buffer, "tick %d %s", tick, each)
			}
		}
	} else {
		write_changes(&watch.buffer, watch.last, text, tick)
	}
	delete(watch.last, allocator)
	watch.last = strings.clone(text, allocator)
	watch.seen = true
	return strings.trim_right(strings.to_string(watch.buffer), "\n"), true
}

// write_changes writes the lines of after that differ from before's as
// "tick N path: old -> new".
@(private)
write_changes :: proc(sb: ^strings.Builder, before, after: string, tick: u64) {
	old := make(map[string]string, context.temp_allocator)
	for line in strings.split_lines(before, context.temp_allocator) {
		if path, value, ok := split_leaf(line); ok {
			old[path] = value
		}
	}
	for line in strings.split_lines(after, context.temp_allocator) {
		path, value := split_leaf(line) or_continue
		was, had := old[path]
		if !had {
			was = "-"
		}
		if was != value {
			fmt.sbprintfln(sb, "tick %d %s: %s -> %s", tick, path, was, value)
		}
		delete_key(&old, path)
	}
	for path, value in old {
		fmt.sbprintfln(sb, "tick %d %s: %s -> -", tick, path, value)
	}
}

@(private)
split_leaf :: proc(line: string) -> (path, value: string, ok: bool) {
	at := strings.index(line, ": ")
	if at < 0 {
		return
	}
	return line[:at], line[at + 2:], true
}

// under reports whether path is watched by watched: the same, or below it.
@(private)
under :: proc(path, watched: string) -> bool {
	if !strings.has_prefix(path, watched) {
		return false
	}
	rest := path[len(watched):]
	return rest == "" || rest[0] == '.' || rest[0] == '['
}

@(private)
dump_any :: proc(world: any, allocator: runtime.Allocator) -> string {
	sb := strings.builder_make(allocator)
	for leaf in leaves_of(world, context.temp_allocator) {
		fmt.sbprintfln(&sb, "%s = %s", leaf.path, leaf.value)
	}
	return strings.to_string(sb)
}

@(private)
diff_any :: proc(before, after: any, allocator: runtime.Allocator) -> string {
	old := leaves_of(before, context.temp_allocator)
	new := leaves_of(after, context.temp_allocator)
	was := make(map[string]string, context.temp_allocator)
	for leaf in old {
		was[leaf.path] = leaf.value
	}
	sb := strings.builder_make(allocator)
	for leaf in new {
		value, had := was[leaf.path]
		if !had {
			fmt.sbprintfln(&sb, "%s: - -> %s", leaf.path, leaf.value)
		} else if value != leaf.value {
			fmt.sbprintfln(&sb, "%s: %s -> %s", leaf.path, value, leaf.value)
		}
		delete_key(&was, leaf.path)
	}
	for leaf in old {
		if _, gone := was[leaf.path]; gone {
			fmt.sbprintfln(&sb, "%s: %s -> -", leaf.path, leaf.value)
		}
	}
	return strings.to_string(sb)
}

@(private)
value_any :: proc(world: any, path: string, allocator: runtime.Allocator) -> (value: string, ok: bool) {
	for leaf in leaves_of(world, context.temp_allocator) {
		if leaf.path == path {
			return strings.clone(leaf.value, allocator), true
		}
	}
	return "", false
}

// Leaf is one value of a World: where it is, and it as text.
@(private)
Leaf :: struct {
	path:  string,
	value: string,
}

// leaves_of is every value in world, in field order.
@(private)
leaves_of :: proc(world: any, allocator: runtime.Allocator) -> []Leaf {
	out := make([dynamic]Leaf, allocator)
	walk(&out, world.data, type_info_of(world.id), "", allocator)
	return out[:]
}

@(private)
walk :: proc(out: ^[dynamic]Leaf, data: rawptr, info: ^runtime.Type_Info, path: string, allocator: runtime.Allocator) {
	base := runtime.type_info_base(info)
	if is_plain_value(base) {
		append(out, Leaf{path, value_text(data, info, allocator)})
		return
	}
	#partial switch kind in base.variant {
	case runtime.Type_Info_Struct:
		for ii in 0 ..< int(kind.field_count) {
			field := rawptr(uintptr(data) + kind.offsets[ii])
			walk(out, field, kind.types[ii], child_path(path, kind.names[ii], allocator), allocator)
		}
	case runtime.Type_Info_Array:
		if is_plain_value(runtime.type_info_base(kind.elem)) {
			append(out, Leaf{path, value_text(data, info, allocator)})
			return
		}
		for ii in 0 ..< kind.count {
			walk(out, rawptr(uintptr(data) + uintptr(ii * kind.elem_size)), kind.elem, fmt.aprintf("%s[%d]", path, ii, allocator = allocator), allocator)
		}
	case runtime.Type_Info_Enumerated_Array:
		if is_plain_value(runtime.type_info_base(kind.elem)) {
			append(out, Leaf{path, value_text(data, info, allocator)})
			return
		}
		for ii in 0 ..< kind.count {
			name := enum_name(kind.index, kind.min_value + runtime.Type_Info_Enum_Value(ii))
			walk(out, rawptr(uintptr(data) + uintptr(ii * kind.elem_size)), kind.elem, fmt.aprintf("%s[.%s]", path, name, allocator = allocator), allocator)
		}
	case runtime.Type_Info_Fixed_Capacity_Dynamic_Array:
		count := (^int)(uintptr(data) + kind.len_offset)^
		append(out, Leaf{child_path(path, "len", allocator), fmt.aprint(count, allocator = allocator)})
		for ii in 0 ..< count {
			walk(out, rawptr(uintptr(data) + uintptr(ii * kind.elem_size)), kind.elem, fmt.aprintf("%s[%d]", path, ii, allocator = allocator), allocator)
		}
	case runtime.Type_Info_Union:
		variant := reflect.union_variant_type_info(any{data, info.id})
		if variant == nil {
			append(out, Leaf{path, "nil"})
			return
		}
		walk(out, data, variant, fmt.aprintf("%s.(%v)", path, variant.id, allocator = allocator), allocator)
	case:
		append(out, Leaf{path, value_text(data, info, allocator)})
	}
}

@(private)
child_path :: proc(path, name: string, allocator: runtime.Allocator) -> string {
	return name if path == "" else strings.concatenate({path, ".", name}, allocator)
}

// is_plain_value reports whether a value of base prints on one line:
// numbers, bools, runes, enums and bit sets.
@(private)
is_plain_value :: proc(base: ^runtime.Type_Info) -> bool {
	#partial switch _ in base.variant {
	case runtime.Type_Info_Integer,
	     runtime.Type_Info_Float,
	     runtime.Type_Info_Boolean,
	     runtime.Type_Info_Rune,
	     runtime.Type_Info_Enum,
	     runtime.Type_Info_Bit_Set,
	     runtime.Type_Info_Complex,
	     runtime.Type_Info_Quaternion,
	     runtime.Type_Info_Matrix,
	     runtime.Type_Info_Simd_Vector:
		return true
	}
	return false
}

// text_of is bytes as the text they hold, false unless they are
// printable ASCII and then only zeros.
@(private)
text_of :: proc(bytes: []u8) -> (text: string, ok: bool) {
	end := 0
	for end < len(bytes) && bytes[end] >= ' ' && bytes[end] <= '~' {
		end += 1
	}
	for zero in bytes[end:] {
		if zero != 0 {
			return "", false
		}
	}
	return string(bytes[:end]), true
}

// value_text is the value at data, of type info, as one line.
@(private)
value_text :: proc(data: rawptr, info: ^runtime.Type_Info, allocator: runtime.Allocator) -> string {
	base := runtime.type_info_base(info)
	if array, ok := base.variant.(runtime.Type_Info_Array); ok && array.elem.id == u8 {
		if text, is_text := text_of(([^]u8)(data)[:array.count]); is_text {
			return fmt.aprintf("%q", text, allocator = allocator)
		}
	}
	text := fmt.aprint(any{data, info.id}, allocator = allocator)
	// fmt prints a bit set's type before its members ("bit_set[State]{Jumping}"):
	// keep the members (inspect_test.odin pins "keys = {Jumping}").
	if _, ok := base.variant.(runtime.Type_Info_Bit_Set); ok {
		if at := strings.index_byte(text, '{'); at > 0 {
			return text[at:]
		}
	}
	return text
}

@(private)
enum_name :: proc(index: ^runtime.Type_Info, value: runtime.Type_Info_Enum_Value) -> string {
	if kind, ok := runtime.type_info_base(index).variant.(runtime.Type_Info_Enum); ok {
		for name, ii in kind.names {
			if kind.values[ii] == value {
				return name
			}
		}
	}
	return fmt.tprint(value)
}
