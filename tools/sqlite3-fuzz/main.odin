/*
sqlite3-fuzz runs jm:sqlite3/fuzz for as long as it is asked to and reports
what did not hold.

	sqlite3-fuzz                      1000 cases from a seed off the clock
	sqlite3-fuzz -iters=1000000       a million cases
	sqlite3-fuzz -for=30s             as many as fit in thirty seconds
	sqlite3-fuzz -seed=12345          replay a reported seed exactly
	sqlite3-fuzz -quiet               only the summary

The exit status is 0 when every property held and 1 when one did not, so it
drops into a pipeline. A failure prints the seed to replay it with.

Build it with -sanitize:address to put the FFI boundary under a sanitizer as
well; `just fuzz asan=1` does that.
*/
package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"

import "jm:sqlite3/fuzz"

main :: proc() {
	opts := fuzz.Opts {
		log = report,
	}
	for arg in os.args[1:] {
		switch {
		case arg == "-h", arg == "--help":
			fmt.eprintln(USAGE)
			os.exit(2)
		case arg == "-quiet":
			opts.log = nil
		case arg == "-stop":
			opts.stop_on_first = true
		case strings.has_prefix(arg, "-seed="):
			opts.seed = u64(number(arg, "-seed="))
		case strings.has_prefix(arg, "-iters="):
			opts.iterations = number(arg, "-iters=")
		case strings.has_prefix(arg, "-for="):
			opts.duration = span(arg[len("-for="):])
		case:
			fmt.eprintfln("sqlite3-fuzz: unknown argument %s", arg)
			fmt.eprintln(USAGE)
			os.exit(2)
		}
	}
	// A run bounded only by time needs no iteration ceiling to stop at.
	if opts.duration > 0 && opts.iterations == 0 {
		opts.iterations = max(int)
	}

	report := fuzz.run(opts)
	fmt.printfln(
		"sqlite3-fuzz: %d iterations in %v, seed %d, %d failures",
		report.iterations,
		time.duration_round(report.elapsed, time.Millisecond),
		report.seed,
		len(report.failures),
	)
	if len(report.failures) == 0 {
		return
	}
	for f in report.failures {
		fmt.eprintfln("  %s at iteration %d: %s", f.property, f.iteration, f.detail)
	}
	fmt.eprintfln("replay with: sqlite3-fuzz -seed=%d", report.failures[0].seed)
	os.exit(1)
}

USAGE :: `usage: sqlite3-fuzz [-seed=N] [-iters=N] [-for=30s] [-stop] [-quiet]`

// number reads the digits after a flag's prefix, or gives up loudly: a
// mistyped bound that silently became zero would report a clean run.
number :: proc(arg, prefix: string) -> int {
	v, ok := strconv.parse_int(arg[len(prefix):])
	if !ok || v < 0 {
		fmt.eprintfln("sqlite3-fuzz: %s needs a whole number, got %s", prefix, arg)
		os.exit(2)
	}
	return v
}

// span reads a duration written as 30s, 5m or 250ms.
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
	v, ok := strconv.parse_int(digits)
	if !ok || v < 0 {
		fmt.eprintfln("sqlite3-fuzz: -for needs a duration like 30s, got %s", s)
		os.exit(2)
	}
	return time.Duration(v) * unit
}

// report is what the run calls as it goes, so a long run says something
// before it finishes.
report :: proc(format: string, args: ..any) {
	fmt.eprintfln(format, ..args)
}
