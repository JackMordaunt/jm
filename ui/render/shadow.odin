package render

import "core:math"
import bl "jm:ui/blend2d"
import "jm:ui"
import "jm:ui/ops"

// A shadow is computed in closed form rather than by blurring pixels, by
// one of two formulas chosen by how wide the blur is against the corner.
// When sigma is at least three times the radius the corner's rounding is
// lost in the blur and the shadow is separable: an error-function profile
// along x times one along y, computed once per row and column, exact for
// a square corner. Otherwise it is the Gaussian blur of the rounded rect
// integrated along x with the error function and sampled along y (Evan
// Wallace, "Fast Rounded Rectangle Shadows", 2020) at 8 points, or 16
// where the corner is more than four sigmas, since a narrow blur on a
// wide corner crosses its curve quickly. Measured against a 64-sample
// reference at radii 0, 2, 4, 6, 8, 12, 16 and 28, blurs 2, 4, 8, 16, 28
// and 64 and boxes of 40, 120 and 600 wide, the worst coverage error was
// 0.0085, two steps of 8-bit alpha at full strength (the shipped
// four-sample formula's was 0.067); test_shadow_formulas_stay_near_the_
// reference holds it to three. The large blurs that make large templates
// take the cheap formula.
//
// Only a template is computed that way: the four corners of a shadow
// with this radius, blur and colour around a one-pixel middle row and
// column. Past its corners a rounded rect's shadow varies along one axis
// only, so a shadow of any size is the template's corners copied to its
// corners and the middle row and column repeated between them; resizing
// a surface costs a copy, not a recomputation. Both are made in the
// draw's local units at a power-of-two resolution at or above its device
// scale and blitted under the draw's transform, so a surface scaling
// through an animation keeps hitting the same image, and clips and the
// compositor's bands treat a shadow as they treat an image. A shape too
// small for its corners not to overlap (an avatar's circle) is computed
// whole.

// Shadow_Key is everything a shadow image depends on, in the pixels of
// its resolution. A template has w and h zero.
@(private)
Shadow_Key :: struct {
	w, h:          i32,
	radius, sigma: f32,
	color:         ops.Color,
}

// SHADOW_CACHE_BYTES bounds the pixels a Renderer keeps for shadows; past
// it the cache starts over.
@(private)
SHADOW_CACHE_BYTES :: 64 << 20

// draw_shadow paints s on ctx, whose transform is already d's.
@(private)
draw_shadow :: proc(r: ^Renderer, ctx: ^bl.ContextCore, d: ^ui.Draw, s: ops.Shadow) {
	if s.color[3] == 0 || s.rect.w <= 0 || s.rect.h <= 0 {
		return
	}
	if s.blur <= 0 {
		bl.context_set_fill_style_rgba32(ctx, rgba32(s.color))
		rr := round_rect(ops.Round_Rect{s.rect, s.radius})
		bl.context_fill_geometry(ctx, .ROUND_RECT, &rr)
		return
	}
	t := d.transform
	q := shadow_resolution(f32(math.sqrt(abs(t.a * t.d - t.b * t.c))))
	if q <= 0 {
		return
	}
	radius := min(s.radius, min(s.rect.w, s.rect.h) / 2) * q
	sigma := s.blur / 2 * q
	reach := 3 * sigma
	w := i32(math.ceil(s.rect.w * q + 2 * reach))
	h := i32(math.ceil(s.rect.h * q + 2 * reach))
	img := shadow_image(r, {w, h, radius, sigma, s.color})
	if img == nil {
		return
	}
	// The image is centred on the rect; its local size is its pixels over q.
	iw, ih := f32(w) / q, f32(h) / q
	cx, cy := s.rect.x + s.rect.w / 2, s.rect.y + s.rect.h / 2
	dst := bl.Rect{f64(cx - iw / 2), f64(cy - ih / 2), f64(iw), f64(ih)}
	bl.context_blit_scaled_image_d(ctx, &dst, img, nil)
}

// shadow_resolution is the power of two at or above device scale k that
// a shadow is made at, from 1/8 up: fine enough that blitting it down to
// k loses nothing a soft shadow shows, coarse enough that a scale moving
// through an animation stays on one image.
@(private)
shadow_resolution :: proc(k: f32) -> f32 {
	if k <= 0 {
		return 0
	}
	q: f32 = 0.125
	for q < k {
		q *= 2
	}
	return q
}

// corner_size is the template's corner in pixels: the reach outside the
// edge, the radius and the reach again inside it, past which the shadow
// no longer depends on the corner.
@(private)
corner_size :: proc(radius, sigma: f32) -> i32 {
	return i32(math.ceil(radius + 6 * sigma))
}

// shadow_image is key's image, computed or copied from its template on
// first use.
@(private)
shadow_image :: proc(r: ^Renderer, key: Shadow_Key) -> ^bl.ImageCore {
	if img, ok := &r.shadows[key]; ok {
		return img
	}
	cw := corner_size(key.radius, key.sigma)
	if key.w == 0 || key.w < 2 * cw + 1 || key.h < 2 * cw + 1 {
		// A template, or a shape too small to slice: computed whole.
		w, h := key.w, key.h
		if w == 0 {
			w, h = 2 * cw + 1, 2 * cw + 1
		}
		img, ok := new_shadow_image(r, key, w, h)
		if !ok {
			return nil
		}
		data: bl.ImageData
		bl.image_get_data(img, &data)
		reach := 3 * key.sigma
		fill_shadow(data, w, h, {w, h, key.radius, key.sigma, key.color}, f32(w) - 2 * reach, f32(h) - 2 * reach)
		return img
	}
	// Make room first: starting the cache over after the template is
	// fetched would free the pixels about to be copied.
	t := 2 * cw + 1
	if r.shadow_bytes + (int(key.w) * int(key.h) + int(t) * int(t)) * 4 > SHADOW_CACHE_BYTES {
		clear_shadows(r)
	}
	tpl := shadow_image(r, {0, 0, key.radius, key.sigma, key.color})
	if tpl == nil {
		return nil
	}
	// An ImageCore is one pointer to Blend2D's reference-counted impl,
	// which owns the pixels (blend2d/image.odin ImageCore, object.odin
	// ObjectDetail), so the pixels stay put when the map grows and moves
	// the ImageCore.
	tdata: bl.ImageData
	bl.image_get_data(tpl, &tdata)
	tstride, tbase := int(tdata.stride), uintptr(tdata.pixel_data)
	img, ok := new_shadow_image(r, key, key.w, key.h, evict = false)
	if !ok {
		return nil
	}
	data: bl.ImageData
	bl.image_get_data(img, &data)
	slice_shadow(data, key.w, key.h, tbase, tstride, cw)
	return img
}

// new_shadow_image makes a w by h image in r's cache under key, starting
// the cache over first when it would pass SHADOW_CACHE_BYTES, unless
// evict is false because the caller made room and holds another image.
@(private)
new_shadow_image :: proc(r: ^Renderer, key: Shadow_Key, w, h: i32, evict := true) -> (^bl.ImageCore, bool) {
	if w <= 0 || h <= 0 || w > 8192 || h > 8192 {
		return nil, false
	}
	bytes := int(w) * int(h) * 4
	if evict && r.shadow_bytes + bytes > SHADOW_CACHE_BYTES {
		clear_shadows(r)
	}
	img: bl.ImageCore
	bl.image_init(&img)
	if bl.image_create(&img, w, h, .PRGB32) != 0 {
		bl.image_destroy(&img)
		return nil, false
	}
	r.shadows[key] = img
	r.shadow_bytes += bytes
	return &r.shadows[key], true
}

// slice_shadow fills the w by h pixels of data from the template at tbase
// (2cw+1 square, stride tstride): each row takes the template's row for
// its place, cw rows from the top or bottom or else the middle one, and
// within it the template's left cw pixels, its middle pixel repeated, and
// its right cw pixels.
@(private)
slice_shadow :: proc(data: bl.ImageData, w, h: i32, tbase: uintptr, tstride: int, cw: i32) {
	stride, base := int(data.stride), uintptr(data.pixel_data)
	for y in 0 ..< h {
		ty := y < cw ? y : (y >= h - cw ? y - (h - cw) + cw + 1 : cw)
		src := ([^]u32)(tbase + uintptr(int(ty) * tstride))
		dst := ([^]u32)(base + uintptr(int(y) * stride))
		for x in 0 ..< cw {
			dst[x] = src[x]
			dst[w - cw + x] = src[cw + 1 + x]
		}
		mid := src[cw]
		for x in cw ..< w - cw {
			dst[x] = mid
		}
	}
}

// fill_shadow writes key's shadow into the w by h pixels of data, a box
// of bw by bh centred. The shadow is symmetric about both centre lines,
// so one quadrant is computed and mirrored into the other three.
@(private)
fill_shadow :: proc(data: bl.ImageData, w, h: i32, key: Shadow_Key, bw, bh: f32) {
	half := [2]f32{bw / 2, bh / 2}
	a := f32(key.color[3]) / 255
	cr, cg, cb := f32(key.color[0]), f32(key.color[1]), f32(key.color[2])
	stride := int(data.stride)
	base := uintptr(data.pixel_data)
	put :: proc(base: uintptr, stride: int, x, y: i32, v: u32) {
		(^u32)(base + uintptr(int(y) * stride + int(x) * 4))^ = v
	}
	separable := key.sigma >= 3 * key.radius
	n := shadow_sample_count(key.sigma, key.radius)
	// The separable profiles, one entry per column and row of the quadrant.
	cols := make([]f32, (w + 1) / 2)
	defer delete(cols)
	rows := make([]f32, (h + 1) / 2)
	defer delete(rows)
	if separable {
		for &c, x in cols {
			c = edge_profile(f32(x) + 0.5 - f32(w) / 2, half.x, key.sigma)
		}
		for &r, y in rows {
			r = edge_profile(f32(y) + 0.5 - f32(h) / 2, half.y, key.sigma)
		}
	}
	for y in 0 ..< (h + 1) / 2 {
		py := f32(y) + 0.5 - f32(h) / 2
		for x in 0 ..< (w + 1) / 2 {
			px := f32(x) + 0.5 - f32(w) / 2
			cover := separable ? cols[x] * rows[y] : rounded_box_shadow(half, {px, py}, key.sigma, key.radius, n)
			al := clamp(a * cover, 0, 1)
			v := u32(al * 255 + 0.5) << 24 | u32(cr * al + 0.5) << 16 | u32(cg * al + 0.5) << 8 | u32(cb * al + 0.5)
			put(base, stride, x, y, v)
			put(base, stride, w - 1 - x, y, v)
			put(base, stride, x, h - 1 - y, v)
			put(base, stride, w - 1 - x, h - 1 - y, v)
		}
	}
}

// shadow_sample_count is how many points along y rounded_box_shadow takes: 8,
// or 16 when the corner is more than four sigmas, where a narrow blur
// crosses the corner's curve quickly.
@(private)
shadow_sample_count :: proc(sigma, corner: f32) -> int {
	return corner <= 4 * sigma ? 8 : 16
}

// edge_profile is the blurred coverage along one axis at p, relative to
// the centre, of a span of half size half: the separable shadow's factor.
@(private)
edge_profile :: proc(p, half, sigma: f32) -> f32 {
	s := f32(math.SQRT_TWO) / 2 / sigma
	return 0.5 * (erf((p + half) * s) - erf((p - half) * s))
}

// rounded_box_shadow is the coverage at p, relative to the centre, of a
// rounded box of half size half and corner radius corner blurred by a
// Gaussian of sigma, integrated along y at n points.
@(private)
rounded_box_shadow :: proc(half: [2]f32, p: [2]f32, sigma, corner: f32, n: int) -> f32 {
	low, high := p.y - half.y, p.y + half.y
	start := clamp(-3 * sigma, low, high)
	end := clamp(3 * sigma, low, high)
	step := (end - start) / f32(n)
	y := start + step / 2
	value: f32
	for _ in 0 ..< n {
		value += box_shadow_x(p.x, p.y - y, sigma, corner, half) * gaussian(y, sigma) * step
		y += step
	}
	return value
}

// box_shadow_x is the blurred coverage along x of the box's row at y.
@(private)
box_shadow_x :: proc(x, y, sigma, corner: f32, half: [2]f32) -> f32 {
	delta := min(half.y - corner - abs(y), 0)
	curved := half.x - corner + math.sqrt(max(0, corner * corner - delta * delta))
	s := f32(math.SQRT_TWO) / 2 / sigma
	return 0.5 * (erf((x + curved) * s) - erf((x - curved) * s))
}

@(private)
gaussian :: proc(x, sigma: f32) -> f32 {
	return math.exp(-(x * x) / (2 * sigma * sigma)) / (math.sqrt(f32(2 * math.PI)) * sigma)
}

// erf is the error function to about 5e-4 (Abramowitz and Stegun 7.1.27),
// ample for 8-bit coverage.
@(private)
erf :: proc(x: f32) -> f32 {
	s: f32 = x < 0 ? -1 : 1
	a := abs(x)
	t := 1 + (0.278393 + (0.230389 + 0.078108 * (a * a)) * a) * a
	t *= t
	return s - s / (t * t)
}

// clear_shadows drops every cached shadow image.
@(private)
clear_shadows :: proc(r: ^Renderer) {
	for _, &img in r.shadows {
		bl.image_destroy(&img)
	}
	clear(&r.shadows)
	r.shadow_bytes = 0
}
