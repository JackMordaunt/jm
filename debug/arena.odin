package debug

/*
Arena: an arena whose freed memory is poisoned, so a pointer kept past a reset reads
as garbage instead of whatever the next user wrote there.

An arena frees nothing one block at a time; everything it handed out dies together
at a reset (free_all). The debug allocator never sees those deaths, because the
arena's memory comes from blocks it holds for its whole life. This wrapper makes
them visible:

  - At a reset the memory kept for reuse is filled with 0xDD, the pattern the debug
    allocator uses for freed blocks, so a string kept past its frame reads as 0xDD
    bytes every time.
  - With -sanitize:address everything in the arena past the bytes it has handed
    out is poisoned: memory a reset released, and memory not yet handed out. A read
    or write there traps at the instruction, and the death callback names the arena
    and where it was last reset.
  - Allocations are zeroed (or filled with 0xCD when non-zeroed) by the wrapper,
    since the arena would otherwise hand the poison straight back out.
  - Past warn_bytes in use the arena raises ARENA_GROWTH once: something allocates
    from it in a loop without resetting, which never shows up as a leak.
  - Inside a forbid_alloc scope an allocation from the arena is FORBIDDEN_ALLOC, like
    one from the debug allocator.

Two kinds:

	a: debug.Arena
	debug.arena_init(&a, "frame", &da)  // owns a growing virtual arena
	context.allocator = debug.arena_allocator(&a)
	debug.arena_reset(&a)               // or free_all(debug.arena_allocator(&a))
	debug.arena_destroy(&a)

	t: debug.Arena
	context.temp_allocator = debug.temp_init(&t, &da)  // wraps this thread's temp allocator
	defer debug.temp_destroy(&t)

The temp wrapper keeps the runtime's default temp arena and only swaps the allocator
procedure, so runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD still works: its begin
checks only the data pointer (base/runtime/default_temporary_allocator.odin, Odin
dev-2026-09), and test_temp_wrapper_keeps_the_temp_guard_working holds it to that. The
guard's end rewinds the arena without going through the wrapper: memory it releases
reads as zero rather than 0xDD, and is poisoned again at the next allocation.

The debug allocator passed in is optional. Without one the arena still poisons, but
ASan reports cannot name it and growth prints a plain warning. An Arena that names a
debug allocator must not move after init, and must be destroyed before that allocator.
*/

import "base:runtime"
import "base:sanitizer"
import "core:fmt"
import "core:mem"
import "core:mem/virtual"
import "core:sync"

// Bytes in use past which an arena raises ARENA_GROWTH; 0 turns the check off.
ARENA_GROWTH_WARN :: #config(DEBUG_ALLOC_ARENA_WARN, 64 * 1024 * 1024)

Arena_Kind :: enum {
	Virtual, // owns a growing core:mem/virtual arena
	Temp, // wraps the calling thread's runtime default temp arena
}

Arena :: struct {
	name:       string,
	kind:       Arena_Kind,
	virt:       virtual.Arena,
	temp:       ^runtime.Arena,
	temp_inner: mem.Allocator, // Temp: the runtime's temp allocator
	da:         ^Allocator,
	warn_bytes: int,
	warned:     bool,
	peak:       int,
	resets:     int,
	last_reset: Site,
	// The block whose unused tail is poisoned, its limit then, and how far into it
	// the poison starts. A change of block or limit re-poisons the whole tail.
	tail_block: rawptr,
	tail_limit: uint,
	tail_used:  uint,
	mutex:      sync.Mutex,
}

// Prepare a to own a growing virtual arena. da may be nil; see the package notes.
// Pass a string literal for name.
arena_init :: proc(
	a: ^Arena,
	name: string,
	da: ^Allocator = nil,
	warn_bytes := ARENA_GROWTH_WARN,
) -> mem.Allocator_Error {
	a^ = {}
	virtual.arena_init_growing(&a.virt) or_return
	a.name = name
	a.kind = .Virtual
	a.warn_bytes = warn_bytes
	register(a, da)
	return nil
}

// Free all a holds.
arena_destroy :: proc(a: ^Arena) {
	unregister(a)
	sync.guard(&a.mutex)
	unpoison_all(a)
	virtual.arena_destroy(&a.virt)
}

arena_allocator :: proc(a: ^Arena) -> mem.Allocator {
	return {procedure = arena_proc, data = a}
}

// Free everything allocated from a; the memory kept for reuse is poisoned.
arena_reset :: proc(a: ^Arena, loc := #caller_location) {
	sync.guard(&a.mutex)
	reset(a, loc)
}

/*
Wrap the calling thread's default temp allocator and return the allocator to put in
context.temp_allocator. ok is false, and the allocator is returned unchanged, when
the current temp allocator is not the runtime default.
*/
temp_init :: proc(
	a: ^Arena,
	da: ^Allocator = nil,
	warn_bytes := ARENA_GROWTH_WARN,
) -> (
	temp: mem.Allocator,
	ok: bool,
) {
	t := context.temp_allocator
	when runtime.NO_DEFAULT_TEMP_ALLOCATOR {
		return t, false
	} else {
		if t.procedure != runtime.default_temp_allocator_proc {
			return t, false
		}
		a^ = {}
		a.name = "temp"
		a.kind = .Temp
		a.temp_inner = t
		a.temp = &(^runtime.Default_Temp_Allocator)(t.data).arena
		a.warn_bytes = warn_bytes
		thread_temp = a
		register(a, da)
		sync.guard(&a.mutex)
		poison_tail(a, nil, 0)
		// The data pointer stays the runtime's, which is what the temp guard checks.
		return {procedure = temp_proc, data = t.data}, true
	}
}

// Stop wrapping; the runtime's temp arena carries on, clean, under its own procedure.
temp_destroy :: proc(a: ^Arena) {
	unregister(a)
	sync.guard(&a.mutex)
	unpoison_all(a)
	// The runtime hands out its arena's memory unzeroed, trusting it to be zero:
	// arena_alloc in base/runtime/default_temp_allocator_arena.odin (Odin
	// dev-2026-09) never clears what it returns.
	if b := curr(a); b != nil {
		base, used, limit, _ := view(a, b)
		mem.zero(base[used:], int(limit - used))
	}
	if thread_temp == a {
		thread_temp = nil
	}
}

// ---- allocator ------------------------------------------------------------------

@(private, thread_local)
thread_temp: ^Arena

@(private)
temp_proc :: proc(
	data: rawptr,
	mode: mem.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc := #caller_location,
) -> (
	[]byte,
	mem.Allocator_Error,
) {
	a := thread_temp
	if a == nil || a.temp_inner.data != data {
		// Another thread's context, copied: its arena is not the one wrapped here.
		return runtime.default_temp_allocator_proc(
			data,
			mode,
			size,
			alignment,
			old_memory,
			old_size,
			loc,
		)
	}
	return arena_proc(a, mode, size, alignment, old_memory, old_size, loc)
}

@(private)
arena_proc :: proc(
	data: rawptr,
	mode: mem.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc := #caller_location,
) -> (
	[]byte,
	mem.Allocator_Error,
) {
	a := (^Arena)(data)
	sync.guard(&a.mutex)
	switch mode {
	case .Free_All:
		reset(a, loc)
		return nil, nil
	case .Alloc, .Alloc_Non_Zeroed, .Resize, .Resize_Non_Zeroed:
		return grow(a, mode, size, alignment, old_memory, old_size, loc)
	case .Free, .Query_Features, .Query_Info:
		wrapped := inner(a)
		return wrapped.procedure(wrapped.data, mode, size, alignment, old_memory, old_size, loc)
	}
	return nil, .Mode_Not_Implemented
}

@(private)
grow :: proc(
	a: ^Arena,
	mode: mem.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc: runtime.Source_Code_Location,
) -> (
	out: []byte,
	err: mem.Allocator_Error,
) {
	if a.da != nil && size > 0 {
		forbid(a, size, loc)
	}
	// The arena writes into the bytes it hands out, and a resize copies into them,
	// before this wrapper sees the result: lift the poison from as far as this
	// request can reach. A request that needs a new block gets fresh memory.
	b := curr(a)
	reach: uint
	if b != nil {
		base, used, limit, _ := view(a, b)
		reach = min(used + uint(max(size, 0)) + uint(max(alignment, 1)), limit)
		if reach > used {
			sanitizer.address_unpoison(base[used:reach])
		}
	}
	wrapped := inner(a)
	out, err = wrapped.procedure(wrapped.data, mode, size, alignment, old_memory, old_size, loc)
	poison_tail(a, b, reach)
	if err != nil || len(out) == 0 {
		return
	}
	fresh := out
	if mode == .Resize || mode == .Resize_Non_Zeroed {
		fresh = out[min(old_size, len(out)):]
	}
	if mode == .Alloc || mode == .Resize {
		mem.zero_slice(fresh)
	} else {
		mem.set(raw_data(fresh), PATTERN_FRESH, len(fresh))
	}
	watch_growth(a, loc)
	return
}

@(private)
reset :: proc(a: ^Arena, loc: runtime.Source_Code_Location) {
	// Blocks the reset releases must go back without poison, or whoever maps that
	// address next inherits it.
	unpoison_all(a)
	first := oldest(a)
	first_used: uint
	if first != nil {
		_, first_used, _, _ = view(a, first)
	}
	wrapped := inner(a)
	wrapped.procedure(wrapped.data, .Free_All, 0, 0, nil, 0, loc)
	// Both arena kinds keep their oldest block for reuse.
	if first != nil && curr(a) == first {
		base, _, limit, _ := view(a, first)
		mem.set(base, PATTERN_DEAD, int(first_used))
		sanitizer.address_poison(base[:limit])
		a.tail_block, a.tail_limit, a.tail_used = first, limit, 0
	} else {
		a.tail_block = nil
	}
	a.resets += 1
	a.last_reset = stamp(a, loc)
}

// Poison the current block from its used mark on. before and reach are the block
// that was current, and how far its poison was lifted, before the arena ran.
@(private)
poison_tail :: proc(a: ^Arena, before: rawptr, reach: uint) {
	if before != nil && before != curr(a) {
		base, used, _, _ := view(a, before)
		if reach > used {
			sanitizer.address_poison(base[used:reach])
		}
	}
	b := curr(a)
	if b == nil {
		a.tail_block = nil
		return
	}
	base, used, limit, _ := view(a, b)
	if b != a.tail_block || limit != a.tail_limit {
		sanitizer.address_poison(base[used:limit])
	} else {
		// A temp guard's end may have rewound used below the last mark.
		hi := a.tail_used
		if b == before {
			hi = max(hi, reach)
		}
		if hi > used {
			sanitizer.address_poison(base[used:hi])
		}
	}
	a.tail_block, a.tail_limit, a.tail_used = b, limit, used
}

@(private)
unpoison_all :: proc(a: ^Arena) {
	for b := curr(a); b != nil; {
		base, _, limit, prev := view(a, b)
		sanitizer.address_unpoison(base[:limit])
		b = prev
	}
	a.tail_block = nil
}

// ---- checks -------------------------------------------------------------------------

@(private)
forbid :: proc(a: ^Arena, size: int, loc: runtime.Source_Code_Location) {
	da := a.da
	context.allocator = da.internals
	sync.guard(&da.mutex)
	if da.no_alloc > 0 {
		raise(
			da,
			Issue {
				kind = .Forbidden_Alloc,
				size = size,
				op = make_site(da, loc),
				scope = da.no_alloc_at,
				arena = a.name,
				stage = "arena allocation",
			},
		)
	}
}

@(private)
watch_growth :: proc(a: ^Arena, loc: runtime.Source_Code_Location) {
	used := int(total_used(a))
	a.peak = max(a.peak, used)
	if a.warn_bytes <= 0 || a.warned || used <= a.warn_bytes {
		return
	}
	a.warned = true
	if a.da == nil {
		fmt.eprintfln(
			"!! ARENA_GROWTH: arena '%s' holds %d b, past its warning threshold of %d b, at %s:%d; it is only reclaimed at a reset, so something allocates from it in a loop without resetting",
			a.name,
			used,
			a.warn_bytes,
			loc.file_path,
			loc.line,
		)
		return
	}
	da := a.da
	context.allocator = da.internals
	sync.guard(&da.mutex)
	raise(
		da,
		Issue {
			kind = .Arena_Growth,
			size = used,
			limit = a.warn_bytes,
			arena = a.name,
			op = make_site(da, loc),
			stage = "arena allocation",
		},
	)
}

// ---- registration and block access --------------------------------------------------

@(private)
register :: proc(a: ^Arena, da: ^Allocator) {
	if da == nil {
		return
	}
	a.da = da
	context.allocator = da.internals
	sync.guard(&da.mutex)
	append(&da.arenas, a)
}

@(private)
unregister :: proc(a: ^Arena) {
	da := a.da
	if da == nil {
		return
	}
	sync.guard(&da.mutex)
	for x, i in da.arenas {
		if x == a {
			unordered_remove(&da.arenas, i)
			break
		}
	}
	a.da = nil
}

@(private)
stamp :: proc(a: ^Arena, loc: runtime.Source_Code_Location) -> Site {
	if a.da == nil {
		return Site{loc = loc}
	}
	sync.guard(&a.da.mutex)
	return make_site(a.da, loc)
}

@(private)
curr :: proc(a: ^Arena) -> rawptr {
	switch a.kind {
	case .Virtual:
		return a.virt.curr_block
	case .Temp:
		return a.temp.curr_block
	}
	return nil
}

@(private)
oldest :: proc(a: ^Arena) -> rawptr {
	b := curr(a)
	for b != nil {
		_, _, _, prev := view(a, b)
		if prev == nil {
			break
		}
		b = prev
	}
	return b
}

@(private)
total_used :: proc(a: ^Arena) -> uint {
	switch a.kind {
	case .Virtual:
		return a.virt.total_used
	case .Temp:
		return a.temp.total_used
	}
	return 0
}

// A block's memory, bytes handed out, bytes it can hand out without asking the OS
// or the backing allocator for more, and the block before it.
@(private)
view :: proc(a: ^Arena, b: rawptr) -> (base: [^]byte, used, limit: uint, prev: rawptr) {
	switch a.kind {
	case .Virtual:
		v := (^virtual.Memory_Block)(b)
		return v.base, v.used, v.committed, v.prev
	case .Temp:
		t := (^runtime.Memory_Block)(b)
		return t.base, t.used, t.capacity, t.prev
	}
	return
}

// The allocator a wraps. Built on each call so a Virtual arena holds no pointer to
// itself and can move while no debug allocator names it.
@(private)
inner :: proc(a: ^Arena) -> mem.Allocator {
	if a.kind == .Temp {
		return a.temp_inner
	}
	return virtual.arena_allocator(&a.virt)
}

// Bytes a has handed out since its last reset.
arena_used :: proc(a: ^Arena) -> int {
	sync.guard(&a.mutex)
	return int(total_used(a))
}
