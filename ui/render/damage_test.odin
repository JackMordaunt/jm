package render

import "core:testing"

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
			ops: ui.Ops
			ui.ops_init(&ops)
			defer ui.ops_destroy(&ops)
			id := ui.add_font(&ops, path)
			run := ui.shape(shaper(&r, ops.fonts[:]), id, 48, text, context.allocator)
			defer delete(run.glyphs)
			append(&ops.runs, run)
			f: ui.Frame
			ui.frame_init(&f)
			defer ui.frame_destroy(&f)
			f.ops = &ops
			append(&f.draws, ui.Draw{ui.translate(60, 100), ui.NO_CLIP, ui.Glyphs{0, {0, 0}, {0, 0, 0, 255}}})
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
