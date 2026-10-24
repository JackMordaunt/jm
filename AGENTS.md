# jm — agent instructions

jm is a collection of small Odin packages (`-collection:jm=<this checkout>`), imported one at a
time: scripting, vendored C libraries, streams, fuzzing, and `jm:ui`, a UI toolkit whose every
frame is data. Every task is one `just` recipe; `just` alone lists them.

## Read before you touch

| Before touching | Read |
|-----------------|------|
| `ui/**`, `examples/` (apps, kitchens, 7guis) | [docs/ui.md](docs/ui.md), then [docs/packages.md](docs/packages.md) § UI |
| `justfile`, CI, a native library's recipe | [docs/building.md](docs/building.md), [docs/setup.md](docs/setup.md) |
| `prelude`, `sh`, `path`, `http`, `tools/odin-run` | [docs/scripts.md](docs/scripts.md) |
| `stream` | [docs/streams.md](docs/streams.md) |
| `fuzz`, any `*/fuzz` suite | [docs/fuzzing.md](docs/fuzzing.md) |
| `sqlite3` | [docs/sqlite.md](docs/sqlite.md) |
| `pg_query`, `pq` | [docs/postgres.md](docs/postgres.md) |
| `git` | [docs/git.md](docs/git.md) |
| `wasm` | [docs/wasm.md](docs/wasm.md) |
| `zstd`, `selfupdate` patches | [docs/zstd.md](docs/zstd.md) |
| which package does what | [docs/packages.md](docs/packages.md) |

## Build and test

- `just check ui/primer` type-checks a package for linux, darwin and windows; `just check` checks
  all of them.
- `just test ui/primer`, or one test: `just test ui/primer -define:ODIN_TEST_NAMES=primer.<test>`.
  A run that matches no test fails.
- No test may time what it checks: count the work, or bound only a hang (justfile `serial_tests`).

## jm:ui

Read [docs/ui.md](docs/ui.md) before writing or checking `jm:ui` code. A jm:ui GUI is verified
headlessly, never by asking a person to click it:

- **Probe tests.** `ui.Probe` (`ui/probe.odin`) runs the ui proc with no window: `probe_click`,
  `probe_type`, `probe_key`, `probe_drag`, `probe_scroll` by tag name, then `probe_tagged`,
  `probe_bounds`, `probe_focus_name`, `probe_dump`, `probe_commands` to assert. Models:
  `examples/7guis/*/*_test.odin`, and `ui/need_test.odin` for needs and commands.
- **Pixels and dumps.** A program built on `render.headless_step` (the kitchens) takes
  `-click NAME`, `-drag NAME DX DY`, `-type`, `-key`, `-advance N`, `-dump`, `-semantics`,
  `-overflow`, `-png PATH` in sequence (flag list: `ui/render/headless.odin`). The 7guis tasks
  take `-png PATH` (first frame, `render.snapshot`). `tools/img-diff` compares two PNGs as text.
- **Native libraries, by package.** `ui`, `ui/design`, `ui/base`, `ui/primer`, `ui/fluent`,
  `ui/material` and `ui/plot` link nothing native, so their probe tests need no library.
  `ui/render` and `ui/child` link Blend2D and kb_text_shape (`just blend2d`, `just kb`).
  `ui/shell` (a window) adds AccessKit (`just accesskit`) and SDL3 (a system library on Linux,
  `just sdl3` elsewhere). No linker flag: Blend2D's foreign import names the C++ runtime.

Traps, each checked against the code:

- **Guards close at the end of the enclosing block.** `ui.row(gtx)` as a statement lays out the
  rest of the block in the row, so a second region written the same way nests inside the first.
  Mixing a guard with an explicit `x_open`/`ui.close` in one block asserts "ui: containers ended
  out of order" (`ui/layout.odin`) or "a guard's scope ended with another container on top"
  (`ui/guards.odin`). Give each region body its own proc, or write `if ui.row(gtx) { … }`.
- **Input lands a frame late.** A probe input is routed against the previous frame: assert on
  the model at once, but run one more `ui.probe_frame` before asserting on what the frame draws
  (`examples/7guis/counter/counter_test.odin`).
- **A tag finds its first area.** `probe_find`, `probe_bounds` and `probe_click` take the first
  area with the name; an open menu's item over a cell of the same text needs `probe_click_top`,
  and siblings need distinct names.
- **A Primer button grows to its label.** In a `ui.flexible` cell too narrow for its label, the
  button and its input area grow past the cell over its siblings, so `probe_click` at its centre
  can land on the next widget or outside the window. `ui.clip_box` holds it to the cell, but
  `probe_bounds` still reports the unclipped shape: click near its start with `probe_click_at`.
- **The probe's text is stubbed.** `probe_init` shapes with `stub_shaper()`; measure real text
  through `render.Headless` or `render.snapshot`, which swap in Blend2D's shaper.
- **A Primer overlay takes focus back.** An action menu, dialog or other Primer overlay requests
  focus for its anchor (or what had focus) on the first frame it is closed
  (`overlay_focus` in `ui/primer/overlays.odin`). A dialog opened from a menu item must request
  its field's focus every frame until `ui.focused(gtx)` is that field.
- **Live and headless paint differ.** A live window paints through `render.compose` (damage,
  scroll moves; `ui/shell/shell.odin`); `-png` and `snapshot` paint through `render.render`. A bug
  seen only live is in compose (`ui/render/compose_test.odin`); one in `-png` too is in the scene.
