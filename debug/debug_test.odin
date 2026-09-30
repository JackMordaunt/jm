package debug

import "base:runtime"
import "base:sanitizer"
import "core:mem"
import "core:testing"

@(private = "file")
setup :: proc(da: ^Allocator) {
	init(da, context.allocator)
}

@(private = "file")
kinds :: proc(da: ^Allocator) -> (out: bit_set[Issue_Kind]) {
	for iss in da.issues {
		out += {iss.kind}
	}
	return
}

@(test)
test_expect_released_passes_when_a_scope_frees_what_it_allocates :: proc(t: ^testing.T) {
	da: Allocator
	setup(&da)
	defer destroy(&da)
	kept := make([]int, 4, allocator(&da)) // before the snapshot: not the scope's
	defer delete(kept, allocator(&da))

	s := snapshot(&da)
	tmp := make([]int, 8, allocator(&da))
	delete(tmp, allocator(&da))
	testing.expect(t, expect_released(&da, s))
	testing.expect_value(t, issue_count(&da), 0)
}

@(test)
test_expect_released_reports_a_block_the_scope_kept :: proc(t: ^testing.T) {
	da: Allocator
	setup(&da)
	defer destroy(&da)

	s := snapshot(&da)
	leaked := make([]int, 8, allocator(&da))
	testing.expect(t, !expect_released(&da, s))
	testing.expect_value(t, kinds(&da), bit_set[Issue_Kind]{.Scope_Leak})
	iss := da.issues[0]
	testing.expect_value(t, iss.blocks, 1)
	testing.expect_value(t, iss.size, 8 * size_of(int))
	testing.expect_value(t, iss.ptr, rawptr(raw_data(leaked)))
	delete(leaked, allocator(&da))
}

@(private = "file")
Pair :: struct {
	a, b: []byte,
}

// Allocates two blocks; when the second fails, frees the first only if careful.
@(private = "file")
make_pair :: proc(careful: bool, allocator: mem.Allocator) -> (p: Pair, err: mem.Allocator_Error) {
	p.a = make([]byte, 16, allocator) or_return
	p.b, err = make([]byte, 32, allocator)
	if err != nil {
		if careful {
			delete(p.a, allocator)
		}
		return {}, err
	}
	return
}

@(private = "file")
Sweep_Case :: struct {
	da:      ^Allocator,
	careful: bool,
}

@(private = "file")
sweep_body :: proc(data: rawptr) {
	c := (^Sweep_Case)(data)
	al := allocator(c.da)
	p, err := make_pair(c.careful, al)
	if err == nil {
		delete(p.a, al)
		delete(p.b, al)
	}
}

@(test)
test_sweep_failures_passes_an_error_path_that_cleans_up :: proc(t: ^testing.T) {
	da: Allocator
	setup(&da)
	defer destroy(&da)
	c := Sweep_Case{&da, true}
	runs, ok := sweep_failures(&da, sweep_body, &c)
	testing.expect(t, ok)
	testing.expect_value(t, runs, 2)
	testing.expect_value(t, issue_count(&da), 0)
}

@(test)
test_sweep_failures_names_the_failure_whose_path_leaks :: proc(t: ^testing.T) {
	da: Allocator
	setup(&da)
	defer destroy(&da)
	c := Sweep_Case{&da, false}
	runs, ok := sweep_failures(&da, sweep_body, &c)
	testing.expect(t, !ok)
	testing.expect_value(t, runs, 2)
	testing.expect_value(t, issue_count(&da), 1)
	iss := da.issues[0]
	testing.expect_value(t, iss.kind, Issue_Kind.Scope_Leak)
	testing.expect(t, iss.has_injected)
	testing.expect_value(t, iss.size, 16) // p.a, left behind when p.b failed
	// The leak is real: release it so destroy is not the only thing that does.
	for ptr in da.live {
		free(ptr, allocator(&da))
	}
}

@(test)
test_fail_at_fails_exactly_the_nth_allocation :: proc(t: ^testing.T) {
	da: Allocator
	setup(&da)
	defer destroy(&da)
	al := allocator(&da)
	fail_at(&da, 2)
	a, err_a := make([]byte, 8, al)
	b, err_b := make([]byte, 8, al)
	c, err_c := make([]byte, 8, al)
	testing.expect_value(t, err_a, nil)
	testing.expect_value(t, err_b, mem.Allocator_Error.Out_Of_Memory)
	testing.expect_value(t, err_c, nil)
	testing.expect(t, b == nil)
	delete(a, al)
	delete(c, al)
}

@(test)
test_forbid_alloc_reports_an_allocation_inside_it_only :: proc(t: ^testing.T) {
	da: Allocator
	setup(&da)
	defer destroy(&da)
	al := allocator(&da)
	before := make([]byte, 8, al)
	{
		forbid_alloc(&da)
		delete(before, al) // a free is not an allocation
		inside := make([]byte, 8, al)
		delete(inside, al)
	}
	after := make([]byte, 8, al)
	delete(after, al)
	testing.expect_value(t, issue_count(&da), 1)
	testing.expect_value(t, da.issues[0].kind, Issue_Kind.Forbidden_Alloc)
	testing.expect_value(t, da.no_alloc, 0)
}

@(test)
test_arena_reset_poisons_what_it_handed_out :: proc(t: ^testing.T) {
	da: Allocator
	setup(&da)
	defer destroy(&da)
	a: Arena
	testing.expect_value(t, arena_init(&a, "frame", &da), nil)
	defer arena_destroy(&a)
	al := arena_allocator(&a)

	kept := make([]byte, 64, al)
	for &b in kept {
		b = 'x'
	}
	arena_reset(&a)
	testing.expect_value(t, a.resets, 1)
	if ASAN {
		// Reading it would trap, which is the point.
		testing.expect(t, sanitizer.address_is_poisoned(raw_data(kept)))
	} else {
		for b in kept {
			testing.expect_value(t, b, u8(PATTERN_DEAD))
		}
	}

	// The same memory comes back zeroed, and addressable.
	again := make([]byte, 64, al)
	testing.expect_value(t, raw_data(again), raw_data(kept))
	for b in again {
		testing.expect_value(t, b, 0)
	}
	testing.expect_value(t, issue_count(&da), 0)
}

@(test)
test_arena_growth_warns_once_past_the_threshold :: proc(t: ^testing.T) {
	da: Allocator
	setup(&da)
	defer destroy(&da)
	a: Arena
	testing.expect_value(t, arena_init(&a, "loop", &da, warn_bytes = 1024), nil)
	defer arena_destroy(&a)
	al := arena_allocator(&a)
	for _ in 0 ..< 64 {
		_ = make([]byte, 100, al)
	}
	testing.expect_value(t, issue_count(&da), 1)
	iss := da.issues[0]
	testing.expect_value(t, iss.kind, Issue_Kind.Arena_Growth)
	testing.expect_value(t, iss.arena, "loop")
	testing.expect(t, iss.size > 1024)
}

@(test)
test_arena_allocation_inside_forbid_alloc_is_reported :: proc(t: ^testing.T) {
	da: Allocator
	setup(&da)
	defer destroy(&da)
	a: Arena
	testing.expect_value(t, arena_init(&a, "frame", &da), nil)
	defer arena_destroy(&a)
	{
		forbid_alloc(&da)
		_ = make([]byte, 8, arena_allocator(&a))
	}
	testing.expect_value(t, kinds(&da), bit_set[Issue_Kind]{.Forbidden_Alloc})
	testing.expect_value(t, da.issues[0].arena, "frame")
}

@(test)
test_temp_wrapper_keeps_the_temp_guard_working :: proc(t: ^testing.T) {
	da: Allocator
	setup(&da)
	defer destroy(&da)
	a: Arena
	temp, ok := temp_init(&a, &da)
	if !testing.expect(t, ok, "temp_init refused the thread's temp allocator") {
		return
	}
	defer temp_destroy(&a)
	context.temp_allocator = temp
	free_all(context.temp_allocator)

	outer := make([]byte, 32, context.temp_allocator)
	used := a.temp.total_used
	{
		runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
		_ = make([]byte, 4096, context.temp_allocator)
		testing.expect(t, a.temp.total_used > used)
	}
	testing.expect_value(t, a.temp.total_used, used)

	for &b in outer {
		b = 'x'
	}
	free_all(context.temp_allocator)
	testing.expect_value(t, a.resets, 2)
	if ASAN {
		testing.expect(t, sanitizer.address_is_poisoned(raw_data(outer)))
	} else {
		for b in outer {
			testing.expect_value(t, b, u8(PATTERN_DEAD))
		}
	}
	fresh := make([]byte, 32, context.temp_allocator)
	for b in fresh {
		testing.expect_value(t, b, 0)
	}
	testing.expect_value(t, issue_count(&da), 0)
}
