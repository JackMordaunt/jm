/*
jm-fuzz runs a jm:fuzz suite for as long as it is asked to and reports what
did not hold.

	jm-fuzz                        every suite, a thousand cases each
	jm-fuzz sqlite3                one suite
	jm-fuzz tar -for=30s           as many as fit in thirty seconds
	jm-fuzz pg_query -isolate      a child process per case, for the ones that crash
	jm-fuzz -iters=1000000         a million cases
	jm-fuzz sqlite3 -seed=12345    replay a reported seed exactly
	jm-fuzz -corpus=build/corpus   keep failures, and replay them first
	jm-fuzz -isolate               a child process per case
	jm-fuzz -stop                  stop at the first failure
	jm-fuzz -no-shrink             report the case as found, unshrunk

The exit status is 0 when every property held and 1 when one did not, so it
drops into a pipeline. A failure prints the seed to replay it with, and how
much shrinking cut the case down.

With -corpus, the case about to run is written out before it runs, so a
property that takes the process down leaves the input that did it on disk.
The next run replays it first.

Build it with -sanitize:address to put the work under a sanitizer as well;
`just fuzz-asan` does that.
*/
package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"

import harness "jm:fuzz"
import git_fuzz "jm:git/fuzz"
import http_fuzz "jm:http/fuzz"
import pg_query_fuzz "jm:pg_query/fuzz"
import pq_fuzz "jm:pq/fuzz"
import sqlite3_fuzz "jm:sqlite3/fuzz"
import stream_fuzz "jm:stream/fuzz"
import tar_fuzz "jm:tar/fuzz"
import render_fuzz "jm:ui/render/fuzz"
import wasm_fuzz "jm:wasm/fuzz"
import zstd_fuzz "jm:zstd/fuzz"

// Runner is a suite under a name, already given its subject type. A Suite is
// parametric, so the suites cannot sit in one slice; the run procedures can.
Runner :: struct {
	name:   string,
	// Where this suite keeps its regressions when -corpus says nothing else.
	corpus: string,
	run:    proc(opts: harness.Opts, allocator := context.allocator) -> harness.Report,
}

runners := []Runner {
	{"sqlite3", sqlite3_fuzz.CORPUS, sqlite3_fuzz.run},
	{"tar", tar_fuzz.CORPUS, tar_fuzz.run},
	{"wasm", wasm_fuzz.CORPUS, wasm_fuzz.run},
	{"pg_query", pg_query_fuzz.CORPUS, pg_query_fuzz.run},
	{"pq", pq_fuzz.CORPUS, pq_fuzz.run},
	{"ui_render", render_fuzz.CORPUS, render_fuzz.run},
	{"git", git_fuzz.CORPUS, git_fuzz.run},
	{"zstd", zstd_fuzz.CORPUS, zstd_fuzz.run},
	{"stream", stream_fuzz.CORPUS, stream_fuzz.run},
	{"http_wire", http_fuzz.WIRE_CORPUS, http_fuzz.run_wire},
	{"http_model", http_fuzz.MODEL_CORPUS, http_fuzz.run_model},
}

main :: proc() {
	opts := harness.Opts {
		log = note,
	}
	corpus_root := ""
	no_corpus := false
	wanted: [dynamic]string
	for arg in os.args[1:] {
		switch {
		case arg == "-h", arg == "--help":
			fmt.eprintln(USAGE)
			os.exit(2)
		case arg == "-quiet":
			opts.log = nil
		case arg == "-stop":
			opts.stop_on_first = true
		case arg == "-no-shrink":
			opts.shrink = -1
		case arg == "-isolate":
			opts.isolate = true
		case strings.has_prefix(arg, "-seed="):
			opts.seed = u64(number(arg, "-seed="))
		case strings.has_prefix(arg, "-iters="):
			opts.iterations = number(arg, "-iters=")
		case strings.has_prefix(arg, "-entropy="):
			opts.entropy = number(arg, "-entropy=")
		case strings.has_prefix(arg, "-shrink="):
			opts.shrink = number(arg, "-shrink=")
		case arg == "-no-corpus":
			no_corpus = true
		case strings.has_prefix(arg, "-corpus="):
			corpus_root = arg[len("-corpus="):]
		case strings.has_prefix(arg, "-for="):
			opts.duration = span(arg[len("-for="):])
		case strings.has_prefix(arg, "-"):
			fmt.eprintfln("jm-fuzz: unknown flag %s", arg)
			fmt.eprintln(USAGE)
			os.exit(2)
		case:
			append(&wanted, arg)
		}
	}
	// A run bounded only by time needs no iteration ceiling to stop at.
	if opts.duration > 0 && opts.iterations == 0 {
		opts.iterations = max(int)
	}

	chosen := pick(wanted[:])
	failed := false
	for r in chosen {
		// Each suite keeps its cases apart, so replaying one does not hand
		// the other input it cannot read.
		suite_opts := opts
		switch {
		case no_corpus:
			suite_opts.corpus_dir = ""
		case corpus_root != "":
			suite_opts.corpus_dir = fmt.tprintf("%s/%s", corpus_root, r.name)
		case:
			suite_opts.corpus_dir = r.corpus
		}
		report := r.run(suite_opts)
		fmt.printfln(
			"%s: %d cases in %v, seed %d, %d replayed, %d failures",
			r.name,
			report.iterations,
			time.duration_round(report.elapsed, time.Millisecond),
			report.seed,
			report.replayed,
			len(report.failures),
		)
		for f in report.failures {
			fmt.eprintfln("  %s/%s [%v]: %s", r.name, f.property, f.outcome, f.detail)
			fmt.eprintfln(
				"    case %d, %d bytes of entropy%s%s",
				f.iteration,
				len(f.entropy),
				f.shrunk_by > 0 ? fmt.tprintf(" (shrunk by %d)", f.shrunk_by) : "",
				f.saved != "" ? fmt.tprintf(", saved as %s", f.saved) : "",
			)
		}
		if len(report.failures) > 0 {
			failed = true
			fmt.eprintfln("  replay with: jm-fuzz %s -seed=%d", r.name, report.seed)
		}
	}
	if failed {
		os.exit(1)
	}
}

USAGE :: `usage: jm-fuzz [suite...] [-seed=N] [-iters=N] [-for=30s] [-entropy=N]
               [-shrink=N] [-no-shrink] [-corpus=DIR] [-no-corpus]
               [-isolate] [-stop] [-quiet]

suites: sqlite3, tar, wasm, pg_query, pq, ui_render, git, zstd, stream, http_wire,
http_model. With none named, every suite runs.
Each suite keeps its regressions beside its source and replays them first;
-corpus=DIR uses DIR/<suite> instead, and -no-corpus skips them. pq needs
initdb and pg_ctl to bring up a throwaway server; without them it says so and
runs no cases.

-isolate runs each case in a child process. It is far slower, and nothing a
case does can end the run: a crash or a hang is reported like any other
failure, with the case that caused it.`

// pick resolves the suite names on the command line, or every suite when
// none were named. An unknown name is an error rather than an empty run that
// would look like a clean one.
pick :: proc(names: []string) -> []Runner {
	if len(names) == 0 {
		return runners
	}
	out := make([dynamic]Runner, context.temp_allocator)
	for n in names {
		found := false
		for r in runners {
			if r.name == n {
				append(&out, r)
				found = true
			}
		}
		if !found {
			fmt.eprintfln("jm-fuzz: no suite called %s", n)
			fmt.eprintln(USAGE)
			os.exit(2)
		}
	}
	return out[:]
}

// number reads the digits after a flag's prefix, or gives up loudly: a
// mistyped bound that silently became zero would report a clean run.
number :: proc(arg, prefix: string) -> int {
	v, ok := strconv.parse_int(arg[len(prefix):])
	if !ok {
		fmt.eprintfln("jm-fuzz: %s needs a whole number, got %s", prefix, arg)
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
		fmt.eprintfln("jm-fuzz: -for needs a duration like 30s, got %s", s)
		os.exit(2)
	}
	return time.Duration(v) * unit
}

// note is what a run calls as it goes, so a long run says something before
// it finishes.
note :: proc(format: string, args: ..any) {
	fmt.eprintfln(format, ..args)
}
