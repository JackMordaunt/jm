/*
cells is 7GUIs task 7: a spreadsheet of columns A to Z and rows 0 to 99,
scrolling both ways, where a double click edits a cell in place and a
formula's value follows the cells it refers to
(https://eugenkiss.github.io/7guis/tasks#cells). The formula language and
its evaluation are formula.odin, plain procedures tested with no ui; this
is the sheet. Every cell is a widget, laid out each frame in a grid inside
a scroll box.
*/
package main

import "core:fmt"

import "jm:ui"
import "jm:ui/design"
import "jm:ui/fluent"
import "jm:ui/ops"

import "../shell"

CELL :: ops.Size{80, 26}
HEADER_WIDTH :: 40

Model :: struct {
	sheet:   ^Sheet,
	editing: Maybe(Cell),
	edit:    ui.Text_State, // the editing cell's source as it is typed
	focused: bool, // the editor has had focus, so losing it ends the edit
	scroll:  ui.Scroll_Offset,
}

model_init :: proc(m: ^Model) {
	m.sheet = new(Sheet)
}

model_destroy :: proc(m: ^Model) {
	sheet_destroy(m.sheet)
	free(m.sheet)
	ui.text_destroy(&m.edit)
}

view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Model)(user)
	page := shell.page_open(gtx)
	defer ui.close(&page)
	ui.scroll_box(gtx, offset = &m.scroll, wide = true)

	tracks: [COLS + 1]ui.Track
	tracks[0] = {width = HEADER_WIDTH, align = .Center}
	for &t in tracks[1:] {
		t = {width = CELL.x}
	}
	ui.grid(gtx, tracks[:])

	header(gtx, "", HEADER_WIDTH)
	for c in 0 ..< COLS {
		header(gtx, fmt.tprintf("%c", 'A' + c), CELL.x)
	}
	for r in 0 ..< ROWS {
		header(gtx, fmt.tprint(r), HEADER_WIDTH)
		for c in 0 ..< COLS {
			if at, ok := m.editing.?; ok && at == (Cell{c, r}) {
				editor(gtx, m, at)
			} else {
				cell(gtx, m, {c, r})
			}
		}
	}
}

header :: proc(gtx: ^ui.Ctx, label: string, width: f32) {
	p := ui.widget_open(gtx)
	box := ops.Rect{0, 0, width, CELL.y}
	ops.fill(gtx.scene, box, fluent.color(.Neutral_Background3))
	draw_edges(gtx, box)
	t := fluent.shape_text(gtx, label, .Caption1)
	design.draw_text(gtx, t, {(width - t.width) / 2, (CELL.y - t.height) / 2}, fluent.color(.Neutral_Foreground2))
	ui.widget_close(gtx, &p, {size = {width, CELL.y}})
}

// cell shows a cell's value; a double click on it starts editing its
// source, and a single click ends any edit.
cell :: proc(gtx: ^ui.Ctx, m: ^Model, c: Cell) {
	p := ui.widget_open(gtx, key = u64(c.row * COLS + c.col + 1))
	box := ops.Rect{0, 0, CELL.x, CELL.y}
	// A press on a cell keeps focus where it is (it takes no keys), so
	// the cell itself ends an edit in progress elsewhere.
	for e in ui.events(gtx, p.id) {
		if e.kind == .Press {
			if e.clicks == 2 {
				start_edit(m, c)
			} else {
				commit(m)
			}
		}
	}
	draw_edges(gtx, box)
	if s := shown(m.sheet, c); s != "" {
		t := fluent.shape_text(gtx, s, .Body1)
		v := m.sheet.value[c.row][c.col]
		x := v.kind == .Number ? CELL.x - 6 - t.width : 6 // numbers align right, as in any spreadsheet
		ops.clip_push(gtx.scene, box)
		design.draw_text(gtx, t, {x, (CELL.y - t.height) / 2}, fluent.color(v.kind == .Error ? .Palette_Red_Foreground1 : .Neutral_Foreground1))
		ops.clip_pop(gtx.scene)
	}
	ops.input_area(gtx.scene, p.id, box, {.Press})
	ops.tag(gtx.scene, p.id, cell_name(c))
	ui.widget_close(gtx, &p, {size = CELL})
}

// shown is the text a cell shows: its value, or its source when that is
// text.
shown :: proc(s: ^Sheet, c: Cell) -> string {
	v := s.value[c.row][c.col]
	switch v.kind {
	case .Empty:
		return ""
	case .Number:
		return fmt.tprintf("%.10g", v.num)
	case .Text:
		return s.source[c.row][c.col]
	case .Error:
		return "#ERROR"
	}
	return ""
}

// editor is the input that replaces a cell while it is edited: Enter or
// a click elsewhere keeps the source, Escape drops it. It asks for focus
// until it has it, and from then on losing focus ends the edit.
editor :: proc(gtx: ^ui.Ctx, m: ^Model, c: Cell) {
	r := fluent.input(gtx, &m.edit, size = .Small, width = CELL.x, name = "Editor", key = u64(c.row * COLS + c.col + 1))
	for e in ui.events(gtx, r.id) {
		if e.kind == .Key && e.key == .Escape {
			m.editing = nil
			return
		}
	}
	if !m.focused {
		ui.focus_request(gtx, r.id)
		ui.request_frame(gtx)
		m.focused = r.focused
		return
	}
	if r.submitted || !r.focused {
		commit(m)
	}
}

// start_edit edits c, first keeping the edit in progress, if any.
start_edit :: proc(m: ^Model, c: Cell) {
	commit(m)
	m.editing = c
	m.focused = false
	ui.text_set(&m.edit, m.sheet.source[c.row][c.col])
}

commit :: proc(m: ^Model) {
	if at, ok := m.editing.?; ok {
		sheet_set(m.sheet, at, ui.text_string(&m.edit))
		m.editing = nil
	}
}

// draw_edges draws a cell's right and bottom edges, so neighbours share one.
draw_edges :: proc(gtx: ^ui.Ctx, box: ops.Rect) {
	stroke := fluent.color(.Neutral_Stroke2)
	ops.fill(gtx.scene, ops.Rect{box.w - 1, 0, 1, box.h}, stroke)
	ops.fill(gtx.scene, ops.Rect{0, box.h - 1, box.w, 1}, stroke)
}

main :: proc() {
	m: Model
	model_init(&m)
	defer model_destroy(&m)
	shell.run("Cells", 720, 480, view, &m)
}
