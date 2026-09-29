package main

import "core:fmt"
import "jm:ui"
import "jm:ui/base"
import m3 "jm:ui/material"
import tok "jm:ui/material/tokens"

page_cards :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	section(gtx, "Cards", "corner 12; elevated 1dp on surface-container-low, filled on surface-container-highest, outlined 1dp outline-variant; elevation per state")
	state_header(gtx)
	NAMES := [?]string{"Elevated", "Filled", "Outlined"}
	for n, i in NAMES {
		state_row(gtx, m, n, card_cell, u64(i + 1))
		gap(gtx, 8)
	}
	section(gtx, "Dragged", "elevated 8dp, filled and outlined 6dp: the lift a host drag gives")
	{
		r := ui.wrap_open(gtx, gap = 16)
		defer ui.close(&r)
		for i in 0 ..< len(m3.Card_Kind) {
			card_cell(gtx, m, .Dragged, u64(16 * (i + 1)) + 5)
		}
	}
	section(gtx, "Live", fmt.tprintf("cards hold any widgets; clicked %d times", m.card_hits))
	r := ui.wrap_open(gtx, gap = 16)
	defer ui.close(&r)
	for kind, i in m3.Card_Kind {
		hit: bool
		{
			c := m3.card_open(gtx, kind, clickable = true, clicked = &hit, key = u64(200 + i))
			defer ui.close(&c)
			cc := ui.column_open(gtx, gap = 8)
			defer ui.close(&cc)
			m3.card_icon(gtx, .Photo, kind)
			base.label(gtx, "Glass souls' world", {size = 22, color = m3.scheme()[.On_Surface]})
			base.label(gtx, "Deep ocean exploration", {size = 14, color = m3.scheme()[.On_Surface_Variant]})
			gap(gtx, 8)
			br := ui.row_open(gtx, gap = 8)
			m3.button(gtx, "Explore", .Filled, key = u64(210 + i))
			m3.button(gtx, "Save", .Outlined, key = u64(220 + i))
			ui.close(&br)
		}
		if hit {
			m.card_hits += 1
		}
	}
}

// card_cell is one card of kind key/16 - 1 in state st.
card_cell :: proc(gtx: ^ui.Ctx, m: ^Model, st: m3.Interaction, key: u64) {
	c := m3.card_open(gtx, m3.Card_Kind(key / 16 - 1), clickable = true, state = st, key = key)
	defer ui.close(&c)
	cc := ui.column_open(gtx, gap = 4)
	defer ui.close(&cc)
	dim := st == .Disabled
	on := m3.scheme()[.On_Surface]
	base.label(gtx, "Headline", {size = 16, color = dim ? m3.disabled_content() : on})
	base.label(gtx, "Subhead", {size = 14, color = dim ? m3.disabled_content() : m3.scheme()[.On_Surface_Variant]})
}

page_lists :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	s := m3.scheme()
	section(gtx, "List items", "one line 56, two 72, three 88; corners morph from 4 to 12 hovered, 16 focused, pressed or selected")
	LINES := [?]m3.List_Item {
		{headline = "One line", leading_icon = .Person, trailing_icon = .Chevron_Right},
		{headline = "Two lines", supporting = "Supporting text", leading_avatar = "A", trailing_text = "100+"},
		{overline = "Overline", headline = "Three lines", supporting = "Supporting text", leading_icon = .Photo, trailing_icon = .More_Vert},
	}
	list_state_rows(gtx, LINES[:], 10)
	section(gtx, "Selected", "secondary-container; selected-disabled dims container and content to 38%")
	SEL := [?]m3.List_Item {
		{headline = "One line", leading_icon = .Person, trailing_icon = .Chevron_Right, selected = true},
		{headline = "Two lines", supporting = "Supporting text", leading_avatar = "A", trailing_text = "100+", selected = true},
		{overline = "Overline", headline = "Three lines", supporting = "Supporting text", leading_icon = .Photo, selected = true},
	}
	list_state_rows(gtx, SEL[:], 100)
	section(gtx, "Leading media and wrapping", "image 56×56 corner 8; small video 100×56, large video 114×64; the row grows to fit. Three lines without an overline wrap the supporting text")
	{
		r := ui.wrap_open(gtx, gap = 16)
		defer ui.close(&r)
		MEDIA := [?]m3.List_Item {
			{headline = "Image", supporting = "56 × 56", leading_media = .Image},
			{headline = "Small video", supporting = "100 × 56", leading_media = .Small_Video},
			{headline = "Large video", supporting = "114 × 64", leading_media = .Large_Video},
			{headline = "Three lines", supporting = "Supporting text that runs long enough to wrap onto a second line", three_line = true, leading_icon = .Photo},
		}
		for it, i in MEDIA {
			m3.list_item(gtx, it, 250, .Enabled, key = u64(200 + i))
		}
	}

	section(gtx, "Segmented", "rows 2dp apart on the segmented colour; the run's first and last take the 16dp outer corners. Single select")
	{
		bg := segmented_bg(gtx, 300)
		defer ui.close(&bg)
		lc := ui.column_open(gtx, gap = tok.LIST_SEGMENTED_GAP)
		defer ui.close(&lc)
		NAMES := [?]string{"Wi-Fi", "Bluetooth", "Airplane mode", "Hotspot"}
		GLYPHS := [?]m3.Icon{.Wifi, .Bolt, .Flight, .Share}
		for n, i in NAMES {
			it := m3.List_Item {
				headline      = n,
				leading_icon  = GLYPHS[i],
				selection     = .Single,
				selected      = m.list_single == i,
				segment_index = i,
				segment_count = len(NAMES),
			}
			if m3.list_item(gtx, it, 400, key = u64(310 + i)) {
				m.list_single = i
			}
		}
	}

	section(gtx, "Multi-select and expanded", "multi-select flips checked; an expanded row turns its disclosure and shows its children")
	{
		r := ui.wrap_open(gtx, gap = 24)
		defer ui.close(&r)
		{
			bg := segmented_bg(gtx, 801)
			defer ui.close(&bg)
			lc := ui.column_open(gtx, gap = tok.LIST_SEGMENTED_GAP)
			defer ui.close(&lc)
			TOPPINGS := [?]string{"Cheese", "Olives", "Basil", "Chilli"}
			for n, i in TOPPINGS {
				it := m3.List_Item {
					headline      = n,
					leading_icon  = m.list_multi[i] ? .Check_Box : .Check_Box_Outline_Blank,
					selection     = .Multi,
					checked       = &m.list_multi[i],
					segment_index = i,
					segment_count = len(TOPPINGS),
				}
				m3.list_item(gtx, it, 320, key = u64(400 + i))
			}
		}
		{
			bg := segmented_bg(gtx, 802)
			defer ui.close(&bg)
			lc := ui.column_open(gtx, gap = tok.LIST_SEGMENTED_GAP)
			defer ui.close(&lc)
			GROUPS := [?]string{"Inbox", "Archive"}
			CHILDREN := [2][2]string{{"From Ali", "From Sandra"}, {"Last week", "Last month"}}
			n := 0
			for g in 0 ..< len(GROUPS) {
				n += 1 + (m.list_expand[g] ? 2 : 0)
			}
			idx := 0
			for g, gi in GROUPS {
				it := m3.List_Item {
					headline      = g,
					leading_icon  = gi == 0 ? .Inbox : .Archive,
					kind       = .Expanded,
					expanded      = &m.list_expand[gi],
					segment_index = idx,
					segment_count = n,
				}
				m3.list_item(gtx, it, 320, key = u64(420 + gi))
				idx += 1
				if m.list_expand[gi] {
					for child, ci in CHILDREN[gi] {
						m3.list_item(gtx, {headline = child, leading_icon = .Mail, segment_index = idx, segment_count = n}, 320, key = u64(430 + 2 * gi + ci))
						idx += 1
					}
				}
			}
		}
	}

	section(gtx, "Reorder", "drag a row by any point, or focus it and press Up/Down; a lifted row is tertiary at 8dp over a drop zone")
	{
		r := ui.wrap_open(gtx, gap = 24)
		defer ui.close(&r)
		{
			bg := segmented_bg(gtx, 803)
			defer ui.close(&bg)
			lc := ui.column_open(gtx, gap = tok.LIST_SEGMENTED_GAP)
			defer ui.close(&lc)
			if m.list_order == {} {
				m.list_order = {0, 1, 2, 3, 4}
			}
			TASKS := [?]string{"Write the brief", "Port the menus", "Render the kitchen", "Run the tests", "Commit"}
			for slot in 0 ..< len(m.list_order) {
				task := m.list_order[slot]
				moved := 0
				it := m3.List_Item {
					headline      = TASKS[task],
					leading_icon  = .Label,
					kind       = .Reorder,
					moved         = &moved,
					segment_index = slot,
					segment_count = len(m.list_order),
				}
				m3.list_item(gtx, it, 320, key = u64(500 + task))
				if moved != 0 {
					to := clamp(slot + moved, 0, len(m.list_order) - 1)
					v := m.list_order[slot]
					ordered_remove_insert(m.list_order[:], slot, to, v)
				}
			}
		}
		{
			lc := ui.column_open(gtx, gap = 8)
			defer ui.close(&lc)
			base.label(gtx, "Dragged (forced)", {size = 12, color = s[.On_Surface_Variant]})
			m3.list_item(gtx, {headline = "Lifted row", supporting = "reorder-list item", leading_icon = .Label, kind = .Reorder}, 320, .Dragged, key = 520)
		}
	}

	section(gtx, "Reveal", fmt.tprintf("drag a row left, or focus it and press Left, to uncover its actions; last picked: %s", m.reveal_pick == "" ? "none" : m.reveal_pick))
	{
		r := ui.wrap_open(gtx, gap = 24)
		defer ui.close(&r)
		bg := segmented_bg(gtx, 810)
		lc := ui.column_open(gtx, gap = tok.LIST_SEGMENTED_GAP)
		MAIL := [?]string{"Brunch this weekend?", "Summer BBQ", "Order confirmation"}
		ACTIONS := [?]m3.Icon{.Archive, .Delete}
		ACTION_NAMES := [?]string{"archive", "delete"}
		for subject, i in MAIL {
			picked := -1
			it := m3.List_Item {
				headline      = subject,
				supporting    = "Swipe for actions",
				leading_avatar = subject[:1],
				kind       = .Reveal,
				actions       = ACTIONS[:],
				action        = &picked,
				segment_index = i,
				segment_count = len(MAIL),
			}
			m3.list_item(gtx, it, 420, key = u64(600 + i))
			if picked >= 0 {
				m.reveal_pick = ACTION_NAMES[picked]
			}
		}
		ui.close(&lc)
		ui.close(&bg)
		oc := ui.column_open(gtx, gap = 8)
		defer ui.close(&oc)
		base.label(gtx, "Revealed (forced)", {size = 12, color = s[.On_Surface_Variant]})
		rb := segmented_bg(gtx, 811)
		m3.list_item(gtx, {headline = "Brunch this weekend?", supporting = "Swipe for actions", leading_avatar = "B", kind = .Reveal, actions = ACTIONS[:], revealed = true}, 420, .Enabled, key = 620)
		ui.close(&rb)
	}

	section(gtx, "Live", "a list in an outlined card; click to select")
	c := m3.card_open(gtx, .Outlined, padding = 0, key = 700)
	defer ui.close(&c)
	lc := ui.column_open(gtx)
	defer ui.close(&lc)
	PEOPLE := [?]string{"Ali Connors", "Alex Scott", "Sandra Adams", "Trevor Hansen", "Britta Holt"}
	SUBJ := [?]string{"Brunch this weekend?", "Summer BBQ", "Oui oui", "Order confirmation", "Recipe to try"}
	for name, i in PEOPLE {
		it := m3.List_Item {
			headline       = name,
			supporting     = SUBJ[i],
			leading_avatar = name[:1],
			trailing_text  = fmt.tprintf("%d min", 5 * (i + 1)),
			selected       = m.list_sel == i,
			selection      = .Single,
			divider        = i < len(PEOPLE) - 1,
		}
		if m3.list_item(gtx, it, 420, key = u64(710 + i)) {
			m.list_sel = i
		}
	}
}

// segmented_bg is the filled surface a segmented run sits on, so its
// surface-coloured rows read as segments.
segmented_bg :: proc(gtx: ^ui.Ctx, key: u64) -> ui.Box {
	return m3.card_open(gtx, .Filled, padding = 8, key = key)
}

// list_state_rows lays items out once per forced state, a row each.
list_state_rows :: proc(gtx: ^ui.Ctx, items: []m3.List_Item, base_key: u64) {
	for st, i in m3.STATES {
		r := ui.row_open(gtx, gap = 16, align = .Center, key = base_key + u64(i))
		defer ui.close(&r)
		base.label(gtx, STATE_NAMES[i], {size = 12, color = m3.scheme()[.On_Surface_Variant]})
		ui.spacer(gtx, max(LABEL_W - 16 - label_width(gtx, STATE_NAMES[i]), 0))
		wr := ui.wrap_open(gtx, gap = 16, line_gap = 12, align = .Center)
		defer ui.close(&wr)
		for it, j in items {
			m3.list_item(gtx, it, 300, st, key = base_key + u64(10 * i + j + 10))
		}
	}
}

// ordered_remove_insert moves the value v at from to index to, shifting
// the values between.
ordered_remove_insert :: proc(a: []int, from, to: int, v: int) {
	if from < to {
		copy(a[from:to], a[from + 1:to + 1])
	} else if from > to {
		copy(a[to + 1:from + 1], a[to:from])
	}
	a[to] = v
}

page_divider :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	s := m3.scheme()
	section(gtx, "Divider", "1dp outline-variant: full width, inset 16, middle inset 16/16; insets are the caller's layout in Compose")
	{
		cc := ui.column_open(gtx, gap = 16)
		defer ui.close(&cc)
		base.label(gtx, "Full width", {size = 12, color = s[.On_Surface_Variant]})
		m3.divider(gtx)
		base.label(gtx, "Inset", {size = 12, color = s[.On_Surface_Variant]})
		m3.divider(gtx, 16)
		base.label(gtx, "Middle inset", {size = 12, color = s[.On_Surface_Variant]})
		m3.divider(gtx, 16, 16)
		base.label(gtx, "Heavy (MDC's 8dp, a thickness override)", {size = 12, color = s[.On_Surface_Variant]})
		m3.divider(gtx, thickness = 8)
		base.label(gtx, "Colour override (primary)", {size = 12, color = s[.On_Surface_Variant]})
		m3.divider(gtx, line_color = s[.Primary])
	}
	section(gtx, "Vertical, in a row", "the row's height is unbounded in this scroll view, so each takes length 24")
	r := ui.row_open(gtx, gap = 16, align = .Fill)
	defer ui.close(&r)
	base.label(gtx, "Left")
	m3.divider(gtx, vertical = true, length = 24)
	base.label(gtx, "Middle")
	m3.divider(gtx, vertical = true, length = 24)
	base.label(gtx, "Right")
}

// MENU_STATES is a menu whose items each show one forced state, then a
// selected item and one that opens a submenu.
MENU_STATES := [?]m3.Menu_Item {
	{label = "Enabled", leading = .Content_Cut, trailing = "Ctrl+X", state = .Enabled},
	{label = "Hovered", leading = .Content_Copy, trailing = "Ctrl+C", state = .Hovered},
	{label = "Focused", leading = .Content_Paste, trailing = "Ctrl+V", state = .Focused},
	{label = "Pressed", leading = .Undo, state = .Pressed},
	{label = "Disabled", leading = .Redo, disabled = true, divider = true},
	{label = "Selected", leading = .Check, selected = true, state = .Enabled},
	{label = "Share", leading = .Share, submenu = true, state = .Enabled},
}

// MENU_GROUPED is a grouped Expressive menu: a labelled group, then two
// groups split by divider.
MENU_GROUPED := [?]m3.Menu_Item {
	{label = "Sort by", heading = true},
	{label = "Name", selected_icon = .Check, selected = true},
	{label = "Date modified", selected_icon = .Check},
	{label = "Size", selected_icon = .Check, divider = true},
	{label = "Details", leading = .Info, supporting = "Size, owner, history"},
	{label = "Rename", leading = .Edit, divider = true},
	{label = "Delete", leading = .Delete},
}

page_menus :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	section(gtx, "Menu", "legacy: surface-container, corner 4, 48dp label-large items; Expressive standard and vibrant: 16dp corners, body-large, tertiary selection")
	{
		r := ui.wrap_open(gtx, gap = 24, line_gap = 12)
		defer ui.close(&r)
		{
			st := ui.stack_open(gtx)
			defer ui.close(&st)
			if m3.button(gtx, "Edit", .Outlined, .Edit, key = 1) {
				m.menu_open = !m.menu_open
			}
			if i := m3.menu(gtx, &m.menu_open, EDIT_MENU[:], {0, 44}, key = 2); i >= 0 {
				m.menu_pick = EDIT_MENU[i].label
			}
		}
		{
			st := ui.stack_open(gtx)
			defer ui.close(&st)
			m3.split_button(gtx, "Save", &m.split_menu, .Filled, .Edit, key = 3)
			SAVE := [?]m3.Menu_Item{{label = "Save as..."}, {label = "Save a copy"}, {label = "Export PDF", leading = .Download}}
			if i := m3.menu(gtx, &m.split_menu, SAVE[:], {0, 44}, key = 4); i >= 0 {
				m.menu_pick = SAVE[i].label
			}
		}
		STYLES := [?]m3.Menu_Style{.Standard, .Vibrant, .Vibrant}
		NAMES := [?]string{"Standard", "Vibrant", "Grouped"}
		for style, i in STYLES {
			st := ui.stack_open(gtx, key = u64(10 + i))
			defer ui.close(&st)
			if m3.button(gtx, NAMES[i], .Tonal, key = u64(20 + i)) {
				m.menu_styles[i] = !m.menu_styles[i]
			}
			// The sort group is single-select: its check follows m.menu_sort.
			items := MENU_GROUPED
			sort := m.menu_sort == "" ? "Name" : m.menu_sort
			for &it in items {
				if it.selected_icon != .None {
					it.selected = it.label == sort
				}
			}
			if pick := m3.menu(gtx, &m.menu_styles[i], items[:], {0, 44}, style = style, grouped = i == 2, key = u64(30 + i)); pick >= 0 {
				m.menu_pick = items[pick].label
				if items[pick].selected_icon != .None {
					m.menu_sort = items[pick].label
				}
			}
		}
	}
	base.label(gtx, m.menu_pick == "" ? "Nothing picked yet" : fmt.tprintf("Picked: %s", m.menu_pick), {color = m3.scheme()[.On_Surface_Variant]})
	section(gtx, "Always open", "each style pinned open, its items in every state, a selected item and a submenu arrow; then a grouped menu")
	// Pinned open inline, in the layout, so the live popups above draw
	// over them rather than under.
	r := ui.wrap_open(gtx, gap = 24, align = .Start)
	defer ui.close(&r)
	pinned := true
	m3.menu(gtx, &pinned, MENU_STATES[:], modal = false, inline = true, key = 40)
	m3.menu(gtx, &pinned, MENU_STATES[:], modal = false, style = .Standard, inline = true, key = 41)
	m3.menu(gtx, &pinned, MENU_STATES[:], modal = false, style = .Vibrant, inline = true, key = 42)
	m3.menu(gtx, &pinned, MENU_GROUPED[:], modal = false, style = .Standard, grouped = true, inline = true, key = 43)
}

page_dialogs :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	section(gtx, "Basic dialog", "surface-container-high, corner 28, 6dp, 24dp padding, headline-small; 280-560dp wide; a 32% scrim behind")
	r := ui.row_open(gtx, gap = 12)
	if m3.button(gtx, "Open dialog", .Filled, key = 1) {
		m.dialog = true
	}
	if m3.button(gtx, "With icon", .Tonal, .Delete, key = 2) {
		m.dialog2 = true
	}
	if m3.button(gtx, "Stacked actions", .Outlined, key = 5) {
		m.dialog3 = true
	}
	ui.close(&r)
	if m.dialog_msg != "" {
		base.label(gtx, fmt.tprintf("Chose %s", m.dialog_msg), {color = m3.scheme()[.On_Surface_Variant]})
	}
	ACTIONS := [?]string{"Cancel", "Discard"}
	if i := m3.dialog(gtx, &m.dialog, m.window, "Discard draft?", "This draft will be removed from this device and everywhere you are signed in.", ACTIONS[:], key = 3); i >= 0 {
		m.dialog_msg = ACTIONS[i]
	}
	ACTIONS2 := [?]string{"Cancel", "Delete"}
	if i := m3.dialog(gtx, &m.dialog2, m.window, "Permanently delete?", "Deleting the selected messages will also remove them from all synced devices.", ACTIONS2[:], .Delete, key = 4); i >= 0 {
		m.dialog_msg = ACTIONS2[i]
	}
	// Too wide for one row at 560dp: they stack, confirm first.
	ACTIONS3 := [?]string{"Keep the old version for now", "Replace it everywhere", "Merge both versions together"}
	if i := m3.dialog(gtx, &m.dialog3, m.window, "Replace the file?", "A file with this name already exists in this folder.", ACTIONS3[:], key = 6); i >= 0 {
		m.dialog_msg = ACTIONS3[i]
	}
}

page_tooltips :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	section(gtx, "Plain tooltip", "inverse-surface, body-small, corner 4, 8×4dp padding, wraps at 200dp; a 16×8dp caret points at the anchor")
	{
		r := ui.wrap_open(gtx, gap = 16, align = .Center)
		defer ui.close(&r)
		m3.plain_tooltip(gtx, "Save to favourites", key = 1)
		m3.plain_tooltip(gtx, "Caret up", .Up, key = 2)
		m3.plain_tooltip(gtx, "Caret down", .Down, key = 3)
		m3.plain_tooltip(gtx, "Caret left", .Left, key = 4)
		m3.plain_tooltip(gtx, "Caret right", .Right, key = 5)
		m3.plain_tooltip(gtx, "A plain tooltip whose label runs past the 200dp maximum wraps onto a second line", key = 6)
	}
	section(gtx, "Rich tooltip", "surface-container, 3dp, corner 12, 320dp max; subhead baseline 28dp down, body 24dp under it")
	{
		r := ui.wrap_open(gtx, gap = 16)
		defer ui.close(&r)
		m3.rich_tooltip(gtx, "Rich tooltip", "Rich tooltips bring attention to a particular element or feature that warrants the user's focus.", "Learn more", key = 10)
		m3.rich_tooltip(gtx, "No action", "Without an action the body gets 16dp below it.", key = 11)
		m3.rich_tooltip(gtx, "", "Body only, with a caret pointing up at its anchor.", caret = .Up, key = 12)
	}
	section(gtx, "Live", "hover an icon button: the tooltip shows at once and hides after 1.5s")
	r := ui.wrap_open(gtx, gap = 8)
	defer ui.close(&r)
	TIPS := [?]string{"Favourite", "Share", "Bookmark", "Delete"}
	GLYPHS := [?]m3.Icon{.Favorite, .Share, .Bookmark, .Delete}
	for tip, i in TIPS {
		m3.icon_button(gtx, GLYPHS[i], tooltip = tip, key = u64(20 + i))
	}
}

page_snackbar :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	section(gtx, "Snackbar", "inverse-surface, body-medium, corner 4, 6dp; 48dp one line, 68dp two; inverse-primary action; 600dp max")
	m3.snackbar(gtx, "Photo saved", key = 1)
	m3.snackbar(gtx, "Connection lost", "Retry", key = 2)
	m3.snackbar(gtx, "Message archived", "Undo", closable = true, key = 3)
	m3.snackbar(gtx, "Two lines: this message is long enough that it wraps onto a second line beside its action", "Undo", width = 480, key = 4)
	m3.snackbar(gtx, "The action on its own row, for a long action label", "Open the settings", closable = true, width = 420, action_on_new_line = true, key = 5)
	section(gtx, "Action and close icon states")
	state_header(gtx, SNACKBAR_CELL_W)
	state_row(gtx, m, "Snackbar", snackbar_cell, 6, SNACKBAR_CELL_W)
	section(gtx, "Live", "shows at the bottom of the window; with an action it stays until acted on or closed (indefinite)")
	{
		r := ui.wrap_open(gtx, gap = 12)
		defer ui.close(&r)
		if m3.button(gtx, "Archive", .Tonal, .Archive, key = 10) {
			m.snack = true
			m.snack_n += 1
			m.snack_t = 0
			m.snack_short = false
		}
		if m3.button(gtx, "Save (4s)", .Tonal, .Download, key = 11) {
			m.snack = true
			m.snack_t = 0
			m.snack_short = true
		}
	}
	if m.snack {
		o := ui.overlay_open(gtx, cs = ui.loose(m.window), root = true)
		defer ui.close(&o)
		c := ui.centered_open(gtx)
		defer ui.close(&c)
		cc := ui.column_open(gtx)
		defer ui.close(&cc)
		ui.spacer(gtx, m.window.y - 48 - 24)
		acted, closed: bool
		if m.snack_short {
			_, closed = m3.snackbar(gtx, "Saved to downloads", width = 344, timer = &m.snack_t, key = 20)
		} else {
			acted, closed = m3.snackbar(gtx, fmt.tprintf("%d archived", m.snack_n), "Undo", closable = true, width = 344, timer = &m.snack_t, key = 21)
		}
		if acted {
			m.snack_n = max(m.snack_n - 1, 0)
			m.snack = false
		}
		if closed {
			m.snack = false
		}
	}
}

// SNACKBAR_CELL_W is a state cell wide enough for snackbar_cell.
SNACKBAR_CELL_W :: f32(190)

// snackbar_cell is a snackbar whose action and close icon take st.
snackbar_cell :: proc(gtx: ^ui.Ctx, m: ^Model, st: m3.Interaction, key: u64) {
	m3.snackbar(gtx, "Archived", "Undo", closable = true, state = st, key = key)
}
