package render

import "core:math"
import "core:testing"
import bl "jm:ui/blend2d"
import "jm:ui"
import "jm:ui/ops"

// shadow_alphas renders one black shadow onto a clear 64x64 target under
// m and returns the target's alpha along row y.
@(private = "file")
shadow_alphas :: proc(m: ops.Affine, s: ops.Shadow, y: int) -> (row: [SIZE]u8) {
	r: Renderer
	init(&r)
	defer destroy(&r)
	sc: ops.Scene
	ops.init(&sc)
	defer ops.destroy(&sc)
	f: ui.Frame
	ui.frame_init(&f)
	defer ui.frame_destroy(&f)
	f.scene = &sc
	img: bl.ImageCore
	bl.image_init(&img)
	defer bl.image_destroy(&img)
	bl.image_create(&img, SIZE, SIZE, .PRGB32)
	append(&f.draws, ui.Draw{m, ui.NO_CLIP, s, 0})
	render(&r, &f, &img, {0, 0, 0, 0})
	for x in 0 ..< SIZE {
		row[x] = pixel(&img, x, y)[3]
	}
	return
}

@(test)
test_shadow_is_a_gaussian_of_its_rect :: proc(t: ^testing.T) {
	// A 32px square, blur 8: sigma 4, reaching 12px past each edge.
	s := ops.Shadow{{16, 16, 32, 32}, 0, 8, {0, 0, 0, 255}}
	row := shadow_alphas(ops.IDENTITY, s, 32)
	testing.expectf(t, row[32] >= 250, "centre %d, want solid", row[32])
	// Pixel 16 is centred half a pixel inside the edge: about half cover.
	testing.expectf(t, row[16] > 115 && row[16] < 150, "edge %d, want about half", row[16])
	testing.expectf(t, row[3] <= 2, "13px outside %d, want nothing", row[3])
	// Monotonic from the edge outward, and symmetric about the centre.
	for x in 4 ..< 16 {
		testing.expectf(t, row[x] <= row[x + 1], "not rising at %d: %d then %d", x, row[x], row[x + 1])
	}
	for x in 0 ..< SIZE / 2 {
		testing.expect_value(t, row[x], row[SIZE - 1 - x])
	}
}

@(test)
test_shadow_is_computed_at_device_resolution :: proc(t: ^testing.T) {
	// The same shadow in device pixels, drawn at half size under a 2x scale.
	plain := shadow_alphas(ops.IDENTITY, ops.Shadow{{16, 16, 32, 32}, 8, 8, {0, 0, 0, 255}}, 32)
	scaled := shadow_alphas(ops.scale(2, 2), ops.Shadow{{8, 8, 16, 16}, 4, 4, {0, 0, 0, 255}}, 32)
	testing.expectf(t, plain[32] >= 250 && plain[3] <= 2, "plain shadow %d at the centre, %d outside", plain[32], plain[3])
	for x in 0 ..< SIZE {
		testing.expectf(t, abs(int(plain[x]) - int(scaled[x])) <= 1, "x %d: %d plain, %d scaled", x, plain[x], scaled[x])
	}
}

@(test)
test_shadow_without_blur_is_its_shape :: proc(t: ^testing.T) {
	row := shadow_alphas(ops.IDENTITY, ops.Shadow{{16, 16, 32, 32}, 0, 0, {0, 0, 0, 128}}, 32)
	testing.expect_value(t, row[20], 128)
	testing.expect_value(t, row[8], 0)
}

@(test)
test_sliced_shadow_matches_one_computed_whole :: proc(t: ^testing.T) {
	r: Renderer
	init(&r)
	defer destroy(&r)
	// A card-sized shadow with rounded corners, sliced from its template.
	key := Shadow_Key{220, 150, 8, 10, {10, 20, 30, 200}}
	sliced := shadow_image(&r, key)
	testing.expect(t, sliced != nil)
	testing.expect(t, key.w >= 2 * corner_size(key.radius, key.sigma) + 1) // the sliced path
	whole: bl.ImageCore
	bl.image_init(&whole)
	defer bl.image_destroy(&whole)
	bl.image_create(&whole, key.w, key.h, .PRGB32)
	data: bl.ImageData
	bl.image_get_data(&whole, &data)
	reach := 3 * key.sigma
	fill_shadow(data, key.w, key.h, key, f32(key.w) - 2 * reach, f32(key.h) - 2 * reach)
	// Compared premultiplied, as the renderer blends them: straight colour
	// at a low alpha magnifies one step of rounding several times over.
	sdata: bl.ImageData
	bl.image_get_data(sliced, &sdata)
	worst := 0
	for y in 0 ..< int(key.h) {
		a := ([^][4]u8)(uintptr(sdata.pixel_data) + uintptr(y * int(sdata.stride)))
		b := ([^][4]u8)(uintptr(data.pixel_data) + uintptr(y * int(data.stride)))
		for x in 0 ..< int(key.w) {
			for c in 0 ..< 4 {
				worst = max(worst, abs(int(a[x][c]) - int(b[x][c])))
			}
		}
	}
	testing.expectf(t, worst <= 1, "sliced differs from whole by %d steps", worst)
}

@(test)
test_a_scaling_or_resizing_shadow_reuses_its_template :: proc(t: ^testing.T) {
	r: Renderer
	init(&r)
	defer destroy(&r)
	sc: ops.Scene
	ops.init(&sc)
	defer ops.destroy(&sc)
	f: ui.Frame
	ui.frame_init(&f)
	defer ui.frame_destroy(&f)
	f.scene = &sc
	img: bl.ImageCore
	bl.image_init(&img)
	defer bl.image_destroy(&img)
	bl.image_create(&img, SIZE, SIZE, .PRGB32)
	draw :: proc(r: ^Renderer, f: ^ui.Frame, img: ^bl.ImageCore, k: f32, w: f32) {
		clear(&f.draws)
		append(&f.draws, ui.Draw{ops.scale(k, k), ui.NO_CLIP, ops.Shadow{{0, 0, w, 300}, 8, 64, {0, 0, 0, 60}}, 0})
		render(r, f, img, {0, 0, 0, 0})
	}
	templates :: proc(r: ^Renderer) -> (n: int) {
		for k in r.shadows {
			n += int(k.w == 0)
		}
		return
	}
	// A dialog scaling in from 0.86: one resolution, so one template and
	// one full image throughout.
	for k in ([]f32{0.86, 0.93, 1}) {
		draw(&r, &f, &img, k, 600)
	}
	testing.expect_value(t, len(r.shadows), 2)
	testing.expect_value(t, templates(&r), 1)
	// Resized: a second full image, sliced from the same template.
	draw(&r, &f, &img, 1, 640)
	testing.expect_value(t, len(r.shadows), 3)
	testing.expect_value(t, templates(&r), 1)
}

// reference_erf is Abramowitz and Stegun 7.1.26, |error| < 1.5e-7, and
// reference_shadow the rounded-box integral at 64 points over four
// sigmas: the yardstick the shipped formulas are held to.
@(private = "file")
reference_erf :: proc(x: f32) -> f32 {
	s: f64 = x < 0 ? -1 : 1
	a := f64(abs(x))
	t := 1 / (1 + 0.3275911 * a)
	y := 1 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * math.exp(-a * a)
	return f32(s * y)
}

@(private = "file")
reference_shadow :: proc(half, p: [2]f32, sigma, corner: f32) -> f32 {
	row :: proc(x, y, sigma, corner: f32, half: [2]f32) -> f32 {
		delta := min(half.y - corner - abs(y), 0)
		curved := half.x - corner + math.sqrt(max(0, corner * corner - delta * delta))
		s := f32(math.SQRT_TWO) / 2 / sigma
		return 0.5 * (reference_erf((x + curved) * s) - reference_erf((x - curved) * s))
	}
	start := clamp(-4 * sigma, p.y - half.y, p.y + half.y)
	end := clamp(4 * sigma, p.y - half.y, p.y + half.y)
	step := (end - start) / 64
	y := start + step / 2
	v: f32
	for _ in 0 ..< 64 {
		v += row(p.x, p.y - y, sigma, corner, half) * gaussian(y, sigma) * step
		y += step
	}
	return v
}

@(test)
test_shadow_formulas_stay_near_the_reference :: proc(t: ^testing.T) {
	// Every radius and blur UI shadows use, on a small and a mid box, both
	// formulas exercised: separable where sigma >= 3 radius, integrated
	// otherwise. The worst in 8-bit alpha at full strength.
	worst: f32
	for r in ([]f32{0, 2, 4, 8, 12, 16, 28}) {
		for b in ([]f32{2, 4, 8, 16, 28, 64}) {
			for sz in ([][2]i32{{40, 40}, {120, 80}}) {
				sigma := b / 2
				reach := 3 * sigma
				key := Shadow_Key{i32(math.ceil(f32(sz.x) + 2 * reach)), i32(math.ceil(f32(sz.y) + 2 * reach)), min(r, f32(min(sz.x, sz.y)) / 2), sigma, {0, 0, 0, 255}}
				img: bl.ImageCore
				bl.image_init(&img)
				bl.image_create(&img, key.w, key.h, .PRGB32)
				data: bl.ImageData
				bl.image_get_data(&img, &data)
				bw, bh := f32(key.w) - 2 * reach, f32(key.h) - 2 * reach
				fill_shadow(data, key.w, key.h, key, bw, bh)
				for y := i32(0); y < key.h; y += 3 {
					px := ([^][4]u8)(uintptr(data.pixel_data) + uintptr(int(y) * int(data.stride)))
					for x := i32(0); x < key.w; x += 3 {
						p := [2]f32{f32(x) + 0.5 - f32(key.w) / 2, f32(y) + 0.5 - f32(key.h) / 2}
						want := reference_shadow({bw / 2, bh / 2}, p, sigma, key.radius) * 255
						worst = max(worst, abs(f32(px[x][3]) - want))
					}
				}
				bl.image_destroy(&img)
			}
		}
	}
	testing.expectf(t, worst <= 3, "worst %.2f alpha steps from the reference", worst)
}
