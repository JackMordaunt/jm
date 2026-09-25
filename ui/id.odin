package ui

import "core:mem"

// Identity. A widget's Area_Id is a hash of where it was called from plus a
// caller key, so the same call site yields the same id every frame without
// the author naming anything. Widgets called in a loop from one call site
// need a distinct key each (the loop index, a row id); items drawn by list
// are told apart automatically because list scopes each item.

FNV_OFFSET :: u64(0xcbf29ce484222325)
FNV_PRIME  :: u64(0x100000001b3)

// id hashes the call site and key with FNV-1a 64. Stable across frames and
// runs of the same binary.
id :: proc(key: u64 = 0, loc := #caller_location) -> Area_Id {
	h := fnv_bytes(FNV_OFFSET, transmute([]u8)loc.file_path)
	h = fnv_u64(h, u64(u32(loc.line)))
	h = fnv_u64(h, u64(u32(loc.column)))
	h = fnv_u64(h, key)
	return Area_Id(h)
}

// id_mix derives a child id from a parent id and a key, for ids that must
// be distinct per parent (list items) rather than per call site.
id_mix :: proc(parent: Area_Id, key: u64) -> Area_Id {
	return Area_Id(fnv_u64(fnv_u64(FNV_OFFSET, u64(parent)), key))
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
