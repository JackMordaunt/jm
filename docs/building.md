# Building and testing

**Every task is one `just` recipe, and the same recipes run on your machine and in CI.**

- `just` alone lists the recipes, grouped by the package or tool each serves.
- `check`, `test` and `link` find packages themselves, so a new package needs no list entry.
- One machine type-checks all three platforms.
- CI runs the same recipes on Linux, macOS and Windows.

## The recipes you will use

| Recipe | What it does |
|--------|--------------|
| `just check` | type-check every package and program for linux, darwin and windows |
| `just test` | run every package's tests |
| `just odin-run-install` | install `odin-run` into `~/.local/bin` (`BINDIR` overrides) |
| `just material-kitchen` | build and open a hot-reloaded UI kitchen (also `fluent-kitchen`, `primer-kitchen`) |
| `just readme` | render the README and docs to `build/readme` and open them |

### Run one package or one test

```sh
just check ui/primer
just test ui/primer
just test ui/primer -define:ODIN_TEST_NAMES=primer.<test>
```

A run that matches no test fails, and each `ok` line counts the tests that ran.

### Leave packages out

`SKIP="pq tools/jm-fuzz"` leaves those directories and everything under them out, as on a
machine without libpq.

### Release builds of the apps

`text-lab`, the three kitchens and `gallery` take `release` to build with `-o:speed` instead of
`-debug`: `just material-kitchen release`.

### Work in a git worktree

In a linked git worktree, each native library's recipe first clone-copies that library from the
main checkout when its vendored tree or pinned revisions match there. A fresh worktree links in
seconds instead of rebuilding Blend2D and libgit2.

## Every recipe

The recipe that compiles a package's C library sits in that package's section; `general` holds
what spans them all.

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
             text-png Scripts  render one text-lab page, whole, to build/
ui/material  material-kitchen  build and open the hot-reloaded M3 kitchen
             material-png Chips  render one M3 kitchen page to build/
             material-tokens  regenerate ui/material/tokens from the m3e-kit
             material-shapes  regenerate ui/material/shape_data.odin from the m3e-kit's morphs
             material-kit-{tokens,shapes,fetch,index,check,page}  maintain the m3e-kit in tools/material
ui/fluent    fluent-kitchen  build and open the hot-reloaded Fluent 2 kitchen
             fluent-png Button  render one Fluent kitchen page to build/
             fluent-fonts  fetch Selawik, the kitchen's stand-in for Segoe UI, into ~/.local/share/fonts
             fluent-tokens  regenerate ui/fluent/tokens from the fluent-kit
             fluent-icons  regenerate ui/fluent/icon_data.odin from the Fluent icons in tools/fluent/icons
             fluent-icons-fetch  fetch the icons icons.txt names at its pinned commit (or a ref given)
             fluent-kit-{tokens,fetch,index,check,page}  maintain the fluent-kit in tools/fluent
ui/primer    primer-kitchen  build and open the hot-reloaded Primer kitchen
             primer-png Button Light  render one Primer kitchen page to build/
             primer-tokens  regenerate ui/primer/tokens from the primer-kit
             primer-icons  regenerate ui/primer/icon_data.odin from the kit's octicons
             primer-kit-{tokens,fetch,index,check}  maintain the primer-kit in tools/primer
```

<details>
<summary>Under the hood: how check, test and link find packages</summary>

They read no list. Every directory of `.odin` files git sees counts, tracked or not but never
ignored. A `package main` directory is a program, and one with an `@(test)` proc is a test
package.

Packages run in parallel, except the `serial_tests` the justfile names.

`just odin-run-install` bakes this checkout's path into the runner as the `jm` collection
root; `ODIN_RUN_COLLECTION` overrides it.

</details>

## Continuous integration

| Workflow | What it runs |
|----------|--------------|
| `.github/workflows/test.yml` | `just check`, then `just link test` on Linux, macOS and Windows |
| `wasm-windows.yml` | the shorter loop for jm:wasm on Windows alone |

> [!TIP]
> CI runs on a push to `main` or to any `ci/<name>` branch, so pushing a throwaway `ci/`
> branch checks all three platforms during development.
> `gh workflow run test.yml --ref <branch>` runs it on any other branch.

<details>
<summary>Under the hood: what CI builds and why</summary>

- `test.yml` builds the vendored C libraries, libgit2 and Blend2D the way the recipes do, and
  caches the CMake builds.
- `ui/sdl` runs too. Linux builds SDL3 console-only, which is enough because its tests drive a
  child process rather than open a window.
- `pq` runs on all three, each runner having libpq and a PostgreSQL server.
- `wasm-windows.yml` builds wasm3 with clang-cl at two optimisation levels, runs the trap tests
  one process each, and reruns a faulting one under cdb for its stack.
- The recipe's own cl build of wasm3 does not compile; clang-cl is what Windows uses.

</details>

## See also

- [Setup](setup.md): installing what the recipes need
- [Fuzzing](fuzzing.md): the `fuzz` recipes in depth
- [UI](ui.md): the kitchens and example apps
- [README](../README.md)
