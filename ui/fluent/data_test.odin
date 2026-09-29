package fluent

import "core:slice"
import "core:testing"
import "jm:ui"

// Behaviour of the data display components, driven through ui.Probe.

@(private = "file")
Data_Model :: struct {
	sort:      Sort_Direction,
	sorts:     int,
	rows:      [3]bool,
	row_hits:  int,
	single:    int,
	multi:     [3]bool,
	dismissed: int,
	primary:   int,
	removed:   int,
	group:     bool,
}

@(private = "file")
COLUMNS := [?]f32{160, 0}

@(private = "file")
NAMES := [?]string{"Katri Ahokas", "Elvia Atkins", "Cameron Evans", "Wanda Howard", "Mona Kane", "Allan Munger", "Erik Nason"}

@(private = "file")
data_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Data_Model)(user)
	col := ui.column_open(gtx, gap = 12)
	defer ui.close(&col)
	if table(gtx, COLUMNS[:]) {
		t := current_table()
		if table_header(gtx, t) {
			if table_header_cell(gtx, current_row(), "Name", &m.sort) {
				m.sorts += 1
			}
			table_header_cell(gtx, current_row(), "Modified")
		}
		ROWS := [3]string{"Report", "Plan", "Notes"}
		for name, i in ROWS {
			clicked: bool
			if table_row(gtx, t, &m.rows[i], &clicked, name = name, key = u64(i)) {
				table_cell_layout(gtx, current_row(), name, "Doc", {icon = .Document})
				table_cell(gtx, current_row(), "Today")
			}
			if clicked {
				m.row_hits += 1
			}
		}
	}
	if list(gtx, .Single, &m.single) {
		l := current_list()
		list_item(gtx, l, "Alpha")
		list_item(gtx, l, "Beta", key = 1)
	}
	lm := list_open(gtx, .Multi)
	for label, i in ([3]string{"Red", "Green", "Blue"}) {
		list_item(gtx, &lm, label, &m.multi[i], key = u64(i))
	}
	list_close(&lm)
	if tag(gtx, "Removable", dismissible = true) {
		m.dismissed += 1
	}
	tag(gtx, "Static", .Outline, key = 1)
	if c, d := interaction_tag(gtx, "Pick", .Brand); c {
		m.primary += 1
	} else if d {
		m.removed += 1
	}
	avatar_group(gtx, NAMES[:], max_inline = 3, open = &m.group)
	skeleton_item(gtx, 20, .Rectangle, width = 120)
	text_preset(gtx, "Heading", .Title3, {0, 0, 0, 255})
}

@(test)
test_table_sorts_and_selects_rows :: proc(t: ^testing.T) {
	m: Data_Model
	p: ui.Probe
	ui.probe_init(&p, data_view, &m, {600, 1200}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Name"))
	testing.expect_value(t, m.sort, Sort_Direction.Ascending)
	testing.expect(t, ui.probe_click(&p, "Name"))
	testing.expect_value(t, m.sort, Sort_Direction.Descending)
	testing.expect_value(t, m.sorts, 2)
	// "Modified" has no sort: it registers no input area.
	testing.expect(t, !ui.probe_click(&p, "Modified"))

	// A row is 44px at medium; the header's sortable cell at least 32.
	header := ui.probe_bounds(&p, "Name")
	testing.expect_value(t, header.h, 44)
	testing.expect_value(t, header.w, 160)
	// A row is tagged by its name on its own input area.
	testing.expect(t, ui.probe_click(&p, "Plan"))
	testing.expect(t, m.rows[1])
	testing.expect(t, !m.rows[0])
	testing.expect_value(t, m.row_hits, 1)
	testing.expect(t, ui.probe_click(&p, "Plan"))
	testing.expect(t, !m.rows[1])
}

@(test)
test_list_selects_one_or_many :: proc(t: ^testing.T) {
	m: Data_Model
	p: ui.Probe
	ui.probe_init(&p, data_view, &m, {600, 1200}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Beta"))
	testing.expect_value(t, m.single, 1)
	testing.expect(t, ui.probe_click(&p, "Alpha"))
	testing.expect_value(t, m.single, 0)
	testing.expect(t, ui.probe_click(&p, "Green"))
	testing.expect(t, ui.probe_click(&p, "Blue"))
	testing.expect(t, !m.multi[0] && m.multi[1] && m.multi[2])
	testing.expect(t, ui.probe_click(&p, "Green"))
	testing.expect(t, !m.multi[1])
	testing.expect_value(t, ui.probe_bounds(&p, "Alpha").h, LIST_ITEM_HEIGHT)
}

@(test)
test_tags_dismiss_and_act :: proc(t: ^testing.T) {
	m: Data_Model
	p: ui.Probe
	ui.probe_init(&p, data_view, &m, {600, 1200}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Removable"))
	testing.expect_value(t, m.dismissed, 1)
	// Focused by the click, Delete dismisses it too.
	ui.probe_key(&p, .Delete)
	testing.expect_value(t, m.dismissed, 2)
	// A static tag takes no input.
	testing.expect(t, !ui.probe_click(&p, "Static"))
	// A medium tag is 32px tall.
	testing.expect_value(t, ui.probe_bounds(&p, "Removable").h, 32)
	// An interaction tag's halves act apart.
	testing.expect(t, ui.probe_click(&p, "Pick"))
	testing.expect_value(t, m.primary, 1)
	testing.expect(t, ui.probe_click(&p, "dismiss"))
	testing.expect_value(t, m.removed, 1)
	testing.expect_value(t, m.primary, 1)
}

@(test)
test_avatar_group_overflows_past_its_max :: proc(t: ^testing.T) {
	m: Data_Model
	p: ui.Probe
	ui.probe_init(&p, data_view, &m, {600, 1200}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	// Seven names, three inline: the button counts the other four.
	b := ui.probe_bounds(&p, "+4")
	testing.expect_value(t, b.w, 32)
	testing.expect_value(t, b.h, 32)
	testing.expect(t, !slice.contains(ui.probe_names(&p), "Mona Kane"))
	testing.expect(t, ui.probe_click(&p, "+4"))
	testing.expect(t, m.group)
	// Open, the popover lists the overflow by name.
	testing.expect(t, slice.contains(ui.probe_names(&p), "Mona Kane"))
	testing.expect(t, !slice.contains(ui.probe_names(&p), "Katri Ahokas"))
	ui.probe_key(&p, .Escape)
	testing.expect(t, !m.group)
}

@(test)
test_skeleton_and_text_size_and_animate :: proc(t: ^testing.T) {
	m: Data_Model
	p: ui.Probe
	ui.probe_init(&p, data_view, &m, {600, 1200}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	names := ui.probe_names(&p)
	testing.expect(t, slice.contains(names, "skeleton"))
	testing.expect(t, slice.contains(names, "Heading"))
	// The skeleton's wave never settles.
	testing.expect(t, p.wants_frame)
	testing.expect_value(t, text_style(.S300, .Regular), style(.Body1))
	testing.expect_value(t, text_style(.S500, .Semibold), style(.Subtitle1))
	testing.expect_value(t, tag_group_gap(.Small), f32(6))
}
