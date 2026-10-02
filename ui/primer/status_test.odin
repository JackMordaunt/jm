package primer

import "core:strings"
import "core:testing"
import "jm:ui"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// Behaviour of the progress, skeleton and avatar components.

@(private = "file")
near :: proc(a, b: f32) -> bool {
	return abs(a - b) < 1e-3
}

@(test)
test_shimmer_stops_follow_the_mask_sweep :: proc(t: ^testing.T) {
	gtx := ui.Ctx{allocator = context.temp_allocator}
	defer free_all(context.temp_allocator)
	c := ops.Color{0, 0, 0, 200}
	// At the start of a sweep the box shows the tile's first half: opaque
	// to 0.6 of the width (u 0.3), then falling to g(0.5) = 0.86.
	s := shimmer_stops(&gtx, c, 0)
	testing.expect_value(t, len(s), 3)
	testing.expect(t, s[0].t == 0 && s[0].color[3] == 200)
	testing.expect(t, near(s[1].t, 0.6) && s[1].color[3] == 200)
	testing.expect(t, s[2].t == 1 && s[2].color[3] == 172) // 200 x 0.86
	// Half way, the second half: g(0.5) at the left, the 0.65 floor from
	// 0.6 on, and the seam on the right edge, taken from its left.
	s = shimmer_stops(&gtx, c, 0.5)
	testing.expect_value(t, len(s), 3)
	testing.expect_value(t, s[0].color[3], 172)
	testing.expect(t, near(s[1].t, 0.6) && s[1].color[3] == 130) // 200 x 0.65
	testing.expect_value(t, s[2].color[3], 130)
	// A seam inside the box is a hard edge: two stops at one offset.
	s = shimmer_stops(&gtx, c, 0.25)
	seams := 0
	for i in 1 ..< len(s) {
		if s[i].t == s[i - 1].t {
			seams += 1
			testing.expect_value(t, s[i - 1].color[3], 130)
			testing.expect_value(t, s[i].color[3], 200)
		}
		testing.expect(t, s[i].t >= s[i - 1].t) // ascending
	}
	testing.expect_value(t, seams, 1)
	testing.expect_value(t, shimmer_alpha(0.55), 0.825)
}

@(private = "file")
Loading :: struct {
	segments: []Progress_Item,
}

@(private = "file")
loading_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Loading)(user)
	col := ui.column_open(gtx, gap = 8)
	defer ui.close(&col)
	skeleton_box(gtx, 100, key = 1)
	sz := ui.sized_open(gtx, {max = {200, 0}})
	skeleton_text(gtx, key = 2)
	skeleton_text(gtx, .Body_Medium, 4, key = 3)
	progress_bar(gtx, 50, label = "Half", key = 4)
	progress_bar(gtx, -10, label = "Negative", key = 5)
	progress_bar_items(gtx, m.segments, .Large, key = 6)
	ui.close(&sz)
}

@(private = "file")
count_gradient_fills :: proc(p: ^ui.Probe) -> (n: int) {
	for op in p.scene.ops {
		if f, ok := op.(ops.Fill); ok {
			if _, g := f.paint.(ops.Linear_Gradient); g {
				n += 1
			}
		}
	}
	return
}

@(test)
test_skeletons_shimmer_unless_motion_is_reduced :: proc(t: ^testing.T) {
	m: Loading
	p: ui.Probe
	ui.probe_init(&p, loading_view, &m, {400, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect_value(t, count_gradient_fills(&p), 1 + 1 + 4) // a box, a line, four lines
	testing.expect(t, p.wants_frame)
	p.reduce_motion = true
	ui.probe_frame(&p)
	testing.expect_value(t, count_gradient_fills(&p), 0)
	testing.expect(t, !p.wants_frame) // nothing moves: no frames asked
	testing.expect_value(t, fills_of(&p, color(.Skeleton_Loader_Bg_Color)), 6)
}

@(test)
test_skeleton_text_sits_bars_in_line_boxes :: proc(t: ^testing.T) {
	m: Loading
	p: ui.Probe
	ui.probe_init(&p, loading_view, &m, {400, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	// Body medium: a 14px bar in a 21px line, leading 7.
	one := ui.probe_bounds(&p, "skeleton text")
	testing.expect_value(t, one.h, 21)
	testing.expect_value(t, one.w, 200)
	testing.expect_value(t, ui.probe_bounds(&p, "skeleton").h, 16) // a box's default height
	p.reduce_motion = true
	ui.probe_frame(&p)
	bars: [dynamic]ops.Rect
	bars.allocator = context.temp_allocator
	for op in p.scene.ops {
		if f, ok := op.(ops.Fill); ok {
			if rr, isrr := f.shape.(ops.Round_Rect); isrr && rr.rect.h == 14 {
				append(&bars, rr.rect)
			}
		}
	}
	testing.expect_value(t, len(bars), 5)
	testing.expect_value(t, bars[0].y, 3.5) // L / 2 down its line box
	// Four lines: 3.5 down, 14px bars 2L = 14px apart, the last 65% wide.
	for i in 1 ..< 4 {
		testing.expect_value(t, bars[i].y - bars[1].y, f32(i - 1) * 28)
	}
	testing.expect_value(t, bars[4].y - bars[1].y, 3 * 28)
	testing.expect_value(t, bars[4].w, 200 * 0.65)
	testing.expect_value(t, bars[1].w, 200)
}

@(test)
test_progress_segments_take_their_share_of_the_track :: proc(t: ^testing.T) {
	segs := []Progress_Item{{40, .Bg_Color_Success_Emphasis, "Done"}, {25, .Bg_Color_Danger_Emphasis, "Failed"}}
	m := Loading{segs}
	p: ui.Probe
	ui.probe_init(&p, loading_view, &m, {400, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	half := ui.probe_bounds(&p, "Half")
	testing.expect_value(t, half.h, 8)
	testing.expect_value(t, half.w, 200)
	danger := color(.Bg_Color_Danger_Emphasis)
	found := false
	for op in p.scene.ops {
		f, ok := op.(ops.Fill)
		if !ok {
			continue
		}
		got, solid := f.paint.(ops.Color)
		if r, isr := f.shape.(ops.Rect); isr && solid && got == danger {
			found = true
			testing.expect_value(t, r.x, 200 * 0.4 + PROGRESS_GAP) // after the first, 2px on
			testing.expect_value(t, r.w, 200 * 0.25)
			testing.expect_value(t, r.h, 10)
		}
	}
	testing.expect(t, found)
	sem := ui.probe_semantics(&p, context.temp_allocator)
	testing.expectf(t, strings.contains(sem, `"50%"`), "the value is the rounded percent: %s", sem)
	testing.expectf(t, strings.contains(sem, `"0%"`), "a negative progress reads 0: %s", sem)
	testing.expectf(t, strings.contains(sem, `"Failed"`), "each segment is its own progressbar: %s", sem)
}

@(test)
test_avatar_corners_and_stack_widths_follow_the_css :: proc(t: ^testing.T) {
	testing.expect_value(t, avatar_radius(20, false), 10)
	testing.expect_value(t, avatar_radius(28, true), 4)
	testing.expect_value(t, avatar_radius(29, true), 5)
	testing.expect_value(t, avatar_radius(30, true), tok.BORDER_RADIUS_MEDIUM)
	testing.expect_value(t, avatar_radius(64, true), tok.BORDER_RADIUS_MEDIUM)
	// Cascade: 55% then 85% overlap; the fifth's end is reserved.
	testing.expect_value(t, stack_width(.Cascade, 1, 20), 20)
	testing.expect_value(t, stack_width(.Cascade, 2, 20), 20 + 9)
	testing.expect_value(t, stack_width(.Cascade, 5, 20), 20 + 9 + 3 * 3)
	testing.expect_value(t, stack_width(.Cascade, 9, 20), 20 + 9 + 3 * 3) // five at most
	testing.expect_value(t, stack_width(.Stack, 4, 20), 20 + 3 * 9)
	testing.expect_value(t, stack_width(.Stack, 0, 20), 0)
	testing.expect_value(t, stack_opacity(.Cascade, 2), 0.7)
	testing.expect(t, near(stack_opacity(.Cascade, 4), 0.4))
	testing.expect_value(t, stack_opacity(.Stack, 4), 1)
}

@(private = "file")
Stacks :: struct {
	avatars: []Avatar_Source,
	disable: bool,
}

@(private = "file")
stacks_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Stacks)(user)
	col := ui.column_open(gtx, gap = 8)
	defer ui.close(&col)
	avatar_stack(gtx, m.avatars, disable_expand = m.disable)
}

@(private = "file")
STACK := []Avatar_Source{{"a.png", "@a"}, {"b.png", "@b"}, {"c.png", "@c"}, {"d.png", "@d"}, {"e.png", "@e"}, {"f.png", "@f"}}

// image_alphas is each Image op's alpha, in drawing order.
@(private = "file")
image_alphas :: proc(p: ^ui.Probe) -> (alphas: [dynamic]u8) {
	alphas.allocator = context.temp_allocator
	for op in p.scene.ops {
		if im, ok := op.(ops.Image); ok {
			append(&alphas, im.alpha)
		}
	}
	return
}

@(test)
test_a_cascade_fades_cuts_and_fans_out_on_hover :: proc(t: ^testing.T) {
	m := Stacks{STACK, false}
	p: ui.Probe
	ui.probe_init(&p, stacks_view, &m, {400, 200}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	// Five drawn, last first: 40, 55, 70%, then the first two opaque.
	testing.expect_value(t, len(image_alphas(&p)), 5)
	al := image_alphas(&p)
	testing.expect(t, al[0] == 102 && al[1] == 140 && al[2] == 179 && al[3] == 255 && al[4] == 255)
	cuts := 0
	for op in p.scene.ops {
		if c, ok := op.(ops.Push_Clip); ok {
			if _, path := c.shape.(ops.Path_Ref); path {
				cuts += 1
			}
		}
	}
	testing.expect_value(t, cuts, 4) // every avatar after the first
	sem := ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(t, !strings.contains(sem, `"@f"`)) // the sixth is hidden

	// Hovered, it fans out over 200ms to every avatar at full opacity.
	box := ui.probe_bounds(&p, "avatar stack")
	ui.probe_move(&p, box.x + 5, box.y + box.h / 2)
	ui.probe_frame(&p)
	testing.expect(t, p.wants_frame) // moving
	ui.probe_advance(&p, 15, 1.0 / 60)
	testing.expect_value(t, len(image_alphas(&p)), 6)
	for a in image_alphas(&p) {
		testing.expect_value(t, a, 255)
	}
	testing.expect(t, !p.wants_frame) // settled
	sem = ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(t, strings.contains(sem, `"@f"`))
	// Fanned out, the pointer stays over it past its resting width.
	ui.probe_move(&p, box.x + 5 * 24 + 10, box.y + box.h / 2)
	ui.probe_advance(&p, 15, 1.0 / 60)
	testing.expect_value(t, len(image_alphas(&p)), 6)
	// Away, it folds back.
	ui.probe_move(&p, 390, 190)
	ui.probe_advance(&p, 15, 1.0 / 60)
	testing.expect_value(t, len(image_alphas(&p)), 5)
}

@(test)
test_a_stack_with_expand_disabled_stays_folded :: proc(t: ^testing.T) {
	m := Stacks{STACK[:3], true}
	p: ui.Probe
	ui.probe_init(&p, stacks_view, &m, {400, 200}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	box := ui.probe_bounds(&p, "avatar stack")
	testing.expect_value(t, box.w, stack_width(.Cascade, 3, AVATAR_SIZE))
	ui.probe_move(&p, box.x + 5, box.y + box.h / 2)
	ui.probe_advance(&p, 15, 1.0 / 60)
	al := image_alphas(&p)
	testing.expect_value(t, al[0], 179) // the third still at 70%
	testing.expect(t, !p.wants_frame)
}
