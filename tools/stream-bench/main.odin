/*
stream-bench times jm:stream and says what a message costs, then stresses it.

	stream-bench                                every benchmark, 1M messages
	stream-bench -items=200000 -threads=0,3     fewer messages, two pool sizes
	stream-bench -only=chain                    benchmarks whose name has "chain"
	stream-bench stress                         random DAGs for 30 s on all cores
	stream-bench stress -nodes=2000 -items=50000 -threads=23 -cap=1 -for=5m
	stream-bench crossover                      where a pool starts to pay
	stream-bench crossover -work=0,100,1000 -threads=0,3,7

Each benchmark reports messages, threads, wall time, nanoseconds a message and
millions of messages a second. Threads is what `run` is given besides the
caller, so 0 is one thread in all.

	loop       the same arithmetic in a for loop: the floor
	chan       core:sync/chan between two threads: a hand-off done plainly
	chain1     source, one transform, sink
	chain4     source, four transforms, sink
	chain16    source, sixteen transforms, sink
	fanout8    one source read by eight sinks
	zip2       two sources zipped
	merge8     eight sources, a transform each, merged
	cap1       chain4 with edges of one message: every push parks
	cap256     chain4 with edges of 256
	async      async_map over four workers, concurrency 8, a trivial f
	port       a thread feeds a port through chain1
	latency16  one message at a time through sixteen stages, round trip

The stress mode builds a random DAG of the asked size, runs it, and checks
that every sink saw the count a model predicts and every edge is accounted
for, over and over until the time is up. It is built with the quiescence
check on, so a pipeline that goes quiet unfinished fails loudly.

The crossover mode makes every stage burn a chosen number of nanoseconds per
message, and prints ns per message for each thread count at each level of
work. A pool only pays once a stage's work outweighs the cost of handing a
message between cores; the table shows where that is on this machine.
*/
package main

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:math/rand"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:sync/chan"
import "core:thread"
import "core:time"

import "jm:stream"

Opts :: struct {
	items:   int,
	threads: []int,
	only:    string,
	json:    bool,
}

Stress_Opts :: struct {
	nodes:   int,
	sources: int,
	items:   int,
	threads: int,
	cap:     int,
	for_:    time.Duration,
	runs:    int, // 0 means until the time is up
	seed:    u64,
}

Result :: struct {
	name:    string,
	threads: int,
	items:   int,
	elapsed: time.Duration,
}

main :: proc() {
	args := os.args[1:]
	if len(args) > 0 && args[0] == "stress" {
		so := parse_stress(args[1:])
		os.exit(0 if stress(so) else 1)
	}
	if len(args) > 0 && args[0] == "crossover" {
		measure_crossover(parse_crossover(args[1:]))
		return
	}
	opts := parse(args)
	results := bench_all(opts)
	report(results, opts.json)
}

// cores counts the machine's processors from /proc on Linux; elsewhere it
// guesses eight, and -threads overrides it.
cores :: proc() -> int {
	when ODIN_OS == .Linux {
		if text, err := os.read_entire_file("/proc/cpuinfo", context.allocator); err == nil {
			defer delete(text)
			n := strings.count(string(text), "\nprocessor")
			if strings.has_prefix(string(text), "processor") {
				n += 1
			}
			if n > 0 {
				return n
			}
		}
	}
	return 8
}

span :: proc(s: string) -> time.Duration {
	unit := time.Second
	digits := s
	switch {
	case strings.has_suffix(s, "ms"):
		unit, digits = time.Millisecond, s[:len(s) - 2]
	case strings.has_suffix(s, "s"):
		unit, digits = time.Second, s[:len(s) - 1]
	case strings.has_suffix(s, "m"):
		unit, digits = time.Minute, s[:len(s) - 1]
	case strings.has_suffix(s, "h"):
		unit, digits = time.Hour, s[:len(s) - 1]
	}
	n, _ := strconv.parse_int(digits)
	return time.Duration(n) * unit
}

parse :: proc(args: []string) -> (o: Opts) {
	o.items = 1_000_000
	threads := make([dynamic]int)
	for arg in args {
		switch {
		case strings.has_prefix(arg, "-items="):
			o.items, _ = strconv.parse_int(arg[7:])
		case strings.has_prefix(arg, "-threads="):
			for part in strings.split(arg[9:], ",") {
				n, _ := strconv.parse_int(part)
				append(&threads, n)
			}
		case strings.has_prefix(arg, "-only="):
			o.only = arg[6:]
		case arg == "-json":
			o.json = true
		case:
			fmt.eprintln(USAGE)
			os.exit(2)
		}
	}
	if len(threads) == 0 {
		append(&threads, 0, 1, 3, 7)
		if cores() - 1 > 7 {
			append(&threads, cores() - 1)
		}
	}
	o.threads = threads[:]
	return
}

parse_stress :: proc(args: []string) -> (o: Stress_Opts) {
	o.nodes = 500
	o.sources = 8
	o.items = 20_000
	o.threads = cores() - 1
	o.cap = 4
	o.for_ = 30 * time.Second
	for arg in args {
		switch {
		case strings.has_prefix(arg, "-nodes="):
			o.nodes, _ = strconv.parse_int(arg[7:])
		case strings.has_prefix(arg, "-sources="):
			o.sources, _ = strconv.parse_int(arg[9:])
		case strings.has_prefix(arg, "-items="):
			o.items, _ = strconv.parse_int(arg[7:])
		case strings.has_prefix(arg, "-threads="):
			o.threads, _ = strconv.parse_int(arg[9:])
		case strings.has_prefix(arg, "-cap="):
			o.cap, _ = strconv.parse_int(arg[5:])
		case strings.has_prefix(arg, "-for="):
			o.for_ = span(arg[5:])
		case strings.has_prefix(arg, "-runs="):
			o.runs, _ = strconv.parse_int(arg[6:])
		case strings.has_prefix(arg, "-seed="):
			o.seed, _ = strconv.parse_u64(arg[6:])
		case:
			fmt.eprintln(USAGE)
			os.exit(2)
		}
	}
	return
}

USAGE :: `usage: stream-bench [-items=N] [-threads=a,b,c] [-only=name] [-json]
       stream-bench stress [-nodes=N] [-sources=N] [-items=N] [-threads=N] [-cap=N] [-for=30s] [-runs=N] [-seed=N]
       stream-bench crossover [-work=a,b,c] [-threads=a,b,c]`

// ---------------------------------------------------------------------------
// Benchmarks
// ---------------------------------------------------------------------------

Sum :: struct {
	total: int, // atomic where sinks share it
}

// Nanoseconds every stage burns per message in the crossover mode. Zero is
// the plain benchmark.
work_ns: int

// Loop iterations that take one nanosecond, measured once at start.
spins_per_ns: f64

inc :: proc(x: int) -> int {
	if work_ns > 0 {
		burn(work_ns)
	}
	return x + 1
}

// burn spends about `ns` nanoseconds of CPU doing nothing useful.
burn :: proc(ns: int) {
	spins := int(f64(ns) * spins_per_ns)
	acc: u32 = 1
	for _ in 0 ..< spins {
		acc = acc * 1103515245 + 12345
	}
	intrinsics.volatile_store(&sink, acc)
}

sink: u32

calibrate :: proc() {
	spins := 20_000_000
	start := time.tick_now()
	acc: u32 = 1
	for _ in 0 ..< spins {
		acc = acc * 1103515245 + 12345
	}
	intrinsics.volatile_store(&sink, acc)
	spins_per_ns = f64(spins) / f64(time.tick_since(start))
}
add_to :: proc(s: ^Sum, x: int) {sync.atomic_add(&s.total, x)}
add_local :: proc(s: ^Sum, x: int) {s.total += x}

Bench :: struct {
	name: string,
	run:  proc(items: []int, threads: int) -> int, // returns a checksum
	// A benchmark that uses no pool runs once, not per thread count.
	flat: bool,
}

benches := []Bench {
	{"loop", bench_loop, true},
	{"chan", bench_chan, true},
	{"chain1", bench_chain1, false},
	{"chain4", bench_chain4, false},
	{"chain16", bench_chain16, false},
	{"fanout8", bench_fanout8, false},
	{"zip2", bench_zip2, false},
	{"merge8", bench_merge8, false},
	{"cap1", bench_cap1, false},
	{"cap256", bench_cap256, false},
	{"async", bench_async, false},
	{"port", bench_port, false},
	{"latency16", bench_latency16, false},
}

bench_all :: proc(o: Opts) -> []Result {
	items := make([]int, o.items)
	for &x, ii in items {
		x = ii
	}
	results := make([dynamic]Result)
	for b in benches {
		if o.only != "" && !strings.contains(b.name, o.only) {
			continue
		}
		threads := o.threads
		if b.flat {
			threads = {0}
		}
		for t in threads {
			n := items
			if b.name == "latency16" {
				n = items[:min(len(items), 20_000)]
			}
			if b.name == "async" {
				n = items[:min(len(items), 100_000)]
			}
			start := time.tick_now()
			b.run(n, t)
			append(&results, Result{b.name, t, len(n), time.tick_since(start)})
		}
	}
	return results[:]
}

report :: proc(results: []Result, json: bool) {
	if json {
		fmt.println("[")
		for r, ii in results {
			fmt.printf(
				"  {\"name\": %q, \"threads\": %d, \"items\": %d, \"ns\": %d}%s\n",
				r.name,
				r.threads,
				r.items,
				i64(r.elapsed),
				"," if ii < len(results) - 1 else "",
			)
		}
		fmt.println("]")
		return
	}
	fmt.printf("%-10s %7s %9s %9s %9s %8s\n", "bench", "threads", "items", "ms", "ns/msg", "Mmsg/s")
	for r in results {
		runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
		ns := f64(r.elapsed) / f64(max(r.items, 1))
		// Numbers are formatted to strings first and padded as strings, so the
		// columns pad with spaces.
		fmt.printf(
			"%-10s %7s %9s %9s %9s %8s\n",
			r.name,
			fmt.tprintf("%d", r.threads),
			fmt.tprintf("%d", r.items),
			fmt.tprintf("%.1f", f64(r.elapsed) / 1e6),
			fmt.tprintf("%.1f", ns),
			fmt.tprintf("%.2f", 1e3 / ns),
		)
	}
}

bench_loop :: proc(items: []int, _: int) -> int {
	s: Sum
	for x in items {
		add_local(&s, inc(x))
	}
	return s.total
}

Chan_Side :: struct {
	c:     chan.Chan(int),
	items: []int,
}

bench_chan :: proc(items: []int, _: int) -> int {
	c, _ := chan.create(chan.Chan(int), 256, context.allocator)
	defer chan.destroy(c)
	side := Chan_Side{c, items}
	th := thread.create_and_start_with_poly_data(&side, proc(s: ^Chan_Side) {
		for x in s.items {
			chan.send(s.c, x)
		}
		chan.close(s.c)
	})
	s: Sum
	for {
		x, ok := chan.recv(c)
		if !ok {
			break
		}
		add_local(&s, inc(x))
	}
	thread.join(th)
	thread.destroy(th)
	return s.total
}

chain :: proc(items: []int, threads: int, stages: int, cap: int) -> int {
	p := stream.make_pipeline(context.allocator, cap = cap)
	defer stream.destroy(p)
	s := stream.from_slice(p, items)
	for _ in 0 ..< stages {
		s = stream.transform(s, inc)
	}
	sum: Sum
	stream.for_each(s, &sum, add_local)
	stream.run(p, threads)
	return sum.total
}

bench_chain1 :: proc(items: []int, threads: int) -> int {return chain(items, threads, 1, 64)}
bench_chain4 :: proc(items: []int, threads: int) -> int {return chain(items, threads, 4, 64)}
bench_chain16 :: proc(items: []int, threads: int) -> int {return chain(items, threads, 16, 64)}
bench_cap1 :: proc(items: []int, threads: int) -> int {return chain(items, threads, 4, 1)}
bench_cap256 :: proc(items: []int, threads: int) -> int {return chain(items, threads, 4, 256)}

bench_fanout8 :: proc(items: []int, threads: int) -> int {
	p := stream.make_pipeline(context.allocator, cap = 64)
	defer stream.destroy(p)
	s := stream.from_slice(p, items)
	sum: Sum
	for _ in 0 ..< 8 {
		stream.for_each(stream.transform(s, inc), &sum, add_to)
	}
	stream.run(p, threads)
	return sum.total
}

bench_zip2 :: proc(items: []int, threads: int) -> int {
	p := stream.make_pipeline(context.allocator, cap = 64)
	defer stream.destroy(p)
	half := len(items) / 2
	z := stream.zip(stream.from_slice(p, items[:half]), stream.from_slice(p, items[half:]))
	sum: Sum
	stream.for_each(z, &sum, proc(s: ^Sum, pr: stream.Pair(int, int)) {s.total += pr.first + pr.second})
	stream.run(p, threads)
	return sum.total
}

bench_merge8 :: proc(items: []int, threads: int) -> int {
	p := stream.make_pipeline(context.allocator, cap = 64)
	defer stream.destroy(p)
	part := len(items) / 8
	ins: [8]stream.Stream(int)
	for ii in 0 ..< 8 {
		ins[ii] = stream.transform(stream.from_slice(p, items[ii * part:(ii + 1) * part]), inc)
	}
	sum: Sum
	stream.for_each(stream.merge(ins[:]), &sum, add_local)
	stream.run(p, threads)
	return sum.total
}

Nothing :: struct {}
inc_on_worker :: proc(_: ^Nothing, x: int) -> int {return x + 1}

bench_async :: proc(items: []int, threads: int) -> int {
	p := stream.make_pipeline(context.allocator, cap = 64)
	defer stream.destroy(p)
	w := stream.workers_start(4, context.allocator)
	defer stream.workers_stop(w)
	n: Nothing
	sum: Sum
	stream.for_each(stream.async_map(stream.from_slice(p, items), w, &n, inc_on_worker, concurrency = 8), &sum, add_local)
	stream.run(p, threads)
	return sum.total
}

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

bench_port :: proc(items: []int, threads: int) -> int {
	p := stream.make_pipeline(context.allocator, cap = 64)
	defer stream.destroy(p)
	s, port := stream.port(p, int, cap = 256)
	sum: Sum
	stream.for_each(stream.transform(s, inc), &sum, add_local)
	f := Feeder{port, items}
	th := thread.create_and_start_with_poly_data(&f, feed)
	stream.run(p, threads)
	thread.join(th)
	thread.destroy(th)
	return sum.total
}

Runner :: struct {
	p:       ^stream.Pipeline,
	threads: int,
}

// One message in flight at a time: push, spin until the sink counted it.
bench_latency16 :: proc(items: []int, threads: int) -> int {
	p := stream.make_pipeline(context.allocator, cap = 4)
	defer stream.destroy(p)
	s, port := stream.port(p, int, cap = 4)
	for _ in 0 ..< 16 {
		s = stream.transform(s, inc)
	}
	seen: Sum
	stream.for_each(s, &seen, proc(s: ^Sum, _: int) {sync.atomic_add(&s.total, 1)})
	r := Runner{p, threads}
	th := thread.create_and_start_with_poly_data(&r, proc(r: ^Runner) {stream.run(r.p, r.threads)})
	for x, ii in items {
		stream.port_send(port, x)
		for sync.atomic_load(&seen.total) <= ii {}
	}
	stream.port_close(port)
	thread.join(th)
	thread.destroy(th)
	return seen.total
}

// ---------------------------------------------------------------------------
// Stress
// ---------------------------------------------------------------------------

// Counted_Stream is a stream and how many messages the model says it carries.
Counted_Stream :: struct {
	s:        stream.Stream(int),
	count:    int,
	consumed: bool,
	uses:     int,
	above:    bit_set[0 ..< 64], // sources upstream; a zip never shares one
}

Count :: struct {
	n: int, // atomic
}

count_one :: proc(c: ^Count, _: int) {sync.atomic_add(&c.n, 1)}

stress :: proc(o: Stress_Opts) -> bool {
	seed := o.seed if o.seed != 0 else u64(time.now()._nsec)
	state := rand.create(seed)
	context.random_generator = rand.default_random_generator(&state)
	items := make([]int, o.items)
	defer delete(items)
	for &x, ii in items {
		x = ii
	}
	fmt.printf("stress: %d nodes, %d sources of %d, %d threads, cap %d, seed %d\n", o.nodes, o.sources, o.items, o.threads, o.cap, seed)
	deadline := time.tick_now()
	deadline._nsec += i64(o.for_)
	runs, messages := 0, 0
	for (o.runs == 0 && time.tick_now()._nsec < deadline._nsec) || (o.runs > 0 && runs < o.runs) {
		start := time.tick_now()
		n, ok := stress_once(o, items)
		runs += 1
		messages += n
		fmt.printf("  run %d: %d messages in %v (%.2f Mmsg/s)%s\n", runs, n, time.tick_since(start), f64(n) / f64(time.tick_since(start)) * 1e3, "" if ok else "  FAILED")
		if !ok {
			return false
		}
	}
	fmt.printf("stress: %d runs, %d messages, all accounted for\n", runs, messages)
	return true
}

stress_once :: proc(o: Stress_Opts, items: []int) -> (messages: int, ok: bool) {
	p := stream.make_pipeline(context.allocator, cap = o.cap)
	defer stream.destroy(p)
	streams := make([dynamic]Counted_Stream)
	defer delete(streams)
	for ii in 0 ..< min(o.sources, 64) {
		append(&streams, Counted_Stream{s = stream.from_slice(p, items), count = len(items), above = {ii}})
	}
	// A zip waits on one edge, so a bounded graph deadlocks when a source
	// reaches it along two paths of different rate, directly or through
	// another zip; jm:stream's `connect` refuses the direct form. Zips here
	// are only over sources nothing else reads, and those sources are then
	// frozen. Sources are the only shared ancestors, since every other stream
	// has one consumer by construction below.
	frozen: bit_set[0 ..< 64]
	for len(p.nodes) < o.nodes {
		ii := rand.int_max(len(streams))
		in_ := &streams[ii]
		if in_.above & frozen != {} && in_.uses > 0 {
			continue
		}
		out: Counted_Stream
		switch rand.int_max(5) {
		case 0, 1:
			out = {s = stream.transform(in_.s, inc), count = in_.count, above = in_.above}
		case 2:
			if in_.count * 2 > 4 * len(items) {
				continue
			}
			out = {s = stream.flat_map(in_.s, proc(x: int) -> []int {return twice[:]}), count = in_.count * 2, above = in_.above}
		case 3:
			take_count := rand.int_max(in_.count + 1)
			out = {s = stream.take(in_.s, take_count), count = min(take_count, in_.count), above = in_.above}
		case 4:
			other := &streams[rand.int_max(len(streams))]
			if in_.above & other.above != {} || in_.uses > 0 || other.uses > 0 {
				continue
			}
			shared := false
			for c in streams {
				if c.above & (in_.above | other.above) != {} && c.uses > 1 {
					shared = true
				}
			}
			if shared {
				continue
			}
			frozen |= in_.above | other.above
			other.uses += 1
			z := stream.zip(in_.s, other.s)
			out = {s = stream.transform(z, proc(pr: stream.Pair(int, int)) -> int {return pr.first}), count = min(in_.count, other.count), above = in_.above | other.above}
			other.consumed = true
		}
		in_.consumed = true
		in_.uses += 1
		append(&streams, out)
	}
	sinks := make([dynamic]int)
	defer delete(sinks)
	for c, ii in streams {
		if !c.consumed {
			append(&sinks, ii)
		}
	}
	counts := make([]Count, len(sinks))
	defer delete(counts)
	for si, ii in sinks {
		stream.for_each(streams[si].s, &counts[ii], count_one)
	}
	stream.run(p, o.threads)

	if !stream.finished(p) {
		fmt.println("    a node is unfinished")
		return 0, false
	}
	for e in p.edges {
		messages += stream.edge_pushed(e)
		if stream.edge_pushed(e) - stream.edge_popped(e) != stream.edge_len(e) {
			fmt.println("    an edge's counters disagree with its length")
			return messages, false
		}
		if stream.edge_len(e) > 0 && !stream.edge_cancelled(e) {
			fmt.println("    a live edge was left holding messages")
			return messages, false
		}
	}
	for si, ii in sinks {
		if counts[ii].n != streams[si].count {
			fmt.printf("    sink %d saw %d messages, model says %d\n", ii, counts[ii].n, streams[si].count)
			return messages, false
		}
	}
	return messages, true
}

twice := [2]int{0, 0}

// ---------------------------------------------------------------------------
// Crossover
// ---------------------------------------------------------------------------

Crossover_Opts :: struct {
	work:    []int,
	threads: []int,
}

parse_crossover :: proc(args: []string) -> (o: Crossover_Opts) {
	work := make([dynamic]int)
	threads := make([dynamic]int)
	for arg in args {
		switch {
		case strings.has_prefix(arg, "-work="):
			for part in strings.split(arg[6:], ",") {
				n, _ := strconv.parse_int(part)
				append(&work, n)
			}
		case strings.has_prefix(arg, "-threads="):
			for part in strings.split(arg[9:], ",") {
				n, _ := strconv.parse_int(part)
				append(&threads, n)
			}
		case:
			fmt.eprintln(USAGE)
			os.exit(2)
		}
	}
	if len(work) == 0 {
		append(&work, 0, 25, 50, 100, 200, 400, 800, 1600, 3200)
	}
	if len(threads) == 0 {
		append(&threads, 0, 1, 3, 7)
		if cores() - 1 > 7 {
			append(&threads, cores() - 1)
		}
	}
	o.work = work[:]
	o.threads = threads[:]
	return
}

// Shapes whose stages burn work: a chain, where only pipelining can help, and
// a fan-out and a merge, where the stages are independent.
crossover_shapes := []Bench{{"chain4", bench_chain4, false}, {"fanout8", bench_fanout8, false}, {"merge8", bench_merge8, false}}

measure_crossover :: proc(o: Crossover_Opts) {
	calibrate()
	fmt.printf("burn: %.2f spins per ns; a stage's work is checked against the clock below\n", spins_per_ns)
	for b in crossover_shapes {
		stages := 4 if b.name == "chain4" else 1
		fmt.printf("\n%s: ns per message by threads, each stage burning the work on the left\n", b.name)
		fmt.printf("%9s %9s", "work ns", "measured")
		for t in o.threads {
			runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
			fmt.printf(" %9s", fmt.tprintf("t=%d", t))
		}
		fmt.printf("  %s\n", "best")
		for w in o.work {
			runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
			work_ns = w
			// Size the run so one thread takes about half a second.
			per := max(20 + w * stages, 1)
			count := clamp(500_000_000 / per, 20_000, 1_000_000)
			items := make([]int, count)
			defer delete(items)
			for &x, ii in items {
				x = ii
			}
			// What a stage's burn really costs, measured outside the pipeline.
			start := time.tick_now()
			for _ in 0 ..< 10_000 {
				burn(w)
			}
			measured := f64(time.tick_since(start)) / 10_000
			fmt.printf("%9s %9s", fmt.tprintf("%d", w), fmt.tprintf("%.0f", measured))
			best_t, best := 0, 0.0
			single := 0.0
			for t, ti in o.threads {
				runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
				start = time.tick_now()
				b.run(items, t)
				ns := f64(time.tick_since(start)) / f64(count)
				if ti == 0 {
					single = ns
				}
				if ti == 0 || ns < best {
					best_t, best = t, ns
				}
				fmt.printf(" %9s", fmt.tprintf("%.0f", ns))
			}
			fmt.printf("  t=%d %.1fx\n", best_t, single / best)
		}
	}
	work_ns = 0
}
