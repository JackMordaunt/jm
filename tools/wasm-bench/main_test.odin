package main

import "core:strings"
import "core:testing"

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
@(test)
work_scales_with_the_argument :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	r := measure("tools/wasm-bench/workloads/sortbench.wasm", "run", 2)
	testing.expect(t, r.run > 0, "a run has to take measurable time")
	testing.expect(t, r.work > 0, "run(2n) has to cost more than run(n)")
	// Wide bounds: this is a timing test on a shared machine, and the claim
	// is only that doubling the argument doubles the work, not that the
	// clock is quiet.
	ratio := r.run2 / r.run
	testing.expectf(t, ratio > 1.5 && ratio < 2.5, "run(2n)/run(n) was %.2f", ratio)
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
