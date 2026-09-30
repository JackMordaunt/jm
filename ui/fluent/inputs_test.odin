package fluent

import "core:strings"
import "core:testing"
import "jm:ui"
import "jm:ui/ops"

// Behaviour of the inputs group, driven through ui.Probe by their tags.

@(private = "file")
Inputs_Model :: struct {
	name, notes:     ui.Text_State,
	edits, submits:  int,
	name_focused:    bool,
	links, disabled: int,
	invalid:         bool,
}

@(private = "file")
inputs :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Inputs_Model)(user)
	col := ui.column_open(gtx, gap = 16)
	defer ui.close(&col)
	if fluent_field(gtx, "Name", true, "Your full name", m.invalid ? "Name is required" : "", .Error) {
		r := input(gtx, &m.name, "First and last", invalid = m.invalid, width = 200)
		m.edits += r.changed ? 1 : 0
		m.submits += r.submitted ? 1 : 0
		m.name_focused = r.focused
	}
	input(gtx, &m.name, "Off", width = 200, state = .Disabled)
	textarea(gtx, &m.notes, "Notes", width = 220)
	if link(gtx, "Learn more") {
		m.links += 1
	}
	if link(gtx, "Gone", state = .Disabled) {
		m.disabled += 1
	}
	label(gtx, "Plain label", required = true)
}

// fluent_field is the field guard, spelled apart from the test model's
// own names.
@(private = "file")
fluent_field :: proc(gtx: ^ui.Ctx, text: string, required: bool, hint, message: string, validation: Validation) -> bool {
	return field(gtx, text, required, hint, message, validation)
}

@(test)
test_input_edits_its_text_and_reports_focus_and_submit :: proc(t: ^testing.T) {
	m: Inputs_Model
	p: ui.Probe
	ui.probe_init(&p, inputs, &m, {600, 500}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	defer ui.text_destroy(&m.name)
	defer ui.text_destroy(&m.notes)

	testing.expect(t, ui.probe_click(&p, "First and last"))
	testing.expect(t, m.name_focused)
	ui.probe_type(&p, "Ada")
	testing.expect_value(t, ui.text_string(&m.name), "Ada")
	testing.expect_value(t, m.edits, 1)
	ui.probe_key(&p, .Backspace)
	testing.expect_value(t, ui.text_string(&m.name), "Ad")
	ui.probe_key(&p, .Enter)
	testing.expect_value(t, m.submits, 1)
	// The disabled twin shares the buffer but registers no area.
	testing.expect(t, !ui.probe_click(&p, "Off"))
	// The field's label and hint are widgets a probe finds by text; the
	// message appears once there is one.
	testing.expect(t, ui.probe_tagged(&p, "Name"))
	testing.expect(t, ui.probe_tagged(&p, "Your full name"))
	testing.expect(t, !ui.probe_tagged(&p, "Name is required"))
	m.invalid = true
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "Name is required"))
}

@(test)
test_textarea_takes_lines_and_grows :: proc(t: ^testing.T) {
	m: Inputs_Model
	p: ui.Probe
	ui.probe_init(&p, inputs, &m, {600, 500}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	defer ui.text_destroy(&m.name)
	defer ui.text_destroy(&m.notes)

	rest := ui.probe_bounds(&p, "Notes")
	testing.expect_value(t, rest.h, 52 + 2) // the medium minimum and the borders; the focus line's padding lies outside the box
	testing.expect(t, ui.probe_click(&p, "Notes"))
	ui.probe_type(&p, "one")
	ui.probe_key(&p, .Enter)
	ui.probe_type(&p, "two")
	testing.expect_value(t, ui.text_string(&m.notes), "one\ntwo")
	for _ in 0 ..< 3 {
		ui.probe_key(&p, .Enter)
	}
	testing.expect_value(t, ui.text_string(&m.notes), "one\ntwo\n\n\n")
	// Five lines of 20px plus 12px of padding outgrow the 52px minimum.
	grown := ui.probe_bounds(&p, "Notes")
	testing.expect_value(t, grown.h, 5 * 20 + 12 + 2)
	// Up moves the caret to the line above; Home to its start.
	ui.probe_key(&p, .Up)
	ui.probe_key(&p, .Up)
	ui.probe_key(&p, .Up)
	ui.probe_key(&p, .End)
	testing.expect_value(t, m.notes.cursor, len("one\ntwo"))
	ui.probe_key(&p, .Home)
	testing.expect_value(t, m.notes.cursor, len("one\n"))
	// A long paragraph wraps within the 220px box rather than widening it.
	ui.text_set(&m.notes, strings.repeat("word ", 20, context.temp_allocator))
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_bounds(&p, "Notes").w, 220)
	testing.expect(t, ui.probe_bounds(&p, "Notes").h > 52 + 4)
}

@(test)
test_link_activates_unless_disabled :: proc(t: ^testing.T) {
	m: Inputs_Model
	p: ui.Probe
	ui.probe_init(&p, inputs, &m, {600, 500}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	defer ui.text_destroy(&m.name)
	defer ui.text_destroy(&m.notes)

	testing.expect(t, ui.probe_click(&p, "Learn more"))
	testing.expect_value(t, m.links, 1)
	ui.probe_key(&p, .Enter)
	testing.expect_value(t, m.links, 2)
	testing.expect(t, !ui.probe_click(&p, "Gone"))
	testing.expect_value(t, m.disabled, 0)
	// A link is its text box tall, at the medium line height.
	testing.expect_value(t, ui.probe_bounds(&p, "Learn more").h, 20)
}

@(test)
test_textarea_wraps_at_spaces_and_newlines :: proc(t: ^testing.T) {
	sc: ui.Probe // only for its shaper
	m: Inputs_Model
	ui.probe_init(&sc, inputs, &m, {600, 500}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&sc)
	defer free_all(context.temp_allocator)
	defer ui.text_destroy(&m.name)
	defer ui.text_destroy(&m.notes)
	ctx := ui.Ctx{scene = &sc.scene, font = sc.font, shaper = sc.shaper, allocator = context.temp_allocator}
	gtx := &ctx
	st := style(.Body1)
	one := shape_style(gtx, "word", st).width
	p := layout_style(gtx, "word word word\nnext", st, one * 2.5)
	testing.expect_value(t, len(p.lines), 3)
	testing.expect_value(t, [2]int{p.lines[0].start, p.lines[0].end}, [2]int{0, 10}) // "word word ", its space hanging
	testing.expect_value(t, [2]int{p.lines[1].start, p.lines[1].end}, [2]int{10, 15}) // "word" and the newline
	testing.expect_value(t, [2]int{p.lines[2].start, p.lines[2].end}, [2]int{15, 19}) // "next"
	testing.expect_value(t, p.pitch, st.line_height)
	// A word wider than the box breaks between graphemes.
	long := layout_style(gtx, "abcdefgh", st, one)
	testing.expect(t, len(long.lines) >= 2)
	// The empty string is one empty line, so the caret has a home.
	testing.expect_value(t, len(layout_style(gtx, "", st, one).lines), 1)
}

@(test)
test_inputs_show_the_i_beam_and_links_the_hand :: proc(t: ^testing.T) {
	m: Inputs_Model
	p: ui.Probe
	ui.probe_init(&p, inputs, &m, {600, 500}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	defer ui.text_destroy(&m.name)
	defer ui.text_destroy(&m.notes)
	cursor_over :: proc(p: ^ui.Probe, name: string) -> ops.Cursor {
		c, _ := ui.probe_center(p, name)
		ui.probe_move(p, c.x, c.y)
		return ui.probe_cursor(p)
	}
	testing.expect_value(t, cursor_over(&p, "First and last"), ops.Cursor.Text)
	testing.expect_value(t, cursor_over(&p, "Notes"), ops.Cursor.Text)
	testing.expect_value(t, cursor_over(&p, "Learn more"), ops.Cursor.Pointer)
	ui.probe_move(&p, 590, 490) // nothing there
	testing.expect_value(t, ui.probe_cursor(&p), ops.Cursor.Default)
}

@(test)
test_copy_from_an_input_and_paste_into_a_textarea :: proc(t: ^testing.T) {
	m: Inputs_Model
	p: ui.Probe
	ui.probe_init(&p, inputs, &m, {600, 500}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	defer ui.text_destroy(&m.name)
	defer ui.text_destroy(&m.notes)
	testing.expect(t, ui.probe_click(&p, "First and last"))
	ui.probe_type(&p, "Ada Lovelace")
	// Shift+Left twice selects "ce"; typing replaces it.
	ui.probe_key(&p, .Left, {.Shift})
	ui.probe_key(&p, .Left, {.Shift})
	ui.probe_type(&p, "k")
	testing.expect_value(t, ui.text_string(&m.name), "Ada Lovelak")
	ui.probe_key(&p, .A, {ui.SHORTCUT})
	ui.probe_key(&p, .C, {ui.SHORTCUT})
	testing.expect_value(t, ui.probe_clipboard(&p), "Ada Lovelak")

	testing.expect(t, ui.probe_click(&p, "Notes"))
	ui.probe_key(&p, .V, {ui.SHORTCUT})
	ui.probe_frame(&p) // the Paste lands the frame after the read
	testing.expect_value(t, ui.text_string(&m.notes), "Ada Lovelak")
}

@(test)
test_a_selection_is_highlighted_and_its_text_recoloured :: proc(t: ^testing.T) {
	m: Inputs_Model
	p: ui.Probe
	ui.probe_init(&p, inputs, &m, {600, 500}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	defer ui.text_destroy(&m.name)
	defer ui.text_destroy(&m.notes)
	count :: proc(p: ^ui.Probe) -> (fills, clips, recoloured: int) {
		sel := selection_paint(&ui.Text_State{anchor = 0, cursor = 1}, true)
		for op in p.scene.ops {
			#partial switch v in op {
			case ops.Fill:
				if c, ok := v.paint.(ops.Color); ok && c == sel.bg {
					fills += 1
				}
			case ops.Push_Clip:
				clips += 1
			case ops.Glyphs:
				if v.color == sel.fg {
					recoloured += 1
				}
			}
		}
		return
	}
	ui.probe_click(&p, "First and last")
	ui.probe_type(&p, "Ada")
	f0, c0, r0 := count(&p)
	ui.probe_key(&p, .A, {ui.SHORTCUT})
	f1, c1, r1 := count(&p)
	testing.expect_value(t, r0, 0)
	// Both inputs showing m.name redraw their selected text: the palette
	// here, base's light one, gives the inactive selection the same text
	// colour as the focused one.
	testing.expect_value(t, r1, 2)
	testing.expect_value(t, f0, 0)
	testing.expect_value(t, f1 - f0, 1) // one line, one highlight in the focused colour
	// The selected text drawn again inside it — twice, since the disabled
	// "Off" input shares m.name and shows the same selection, inactive.
	testing.expect_value(t, c1 - c0, 2)
}

@(test)
test_drag_and_triple_click_select_in_an_input :: proc(t: ^testing.T) {
	m: Inputs_Model
	p: ui.Probe
	ui.probe_init(&p, inputs, &m, {600, 500}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	defer ui.text_destroy(&m.name)
	defer ui.text_destroy(&m.notes)
	testing.expect(t, ui.probe_click(&p, "First and last"))
	ui.probe_type(&p, "grace hopper")
	b := ui.probe_bounds(&p, "First and last")
	y := b.y + b.h / 2
	// Press just inside the left padding, drag past the end, release.
	ui.router_push(&p.router, {kind = .Press, pos = {b.x + 2, y}, clicks = 1})
	ui.router_push(&p.router, {kind = .Move, pos = {b.x + b.w - 2, y}})
	ui.router_push(&p.router, {kind = .Release, pos = {b.x + b.w - 2, y}})
	ui.probe_frame(&p)
	testing.expect_value(t, ui.text_selected(&m.name), "grace hopper")

	ui.probe_key(&p, .End)
	testing.expect_value(t, ui.text_selected(&m.name), "")
	ui.router_push(&p.router, {kind = .Press, pos = {b.x + b.w / 2, y}, clicks = 3})
	ui.router_push(&p.router, {kind = .Release, pos = {b.x + b.w / 2, y}, clicks = 3})
	ui.probe_frame(&p)
	testing.expect_value(t, ui.text_selected(&m.name), "grace hopper")
}
