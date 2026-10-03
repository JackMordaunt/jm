# Building and testing

Every task is a `just` recipe, grouped by the package it serves.

```
general      check    3-target type-check of every package and program, or of those named
             test     every package's tests, or the named packages'; -flags go to odin test
             link     build every program into build/debug
             clean    drop build/ and every package's compiled C library
             readme   render the README and docs to build/readme and open them
odin-run     odin-run-build    debug odin-run   odin-run-release  optimised odin-run
             odin-run-install  odin-run -> ~/.local/bin (BINDIR overrides)
             odin-run-example  run examples/hello.odin
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
ui/primer    primer-kitchen  build and open the hot-reloaded Primer kitchen
             primer-png page=Button theme=Light  render one Primer kitchen page to build/
             primer-tokens  regenerate ui/primer/tokens from the primer-kit
             primer-icons  regenerate ui/primer/icon_data.odin from the kit's octicons
             primer-kit-{tokens,fetch,index,check}  maintain the primer-kit in tools/primer
```

`text-lab`, the three kitchens and `gallery` take `release` to build with `-o:speed`
instead of `-debug`: `just material-kitchen release`.

`just` alone lists the recipes in these sections: one per package or tool,
the recipe that compiles a package's C library in its section, and general
for what spans them all.

`just odin-run-install` bakes this checkout's path into the runner as the `jm`
collection root; `ODIN_RUN_COLLECTION` overrides it.

`check`, `test` and `link` find their packages rather than read a list:
every directory of `.odin` files git sees, tracked or not but never
ignored, a `package main` directory being a program and one with an
`@(test)` proc a test package. `SKIP="pq tools/jm-fuzz"` leaves those
directories and everything under them out, as on a machine without libpq.
Packages run in parallel, except the `serial_tests` the justfile names.
`just check ui/primer` and `just test ui/primer` take the same flags for
one package, and `just test ui/primer -define:ODIN_TEST_NAMES=primer.<test>`
runs one test; a run that matches no test fails, and each `ok` line counts
the tests that ran.

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
