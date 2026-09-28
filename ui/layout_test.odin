package ui

import "core:testing"
import "jm:ui/testutil"

// Harness is one window's worth of ui state for tests: ops, layout, router
// and a light theme, over the stub shaper and the temp allocator.
@(private)
Harness :: struct {
	ops:    Ops,
	layout: Layout,
	router: Router,
	theme:  Theme,
	gtx:    Ctx,
	size:   Size,
}

@(private)
harness_init :: proc(h: ^Harness, size := Size{400, 300}) {
	ops_init(&h.ops)
	layout_init(&h.layout)
	router_init(&h.router)
	h.theme = light_theme(0)
	h.size = size
	harness_frame(h)
}

// harness_frame starts a frame: empty ops, a fresh layout frame, root
// constraints loose up to the window size. Router events are left alone so
// a test can push them first.
@(private)
harness_frame :: proc(h: ^Harness) {
	ops_reset(&h.ops)
	layout_reset(&h.layout)
	h.gtx = {
		ops         = &h.ops,
		constraints = loose(h.size),
		theme       = &h.theme,
		shaper      = stub_shaper(),
		router      = &h.router,
		layout      = &h.layout,
		allocator   = context.temp_allocator,
	}
}

@(private)
harness_destroy :: proc(h: ^Harness) {
	ops_destroy(&h.ops)
	layout_destroy(&h.layout)
	router_destroy(&h.router)
	free_all(context.temp_allocator)
}

@(private)
near :: proc(a, b: f32) -> bool {
	return abs(a - b) < 1e-3
}

// pushes lists the translation of every Push_Transform, in order.
@(private)
pushes :: proc(o: ^Ops) -> [dynamic]Point {
	out := make([dynamic]Point, context.temp_allocator)
	for op in o.ops {
		if t, ok := op.(Push_Transform); ok {
			append(&out, Point{f32(t.m.e), f32(t.m.f)})
		}
	}
	return out
}

@(private)
index_of :: proc(o: ^Ops, $T: typeid, from := 0) -> int {
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
		col := column(gtx, gap = 8); defer end(&col)
		label(gtx, "Name")
		label(gtx, "Ada")
	}
	p := pushes(&h.ops)
	testing.expect_value(t, len(p), 2)
	testing.expect_value(t, p[0], Point{0, 0})
	testing.expect_value(t, p[1], Point{0, 14 + 8})
	testing.expect_value(t, testutil.count_ops(h.ops.ops[:], Pop_Transform), 2)
	testing.expect_value(t, testutil.count_ops(h.ops.ops[:], Glyphs), 2)
	testing.expect_value(t, testutil.count_ops(h.ops.ops[:], Macro_Begin), 0)
}

@(test)
test_row_advances_on_x :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	gtx := &h.gtx
	{
		r := row(gtx, gap = 4); defer end(&r)
		label(gtx, "ab")
		label(gtx, "c")
	}
	p := pushes(&h.ops)
	testing.expect_value(t, len(p), 2)
	testing.expect(t, near(p[1].x, 2 * W + 4))
	testing.expect_value(t, p[1].y, 0)
}

@(test)
test_inset_offsets_by_padding :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	gtx := &h.gtx
	{
		col := column(gtx); defer end(&col)
		{
			in_ := inset(gtx, {10, 20, 30, 40}); defer end(&in_)
			label(gtx, "x")
		}
		label(gtx, "after")
	}
	// column child 0 (the inset), inset child, column child 1.
	p := pushes(&h.ops)
	testing.expect_value(t, len(p), 3)
	testing.expect_value(t, p[0], Point{0, 0})
	testing.expect_value(t, p[1], Point{10, 20})
	testing.expect_value(t, p[2], Point{0, 20 + 14 + 40})
}

@(test)
test_box_records_macro_then_fill_then_call :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	gtx := &h.gtx
	{
		b := box(gtx); defer end(&b)
		label(gtx, "card")
	}
	begin := index_of(&h.ops, Macro_Begin)
	finish := index_of(&h.ops, Macro_End)
	paint := index_of(&h.ops, Fill)
	outline := index_of(&h.ops, Stroke)
	run := index_of(&h.ops, Call)
	testing.expect(
		t,
		begin >= 0 && begin < finish && finish < paint && paint < outline && outline < run,
	)
	f := h.ops.ops[paint].(Fill)
	rr := f.shape.(Round_Rect)
	testing.expect(t, near(rr.rect.w, 4 * W + 16))
	testing.expect(t, near(rr.rect.h, 14 + 16))
	testing.expect_value(t, rr.radius, h.theme.radius)
	testing.expect_value(t, f.paint.(Color), h.theme.surface)
	testing.expect_value(t, h.ops.ops[begin].(Macro_Begin).id, h.ops.ops[run].(Call).id)
	// The label inside is offset by the padding.
	p := pushes(&h.ops)
	testing.expect_value(t, p[0], Point{8, 8})
}

@(test)
test_align_center_offsets_narrow_child :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	gtx := &h.gtx
	{
		col := column(gtx, align = .Center); defer end(&col)
		label(gtx, "i")
		label(gtx, "wide")
	}
	// Both children are macros placed at end: narrow first, then wide.
	testing.expect_value(t, testutil.count_ops(h.ops.ops[:], Macro_Begin), 2)
	testing.expect_value(t, testutil.count_ops(h.ops.ops[:], Call), 2)
	p := pushes(&h.ops)
	testing.expect_value(t, len(p), 2)
	testing.expect(t, near(p[0].x, (4 * W - W) / 2))
	testing.expect_value(t, p[0].y, 0)
	testing.expect_value(t, p[1], Point{0, 14})
	// Each push wraps a call.
	first := index_of(&h.ops, Push_Transform)
	_, is_call := h.ops.ops[first + 1].(Call)
	testing.expect(t, is_call)
}

@(test)
test_align_end_and_fill :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h, {200, 100})
	defer harness_destroy(&h)
	gtx := &h.gtx
	{
		col := column(gtx, align = .End); defer end(&col)
		label(gtx, "i")
		label(gtx, "wide")
	}
	p := pushes(&h.ops)
	testing.expect(t, near(p[0].x, 3 * W))

	harness_frame(&h)
	gtx = &h.gtx
	{
		col := column(gtx, align = .Fill); defer end(&col)
		d := divider(gtx)
		testing.expect_value(t, d.size, Size{200, 1})
	}
	testing.expect_value(t, testutil.count_ops(h.ops.ops[:], Macro_Begin), 0)
}

@(test)
test_weighted_child_gets_remaining_space :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h, {300, 50})
	defer harness_destroy(&h)
	gtx := &h.gtx
	{
		r := row(gtx, gap = 10); defer end(&r)
		label(gtx, "ab")
		flexible(gtx, 1)
		d := label(gtx, "x")
		testing.expect(t, near(d.size.x, 300 - 2 * W - 10))
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
		r := row(gtx)
		flexible(gtx, 1)
		sizes[frame] = label(gtx, "x").size.x
		label(gtx, "abcd")
		end(&r)
	}
	// Frame 1 cannot know the rigid child after it; frame 2 uses frame 1's.
	testing.expect(t, near(sizes[0], 300))
	testing.expect(t, near(sizes[1], 300 - 4 * W))
}

@(test)
test_fill_space_pushes_the_rest_to_the_end :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h, {300, 50})
	defer harness_destroy(&h)
	gtx := &h.gtx
	{
		r := row(gtx); defer end(&r)
		label(gtx, "a")
		fill_space(gtx)
		label(gtx, "bc")
	}
	// "a" is placed directly; "bc" after the slot is a macro placed at end.
	p := pushes(&h.ops)
	testing.expect_value(t, len(p), 2)
	testing.expect_value(t, p[0], Point{0, 0})
	testing.expect(t, near(p[1].x, 300 - 2 * W))
	testing.expect_value(t, testutil.count_ops(h.ops.ops[:], Macro_Begin), 1)
}

@(test)
test_stack_clip_and_centered :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h, {100, 60})
	defer harness_destroy(&h)
	gtx := &h.gtx
	{
		c := clip_box(gtx); defer end(&c)
		label(gtx, "clip")
	}
	i := index_of(&h.ops, Push_Clip)
	testing.expect(t, i > index_of(&h.ops, Macro_End))
	r := h.ops.ops[i].(Push_Clip).shape.(Rect)
	testing.expect(t, near(r.w, 4 * W) && near(r.h, 14))

	harness_frame(&h)
	gtx = &h.gtx
	{
		c := centered(gtx); defer end(&c)
		label(gtx, "ab")
	}
	p := pushes(&h.ops)
	testing.expect_value(t, len(p), 1)
	testing.expect(t, near(p[0].x, (100 - 2 * W) / 2) && near(p[0].y, (60 - 14) / 2.0))

	harness_frame(&h)
	gtx = &h.gtx
	{
		col := column(gtx); defer end(&col)
		{
			s := stack(gtx); defer end(&s)
			label(gtx, "abc")
			label(gtx, "a")
		}
		label(gtx, "below")
	}
	p = pushes(&h.ops)
	testing.expect_value(t, len(p), 2) // stack children sit at the origin, unpushed
	testing.expect_value(t, p[1], Point{0, 14})
}

@(test)
test_spacer_and_nesting :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	gtx := &h.gtx
	{
		col := column(gtx); defer end(&col)
		{
			r := row(gtx); defer end(&r)
			label(gtx, "a")
			spacer(gtx, 20)
			label(gtx, "b")
		}
		label(gtx, "c")
	}
	p := pushes(&h.ops)
	// col child 0 (row), a, spacer, b, col child 1.
	testing.expect_value(t, len(p), 5)
	testing.expect(t, near(p[3].x, W + 20))
	testing.expect_value(t, p[4], Point{0, 14})
}

@(test)
test_nil_layout_places_at_origin :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	gtx := &h.gtx
	gtx.layout = nil
	{
		col := column(gtx, gap = 8); defer end(&col)
		label(gtx, "a")
		label(gtx, "b")
	}
	testing.expect_value(t, testutil.count_ops(h.ops.ops[:], Push_Transform), 0)
	testing.expect_value(t, testutil.count_ops(h.ops.ops[:], Glyphs), 2)
}

@(test)
test_state_is_pruned_after_a_frame_unseen :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	button(&h.gtx, "a")
	testing.expect_value(t, len(h.layout.state), 1)
	harness_frame(&h)
	testing.expect_value(t, len(h.layout.state), 1)
	harness_frame(&h)
	testing.expect_value(t, len(h.layout.state), 0)
}

@(test)
test_id_is_stable_per_site_and_key :: proc(t: ^testing.T) {
	ids: [3]Area_Id
	for i in 0 ..< 2 {
		ids[i] = id()
	}
	ids[2] = id(7)
	testing.expect_value(t, ids[0], ids[1])
	testing.expect(t, ids[0] != ids[2])
	testing.expect(t, id() != ids[0])
	testing.expect(t, id_mix(ids[0], 1) != id_mix(ids[0], 2))
}

@(test)
test_style_zero_means_theme :: proc(t: ^testing.T) {
	th := light_theme(0)
	b := resolve_button(&th, {})
	testing.expect_value(t, b.fill, th.accent)
	testing.expect_value(t, b.text, th.on_accent)
	testing.expect_value(t, b.radius, f32(0)) // unresolved here; button() defaults it to a pill from the measured height
	testing.expect_value(t, b.padding, Padding{12, 6, 12, 6})
	o := resolve_button(&th, {fill = th.danger, radius = -1})
	testing.expect_value(t, o.fill, th.danger)
	testing.expect_value(t, o.text, th.on_accent)
	testing.expect_value(t, o.radius, f32(-1)) // resolve_button passes radius through untouched; button() turns negative into exactly 0
	tonal := resolve_button(&th, {kind = .Tonal})
	testing.expect_value(t, tonal.fill, th.secondary_container)
	testing.expect_value(t, tonal.text, th.on_secondary_container)
	outlined := resolve_button(&th, {kind = .Outlined})
	testing.expect_value(t, outlined.fill, CLEAR)
	testing.expect_value(t, outlined.outline, th.outline)
	testing.expect_value(t, outlined.text, th.accent)
	l := resolve_label(&th, {size = th.heading_size})
	testing.expect_value(t, l.color, th.fg)
	testing.expect_value(t, l.size, f32(20))
	d := dark_theme(0)
	testing.expect(t, d.bg != th.bg)
	testing.expect_value(t, default_theme(0), th)
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
// returns the box's input area.
@(private)
scroll_frame :: proc(h: ^Harness) -> Input_Area {
	gtx := &h.gtx
	{
		sb := scroll_box(gtx); defer end(&sb)
		col := column(gtx); defer end(&col)
		spacer(gtx, 300)
		label(gtx, "last")
	}
	return h.ops.ops[index_of(&h.ops, Input_Area)].(Input_Area)
}

// scroll_offset is the y of the transform scroll_box pushes right after its
// clip (the body's own transforms come earlier, inside its macro).
@(private)
scroll_offset :: proc(h: ^Harness) -> f64 {
	i := index_of(&h.ops, Push_Clip)
	return h.ops.ops[i + 1].(Push_Transform).m.f
}

@(test)
test_scroll_box_clips_to_viewport_and_scrolls :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h, {200, 100})
	defer harness_destroy(&h)
	ia := scroll_frame(&h)
	testing.expect_value(t, ia.kinds, Event_Kinds{.Scroll})
	clip := h.ops.ops[index_of(&h.ops, Push_Clip)].(Push_Clip)
	testing.expect_value(t, clip.shape.(Rect).h, 100) // the offered height, not the content's
	testing.expect_value(t, scroll_offset(&h), 0)

	// One unit of scroll moves SCROLL_STEP pixels.
	harness_frame(&h)
	push_event(&h, {kind = .Scroll, area = ia.id, scroll = {0, 1}})
	scroll_frame(&h)
	testing.expect_value(t, scroll_offset(&h), f64(-SCROLL_STEP))

	// Scrolling past the end clamps to the overflow: 300 + 14 - 100.
	clear(&h.router.events)
	harness_frame(&h)
	push_event(&h, {kind = .Scroll, area = ia.id, scroll = {0, 1e6}})
	scroll_frame(&h)
	testing.expect_value(t, scroll_offset(&h), -(300 + 14 - 100))
}

// wide_scroll_frame lays a scroll_box with min_width 500 over a 500px
// wide, 300px tall column in h's 200x100 window.
@(private)
wide_scroll_frame :: proc(h: ^Harness) -> Input_Area {
	gtx := &h.gtx
	{
		sb := scroll_box(gtx, min_width = 500); defer end(&sb)
		col := column(gtx); defer end(&col)
		spacer(gtx, 300)
	}
	return h.ops.ops[index_of(&h.ops, Input_Area)].(Input_Area)
}

@(test)
test_scroll_box_min_width_scrolls_sideways :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h, {200, 100})
	defer harness_destroy(&h)
	ia := wide_scroll_frame(&h)
	clip := h.ops.ops[index_of(&h.ops, Push_Clip)].(Push_Clip)
	testing.expect_value(t, clip.shape.(Rect).w, 200) // the box stays the window's width
	x_offset :: proc(h: ^Harness) -> f64 {
		return h.ops.ops[index_of(&h.ops, Push_Clip) + 1].(Push_Transform).m.e
	}
	testing.expect_value(t, x_offset(&h), 0)

	// A horizontal wheel moves it sideways; Shift turns a vertical one.
	harness_frame(&h)
	push_event(&h, {kind = .Scroll, area = ia.id, scroll = {1, 0}})
	wide_scroll_frame(&h)
	testing.expect_value(t, x_offset(&h), f64(-SCROLL_STEP))
	testing.expect_value(t, scroll_offset(&h), 0)
	clear(&h.router.events)
	harness_frame(&h)
	push_event(&h, {kind = .Scroll, area = ia.id, scroll = {0, 1}, mods = {.Shift}})
	wide_scroll_frame(&h)
	testing.expect_value(t, x_offset(&h), f64(-2 * SCROLL_STEP))
	testing.expect_value(t, scroll_offset(&h), 0)

	// It clamps to the overflow: 500 - 200.
	clear(&h.router.events)
	harness_frame(&h)
	push_event(&h, {kind = .Scroll, area = ia.id, scroll = {1e6, 0}})
	wide_scroll_frame(&h)
	testing.expect_value(t, x_offset(&h), -300)
}

@(test)
test_box_paint_replaces_fill_and_outline :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	gtx := &h.gtx
	got: Size
	painter :: proc(gtx: ^Ctx, id: Area_Id, size: Size, user: rawptr) {
		(^Size)(user)^ = size
		fill(gtx.ops, Rect{0, 0, size.x, size.y}, Color{1, 2, 3, 255})
	}
	{
		b := box(gtx, {paint = painter, user = &got}); defer end(&b)
		label(gtx, "card")
	}
	testing.expect(t, near(got.x, 4 * W + 16) && near(got.y, 14 + 16))
	testing.expect_value(t, testutil.count_ops(h.ops.ops[:], Stroke), 0)
	f := h.ops.ops[index_of(&h.ops, Fill)].(Fill)
	testing.expect_value(t, f.paint.(Color), Color{1, 2, 3, 255})
	// The paint runs under the body.
	testing.expect(t, index_of(&h.ops, Fill) < index_of(&h.ops, Call))
}

@(test)
test_negative_padding_means_none :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	gtx := &h.gtx
	{
		b := box(gtx, {padding = pad_all(-1)}); defer end(&b)
		label(gtx, "card")
	}
	rr := h.ops.ops[index_of(&h.ops, Fill)].(Fill).shape.(Round_Rect)
	testing.expect(t, near(rr.rect.w, 4 * W) && near(rr.rect.h, 14))
	testing.expect_value(t, len(pushes(&h.ops)), 0) // no offset for the body
}

@(test)
test_overlay_takes_no_space_and_draws_last :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	gtx := &h.gtx
	{
		col := column(gtx); defer end(&col)
		label(gtx, "before")
		{
			o := overlay(gtx, {5, 6}); defer end(&o)
			inner := column(gtx); defer end(&inner)
			label(gtx, "menu")
		}
		label(gtx, "after")
	}
	// "after" sits right below "before": the overlay took no space.
	p := pushes(&h.ops)
	testing.expect_value(t, p[len(p) - 1], Point{0, 14})
	testing.expect_value(t, testutil.count_ops(h.ops.ops[:], Defer), 1)

	f: Frame
	frame_init(&f, context.temp_allocator)
	flatten(&h.ops, &f)
	names := make([dynamic]string, context.temp_allocator)
	for tg in f.tags {
		append(&names, tg.name)
	}
	testing.expect_value(t, names[len(names) - 1], "menu")
	// At `at` from the enclosing column's origin, not from a slot in it.
	last := f.draws[len(f.draws) - 1]
	testing.expect_value(t, apply(last.transform, {0, 0}), Point{5, 6})
}

@(test)
test_discarded_overlay_is_never_drawn :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	gtx := &h.gtx
	{
		o := overlay(gtx); defer end(&o)
		label(gtx, "gone")
		o.discard = true
	}
	testing.expect_value(t, testutil.count_ops(h.ops.ops[:], Defer), 0)
	f: Frame
	frame_init(&f, context.temp_allocator)
	flatten(&h.ops, &f)
	testing.expect_value(t, len(f.draws), 0)
}
