# Packages

**Small packages that each do one job, built on `core:` and imported one at a time.**

- **Scripting:** the shell, HTTP, paths and time, one import each.
- **Data and formats:** SQLite, zstd, PostgreSQL, libgit2 and wasm3, linked statically.
- **UI:** an immediate-mode toolkit with Material 3, Fluent 2 and Primer on top.
- **Testing:** a property fuzzer, with suites for nine packages.

Every package reads on its own; the doc comment at the top of each file is the reference.

## Scripting

Everyday script work: the shell, the web, files, time and archives.

| Package | Job |
|---------|-----|
| `prelude` | `must`, `die`, `env`, `args`; arena or debug allocator; logfmt log file plus `deaths.log` audit trail |
| `sh` | `out`, `lines`, `ok`, `run`, `capture` through the shell; `exec`, `exec_run` with argv; `which`, `quote`, `error` |
| `http` | `get`, `post`, `post_json`, `get_json`, `download`, `request` over libcurl, and a `Client` whose requests run on its own thread and can be cancelled |
| `path` | `expand`, `join`, `mkdirs`, `read`, `read_lines`, `write`, `append_file`, `list`, `walk`, `temp_dir`, `same`, per-user app dirs |
| `timefmt` | strftime `format`, `local`, `parse`; `iso`, `stamp`, `date`, `duration` |
| `tar` | `read`, `extract`: `git archive` output without a tar program |

## Data and formats

Databases, compression, parsers and an interpreter, statically linked unless noted.

| Package | Job |
|---------|-----|
| `sqlite3` | `open`, `exec`, `exec_args`, `query`/`next`, `prepare`, `transact` over a statically linked SQLite |
| `zstd` | `compress`, `decompress`, their `_stream` forms, and binary patches with `diff` and `patch`, over a statically linked zstd |
| `pg_query` | `parse`, `split`, `is_utility`, `fingerprint`, `normalize`: PostgreSQL's own SQL parser, statically linked, with node types generated from its schema |
| `pq` | `connect`, `exec`, `escape_literal`, `escape_identifier`, `identity`: a PostgreSQL client over the system libpq, the one dynamically linked library |
| `pq/testdb` | a throwaway PostgreSQL server on a Unix socket, for tests |
| `git` | `open`, `init`, `clone`, `status`, `add`, `commit`, `log`, `remotes`, `fetch`, `push`, `pull`, `diff` over a statically linked libgit2, so a shipped program needs no git on the machine |
| `wasm` | `open`, `load`, `find`, `call`, `link`, `run`: WebAssembly through a statically linked wasm3 |

## Shipping

What a distributed program needs once it leaves your machine.

| Package | Job |
|---------|-----|
| `selfupdate` | `run`: a distributed binary checks a signed release and replaces itself, by patch, compressed asset or full download |

## UI

An immediate-mode UI whose frame is data, and three design systems on it.

| Package | Job |
|---------|-----|
| `ui/ops` | the recorded drawing: geometry, colour, paint, shapes, glyph runs and the scene ops a ui proc emits into a `Scene`, with their wire form (`encode`) and text form (`dump`); everything above shares these types |
| `ui` | immediate-mode UI: `ops.Scene` → `flatten` → draw and hit lists; layout, theme, widgets, a `Probe` that clicks and types without a window |
| `ui/render` | executes a `ui.Frame` on Blend2D (vendored binding in `ui/blend2d`), hands out a `ui/shape` shaper with Blend2D's line metrics, and `snapshot`s a `ui` proc straight to a PNG |
| `ui/shape` | text to glyph runs with kb_text_shape: OpenType shaping for complex scripts, normalisation, per-run direction, clusters as byte offsets |
| `ui/kb` | the binding to kb_text_shape, vendored in `ui/kb/vendor` and statically linked |
| `ui/accesskit` | the binding to AccessKit's C library (prebuilt, `just accesskit`), and the tree it is fed from a frame's semantic nodes: what a screen reader hears |
| `ui/shell` | the shell: joins the OS (SDL3 window, events and renderer, AccessKit, native APIs), the `ui` stack and the app; `run_host` runs the same window against a subprocess instead of a local ui proc |
| `ui/ipc` | length-prefixed frames over a pipe, and spawning a child process wired up for exactly that — the transport under `ui/shell`'s host/subprocess split |
| `ui/child` | the subprocess half of that split: owns the Model, the ui proc, `Router` and `Layout`, and speaks `ui`'s wire format over its own stdin/stdout |
| `ui/diagram` | titled, accent-bordered groups of chips and arrows (solid or dashed) for an architecture diagram, over plain `ui` calls |
| `ui/design` | what every design system on `ui` shares: the interaction states and per-frame `Control`, per-corner geometry, text shaping in a line box, box-shadow layers drawn as exact Gaussian shadows, CSS easing, and a generic `Theme(Role, Context)` with axioms that `check` measures in every context (OKLab, APCA and WCAG metrics) |
| `ui/base` | the smallest design system on `ui`: a five-role palette bound light and dark as an instance of `ui/design`, checked by its axioms, and the plain widgets every page needs — label, text, divider, panel; a full system maps its scheme down to it |
| `ui/material` | Material 3 Expressive on `ui`: the colour scheme, type scale, shape, motion springs and state tokens generated from the m3e-kit (`tools/material`) into `ui/material/tokens`, Material Symbols icons as paths, and the components (buttons, text fields, selection controls, chips, cards, lists, navigation, app bars, tabs), each able to paint any spec state on demand |
| `ui/fluent` | Fluent 2 on `ui`: the five colour themes (web and Teams, light and dark, high contrast), type ramp, spacing, radii, strokes, shadows and motion generated from the fluent-kit (`tools/fluent`) into `ui/fluent/tokens`, with states read as separate tokens through a `design.Control` and colour changes eased over the kit's duration and curve |
| `ui/primer` | GitHub's Primer on `ui`: the 14 colour themes (light, dark and dark dimmed, each with high-contrast, colorblind and tritanopia variants), type scale, control sizes, radii, borders, layered shadows and motion generated from the primer-kit (`tools/primer`) into `ui/primer/tokens`, and every Octicon at its 12, 16 and 24px designs |
| `ui/testutil` | `count_ops`: assertions a `ui` package's own tests and a downstream package's tests both want, without an import cycle |

## Concurrency

Worker pools and non-blocking dataflow pipelines.

| Package | Job |
|---------|-----|
| `flow` | `width`, `each`, `manage`: lock-free worker pools where each worker owns one state slot and the caller merges afterwards |
| `stream` | non-blocking dataflow pipelines: typed operators over a DAG of nodes and bounded edges, run on one thread or a pool, with a clock, ports from other threads and a worker pool for blocking work |
| `stream/ring` | one-producer one-consumer ring of messages of one `Shape` (size, alignment, type), each end on its own cache line with a cached copy of the other's index, storage aligned to the shape; what a stream edge and inlet are built on |

## Testing

The property fuzzer, its per-package suites, and the debug allocator.

| Package | Job |
|---------|-----|
| `fuzz` | property fuzzing: an entropy `Source`, generators, format-agnostic `damage`, shrinking, a corpus, a per-case deadline |
| `debug` | guard-byte debug allocator (origin: sonar, which now imports this copy) |
| `sqlite3/fuzz` | the `jm:sqlite3` suite for `jm:fuzz` |
| `zstd/fuzz` | the `jm:zstd` suite for `jm:fuzz` |
| `tar/fuzz` | the `jm:tar` suite for `jm:fuzz` |
| `wasm/fuzz` | the `jm:wasm` suite for `jm:fuzz`, with a small Wasm encoder to build cases from |
| `pg_query/fuzz` | the `jm:pg_query` suite for `jm:fuzz`, with a SQL generator to build cases from |
| `pq/fuzz` | the `jm:pq` suite for `jm:fuzz`, against the `pq/testdb` server |
| `ui/render/fuzz` | the `jm:ui/render` suite for `jm:fuzz`: composed frames checked against whole renders |
| `git/fuzz` | the `jm:git` suite for `jm:fuzz`: random operation sequences over two clones of a hub, held against a model that knows no merges |
| `stream/fuzz` | the `jm:stream` suite for `jm:fuzz`: random graphs against a sequential model, single-threaded with a drawn scheduler and on a pool |

## Tools

| Tool | Job |
|------|-----|
| `tools/odin-run` | the runner: see [Writing scripts](scripts.md#runner) |
| `tools/mkpatch` | makes the compressed asset and the patches `jm:selfupdate` looks for, in a release's CI |

## See also

- [Writing scripts](scripts.md): the conventions the scripting packages share
- [UI](ui.md), [Streams](streams.md) and [Fuzzing](fuzzing.md): the larger packages in depth
- [SQLite](sqlite.md), [zstd](zstd.md), [WebAssembly](wasm.md), [PostgreSQL](postgres.md) and [Git](git.md): the vendored libraries
- [README](../README.md)
