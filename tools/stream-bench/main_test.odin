package main

import "core:testing"
import "core:time"

// Every benchmark runs and agrees with the loop on its checksum, on one
// thread and on a small pool.
@(test)
benchmarks_agree :: proc(t: ^testing.T) {
	items := make([]int, 10_000)
	defer delete(items)
	for &x, ii in items {
		x = ii
	}
	want := bench_loop(items, 0)
	for b in benches {
		for threads in ([]int{0, 2}) {
			if b.flat && threads > 0 {
				continue
			}
			got := b.run(items, threads)
			n := len(items)
			switch b.name {
			case "fanout8":
				testing.expectf(t, got == want * 8, "%s: %d, loop says %d x 8", b.name, got, want)
			case "chain4", "cap1", "cap256":
				testing.expectf(t, got == want + 3 * n, "%s on %d threads: %d, loop says %d", b.name, threads, got, want + 3 * n)
			case "chain16":
				testing.expectf(t, got == want + 15 * n, "%s on %d threads: %d, loop says %d", b.name, threads, got, want + 15 * n)
			case "zip2":
				// Both halves summed, without the increment: the items' own sum.
				testing.expectf(t, got == want - n, "%s on %d threads: %d, items sum to %d", b.name, threads, got, want - n)
			case "latency16":
				testing.expectf(t, got == n, "%s on %d threads: counted %d of %d", b.name, threads, got, n)
			case "merge8":
				// Eight parts of n/8 each, incremented, so the loop's own answer.
				testing.expectf(t, got == want, "%s on %d threads: %d, loop says %d", b.name, threads, got, want)
			case:
				testing.expectf(t, got == want, "%s on %d threads: %d, loop says %d", b.name, threads, got, want)
			}
		}
	}
}

@(test)
stress_runs_and_accounts :: proc(t: ^testing.T) {
	ok := stress({nodes = 60, sources = 4, items = 500, threads = 3, cap = 2, for_ = time.Second, runs = 3, seed = 1})
	testing.expect(t, ok)
}
