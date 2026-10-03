// The Primer kitchen: every component in jm:ui/primer, one page each,
// picked from the list on the left, in the primer-kit's groups. Each page
// shows a component's variants against every spec state (enabled,
// hovered, focused, pressed, disabled — forced, so they sit side by
// side), plus a live row to poke. The theme button cycles the kit's 14
// themes. The scaffolding (state grid, session, command line) is
// examples/kitchen's.
//
//	primer-kitchen-child                                  run as the hot-reload subprocess
//	primer-kitchen-child -page Button -png out.png        render one page headlessly
//	primer-kitchen-child -theme "Dark dimmed" ...         another theme (see primer.THEME_NAMES)
//
// The rest of the flags are kitchen.run's.
package main

import "core:os"
import "jm:ui"
import "jm:ui/base"
import "jm:ui/ops"
import "jm:ui/primer"

import "../../kitchen"

#assert(len(PAGES) <= kitchen.MAX_PAGES)
NAV_WIDTH :: 232

Page :: struct {
	name: string,
	draw: proc(gtx: ^ui.Ctx, m: ^Model), // nil for a group heading or a component not built yet
	head: bool,
}

// Model is the kitchen's state: the page, theme and scroll the session
// keeps, and each family's demo state, declared in its pages file.
Model :: struct {
	page:     int,
	theme:    int,
	scheme:   primer.Scheme,
	scroll:   [kitchen.MAX_PAGES]ui.Scroll_Offset,
	clicks:   int,
	loading:  bool,
	forms:    Forms,
	status:   Status,
	messages: Messages,
	overlays: Overlays,
	lists:    Lists,
	navs:     Navs,
	layouts:  Layouts,
	actions:  Actions,
}

// PAGES follows the primer-kit's families, in the plan's build order; a
// nil draw under a heading is a component not built yet.
PAGES := [?]Page {
	{"Actions", nil, true},
	{"Button", page_button, false},
	{"Icon button", page_icon_button, false},
	{"Button group", page_button_group, false},
	{"Action bar", nil, false},
	{"Link", page_link, false},
	{"Keybinding hint", page_keybinding_hint, false},
	{"Form controls", nil, true},
	{"Text input", page_text_input, false},
	{"Textarea", page_textarea, false},
	{"Select", page_select, false},
	{"Checkbox", page_checkbox, false},
	{"Checkbox group", page_checkbox_group, false},
	{"Radio", page_radio, false},
	{"Radio group", page_radio_group, false},
	{"Toggle switch", page_toggle_switch, false},
	{"Form control", page_form_control, false},
	{"Segmented control", page_segmented_control, false},
	{"Labels and status", nil, true},
	{"Label", page_label, false},
	{"Label group", page_label_group, false},
	{"State label", page_state_label, false},
	{"Counter label", page_counter_label, false},
	{"Token", page_token, false},
	{"Issue label", page_issue_label, false},
	{"Topic tag", page_topic_tag, false},
	{"Branch name", page_branch_name, false},
	{"Avatar", page_avatar, false},
	{"Avatar stack", page_avatar_stack, false},
	{"Circle badge", page_circle_badge, false},
	{"Spinner", page_spinner, false},
	{"Progress bar", page_progress_bar, false},
	{"Skeleton box", page_skeleton_box, false},
	{"Skeleton text", page_skeleton_text, false},
	{"Skeleton avatar", page_skeleton_avatar, false},
	{"Messages and text", nil, true},
	{"Banner", page_banner, false},
	{"Inline message", page_inline_message, false},
	{"Blankslate", page_blankslate, false},
	{"Heading", page_heading, false},
	{"Text", page_text, false},
	{"Truncate", page_truncate, false},
	{"Relative time", page_relative_time, false},
	{"Timeline", page_timeline, false},
	{"Overlays", nil, true},
	{"Overlay", page_overlay, false},
	{"Anchored overlay", page_anchored_overlay, false},
	{"Popover", page_popover, false},
	{"Tooltip", page_tooltip, false},
	{"Dialog", page_dialog, false},
	{"Confirmation dialog", page_confirmation_dialog, false},
	{"Details", page_details, false},
	{"Lists and pickers", nil, true},
	{"Action list", page_action_list, false},
	{"Action menu", page_action_menu, false},
	{"Select panel", nil, false},
	{"Autocomplete", page_autocomplete, false},
	{"Text input with tokens", page_text_input_with_tokens, false},
	{"Navigation", nil, true},
	{"Nav list", nil, false},
	{"Underline nav", nil, false},
	{"Underline panels", nil, false},
	{"Tree view", nil, false},
	{"Pagination", nil, false},
	{"Breadcrumbs", nil, false},
	{"Sub nav", nil, false},
	{"Layout and data", nil, true},
	{"Stack", page_stack, false},
	{"Page layout", page_page_layout, false},
	{"Split page layout", page_split_page_layout, false},
	{"Page header", page_page_header, false},
	{"Header", page_header, false},
	{"Card", page_card, false},
	{"Data table", page_data_table, false},
}

kitchen_ui :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Model)(user)
	kitchen.restore(gtx, &m.page, &m.theme, &m.scroll, len(PAGES), len(primer.Theme))
	theme := primer.Theme(m.theme)
	m.scheme = primer.theme_scheme(theme)
	primer.use(&m.scheme, theme)
	primer.use_fonts({0, 1, 2, 3})
	ops.fill(gtx.scene, ops.Rect{0, 0, gtx.constraints.max.x, gtx.constraints.max.y}, m.scheme[.Bg_Color_Default])

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
		at := clamp(m.page, 0, len(PAGES) - 1)
		p := PAGES[at]
		ps := ui.scope_open(gtx, at)
		defer ui.close(&ps)
		sb := ui.scroll_box_open(gtx, offset = &m.scroll[at])
		defer ui.close(&sb)
		page := ui.inset_open(gtx, {24, 8, 24, 48})
		defer ui.close(&page)
		if p.draw != nil {
			p.draw(gtx, m)
		} else {
			kitchen.page_todo(gtx, p.name, p.head)
		}
	}
	kitchen.persist(gtx, m.page, m.theme, &m.scroll)
}

// nav is the page list on a muted panel: a caption per group and an
// invisible button per page, the current one a muted fill. It stands in
// for primer.nav_list until that component is built.
nav :: proc(gtx: ^ui.Ctx, m: ^Model) {
	s := &m.scheme
	panel := ui.sized_open(gtx, {min = {NAV_WIDTH, 0}, max = {NAV_WIDTH, ui.INF}})
	defer ui.close(&panel)
	ops.fill(gtx.scene, ops.Rect{0, 0, NAV_WIDTH, gtx.constraints.max.y}, s[.Bg_Color_Muted])
	ops.fill(gtx.scene, ops.Rect{NAV_WIDTH - 1, 0, 1, gtx.constraints.max.y}, s[.Border_Color_Default])
	sb := ui.scroll_box_open(gtx)
	defer ui.close(&sb)
	col := ui.column_open(gtx, gap = 2, align = .Fill)
	defer ui.close(&col)
	ui.spacer(gtx, 12)
	for p, i in PAGES {
		if p.head {
			ui.spacer(gtx, 8)
			row := ui.inset_open(gtx, {16, 4, 8, 4}, key = u64(i))
			base.label(gtx, p.name, {size = 12, color = s[.Fg_Color_Muted]}, heading = true)
			ui.close(&row)
			continue
		}
		row := ui.inset_open(gtx, {8, 0, 8, 0}, key = u64(i))
		variant := i == m.page ? primer.Button_Variant.Default : .Invisible
		if primer.button(gtx, p.name, variant, .Small, block = true, align = .Start, key = u64(i)) {
			m.page = i
		}
		ui.close(&row)
	}
}

// app_bar is the page title and the theme button.
app_bar :: proc(gtx: ^ui.Ctx, m: ^Model) {
	bar := ui.inset_open(gtx, {24, 12, 16, 8})
	defer ui.close(&bar)
	r := ui.row_open(gtx, align = .Center)
	defer ui.close(&r)
	base.label(gtx, PAGES[clamp(m.page, 0, len(PAGES) - 1)].name, {size = 20}, heading = true)
	ui.fill_space(gtx)
	names := primer.THEME_NAMES
	if primer.button(gtx, names[primer.Theme(m.theme)], leading = .Paintbrush) {
		m.theme = (m.theme + 1) % len(primer.Theme)
	}
}

// kitchen_fonts is the system sans at normal, medium and semibold (font
// ids 0, 1, 2): SF on macOS, one variable font drawn at each weight, else
// jm:ui's default font, whose static outlines ignore the weight; and as
// id 3 the monospace face at /System/Library/Fonts/SFNSMono.ttf where
// that file exists, else the sans.
kitchen_fonts :: proc() -> []ops.Font_Ref {
	sf := "/System/Library/Fonts/SFNS.ttf"
	path := os.exists(sf) ? sf : ui.default_font()
	weights := [3]f32{400, 500, 600}
	fonts := make([]ops.Font_Ref, 4)
	for w, i in weights {
		fonts[i] = {id = ops.Font_Id(i), path = path, weight = w}
	}
	mono := "/System/Library/Fonts/SFNSMono.ttf"
	fonts[3] = {id = 3, path = os.exists(mono) ? mono : path, weight = 400}
	return fonts
}

main :: proc() {
	m: Model
	m.page = 1
	pages := make([]string, len(PAGES))
	for p, i in PAGES {
		pages[i] = p.name
	}
	themes := make([]string, len(primer.Theme))
	names := primer.THEME_NAMES
	for n, t in names {
		themes[int(t)] = n
	}
	kitchen.run({ui = kitchen_ui, user = &m, fonts = kitchen_fonts(), size = {1400, 900}, pages = pages, themes = themes, page = &m.page, theme = &m.theme})
}
