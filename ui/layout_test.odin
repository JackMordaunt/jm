package ui

import "core:strings"
import "jm:ui/ops"
import "core:testing"
import "jm:ui/testutil"

// Harness is one window's worth of ui state for tests: sc, layout, router
// and font 0, over the stub shaper and the temp allocator.
@(private)
Harness :: struct {
	scene:    ops.Scene,
	layout: Layout,
	router: Router,
	gtx:    Ctx,
	size:   ops.Size,
}

@(private)
harness_init :: proc(h: ^Harness, size := ops.Size{400, 300}) {
	ops.init(&h.scene)
	layout_init(&h.layout)
	router_init(&h.router)
	h.size = size
	harness_frame(h)
}

// harness_frame starts a frame: empty sc, a fresh layout frame, root
// constraints loose up to the window size. Router events are left alone so
// a test can push them first.
@(private)
harness_frame :: proc(h: ^Harness) {
	ops.reset(&h.scene)
	layout_reset(&h.layout)
	h.gtx = {
		scene         = &h.scene,
		constraints = loose(h.size),
		font        = 0,
		shaper      = stub_shaper(),
		router      = &h.router,
		layout      = &h.layout,
		allocator   = context.temp_allocator,
	}
}

@(private)
harness_destroy :: proc(h: ^Harness) {
	ops.destroy(&h.scene)
	layout_destroy(&h.layout)
	router_destroy(&h.router)
	free_all(context.temp_allocator)
}

// pushes lists the translation of every Push_Transform, in order.
@(private)
pushes :: proc(o: ^ops.Scene) -> [dynamic]ops.Point {
	out := make([dynamic]ops.Point, context.temp_allocator)
	for op in o.ops {
		if t, ok := op.(ops.Push_Transform); ok {
			append(&out, ops.Point{f32(t.m.e), f32(t.m.f)})
		}
	}
	return out
}

@(private)
index_of :: proc(o: ^ops.Scene, $T: typeid, from := 0) -> int {
	for i in from ..< len(o.ops) {
		if _, ok := o.ops[i].(T); ok {
			return i
		}
	}
	return -1
}

// W is the stub shaper's advance per rune at the default text size 14.
@(private)
W :: f32(0.6 * 14)

@(test)
test_column_places_second_label_below_first :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	gtx := &h.gtx
	{
		col := column_open(gtx, gap = 8); defer close(&col)
		label(gtx, "Name")
		label(gtx, "Ada")
	}
	p := pushes(&h.scene)
	testing.expect_value(t, len(p), 2)
	testing.expect_value(t, p[0], ops.Point{0, 0})
	testing.expect_value(t, p[1], ops.Point{0, 14 + 8})
	testing.expect_value(t, testutil.count_ops(h.scene.ops[:], ops.Pop_Transform), 2)
	testing.expect_value(t, testutil.count_ops(h.scene.ops[:], ops.Glyphs), 2)
	testing.expect_value(t, testutil.count_ops(h.scene.ops[:], ops.Macro_Begin), 0)
}

@(test)
test_row_advances_on_x :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	gtx := &h.gtx
	{
		r := row_open(gtx, gap = 4); defer close(&r)
		label(gtx, "ab")
		label(gtx, "c")
	}
	p := pushes(&h.scene)
	testing.expect_value(t, len(p), 2)
	testing.expect(t, testutil.near(p[1].x, 2 * W + 4))
	testing.expect_value(t, p[1].y, 0)
}

@(test)
test_inset_offsets_by_padding :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	gtx := &h.gtx
	{
		col := column_open(gtx); defer close(&col)
		{
			in_ := inset_open(gtx, {10, 20, 30, 40}); defer close(&in_)
			label(gtx, "x")
		}
		label(gtx, "after")
	}
	// column child 0 (the inset), inset child, column child 1.
	p := pushes(&h.scene)
	testing.expect_value(t, len(p), 3)
	testing.expect_value(t, p[0], ops.Point{0, 0})
	testing.expect_value(t, p[1], ops.Point{10, 20})
	testing.expect_value(t, p[2], ops.Point{0, 20 + 14 + 40})
}

@(test)
test_box_records_macro_then_fill_then_call :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	gtx := &h.gtx
	{
		b := box_open(gtx, {fill = {4, 5, 6, 255}, outline = {7, 8, 9, 255}, stroke = 1, radius = 6, padding = pad_all(8)}); defer close(&b)
		label(gtx, "card")
	}
	begin := index_of(&h.scene, ops.Macro_Begin)
	finish := index_of(&h.scene, ops.Macro_End)
	paint := index_of(&h.scene, ops.Fill)
	outline := index_of(&h.scene, ops.Stroke)
	run := index_of(&h.scene, ops.Call)
	testing.expect(
		t,
		begin >= 0 && begin < finish && finish < paint && paint < outline && outline < run,
	)
	f := h.scene.ops[paint].(ops.Fill)
	rr := f.shape.(ops.Round_Rect)
	testing.expect(t, testutil.near(rr.rect.w, 4 * W + 16))
	testing.expect(t, testutil.near(rr.rect.h, 14 + 16))
	testing.expect_value(t, rr.radius, 6)
	testing.expect_value(t, f.paint.(ops.Color), ops.Color{4, 5, 6, 255})
	testing.expect_value(t, h.scene.ops[begin].(ops.Macro_Begin).id, h.scene.ops[run].(ops.Call).id)
	// The label inside is offset by the padding.
	p := pushes(&h.scene)
	testing.expect_value(t, p[0], ops.Point{8, 8})
}

@(test)
test_align_center_offsets_narrow_child :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	gtx := &h.gtx
	{
		col := column_open(gtx, align = .Center); defer close(&col)
		label(gtx, "i")
		label(gtx, "wide")
	}
	// Both children are macros placed at end: narrow first, then wide.
	testing.expect_value(t, testutil.count_ops(h.scene.ops[:], ops.Macro_Begin), 2)
	testing.expect_value(t, testutil.count_ops(h.scene.ops[:], ops.Call), 2)
	p := pushes(&h.scene)
	testing.expect_value(t, len(p), 2)
	testing.expect(t, testutil.near(p[0].x, (4 * W - W) / 2))
	testing.expect_value(t, p[0].y, 0)
	testing.expect_value(t, p[1], ops.Point{0, 14})
	// Each push wraps a call.
	first := index_of(&h.scene, ops.Push_Transform)
	_, is_call := h.scene.ops[first + 1].(ops.Call)
	testing.expect(t, is_call)
}

@(test)
test_align_end_and_fill :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h, {200, 100})
	defer harness_destroy(&h)
	gtx := &h.gtx
	{
		col := column_open(gtx, align = .End); defer close(&col)
		label(gtx, "i")
		label(gtx, "wide")
	}
	p := pushes(&h.scene)
	testing.expect(t, testutil.near(p[0].x, 3 * W))

	harness_frame(&h)
	gtx = &h.gtx
	{
		col := column_open(gtx, align = .Fill); defer close(&col)
		d := divider(gtx)
		testing.expect_value(t, d.size, ops.Size{200, 1})
	}
	testing.expect_value(t, testutil.count_ops(h.scene.ops[:], ops.Macro_Begin), 0)
}

@(test)
test_weighted_child_gets_remaining_space :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h, {300, 50})
	defer harness_destroy(&h)
	gtx := &h.gtx
	{
		r := row_open(gtx, gap = 10); defer close(&r)
		label(gtx, "ab")
		flexible(gtx, 1)
		d := label(gtx, "x")
		testing.expect(t, testutil.near(d.size.x, 300 - 2 * W - 10))
	}
}

@(test)
test_weighted_child_before_rigid_converges_next_frame :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h, {300, 50})
	defer harness_destroy(&h)
	sizes: [2]f32
	for frame in 0 ..< 2 {
		harness_frame(&h)
		gtx := &h.gtx
		r := row_open(gtx)
		flexible(gtx, 1)
		sizes[frame] = label(gtx, "x").size.x
		label(gtx, "abcd")
		close(&r)
	}
	// Frame 1 cannot know the rigid child after it; frame 2 uses frame 1's.
	testing.expect(t, testutil.near(sizes[0], 300))
	testing.expect(t, testutil.near(sizes[1], 300 - 4 * W))
}

@(test)
test_fill_space_pushes_the_rest_to_the_end :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h, {300, 50})
	defer harness_destroy(&h)
	gtx := &h.gtx
	{
		r := row_open(gtx); defer close(&r)
		label(gtx, "a")
		fill_space(gtx)
		label(gtx, "bc")
	}
	// "a" is placed directly; "bc" after the slot is a macro placed at end.
	p := pushes(&h.scene)
	testing.expect_value(t, len(p), 2)
	testing.expect_value(t, p[0], ops.Point{0, 0})
	testing.expect(t, testutil.near(p[1].x, 300 - 2 * W))
	testing.expect_value(t, testutil.count_ops(h.scene.ops[:], ops.Macro_Begin), 1)
}

@(test)
test_stack_clip_and_centered :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h, {100, 60})
	defer harness_destroy(&h)
	gtx := &h.gtx
	{
		c := clip_box_open(gtx); defer close(&c)
		label(gtx, "clip")
	}
	i := index_of(&h.scene, ops.Push_Clip)
	testing.expect(t, i > index_of(&h.scene, ops.Macro_End))
	r := h.scene.ops[i].(ops.Push_Clip).shape.(ops.Rect)
	testing.expect(t, testutil.near(r.w, 4 * W) && testutil.near(r.h, 14))

	harness_frame(&h)
	gtx = &h.gtx
	{
		c := centered_open(gtx); defer close(&c)
		label(gtx, "ab")
	}
	p := pushes(&h.scene)
	testing.expect_value(t, len(p), 1)
	testing.expect(t, testutil.near(p[0].x, (100 - 2 * W) / 2) && testutil.near(p[0].y, (60 - 14) / 2.0))

	harness_frame(&h)
	gtx = &h.gtx
	{
		col := column_open(gtx); defer close(&col)
		{
			s := stack_open(gtx); defer close(&s)
			label(gtx, "abc")
			label(gtx, "a")
		}
		label(gtx, "below")
	}
	p = pushes(&h.scene)
	testing.expect_value(t, len(p), 2) // stack children sit at the origin, unpushed
	testing.expect_value(t, p[1], ops.Point{0, 14})
}

@(test)
test_spacer_and_nesting :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	gtx := &h.gtx
	{
		col := column_open(gtx); defer close(&col)
		{
			r := row_open(gtx); defer close(&r)
			label(gtx, "a")
			spacer(gtx, 20)
			label(gtx, "b")
		}
		label(gtx, "c")
	}
	p := pushes(&h.scene)
	// col child 0 (row), a, spacer, b, col child 1.
	testing.expect_value(t, len(p), 5)
	testing.expect(t, testutil.near(p[3].x, W + 20))
	testing.expect_value(t, p[4], ops.Point{0, 14})
}

@(test)
test_nil_layout_places_at_origin :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	gtx := &h.gtx
	gtx.layout = nil
	{
		col := column_open(gtx, gap = 8); defer close(&col)
		label(gtx, "a")
		label(gtx, "b")
	}
	testing.expect_value(t, testutil.count_ops(h.scene.ops[:], ops.Push_Transform), 0)
	testing.expect_value(t, testutil.count_ops(h.scene.ops[:], ops.Glyphs), 2)
}

@(test)
test_state_is_pruned_after_a_frame_unseen :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	widget_state(&h.gtx, claim_id(&h.gtx)) // a widget asking for retained state
	testing.expect_value(t, len(h.layout.state), 1)
	harness_frame(&h)
	testing.expect_value(t, len(h.layout.state), 1)
	harness_frame(&h)
	testing.expect_value(t, len(h.layout.state), 0)
}

@(test)
test_id_is_stable_per_site_and_key :: proc(t: ^testing.T) {
	ids: [3]ops.Area_Id
	for i in 0 ..< 2 {
		ids[i] = id()
	}
	ids[2] = id(7)
	testing.expect_value(t, ids[0], ids[1])
	testing.expect(t, ids[0] != ids[2])
	testing.expect(t, id() != ids[0])
	testing.expect(t, id_mix(ids[0], 1) != id_mix(ids[0], 2))
}

// Of several frame requests the soonest wins, whatever the order, and a
// frame with none asks for nothing.
@(test)
test_request_frame_soonest_wins :: proc(t: ^testing.T) {
	gtx: Ctx
	testing.expect(t, !gtx.wants_frame)
	request_frame(&gtx, 0.5)
	request_frame(&gtx, 2)
	testing.expect(t, gtx.wants_frame)
	testing.expect_value(t, gtx.frame_after, 0.5)
	request_frame(&gtx)
	testing.expect_value(t, gtx.frame_after, 0)
	request_frame(&gtx, -3)
	testing.expect_value(t, gtx.frame_after, 0)
}

// scroll_frame lays a scroll_box over 300px of content in h's window and
// returns the box's input area, the zero area when it laid none.
@(private)
scroll_frame :: proc(h: ^Harness) -> ops.Input_Area {
	gtx := &h.gtx
	{
		sb := scroll_box_open(gtx); defer close(&sb)
		col := column_open(gtx); defer close(&col)
		spacer(gtx, 300)
		label(gtx, "last")
	}
	i := index_of(&h.scene, ops.Input_Area)
	if i < 0 {
		return {}
	}
	return h.scene.ops[i].(ops.Input_Area)
}

// A box whose content fits takes no wheel events, so they reach the box
// around it; once the content overflows it takes them.
@(test)
test_scroll_box_takes_the_wheel_only_while_it_overflows :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h, {200, 400})
	defer harness_destroy(&h)
	testing.expect_value(t, scroll_frame(&h).kinds, ops.Event_Kinds{})
	h.size = {200, 100}
	harness_frame(&h)
	testing.expect_value(t, scroll_frame(&h).kinds, ops.Event_Kinds{.Scroll})
}

// wide lays content out at its own width, at least the box's: a row
// wider than the box scrolls sideways, a narrow one is offered the box.
@(test)
test_scroll_box_wide_lays_content_at_its_own_width :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h, {100, 100})
	defer harness_destroy(&h)
	frame :: proc(h: ^Harness) -> Constraints {
		gtx := &h.gtx
		sb := scroll_box_open(gtx, wide = true); defer close(&sb)
		r := row_open(gtx); defer close(&r)
		label(gtx, "abcdefghijklmnop") // 16W = 134.4
		return gtx.constraints
	}
	offered := frame(&h)
	testing.expect_value(t, offered.max.x, INF)
	testing.expect_value(t, offered.min.x, 100) // at least the box
	clip := h.scene.ops[index_of(&h.scene, ops.Push_Clip)].(ops.Push_Clip)
	testing.expect_value(t, clip.shape.(ops.Rect).w, 100) // the box keeps its width
	ia := h.scene.ops[index_of(&h.scene, ops.Input_Area)].(ops.Input_Area)
	harness_frame(&h)
	event_push(&h, {kind = .Scroll, area = ia.id, scroll = {1e6, 0}})
	frame(&h)
	x := h.scene.ops[index_of(&h.scene, ops.Push_Clip) + 1].(ops.Push_Transform).m.e
	testing.expectf(t, testutil.near(f32(x), -(16 * W - 100)), "x %v", x) // clamped to the overflow
}

// scroll_offset is the y of the transform scroll_box pushes right after its
// clip (the body's own transforms come earlier, inside its macro).
@(private)
scroll_offset :: proc(h: ^Harness) -> f64 {
	i := index_of(&h.scene, ops.Push_Clip)
	return h.scene.ops[i + 1].(ops.Push_Transform).m.f
}

@(test)
test_scroll_box_clips_to_viewport_and_scrolls :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h, {200, 100})
	defer harness_destroy(&h)
	ia := scroll_frame(&h)
	testing.expect_value(t, ia.kinds, ops.Event_Kinds{.Scroll})
	clip := h.scene.ops[index_of(&h.scene, ops.Push_Clip)].(ops.Push_Clip)
	testing.expect_value(t, clip.shape.(ops.Rect).h, 100) // the offered height, not the content's
	testing.expect_value(t, scroll_offset(&h), 0)

	// One unit of scroll moves SCROLL_STEP pixels.
	harness_frame(&h)
	event_push(&h, {kind = .Scroll, area = ia.id, scroll = {0, SCROLL_STEP}})
	scroll_frame(&h)
	testing.expect_value(t, scroll_offset(&h), f64(-SCROLL_STEP))

	// Scrolling past the end clamps to the overflow: 300 + 14 - 100.
	clear(&h.router.events)
	harness_frame(&h)
	event_push(&h, {kind = .Scroll, area = ia.id, scroll = {0, 1e6}})
	scroll_frame(&h)
	testing.expect_value(t, scroll_offset(&h), -(300 + 14 - 100))
}

@(private = "file")
Scroll_Fit_Model :: struct {
	content: f32, // the child's height
	fit:     bool,
	inner:   Last_Widget, // last_widget after the child
	outer:   Last_Widget, // last_widget after the scroll box
}

@(private = "file")
fit_view :: proc(gtx: ^Ctx, user: rawptr) {
	m := (^Scroll_Fit_Model)(user)
	gtx.constraints = loose(gtx.viewport)
	box := sized_open(gtx, {max = {100, 120}})
	defer close(&box)
	sb := scroll_box_open(gtx, fit = m.fit)
	p := widget_open(gtx, 7)
	widget_close(gtx, &p, {size = {500, m.content}}) // wider than offered: clamped to 100
	m.inner = last_widget(gtx)
	close(&sb)
	m.outer = last_widget(gtx)
}

@(test)
test_a_fitting_scroll_box_hugs_its_content_up_to_its_cap :: proc(t: ^testing.T) {
	m := Scroll_Fit_Model{content = 40, fit = true}
	p: Probe
	probe_init(&p, fit_view, &m, {300, 300})
	defer probe_destroy(&p)
	testing.expect_value(t, m.inner.size, ops.Size{100, 40}) // the size it took, clamped
	testing.expect(t, m.inner.id != 0 && m.outer.id != m.inner.id, "last_widget names the widget just closed")
	testing.expect_value(t, m.outer.size.y, 40) // short content: its own height
	m.content = 300
	probe_frame(&p)
	testing.expect_value(t, m.outer.size.y, 120) // tall content: the cap, and it scrolls
	m.content, m.fit = 40, false
	probe_frame(&p)
	testing.expect_value(t, m.outer.size.y, 120) // without fit: the height offered, as before
}

@(test)
test_widget_close_emits_semantics_with_the_widgets_depth :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h, {200, 100})
	defer harness_destroy(&h)
	gtx := &h.gtx
	{
		col := column_open(gtx); defer close(&col)
		container_semantics(gtx, {role = .List, label = "Fruit"})
		p := widget_open(gtx, 1)
		semantics(gtx, &p, {role = .List_Item, label = "Apple", states = {.Selected}})
		widget_close(gtx, &p, {size = {80, 20}})
		spacer(gtx, 10) // says nothing: no op for it
	}
	{
		// A widget with a part and no declaration of its own closes as a
		// group of its parts, under the nearest declared container.
		q := widget_open(gtx, 2)
		part_semantics(gtx, &q, id_mix(q.id, 1), {0, 0, 5, 5}, {role = .Tab, label = "One"})
		widget_close(gtx, &q, {size = {20, 10}})
	}
	tip: ops.Area_Id
	{
		// A popup described as a node of its own: a root, boxed by the
		// size popup_close is given, its op inside the popup's macro.
		o := popup_open(gtx, {0, 0, 10, 10}, key = 9)
		tip = overlay_semantics(gtx, &o, {role = .Tooltip, label = "tip"})
		popup_close(&o, {40, 16})
	}
	{
		// A plain overlay has no size: its node takes the box it is given,
		// and the id of the area it already has.
		o := overlay_open(gtx)
		testing.expect_value(t, overlay_semantics(gtx, &o, {role = .Status}, id = 77, rect = {0, 0, 30, 12}), ops.Area_Id(77))
		close(&o)
	}
	got := make([dynamic]ops.Semantic, context.temp_allocator)
	for op in h.scene.ops {
		if s, ok := op.(ops.Semantic); ok {
			append(&got, s)
		}
	}
	// The child closes first, naming the column as its parent; the
	// column's op carries its own box and the role it declared.
	testing.expect_value(t, len(got), 6)
	testing.expect_value(t, got[2].parent, got[3].id)
	testing.expect_value(t, got[3].semantics, ops.Semantics{role = .Group})
	testing.expect_value(t, got[3].parent, ops.Area_Id(0))
	testing.expect_value(t, got[4].id, tip)
	testing.expect_value(t, got[4].parent, ops.Area_Id(0))
	testing.expect_value(t, got[4].rect, ops.Rect{0, 0, 40, 16})
	testing.expect_value(t, got[4].semantics.role, ops.Role.Tooltip)
	testing.expect_value(t, got[5].id, ops.Area_Id(77))
	testing.expect_value(t, got[5].rect, ops.Rect{0, 0, 30, 12})
	testing.expect_value(t, got[0].semantics, ops.Semantics{role = .List_Item, label = "Apple", states = {.Selected}})
	testing.expect_value(t, got[0].rect, ops.Rect{0, 0, 80, 20})
	testing.expect_value(t, got[0].parent, got[1].id)
	testing.expect_value(t, got[1].semantics, ops.Semantics{role = .List, label = "Fruit"})
	testing.expect_value(t, got[1].rect, ops.Rect{0, 0, 80, 30}) // the column hugs its content
	testing.expect_value(t, got[1].parent, ops.Area_Id(0))
}

// owned_scroll_frame is scroll_frame with the caller's offset.
@(private)
owned_scroll_frame :: proc(h: ^Harness, offset: ^Scroll_Offset) -> ops.Input_Area {
	gtx := &h.gtx
	{
		sb := scroll_box_open(gtx, offset = offset); defer close(&sb)
		col := column_open(gtx); defer close(&col)
		spacer(gtx, 300)
		label(gtx, "last")
	}
	return h.scene.ops[index_of(&h.scene, ops.Input_Area)].(ops.Input_Area)
}

@(test)
test_scroll_box_scrolls_the_callers_offset_when_given_one :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h, {200, 100})
	defer harness_destroy(&h)
	mine: Scroll_Offset
	ia := owned_scroll_frame(&h, &mine)
	// A scroll lands in the caller's offset, clamped to the overflow.
	harness_frame(&h)
	event_push(&h, {kind = .Scroll, area = ia.id, scroll = {0, SCROLL_STEP}})
	owned_scroll_frame(&h, &mine)
	testing.expect_value(t, mine, Scroll_Offset{0, SCROLL_STEP})
	testing.expect_value(t, scroll_offset(&h), f64(-SCROLL_STEP))
	// The caller sets it, and the box shows that: a restored position.
	clear(&h.router.events)
	mine.y = 1e6
	harness_frame(&h)
	owned_scroll_frame(&h, &mine)
	testing.expect_value(t, mine.y, f32(300 + 14 - 100))
	testing.expect_value(t, scroll_offset(&h), -(300 + 14 - 100))
	// The box's own slot was never written.
	_, kept := h.layout.data[Data_Key{ia.id, Scroll_Offset}]
	testing.expect(t, !kept)
}

// thumb_of is the scroll bar thumb scroll_box drew in the track starting
// at x, if any: a Round_Rect fill inside the track's width.
@(private)
thumb_of :: proc(h: ^Harness, x: f32) -> (ops.Rect, bool) {
	for op in h.scene.ops {
		f, is_fill := op.(ops.Fill)
		if !is_fill {
			continue
		}
		rr, is_rr := f.shape.(ops.Round_Rect)
		if is_rr && rr.rect.x >= x - 0.01 && rr.rect.x + rr.rect.w <= x + SCROLL_BAR_THICKNESS + 0.01 && rr.rect.w <= SCROLL_BAR_THICKNESS {
			return rr.rect, true
		}
	}
	return {}, false
}

// scroll_frames runs n frames of scroll_frame at 60 Hz, pushing evs into
// the first, and returns the box's input area.
@(private)
scroll_frames :: proc(h: ^Harness, n: int, evs: ..Event) -> ops.Input_Area {
	ia: ops.Input_Area
	for i in 0 ..< n {
		clear(&h.router.events)
		harness_frame(h)
		h.gtx.dt = 1.0 / 60
		if i == 0 {
			for e in evs {
				event_push(h, e)
			}
		}
		ia = scroll_frame(h)
	}
	return ia
}

@(test)
test_scroll_box_bar_hides_until_used_and_expands_on_hover :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h, {200, 100})
	defer harness_destroy(&h)
	ia := scroll_frame(&h)
	bar := id_mix(ia.id, 1)
	w := h.scene.ops[index_of(&h.scene, ops.Push_Clip)].(ops.Push_Clip).shape.(ops.Rect).w // the box's width
	edge := w - SCROLL_BAR_THICKNESS - SCROLL_BAR_INSET
	_, shown := thumb_of(&h, edge)
	testing.expect(t, !shown) // nothing has happened yet

	// Scrolling shows it, thin, against the box's edge.
	scroll_frames(&h, 20, Event{kind = .Scroll, area = ia.id, scroll = {0, SCROLL_STEP}})
	thumb, ok := thumb_of(&h, edge)
	testing.expect(t, ok)
	testing.expect(t, testutil.near(thumb.w, SCROLL_BAR_THIN) && testutil.near(thumb.x + thumb.w, edge + SCROLL_BAR_THICKNESS))

	// The pointer on it widens it, and keeps it while it stays.
	scroll_frames(&h, 120, Event{kind = .Enter, area = bar})
	thumb, ok = thumb_of(&h, edge)
	testing.expect(t, ok && testutil.near(thumb.w, SCROLL_BAR_THICKNESS))

	// Left alone past SCROLL_BAR_LINGER, it fades away.
	scroll_frames(&h, 120, Event{kind = .Leave, area = bar})
	_, shown = thumb_of(&h, edge)
	testing.expect(t, !shown)
}

@(test)
test_scroll_box_bar_drags_and_pages :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h, {200, 100})
	defer harness_destroy(&h)
	ia := scroll_frame(&h)
	bar := id_mix(ia.id, 1)
	w := h.scene.ops[index_of(&h.scene, ops.Push_Clip)].(ops.Push_Clip).shape.(ops.Rect).w // the box's width
	edge := w - SCROLL_BAR_THICKNESS - SCROLL_BAR_INSET
	// 314 of content in a 100 view: the thumb is 100/314 of the 96 track.
	thumb_h := f32(96 * 100.0 / 314)

	// Dragging the thumb across half its travel scrolls half the range. A
	// hidden bar takes input too: the pointer reaching it shows it.
	travel := 96 - thumb_h
	harness_frame(&h)
	h.gtx.dt = 1.0 / 60 // so the bar can start to fade in
	event_push(&h, {kind = .Press, area = bar, pos = {edge + 4, SCROLL_BAR_INSET + 4}})
	event_push(&h, {kind = .Move, area = bar, travel = {0, travel / 2}})
	scroll_frame(&h)
	testing.expect(t, testutil.near(f32(-scroll_offset(&h)), (314 - 100) / 2.0))
	thumb, ok := thumb_of(&h, edge)
	testing.expect(t, ok) // shown while held
	testing.expect(t, testutil.near(thumb.h, thumb_h))
	clear(&h.router.events)
	harness_frame(&h)
	event_push(&h, {kind = .Release, area = bar})
	scroll_frame(&h)

	// A press on the track above the thumb moves back a page.
	clear(&h.router.events)
	harness_frame(&h)
	event_push(&h, {kind = .Press, area = bar, pos = {edge + 4, SCROLL_BAR_INSET + 1}})
	scroll_frame(&h)
	paged := f32((314 - 100) / 2.0 - 100)
	testing.expect(t, testutil.near(f32(-scroll_offset(&h)), paged))
	// Moving while that track press is held drags nothing: only the thumb drags.
	clear(&h.router.events)
	harness_frame(&h)
	event_push(&h, {kind = .Move, area = bar, travel = {0, 30}})
	scroll_frame(&h)
	testing.expect(t, testutil.near(f32(-scroll_offset(&h)), paged))
}

@(test)
test_scroll_box_draws_no_bar_without_overflow :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h, {200, 400})
	defer harness_destroy(&h)
	scroll_frame(&h)
	w := h.scene.ops[index_of(&h.scene, ops.Push_Clip)].(ops.Push_Clip).shape.(ops.Rect).w
	_, ok := thumb_of(&h, w - SCROLL_BAR_THICKNESS - SCROLL_BAR_INSET)
	testing.expect(t, !ok)
}

@(test)
test_wrap_breaks_children_into_lines :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h, {100, 300})
	defer harness_destroy(&h)
	gtx := &h.gtx
	d: Dims
	{
		wr := wrap_open(gtx, gap = 10, line_gap = 4)
		defer close(&wr)
		for _ in 0 ..< 3 {
			d = label(gtx, "aaaaa")
		}
	}
	// Each placed child is a Push_Transform then its Call.
	at: [dynamic]ops.Point
	defer delete(at)
	for i in 0 ..< len(h.scene.ops) - 1 {
		pt, is_pt := h.scene.ops[i].(ops.Push_Transform)
		if _, is_call := h.scene.ops[i + 1].(ops.Call); is_pt && is_call {
			append(&at, ops.Point{f32(pt.m.e), f32(pt.m.f)})
		}
	}
	w, lh := d.size.x, d.size.y
	testing.expect(t, 2 * w + 10 <= 100 && 3 * w + 20 > 100) // two fit a line, three do not
	if !testing.expect_value(t, len(at), 3) {
		return
	}
	testing.expect_value(t, at[0], ops.Point{0, 0})
	testing.expect(t, testutil.near(at[1].x, w + 10) && at[1].y == 0)
	testing.expect(t, at[2].x == 0 && testutil.near(at[2].y, lh + 4))
}

// wide_scroll_frame lays a scroll_box with min_width 500 over a 500px
// wide, 300px tall column in h's 200x100 window.
@(private)
wide_scroll_frame :: proc(h: ^Harness) -> ops.Input_Area {
	gtx := &h.gtx
	{
		sb := scroll_box_open(gtx, min_width = 500); defer close(&sb)
		col := column_open(gtx); defer close(&col)
		spacer(gtx, 300)
	}
	return h.scene.ops[index_of(&h.scene, ops.Input_Area)].(ops.Input_Area)
}

@(test)
test_scroll_box_min_width_scrolls_sideways :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h, {200, 100})
	defer harness_destroy(&h)
	ia := wide_scroll_frame(&h)
	clip := h.scene.ops[index_of(&h.scene, ops.Push_Clip)].(ops.Push_Clip)
	testing.expect_value(t, clip.shape.(ops.Rect).w, 200) // the box stays the window's width
	x_offset :: proc(h: ^Harness) -> f64 {
		return h.scene.ops[index_of(&h.scene, ops.Push_Clip) + 1].(ops.Push_Transform).m.e
	}
	testing.expect_value(t, x_offset(&h), 0)

	// A horizontal wheel moves it sideways; Shift turns a vertical one.
	harness_frame(&h)
	event_push(&h, {kind = .Scroll, area = ia.id, scroll = {SCROLL_STEP, 0}})
	wide_scroll_frame(&h)
	testing.expect_value(t, x_offset(&h), f64(-SCROLL_STEP))
	testing.expect_value(t, scroll_offset(&h), 0)
	clear(&h.router.events)
	harness_frame(&h)
	event_push(&h, {kind = .Scroll, area = ia.id, scroll = {0, SCROLL_STEP}, mods = {.Shift}})
	wide_scroll_frame(&h)
	testing.expect_value(t, x_offset(&h), f64(-2 * SCROLL_STEP))
	testing.expect_value(t, scroll_offset(&h), 0)

	// It clamps to the overflow: 500 - 200.
	clear(&h.router.events)
	harness_frame(&h)
	event_push(&h, {kind = .Scroll, area = ia.id, scroll = {1e6, 0}})
	wide_scroll_frame(&h)
	testing.expect_value(t, x_offset(&h), -300)
}

@(test)
test_box_paint_replaces_fill_and_outline :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	gtx := &h.gtx
	got: ops.Size
	painter :: proc(gtx: ^Ctx, id: ops.Area_Id, size: ops.Size, user: rawptr) {
		(^ops.Size)(user)^ = size
		ops.fill(gtx.scene, ops.Rect{0, 0, size.x, size.y}, ops.Color{1, 2, 3, 255})
	}
	{
		b := box_open(gtx, {padding = pad_all(8), paint = painter, user = &got}); defer close(&b)
		label(gtx, "card")
	}
	testing.expect(t, testutil.near(got.x, 4 * W + 16) && testutil.near(got.y, 14 + 16))
	testing.expect_value(t, testutil.count_ops(h.scene.ops[:], ops.Stroke), 0)
	f := h.scene.ops[index_of(&h.scene, ops.Fill)].(ops.Fill)
	testing.expect_value(t, f.paint.(ops.Color), ops.Color{1, 2, 3, 255})
	// The paint runs under the body.
	testing.expect(t, index_of(&h.scene, ops.Fill) < index_of(&h.scene, ops.Call))
}

@(test)
test_zero_style_paints_nothing_and_pads_nothing :: proc(t: ^testing.T) {
	// ui has no theme: a box's zero style is exactly that, so a design
	// system's panel fills the defaults before calling.
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	gtx := &h.gtx
	{
		b := box_open(gtx); defer close(&b)
		label(gtx, "card")
	}
	testing.expect_value(t, testutil.count_ops(h.scene.ops[:], ops.Fill), 0)
	testing.expect_value(t, testutil.count_ops(h.scene.ops[:], ops.Stroke), 0)
	testing.expect_value(t, len(pushes(&h.scene)), 0) // no offset for the body
	harness_frame(&h)
	{
		b := box_open(gtx, {fill = {1, 2, 3, 255}}); defer close(&b)
		label(gtx, "card")
	}
	rr := h.scene.ops[index_of(&h.scene, ops.Fill)].(ops.Fill).shape.(ops.Round_Rect)
	testing.expect(t, testutil.near(rr.rect.w, 4 * W) && testutil.near(rr.rect.h, 14)) // the body's size, unpadded
}

@(test)
test_overlay_takes_no_space_and_draws_last :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	gtx := &h.gtx
	{
		col := column_open(gtx); defer close(&col)
		label(gtx, "before")
		{
			o := overlay_open(gtx, {5, 6}); defer close(&o)
			inner := column_open(gtx); defer close(&inner)
			label(gtx, "menu")
		}
		label(gtx, "after")
	}
	// "after" sits right below "before": the overlay took no space.
	p := pushes(&h.scene)
	testing.expect_value(t, p[len(p) - 1], ops.Point{0, 14})
	testing.expect_value(t, testutil.count_ops(h.scene.ops[:], ops.Defer), 1)

	f: Frame
	frame_init(&f, context.temp_allocator)
	flatten(&h.scene, &f)
	names := make([dynamic]string, context.temp_allocator)
	for tg in f.tags {
		append(&names, tg.name)
	}
	testing.expect_value(t, names[len(names) - 1], "menu")
	// At `at` from the enclosing column's origin, not from a slot in it.
	last := f.draws[len(f.draws) - 1]
	testing.expect_value(t, ops.apply(last.transform, {0, 0}), ops.Point{5, 6})
}

@(test)
test_covering_overlay_stacks_over_its_whole_container :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	gtx := &h.gtx
	{
		// At the root, recorded first: it covers the window, so it runs last.
		o := overlay_open(gtx, cover = true); defer close(&o)
		label(gtx, "window")
	}
	{
		col := column_open(gtx); defer close(&col)
		{
			o := overlay_open(gtx, cover = true); defer close(&o)
			label(gtx, "modal")
			n := overlay_open(gtx); defer close(&n)
			label(gtx, "from modal")
		}
		label(gtx, "page")
		{
			o := overlay_open(gtx); defer close(&o)
			label(gtx, "popup")
		}
		{
			r := row_open(gtx); defer close(&r)
			{
				o := overlay_open(gtx, cover = true); defer close(&o)
				label(gtx, "row modal")
			}
			o := overlay_open(gtx); defer close(&o)
			label(gtx, "row popup")
		}
		o := overlay_open(gtx); defer close(&o)
		label(gtx, "late")
	}
	f: Frame
	frame_init(&f, context.temp_allocator)
	flatten(&h.scene, &f)
	names := make([dynamic]string, context.temp_allocator)
	for tg in f.tags {
		append(&names, tg.name)
	}
	// Each modal sits over everything in its own container and what that
	// raises, under what its container's later siblings raise; one raised
	// from inside a modal sits over it.
	want := []string{"page", "popup", "row popup", "row modal", "late", "modal", "from modal", "window"}
	testing.expect_value(t, len(names), len(want))
	for w, i in want {
		if i < len(names) {
			testing.expect_value(t, names[i], w)
		}
	}
	// One draw per label, in the same order. The row's modal still lands
	// where it was recorded: the row's origin, below "page".
	testing.expect_value(t, len(f.draws), len(want))
	if len(f.draws) == len(want) {
		testing.expect_value(t, ops.apply(f.draws[3].transform, {0, 0}).y, 14)
	}
}

@(test)
test_discarded_overlay_is_never_drawn :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	gtx := &h.gtx
	{
		o := overlay_open(gtx); defer close(&o)
		label(gtx, "gone")
		o.discard = true
	}
	testing.expect_value(t, testutil.count_ops(h.scene.ops[:], ops.Defer), 0)
	f: Frame
	frame_init(&f, context.temp_allocator)
	flatten(&h.scene, &f)
	testing.expect_value(t, len(f.draws), 0)
}

@(test)
test_scroll_bar_ends_stop_the_track_at_the_corners :: proc(t: ^testing.T) {
	plain, ok := scroll_bar_layout(.Vertical, {100, 200}, 400, false)
	testing.expect(t, ok)
	testing.expect_value(t, plain.track.y, SCROLL_BAR_INSET)
	testing.expect_value(t, plain.track.h, 200 - 2 * SCROLL_BAR_INSET)
	// A 16dp corner radius: the track runs only along the straight edge.
	rounded, _ := scroll_bar_layout(.Vertical, {100, 200}, 400, false, ends = 16)
	testing.expect_value(t, rounded.track.y, 16)
	testing.expect_value(t, rounded.track.h, 200 - 2 * 16)
}

@(test)
test_scroll_box_bar_shows_at_once_when_revealing :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h, {200, 100})
	defer harness_destroy(&h)
	harness_frame(&h)
	h.gtx.debug = {.Reveal}
	scroll_frame(&h)
	w := h.scene.ops[index_of(&h.scene, ops.Push_Clip)].(ops.Push_Clip).shape.(ops.Rect).w
	thumb, ok := thumb_of(&h, w - SCROLL_BAR_THICKNESS - SCROLL_BAR_INSET)
	testing.expect(t, ok) // nothing has happened, yet it draws
	testing.expect(t, testutil.near(thumb.w, SCROLL_BAR_THIN))
}

@(test)
test_bounds_flag_outlines_each_widget :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	count :: proc(h: ^Harness) -> (n: int) {
		for op in h.scene.ops {
			s, is_stroke := op.(ops.Stroke)
			if !is_stroke {
				continue
			}
			if c, is_color := s.paint.(ops.Color); is_color && c == BOUNDS_COLOR {
				n += 1
			}
		}
		return
	}
	frame :: proc(h: ^Harness, debug: Debug_Flags) {
		harness_frame(h)
		h.gtx.debug = debug
		col := column_open(&h.gtx); defer close(&col)
		label(&h.gtx, "a")
		label(&h.gtx, "b")
	}
	frame(&h, {})
	testing.expect_value(t, count(&h), 0)
	frame(&h, {.Bounds})
	testing.expect_value(t, count(&h), 3) // two labels and their column
}

@(test)
test_inspect_flag_records_each_widgets_box :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	boxes :: proc(h: ^Harness) -> (out: [dynamic]ops.Debug_Box) {
		out = make([dynamic]ops.Debug_Box, context.temp_allocator)
		for op in h.scene.ops {
			if b, ok := op.(ops.Debug_Box); ok {
				append(&out, b)
			}
		}
		return
	}
	harness_frame(&h)
	label(&h.gtx, "a")
	testing.expect_value(t, len(boxes(&h)), 0)
	harness_frame(&h)
	h.gtx.debug = {.Inspect}
	d := label(&h.gtx, "a")
	got := boxes(&h)
	if !testing.expect_value(t, len(got), 1) {
		return
	}
	testing.expect_value(t, got[0].size, d.size)
	testing.expect_value(t, got[0].max, h.size) // the harness offers the window, loosely
	testing.expect_value(t, got[0].procedure, "test_inspect_flag_records_each_widgets_box")
	testing.expect_value(t, got[0].kind, "label") // the widget proc that made it, not the caller
	// A container is named by its opener with _open trimmed, through the
	// private flex_open it delegates to, and a guard the same.
	harness_frame(&h)
	h.gtx.debug = {.Inspect}
	col := column_open(&h.gtx)
	close(&col)
	if row(&h.gtx) {
	}
	kinds := boxes(&h)
	if testing.expect_value(t, len(kinds), 2) {
		testing.expect_value(t, kinds[0].kind, "column")
		testing.expect_value(t, kinds[1].kind, "row")
	}
}

@(test)
test_widget_state_pointers_survive_the_map_growing :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	first := widget_state(&h.gtx, 1)
	first.springs[0].value = 42
	for i in 2 ..< 2000 {
		widget_state(&h.gtx, ops.Area_Id(i))
	}
	testing.expect_value(t, first, widget_state(&h.gtx, 1))
	testing.expect_value(t, first.springs[0].value, 42)
}

@(test)
test_layout_accessors_name_the_open_containers :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	gtx := &h.gtx
	l := &h.layout
	testing.expect_value(t, depth(l), 0)
	testing.expect(t, innermost(l) == nil)
	testing.expect_value(t, depth(nil), 0) // without a layout there is nothing open
	testing.expect(t, innermost(nil) == nil)
	{
		col := column_open(gtx); defer close(&col)
		testing.expect_value(t, depth(l), 1)
		c := innermost(l)
		testing.expect(t, c != nil && c.kind == .Flex && c.axis == .Vertical)
		testing.expect(t, c == container_at(l, col.index)) // the handle's index is the innermost
		testing.expect_value(t, len(children_of(l, c)), 0)
		one := label(gtx, "one")
		two := label(gtx, "two, wider")
		kids := children_of(l, c)
		testing.expect_value(t, len(kids), 2)
		if len(kids) == 2 {
			testing.expect_value(t, kids[0].size, one.size) // the labels, in order, at the size they took
			testing.expect_value(t, kids[1].size, two.size)
		}
		// A nested row is innermost while open and the column's child once ended.
		{
			r := row_open(gtx); defer close(&r)
			testing.expect_value(t, depth(l), 2)
			testing.expect(t, innermost(l) != c) // the row is innermost now
			testing.expect(t, innermost(l).axis == .Horizontal)
			testing.expect_value(t, len(children_of(l, innermost(l))), 0) // and has placed nothing yet
			testing.expect(t, container_at(l, col.index) == c) // the column is still there by index
			testing.expect_value(t, len(children_of(l, c)), 2) // the row joins it only when it ends
			// An overlay lays out on its own stack: nothing is open inside it,
			// and the column and row come back when it ends.
			{
				o := overlay_open(gtx); defer close(&o)
				testing.expect_value(t, depth(l), 0)
				testing.expect(t, innermost(l) == nil)
			}
			testing.expect_value(t, depth(l), 2)
			testing.expect(t, innermost(l).axis == .Horizontal)
		}
		testing.expect_value(t, depth(l), 1)
		testing.expect(t, innermost(l) == c)
		testing.expect_value(t, len(children_of(l, c)), 3) // the row, placed
	}
	testing.expect_value(t, depth(l), 0)
}

@(test)
test_openers_push_complete_containers :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	gtx := &h.gtx
	l := &h.layout
	{
		w := wrap_open(gtx, gap = 6); defer close(&w)
		c := innermost(l)
		testing.expect(t, c.kind == .Flex && c.axis == .Horizontal && c.wrap)
		testing.expect_value(t, c.gap, 6)
		testing.expect_value(t, c.line_gap, 6) // line_gap follows gap when not given
		testing.expect(t, c.deferred)
	}
	{
		w := wrap_open(gtx, gap = 6, line_gap = 2); defer close(&w)
		testing.expect_value(t, innermost(l).line_gap, 2)
	}
	{
		col := column_open(gtx, align = .Fill); defer close(&col)
		testing.expect(t, !innermost(l).deferred) // Fill places as it goes
		r := row_open(gtx, align = .End); defer close(&r)
		testing.expect(t, innermost(l).deferred) // End must know the total first
	}
	{
		macros := testutil.count_ops(h.scene.ops[:], ops.Macro_Begin)
		b := box_open(gtx, {padding = {4, 8, 4, 8}}); defer close(&b)
		c := innermost(l)
		testing.expect(t, c.kind == .Box)
		testing.expect_value(t, c.pad, Padding{4, 8, 4, 8})
		testing.expect_value(t, c.offset, ops.Point{4, 8})
		testing.expect_value(t, c.inner.max, c.cs.max - {8, 16}) // shrunk by the padding
		testing.expect_value(t, testutil.count_ops(h.scene.ops[:], ops.Macro_Begin), macros + 1) // its body records
	}
	{
		st := stack_open(gtx); defer close(&st)
		c := innermost(l)
		testing.expect(t, c.kind == .Stack)
		testing.expect_value(t, c.inner.min, ops.Size{0, 0}) // loose: children may be any size up to the max
		testing.expect_value(t, c.inner.max, c.cs.max)
	}
	{
		tracks := []Track{{width = 40}, {grow = 1}}
		g := grid_open(gtx, tracks, column_gap = 3, row_gap = 5); defer close(&g)
		c := innermost(l)
		testing.expect(t, c.kind == .Grid && c.deferred)
		testing.expect_value(t, c.gap, 3)
		testing.expect_value(t, c.line_gap, 5)
		testing.expect(t, raw_data(c.tracks) != raw_data(tracks)) // its own copy, for the frame
		testing.expect_value(t, len(c.tracks), 2)
	}
}

@(test)
test_guards_close_what_they_open_at_the_end_of_their_if :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	gtx := &h.gtx
	l := &h.layout
	{
		opened := column(gtx) // a guard reports true, so its if body runs
		testing.expect(t, opened)
		testing.expect_value(t, depth(l), 1)
	}
	testing.expect_value(t, depth(l), 0) // and closed with the block
	if column(gtx, gap = 8) {
		testing.expect_value(t, depth(l), 1)
		testing.expect(t, innermost(l).kind == .Flex && innermost(l).axis == .Vertical)
		label(gtx, "one")
		if row(gtx, align = .End) {
			testing.expect_value(t, depth(l), 2)
			testing.expect(t, innermost(l).axis == .Horizontal)
		}
		testing.expect_value(t, depth(l), 1) // the row closed with its if
		if box(gtx, {padding = {4, 4, 4, 4}}) {
			testing.expect(t, innermost(l).kind == .Box)
			if stack(gtx) {
				testing.expect(t, innermost(l).kind == .Stack)
			}
			testing.expect(t, innermost(l).kind == .Box)
		}
		testing.expect_value(t, depth(l), 1)
	}
	testing.expect_value(t, depth(l), 0)
	if wrap(gtx, gap = 6) {
		testing.expect(t, innermost(l).wrap)
	}
	if inset(gtx, {2, 2, 2, 2}) {
		testing.expect(t, innermost(l).kind == .Inset)
	}
	if scroll_box(gtx) {
		testing.expect(t, innermost(l).kind == .Scroll)
	}
	if centered(gtx) {
		testing.expect(t, innermost(l).kind == .Center)
	}
	if clip_box(gtx) {
		testing.expect(t, innermost(l).kind == .Clip)
	}
	testing.expect_value(t, depth(l), 0)
}

@(test)
test_guard_and_explicit_pair_lay_out_the_same :: proc(t: ^testing.T) {
	// The same tree through guards and through open/close pairs produces
	// the same sc, so a caller may pick either form.
	Draw :: proc(gtx: ^Ctx, guarded: bool) {
		if guarded {
			if column(gtx, gap = 8) {
				label(gtx, "a")
				if row(gtx, gap = 4) {
					label(gtx, "b")
					label(gtx, "c")
				}
			}
		} else {
			col := column_open(gtx, gap = 8); defer close(&col)
			label(gtx, "a")
			r := row_open(gtx, gap = 4); defer close(&r)
			label(gtx, "b")
			label(gtx, "c")
		}
	}
	a, b: Harness
	harness_init(&a)
	harness_init(&b)
	defer harness_destroy(&a)
	defer harness_destroy(&b)
	Draw(&a.gtx, true)
	Draw(&b.gtx, false)
	// Widget ids come from the call site, so the two trees differ only in
	// the ids their input areas carry; masked, the op streams must match.
	testing.expect_value(t, mask_ids(ops.dump(&a.scene, context.temp_allocator)), mask_ids(ops.dump(&b.scene, context.temp_allocator)))
	testing.expect_value(t, len(a.layout.state), len(b.layout.state))
}

// mask_ids replaces every run of 12 or more digits (an Area_Id) with #.
@(private = "file")
mask_ids :: proc(s: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	run := 0
	for i := 0; i < len(s); i += 1 {
		if s[i] >= '0' && s[i] <= '9' {
			run += 1
			continue
		}
		if run >= 12 {
			strings.write_byte(&b, '#')
		} else {
			strings.write_string(&b, s[i - run:i])
		}
		run = 0
		strings.write_byte(&b, s[i])
	}
	if run >= 12 {
		strings.write_byte(&b, '#')
	} else {
		strings.write_string(&b, s[len(s) - run:])
	}
	return strings.to_string(b)
}

// Popups: placed by flatten, flipped and shifted to stay in the window.

@(private = "file")
Popup_Model :: struct {
	anchor: ops.Rect, // where the anchor widget is laid out
	side:   ops.Side,
	align:  ops.Side_Align,
	seen:   ops.Side, // placed_side as the popup's frame read it
	shift:  ops.Point,
}

// popup_view lays a 40x20 anchor at m.anchor's origin and opens a 100x120
// popup from it, tagged "popup".
@(private = "file")
popup_view :: proc(gtx: ^Ctx, user: rawptr) {
	m := (^Popup_Model)(user)
	ops.transform_push(gtx.scene, ops.translate(m.anchor.x, m.anchor.y))
	defer ops.transform_pop(gtx.scene)
	key := ops.Area_Id(0x9090)
	m.seen = placed_side(gtx, key, m.side)
	o := popup_open(gtx, {0, 0, m.anchor.w, m.anchor.h}, key, m.side, m.align, gap = 4)
	ops.input_area(gtx.scene, 7, ops.Rect{0, 0, 100, 120}, {.Press})
	ops.tag(gtx.scene, 7, "popup")
	popup_close(&o, {100, 120})
}

@(test)
test_popup_opens_where_asked_when_it_fits :: proc(t: ^testing.T) {
	m := Popup_Model{anchor = {20, 20, 40, 20}}
	p: Probe
	probe_init(&p, popup_view, &m, {400, 300}, allocator = context.temp_allocator)
	defer probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect_value(t, probe_bounds(&p, "popup"), ops.Rect{20, 44, 100, 120})
	probe_frame(&p)
	testing.expect_value(t, m.seen, ops.Side.Below)
}

@(test)
test_popup_flips_above_near_the_bottom_and_reports_it :: proc(t: ^testing.T) {
	m := Popup_Model{anchor = {20, 260, 40, 20}}
	p: Probe
	probe_init(&p, popup_view, &m, {400, 300}, allocator = context.temp_allocator)
	defer probe_destroy(&p)
	defer free_all(context.temp_allocator)
	// Below would run to y 404 in a 300 window: above, 4px over the anchor.
	testing.expect_value(t, probe_bounds(&p, "popup"), ops.Rect{20, 260 - 4 - 120, 100, 120})
	probe_frame(&p)
	testing.expect_value(t, m.seen, ops.Side.Above)
}

@(test)
test_popup_shifts_inside_at_the_edges :: proc(t: ^testing.T) {
	// Near the right edge: kept below, shifted left to end at the window's edge.
	m := Popup_Model{anchor = {370, 20, 20, 20}}
	p: Probe
	probe_init(&p, popup_view, &m, {400, 300}, allocator = context.temp_allocator)
	defer probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect_value(t, probe_bounds(&p, "popup"), ops.Rect{300, 44, 100, 120})
	// Too tall for either side in a short window: the side with less
	// overflow, then shifted to lie inside from the top.
	m.anchor = {20, 60, 40, 20}
	p2: Probe
	probe_init(&p2, popup_view, &m, {400, 130}, allocator = context.temp_allocator)
	defer probe_destroy(&p2)
	r := probe_bounds(&p2, "popup")
	testing.expect_value(t, r.y, 0)
	testing.expect_value(t, r.h, 120)
	// After, centred on the anchor's edge.
	m.anchor, m.side, m.align = {20, 100, 40, 20}, .After, .Center
	p3: Probe
	probe_init(&p3, popup_view, &m, {400, 300}, allocator = context.temp_allocator)
	defer probe_destroy(&p3)
	testing.expect_value(t, probe_bounds(&p3, "popup"), ops.Rect{64, 110 - 60, 100, 120})
}

@(test)
test_popup_of_an_offscreen_anchor_stays_with_it :: proc(t: ^testing.T) {
	// An anchor scrolled below the window: its popup is not pulled into view.
	m := Popup_Model{anchor = {20, 500, 40, 20}}
	p: Probe
	probe_init(&p, popup_view, &m, {400, 300}, allocator = context.temp_allocator)
	defer probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect_value(t, probe_bounds(&p, "popup"), ops.Rect{20, 524, 100, 120})
}

@(test)
test_popup_of_a_zero_width_anchor_still_flips :: proc(t: ^testing.T) {
	// An anchor that is only an edge, as a picker's field often gives.
	m := Popup_Model{anchor = {20, 260, 0, 20}}
	p: Probe
	probe_init(&p, popup_view, &m, {400, 300}, allocator = context.temp_allocator)
	defer probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect_value(t, probe_bounds(&p, "popup"), ops.Rect{20, 260 - 4 - 120, 100, 120})
}

@(test)
test_popup_reports_its_shift_in_anchor_coordinates :: proc(t: ^testing.T) {
	view :: proc(gtx: ^Ctx, user: rawptr) {
		m := (^Popup_Model)(user)
		// A 2x scale: the shift reads back in the anchor's own units.
		ops.transform_push(gtx.scene, ops.mul(ops.scale(2, 2), ops.translate(m.anchor.x, m.anchor.y)))
		defer ops.transform_pop(gtx.scene)
		_, m.shift = placed(gtx, 0x9191, .Below)
		o := popup_open(gtx, {0, 0, 10, 10}, 0x9191)
		popup_close(&o, {100, 20})
	}
	// The popup is 200 device px wide from x 300 in a 400 window: shifted
	// 100 device px left, 50 in the anchor's units.
	m := Popup_Model{anchor = {300, 20, 0, 0}}
	p: Probe
	probe_init(&p, view, &m, {400, 300}, allocator = context.temp_allocator)
	defer probe_destroy(&p)
	defer free_all(context.temp_allocator)
	probe_frame(&p)
	testing.expect_value(t, m.shift, ops.Point{-50, 0})
}

// Fallback orders: @primer/behaviors' getAnchoredPosition, expressed in
// a Placement (anchored-position.mjs:1-11,112-176).

@(private = "file")
Fallback_Model :: struct {
	place: ops.Placement, // the anchor's rect is its position; key, sides and the rest as asked
	size:  ops.Size, // the popup's
	fit:   Placed, // last_placed as the popup's frame read it
}

// PRIMER_BELOW is outside-bottom's alternates and the alignment
// alternates for start, with the overhang that lets an overlay that fits
// nowhere hang off the bottom.
@(private = "file")
PRIMER_BELOW :: ops.Placement {
	key         = 0x9292,
	side        = .Below,
	align       = .Start,
	gap         = 4,
	overhang    = true,
	side_count  = 4,
	sides       = {.Above, .After, .Before, .Below},
	align_count = 2,
	aligns      = {.End, .Center},
}

@(private = "file")
fallback_view :: proc(gtx: ^Ctx, user: rawptr) {
	m := (^Fallback_Model)(user)
	a := m.place.anchor
	ops.transform_push(gtx.scene, ops.translate(a.x, a.y))
	defer ops.transform_pop(gtx.scene)
	m.fit, _ = last_placed(gtx, m.place.key)
	pl := m.place
	pl.anchor = {0, 0, a.w, a.h}
	o := popup_place(gtx, pl)
	ops.input_area(gtx.scene, 8, ops.Rect{0, 0, m.size.x, m.size.y}, {.Press})
	ops.tag(gtx.scene, 8, "popup")
	popup_close(&o, m.size)
}

@(private = "file")
fallback_bounds :: proc(m: ^Fallback_Model, window: ops.Size) -> ops.Rect {
	p: Probe
	probe_init(&p, fallback_view, m, window, allocator = context.temp_allocator)
	defer probe_destroy(&p)
	probe_frame(&p)
	return probe_bounds(&p, "popup")
}

@(test)
test_popup_tries_its_sides_in_order_and_takes_the_first_that_fits :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	// 220 tall from a 20px anchor at y 100 in a 300 window: below runs to
	// 344, above to -124; right is the first that fits on its own axis,
	// start-aligned at the anchor's top, then shifted up into the window.
	m := Fallback_Model{place = PRIMER_BELOW, size = {100, 220}}
	m.place.anchor = {20, 100, 40, 20}
	testing.expect_value(t, fallback_bounds(&m, {400, 300}), ops.Rect{64, 80, 100, 220})
	testing.expect_value(t, m.fit.side, ops.Side.After)
	testing.expect_value(t, m.fit.align, ops.Side_Align.Start)
	// jm:ui's own flip, with no order, keeps the side that overflows less.
	m.place.side_count = 0
	m.place.align_count = 0
	testing.expect_value(t, fallback_bounds(&m, {400, 300}).x, 20)
}

@(test)
test_popup_that_fits_nowhere_hangs_off_the_bottom_with_overhang :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	// Every side overflows: the order ends on below, and with the sides run
	// out the bottom is left unclamped.
	m := Fallback_Model{place = PRIMER_BELOW, size = {380, 260}}
	m.place.anchor = {20, 100, 40, 20}
	testing.expect_value(t, fallback_bounds(&m, {400, 300}), ops.Rect{20, 124, 380, 260})
	testing.expect_value(t, m.fit.side, ops.Side.Below)
	// Without overhang it is shifted up to end at the window's bottom.
	m.place.overhang = false
	testing.expect_value(t, fallback_bounds(&m, {400, 300}), ops.Rect{20, 40, 380, 260})
}

@(test)
test_popup_realigns_before_it_shifts :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	// Start-aligned at x 340, a 100 wide popup leaves a 400 window; end
	// alignment fits, so it ends at the anchor's right edge.
	m := Fallback_Model{place = PRIMER_BELOW, size = {100, 50}}
	m.place.anchor = {340, 20, 40, 20}
	testing.expect_value(t, fallback_bounds(&m, {400, 300}), ops.Rect{280, 44, 100, 50})
	testing.expect_value(t, m.fit.align, ops.Side_Align.End)
	// End only tests the left edge: an anchor running off the right keeps
	// end alignment and is shifted in.
	m.place.align, m.place.aligns = .End, {.Start, .Center}
	m.place.anchor = {380, 20, 40, 20}
	testing.expect_value(t, fallback_bounds(&m, {400, 300}), ops.Rect{300, 44, 100, 50})
	testing.expect_value(t, m.fit.align, ops.Side_Align.End)
	m.place.align, m.place.aligns = .Start, {.End, .Center}
	// Beside the anchor the test stays horizontal: a popup on the right
	// that runs off the bottom keeps its alignment and is shifted up.
	m.place.side = .After
	m.place.anchor = {20, 260, 40, 20}
	testing.expect_value(t, fallback_bounds(&m, {400, 300}), ops.Rect{64, 250, 100, 50})
	testing.expect_value(t, m.fit.align, ops.Side_Align.Start)
}

@(test)
test_popup_inside_its_anchor_sits_against_the_edge_nudged :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	// inside-top, start: gap in from the top, nudged in from the left.
	m := Fallback_Model{size = {50, 30}}
	m.place = {key = 0x9393, anchor = {20, 20, 200, 100}, side = .Above, align = .Start, gap = 4, nudge = 4, inside = true}
	testing.expect_value(t, fallback_bounds(&m, {400, 300}), ops.Rect{24, 24, 50, 30})
	// inside-right, end: against the right edge, nudged up from the bottom.
	m.place.side, m.place.align = .After, .End
	testing.expect_value(t, fallback_bounds(&m, {400, 300}), ops.Rect{20 + 200 - 4 - 50, 20 + 100 - 30 - 4, 50, 30})
	// Outside, end-aligned below: the nudge moves it in from the right edge.
	m.place.side, m.place.inside = .Below, false
	testing.expect_value(t, fallback_bounds(&m, {400, 300}), ops.Rect{20 + 200 - 50 - 4, 124, 50, 30})
}

@(test)
test_a_cancelled_thumb_drag_stops_scrolling :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h, {200, 100})
	defer harness_destroy(&h)
	ia := scroll_frame(&h)
	bar := id_mix(ia.id, 1)
	w := h.scene.ops[index_of(&h.scene, ops.Push_Clip)].(ops.Push_Clip).shape.(ops.Rect).w
	edge := w - SCROLL_BAR_THICKNESS - SCROLL_BAR_INSET
	harness_frame(&h)
	// Held on the thumb, then its press is taken: moves no longer drag.
	event_push(&h, {kind = .Press, area = bar, pos = {edge + 4, SCROLL_BAR_INSET + 4}})
	event_push(&h, {kind = .Cancel, area = bar})
	event_push(&h, {kind = .Move, area = bar, travel = {0, 30}})
	scroll_frame(&h)
	testing.expect_value(t, scroll_offset(&h), 0)
}

// block is a leaf size big whose first baseline is baseline down (0: none).
@(private = "file")
block :: proc(gtx: ^Ctx, size: ops.Size, baseline: f32, key: u64, loc := #caller_location) -> Dims {
	p := widget_open(gtx, key, loc)
	return widget_close(gtx, &p, {size, baseline})
}

@(test)
test_align_baseline_lines_up_first_baselines_in_a_row :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	gtx := &h.gtx
	d: Dims
	{
		outer := column_open(gtx); defer close(&outer)
		r := row_open(gtx, align = .Baseline)
		block(gtx, {10, 30}, 20, 1) // tallest ascent
		block(gtx, {10, 14}, 10, 2)
		block(gtx, {10, 8}, 0, 3) // no baseline: its bottom edge sits on the line
		block(gtx, {10, 24}, 6, 4) // deepest descent
		close(&r)
		kids := children_of(gtx.layout, innermost(gtx.layout))
		d = {kids[len(kids) - 1].size, kids[len(kids) - 1].baseline} // the row, as its parent saw it
	}
	all := pushes(&h.scene) // the column places the row first, then the row its children
	testing.expect_value(t, len(all), 5)
	p := all[1:]
	if len(p) == 4 {
		testing.expect_value(t, p[0].y, 0)
		testing.expect_value(t, p[1].y, 10)
		testing.expect_value(t, p[2].y, 12)
		testing.expect_value(t, p[3].y, 14)
	}
	testing.expect_value(t, d.size.y, 20 + 18) // deepest ascent plus deepest descent
	testing.expect_value(t, d.baseline, 20)
}

@(test)
test_align_baseline_is_start_in_a_column_and_per_line_in_a_wrap :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h, {25, 300})
	defer harness_destroy(&h)
	gtx := &h.gtx
	{
		col := column_open(gtx, align = .Baseline); defer close(&col)
		block(gtx, {10, 30}, 20, 1)
		block(gtx, {5, 14}, 10, 2)
	}
	testing.expect_value(t, testutil.count_ops(h.scene.ops[:], ops.Macro_Begin), 0) // placed as it goes

	harness_frame(&h)
	gtx = &h.gtx
	{
		w := wrap_open(gtx, align = .Baseline); defer close(&w)
		block(gtx, {10, 30}, 20, 1)
		block(gtx, {10, 14}, 10, 2)
		block(gtx, {10, 10}, 4, 3) // 25 wide: a second line
		block(gtx, {10, 20}, 16, 4)
	}
	p := pushes(&h.scene)
	testing.expect_value(t, len(p), 4)
	if len(p) == 4 {
		testing.expect_value(t, p[0], ops.Point{0, 0})
		testing.expect_value(t, p[1], ops.Point{10, 10})
		testing.expect_value(t, p[2], ops.Point{0, 30 + 12}) // line two's baseline is 16 down
		testing.expect_value(t, p[3], ops.Point{10, 30})
	}
}

// A shape delivered for a need that no frame asks for again lives through
// the frame after, as a widget's state does, then goes.
@(test)
test_layout_drops_a_shape_nobody_asks_for :: proc(t: ^testing.T) {
	l: Layout
	layout_init(&l)
	defer layout_destroy(&l)
	deliver(&l, 7, {1, 2, 3})
	testing.expect_value(t, len(l.shapes), 1)
	layout_reset(&l)
	testing.expect_value(t, len(l.shapes), 1)
	layout_reset(&l)
	testing.expect_value(t, len(l.shapes), 0)
}

// Fit_Model is flex_fit's test row: children of these widths, a reserve,
// and what the row reported.
@(private = "file")
Fit_Model :: struct {
	widths:  []f32,
	reserve: f32,
	n:       int, // flex_truncate to this many instead, when >= 0
	dropped: int,
	count:   int, // flex_count after the fit
	extent:  f32, // flex_extent after the fit
}

@(private = "file")
fit_chip :: proc(gtx: ^Ctx, name: string, w: f32, key: u64) {
	p := widget_open(gtx, key)
	ops.input_area(gtx.scene, p.id, ops.Rect{0, 0, w, 10}, {.Press})
	ops.tag(gtx.scene, p.id, name)
	widget_close(gtx, &p, {size = {w, 10}})
}

@(private = "file")
fit_row :: proc(gtx: ^Ctx, user: rawptr) {
	m := (^Fit_Model)(user)
	names := [?]string{"a", "b", "c", "d", "e"}
	col := column_open(gtx) // loose: the window's constraints are exact
	defer close(&col)
	sz := sized_open(gtx, {max = {100, 0}})
	defer close(&sz)
	r := overflow_row_open(gtx, gap = 4, align = .Center)
	defer close(&r)
	for w, i in m.widths {
		fit_chip(gtx, names[i], w, u64(i))
	}
	if m.n >= 0 {
		flex_truncate(&r, m.n)
	} else {
		m.dropped = flex_fit(&r, m.reserve)
	}
	m.count, m.extent = flex_count(&r), flex_extent(&r)
	fit_chip(gtx, "more", m.reserve, 99)
}

@(test)
test_flex_fit_keeps_the_prefix_that_fits_beside_the_reserve :: proc(t: ^testing.T) {
	// 30 + 4 + 30 + 4 + 30 = 98 fits 100 whole: nothing drops.
	m := Fit_Model{widths = {30, 30, 30}, reserve = 0, n = -1}
	p: Probe
	probe_init(&p, fit_row, &m, {400, 100}, allocator = context.temp_allocator)
	defer probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect_value(t, m.dropped, 0)
	testing.expect(t, probe_tagged(&p, "c"))

	// Five 30s overflow, each measured at its natural width; leaving a
	// gap and a 20px reserve, 100 - 4 - 20 = 76 holds two (30 + 4 + 30 =
	// 64; a third ends at 98).
	m.widths = {30, 30, 30, 30, 30}
	m.reserve = 20
	probe_frame(&p)
	testing.expect_value(t, m.dropped, 3)
	testing.expect_value(t, m.count, 2)
	testing.expect_value(t, m.extent, 64) // where the kept children end
	testing.expect(t, probe_tagged(&p, "b"))
	testing.expect(t, !probe_tagged(&p, "c")) // a dropped child's macro never runs
	testing.expect(t, !probe_tagged(&p, "e"))
	b, more := probe_bounds(&p, "b"), probe_bounds(&p, "more")
	testing.expect_value(t, more.x - b.x, 30 + 4) // the next child follows the last kept

	// A strict prefix: a narrow child after a wide one that missed stays
	// dropped.
	m.widths = {30, 60, 5}
	m.reserve = 10
	probe_frame(&p)
	testing.expect_value(t, m.dropped, 2)
	testing.expect(t, !probe_tagged(&p, "c"))

	// The reserve keeps its gap: a third child ending at 94 would leave
	// 6px for a 6px reserve, but not the 4px gap before it.
	m.widths = {30, 30, 26, 30}
	m.reserve = 6
	probe_frame(&p)
	testing.expect_value(t, m.dropped, 2)
}

@(test)
test_flex_truncate_keeps_the_first_n :: proc(t: ^testing.T) {
	m := Fit_Model{widths = {10, 10, 10}, reserve = 8, n = 1}
	p: Probe
	probe_init(&p, fit_row, &m, {400, 100}, allocator = context.temp_allocator)
	defer probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect(t, probe_tagged(&p, "a"))
	testing.expect(t, !probe_tagged(&p, "b"))
	testing.expect(t, !probe_click(&p, "c"))
	a, more := probe_bounds(&p, "a"), probe_bounds(&p, "more")
	testing.expect_value(t, more.x - a.x, 10 + 4)
	m.n = 0
	probe_frame(&p)
	testing.expect(t, !probe_tagged(&p, "a"))
	testing.expect(t, probe_tagged(&p, "more"))
	testing.expect_value(t, probe_bounds(&p, "more").x, 0)
}

// justify places a row's children in the space they leave over, which
// it takes the whole of: 400px here, for children 3W + 10 wide.
@(test)
test_justify_shares_the_space_over_along_the_main_axis :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	free := 400 - (3 * W + 10)
	cases := [Justify][2]f32 {
		.Start         = {0, 2 * W + 10},
		.Center        = {free / 2, free / 2 + 2 * W + 10},
		.End           = {free, free + 2 * W + 10},
		.Space_Between = {0, 400 - W},
		.Space_Evenly  = {free / 3, 2 * free / 3 + 2 * W + 10},
	}
	for want, j in cases {
		harness_frame(&h)
		gtx := &h.gtx
		{
			outer := column_open(gtx); defer close(&outer)
			r := row_open(gtx, gap = 10, justify = j); defer close(&r)
			label(gtx, "ab")
			label(gtx, "c")
		}
		p := pushes(&h.scene)
		testing.expectf(t, len(p) >= 2, "%v: %d pushes", j, len(p))
		xs := [2]f32{p[len(p) - 2].x, p[len(p) - 1].x}
		testing.expectf(t, testutil.near(xs[0], want[0]) && testutil.near(xs[1], want[1]), "%v: children at %v, want %v", j, xs, want)
	}
}

// A justified column spreads down a bounded height; a lone child in
// Space_Between stays at the start, as in CSS.
@(test)
test_justify_works_down_a_column_and_keeps_a_lone_child_at_the_start :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h, {400, 300})
	defer harness_destroy(&h)
	gtx := &h.gtx
	{
		c := column_open(gtx, justify = .End); defer close(&c)
		label(gtx, "a")
	}
	p := pushes(&h.scene)
	testing.expect_value(t, p[len(p) - 1], ops.Point{0, 300 - 14})

	harness_frame(&h)
	gtx = &h.gtx
	{
		c := column_open(gtx, justify = .Space_Between); defer close(&c)
		label(gtx, "a")
	}
	p = pushes(&h.scene)
	testing.expect_value(t, p[len(p) - 1], ops.Point{0, 0})
}

// A wrap justifies each line on its own: two lines, each centred.
@(test)
test_wrap_justifies_each_line :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h, {100, 300})
	defer harness_destroy(&h)
	gtx := &h.gtx
	{
		w := wrap_open(gtx, gap = 4, justify = .Center); defer close(&w)
		label(gtx, "abcdefghij") // 10W = 84: one per line
		label(gtx, "abc")
	}
	p := pushes(&h.scene)
	testing.expect(t, len(p) >= 2)
	testing.expectf(t, testutil.near(p[len(p) - 2].x, (100 - 10 * W) / 2), "%v", p)
	testing.expectf(t, testutil.near(p[len(p) - 1].x, (100 - 3 * W) / 2), "%v", p)
	testing.expectf(t, testutil.near(p[len(p) - 1].y, 14 + 4), "%v", p)
}

// A recorded run takes no space where it is recorded and is drawn where
// its macro is called; its size is known before that.
@(test)
test_record_measures_a_run_before_it_is_placed :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	gtx := &h.gtx
	m: ops.Macro_Id
	d: Dims
	{
		col := column_open(gtx, gap = 8); defer close(&col)
		r := record_open(gtx, loose({100, 100}))
		label(gtx, "abc")
		label(gtx, "de")
		m, d = record_close(&r)
		testing.expect_value(t, gtx.constraints.max, h.size) // the column's offer is back
		label(gtx, "after")
		ops.transform_push(gtx.scene, ops.translate(50, 60))
		ops.call(gtx.scene, m)
		ops.transform_pop(gtx.scene)
	}
	testing.expect(t, testutil.near(d.size.x, 3 * W))
	testing.expect_value(t, d.size.y, 14) // a recording overlays its children, as a stack
	testing.expect(t, d.baseline > 0)
	frame: Frame
	frame_init(&frame)
	defer frame_destroy(&frame)
	flatten(&h.scene, &frame)
	at := map[string]ops.Rect{}
	defer delete(at)
	for tg in frame.tags {
		at[tg.name] = tg.bounds
	}
	// "after" is the column's first child: at y 0, not below the recording.
	after, has_after := at["after"]
	abc, has_abc := at["abc"]
	testing.expect(t, has_after && has_abc)
	testing.expect_value(t, after.y, 0)
	testing.expect_value(t, abc.x, 50)
	testing.expect_value(t, abc.y, 60)
}

// A recorded widget's semantic node hangs under the node around the
// recording, not at the root; an overlay's still starts at the root.
@(test)
test_record_keeps_the_semantic_parent :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	gtx := &h.gtx
	group: ops.Area_Id
	{
		col := column_open(gtx); defer close(&col)
		container_semantics(gtx, {role = .Group, label = "group"})
		group = innermost(gtx.layout).place.id
		r := record_open(gtx, loose({100, 100}))
		label(gtx, "inside")
		o := overlay_open(gtx)
		label(gtx, "layer")
		close(&o)
		m, _ := record_close(&r)
		ops.call(gtx.scene, m)
	}
	parents := map[string]ops.Area_Id{}
	defer delete(parents)
	for op in h.scene.ops {
		if s, ok := op.(ops.Semantic); ok {
			parents[s.semantics.label] = s.parent
		}
	}
	inside, has_inside := parents["inside"]
	layer, has_layer := parents["layer"]
	testing.expect(t, has_inside && has_layer)
	testing.expect(t, group != 0)
	testing.expect_value(t, inside, group)
	testing.expect_value(t, layer, 0)
}

// offer is what the next widget will be given, in every container kind,
// before it is made: a weighted flex child's share included.
@(test)
test_offer_is_what_the_next_widget_gets :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h, {400, 300})
	defer harness_destroy(&h)
	gtx := &h.gtx
	check :: proc(t: ^testing.T, gtx: ^Ctx, loc := #caller_location) {
		want := offer(gtx)
		p := widget_open(gtx)
		got := gtx.constraints
		widget_close(gtx, &p, {size = {10, 10}})
		testing.expect_value(t, got, want, loc = loc)
	}
	testing.expect_value(t, offer(gtx), gtx.constraints) // at the root
	{
		col := column_open(gtx, align = .Fill); defer close(&col)
		check(t, gtx)
		inner := column_open(gtx); defer close(&inner)
		sz := sized_open(gtx, {max = {120, 0}}); defer close(&sz)
		testing.expect_value(t, offer(gtx).max.x, 120)
		check(t, gtx)
		r := row_open(gtx); defer close(&r)
		check(t, gtx)
		flexible(gtx, 1)
		testing.expect_value(t, offer(gtx).min.x, 120 - 10) // the share beside the 10px child
		check(t, gtx)
	}
}

@(private = "file")
Reveal_Model :: struct {
	reveal: int, // the row that asks to be shown this frame, -1 for none
	align:  Align, // the rows' column: Center records each row in a macro
	nested: bool, // the rows sit in a scroll box inside the outer one
}

@(private = "file")
reveal_row :: proc(gtx: ^Ctx, m: ^Reveal_Model, i: int) {
	p := widget_open(gtx, u64(i + 1))
	if i == m.reveal {
		scroll_into_view(gtx, {0, 0, 50, 30})
	}
	ops.tag(gtx.scene, p.id, fmt_row(gtx, i), {0, 0, 50, 30})
	widget_close(gtx, &p, {size = {50, 30}})
}

@(private = "file")
fmt_row :: proc(gtx: ^Ctx, i: int) -> string {
	names := [10]string{"row 0", "row 1", "row 2", "row 3", "row 4", "row 5", "row 6", "row 7", "row 8", "row 9"}
	return names[i]
}

@(private = "file")
reveal_view :: proc(gtx: ^Ctx, user: rawptr) {
	m := (^Reveal_Model)(user)
	root := column_open(gtx, align = .Start)
	defer close(&root)
	box := sized_open(gtx, {min = {200, 100}, max = {200, 100}})
	defer close(&box)
	sb := scroll_box_open(gtx)
	defer close(&sb)
	col := column_open(gtx, align = m.align)
	defer close(&col)
	if m.nested {
		inner := sized_open(gtx, {min = {0, 60}, max = {0, 60}})
		isb := scroll_box_open(gtx)
		icol := column_open(gtx)
		for i in 0 ..< 10 {
			reveal_row(gtx, m, i)
		}
		close(&icol)
		close(&isb)
		close(&inner)
		return
	}
	for i in 0 ..< 10 {
		reveal_row(gtx, m, i)
	}
}

@(test)
scroll_into_view_scrolls_the_least_that_shows_the_rect :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	m := Reveal_Model{reveal = -1}
	p: Probe
	probe_init(&p, reveal_view, &m, {300, 300})
	defer probe_destroy(&p)

	testing.expect_value(t, probe_bounds(&p, "row 7").y, 210)
	m.reveal = 7
	probe_frame(&p)
	testing.expect_value(t, probe_bounds(&p, "row 7").y, 70) // its bottom at the view's: scrolled 140
	m.reveal = -1
	probe_frame(&p)
	testing.expect_value(t, probe_bounds(&p, "row 7").y, 70) // asked once, it stays
	m.reveal = 5 // already shown: nothing moves
	probe_frame(&p)
	testing.expect_value(t, probe_bounds(&p, "row 7").y, 70)
	m.reveal = 1 // above the view: its top comes to the view's top
	probe_frame(&p)
	testing.expect_value(t, probe_bounds(&p, "row 1").y, 0)
	m.reveal, m.align = 9, .Center // a deferred row, recorded in a macro
	probe_frame(&p)
	testing.expect_value(t, probe_bounds(&p, "row 9").y, 70)
}

@(test)
scroll_into_view_moves_every_box_around_the_rect :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	m := Reveal_Model{reveal = 8, nested = true}
	p: Probe
	probe_init(&p, reveal_view, &m, {300, 300})
	defer probe_destroy(&p)

	// The inner 60px box scrolls row 8 to its bottom; the outer one has
	// nothing to move, as the inner box fits in it.
	testing.expect_value(t, probe_bounds(&p, "row 8").y, 30)
}

// A 100 px tall box over 1000 px of content, a tagged strip at its top
// for the probe to drag, and a button lower down.
@(private = "file")
Drag_Scroll_Model :: struct {
	offset:  Scroll_Offset,
	drag:    bool,
	clicked: int,
}

@(private = "file")
TALL :: f32(1000)

@(private = "file")
drag_scroll_view :: proc(gtx: ^Ctx, user: rawptr) {
	m := (^Drag_Scroll_Model)(user)
	sb := scroll_box_open(gtx, offset = &m.offset, drag_scroll = m.drag)
	defer close(&sb)
	col := column_open(gtx)
	defer close(&col)
	strip := widget_open(gtx, 1)
	ops.tag(gtx.scene, strip.id, "strip", {0, 0, 200, 20})
	widget_close(gtx, &strip, {size = {200, 20}})
	b := widget_open(gtx, 2)
	ops.input_area(gtx.scene, b.id, ops.Rect{0, 0, 200, 20}, {.Press, .Release, .Move})
	ops.tag(gtx.scene, b.id, "button")
	for e in events(gtx, b.id) {
		if e.kind == .Release {
			m.clicked += 1
		}
	}
	widget_close(gtx, &b, {size = {200, 20}})
	spacer(gtx, TALL - 40)
}

@(private = "file")
open :: proc(p: ^Probe, m: ^Drag_Scroll_Model) {
	probe_init(p, drag_scroll_view, m, {200, 100})
}

@(private = "file")
settle :: proc(p: ^Probe) -> int {
	frames := 0
	for p.wants_frame && frames < 600 {
		probe_frame(p)
		frames += 1
	}
	return frames
}

@(test)
drag_scroll_is_off_unless_asked_for :: proc(t: ^testing.T) {
	m: Drag_Scroll_Model
	p: Probe
	open(&p, &m)
	defer probe_destroy(&p)
	testing.expect(t, probe_drag(&p, "strip", 0, -60, steps = 30))
	testing.expect_value(t, m.offset.y, 0)
}

@(test)
drag_scroll_follows_a_slow_drag_and_stays :: proc(t: ^testing.T) {
	m := Drag_Scroll_Model{drag = true}
	p: Probe
	open(&p, &m)
	defer probe_destroy(&p)
	// 60 px over half a second: 120 px/s, and the last move stops short
	// of the release by a frame, so it glides only a little.
	testing.expect(t, probe_drag(&p, "strip", 0, -60, steps = 30))
	testing.expect_value(t, m.offset.y, 60)
	settle(&p)
	testing.expect(t, m.offset.y >= 60 && m.offset.y < 60 + 120 / -SLING_DECAY + 1)
}

@(test)
drag_scroll_slings_a_fast_release_and_stops :: proc(t: ^testing.T) {
	m := Drag_Scroll_Model{drag = true}
	p: Probe
	open(&p, &m)
	defer probe_destroy(&p)
	// 80 px in four frames: 1200 px/s, which glides 1200 / -k further.
	testing.expect(t, probe_drag(&p, "strip", 0, -80, steps = 4))
	testing.expect_value(t, m.offset.y, 80)
	testing.expect(t, p.wants_frame)
	frames := settle(&p)
	want := 80 + 1200 / -SLING_DECAY
	testing.expectf(t, abs(m.offset.y - want) < 2, "glided to %v, want %v", m.offset.y, want)
	testing.expect(t, frames > 30 && !p.wants_frame)
}

@(test)
drag_scroll_sling_stops_at_the_edge :: proc(t: ^testing.T) {
	m := Drag_Scroll_Model{drag = true}
	p: Probe
	open(&p, &m)
	defer probe_destroy(&p)
	// 150 px a frame is past SLING_MAX, which glides further than the 600
	// px left whatever the decay.
	testing.expect(t, probe_drag(&p, "strip", 0, -300, steps = 2))
	s := box_sling(&p)
	testing.expect(t, s != nil && sling_active(s))
	for _ in 0 ..< 60 {
		probe_frame(&p)
		if m.offset.y == TALL - 100 {
			break
		}
	}
	testing.expect_value(t, m.offset.y, TALL - 100)
	testing.expect(t, !sling_active(s)) // it ended at the edge, still fast
}

// box_sling is the scroll box's Sling, the only one the view keeps.
@(private = "file")
box_sling :: proc(p: ^Probe) -> ^Sling {
	for k, v in p.layout.data {
		if k.type == Sling {
			return (^Sling)(v.ptr)
		}
	}
	return nil
}

@(test)
drag_scroll_press_stops_a_glide_and_children_keep_theirs :: proc(t: ^testing.T) {
	m := Drag_Scroll_Model{drag = true}
	p: Probe
	open(&p, &m)
	defer probe_destroy(&p)
	testing.expect(t, probe_drag(&p, "strip", 0, -20, steps = 2)) // 600 px/s
	probe_frame(&p)
	gliding := m.offset.y
	testing.expect(t, gliding > 20)
	// A press on the box's own area (the gap below the button) stops it.
	router_push(&p.router, {kind = .Move, pos = {100, 90}})
	router_push(&p.router, {kind = .Press, pos = {100, 90}, button = .Left})
	probe_frame(&p)
	held := m.offset.y
	probe_advance(&p, 30, 1.0 / 60)
	testing.expect_value(t, m.offset.y, held)
	router_push(&p.router, {kind = .Release, pos = {100, 90}, button = .Left})
	probe_frame(&p)
	// The button above the box's area still takes its own press.
	m.offset.y = 0
	probe_frame(&p)
	testing.expect(t, probe_click(&p, "button"))
	testing.expect_value(t, m.clicked, 1)
	testing.expect_value(t, m.offset.y, 0)
}
