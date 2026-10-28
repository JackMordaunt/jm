package shell

import "core:log"
import sdl3 "vendor:sdl3"

// ICON_PX is the longest side of a window icon. A larger mark is scaled
// down; a smaller one is kept, so a 16px source is not blurred up.
@(private)
ICON_PX :: 256

// icon_destroy frees the surfaces icon_apply decoded, and the icon the
// window is showing.
@(private)
icon_destroy :: proc(w: ^Window) {
	if w == nil {
		return
	}
	icon_release(w)
	for &s in w.icon_surf {
		if s != nil {
			sdl3.DestroySurface(s)
			s = nil
		}
	}
}

// icon_apply sets the window icon for a dark or light window, from the
// PNG given at open. The mark is cropped to its ink. An empty PNG leaves
// the executable's icon.
@(private)
icon_apply :: proc(w: ^Window, dark: bool) {
	if w == nil || w.window == nil {
		return
	}
	s := icon_surface(w, dark)
	if s == nil {
		return
	}
	if !icon_present(w, s) {
		when ODIN_OS != .Windows {
			log.warnf("ui/shell: icon: %s", sdl3.GetError())
		}
	}
}

@(private)
icon_surface :: proc(w: ^Window, dark: bool) -> ^sdl3.Surface {
	i := 1 if dark else 0
	if w.icon_surf[i] != nil {
		return w.icon_surf[i]
	}
	png := w.icon_png[i]
	if len(png) == 0 {
		return nil
	}
	w.icon_surf[i] = icon_from_png(png)
	return w.icon_surf[i]
}

// icon_from_png decodes png, crops it to the ink and scales it down to
// ICON_PX. Nil when the bytes are not a PNG.
@(private)
icon_from_png :: proc(png: []byte) -> ^sdl3.Surface {
	if len(png) == 0 {
		return nil
	}
	io := sdl3.IOFromConstMem(raw_data(png), uint(len(png)))
	if io == nil {
		log.warnf("ui/shell: icon: %s", sdl3.GetError())
		return nil
	}
	loaded := sdl3.LoadPNG_IO(io, true)
	if loaded == nil {
		log.warnf("ui/shell: icon: %s", sdl3.GetError())
		return nil
	}
	rgba := sdl3.ConvertSurface(loaded, .RGBA32)
	if rgba == nil {
		sdl3.DestroySurface(loaded)
		log.warnf("ui/shell: icon: %s", sdl3.GetError())
		return nil
	}
	if rgba != loaded {
		sdl3.DestroySurface(loaded)
	}
	defer sdl3.DestroySurface(rgba)
	if rgba.pixels == nil || rgba.w <= 0 || rgba.h <= 0 || rgba.pitch < rgba.w * 4 {
		return nil
	}
	locked := sdl3.MUSTLOCK(rgba)
	if locked && !sdl3.LockSurface(rgba) {
		return nil
	}
	n := int(rgba.pitch) * int(rgba.h)
	buf := ([^]byte)(rgba.pixels)[:n]
	x, y, bw, bh := 0, 0, int(rgba.w), int(rgba.h)
	if bx, by, bw2, bh2, ok := icon_bounds(buf, int(rgba.w), int(rgba.h), int(rgba.pitch)); ok {
		x, y, bw, bh = bx, by, bw2, bh2
	}
	if locked {
		sdl3.UnlockSurface(rgba)
	}
	dst_w, dst_h := bw, bh
	long := max(bw, bh)
	if long > ICON_PX {
		dst_w = max(bw * ICON_PX / long, 1)
		dst_h = max(bh * ICON_PX / long, 1)
	}
	out := sdl3.CreateSurface(i32(dst_w), i32(dst_h), .RGBA32)
	if out == nil {
		log.warnf("ui/shell: icon: %s", sdl3.GetError())
		return nil
	}
	src := sdl3.Rect{i32(x), i32(y), i32(bw), i32(bh)}
	dst := sdl3.Rect{0, 0, i32(dst_w), i32(dst_h)}
	if !sdl3.BlitSurfaceScaled(rgba, &src, out, &dst, .LINEAR) {
		sdl3.DestroySurface(out)
		log.warnf("ui/shell: icon: %s", sdl3.GetError())
		return nil
	}
	return out
}

// icon_bounds is the tight box of pixels whose alpha is not 0, in RGBA
// rows of pitch bytes. A fully transparent image returns ok false.
@(private)
icon_bounds :: proc(pixels: []byte, width, height, pitch: int) -> (x, y, w, h: int, ok: bool) {
	if width <= 0 || height <= 0 || pitch < width * 4 || len(pixels) < height * pitch {
		return
	}
	min_x, min_y := width, height
	max_x, max_y := -1, -1
	for row in 0 ..< height {
		base := row * pitch
		for col in 0 ..< width {
			if pixels[base + col * 4 + 3] == 0 {
				continue
			}
			if col < min_x {
				min_x = col
			}
			if col > max_x {
				max_x = col
			}
			if row < min_y {
				min_y = row
			}
			if row > max_y {
				max_y = row
			}
		}
	}
	if max_x < 0 {
		return
	}
	return min_x, min_y, max_x - min_x + 1, max_y - min_y + 1, true
}
