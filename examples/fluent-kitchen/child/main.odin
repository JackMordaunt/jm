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
// -inspect, -reveal and -bounds. The selected page, theme and each page's
// scroll position survive a hot-reload respawn through ui.persist_struct
// and ui.restore_struct.
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
// MAX_PAGES sizes the per-page state in Model: it cannot be len(PAGES),
// since the pages' procs take the Model.
MAX_PAGES :: 128
#assert(len(PAGES) <= MAX_PAGES)
NAV_WIDTH :: 240

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
	scroll:    [MAX_PAGES]ui.Scroll_Offset, // each page's scroll position: the app owns it, so it persists
	// form controls
	checks:    [4]bool,
	all:       bool,
	all_mixed: bool,
	radio:     int,
	radio2:    int,
	switches:  [3]bool,
	volume:    f32,
	steps:     f32,
	level:     f32,
	// inputs
	input_cells: [8]ui.Text_State, // one per state-grid cell, so each holds its own text
	area_cells:  [7]ui.Text_State,
	first:       ui.Text_State,
	last:        ui.Text_State,
	query:       ui.Text_State,
	mail:        ui.Text_State,
	notes:       ui.Text_State,
	field_a:     ui.Text_State,
	field_b:     ui.Text_State,
	field_c:     ui.Text_State,
	field_d:     ui.Text_State,
	field_e:     ui.Text_State,
	field_f:     ui.Text_State,
	field_g:     ui.Text_State,
	field_h:     ui.Text_State,
	field_i:     ui.Text_State,
	link_clicks: int,
	// containers
	card_sel:    [3]bool,
	card_hit:    bool,
	card_hits:   int,
	tab_a:       int,
	tab_b:       int,
	tab_c:       int,
	tab_d:       int,
	tool_clicks: int,
	acc_open:    [7]bool,
	acc_single:  [3]bool,
	// feedback
	avatar_active: bool,
	progress:      f32,
	toasts:         fluent.Toasts,
	toast_seeded:   bool,
	bar_closed:     bool,
	bar_action:     string, // a literal
	pop_open:       [8]bool,
	pop_seeded:     bool,
	teach_open:     bool,
	teach_brand:    bool,
	teach_seeded:   bool,
	teach_page:     int,
	info_open:      bool,
	info_seeded:    bool,
	slide_flat:     int,
	slide_elevated: int,
	slide_auto:     bool,
	// overlays and the button family
	window:                                       ops.Size,
	menu_open, menu_bold, menu_italic:            bool,
	menu_pick:                                    string, // an item literal, never frame memory
	split_open, split_live:                       bool,
	split_count:                                  int,
	dialog_open:                                  bool,
	dialog_kind:                                  fluent.Dialog_Kind,
	dialog_result:                                string, // a literal
	fmt_bold, fmt_italic, fmt_underline, fmt_star: bool,
	menu_button_open, menu_icon_open:             bool,
	// navigation
	nav_selected:    string, // a value literal
	nav_reports:     bool,
	nav_open:        bool,
	drawer_open:     bool,
	drawer_inline:   bool,
	drawer_size:     fluent.Drawer_Size,
	drawer_position: fluent.Drawer_Position,
	drawer_checks:   [4]bool,
	crumb_pick:      int,
	tree_open:       [4]bool,
	tree_checks:     [3]bool,
	// pickers
	pk_ready:       bool,
	pk_fruit:       ui.Text_State,
	pk_clear:       ui.Text_State,
	pk_query:       ui.Text_State,
	pk_empty:       ui.Text_State,
	pk_people:      ui.Text_State,
	pk_pick:        int,
	pk_drop:        int,
	pk_clear_pick:  int,
	pk_grid_pick:   int,
	pk_select:      int,
	pk_count:       f32,
	pk_price:       f32,
	pk_chosen:      [6]bool,
	pk_grid_chosen: [6]bool,
	pk_swatch:      int,
	pk_swatch_grid: int,
	pk_hsv:         fluent.Hsv,
	pk_stars:       f32,
	pk_halves:      f32,
	// data display
	table_rows:   [4]bool,
	table_sort:   fluent.Sort_Direction,
	list_single:  int,
	list_multi:   [4]bool,
	list_actions: int,
	tags_removed: [5]bool,
	groups_open:  [9]bool,
	// dates
	cal_selected, cal_view:   fluent.Date,
	cal_selected2, cal_view2: fluent.Date,
	cal_picks:                int,
	date_cells:               [15]ui.Text_State, // one per state-grid cell
	date_text, due_text:      ui.Text_State,
	date_value, due_value:    fluent.Date,
	date_open, due_open:      bool,
	due_check:                fluent.Date_Validation,
	time_cells:               [5]ui.Text_State,
	time_text, time24_text:   ui.Text_State,
	free_text:                ui.Text_State,
	time_value, time24_value: fluent.Time,
	free_value:               fluent.Time,
	time_valid, time24_valid: bool,
	free_valid:               bool,
	time_open, time24_open:   bool,
	free_open:                bool,
	free_err:                 fluent.Time_Error,
}

// PAGES follows the fluent-kit's component index, grouped by the plan's
// build order; a nil draw under a heading is a component not built yet.
PAGES := [?]Page {
	{"Buttons", nil, true},
	{"Button", page_buttons, false},
	{"Toggle button", page_toggle_button, false},
	{"Split button", page_split_button, false},
	{"Menu button", page_menu_button, false},
	{"Compound button", page_compound_button, false},
	{"Form controls", nil, true},
	{"Checkbox", page_checkbox, false},
	{"Radio group", page_radio, false},
	{"Switch", page_switch, false},
	{"Slider", page_slider, false},
	{"Inputs", nil, true},
	{"Input", page_input, false},
	{"Textarea", page_textarea, false},
	{"Field", page_field, false},
	{"Label", page_label, false},
	{"Link", page_link, false},
	{"Containers", nil, true},
	{"Card", page_card, false},
	{"Divider", page_divider, false},
	{"Tab list", page_tab_list, false},
	{"Toolbar", page_toolbar, false},
	{"Accordion", page_accordion, false},
	{"Carousel", page_carousel, false},
	{"Feedback", nil, true},
	{"Badge", page_badge, false},
	{"Avatar", page_avatar, false},
	{"Progress bar", page_progress_bar, false},
	{"Spinner", page_spinner, false},
	{"Toast", page_toast, false},
	{"Message bar", page_message_bar, false},
	{"Overlays", nil, true},
	{"Menu", page_menu, false},
	{"Dialog", page_dialog, false},
	{"Tooltip", page_tooltip, false},
	{"Popover", page_popover, false},
	{"Teaching popover", page_teaching_popover, false},
	{"Info label", page_info_label, false},
	{"Navigation", nil, true},
	{"Nav", page_nav, false},
	{"Drawer", page_drawer, false},
	{"Breadcrumb", page_breadcrumb, false},
	{"Tree", page_tree, false},
	{"Pickers", nil, true},
	{"Combobox", page_combobox, false},
	{"Select", page_select, false},
	{"Spin button", page_spin_button, false},
	{"Search box", page_search_box, false},
	{"Tag picker", page_tag_picker, false},
	{"Swatch picker", page_swatch_picker, false},
	{"Color picker", page_color_picker, false},
	{"Rating", page_rating, false},
	{"Data display", nil, true},
	{"Table", page_table, false},
	{"List", page_list, false},
	{"Tag", page_tag, false},
	{"Persona", page_persona, false},
	{"Avatar group", page_avatar_group, false},
	{"Skeleton", page_skeleton, false},
	{"Text", page_text, false},
	{"Image", page_image, false},
	{"Dates", nil, true},
	{"Calendar", page_calendar, false},
	{"Date picker", page_date_picker, false},
	{"Time picker", page_time_picker, false},
}

kitchen_ui :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Model)(user)
	restore(gtx, m)
	m.scheme = fluent.theme_scheme(m.theme)
	fluent.use(&m.scheme, fluent.mode_of(m.theme))
	fluent.use_fonts({0, 1, 2})
	s := &m.scheme
	ops.fill(gtx.scene, ops.Rect{0, 0, gtx.constraints.max.x, gtx.constraints.max.y}, s[.Neutral_Background2])
	m.window = gtx.constraints.max // for the dialog page's backdrop and centring

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
		sb := ui.scroll_box_open(gtx, offset = &m.scroll[clamp(m.page, 0, len(PAGES) - 1)])
		defer ui.close(&sb)
		page := ui.inset_open(gtx, {24, 8, 24, 48})
		defer ui.close(&page)
		if p.draw != nil {
			p.draw(gtx, m)
		} else {
			page_todo(gtx, p)
		}
	}
	persist(gtx, m)
}

// nav is the page list as the toolkit's own inline nav drawer: the
// kitchen's name in the header, a section header per group and a nav
// item per page, the current one selected. Its body scrolls.
nav :: proc(gtx: ^ui.Ctx, m: ^Model) {
	n := fluent.nav_open(gtx, width = NAV_WIDTH)
	defer fluent.nav_close(&n)
	if fluent.nav_header(gtx) {
		fluent.app_item(gtx, "jm:ui fluent", .Grid, static = true)
	}
	if fluent.nav_body(gtx) {
		selected := PAGES[clamp(m.page, 0, len(PAGES) - 1)].name
		for p, i in PAGES {
			if p.head {
				fluent.nav_section_header(gtx, p.name, key = u64(i))
				continue
			}
			if fluent.nav_item(gtx, p.name, p.name, &selected, key = u64(i)) {
				m.page = i
			}
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

// Session is the state that survives a respawn, as ui.persist_struct
// writes it: `page 3`, `theme Teams_Dark`, `scroll[3].y 240`.
Session :: struct {
	page:   int,
	theme:  fluent.Theme,
	scroll: [MAX_PAGES]ui.Scroll_Offset,
}

persist :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.persist_struct(gtx, Session{m.page, m.theme, m.scroll})
}

restore :: proc(gtx: ^ui.Ctx, m: ^Model) {
	s := Session{m.page, m.theme, m.scroll}
	if ui.restore_struct(gtx, &s, gtx.allocator) {
		m.page = clamp(s.page, 0, len(PAGES) - 1)
		m.theme, m.scroll = s.theme, s.scroll
	}
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
