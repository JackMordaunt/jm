# jm — Odin for scripts

A collection of small packages and one runner that make Odin comfortable for
the scripts Python and bash usually get. Everything builds on `core:`. The
only system library is libcurl through `vendor:curl`; SQLite is vendored and
linked statically, so a script that uses it still installs nothing.

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
just sqlite    compile the vendored SQLite  just clean
just example   run examples/hello.odin      just fuzz      30s of fuzzing
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
just fuzz "-corpus=build/corpus"      keep failures and replay them first
just fuzz-asan                        the same under AddressSanitizer
```

`just test` runs a few hundred cases of each suite on fixed seeds.

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
  and a damaged recursive CTE returns rows for ever. A suite supplies
  `cancel`; without one there is no deadline, which is the case for `jm:tar`,
  whose parser is a loop with nothing to interrupt.

One trap the sqlite3 suite exists to catch: its properties read every row
before comparing any of them. Comparing inside the loop passes even when a
column read hands back SQLite's memory instead of a copy, because the bytes
have not been reused yet. Deleting the clone from `sqlite3.text` leaves the
example-based tests green and fails one case in three here.

### What it found

Wiring `jm:tar` up as the second suite turned up two ways to crash the parser
on a malformed archive, both now fixed and both with regression tests in
`tar/tar_test.odin`:

- A size field in the base-256 form can name a number larger than an `int`
  holds. The shift wrapped, the size came back negative, and `read` sliced
  the archive backwards.
- A pax record whose claimed length did not reach past its own length field
  made `read` slice backwards too. `"1 "` was enough.
