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
import "core:mem/virtual"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "jm:ui"
import "jm:ui/base"
import "jm:ui/child"
import "jm:ui/design"
import "jm:ui/ops"
import "jm:ui/render"
import "jm:ui/scrub"

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
	ui.row(gtx)
	ui.spacer(gtx, LABEL_W)
	for name in STATE_NAMES {
		ui.flexible(gtx, 1)
		ui.stack(gtx)
		base.label(gtx, name, {size = 12, color = base.color(.Muted)})
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
		ui.column(gtx, gap = 8, key = key)
		base.label(gtx, label, {size = 12})
		ui.wrap(gtx, gap = 24, line_gap = 12, align = .End)
		for st, i in design.STATES {
			ui.column(gtx, gap = 4, key = u64(i))
			base.label(gtx, STATE_NAMES[i], {size = 12, color = base.color(.Muted)})
			cell(gtx, user, st, key * 16 + u64(i))
		}
		return
	}
	ui.row(gtx, align = .Center, key = key)
	{
		ui.sized(gtx, {min = {LABEL_W, 0}, max = {LABEL_W, ui.INF}})
		base.label(gtx, label, {size = 12, color = base.color(.Muted)})
	}
	for st, i in design.STATES {
		ui.flexible(gtx, 1)
		ui.stack(gtx, key = u64(i))
		cell(gtx, user, st, key * 16 + u64(i))
	}
}

// page_todo stands in for a page whose component is not built yet, or
// for a group heading picked from the list.
page_todo :: proc(gtx: ^ui.Ctx, name: string, heading: bool) {
	ui.column(gtx, gap = 8)
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
// live in user, so the command line can pick them. flag, if set, is the
// kitchen's own setting flags (see Flag).
App :: struct {
	ui:     proc(gtx: ^ui.Ctx, user: rawptr),
	user:   rawptr,
	fonts:  []ops.Font_Ref,
	size:   ops.Size,
	pages:  []string,
	themes: []string,
	page:   ^int,
	theme:  ^int,
	flag:   Flag,
	data:   ^Data_Host, // the application answering the pages' needs, if any
}

// Data_Host is ui's, named here because App's field ui hides the package.
Data_Host :: ui.Data_Host

// Flag applies a kitchen's own setting flag at args[i^] to user, moving
// i^ past any value it takes, and reports whether it was one. run tries
// it after its own settings and before ui/render's steps; like -page, it
// may come anywhere, and a frame runs after it so a later step sees it.
Flag :: proc(user: rawptr, args: []string, i: ^int) -> bool

// run is a kitchen's main: with no arguments it is the hot-reload host's
// child; with -lint alone it prints lint's lines for every page and
// theme; with -scrub PATH alone it opens the replay scrubber on the
// recording at PATH (jm:ui/scrub); otherwise it renders headlessly, running its flags in order:
// the size (-size WxH), whole-page capture (-full) and debug overlays
// (-reveal, -bounds) before any step; the page (-page), theme (-theme)
// and the kitchen's own flags (App.flag) anywhere, so one run can capture
// several; and ui/render's headless steps (-png, -dump, -click, -key,
// -advance, -layout, -inspect...). A step runs only the frames it needs
// (see render.headless_step), so `-click Edit -png` captures the frame
// the click produced, mid-animation; a setting after the first step runs
// one frame so the next step sees it.
run :: proc(app: App) {
	if len(os.args) == 1 {
		host := app.data^ if app.data != nil else {}
		child.run({ui = app.ui, user = app.user, fonts = app.fonts, data = host})
		return
	}
	if len(os.args) == 3 && os.args[1] == "-scrub" {
		// Alone: the recording began with the kitchen as it starts.
		if !scrub.run({ui = app.ui, user = app.user, fonts = app.fonts}, os.args[2]) {
			os.exit(1)
		}
		return
	}
	if len(os.args) == 2 && os.args[1] == "-lint" {
		lines, renders := lint(app)
		for line in lines {
			fmt.println(line)
		}
		fmt.eprintfln("lint: %d line(s) from %d page and theme renders", len(lines), renders)
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
			render.headless_init(&h, app.ui, app.user, size, app.fonts, debug, full = full, data = app.data)
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
		return app.flag != nil && app.flag(app.user, args, i)
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

// group_stop_violations renders every page of app headlessly and lists,
// a line each prefixed with the page, the groups holding more than one
// Tab stop (ui.group_stop_report): a tab list, radio group, toolbar,
// tree, menu or listbox whose widget forgot its roving focus scope. Each
// kitchen's tests assert it is empty, and that groups, how many groups
// held a stop across the pages, is not 0: that the check ran. The lines
// are on allocator.
group_stop_violations :: proc(app: App, allocator := context.allocator) -> (lines: []string, groups: int) {
	h: render.Headless
	render.headless_init(&h, app.ui, app.user, app.size, app.fonts)
	defer render.headless_destroy(&h)
	out := make([dynamic]string, allocator)
	for name, i in app.pages {
		app.page^ = i
		ui.probe_frame(&h.p) // draws the page
		ui.probe_frame(&h.p) // routes against it
		found, seen := ui.group_stop_report(ui.probe_current(&h.p), &h.p.router, context.temp_allocator)
		for line in found {
			append(&out, fmt.aprintf("%s: %s", name, line, allocator = allocator))
		}
		groups += seen
	}
	return out[:], groups
}

// lint renders every page of app in every theme headlessly and lists, a
// line each prefixed with the page, what a reader would otherwise find by
// looking at a PNG: draws the window or a clip cuts off at a side
// (ui.frame_overflow), with the themes that cut them, and groups holding
// more than one Tab stop (ui.group_stop_report). A line names no
// coordinates, so an animation's moving draw stays one line; `-page P
// -overflow` gives them. Some cuts are meant, a shimmer or a cover-fit
// image, so each kitchen keeps the lines it accepts in its lint.txt and
// its test fails on any other. renders counts the page and theme pairs
// drawn, so an empty list can be told from a check that never ran. The
// lines are on allocator, sorted.
lint :: proc(app: App, allocator := context.allocator) -> (lines: []string, renders: int) {
	h: render.Headless
	render.headless_init(&h, app.ui, app.user, app.size, app.fonts)
	defer render.headless_destroy(&h)
	// Scratch is its own arena, freed per page, so lint never frees the
	// temp allocator a caller's lines may be on.
	arena: virtual.Arena
	if err := virtual.arena_init_growing(&arena); err != nil {
		fmt.panicf("lint: scratch arena: %v", err)
	}
	defer virtual.arena_destroy(&arena)
	scratch := virtual.arena_allocator(&arena)
	out := make([dynamic]string, allocator)
	for page, i in app.pages {
		app.page^ = i
		// Each cut, in the order first met, and the themes it is in.
		found := make([dynamic]string, scratch)
		themes := make(map[string][dynamic]string, scratch)
		for theme, j in app.themes {
			app.theme^ = j
			ui.probe_frame(&h.p) // draws the page
			ui.probe_frame(&h.p) // routes against it
			renders += 1
			f := ui.probe_current(&h.p)
			for o in ui.frame_overflow(f, h.p.size, scratch) {
				left := o.bounds.x < o.visible.x - ui.OVERFLOW_SLOP
				right := o.bounds.x + o.bounds.w > o.visible.x + o.visible.w + ui.OVERFLOW_SLOP
				side := "both sides" if left && right else "the left" if left else "the right"
				msg := fmt.aprintf("%s cut at %s near %q", o.kind, side, o.near, allocator = scratch)
				if msg not_in themes {
					append(&found, msg)
					themes[msg] = make([dynamic]string, scratch)
				}
				// A cut repeats when identical draws do, as rows do.
				if list := &themes[msg]; len(list) == 0 || list[len(list) - 1] != theme {
					append(list, theme)
				}
			}
			if j == 0 { // Tab stops do not change with the theme
				stops, _ := ui.group_stop_report(f, &h.p.router, scratch)
				for line in stops {
					append(&out, fmt.aprintf("%s: %s", page, line, allocator = allocator))
				}
			}
		}
		for msg in found {
			in_themes := themes[msg][:]
			cut_in := "every theme" if len(in_themes) == len(app.themes) else strings.join(in_themes, ", ", scratch)
			append(&out, fmt.aprintf("%s: %s (%s)", page, msg, cut_in, allocator = allocator))
		}
		virtual.arena_free_all(&arena)
	}
	slice.sort(out[:])
	return out[:], renders
}

// lint_unaccepted is lines less those in accepted, lint.txt's text: what
// a change newly cut off or ungrouped.
lint_unaccepted :: proc(lines: []string, accepted: string, allocator := context.allocator) -> []string {
	known := make(map[string]bool, context.temp_allocator)
	rest := accepted
	for line in strings.split_lines_iterator(&rest) {
		known[line] = true
	}
	out := make([dynamic]string, allocator)
	for line in lines {
		if !known[line] {
			append(&out, line)
		}
	}
	return out[:]
}
