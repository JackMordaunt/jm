/*
Package kitchen is what the design-system kitchens share, whatever the
system: the state grid every page lays a component's variants out on,
the session that survives a hot-reload respawn, and the command line that
renders a page headlessly. A kitchen supplies its pages, its themes and
its ui proc; this package draws its scaffolding in ui/base's widgets,
which every system maps its theme onto, so the grid sits in the active
system's colours.

	kitchen.run({ui = kitchen_ui, user = &m, fonts = fonts, pages = names, themes = themes, page = &m.page, theme = &m.theme})
*/
package kitchen

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "jm:ui"
import "jm:ui/base"
import "jm:ui/child"
import "jm:ui/design"
import "jm:ui/ops"
import "jm:ui/render"

// MAX_PAGES sizes the per-page state a kitchen keeps: it cannot be a
// kitchen's page count, since its pages' procs take its model.
MAX_PAGES :: 128

// STATE_NAMES heads a state grid's columns, one per design.STATES.
STATE_NAMES := [len(design.STATES)]string{"Enabled", "Hovered", "Focused", "Pressed", "Disabled"}

// LABEL_W is the width of a state grid's row-label column.
LABEL_W :: f32(110)

// CELL_W is the width a state grid's cell needs by default: a grid whose
// states fit beside the labels at this width lays out as columns, and one
// that does not stacks (see state_row).
CELL_W :: f32(130)

// grid_stacked reports whether a state grid of cell_w cells is too wide
// for the width it is offered, so each row must stack instead.
grid_stacked :: proc(gtx: ^ui.Ctx, cell_w: f32) -> bool {
	return gtx.constraints.max.x < LABEL_W + f32(len(design.STATES)) * cell_w
}

// section is a titled block: a subtitle, then a caption note.
section :: proc(gtx: ^ui.Ctx, title: string, note := "") {
	ui.spacer(gtx, 12)
	base.label(gtx, title, {size = 16})
	if note != "" {
		base.label(gtx, note, {size = 12, color = base.color(.Muted)})
	}
}

// state_header is the column headings of a state grid; a stacked grid
// has none, as each of its cells carries its own.
state_header :: proc(gtx: ^ui.Ctx, cell_w := CELL_W) {
	if grid_stacked(gtx, cell_w) {
		return
	}
	r := ui.row_open(gtx)
	defer ui.close(&r)
	ui.spacer(gtx, LABEL_W)
	for name in STATE_NAMES {
		ui.flexible(gtx, 1)
		c := ui.stack_open(gtx)
		base.label(gtx, name, {size = 12, color = base.color(.Muted)})
		ui.close(&c)
	}
}

// State_Cell draws one component in state; user is the kitchen's model
// and key tells the cells apart.
State_Cell :: proc(gtx: ^ui.Ctx, user: rawptr, state: design.Interaction, key: u64)

// state_row is one variant across every forced state. Where the cells do
// not fit beside the label (see grid_stacked), the label takes its own
// line and the cells, each captioned with its state, wrap below it: the
// grid reflows rather than overflow the window.
state_row :: proc(gtx: ^ui.Ctx, user: rawptr, label: string, cell: State_Cell, key: u64, cell_w := CELL_W) {
	if grid_stacked(gtx, cell_w) {
		col := ui.column_open(gtx, gap = 8, key = key)
		defer ui.close(&col)
		base.label(gtx, label, {size = 12})
		wr := ui.wrap_open(gtx, gap = 24, line_gap = 12, align = .End)
		defer ui.close(&wr)
		for st, i in design.STATES {
			c := ui.column_open(gtx, gap = 4, key = u64(i))
			base.label(gtx, STATE_NAMES[i], {size = 12, color = base.color(.Muted)})
			cell(gtx, user, st, key * 16 + u64(i))
			ui.close(&c)
		}
		return
	}
	r := ui.row_open(gtx, align = .Center, key = key)
	defer ui.close(&r)
	{
		c := ui.sized_open(gtx, {min = {LABEL_W, 0}, max = {LABEL_W, ui.INF}})
		base.label(gtx, label, {size = 12, color = base.color(.Muted)})
		ui.close(&c)
	}
	for st, i in design.STATES {
		ui.flexible(gtx, 1)
		c := ui.stack_open(gtx, key = u64(i))
		cell(gtx, user, st, key * 16 + u64(i))
		ui.close(&c)
	}
}

// page_todo stands in for a page whose component is not built yet, or
// for a group heading picked from the list.
page_todo :: proc(gtx: ^ui.Ctx, name: string, heading: bool) {
	col := ui.column_open(gtx, gap = 8)
	defer ui.close(&col)
	if heading {
		base.label(gtx, fmt.tprintf("%s: pick a component below this heading.", name), {color = base.color(.Muted)})
		return
	}
	base.label(gtx, "Not built yet.", {size = 16})
}

// Session is the state that survives a respawn, as ui.persist_struct
// writes it: `page 3`, `theme 2`, `scroll[3].y 240`.
Session :: struct {
	page:   int,
	theme:  int,
	scroll: [MAX_PAGES]ui.Scroll_Offset,
}

// persist writes a kitchen's session for the next respawn.
persist :: proc(gtx: ^ui.Ctx, page, theme: int, scroll: ^[MAX_PAGES]ui.Scroll_Offset) {
	ui.persist_struct(gtx, Session{page, theme, scroll^})
}

// restore reads back the session a respawn kept. A kitchen rebuilt with
// fewer pages or themes than the session names lands on its last one.
restore :: proc(gtx: ^ui.Ctx, page, theme: ^int, scroll: ^[MAX_PAGES]ui.Scroll_Offset, pages, themes: int) {
	s := Session{page^, theme^, scroll^}
	if ui.restore_struct(gtx, &s, gtx.allocator) {
		page^ = clamp(s.page, 0, pages - 1)
		theme^ = clamp(s.theme, 0, themes - 1)
		scroll^ = s.scroll
	}
}

// App is a kitchen as run sees it: its ui proc over user, its fonts, the
// names of its pages and themes, and where the current page and theme
// live in user, so the command line can pick them.
App :: struct {
	ui:     proc(gtx: ^ui.Ctx, user: rawptr),
	user:   rawptr,
	fonts:  []ops.Font_Ref,
	size:   ops.Size,
	pages:  []string,
	themes: []string,
	page:   ^int,
	theme:  ^int,
}

// run is a kitchen's main: with no arguments it is the hot-reload host's
// child; otherwise it renders headlessly, running its flags in order:
// the size (-size WxH), whole-page capture (-full) and debug overlays
// (-reveal, -bounds) before any step; the page (-page) and theme (-theme)
// anywhere, so one run can capture several; and ui/render's headless
// steps (-png, -dump, -click, -key, -advance, -layout, -inspect...).
run :: proc(app: App) {
	if len(os.args) == 1 {
		child.run({ui = app.ui, user = app.user, fonts = app.fonts})
		return
	}
	args := os.args[1:]
	size := app.size
	debug: ui.Debug_Flags
	full := false
	h: render.Headless
	open := false
	defer if open {
		render.headless_destroy(&h)
	}
	for i := 0; i < len(args); i += 1 {
		if setting(args, &i, app, open, &size, &debug, &full) {
			if open {
				ui.probe_frame(&h.p)
			}
			continue
		}
		if !open {
			render.headless_init(&h, app.ui, app.user, size, app.fonts, debug, full = full)
			open = true
		}
		handled, ok := render.headless_step(&h, args, &i)
		if !handled {
			fmt.eprintfln("unknown flag %s", args[i])
			os.exit(2)
		}
		if !ok {
			os.exit(1)
		}
		ui.probe_frame(&h.p)
	}
}

// setting applies the setting flag at args[i^], moving i^ past its value,
// and reports whether it was one. A setup flag after the first step (open)
// is refused: the headless renderer is already made.
@(private)
setting :: proc(args: []string, i: ^int, app: App, open: bool, size: ^ops.Size, debug: ^ui.Debug_Flags, full: ^bool) -> bool {
	switch args[i^] {
	case "-reveal", "-bounds", "-full", "-size":
		if open {
			fmt.eprintfln("%s must come before the first step", args[i^])
			os.exit(2)
		}
	}
	switch args[i^] {
	case "-reveal":
		debug^ += {.Reveal}
	case "-bounds":
		debug^ += {.Bounds}
	case "-full":
		full^ = true
	case "-size":
		w, _, h := strings.partition(value(args, i), "x")
		size^ = {f32(parse_int(w)), f32(parse_int(h))}
		if size.x <= 0 || size.y <= 0 {
			fmt.eprintln("-size needs WxH, e.g. 950x1040")
			os.exit(2)
		}
	case "-theme":
		app.theme^ = pick(app.themes, value(args, i), "theme")
	case "-page":
		app.page^ = pick(app.pages, value(args, i), "page")
	case:
		return false
	}
	return true
}

// value is the argument after flag args[i^], moving i^ onto it.
@(private)
value :: proc(args: []string, i: ^int) -> string {
	if i^ + 1 >= len(args) {
		fmt.eprintfln("%s needs a value", args[i^])
		os.exit(2)
	}
	i^ += 1
	return args[i^]
}

// pick is the index of name in names, case-insensitively.
@(private)
pick :: proc(names: []string, name, what: string) -> int {
	for n, j in names {
		if strings.equal_fold(n, name) {
			return j
		}
	}
	fmt.eprintfln("no %s %q", what, name)
	os.exit(2)
}

// parse_int is s as a non-negative integer, 0 for anything else.
parse_int :: proc(s: string) -> int {
	n, ok := strconv.parse_int(s, 10)
	return n if ok && n >= 0 else 0
}
