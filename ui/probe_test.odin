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
