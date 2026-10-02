package ui

import "base:runtime"
import "core:mem"
import "core:strings"
import "jm:ui/ops"
import "core:testing"

@(private = "file")
Probe_Model :: struct {
	saved:   int,
	focused: bool,
	typed:   strings.Builder,
	keys:    [dynamic]Key,
}

@(private = "file")
SAVE :: ops.Area_Id(1)
@(private = "file")
FIELD :: ops.Area_Id(2)

// probe_model_ui is a hand-recorded ui: a Save button under a translate
// and a text field below it.
@(private = "file")
probe_model_ui :: proc(gtx: ^Ctx, user: rawptr) {
	m := (^Probe_Model)(user)
	ops.transform_push(gtx.scene, ops.translate(40, 30))
	ops.input_area(gtx.scene, SAVE, ops.Rect{0, 0, 80, 20}, {.Press, .Release})
	ops.tag(gtx.scene, SAVE, "Save")
	ops.transform_pop(gtx.scene)
	ops.input_area(gtx.scene, FIELD, ops.Rect{0, 100, 200, 20}, {.Press, .Key, .Text, .Focus, .Blur})
	ops.tag(gtx.scene, FIELD, "Name")

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
	testing.expect_value(t, c, ops.Point{80, 40})

	testing.expect(t, probe_click(&p, "Save"))
	testing.expect_value(t, m.saved, 1)
	testing.expect(t, !probe_click(&p, "Missing"))
	testing.expect_value(t, m.saved, 1)
}

// A click can change what widgets drawn before it read, so the frame that
// handles it asks for another; a frame without input asks for nothing.
@(test)
probe_input_asks_for_a_frame :: proc(t: ^testing.T) {
	m: Probe_Model
	p: Probe
	probe_init(&p, probe_model_ui, &m, {400, 300})
	defer probe_destroy(&p)
	testing.expect(t, !p.wants_frame)
	testing.expect(t, probe_click(&p, "Save"))
	testing.expect_value(t, m.saved, 1)
	testing.expect(t, p.wants_frame)
	probe_frame(&p)
	testing.expect(t, !p.wants_frame)
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

@(private = "file")
steady_view :: proc(gtx: ^Ctx, user: rawptr) {
	if column(gtx, gap = 4) {
		label(gtx, "title")
		if row(gtx, gap = 8, align = .Baseline) {
			label(gtx, "left")
			flexible(gtx, 1)
			label(gtx, "grow")
		}
		if clip_box(gtx) {
			label(gtx, "clipped")
		}
		o := popup_open(gtx, {0, 0, 20, 20}, 99)
		label(gtx, "popup")
		popup_close(&o, {20, 20})
	}
}

@(test)
test_a_steady_frame_allocates_nothing :: proc(t: ^testing.T) {
	// Every allocator the frame could reach goes through a spy: the probe's
	// own (its scene, frames, router and layout), the default and temp.
	spy := Alloc_Spy{inner = context.allocator}
	spy_t := Alloc_Spy{inner = context.temp_allocator}
	inner, inner_t := context.allocator, context.temp_allocator
	context.allocator = mem.Allocator{spy_proc, &spy}
	context.temp_allocator = mem.Allocator{spy_proc, &spy_t}
	defer context.allocator, context.temp_allocator = inner, inner_t
	p: Probe
	probe_init(&p, steady_view, nil, {200, 200})
	defer probe_destroy(&p)
	probe_frame(&p) // a second frame settles the weighted child and the popup
	spy.n, spy_t.n = 0, 0
	probe_frame(&p)
	probe_frame(&p)
	for i in 0 ..< min(spy.n, len(spy.at)) {
		testing.expectf(t, false, "heap allocator called at %v", spy.at[i])
	}
	for i in 0 ..< min(spy_t.n, len(spy_t.at)) {
		testing.expectf(t, false, "temp allocator called at %v", spy_t.at[i])
	}
	testing.expect(t, probe_tagged(&p, "popup")) // the frames did lay the view out
}

// Alloc_Spy records where allocations came from, in a fixed buffer, and
// passes them on to inner: a failing test names every site.
@(private = "file")
Alloc_Spy :: struct {
	inner: mem.Allocator,
	at:    [16]runtime.Source_Code_Location,
	n:     int,
}

@(private = "file")
spy_proc :: proc(data: rawptr, mode: mem.Allocator_Mode, size, alignment: int, old: rawptr, old_size: int, loc := #caller_location) -> ([]byte, mem.Allocator_Error) {
	s := (^Alloc_Spy)(data)
	if mode != .Query_Features && mode != .Query_Info {
		if s.n < len(s.at) {
			s.at[s.n] = loc
		}
		s.n += 1
	}
	return s.inner.procedure(s.inner.data, mode, size, alignment, old, old_size, loc)
}

// tagged_view is a column of a label, which has no input area, over a
// button, which has one.
@(private = "file")
tagged_view :: proc(gtx: ^Ctx, user: rawptr) {
	col := column_open(gtx, key = 1)
	defer close(&col)
	label(gtx, "Status: ready", key = 2)
	p := widget_open(gtx, 3)
	ops.input_area(gtx.scene, p.id, ops.Rect{0, 0, 60, 20}, {.Press})
	ops.tag(gtx.scene, p.id, "Go")
	widget_close(gtx, &p, {size = {60, 20}})
}

@(test)
probe_finds_a_tag_without_an_area_by_its_bounds :: proc(t: ^testing.T) {
	p: Probe
	probe_init(&p, tagged_view, nil, {200, 100})
	defer probe_destroy(&p)
	// The label's tag carries its box, so it is found and measured
	// though no area has its id.
	h, ok := probe_find(&p, "Status: ready")
	testing.expect(t, ok)
	testing.expect_value(t, h.kinds, ops.Event_Kinds{})
	r := probe_bounds(&p, "Status: ready")
	testing.expect(t, r.w > 0 && r.h > 0 && r.x == 0 && r.y == 0, "label bounds")
	// The button below it starts where the label ends: tag bounds are in
	// device space, as hits are.
	b := probe_bounds(&p, "Go")
	testing.expect_value(t, b.y, r.y + r.h)
	testing.expect_value(t, b.w, f32(60))
	// An area's hit still wins over its tag's bounds.
	hb, _ := probe_find(&p, "Go")
	testing.expect(t, .Press in hb.kinds)
	_, missing := probe_find(&p, "nothing")
	testing.expect(t, !missing)
}

// Drag_Model sums what a draggable area is told: how far it travelled
// while pressed, in how many moves, and whether the press was released.
// The move onto it before the press is hover, not drag, and not counted.
@(private = "file")
Drag_Model :: struct {
	travel:   ops.Point,
	moves:    int,
	pressed:  bool,
	released: bool,
}

@(private = "file")
drag_view :: proc(gtx: ^Ctx, user: rawptr) {
	m := (^Drag_Model)(user)
	p := widget_open(gtx, 1)
	ops.input_area(gtx.scene, p.id, ops.Rect{0, 0, 50, 50}, {.Press, .Move, .Release})
	ops.tag(gtx.scene, p.id, "handle")
	for e in events(gtx, p.id) {
		#partial switch e.kind {
		case .Press:
			m.pressed = true
		case .Move:
			if m.pressed {
				m.travel += e.travel
				m.moves += 1
			}
		case .Release:
			m.pressed, m.released = false, true
		}
	}
	widget_close(gtx, &p, {size = {50, 50}})
}

@(test)
probe_drag_moves_in_steps_and_releases :: proc(t: ^testing.T) {
	m: Drag_Model
	p: Probe
	probe_init(&p, drag_view, &m, {200, 200})
	defer probe_destroy(&p)
	testing.expect(t, probe_drag(&p, "handle", 120, -10))
	// The grab holds past the area's edge, so every step's move arrives
	// and they add up to the whole distance.
	testing.expect_value(t, m.moves, 4)
	testing.expect_value(t, m.travel, ops.Point{120, -10})
	testing.expect(t, m.released)
	testing.expect(t, !probe_drag(&p, "nothing", 1, 1))
}

@(test)
test_a_probe_hands_reduce_motion_to_every_frame :: proc(t: ^testing.T) {
	view :: proc(gtx: ^Ctx, user: rawptr) {
		(^bool)(user)^ = gtx.reduce_motion
	}
	seen := true
	p: Probe
	probe_init(&p, view, &seen, {10, 10}, allocator = context.temp_allocator)
	defer probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect(t, !seen) // off unless the test asks: never the machine's setting
	p.reduce_motion = true
	probe_frame(&p)
	testing.expect(t, seen)
	// The platform read a host makes each frame answers without a window.
	_ = reduce_motion_preferred()
}

// Viewport_Reading is what a widget deep in a layout read of the window.
@(private = "file")
Viewport_Reading :: struct {
	viewport, offered: ops.Size,
}

@(test)
test_a_widget_inside_containers_reads_the_window_size :: proc(t: ^testing.T) {
	view :: proc(gtx: ^Ctx, user: rawptr) {
		seen := (^Viewport_Reading)(user)
		r := row_open(gtx)
		defer close(&r)
		spacer(gtx, 100)
		in_ := inset_open(gtx, pad_xy(20, 10))
		defer close(&in_)
		p := widget_open(gtx)
		seen^ = {gtx.viewport, gtx.constraints.max}
		widget_close(gtx, &p, {})
	}
	seen: Viewport_Reading
	p: Probe
	probe_init(&p, view, &seen, {640, 480}, allocator = context.temp_allocator)
	defer probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect_value(t, seen.viewport, ops.Size{640, 480}) // the window, through a row and an inset
	testing.expect_value(t, seen.offered, ops.Size{640 - 100 - 40, 480 - 20}) // the constraints are the box's own
}

