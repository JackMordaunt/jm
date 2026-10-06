package stream

// One test per operator, on what the operator alone promises. The pipeline
// tests in stream_test.odin cover the runtime; these cover the dictionary.

import "core:mem"
import "core:sync"
import "core:testing"
import "core:thread"
import "core:time"

import "jm:stream/ring"

@(private = "file")
ints :: proc(p: ^Pipeline, items: []int) -> Stream(int) {
	return from_slice(p, items)
}

@(private = "file")
expect_ints :: proc(t: ^testing.T, got: []int, want: []int, loc := #caller_location) {
	testing.expect_value(t, len(got), len(want), loc = loc)
	for v, ii in want {
		if ii < len(got) {
			testing.expect_value(t, got[ii], v, loc = loc)
		}
	}
}

// --- sources ---------------------------------------------------------------

@(test)
op_from_slice_empty_ends_at_once :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator)
	defer destroy(p)
	got := make([dynamic]int)
	defer delete(got)
	collect(ints(p, {}), &got)
	run(p)
	testing.expect_value(t, len(got), 0)
	testing.expect(t, finished(p))
}

@(test)
op_from_slice_keeps_order_past_the_budget :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator, cap = 2)
	defer destroy(p)
	items: [3 * BUDGET + 1]int
	for &x, ii in items {
		x = ii
	}
	got := make([dynamic]int)
	defer delete(got)
	collect(ints(p, items[:]), &got)
	run(p)
	testing.expect_value(t, len(got), len(items))
	expect_ints(t, got[:], items[:])
}

Countdown :: struct {
	n: int,
}

count_down :: proc(c: ^Countdown) -> (int, bool) {
	if c.n == 0 {
		return 0, false
	}
	c.n -= 1
	return c.n, true
}

@(test)
op_generate_ends_when_next_says :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator)
	defer destroy(p)
	got := make([dynamic]int)
	defer delete(got)
	c := Countdown{3}
	collect(generate(p, &c, count_down), &got)
	run(p)
	expect_ints(t, got[:], {2, 1, 0})
	testing.expect(t, finished(p))
}

@(test)
op_generate_with_nothing_to_give :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator)
	defer destroy(p)
	got := make([dynamic]int)
	defer delete(got)
	c := Countdown{0}
	collect(generate(p, &c, count_down), &got)
	run(p)
	testing.expect_value(t, len(got), 0)
	testing.expect(t, finished(p))
}

// --- one in, one out -------------------------------------------------------

@(test)
op_transform_stateless :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator)
	defer destroy(p)
	got := make([dynamic]int)
	defer delete(got)
	collect(transform(ints(p, {1, 2, 3}), proc(x: int) -> int {return x * x}), &got)
	run(p)
	testing.expect_value(t, len(got), 3)
	expect_ints(t, got[:], {1, 4, 9})
}

@(test)
op_transform_changes_type :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator)
	defer destroy(p)
	got := make([dynamic]string)
	defer delete(got)
	collect(transform(ints(p, {1, 2}), proc(x: int) -> string {return x == 1 ? "one" : "two"}), &got)
	run(p)
	testing.expect_value(t, len(got), 2)
	testing.expect_value(t, got[0], "one")
	testing.expect_value(t, got[1], "two")
}

@(test)
op_transform_stateful_sees_every_item_in_order :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator)
	defer destroy(p)
	got := make([dynamic]int)
	defer delete(got)
	prev := Sum{-1}
	collect(transform(ints(p, {5, 6, 7}), &prev, proc(st: ^Sum, x: int) -> int {
		d := x - st.total
		st.total = x
		return d
	}), &got)
	run(p)
	testing.expect_value(t, len(got), 3)
	expect_ints(t, got[:], {6, 1, 1})
}

@(test)
op_filter_keeps_none_and_all :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator)
	defer destroy(p)
	none := make([dynamic]int)
	all := make([dynamic]int)
	defer delete(none)
	defer delete(all)
	s := ints(p, {1, 2, 3})
	collect(filter(s, proc(x: int) -> bool {return false}), &none)
	collect(filter(s, proc(x: int) -> bool {return true}), &all)
	run(p)
	testing.expect_value(t, len(none), 0)
	expect_ints(t, all[:], {1, 2, 3})
	testing.expect(t, finished(p))
}

@(test)
op_filter_stateful_drops_a_prefix :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator)
	defer destroy(p)
	got := make([dynamic]int)
	defer delete(got)
	seen := Sum{}
	collect(filter(ints(p, {9, 9, 9, 1, 2}), &seen, proc(st: ^Sum, x: int) -> bool {
		st.total += 1
		return st.total > 3
	}), &got)
	run(p)
	testing.expect_value(t, len(got), 2)
	expect_ints(t, got[:], {1, 2})
}

Repeat :: struct {
	buf: [4]int,
}

repeat_n :: proc(r: ^Repeat, x: int) -> []int {
	for ii in 0 ..< x {
		r.buf[ii] = x
	}
	return r.buf[:x]
}

@(test)
op_flat_map_varies_per_item_and_allows_empty :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator, cap = 1)
	defer destroy(p)
	got := make([dynamic]int)
	defer delete(got)
	r: Repeat
	collect(flat_map(ints(p, {2, 0, 3, 1}), &r, repeat_n), &got)
	run(p)
	testing.expect_value(t, len(got), 6)
	expect_ints(t, got[:], {2, 2, 3, 3, 3, 1})
}

three := [3]int{7, 7, 7}

@(test)
op_flat_map_stateless :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator)
	defer destroy(p)
	got := make([dynamic]int)
	defer delete(got)
	collect(flat_map(ints(p, {0, 0}), proc(x: int) -> []int {return three[:]}), &got)
	run(p)
	testing.expect_value(t, len(got), 6)
	expect_ints(t, got[:], {7, 7, 7, 7, 7, 7})
}

@(test)
op_take_zero_more_and_exact :: proc(t: ^testing.T) {
	for want, ii in ([][]int{{}, {1, 2, 3}, {1, 2, 3}, {1, 2}}) {
		counts := []int{0, 5, 3, 2}
		p := make_pipeline(context.allocator)
		got := make([dynamic]int)
		src := ints(p, {1, 2, 3})
		collect(take(src, counts[ii]), &got)
		run(p)
		expect_ints(t, got[:], want)
		testing.expect(t, finished(p))
		testing.expect(t, node_of(src).done, "take must end its source")
		delete(got)
		destroy(p)
	}
}

@(test)
op_take_stops_an_endless_source_early :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator, cap = 4)
	defer destroy(p)
	got := make([dynamic]int)
	defer delete(got)
	c := Countdown{1 << 30}
	src := generate(p, &c, count_down)
	collect(take(src, 3), &got)
	run(p, 0) // one thread: the bound below assumes the source cannot run ahead
	testing.expect_value(t, len(got), 3)
	// The source filled at most its edge plus one run's budget before the
	// cancel reached it.
	testing.expect(t, (1 << 30) - c.n <= 3 + 4 + BUDGET)
}

// --- many in ---------------------------------------------------------------

@(test)
op_zip_equal_lengths_and_types :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator)
	defer destroy(p)
	got := make([dynamic]Pair(int, string))
	defer delete(got)
	collect(zip(ints(p, {1, 2}), from_slice(p, []string{"a", "b"})), &got)
	run(p)
	testing.expect_value(t, len(got), 2)
	testing.expect_value(t, got[0].first, 1)
	testing.expect_value(t, got[0].second, "a")
	testing.expect_value(t, got[1].first, 2)
	testing.expect_value(t, got[1].second, "b")
}

@(test)
op_zip_with_an_empty_side_ends_the_other :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator)
	defer destroy(p)
	got := make([dynamic]Pair(int, int))
	defer delete(got)
	long := ints(p, {1, 2, 3, 4})
	collect(zip(long, ints(p, {})), &got)
	run(p)
	testing.expect_value(t, len(got), 0)
	testing.expect(t, node_of(long).done, "zip must cancel the longer side")
	testing.expect(t, finished(p))
}

@(test)
op_merge_one_and_many :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator)
	defer destroy(p)
	one := make([dynamic]int)
	many := make([dynamic]int)
	defer delete(one)
	defer delete(many)
	collect(merge([]Stream(int){ints(p, {1, 2})}), &one)
	collect(merge([]Stream(int){ints(p, {1}), ints(p, {}), ints(p, {2, 3})}), &many)
	run(p)
	expect_ints(t, one[:], {1, 2})
	sum := 0
	for v in many {
		sum += v
	}
	testing.expect_value(t, len(many), 3)
	testing.expect_value(t, sum, 6)
	testing.expect(t, finished(p))
}

@(test)
op_merge_is_fair_per_batch :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator, cap = 8)
	defer destroy(p)
	got := make([dynamic]int)
	defer delete(got)
	a: [200]int
	b: [200]int
	for ii in 0 ..< 200 {
		a[ii] = 1
		b[ii] = 2
	}
	collect(merge([]Stream(int){ints(p, a[:]), ints(p, b[:])}), &got)
	run(p, 0)
	testing.expect_value(t, len(got), 400)
	// Merge drains the input it is on, then moves to the next, so within
	// the first two edge-fulls both inputs have been served.
	ones, twos := 0, 0
	for v in got[:16] {
		if v == 1 {ones += 1} else {twos += 1}
	}
	testing.expect(t, ones > 0 && twos > 0, "neither input waits for the other to end")
}

// --- sinks -----------------------------------------------------------------

@(test)
op_for_each_both_forms :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator)
	defer destroy(p)
	sum: Sum
	for_each(ints(p, {1, 2, 3}), &sum, proc(st: ^Sum, x: int) {st.total += x})
	for_each(ints(p, {4}), proc(x: int) {})
	run(p)
	testing.expect_value(t, sum.total, 6)
	testing.expect(t, finished(p))
}

@(test)
op_collect_uses_the_callers_allocator :: proc(t: ^testing.T) {
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	p := make_pipeline(context.allocator)
	defer destroy(p)
	got := make([dynamic]int, mem.dynamic_arena_allocator(&arena))
	collect(ints(p, {1, 2, 3}), &got)
	run(p)
	testing.expect_value(t, len(got), 3)
	expect_ints(t, got[:], {1, 2, 3})
	testing.expect(t, got.allocator.data == &arena, "the sink grew in the caller's arena")
	testing.expect(t, arena.current_block != nil || len(arena.used_blocks) > 0, "the arena was used")
}

// --- port ------------------------------------------------------------------

@(test)
op_port_push_reports_full_and_closed :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator)
	defer destroy(p)
	got := make([dynamic]int)
	defer delete(got)
	s, port := port(p, int, cap = 2)
	collect(s, &got)
	testing.expect(t, port_push(port, 1))
	testing.expect(t, port_push(port, 2))
	testing.expect(t, !port_push(port, 3), "a full port refuses")
	drain(p)
	testing.expect(t, port_push(port, 3), "drained, it has room again")
	port_close(port)
	port_close(port) // idempotent
	testing.expect(t, !port_push(port, 4), "a closed port refuses")
	testing.expect(t, !port_send(port, 4), "and send says so too")
	run(p)
	expect_ints(t, got[:], {1, 2, 3})
	testing.expect(t, finished(p))
}

@(test)
op_port_send_waits_for_room :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator)
	defer destroy(p)
	got := make([dynamic]int)
	defer delete(got)
	s, port := port(p, int, cap = 1)
	collect(s, &got)
	feeder := Feeder{port, 20}
	th := thread.create_and_start_with_poly_data(&feeder, proc(f: ^Feeder) {
		for ii in 0 ..< f.count {
			port_send(f.port, ii)
		}
		port_close(f.port)
	})
	run(p)
	thread.join(th)
	thread.destroy(th)
	testing.expect_value(t, len(got), 20)
	for v, ii in got {
		testing.expect_value(t, v, ii)
	}
}

// --- clock -----------------------------------------------------------------

@(test)
op_interval_two_tickers_keep_their_own_time :: proc(t: ^testing.T) {
	clock := manual_clock()
	p := make_pipeline(context.allocator, clock = &clock)
	defer destroy(p)
	fast := make([dynamic]time.Duration)
	slow := make([dynamic]time.Duration)
	defer delete(fast)
	defer delete(slow)
	collect(take(interval(p, 2 * time.Millisecond), 4), &fast)
	collect(take(interval(p, 5 * time.Millisecond), 2), &slow)
	run(p) // both arm at t=0
	for _ in 0 ..< 10 {
		advance(&clock, time.Millisecond)
		run(p)
	}
	testing.expect_value(t, len(fast), 4)
	testing.expect_value(t, fast[3], 8 * time.Millisecond)
	testing.expect_value(t, len(slow), 2)
	testing.expect_value(t, slow[1], 10 * time.Millisecond)
	testing.expect(t, finished(p))
}

@(test)
op_interval_tick_waits_for_room_and_does_not_pile_up :: proc(t: ^testing.T) {
	clock := manual_clock()
	p := make_pipeline(context.allocator, cap = 1, clock = &clock)
	defer destroy(p)
	got := make([dynamic]Pair(time.Duration, int))
	defer delete(got)
	s, gate := port(p, int, cap = 4) // a consumer that only moves when poked
	collect(take(zip(interval(p, time.Millisecond), s), 2), &got)
	drain(p)
	advance(&clock, 10 * time.Millisecond)
	drain(p) // one tick sits in the full edge, the others are dropped
	testing.expect_value(t, len(got), 0)
	port_push(gate, 0)
	port_push(gate, 0)
	drain(p)
	testing.expect_value(t, len(got), 1)
	advance(&clock, time.Millisecond)
	drain(p)
	testing.expect_value(t, len(got), 2)
	testing.expect(t, finished(p))
}

@(test)
op_debounce_bursts_and_flush_on_end :: proc(t: ^testing.T) {
	clock := manual_clock()
	p := make_pipeline(context.allocator, clock = &clock)
	defer destroy(p)
	got := make([dynamic]int)
	defer delete(got)
	s, port := port(p, int)
	collect(debounce(s, 3 * time.Millisecond), &got)
	for v in ([]int{1, 2, 3}) {
		port_push(port, v)
		drain(p)
		advance(&clock, time.Millisecond)
		drain(p)
	}
	testing.expect(t, len(got) == 0, "a burst faster than quiet emits nothing yet")
	advance(&clock, 3 * time.Millisecond)
	drain(p)
	expect_ints(t, got[:], {3})
	port_push(port, 4)
	port_close(port)
	drain(p)
	expect_ints(t, got[:], {3, 4})
	testing.expect(t, finished(p))
}

@(test)
op_debounce_holds_a_due_value_until_there_is_room :: proc(t: ^testing.T) {
	clock := manual_clock()
	p := make_pipeline(context.allocator, cap = 1, clock = &clock)
	defer destroy(p)
	got := make([dynamic]Pair(int, int))
	defer delete(got)
	s, inp := port(p, int, cap = 4)
	gate_s, gate := port(p, int, cap = 4)
	collect(zip(debounce(s, time.Millisecond), gate_s), &got)
	port_push(inp, 1)
	drain(p)
	advance(&clock, 2 * time.Millisecond)
	drain(p)
	port_push(inp, 2)
	drain(p)
	advance(&clock, 2 * time.Millisecond)
	drain(p) // 1 sits in the full edge; 2 is due and waits in the node
	port_push(gate, 0)
	port_push(gate, 0)
	port_close(gate)
	port_close(inp)
	drain(p)
	testing.expect_value(t, len(got), 2)
	testing.expect_value(t, got[0].first, 1)
	testing.expect_value(t, got[1].first, 2)
}

// --- async -----------------------------------------------------------------

Call_Counter :: struct {
	calls: int, // atomic
}

count_double :: proc(counter: ^Call_Counter, x: int) -> int {
	sync.atomic_add(&counter.calls, 1)
	if x % 5 == 0 {
		time.sleep(100 * time.Microsecond)
	}
	return x * 2
}

@(test)
op_async_map_empty_and_serial :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator)
	defer destroy(p)
	w := workers_start(2, context.allocator)
	defer workers_stop(w)
	none := make([dynamic]int)
	serial := make([dynamic]int)
	defer delete(none)
	defer delete(serial)
	sh: Call_Counter
	collect(async_map(ints(p, {}), w, &sh, count_double), &none)
	collect(async_map(ints(p, {5, 1, 10, 2}), w, &sh, count_double, concurrency = 1, ordered = false), &serial)
	run(p)
	testing.expect_value(t, len(none), 0)
	expect_ints(t, serial[:], {10, 2, 20, 4})
	testing.expect_value(t, sync.atomic_load(&sh.calls), 4)
}

@(test)
op_async_map_cancelled_with_work_in_flight :: proc(t: ^testing.T) {
	for ordered in ([]bool{true, false}) {
		p := make_pipeline(context.allocator, cap = 4)
		w := workers_start(4, context.allocator)
		got := make([dynamic]int)
		items: [200]int
		for &x, ii in items {
			x = ii
		}
		sh: Call_Counter
		mapped := async_map(ints(p, items[:]), w, &sh, count_double, concurrency = 8, ordered = ordered)
		collect(take(mapped, 7), &got)
		run(p, 3)
		workers_stop(w)
		testing.expect(t, finished(p))
		testing.expect_value(t, len(got), 7)
		if ordered {
			expect_ints(t, got[:], {0, 2, 4, 6, 8, 10, 12})
		}
		calls := sync.atomic_load(&sh.calls)
		testing.expect(t, calls >= 7 && calls < 200, "the cancel reached the source long before the end")
		delete(got)
		destroy(p)
	}
}

@(test)
op_async_map_shares_state_across_workers :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator)
	defer destroy(p)
	w := workers_start(4, context.allocator)
	defer workers_stop(w)
	items: [300]int
	sh: Call_Counter
	for_each(async_map(ints(p, items[:]), w, &sh, count_double, concurrency = 16, ordered = false), proc(x: int) {})
	run(p, 2)
	testing.expect_value(t, sync.atomic_load(&sh.calls), 300)
}

// --- runtime pieces the operators lean on ----------------------------------

Blob :: struct {
	bytes: [200]u8,
	tag:   int,
}

@(test)
op_edges_carry_any_message_size :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator, cap = 3)
	defer destroy(p)
	nothing := make([dynamic]struct {})
	blobs := make([dynamic]Blob)
	bytes := make([dynamic]u8)
	defer delete(nothing)
	defer delete(blobs)
	defer delete(bytes)
	in_blobs: [10]Blob
	for &b, ii in in_blobs {
		b.tag = ii
		b.bytes[199] = u8(ii)
	}
	in_bytes: [10]u8
	for &b, ii in in_bytes {
		b = u8(ii)
	}
	collect(from_slice(p, []struct {}{{}, {}, {}, {}, {}, {}, {}}), &nothing)
	collect(from_slice(p, in_blobs[:]), &blobs)
	collect(from_slice(p, in_bytes[:]), &bytes)
	run(p)
	testing.expect_value(t, len(nothing), 7)
	testing.expect_value(t, len(blobs), 10)
	for b, ii in blobs {
		testing.expect_value(t, b.tag, ii)
		testing.expect_value(t, b.bytes[199], u8(ii))
	}
	testing.expect_value(t, len(bytes), 10)
	testing.expect_value(t, bytes[9], u8(9))
}

@(test)
op_arm_replaces_a_deadline_and_disarm_forgets_it :: proc(t: ^testing.T) {
	clock := manual_clock()
	p := make_pipeline(context.allocator, clock = &clock)
	defer destroy(p)
	n := add_node(p, "timer", lies_drained, struct {}{})
	add_inlet(p, n, ring.shape_of(int)) // so waiting with no deadline is legitimate
	arm(n, 5 * time.Millisecond)
	arm(n, 2 * time.Millisecond)
	testing.expect_value(t, armed_count(p), 1)
	advance(&clock, 2 * time.Millisecond)
	start(p)
	testing.expect(t, step(p), "the earlier deadline fired")
	testing.expect_value(t, n.runs, 1)
	testing.expect(t, !step(p), "the replaced one did not")
	arm(n, 3 * time.Millisecond)
	disarm(n)
	testing.expect_value(t, armed_count(p), 0)
	advance(&clock, 5 * time.Millisecond)
	testing.expect(t, !step(p), "disarmed, nothing fires")
	testing.expect(t, !fired(n))
}

// --- the build-time zip check ------------------------------------------------

// A zip under construction: waits, with its first input wired.
@(private = "file")
half_zip :: proc(p: ^Pipeline, first: Stream(int)) -> ^Node {
	z := add_node(p, "zip", lies_drained, struct {}{})
	z.waits = true
	connect(p, first.node, z, ring.shape_of(int))
	return z
}

@(test)
zip_check_allows_disjoint_sources_and_lockstep_paths :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator)
	defer destroy(p)
	a := ints(p, {1})
	b := ints(p, {2})
	z := half_zip(p, a)
	_, _, _, ok := shared_source(p, z, node_of(b))
	testing.expect(t, ok, "two sources")
	_, _, _, ok = shared_source(p, z, node_of(a))
	testing.expect(t, ok, "the same stream on both inputs stays in step")
	t2 := transform(transform(a, proc(x: int) -> int {return x}), proc(x: int) -> int {return x})
	_, _, _, ok = shared_source(p, z, node_of(t2))
	testing.expect(t, ok, "one-to-one stages stay in step")
	sh: Call_Counter
	w := workers_start(1, context.allocator)
	defer workers_stop(w)
	am := async_map(a, w, &sh, count_double, ordered = false)
	_, _, _, ok = shared_source(p, z, node_of(am))
	testing.expect(t, ok, "async_map keeps the count, in either order")
}

@(test)
zip_check_refuses_a_shared_source_across_a_rate_change :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator)
	defer destroy(p)
	a := ints(p, {1})
	z := half_zip(p, a)
	f := filter(a, proc(x: int) -> bool {return true})
	shared, blame, input, ok := shared_source(p, z, node_of(f))
	testing.expect(t, !ok)
	testing.expect_value(t, shared, node_of(a))
	testing.expect_value(t, blame, node_of(f))
	testing.expect_value(t, input, 0)

	// Deeper: the change may sit anywhere on the path, on either side.
	deep := transform(take(transform(a, proc(x: int) -> int {return x}), 3), proc(x: int) -> int {return x})
	_, blame, _, ok = shared_source(p, z, node_of(deep))
	testing.expect(t, !ok)
	testing.expect_value(t, blame.name, "take")

	// The impure path may be the one already wired.
	z2 := half_zip(p, flat_map(a, proc(x: int) -> []int {return three[:]}))
	_, blame, _, ok = shared_source(p, z2, node_of(a))
	testing.expect(t, !ok)
	testing.expect_value(t, blame.name, "flat_map")

	// A merge is not one-to-one either.
	m := merge([]Stream(int){a, ints(p, {9})})
	_, blame, _, ok = shared_source(p, z, node_of(m))
	testing.expect(t, !ok)
	testing.expect_value(t, blame.name, "merge")
}

@(test)
zip_check_catches_a_second_zip_sharing_a_source :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator)
	defer destroy(p)
	a := ints(p, {1})
	b := ints(p, {2})
	first := zip(a, b) // fine: disjoint
	z := half_zip(p, transform(first, proc(pr: Pair(int, int)) -> int {return pr.first}))
	// zip itself changes the count (min of both), so a reaching z twice is unsafe.
	shared, blame, _, ok := shared_source(p, z, node_of(a))
	testing.expect(t, !ok)
	testing.expect_value(t, shared, node_of(a))
	testing.expect_value(t, blame, node_of(first))
}

// --- layout and defaults -----------------------------------------------------

// The edge's flags keep the ring's separation: nothing the consumer touches
// per pop shares a line with anything the producer touches per push.
@(test)
edge_flags_keep_the_ends_apart :: proc(t: ^testing.T) {
	producer := offset_of(Edge, buffer) + offset_of(ring.Raw, tail)
	consumer := offset_of(Edge, buffer) + offset_of(ring.Raw, head)
	parked := offset_of(Edge, parked)
	dirty := offset_of(Edge, dirty)
	apart :: proc(a, b: uintptr) -> bool {return a > b ? a - b >= ring.LINE : b - a >= ring.LINE}
	testing.expect(t, apart(parked, producer), "parked shares the producer's line")
	testing.expect(t, apart(parked, dirty), "parked shares a line with dirty")
	testing.expect(t, apart(dirty, consumer), "dirty shares the consumer's line")
	testing.expect(t, offset_of(Edge, closed) - parked < ring.LINE, "closed sits with the consumer's flag")
	testing.expect(t, offset_of(Edge, cancelled) - dirty < ring.LINE, "cancelled sits with the producer's flag")
}

@(test)
run_picks_a_pool_from_the_graph :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator)
	defer destroy(p)
	got := make([dynamic]int)
	defer delete(got)
	collect(ints(p, {1, 2, 3}), &got)
	testing.expect_value(t, pool_size(p, AUTO), 1)
	run(p)
	expect_ints(t, got[:], {1, 2, 3})
	for _ in 0 ..< 5 {
		transform(ints(p, {}), proc(x: int) -> int {return x})
	}
	testing.expect_value(t, pool_size(p, AUTO), 3)
	testing.expect_value(t, pool_size(p, 7), 7)
	p.choose = proc(data: rawptr, count: int) -> int {return 0}
	testing.expect_value(t, pool_size(p, 7), 0)
}

@(test)
connect_checks_the_producer_emits_one_type :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator)
	defer destroy(p)
	src := ints(p, {1})
	_, ok := out_shape(node_of(src), ring.shape_of(f64))
	testing.expect(t, ok, "a node with no outs yet agrees with anything")
	sink := add_node(p, "sink", lies_drained, struct {}{})
	connect(p, src.node, sink, ring.shape_of(int))
	want, ok2 := out_shape(node_of(src), ring.shape_of(f64))
	testing.expect(t, !ok2, "same size, different type: refused")
	testing.expect(t, want.id == int)
	_, ok3 := out_shape(node_of(src), ring.shape_of(int))
	testing.expect(t, ok3)
}

// --- latest -----------------------------------------------------------------

@(test)
op_latest_keeps_the_newest_and_takes_once :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator, cap = 4)
	defer destroy(p)
	items: [3 * BUDGET]int
	for &x, ii in items {
		x = ii
	}
	l := latest(ints(p, items[:]))
	v: int
	testing.expect(t, !latest_take(l, &v))
	run(p)
	testing.expect(t, finished(p))
	testing.expect(t, latest_take(l, &v))
	testing.expect_value(t, v, len(items) - 1)
	testing.expect(t, !latest_take(l, &v))
	testing.expect(t, latest_ended(l))
}

@(test)
op_latest_never_parks_its_producer :: proc(t: ^testing.T) {
	// A sink nobody reads: with a bounded edge the producer would park;
	// latest drains it, so the run finishes with the last value waiting.
	p := make_pipeline(context.allocator, cap = 1)
	defer destroy(p)
	items: [200]int
	for &x, ii in items {
		x = ii
	}
	l := latest(ints(p, items[:]))
	run(p, 2)
	testing.expect(t, finished(p))
	v: int
	testing.expect(t, latest_take(l, &v))
	testing.expect_value(t, v, 199)
}

// --- debounce_by -----------------------------------------------------------

@(private = "file")
Keyed :: struct {
	key, seq: int,
}

@(private = "file")
keyed_key :: proc(v: Keyed) -> int {
	return v.key
}

@(test)
op_debounce_by_settles_each_key_alone :: proc(t: ^testing.T) {
	clock := manual_clock()
	p := make_pipeline(context.allocator, clock = &clock)
	defer destroy(p)
	s, port := port(p, Keyed)
	got := make([dynamic]Keyed)
	defer delete(got)
	collect(debounce_by(s, 10 * time.Millisecond, keyed_key), &got)
	drain(p)

	// Key 1 changes three times in a burst; key 2 once in the middle.
	port_push(port, Keyed{1, 1})
	drain(p)
	advance(&clock, 4 * time.Millisecond)
	port_push(port, Keyed{2, 1})
	port_push(port, Keyed{1, 2})
	drain(p)
	advance(&clock, 4 * time.Millisecond)
	port_push(port, Keyed{1, 3})
	drain(p)
	testing.expect_value(t, len(got), 0)

	// 14 ms: key 2 has been quiet 10 ms, key 1 only 6.
	advance(&clock, 6 * time.Millisecond)
	drain(p)
	testing.expect_value(t, len(got), 1)
	testing.expect_value(t, got[0], Keyed{2, 1})

	// 18 ms: key 1 settles on its last value.
	advance(&clock, 4 * time.Millisecond)
	drain(p)
	testing.expect_value(t, len(got), 2)
	testing.expect_value(t, got[1], Keyed{1, 3})

	// What is pending when the input ends is flushed.
	port_push(port, Keyed{3, 1})
	port_close(port)
	drain(p)
	testing.expect_value(t, len(got), 3)
	testing.expect_value(t, got[2], Keyed{3, 1})
	testing.expect(t, finished(p))
}

@(test)
op_debounce_by_emits_due_keys_in_due_order :: proc(t: ^testing.T) {
	clock := manual_clock()
	p := make_pipeline(context.allocator, clock = &clock)
	defer destroy(p)
	s, port := port(p, Keyed)
	got := make([dynamic]Keyed)
	defer delete(got)
	collect(debounce_by(s, 10 * time.Millisecond, keyed_key), &got)
	drain(p)
	for k in 0 ..< 5 {
		port_push(port, Keyed{4 - k, 1})
		drain(p)
		advance(&clock, time.Millisecond)
	}
	advance(&clock, 20 * time.Millisecond)
	drain(p)
	testing.expect_value(t, len(got), 5)
	for v, ii in got {
		testing.expect_value(t, v.key, 4 - ii)
	}
	port_close(port)
	drain(p)
	testing.expect(t, finished(p))
}

// A pipeline driven only by step starts its sources itself: an interval
// arms on the first step and fires as a manual clock passes it. Once,
// step ran only what something else had queued, and an interval never
// armed in a test that never called run or drain.
@(test)
op_an_interval_fires_under_step_alone :: proc(t: ^testing.T) {
	clock := manual_clock()
	p := make_pipeline(context.allocator, clock = &clock)
	defer destroy(p)
	got: [dynamic]time.Duration
	defer delete(got)
	collect(interval(p, 10 * time.Millisecond), &got)
	for step(p) {}
	testing.expect_value(t, armed_count(p), 1)
	for i in 1 ..= 3 {
		advance(&clock, 10 * time.Millisecond)
		for step(p) {}
		testing.expect_value(t, len(got), i)
	}
	testing.expect_value(t, got[2], 30 * time.Millisecond)
}
