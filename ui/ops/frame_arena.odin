package ops

import "core:mem"
// Used only when POISON_FRAMES is off.
@(require) import "core:mem/virtual"

import jdebug "jm:debug"

// POISON_FRAMES makes Frame_Arena a jm:debug Arena, which poisons a frame's
// memory when it is reset, in debug and test builds by default
// (-define:JM_UI_POISON=false turns it off). Frame memory kept past its
// frame, such as a fmt.tprintf string stored in the model, then reads as
// 0xDD bytes, invalid UTF-8 that draws as tofu, every time, rather than as
// whatever the next frame happened to write there; under -sanitize:address
// the read traps where it happens (test_frame_memory_kept_past_its_frame_reads_as_poison
// checks the poison).
POISON_FRAMES :: #config(JM_UI_POISON, ODIN_DEBUG || ODIN_TEST)

// FRAME_POISON is the byte a reset frame's memory is filled with: jm:debug's
// dead-memory pattern.
FRAME_POISON :: jdebug.PATTERN_DEAD

// Frame_Arena is the arena behind Ctx.allocator: a growing virtual arena
// reset at the start of each frame that uses it.
when POISON_FRAMES {
	Frame_Arena :: struct {
		arena: jdebug.Arena,
	}
} else {
	Frame_Arena :: struct {
		arena: virtual.Arena,
	}
}

// frame_arena_init prepares a.
frame_arena_init :: proc(a: ^Frame_Arena) -> mem.Allocator_Error {
	when POISON_FRAMES {
		return jdebug.arena_init(&a.arena, "frame")
	} else {
		return virtual.arena_init_growing(&a.arena)
	}
}

// frame_arena_destroy frees all a holds.
frame_arena_destroy :: proc(a: ^Frame_Arena) {
	when POISON_FRAMES {
		jdebug.arena_destroy(&a.arena)
	} else {
		virtual.arena_destroy(&a.arena)
	}
}

// frame_arena_allocator is a's allocator.
frame_arena_allocator :: proc(a: ^Frame_Arena) -> mem.Allocator {
	when POISON_FRAMES {
		return jdebug.arena_allocator(&a.arena)
	} else {
		return virtual.arena_allocator(&a.arena)
	}
}

// frame_arena_reset frees everything allocated from a since the last
// reset; under POISON_FRAMES the memory kept for reuse is poisoned.
frame_arena_reset :: proc(a: ^Frame_Arena) {
	when POISON_FRAMES {
		jdebug.arena_reset(&a.arena)
	} else {
		virtual.arena_free_all(&a.arena)
	}
}

// frame_arena_used is the bytes a has handed out since its last reset.
frame_arena_used :: proc(a: ^Frame_Arena) -> int {
	when POISON_FRAMES {
		return jdebug.arena_used(&a.arena)
	} else {
		return int(a.arena.total_used)
	}
}

// frame_arena_reserved is the address space a has reserved.
frame_arena_reserved :: proc(a: ^Frame_Arena) -> int {
	when POISON_FRAMES {
		return int(a.arena.virt.total_reserved)
	} else {
		return int(a.arena.total_reserved)
	}
}
