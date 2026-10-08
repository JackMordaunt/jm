# UI

**`jm:ui` is an immediate-mode UI toolkit whose every frame is data: test it with no window,
render it with no GPU, and reload it while it runs.**

- **Testable.** A frame is plain arrays with a text dump. A test clicks, types and asserts with no
  window, and CI renders pixels with no display.
- **Live.** The app runs in a child process and reloads on every build, keeping its state.
- **Three design systems.** Material 3 Expressive, Fluent 2 and GitHub Primer, generated from each
  system's own tokens and drawn in every spec state.
- **Real text.** OpenType shaping for complex scripts, bidirectional runs and exact caret stops.
- **Accessible.** Screen readers read the widgets through AccessKit on Linux, macOS and Windows.

<p align="center">
  <img src="images/gallery-demo.gif" alt="The gallery: tiles fill in, a fast scroll abandons work, a tile opens and a deep zoom streams in" width="540">
</p>

<p align="center"><sub>The gallery app, recorded headlessly: <code>ui.Probe</code> drove the real
pipeline, workers and files, and <code>ui/render</code> drew each frame. 13 seconds, played back
at the speed it ran.</sub></p>

## Quick start

Widgets nest through containers, with no per-child boilerplate:

```odin
ui.column(gtx, gap = 8)
base.label(gtx, "Name")
m3.text_field(gtx, &m.name, "Name")
if m3.button(gtx, "Save") { save(m) }
```

A container is a guard: it closes itself at the end of the block it is called in, or of the
`if` when written `if ui.row(gtx) { … }`. The explicit `ui.row_open` and `ui.close` pair is for
a body that spans procs or needs the container's handle.

Open a demo:

```sh
just material-kitchen     # every Material 3 component, a page each
just files                # a file browser over your home folder
just gallery              # ten thousand pictures made on demand
```

## The example apps

Every screenshot here is a real app rendered headlessly by jm itself.

### Files

<img src="images/files.png" alt="The files app: a sidebar of places, a sortable table with thumbnails, and a details card" width="100%">

A file browser built from Fluent's own parts: a breadcrumb toolbar with the actions and search, a
sortable table with thumbnails, a details card, and a sidebar of places, pins and recent folders. It
renames, makes folders, copies, moves and moves to the Trash, asks when a paste would collide, and
undoes. Listings and thumbnails load on worker threads as they come into view, and a folder shown
updates when another application changes it. `just files [path]` · `examples/files`

<details>
<summary>How it works</summary>

A folder's listing and each thumbnail are needs, read and made on worker threads as they come into
view, with Blend2D decoding the pictures. A double click on a folder goes into it, keeping the old
listing drawn until the new one lands. The mouse's back and forward buttons, Alt with an arrow, and
the toolbar's buttons walk the folders visited.

Every change is a command the ui sends without knowing whether it can be done, because the listing
it read may already be stale. The application finds out. It gathers the facts the command needs from
the filesystem and from SQLite. Three pure domains judge them: `naming` (is this a name the system
accepts, and is it taken?), `placement` (is this paste a rename, a copy, or a copy then a trash?) and
`protection` (is this a folder a slip of the mouse must not break?). `logic` turns the verdicts into
a plan of effects, and the host carries the plan out in a fixed order. Filesystem effects go first,
one at a time, each through a primitive that fails rather than replaces (`renamex_np`, `renameat2`,
`MoveFileExW`). Then the store's effects commit in one transaction: pins follow a renamed folder,
and the journal records what Undo needs. Undo is a command like any other: it checks that the world
still matches what the change left, and refuses with a reason if it does not.

A paste whose name is taken asks Replace, Keep both or Skip. The answer is a new command, enriched
and decided again against the files as they are then. Copies run on a thread of their own with
progress and a Stop button. A folder shown is polled for change every half second, and the
application relists the folders its own changes touch at once.

The window can't be made smaller than 480 by 360 points, and every size from there up lays out
whole, as the Finder's does. The view plans the frame from the window's width before drawing. The
sidebar moves into a drawer below 760 points, the details pane goes when the table would be left too
little, and the table drops its Modified and then its Size column. Toolbar actions fold into a
"More" menu in a fixed order, measured with `fluent.button_size`. Search is a box when there is room
and a button that opens one when there isn't, displacing actions as it opens. The path bar, pinned
under the content, folds crumbs from the root to their icons. A hovered crumb shows its name, and the
crumbs after it make room, so it stays under the pointer. A test lays the view out at every width
from 480 to 1600 and checks that every action stays reachable and none is squeezed.

`just files` opens the home folder, `just files <path>` another, and `just files-test` runs its
suites, the last on real folders.

</details>

### Gallery

<img src="images/gallery.png" alt="The gallery: a grid of fractal tiles with live counters in the header" width="540">

A grid of ten thousand pictures, each made on a worker thread when its row scrolls into view and
abandoned when it scrolls away. Click one to zoom it like a map, as deep as `f64` goes.
`just gallery` · `examples/gallery`

<details>
<summary>How it works</summary>

`ui.list` lays out only the rows in view, so a tile's need appears as it scrolls in and goes as it
scrolls out. The host starts a job after a short quiet, sets the job's cancel flag when the need
goes, and the generator checks the flag every row and gives up. A tile is blank for 150 ms, then a
skeleton, then its picture; the header counts what was made and what was abandoned.

A click opens the picture over the window, where the wheel zooms about the pointer and a drag pans.
The picture at each zoom level is a grid of patches, each a need of its own made on a worker as it
comes into view and given up as it leaves. The level below is kept until the new one is whole, so
the zoom streams in square by square.

A stream asks a cache before it makes a picture: the files the generator wrote, 10 MB of them,
least recently used out first and never one a frame still needs. The header counts the streams
open, the pictures made and abandoned, and the cache's images, bytes, hits, misses and evictions.

`just gallery` opens it, and `just gallery-test` runs its suites, the last against the real
workers and files.

</details>

### Todo

<img src="images/todo.png" alt="TodoMVC in Fluent with two items completed" width="540">

TodoMVC in Fluent, with SQLite as the data engine and a stream pipeline joining four threads. It is
the smallest complete picture of how a jm application is put together. `just todo` ·
`examples/todo`

<details>
<summary>How it works</summary>

| Package | Job |
|---------|-----|
| `shapes` | The contract |
| `view` | The frame, which imports the contract and jm:ui and nothing else |
| `logic` | The rules, pure: a request in and a write or a problem out |
| `store` | The connection and its thread, a pipeline stage pinned to it |
| `app` | The host that wires them: a worker thread for the rules and a pool for the rest |
| `main` | The window |

The store's update hook buffers each row a statement touches, and its commit hook pushes the batch
into a port; the rollback hook drops it. A need for a filter subscribes a query the pipeline re-runs
on every change batch while the need is live. Problems are never stored: a fold in the pipeline
keeps the list and delivers it as a shape.

`just test examples/todo/app` runs the view in a probe against the real pipeline, threads and
database, with no window.

```
just todo                        todo.db in the working directory
just todo -memory                a database gone when the window closes
just todo-test                   its suites, the last on real threads and a database
```

</details>

### 7GUIs

<img src="images/7guis-cells.png" alt="The Cells task: a spreadsheet with a sum, an error and a cell being edited" width="540">

The seven tasks of the [7GUIs](https://eugenkiss.github.io/7guis/) benchmark, each a program
with its tests beside it. A task is a model struct and a ui proc, and every test drives it with
`ui.Probe` and no window. `just sevenguis <task>` opens one, `just sevenguis-test` runs every
suite, and `just sevenguis cells -png out.png` renders a first frame headlessly.

| Task | Lines | Tests | What it shows |
|------|------:|------:|---------------|
| `counter` | 35 | 20 | The model is read and written in one proc; nothing is kept in sync |
| `temperature` | 67 | 48 | Two-way binding as two `if`s, and an invalid field |
| `flight` | 82 | 68 | Constraints computed from the text each frame, and disabled controls |
| `timer` | 56 | 39 | Time as `gtx.dt`, a frame asked for only while it runs, a test stepping time |
| `crud` | 138 | 63 | A filtered list derived in the frame, not cached beside the data |
| `circles` | 228 | 101 | A canvas from core ops, a context menu, a popover, undo as a list of actions |
| `cells` | 510 | 188 | 2,727 cell widgets a frame in a two-way scroll box, editing in place, a formula engine tested without ui |

Lines count comments. The shared window and theme are `examples/7guis/shell`, 48 lines.

### Design-system kitchens

| Material 3 Expressive | Fluent 2 | Primer |
|:---:|:---:|:---:|
| <img src="images/material.png" alt="Material 3 buttons in every state"> | <img src="images/fluent.png" alt="Fluent 2 buttons in every state"> | <img src="images/primer.png" alt="Primer buttons in the dark theme"> |
| `just material-kitchen` | `just fluent-kitchen` | `just primer-kitchen` |

Each kitchen shows every component of its system, a page each, in all its spec states. Fluent shows
all five of its themes and Primer all fourteen. `just material-png Chips` and its siblings
render one page to `build/`. The sources are `examples/material-kitchen`,
`examples/fluent-kitchen` and `examples/primer-kitchen`.

### Text lab

<img src="images/text-lab.png" alt="The text lab's Bidi page: Hebrew, Arabic and mixed runs with clusters and caret stops drawn over them" width="100%">

Text specimens in many scripts and directions, with the shaper's clusters, glyph origins and caret
stops drawn over them. `just text-lab`, or `just text-png Scripts` for one page ·
`examples/text-lab`

> [!NOTE]
> The lab draws a script in the default font when no installed font covers it. On a machine
> without Noto fonts, several of its script samples show missing-glyph boxes.

### Hot-reload demos

| Live architecture diagram | The subprocess split |
|:---:|:---:|
| <img src="images/hot-architecture.png" alt="jm:ui's own pipeline drawn as a diagram"> | <img src="images/hotreload-diagram.png" alt="The host and subprocess split drawn as a diagram"> |
| `just hot-architecture` | `examples/hotreload-diagram` |

`examples/hot-architecture` is a live-editable diagram of jm:ui's own pipeline, and
`examples/hot-counter` is the smallest hot-reloaded app: a two-binary click counter.

<img src="images/hot-counter.png" alt="The hot counter: minus, count 0, plus" width="360">

## Test it without a window

Every stage of a frame is an array with a text dump, so a frame can be asserted on, serialized (`encode`)
for a renderer in another process, or driven by `ui.Probe` with no window at all.

```
build/debug/material-kitchen-child -page Buttons -dump          the scene as text
build/debug/material-kitchen-child -page Menus -click Edit -events   click by tag, list what it routed
build/debug/material-kitchen-child -page Buttons -png out.png   render it headlessly
```

| To check | Use | Why |
|----------|-----|-----|
| Structure and text | `-dump` | Free of vision tokens, and enough for most bugs |
| Pixels | `-png` | When the question is actually about pixels |
| What changed | `tools/img-diff` | Turns two PNGs into a list of changed regions as text |

`tools/img-diff` is built over `ui/render`'s `diff_files`. Confirming an edit changed what it
should needs looking at neither picture.

### Record a session, replay it, scrub through it

`JM_UI_RECORD=path` makes a running app write every frame's input to `path`: its events, size, dt,
and the shapes the application answered. Since the shapes are in the recording, a replay needs no
application, and it runs nothing a command would have done. A frame is a function of that data, so
the app's headless binary replays it exactly:

```
JM_UI_RECORD=build/session.rec just material-kitchen       use it, then close it
build/debug/material-kitchen-child -replay build/session.rec -dump        the last frame
build/debug/material-kitchen-child -replay-to build/session.rec 40 -png out.png   frame 40
build/debug/material-kitchen-child -bless build/session.rec      keep each frame's digest
build/debug/material-kitchen-child -check build/session.rec      fail on the first that differs
build/debug/material-kitchen-child -scrub build/session.rec      step through it in a window
build/debug/material-kitchen-child -timeline build/session.rec   the frames where something happened
build/debug/material-kitchen-child -diff build/session.rec 22    what frame 22 changed
```

A recording is also a regression test. `-bless` writes `session.rec.digests`, one hash per frame
of what that frame shows: its draws, clips and semantic tree. Area ids are left out, because they
hash the source line. Editing code that moves a line, or building in another folder, therefore
keeps the digests. Commit both files; `-check` replays the recording and names the first frame that
looks or reads differently, which `-replay-to` then shows.

`-timeline` and `-diff` give the same view as text, for a reader who cannot watch the window.
`-timeline` lists a line for each frame where the picture changed, the input did something other
than move the pointer, or the digest differs from the blessed one. A press that changed nothing
still gets a line, without `changed`. An animation's run of changing frames is a single line.
`-diff` prints a frame's input and the lines of its picture that differ from the frame before.
Paths, glyph runs and clips are named by what they are, not by their index, so a press reads as a
handful of lines: a state layer's alpha, a ripple, a focus ring.

```
22  0.367 s  changed  Move 220,330  Press 220,330
24-52  0.400-0.867 s  changed on all 29
```

`jm:ui/scrub` is the scrubber. It replays the recording once and keeps each distinct picture, so
it can go backwards without rewinding the app.

| Input | What it does |
|-------|--------------|
| Left, Right | Step one frame |
| Shift+Left, Shift+Right | Jump to the previous or next change |
| Home, End | Go to the first or last frame |
| Space | Play at the recorded pace |
| Press or drag on the timeline | Seek |

The timeline marks each change, and marks in red each frame `-check` would fail. The pointer over
the picture inspects that frame: the widget, its source line and its box. Any app with a headless
main gets these steps from `render.headless_step` and `scrub.run`; the kitchens wire up all of
them.

## Data in, data out

A frame is a function of plain data, and the data goes both ways.

| Direction | What crosses |
|-----------|--------------|
| In | The host's input, and shapes: the answers to what the frame needed |
| Out | The scene, what to persist, requests of the platform (clipboard, a URL), needs, and commands |

A **need** is a query the frame records with `ui.need` and reads the delivered shape for. A
**command** is a value for the application to process, sent with `ui.command`. The application
never addresses the ui, so a row scrolled out of view releases its avatar with no cleanup in the
widget.

```odin
page, status := ui.need(gtx, shapes.Users_Page{page = m.page, size = 50}, shapes.Users_Page_Result)
if status == .Missing || status == .Loading { skeleton(gtx); return }
for row in page.rows {
	s := ui.scope_open(gtx, row.id); defer ui.scope_close(&s)
	avatar, av := ui.need(gtx, shapes.Avatar{user = row.id, px = 48}, shapes.Avatar_Result)
	if m3.button(gtx, "Delete") { ui.command(gtx, shapes.Delete_User{id = row.id}) }
}
```

<details>
<summary>Under the hood: how needs and commands travel</summary>

A need is a value of a type the application's contract declares. Needs and commands cross the
boundary as kind and cbor bytes, so `ui` knows nothing of the contract's types. The application
answers needs through an `Inbox` from any thread and sees commands through a `Data_Host` on the
loop's thread.

The need set is rebuilt every frame and `Subscriptions` diffs it, so a host starts what appeared
and cancels what went. `ui/shell`'s `App` and `Host_App` and `ui/child`'s `App` each carry a
`Data_Host`. Over the hot-reload wire the child sends its need diff and commands with each reply,
and the host's answers ride the next input, so the application can live in either process.

`ui.Probe` delivers shapes and reads needs and commands, which is how a frame is tested with no
application linked: `ui/need_test.odin` is the model.

</details>

## Hot reload

A host owns the window and renders. A subprocess owns the model and the ui proc, and the host
respawns it whenever a build succeeds. The window never closes and a crash in the app never takes
it down.

`just material-kitchen`, `just fluent-kitchen` and `just text-lab` build and open their own host.
`just hot-architecture` builds its host and prints the two commands that run it.

<details>
<summary>Under the hood: the host, the child and the watcher</summary>

The host is `ui/shell.run_host`. The subprocess (`ui/child`) owns the Model, the ui proc, `Router`
and `Layout`, and the two talk `ui/wire`'s Input/Reply over `ui/ipc`'s pipes.

`Host_App.watch` names a pointer file a builder republishes on every successful build;
`tools/hot-watch` is one. The host re-reads it and respawns the child on a change, never
overwriting a running executable in place, which Windows refuses.

`tools/hot-watch` takes extra directories to watch after the pointer file, so a child rebuilds when
the `ui` package it imports is edited too. With `-host` it rebuilds the host as well, which
restarts itself when the ops encoding changed under it. `just fluent-kitchen` and
`just material-kitchen` also watch `examples/kitchen`, the state grid, session and command line
both kitchens draw on.

</details>

## Design systems

`ui` itself has layout, input, text and paint, and no look of its own. The design systems sit on
the shared `ui/design` layer.

| Package | What it is |
|---------|------------|
| `ui/base` | The smallest design system: a checked palette, label, divider, panel |
| `ui/material` | Material 3 Expressive, in full |
| `ui/fluent` | Fluent 2, in full |
| `ui/primer` | GitHub's Primer, in full |

A zero field in a style struct takes the theme's value.

## How a frame is drawn

A ui proc records scene ops. `flatten` turns them into a draw list and a hit list. `ui/render`
executes the draw list on Blend2D while the router hit-tests the hit list.

<details>
<summary>Under the hood: rendering, text and accessibility</summary>

**Clipping** is exact for any shape under any affine. Blend2D clips only to rectangles, so a path
or rotated clip renders through an A8 mask.

**Blend2D.** The binding is copied from `odin-blend2d`. `just blend2d` fetches the upstream Blend2D
and asmjit commits it was generated from and builds the archive. Its foreign import names the C++
runtime, so `-collection:jm=` alone builds a program that links it.

**Text** is shaped by kb_text_shape, vendored upstream at a pinned commit in `ui/kb/vendor` (zlib
licence). `just kb` builds it, and `JM_UI_SHAPER=blend2d` shapes with Blend2D's own shaper
instead, to compare.

**Accessibility.** Assistive technology reads the widgets' semantics (`ui.semantics`) through
AccessKit (`ui/accesskit`, Apache-2.0 or MIT). `just accesskit` fetches the upstream release's
prebuilt library rather than building it, so no Rust toolchain is needed:

| Platform | Library | Protocol |
|----------|---------|----------|
| Linux | static archive | AT-SPI2 |
| macOS | static archive | NSAccessibility |
| Windows | DLL beside the executable | UI Automation |

</details>

## See also

- [Packages](packages.md): every `ui/…` package and what it does
- [Streams](streams.md): the pipelines the example apps run on
- [Building and testing](building.md): the UI recipes and release builds
