package main

import "core:fmt"
import "jm:examples/kitchen"
import "jm:ui"
import "jm:ui/base"
import "jm:ui/fluent"

// The navigation and layout pages, on the fluent-kit's nav.json,
// drawer.json, breadcrumb.json and tree.json.

// lay_nav_rows lays out the nav example's rows into whichever nav holds them.
lay_nav_rows :: proc(gtx: ^ui.Ctx, m: ^Model) {
	fluent.nav_section_header(gtx, "Workspace")
	fluent.nav_item(gtx, "Dashboard", "dashboard", &m.nav_selected, .Home)
	fluent.nav_item(gtx, "Documents", "documents", &m.nav_selected, .Document)
	if fluent.nav_category(gtx, "Reports", &m.nav_reports, .Folder) {
		fluent.nav_sub_item(gtx, "Sales", "sales", &m.nav_selected)
		fluent.nav_sub_item(gtx, "Costs", "costs", &m.nav_selected)
		fluent.nav_sub_item(gtx, "Forecast", "forecast", &m.nav_selected)
	}
	fluent.nav_divider(gtx)
	fluent.nav_section_header(gtx, "Account")
	fluent.nav_item(gtx, "Profile", "profile", &m.nav_selected, .Person)
	fluent.nav_item(gtx, "Settings", "settings", &m.nav_selected, .Settings)
}

// NAV_CELL_W is a state cell wide enough for a nav row.
NAV_CELL_W :: f32(190)

page_nav :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	kitchen.section(gtx, "Rows", "Background 4 rows padded MNudge (XS at small), each cell a 180px nav; selected: body1Strong, filled brand icon, a 4×20px Compound_Brand pill in the gutter")
	kitchen.state_header(gtx, NAV_CELL_W)
	{
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: fluent.Interaction, key: u64) {
			none := ""
			if fluent.nav(gtx, width = NAV_CELL_W - 10, key = key) {
				fluent.nav_item(gtx, "Dashboard", "d", &none, .Home, state = st, key = key)
			}
		}
		kitchen.state_row(gtx, m, "Item", cell, 1, NAV_CELL_W)
	}
	{
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: fluent.Interaction, key: u64) {
			on := "d"
			if fluent.nav(gtx, width = NAV_CELL_W - 10, key = key) {
				fluent.nav_item(gtx, "Dashboard", "d", &on, .Home, state = st, key = key)
			}
		}
		kitchen.state_row(gtx, m, "Selected", cell, 2, NAV_CELL_W)
	}
	kitchen.section(gtx, "Inline", "260px NavDrawer in the flow, medium and small density; click a category to open it")
	r := ui.row_open(gtx, gap = 24, align = .Start)
	if fluent.nav(gtx) {
		if fluent.nav_header(gtx) {
			fluent.hamburger(gtx)
			fluent.app_item(gtx, "Contoso", .Grid)
		}
		if fluent.nav_body(gtx) {
			lay_nav_rows(gtx, m)
		}
	}
	if fluent.nav(gtx, density = .Small, key = 1) {
		if fluent.nav_body(gtx, key = 1) {
			lay_nav_rows(gtx, m)
		}
	}
	ui.close(&r)
	kitchen.section(gtx, "Overlay", "the hamburger opens the nav drawer over the page; the backdrop, Escape or a pick closes it")
	base.label(gtx, fmt.tprintf("Selected: %s", m.nav_selected), {color = fluent.color(.Neutral_Foreground2)})
	if fluent.hamburger(gtx, key = 9) {
		m.nav_open = true
	}
	if fluent.nav(gtx, &m.nav_open, m.window, key = 2) {
		if fluent.nav_header(gtx, key = 2) {
			if fluent.hamburger(gtx, key = 10) {
				m.nav_open = false
			}
			fluent.app_item(gtx, "Contoso", .Grid, static = true)
		}
		if fluent.nav_body(gtx, key = 2) {
			lay_nav_rows(gtx, m)
		}
	}
}

DRAWER_SIZE_NAMES := [?]string{"Small", "Medium", "Large", "Full"}

page_drawer :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	kitchen.section(gtx, "Overlay", "320 / 592 / 940px or the whole window, sliding in over durationGentle / Slow / Slower / UltraSlow under shadow64 and the backdrop")
	{
		r := ui.wrap_open(gtx, gap = 12)
		defer ui.close(&r)
		for name, i in DRAWER_SIZE_NAMES {
			if fluent.button(gtx, fmt.tprintf("%s start", name), key = u64(i)) {
				m.drawer_size, m.drawer_position, m.drawer_open = fluent.Drawer_Size(i), .Start, true
			}
		}
		if fluent.button(gtx, "Medium end", key = 10) {
			m.drawer_size, m.drawer_position, m.drawer_open = .Medium, .End, true
		}
		if fluent.button(gtx, "Bottom", key = 11) {
			m.drawer_size, m.drawer_position, m.drawer_open = .Small, .Bottom, true
		}
	}
	kitchen.section(gtx, "Inline", "in the flow beside the content, with the 1px Background 3 separator; its width grows with the motion")
	if fluent.button(gtx, m.drawer_inline ? "Close inline" : "Open inline", key = 20) {
		m.drawer_inline = !m.drawer_inline
	}
	inline_drawer_demo(gtx, m)
	if fluent.drawer(gtx, &m.drawer_open, m.window, .Overlay, m.drawer_position, m.drawer_size, key = 30) {
		if fluent.drawer_header(gtx, key = 31) {
			fluent.drawer_header_title(gtx, "Settings", &m.drawer_open)
		}
		if fluent.drawer_body(gtx, key = 32) {
			fluent.text_block(gtx, "The body takes the remaining height and scrolls; it pads spacingHorizontalXXL at each side.", .Body1, fluent.color(.Neutral_Foreground1), 260)
			fluent.checkbox(gtx, &m.drawer_checks[3], "Notifications", key = 3)
		}
		if fluent.drawer_footer(gtx, key = 33) {
			if fluent.button(gtx, "Save", .Primary) {
				m.drawer_open = false
			}
			if fluent.button(gtx, "Cancel") {
				m.drawer_open = false
			}
		}
	}
}

CRUMB_ITEMS := [?]string{"Home", "Projects", "Contoso redesign", "Assets", "Icons", "Navigation", "Regular", "Chevron right"}
CRUMB_SHORT := [?]string{"Home", "Projects", "Contoso redesign"}

page_breadcrumb :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	kitchen.section(gtx, "Sizes", "subtle buttons with no minimum width, 24 / 32 / 40px; the current item reads as strong text and takes no input")
	SIZE_NAMES :: [?]string{"Small", "Medium", "Large"}
	for name, i in SIZE_NAMES {
		r := ui.row_open(gtx, gap = 16, align = .Center, key = u64(i))
		base.label(gtx, name, {size = 12, color = fluent.color(.Neutral_Foreground2)})
		fluent.breadcrumb(gtx, CRUMB_SHORT[:], fluent.Size(i), key = u64(10 + i))
		ui.close(&r)
	}
	kitchen.section(gtx, "With icons", "the icon turns brand and filled on hover")
	icons := [?]fluent.Icon{.Home, .Folder, .Document}
	fluent.breadcrumb(gtx, CRUMB_SHORT[:], icons = icons[:], key = 20)
	kitchen.section(gtx, "Overflow", "more than 6 items: the first stays, the run after it folds into a … menu")
	if i := fluent.breadcrumb(gtx, CRUMB_ITEMS[:], key = 30); i >= 0 {
		m.crumb_pick = i
	}
	base.label(gtx, fmt.tprintf("Last picked: %d", m.crumb_pick), {color = fluent.color(.Neutral_Foreground2)})
}

page_tree :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	kitchen.section(gtx, "Rows", "32px rows (24 at small) in the Subtle family; the chevron is Foreground 3; nothing transitions")
	kitchen.state_header(gtx, 180)
	{
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: fluent.Interaction, key: u64) {
			open := false
			fluent.tree_item(gtx, "Folder", &open, icon_before = .Folder, state = st, key = key)
		}
		kitchen.state_row(gtx, m, "Branch", cell, 1, 180)
	}
	{
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: fluent.Interaction, key: u64) {
			fluent.tree_item(gtx, "File", icon_before = .Document, state = st, key = key)
		}
		kitchen.state_row(gtx, m, "Leaf", cell, 2, 180)
	}
	kitchen.section(gtx, "Live", "click or Right/Left on a branch; a leaf is indented one XXL step past its branch")
	{
		tc := ui.column_open(gtx, gap = 2, align = .Fill)
		defer ui.close(&tc)
		if fluent.tree_item(gtx, "Documents", &m.tree_open[0], icon_before = .Folder, aside = "3 items") {
			if fluent.tree_item(gtx, "Reports", &m.tree_open[1], level = 2, icon_before = .Folder) {
				fluent.tree_item(gtx, "Q3 summary", level = 3, icon_before = .Document, description = "Edited today")
				fluent.tree_item(gtx, "Q4 plan", level = 3, icon_before = .Document)
			}
			fluent.tree_item(gtx, "Readme", level = 2, icon_before = .Document)
		}
		if fluent.tree_item(gtx, "Pictures", &m.tree_open[2], icon_before = .Folder, key = 1) {
			fluent.tree_item(gtx, "Holiday", level = 2, icon_before = .Image, key = 1)
		}
	}
	kitchen.section(gtx, "Selection and small", "multiselect puts a checkbox before each row")
	sc := ui.column_open(gtx, gap = 2, align = .Start, key = 5)
	if fluent.tree_item(gtx, "All tasks", &m.tree_open[3], size = .Small, checked = &m.tree_checks[0], mixed = m.tree_checks[1] != m.tree_checks[2], key = 10) {
		fluent.tree_item(gtx, "Write spec", level = 2, size = .Small, checked = &m.tree_checks[1], key = 11)
		fluent.tree_item(gtx, "Review", level = 2, size = .Small, checked = &m.tree_checks[2], key = 12)
	}
	ui.close(&sc)
}

// inline_drawer_demo is the inline drawer beside a line of page content.
inline_drawer_demo :: proc(gtx: ^ui.Ctx, m: ^Model) {
	r := ui.row_open(gtx, align = .Start)
	defer ui.close(&r)
	if fluent.drawer(gtx, &m.drawer_inline, m.window, .Inline, separator = true, key = 21) {
		if fluent.drawer_header(gtx, key = 22) {
			fluent.drawer_header_title(gtx, "Filters", &m.drawer_inline)
		}
		if fluent.drawer_body(gtx, key = 23) {
			fluent.checkbox(gtx, &m.drawer_checks[0], "Unread only")
			fluent.checkbox(gtx, &m.drawer_checks[1], "With attachments", key = 1)
			fluent.checkbox(gtx, &m.drawer_checks[2], "Flagged", key = 2)
		}
	}
	c := ui.inset_open(gtx, {24, 0, 0, 0})
	base.label(gtx, "The page content sits beside the inline drawer.", {color = fluent.color(.Neutral_Foreground2)})
	ui.close(&c)
}
