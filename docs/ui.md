# UI

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

`examples/todo` is the whole of it as an application: TodoMVC in Fluent,
with SQLite as the data engine and a stream pipeline joining four threads.
`shapes` is the contract; `view` the frame, which imports the contract and
jm:ui and nothing else; `logic` the rules, pure, a request in and a write
or a problem out; `store` the connection and its thread, a pipeline stage
pinned to it, whose update hook buffers each row a statement touches and
whose commit hook pushes the batch into a port (the rollback hook drops
it); `app` the host that wires them, a worker thread for the rules and a
pool for the rest; `main` the window. A need for a filter subscribes a
query the pipeline re-runs on every change batch while the need is live.
Problems are never stored: a fold in the pipeline keeps the list and
delivers it as a shape. `just test examples/todo/app` runs the view in a
probe against the real pipeline, threads and database, with no window.

```
just todo                        todo.db in the working directory
just todo -memory                a database gone when the window closes
just todo-test                   its suites, the last on real threads and a database
```

`examples/gallery` is the same model with work that takes time: a grid of
ten thousand pictures, each made on a worker thread when its row comes
into view. `ui.list` lays out only the rows in view, so a tile's need
appears as it scrolls in and goes as it scrolls out; the host starts a
job after a short quiet, sets the job's cancel flag when the need goes,
and the generator checks the flag every row and gives up. A tile is blank
for 150 ms, then a skeleton, then its picture; the header counts what was
made and what was abandoned. A click opens the picture over the window,
where the wheel zooms about the pointer and a drag pans, as a map does:
the picture at each zoom level is a grid of patches, each a need of its
own made on a worker as it comes into view and given up as it leaves,
with the level below kept until the new one is whole, so the zoom streams
in square by square as deep as f64 can go. A stream asks a cache before
it makes a picture: the files the generator wrote, 10 MB of them, least
recently used out first and never one a frame still needs; the header
counts the streams open, the pictures made and abandoned, and the
cache's images, bytes, hits, misses and evictions.

`examples/files` is the same model over the real filesystem, built from
Fluent's own parts: a toolbar with the folder's breadcrumb and a search
box, a table that sorts by its columns with a thumbnail in each picture's
row, and a details card for the selection. A folder's listing and each
thumbnail are needs, read and made on worker threads as they come into
view, with Blend2D decoding the pictures. A double click on a folder goes
into it, keeping the old listing drawn until the new one lands; a double
click on a file is a command the application carries out by asking the
system to open it. The mouse's back and forward buttons, Alt with an
arrow, and the toolbar's buttons walk the folders visited: the side
buttons reach the ui as keys the frame asks for app-wide, as a browser
takes them. A sidebar lists the standard places, the folders pinned and
the places visited lately; pins and visits are commands the application
keeps in SQLite on its own thread, a pinned pipeline stage as in the todo
app, whose commit hook re-runs the pins query, so a pin shows the moment
it is committed, while Recent is a snapshot from when the sidebar first
asked, so it holds still as you click. `just files`
opens the home folder, `just files <path>` another, `just files-test`
runs its suites, the last on a real folder. `just gallery` opens it,
`just gallery-test` runs its suites, the last against the real workers
and files.

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
encoding changed under it. `just fluent-kitchen` and
`just material-kitchen` also watch `examples/kitchen`, the state grid,
session and command line both kitchens draw on.

Checking a change without a window: `-dump` prints the scene as text,
free of vision tokens and enough for most bugs; `-png` renders it to a
PNG when the question is actually about pixels; `tools/img-diff` (over
`ui/render`'s `diff_files`) turns two PNGs into a list of changed regions
as text, so confirming an edit changed what it should needs looking at
neither.
