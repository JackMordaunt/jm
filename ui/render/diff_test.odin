package render

import "core:os"
import "core:strings"
import "core:testing"

import "jm:ui"
import bl "jm:ui/blend2d"

@(private = "file")
fill_solid :: proc(img: ^bl.ImageCore, c: ui.Color) {
	bl.image_init(img)
	bl.image_create(img, SIZE, SIZE, .PRGB32)
	ctx: bl.ContextCore
	bl.context_init(&ctx)
	defer bl.context_destroy(&ctx)
	bl.context_begin(&ctx, img, nil)
	bl.context_fill_all_rgba32(&ctx, rgba32(c))
	bl.context_end(&ctx)
}

@(private = "file")
fill_solid_with_patch :: proc(img: ^bl.ImageCore, c, patch: ui.Color, at: ui.Rect) {
	fill_solid(img, c)
	ctx: bl.ContextCore
	bl.context_init(&ctx)
	defer bl.context_destroy(&ctx)
	bl.context_begin(&ctx, img, nil)
	rect := bl.Rect{f64(at.x), f64(at.y), f64(at.w), f64(at.h)}
	bl.context_fill_rect_d_rgba32(&ctx, &rect, rgba32(patch))
	bl.context_end(&ctx)
}

@(test)
test_image_diff_identical_images :: proc(t: ^testing.T) {
	a, b: bl.ImageCore
	fill_solid(&a, WHITE)
	defer bl.image_destroy(&a)
	fill_solid(&b, WHITE)
	defer bl.image_destroy(&b)

	changed, identical, ok := diff_images(&a, &b, 16, context.temp_allocator)
	testing.expect(t, ok)
	testing.expect(t, identical)
	testing.expect_value(t, len(changed), 0)
}

@(test)
test_image_diff_finds_a_changed_region :: proc(t: ^testing.T) {
	a, b: bl.ImageCore
	fill_solid(&a, WHITE)
	defer bl.image_destroy(&a)
	// A patch inside tile (3, 0) of a 16px grid (x: 48-64), nowhere near
	// tile (0, 0) — both should show up correctly, changed and not.
	fill_solid_with_patch(&b, WHITE, RED, {50, 2, 8, 8})
	defer bl.image_destroy(&b)

	changed, identical, ok := diff_images(&a, &b, 16, context.temp_allocator)
	testing.expect(t, ok)
	testing.expect(t, !identical)
	testing.expect_value(t, len(changed), 1)
	testing.expect_value(t, changed[0], ui.Rect{48, 0, 16, 16})
}

@(test)
test_image_diff_different_sizes_is_one_full_rect :: proc(t: ^testing.T) {
	a, b: bl.ImageCore
	bl.image_init(&a)
	bl.image_create(&a, 32, 32, .PRGB32)
	defer bl.image_destroy(&a)
	bl.image_init(&b)
	bl.image_create(&b, 64, 48, .PRGB32)
	defer bl.image_destroy(&b)

	changed, identical, ok := diff_images(&a, &b, 16, context.temp_allocator)
	testing.expect(t, ok)
	testing.expect(t, !identical)
	testing.expect_value(t, len(changed), 1)
	testing.expect_value(t, changed[0], ui.Rect{0, 0, 64, 48})
}

// test_diff_files_round_trip drives the real path an agent's edit/rebuild
// loop uses: two PNGs written to disk, diffed by path. This is what
// caught both of load_png's real bugs while this file was written —
// diff_images on two freshly loaded, in-memory-only images always looked
// fine, since the bugs (ImageCore corrupted by a by-value return, and a
// missing context_init before the highlight write) only showed up going
// through actual files and an actual highlight write.
@(test)
test_diff_files_round_trip :: proc(t: ^testing.T) {
	a, b: bl.ImageCore
	fill_solid(&a, WHITE)
	defer bl.image_destroy(&a)
	fill_solid_with_patch(&b, WHITE, RED, {50, 2, 8, 8})
	defer bl.image_destroy(&b)

	a_path := "build/test/diff_a.png"
	b_path := "build/test/diff_b.png"
	highlight_path := "build/test/diff_highlight.png"
	defer os.remove(a_path)
	defer os.remove(b_path)
	defer os.remove(highlight_path)
	testing.expect(t, bl.image_write_to_file(&a, strings.clone_to_cstring(a_path, context.temp_allocator), nil) == 0)
	testing.expect(t, bl.image_write_to_file(&b, strings.clone_to_cstring(b_path, context.temp_allocator), nil) == 0)

	changed, identical, ok := diff_files(a_path, b_path, 16, highlight_path, context.temp_allocator)
	testing.expect(t, ok)
	testing.expect(t, !identical)
	testing.expect_value(t, len(changed), 1)

	// Not just that highlight_path exists: that write_highlight actually
	// drew onto it, by diffing it back against the plain b it started
	// from. A stub that only copied b across would pass os.exists but
	// fail this.
	highlight: bl.ImageCore
	bl.image_init(&highlight)
	defer bl.image_destroy(&highlight)
	testing.expect(t, load_png(&highlight, highlight_path))
	h_changed, h_identical, h_ok := diff_images(&b, &highlight, 16, context.temp_allocator)
	testing.expect(t, h_ok)
	testing.expect(t, !h_identical)
	// Not just that the highlight differs from b somewhere: that one of
	// the tiles it touched is changed[0], the rect the diff actually
	// found — not necessarily the only tile, since a 2px stroke drawn
	// exactly on {48,0,16,16}'s boundary spills a pixel into the tile
	// beside it too.
	found := false
	for r in h_changed {
		if r == changed[0] {
			found = true
			break
		}
	}
	testing.expect(t, found)

	same, sidentical, sok := diff_files(a_path, a_path, 16, "", context.temp_allocator)
	testing.expect(t, sok)
	testing.expect(t, sidentical)
	testing.expect_value(t, len(same), 0)
}
