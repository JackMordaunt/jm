package ui

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:reflect"
import "core:strconv"
import "core:strings"

// persist_struct and restore_struct are persist and restored for a struct
// the app declares to hold what should outlive a hot-reload respawn: a
// page index, a theme, a scroll offset it owns. The struct is written as
// keyed lines of text, one `name value` per field, the vocabulary of the
// ops dump:
//
//	page 3
//	dark true
//	scroll[3].y 240
//	title "Settings"
//
// Fields that persist: integers, floats, booleans, enums (by name),
// strings (quoted), and nested structs and fixed arrays of those, named
// `outer.inner` and `name[i]`. Any other field is skipped. A reader keys
// by name, so a field added by the new build keeps its value, one it
// removed is ignored, and a value it cannot parse leaves the field alone:
// the blob was written by the last build, not this one.
//
//	Session :: struct { page: int, dark: bool, scroll: [PAGES]ui.Scroll_Offset }
//	// in the ui proc, first:
//	ui.restore_struct(gtx, &m.session)
//	// and last:
//	ui.persist_struct(gtx, m.session)

// persist_struct encodes v (see above) and persists it when the text
// differs from what was last persisted this way, so calling it every
// frame costs an encode into the frame arena and a comparison, and the
// host hears only of changes.
persist_struct :: proc(gtx: ^Ctx, v: $T) where intrinsics.type_is_struct(T) {
	v := v
	b := strings.builder_make(gtx.allocator)
	write_fields(&b, &v, type_info_of(T), "")
	text := strings.to_string(b)
	l := gtx.layout
	if l == nil {
		persist(gtx, transmute([]byte)text)
		return
	}
	if l.persisted_once && string(l.persisted[:]) == text {
		return
	}
	clear(&l.persisted)
	append(&l.persisted, text)
	l.persisted_once = true
	persist(gtx, l.persisted[:])
}

// restore_struct sets the fields of v^ that restored names, on the first
// frame after a respawn, and reports whether there was anything to
// restore. String fields are cloned with allocator and are the caller's
// to free; everything else is parsed in place with no allocation.
restore_struct :: proc(gtx: ^Ctx, v: ^$T, allocator := context.allocator) -> bool where intrinsics.type_is_struct(T) {
	data := restored(gtx)
	if data == nil {
		return false
	}
	rest := string(data)
	for line in strings.split_lines_iterator(&rest) {
		name, _, value := strings.partition(line, " ")
		if name != "" {
			set_field(v, type_info_of(T), name, value, allocator)
		}
	}
	return true
}

// write_fields writes every persistable field under base, of type ti, as
// a line named from prefix.
@(private = "file")
write_fields :: proc(b: ^strings.Builder, base: rawptr, ti: ^runtime.Type_Info, prefix: string) {
	path: [256]u8
	#partial switch info in runtime.type_info_base(ti).variant {
	case runtime.Type_Info_Struct:
		for i in 0 ..< info.field_count {
			name := prefix == "" ? info.names[i] : fmt.bprintf(path[:], "%s.%s", prefix, info.names[i])
			write_fields(b, rawptr(uintptr(base) + info.offsets[i]), info.types[i], name)
		}
	case runtime.Type_Info_Array:
		for i in 0 ..< info.count {
			name := fmt.bprintf(path[:], "%s[%d]", prefix, i)
			write_fields(b, rawptr(uintptr(base) + uintptr(i * info.elem_size)), info.elem, name)
		}
	case runtime.Type_Info_Integer, runtime.Type_Info_Float, runtime.Type_Info_Boolean, runtime.Type_Info_Enum:
		fmt.sbprintf(b, "%s %v\n", prefix, any{base, ti.id})
	case runtime.Type_Info_String:
		if !info.is_cstring {
			fmt.sbprintf(b, "%s %q\n", prefix, any{base, ti.id})
		}
	}
}

// set_field stores value into the field path names under base, of type
// ti, when the path resolves and the value parses; otherwise nothing.
@(private = "file")
set_field :: proc(base: rawptr, ti: ^runtime.Type_Info, path, value: string, allocator: runtime.Allocator) {
	#partial switch info in runtime.type_info_base(ti).variant {
	case runtime.Type_Info_Struct:
		head, rest := split_path(path)
		for i in 0 ..< info.field_count {
			if info.names[i] == head {
				set_field(rawptr(uintptr(base) + info.offsets[i]), info.types[i], rest, value, allocator)
				return
			}
		}
	case runtime.Type_Info_Array:
		if len(path) < 3 || path[0] != '[' {
			return
		}
		close := strings.index_byte(path, ']')
		if close < 0 {
			return
		}
		i, ok := strconv.parse_int(path[1:close], 10)
		if !ok || i < 0 || i >= info.count {
			return
		}
		rest := path[close + 1:]
		if len(rest) > 0 && rest[0] == '.' {
			rest = rest[1:]
		}
		set_field(rawptr(uintptr(base) + uintptr(i * info.elem_size)), info.elem, rest, value, allocator)
	case runtime.Type_Info_Integer:
		if path != "" {
			return
		}
		if info.signed {
			if n, ok := strconv.parse_i64(value); ok {
				store_int(base, ti.size, n)
			}
		} else if n, ok := strconv.parse_u64(value); ok {
			store_int(base, ti.size, i64(n))
		}
	case runtime.Type_Info_Float:
		if path != "" {
			return
		}
		if f, ok := strconv.parse_f64(value); ok {
			switch ti.size {
			case 4:
				(^f32)(base)^ = f32(f)
			case 8:
				(^f64)(base)^ = f
			}
		}
	case runtime.Type_Info_Boolean:
		if path != "" {
			return
		}
		if v, ok := strconv.parse_bool(value); ok {
			store_int(base, ti.size, i64(v))
		}
	case runtime.Type_Info_Enum:
		if path != "" {
			return
		}
		if v, ok := reflect.enum_from_name_any(ti.id, value); ok {
			store_int(base, ti.size, i64(v))
		}
	case runtime.Type_Info_String:
		if path != "" || info.is_cstring {
			return
		}
		if s, _, ok := strconv.unquote_string(value, allocator); ok {
			(^string)(base)^ = s
		}
	}
}

// split_path is path's first name and what follows it: `a.b[2]` is `a`
// and `b[2]`, `a[2].b` is `a` and `[2].b`.
@(private = "file")
split_path :: proc(path: string) -> (head, rest: string) {
	for c, i in path {
		if c == '.' {
			return path[:i], path[i + 1:]
		}
		if c == '[' {
			return path[:i], path[i:]
		}
	}
	return path, ""
}

// store_int writes n into the size-byte integer, boolean or enum at base.
@(private = "file")
store_int :: proc(base: rawptr, size: int, n: i64) {
	switch size {
	case 1:
		(^u8)(base)^ = u8(n)
	case 2:
		(^u16)(base)^ = u16(n)
	case 4:
		(^u32)(base)^ = u32(n)
	case 8:
		(^u64)(base)^ = u64(n)
	}
}
