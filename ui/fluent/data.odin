package fluent

import "base:runtime"
import "core:fmt"
import "jm:ui"
import "jm:ui/design"
import tok "jm:ui/fluent/tokens"
import "jm:ui/ops"

// Data display: table, list, tag, persona, avatar group, skeleton, text
// and image, on the fluent-kit's table, list, tag, persona,
// avatar-group, skeleton, text and image specs and the styles files they
// cite at the kit's commit (source/COMMIT), as use<Name>Styles.
// styles.ts:lines. Every colour is a role; every hard-coded number is
// cited where it is used.

// Table.

// Table_Size is a table's row density: 44, 34 or 24px cells
// (useTableCellStyles.styles.ts:14-66).
Table_Size :: enum u8 {
	Medium,
	Small,
	Extra_Small,
}

// Table_Selection is how a selected row shows (TableRow.types.ts:17,
// useTableRowStyles.styles.ts:99-136): not at all, the brand tint, or
// the neutral tint.
Table_Selection :: enum u8 {
	None,
	Brand,
	Neutral,
}

// Table is an open table: its size, its column widths (0 for a column
// that shares the free width), and the column it lays its rows in.
Table :: struct {
	size:    Table_Size,
	columns: []f32,
	col:     ui.Flex,
}

// Table_Row is an open body or header row: which cell comes next, so
// cells find their column, and the row's containers.
Table_Row :: struct {
	table: ^Table,
	cell:  int,
	box:   ui.Box,
	row:   ui.Flex,
}

// Table_Row_Paint is what a body row's paint callback reads: its
// selection state and the results it reports back.
@(private)
Table_Row_Paint :: struct {
	size:       Table_Size,
	appearance: Table_Selection,
	selected:   ^bool,
	clicked:    ^bool,
	state:      Interaction,
	header:     bool,
	name:       string,
}

// TABLE_CELL_HEIGHT is a cell's height per size (useTableCellStyles.
// styles.ts:14-66: 44, 34 and 24px).
TABLE_CELL_HEIGHT := [Table_Size]f32{.Medium = 44, .Small = 34, .Extra_Small = 24}

// TABLE_SELECTION_WIDTH is the selection column, fixed at 44px in both
// layouts (useTableSelectionCellStyles.styles.ts:9).
TABLE_SELECTION_WIDTH :: f32(44)

// TABLE_HEADER_BUTTON_MIN is the header cell's button minimum height
// (useTableHeaderCellStyles.styles.ts:71-82).
@(private)
TABLE_HEADER_BUTTON_MIN :: f32(32)

// table_style is a cell's text: body1, or caption1 at extra-small, whose
// rows set fontSizeBase200 (useTableRowStyles.styles.ts:91-97).
@(private)
table_style :: proc(size: Table_Size) -> tok.Type_Style {
	return style(size == .Extra_Small ? .Caption1 : .Body1)
}

// table_open opens a table (table.json): a column of rows on the
// Subtle background, so it shows whatever surface it sits on. columns
// are the widths in px, 0 for a column that shares the free width; a
// row lays its cells in that order. Close it with table_close.
table_open :: proc(gtx: ^ui.Ctx, columns: []f32, size := Table_Size.Medium, key: u64 = 0, loc := #caller_location) -> Table {
	col := ui.column_open(gtx, align = .Fill, key = key, loc = loc)
	ui.container_semantics(gtx, {role = .Table})
	return {size, columns, col}
}

table_close :: proc(t: ^Table) {
	ui.close(&t.col)
}

// GUARD_DEPTH is how deeply guards of one kind (table, row, list) may
// nest on a thread.
@(private)
GUARD_DEPTH :: 8

// The open guards' handles: a guard cannot return its handle, so it
// keeps it here for its children and pops it when it closes. Per
// thread, like the scheme.
@(private = "file", thread_local)
open_tables: [GUARD_DEPTH]Table
@(private = "file", thread_local)
open_table_count: int
@(private = "file", thread_local)
open_rows: [GUARD_DEPTH]Table_Row
@(private = "file", thread_local)
open_row_count: int
@(private = "file", thread_local)
open_lists: [GUARD_DEPTH]List
@(private = "file", thread_local)
open_list_count: int

// table is table_open as a guard: `if fluent.table(gtx, cols) { … }`
// lays the rows out and closes the table at the end of the if; its rows
// reach the table through current_table.
@(deferred_in = table_guard_close)
table :: proc(gtx: ^ui.Ctx, columns: []f32, size := Table_Size.Medium, key: u64 = 0, loc := #caller_location) -> bool {
	assert(open_table_count < GUARD_DEPTH, "fluent: tables nested too deeply")
	open_tables[open_table_count] = table_open(gtx, columns, size, key, loc)
	open_table_count += 1
	return true
}

@(private = "file")
table_guard_close :: proc(gtx: ^ui.Ctx, columns: []f32, size: Table_Size, key: u64, loc: runtime.Source_Code_Location) {
	open_table_count -= 1
	table_close(&open_tables[open_table_count])
}

// current_table is the innermost table a table guard opened:
// `if fluent.table(gtx, cols) { t := fluent.current_table(); … }`.
current_table :: proc() -> ^Table {
	assert(open_table_count > 0, "fluent: current_table outside a table guard")
	return &open_tables[open_table_count - 1]
}

// table_row_open opens a body row: a box painted per state under the
// cells (Subtle Hover and Pressed, the appearance's selection tint,
// the bottom Stroke 2 border at medium and small) with a flex row for
// the cells. selected non-nil makes the row selectable, a click
// flipping it; clicked reports the click; name is what the row's input
// area is tagged, for a probe. The row's text colour does
// not reach its cells (no inherited colour): a cell picks its own.
// Close it with table_row_close.
table_row_open :: proc(
	gtx: ^ui.Ctx,
	t: ^Table,
	selected: ^bool = nil,
	clicked: ^bool = nil,
	appearance := Table_Selection.Brand,
	interactive := true,
	name := "",
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> Table_Row {
	rp := new(Table_Row_Paint, gtx.allocator)
	rp^ = {t.size, appearance, selected, clicked, state, !interactive, name}
	box := ui.box_open(gtx, {paint = paint_table_row, user = rp}, key, loc)
	ui.container_semantics(gtx, {role = .Row, label = name, states = state_if(selected != nil && selected^, {.Selected}) + state_if(interactive && state == .Disabled, {.Disabled})})
	row := ui.row_open(gtx, align = .Center)
	return {t, 0, box, row}
}

table_row_close :: proc(r: ^Table_Row) {
	ui.close(&r.row)
	ui.close(&r.box)
}

// table_row is table_row_open as a guard; cells reach the row through
// current_row.
@(deferred_in = table_row_guard_close)
table_row :: proc(
	gtx: ^ui.Ctx,
	t: ^Table,
	selected: ^bool = nil,
	clicked: ^bool = nil,
	appearance := Table_Selection.Brand,
	interactive := true,
	name := "",
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	push_row(table_row_open(gtx, t, selected, clicked, appearance, interactive, name, state, key, loc))
	return true
}

@(private = "file")
table_row_guard_close :: proc(gtx: ^ui.Ctx, t: ^Table, selected: ^bool, clicked: ^bool, appearance: Table_Selection, interactive: bool, name: string, state: Interaction, key: u64, loc: runtime.Source_Code_Location) {
	pop_row()
}

@(private = "file")
push_row :: proc(r: Table_Row) {
	assert(open_row_count < GUARD_DEPTH, "fluent: table rows nested too deeply")
	open_rows[open_row_count] = r
	open_row_count += 1
}

@(private = "file")
pop_row :: proc() {
	open_row_count -= 1
	table_row_close(&open_rows[open_row_count])
}

// current_row is the innermost row a table_row or table_header guard
// opened, for its cells.
current_row :: proc() -> ^Table_Row {
	assert(open_row_count > 0, "fluent: current_row outside a row guard")
	return &open_rows[open_row_count - 1]
}

// table_header_open opens the header row: the same box and flex, but
// it never takes the interactive row styles (table.json gotcha): its
// hover and press belong to the sortable header cells.
table_header_open :: proc(gtx: ^ui.Ctx, t: ^Table, key: u64 = 0, loc := #caller_location) -> Table_Row {
	return table_row_open(gtx, t, interactive = false, key = key, loc = loc)
}

table_header_close :: proc(r: ^Table_Row) {
	table_row_close(r)
}

// table_header is table_header_open as a guard.
@(deferred_in = table_header_guard_close)
table_header :: proc(gtx: ^ui.Ctx, t: ^Table, key: u64 = 0, loc := #caller_location) -> bool {
	push_row(table_header_open(gtx, t, key, loc))
	return true
}

@(private = "file")
table_header_guard_close :: proc(gtx: ^ui.Ctx, t: ^Table, key: u64, loc: runtime.Source_Code_Location) {
	pop_row()
}

// paint_table_row paints a body row under its cells: Subtle Hover and
// Pressed with the row's bottom border (useTableRowStyles.styles.ts:
// 32-35,62-81,91-97), the appearance's selection: Brand Background 2
// with a Transparent Stroke Interactive border, or Subtle Selected with
// a Neutral Stroke On Brand border, kept when pressed (styles.ts:
// 99-136), and on keyboard focus a 2px Stroke_Focus2 ring with
// borderRadiusMedium flush inside the row (styles.ts:36-50; the
// outline is drawn inside so rows do not overlap). A header row paints
// only the border. Colours change at once: no transition is declared.
@(private)
paint_table_row :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, size: ops.Size, user: rawptr) {
	rp := (^Table_Row_Paint)(user)
	area := ops.Rect{0, 0, size.x, size.y}
	c: Control
	if !rp.header {
		c = control(gtx, id, area, rp.state)
		if c.clicked && rp.selected != nil {
			rp.selected^ = !rp.selected^
		}
		if rp.clicked != nil {
			rp.clicked^ = c.clicked
		}
	}
	on := rp.selected != nil && rp.selected^
	bg := color_for({.Subtle_Background, .Subtle_Background_Hover, .Subtle_Background_Pressed, .Subtle_Background}, c)
	border := ops.Color{}
	if on {
		switch rp.appearance {
		case .Brand:
			bg = color(.Brand_Background2)
			border = color(.Transparent_Stroke_Interactive)
		case .Neutral:
			bg = color(.Subtle_Background_Selected)
			border = color(.Neutral_Stroke_On_Brand)
		case .None:
		}
	}
	if ui.painted(bg) {
		ops.fill(gtx.scene, area, bg)
	}
	if ui.painted(border) {
		stroke_inside(gtx, {area, 0}, border, tok.STROKE_WIDTH_THIN)
	}
	if rp.size != .Extra_Small {
		ops.fill(gtx.scene, ops.Rect{0, size.y - tok.STROKE_WIDTH_THIN, size.x, tok.STROKE_WIDTH_THIN}, color(.Neutral_Stroke2))
	}
	if c.focus_visible && !c.disabled {
		stroke_inside(gtx, {area, tok.BORDER_RADIUS_MEDIUM}, color(.Stroke_Focus2), FOCUS_OUTLINE_WIDTH)
	}
	if !rp.header {
		listen(gtx, c.st, id, area)
		if rp.name != "" {
			ops.tag(gtx.scene, id, ui.frame_string(gtx, rp.name))
		}
	}
}

// table_column_width is the width the next cell of r takes: its column's
// width, or the share the row's flex gives a 0 column. It advances r.cell.
@(private)
table_cell_width :: proc(gtx: ^ui.Ctx, r: ^Table_Row) -> (w: f32, flexible: bool) {
	i := r.cell
	r.cell += 1
	if i < len(r.table.columns) && r.table.columns[i] > 0 {
		return r.table.columns[i], false
	}
	return 0, true
}

// table_cell_open opens the next cell of r as a widget of its column's
// width and the size's height, padded spacingHorizontalS each side
// (useTableCellStyles.styles.ts:14-66); a flexible column takes its
// share of the row. It returns the cell's placement, content rect and
// the text style, for table_cell and the layouts to draw into; close
// it with table_cell_close.
@(private)
table_cell_open :: proc(gtx: ^ui.Ctx, r: ^Table_Row, key: u64, loc: runtime.Source_Code_Location, self := #caller_location) -> (p: ui.Placement, content: ops.Rect, st: tok.Type_Style) {
	w, flexible := table_cell_width(gtx, r)
	if flexible {
		ui.flexible(gtx, 1)
	}
	p = ui.widget_open(gtx, key, loc, self)
	cs := gtx.constraints
	h := TABLE_CELL_HEIGHT[r.table.size]
	width := w
	if flexible {
		width = ui.is_finite(cs.max.x) ? cs.max.x : 0
	}
	content = {tok.SPACING_HORIZONTAL_S, 0, max(width - 2 * tok.SPACING_HORIZONTAL_S, 0), h}
	return p, content, table_style(r.table.size)
}

// table_cell is a cell of one line of text in Foreground 1, truncated
// to its column (table.json layout cells, rows).
table_cell :: proc(gtx: ^ui.Ctx, r: ^Table_Row, text: string, color := ops.Color{}, key: u64 = 0, loc := #caller_location) -> ui.Dims {
	p, content, st := table_cell_open(gtx, r, key, loc)
	t := shape_style(gtx, text, st)
	fg := ui.or_color(color, role_color(.Neutral_Foreground1))
	w := content.w > 0 ? content.w + 2 * tok.SPACING_HORIZONTAL_S : t.width + 2 * tok.SPACING_HORIZONTAL_S
	sz := ui.constrain(gtx.constraints, {w, content.h})
	draw_clipped_line(gtx, t, {content.x, (sz.y - t.height) / 2}, max(sz.x - 2 * tok.SPACING_HORIZONTAL_S, 0), fg)
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, text))
	ui.semantics(gtx, &p, {role = .Cell, label = text})
	return ui.widget_close(gtx, &p, {sz, (sz.y - t.height) / 2 + baseline_of(t)})
}

// draw_clipped_line draws t at pos clipped to width: a cell's text
// stays in its column (table.json cell-layout truncate).
@(private)
draw_clipped_line :: proc(gtx: ^ui.Ctx, t: Text, pos: ops.Point, width: f32, fg: ops.Color) {
	if t.width <= width + 0.5 {
		draw_text(gtx, t, pos, fg)
		return
	}
	ops.clip_push(gtx.scene, ops.Rect{pos.x, pos.y, width, t.height})
	draw_text(gtx, t, pos, fg)
	ops.clip_pop(gtx.scene)
}

// Cell_Media is a cell layout's leading media: an icon, or an avatar of
// a name.
Cell_Media :: struct {
	icon: Icon,
	name: string, // an avatar's name; "" for none
}

// table_cell_layout is a cell with media, a main line and an optional
// description under it (useTableCellLayoutStyles.styles.ts:20-72,
// 88-105): a flex row with spacingHorizontalS gap; media 20px (16 at
// extra-small, 24 when primary); primary makes the main text semibold;
// the description is caption1 Foreground 2. Both lines truncate to the
// column.
table_cell_layout :: proc(
	gtx: ^ui.Ctx,
	r: ^Table_Row,
	main: string,
	description := "",
	media := Cell_Media{},
	primary := false,
	key: u64 = 0,
	loc := #caller_location,
) -> ui.Dims {
	p, content, st := table_cell_open(gtx, r, key, loc)
	if primary {
		st.weight = tok.FONT_WEIGHT_SEMIBOLD
	}
	t := shape_style(gtx, main, st)
	d := shape_text(gtx, description, .Caption1)
	media_px: f32 = primary ? 24 : r.table.size == .Extra_Small ? 16 : 20
	has_media := media.icon != .None || media.name != ""
	x := content.x
	natural := t.width
	if description != "" {
		natural = max(natural, d.width)
	}
	if has_media {
		natural += media_px + tok.SPACING_HORIZONTAL_S
	}
	w := content.w > 0 ? content.w + 2 * tok.SPACING_HORIZONTAL_S : natural + 2 * tok.SPACING_HORIZONTAL_S
	sz := ui.constrain(gtx.constraints, {w, content.h})
	text_h := t.height + (description != "" ? d.height : 0)
	y := (sz.y - text_h) / 2
	if has_media {
		my := (sz.y - media_px) / 2
		if media.name != "" {
			paint_avatar_disc(gtx, {x, my, media_px, media_px}, media.name, .Circular, .Colorful)
		} else {
			icon(gtx, media.icon, {x, my}, media_px, role_color(.Neutral_Foreground2))
		}
		x += media_px + tok.SPACING_HORIZONTAL_S
	}
	avail := max(sz.x - tok.SPACING_HORIZONTAL_S - x, 0)
	draw_clipped_line(gtx, t, {x, y}, avail, role_color(.Neutral_Foreground1))
	if description != "" {
		draw_clipped_line(gtx, d, {x, y + t.height}, avail, role_color(.Neutral_Foreground2))
	}
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, main))
	ui.semantics(gtx, &p, {role = .Cell, label = main, description = description})
	return ui.widget_close(gtx, &p, {sz, y + baseline_of(t)})
}

// Sort_Direction is a sortable column's order; None is unsorted.
Sort_Direction :: enum u8 {
	None,
	Ascending,
	Descending,
}

// table_header_cell is a header cell (useTableHeaderCellStyles.styles.
// ts:35-54,71-92): the column's label at fontWeightRegular in a button
// at least 32px tall. With sort non-nil it is sortable: a click or
// Enter cycles ascending and descending and the Arrow_Up or Arrow_Down
// icon after the label shows the direction, spacingHorizontalXS after
// the label; hovered it reads Subtle Hover with Foreground 1 Hover,
// pressed the Pressed twins. Returns true on the frame it was clicked.
table_header_cell :: proc(
	gtx: ^ui.Ctx,
	r: ^Table_Row,
	label: string,
	sort: ^Sort_Direction = nil,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p, content, st := table_cell_open(gtx, r, key, loc)
	st.weight = tok.FONT_WEIGHT_REGULAR
	t := shape_style(gtx, label, st)
	icon_px: f32 = r.table.size == .Extra_Small ? 12 : 16
	natural := t.width + 2 * tok.SPACING_HORIZONTAL_S
	if sort != nil {
		natural += tok.SPACING_HORIZONTAL_XS + icon_px
	}
	w := content.w > 0 ? content.w + 2 * tok.SPACING_HORIZONTAL_S : natural
	sz := ui.constrain(gtx.constraints, {w, max(content.h, TABLE_HEADER_BUTTON_MIN)})
	area := ops.Rect{0, 0, sz.x, sz.y}
	c: Control
	if sort != nil {
		c = control(gtx, p.id, area, state)
		if c.clicked {
			sort^ = sort^ == .Ascending ? .Descending : .Ascending
		}
	}
	bg := color_for({.Subtle_Background, .Subtle_Background_Hover, .Subtle_Background_Pressed, .Subtle_Background}, c)
	fg := color_for({.Neutral_Foreground1, .Neutral_Foreground1_Hover, .Neutral_Foreground1_Pressed, .Neutral_Foreground_Disabled}, c)
	if ui.painted(bg) {
		ops.fill(gtx.scene, area, bg)
	}
	y := (sz.y - t.height) / 2
	draw_clipped_line(gtx, t, {content.x, y}, max(sz.x - 2 * tok.SPACING_HORIZONTAL_S, 0), fg)
	if sort != nil {
		ic := Icon.None
		#partial switch sort^ {
		case .Ascending:
			ic = .Arrow_Up
		case .Descending:
			ic = .Arrow_Down
		}
		if ic == .None && (c.hovered || c.pressed) {
			ic = .Arrow_Sort
		}
		icon(gtx, ic, {content.x + t.width + tok.SPACING_HORIZONTAL_XS, (sz.y - icon_px) / 2 + tok.SPACING_VERTICAL_XXS / 2}, icon_px, fg)
		if c.focus_visible && !c.disabled {
			stroke_inside(gtx, {area, tok.BORDER_RADIUS_MEDIUM}, color(.Stroke_Focus2), FOCUS_OUTLINE_WIDTH)
		}
		listen(gtx, c.st, p.id, area)
	}
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, label))
	sorted := ""
	if sort != nil {
		#partial switch sort^ {
		case .Ascending:
			sorted = "ascending"
		case .Descending:
			sorted = "descending"
		}
	}
	ui.semantics(gtx, &p, {role = .Cell, label = label, value = sorted, states = state_if(c.disabled, {.Disabled})})
	ui.widget_close(gtx, &p, {sz, y + baseline_of(t)})
	return c.clicked
}

// Selection_Kind is a selection cell's control.
Selection_Kind :: enum u8 {
	Checkbox,
	Radio,
}

// table_selection_cell is the 44px selection column (useTableSelection
// CellStyles.styles.ts:9,17-53): a centred checkbox, or a radio, that
// selects the row; mixed shows the header's some-selected state. subtle
// draws it only while its row is hovered or pressed (the caller passes
// that: rows do not reach their cells), hidden keeps the width and
// draws nothing. Returns true on the frame it toggled.
table_selection_cell :: proc(
	gtx: ^ui.Ctx,
	r: ^Table_Row,
	checked: ^bool,
	kind := Selection_Kind.Checkbox,
	mixed := false,
	subtle := false,
	row_active := false,
	hidden := false,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	// The selection column is fixed at 44px and is not one of columns.
	p := ui.widget_open(gtx, key, loc)
	h := TABLE_CELL_HEIGHT[r.table.size]
	sz := ui.constrain(gtx.constraints, {TABLE_SELECTION_WIDTH, h})
	toggled := false
	if !hidden && (!subtle || row_active) {
		ind: f32 = 16
		box := ops.Rect{(sz.x - ind) / 2, (sz.y - ind) / 2, ind, ind}
		c := control(gtx, p.id, {0, 0, sz.x, sz.y}, state)
		if c.clicked {
			checked^ = mixed ? true : !checked^
			toggled = true
		}
		switch kind {
		case .Checkbox:
			paint_check_box(gtx, c, box, checked^, mixed)
		case .Radio:
			paint_radio_dot(gtx, c, box, checked^)
		}
		if c.focus_visible && !c.disabled {
			stroke_inside(gtx, {{0, 0, sz.x, sz.y}, tok.BORDER_RADIUS_MEDIUM}, color(.Stroke_Focus2), FOCUS_OUTLINE_WIDTH)
		}
		listen(gtx, c.st, p.id, ops.Rect{0, 0, sz.x, sz.y})
	}
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, kind == .Radio ? "radio" : "checkbox"))
	if !hidden {
		role: ops.Role = kind == .Radio ? .Radio : .Checkbox
		ui.semantics(gtx, &p, {role = role, states = state_if(mixed, {.Mixed}) + state_if(checked^ && !mixed, {.Checked}) + state_if(state == .Disabled, {.Disabled})})
	}
	ui.widget_close(gtx, &p, {size = sz})
	return toggled
}

// paint_check_box is a checkbox's 16px indicator alone, as the Checkbox
// component draws it (useCheckboxStyles.styles.ts): Stroke Accessible
// border unchecked, Compound Brand fill with the Checkmark checked, the
// square when mixed; hover and press step the Accessible and Compound
// twins; disabled reads the Disabled tokens.
@(private)
paint_check_box :: proc(gtx: ^ui.Ctx, c: Control, box: ops.Rect, checked, mixed: bool) {
	rr := ops.Round_Rect{box, tok.BORDER_RADIUS_SMALL}
	on := checked || mixed
	border := color_for({.Neutral_Stroke_Accessible, .Neutral_Stroke_Accessible_Hover, .Neutral_Stroke_Accessible_Pressed, .Neutral_Stroke_Disabled}, c)
	fill := ops.Color{}
	glyph := color_for({.Compound_Brand_Foreground1, .Compound_Brand_Foreground1_Hover, .Compound_Brand_Foreground1_Pressed, .Neutral_Foreground_Disabled}, c)
	if on {
		border = color_for({.Compound_Brand_Stroke, .Compound_Brand_Stroke_Hover, .Compound_Brand_Stroke_Pressed, .Neutral_Stroke_Disabled}, c)
	}
	if checked && !mixed {
		fill = color_for({.Compound_Brand_Background, .Compound_Brand_Background_Hover, .Compound_Brand_Background_Pressed, .Neutral_Background_Disabled}, c)
		glyph = color_for({.Neutral_Foreground_Inverted, .Neutral_Foreground_Inverted, .Neutral_Foreground_Inverted, .Neutral_Foreground_Disabled}, c)
		if c.disabled {
			fill = {}
		}
	}
	if ui.painted(fill) {
		ops.fill(gtx.scene, rr, fill)
	}
	stroke_inside(gtx, rr, border, tok.STROKE_WIDTH_THIN)
	if checked && !mixed {
		icon(gtx, .Checkmark, {box.x + 2, box.y + 2}, box.w - 4, glyph)
	} else if mixed {
		ops.fill(gtx.scene, ops.Round_Rect{{box.x + 4, box.y + 4, box.w - 8, box.h - 8}, 1}, glyph)
	}
}

// paint_radio_dot is a radio's 16px indicator alone (useRadioStyles.
// styles.ts): a Stroke Accessible ring, a Compound Brand dot when on.
@(private)
paint_radio_dot :: proc(gtx: ^ui.Ctx, c: Control, box: ops.Rect, on: bool) {
	border := color_for({.Neutral_Stroke_Accessible, .Neutral_Stroke_Accessible_Hover, .Neutral_Stroke_Accessible_Pressed, .Neutral_Stroke_Disabled}, c)
	if on {
		border = color_for({.Compound_Brand_Stroke, .Compound_Brand_Stroke_Hover, .Compound_Brand_Stroke_Pressed, .Neutral_Stroke_Disabled}, c)
	}
	ops.stroke(gtx.scene, ops.Ellipse{{box.x + 0.5, box.y + 0.5, box.w - 1, box.h - 1}}, border, {width = tok.STROKE_WIDTH_THIN})
	if on {
		dot := color_for({.Compound_Brand_Foreground1, .Compound_Brand_Foreground1_Hover, .Compound_Brand_Foreground1_Pressed, .Neutral_Foreground_Disabled}, c)
		ops.fill(gtx.scene, ops.Ellipse{{box.x + 4, box.y + 4, box.w - 8, box.h - 8}}, dot)
	}
}

// List.

// List_Selection is whether a list selects nothing, one item or many.
List_Selection :: enum u8 {
	None,
	Single,
	Multi,
}

// List is an open list: its selection mode, the single selection it
// keeps (nil for none or multi), the index the next item takes, and
// its column.
List :: struct {
	mode:     List_Selection,
	selected: ^int,
	next:     int,
	col:      ui.Flex,
}

// list_open opens a list (list.json): a plain column of items, the
// root resetting every margin. selected is the one selection in single
// mode. Close it with list_close.
list_open :: proc(gtx: ^ui.Ctx, mode := List_Selection.None, selected: ^int = nil, key: u64 = 0, loc := #caller_location) -> List {
	col := ui.column_open(gtx, align = .Fill, key = key, loc = loc)
	ui.container_semantics(gtx, {role = .List})
	return {mode, selected, 0, col}
}

list_close :: proc(l: ^List) {
	ui.close(&l.col)
}

// list is list_open as a guard; items reach it through current_list.
@(deferred_in = list_guard_close)
list :: proc(gtx: ^ui.Ctx, mode := List_Selection.None, selected: ^int = nil, key: u64 = 0, loc := #caller_location) -> bool {
	assert(open_list_count < GUARD_DEPTH, "fluent: lists nested too deeply")
	open_lists[open_list_count] = list_open(gtx, mode, selected, key, loc)
	open_list_count += 1
	return true
}

@(private = "file")
list_guard_close :: proc(gtx: ^ui.Ctx, mode: List_Selection, selected: ^int, key: u64, loc: runtime.Source_Code_Location) {
	open_list_count -= 1
	list_close(&open_lists[open_list_count])
}

// current_list is the innermost list a list guard opened, for its items.
current_list :: proc() -> ^List {
	assert(open_list_count > 0, "fluent: current_list outside a list guard")
	return &open_lists[open_list_count - 1]
}

// LIST_ITEM_HEIGHT is a row's height: the styles file gives an item no
// height, padding or hover of its own (list.json notes), so this is the
// design site's 32px row, with spacingHorizontalS padding.
LIST_ITEM_HEIGHT :: f32(32)

// list_item is one row of l (useListItemStyles.styles.ts:42-101):
// label at body1 Foreground 1, an optional icon before it, and in a
// selectable list a checkbox whose indicator has a 4px margin on every
// side (styles.ts:56-62) reflecting the selection. A click, Space or
// Enter toggles it in multi mode (checked^) or makes it the one
// selection in single mode; a navigable item reports the click.
// Keyboard focus draws the default outline. Hover reads Subtle Hover,
// the design site's look the file leaves to the caller (list.json
// notes). Returns true on the frame it was activated.
list_item :: proc(
	gtx: ^ui.Ctx,
	l: ^List,
	label: string,
	checked: ^bool = nil,
	ic := Icon.None,
	navigable := true,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	index := l.next
	l.next += 1
	p := ui.widget_open(gtx, key, loc)
	t := shape_text(gtx, label, .Body1)
	cs := gtx.constraints
	selectable := l.mode != .None
	ind: f32 = 16
	margin: f32 = 4 // useListItemStyles.styles.ts:56-62
	natural := 2 * tok.SPACING_HORIZONTAL_S + t.width
	if selectable {
		natural += ind + 2 * margin
	}
	if ic != .None {
		natural += 20 + tok.SPACING_HORIZONTAL_S
	}
	w := ui.is_finite(cs.max.x) ? cs.max.x : natural
	sz := ui.constrain(cs, {w, LIST_ITEM_HEIGHT})
	area := ops.Rect{0, 0, sz.x, sz.y}
	c: Control
	if selectable || navigable {
		c = control(gtx, p.id, area, state)
	}
	on := false
	switch l.mode {
	case .Single:
		on = l.selected != nil && l.selected^ == index
		if c.clicked && l.selected != nil {
			l.selected^ = index
			on = true
		}
	case .Multi:
		on = checked != nil && checked^
		if c.clicked && checked != nil {
			checked^ = !checked^
			on = checked^
		}
	case .None:
	}
	bg := color_for({.Subtle_Background, .Subtle_Background_Hover, .Subtle_Background_Pressed, .Subtle_Background}, c)
	if ui.painted(bg) {
		ops.fill(gtx.scene, ops.Round_Rect{area, tok.BORDER_RADIUS_MEDIUM}, bg)
	}
	x := tok.SPACING_HORIZONTAL_S
	if selectable {
		paint_check_box(gtx, c, {x + margin, (sz.y - ind) / 2, ind, ind}, on, false)
		x += ind + 2 * margin
	}
	fg := color_for({.Neutral_Foreground1, .Neutral_Foreground1_Hover, .Neutral_Foreground1_Pressed, .Neutral_Foreground_Disabled}, c)
	if ic != .None {
		icon(gtx, ic, {x, (sz.y - 20) / 2}, 20, fg)
		x += 20 + tok.SPACING_HORIZONTAL_S
	}
	y := (sz.y - t.height) / 2
	draw_clipped_line(gtx, t, {x, y}, max(sz.x - x - tok.SPACING_HORIZONTAL_S, 0), fg)
	if c.focus_visible && !c.disabled {
		stroke_inside(gtx, {area, tok.BORDER_RADIUS_MEDIUM}, color(.Stroke_Focus2), tok.STROKE_WIDTH_THICK)
	}
	if selectable || navigable {
		listen(gtx, c.st, p.id, area)
	}
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, label))
	ui.semantics(gtx, &p, {role = .List_Item, label = label, states = state_if(on, {.Selected}) + state_if(c.disabled, {.Disabled})})
	ui.widget_close(gtx, &p, {sz, y + baseline_of(t)})
	return c.clicked
}

// Tag.

// Tag_Appearance is a tag's colour treatment (tag.json variants).
Tag_Appearance :: enum u8 {
	Filled,
	Outline,
	Brand,
}

// Tag_Shape is a tag's corners: borderRadiusMedium or a pill.
Tag_Shape :: enum u8 {
	Rounded,
	Circular,
}

// Tag_Size is a tag's height: 32, 24 or 20px (useTagStyles.styles.ts:
// 127-136).
Tag_Size :: enum u8 {
	Medium,
	Small,
	Extra_Small,
}

// Tag_Metrics are one size's numbers (useTagStyles.styles.ts:22-28,
// 127-136,181-282): height, the inner side spacing, icon size, the
// media's gap to the text, the secondary button's padding around its
// icon, and the label's style.
@(private)
Tag_Metrics :: struct {
	height, spacing, icon, media_gap, secondary_pad: f32,
	style:                                           tok.Type_Style,
}

@(private)
tag_metrics :: proc(size: Tag_Size) -> Tag_Metrics {
	switch size {
	case .Medium:
		return {32, 7, 20, tok.SPACING_HORIZONTAL_S, 5, style(.Body1)}
	case .Small:
		return {24, 5, 16, tok.SPACING_HORIZONTAL_SNUDGE, 3, style(.Caption1)}
	case .Extra_Small:
	}
	return {20, 5, 12, tok.SPACING_HORIZONTAL_SNUDGE, 5, style(.Caption1)}
}

// Tag_Roles are one appearance's background, border and text per state
// on an InteractionTag's buttons, and the icon's hover tint where it
// differs (useTagStyles.styles.ts:102-115; useInteractionTagPrimary
// Styles.styles.ts:110-189).
@(private)
Tag_Roles :: struct {
	bg, border, text, icon: State_Roles,
	divider:                tok.Role,
}

@(private)
tag_roles :: proc(a: Tag_Appearance) -> (r: Tag_Roles) {
	switch a {
	case .Filled:
		r.bg = {.Neutral_Background3, .Neutral_Background3_Hover, .Neutral_Background3_Pressed, .Neutral_Background_Disabled}
		r.border = {.Transparent_Stroke, .Transparent_Stroke, .Transparent_Stroke, .Transparent_Stroke_Disabled}
		r.text = {.Neutral_Foreground2, .Neutral_Foreground2_Hover, .Neutral_Foreground2_Pressed, .Neutral_Foreground_Disabled}
		r.icon = {.Neutral_Foreground2, .Neutral_Foreground2_Brand_Hover, .Neutral_Foreground2_Brand_Pressed, .Neutral_Foreground_Disabled}
		r.divider = .Neutral_Stroke2
	case .Outline:
		r.bg = {.Subtle_Background, .Subtle_Background_Hover, .Subtle_Background_Pressed, .Subtle_Background}
		r.border = {.Neutral_Stroke1, .Neutral_Stroke1_Hover, .Neutral_Stroke1_Pressed, .Neutral_Stroke_Disabled}
		r.text = {.Neutral_Foreground2, .Neutral_Foreground2_Hover, .Neutral_Foreground2_Pressed, .Neutral_Foreground_Disabled}
		r.icon = {.Neutral_Foreground2, .Neutral_Foreground2_Brand_Hover, .Neutral_Foreground2_Brand_Pressed, .Neutral_Foreground_Disabled}
		r.divider = .Neutral_Stroke1
	case .Brand:
		r.bg = {.Brand_Background2, .Brand_Background2_Hover, .Brand_Background2_Pressed, .Neutral_Background_Disabled}
		r.border = {.Transparent_Stroke, .Transparent_Stroke, .Transparent_Stroke, .Transparent_Stroke_Disabled}
		r.text = {.Brand_Foreground2, .Compound_Brand_Foreground1_Hover, .Compound_Brand_Foreground1_Pressed, .Neutral_Foreground_Disabled}
		r.icon = r.text
		r.divider = .Brand_Stroke2
	}
	return
}

// SELECTED_TAG are a selected tag's roles: Brand Background stepping to
// its Hover and Pressed with on-brand text and a Brand Stroke 1 border
// (useTagStyles.styles.ts:116-126,310-317).
@(private)
selected_tag_roles :: proc() -> (r: Tag_Roles) {
	r.bg = {.Brand_Background, .Brand_Background_Hover, .Brand_Background_Pressed, .Neutral_Background_Disabled}
	r.border = {.Brand_Stroke1, .Brand_Stroke1, .Brand_Stroke1, .Transparent_Stroke_Disabled}
	r.text = {.Neutral_Foreground_On_Brand, .Neutral_Foreground_On_Brand, .Neutral_Foreground_On_Brand, .Neutral_Foreground_Disabled}
	r.icon = r.text
	r.divider = .Neutral_Stroke_On_Brand2
	return
}

// tag_radius is the shape's radius for a tag of height h.
@(private)
tag_radius :: proc(shape: Tag_Shape, h: f32) -> f32 {
	return shape == .Circular ? h / 2 : tok.BORDER_RADIUS_MEDIUM
}

// tag_content measures a tag's content: the label (and secondary line)
// and the media or icon before it, in the size's metrics; it returns
// the width from the left edge to the end of the text, the leading
// slot's width, and the shaped lines.
@(private)
Tag_Content :: struct {
	primary, secondary: Text,
	lead:               f32, // media or icon width, 0 for none
	width:              f32, // left edge to the end of the text
	text_x:             f32,
}

@(private)
tag_content :: proc(gtx: ^ui.Ctx, mt: Tag_Metrics, text, secondary: string, ic: Icon, media: string) -> (k: Tag_Content) {
	// With a secondary line the label is caption1 pulled up 2px and the
	// secondary caption2 (useTagStyles.styles.ts:320-357).
	if secondary != "" {
		k.primary = shape_text(gtx, text, .Caption1)
		k.secondary = shape_text(gtx, secondary, .Caption2)
	} else {
		k.primary = shape_style(gtx, text, mt.style)
	}
	x := mt.spacing
	switch {
	case media != "":
		// The media sits 1px in and leaves the gap before the text
		// (styles.ts:233-249).
		k.lead = mt.height - 2
		x = 1 + k.lead + mt.media_gap
	case ic != .None:
		k.lead = mt.icon
		x = mt.spacing + mt.icon + tok.SPACING_HORIZONTAL_XS
	}
	k.text_x = x
	tw := k.primary.width
	if secondary != "" {
		tw = max(tw, k.secondary.width)
	}
	k.width = x + tok.SPACING_HORIZONTAL_XXS + tw + tok.SPACING_HORIZONTAL_XXS
	return
}

// paint_tag_content draws the leading media or icon and the text of a
// tag into r with the given colours.
@(private)
paint_tag_content :: proc(gtx: ^ui.Ctx, mt: Tag_Metrics, k: Tag_Content, r: ops.Rect, ic: Icon, media: string, fg, icon_fg: ops.Color) {
	switch {
	case media != "":
		paint_avatar_disc(gtx, {r.x + 1, r.y + 1, k.lead, k.lead}, media, .Circular, .Colorful)
	case ic != .None:
		icon(gtx, ic, {r.x + mt.spacing, r.y + (r.h - mt.icon) / 2}, mt.icon, icon_fg)
	}
	x := r.x + k.text_x + tok.SPACING_HORIZONTAL_XXS
	if k.secondary.height > 0 {
		total := k.primary.height + k.secondary.height - 2
		y := r.y + (r.h - total) / 2
		draw_text(gtx, k.primary, {x, y - 2}, fg)
		draw_text(gtx, k.secondary, {x, y - 2 + k.primary.height}, fg)
	} else {
		draw_text(gtx, k.primary, {x, r.y + (r.h - k.primary.height) / 2}, fg)
	}
}

// tag is one static or dismissible tag (tag.json kind tag): media (an
// avatar of a name) or an icon, a label, an optional secondary line,
// and with dismissible a Dismiss icon after the text. The root takes no
// hover or pressed look of its own (the spec's gotcha); only the
// dismiss icon turns Foreground 2 Brand Hover under the pointer. A
// dismissible tag is a button: a click, or Enter, Space, Delete or
// Backspace while focused, dismisses it, and it returns true on that
// frame. selected paints the Brand Background look. Keyboard focus
// draws the default outline following the shape. An extra-small tag
// grows its hit area 2px above and below to the 24px target.
tag :: proc(
	gtx: ^ui.Ctx,
	text: string,
	appearance := Tag_Appearance.Filled,
	ic := Icon.None,
	media := "",
	secondary := "",
	size := Tag_Size.Medium,
	shape := Tag_Shape.Rounded,
	dismissible := false,
	selected := false,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_open(gtx, key, loc)
	mt := tag_metrics(size)
	k := tag_content(gtx, mt, text, secondary, ic, media)
	w := k.width
	if dismissible {
		w += mt.icon + mt.spacing
	} else {
		w += mt.spacing
	}
	sz := ui.constrain_min(gtx.constraints, {w, mt.height})
	area := ops.Rect{0, 0, sz.x, sz.y}
	band: f32 = size == .Extra_Small ? 2 : 0 // useTagStyles.styles.ts:133-154
	hit := ops.Rect{0, -band, sz.x, sz.y + 2 * band}
	c: Control
	if dismissible {
		c = control(gtx, p.id, hit, state)
		if c.st != nil {
			for e in ui.events(gtx, p.id) {
				if e.kind == .Key && c.focused && (e.key == .Delete || e.key == .Backspace) {
					c.clicked = true
				}
			}
		}
	} else if state == .Disabled {
		c.disabled = true
		c.state = .Disabled
	}
	r := selected ? selected_tag_roles() : tag_roles(appearance)
	rest := c
	rest.hovered, rest.pressed = false, false // the root never reacts
	rest.state = design.effective_state(rest)
	bg := color_for(r.bg, rest)
	border := color_for(r.border, rest)
	fg := color_for(r.text, rest)
	radius := tag_radius(shape, sz.y)
	rr := ops.Round_Rect{area, radius}
	if ui.painted(bg) {
		ops.fill(gtx.scene, rr, bg)
	}
	if ui.painted(border) {
		stroke_inside(gtx, rr, border, tok.STROKE_WIDTH_THIN)
	}
	paint_tag_content(gtx, mt, k, area, ic, media, fg, fg)
	if dismissible {
		dc := color_for(r.icon, c)
		if selected {
			dc = fg
		}
		icon(gtx, .Dismiss, {sz.x - mt.spacing - mt.icon, (sz.y - mt.icon) / 2}, mt.icon, dc)
		paint_focus_outline(gtx, c, rr)
		listen(gtx, c.st, p.id, hit)
	}
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, text))
	// A dismissible tag is a button, dismiss being its one action.
	role: ops.Role = dismissible ? .Button : .Text
	ui.semantics(gtx, &p, {role = role, label = text, description = secondary, states = state_if(selected, {.Selected}) + state_if(c.disabled, {.Disabled})})
	ui.widget_close(gtx, &p, {sz, (sz.y - k.primary.height) / 2 + baseline_of(k.primary)})
	return c.clicked
}

// interaction_tag is a tag split into a primary button carrying the
// content and the action and a secondary button carrying the dismiss
// (tag.json kind interaction-tag): each steps to its appearance's Hover
// and Pressed background and text under the pointer, the outline
// primary swapping its icon for the filled twin in Foreground 2 Brand
// Hover; the secondary draws the divider as its left border, has no
// left radius and pads its icon 5, 3 or 5px (useInteractionTagSecondary
// Styles.styles.ts:17-48,147-170). Returns whether the primary was
// clicked and whether the tag was dismissed.
interaction_tag :: proc(
	gtx: ^ui.Ctx,
	text: string,
	appearance := Tag_Appearance.Filled,
	ic := Icon.None,
	media := "",
	secondary := "",
	size := Tag_Size.Medium,
	shape := Tag_Shape.Rounded,
	dismissible := true,
	selected := false,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> (clicked, dismissed: bool) {
	p := ui.widget_open(gtx, key, loc)
	mt := tag_metrics(size)
	k := tag_content(gtx, mt, text, secondary, ic, media)
	pw := k.width + mt.spacing
	sw: f32 = dismissible ? mt.icon + 2 * mt.secondary_pad + tok.STROKE_WIDTH_THIN : 0
	sz := ui.constrain_min(gtx.constraints, {pw + sw, mt.height})
	pw = sz.x - sw
	band: f32 = size == .Extra_Small ? 2 : 0
	primary := ops.Rect{0, 0, pw, sz.y}
	second := ops.Rect{pw, 0, sw, sz.y}
	pc := control(gtx, p.id, {primary.x, -band, primary.w, primary.h + 2 * band}, state)
	sid := ui.id_mix(p.id, 1)
	sc: Control
	if dismissible {
		sc = control(gtx, sid, {second.x, -band, second.w, second.h + 2 * band}, state)
	}
	if pc.st != nil {
		for e in ui.events(gtx, p.id) {
			if e.kind == .Key && pc.focused && (e.key == .Delete || e.key == .Backspace) {
				sc.clicked = true
			}
		}
	}
	r := selected ? selected_tag_roles() : tag_roles(appearance)
	radius := tag_radius(shape, sz.y)
	ui.semantics(gtx, &p, {role = .Button, label = text, description = secondary, states = state_if(selected, {.Selected}) + state_if(pc.disabled, {.Disabled})})
	// The primary keeps the right corners square when a secondary follows
	// and drops its right border, drawn once by the secondary
	// (tag.json gotcha).
	pk := Corners{radius, dismissible ? 0 : radius, dismissible ? 0 : radius, radius}
	sk := Corners{0, radius, radius, 0}
	pbg, pborder, pfg := color_for(r.bg, pc), color_for(r.border, pc), color_for(r.text, pc)
	picon := color_for(r.icon, pc)
	shown := ic
	if appearance == .Outline && (pc.hovered || pc.pressed) && !pc.disabled {
		shown = filled(ic)
	}
	if ui.painted(pbg) {
		ops.fill(gtx.scene, rounded(gtx, primary, pk), pbg)
	}
	if ui.painted(pborder) {
		stroke_inside_corners(gtx, primary, pk, pborder, tok.STROKE_WIDTH_THIN)
	}
	paint_tag_content(gtx, mt, k, primary, shown, media, pfg, picon)
	if dismissible {
		sbg, sborder := color_for(r.bg, sc), color_for(r.border, sc)
		sicon := color_for(r.icon, sc)
		if selected {
			sicon = color_for(r.text, sc)
		}
		if ui.painted(sbg) {
			ops.fill(gtx.scene, rounded(gtx, second, sk), sbg)
		}
		if ui.painted(sborder) && appearance == .Outline {
			stroke_inside_corners(gtx, second, sk, sborder, tok.STROKE_WIDTH_THIN)
		}
		div := color(sc.disabled ? .Neutral_Stroke_Disabled : r.divider)
		ops.fill(gtx.scene, ops.Rect{second.x, 0, tok.STROKE_WIDTH_THIN, sz.y}, div)
		icon(gtx, .Dismiss, {second.x + tok.STROKE_WIDTH_THIN + mt.secondary_pad, (sz.y - mt.icon) / 2}, mt.icon, sicon)
		paint_focus_outline_corners(gtx, sc, second, sk)
		listen(gtx, sc.st, sid, second)
		ops.tag(gtx.scene, sid, ui.frame_string(gtx, "dismiss"))
		ui.part_semantics(gtx, &p, sid, second, {role = .Button, label = "dismiss", states = state_if(sc.disabled, {.Disabled})})
	}
	paint_focus_outline_corners(gtx, pc, primary, pk)
	listen(gtx, pc.st, p.id, primary)
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, text))
	ui.widget_close(gtx, &p, {sz, (sz.y - k.primary.height) / 2 + baseline_of(k.primary)})
	return pc.clicked, sc.clicked
}

// tag_group_gap is a group's column gap: spacingHorizontalS at medium,
// SNudge at small, XS at extra-small (useTagGroupStyles.styles.ts:15-28).
tag_group_gap :: proc(size: Tag_Size) -> f32 {
	switch size {
	case .Medium:
		return tok.SPACING_HORIZONTAL_S
	case .Small:
		return tok.SPACING_HORIZONTAL_SNUDGE
	case .Extra_Small:
	}
	return tok.SPACING_HORIZONTAL_XS
}

// tag_group_open opens a group (tag.json group): a wrapping row of tags
// with the size's gap; the tags pass the size themselves. Close it with
// ui.close.
tag_group_open :: proc(gtx: ^ui.Ctx, size := Tag_Size.Medium, key: u64 = 0, loc := #caller_location) -> ui.Flex {
	gap := tag_group_gap(size)
	return ui.wrap_open(gtx, gap = gap, line_gap = gap, align = .Center, key = key, loc = loc)
}

// tag_group is tag_group_open as a guard.
@(deferred_in = tag_group_guard_close)
tag_group :: proc(gtx: ^ui.Ctx, size := Tag_Size.Medium, key: u64 = 0, loc := #caller_location) -> bool {
	tag_group_open(gtx, size, key, loc)
	return true
}

@(private = "file")
tag_group_guard_close :: proc(gtx: ^ui.Ctx, size: Tag_Size, key: u64, loc: runtime.Source_Code_Location) {
	ui.innermost_close(gtx, .Flex)
}

// Persona.

// Persona_Size is a persona's size (persona.json), which picks its
// avatar's pixel size and its spacing.
Persona_Size :: enum u8 {
	Extra_Small,
	Small,
	Medium,
	Large,
	Extra_Large,
	Huge,
}

// Text_Position is where a persona's text sits against its media.
Text_Position :: enum u8 {
	After,
	Before,
	Below,
}

// PERSONA_AVATAR is the avatar size per persona size (persona.json
// notes: 20, 28, 32, 36, 40, 56px, set by the persona hook).
PERSONA_AVATAR := [Persona_Size]Avatar_Size{.Extra_Small = .S20, .Small = .S28, .Medium = .S32, .Large = .S36, .Extra_Large = .S40, .Huge = .S56}

// persona_spacing is the gap between media and text (usePersonaStyles.
// styles.ts:87-121): SNudge at extra-small, S at small and medium
// (SNudge when presence-only at small), MNudge at large and
// extra-large, M at huge.
@(private)
persona_spacing :: proc(size: Persona_Size, presence_only: bool) -> f32 {
	switch size {
	case .Extra_Small:
		return tok.SPACING_HORIZONTAL_SNUDGE
	case .Small:
		return presence_only ? tok.SPACING_HORIZONTAL_SNUDGE : tok.SPACING_HORIZONTAL_S
	case .Medium:
		return tok.SPACING_HORIZONTAL_S
	case .Large, .Extra_Large:
		return tok.SPACING_HORIZONTAL_MNUDGE
	case .Huge:
	}
	return tok.SPACING_HORIZONTAL_M
}

// persona is a person (persona.json): an avatar (or only a presence
// badge) beside the name in body1 Foreground 1 and up to three lines
// in caption1 Foreground 2, the second line pulled up 2px
// (usePersonaStyles.styles.ts:77-79,219-289); at extra-large and huge
// the name is subtitle2, at huge with an avatar the other lines body1,
// and a one-line presence-only extra-small persona's name is caption1.
// Text sits after, before or below the media. Nothing animates.
//
// Departure: text alignment center (the media centred against the text
// block) is the only alignment; start-aligned media is the row's
// centre here too, as the lines are few.
persona :: proc(
	gtx: ^ui.Ctx,
	name: string,
	secondary := "",
	tertiary := "",
	quaternary := "",
	size := Persona_Size.Medium,
	position := Text_Position.After,
	presence_only := false,
	status := Presence_Status.Available,
	out_of_office := false,
	color := Avatar_Color.Colorful,
	key: u64 = 0,
	loc := #caller_location,
) -> ui.Dims {
	p := ui.widget_open(gtx, key, loc)
	lines := [4]string{name, secondary, tertiary, quaternary}
	n := 1
	for l, i in lines[1:] {
		if l != "" {
			n = i + 2
		}
	}
	primary_role := Type_Role.Body1
	other_role := Type_Role.Caption1
	#partial switch size {
	case .Extra_Large:
		primary_role = .Subtitle2
	case .Huge:
		primary_role = .Subtitle2
		if !presence_only {
			other_role = .Body1
		}
	case .Extra_Small:
		if presence_only && n == 1 {
			primary_role = .Caption1
		}
	}
	shaped: [4]Text
	tw, th: f32
	for i in 0 ..< n {
		shaped[i] = shape_text(gtx, lines[i], i == 0 ? primary_role : other_role)
		tw = max(tw, shaped[i].width)
		th += shaped[i].height
	}
	if n > 1 {
		th -= 2 // the second line's pull-up
	}
	av := PERSONA_AVATAR[size]
	mpx := AVATAR_PX[av]
	if presence_only {
		mpx = f32(badge_px_for_avatar(av))
	}
	gap := persona_spacing(size, presence_only)
	sz: ops.Size
	switch position {
	case .After, .Before:
		sz = {mpx + gap + tw, max(mpx, th)}
	case .Below:
		sz = {max(mpx, tw), mpx + gap + th}
	}
	sz = ui.constrain(gtx.constraints, sz)
	media: ops.Rect
	text_at: ops.Point
	switch position {
	case .After:
		media = {0, (sz.y - mpx) / 2, mpx, mpx}
		text_at = {mpx + gap, (sz.y - th) / 2}
	case .Before:
		media = {sz.x - mpx, (sz.y - mpx) / 2, mpx, mpx}
		text_at = {sz.x - mpx - gap - tw, (sz.y - th) / 2}
	case .Below:
		media = {(sz.x - mpx) / 2, 0, mpx, mpx}
		text_at = {(sz.x - tw) / 2, mpx + gap}
	}
	if presence_only {
		paint_presence(gtx, media, status, out_of_office)
	} else {
		paint_avatar_disc(gtx, media, name, .Circular, color)
	}
	y := text_at.y
	for i in 0 ..< n {
		x := position == .Below ? text_at.x + (tw - shaped[i].width) / 2 : text_at.x
		draw_text(gtx, shaped[i], {x, y}, role_color(i == 0 ? .Neutral_Foreground1 : .Neutral_Foreground2))
		y += shaped[i].height - (i == 0 && n > 1 ? 2 : 0)
	}
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, name))
	ui.semantics(gtx, &p, {role = .Text, label = name, description = secondary})
	return ui.widget_close(gtx, &p, {sz, text_at.y + baseline_of(shaped[0])})
}

// badge_px_for_avatar is the presence badge size a persona of avatar
// size av shows alone (useAvatar's badge rule, as feedback.odin's
// avatar_metrics applies it).
@(private)
badge_px_for_avatar :: proc(av: Avatar_Size) -> int {
	m := avatar_metrics(av)
	return int(badge_metrics(m.badge).height)
}

// paint_avatar_disc paints an avatar's disc and initials into r, as the
// avatar component does (feedback.odin), for the places that lay
// several out themselves: a group's items, a persona, a tag's media.
// corner, when not negative, overrides the shape's radius: a pie's
// avatars lose theirs.
@(private)
paint_avatar_disc :: proc(gtx: ^ui.Ctx, r: ops.Rect, name: string, shape: Avatar_Shape, color: Avatar_Color, corner: f32 = -1) {
	roles := avatar_roles(avatar_color(color, name))
	px := r.w
	rad := shape == .Circular ? px / 2 : avatar_square_radius(px)
	if corner >= 0 {
		rad = corner
	}
	ops.fill(gtx.scene, ops.Round_Rect{r, rad}, role_color(roles.bg))
	stroke_inside(gtx, {r, rad}, role_color(.Transparent_Stroke), tok.STROKE_WIDTH_THIN)
	ini := initials(name, px <= 20, gtx.allocator)
	st := tok.Type_Style{weight = tok.FONT_WEIGHT_SEMIBOLD, size = avatar_text_px(px), line_height = px}
	t := shape_style(gtx, ini, st)
	draw_text(gtx, t, {r.x + (px - t.width) / 2, r.y}, role_color(roles.fg))
}

// avatar_text_px is the initials' font size for a px disc (useAvatar
// Styles.styles.ts, as avatar_metrics steps it).
@(private)
avatar_text_px :: proc(px: f32) -> f32 {
	switch {
	case px <= 24:
		return tok.FONT_SIZE_BASE100
	case px <= 28:
		return tok.FONT_SIZE_BASE200
	case px <= 40:
		return tok.FONT_SIZE_BASE300
	case px <= 56:
		return tok.FONT_SIZE_BASE400
	case px <= 96:
		return tok.FONT_SIZE_BASE500
	}
	return tok.FONT_SIZE_BASE600
}

// avatar_square_radius is a square avatar's radius for a px side
// (useAvatarStyles.styles.ts size classes): small to 4XLarge.
@(private)
avatar_square_radius :: proc(px: f32) -> f32 {
	switch {
	case px <= 24:
		return tok.BORDER_RADIUS_SMALL
	case px <= 48:
		return tok.BORDER_RADIUS_MEDIUM
	case px <= 72:
		return tok.BORDER_RADIUS_LARGE
	}
	return tok.BORDER_RADIUS_XLARGE
}

// Avatar group.

// Group_Layout is how a group's avatars sit: spread in a row, stacked
// with overlap, or cut into a pie.
Group_Layout :: enum u8 {
	Spread,
	Stack,
	Pie,
}

// group_step is a stack's overlap or a spread's gap for a px avatar
// (useAvatarGroupItemStyles.styles.ts:58-83,230-263).
@(private)
group_step :: proc(layout: Group_Layout, px: f32) -> f32 {
	if layout == .Stack {
		switch {
		case px < 24:
			return -tok.SPACING_HORIZONTAL_XXS
		case px < 48:
			return -tok.SPACING_HORIZONTAL_XS
		case px < 96:
			return -tok.SPACING_HORIZONTAL_S
		}
		return -tok.SPACING_HORIZONTAL_L
	}
	switch {
	case px < 20:
		return tok.SPACING_HORIZONTAL_S
	case px < 32:
		return tok.SPACING_HORIZONTAL_MNUDGE
	case px < 64:
		return tok.SPACING_HORIZONTAL_L
	}
	return tok.SPACING_HORIZONTAL_XL
}

// group_ring is a stack's Background 2 ring width and a pie's divider
// for a px avatar: Thick below 56, Thicker below 72, Thickest from 72
// (useAvatarGroupItemStyles.styles.ts:58-72).
@(private)
group_ring :: proc(px: f32) -> f32 {
	switch {
	case px < 56:
		return tok.STROKE_WIDTH_THICK
	case px < 72:
		return tok.STROKE_WIDTH_THICKER
	}
	return tok.STROKE_WIDTH_THICKEST
}

// overflow_border is the overflow button's border width: Thin below 36,
// Thick below 56, Thicker below 72, Thickest from 72
// (useAvatarGroupPopoverStyles.styles.ts:48-66,128-138).
@(private)
overflow_border :: proc(px: f32) -> f32 {
	switch {
	case px < 36:
		return tok.STROKE_WIDTH_THIN
	case px < 56:
		return tok.STROKE_WIDTH_THICK
	case px < 72:
		return tok.STROKE_WIDTH_THICKER
	}
	return tok.STROKE_WIDTH_THICKEST
}

// overflow_style is the count's style: caption2Strong up to 24, caption1
// Strong to 28, body1Strong to 40, subtitle2 to 56, subtitle1 to 96,
// title3 above (useAvatarGroupPopoverStyles.styles.ts:98-110,140-170).
@(private)
overflow_style :: proc(px: f32) -> tok.Type_Style {
	switch {
	case px <= 24:
		return style(.Caption2_Strong)
	case px <= 28:
		return style(.Caption1_Strong)
	case px <= 40:
		return style(.Body1_Strong)
	case px <= 56:
		return style(.Subtitle2)
	case px <= 96:
		return style(.Subtitle1)
	}
	return style(.Title3)
}

// avatar_group is several people as one unit (avatar-group.json): up to
// max avatars in the layout, then an overflow button showing the rest's
// count, which opens a popover listing their names while open^ is true
// (a click, Enter or Space toggles it; Escape or a press outside closes
// it, and the button reads the Selected tokens meanwhile). In a stack
// every item wears a Background 2 ring so each reads against the next;
// a pie holds at most three, as halves and quarters behind a divider
// of Transparent Stroke.
//
// Departures: the popover's list rows are plain (no hover); the overflow
// indicator is always the count, never an icon.
avatar_group :: proc(
	gtx: ^ui.Ctx,
	names: []string,
	size := Avatar_Size.S32,
	layout := Group_Layout.Spread,
	max_inline := 5,
	open: ^bool = nil,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> ui.Dims {
	p := ui.widget_open(gtx, key, loc)
	px := AVATAR_PX[size]
	limit := layout == .Pie ? min(max_inline, 3) : max_inline
	shown := min(len(names), limit)
	overflow := len(names) - shown
	ring := group_ring(px)
	step := group_step(layout, px)
	items := shown + (overflow > 0 && layout != .Pie ? 1 : 0)
	w := px
	if layout == .Pie {
		w = px
	} else if items > 1 {
		w = px + f32(items - 1) * (px + step)
	}
	sz := ui.constrain(gtx.constraints, {w, px})
	ui.semantics(gtx, &p, {role = .Group, label = "avatar group"})
	x: f32
	if layout == .Pie {
		paint_pie(gtx, {0, 0, px, px}, names[:shown], ring)
	} else {
		for i in 0 ..< shown {
			r := ops.Rect{x, 0, px, px}
			if layout == .Stack && i > 0 {
				ops.fill(gtx.scene, ops.Ellipse{{r.x - ring, r.y - ring, px + 2 * ring, px + 2 * ring}}, role_color(.Neutral_Background2))
			}
			paint_avatar_disc(gtx, r, names[i], .Circular, .Colorful)
			x += px + step
		}
	}
	if overflow > 0 && layout != .Pie {
		bid := ui.id_mix(p.id, 1)
		r := ops.Rect{x, 0, px, px}
		c := control(gtx, bid, r, state)
		if c.clicked && open != nil {
			open^ = !open^
		}
		if c.st != nil && open != nil {
			for e in ui.events(gtx, bid) {
				if e.kind == .Key && e.key == .Escape {
					open^ = false
				}
			}
		}
		is_open := open != nil && open^
		bg := color_for({.Neutral_Background1, .Neutral_Background1_Hover, .Neutral_Background1_Pressed, .Neutral_Background_Disabled}, c)
		fg := color_for({.Neutral_Foreground1, .Neutral_Foreground1_Hover, .Neutral_Foreground1_Pressed, .Neutral_Foreground_Disabled}, c)
		border := color_for({.Neutral_Stroke1, .Neutral_Stroke1_Hover, .Neutral_Stroke1_Pressed, .Neutral_Stroke_Disabled}, c)
		if is_open {
			bg, fg, border = color(.Neutral_Background1_Selected), color(.Neutral_Foreground1_Selected), color(.Neutral_Stroke1_Selected)
		}
		if layout == .Stack {
			ops.fill(gtx.scene, ops.Ellipse{{r.x - ring, r.y - ring, px + 2 * ring, px + 2 * ring}}, role_color(.Neutral_Background2))
		}
		ops.fill(gtx.scene, ops.Ellipse{r}, bg)
		bw := overflow_border(px)
		if c.focus_visible && !c.disabled {
			border, bw = color(.Stroke_Focus2), tok.STROKE_WIDTH_THICK
		}
		ops.stroke(gtx.scene, ops.Ellipse{{r.x + bw / 2, r.y + bw / 2, px - bw, px - bw}}, border, {width = bw})
		count := fmt.tprintf("+%d", overflow)
		t := shape_style(gtx, count, overflow_style(px))
		draw_text(gtx, t, {r.x + (px - t.width) / 2, r.y + (px - t.height) / 2}, fg)
		listen(gtx, c.st, bid, ops.Ellipse{r})
		said := ui.frame_string(gtx, count)
		ops.tag(gtx.scene, bid, said)
		ui.part_semantics(gtx, &p, bid, r, {role = .Button, label = said, states = ops.States{.Expandable} + state_if(is_open, {.Expanded}) + state_if(c.disabled, {.Disabled})})
		if is_open {
			paint_overflow_list(gtx, open, names[shown:], r, u64(bid))
		}
	}
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, "avatar group"))
	return ui.widget_close(gtx, &p, {size = sz})
}

// paint_pie cuts up to three avatars into one circle (useAvatarGroup
// ItemStyles.styles.ts:88-127): the avatars lose their radius, two are
// the left and right halves, each shifted a quarter so its middle
// shows, and three are a left half and two right quarters at half
// scale, a divider of the ring's width between them. The group circle
// clips them all, over a Transparent Stroke fill.
@(private)
paint_pie :: proc(gtx: ^ui.Ctx, r: ops.Rect, names: []string, divider: f32) {
	ops.fill(gtx.scene, ops.Ellipse{r}, role_color(.Transparent_Stroke))
	px := r.w
	if len(names) == 1 {
		paint_avatar_disc(gtx, r, names[0], .Circular, .Colorful)
		return
	}
	half := divider / 2
	ops.clip_push(gtx.scene, ops.Ellipse{r})
	ops.clip_push(gtx.scene, ops.Rect{r.x, r.y, px / 2 - half, px})
	paint_avatar_disc(gtx, {r.x - px / 4, r.y, px, px}, names[0], .Circular, .Colorful, 0)
	ops.clip_pop(gtx.scene)
	if len(names) == 2 {
		ops.clip_push(gtx.scene, ops.Rect{r.x + px / 2 + half, r.y, px / 2 - half, px})
		paint_avatar_disc(gtx, {r.x + px / 4, r.y, px, px}, names[1], .Circular, .Colorful, 0)
		ops.clip_pop(gtx.scene)
	} else {
		q := px / 2
		ops.clip_push(gtx.scene, ops.Rect{r.x + q + half, r.y, q - half, q - half})
		paint_avatar_disc(gtx, {r.x + q, r.y, q, q}, names[1], .Circular, .Colorful, 0)
		ops.clip_pop(gtx.scene)
		ops.clip_push(gtx.scene, ops.Rect{r.x + q + half, r.y + q + half, q - half, q - half})
		paint_avatar_disc(gtx, {r.x + q, r.y + q, q, q}, names[2], .Circular, .Colorful, 0)
		ops.clip_pop(gtx.scene)
	}
	ops.clip_pop(gtx.scene)
}

// paint_overflow_list is the group's popover (useAvatarGroupPopover
// Styles.styles.ts:22-43): a 220px surface, at most 220px tall, padded
// spacingVerticalS, with a row per name of a 24px avatar and the name
// in body1 Foreground 1 spacingHorizontalS after, each row padded XS;
// Escape or a press outside closes it. It opens from anchor, the
// overflow button, as a menu does (below, flipped or shifted to stay in
// the window).
@(private)
paint_overflow_list :: proc(gtx: ^ui.Ctx, open: ^bool, names: []string, anchor: ops.Rect, key: u64) {
	m := menu_open(gtx, open, anchor, key)
	defer menu_close(&m)
	col := ui.column_open(gtx)
	defer ui.close(&col)
	for n, i in names {
		overflow_row(gtx, n, u64(i))
	}
}

@(private = "file")
overflow_row :: proc(gtx: ^ui.Ctx, name: string, key: u64, loc := #caller_location) {
	p := ui.widget_open(gtx, key, loc)
	t := shape_text(gtx, name, .Body1)
	pad := tok.SPACING_VERTICAL_XS
	av: f32 = 24
	w := 220 - 2 * tok.SPACING_HORIZONTAL_S
	sz := ui.constrain(gtx.constraints, {w, av + 2 * pad})
	paint_avatar_disc(gtx, {tok.SPACING_HORIZONTAL_XS, pad, av, av}, name, .Circular, .Colorful)
	draw_text(gtx, t, {tok.SPACING_HORIZONTAL_XS + av + tok.SPACING_HORIZONTAL_S, (sz.y - t.height) / 2}, role_color(.Neutral_Foreground1))
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, name))
	ui.semantics(gtx, &p, {role = .Text, label = name})
	ui.widget_close(gtx, &p, {sz, (sz.y - t.height) / 2 + baseline_of(t)})
}

// Skeleton.

// Skeleton_Shape is an item's outline.
Skeleton_Shape :: enum u8 {
	Rectangle,
	Circle,
	Square,
}

// Skeleton_Animation is the loading motion: a wave sliding across, or
// a pulse of opacity.
Skeleton_Animation :: enum u8 {
	Wave,
	Pulse,
}

// SKELETON_SIZES are the size steps in px (Skeleton.types.ts:15-35).
SKELETON_SIZES :: [?]f32{8, 12, 14, 16, 20, 22, 24, 28, 32, 36, 40, 48, 52, 56, 64, 72, 92, 96, 120, 128}

// Skeleton_Motion is the group's shared clock: every item in a frame
// reads the same phase, so they animate in step.
@(private)
Skeleton_Motion :: struct {
	tween: ui.Tween,
	live:  bool,
}

// SKELETON_EASE is CSS ease-in-out, the wave's and pulse's curve
// (useSkeletonItemStyles.styles.ts:43-49).
SKELETON_EASE :: tok.Bezier{0.42, 0, 0.58, 1}

// skeleton_item is one loading placeholder (skeleton.json): a
// rectangle of the size's height and the full width (or width), a
// square or a circle of the size, in Stencil 1 (Stencil 1 Alpha when
// translucent), 4px corners on rectangles and squares. The wave is an
// overlay the item's own size, a gradient Stencil 1, Stencil 2 at 50%,
// Stencil 1 (transparent, Stencil 1 Alpha, transparent when
// translucent), sliding from -100% to +100% of the item's width over 3s
// on ease-in-out, forever (useSkeletonItemStyles.styles.ts:5-9,50-90);
// the pulse runs the item's opacity 1, 0.4, 1 over 1s.
skeleton_item :: proc(
	gtx: ^ui.Ctx,
	size: f32 = 16,
	shape := Skeleton_Shape.Rectangle,
	width: f32 = 0,
	animation := Skeleton_Animation.Wave,
	translucent := false,
	key: u64 = 0,
	loc := #caller_location,
) -> ui.Dims {
	p := ui.widget_open(gtx, key, loc)
	cs := gtx.constraints
	w := size
	if shape == .Rectangle {
		w = width > 0 ? width : (ui.is_finite(cs.max.x) ? cs.max.x : 200)
	}
	sz := ui.constrain(cs, {w, size})
	rad: f32 = shape == .Circle ? size / 2 : 4 // useSkeletonItemStyles.styles.ts:99-153
	rr := ops.Round_Rect{{0, 0, sz.x, sz.y}, rad}
	mo := ui.widget_data(gtx, p.id, Skeleton_Motion)
	period: f32 = animation == .Wave ? 3 : 1
	if !mo.live || mo.tween.duration != period {
		mo^ = {tween = {to = 1, duration = period, loop = true}, live = true}
	}
	t := bezier_ease(SKELETON_EASE, ui.tween_update(&mo.tween, gtx))
	base := role_color(translucent ? .Neutral_Stencil1_Alpha : .Neutral_Stencil1)
	peak := role_color(translucent ? .Neutral_Stencil1_Alpha : .Neutral_Stencil2)
	switch animation {
	case .Wave:
		ops.fill(gtx.scene, rr, base)
		edge := translucent ? ops.with_alpha(peak, 0) : base
		// The overlay's left edge runs from -w (fully left) to +w.
		x := -sz.x + t * 2 * sz.x
		stops := make([]ops.Gradient_Stop, 3, gtx.allocator)
		stops[0], stops[1], stops[2] = {0, edge}, {0.5, peak}, {1, edge}
		ops.clip_push(gtx.scene, rr)
		ops.fill(gtx.scene, ops.Rect{x, 0, sz.x, sz.y}, ops.Linear_Gradient{{x, 0}, {x + sz.x, 0}, stops})
		ops.clip_pop(gtx.scene)
	case .Pulse:
		// 1, 0.4 at the half, 1 (styles.ts:18-28).
		a := 1 - 0.6 * (1 - abs(2 * t - 1))
		ops.fill(gtx.scene, rr, ops.with_alpha(base, f32(base[3]) / 255 * a))
	}
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, "skeleton"))
	ui.semantics(gtx, &p, {role = .Progress, states = {.Busy}})
	return ui.widget_close(gtx, &p, {size = sz})
}

// Text.

// Text_Size is a run's size on the base ramp (text.json variants).
Text_Size :: enum u8 {
	S100,
	S200,
	S300,
	S400,
	S500,
	S600,
	S700,
	S800,
	S900,
	S1000,
}

// Text_Weight is a run's weight on the ramp.
Text_Weight :: enum u8 {
	Regular,
	Medium,
	Semibold,
	Bold,
}

// Text_Align is where a block run's lines sit in its box.
Text_Align :: enum u8 {
	Start,
	Center,
	End,
}

// text_style is the style for a size and weight (useTextStyles.styles.
// ts:15-26,52-98): the size's font size and line height at the weight.
text_style :: proc(size: Text_Size, weight: Text_Weight) -> tok.Type_Style {
	w: f32
	switch weight {
	case .Regular:
		w = tok.FONT_WEIGHT_REGULAR
	case .Medium:
		w = tok.FONT_WEIGHT_MEDIUM
	case .Semibold:
		w = tok.FONT_WEIGHT_SEMIBOLD
	case .Bold:
		w = tok.FONT_WEIGHT_BOLD
	}
	switch size {
	case .S100:
		return {w, tok.FONT_SIZE_BASE100, tok.LINE_HEIGHT_BASE100, 0}
	case .S200:
		return {w, tok.FONT_SIZE_BASE200, tok.LINE_HEIGHT_BASE200, 0}
	case .S300:
		return {w, tok.FONT_SIZE_BASE300, tok.LINE_HEIGHT_BASE300, 0}
	case .S400:
		return {w, tok.FONT_SIZE_BASE400, tok.LINE_HEIGHT_BASE400, 0}
	case .S500:
		return {w, tok.FONT_SIZE_BASE500, tok.LINE_HEIGHT_BASE500, 0}
	case .S600:
		return {w, tok.FONT_SIZE_BASE600, tok.LINE_HEIGHT_BASE600, 0}
	case .S700:
		return {w, tok.FONT_SIZE_HERO700, tok.LINE_HEIGHT_HERO700, 0}
	case .S800:
		return {w, tok.FONT_SIZE_HERO800, tok.LINE_HEIGHT_HERO800, 0}
	case .S900:
		return {w, tok.FONT_SIZE_HERO900, tok.LINE_HEIGHT_HERO900, 0}
	case .S1000:
	}
	return {w, tok.FONT_SIZE_HERO1000, tok.LINE_HEIGHT_HERO1000, 0}
}

// ITALIC_SHEAR is the slant a run gets for italic: jm:ui has no oblique
// faces, so the glyphs are sheared about their baseline.
ITALIC_SHEAR :: f32(0.2)

// text is one run of text (text.json) at a size and weight in color:
// Text sets no colour of its own, so the caller passes the surface's
// foreground. Inline, it is its content's width on one line; block
// lays it out to width (the constraints' when 0), wrapping when wrap
// is true, else cut to one line where it meets the box, with an
// ellipsis when truncate is set and clipped otherwise
// (useTextStyles.styles.ts:27-36,121-123). A block with no width,
// Start-aligned and left to right, is as wide as its widest line up to
// that, as a CSS block is in a flex row: it hugs its content in a row
// and still fills a Fill column, whose constraints set its minimum.
// Other alignments and right-to-left text take the whole box, which
// they place their lines in. italic shears the glyphs,
// underline and strikethrough draw their lines; align places block
// lines. Returns its dims; the run is tagged with s. The text is
// selectable (ui.selectable_text) unless selectable is false; a selection
// through an ellipsis takes the text it hides.
text :: proc(
	gtx: ^ui.Ctx,
	s: string,
	color: ops.Color,
	size := Text_Size.S300,
	weight := Text_Weight.Regular,
	block := false,
	width: f32 = 0,
	wrap_lines := true,
	truncate := false,
	align := Text_Align.Start,
	italic := false,
	underline := false,
	strikethrough := false,
	key: u64 = 0,
	selectable := true,
	loc := #caller_location,
) -> ui.Dims {
	return text_styled(gtx, s, text_style(size, weight), color, block, width, wrap_lines, truncate, align, italic, underline, strikethrough, key, loc, selectable)
}

// is_heading is whether a preset reads as a heading: the titles and
// the display style, not the body and caption ramp.
@(private)
is_heading :: proc(role: Type_Role) -> bool {
	#partial switch role {
	case .Title3, .Title2, .Title1, .Large_Title, .Display:
		return true
	}
	return false
}

// text_preset is text at one of the ramp's named styles (text.json
// preset typography-style): Caption1, Body1Strong, Title2 and the rest.
text_preset :: proc(
	gtx: ^ui.Ctx,
	s: string,
	role: Type_Role,
	color: ops.Color,
	block := false,
	width: f32 = 0,
	wrap_lines := true,
	truncate := false,
	align := Text_Align.Start,
	italic := false,
	underline := false,
	strikethrough := false,
	key: u64 = 0,
	selectable := true,
	loc := #caller_location,
) -> ui.Dims {
	return text_styled(gtx, s, style(role), color, block, width, wrap_lines, truncate, align, italic, underline, strikethrough, key, loc, selectable, is_heading(role))
}

@(private)
text_styled :: proc(gtx: ^ui.Ctx, s: string, st: tok.Type_Style, color: ops.Color, block: bool, width: f32, wrap_lines, truncate: bool, align: Text_Align, italic, underline, strikethrough: bool, key: u64, loc: runtime.Source_Code_Location, selectable := true, heading := false) -> ui.Dims {
	p := ui.widget_open(gtx, key, loc)
	cs := gtx.constraints
	box_w := width
	if block && box_w == 0 {
		box_w = ui.is_finite(cs.max.x) ? cs.max.x : 0
	}
	para: ui.Paragraph
	if wrap_lines {
		para = layout_style(gtx, s, st, box_w if block && box_w > 0 else 0)
	} else {
		// One line, cut where it meets its box: with an ellipsis, or run
		// on for the clip below.
		limit := box_w if box_w > 0 else (cs.max.x if ui.is_finite(cs.max.x) else 0)
		para = layout_style(gtx, s, st, limit, max_lines = 1, ellipsis = ui.ELLIPSIS if truncate else "")
	}
	hug := width == 0 && align == .Start && !para.rtl
	sz := ui.constrain(cs, {box_w > 0 && !hug ? box_w : para.width, para.height})
	if italic {
		// Shear about the run's bottom: the top leans right by the shear.
		ops.transform_push(gtx.scene, ops.Affine{1, 0, f64(-ITALIC_SHEAR), 1, f64(ITALIC_SHEAR * sz.y), 0})
	}
	for &ln in para.lines {
		ln.x = align_x(align, sz.x, min(ln.width, sz.x)) if !para.rtl || align != .Start else ln.x
	}
	clipped := para.width > sz.x + 0.5
	if clipped {
		ops.clip_push(gtx.scene, ops.Rect{0, 0, sz.x, sz.y})
	}
	sel: design.Selection_Paint
	if selectable {
		lo, hi, focused := ui.selectable_text(gtx, p.id, para, {}, {0, 0, sz.x, sz.y})
		sel = selection_colors(lo, hi, focused)
	}
	draw_paragraph(gtx, para, {}, color, sel)
	for ln in para.lines {
		decorate(gtx, {ln.x, ln.baseline - para.lines[0].baseline}, min(ln.width, sz.x), para.lines[0].baseline, para.metrics.ascent, color, underline, strikethrough)
	}
	if clipped {
		ops.clip_pop(gtx.scene)
	}
	if italic {
		ops.transform_pop(gtx.scene)
	}
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, s), {0, 0, sz.x, sz.y})
	ui.semantics(gtx, &p, {role = heading ? .Heading : .Text, label = s})
	return ui.widget_close(gtx, &p, {sz, para.lines[0].baseline})
}

// align_x is where a line w wide starts in a box box_w wide.
@(private = "file")
align_x :: proc(align: Text_Align, box_w, w: f32) -> f32 {
	switch align {
	case .Start:
	case .Center:
		return (box_w - w) / 2
	case .End:
		return box_w - w
	}
	return 0
}

// decorate draws a line's underline and strikethrough, the line box's
// top-left at pos, w wide, its baseline that far down.
@(private = "file")
decorate :: proc(gtx: ^ui.Ctx, pos: ops.Point, w, baseline, ascent: f32, color: ops.Color, underline, strikethrough: bool) {
	if underline {
		ops.fill(gtx.scene, ops.Rect{pos.x, pos.y + baseline + 1, w, 1}, color)
	}
	if strikethrough {
		ops.fill(gtx.scene, ops.Rect{pos.x, pos.y + baseline - ascent * 0.3, w, 1}, color)
	}
}

// Image.

// Image_Shape is the box's corners.
Image_Shape :: enum u8 {
	Square,
	Rounded,
	Circular,
}

// Image_Fit is how a source of natural size fills the box (image.json
// variants).
Image_Fit :: enum u8 {
	Default, // the box is the source's size
	None, // natural size from the top-left
	Center, // natural size around the centre
	Contain, // scaled to fit inside, centred
	Cover, // scaled to cover, centred, clipped
}

// Image_Paint draws the picture into rect, the source's placed and
// scaled box, clipped to the image's shape.
Image_Paint :: proc(gtx: ^ui.Ctx, rect: ops.Rect, user: rawptr)

// image is a picture's box (image.json): width by height (or the
// source's natural size at fit default), shape square, rounded
// (borderRadiusMedium) or circular, a Stroke 1 strokeWidthThin border
// when bordered, shadow4 when shadow (useImageStyles.styles.ts:14-38).
// jm:ui draws no bitmaps: paint, if given, draws the source into the
// rect the fit rule places, clipped to the shape; without it the box
// is a Neutral_Background3 placeholder with the Image icon, the honest
// stand-in the spec names.
image :: proc(
	gtx: ^ui.Ctx,
	natural: ops.Size,
	width: f32 = 0,
	height: f32 = 0,
	shape := Image_Shape.Square,
	fit := Image_Fit.Default,
	bordered := false,
	shadow := false,
	paint: Image_Paint = nil,
	user: rawptr = nil,
	key: u64 = 0,
	loc := #caller_location,
) -> ui.Dims {
	p := ui.widget_open(gtx, key, loc)
	cs := gtx.constraints
	box := ops.Size{width, height}
	if fit == .Default {
		if box.x == 0 && box.y == 0 {
			box = natural
		} else if box.x == 0 {
			box.x = natural.y > 0 ? natural.x * box.y / natural.y : box.y
		} else if box.y == 0 {
			box.y = natural.x > 0 ? natural.y * box.x / natural.x : box.x
		}
	} else {
		// Any other fit with no size fills the container (styles.ts:61-66).
		if box.x == 0 {
			box.x = ui.is_finite(cs.max.x) ? cs.max.x : natural.x
		}
		if box.y == 0 {
			box.y = ui.is_finite(cs.max.y) ? cs.max.y : natural.y
		}
	}
	sz := ui.constrain(cs, box)
	area := ops.Rect{0, 0, sz.x, sz.y}
	rad: f32
	switch shape {
	case .Square:
	case .Rounded:
		rad = tok.BORDER_RADIUS_MEDIUM
	case .Circular:
		rad = radius(tok.BORDER_RADIUS_CIRCULAR, area)
	}
	rr := ops.Round_Rect{area, rad}
	if shadow {
		paint_shadow(gtx, rr, tok.SHADOW4)
	}
	src := area
	switch fit {
	case .Default:
	case .None:
		src = {0, 0, natural.x, natural.y}
	case .Center:
		src = {(sz.x - natural.x) / 2, (sz.y - natural.y) / 2, natural.x, natural.y}
	case .Contain, .Cover:
		if natural.x > 0 && natural.y > 0 {
			k := fit == .Contain ? min(sz.x / natural.x, sz.y / natural.y) : max(sz.x / natural.x, sz.y / natural.y)
			w, h := natural.x * k, natural.y * k
			src = {(sz.x - w) / 2, (sz.y - h) / 2, w, h}
		}
	}
	ops.clip_push(gtx.scene, rr)
	if paint != nil {
		paint(gtx, src, user)
	} else {
		ops.fill(gtx.scene, rr, role_color(.Neutral_Background3))
		ic := min(sz.x, sz.y) / 2
		icon(gtx, .Image, {(sz.x - ic) / 2, (sz.y - ic) / 2}, ic, role_color(.Neutral_Foreground3))
	}
	ops.clip_pop(gtx.scene)
	if bordered {
		stroke_inside(gtx, rr, role_color(.Neutral_Stroke1), tok.STROKE_WIDTH_THIN)
	}
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, "image"))
	ui.semantics(gtx, &p, {role = .Image})
	return ui.widget_close(gtx, &p, {size = sz})
}
