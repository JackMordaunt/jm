/*
Package fuzz is the jm:stream suite for jm:fuzz: pipelines drawn at random, run
single-threaded under a scheduler that picks the next node at random, and again
on a pool of threads, each checked against a plain sequential model.

	report := fuzz.run({seed = 1, iterations = 10_000})

	dataflow        any graph of sources, chains, zip, merge and fan-out gives
	                what the model gives, ends, and leaves every edge accounted for
	debounce        under a manual clock, the latest message is emitted once the
	                input is quiet, exactly when the model says
	interval        a ticker ticks the asked number of times, forward in time
	async           work sent to threads comes back complete, in order when asked
	dataflow_pool   dataflow, run on 1 to 4 threads
	port_pool       a thread feeds a port while the pool runs the graph
	interval_pool   interval, with the pool firing the timers
	async_pool      async, with the pool draining the completions
	shapes          messages of 0 to 1000 bytes, one 32-byte aligned, cross edges and inlets intact
	stop_resume     stopping a pool at a random moment and running again loses nothing
	cancel_async    a take downstream of async_map ends the source with work in flight
	latest_pool     a thread reads a latest sink while the pool fills it: every take is
	                a later message than the last, and the final one is the model's last
	pinned_pool     a pinned sink runs only on the thread draining it, and sees every
	                message the model says, in order
	stress          a random DAG of up to 40 nodes, fan-out, zip and merge, on up to 8 threads

The single-threaded properties draw the next node from the case's entropy, so
every interleaving the scheduler allows is reachable and reproducible. The pool
properties run real threads, so a lost wake or a torn edge shows up as a wrong
answer or a pipeline that went quiet unfinished, which `run` reports. A case that
hangs is stopped by the deadline and fails rather than hanging the run.
*/
package stream_fuzz

import "base:runtime"
import "core:fmt"
import "core:slice"
import "core:sync"
import "core:thread"
import "core:time"

import harness "jm:fuzz"
import "jm:stream"

// properties is package level because a Suite holds a slice, which has to
// outlive the call that hands the Suite back.
properties := []harness.Property(^Case) {
	{"dataflow", dataflow},
	{"debounce", debounce},
	{"interval", interval},
	{"async", async},
	{"dataflow_pool", dataflow_pool},
	{"port_pool", port_pool},
	{"interval_pool", interval_pool},
	{"async_pool", async_pool},
	{"shapes", shapes},
	{"stop_resume", stop_resume},
	{"cancel_async", cancel_async},
	{"latest_pool", latest_pool},
	{"pinned_pool", pinned_pool},
	{"stress", stress},
}

// Case holds the pipeline a property is running, so the deadline can stop it.
Case :: struct {
	p: ^stream.Pipeline, // atomic
}

suite :: proc() -> harness.Suite(^Case) {
	return harness.Suite(^Case){name = "stream", setup = setup, cancel = cancel, properties = properties}
}

// CORPUS is where this suite's regressions live, relative to the repository
// root. A case that failed once is kept there and replayed on every run.
CORPUS :: "stream/fuzz/corpus"

// run checks the suite. It is the whole package from a caller's side.
run :: proc(opts := harness.Opts{}, allocator := context.allocator) -> harness.Report {
	return harness.run(suite(), opts, allocator)
}

setup :: proc() -> (^Case, bool) {
	return new(Case), true
}

// cancel is what the deadline calls: a pipeline that will not go quiet is
// stopped, and the property then reports what it found.
cancel :: proc(c: ^Case) {
	if p := sync.atomic_load(&c.p); p != nil {
		stream.stop(p)
	}
}

// pick stands in for a pool: the next node to run is whichever the case's
// bytes say, so every interleaving the scheduler allows is reachable.
pick :: proc(data: rawptr, count: int) -> int {
	return harness.integer_in((^harness.Source)(data), 0, count)
}

// open builds a pipeline for the case. A pool run allocates from many threads,
// so it gets the heap; the case arena is not safe to share.
open :: proc(c: ^Case, src: ^harness.Source, threads: int, clock: ^stream.Clock = nil) -> ^stream.Pipeline {
	allocator := context.allocator if threads == 0 else runtime.heap_allocator()
	p := stream.make_pipeline(allocator, cap = harness.integer_in(src, 1, 9), clock = clock)
	if threads == 0 {
		p.choose = pick
		p.choose_data = src
	}
	sync.atomic_store(&c.p, p)
	return p
}

close :: proc(c: ^Case, p: ^stream.Pipeline) {
	sync.atomic_store(&c.p, nil)
	stream.destroy(p)
}

// ---------------------------------------------------------------------------
// dataflow
// ---------------------------------------------------------------------------

// Op is one stage of a chain. The first is the least interesting, so a
// shrunk case tends towards it.
Op :: enum {
	Add,
	Even,
	Scan,
	Dup,
	Drop,
	Take,
}

// Op_State is what a stage of each kind keeps. One per stage, in the arena.
Op_State :: struct {
	amount: int,
	acc:    int,
	buf:    [2]int,
}

add :: proc(st: ^Op_State, x: int) -> int {return x + st.amount}
even :: proc(x: int) -> bool {return x % 2 == 0}
scan :: proc(st: ^Op_State, x: int) -> int {st.acc += x; return st.acc}
dup :: proc(st: ^Op_State, x: int) -> []int {st.buf = {x, x}; return st.buf[:]}
drop :: proc(st: ^Op_State, x: int) -> bool {
	if st.acc < st.amount {
		st.acc += 1
		return false
	}
	return true
}

// apply_op is the model: the same stage over a slice.
apply_op :: proc(op: Op, amount: int, in_: []int) -> []int {
	out := make([dynamic]int)
	acc := 0
	for x in in_ {
		switch op {
		case .Add:
			append(&out, x + amount)
		case .Even:
			if x % 2 == 0 {append(&out, x)}
		case .Scan:
			acc += x
			append(&out, acc)
		case .Dup:
			append(&out, x, x)
		case .Drop:
			if acc < amount {acc += 1} else {append(&out, x)}
		case .Take:
			if acc < amount {acc += 1; append(&out, x)}
		}
	}
	return out[:]
}

// chain draws a stage list, builds it on `s`, and returns the model's answer.
chain :: proc(src: ^harness.Source, s: stream.Stream(int), items: []int) -> (out: stream.Stream(int), expect: []int) {
	out = s
	expect = items
	for _ in 0 ..< harness.integer_in(src, 0, 5) {
		op := Op(harness.integer_in(src, 0, len(Op)))
		st := new(Op_State)
		st.amount = harness.integer_in(src, 0, 6)
		switch op {
		case .Add:
			out = stream.transform(out, st, add)
		case .Even:
			out = stream.filter(out, even)
		case .Scan:
			out = stream.transform(out, st, scan)
		case .Dup:
			out = stream.flat_map(out, st, dup)
		case .Drop:
			out = stream.filter(out, st, drop)
		case .Take:
			out = stream.take(out, st.amount)
		}
		expect = apply_op(op, st.amount, expect)
	}
	return
}

// draw_items draws up to `max` values. Pool cases ask for more, since a race
// between two threads needs messages to be flowing to show.
draw_items :: proc(src: ^harness.Source, max := 17) -> []int {
	items := make([]int, harness.integer_in(src, 0, max))
	for &x in items {
		x = harness.integer_in(src, -5, 40)
	}
	return items
}

Combination :: enum {
	Separate,
	Zip,
	Merge,
}

// Graph is a drawn pipeline and what the model says each sink should hold.
// The sinks live in the pipeline's allocator, since nodes append to them.
Graph :: struct {
	p:       ^stream.Pipeline,
	how:     Combination,
	items:   [][]int,
	expects: [][]int,
	raw:     [dynamic]int,
	got:     [][dynamic]int,
	pairs:   [dynamic]stream.Pair(int, int),
	merged:  [dynamic]int,
}

// The Graph is heap allocated because the sinks hold pointers into it.
build_graph :: proc(src: ^harness.Source, p: ^stream.Pipeline, max_items := 17) -> (g: ^Graph) {
	g = new(Graph)
	g.p = p
	count := harness.integer_in(src, 1, 4)
	sources := make([]stream.Stream(int), count)
	chains := make([]stream.Stream(int), count)
	g.expects = make([][]int, count)
	g.items = make([][]int, count)
	for ii in 0 ..< count {
		g.items[ii] = draw_items(src, max_items)
		sources[ii] = stream.from_slice(p, g.items[ii])
		chains[ii], g.expects[ii] = chain(src, sources[ii], g.items[ii])
	}
	g.how = Combination(harness.integer_in(src, 0, len(Combination)))
	if count < 2 && g.how == .Zip {
		g.how = .Separate
	}
	// Fan-out: the first source is also read raw, beside its chain.
	g.raw = make([dynamic]int, p.allocator)
	stream.collect(sources[0], &g.raw)
	g.got = make([][dynamic]int, count)
	for &got in g.got {
		got = make([dynamic]int, p.allocator)
	}
	g.pairs = make([dynamic]stream.Pair(int, int), p.allocator)
	g.merged = make([dynamic]int, p.allocator)
	switch g.how {
	case .Separate:
		for ii in 0 ..< count {
			stream.collect(chains[ii], &g.got[ii])
		}
	case .Zip:
		stream.collect(stream.zip(chains[0], chains[1]), &g.pairs)
		for ii in 2 ..< count {
			stream.collect(chains[ii], &g.got[ii])
		}
	case .Merge:
		stream.collect(stream.merge(chains), &g.merged)
	}
	return
}

release_graph :: proc(g: ^Graph) {
	delete(g.raw)
	for got in g.got {
		delete(got)
	}
	delete(g.pairs)
	delete(g.merged)
}

check_graph :: proc(g: ^Graph) -> (detail: string, ok: bool) {
	p := g.p
	if !stream.finished(p) {
		return "run returned with a node unfinished", false
	}
	for e in p.edges {
		if stream.edge_pushed(e) - stream.edge_popped(e) != stream.edge_len(e) {
			return "an edge's counters disagree with its length", false
		}
		if stream.edge_len(e) > 0 && !stream.edge_cancelled(e) {
			return "a live edge was left holding messages", false
		}
	}
	if !slice.equal(g.raw[:], g.items[0]) {
		return fmt.tprintf("fan-out: raw read %v, source had %v", g.raw[:], g.items[0]), false
	}
	switch g.how {
	case .Separate:
		for ii in 0 ..< len(g.got) {
			if !slice.equal(g.got[ii][:], g.expects[ii]) {
				return fmt.tprintf("chain %d gave %v, model says %v", ii, g.got[ii][:], g.expects[ii]), false
			}
		}
	case .Zip:
		n := min(len(g.expects[0]), len(g.expects[1]))
		if len(g.pairs) != n {
			return fmt.tprintf("zip gave %d pairs, model says %d", len(g.pairs), n), false
		}
		for pr, ii in g.pairs {
			if pr.first != g.expects[0][ii] || pr.second != g.expects[1][ii] {
				return fmt.tprintf("zip pair %d is %v, model says {%d, %d}", ii, pr, g.expects[0][ii], g.expects[1][ii]), false
			}
		}
		for ii in 2 ..< len(g.got) {
			if !slice.equal(g.got[ii][:], g.expects[ii]) {
				return fmt.tprintf("chain %d gave %v, model says %v", ii, g.got[ii][:], g.expects[ii]), false
			}
		}
	case .Merge:
		all := make([dynamic]int)
		for e in g.expects {
			append(&all, ..e)
		}
		slice.sort(all[:])
		slice.sort(g.merged[:])
		if !slice.equal(g.merged[:], all[:]) {
			return fmt.tprintf("merge gave %v, model says %v", g.merged[:], all[:]), false
		}
	}
	return "", true
}

dataflow :: proc(c: ^Case, src: ^harness.Source) -> (detail: string, ok: bool) {
	p := open(c, src, 0)
	defer close(c, p)
	g := build_graph(src, p)
	stream.run(p)
	return check_graph(g)
}

dataflow_pool :: proc(c: ^Case, src: ^harness.Source) -> (detail: string, ok: bool) {
	threads := harness.integer_in(src, 1, 5)
	p := open(c, src, threads)
	defer close(c, p)
	g := build_graph(src, p, max_items = 120)
	defer release_graph(g)
	stream.run(p, threads)
	detail, ok = check_graph(g)
	if !ok {
		detail = fmt.tprintf("%d threads: %s", threads, detail)
	}
	return
}

// ---------------------------------------------------------------------------
// debounce
// ---------------------------------------------------------------------------

Event :: struct {
	at: time.Duration,
	v:  int,
}

// A timer due at T fires before a message pushed at T is seen, so a gap of
// exactly `quiet` emits. The case advances, drains, then pushes, which is the
// order a real clock gives.
debounce :: proc(c: ^Case, src: ^harness.Source) -> (detail: string, ok: bool) {
	clock := stream.manual_clock()
	p := open(c, src, 0, &clock)
	defer close(c, p)
	quiet := time.Duration(harness.integer_in(src, 1, 20)) * time.Millisecond
	got := make([dynamic]int)
	s, port := stream.port(p, int)
	stream.collect(stream.debounce(s, quiet), &got)
	stream.drain(p)

	events := make([dynamic]Event)
	for ii in 0 ..< harness.integer_in(src, 0, 12) {
		stream.advance(&clock, time.Duration(harness.integer_in(src, 0, 25)) * time.Millisecond)
		stream.drain(p)
		stream.port_push(port, ii)
		append(&events, Event{clock.t, ii})
		stream.drain(p)
	}
	if harness.boolean(src) {
		stream.advance(&clock, time.Duration(harness.integer_in(src, 0, 30)) * time.Millisecond)
		stream.drain(p)
	}
	stream.port_close(port)
	stream.drain(p)

	expect := make([dynamic]int)
	for e, ii in events {
		if ii == len(events) - 1 || events[ii + 1].at - e.at >= quiet {
			append(&expect, e.v)
		}
	}
	if !stream.finished(p) {
		return "a node is unfinished after the port closed", false
	}
	if !slice.equal(got[:], expect[:]) {
		return fmt.tprintf("quiet %v, events %v: got %v, model says %v", quiet, events[:], got[:], expect[:]), false
	}
	return "", true
}

// ---------------------------------------------------------------------------
// interval
// ---------------------------------------------------------------------------

check_ticks :: proc(p: ^stream.Pipeline, got: []time.Duration, every: time.Duration, count: int) -> (detail: string, ok: bool) {
	if !stream.finished(p) {
		return fmt.tprintf("every %v, take %d: not finished after 50 advances, %d ticks", every, count, len(got)), false
	}
	if len(got) != count {
		return fmt.tprintf("every %v: %d ticks, asked for %d", every, len(got), count), false
	}
	for t, ii in got {
		if t < time.Duration(ii + 1) * every {
			return fmt.tprintf("tick %d at %v, before its time %v", ii, t, time.Duration(ii + 1) * every), false
		}
		if ii > 0 && t <= got[ii - 1] {
			return fmt.tprintf("tick %d at %v is not after tick %d at %v", ii, t, ii - 1, got[ii - 1]), false
		}
	}
	return "", true
}

interval :: proc(c: ^Case, src: ^harness.Source) -> (detail: string, ok: bool) {
	clock := stream.manual_clock()
	p := open(c, src, 0, &clock)
	defer close(c, p)
	every := time.Duration(harness.integer_in(src, 1, 20)) * time.Millisecond
	count := harness.integer_in(src, 0, 7)
	got := make([dynamic]time.Duration)
	stream.collect(stream.take(stream.interval(p, every), count), &got)

	stream.run(p)
	for _ in 0 ..< 50 {
		if stream.finished(p) {
			break
		}
		stream.advance(&clock, time.Duration(harness.integer_in(src, 1, 30)) * time.Millisecond)
		stream.run(p)
	}
	return check_ticks(p, got[:], every, count)
}

interval_pool :: proc(c: ^Case, src: ^harness.Source) -> (detail: string, ok: bool) {
	clock := stream.manual_clock()
	threads := harness.integer_in(src, 1, 4)
	p := open(c, src, threads, &clock)
	defer close(c, p)
	every := time.Duration(harness.integer_in(src, 1, 20)) * time.Millisecond
	count := harness.integer_in(src, 0, 7)
	got := make([dynamic]time.Duration, p.allocator)
	defer delete(got)
	stream.collect(stream.take(stream.interval(p, every), count), &got)

	stream.run(p, threads)
	for _ in 0 ..< 50 {
		if stream.finished(p) {
			break
		}
		stream.advance(&clock, time.Duration(harness.integer_in(src, 1, 30)) * time.Millisecond)
		stream.run(p, threads)
	}
	return check_ticks(p, got[:], every, count)
}

// ---------------------------------------------------------------------------
// async
// ---------------------------------------------------------------------------

Triple :: struct {}

triple :: proc(_: ^Triple, x: int) -> int {
	if x % 4 == 0 {
		time.sleep(50 * time.Microsecond)
	}
	return x * 3
}

run_async :: proc(c: ^Case, src: ^harness.Source, threads: int) -> (detail: string, ok: bool) {
	p := open(c, src, threads)
	defer close(c, p)
	workers := harness.integer_in(src, 1, 5)
	concurrency := harness.integer_in(src, 1, 6)
	ordered := harness.boolean(src)
	items := draw_items(src)
	w := stream.workers_start(workers, p.allocator)
	defer stream.workers_stop(w)
	got := make([dynamic]int, p.allocator)
	defer delete(got)
	st: Triple
	s := stream.from_slice(p, items)
	stream.collect(stream.async_map(s, w, &st, triple, concurrency = concurrency, ordered = ordered), &got)
	stream.run(p, threads)

	if !stream.finished(p) {
		return "run returned with a node unfinished", false
	}
	expect := make([]int, len(items))
	for x, ii in items {
		expect[ii] = x * 3
	}
	if !ordered {
		slice.sort(got[:])
		slice.sort(expect)
	}
	if !slice.equal(got[:], expect) {
		return fmt.tprintf("%d threads, %d workers, concurrency %d, ordered %v: got %v, expected %v", threads, workers, concurrency, ordered, got[:], expect), false
	}
	return "", true
}

async :: proc(c: ^Case, src: ^harness.Source) -> (detail: string, ok: bool) {
	return run_async(c, src, 0)
}

async_pool :: proc(c: ^Case, src: ^harness.Source) -> (detail: string, ok: bool) {
	return run_async(c, src, harness.integer_in(src, 1, 5))
}

// ---------------------------------------------------------------------------
// port_pool
// ---------------------------------------------------------------------------

Feeder :: struct {
	port:  stream.Port(int),
	items: []int,
}

feed :: proc(f: ^Feeder) {
	for x in f.items {
		stream.port_send(f.port, x)
	}
	stream.port_close(f.port)
}

// A thread feeds a port through a chain the pool runs; the chain's answer is
// the model's, however the feeder and the workers interleave.
port_pool :: proc(c: ^Case, src: ^harness.Source) -> (detail: string, ok: bool) {
	threads := harness.integer_in(src, 1, 5)
	p := open(c, src, threads)
	defer close(c, p)
	items := draw_items(src, 120)
	s, port := stream.port(p, int, cap = harness.integer_in(src, 1, 5))
	out, expect := chain(src, s, items)
	got := make([dynamic]int, p.allocator)
	defer delete(got)
	stream.collect(out, &got)
	feeder := Feeder{port, items}
	th := thread.create_and_start_with_poly_data(&feeder, feed)
	stream.run(p, threads)
	thread.join(th)
	thread.destroy(th)

	if !stream.finished(p) {
		return "run returned with a node unfinished", false
	}
	if !slice.equal(got[:], expect) {
		return fmt.tprintf("%d threads: got %v, model says %v", threads, got[:], expect), false
	}
	return "", true
}

// ---------------------------------------------------------------------------
// latest and pinned
// ---------------------------------------------------------------------------

Pool_Runner :: struct {
	p:       ^stream.Pipeline,
	threads: int,
}

run_pool :: proc(r: ^Pool_Runner) {
	stream.run(r.p, r.threads)
}

latest_pool :: proc(c: ^Case, src: ^harness.Source) -> (detail: string, ok: bool) {
	threads := harness.integer_in(src, 1, 5)
	p := open(c, src, threads)
	defer close(c, p)
	items := draw_items(src, 200)
	out, expect := chain(src, stream.from_slice(p, items), items)
	l := stream.latest(out)
	runner := Pool_Runner{p, threads}
	th := thread.create_and_start_with_poly_data(&runner, run_pool)
	// Read while it runs, as a frame loop would, then once more after.
	taken := make([dynamic]int, p.allocator)
	defer delete(taken)
	v: int
	for !stream.latest_ended(l) {
		if stream.latest_take(l, &v) {
			append(&taken, v)
		}
	}
	thread.join(th)
	thread.destroy(th)
	if stream.latest_take(l, &v) {
		append(&taken, v)
	}
	if !stream.finished(p) {
		return "run returned with a node unfinished", false
	}
	if len(expect) == 0 {
		if len(taken) != 0 {
			return fmt.tprintf("took %v from an empty stream", taken[:]), false
		}
		return "", true
	}
	if len(taken) == 0 || taken[len(taken) - 1] != expect[len(expect) - 1] {
		return fmt.tprintf("%d threads: last take %v, model's last message %d", threads, taken[:], expect[len(expect) - 1]), false
	}
	// Every take is a message, each later in the sequence than the one before.
	at := 0
	for t in taken {
		for at < len(expect) && expect[at] != t {
			at += 1
		}
		if at == len(expect) {
			return fmt.tprintf("%d threads: takes %v are not in order along %v", threads, taken[:], expect), false
		}
		at += 1
	}
	return "", true
}

Pinned_Sink :: struct {
	got:    [dynamic]int,
	thread: int,
	mixed:  bool, // ran on more than one thread
}

pinned_sink :: proc(st: ^Pinned_Sink, v: int) {
	append(&st.got, v)
	id := int(sync.current_thread_id())
	if st.thread == 0 {
		st.thread = id
	} else if st.thread != id {
		st.mixed = true
	}
}

pinned_pool :: proc(c: ^Case, src: ^harness.Source) -> (detail: string, ok: bool) {
	threads := harness.integer_in(src, 1, 5)
	p := open(c, src, threads)
	defer close(c, p)
	items := draw_items(src, 200)
	out, expect := chain(src, stream.from_slice(p, items), items)
	st := Pinned_Sink {
		got = make([dynamic]int, p.allocator),
	}
	defer delete(st.got)
	stream.pin(p, stream.for_each(out, &st, pinned_sink))
	runner := Pool_Runner{p, threads}
	th := thread.create_and_start_with_poly_data(&runner, run_pool)
	for !stream.finished(p) {
		if stream.drain_pinned(p) == 0 {
			time.sleep(20 * time.Microsecond)
		}
	}
	thread.join(th)
	thread.destroy(th)
	if st.mixed || (st.thread != 0 && st.thread != int(sync.current_thread_id())) {
		return "the pinned sink ran on a pool thread", false
	}
	if !slice.equal(st.got[:], expect) {
		return fmt.tprintf("%d threads: got %v, model says %v", threads, st.got[:], expect), false
	}
	return "", true
}

// ---------------------------------------------------------------------------
// shapes
// ---------------------------------------------------------------------------

Shape0 :: struct {}
Shape1 :: struct {
	b: u8,
}
Shape3 :: struct {
	b: [3]u8,
}
Shape12 :: struct {
	a: i64,
	b: u8, // padded to 16
}
Shape33 :: struct {
	b: [33]u8,
}
Shape1000 :: struct {
	b: [1000]u8,
}
Shape32 :: struct #align (32) {
	b: [40]u8,
}

// shape_case pushes random values of T through an edge chain and a port and
// expects the bytes back unchanged.
shape_case :: proc(c: ^Case, src: ^harness.Source, $T: typeid) -> (detail: string, ok: bool) {
	identity :: proc(v: T) -> T {return v}
	p := open(c, src, 0)
	defer close(c, p)
	items := make([]T, harness.integer_in(src, 0, 40))
	when size_of(T) > 0 {
		for &v in items {
			for &b in ([^]u8)(&v)[:size_of(T)] {
				b = harness.byte_of(src)
			}
		}
	}
	via_edges := make([dynamic]T)
	via_port := make([dynamic]T)
	stream.collect(stream.transform(stream.from_slice(p, items), identity), &via_edges)
	s, port := stream.port(p, T, cap = harness.integer_in(src, 1, 5))
	stream.collect(s, &via_port)
	// A zero-size element is never loaded: a `for in` over a slice `make`
	// gave no storage faults on the load.
	when size_of(T) > 0 {
		for v in items {
			stream.port_push(port, v)
			stream.drain(p)
		}
	} else {
		for _ in 0 ..< len(items) {
			stream.port_push(port, T{})
			stream.drain(p)
		}
	}
	stream.port_close(port)
	stream.run(p)
	if !stream.finished(p) {
		return "unfinished", false
	}
	for got, label in ([][dynamic]T{via_edges, via_port}) {
		if len(got) != len(items) {
			return fmt.tprintf("%d-byte messages, path %d: %d of %d arrived", size_of(T), label, len(got), len(items)), false
		}
		when size_of(T) > 0 {
			for v, ii in items {
				v := v
				g := got[ii]
				if !slice.equal(([^]u8)(&v)[:size_of(T)], ([^]u8)(&g)[:size_of(T)]) {
					return fmt.tprintf("%d-byte messages, path %d: item %d changed", size_of(T), label, ii), false
				}
			}
		}
	}
	return "", true
}

shapes :: proc(c: ^Case, src: ^harness.Source) -> (detail: string, ok: bool) {
	switch harness.integer_in(src, 0, 7) {
	case 0:
		return shape_case(c, src, Shape0)
	case 6:
		return shape_case(c, src, Shape32)
	case 1:
		return shape_case(c, src, Shape1)
	case 2:
		return shape_case(c, src, Shape3)
	case 3:
		return shape_case(c, src, Shape12)
	case 4:
		return shape_case(c, src, Shape33)
	case:
		return shape_case(c, src, Shape1000)
	}
}

// ---------------------------------------------------------------------------
// stop_resume
// ---------------------------------------------------------------------------

Stopper :: struct {
	p:     ^stream.Pipeline,
	after: time.Duration,
}

stop_later :: proc(s: ^Stopper) {
	time.sleep(s.after)
	stream.stop(s.p)
}

// Stop lands at a random moment: before anything ran, mid-flight, or after
// the end. Running again until finished must give the model's answer.
stop_resume :: proc(c: ^Case, src: ^harness.Source) -> (detail: string, ok: bool) {
	threads := harness.integer_in(src, 1, 5)
	p := open(c, src, threads)
	defer close(c, p)
	g := build_graph(src, p, max_items = 120)
	defer release_graph(g)
	stopper := Stopper{p, time.Duration(harness.integer_in(src, 0, 400)) * time.Microsecond}
	th := thread.create_and_start_with_poly_data(&stopper, stop_later)
	stream.run(p, threads)
	thread.join(th)
	thread.destroy(th)
	resumed := 0
	for !stream.finished(p) && resumed < 100 {
		stream.run(p, threads)
		resumed += 1
	}
	detail, ok = check_graph(g)
	if !ok {
		detail = fmt.tprintf("%d threads, stop after %v, %d resumes: %s", threads, stopper.after, resumed, detail)
	}
	return
}

// ---------------------------------------------------------------------------
// cancel_async
// ---------------------------------------------------------------------------

// A take downstream of async_map ends with jobs still on the workers. The
// first k results must be right, the source must have been cancelled, and
// the workers must drain cleanly before the pipeline goes.
cancel_async :: proc(c: ^Case, src: ^harness.Source) -> (detail: string, ok: bool) {
	threads := harness.integer_in(src, 0, 5)
	p := open(c, src, threads)
	defer close(c, p)
	workers := harness.integer_in(src, 1, 5)
	concurrency := harness.integer_in(src, 1, 9)
	ordered := harness.boolean(src)
	items := draw_items(src, 120)
	take_count := harness.integer_in(src, 0, len(items) + 2)
	w := stream.workers_start(workers, p.allocator)
	defer stream.workers_stop(w)
	got := make([dynamic]int, p.allocator)
	defer delete(got)
	st: Triple
	s := stream.from_slice(p, items)
	stream.collect(stream.take(stream.async_map(s, w, &st, triple, concurrency = concurrency, ordered = ordered), take_count), &got)
	stream.run(p, threads)

	if !stream.finished(p) {
		return "run returned with a node unfinished", false
	}
	want := min(take_count, len(items))
	if len(got) != want {
		return fmt.tprintf("take %d of %d: got %d", take_count, len(items), len(got)), false
	}
	if ordered {
		for v, ii in got {
			if v != items[ii] * 3 {
				return fmt.tprintf("ordered: item %d is %d, expected %d", ii, v, items[ii] * 3), false
			}
		}
	} else {
		for v in got {
			found := false
			for x in items {
				if x * 3 == v {
					found = true
					break
				}
			}
			if !found {
				return fmt.tprintf("unordered: %d is not a result of any input", v), false
			}
		}
	}
	return "", true
}

// ---------------------------------------------------------------------------
// stress
// ---------------------------------------------------------------------------

// Model_Stream is a stream and what the model says it carries. After a merge
// the order is the scheduler's, so the model keeps a multiset and only
// elementwise stages may follow.
Model_Stream :: struct {
	s:         stream.Stream(int),
	expect:    []int,
	unordered: bool,
	consumed:  bool,
	// Every stream upstream of this one, itself included.
	above:     bit_set[0 ..< 64],
	uses:      int, // consumers so far
}

Stage :: enum {
	Add,
	Even,
	Dup,
	Scan,
	Drop,
	Take,
	Zip,
	Merge,
}

// A random DAG: sources, then nodes each over one or more earlier streams,
// then a collect on every stream nothing consumed. Fan-out comes free when
// two nodes pick the same earlier stream.
//
// Zip is the one stage that waits on a particular edge, so it is the one
// that can deadlock a bounded graph: a source fanned out to a zip and to a
// slower branch that feeds the same zip, or another zip, parks on one full
// edge while the zip waits on the other. jm:stream's `connect` refuses the
// direct form; the generator stays clear of the whole family by zipping only
// streams whose ancestry has a single consumer each, and freezing that
// ancestry so nothing later fans it out.
stress :: proc(c: ^Case, src: ^harness.Source) -> (detail: string, ok: bool) {
	threads := harness.integer_in(src, 0, 9)
	p := open(c, src, threads)
	defer close(c, p)
	streams := make([dynamic]Model_Stream)
	frozen: bit_set[0 ..< 64]
	exclusive :: proc(streams: []Model_Stream, m: ^Model_Stream) -> bool {
		if m.uses != 0 {
			return false
		}
		for jj in 0 ..< len(streams) {
			if jj in m.above && streams[jj].uses > 1 {
				return false
			}
		}
		return true
	}
	for _ in 0 ..< harness.integer_in(src, 1, 5) {
		items := draw_items(src, 300)
		append(&streams, Model_Stream{s = stream.from_slice(p, items), expect = items, above = {len(streams)}})
	}
	for _ in 0 ..< harness.integer_in(src, 1, 36) {
		stage := Stage(harness.integer_in(src, 0, len(Stage)))
		ii := harness.integer_in(src, 0, len(streams))
		in_ := &streams[ii]
		if ii in frozen {
			continue
		}
		st := new(Op_State)
		st.amount = harness.integer_in(src, 0, 6)
		out: Model_Stream
		switch stage {
		case .Add:
			out = {s = stream.transform(in_.s, st, add), expect = apply_op(.Add, st.amount, in_.expect), unordered = in_.unordered}
		case .Even:
			out = {s = stream.filter(in_.s, even), expect = apply_op(.Even, 0, in_.expect), unordered = in_.unordered}
		case .Dup:
			out = {s = stream.flat_map(in_.s, st, dup), expect = apply_op(.Dup, 0, in_.expect), unordered = in_.unordered}
		case .Scan, .Drop, .Take:
			if in_.unordered {
				continue
			}
			op := Op.Scan if stage == .Scan else (Op.Drop if stage == .Drop else Op.Take)
			switch op {
			case .Scan:
				out = {s = stream.transform(in_.s, st, scan)}
			case .Drop:
				out = {s = stream.filter(in_.s, st, drop)}
			case .Take:
				out = {s = stream.take(in_.s, st.amount)}
			case .Add, .Even, .Dup:
			}
			out.expect = apply_op(op, st.amount, in_.expect)
		case .Zip:
			jj := harness.integer_in(src, 0, len(streams))
			other := &streams[jj]
			if jj in frozen || in_.unordered || other.unordered || in_.above & other.above != {} {
				continue
			}
			if !exclusive(streams[:], in_) || !exclusive(streams[:], other) {
				continue
			}
			frozen |= in_.above | other.above
			other.uses += 1
			out.above = other.above
			n := min(len(in_.expect), len(other.expect))
			pairs := stream.zip(in_.s, other.s)
			out = {s = stream.transform(pairs, proc(pr: stream.Pair(int, int)) -> int {return pr.first * 1000 + pr.second})}
			expect := make([]int, n)
			for x in 0 ..< n {
				expect[x] = in_.expect[x] * 1000 + other.expect[x]
			}
			out.expect = expect
			other.consumed = true
		case .Merge:
			count := harness.integer_in(src, 2, 4)
			ins := make([]stream.Stream(int), count)
			all := make([dynamic]int)
			picked := 0
			for picked < count {
				mi := harness.integer_in(src, 0, len(streams))
				if mi in frozen {
					continue
				}
				m := &streams[mi]
				ins[picked] = m.s
				append(&all, ..m.expect)
				m.consumed = true
				m.uses += 1
				out.above |= m.above
				picked += 1
			}
			out.s = stream.merge(ins)
			out.expect = all[:]
			out.unordered = true
		}
		in_.consumed = true
		in_.uses += 1
		out.above |= in_.above + {len(streams)}
		append(&streams, out)
	}
	sinks := make([dynamic]^Model_Stream)
	for &m in streams {
		if !m.consumed {
			append(&sinks, &m)
		}
	}
	// Sized once: a collect keeps a pointer to its slot.
	outs := make([][dynamic]int, len(sinks))
	for m, ii in sinks {
		outs[ii] = make([dynamic]int, p.allocator)
		stream.collect(m.s, &outs[ii])
	}
	defer for o in outs {delete(o)}
	stream.run(p, threads)

	if !stream.finished(p) {
		return fmt.tprintf("%d nodes, %d threads: a node is unfinished", len(p.nodes), threads), false
	}
	for e in p.edges {
		if stream.edge_pushed(e) - stream.edge_popped(e) != stream.edge_len(e) {
			return "an edge's counters disagree with its length", false
		}
		if stream.edge_len(e) > 0 && !stream.edge_cancelled(e) {
			return "a live edge was left holding messages", false
		}
	}
	for m, ii in sinks {
		got := outs[ii][:]
		expect := m.expect
		if m.unordered {
			slice.sort(got)
			expect = slice.clone(expect)
			slice.sort(expect)
		}
		if !slice.equal(got, expect) {
			return fmt.tprintf("%d nodes, %d threads, sink %d (unordered %v): got %d items, model says %d", len(p.nodes), threads, ii, m.unordered, len(got), len(expect)), false
		}
	}
	return "", true
}
