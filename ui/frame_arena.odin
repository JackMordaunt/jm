package ui

import "core:mem"
import "core:mem/virtual"

import jdebug "jm:debug"

// POISON_FRAMES makes Frame_Arena overwrite a frame's memory when it is
// reset, in debug builds by default (-define:JM_UI_POISON=false turns it
// off). Frame memory kept past its frame, such as a fmt.tprintf string
// stored in the model, then reads as 0xDD bytes, invalid UTF-8 that draws
// as tofu, every time, rather than as whatever the next frame happened to
// write there.
POISON_FRAMES :: #config(JM_UI_POISON, ODIN_DEBUG)

// FRAME_POISON is the byte a reset frame's memory is filled with: jm:debug's
// dead-memory pattern, so the two read alike in a debugger.
FRAME_POISON :: jdebug.PATTERN_DEAD

// Frame_Arena is the arena behind Ctx.allocator: a growing virtual arena
// reset at the start of each frame that uses it.
Frame_Arena :: struct {
	arena: virtual.Arena,
}

// frame_arena_init prepares a.
frame_arena_init :: proc(a: ^Frame_Arena) -> mem.Allocator_Error {
	return virtual.arena_init_growing(&a.arena)
}

// frame_arena_destroy frees all a holds.
frame_arena_destroy :: proc(a: ^Frame_Arena) {
	virtual.arena_destroy(&a.arena)
}

// frame_arena_allocator is a's allocator. Under POISON_FRAMES it zeroes
// every allocation itself, since the memory a reset poisoned is handed out
// again and callers of make expect zeroes.
frame_arena_allocator :: proc(a: ^Frame_Arena) -> mem.Allocator {
	when POISON_FRAMES {
		return {procedure = poisoned_allocator_proc, data = a}
	} else {
		return virtual.arena_allocator(&a.arena)
	}
}

// frame_arena_reset frees everything allocated from a since the last
// reset; under POISON_FRAMES the memory kept for reuse is filled with
// FRAME_POISON first.
frame_arena_reset :: proc(a: ^Frame_Arena) {
	when POISON_FRAMES {
		// arena_free_all keeps the oldest block, zeroed, and unmaps the rest
		// (core/mem/virtual/arena.odin, Odin dev-2026-09);
		// note how much of it was used, then poison that after.
		first := a.arena.curr_block
		for first != nil && first.prev != nil {
			first = first.prev
		}
		used := first != nil ? first.used : 0
		virtual.arena_free_all(&a.arena)
		if first != nil {
			mem.set(first.base, FRAME_POISON, int(used))
		}
	} else {
		virtual.arena_free_all(&a.arena)
	}
}

@(private = "file")
poisoned_allocator_proc :: proc(
	data: rawptr,
	mode: mem.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc := #caller_location,
) -> ([]byte, mem.Allocator_Error) {
	a := (^Frame_Arena)(data)
	inner := virtual.arena_allocator(&a.arena)
	out, err := inner.procedure(inner.data, mode, size, alignment, old_memory, old_size, loc)
	if err != nil {
		return out, err
	}
	#partial switch mode {
	case .Alloc:
		mem.zero_slice(out)
	case .Resize:
		if len(out) > old_size {
			mem.zero_slice(out[old_size:])
		}
	}
	return out, err
}
