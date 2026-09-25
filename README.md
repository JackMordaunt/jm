# jm — Odin for scripts

A collection of small packages and one runner that make Odin comfortable for
the scripts Python and bash usually get. Everything builds on `core:`. The
only system library is libcurl through `vendor:curl`; SQLite and the wasm3
interpreter are vendored and linked statically, so a script that uses either
still installs nothing.

```odin
#!/usr/bin/env odin-run
package main

import "core:fmt"
import "jm:prelude"
import "jm:sh"
import "jm:path"

must :: prelude.must
die :: prelude.die

main :: proc() {
	context = prelude.init()
	branch := must(sh.out("git rev-parse --abbrev-ref HEAD"))
	for f in must(path.walk(".")) {
		fmt.println(branch, f)
	}
}
```

`chmod +x` and run it. The first run compiles; later runs start the cached
binary.

## Packages

| Package   | Job |
|-----------|-----|
| `prelude` | `must`, `die`, `env`, `args`; arena or debug allocator; logfmt log file plus `deaths.log` audit trail |
| `sh`      | `out`, `lines`, `ok`, `run`, `capture` through the shell; `exec`, `exec_run` with argv; `which`, `quote`, `error` |
| `http`    | `get`, `post`, `post_json`, `get_json`, `download`, `request` over libcurl |
| `path`    | `expand`, `join`, `mkdirs`, `read`, `read_lines`, `write`, `append_file`, `list`, `walk`, `temp_dir`, `same`, per-user app dirs |
| `timefmt` | strftime `format`, `local`, `parse`; `iso`, `stamp`, `date`, `duration` |
| `debug`   | guard-byte debug allocator (origin: sonar, which now imports this copy) |
| `flow`    | `width`, `each`, `manage`: lock-free worker pools where each worker owns one state slot and the caller merges afterwards |
| `tar`     | `read`, `extract`: `git archive` output without a tar program |
| `sqlite3` | `open`, `exec`, `exec_args`, `query`/`next`, `prepare`, `transact` over a statically linked SQLite |
| `wasm`    | `open`, `load`, `find`, `call`, `link`, `run`: WebAssembly through a statically linked wasm3 |
| `fuzz`    | property fuzzing: an entropy `Source`, generators, format-agnostic `damage`, shrinking, a corpus, a per-case deadline |
| `sqlite3/fuzz` | the `jm:sqlite3` suite for `jm:fuzz` |
| `tar/fuzz` | the `jm:tar` suite for `jm:fuzz` |

`tools/odin-run` is the runner. Every package reads on its own; the doc
comment at the top of each file is the reference.

## Conventions

- Scripts never free. `prelude.init` puts a growing arena in
  `context.allocator`; the exit reclaims it. `ODIN_SCRIPT_DEBUG=1` swaps in
  the debug allocator, which reports overflow, double free and write after
  free at exit.
- Anything that can fail returns `(value, ok)` or `(value, os.Error)` so
  `must(...)` wraps it. `die` writes the message and the call site to the
  script log, to stderr, and to one shared `deaths.log`.
- `prelude` never writes to stdout. Stdout is the script's data channel.
- Logs: `<log dir>/odin/<name>/<name>.log`, rotated to `.1` at 8 MiB, and
  `<log dir>/odin/deaths.log`. The log dir is `~/.local/state` on Linux,
  `~/Library/Logs` on macOS and `%LOCALAPPDATA%` on Windows. `ODIN_LOG=debug`
  echoes everything to stderr; the default echoes warning and above.
- Platform splits live in `_unix.odin` / `_windows.odin` files. `just check`
  type-checks every package for `linux_amd64`, `darwin_arm64` and
  `windows_amd64` from one machine.

## Runner

```
odin-run script.odin [args...]   compile if stale, then run
odin-run -clean                  drop the cache
```

Cache key: script bytes and path, every `.odin` in the collection, the odin
binary, target and flags. `ODIN_RUN_FLAGS="-debug"` builds unoptimised;
`ODIN_RUN_VERBOSE=1` prints the build line. On Windows the shebang does
nothing; call `odin-run script.odin` or associate `.odin` with it. When
`vendor/curl/lib/libcurl.dll` exists under the Odin root it is copied beside
the cached binary.

## Recipes

```
just build     debug odin-run          just release   optimised odin-run
just test      all package tests       just check     3-target type-check
just install   odin-run -> ~/.local/bin (BINDIR overrides)
just sqlite    compile the vendored SQLite  just wasm      compile wasm3
just example   run examples/hello.odin      just fuzz      30s of fuzzing
just clean     drop build/ and both archives
```

`just install` bakes this checkout's path into the runner as the `jm`
collection root; `ODIN_RUN_COLLECTION` overrides it.

## SQLite

`sqlite3/vendor/` holds the SQLite **3.53.4** amalgamation (`sqlite3.c` and
`sqlite3.h`, source id `bf7c7f30031888f4e796e429ab3978879485813aaca6f641c7b33e4e09459bcc`),
taken from sqlite.org and verified against the SHA3-256 that page publishes.
SQLite is public domain, so vendoring it carries no licence obligation.

`just sqlite` compiles it once into `sqlite3/lib/sqlite3.a`, which is
gitignored and rebuilt when the amalgamation changes. `foreign import`
resolves that archive relative to the package directory. `odin check` never
opens a foreign import, so `just check` still type-checks all three targets on
one machine with no archive built.

The compile options are sqlite.org's recommended set, with three deliberate
departures, all of them in the justfile:

- `SQLITE_THREADSAFE=1`, not the recommended `0`. `jm:flow` exists, and a
  connection per worker has to be safe.
- `SQLITE_OMIT_AUTOINIT` is **not** set, though it is recommended. With it, any
  call made before `sqlite3_initialize` is a segfault rather than an error.
- `SQLITE_ENABLE_FTS5` is added, for a full-text index, and
  `SQLITE_OMIT_LOAD_EXTENSION` keeps the link from needing libdl.

One trap is worth knowing even though the package handles it: the bytes behind
a text or blob column are freed on the next `step`, and SQLite reuses its own
pool rather than returning them to libc, so reading a stale pointer yields the
*next* row's data instead of crashing. AddressSanitizer cannot see it. That is
why `text` and `blob` clone into the allocator the query was given.

## WebAssembly

`wasm/vendor/` holds **wasm3 0.9.1** (commit `c036c43`), the interpreter's
`source/` tree minus the two files this build does not compile: the uvwasi
backend, which needs libuv, and the meta-WASI one, which is for running wasm3
inside wasm3. wasm3 is MIT, and `wasm/vendor/LICENSE` is its copy.

`just wasm` compiles it once into `wasm/lib/wasm3.a`, which is gitignored and
rebuilt when any vendored source changes. As with SQLite, `foreign import`
resolves that archive relative to the package directory, and `odin check`
never opens it, so `just check` still type-checks all three targets on one
machine with no archive built.

The build takes wasm3's defaults, which already have bytecode validation and
gas metering on, and adds one option: `d_m3HasWASI`, without which `run` has
no `_start` to call. That is an interpreter, not a JIT — several times slower
than Wasmtime on arithmetic, and in exchange it is 550 KB of portable C with
nothing to install and no executable pages to allocate at runtime.

One limit is worth knowing before reaching for `jm:flow`: wasm3 is not
thread-safe, and not merely per runtime. Eight threads, each with its own
environment, runtime and copy of a two-instruction module, still produce
spurious traps — a stack overflow, an out of bounds access — roughly five
times in sixteen hundred calls. That was reproduced in C against this archive,
with no Odin involved, so it is wasm3's own state and not the binding's.
`jm:wasm` is therefore a one-thread package; `interrupt` is the only call
meant to cross a thread, because it does nothing but set a flag. `just test`
runs this package's tests with the test runner on a single thread for the
same reason.

## Fuzzing

`jm:fuzz` runs properties against generated input and tells you the smallest
case that broke one. A property is handed a subject and a `Source`, draws
whatever input it wants, and says whether the promise held. The package does
the rest: seeding, budgets, an arena per case, shrinking, the corpus, and a
deadline on a case that will not finish.

```
just fuzz                             30 seconds of every suite
just fuzz "tar -for=5m"               one suite, longer
just fuzz "sqlite3 -seed=12345"       replay a reported seed exactly
just fuzz "-corpus=DIR"               keep failures somewhere else
just fuzz-isolate                     five minutes, a child process per case
just fuzz-asan                        the same under AddressSanitizer
```

Each suite keeps its regressions beside its source, in `<suite>/corpus`, and
replays them before generating anything. `just test` runs a few hundred cases
of each suite on fixed seeds and replays those corpora, so a bug found once by
fuzzing stays found without anyone running the fuzzer again.

A case's randomness is **a finite byte string**, and every generator draws
from it. That one decision is what the rest rests on: a case is a pure
function of its bytes, so it replays exactly, it can be written to disk as a
regression, and it can be shrunk by simplifying the bytes and running it
again. Generators are written so a zero byte asks for the simplest value they
can give, which is what shrinking converges on.

Writing a suite means naming a subject, how to make and unmake one, how to
cancel work in flight, and the promises:

```odin
properties := []fuzz.Property(Sandbox){{"no_escape", no_escape}}

suite :: proc() -> fuzz.Suite(Sandbox) {
	return fuzz.Suite(Sandbox) {
		name = "tar", setup = open, teardown = shut, properties = properties,
	}
}
```

Three things in it were each put there by something that went wrong:

- **Shrinking**, because a failure arrived as an 80-byte blob when one byte
  was enough. A found case shrinks to its simplest form before it is
  reported.
- **A corpus**, because a bug found once should be a test from then on. With
  `-corpus`, the case about to run is also written out before it runs, so a
  property that takes the process down — a panic, a failed bounds check,
  anything the harness cannot catch — leaves the input that did it on disk.
  That is how the `jm:tar` crash below was captured.
- **A deadline**, because nothing in SQLite bounds how long a statement runs
  and a damaged recursive CTE returns rows for ever. In this process a suite
  has to supply `cancel` for that to work; `-isolate` lifts the restriction,
  below.

### Isolation

`-isolate` runs each case in a child process. The child is the same binary,
re-run with the case named in its environment, so a program that calls
`fuzz.run` is its own child with no extra wiring.

It costs a spawn per case. Measured with
`just fuzz "tar -for=5s -no-corpus"` against the same run with `-isolate`,
this machine does about 16,200 cases a second in process and 1,070 isolated
— fifteen times slower — which is why it is off by default. What it buys:

- **A crash is a result, not the end of the run.** A panic or a failed bounds
  check comes back as `Crashed`, carrying whatever the child wrote to stderr,
  and the next case starts from a clean process.
- **The deadline works for any subject.** A child is killed whether or not it
  cooperates, so a suite over a parser with no interruption point — `jm:tar`,
  whose loop has nothing to check — gets a deadline for free. No `cancel`
  needed.
- **Shrinking still applies**, so a crash shrinks to its smallest case like
  any other failure.

Use it for unattended runs. In process is the right default for the quick
pass that `just test` and a 30-second `just fuzz` do.

One trap the sqlite3 suite exists to catch: its properties read every row
before comparing any of them. Comparing inside the loop passes even when a
column read hands back SQLite's memory instead of a copy, because the bytes
have not been reused yet. Deleting the clone from `sqlite3.text` leaves the
example-based tests green and fails one case in three here.

### What it found

Wiring `jm:tar` up as the second suite turned up three ways to crash the
parser on a malformed archive, all now fixed, all with regression tests in
`tar/tar_test.odin`:

- A size field in the base-256 form can name a number larger than an `int`
  holds. The shift wrapped, the size came back negative, and `read` sliced
  the archive backwards.
- A pax record whose claimed length did not reach past its own length field
  made `read` slice backwards too. `"1 "` was enough.
- Guarding the size field was not enough on its own: `read` then adds the
  header's offset to it, and a size of `max(int)` made *that* wrap. The
  check has to be a subtraction. This one is also `tar/fuzz/corpus`'s first
  entry: the shape needs a dozen specific bytes, so the corpus rather than
  the fuzzer is what keeps it tested.
