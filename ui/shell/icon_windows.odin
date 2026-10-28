#+build windows
package shell

import "core:log"
import win "core:sys/windows"
import sdl3 "vendor:sdl3"

// icon_present gives the window s as its icon, at s's own size. SDL builds
// the icon with CreateIconFromResource, which scales it to the system
// icon, 32px, so the taskbar receives that. This keeps the 256px mark.
@(private)
icon_present :: proc(w: ^Window, s: ^sdl3.Surface) -> bool {
	hwnd := window_hwnd(w)
	if hwnd == nil || s == nil {
		return false
	}
	icon := icon_hicon(s)
	if icon == nil {
		log.warn("ui/shell: icon: the window icon was not built")
		return false
	}
	_ = win.SendMessageW(hwnd, win.WM_SETICON, 0, win.LPARAM(uintptr(icon)))
	_ = win.SendMessageW(hwnd, win.WM_SETICON, 1, win.LPARAM(uintptr(icon)))
	if w.icon_handle != nil {
		_ = win.DestroyIcon(win.HICON(uintptr(w.icon_handle)))
	}
	w.icon_handle = rawptr(uintptr(icon))
	return true
}

// icon_release drops the icon icon_present installed. Windows does not
// copy the handle, so it is cleared off the window before it is destroyed.
@(private)
icon_release :: proc(w: ^Window) {
	if w == nil || w.icon_handle == nil {
		return
	}
	if hwnd := window_hwnd(w); hwnd != nil {
		_ = win.SendMessageW(hwnd, win.WM_SETICON, 0, 0)
		_ = win.SendMessageW(hwnd, win.WM_SETICON, 1, 0)
	}
	_ = win.DestroyIcon(win.HICON(uintptr(w.icon_handle)))
	w.icon_handle = nil
}

// icon_hicon copies s into an icon that keeps its alpha. s is RGBA.
@(private)
icon_hicon :: proc(s: ^sdl3.Surface) -> win.HICON {
	if s == nil || s.pixels == nil || s.w <= 0 || s.h <= 0 {
		return nil
	}
	bi: win.BITMAPV5HEADER
	bi.bV5Size = win.DWORD(size_of(bi))
	bi.bV5Width = win.LONG(s.w)
	bi.bV5Height = -win.LONG(s.h)
	bi.bV5Planes = 1
	bi.bV5BitCount = 32
	bi.bV5Compression = win.BI_BITFIELDS
	bi.bV5RedMask = 0x00ff0000
	bi.bV5GreenMask = 0x0000ff00
	bi.bV5BlueMask = 0x000000ff
	bi.bV5AlphaMask = 0xff000000

	hdc := win.GetDC(nil)
	defer win.ReleaseDC(nil, hdc)
	bits: rawptr
	color := win.CreateDIBSection(hdc, cast(^win.BITMAPINFO)rawptr(&bi), win.DIB_RGB_COLORS, &bits, nil, 0)
	if color == nil || bits == nil {
		if color != nil {
			_ = win.DeleteObject(win.HGDIOBJ(uintptr(color)))
		}
		return nil
	}
	defer win.DeleteObject(win.HGDIOBJ(uintptr(color)))

	locked := sdl3.MUSTLOCK(s)
	if locked && !sdl3.LockSurface(s) {
		return nil
	}
	defer if locked {
		sdl3.UnlockSurface(s)
	}
	src := ([^]byte)(s.pixels)
	dst := ([^]byte)(bits)
	for row in 0 ..< int(s.h) {
		sp := row * int(s.pitch)
		dp := row * int(s.w) * 4
		for col in 0 ..< int(s.w) {
			o := sp + col * 4
			r, g, b, a := int(src[o]), int(src[o + 1]), int(src[o + 2]), int(src[o + 3])
			d := dp + col * 4
			// Windows draws a 32-bit icon premultiplied.
			dst[d] = byte(b * a / 255)
			dst[d + 1] = byte(g * a / 255)
			dst[d + 2] = byte(r * a / 255)
			dst[d + 3] = byte(a)
		}
	}

	row := (int(s.w) + 15) / 16 * 2
	mask_bits := make([]byte, row * int(s.h))
	defer delete(mask_bits)
	mask := win.CreateBitmap(win.INT(s.w), win.INT(s.h), 1, 1, raw_data(mask_bits))
	if mask == nil {
		return nil
	}
	defer win.DeleteObject(win.HGDIOBJ(uintptr(mask)))

	ii: win.ICONINFO
	ii.fIcon = win.TRUE
	ii.hbmMask = mask
	ii.hbmColor = color
	return win.CreateIconIndirect(&ii)
}
