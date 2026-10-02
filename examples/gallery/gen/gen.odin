/*
Package gen makes a tile's picture: a Julia set whose parameters come from
the tile's index, so every tile differs and the same index always gives
the same picture. It is slow on purpose, by being real work: a pixel costs
up to ITERATIONS steps, so a tile takes long enough to see loading, and
the work checks a cancel flag every row and stops once it is set, so a
tile the ui no longer needs costs little more than the rows it got to.

The picture is written as a BMP, 54 bytes of header and the pixels, so
writing it needs no codec.
*/
package gallery_gen

import "core:fmt"
import "core:math"
import "core:os"
import "core:sync"

ITERATIONS :: 8000

// tile writes the picture for index at px by px to path, with at most
// iterations steps a pixel. False when cancel^ was set before it
// finished, or the file could not be written.
tile :: proc(index, px: int, path: string, cancel: ^bool, iterations := ITERATIONS) -> bool {
	pixels := make([]u32, px * px)
	defer delete(pixels)
	if !render(index, px, pixels, cancel, iterations) {
		return false
	}
	return write_bmp(path, px, px, pixels)
}

// render fills pixels, px by px, with the whole picture: the plane from
// -1.5 to 1.5 each way.
render :: proc(index, px: int, pixels: []u32, cancel: ^bool, iterations := ITERATIONS) -> bool {
	return region(index, px, -1.5, -1.5, 3, pixels, cancel, iterations)
}

// patch writes the square x, y of the picture at level to path, px by px:
// the plane split 2^level ways each way. A deep level is a deep zoom,
// and the same point gives the same colour at every level, so patches
// tile seamlessly over the picture they refine.
patch :: proc(index, level, x, y, px: int, path: string, cancel: ^bool, iterations := ITERATIONS) -> bool {
	pixels := make([]u32, px * px)
	defer delete(pixels)
	size := 3 / math.pow(2, f64(level))
	if !region(index, px, -1.5 + f64(x) * size, -1.5 + f64(y) * size, size, pixels, cancel, iterations) {
		return false
	}
	return write_bmp(path, px, px, pixels)
}

// region fills pixels, px by px, with the square of the plane at x0, y0
// of side size, row by row, giving up when cancel^ is set. Each row's
// cost is the loop's; the check costs one atomic load.
region :: proc(index, px: int, x0, y0, size: f64, pixels: []u32, cancel: ^bool, iterations := ITERATIONS) -> bool {
	cx, cy, hue := params(index)
	for row in 0 ..< px {
		if cancel != nil && sync.atomic_load(cancel) {
			return false
		}
		y := y0 + (f64(row) + 0.5) / f64(px) * size
		for col in 0 ..< px {
			x := x0 + (f64(col) + 0.5) / f64(px) * size
			zx, zy := x, y
			n := 0
			for ; n < iterations && zx * zx + zy * zy < 4; n += 1 {
				zx, zy = zx * zx - zy * zy + cx, 2 * zx * zy + cy
			}
			pixels[row * px + col] = shade(n, iterations, hue)
		}
	}
	return true
}

// params is the Julia constant and the palette hue for index: constants
// along the boundary of the Mandelbrot set, where the pictures are rich.
@(private)
params :: proc(index: int) -> (cx, cy, hue: f64) {
	t := f64(index) * 0.618033988749895
	t -= math.floor(t)
	angle := t * 2 * math.PI
	// A point on the main cardioid, nudged outward: filaments, not a blob.
	cx = 0.5 * math.cos(angle) - 0.25 * math.cos(2 * angle) + 0.02 * math.cos(3 * angle)
	cy = 0.5 * math.sin(angle) - 0.25 * math.sin(2 * angle) + 0.02 * math.sin(3 * angle)
	hue = t
	return
}

// shade is the colour of a pixel that escaped after n steps, as BGRA for
// the BMP: black inside the set, a hue cycling outside.
@(private)
shade :: proc(n, iterations: int, hue: f64) -> u32 {
	if n >= iterations {
		return 0xFF000000
	}
	t := math.pow(f64(n) / f64(iterations), 0.35)
	r, g, b := hsv_to_rgb(hue + t * 1.5, 0.85, 0.35 + 0.65 * t)
	return 0xFF000000 | u32(r) << 16 | u32(g) << 8 | u32(b)
}

@(private)
hsv_to_rgb :: proc(hue, s, v: f64) -> (r, g, b: u8) {
	h := hue - math.floor(hue)
	sector := int(h * 6)
	f := h * 6 - f64(sector)
	p, q, t := v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
	rf, gf, bf: f64
	switch sector % 6 {
	case 0:
		rf, gf, bf = v, t, p
	case 1:
		rf, gf, bf = q, v, p
	case 2:
		rf, gf, bf = p, v, t
	case 3:
		rf, gf, bf = p, q, v
	case 4:
		rf, gf, bf = t, p, v
	case 5:
		rf, gf, bf = v, p, q
	}
	return u8(rf * 255), u8(gf * 255), u8(bf * 255)
}

// write_bmp writes pixels, width by height BGRA, as a 32-bit BMP.
write_bmp :: proc(path: string, width, height: int, pixels: []u32) -> bool {
	row := width * 4
	size := 54 + row * height
	data := make([]u8, size)
	defer delete(data)
	put :: proc(d: []u8, at: int, v: u32) {
		d[at] = u8(v)
		d[at + 1] = u8(v >> 8)
		d[at + 2] = u8(v >> 16)
		d[at + 3] = u8(v >> 24)
	}
	data[0], data[1] = 'B', 'M'
	put(data, 2, u32(size))
	put(data, 10, 54)
	put(data, 14, 40)
	put(data, 18, u32(width))
	put(data, 22, u32(-height)) // top-down rows
	data[26], data[28] = 1, 32
	put(data, 34, u32(row * height))
	for p, ii in pixels {
		put(data, 54 + ii * 4, p)
	}
	if err := os.write_entire_file(path, data); err != nil {
		fmt.eprintln("gallery: write:", path, err)
		return false
	}
	return true
}
