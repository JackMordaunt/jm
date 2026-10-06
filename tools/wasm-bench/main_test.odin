package main

import "core:os"
import "core:strings"
import "core:testing"

import "jm:wasm"

// Paths are relative to the repository root, which is where `just test` runs
// from, the same as the command line in docs/wasm.md.
//
// The committed workloads are the benchmark: a corrupted one, or a rebuild
// from a changed source, would move every number in docs/wasm.md without
// anything saying so. Each one is run here for its checksum, which is the
// same value every engine in that table returned.
@(test)
the_workloads_are_the_ones_measured :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	known := []struct {
		path:     string,
		n:        int,
		checksum: i64,
	} {
		{"tools/wasm-bench/workloads/fib.wasm", 7, 1725788206},
		{"tools/wasm-bench/workloads/mandel.wasm", 7, 323197},
		{"tools/wasm-bench/workloads/memsum.wasm", 7, 233570304},
		{"tools/wasm-bench/workloads/sortbench.wasm", 7, 117431476},
	}
	for w in known {
		testing.expect_value(t, invoke_once(w.path, "run", i32(w.n)), w.checksum)
	}
}

// A run of the same module at twice the size does about twice the work, which
// is the assumption the whole `work` column rests on: if a workload did not
// scale linearly in its argument, subtracting two runs would leave something
// that is not the work.
//
// The work is counted rather than timed. wasm3's gas meter charges every
// instruction a fixed cost, so the gas a call spends is a step count that
// nothing else on the machine can move. Timed by the wall clock, as this test
// once was, run(2n)/run(n) for sortbench ranged from 0.35 to 16 beside sixteen
// busy processes on eight cores: a call preempted mid-run carries the wait in
// its time, and the fastest of five consecutive calls is no defence when the
// load outlasts all five.
@(test)
work_scales_with_the_argument :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	for path in WORKLOADS {
		one, two := gas_for(t, path, 7), gas_for(t, path, 14)
		testing.expectf(t, one > 0, "%s: run(7) has to spend gas", path)
		// Not exactly 2: the count is exact, but a workload's cost per unit
		// is not quite constant. sortbench's shell sort does more or less
		// work as its data changes (2.10 at these sizes) and fib's 2.07.
		ratio := two / one
		testing.expectf(
			t,
			ratio > 1.8 && ratio < 2.2,
			"%s: gas for run(14)/run(7) was %.3f",
			path,
			ratio,
		)
	}
	// measure still has to time something, but on a shared machine its two
	// timings are not compared: only the count above can be.
	r := measure("tools/wasm-bench/workloads/sortbench.wasm", "run", 2)
	testing.expect(t, r.run > 0 && r.run2 > 0, "a run has to take measurable time")
}

WORKLOADS := []string {
	"tools/wasm-bench/workloads/fib.wasm",
	"tools/wasm-bench/workloads/mandel.wasm",
	"tools/wasm-bench/workloads/memsum.wasm",
	"tools/wasm-bench/workloads/sortbench.wasm",
}

// gas_for is the gas one warm call of run(n) spends, in a runtime metered from
// the start so that every instruction is charged.
gas_for :: proc(t: ^testing.T, path: string, n: i32) -> f64 {
	module, rerr := os.read_entire_file_from_path(path, context.allocator)
	if !testing.expectf(t, rerr == nil, "cannot read %s", path) {
		return 0
	}
	vm, verr := wasm.open({gas = 1e15})
	if !testing.expectf(t, verr == nil, "%s: %v", path, verr) {
		return 0
	}
	defer wasm.close(&vm)
	mod, lerr := wasm.load(vm, module)
	fn, ferr := wasm.find(mod, "run")
	if !testing.expectf(t, lerr == nil && ferr == nil, "%s: %v %v", path, lerr, ferr) {
		return 0
	}
	// The first call compiles the body; charge only the call that is measured.
	_, _ = wasm.call(fn, i32(0))
	before := wasm.gas_used(vm)
	_, cerr := wasm.call(fn, n)
	testing.expectf(t, cerr == nil, "%s: run(%d): %v", path, n, cerr)
	return wasm.gas_used(vm) - before
}

// expand is what lets `just bench` name the workload directory rather than
// every file in it.
@(test)
a_directory_expands_to_its_modules :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	found := expand("tools/wasm-bench/workloads")
	testing.expect_value(t, len(found), 4)
	for f in found {
		testing.expect(t, strings.has_suffix(f, ".wasm"), f)
	}
	// A file is itself, so a caller can still name one module.
	one := expand("tools/wasm-bench/workloads/fib.wasm")
	testing.expect_value(t, len(one), 1)
	testing.expect_value(t, one[0], "tools/wasm-bench/workloads/fib.wasm")
}

@(test)
a_duration_reads_in_its_own_unit :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	testing.expect_value(t, span(940), "940ns")
	testing.expect_value(t, span(1_500), "1.5µs")
	testing.expect_value(t, span(2_500_000), "2.50ms")
	testing.expect_value(t, span(3_000_000_000), "3.000s")
}
