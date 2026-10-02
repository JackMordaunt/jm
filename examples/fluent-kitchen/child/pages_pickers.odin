package main

import "core:fmt"
import "jm:examples/kitchen"
import "jm:ui"
import "jm:ui/base"
import "jm:ui/fluent"

// The pickers group: combobox and dropdown, select, spin button, search
// box, tag picker, swatch picker, colour picker and rating, on the
// fluent-kit's specs.

PICKER_APPEARANCES := [?]fluent.Input_Appearance{.Outline, .Underline, .Filled_Darker, .Filled_Lighter}
PICKER_APPEARANCE_NAMES := [?]string{"Outline", "Underline", "Filled darker", "Filled lighter"}
PICKER_CELL_W :: f32(270)
PICKER_FRUIT := [?]string{"Apple", "Banana", "Cherry", "Date", "Elderberry", "Fig", "Grape", "Honeydew", "Kiwi", "Lemon"}
PICKER_PEOPLE := [?]string{"Katri Ahokas", "Elvia Atkins", "Cameron Evans", "Wanda Howard", "Mona Kane", "Allan Munger"}
PICKER_SWATCHES := [?]fluent.Swatch {
	{color = {196, 49, 75, 255}, name = "cranberry"},
	{color = {202, 80, 16, 255}, name = "pumpkin"},
	{color = {234, 163, 0, 255}, name = "marigold"},
	{color = {16, 124, 16, 255}, name = "green"},
	{color = {0, 120, 212, 255}, name = "blue"},
	{color = {92, 46, 145, 255}, name = "purple"},
	{color = {255, 255, 255, 255}, border = {209, 209, 209, 255}, name = "white"},
	{empty = true, name = "none"},
}
PICKER_SWATCH_SIZES := [?]string{"Extra small", "Small", "Medium", "Large"}
PICKER_SWATCH_SHAPES := [?]string{"Square", "Rounded", "Circular"}
RATING_SIZE_NAMES := [?]string{"Small", "Medium", "Large", "Extra large"}
RATING_COLOR_NAMES := [?]string{"Neutral", "Brand", "Marigold"}

// init_pickers sets the pickers' model defaults once: nothing picked,
// a count, a colour.
init_pickers :: proc(m: ^Model) {
	if m.pk_ready {
		return
	}
	m.pk_ready = true
	m.pk_pick, m.pk_drop, m.pk_clear_pick, m.pk_select = -1, -1, 2, -1
	m.pk_grid_pick = 1
	m.pk_count, m.pk_price = 3, 9.5
	m.pk_chosen = {true, false, true, false, false, false}
	m.pk_grid_chosen = {true, true, false, false, false, false}
	m.pk_swatch, m.pk_swatch_grid = 4, 1
	m.pk_hsv = {210, 0.7, 0.8, 1}
	m.pk_stars, m.pk_halves = 3, 3.5
	ui.text_set(&m.pk_clear, PICKER_FRUIT[2])
}

page_combobox :: proc(gtx: ^ui.Ctx, m: ^Model) {
	init_pickers(m)
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	kitchen.section(gtx, "Appearances", "medium: 32px, 250px minimum, body1; only outline steps its border; focus grows a 2px brand line")
	kitchen.state_header(gtx, PICKER_CELL_W)
	for n, i in PICKER_APPEARANCE_NAMES {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: fluent.Interaction, key: u64) {
			m := (^Model)(user)
			fluent.dropdown(gtx, PICKER_FRUIT[:], &m.pk_grid_pick, "Pick a fruit", PICKER_APPEARANCES[key / 16 - 1], width = 250, state = st, key = key)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 1), PICKER_CELL_W)
	}
	kitchen.section(gtx, "Sizes", "24 / 32 / 40px; caption1 / body1 / body2; 16 / 20 / 24px chevron")
	kitchen.state_header(gtx, PICKER_CELL_W)
	for n, i in SIZE_NAMES {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: fluent.Interaction, key: u64) {
			m := (^Model)(user)
			fluent.dropdown(gtx, PICKER_FRUIT[:], &m.pk_grid_pick, "Pick a fruit", size = fluent.Size(key / 16 - 11), width = 250, state = st, key = key)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 11), PICKER_CELL_W)
	}
	kitchen.section(gtx, "Live", "type to filter; Down, Up, Enter and Escape; the clearable one swaps its chevron for a dismiss")
	r := ui.wrap_open(gtx, gap = 16, align = .Start)
	defer ui.close(&r)
	fluent.combobox(gtx, &m.pk_fruit, PICKER_FRUIT[:], &m.pk_pick, "Type a fruit", width = 260, key = 100)
	fluent.dropdown(gtx, PICKER_FRUIT[:], &m.pk_drop, "Dropdown", width = 260, key = 101)
	fluent.combobox(gtx, &m.pk_clear, PICKER_FRUIT[:], &m.pk_clear_pick, "Clearable", clearable = true, width = 260, key = 102)
}

page_select :: proc(gtx: ^ui.Ctx, m: ^Model) {
	init_pickers(m)
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	kitchen.section(gtx, "Appearances", "Input's looks; hover and press step the sides but never the bottom edge; the focus line sits inside")
	kitchen.state_header(gtx, PICKER_CELL_W)
	for n, i in PICKER_APPEARANCE_NAMES {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: fluent.Interaction, key: u64) {
			m := (^Model)(user)
			fluent.select(gtx, PICKER_FRUIT[:], &m.pk_grid_pick, "Choose", PICKER_APPEARANCES[key / 16 - 1], width = 240, state = st, key = key)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 1), PICKER_CELL_W)
	}
	kitchen.section(gtx, "Live", "the platform's popup is the listbox here")
	fluent.select(gtx, PICKER_FRUIT[:], &m.pk_select, "Choose a fruit", width = 240, key = 100)
}

page_spin_button :: proc(gtx: ^ui.Ctx, m: ^Model) {
	init_pickers(m)
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	kitchen.section(gtx, "Appearances", "a 24px column of stacked buttons; outline and underline tint Subtle, the filled ones their own fill")
	kitchen.state_header(gtx, 190)
	for n, i in PICKER_APPEARANCE_NAMES {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: fluent.Interaction, key: u64) {
			v := f32(12)
			fluent.spin_button(gtx, &v, appearance = PICKER_APPEARANCES[key / 16 - 1], width = 160, state = st, key = key)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 1), 190)
	}
	kitchen.section(gtx, "Sizes", "small 24px with 12px buttons, medium 32px with 16px buttons")
	kitchen.state_header(gtx, 190)
	for n, i in SIZE_NAMES[:2] {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: fluent.Interaction, key: u64) {
			v := f32(12)
			fluent.spin_button(gtx, &v, size = fluent.Size(key / 16 - 11), width = 160, state = st, key = key)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 11), 190)
	}
	kitchen.section(gtx, "Live", "buttons, Up and Down, Page keys by ten; hold a button to spin; type and Enter to commit")
	r := ui.wrap_open(gtx, gap = 16, align = .Center)
	defer ui.close(&r)
	fluent.spin_button(gtx, &m.pk_count, lo = 0, hi = 20, name = "Guests", width = 160, key = 100)
	fluent.spin_button(gtx, &m.pk_price, step = 0.5, lo = 0, name = "Price", appearance = .Filled_Darker, width = 160, key = 101)
	base.label(gtx, fmt.tprintf("%v guests at %.2f", m.pk_count, m.pk_price))
}

page_search_box :: proc(gtx: ^ui.Ctx, m: ^Model) {
	init_pickers(m)
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	kitchen.section(gtx, "Appearances", "Input with the Search icon leading; at most 468px wide")
	kitchen.state_header(gtx, PICKER_CELL_W)
	for n, i in PICKER_APPEARANCE_NAMES {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: fluent.Interaction, key: u64) {
			m := (^Model)(user)
			fluent.search_box(gtx, &m.pk_empty, appearance = PICKER_APPEARANCES[key / 16 - 1], width = 240, state = st, key = key)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 1), PICKER_CELL_W)
	}
	kitchen.section(gtx, "Sizes", "the dismiss icon is 16 / 20 / 24px")
	kitchen.state_header(gtx, PICKER_CELL_W)
	for n, i in SIZE_NAMES {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: fluent.Interaction, key: u64) {
			m := (^Model)(user)
			fluent.search_box(gtx, &m.pk_empty, size = fluent.Size(key / 16 - 11), width = 240, state = st, key = key)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 11), PICKER_CELL_W)
	}
	kitchen.section(gtx, "Live", "type; the dismiss control shows while focused with text; Escape clears")
	fluent.search_box(gtx, &m.pk_query, "Search files", width = 320, key = 100)
}

page_tag_picker :: proc(gtx: ^ui.Ctx, m: ^Model) {
	init_pickers(m)
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	kitchen.section(gtx, "Appearances", "picks show as filled tags one size down; the control is 250px at least")
	kitchen.state_header(gtx, 330)
	for n, i in PICKER_APPEARANCE_NAMES {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: fluent.Interaction, key: u64) {
			m := (^Model)(user)
			fluent.tag_picker(gtx, &m.pk_empty, PICKER_PEOPLE[:2], m.pk_grid_chosen[:2], "People", PICKER_APPEARANCES[key / 16 - 1], width = 310, state = st, key = key)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 1), 330)
	}
	kitchen.section(gtx, "Sizes", "medium 32px / large 40px / extra-large 44px, holding extra-small / small / medium tags")
	TP_SIZES := [?]string{"Medium", "Large", "Extra large"}
	kitchen.state_header(gtx, 330)
	for n, i in TP_SIZES {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: fluent.Interaction, key: u64) {
			m := (^Model)(user)
			fluent.tag_picker(gtx, &m.pk_empty, PICKER_PEOPLE[:2], m.pk_grid_chosen[:2], "People", size = fluent.Tag_Picker_Size(key / 16 - 11), width = 310, state = st, key = key)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 11), 330)
	}
	kitchen.section(gtx, "Live", "click to open, type to filter, pick to add; click a tag or Backspace in the empty text to remove")
	fluent.tag_picker(gtx, &m.pk_people, PICKER_PEOPLE[:], m.pk_chosen[:], "Add people", width = 480, key = 100)
}

page_swatch_picker :: proc(gtx: ^ui.Ctx, m: ^Model) {
	init_pickers(m)
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	kitchen.section(gtx, "Sizes", "20 / 24 / 28 / 32px; the selected swatch wears a brand ring inside a light one")
	for n, i in PICKER_SWATCH_SIZES {
		r := ui.row_open(gtx, gap = 16, align = .Center, key = u64(i))
		base.label(gtx, n, {size = 12})
		sel := 4
		fluent.swatch_picker(gtx, PICKER_SWATCHES[:], &sel, size = fluent.Swatch_Size(i), state = .Enabled, key = u64(10 + i))
		ui.close(&r)
	}
	kitchen.section(gtx, "Shapes and states", "square, rounded, circular; the second row forces hovered, pressed and focused")
	for n, i in PICKER_SWATCH_SHAPES {
		r := ui.row_open(gtx, gap = 16, align = .Center, key = u64(20 + i))
		base.label(gtx, n, {size = 12})
		sel := 0
		fluent.swatch_picker(gtx, PICKER_SWATCHES[:4], &sel, shape = fluent.Swatch_Shape(i), state = .Enabled, key = u64(30 + i))
		for st, j in ([]fluent.Interaction{.Hovered, .Pressed, .Focused}) {
			none := -1
			fluent.swatch_picker(gtx, PICKER_SWATCHES[:1], &none, shape = fluent.Swatch_Shape(i), state = st, key = u64(40 + i * 3 + j))
		}
		ui.close(&r)
	}
	kitchen.section(gtx, "Live", "click, or arrows on a focused swatch; the grid wraps at four columns")
	r := ui.row_open(gtx, gap = 32, align = .Start)
	defer ui.close(&r)
	fluent.swatch_picker(gtx, PICKER_SWATCHES[:], &m.pk_swatch, key = 100)
	fluent.swatch_picker(gtx, PICKER_SWATCHES[:], &m.pk_swatch_grid, columns = 4, shape = .Circular, size = .Large, key = 101)
}

page_color_picker :: proc(gtx: ^ui.Ctx, m: ^Model) {
	init_pickers(m)
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	kitchen.section(gtx, "Picker", "a 300px saturation-and-value area, the hue rail and the alpha rail over a checkerboard, sharing one colour")
	r := ui.row_open(gtx, gap = 32, align = .Start)
	fluent.color_picker(gtx, &m.pk_hsv, key = 1)
	{
		c := ui.column_open(gtx, gap = 12, key = 2)
		c3 := fluent.hsv_to_rgb(m.pk_hsv)
		base.label(gtx, fmt.tprintf("#%02x%02x%02x  alpha %.0f%%", c3[0], c3[1], c3[2], m.pk_hsv.a * 100))
		fluent.color_slider(gtx, &m.pk_hsv, .Saturation, 300, key = 3)
		fluent.color_slider(gtx, &m.pk_hsv, .Value, 300, shape = .Square, key = 4)
		v := ui.row_open(gtx, gap = 12, key = 5)
		fluent.color_slider(gtx, &m.pk_hsv, .Hue, vertical = true, key = 6)
		fluent.alpha_slider(gtx, &m.pk_hsv, vertical = true, transparency = true, key = 7)
		ui.close(&v)
		ui.close(&c)
	}
	ui.close(&r)
	kitchen.section(gtx, "Focused", "the area's thumb takes the default outline; a slider's thumb border turns Stroke_Focus2")
	f := ui.row_open(gtx, gap = 24, align = .Center, key = 8)
	defer ui.close(&f)
	hsv := m.pk_hsv
	fluent.color_slider(gtx, &hsv, .Hue, 240, state = .Focused, key = 9)
	fluent.alpha_slider(gtx, &hsv, 240, state = .Focused, key = 10)
}

page_rating :: proc(gtx: ^ui.Ctx, m: ^Model) {
	init_pickers(m)
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	kitchen.section(gtx, "Sizes", "12 / 16 / 20 / 28px stars; a rating's unfilled stars are outlines, a display's the muted fill")
	for n, i in RATING_SIZE_NAMES {
		r := ui.row_open(gtx, gap = 24, align = .Center, key = u64(i))
		base.label(gtx, n, {size = 12})
		v := f32(3.5)
		fluent.rating(gtx, &v, half_steps = true, size = fluent.Rating_Size(i), state = .Enabled, key = u64(10 + i))
		fluent.rating_display(gtx, 3.5, 1160, size = fluent.Rating_Size(i), key = u64(20 + i))
		ui.close(&r)
	}
	kitchen.section(gtx, "Colours", "neutral, brand and marigold")
	for n, i in RATING_COLOR_NAMES {
		r := ui.row_open(gtx, gap = 24, align = .Center, key = u64(30 + i))
		base.label(gtx, n, {size = 12})
		v := f32(4)
		fluent.rating(gtx, &v, tint = fluent.Rating_Color(i), state = .Enabled, key = u64(40 + i))
		fluent.rating_display(gtx, 4, size = .Large, tint = fluent.Rating_Color(i), key = u64(50 + i))
		fluent.rating_display(gtx, 4.5, 23, compact = true, size = .Large, tint = fluent.Rating_Color(i), key = u64(60 + i))
		ui.close(&r)
	}
	kitchen.section(gtx, "Live", "hover to preview, click to rate; the second takes half stars from a star's left half")
	r := ui.row_open(gtx, gap = 24, align = .Center, key = 70)
	defer ui.close(&r)
	fluent.rating(gtx, &m.pk_stars, key = 71)
	fluent.rating(gtx, &m.pk_halves, half_steps = true, tint = .Marigold, name = "half", key = 72)
	base.label(gtx, fmt.tprintf("%v and %v", m.pk_stars, m.pk_halves))
}
