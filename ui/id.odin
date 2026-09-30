package ui

import "base:runtime"
import "core:mem"
import "jm:ui/ops"

// Identity. A widget claims its Area_Id once a frame, in widget_open or
// claim_id, and the id hashes three things: what it sits in (the innermost
// open container, or what an overlay was opened from, mixed with the open
// scopes), where it was called from, and which of that call site's widgets
// in that parent it is. Without a key that last part is the occurrence:
// the first claim from a site in a parent is 0, the next 1. So a helper
// drawn in a loop or twice from one line gets its own ids with no key, and
// a widget shown only sometimes shifts nothing but later occurrences of its
// own call site in its own parent. A key replaces the occurrence, for state
// that must follow data rather than position: a row id in a list that
// reorders or filters. Key 0 is no key.

FNV_OFFSET :: u64(0xcbf29ce484222325)
FNV_PRIME  :: u64(0x100000001b3)

// id hashes the call site and key with FNV-1a 64. Stable across frames and
// runs of the same binary. It is the call-site half of a claim, and the
// whole of one without a layout.
@(private)
id :: proc(key: u64 = 0, loc := #caller_location) -> ops.Area_Id {
	h := fnv_bytes(FNV_OFFSET, transmute([]u8)loc.file_path)
	h = fnv_u64(h, u64(u32(loc.line)))
	h = fnv_u64(h, u64(u32(loc.column)))
	h = fnv_u64(h, key)
	return ops.Area_Id(h)
}

// id_mix derives a child id from a parent id and a key, for ids that must
// be distinct per parent (list items) rather than per call site.
id_mix :: proc(parent: ops.Area_Id, key: u64) -> ops.Area_Id {
	return ops.Area_Id(fnv_u64(fnv_u64(FNV_OFFSET, u64(parent)), key))
}

@(private)
fnv_bytes :: proc(h: u64, b: []u8) -> u64 {
	h := h
	for c in b {
		h ~= u64(c)
		h *= FNV_PRIME
	}
	return h
}

@(private)
fnv_u64 :: proc(h: u64, v: u64) -> u64 {
	v := v
	return fnv_bytes(h, mem.ptr_to_bytes(&v))
}

// claim is the id of a widget made now at loc under l, counting it as its
// call site's next occurrence in its parent when key is 0.
@(private)
claim :: proc(l: ^Layout, key: u64, loc: runtime.Source_Code_Location) -> ops.Area_Id {
	if l == nil {
		return id(key, loc)
	}
	site := u64(id(0, loc))
	parent := l.root_parent
	if c := innermost(l); c != nil {
		parent = c.place.id
	}
	parent = id_mix(l.scope, u64(parent))
	which: u64
	if key != 0 {
		which = fnv_u64(fnv_u64(site, 1), key)
	} else {
		k := Claim_Key{parent, site}
		n := l.claims[k]
		l.claims[k] = n + 1
		which = fnv_u64(fnv_u64(site, 0), n)
	}
	return id_mix(parent, which)
}

// Claim_Key is a call site in a parent, whose unkeyed claims claim counts.
@(private)
Claim_Key :: struct {
	parent: ops.Area_Id,
	site:   u64,
}
