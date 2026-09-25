/*
wasm-bench times jm:wasm against a Wasm module and says where the time went.

	just bench                                      the workload set
	wasm-bench fib.wasm -n=400                      one module, more work
	wasm-bench -json                                machine readable
	wasm-bench -invoke fib.wasm -n=200              call it once and print

Four numbers are reported for each module, because they answer different
questions and an engine can be good at one and bad at another:

	load        parse and instantiate, with nothing run yet
	first       the first call, less the load: wasm3 compiles a body the
	            first time it is called, so this is that compile plus a call
	call        a call that does no work: the cost of the crossing itself
	run(n)      the workload, once the body is compiled and warm

	work        run(2n) - run(n), which is the workload with everything
	            constant subtracted out - the load, the compile, the
	            crossing, and whatever the module does before the loop

work is the number to compare across engines, because the totals do not: they
carry every constant an engine pays before the loop starts, from process
startup to whatever compiling it does. Subtracting two runs of one module at
two sizes cancels all of it and leaves what scales.

Each module exports `run(i32) -> i32`, where the argument scales the work
linearly and the result is a checksum. The checksum is printed so two engines
can be checked against each other: a runtime that returns a different number
is not running the same benchmark.

-invoke is the same protocol for an engine that cannot be timed from inside:
it loads the module, calls `run(n)` once, prints the result, and exits, so a
script can time this process the way it times `wasmtime run --invoke`.
*/
package main

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:time"

import "jm:wasm"

// Result is one module's measurements, in nanoseconds.
Result :: struct {
	name:     string,
	path:     string,
	bytes:    int,
	load:     f64,
	first:    f64,
	call:     f64,
	run:      f64,
	run2:     f64,
	work:     f64,
	n:        int,
	checksum: i64,
}

// REPS is how many times each measurement is taken. The smallest is reported:
// a benchmark is bounded below by the work and above by whatever else the
// machine was doing, so the minimum is the least noisy estimate of the work.
REPS :: 5

// TARGET_NS is how long a calibrated run(n) should take: long enough that the
// clock and the crossing are noise, short enough that a table of workloads
// comes back in seconds.
TARGET_NS :: 25_000_000.0

// MAX_N caps the search, so a workload that does almost nothing per unit
// stops doubling rather than running out of i32.
MAX_N :: 1 << 22

// GAS is how much a benchmark call is allowed to spend. It is off rather than
// generous, because jm:wasm's Opts.gas arms wasm3's metering, and a benchmark
// of an instrumented build is a benchmark of the instrumentation.
GAS :: 0

main :: proc() {
	files: [dynamic]string
	func := "run"
	n := 0
	as_json := false
	invoke := false

	for arg in os.args[1:] {
		switch {
		case arg == "-h", arg == "--help":
			fmt.eprintln(USAGE)
			os.exit(2)
		case arg == "-json":
			as_json = true
		case arg == "-invoke":
			invoke = true
		case strings.has_prefix(arg, "-func="):
			func = arg[len("-func="):]
		case strings.has_prefix(arg, "-n="):
			parsed, ok := strconv.parse_int(arg[len("-n="):])
			if !ok || parsed <= 0 {
				fmt.eprintfln("wasm-bench: -n= needs work to do, got %s", arg)
				os.exit(2)
			}
			n = parsed
		case strings.has_prefix(arg, "-"):
			fmt.eprintfln("wasm-bench: unknown flag %s", arg)
			fmt.eprintln(USAGE)
			os.exit(2)
		case:
			append(&files, ..expand(arg))
		}
	}
	if len(files) == 0 {
		fmt.eprintln(USAGE)
		os.exit(2)
	}
	slice.sort(files[:])

	if invoke {
		// One call, one line, nothing timed here: whoever asked for this is
		// timing the process.
		for path in files {
			fmt.println(invoke_once(path, func, i32(max(n, 1))))
		}
		return
	}

	results := make([dynamic]Result)
	for path in files {
		append(&results, measure(path, func, n))
	}
	if as_json {
		print_json(results[:])
		return
	}
	print_table(results[:])
}

// expand turns a directory into the .wasm files in it, so a caller can name
// the workload directory rather than every module in it. A file is itself.
expand :: proc(path: string) -> []string {
	info, err := os.stat(path, context.allocator)
	if err != nil || info.type != .Directory {
		return slice.clone([]string{path})
	}
	entries, rerr := os.read_directory_by_path(path, -1, context.allocator)
	if rerr != nil {
		return nil
	}
	out := make([dynamic]string)
	for e in entries {
		if strings.has_suffix(e.name, ".wasm") {
			joined, _ := filepath.join({path, e.name}, context.allocator)
			append(&out, joined)
		}
	}
	return out[:]
}

// measure runs every measurement for one module. A fresh Vm is made for each
// one, so nothing a previous measurement compiled is still warm.
measure :: proc(path: string, func: string, n: int) -> Result {
	module, rerr := os.read_entire_file_from_path(path, context.allocator)
	if rerr != nil {
		fmt.eprintfln("wasm-bench: cannot read %s", path)
		os.exit(1)
	}
	out := Result {
		name  = strings.trim_suffix(filepath.base(path), ".wasm"),
		path  = path,
		bytes = len(module),
		n     = n,
	}

	// load: parse and instantiate, with nothing run.
	out.load = best(proc(m: Measurement) {
		vm, _ := wasm.open({gas = GAS})
		defer wasm.close(&vm)
		_, _ = wasm.load(vm, m.module)
	}, module, func, 0)

	// first: load, then the first call, which is where the body is compiled.
	// The load is subtracted, so what is left is the compile and the call.
	first_total := best(proc(m: Measurement) {
		vm, _ := wasm.open({gas = GAS})
		defer wasm.close(&vm)
		mod, err := wasm.load(vm, m.module)
		if err != nil {
			return
		}
		fn, ferr := wasm.find(mod, m.func)
		if ferr != nil {
			return
		}
		_, _ = wasm.call(fn, i32(0))
	}, module, func, 0)
	out.first = max(first_total - out.load, 0)

	// The rest run against one warm module, because that is what a program
	// that calls into a guest more than once actually has.
	vm, verr := wasm.open({gas = GAS})
	if verr != nil {
		fmt.eprintfln("wasm-bench: %s: %v", path, verr)
		os.exit(1)
	}
	defer wasm.close(&vm)
	mod, lerr := wasm.load(vm, module)
	if lerr != nil {
		fmt.eprintfln("wasm-bench: %s: %v", path, lerr)
		os.exit(1)
	}
	fn, ferr := wasm.find(mod, func)
	if ferr != nil {
		fmt.eprintfln("wasm-bench: %s: no export called %s", path, func)
		os.exit(1)
	}

	// call: the crossing with no work behind it.
	out.call = fastest_call(fn, 0, 1000)

	// Without an n on the command line, find one that runs long enough to
	// measure. Every workload scales linearly in its argument but they do
	// wildly different amounts of work per unit, so one n across all of them
	// would leave some too short to time and others running for seconds.
	size := n
	if size == 0 {
		size = 1
		for size < MAX_N {
			if fastest_call(fn, i32(size), 1) >= TARGET_NS {
				break
			}
			size *= 2
		}
	}
	out.n = size

	// run(n) and run(2n), warm.
	_, _ = wasm.call(fn, i32(size))
	out.run = fastest_call(fn, i32(size), 1)
	out.run2 = fastest_call(fn, i32(2 * size), 1)
	out.work = out.run2 - out.run

	if res, err := wasm.call(fn, i32(size)); err == nil && len(res) == 1 {
		#partial switch v in res[0] {
		case i32:
			out.checksum = i64(v)
		case i64:
			out.checksum = v
		}
	}
	return out
}

// Measurement is what best hands the procedure it times. A closure would
// carry this implicitly; Odin has none, so it is passed.
Measurement :: struct {
	module: []byte,
	func:   string,
	n:      int,
}

// best runs body REPS times and returns the fastest, in nanoseconds.
best :: proc(body: proc(m: Measurement), module: []byte, func: string, n: int) -> f64 {
	m := Measurement {
		module = module,
		func   = func,
		n      = n,
	}
	lowest := max(f64)
	for _ in 0 ..< REPS {
		start := time.tick_now()
		body(m)
		took := f64(time.duration_nanoseconds(time.tick_since(start)))
		lowest = min(lowest, took)
	}
	return lowest
}

// fastest_call times calls of an already warm function and returns the
// fastest nanoseconds per call.
fastest_call :: proc(fn: wasm.Func, arg: i32, per_round: int) -> f64 {
	lowest := max(f64)
	for _ in 0 ..< REPS {
		start := time.tick_now()
		for _ in 0 ..< per_round {
			_, _ = wasm.call(fn, arg)
		}
		took := f64(time.duration_nanoseconds(time.tick_since(start))) / f64(per_round)
		lowest = min(lowest, took)
	}
	return lowest
}

// invoke_once is the protocol an external timer drives: load, call, print.
invoke_once :: proc(path: string, func: string, n: i32) -> i64 {
	module, rerr := os.read_entire_file_from_path(path, context.allocator)
	if rerr != nil {
		fmt.eprintfln("wasm-bench: cannot read %s", path)
		os.exit(1)
	}
	vm, verr := wasm.open({gas = GAS})
	if verr != nil {
		fmt.eprintfln("wasm-bench: %v", verr)
		os.exit(1)
	}
	defer wasm.close(&vm)
	mod, lerr := wasm.load(vm, module)
	if lerr != nil {
		fmt.eprintfln("wasm-bench: %v", lerr)
		os.exit(1)
	}
	fn, ferr := wasm.find(mod, func)
	if ferr != nil {
		fmt.eprintfln("wasm-bench: no export called %s", func)
		os.exit(1)
	}
	res, cerr := wasm.call(fn, n)
	if cerr != nil {
		fmt.eprintfln("wasm-bench: %v", cerr)
		os.exit(1)
	}
	if len(res) == 0 {
		return 0
	}
	#partial switch v in res[0] {
	case i32:
		return i64(v)
	case i64:
		return v
	}
	return 0
}

print_table :: proc(results: []Result) {
	fmt.printfln(
		"%-12s %8s %10s %10s %10s %12s %12s %12s",
		"module",
		"bytes",
		"load",
		"first",
		"call",
		"run(n)",
		"run(2n)",
		"work",
	)
	for r in results {
		fmt.printfln(
			"%-12s %8s %10s %10s %10s %12s %12s %12s   n=%d checksum=%d",
			r.name,
			fmt.tprintf("%d", r.bytes),
			span(r.load),
			span(r.first),
			span(r.call),
			span(r.run),
			span(r.run2),
			span(r.work),
			r.n,
			r.checksum,
		)
	}
}

print_json :: proc(results: []Result) {
	fmt.println("[")
	for r, i in results {
		fmt.printfln(
			`  {{"engine": "jm:wasm", "module": "%s", "bytes": %d, "n": %d, "load_ns": %.0f, "first_ns": %.0f, "call_ns": %.1f, "run_ns": %.0f, "run2_ns": %.0f, "work_ns": %.0f, "checksum": %d}}%s`,
			r.name,
			r.bytes,
			r.n,
			r.load,
			r.first,
			r.call,
			r.run,
			r.run2,
			r.work,
			r.checksum,
			i == len(results) - 1 ? "" : ",",
		)
	}
	fmt.println("]")
}

// span prints a duration in whatever unit keeps it readable.
span :: proc(ns: f64) -> string {
	switch {
	case ns < 1_000:
		return fmt.tprintf("%.0fns", ns)
	case ns < 1_000_000:
		return fmt.tprintf("%.1fµs", ns / 1_000)
	case ns < 1_000_000_000:
		return fmt.tprintf("%.2fms", ns / 1_000_000)
	}
	return fmt.tprintf("%.3fs", ns / 1_000_000_000)
}

USAGE :: `usage: wasm-bench [-func=run] [-n=N] [-json] [-invoke] module.wasm...

Each module exports run(i32) -> i32: the argument scales the work and the
result is a checksum. Reported per module, fastest of five:

  load     parse and instantiate
  first    the first call, less the load: wasm3 compiles a body on its first
  call     run(0), the crossing with no work behind it
  run(n)   the workload, warm
  work     run(2n) - run(n), the workload with every constant subtracted out

work is what compares across engines. -invoke calls run(n) once and prints the
result, for a script timing this process against another engine's CLI.`
