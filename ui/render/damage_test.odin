package render

import "core:testing"
import "jm:ui/ops"

import "jm:ui"
import bl "jm:ui/blend2d"

when ODIN_OS == .Windows {
	@(private = "file")
	FONT :: "C:/Windows/Fonts/arial.ttf"
} else when ODIN_OS == .Darwin {
	// A plain TrueType file every macOS since Catalina ships; the
	// system face, SFNS.ttf, is not one Blend2D reads.
	@(private = "file")
	FONT :: "/System/Library/Fonts/Supplemental/Arial.ttf"
} else {
	@(private = "file")
	FONT :: "/usr/share/fonts/liberation/LiberationSans-Regular.ttf"
}

// A draw whose fade changes, and nothing else, repaints where it lies.
@(test)
test_damage_sees_a_change_of_fade :: proc(t: ^testing.T) {
	f: ui.Frame
	ui.frame_init(&f)
	defer ui.frame_destroy(&f)
	sc: ops.Scene
	ops.init(&sc)
	defer ops.destroy(&sc)
	f.scene = &sc
	append(&f.draws, ui.Draw{ops.IDENTITY, ui.NO_CLIP, ops.Fill{ops.Ellipse{{0, 0, 128, 128}}, ops.Color{255, 0, 0, 255}}, 0})
	d: Damage
	defer damage_destroy(&d)
	damage_update(&d, &f, 256, 256, {0, 0, 0, 0})
	rects, _ := damage_update(&d, &f, 256, 256, {0, 0, 0, 0})
	testing.expect_value(t, len(rects), 0) // the same frame twice repaints nothing
	f.draws[0].fade = 0.5
	rects, _ = damage_update(&d, &f, 256, 256, {0, 0, 0, 0})
	testing.expect(t, len(rects) > 0, "a faded draw repaints")
}

// Text bounds must hold every pixel the text paints, swashes included; a
// pixel outside them would never be repainted when the text changes.
@(test)
test_damage_text_bounds :: proc(t: ^testing.T) {
	when ODIN_OS == .Windows {
		fonts := []string{FONT, "C:/Windows/Fonts/Gabriola.ttf", "C:/Windows/Fonts/segoesc.ttf"}
	} else {
		fonts := []string{FONT}
	}
	r: Renderer
	init(&r)
	defer destroy(&r)
	img: bl.ImageCore
	bl.image_init(&img)
	defer bl.image_destroy(&img)
	bl.image_create(&img, 400, 200, .PRGB32)
	for path in fonts {
		for text in ([]string{"Wafgjy", "ÅÉÎ ǅ fff", "Thq"}) {
			sc: ops.Scene
			ops.init(&sc)
			defer ops.destroy(&sc)
			id := ops.add_font(&sc, path)
			run := ui.shape(shaper(&r, sc.fonts[:]), id, 48, text, context.allocator)
			defer delete(run.glyphs)
			append(&sc.runs, run)
			f: ui.Frame
			ui.frame_init(&f)
			defer ui.frame_destroy(&f)
			f.scene = &sc
			append(&f.draws, ui.Draw{ops.translate(60, 100), ui.NO_CLIP, ops.Glyphs{0, {0, 0}, {0, 0, 0, 255}}, 0})
			render(&r, &f, &img, {0, 0, 0, 0})

			d: Damage
			defer damage_destroy(&d)
			damage_update(&d, &f, 400, 200, {0, 0, 0, 0}, &r)
			b := d.old_draws[0].bounds // damage_close files this frame as the old one

			data: bl.ImageData
			bl.image_get_data(&img, &data)
			outside := 0
			for y in 0 ..< 200 {
				row := ([^]u32)(uintptr(data.pixel_data) + uintptr(y) * uintptr(data.stride))
				for x in 0 ..< 400 {
					if row[x] >> 24 != 0 && !contains(b, {f32(x), f32(y), 1, 1}) {
						outside += 1
					}
				}
			}
			testing.expectf(t, outside == 0, "%s %q: %d painted pixels fall outside bounds %v", path, text, outside, b)
		}
	}
}

// cards is a frame of a background and a row of cards, card c tinted by
// shade, with the text and path a scene can hold: a run of glyphs and a
// triangle. A card's shade, a glyph's id or a path point are what change.
@(private = "file")
Cards :: struct {
	shade: u8,
	glyph: u32,
	point: f32,
	card:  int, // which card shade tints
	skip:  int, // a card left out, shifting the draws after it; -1 for none
}

@(private = "file")
cards :: proc(sc: ^ops.Scene, f: ^ui.Frame, c: Cards) {
	ops.reset(sc)
	ui.frame_reset(f)
	f.scene = sc
	append(&f.draws, ui.Draw{ops.IDENTITY, ui.NO_CLIP, ops.Fill{ops.Rect{0, 0, 512, 256}, ops.Color{250, 250, 250, 255}}, 0})
	append(&f.clips, ui.Clip{ui.NO_CLIP, ops.Rect{0, 0, 512, 256}, ops.IDENTITY})
	for i in 0 ..< 6 {
		if i == c.skip {
			continue
		}
		col := ops.Color{u8(40 * i), 120, 200, 255}
		if i == c.card {
			col.r = c.shade
		}
		append(&f.draws, ui.Draw{ops.translate(f32(i) * 80 + 8, 8), 0, ops.Fill{ops.Round_Rect{{0, 0, 64, 64}, 6}, col}, 0})
	}
	glyphs := make([]ops.Glyph, 3, sc.allocator)
	glyphs[0] = {c.glyph, 0, 0, 0, 0}
	glyphs[1] = {7, 1, 12, 0, 0}
	glyphs[2] = {9, 2, 24, 0, 0}
	append(&sc.runs, ops.Glyph_Run{0, 16, glyphs, 36})
	append(&f.draws, ui.Draw{ops.translate(20, 120), 0, ops.Glyphs{0, {0, 0}, {0, 0, 0, 255}}, 0})
	verbs := make([]ops.Path_Verb, 4, sc.allocator)
	verbs[0], verbs[1], verbs[2], verbs[3] = .Move, .Line, .Line, .Close
	points := make([]ops.Point, 3, sc.allocator)
	points[0], points[1], points[2] = {300, 200}, {340, 200}, {c.point, 160}
	append(&sc.paths, ops.Path{verbs, points, .Non_Zero})
	append(&f.draws, ui.Draw{ops.IDENTITY, 0, ops.Fill{ops.Path_Ref{0}, ops.Color{200, 40, 40, 255}}, 0})
}

@(private = "file")
CARDS :: Cards{shade = 40, glyph = 5, point = 320, card = 2, skip = -1}

// The same frame again keeps every record and every tile; a frame with one
// card's color changed works out that draw alone and folds only the tiles
// it touches, and the tiles that repaint are those.
@(test)
test_damage_keeps_unchanged_draws :: proc(t: ^testing.T) {
	sc: ops.Scene
	ops.init(&sc, context.temp_allocator)
	f: ui.Frame
	ui.frame_init(&f)
	defer ui.frame_destroy(&f)
	d: Damage
	defer damage_destroy(&d)
	cards(&sc, &f, CARDS)
	damage_update(&d, &f, 512, 256, {0, 0, 0, 0})
	testing.expect_value(t, d.hashed, len(f.draws))
	cards(&sc, &f, CARDS)
	rects, _ := damage_update(&d, &f, 512, 256, {0, 0, 0, 0})
	testing.expect_value(t, len(rects), 0)
	testing.expect_value(t, d.hashed, 0)
	testing.expect_value(t, d.rebinned, 0)

	c := CARDS
	c.shade = 200
	cards(&sc, &f, c)
	rects, _ = damage_update(&d, &f, 512, 256, {0, 0, 0, 0})
	testing.expect_value(t, d.hashed, 1)
	// Card 2 spans x 168 ..< 232 and y 8 ..< 72 plus a pixel of
	// antialiasing: tiles (2, 0), (3, 0), (2, 1) and (3, 1).
	testing.expect_value(t, d.rebinned, 4)
	testing.expect_value(t, len(rects), 1)
	if len(rects) == 1 {
		testing.expect_value(t, rects[0], ops.Rect{128, 0, 128, 128})
	}
}

// What a draw refers to in the scene is compared too: a run whose glyphs
// change and a path whose points change repaint, though their ids,
// origins and colors are the same.
@(test)
test_damage_sees_referenced_data_change :: proc(t: ^testing.T) {
	sc: ops.Scene
	ops.init(&sc, context.temp_allocator)
	f: ui.Frame
	ui.frame_init(&f)
	defer ui.frame_destroy(&f)
	d: Damage
	defer damage_destroy(&d)
	cards(&sc, &f, CARDS)
	damage_update(&d, &f, 512, 256, {0, 0, 0, 0})

	c := CARDS
	c.glyph = 6
	cards(&sc, &f, c)
	rects, _ := damage_update(&d, &f, 512, 256, {0, 0, 0, 0})
	testing.expect_value(t, d.hashed, 1)
	testing.expect(t, len(rects) > 0, "changed glyphs repaint")
	c.point = 330
	cards(&sc, &f, c)
	rects, _ = damage_update(&d, &f, 512, 256, {0, 0, 0, 0})
	testing.expect_value(t, d.hashed, 1)
	testing.expect(t, len(rects) > 0, "a changed path repaints")
	cards(&sc, &f, c)
	rects, _ = damage_update(&d, &f, 512, 256, {0, 0, 0, 0})
	testing.expect_value(t, d.hashed, 0)
	testing.expect_value(t, len(rects), 0)
}

// A draw left out shifts every draw after it to a new index, where it no
// longer matches the previous frame's: those are worked out again and the
// repaint covers what was removed and what moved. The frame after, the
// indices agree again and nothing is.
@(test)
test_damage_shifted_draws :: proc(t: ^testing.T) {
	sc: ops.Scene
	ops.init(&sc, context.temp_allocator)
	f: ui.Frame
	ui.frame_init(&f)
	defer ui.frame_destroy(&f)
	d: Damage
	defer damage_destroy(&d)
	cards(&sc, &f, CARDS)
	damage_update(&d, &f, 512, 256, {0, 0, 0, 0})
	n := len(f.draws)

	c := CARDS
	c.skip = 1
	cards(&sc, &f, c)
	rects, _ := damage_update(&d, &f, 512, 256, {0, 0, 0, 0})
	testing.expect_value(t, d.hashed, n - 3) // the background and card 0 keep theirs
	covered :: proc(rects: []ops.Rect, r: ops.Rect) -> bool {
		for q in rects {
			if contains(q, r) {
				return true
			}
		}
		return false
	}
	testing.expect(t, covered(rects, {88, 8, 64, 64}), "the removed card's pixels repaint")
	testing.expect(t, !covered(rects, {8, 8, 64, 64}), "the card before it does not")
	cards(&sc, &f, c)
	rects, _ = damage_update(&d, &f, 512, 256, {0, 0, 0, 0})
	testing.expect_value(t, d.hashed, 0)
	testing.expect_value(t, len(rects), 0)

	cards(&sc, &f, CARDS)
	rects, _ = damage_update(&d, &f, 512, 256, {0, 0, 0, 0})
	testing.expect(t, covered(rects, {88, 8, 64, 64}), "the card put back repaints")
}
