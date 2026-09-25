package ui

import "core:strings"
import "core:testing"

@(private = "file")
Probe_Model :: struct {
	saved:   int,
	focused: bool,
	typed:   strings.Builder,
	keys:    [dynamic]Key,
}

@(private = "file")
SAVE :: Area_Id(1)
@(private = "file")
FIELD :: Area_Id(2)

// probe_model_ui is a hand-recorded ui: a Save button under a translate
// and a text field below it.
@(private = "file")
probe_model_ui :: proc(gtx: ^Ctx, user: rawptr) {
	m := (^Probe_Model)(user)
	push_transform(gtx.ops, translate(40, 30))
	input_area(gtx.ops, SAVE, Rect{0, 0, 80, 20}, {.Press, .Release})
	tag(gtx.ops, SAVE, "Save")
	pop_transform(gtx.ops)
	input_area(gtx.ops, FIELD, Rect{0, 100, 200, 20}, {.Press, .Key, .Text, .Focus, .Blur})
	tag(gtx.ops, FIELD, "Name")

	for e in events(gtx, SAVE) {
		if e.kind == .Release {
			m.saved += 1
		}
	}
	for e in events(gtx, FIELD) {
		#partial switch e.kind {
		case .Focus:
			m.focused = true
		case .Blur:
			m.focused = false
		case .Text:
			strings.write_string(&m.typed, e.text)
		case .Key:
			append(&m.keys, e.key)
		}
	}
}

@(test)
probe_click_by_name :: proc(t: ^testing.T) {
	m: Probe_Model
	p: Probe
	probe_init(&p, probe_model_ui, &m, {400, 300})
	defer probe_destroy(&p)

	names := probe_names(&p)
	testing.expect_value(t, len(names), 2)
	testing.expect_value(t, names[0], "Save")
	testing.expect_value(t, names[1], "Name")

	c, ok := probe_center(&p, "Save")
	testing.expect(t, ok)
	testing.expect_value(t, c, Point{80, 40})

	testing.expect(t, probe_click(&p, "Save"))
	testing.expect_value(t, m.saved, 1)
	testing.expect(t, !probe_click(&p, "Missing"))
	testing.expect_value(t, m.saved, 1)
}

@(test)
probe_type_into_focused :: proc(t: ^testing.T) {
	m: Probe_Model
	strings.builder_init(&m.typed)
	defer strings.builder_destroy(&m.typed)
	defer delete(m.keys)
	p: Probe
	probe_init(&p, probe_model_ui, &m, {400, 300})
	defer probe_destroy(&p)

	probe_type(&p, "lost")
	testing.expect_value(t, strings.to_string(m.typed), "")

	testing.expect(t, probe_click(&p, "Name"))
	testing.expect(t, m.focused)
	probe_type(&p, "Ada")
	probe_type(&p, " L")
	probe_key(&p, .Enter)
	testing.expect_value(t, strings.to_string(m.typed), "Ada L")
	testing.expect_value(t, len(m.keys), 1)

	probe_move(&p, 390, 290)
	testing.expect(t, probe_click(&p, "Save"))
	testing.expect(t, m.focused, "a non-key button keeps focus")
	testing.expect_value(t, m.saved, 1)
}
