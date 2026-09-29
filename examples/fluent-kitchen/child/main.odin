// The Fluent 2 kitchen: every component in jm:ui/fluent, one page each,
// picked from the list on the left. Each page shows a component's
// variants against every spec state (enabled, hovered, focused, pressed,
// disabled — forced, so they sit side by side), plus a live row to poke.
// The theme button cycles the kit's five themes.
//
//	fluent-kitchen-child                                run as the hot-reload subprocess
//	fluent-kitchen-child -page Buttons -png out.png     render one page headlessly
//	fluent-kitchen-child -theme "Web dark" ...          another theme (see fluent.THEME_NAMES)
//	fluent-kitchen-child -size 950x1040 ...             at another window size
//	fluent-kitchen-child -full -page Buttons -png out.png  the whole page, trimmed
//
// The rest of the flags are ui/render's headless steps, as in
// examples/material-kitchen: -dump, -click, -key, -advance, -layout,
// -inspect, -reveal and -bounds. The selected page and theme survive a
// hot-reload respawn through build/debug/fluent-kitchen.state.
package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "jm:ui"
import "jm:ui/base"
import "jm:ui/child"
import "jm:ui/fluent"
import "jm:ui/ops"
import "jm:ui/render"

WIDTH :: 1400
HEIGHT :: 900
STATE_FILE :: "build/debug/fluent-kitchen.state"
NAV_WIDTH :: 220

Page :: struct {
	name: string,
	draw: proc(gtx: ^ui.Ctx, m: ^Model), // nil for a group heading or a component not built yet
	head: bool,
}

Model :: struct {
	page:      int,
	theme:     fluent.Theme,
	scheme:    fluent.Scheme,
	clicks:    int,
	persisted: [2]int,
}

// PAGES follows the fluent-kit's component index, grouped by the plan's
// build order; a nil draw under a heading is a component not built yet.
PAGES := [?]Page {
	{"Buttons", nil, true},
	{"Button", page_buttons, false},
	{"Toggle button", nil, false},
	{"Split button", nil, false},
	{"Menu button", nil, false},
	{"Compound button", nil, false},
	{"Form controls", nil, true},
	{"Checkbox", nil, false},
	{"Radio group", nil, false},
	{"Switch", nil, false},
	{"Slider", nil, false},
	{"Inputs", nil, true},
	{"Input", nil, false},
	{"Textarea", nil, false},
	{"Field", nil, false},
	{"Label", nil, false},
	{"Link", nil, false},
	{"Containers", nil, true},
	{"Card", nil, false},
	{"Divider", nil, false},
	{"Tab list", nil, false},
	{"Toolbar", nil, false},
	{"Accordion", nil, false},
	{"Feedback", nil, true},
	{"Badge", nil, false},
	{"Avatar", nil, false},
	{"Progress bar", nil, false},
	{"Spinner", nil, false},
	{"Overlays", nil, true},
	{"Menu", nil, false},
	{"Dialog", nil, false},
	{"Tooltip", nil, false},
}

kitchen_ui :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Model)(user)
	m.scheme = fluent.theme_scheme(m.theme)
	fluent.use(&m.scheme, fluent.mode_of(m.theme))
	fluent.use_fonts({0, 1, 2})
	s := &m.scheme
	ops.fill(gtx.scene, ops.Rect{0, 0, gtx.constraints.max.x, gtx.constraints.max.y}, s[.Neutral_Background2])

	r := ui.row_open(gtx, align = .Fill)
	defer ui.close(&r)
	nav(gtx, m)
	ui.flexible(gtx, 1)
	body := ui.column_open(gtx)
	defer ui.close(&body)
	app_bar(gtx, m)
	ui.flexible(gtx, 1)
	{
		// Each page is a root scope, and every page is retained, drawn or
		// not, so switching away and back keeps its state.
		for i in 0 ..< len(PAGES) {
			ui.retain(gtx, i)
		}
		p := PAGES[clamp(m.page, 0, len(PAGES) - 1)]
		ps := ui.scope_open(gtx, m.page)
		defer ui.close(&ps)
		sb := ui.scroll_box_open(gtx)
		defer ui.close(&sb)
		page := ui.inset_open(gtx, {24, 8, 24, 48})
		defer ui.close(&page)
		if p.draw != nil {
			p.draw(gtx, m)
		} else {
			page_todo(gtx, p)
		}
	}
	persist(m)
}

// nav is the page list: a heading per group in caption text, and a
// subtle button per page, the current one secondary. It stands in for
// a tab list until that component lands.
nav :: proc(gtx: ^ui.Ctx, m: ^Model) {
	s := fluent.scheme()
	panel := ui.box_open(gtx, {fill = s[.Neutral_Background1], padding = ui.pad_all(8)})
	defer ui.close(&panel)
	sb := ui.scroll_box_open(gtx, min_width = NAV_WIDTH)
	defer ui.close(&sb)
	col := ui.column_open(gtx, gap = 2)
	defer ui.close(&col)
	for p, i in PAGES {
		if p.head {
			ui.spacer(gtx, i == 0 ? 4 : 12)
			hd := ui.inset_open(gtx, {12, 0, 0, 4})
			base.label(gtx, p.name, {color = s[.Neutral_Foreground3], size = 12})
			ui.close(&hd)
			continue
		}
		label := p.name
		if p.draw == nil {
			label = fmt.tprintf("%s (soon)", p.name)
		}
		if fluent.button(gtx, label, i == m.page ? .Secondary : .Subtle, size = .Small, key = u64(i)) {
			m.page = i
		}
	}
}

// app_bar is the page title and the theme button.
app_bar :: proc(gtx: ^ui.Ctx, m: ^Model) {
	s := fluent.scheme()
	bar := ui.inset_open(gtx, {24, 12, 16, 8})
	defer ui.close(&bar)
	r := ui.row_open(gtx, align = .Center)
	defer ui.close(&r)
	base.label(gtx, PAGES[clamp(m.page, 0, len(PAGES) - 1)].name, {size = 20, color = s[.Neutral_Foreground1]})
	ui.fill_space(gtx)
	names := fluent.THEME_NAMES
	if fluent.button(gtx, names[m.theme], .Outline, .Settings) {
		m.theme = fluent.Theme((int(m.theme) + 1) % len(fluent.Theme))
	}
}

// Page scaffolding.

// section is a titled block: a subtitle, then a caption note.
section :: proc(gtx: ^ui.Ctx, title: string, note := "") {
	s := fluent.scheme()
	ui.spacer(gtx, 12)
	base.label(gtx, title, {size = 16, color = s[.Neutral_Foreground1]})
	if note != "" {
		base.label(gtx, note, {size = 12, color = s[.Neutral_Foreground2]})
	}
}

STATE_NAMES := [?]string{"Enabled", "Hovered", "Focused", "Pressed", "Disabled"}

// LABEL_W is the width of a state grid's row-label column.
LABEL_W :: 110

// CELL_W is the width a state grid's cell needs by default: a grid whose
// five states fit beside the labels at this width lays out as columns,
// and one that does not stacks (see state_row).
CELL_W :: f32(130)

// grid_stacked reports whether a state grid of cell_w cells is too wide
// for the width it is offered, so each row must stack instead.
grid_stacked :: proc(gtx: ^ui.Ctx, cell_w: f32) -> bool {
	return gtx.constraints.max.x < LABEL_W + f32(len(fluent.STATES)) * cell_w
}

// state_header is the column headings of a state grid; a stacked grid
// has none, as each of its cells carries its own.
state_header :: proc(gtx: ^ui.Ctx, cell_w := CELL_W) {
	if grid_stacked(gtx, cell_w) {
		return
	}
	s := fluent.scheme()
	r := ui.row_open(gtx)
	defer ui.close(&r)
	ui.spacer(gtx, LABEL_W)
	for name in STATE_NAMES {
		ui.flexible(gtx, 1)
		c := ui.stack_open(gtx)
		base.label(gtx, name, {size = 12, color = s[.Neutral_Foreground2]})
		ui.close(&c)
	}
}

// State_Cell draws one component in state; key tells the cells apart.
State_Cell :: proc(gtx: ^ui.Ctx, m: ^Model, state: fluent.Interaction, key: u64)

// state_row is one variant across every forced state, then a gap. Where
// the five cells do not fit beside the label (see grid_stacked), the label
// takes its own line and the cells, each captioned with its state, wrap
// below it: the grid reflows rather than overflow the window.
state_row :: proc(gtx: ^ui.Ctx, m: ^Model, label: string, cell: State_Cell, key: u64, cell_w := CELL_W) {
	s := fluent.scheme()
	if grid_stacked(gtx, cell_w) {
		col := ui.column_open(gtx, gap = 8, key = key)
		defer ui.close(&col)
		base.label(gtx, label, {size = 12, color = s[.Neutral_Foreground1]})
		wr := ui.wrap_open(gtx, gap = 24, line_gap = 12, align = .End)
		defer ui.close(&wr)
		for st, i in fluent.STATES {
			c := ui.column_open(gtx, gap = 4, key = u64(i))
			base.label(gtx, STATE_NAMES[i], {size = 12, color = s[.Neutral_Foreground2]})
			cell(gtx, m, st, key * 16 + u64(i))
			ui.close(&c)
		}
		return
	}
	r := ui.row_open(gtx, align = .Center, key = key)
	defer ui.close(&r)
	{
		c := ui.stack_open(gtx)
		base.label(gtx, label, {size = 12, color = s[.Neutral_Foreground2]})
		ui.close(&c)
	}
	ui.spacer(gtx, max(LABEL_W - label_width(gtx, label), 0))
	for st, i in fluent.STATES {
		ui.flexible(gtx, 1)
		c := ui.stack_open(gtx, key = u64(i))
		cell(gtx, m, st, key * 16 + u64(i))
		ui.close(&c)
	}
}

// label_width is s's advance in the caption style the grid's labels use.
label_width :: proc(gtx: ^ui.Ctx, s: string) -> f32 {
	return fluent.shape_text(gtx, s, .Caption1).width
}

page_todo :: proc(gtx: ^ui.Ctx, p: Page) {
	s := fluent.scheme()
	col := ui.column_open(gtx, gap = 8)
	defer ui.close(&col)
	if p.head {
		base.label(gtx, fmt.tprintf("%s: pick a component below this heading.", p.name), {color = s[.Neutral_Foreground2]})
		return
	}
	base.label(gtx, "Not built yet.", {size = 16, color = s[.Neutral_Foreground1]})
	base.label(gtx, "See the build order in the fluent-kit handoff.", {color = s[.Neutral_Foreground2]})
}

// State that survives a respawn.

persist :: proc(m: ^Model) {
	now := [2]int{m.page, int(m.theme)}
	if now == m.persisted {
		return
	}
	m.persisted = now
	_ = os.write_entire_file(STATE_FILE, transmute([]u8)fmt.tprintf("%d %d", now[0], now[1]))
}

restore :: proc(m: ^Model) {
	data, err := os.read_entire_file(STATE_FILE, context.temp_allocator)
	if err != nil {
		return
	}
	fields := strings.fields(string(data), context.temp_allocator)
	if len(fields) == 2 {
		m.page = clamp(parse_int(fields[0]), 0, len(PAGES) - 1)
		m.theme = fluent.Theme(clamp(parse_int(fields[1]), 0, len(fluent.Theme) - 1))
	}
	m.persisted = {m.page, int(m.theme)}
}

// parse_int is s as a non-negative integer, 0 for anything else.
parse_int :: proc(s: string) -> int {
	n, ok := strconv.parse_int(s, 10)
	return n if ok && n >= 0 else 0
}

// kitchen_fonts is Selawik at regular, semibold and bold (font ids 0, 1,
// 2), the kit's open stand-in for Segoe UI, from the user's font
// directory (just fluent-fonts fetches it), or jm:ui's default font for
// all three.
kitchen_fonts :: proc() -> []ops.Font_Ref {
	dir := strings.concatenate({os.get_env("HOME", context.allocator), "/.local/share/fonts/selawik/"})
	names := [3]string{"selawk.ttf", "selawksb.ttf", "selawkb.ttf"}
	fonts := make([]ops.Font_Ref, 3)
	for n, i in names {
		p := strings.concatenate({dir, n})
		fonts[i] = {ops.Font_Id(i), os.exists(p) ? p : ui.default_font()}
	}
	return fonts
}

main :: proc() {
	m: Model
	m.page = 1
	fonts := kitchen_fonts()
	if len(os.args) == 1 {
		restore(&m)
		child.run({ui = kitchen_ui, user = &m, fonts = fonts})
		return
	}
	args := os.args[1:]
	size := ops.Size{WIDTH, HEIGHT}
	debug: ui.Debug_Flags
	full := false
	h: render.Headless
	open := false
	defer if open {
		render.headless_destroy(&h)
	}
	setup :: proc(open: bool, flag: string) {
		if open {
			fmt.eprintfln("%s must come before the first step", flag)
			os.exit(2)
		}
	}
	for i := 0; i < len(args); i += 1 {
		switch args[i] {
		case "-reveal":
			setup(open, args[i])
			debug += {.Reveal}
		case "-bounds":
			setup(open, args[i])
			debug += {.Bounds}
		case "-full":
			setup(open, args[i])
			full = true
		case "-size":
			setup(open, args[i])
			i += 1
			w, _, ht := strings.partition(i < len(args) ? args[i] : "", "x")
			size = {f32(parse_int(w)), f32(parse_int(ht))}
			if size.x <= 0 || size.y <= 0 {
				fmt.eprintln("-size needs WxH, e.g. 950x1040")
				os.exit(2)
			}
		case "-theme":
			if i + 1 >= len(args) {
				fmt.eprintln("-theme needs a name")
				os.exit(2)
			}
			i += 1
			found := false
			names := fluent.THEME_NAMES
			for name, t in names {
				if strings.equal_fold(name, args[i]) {
					m.theme, found = t, true
				}
			}
			if !found {
				fmt.eprintfln("no theme %q", args[i])
				os.exit(2)
			}
		case "-page":
			if i + 1 >= len(args) {
				fmt.eprintln("-page needs a name")
				os.exit(2)
			}
			i += 1
			found := false
			for p, j in PAGES {
				if strings.equal_fold(p.name, args[i]) {
					m.page, found = j, true
				}
			}
			if !found {
				fmt.eprintfln("no page %q", args[i])
				os.exit(2)
			}
		case:
			if !open {
				render.headless_init(&h, kitchen_ui, &m, size, fonts, debug, full = full)
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
			continue
		}
		if open {
			ui.probe_frame(&h.p)
		}
	}
}
