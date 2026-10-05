package ui

import "base:intrinsics"
import "base:runtime"
import "core:reflect"
import "jm:ui/ops"
import "core:mem"

// Scope is an open ui.scope; end it with close(&s), usually deferred.
Scope :: struct {
	gtx:       ^Ctx,
	prev:      ops.Area_Id,
	prev_root: ops.Area_Id,
	active:    bool,
}

// scope mixes v into the id of every widget recorded until end: a key for a
// whole region at once. Widgets need no scope to be told apart (see claim_id
// in ui/id.odin); a scope makes a region's state follow its data, so a row
// drawn from a record keeps its hover, focus and animations when the list
// reorders or filters, where by position it would take its neighbour's.
// Scopes nest: each mixes into the one around it. v is what the region is: a
// pointer to its state, an index, an enum, or a string such as a record's
// id. A pointer into a slice that grows moves, and its ids with it; scope by
// a stable id there.
//
// A scope opened with no scope around it is a root, such as a page: state
// kept for widgets under it can outlive frames the page is not drawn in,
// with retain.
scope_open :: proc(gtx: ^Ctx, v: $T) -> Scope {
	return scope_open_hash(gtx, scope_hash(v))
}

// scope_open_hash is scope_open with v already hashed.
@(private)
scope_open_hash :: proc(gtx: ^Ctx, hash: u64) -> Scope {
	l := gtx.layout
	if l == nil {
		return {}
	}
	s := Scope{gtx, l.scope, l.scope_root, true}
	l.scope = id_mix(l.scope, hash)
	if l.scope_root == 0 {
		l.scope_root = l.scope
	}
	return s
}

// scope_close closes s: ids stop mixing its value.
scope_close :: proc(s: ^Scope) {
	if !s.active {
		return
	}
	s.active = false
	if l := s.gtx.layout; l != nil {
		l.scope, l.scope_root = s.prev, s.prev_root
	}
}

// retain keeps the state of widgets under the root scope of v (a page
// scoped with ui.scope_open(gtx, v) at the top) through this frame whether or
// not they are drawn, so a page switched away from keeps its scroll
// offsets, animations and gestures for when it comes back. Call it every
// frame the page should live, drawn or not.
retain :: proc(gtx: ^Ctx, v: $T) {
	if l := gtx.layout; l != nil {
		l.retained[id_mix(0, scope_hash(v))] = l.frame
	}
}

// claim_id is the id of a widget made now at loc, for a widget that makes
// its id without widget_open (an overlay's own state, say). Call it once
// per widget per frame and derive every further id the widget needs from
// the result with id_mix: a second claim is a second widget.
claim_id :: proc(gtx: ^Ctx, key: u64 = 0, loc := #caller_location) -> ops.Area_Id {
	return claim(gtx.layout, key, loc)
}

// widget_data is the retained value of type T kept for widget id: zero the
// first frame it is asked for, then whatever the widget left in it. It
// lives, at the same address, until a frame passes without the widget
// asking for it (or, under a retained scope, until the scope lapses): a
// component's own presentation state — timers, gesture progress, an
// animation's anchor — without borrowing Widget_State's fields. Each type
// is its own slot, so one widget may keep several.
widget_data :: proc(gtx: ^Ctx, id: ops.Area_Id, $T: typeid) -> ^T {
	l := gtx.layout
	if l == nil {
		return new(T, gtx.allocator)
	}
	return (^T)(data_slot(l, Data_Key{id, T}, size_of(T), align_of(T)))
}

// data_slot is widget_data's untyped half: key's value, allocated zeroed
// the first time, marked seen this frame under the open root scope.
@(private)
data_slot :: proc(l: ^Layout, key: Data_Key, size, align: int) -> rawptr {
	e, ok := &l.data[key]
	if !ok {
		ptr, _ := mem.alloc(size, align, l.allocator)
		l.data[key] = Data_Entry{ptr = ptr}
		e = &l.data[key]
	}
	e.seen, e.root = l.frame, l.scope_root
	return e.ptr
}

// Data_Key and Data_Entry are widget_data's table.
@(private)
Data_Key :: struct {
	id:   ops.Area_Id,
	type: typeid,
}

@(private)
Data_Entry :: struct {
	ptr:  rawptr,
	seen: u64,
	root: ops.Area_Id,
}

// kept reports whether state last seen in frame seen under root lives on
// into frame: seen last frame or this, or under a root retained then.
@(private)
kept :: proc(l: ^Layout, seen: u64, root: ops.Area_Id) -> bool {
	if seen + 1 >= l.frame {
		return true
	}
	if root != 0 {
		if r, ok := l.retained[root]; ok && r + 1 >= l.frame {
			return true
		}
	}
	return false
}

// scope_hash is v as the u64 a scope mixes in.
@(private)
scope_hash :: proc(v: $T) -> u64 {
	when T == string {
		return fnv_bytes(FNV_OFFSET, transmute([]u8)v)
	} else when intrinsics.type_is_pointer(T) || T == rawptr {
		return u64(uintptr(rawptr(v)))
	} else when intrinsics.type_is_integer(T) || intrinsics.type_is_enum(T) {
		return u64(v)
	} else {
		#panic("ui.scope takes a pointer, an integer, an enum or a string")
	}
}

// scope_hash_any is scope_hash for a value known only at run time, as the
// scope guard takes it; anything else fails as scope_hash fails to build.
@(private)
scope_hash_any :: proc(v: any) -> u64 {
	#partial switch info in runtime.type_info_core(type_info_of(v.id)).variant {
	case runtime.Type_Info_String:
		if !info.is_cstring && info.encoding == .UTF_8 {
			s := (^string)(v.data)^
			return fnv_bytes(FNV_OFFSET, transmute([]u8)s)
		}
	case runtime.Type_Info_Pointer:
		return u64(uintptr((^rawptr)(v.data)^))
	case runtime.Type_Info_Integer:
		h, _ := reflect.as_u64(v)
		return h
	}
	panic("ui.scope takes a pointer, an integer, an enum or a string")
}
