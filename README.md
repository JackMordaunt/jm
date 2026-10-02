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

## Setup

`./setup.sh` installs what the recipes need and then reports what is still
missing; `./setup.sh --check` only reports, and exits 1 when something
required is absent. It uses Homebrew on macOS, apt, dnf or pacman on Linux,
and winget or else scoop on Windows under Git Bash. A package that fails to
install is reported and the rest carry on. Odin is fetched from its GitHub
release at the version CI pins, and only when no `odin` is on `PATH`.

| Need | macOS | Linux | Windows |
|------|-------|-------|---------|
| Odin `dev-2026-09`, just 1.23+, git, cmake | yes | yes | yes |
| C toolchain | Xcode command line tools | cc, clang, make | MSVC Build Tools, clang-cl, ninja |
| libpq | `libpq` (keg-only; the justfile finds it) | libpq dev package | `libpq.lib` from PostgreSQL, via `LINKFLAGS` |
| SDL3 | `sdl3` | SDL3 dev package | ships with Odin |
| libcurl, mbedtls, zlib | system | dev packages | ships with Odin |
| Liberation Sans in `/usr/share/fonts/liberation` | — | render tests | — |
| `initdb`, `pg_ctl` (optional) | pq tests; they skip without | same | same |
| Selawik, Noto Sans (optional) | fluent kitchen | both kitchens | fluent kitchen |

Ubuntu 24.04 packages neither SDL3 nor a new enough just: the script fetches
just's own release, and SDL3 has to be built from source there.

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
| `zstd`    | `compress`, `decompress`, their `_stream` forms, and binary patches with `diff` and `patch`, over a statically linked zstd |
| `selfupdate` | `run`: a distributed binary checks a signed release and replaces itself, by patch, compressed asset or full download |
| `wasm`    | `open`, `load`, `find`, `call`, `link`, `run`: WebAssembly through a statically linked wasm3 |
| `ui/ops`  | the recorded drawing: geometry, colour, paint, shapes, glyph runs and the scene ops a ui proc emits into a `Scene`, with their wire form (`encode`) and text form (`dump`); everything above shares these types |
| `ui`      | immediate-mode UI: `ops.Scene` → `flatten` → draw and hit lists; layout, theme, widgets, a `Probe` that clicks and types without a window |
| `ui/render` | executes a `ui.Frame` on Blend2D (vendored binding in `ui/blend2d`), hands out a `ui/shape` shaper with Blend2D's line metrics, and `snapshot`s a `ui` proc straight to a PNG |
| `ui/shape` | text to glyph runs with kb_text_shape: OpenType shaping for complex scripts, normalisation, per-run direction, clusters as byte offsets |
| `ui/kb`   | the binding to kb_text_shape, vendored in `ui/kb/vendor` and statically linked |
| `ui/accesskit` | the binding to AccessKit's C library (prebuilt, `just accesskit`), and the tree it is fed from a frame's semantic nodes: what a screen reader hears |
| `ui/sdl`  | the SDL3 window and event loop for a `ui` app; `run_host` runs the same window against a subprocess instead of a local ui proc |
| `ui/ipc`  | length-prefixed frames over a pipe, and spawning a child process wired up for exactly that — the transport under `ui/sdl`'s host/subprocess split |
| `ui/child` | the subprocess half of that split: owns the Model, the ui proc, `Router` and `Layout`, and speaks `ui`'s wire format over its own stdin/stdout |
| `ui/diagram` | titled, accent-bordered groups of chips and arrows (solid or dashed) for an architecture diagram, over plain `ui` calls |
| `ui/design` | what every design system on `ui` shares: the interaction states and per-frame `Control`, per-corner geometry, text shaping in a line box, box-shadow layers drawn as exact Gaussian shadows, CSS easing, and a generic `Theme(Role, Context)` with axioms that `check` measures in every context (OKLab, APCA and WCAG metrics) |
| `ui/base` | the smallest design system on `ui`: a five-role palette bound light and dark as an instance of `ui/design`, checked by its axioms, and the plain widgets every page needs — label, text, divider, panel; a full system maps its scheme down to it |
| `ui/material` | Material 3 Expressive on `ui`: the colour scheme, type scale, shape, motion springs and state tokens generated from the m3e-kit (`tools/material`) into `ui/material/tokens`, Material Symbols icons as paths, and the components (buttons, text fields, selection controls, chips, cards, lists, navigation, app bars, tabs), each able to paint any spec state on demand |
| `ui/fluent` | Fluent 2 on `ui`: the five colour themes (web and Teams, light and dark, high contrast), type ramp, spacing, radii, strokes, shadows and motion generated from the fluent-kit (`tools/fluent`) into `ui/fluent/tokens`, with states read as separate tokens through a `design.Control` and colour changes eased over the kit's duration and curve |
| `ui/testutil` | `count_ops`: assertions a `ui` package's own tests and a downstream package's tests both want, without an import cycle |
| `pg_query` | `parse`, `split`, `is_utility`, `fingerprint`, `normalize`: PostgreSQL's own SQL parser, statically linked, with node types generated from its schema |
| `pq`      | `connect`, `exec`, `escape_literal`, `escape_identifier`, `identity`: a PostgreSQL client over the system libpq, the one dynamically linked library |
| `pq/testdb` | a throwaway PostgreSQL server on a Unix socket, for tests |
| `git`     | `open`, `init`, `clone`, `status`, `add`, `commit`, `log`, `remotes`, `fetch`, `push`, `pull`, `diff` over a statically linked libgit2, so a shipped program needs no git on the machine |
| `stream`  | non-blocking dataflow pipelines: typed operators over a DAG of nodes and bounded edges, run on one thread or a pool, with a clock, ports from other threads and a worker pool for blocking work |
| `stream/ring` | one-producer one-consumer ring of messages of one `Shape` (size, alignment, type), each end on its own cache line with a cached copy of the other's index, storage aligned to the shape; what a stream edge and inlet are built on |
| `stream/fuzz` | the `jm:stream` suite for `jm:fuzz`: random graphs against a sequential model, single-threaded with a drawn scheduler and on a pool |
| `fuzz`    | property fuzzing: an entropy `Source`, generators, format-agnostic `damage`, shrinking, a corpus, a per-case deadline |
| `sqlite3/fuzz` | the `jm:sqlite3` suite for `jm:fuzz` |
| `tar/fuzz` | the `jm:tar` suite for `jm:fuzz` |
| `wasm/fuzz` | the `jm:wasm` suite for `jm:fuzz`, with a small Wasm encoder to build cases from |
| `pg_query/fuzz` | the `jm:pg_query` suite for `jm:fuzz`, with a SQL generator to build cases from |
| `pq/fuzz` | the `jm:pq` suite for `jm:fuzz`, against the `pq/testdb` server |
| `ui/render/fuzz` | the `jm:ui/render` suite for `jm:fuzz`: composed frames checked against whole renders |
| `git/fuzz` | the `jm:git` suite for `jm:fuzz`: random operation sequences over two clones of a hub, held against a model that knows no merges |

`tools/odin-run` is the runner. `tools/mkpatch` makes the compressed asset
and the patches `jm:selfupdate` looks for, in a release's CI. Every package
reads on its own; the doc comment at the top of each file is the reference.

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
general      check    3-target type-check of every package and program
             test     every package's tests
             link     build every program into build/debug
             clean    drop build/ and every package's compiled C library
odin-run     build    debug odin-run         release  optimised odin-run
             install  odin-run -> ~/.local/bin (BINDIR overrides)
             example  run examples/hello.odin
sqlite3      sqlite   compile the vendored SQLite
wasm         wasm     compile wasm3          bench    time jm:wasm's workloads
             bench-build  rebuild the workloads from their C sources
pg_query     pg_query  compile the vendored libpg_query
             pg_query-gen  regenerate pg_query/nodes.odin from the vendored schema
git          libgit2  fetch and compile libgit2 into git/lib
fuzz         fuzz     30s of fuzzing         fuzz-isolate  a child process per case
             fuzz-asan  the same under AddressSanitizer
ui           blend2d  fetch and compile Blend2D into ui/blend2d/lib
             kb       compile the vendored kb_text_shape into ui/kb/lib
             accesskit  fetch AccessKit's prebuilt library into ui/accesskit/lib
             hot-counter-child  build the subprocess `just test`'s own host/child test spawns
             bench-ui  ms per frame for layout and the Blend2D executor
             hot-architecture  build the hot-reloaded architecture diagram
             text-lab  build and open the hot-reloaded text lab: scripts, bidi, emoji, carets
             text-png page=Scripts  render one text-lab page, whole, to build/
ui/material  material-kitchen  build and open the hot-reloaded M3 kitchen
             material-png page=Chips  render one M3 kitchen page to build/
             material-tokens  regenerate ui/material/tokens from the m3e-kit
             material-shapes  regenerate ui/material/shape_data.odin from the m3e-kit's morphs
             material-kit-{tokens,shapes,fetch,index,check,page}  maintain the m3e-kit in tools/material
ui/fluent    fluent-kitchen  build and open the hot-reloaded Fluent 2 kitchen
             fluent-png page=Button  render one Fluent kitchen page to build/
             fluent-fonts  fetch Selawik, the kitchen's stand-in for Segoe UI, into ~/.local/share/fonts
             fluent-tokens  regenerate ui/fluent/tokens from the fluent-kit
             fluent-icons  regenerate ui/fluent/icon_data.odin from the Fluent icons in tools/fluent/icons
             fluent-icons-fetch  fetch the icons icons.txt names at its pinned commit (or a ref given)
             fluent-kit-{tokens,fetch,index,check,page}  maintain the fluent-kit in tools/fluent
```

`just` alone lists the recipes in these sections: one per package or tool,
the recipe that compiles a package's C library in its section, and general
for what spans them all.

`just install` bakes this checkout's path into the runner as the `jm`
collection root; `ODIN_RUN_COLLECTION` overrides it.

`check`, `test` and `link` find their packages rather than read a list:
every directory of `.odin` files git sees, tracked or not but never
ignored, a `package main` directory being a program and one with an
`@(test)` proc a test package. `SKIP="pq tools/jm-fuzz"` leaves those
directories and everything under them out, as on a machine without libpq.
Packages run in parallel, except the `serial_tests` the justfile names.

GitHub Actions runs `just check`, then `just link test` on Linux, macOS
and Windows (`.github/workflows/test.yml`), building the vendored C libraries, libgit2
and Blend2D there the way the recipes do and caching the CMake builds. It
runs on a push to `main` or to any `ci/<name>` branch, so pushing a
throwaway `ci/` branch checks all three platforms during development;
`gh workflow run test.yml --ref <branch>` runs it on any other branch.
`ui/sdl` runs too: Linux builds SDL3 console-only, which is enough because
its tests drive a child process rather than open a window. `pq` runs on
all three, each runner having libpq and a PostgreSQL server.
`wasm-windows.yml` is the shorter loop for jm:wasm on Windows alone: wasm3
with clang-cl at two optimisation levels, the trap tests one process each,
and a faulting one rerun under cdb for its stack. The recipe's own cl
build of wasm3 does not compile; clang-cl is what Windows uses.


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

## zstd

`zstd/vendor/zstd.c` is zstd **1.5.7**'s single-file library, generated by
`build/single_file_libs/create_single_file_library.sh` from the release
tarball, whose SHA-256
(`eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3`) was
checked against the one the release publishes. `zstd.h`, `zstd_errors.h`,
`zdict.h` and `LICENSE` are copied beside it; zstd is dual BSD and GPLv2,
and jm takes it under BSD. The amalgamation holds compression, decompression
and the dictionary builder, without the legacy formats or assembly.

`just zstd` compiles it into `zstd/lib/zstd.a`, as `just sqlite` does for
SQLite. `ffi.odin` binds all of `zstd.h`'s stable API, `zdict.h`'s, and the
experimental `_advanced` constructors, which let the wrapper route zstd's
allocations through an Odin allocator.

A patch from `diff` is a zstd frame compressed with the old file as its
prefix, so `zstd -d --patch-from=old` applies one too. Between two brain-cli
release builds 15 commits apart (darwin-arm64, 2.19 MB), the patch is 197 KB
against 946 KB for the compressed build; between two builds of one commit
it is 5.4 KB. Builds are not reproducible, so patches are made against the
published files, never rebuilds.

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

`wasm/fuzz` is the suite: six properties over generated modules, damaged ones
and bytes that were never a module, with a small Wasm encoder so a case needs
no toolchain. `just fuzz "wasm -for=1m"` runs it; the section below records
what it found.

### Speed

`just bench` times jm:wasm against the four workloads in
`tools/wasm-bench/workloads`, compiled from the C beside them by
`just bench-build`. Each exports `run(i32) -> i32`: the argument scales the
work linearly and the result is a checksum, so the same module can be run
through another engine and checked. The harness reports the load, the first
call — which is where wasm3 compiles the body — an empty call, and the
workload, and subtracts `run(2n) - run(n)` so that only what scales with the
work is left. On this machine:

```
module        load    first     call     work
fib          14.5µs    2.8µs    138ns   219µs per unit
mandel       10.5µs    7.4µs    118ns   481µs
memsum       10.8µs    5.3µs    106ns   2.3ms
sortbench     9.9µs    7.9µs    102ns   9.5ms
```

A module is instantiated in about ten microseconds and a call into it costs
around a hundred nanoseconds, which is what an embedded interpreter is for.
The work is another matter. The same four modules, at a fixed size — `run(4096)`,
`run(2048)`, `run(512)` and `run(128)` — through every engine that could be
made to run them, each one a command that loads the module, calls `run` once
and exits. Milliseconds of work, fastest of three, lowest first; *first run*
is what the whole process costs at `run(1)`:

| engine | fib | mandel | memsum | sort | first run |
|---|---|---|---|---|---|
| wasmtime 49.0.1, Cranelift JIT | 84 | 178 | 52 | 158 | 2.9ms |
| Node 26.8.1, V8 JIT | 93 | 316 | 80 | 309 | 15.6ms |
| wazero 1.12.0, Go compiler | 125 | 193 | 130 | 380 | 2.0ms |
| WAMR 2.4.5, default (JIT) | 160 | 370 | 71 | 301 | 18.7ms |
| **jm:wasm** (wasm3 0.9.1) | 820 | 897 | 1200 | 1140 | 1.0ms |
| wasm3 0.9.1, its own CLI | 920 | 937 | 1367 | 1236 | 1.1ms |
| WAMR 2.4.5, `--interp` | 2643 | 6528 | 2806 | 6437 | 20.2ms |

Three things are worth taking from it. The bindings cost nothing: the same
modules through wasm3's own CLI come out a few percent *slower*, so what is
measured above is the interpreter, not the crossing. Against a JIT the
interpreter is five to ten times slower on arithmetic and twenty times on
memory traffic, which is the price of the 550 KB of portable C and the one
millisecond to first execution — the fastest start of anything measured here,
where a JIT pays two to twenty milliseconds before it runs a thing. And among
interpreters wasm3 holds up: WAMR's classic interpreter, the other embedded
standard, is three to seven times slower than it on the same modules. WAMR's
default mode is not an interpreter at all, which is what makes it look fast
in the fourth row.

Every engine returned the same checksum for every workload, which is what
makes the columns comparable. The figures are the fastest of three runs on an
otherwise idle machine and repeat to within about fifteen percent, so the
orders of magnitude are the point and the last digit is not. "The bindings
cost nothing" is the same measurement against a C program driving
`wasm/lib/wasm3.a` directly: 800ms against 923 on fib, 1166 against 1153 on
memsum — the two are inside each other's noise.

## PostgreSQL

`pg_query/vendor/` holds **libpg_query** at commit `6e764b79` of the
`17-latest` branch: PostgreSQL's own `gram.y` and everything it needs, lifted
out of the server source tree, carrying the **17.7** grammar. Vendored is the
`src/` tree, `protobuf/pg_query.pb-c.{c,h}`, the two third-party directories
under `vendor/` and `srcdata/`, which is the schema the node types are
generated from; left out are upstream's tests, generator scripts and the
optional C++ protobuf path. libpg_query is BSD-3-Clause, and
`pg_query/vendor/LICENSE` is its copy.

`just pg_query` compiles it once into `pg_query/lib/pg_query.a` — 86
translation units, about twenty seconds, 5 MB — which is gitignored and
rebuilt when any vendored source changes. As with SQLite and wasm3,
`foreign import` resolves that archive relative to the package directory and
`odin check` never opens it, so `just check` still type-checks all three
targets on one machine with no archive built.

The flags are upstream's Makefile exactly, less its `-g` and at `-O2` rather
than `-O3`, and they are in the justfile. Two of them are correctness rather
than taste: the PostgreSQL sources are written against `-fno-strict-aliasing`
and `-fwrapv` and miscompile without them.

The protobuf objects are compiled although this binding only wants the JSON
API, which is not for want of trying: `pg_query_parse.c` defines
`pg_query_parse_protobuf` beside `pg_query_parse`, so the object that holds
the one entry point we call also references the protobuf writer, and an
archive without it fails to link. Measured, then written down in the recipe.

### Typed nodes

A parse tree comes back as the JSON libpg_query wrote *and* as typed Odin
nodes, and the nodes are generated rather than written by hand.
`vendor/srcdata/` is libpg_query's own schema — the input it generates its Go,
Ruby and Python bindings from — and `pg_query/gen` turns the four sections
that describe parse nodes into `pg_query/nodes.odin`: **267 structs, 63
enumerated types** and a tag-dispatched decoder. `just pg_query-gen`
regenerates it; the file is checked in, so nothing normally runs the
generator.

267 rather than the 474 in `nodetypes.json`, and the difference is not a
subset taken for convenience. `struct_defs.json` describes nodes in sixteen
sections; four of them — `nodes/parsenodes`, `nodes/primnodes`, `nodes/value`
and `nodes/pg_list` — are what a *parse* tree can contain, and they hold 267
structs between them. The rest describe planner and executor nodes, which
exist only in a tree the server has already analysed and which
`pg_query_parse` never emits. The fuzz suite is what says so rather than this
paragraph: an unknown tag fails a parse, and a run that meets one fails.

Typing them is the point rather than a convenience. Dropping the schema would
not remove it, only make it implicit: a field PostgreSQL renames in its next
major would stop decoding silently, and a caller asking "does this statement
write?" would be told no because the field it looked for was absent rather
than because the statement was harmless — a failure that fails *open*.
Generated from the schema, the same rename fails to compile, and
`schema_conforms` in the tests fails before that: it loads the vendored
`struct_defs.json` at compile time and holds every node and field the Odin
side names against it.

The decoder dispatches on the tag rather than trying variants in order. Every
node arrives as a single-key object — `{"UpdateStmt": {…}}`, `{"BoolExpr":
{…}}` — so a union matched structurally would match whichever variant was
declared first and hand back the wrong node, silently. A tag this build has no
struct for fails the parse, for the same reason a missing field would: a gate
must not be handed a tree with a hole in it.

Fields are plain and left at their zero value when absent, because
libpg_query omits anything false, zero or empty; `"inh":true` is written and
`"inh":false` is not. Two shapes are written by hand in the C rather than
generated from the schema — `A_Const`, whose value arrives under `ival`,
`fval`, `boolval`, `sval` or `bsval`, and the bare `RawStmt` at the top level
— and both are special-cased in `decode.odin` and named in the generator.

Two traps, both handled, both worth knowing:

- Every `char *` in a result dies at its `pg_query_free_*`, which releases a
  whole memory context. A pointer held past that reads memory the next parse
  reuses — the `sqlite3_column_text` trap in another dialect — so everything
  the package hands back is cloned first.
- `pg_query_exit` is the one entry point deliberately left unwrapped.
  `pg_query_init` registers a pthread destructor over the same top memory
  context, so a thread that calls it and then ends frees that context twice
  and the process aborts in glibc. One worker thread, one parse, no
  concurrency needed; reproduced in C against this archive. Let the thread
  end and the destructor does it.

Parsing itself *is* thread-safe, unlike wasm3: the memory contexts are
`__thread`, and eight threads over the same statements agree on every tree
through 144,000 parses in C and 9,600 in `pg_query_test.odin`.

Statements must be valid UTF-8, and the package refuses one that is not with
the offset of the first bad byte. That is not tidiness — see what the fuzzer
found, below. `normalize`'s output is for showing a human and not for
re-parsing, for a reason recorded there too.

`pg_query/fuzz` is the suite: eight properties over generated SQL, damaged
SQL and bytes that were never SQL, with a SQL generator so a case needs no
fixtures. `just fuzz "pg_query -for=1m"` runs it.

## libgit2

`jm:git` is the git a shipped program carries with it: `just libgit2`
fetches libgit2 v1.9.7 into `build/src` and builds it into
`git/lib`, and the package links that archive when it exists and the
system libgit2 otherwise, so a machine with the distribution's package
tests without the CMake step. The archive is built with the platform's
own HTTPS (WinHTTP, SecureTransport, OpenSSL loaded at run time on Linux),
`USE_SSH=exec` so `git@` remotes go through the platform's ssh and agent,
and the bundled zlib, regex engine and HTTP parser. libgit2 runs no
hooks; a program that wants pre-commit checks runs them before `commit`.
`git/ffi_test.odin` pins every option struct's size and offsets against
what the C headers lay out, so a libgit2 bump that moves a field fails a
test instead of corrupting a stack.

**The network is tested by hand.** `tools/git-probe` is the run no test in
the repository can make: an anonymous HTTPS clone and fetch, a token
pulling from and pushing to a private remote (from an unborn branch, so
the remote is asked for its default branch), a push refused as
non-fast-forward, a wrong token refused with a plain message, and the
same repository over `git@` through the platform's ssh. It passed on
2026-09-28 against GitHub with the static Linux build, OpenSSL loaded at
run time. Run it again after a libgit2 bump or a change to the transport
options:

```
just libgit2
odin build tools/git-probe -collection:jm=. -out:build/debug/git-probe
build/debug/git-probe https://github.com/octocat/Hello-World.git \
    https://github.com/<you>/<throwaway>.git "$(gh auth token)" git@github.com:<you>/<throwaway>.git
```

`git/fuzz` is the suite: three properties, each case a fresh bare hub with
two clones on local paths. `sequence` draws any order of writes, adds,
commits, pushes, fetches and pulls across the clones and holds every step
against a model of the three trees and the commit history, so a push
succeeds exactly when the hub is behind, a pull fast-forwards exactly when
the clone is and refuses when work is uncommitted, and status is what the
trees say. `strings` sends a generated message, path and remote name
through and reads each back byte for byte, or sees the call refuse it: it
is why the wrapper refuses a string with a NUL in it rather than letting
the C boundary cut it short. `damaged` corrupts one file under `.git` and
asks every question; a Fault is a fine answer, a crash is not.

## libpq

`jm:pq` talks to a PostgreSQL server over **libpq**, and it is the one C
library in the collection that is not vendored: it links the system's
`libpq.so.5` dynamically, and a built script needs it at runtime. Every other
binding here vendors its C because that C builds with a plain `cc` and nothing
else. libpq does not — it is a slice of the PostgreSQL tree with its own
configure step — and it brings OpenSSL and GSSAPI with it for TLS and
Kerberos, which a machine should keep patched on its own schedule rather than
have frozen into every script. What makes the exception safe is libpq's
record: `libpq.so.5` has kept its ABI since 2006 and is on every machine with
a PostgreSQL client, psql included. Built and tested against libpq 18.6;
Windows links `libpq.lib` and is untested, like every Windows build here.

So there is no `just` recipe for it and nothing under `pq/lib`. `foreign
import "system:pq"` is resolved by the linker, and `odin check` never opens a
foreign import, so `just check` type-checks all three targets on a machine
without libpq installed. Only building and testing need it.

**Tests need a server, and bring their own.** `jm:pq/testdb` runs `initdb`
into a fresh directory under the temp location and `pg_ctl start` on it, once
per process: a Unix socket in that directory, `listen_addresses=''` so nothing
listens on TCP, `trust` authentication behind a socket only this user can
reach. It clears every `PG*` variable — a shell exporting `PGHOSTADDR` or
`PGSERVICE` for a real database would otherwise send a test there — and sets
`PGHOST`, `PGPORT`, `PGUSER` and `PGDATABASE` to the throwaway, which is also
what `pq.connect("")` reads. Bringing it up takes about half a second. It
leaves a shell loop behind that waits for the test process to be gone, however
it went, and then stops the server and deletes the directory; an `@(fini)`
would miss an `os.exit`, a failed assertion and a sanitizer abort. No Docker,
and no server needs to exist beforehand: on this machine `initdb` and `pg_ctl`
come with the `postgresql` package. Where they are not on `PATH`, every test
that needs a server logs why and skips, and `jm-fuzz pq` says so and runs no
cases, so the other suites keep running without PostgreSQL.

`pq/fuzz` is the suite: six properties against that server, each case on its
own connection as an unprivileged role with a `statement_timeout`.
`just fuzz "pq -for=1m"` runs it.

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

`jm:wasm` was the third suite, and its `bounds` property found the same bug in
a different package on its first run. `wasm.bytes` is what stands between a
guest's chosen pointer and the rest of the process; it checked the range by
adding `ptr + size`, so a size near the top of `int` wrapped the sum back down
into the memory, the check passed, and the slice that followed had a negative
length. `wasm.bytes(mod, 8, max(int))` was enough. It subtracts now — what is
left of the memory after `ptr`, which cannot wrap — and `wasm_test.odin` keeps
the case. Two packages, written days apart, got the same arithmetic wrong in
the same place; a property that draws pointers at the edges finds it in
seconds, and no example-based test here had.

`jm:pg_query` was the fourth suite, and it found two things in its first
runs. `error_sane` bounded `cursorpos` by the length of the statement; a
statement cut short faults at *one past* the end, which is how PostgreSQL
says "at end of input". That one was the property being wrong, and it is
written down in the package now rather than left to be rediscovered.

The second was real. `split_covers` took the process down on raw bytes after
ten thousand cases, inside `core:encoding/json`. libpg_query sets the scanner's
encoding to UTF-8 but does not validate its input against it, so
`SELECT '<0xff><0xfe>' FROM t` parses and those bytes are copied into the parse
tree verbatim — making the tree JSON that is not UTF-8. Decoding that walks
`unquote_string` off the end of its buffer, because an invalid byte decodes as
one byte and re-encodes as the three of U+FFFD. `jm:pg_query` now refuses a
statement that is not UTF-8 before the parser sees it, which is what a
PostgreSQL server with a UTF-8 database does anyway.

A third, under the sanitizer, is upstream's rather than ours and is written
down rather than fixed: `normalize` substitutes a parameter over the literal's
recorded extent without checking that a token boundary survives. A leading
minus belongs to the constant, so `SELECT-1` comes back as `SELECT$1` — one
identifier, not a statement. `normalize_reparses` skips that shape and names
it; `pg_query_test.odin` keeps the case, and the package doc tells a caller
not to re-parse what normalize writes.

`jm:pq` was the fifth suite. Its first run failed `error_sane` on every COPY:
the binding refused `COPY … TO STDOUT` with no SQLSTATE, the mark of a
refusal that never reached the server — but by then the server had started
the COPY. It now carries `0A000`, feature_not_supported, which is both true
and something a caller branching on SQLSTATE can match. Nothing else turned
up in 100,000 cases under the sanitizer.

The sanitizer taught something about itself while the tests were written.
`values_outlive_the_connection` closes the connection and then reads every
string the binding handed back, so that a string still pointing into a freed
`PGresult` traps. With the clone deliberately removed it passed anyway: the
comparison runs in `base:runtime`, which is not instrumented, so ASan never
saw the read. The test now walks every byte in its own code first, and with
the clone removed it fails with a heap-use-after-free, as it should.

## Streams

`stream` is a dataflow pipeline: typed operators build a DAG of nodes joined
by bounded edges, and a driver runs the nodes. A node runs only when an edge
changed and never blocks, so there is no thread per stage and no select;
blocking lives at the edges, in a thread feeding a `port` or in `workers`
doing a job and reporting through an inlet. `run(p)` drives a pipeline on
the calling thread plus a pool sized from the graph, at most three threads,
which is where the measurements below say a pool is never a loss; `run(p, n)`
asks for `n` threads, `run(p, 0)` for none; `step` runs one node for a
deterministic test, and a `Clock` can be manual so timers are driven by the
test.

Bounded edges carry one caveat: `zip` waits on a particular input, so a source
that reaches a zip along two paths of different rate would deadlock on it.
Building such a graph panics at the `zip` call, naming the shared source and
the stage that changes the count; paths of one-in-one-out stages are allowed,
since they stay in step. Merge never waits on one input and is safe to fan
into.

Three pieces serve a frame loop. `latest` is a sink another thread reads
with `latest_take`: it keeps only the newest message and never parks its
producer, so a loop that stops reading, with its window hidden say, never
stalls the pipeline, and a burst of answers costs the next frame one take.
`debounce_by` is `debounce` per key: a burst of changes to one record
settles to one message without holding up another record's. `pin` keeps a
node off the pool, for work that must run on one thread, a texture upload
say: `run` never runs it, the owning thread runs what is ready of them with
`drain_pinned`, once a frame, and `p.wake` is called when one becomes ready
so that thread can be told. `step` and `drain` run pinned nodes too, since
the one thread driving is the owner.

In debug and test builds every yield is checked against the edges when the
run is single-threaded, and a pool run fails loudly if the pipeline goes
quiet with a node unfinished. `-define:STREAM_CHECK_YIELDS=false` turns both
off.

`stream/fuzz` is the suite: fourteen properties over random graphs, with the
next node drawn from the case's entropy to stand in for a pool's interleaving,
and again on real threads. `just fuzz "stream -for=1m"` runs it.
`just stream-bench` prints what a message costs through each shape,
`just stream-bench crossover` burns a chosen amount of work per stage and
shows where a pool starts to beat one thread, and
`just stream-stress "-nodes=2000 -for=5m"` runs random DAGs of that size
until the time is up, checking every sink's count against a model. On a
24-core desktop a stage hop costs about 20 ns, and a pool pays once a stage
does roughly 50 ns of work per message for a chain or fan-out of a few
branches, and 200 ns before eight branches fill eight threads.

## UI

`jm:ui` is an immediate-mode user interface whose frame is data. A ui proc
records scene ops, `flatten` turns them into a draw list and a hit list, and
`ui/render` executes the draw list on Blend2D while the router hit-tests the
hit list. Every stage is an array with a text dump, so a frame can be
asserted on, serialized (`encode`) for a renderer in another process, or
driven by `ui.Probe` with no window at all:

```
build/debug/material-kitchen-child -page Buttons -dump          the scene as text
build/debug/material-kitchen-child -page Menus -click Edit -events   click by tag, list what it routed
build/debug/material-kitchen-child -page Buttons -png out.png   render it headlessly
```

Widgets nest through containers with no per-child boilerplate:

```odin
col := ui.column_open(gtx, gap = 8); defer ui.close(&col)
base.label(gtx, "Name")
m3.text_field(gtx, &m.name, "Name")
if m3.button(gtx, "Save") { save(m) }
```

`ui` itself has layout, input, text and paint and no look of its own;
`ui/base` is the smallest design system on it (a checked palette, label,
divider, panel), `ui/material` and `ui/fluent` the full ones, all through
the shared `ui/design` layer.

A frame is a function of plain data, and the data goes both ways. In: the
host's input, and shapes, the answers to what the frame needed. Out: the
scene, what to persist, requests of the platform (clipboard, a URL), needs,
and commands. A need is a query, a value of a type the application's
contract declares, that `ui.need` records and reads the delivered shape
for; a command is a value for the application to process, `ui.command`.
Both cross the boundary as kind and cbor bytes, so `ui` knows nothing of the
contract's types, and the application never addresses the ui: it answers
needs through an `Inbox` from any thread and sees commands through a
`Data_Host` on the loop's thread. The need set is rebuilt every frame and
`Subscriptions` diffs it, so a host starts what appeared and cancels what
went, and a row scrolled out of view releases its avatar with no cleanup
in the widget. `ui/sdl`'s `App` and `Host_App` and `ui/child`'s `App` each
carry a `Data_Host`; over the hot-reload wire the child sends its need
diff and commands with each reply and the host's answers ride the next
input, so the application can live in either process. `ui.Probe` delivers
shapes and reads needs and commands, which is how a frame is tested with no
application linked: `ui/need_test.odin` is the model.

```odin
page, status := ui.need(gtx, shapes.Users_Page{page = m.page, size = 50}, shapes.Users_Page_Result)
if status == .Missing || status == .Loading { skeleton(gtx); return }
for row in page.rows {
	s := ui.scope_open(gtx, row.id); defer ui.scope_close(&s)
	avatar, av := ui.need(gtx, shapes.Avatar{user = row.id, px = 48}, shapes.Avatar_Result)
	if m3.button(gtx, "Delete") { ui.command(gtx, shapes.Delete_User{id = row.id}) }
}
```

A zero field in a style struct takes the theme's value. Clipping is exact for
any shape under any affine: Blend2D clips only to rectangles, so a path or
rotated clip renders through an A8 mask. The Blend2D binding is copied from
`odin-blend2d`; `just blend2d` fetches the upstream Blend2D and asmjit commits
it was generated from and builds the archive, and anything linking it needs
`-lstdc++`. Text is shaped by kb_text_shape, vendored upstream at a pinned
commit in `ui/kb/vendor` (zlib licence); `just kb` builds it, and
`JM_UI_SHAPER=blend2d` shapes with Blend2D's own shaper instead, to compare.
Assistive technology reads the widgets' semantics (`ui.semantics`) through
AccessKit (`ui/accesskit`, Apache-2.0 or MIT), fetched as the upstream
release's prebuilt library by `just accesskit` rather than built, so no
Rust toolchain is needed: the static archive on Linux (AT-SPI2) and macOS
(NSAccessibility), the DLL on Windows (UI Automation), beside the executable.
`examples/material-kitchen` is the demo, `just material-kitchen` opens it.

That "serialized for a renderer in another process" is `ui/sdl.run_host`:
a host owns the window and renders, a subprocess (`ui/child`) owns the
Model, the ui proc, `Router` and `Layout`, and the two talk `ui/wire`'s
Input/Reply over `ui/ipc`'s pipes. `Host_App.watch` names a pointer file a
builder republishes on every successful build (`tools/hot-watch` is one);
the host re-reads it and respawns the child on a change, never
overwriting a running executable in place, which Windows refuses.
`examples/hot-counter` (a two-binary click counter),
`examples/hot-architecture` (a live-editable diagram of this very
pipeline), `examples/material-kitchen` (every `ui/material`
component, a page each, in all its spec states) and
`examples/fluent-kitchen` (the same for `ui/fluent`, in all five themes)
and `examples/text-lab` (text specimens in many scripts and directions,
with the shaper's clusters and caret stops drawn over them) are the
demos; `just hot-architecture` builds its own host and prints the two
commands that run it, and `just material-kitchen`, `just fluent-kitchen`
and `just text-lab` build and open their own. `tools/hot-watch`
takes extra directories to watch after the pointer file, so a child
rebuilds when the `ui` package it imports is edited too, and with `-host`
it rebuilds the host as well, which restarts itself when the ops
encoding changed under it.

Checking a change without a window: `-dump` prints the scene as text,
free of vision tokens and enough for most bugs; `-png` renders it to a
PNG when the question is actually about pixels; `tools/img-diff` (over
`ui/render`'s `diff_files`) turns two PNGs into a list of changed regions
as text, so confirming an edit changed what it should needs looking at
neither.
