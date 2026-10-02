package stream

import "core:strings"
import "core:sync"
import "core:testing"
import "core:thread"
import "core:time"

import "jm:stream/ring"

@(test)
transform_filter_collect :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator)
	defer destroy(p)
	items := []int{1, 2, 3, 4, 5, 6}
	got := make([dynamic]int)
	defer delete(got)

	s := from_slice(p, items)
	s = filter(s, proc(x: int) -> bool {return x % 2 == 0})
	s = transform(s, proc(x: int) -> int {return x * 10})
	collect(s, &got)
	run(p)

	testing.expect_value(t, len(got), 3)
	testing.expect_value(t, got[0], 20)
	testing.expect_value(t, got[2], 60)
	testing.expect(t, finished(p))
}

Sum :: struct {
	total: int,
}

@(test)
stateful_stages :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator)
	defer destroy(p)
	items := []int{1, 2, 3, 4}
	sum: Sum
	running: Sum

	s := from_slice(p, items)
	s = transform(s, &running, proc(st: ^Sum, x: int) -> int {st.total += x; return st.total})
	for_each(s, &sum, proc(st: ^Sum, x: int) {st.total += x})
	run(p)

	testing.expect_value(t, running.total, 10)
	testing.expect_value(t, sum.total, 1 + 3 + 6 + 10)
}

@(test)
back_pressure_keeps_order :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator, cap = 4)
	defer destroy(p)
	items: [100]int
	for ii in 0 ..< 100 {
		items[ii] = ii
	}
	got := make([dynamic]int)
	defer delete(got)

	s := from_slice(p, items[:])
	collect(s, &got)
	run(p, 0)

	testing.expect_value(t, len(got), 100)
	for v, ii in got {
		testing.expect_value(t, v, ii)
	}
	// The source was parked and woken, not run once over an unbounded edge.
	testing.expect(t, node_of(s).runs > 1)
}

@(test)
zip_ends_with_the_shorter :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator)
	defer destroy(p)
	got := make([dynamic]Pair(int, string))
	defer delete(got)

	a := from_slice(p, []int{1, 2, 3})
	b := from_slice(p, []string{"a", "b"})
	collect(zip(a, b), &got)
	run(p)

	testing.expect_value(t, len(got), 2)
	testing.expect_value(t, got[1].first, 2)
	testing.expect_value(t, got[1].second, "b")
	testing.expect(t, finished(p))
}

@(test)
merge_carries_everything :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator)
	defer destroy(p)
	got := make([dynamic]int)
	defer delete(got)

	a := from_slice(p, []int{1, 1, 1})
	b := from_slice(p, []int{2, 2})
	c := from_slice(p, []int{3})
	collect(merge([]Stream(int){a, b, c}), &got)
	run(p)

	ones, twos, threes: int
	for v in got {
		switch v {
		case 1:
			ones += 1
		case 2:
			twos += 1
		case 3:
			threes += 1
		}
	}
	testing.expect_value(t, len(got), 6)
	testing.expect_value(t, ones, 3)
	testing.expect_value(t, twos, 2)
	testing.expect_value(t, threes, 1)
}

Counter :: struct {
	n:   int,
	buf: [3]int,
}

@(test)
take_ends_an_endless_source :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator)
	defer destroy(p)
	got := make([dynamic]int)
	defer delete(got)
	c: Counter

	s := generate(p, &c, proc(c: ^Counter) -> (int, bool) {c.n += 1; return c.n, true})
	collect(take(s, 5), &got)
	run(p, 0) // one thread: the bound below assumes the source cannot run ahead

	testing.expect_value(t, len(got), 5)
	testing.expect_value(t, got[4], 5)
	testing.expect(t, finished(p))
	// The source stopped soon after the take cancelled it, not at some
	// unrelated limit.
	testing.expect(t, c.n < 5 + 2 * DEFAULT_CAP + BUDGET)
}

@(test)
flat_map_emits_many :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator, cap = 2)
	defer destroy(p)
	got := make([dynamic]int)
	defer delete(got)
	c: Counter

	s := from_slice(p, []int{1, 2, 3})
	s = flat_map(s, &c, proc(c: ^Counter, x: int) -> []int {
		c.buf = {x, x, x}
		return c.buf[:]
	})
	collect(s, &got)
	run(p)

	testing.expect_value(t, len(got), 9)
	testing.expect_value(t, got[3], 2)
	testing.expect_value(t, got[8], 3)
}

@(test)
fan_out_delivers_to_every_subscriber :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator, cap = 2)
	defer destroy(p)
	left := make([dynamic]int)
	right := make([dynamic]int)
	defer delete(left)
	defer delete(right)

	s := from_slice(p, []int{1, 2, 3, 4, 5})
	collect(s, &left)
	collect(transform(s, proc(x: int) -> int {return -x}), &right)
	run(p)

	testing.expect_value(t, len(left), 5)
	testing.expect_value(t, len(right), 5)
	testing.expect_value(t, right[4], -5)
}

@(test)
step_walks_one_node_at_a_time :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator)
	defer destroy(p)
	got := make([dynamic]int)
	defer delete(got)

	s := from_slice(p, []int{1, 2})
	sink := collect(s, &got)
	start(p)

	testing.expect(t, step(p)) // source emits both and ends
	testing.expect(t, node_of(s).done)
	testing.expect_value(t, len(got), 0)
	testing.expect(t, step(p)) // sink drains
	testing.expect_value(t, len(got), 2)
	testing.expect(t, node_at(p, sink).done)
	testing.expect(t, !step(p))
}

@(test)
dump_names_nodes_and_edges :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator)
	defer destroy(p)
	got := make([dynamic]int)
	defer delete(got)

	collect(from_slice(p, []int{1}, name = "numbers"), &got, name = "sink")
	run(p, 0)

	b := strings.builder_make(context.allocator)
	defer strings.builder_destroy(&b)
	dump(p, &b)
	out := strings.to_string(b)
	testing.expect(t, strings.contains(out, "numbers#0 Idle runs=1 done\n"))
	testing.expect(t, strings.contains(out, "numbers#0 -> sink#1 0/16 pushed=1 popped=1 closed cancelled"))
}

// ---------------------------------------------------------------------------
// The remaining symbols: ports, the clock, completions, and the yield checks
// ---------------------------------------------------------------------------

Feeder :: struct {
	port:  Port(int),
	count: int,
}

@(test)
port_is_fed_from_another_thread :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator, cap = 4)
	defer destroy(p)
	got := make([dynamic]int)
	defer delete(got)

	s, port := port(p, int, cap = 2)
	collect(s, &got)
	feeder := Feeder{port, 50}
	th := thread.create_and_start_with_poly_data(&feeder, proc(f: ^Feeder) {
		for ii in 0 ..< f.count {
			port_send(f.port, ii)
		}
		port_close(f.port)
	})
	run(p)
	thread.join(th)
	thread.destroy(th)

	testing.expect_value(t, len(got), 50)
	for v, ii in got {
		testing.expect_value(t, v, ii)
	}
	testing.expect(t, finished(p))
}

@(test)
interval_ticks_on_a_manual_clock :: proc(t: ^testing.T) {
	clock := manual_clock()
	p := make_pipeline(context.allocator, clock = &clock)
	defer destroy(p)
	got := make([dynamic]time.Duration)
	defer delete(got)

	collect(take(interval(p, 10 * time.Millisecond), 3), &got)
	run(p) // arms, returns: a manual clock never sleeps
	testing.expect_value(t, len(got), 0)
	for _ in 0 ..< 5 {
		advance(&clock, 5 * time.Millisecond)
		run(p)
	}
	testing.expect_value(t, len(got), 2)
	testing.expect_value(t, got[0], 10 * time.Millisecond)
	testing.expect_value(t, got[1], 20 * time.Millisecond)
	advance(&clock, 10 * time.Millisecond)
	run(p)
	testing.expect_value(t, len(got), 3)
	testing.expect(t, finished(p))
}

@(test)
debounce_emits_when_quiet :: proc(t: ^testing.T) {
	clock := manual_clock()
	p := make_pipeline(context.allocator, clock = &clock)
	defer destroy(p)
	got := make([dynamic]int)
	defer delete(got)

	s, port := port(p, int)
	collect(debounce(s, 8 * time.Millisecond), &got)
	port_push(port, 1)
	port_push(port, 2)
	drain(p)
	advance(&clock, 5 * time.Millisecond)
	port_push(port, 3)
	drain(p)
	testing.expect_value(t, len(got), 0)
	advance(&clock, 8 * time.Millisecond)
	drain(p)
	testing.expect_value(t, len(got), 1)
	testing.expect_value(t, got[0], 3)
	port_push(port, 4)
	port_close(port)
	drain(p)
	testing.expect_value(t, len(got), 2)
	testing.expect_value(t, got[1], 4)
	testing.expect(t, finished(p))
}

Slow :: struct {}

slow_double :: proc(_: ^Slow, x: int) -> int {
	if x % 3 == 0 {
		time.sleep(200 * time.Microsecond)
	}
	return x * 2
}

@(test)
async_map_keeps_order_when_asked :: proc(t: ^testing.T) {
	for ordered in ([]bool{true, false}) {
		p := make_pipeline(context.allocator, cap = 4)
		w := workers_start(3, context.allocator)
		got := make([dynamic]int)
		items: [40]int
		for ii in 0 ..< 40 {
			items[ii] = ii
		}
		slow: Slow

		s := from_slice(p, items[:])
		collect(async_map(s, w, &slow, slow_double, concurrency = 3, ordered = ordered), &got)
		run(p)
		workers_stop(w)

		testing.expect_value(t, len(got), 40)
		sum := 0
		in_order := true
		for v, ii in got {
			sum += v
			in_order &&= v == ii * 2
		}
		testing.expect_value(t, sum, 2 * (39 * 40 / 2))
		if ordered {
			testing.expect(t, in_order)
		}
		testing.expect(t, finished(p))
		delete(got)
		destroy(p)
	}
}

@(test)
run_sleeps_until_a_real_timer :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator)
	defer destroy(p)
	got := make([dynamic]time.Duration)
	defer delete(got)

	collect(take(interval(p, 2 * time.Millisecond), 2), &got)
	run(p)

	testing.expect_value(t, len(got), 2)
	testing.expect(t, got[1] - got[0] >= 2 * time.Millisecond)
}

lies_drained :: proc(n: ^Node) -> Yield {return .Drained}
lies_blocked :: proc(n: ^Node) -> Yield {return .Blocked}

@(test)
yield_checks_catch_a_lying_node :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator)
	defer destroy(p)

	s := from_slice(p, []int{1})
	liar := add_node(p, "liar", lies_drained, struct {}{})
	e := connect(p, s.node, liar, ring.shape_of(int))
	_, ok := check_yield(liar, .Drained)
	testing.expect(t, ok, "the input is open: a message may still arrive")
	v := 1
	edge_push(e, &v)
	_, ok = check_yield(liar, .Drained)
	testing.expect(t, !ok, "a message is waiting and there is room to emit")
	edge_pop(e, &v)
	edge_close(e)
	_, ok = check_yield(liar, .Drained)
	testing.expect(t, !ok, "every input ended, no inlet, no timer: a hang")
	arm_in(liar, time.Second)
	_, ok = check_yield(liar, .Drained)
	testing.expect(t, ok, "a timer will run it again")
	disarm(liar)
	_, ok = check_yield(liar, .Blocked)
	testing.expect(t, !ok, "Blocked without block")
	_, ok = check_yield(liar, .Budget)
	testing.expect(t, ok)
}

// ---------------------------------------------------------------------------
// Many threads
// ---------------------------------------------------------------------------

@(test)
pool_runs_a_graph_to_the_same_answer :: proc(t: ^testing.T) {
	for threads in ([]int{1, 2, 4, 8}) {
		p := make_pipeline(context.allocator, cap = 3)
		items: [500]int
		for ii in 0 ..< 500 {
			items[ii] = ii
		}
		got := make([dynamic]int)
		pairs := make([dynamic]Pair(int, int))
		running: Sum

		s := from_slice(p, items[:])
		evens := filter(from_slice(p, items[:]), proc(x: int) -> bool {return x % 2 == 0})
		odds := filter(from_slice(p, items[:]), proc(x: int) -> bool {return x % 2 == 1})
		collect(zip(evens, odds), &pairs)
		collect(take(transform(s, &running, proc(st: ^Sum, x: int) -> int {st.total += x; return st.total}), 100), &got)
		run(p, threads)

		testing.expect(t, finished(p))
		testing.expect_value(t, len(pairs), 250)
		for pr, ii in pairs {
			testing.expect_value(t, pr.first, 2 * ii)
			testing.expect_value(t, pr.second, 2 * ii + 1)
		}
		testing.expect_value(t, len(got), 100)
		testing.expect_value(t, got[99], 99 * 100 / 2)
		delete(got)
		delete(pairs)
		destroy(p)
	}
}

@(test)
pool_runs_ports_timers_and_workers_together :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator, cap = 2)
	defer destroy(p)
	w := workers_start(3, context.allocator)
	defer workers_stop(w)
	got := make([dynamic]int)
	defer delete(got)
	ticks := make([dynamic]time.Duration)
	defer delete(ticks)
	slow: Slow

	s, port := port(p, int, cap = 2)
	collect(async_map(s, w, &slow, slow_double, concurrency = 3), &got)
	collect(take(interval(p, time.Millisecond), 3), &ticks)
	feeder := Feeder{port, 200}
	th := thread.create_and_start_with_poly_data(&feeder, proc(f: ^Feeder) {
		for ii in 0 ..< f.count {
			port_send(f.port, ii)
		}
		port_close(f.port)
	})
	run(p, 4)
	thread.join(th)
	thread.destroy(th)

	testing.expect(t, finished(p))
	testing.expect_value(t, len(got), 200)
	for v, ii in got {
		testing.expect_value(t, v, ii * 2)
	}
	testing.expect_value(t, len(ticks), 3)
}

@(test)
stop_returns_early_and_run_resumes :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator)
	defer destroy(p)
	got := make([dynamic]int)
	defer delete(got)

	s, port := port(p, int)
	collect(s, &got)
	port_push(port, 1)
	stopper := thread.create_and_start_with_poly_data(p, proc(p: ^Pipeline) {
		time.sleep(5 * time.Millisecond)
		stop(p)
	})
	run(p, 2) // the port is open, so only stop can end this
	thread.join(stopper)
	thread.destroy(stopper)
	testing.expect(t, !finished(p))
	testing.expect_value(t, len(got), 1)

	port_push(port, 2)
	port_close(port)
	run(p)
	testing.expect(t, finished(p))
	testing.expect_value(t, len(got), 2)
}

// --- pinned nodes ----------------------------------------------------------

@(private = "file")
Pinned_Sink :: struct {
	thread: int, // the id of the thread that ran it, for the check
	sum:    int,
	runs:   int,
}

@(private = "file")
pinned_sink :: proc(st: ^Pinned_Sink, v: int) {
	st.sum += v
	st.thread = int(sync.current_thread_id())
}

@(private = "file")
Pinned_Case :: struct {
	p:     ^Pipeline,
	wakes: int, // atomic
}

@(private = "file")
pinned_wake :: proc(data: rawptr) {
	c := (^Pinned_Case)(data)
	sync.atomic_add(&c.wakes, 1)
}

@(private = "file")
pinned_pool :: proc(c: ^Pinned_Case) {
	run(c.p, 2)
}

@(test)
pinned_node_runs_only_in_drain_pinned :: proc(t: ^testing.T) {
	items: [500]int
	want := 0
	for &x, ii in items {
		x = ii
		want += ii
	}
	c: Pinned_Case
	c.p = make_pipeline(context.allocator, cap = 8)
	defer destroy(c.p)
	c.p.wake = pinned_wake
	c.p.wake_data = &c
	st: Pinned_Sink
	sink := for_each(transform(from_slice(c.p, items[:]), proc(v: int) -> int { return v * 1 }), &st, pinned_sink)
	pin(c.p, sink)

	// The pool runs the source and the transform; the sink waits for us.
	pool := thread.create_and_start_with_poly_data(&c, pinned_pool)
	me := int(sync.current_thread_id())
	ran := 0
	for !finished(c.p) {
		ran += drain_pinned(c.p)
		time.sleep(100 * time.Microsecond)
	}
	thread.join(pool)
	thread.destroy(pool)
	testing.expect_value(t, st.sum, want)
	testing.expect_value(t, st.thread, me)
	testing.expect(t, ran > 0)
	testing.expect(t, sync.atomic_load(&c.wakes) > 0)
	testing.expect(t, drain_pinned(c.p) == 0)
}

@(test)
drain_runs_pinned_nodes_on_the_one_thread :: proc(t: ^testing.T) {
	p := make_pipeline(context.allocator)
	defer destroy(p)
	items := []int{1, 2, 3}
	st: Pinned_Sink
	sink := for_each(from_slice(p, items), &st, pinned_sink)
	pin(p, sink)
	drain(p)
	testing.expect(t, finished(p))
	testing.expect_value(t, st.sum, 6)
}
