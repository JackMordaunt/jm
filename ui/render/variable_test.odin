package render

import "core:os"
import "core:strings"
import "core:testing"
import "jm:ui/ops"
import "jm:ui/testutil"

import "jm:ui"
import bl "jm:ui/blend2d"

@(private = "file")
W :: 160
@(private = "file")
H :: 48

// ink is how much black a white image holds: each pixel's darkness summed.
@(private = "file")
ink :: proc(img: ^bl.ImageCore) -> int {
	sum := 0
	for y in 0 ..< H {
		for x in 0 ..< W {
			sum += 255 - int(pixel(img, x, y).r)
		}
	}
	return sum
}

// draw_run renders run in black at {4, 36} on white into img.
@(private = "file")
draw_run :: proc(r: ^Renderer, sc: ^ops.Scene, run: ops.Glyph_Run, img: ^bl.ImageCore) {
	f: ui.Frame
	ui.frame_init(&f)
	defer ui.frame_destroy(&f)
	f.scene = sc
	ops.reset(sc)
	id := ops.add_run(sc, run)
	append(&f.draws, ui.Draw{ops.IDENTITY, ui.NO_CLIP, ops.Glyphs{id, {4, 36}, {0, 0, 0, 255}}, 0})
	render(r, &f, img, {255, 255, 255, 255})
}

@(private = "file")
with_font :: proc(run: ops.Glyph_Run, font: ops.Font_Id) -> ops.Glyph_Run {
	out := run
	out.glyphs = make([]ops.Glyph, len(run.glyphs), context.temp_allocator)
	for g, i in run.glyphs {
		out.glyphs[i] = g
		out.glyphs[i].font = font
	}
	return out
}

// The same glyphs at the same places at 700 hold more ink than at 400:
// the weight reaches the outlines, not only the advances. The fixture
// (see testutil.variable_font) is 15% wider at 700, so it holds about 15%
// more ink (1.15 measured); SFNS, where it is, thickens its stems and
// must hold at least 20% more (1.57 measured on macOS 15).
@(test)
test_variable_font_draws_heavier_at_700 :: proc(t: ^testing.T) {
	os.make_directory("build/test")
	fixture := "build/test/render-wght.ttf"
	defer os.remove(fixture)
	testing.expect(t, testutil.variable_font(fixture), "write the variable fixture")
	light, heavy := ink_at(t, fixture, 400, 700)
	testing.expectf(t, f64(heavy) > 1.1 * f64(light), "fixture ink at 700 %d, at 400 %d", heavy, light)
	if os.exists(testutil.SFNS) {
		light, heavy = ink_at(t, testutil.SFNS, 400, 700)
		testing.expectf(t, f64(heavy) > 1.2 * f64(light), "SFNS ink at 700 %d, at 400 %d", heavy, light)
	}
}

// ink_at is the ink of one glyph run, shaped at light, drawn in the font
// at path at light and then at heavy.
@(private = "file")
ink_at :: proc(t: ^testing.T, path: string, light, heavy: f32) -> (int, int) {
	defer free_all(context.temp_allocator)
	r: Renderer
	init(&r)
	defer destroy(&r)
	sc: ops.Scene
	ops.init(&sc)
	defer ops.destroy(&sc)
	regular := ops.add_font(&sc, path, light)
	bold := ops.add_font(&sc, path, heavy)
	s := shaper(&r, sc.fonts[:])
	run := ui.shape(s, regular, 28, "Hamburg", context.temp_allocator)
	testing.expect(t, len(run.glyphs) > 0, path)

	img: bl.ImageCore
	bl.image_init(&img)
	defer bl.image_destroy(&img)
	bl.image_create(&img, W, H, .PRGB32)
	draw_run(&r, &sc, run, &img)
	at_light := ink(&img)
	draw_run(&r, &sc, with_font(run, bold), &img)
	testing.expect(t, at_light > 0, path)
	return at_light, ink(&img)
}

// A static font at a weight loads and draws as it does at no weight: the
// weight is ignored, not an error.
@(test)
test_static_font_ignores_weight :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	r: Renderer
	init(&r)
	defer destroy(&r)
	sc: ops.Scene
	ops.init(&sc)
	defer ops.destroy(&sc)
	plain := ops.add_font(&sc, testutil.ASCII_FONT)
	weighted := ops.add_font(&sc, testutil.ASCII_FONT, 600)
	s := shaper(&r, sc.fonts[:])
	run := ui.shape(s, weighted, 28, "Weight", context.temp_allocator)
	testing.expect(t, len(run.glyphs) > 0, "a static font at a weight shapes")

	img: bl.ImageCore
	bl.image_init(&img)
	defer bl.image_destroy(&img)
	bl.image_create(&img, W, H, .PRGB32)
	draw_run(&r, &sc, run, &img)
	at_weight := ink(&img)
	draw_run(&r, &sc, with_font(run, plain), &img)
	testing.expect(t, at_weight > 0, "a static font at a weight draws")
	testing.expect_value(t, at_weight, ink(&img))
}

// fill_variable at a font's default instance draws what Blend2D's own
// glyph run draws: jm:ui/glyf decodes outlines, simple and composite, as
// Blend2D does.
@(test)
test_variable_outlines_match_blend2d :: proc(t: ^testing.T) {
	compare_outlines(t, testutil.ASCII_FONT, "Hamburg")
	if os.exists(testutil.SFNS) {
		compare_outlines(t, testutil.SFNS, "Hämbürg Åß") // accents are composites
	}
}

@(private = "file")
compare_outlines :: proc(t: ^testing.T, path, text: string) {
	defer free_all(context.temp_allocator)
	r: Renderer
	init(&r)
	defer destroy(&r)
	sc: ops.Scene
	ops.init(&sc)
	defer ops.destroy(&sc)
	font := ops.add_font(&sc, path)
	run := ui.shape(shaper(&r, sc.fonts[:]), font, 28, text, context.temp_allocator)
	testing.expect(t, len(run.glyphs) > 0, path)

	v: Variable
	bl.font_data_init(&v.data)
	defer bl.font_data_destroy(&v.data)
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	testing.expect_value(t, bl.font_data_create_from_file(&v.data, cpath, .NO_FLAGS), bl.Result(0))
	testing.expect(t, read_tables(&v), path)

	ids := make([]u32, len(run.glyphs), context.temp_allocator)
	pts := make([]bl.Point, len(run.glyphs), context.temp_allocator)
	for g, i in run.glyphs {
		ids[i], pts[i] = g.id, {f64(g.x), f64(g.y)}
	}
	origin := bl.Point{4, 36}
	ours, theirs: bl.ImageCore
	for img in ([]^bl.ImageCore{&ours, &theirs}) {
		bl.image_init(img)
		bl.image_create(img, W, H, .PRGB32)
	}
	defer bl.image_destroy(&ours)
	defer bl.image_destroy(&theirs)

	ctx: bl.ContextCore
	bl.context_init_as(&ctx, &ours, nil)
	bl.context_fill_all_rgba32(&ctx, 0xffffffff)
	fill_variable(&r, &ctx, font, &v, ids, pts, origin, run.size, 0xff000000)
	bl.context_end(&ctx)

	fnt := font_for(&r, font, run.size, sc.fonts[:])
	testing.expect(t, fnt != nil, path)
	gr := bl.GlyphRun {
		glyph_data        = raw_data(ids),
		placement_data    = raw_data(pts),
		size              = uint(len(ids)),
		placement_type    = u8(bl.GlyphPlacementType.USER_UNITS),
		glyph_advance     = size_of(u32),
		placement_advance = size_of(bl.Point),
	}
	bl.context_init_as(&ctx, &theirs, nil)
	bl.context_fill_all_rgba32(&ctx, 0xffffffff)
	bl.context_fill_glyph_run_d_rgba32(&ctx, &origin, fnt, &gr, 0xff000000)
	bl.context_end(&ctx)
	bl.context_destroy(&ctx)

	worst := 0
	for y in 0 ..< H {
		for x in 0 ..< W {
			worst = max(worst, abs(int(pixel(&ours, x, y).r) - int(pixel(&theirs, x, y).r)))
		}
	}
	testing.expect(t, ink(&theirs) > 0, path)
	testing.expectf(t, worst <= 8, "%s: worst pixel differs by %d", path, worst)
}
