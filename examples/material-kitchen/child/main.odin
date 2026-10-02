// The Material 3 kitchen: every M3 component in jm:ui/material, one page
// each, picked from a navigation drawer. Each page shows a component's
// variants against every spec state (enabled, hovered, focused, pressed,
// disabled — forced, so they sit side by side), plus a live row to poke.
// Components not built yet show where they sit in the plan.
//
//	material-kitchen-child                                run as the hot-reload subprocess
//	material-kitchen-child -page Buttons -png out.png     render one page headlessly
//	material-kitchen-child -page Buttons -dump            that page's sc as text
//	material-kitchen-child -dark ...                      the dark scheme (or -theme Dark)
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
// The rest of the flags are kitchen.run's. The scaffolding (state grid,
// session, command line) is examples/kitchen's; the section with its
// wrapped note, the cell width and the docked or modal page drawer are
// this kitchen's own.
package main

import "core:os"
import "jm:examples/kitchen"
import "jm:ui"
import "jm:ui/base"
import m3 "jm:ui/material"
import "jm:ui/ops"

// DOCKED_NAV_MIN is the narrowest window that keeps the page drawer
// docked beside the page: the m3e-kit foundations.json large window
// class (layout.windowSizeClasses, 1200-1599dp).
DOCKED_NAV_MIN :: 1200
#assert(len(PAGES) <= kitchen.MAX_PAGES)

// THEMES are the kitchen's schemes by name, for -theme; -dark picks the
// second.
THEMES := []string{"Light", "Dark"}

Page :: struct {
	name: string,
	icon: m3.Icon,
	draw: proc(gtx: ^ui.Ctx, m: ^Model),
}

Model :: struct {
	page:      int,
	nav_open:  bool, // the modal page drawer, in a narrow window
	theme:     int, // 0 light, 1 dark: an index into THEMES
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
	scroll:    [kitchen.MAX_PAGES]ui.Scroll_Offset, // each page's scroll position: the app owns it, so it persists
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
	kitchen.restore(gtx, &m.page, &m.theme, &m.scroll, len(PAGES), len(THEMES))
	dark := m.theme == 1
	m.scheme = dark ? m3.dark_scheme() : m3.light_scheme()
	m3.use(&m.scheme, dark ? .Dark : .Light)
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
	} else if m3.navigation_drawer(gtx, items, &m.page, width = 300, variant = .Modal, open = &m.nav_open) {
		m.nav_open = false
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
		sb := ui.scroll_box_open(gtx, offset = &m.scroll[clamp(m.page, 0, len(PAGES) - 1)])
		defer ui.close(&sb)
		page := ui.inset_open(gtx, {24, 8, 24, 48})
		defer ui.close(&page)
		if p.draw != nil {
			p.draw(gtx, m)
		} else {
			kitchen.page_todo(gtx, p.name, p.icon == .None)
		}
	}
	kitchen.persist(gtx, m.page, m.theme, &m.scroll)
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
	base.label(gtx, PAGES[clamp(m.page, 0, len(PAGES) - 1)].name, {size = 22, color = s[.On_Surface]}, heading = true)
	ui.fill_space(gtx)
	dark := m.theme == 1
	if m3.icon_button(gtx, dark ? .Light_Mode : .Dark_Mode, tooltip = dark ? "Light scheme" : "Dark scheme") {
		m.theme = 1 - m.theme
	}
}

// Page scaffolding.

// section is a titled block: Title_Medium caption, then whatever follows.
// It is not kitchen.section, whose note is one line in base's type: this
// one's note wraps, in M3's Body_Small.
section :: proc(gtx: ^ui.Ctx, title: string, note := "") {
	s := m3.scheme()
	ui.spacer(gtx, 12)
	base.label(gtx, title, {size = 16, color = s[.On_Surface]})
	if note != "" {
		// Wrapped, not a one-line label: notes run long, and a narrow
		// window must not cut them off.
		m3.text(gtx, note, .Body_Small, s[.On_Surface_Variant])
	}
}

// CELL_W is the width a state grid's cell needs here by default, rather
// than kitchen.CELL_W: Material's components are narrower. Grids of wider
// components pass their own.
CELL_W :: f32(120)

// cell_fixed takes w of a row's width.
cell_fixed :: proc(gtx: ^ui.Ctx, w: f32, loc := #caller_location) {
	ui.spacer(gtx, w, loc)
}

// label_width is s's advance at the state grid's label size.
label_width :: proc(gtx: ^ui.Ctx, s: string) -> f32 {
	return ui.shape(gtx.shaper, gtx.font, 12, s, gtx.allocator).advance
}

gap :: proc(gtx: ^ui.Ctx, h: f32 = 20, loc := #caller_location) {
	ui.spacer(gtx, h, loc)
}

// Pages.

// TODAY is fixed rather than read from the clock, so -png renders are
// reproducible.
TODAY :: m3.Date{2026, 9, 28}

// kitchen_fonts is Noto Sans at 400, 500 and 700 (font ids 0, 1, 2) for
// the type scale's weights, or jm:ui's default font for all three.
kitchen_fonts :: proc() -> []ops.Font_Ref {
	NOTO :: "/usr/share/fonts/noto/NotoSans-"
	paths := [3]string{NOTO + "Regular.ttf", NOTO + "Medium.ttf", NOTO + "Bold.ttf"}
	fonts := make([]ops.Font_Ref, 3)
	for p, i in paths {
		fonts[i] = {id = ops.Font_Id(i), path = os.exists(p) ? p : ui.default_font()}
	}
	return fonts
}

main :: proc() {
	m: Model
	m.page = 1
	m.volume, m.steps, m.range_lo, m.range_hi = 0.4, 30, 20, 70
	m.date, m.time = TODAY, {9, 41}
	pages := make([]string, len(PAGES))
	for p, i in PAGES {
		pages[i] = p.name
	}
	kitchen.run({ui = kitchen_ui, user = &m, fonts = kitchen_fonts(), size = {1400, 900}, pages = pages, themes = THEMES, page = &m.page, theme = &m.theme, flag = flag})
}

// flag is this kitchen's own flags: -dark for the dark scheme, and -open
// for every menu, dialog and snackbar open.
flag :: proc(user: rawptr, args: []string, i: ^int) -> bool {
	m := (^Model)(user)
	switch args[i^] {
	case "-dark":
		m.theme = 1
	case "-open":
		m.menu_open, m.split_menu, m.dialog, m.snack, m.fab_open, m.bottom, m.side = true, true, true, true, true, true, true
	case:
		return false
	}
	return true
}
