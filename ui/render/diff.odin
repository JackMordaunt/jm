package render

import "core:fmt"
import "jm:ui/ops"
import "core:slice"
import "core:strings"

import bl "jm:ui/blend2d"

// diff_images, load_png and diff_files exist for one loop: an agent (or a
// person) edited a ui proc's source, wants to know whether the render
// changed and roughly where, and would rather not spend the tokens (or
// the eyes) looking at either image unless something actually moved.
// diff_files is the one call that loop needs; diff_images and load_png are
// its two pieces, each useful on their own — diff_images works on any two
// PRGB32 images, however they were made.

// diff_images compares a and b tile by tile (tile x tile pixel blocks,
// compared by raw bytes — no un-premultiplying, so this is exact only
// when both share a format, true of any two images this package wrote)
// and returns the bounding rect of every tile where at least one pixel
// differs. identical is true only when every tile matched. Differently
// sized images are never identical and come back as one changed rect
// covering the larger extent, tile ignored — there is no tile grid two
// different sizes could share.
diff_images :: proc(a, b: ^bl.ImageCore, tile: int = 32, allocator := context.allocator) -> (changed: []ops.Rect, identical: bool, ok: bool) {
	da, db: bl.ImageData
	if bl.image_get_data(a, &da) != 0 || bl.image_get_data(b, &db) != 0 {
		return nil, false, false
	}
	if da.size.w != db.size.w || da.size.h != db.size.h {
		w, h := max(da.size.w, db.size.w), max(da.size.h, db.size.h)
		out := make([]ops.Rect, 1, allocator)
		out[0] = {0, 0, f32(w), f32(h)}
		return out, false, true
	}
	w, h := int(da.size.w), int(da.size.h)
	if w <= 0 || h <= 0 {
		return nil, true, true
	}

	out := make([dynamic]ops.Rect, allocator)
	for ty := 0; ty < h; ty += tile {
		th := min(tile, h - ty)
		for tx := 0; tx < w; tx += tile {
			tw := min(tile, w - tx)
			if tile_differs(&da, &db, tx, ty, tw, th) {
				append(&out, ops.Rect{f32(tx), f32(ty), f32(tw), f32(th)})
			}
		}
	}
	return out[:], len(out) == 0, true
}

@(private = "file")
tile_differs :: proc(da, db: ^bl.ImageData, x, y, w, h: int) -> bool {
	for row in 0 ..< h {
		a_off := uintptr((y + row) * int(da.stride) + x * 4)
		b_off := uintptr((y + row) * int(db.stride) + x * 4)
		a_row := ([^]byte)(rawptr(uintptr(da.pixel_data) + a_off))[:w * 4]
		b_row := ([^]byte)(rawptr(uintptr(db.pixel_data) + b_off))[:w * 4]
		if !slice.equal(a_row, b_row) {
			return true
		}
	}
	return false
}

// load_png reads path into img, which the caller owns: bl.image_init it
// before, bl.image_destroy it after, same as every other ImageCore in
// this package. It takes img by pointer, never by value: an earlier
// version returned a fresh ImageCore, and that by-value return silently
// corrupted it — image_get_data still reported success afterward, but
// with a 0x0 size and a nil pixel_data. Every other ImageCore in this
// package is already only ever held as a local passed by pointer, never
// returned; whether that generalizes to every Blend2D Core type was not
// tested, only this one.
//
// image_read_from_file also takes a codec array, not nil: observed here
// (again not independently re-tested) passing nil reported success while
// leaving the image at its zero value rather than actually decoding
// anything, which is the other way an early version of this returned
// "identical" for two images that plainly were not.
load_png :: proc(img: ^bl.ImageCore, path: string) -> bool {
	codecs: bl.ArrayCore
	if bl.image_codec_array_init_built_in_codecs(&codecs) != 0 {
		return false
	}
	defer bl.array_destroy(&codecs)
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	return bl.image_read_from_file(img, cpath, &codecs) == 0
}

// diff_files is diff_images over two PNGs on disk by path. When highlight
// is not "", and the two differ, it writes b with every changed rect
// outlined in red to that path — the one image worth opening, if any is.
diff_files :: proc(
	a_path, b_path: string,
	tile: int = 32,
	highlight: string = "",
	allocator := context.allocator,
) -> (
	changed: []ops.Rect,
	identical: bool,
	ok: bool,
) {
	a, b: bl.ImageCore
	bl.image_init(&a)
	defer bl.image_destroy(&a)
	bl.image_init(&b)
	defer bl.image_destroy(&b)
	if !load_png(&a, a_path) || !load_png(&b, b_path) {
		return nil, false, false
	}
	changed, identical, ok = diff_images(&a, &b, tile, allocator)
	if ok && !identical && highlight != "" {
		write_highlight(&b, changed, highlight)
	}
	return
}

@(private = "file")
write_highlight :: proc(img: ^bl.ImageCore, changed: []ops.Rect, path: string) -> bool {
	ctx: bl.ContextCore
	bl.context_init(&ctx)
	defer bl.context_destroy(&ctx)
	if bl.context_begin(&ctx, img, nil) != 0 {
		return false
	}
	bl.context_set_stroke_width(&ctx, 2)
	for r in changed {
		rect := bl.Rect{f64(r.x), f64(r.y), f64(r.w), f64(r.h)}
		bl.context_stroke_rect_d_rgba32(&ctx, &rect, rgba32(ops.Color{255, 32, 32, 255}))
	}
	bl.context_end(&ctx)
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	return bl.image_write_to_file(img, cpath, nil) == 0
}

// diff_summary is changed and identical as one line per rect plus a
// header, for printing straight to a terminal without opening either
// image.
diff_summary :: proc(changed: []ops.Rect, identical: bool, allocator := context.allocator) -> string {
	if identical {
		return strings.clone("identical", allocator)
	}
	b := strings.builder_make(allocator)
	fmt.sbprintfln(&b, "%d region(s) changed:", len(changed))
	for r in changed {
		fmt.sbprintfln(&b, "  %dx%d at (%d, %d)", int(r.w), int(r.h), int(r.x), int(r.y))
	}
	return strings.to_string(b)
}
