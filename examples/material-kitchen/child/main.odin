// The Material 3 kitchen: every M3 component in jm:ui/material, one page
// each, picked from a navigation drawer. Each page shows a component's
// variants against every spec state (enabled, hovered, focused, pressed,
// disabled — forced, so they sit side by side), plus a live row to poke.
// Components not built yet show where they sit in the plan.
//
//	material-kitchen-child                                run as the hot-reload subprocess
//	material-kitchen-child -page Buttons -png out.png     render one page headlessly
//	material-kitchen-child -page Buttons -dump            that page's sc as text
//	material-kitchen-child -dark ...                      the dark scheme
//	material-kitchen-child -size 950x1040 ...             at another window size
//	material-kitchen-child -reveal ...                    show what hides until used
//	material-kitchen-child -bounds ...                    outline every widget's box
//	JM_UI_DEBUG=reveal,bounds ...                         either, live or headless
//	F11 in the live window                                the debug tray: toggles, frame and host stats, repaint flash, event log
//	material-kitchen-child -page Chips -key F11 -advance 30 -stats   the tray's stats as text
//	material-kitchen-child -page Menus -click Edit -events   the routed events, each with its target
//	material-kitchen-child -page Chips -layout            every widget's box, constraints and call, as text
//	material-kitchen-child -page Chips -inspect 470 170   the widget and input area under a point
//	material-kitchen-child -page Menus -click Edit -png out.png  click by tag first
//	material-kitchen-child -page Lists -scroll "One line" 3 -advance 30 -png out.png
//	material-kitchen-child -full -page Chips -png out.png  the whole page, trimmed
//	material-kitchen-child -open ...                      every menu, dialog and snackbar open
//
// The selected page and scheme survive a hot-reload respawn through
// build/debug/material-kitchen.state: the child owns the model, and a
// respawn starts a fresh child.
package main

import "core:fmt"
import "jm:ui/ops"
import "core:os"
import "core:strings"
import "jm:ui"
import "jm:ui/base"
import "jm:ui/child"
import m3 "jm:ui/material"
import "jm:ui/render"

WIDTH :: 1400
// DOCKED_NAV_MIN is the narrowest window that keeps the page drawer
// docked beside the page: the m3e-kit foundations.json large window
// class (layout.windowSizeClasses, 1200-1599dp).
DOCKED_NAV_MIN :: 1200
HEIGHT :: 900
STATE_FILE :: "build/debug/material-kitchen.state"

Page :: struct {
	name: string,
	icon: m3.Icon,
	draw: proc(gtx: ^ui.Ctx, m: ^Model),
}

Model :: struct {
	page:      int,
	nav_open:  bool, // the modal page drawer, in a narrow window
	dark:      bool,
	scheme:    m3.Scheme,
	clicks:    int,
	toggles:   [8]bool,
	segments:  [3]bool,
	multi:     [4]bool,
	expanded:  bool,
	checks:    [4]bool,
	radio:     int,
	switches:  [3]bool,
	name:      ui.Text_State,
	email:     ui.Text_State,
	list_sel:  int,
	card_hits: int,
	filters:   [5]bool,
	inputs:    [4]bool, // true once removed
	rail_sel:  int,
	bar_sel:   int,
	tab_a:     int,
	tab_b:     int,
	tab_c:     int,
	window:    ops.Size,
	menu_open: bool,
	menu_pick: string,
	split_menu: bool,
	dialog:    bool,
	dialog2:   bool,
	dialog_msg: string, // a static action label; never a tprintf result, which dies with the frame
	snack:     bool,
	snack_n:   int,
	volume:    f32,
	steps:     f32,
	range_lo:  f32,
	range_hi:  f32,
	group_a:   [3]bool,
	group_b:   [4]bool,
	fab_open:  bool,
	fab_pick:  string,
	tool_sel:  int,
	query:     ui.Text_State,
	bottom:    bool,
	side:      bool,
	date:      m3.Date,
	date_view: m3.Date,
	time:      m3.Time,
	minutes:   bool,
	persisted: [2]int, // page and dark as last written, to write only on change
	// actions
	group_c:       [5]bool,
	group_menu:    bool,
	tool_folded:   bool,
	bab_hide:      f32,
	bab_clicks:    int,
	// buttons
	btn_checked:   [4]bool,
	size_checked:  [4]bool,
	fab_collapsed: bool,
	split_open:    bool,
	// progress
	progress_ready: bool, // init_progress_values has run
	centered:       f32,
	upright:        f32,
	brightness:     f32,
	progress:       f32,
	// navigation
	drawer_sel:    int,
	drawer_open:   bool, // the dismissible drawer
	drawer_modal:  bool,
	rail_plain:    int,
	rail_expanded: bool,
	rail_modal:    bool,
	rail_modal_sel: int,
	bar_flex:      int,
	bar_wide:      int,
	bar_quiet:     int,
	tab_d:         int,
	tab_e:         int,
	// containment
	list_single: int,
	list_multi:  [4]bool,
	list_expand: [2]bool,
	list_order:  [5]int, // task shown in each slot of the reorder list
	reveal_pick: string, // a static action name
	menu_styles: [3]bool, // the standard, vibrant and grouped live menus
	menu_sort:   string, // a static label
	dialog3:     bool,
	snack_t:     f32, // seconds the live snackbar has been up
	snack_short: bool,
	// selection
	agree:         bool,
	fruit:         ui.Text_State,
	fruit2:        ui.Text_State,
	fruit_open:    bool,
	fruit2_open:   bool,
	fruit_pick:    string, // an option literal, never frame memory
	amount:        ui.Text_State,
	amount_clear:  bool,
	morph_filters: [4]bool,
	input_sel:     [4]bool,
	suggestion:    string, // a hint literal
	// surfaces
	queries:     [3]ui.Text_State, // the live search bars after the first (which uses query)
	search_open: [4]bool,
	searched:    bool,
	sheet_value: m3.Sheet_Value,
	bottom_std:  bool,
	side_left:   bool,
	pane:        f32, // the drag-handle demo's left pane width
	date_mode:   m3.Date_Mode,
	date_input:  ui.Text_State,
	date_action: int,
	range_start: m3.Date,
	range_end:   m3.Date,
	range_view:  m3.Date,
	input_mode:  m3.Date_Mode,
	input_text:  ui.Text_State,
	input_date:  m3.Date,
	input_view:  m3.Date,
	times:       [3]m3.Time,
	editing:     [3]bool,
	carousel_hit: int,
}

// PAGES follows m3.material.io/components' own grouping; a nil draw is a
// component not built yet.
PAGES := [?]Page {
	{"Actions", .None, nil},
	{"Buttons", .Smart_Button, page_buttons},
	{"Button sizes", .Smart_Button, page_button_sizes},
	{"Toggle buttons", .Smart_Button, page_toggle_buttons},
	{"Icon buttons", .Favorite, page_icon_buttons},
	{"Icon button sizes", .Favorite, page_icon_button_sizes},
	{"FAB", .Add, page_fab},
	{"Extended FAB", .Edit, page_extended_fab},
	{"Segmented buttons", .View_Agenda, page_segmented},
	{"Split buttons", .Arrow_Drop_Down, page_split},
	{"Button groups", .Widgets, page_button_groups},
	{"FAB menu", .Add, page_fab_menu},
	{"Navigation", .None, nil},
	{"Navigation drawer", .Side_Navigation, page_drawer},
	{"Navigation rail", .Side_Navigation, page_rail},
	{"Navigation bar", .Dock_To_Bottom, page_bar},
	{"App bars", .Web_Asset, page_app_bars},
	{"Tabs", .Tab, page_tabs},
	{"Toolbars", .Tune, page_toolbars},
	{"Bottom app bar", .Dock_To_Bottom, page_bottom_app_bar},
	{"Selection", .None, nil},
	{"Checkbox", .Check_Box, page_checkbox},
	{"Radio button", .Radio_Button_Checked, page_radio},
	{"Switch", .Toggle_On, page_switch},
	{"Chips", .Label, page_chips},
	{"Sliders", .Linear_Scale, page_sliders},
	{"Menus", .More_Vert, page_menus},
	{"Date pickers", .Calendar_Today, page_date_picker},
	{"Time pickers", .Schedule, page_time_picker},
	{"Text inputs", .None, nil},
	{"Text fields", .Text_Fields, page_text_fields},
	{"Search", .Search, page_search},
	{"Containment", .None, nil},
	{"Cards", .Crop_Square, page_cards},
	{"Lists", .List, page_lists},
	{"Dialogs", .Picture_In_Picture, page_dialogs},
	{"Bottom sheets", .Dock_To_Bottom, page_bottom_sheet},
	{"Side sheets", .Side_Navigation, page_side_sheet},
	{"Carousel", .View_Carousel, page_carousel},
	{"Divider", .Table_Rows, page_divider},
	{"Communication", .None, nil},
	{"Badges", .Notifications, page_badges},
	{"Progress indicators", .Progress_Activity, page_progress},
	{"Loading indicator", .Progress_Activity, page_loading},
	{"Snackbar", .Chat_Bubble, page_snackbar},
	{"Tooltips", .Info, page_tooltips},
}

kitchen_ui :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Model)(user)
	m.scheme = m.dark ? m3.dark_scheme() : m3.light_scheme()
	m3.use(&m.scheme, m.dark ? .Dark : .Light)
	m3.use_fonts({0, 1, 2})
	s := &m.scheme
	m.window = gtx.constraints.max
	ops.fill(gtx.scene, ops.Rect{0, 0, gtx.constraints.max.x, gtx.constraints.max.y}, s[.Surface])

	items := make([]m3.Nav_Item, len(PAGES), gtx.allocator)
	for p, i in PAGES {
		items[i] = {label = p.name, icon = p.icon, headline = p.icon == .None}
		if p.icon != .None && p.draw == nil {
			items[i].badge = "soon"
		}
	}

	// Windows narrower than DOCKED_NAV_MIN (a half-screen tile) give the
	// page the whole width: the drawer becomes a modal one, opened from
	// the app bar and closed once a page is picked.
	docked := m.window.x >= DOCKED_NAV_MIN
	r := ui.row_open(gtx, align = .Fill)
	defer ui.close(&r)
	if docked {
		m3.navigation_drawer(gtx, items, &m.page, width = 300)
	} else if m.nav_open {
		if m3.navigation_drawer(gtx, items, &m.page, width = 300, variant = .Modal, open = &m.nav_open) {
			m.nav_open = false
		}
	}
	ui.flexible(gtx, 1)
	body := ui.column_open(gtx)
	defer ui.close(&body)
	app_bar(gtx, m, docked)
	ui.flexible(gtx, 1)
	{
		// Each page is a root scope, and every page is retained, drawn or
		// not: switching away and back keeps its scroll position and any
		// state its widgets hold. The scope also keeps two pages' widgets
		// from sharing ids.
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

// app_bar is a plain small top app bar until the real component lands:
// the page title and a light/dark toggle.
// Undocked, it leads with a menu button that opens the modal drawer.
app_bar :: proc(gtx: ^ui.Ctx, m: ^Model, docked: bool) {
	s := m3.scheme()
	bar := ui.inset_open(gtx, {docked ? 24 : 8, 8, 16, 8})
	defer ui.close(&bar)
	r := ui.row_open(gtx, align = .Center)
	defer ui.close(&r)
	if !docked {
		if m3.icon_button(gtx, .Menu, tooltip = "Pages") {
			m.nav_open = true
		}
		ui.spacer(gtx, 8)
	}
	base.label(gtx, PAGES[clamp(m.page, 0, len(PAGES) - 1)].name, {size = 22, color = s[.On_Surface]})
	ui.fill_space(gtx)
	if m3.icon_button(gtx, m.dark ? .Light_Mode : .Dark_Mode, tooltip = m.dark ? "Light scheme" : "Dark scheme") {
		m.dark = !m.dark
	}
}

// Page scaffolding.

// section is a titled block: Title_Medium caption, then whatever follows.
section :: proc(gtx: ^ui.Ctx, title: string, note := "") {
	s := m3.scheme()
	ui.spacer(gtx, 12)
	base.label(gtx, title, {size = 16, color = s[.On_Surface]})
	if note != "" {
		// Wrapped, not a one-line label: notes run long, and a narrow
		// window must not cut them off.
		m3.wrapped_text(gtx, note, .Body_Small, s[.On_Surface_Variant], gtx.constraints.max.x)
	}
}

STATE_NAMES := [?]string{"Enabled", "Hovered", "Focused", "Pressed", "Disabled"}

// LABEL_W is the width of a state grid's row-label column.
LABEL_W :: 110

// CELL_W is the width a state grid's cell needs by default: a grid whose
// five states fit beside the labels at this width lays out as columns,
// and one that does not stacks (see state_row). Grids of wider components
// pass their own.
CELL_W :: f32(120)

// grid_stacked reports whether a state grid of cell_w cells is too wide
// for the width it is offered, so each row must stack instead.
grid_stacked :: proc(gtx: ^ui.Ctx, cell_w: f32) -> bool {
	return gtx.constraints.max.x < LABEL_W + f32(len(m3.STATES)) * cell_w
}

// state_header is the column headings of a state grid; a stacked grid
// has none, as each of its cells carries its own.
state_header :: proc(gtx: ^ui.Ctx, cell_w := CELL_W) {
	if grid_stacked(gtx, cell_w) {
		return
	}
	s := m3.scheme()
	r := ui.row_open(gtx)
	defer ui.close(&r)
	cell_fixed(gtx, LABEL_W)
	for name in STATE_NAMES {
		ui.flexible(gtx, 1)
		c := ui.stack_open(gtx)
		base.label(gtx, name, {size = 12, color = s[.On_Surface_Variant]})
		ui.close(&c)
	}
}

// cell_fixed takes w of a row's width.
cell_fixed :: proc(gtx: ^ui.Ctx, w: f32, loc := #caller_location) {
	ui.spacer(gtx, w, loc)
}

// State_Cell draws one component in state; key tells the cells apart.
State_Cell :: proc(gtx: ^ui.Ctx, m: ^Model, state: m3.Interaction, key: u64)

// state_row is one variant across every forced state, then a gap. Where
// the five cells do not fit beside the label (see grid_stacked), the label
// takes its own line and the cells, each captioned with its state, wrap
// below it: the grid reflows rather than overflow the window.
state_row :: proc(gtx: ^ui.Ctx, m: ^Model, label: string, cell: State_Cell, key: u64, cell_w := CELL_W) {
	s := m3.scheme()
	if grid_stacked(gtx, cell_w) {
		col := ui.column_open(gtx, gap = 8, key = key)
		defer ui.close(&col)
		base.label(gtx, label, {size = 12, color = s[.On_Surface]})
		wr := ui.wrap_open(gtx, gap = 24, line_gap = 12, align = .End)
		defer ui.close(&wr)
		for st, i in m3.STATES {
			c := ui.column_open(gtx, gap = 4, key = u64(i))
			base.label(gtx, STATE_NAMES[i], {size = 12, color = s[.On_Surface_Variant]})
			cell(gtx, m, st, key * 16 + u64(i))
			ui.close(&c)
		}
		return
	}
	r := ui.row_open(gtx, align = .Center, key = key)
	defer ui.close(&r)
	{
		c := ui.stack_open(gtx)
		base.label(gtx, label, {size = 12, color = s[.On_Surface_Variant]})
		ui.close(&c)
	}
	ui.spacer(gtx, max(LABEL_W - label_width(gtx, label), 0))
	for st, i in m3.STATES {
		ui.flexible(gtx, 1)
		c := ui.stack_open(gtx, key = u64(i))
		cell(gtx, m, st, key * 16 + u64(i))
		ui.close(&c)
	}
}

label_width :: proc(gtx: ^ui.Ctx, s: string) -> f32 {
	return ui.shape(gtx.shaper, gtx.font, 12, s, gtx.allocator).advance
}

gap :: proc(gtx: ^ui.Ctx, h: f32 = 20, loc := #caller_location) {
	ui.spacer(gtx, h, loc)
}

page_todo :: proc(gtx: ^ui.Ctx, p: Page) {
	s := m3.scheme()
	col := ui.column_open(gtx, gap = 8)
	defer ui.close(&col)
	if p.icon == .None {
		base.label(gtx, fmt.tprintf("%s: pick a component below this heading.", p.name), {color = s[.On_Surface_Variant]})
		return
	}
	base.label(gtx, "Not built yet.", {size = 16, color = s[.On_Surface]})
	base.label(gtx, "See the priority list in the material kitchen plan.", {color = s[.On_Surface_Variant]})
}

// Pages.

// TODAY is fixed rather than read from the clock, so -png renders are
// reproducible.
TODAY :: m3.Date{2026, 9, 28}

// State that survives a respawn.

persist :: proc(m: ^Model) {
	now := [2]int{m.page, int(m.dark)}
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
		m.dark = parse_int(fields[1]) != 0
	}
	m.persisted = {m.page, int(m.dark)}
}

parse_int :: proc(s: string) -> int {
	n := 0
	for c in s {
		if c < '0' || c > '9' {
			return 0
		}
		n = n * 10 + int(c - '0')
	}
	return n
}

// kitchen_fonts is Noto Sans at 400, 500 and 700 (font ids 0, 1, 2) for
// the type scale's weights, or jm:ui's default font for all three.
kitchen_fonts :: proc() -> []ops.Font_Ref {
	NOTO :: "/usr/share/fonts/noto/NotoSans-"
	paths := [3]string{NOTO + "Regular.ttf", NOTO + "Medium.ttf", NOTO + "Bold.ttf"}
	fonts := make([]ops.Font_Ref, 3)
	for p, i in paths {
		fonts[i] = {ops.Font_Id(i), os.exists(p) ? p : ui.default_font()}
	}
	return fonts
}

main :: proc() {
	m: Model
	m.page = 1
	m.volume, m.steps, m.range_lo, m.range_hi = 0.4, 30, 20, 70
	m.date, m.time = TODAY, {9, 41}
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
	// One headless session runs every step (see render.headless_step), so
	// a click, scroll or key press is still in effect when a later -png or
	// -dump captures the frame. It opens at the first step; flags that set
	// it up must come before that.
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
			// Parts that hide until used (idle scroll bars) draw anyway.
			setup(open, args[i])
			debug += {.Reveal}
		case "-bounds":
			// Every widget's box outlined.
			setup(open, args[i])
			debug += {.Bounds}
		case "-full":
			// The whole page, not a window's height of it.
			setup(open, args[i])
			full = true
		case "-size":
			// -size WxH renders at another window size, to check the
			// layout at a phone width or a half-screen tile.
			setup(open, args[i])
			i += 1
			w, _, ht := strings.partition(i < len(args) ? args[i] : "", "x")
			size = {f32(parse_int(w)), f32(parse_int(ht))}
			if size.x <= 0 || size.y <= 0 {
				fmt.eprintln("-size needs WxH, e.g. 950x1040")
				os.exit(2)
			}
		case "-dark":
			m.dark = true
		case "-open":
			m.menu_open, m.split_menu, m.dialog, m.snack, m.fab_open, m.bottom, m.side = true, true, true, true, true, true, true
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
		// A model flag after the session opened shows from the next frame,
		// so run one now: a -png that follows sees it.
		if open {
			ui.probe_frame(&h.p)
		}
	}
}
