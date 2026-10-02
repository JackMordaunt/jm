/*
Package ring is a bounded ring of fixed-size messages for one producer and one
consumer on different threads, with no lock.

	Shape    a message type's layout: size, alignment and identity
	Raw      messages of a Shape known at run time, as a pipeline edge needs
	Ring(T)  the same for one type, as a test or a plain program wants

Each end lives on its own cache line and keeps a copy of the other end's index,
refreshed only when the copy says full or empty. A push or a pop therefore
touches the other side's line once per fill, not once per message, and the two
ends never write the same line. The storage sits with the read-only fields on
a third line.

The producer calls push and full; the consumer calls pop and has. Both may call
len, which reads both ends and is exact. Nothing here wakes anyone: what to do
when a message lands is the caller's.
*/
package ring

import "core:mem"
import "core:sync"

// LINE is the cache line the two ends are kept apart by.
LINE :: 64

// Shape is what a ring needs to know about its message type: how many bytes,
// how they must be aligned, and which type it is, so two ends wired by hand
// can be checked to agree. The ring lays messages out at a stride of `size`,
// which relies on the size being padded to the alignment; the alignment test
// checks that for an over-aligned type.
Shape :: struct {
	size:  int,
	align: int,
	id:    typeid,
}

shape_of :: proc($T: typeid) -> Shape {
	return {size_of(T), align_of(T), T}
}

Raw :: struct {
	// Shared, and read only once made.
	data:      []byte,
	shape:     Shape,
	cap:       int, // messages
	_pad0:     [LINE]u8,
	// The producer's line.
	tail:      int,
	head_seen: int,
	pushed:    int,
	_pad1:     [LINE]u8,
	// The consumer's line.
	head:      int,
	tail_seen: int,
	popped:    int,
	_pad2:     [LINE]u8,
}

// Make a ring of `cap` messages of `shape`, in `allocator`, with the storage
// aligned as the shape asks.
init :: proc(r: ^Raw, cap: int, shape: Shape, allocator: mem.Allocator) {
	r^ = {}
	r.cap = cap
	r.shape = shape
	r.data, _ = mem.make_aligned([]byte, cap * shape.size, max(shape.align, 1), allocator)
}

destroy :: proc(r: ^Raw, allocator: mem.Allocator) {
	delete(r.data, allocator)
	r^ = {}
}

// Exact, from either side.
len :: proc(r: ^Raw) -> int {
	return sync.atomic_load(&r.tail) - sync.atomic_load(&r.head)
}

// Producer side.
full :: proc(r: ^Raw) -> bool {
	if r.tail - r.head_seen == r.cap {
		r.head_seen = sync.atomic_load(&r.head)
	}
	return r.tail - r.head_seen == r.cap
}

// Consumer side: at least one message waits.
has :: proc(r: ^Raw) -> bool {
	if r.tail_seen == r.head {
		r.tail_seen = sync.atomic_load(&r.tail)
	}
	return r.tail_seen != r.head
}

// Producer side. False when full.
push :: proc(r: ^Raw, msg: rawptr) -> bool {
	if full(r) {
		return false
	}
	tail := r.tail
	if r.shape.size > 0 {
		mem.copy(&r.data[(tail % r.cap) * r.shape.size], msg, r.shape.size)
	}
	sync.atomic_store(&r.tail, tail + 1)
	r.pushed += 1
	return true
}

// Consumer side. False when empty.
pop :: proc(r: ^Raw, out: rawptr) -> bool {
	if !has(r) {
		return false
	}
	head := r.head
	if r.shape.size > 0 {
		mem.copy(out, &r.data[(head % r.cap) * r.shape.size], r.shape.size)
	}
	sync.atomic_store(&r.head, head + 1)
	r.popped += 1
	return true
}

// Ring is Raw for one message type.
Ring :: struct($T: typeid) {
	using raw: Raw,
}

make_ring :: proc($T: typeid, cap: int, allocator: mem.Allocator) -> (r: Ring(T)) {
	init(&r.raw, cap, shape_of(T), allocator)
	return
}

destroy_ring :: proc(r: ^Ring($T), allocator: mem.Allocator) {
	destroy(&r.raw, allocator)
}

push_value :: proc(r: ^Ring($T), v: T) -> bool {
	v := v
	return push(&r.raw, &v)
}

pop_value :: proc(r: ^Ring($T)) -> (v: T, ok: bool) {
	ok = pop(&r.raw, &v)
	return
}
