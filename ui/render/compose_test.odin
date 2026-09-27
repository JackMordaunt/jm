package render

import "core:fmt"
import "core:mem"
import "core:testing"

import "jm:ui"
import bl "jm:ui/blend2d"

@(private = "file")
BG :: ui.Color{240, 240, 244, 255}
@(private = "file")
CW :: 320
@(private = "file")
CH :: 256

// Scene is a Frame with one draw per card plus a card under a rotated
// round-rect clip; moved shifts one card and turns the clip.
@(private = "file")
Scene :: struct {
	ops:   ui.Ops,
	frame: ui.Frame,
}

@(private = "file")
scene_build :: proc(s: ^Scene, moved: bool) {
	ui.ops_reset(&s.ops)
	ui.frame_reset(&s.frame)
	s.frame.ops = &s.ops
	append(&s.frame.draws, ui.Draw{ui.IDENTITY, ui.NO_CLIP, ui.Fill{ui.Rect{0, 0, CW, CH}, BG}})
	for i in 0 ..< 20 {
		x, y := f32(i % 5) * 60 + 10, f32(i / 5) * 60 + 10
		if moved && i == 7 {
			x += 23
		}
		col := ui.Color{u8(i * 12), 120, u8(255 - i * 10), 255}
		append(&s.frame.draws, ui.Draw{ui.translate(x, y), ui.NO_CLIP, ui.Fill{ui.Round_Rect{{0, 0, 44, 44}, 8}, col}})
	}
	angle: f32 = 0.5 if moved else 0.3
	m := ui.mul(ui.rotate(angle), ui.translate(200, 150))
	append(&s.frame.clips, ui.Clip{ui.NO_CLIP, ui.Round_Rect{{0, 0, 90, 40}, 12}, m})
	append(&s.frame.draws, ui.Draw{m, 0, ui.Fill{ui.Rect{-10, -10, 110, 60}, ui.Color{200, 60, 60, 255}}})
}

@(private = "file")
Rig :: struct {
	scene:  Scene,
	c:      Compositor,
	r:      Renderer,
	img:    bl.ImageCore, // composed into, kept across composes
	ref:    bl.ImageCore, // whole renders to compare with
	size:   [2]i32,
}

@(private = "file")
rig_init :: proc(g: ^Rig, workers: int) {
	ui.ops_init(&g.scene.ops)
	ui.frame_init(&g.scene.frame)
	compositor_init(&g.c, workers)
	init(&g.r)
	bl.image_init(&g.img)
	bl.image_init(&g.ref)
	bl.image_create(&g.img, CW, CH, .PRGB32)
	bl.image_create(&g.ref, CW, CH, .PRGB32)
}

@(private = "file")
rig_destroy :: proc(g: ^Rig) {
	bl.image_destroy(&g.img)
	bl.image_destroy(&g.ref)
	destroy(&g.r)
	compositor_destroy(&g.c)
	ui.frame_destroy(&g.scene.frame)
	ui.ops_destroy(&g.scene.ops)
}

// max_delta is the largest channel difference between two same-size images.
@(private = "file")
max_delta :: proc(a, b: ^bl.ImageCore) -> int {
	da, db: bl.ImageData
	bl.image_get_data(a, &da)
	bl.image_get_data(b, &db)
	worst := 0
	for y in 0 ..< int(da.size.h) {
		ra := ([^]u32)(uintptr(da.pixel_data) + uintptr(y) * uintptr(da.stride))
		rb := ([^]u32)(uintptr(db.pixel_data) + uintptr(y) * uintptr(db.stride))
		for x in 0 ..< int(da.size.w) {
			for sh in ([]u32{0, 8, 16, 24}) {
				worst = max(worst, abs(int((ra[x] >> sh) & 0xFF) - int((rb[x] >> sh) & 0xFF)))
			}
		}
	}
	return worst
}

@(private = "file")
area :: proc(rects: []ui.Rect) -> f32 {
	a: f32
	for r in rects {
		a += r.w * r.h
	}
	return a
}

@(test)
test_compose_first_frame_paints_all :: proc(t: ^testing.T) {
	g: Rig
	rig_init(&g, 1)
	defer rig_destroy(&g)
	scene_build(&g.scene, false)
	rects := compose(&g.c, &g.scene.frame, &g.img, BG)
	testing.expect_value(t, area(rects), f32(CW * CH))
	render(&g.r, &g.scene.frame, &g.ref, BG)
	testing.expect(t, max_delta(&g.img, &g.ref) <= 1)
}

@(test)
test_compose_unchanged_paints_nothing :: proc(t: ^testing.T) {
	g: Rig
	rig_init(&g, 1)
	defer rig_destroy(&g)
	scene_build(&g.scene, false)
	compose(&g.c, &g.scene.frame, &g.img, BG)
	scene_build(&g.scene, false)
	rects := compose(&g.c, &g.scene.frame, &g.img, BG)
	testing.expect_value(t, len(rects), 0)
}

// A moved card and a turned clip repaint their tiles only, and the result is
// what a whole render of the new frame draws.
@(test)
test_compose_change_matches_render :: proc(t: ^testing.T) {
	g: Rig
	rig_init(&g, 1)
	defer rig_destroy(&g)
	scene_build(&g.scene, false)
	compose(&g.c, &g.scene.frame, &g.img, BG)
	scene_build(&g.scene, true)
	rects := compose(&g.c, &g.scene.frame, &g.img, BG)
	a := area(rects)
	testing.expectf(t, a > 0 && a < CW * CH / 2, "repainted %v of %v px", a, CW * CH)
	for r in rects {
		testing.expect(t, int(r.x) % TILE == 0 && int(r.y) % TILE == 0, "rects are tile-aligned")
	}
	render(&g.r, &g.scene.frame, &g.ref, BG)
	testing.expectf(t, max_delta(&g.img, &g.ref) <= 1, "composed differs from a whole render by %d", max_delta(&g.img, &g.ref))
}

// The crew splits work differently every run but must paint the same pixels
// as one worker.
@(test)
test_compose_workers_match_one :: proc(t: ^testing.T) {
	one, four: Rig
	rig_init(&one, 1)
	defer rig_destroy(&one)
	rig_init(&four, 4)
	defer rig_destroy(&four)
	for moved in ([]bool{false, true, false}) {
		scene_build(&one.scene, moved)
		scene_build(&four.scene, moved)
		compose(&one.c, &one.scene.frame, &one.img, BG)
		compose(&four.c, &four.scene.frame, &four.img, BG)
		testing.expect_value(t, max_delta(&one.img, &four.img), 0)
	}
}

@(test)
test_compose_resize_paints_all :: proc(t: ^testing.T) {
	g: Rig
	rig_init(&g, 2)
	defer rig_destroy(&g)
	scene_build(&g.scene, false)
	compose(&g.c, &g.scene.frame, &g.img, BG)
	bl.image_create(&g.img, CW + 40, CH, .PRGB32)
	rects := compose(&g.c, &g.scene.frame, &g.img, BG)
	testing.expect_value(t, area(rects), f32((CW + 40) * CH))
}

// List is a scrollable list: a box with a stroked border and 40 rows of
// uniquely colored cells under a rect clip, scrolled by offset. under puts a
// gradient beneath the rows; over draws a panel across them.
@(private = "file")
List :: struct {
	origin: ui.Point,
	offset: f32,
	under:  bool,
	over:   bool,
	cols:   int, // repeat every row across this many columns; 0 means 1
}

@(private = "file")
list_stops := [2]ui.Gradient_Stop{{0, {255, 200, 200, 255}}, {1, {200, 200, 255, 255}}}

@(private = "file")
list_build :: proc(s: ^Scene, l: List) {
	ui.ops_reset(&s.ops)
	ui.frame_reset(&s.frame)
	s.frame.ops = &s.ops
	draw :: proc(s: ^Scene, t: ui.Affine, clip: ui.Clip_Id, cmd: ui.Draw_Cmd) {
		append(&s.frame.draws, ui.Draw{t, clip, cmd})
	}
	draw(s, ui.IDENTITY, ui.NO_CLIP, ui.Fill{ui.Rect{0, 0, CW, CH}, BG})
	box := ui.translate(l.origin.x, l.origin.y)
	draw(s, box, ui.NO_CLIP, ui.Fill{ui.Round_Rect{{0, 0, 200, 200}, 6}, ui.Color{255, 255, 255, 255}})
	draw(s, box, ui.NO_CLIP, ui.Stroke{ui.Round_Rect{{0.5, 0.5, 199, 199}, 6}, ui.Color{180, 180, 190, 255}, {width = 1}})
	if l.under {
		draw(s, box, ui.NO_CLIP, ui.Fill{ui.Rect{8, 8, 184, 184}, ui.Linear_Gradient{{0, 0}, {0, 184}, list_stops[:]}})
	}
	append(&s.frame.clips, ui.Clip{ui.NO_CLIP, ui.Rect{8, 8, 184, 184}, box})
	cols := max(l.cols, 1)
	for i in 0 ..< 40 {
		for c in 0 ..< cols {
			cw := 184 / f32(cols)
			row := ui.mul(ui.translate(8 + f32(c) * cw, 8 + f32(i) * 22 - l.offset), box)
			col := ui.Color{u8(i * 6), u8(200 - i * 4), u8(60 + i * 4), 255}
			draw(s, row, 0, ui.Fill{ui.Round_Rect{{1, 2, cw * 0.65, 18}, 4}, col})
			draw(s, row, 0, ui.Fill{ui.Rect{cw * 0.75, 6, cw * 0.2, 10}, ui.Color{40, 40, 50, 255}})
		}
	}
	if l.over {
		draw(s, box, ui.NO_CLIP, ui.Fill{ui.Round_Rect{{60, 60, 90, 50}, 8}, ui.Color{250, 180, 40, 230}})
	}
}

// step composes the list after l and checks the result against a whole
// render; it returns how many pixels were repainted rather than moved.
@(private = "file")
step :: proc(t: ^testing.T, g: ^Rig, l: List, loc := #caller_location) -> f32 {
	list_build(&g.scene, l)
	compose(&g.c, &g.scene.frame, &g.img, BG)
	render(&g.r, &g.scene.frame, &g.ref, BG)
	d := max_delta(&g.img, &g.ref)
	testing.expectf(t, d <= 1, "after %v the composed target differs from a whole render by %d", l, d, loc = loc)
	return area(g.c.damage.rects[:])
}

@(test)
test_compose_scroll_moves_pixels :: proc(t: ^testing.T) {
	for origin in ([]ui.Point{{40, 20}, {40.3, 20.6}}) {
		g: Rig
		rig_init(&g, 2)
		defer rig_destroy(&g)
		step(t, &g, {origin = origin, offset = 30})
		painted := step(t, &g, {origin = origin, offset = 37})
		testing.expectf(t, len(g.c.damage.scrolls) == 1, "origin %v: expected one scroll, got %v", origin, g.c.damage.scrolls[:])
		if len(g.c.damage.scrolls) == 1 {
			testing.expect_value(t, g.c.damage.scrolls[0].delta, [2]i32{0, -7})
		}
		testing.expectf(t, painted < 200 * 200 / 2, "origin %v: repainted %v px of a 200x200 list", origin, painted)
	}
}

// Moving pixels is only right when what lies under and over the rows moves
// with them or looks the same everywhere; otherwise the change repaints.
@(test)
test_compose_scroll_refused :: proc(t: ^testing.T) {
	cases := []struct {
		name:     string,
		from, to: List,
	} {
		{"gradient under", {origin = {40, 20}, offset = 30, under = true}, {origin = {40, 20}, offset = 37, under = true}},
		{"panel over", {origin = {40, 20}, offset = 30, over = true}, {origin = {40, 20}, offset = 37, over = true}},
		{"half a pixel", {origin = {40, 20}, offset = 30}, {origin = {40, 20}, offset = 37.5}},
	}
	for tc in cases {
		g: Rig
		rig_init(&g, 1)
		defer rig_destroy(&g)
		step(t, &g, tc.from)
		step(t, &g, tc.to)
		testing.expectf(t, len(g.c.damage.scrolls) == 0, "%s: expected no scroll, got %v", tc.name, g.c.damage.scrolls[:])
	}
}

// Whatever the sequence of scrolls and overlays, every frame must come out
// as a whole render draws it. The sequence is fixed: from the test runner's
// random seed, 18 of 200 seeds scrolled too little to count, and
// ui/render/fuzz covers the variety.
@(test)
test_compose_scroll_sequence :: proc(t: ^testing.T) {
	g: Rig
	rig_init(&g, 3)
	defer rig_destroy(&g)
	rng: u64 = 0x9E3779B97F4A7C15
	next :: proc(x: ^u64) -> u64 {
		x^ ~= x^ << 13
		x^ ~= x^ >> 7
		x^ ~= x^ << 17
		return x^
	}
	l := List{origin = {40.5, 20}, offset = 100}
	scrolled := 0
	for _ in 0 ..< 40 {
		switch next(&rng) % 6 {
		case 0:
			l.over = !l.over
		case 1:
			l.offset += 0.25
		case:
			l.offset += f32(i64(next(&rng) % 81) - 40)
		}
		l.offset = clamp(l.offset, 0, 700)
		step(t, &g, l)
		scrolled += len(g.c.damage.scrolls)
	}
	testing.expectf(t, scrolled > 5, "only %d of 40 frames scrolled", scrolled)
}

// Frames past HASH_CHUNK draws are hashed by the whole crew; the rects and
// pixels must be what one worker finds.
@(test)
test_compose_shared_hashing :: proc(t: ^testing.T) {
	one, four: Rig
	rig_init(&one, 1)
	defer rig_destroy(&one)
	rig_init(&four, 4)
	defer rig_destroy(&four)
	build :: proc(s: ^Scene, moved: int) {
		ui.ops_reset(&s.ops)
		ui.frame_reset(&s.frame)
		s.frame.ops = &s.ops
		append(&s.frame.draws, ui.Draw{ui.IDENTITY, ui.NO_CLIP, ui.Fill{ui.Rect{0, 0, CW, CH}, BG}})
		for i in 0 ..< 3000 {
			x, y := f32(i % 60) * 5, f32(i / 60) * 5
			if i == moved {
				x += 3
			}
			append(&s.frame.draws, ui.Draw{ui.translate(x, y), ui.NO_CLIP, ui.Fill{ui.Rect{0, 0, 4, 4}, ui.Color{u8(i), u8(i >> 3), 90, 255}}})
		}
	}
	for moved in ([]int{-1, 1234, 2999, -1}) {
		build(&one.scene, moved)
		build(&four.scene, moved)
		a := compose(&one.c, &one.scene.frame, &one.img, BG)
		b := compose(&four.c, &four.scene.frame, &four.img, BG)
		testing.expect_value(t, len(a), len(b))
		testing.expect_value(t, area(a), area(b))
		testing.expect_value(t, max_delta(&one.img, &four.img), 0)
	}
}

when ODIN_OS == .Windows {
	@(private = "file")
	LIST_FONT :: "C:/Windows/Fonts/arial.ttf"
} else {
	@(private = "file")
	LIST_FONT :: "/usr/share/fonts/liberation/LiberationSans-Regular.ttf"
}

@(private = "file")
Widgets :: struct {
	list: ui.List_State,
	on:   bool,
}

@(private = "file")
widgets_ui :: proc(gtx: ^ui.Ctx, user: rawptr) {
	w := (^Widgets)(user)
	page := ui.inset(gtx, ui.pad_all(12))
	defer ui.end(&page)
	card := ui.box(gtx)
	defer ui.end(&card)
	ui.list(gtx, &w.list, 200, proc(gtx: ^ui.Ctx, i: int, user: rawptr) {
		w := (^Widgets)(user)
		r := ui.row(gtx, gap = 8, align = .Center)
		defer ui.end(&r)
		ui.label(gtx, fmt.tprintf("Row %d", i))
		ui.checkbox(gtx, "on", &w.on)
		ui.fill_space(gtx)
		ui.button(gtx, "Pick")
	}, w)
}

// Scrolling ui.list with the wheel is detected as a scroll, and every frame
// still comes out as a whole render draws it.
@(test)
test_compose_list_widget_scrolls :: proc(t: ^testing.T) {
	g: Rig
	rig_init(&g, 2)
	defer rig_destroy(&g)
	w: Widgets
	p: ui.Probe
	ui.probe_init(&p, widgets_ui, &w, {CW, CH})
	defer ui.probe_destroy(&p)
	ui.add_font(&p.ops, LIST_FONT)
	p.shaper = shaper(&g.r, p.ops.fonts[:])
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	compose(&g.c, ui.probe_current(&p), &g.img, BG)
	scrolled := 0
	for dy in ([]f32{1, 1, 2, -1, 3, 1}) {
		if !testing.expect(t, ui.probe_scroll(&p, "Pick", dy), "found something to scroll over") {
			return
		}
		f := ui.probe_current(&p)
		compose(&g.c, f, &g.img, BG)
		scrolled += len(g.c.damage.scrolls)
		render(&g.r, f, &g.ref, BG)
		d := max_delta(&g.img, &g.ref)
		testing.expectf(t, d <= 1, "after scrolling %v the composed target differs from a whole render by %d", dy, d)
	}
	testing.expectf(t, scrolled >= 3, "only %d of 6 wheel steps were scrolls", scrolled)
}

// Once its buffers have grown to fit, compose allocates nothing per frame,
// scrolling or not.
@(test)
test_compose_steady_state_allocates_nothing :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	context.allocator = mem.tracking_allocator(&track)

	g: Rig
	rig_init(&g, 3)
	defer rig_destroy(&g)
	offsets := []f32{30, 37, 37, 50, 44, 44, 60, 53}
	for o in offsets { // grow everything to fit
		step(t, &g, {origin = {40.5, 20}, offset = o})
	}
	spent: i64
	scrolled := 0
	for o in offsets {
		list_build(&g.scene, {origin = {40.5, 20}, offset = o})
		before := track.total_allocation_count
		compose(&g.c, &g.scene.frame, &g.img, BG)
		spent += track.total_allocation_count - before
		scrolled += len(g.c.damage.scrolls)
	}
	testing.expect_value(t, spent, 0)
	testing.expect(t, scrolled > 0, "the measured frames include scrolls")
}

// Wide layouts repeat every row across columns, so no draw is unique; the
// scroll must still be found.
@(test)
test_compose_scroll_repeated_columns :: proc(t: ^testing.T) {
	g: Rig
	rig_init(&g, 2)
	defer rig_destroy(&g)
	step(t, &g, {origin = {40, 20}, offset = 30, cols = 24})
	step(t, &g, {origin = {40, 20}, offset = 41, cols = 24})
	testing.expectf(t, len(g.c.damage.scrolls) == 1, "expected one scroll, got %v", g.c.damage.scrolls[:])
	if len(g.c.damage.scrolls) == 1 {
		testing.expect_value(t, g.c.damage.scrolls[0].delta, [2]i32{0, -11})
	}
}


// A scroll big enough for the crew to share everything: the draws are
// hashed and moved by several workers, the pixels are moved in parts, and
// the thin strip uncovered is cut into several bands. Every frame must come
// out as a whole render draws it, and as one worker composes it.
@(test)
test_compose_large_scroll_shared :: proc(t: ^testing.T) {
	W, H :: 800, 600
	grid :: proc(s: ^Scene, off: [2]f32) {
		ui.ops_reset(&s.ops)
		ui.frame_reset(&s.frame)
		s.frame.ops = &s.ops
		append(&s.frame.draws, ui.Draw{ui.IDENTITY, ui.NO_CLIP, ui.Fill{ui.Rect{0, 0, W, H}, BG}})
		append(&s.frame.clips, ui.Clip{ui.NO_CLIP, ui.Rect{10, 10, W - 20, H - 20}, ui.IDENTITY})
		for i in 0 ..< 60 {
			for c in 0 ..< 20 {
				m := ui.translate(10 + f32(c) * 48 - off.x, 10 + f32(i) * 24 - off.y)
				col := ui.Color{u8(i * 4), u8(c * 12), u8(255 - i * 3), 255}
				append(&s.frame.draws, ui.Draw{m, 0, ui.Fill{ui.Round_Rect{{2, 2, 42, 18}, 5}, col}})
			}
		}
	}
	scenes: [2]Scene
	comps: [2]Compositor
	imgs: [3]bl.ImageCore
	r: Renderer
	init(&r)
	defer destroy(&r)
	for i in 0 ..< 2 {
		ui.ops_init(&scenes[i].ops)
		ui.frame_init(&scenes[i].frame)
		compositor_init(&comps[i], 1 if i == 0 else 4)
	}
	defer for i in 0 ..< 2 {
		compositor_destroy(&comps[i])
		ui.frame_destroy(&scenes[i].frame)
		ui.ops_destroy(&scenes[i].ops)
	}
	for &img in imgs {
		bl.image_init(&img)
		bl.image_create(&img, W, H, .PRGB32)
	}
	defer for &img in imgs {
		bl.image_destroy(&img)
	}

	// Down, further down, back up, then sideways each way.
	moves := [][2]f32{{0, 100}, {0, 107}, {0, 131}, {0, 118}, {13, 118}, {4, 118}}
	scrolled := 0
	for off in moves {
		for i in 0 ..< 2 {
			grid(&scenes[i], off)
			compose(&comps[i], &scenes[i].frame, &imgs[i], BG)
		}
		scrolled += len(comps[1].damage.scrolls)
		render(&r, &scenes[1].frame, &imgs[2], BG)
		testing.expectf(t, max_delta(&imgs[1], &imgs[2]) <= 1, "at %v four workers differ from a whole render by %d", off, max_delta(&imgs[1], &imgs[2]))
		testing.expectf(t, max_delta(&imgs[0], &imgs[1]) == 0, "at %v four workers differ from one by %d", off, max_delta(&imgs[0], &imgs[1]))
	}
	testing.expectf(t, scrolled == len(moves) - 1, "%d of %d moves scrolled", scrolled, len(moves) - 1)
}

// off_render is how far g's composed target is from a whole render of its
// scene; bands may leave up to SEAM where they meet.
@(private = "file")
off_render :: proc(g: ^Rig) -> int {
	render(&g.r, &g.scene.frame, &g.ref, BG)
	return max_delta(&g.img, &g.ref)
}

@(private = "file")
SEAM :: 3

@(private = "file")
reset :: proc(s: ^Scene) {
	ui.ops_reset(&s.ops)
	ui.frame_reset(&s.frame)
	s.frame.ops = &s.ops
}

// Draws A and C, translucent under a turned round-rect clip, overlap along
// its edge; B, far off, parts them. In the whole frame they are two groups,
// so the edge covers each once. A band that leaves B out must too.
@(private = "file")
split_groups :: proc(s: ^Scene, b_between: bool) {
	reset(s)
	append(&s.frame.clips, ui.Clip{ui.NO_CLIP, ui.Round_Rect{{0, 0, 200, 120}, 6}, ui.mul(ui.rotate(0.1), ui.translate(100, 80))})
	a := ui.Draw{ui.translate(150, 70), 0, ui.Fill{ui.Rect{0, 0, 60, 40}, ui.Color{200, 40, 40, 150}}}
	b := ui.Draw{ui.translate(10, 10), ui.NO_CLIP, ui.Fill{ui.Rect{0, 0, 30, 20}, ui.Color{40, 40, 200, 255}}}
	c := ui.Draw{ui.translate(170, 75), 0, ui.Fill{ui.Rect{0, 0, 60, 40}, ui.Color{40, 180, 40, 150}}}
	if b_between {
		append(&s.frame.draws, a, b, c)
	} else {
		append(&s.frame.draws, b, a, c)
	}
}

@(test)
test_compose_band_keeps_groups_apart :: proc(t: ^testing.T) {
	g: Rig
	rig_init(&g, 1)
	defer rig_destroy(&g)
	split_groups(&g.scene, true)
	compose(&g.c, &g.scene.frame, &g.img, BG)
	d := off_render(&g)
	testing.expectf(t, d <= SEAM, "composed differs from a whole render by %d", d)
}

// Moving B between A and C splits their group and changes the clip's edge
// where they overlap, though B lies in other tiles: those tiles must repaint.
@(test)
test_compose_regrouping_repaints :: proc(t: ^testing.T) {
	g: Rig
	rig_init(&g, 1)
	defer rig_destroy(&g)
	split_groups(&g.scene, false)
	compose(&g.c, &g.scene.frame, &g.img, BG)
	split_groups(&g.scene, true)
	compose(&g.c, &g.scene.frame, &g.img, BG)
	d := off_render(&g)
	testing.expectf(t, d <= SEAM, "composed differs from a whole render by %d", d)
}

// A rect ending at x = 48.25 under a round-rect clip starting there: the
// shapes do not overlap, but pixel 48 is partly in each, and a whole render
// shows the rect there. The draw must be bounded to include it.
@(test)
test_compose_draw_reaches_clip_edge :: proc(t: ^testing.T) {
	g: Rig
	rig_init(&g, 1)
	defer rig_destroy(&g)
	reset(&g.scene)
	append(&g.scene.frame.clips, ui.Clip{ui.NO_CLIP, ui.Round_Rect{{0, 0, 78, 24}, 3}, ui.translate(48.25, 15.5)})
	append(&g.scene.frame.draws, ui.Draw{ui.translate(-27.75, -10.7), 0, ui.Fill{ui.Rect{0, 0, 76, 41}, ui.Color{60, 220, 5, 255}}})
	compose(&g.c, &g.scene.frame, &g.img, BG)
	d := off_render(&g)
	testing.expectf(t, d <= SEAM, "composed differs from a whole render by %d", d)
}

// scrolled_grid is a column of distinct cells under a rect clip, moved
// right by dx, and a mark outside the clip that changes with dx, in the
// tile the strip the move uncovers lies in.
@(private = "file")
scrolled_grid :: proc(s: ^Scene, dx: f32) {
	reset(s)
	append(&s.frame.clips, ui.Clip{ui.NO_CLIP, ui.Rect{0, 0, 100, 200}, ui.translate(20, 20)})
	for i in 0 ..< 18 {
		col := ui.Color{u8(i * 13), u8(200 - i * 9), 90, 255}
		append(&s.frame.draws, ui.Draw{ui.translate(22 + dx, 22 + f32(i) * 11), 0, ui.Fill{ui.Rect{0, 0, 60, 9}, col}})
	}
	append(&s.frame.draws, ui.Draw{ui.translate(2, 2), ui.NO_CLIP, ui.Fill{ui.Rect{0, 0, 10, 10}, ui.Color{u8(dx * 5), 0, 0, 255}}})
}

// Workers paint the rects to repaint at once, so no two may overlap, even
// when a strip a scroll uncovers lies in a tile that changed.
@(test)
test_compose_repaints_do_not_overlap :: proc(t: ^testing.T) {
	g: Rig
	rig_init(&g, 4)
	defer rig_destroy(&g)
	scrolled_grid(&g.scene, 0)
	compose(&g.c, &g.scene.frame, &g.img, BG)
	scrolled_grid(&g.scene, 12)
	compose(&g.c, &g.scene.frame, &g.img, BG)
	testing.expectf(t, len(g.c.damage.scrolls) == 1, "expected one scroll, got %v", g.c.damage.scrolls[:])
	rects := g.c.damage.rects[:]
	for a, i in rects {
		for b in rects[i + 1:] {
			o := ui.rect_intersect(a, b)
			testing.expectf(t, o.w <= 0 || o.h <= 0, "%v and %v overlap", a, b)
		}
	}
	d := off_render(&g)
	testing.expectf(t, d <= SEAM, "composed differs from a whole render by %d", d)
}

// A grid that repeats looks scrolled by its period; drawn again unchanged,
// it must still repaint and move nothing.
@(test)
test_compose_repeats_do_not_scroll :: proc(t: ^testing.T) {
	g: Rig
	rig_init(&g, 1)
	defer rig_destroy(&g)
	grid :: proc(s: ^Scene) {
		reset(s)
		append(&s.frame.clips, ui.Clip{ui.NO_CLIP, ui.Rect{0, 0, 300, 230}, ui.translate(10, 10)})
		for i in 0 ..< 200 {
			x, y := f32(i % 10) * 30, f32(i / 10) * 12
			append(&s.frame.draws, ui.Draw{ui.translate(12 + x, 12 + y), 0, ui.Fill{ui.Rect{0, 0, 26, 9}, ui.Color{u8(i % 10) * 25, 120, 200, 255}}})
		}
	}
	grid(&g.scene)
	first := compose(&g.c, &g.scene.frame, &g.img, BG)
	testing.expect_value(t, area(first), f32(CW * CH))
	grid(&g.scene)
	again := compose(&g.c, &g.scene.frame, &g.img, BG)
	testing.expectf(t, len(again) == 0, "composing it again changed %v", again)
	testing.expectf(t, len(g.c.damage.scrolls) == 0, "an unchanged frame scrolled %v", g.c.damage.scrolls[:])
}

// A target resized in place, as a view into one bigger buffer, keeps its
// pixels: shrinking repaints nothing that did not change, growing repaints
// only the tiles it uncovers, and every frame is what a whole render draws.
// Without resize_in_place a new size repaints all of it.
@(test)
test_compose_resize_in_place :: proc(t: ^testing.T) {
	CAP :: [2]i32{400, 320}
	buffer, ref: bl.ImageCore
	bl.image_init(&buffer)
	bl.image_init(&ref)
	defer bl.image_destroy(&buffer)
	defer bl.image_destroy(&ref)
	bl.image_create(&buffer, CAP.x, CAP.y, .PRGB32)
	data: bl.ImageData
	bl.image_get_data(&buffer, &data)

	for in_place in ([]bool{true, false}) {
		g: Rig
		rig_init(&g, 2)
		defer rig_destroy(&g)
		g.c.damage.resize_in_place = in_place
		scene_build(&g.scene, false)

		sizes := [][2]i32{{320, 256}, {300, 240}, {360, 300}, {360, 300}}
		for size, i in sizes {
			view: bl.ImageCore
			bl.image_init(&view)
			defer bl.image_destroy(&view)
			bl.image_create_from_data(&view, size.x, size.y, .PRGB32, data.pixel_data, data.stride, .RW, nil, nil)
			rects := compose(&g.c, &g.scene.frame, &view, BG)

			bl.image_create(&ref, size.x, size.y, .PRGB32)
			render(&g.r, &g.scene.frame, &ref, BG)
			d := max_delta(&view, &ref)
			testing.expectf(t, d <= 3, "in place %v, size %v: composed differs from a whole render by %d", in_place, size, d)

			painted := area(rects)
			full := f32(size.x * size.y)
			switch {
			case i == 0 || !in_place && i < 3:
				testing.expectf(t, painted == full, "in place %v, size %v: repainted %v of %v", in_place, size, painted, full)
			case i == 1:
				testing.expectf(t, painted == 0, "shrinking in place repainted %v", painted)
			case i == 2:
				// Only whole tiles inside 300x240 were drawn before: 256x192.
				testing.expectf(t, painted == full - 256 * 192, "growing in place repainted %v of %v", painted, full)
			case:
				testing.expectf(t, painted == 0, "an unchanged frame repainted %v", painted)
			}
		}
	}
}

// A resize frame skips scroll detection, so the frame after it must not
// compare itself with the frame before the resize: drawn again unchanged,
// it repaints and moves nothing.
@(test)
test_compose_frame_after_resize_does_not_scroll :: proc(t: ^testing.T) {
	buffer: bl.ImageCore
	bl.image_init(&buffer)
	defer bl.image_destroy(&buffer)
	bl.image_create(&buffer, CW, CH, .PRGB32)
	data: bl.ImageData
	bl.image_get_data(&buffer, &data)

	g: Rig
	rig_init(&g, 1)
	defer rig_destroy(&g)
	g.c.damage.resize_in_place = true
	steps := []struct {
		size:   [2]i32,
		offset: f32,
	}{{{CW, CH}, 30}, {{CW, CH}, 30}, {{CW - 20, CH}, 37}, {{CW - 20, CH}, 37}}
	for st, i in steps {
		view: bl.ImageCore
		bl.image_init(&view)
		defer bl.image_destroy(&view)
		bl.image_create_from_data(&view, st.size.x, st.size.y, .PRGB32, data.pixel_data, data.stride, .RW, nil, nil)
		list_build(&g.scene, {origin = {40, 20}, offset = st.offset})
		rects := compose(&g.c, &g.scene.frame, &view, BG)
		if i == 2 {
			testing.expectf(t, len(rects) > 0, "the resize frame, whose list scrolled, repainted nothing")
		}
		if i == len(steps) - 1 {
			testing.expectf(t, len(rects) == 0, "drawn again unchanged, it changed %v", rects)
			testing.expectf(t, len(g.c.damage.scrolls) == 0, "drawn again unchanged, it scrolled %v", g.c.damage.scrolls[:])
		}
	}
}
