#+build windows
package shell

import "base:runtime"
import "core:log"
import win "core:sys/windows"
import sdl3 "vendor:sdl3"

import "jm:ui"
import "jm:ui/ops"

// DwmDefWindowProc and RemoveWindowSubclass are not in core:sys/windows.
// Bound here: this tree does not patch the core collection. Core's
// SetWindowSubclass drops the BOOL, and a second foreign declaration of
// that symbol is rejected, so the one that returns it is loaded below.
foreign import dwmapi "system:Dwmapi.lib"
foreign import comctl32 "system:Comctl32.lib"

@(default_calling_convention = "system")
foreign dwmapi {
	DwmDefWindowProc :: proc(hwnd: win.HWND, msg: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM, result: ^win.LRESULT) -> win.BOOL ---
}

@(default_calling_convention = "system")
foreign comctl32 {
	RemoveWindowSubclass :: proc(hwnd: win.HWND, pfn: win.SUBCLASSPROC, id: win.UINT_PTR) -> win.BOOL ---
}

// Set_Window_Subclass is SetWindowSubclass with its BOOL kept.
@(private)
Set_Window_Subclass :: #type proc "system" (hwnd: win.HWND, pfn: win.SUBCLASSPROC, id: win.UINT_PTR, ref: win.DWORD_PTR) -> win.BOOL

@(private)
title_set: Set_Window_Subclass

// title_load_set resolves SetWindowSubclass once. The library is left
// loaded: title_set points into it.
@(private)
title_load_set :: proc() -> Set_Window_Subclass {
	if title_set != nil {
		return title_set
	}
	lib := win.LoadLibraryW(win.L("Comctl32.dll"))
	if lib == nil {
		return nil
	}
	p := win.GetProcAddress(lib, "SetWindowSubclass")
	if p == nil {
		return nil
	}
	title_set = cast(Set_Window_Subclass)p
	return title_set
}

// 'jmtb'. AccessKit subclasses the same HWND later, so it runs first.
@(private)
TITLE_SUBCLASS_ID :: win.UINT_PTR(0x6A6D7462)

@(private)
title_attach :: proc(w: ^Window) -> bool {
	if (w.title_mode != .Unified && w.title_mode != .Drawn) || w.window == nil {
		return true
	}
	raw := sdl3.GetPointerProperty(sdl3.GetWindowProperties(w.window), sdl3.PROP_WINDOW_WIN32_HWND_POINTER, nil)
	if raw == nil {
		log.warn("ui/shell: no HWND for the unified title bar")
		return false
	}
	// Set before the subclass: the frame change below sends NCCALCSIZE.
	w.hwnd = raw
	w.title_on = true
	hwnd := title_hwnd(raw)
	set := title_load_set()
	if set == nil || set(hwnd, title_proc, TITLE_SUBCLASS_ID, win.DWORD_PTR(uintptr(w))) == win.FALSE {
		w.hwnd = nil
		w.title_on = false
		log.warn("ui/shell: SetWindowSubclass failed; the title bar stays the system's")
		return false
	}
	_ = win.SetWindowPos(
		hwnd,
		nil,
		0,
		0,
		0,
		0,
		win.UINT(win.SWP_FRAMECHANGED | win.SWP_NOSIZE | win.SWP_NOMOVE | win.SWP_NOZORDER | win.SWP_NOACTIVATE),
	)
	title_cache(w)
	return true
}

@(private)
title_detach :: proc(w: ^Window) {
	if !w.title_on {
		return
	}
	w.title_on = false
	hwnd := title_hwnd(w.hwnd)
	w.hwnd = nil
	if hwnd != nil {
		_ = RemoveWindowSubclass(hwnd, title_proc, TITLE_SUBCLASS_ID)
	}
}

// title_metrics is the caption in window points. Zero when the mode is
// off, the subclass is not installed, or the window has no caption
// (fullscreen). active is whether the window is in front. Under Drawn,
// pressed is reported only while the pointer is still over that button.
@(private)
title_metrics :: proc(w: ^Window) -> ui.Title_Bar {
	if (w.title_mode != .Unified && w.title_mode != .Drawn) || !w.title_on || w.hwnd == nil {
		return {}
	}
	title_cache(w)
	if w.buttons_px.w <= 0 || w.buttons_px.h <= 0 {
		return {}
	}
	d := w.density if w.density > 0 else 1
	return {
		height = (w.buttons_px.y + w.buttons_px.h) / d,
		buttons = {
			w.buttons_px.x / d,
			w.buttons_px.y / d,
			w.buttons_px.w / d,
			w.buttons_px.h / d,
		},
		maximized = w.maximized,
		active = win.GetForegroundWindow() == title_hwnd(w.hwnd),
		drawn = w.title_mode == .Drawn,
		hover = w.caption_hover,
		pressed = w.caption_pressed if w.caption_pressed == w.caption_hover else .None,
	}
}

// title_proc is called by Windows with no Odin context. "system" is the
// subclass convention and does not pass one; this body does not read it.
title_proc :: proc "system" (
	hwnd: win.HWND,
	msg: win.UINT,
	wparam: win.WPARAM,
	lparam: win.LPARAM,
	_: win.UINT_PTR,
	ref: win.DWORD_PTR,
) -> win.LRESULT {
	w := (^Window)(uintptr(ref))
	if w == nil || !w.title_on {
		return win.DefSubclassProc(hwnd, msg, wparam, lparam)
	}
	switch msg {
	case win.WM_NCCALCSIZE:
		return title_nccalc(hwnd, wparam, lparam)
	case win.WM_NCHITTEST:
		return title_nchit(w, hwnd, lparam)
	case win.WM_GETDPISCALEDSIZE:
		if scaled, ok := title_dpi_size(hwnd, wparam, lparam); ok {
			return scaled
		}
		return win.DefSubclassProc(hwnd, msg, wparam, lparam)
	case win.WM_DPICHANGED:
		title_dpi_changed(w, hwnd, wparam, lparam)
		return 0
	case win.WM_SIZE:
		title_cache(w)
	case win.WM_NCMOUSEMOVE, win.WM_NCMOUSELEAVE, win.WM_NCLBUTTONDOWN, win.WM_NCLBUTTONDBLCLK, win.WM_NCLBUTTONUP:
		if w.title_mode == .Drawn && title_caption_mouse(w, hwnd, msg, wparam) {
			return 0
		}
	}
	return win.DefSubclassProc(hwnd, msg, wparam, lparam)
}

// title_caption_mouse follows the pointer over a Drawn frame's caption
// buttons, which the hit test reports as HTMINBUTTON, HTMAXBUTTON and
// HTCLOSE. A press over a button is kept here, so DefWindowProc does not
// run its own button loop; a release over the same button performs it
// through WM_SYSCOMMAND. Leaving the buttons drops both. Returns whether
// the message was taken. Moves are passed on: Windows 11 opens snap
// layouts from them.
@(private)
title_caption_mouse :: proc "contextless" (w: ^Window, hwnd: win.HWND, msg: win.UINT, wparam: win.WPARAM) -> bool {
	b := title_caption_button(wparam)
	switch msg {
	case win.WM_NCMOUSELEAVE:
		w.caption_tracking = false
		title_caption_set(w, .None, .None)
		return false
	case win.WM_NCMOUSEMOVE:
		if !w.caption_tracking && b != .None {
			tme := win.TRACKMOUSEEVENT {
				cbSize    = size_of(win.TRACKMOUSEEVENT),
				dwFlags   = win.TME_LEAVE | win.TME_NONCLIENT,
				hwndTrack = hwnd,
			}
			w.caption_tracking = win.TrackMouseEvent(&tme) == win.TRUE
		}
		title_caption_set(w, b, w.caption_pressed if b != .None else .None)
		return false
	case win.WM_NCLBUTTONDOWN, win.WM_NCLBUTTONDBLCLK:
		if b == .None {
			title_caption_set(w, w.caption_hover, .None)
			return false
		}
		title_caption_set(w, b, b)
		return true
	case win.WM_NCLBUTTONUP:
		held := w.caption_pressed
		title_caption_set(w, b, .None)
		if b == .None {
			return false
		}
		if b == held {
			title_caption_perform(hwnd, b)
		}
		return true
	}
	return false
}

// title_caption_button is the caption button a non-client hit code names.
@(private)
title_caption_button :: proc "contextless" (hit: win.WPARAM) -> ops.Caption_Button {
	switch win.LRESULT(hit) {
	case win.HTMINBUTTON:
		return .Minimize
	case win.HTMAXBUTTON:
		return .Maximize
	case win.HTCLOSE:
		return .Close
	}
	return .None
}

// title_caption_set records hover and pressed, and asks for a frame that
// shows them when either changed.
@(private)
title_caption_set :: proc "contextless" (w: ^Window, hover, pressed: ops.Caption_Button) {
	if w.caption_hover == hover && w.caption_pressed == pressed {
		return
	}
	w.caption_hover, w.caption_pressed = hover, pressed
	context = runtime.default_context()
	wake()
}

// title_caption_perform does what button does, as the system's own
// caption buttons would.
@(private)
title_caption_perform :: proc "contextless" (hwnd: win.HWND, button: ops.Caption_Button) {
	command: win.WPARAM
	switch button {
	case .None:
		return
	case .Minimize:
		command = win.SC_MINIMIZE
	case .Maximize:
		command = win.SC_RESTORE if win.IsZoomed(hwnd) == win.TRUE else win.SC_MAXIMIZE
	case .Close:
		command = win.SC_CLOSE
	}
	_ = win.PostMessageW(hwnd, win.WM_SYSCOMMAND, command, 0)
}

@(private)
title_nccalc :: proc "contextless" (hwnd: win.HWND, wparam: win.WPARAM, lparam: win.LPARAM) -> win.LRESULT {
	if wparam == 0 {
		return win.DefSubclassProc(hwnd, win.WM_NCCALCSIZE, wparam, lparam)
	}
	params := (^win.NCCALCSIZE_PARAMS)(uintptr(lparam))
	if params == nil {
		return win.DefSubclassProc(hwnd, win.WM_NCCALCSIZE, wparam, lparam)
	}
	saved := params.rgrc[0]
	ret := win.DefSubclassProc(hwnd, win.WM_NCCALCSIZE, wparam, lparam)
	// Fullscreen drops WS_CAPTION. A minimized window keeps DefWindowProc's rect.
	if !title_has_caption(hwnd) || win.IsIconic(hwnd) == win.TRUE {
		return ret
	}
	if win.IsZoomed(hwnd) == win.TRUE {
		dpi := title_dpi(hwnd)
		x := title_frame(dpi, win.SM_CXFRAME)
		y := title_frame(dpi, win.SM_CYFRAME)
		params.rgrc[0].left = saved.left + x
		params.rgrc[0].right = saved.right - x
		params.rgrc[0].top = saved.top + y
		params.rgrc[0].bottom = saved.bottom - y
	} else {
		// The top resize border moves into the client. Left, right and
		// bottom stay non-client, which is what DefWindowProc computed.
		params.rgrc[0].top = saved.top
	}
	return 0
}

// title_nchit hit-tests the caption. Under Drawn the frame's own buttons
// stand in for the platform's: DWM's, which it does not draw there, are
// not asked.
@(private)
title_nchit :: proc "contextless" (w: ^Window, hwnd: win.HWND, lparam: win.LPARAM) -> win.LRESULT {
	drawn := w.title_mode == .Drawn
	handled: win.LRESULT
	if !drawn && DwmDefWindowProc(hwnd, win.WM_NCHITTEST, 0, lparam, &handled) == win.TRUE {
		return handled
	}
	def := win.DefSubclassProc(hwnd, win.WM_NCHITTEST, 0, lparam)
	if title_keep(def, drawn) {
		return def
	}
	pt := win.POINT{win.LONG(win.GET_X_LPARAM(lparam)), win.LONG(win.GET_Y_LPARAM(lparam))}
	_ = win.ScreenToClient(hwnd, &pt)
	slot := w.drag_read
	if slot != 0 && slot != 1 {
		slot = 0
	}
	n := w.drag_n[slot]
	if n < 0 {
		n = 0
	}
	if n > TITLE_DRAG_CAP {
		n = TITLE_DRAG_CAP
	}
	m := w.drawn_n[slot]
	if m < 0 {
		m = 0
	}
	if m > TITLE_BUTTON_CAP {
		m = TITLE_BUTTON_CAP
	}
	buttons := w.buttons_px
	if drawn {
		buttons = {}
	}
	hit := title_hit({f32(pt.x), f32(pt.y)}, w.client_px, buttons, w.border_px, w.drags[slot][:n], w.rtl, w.drawn[slot][:m])
	if hit == .Client {
		return def
	}
	return title_hit_code(hit)
}

// title_dpi_size corrects the linearly scaled window size. The client
// includes the caption, so the frame added back has no top. Returns false
// when the dpi is unknown, and the caller lets SDL handle the message.
@(private)
title_dpi_size :: proc "contextless" (hwnd: win.HWND, wparam: win.WPARAM, lparam: win.LPARAM) -> (win.LRESULT, bool) {
	new_dpi := win.UINT(uintptr(wparam))
	if new_dpi == 0 {
		return 0, false
	}
	old_dpi := win.GetDpiForWindow(hwnd)
	if old_dpi == 0 {
		return 0, false
	}
	size := (^win.SIZE)(uintptr(lparam))
	if size == nil {
		return 0, false
	}
	ox := title_frame(old_dpi, win.SM_CXFRAME)
	oy := title_frame(old_dpi, win.SM_CYFRAME)
	nx := title_frame(new_dpi, win.SM_CXFRAME)
	ny := title_frame(new_dpi, win.SM_CYFRAME)
	cw := size.cx - 2 * ox
	ch := size.cy - oy
	if cw < 0 {
		cw = 0
	}
	if ch < 0 {
		ch = 0
	}
	size.cx = cw + 2 * nx
	size.cy = ch + ny
	return 1, true
}

// title_dpi_changed sizes the window from the client, not from SDL's
// AdjustWindowRect, which would add a caption the client already holds.
// It does not call DefSubclassProc.
@(private)
title_dpi_changed :: proc "contextless" (w: ^Window, hwnd: win.HWND, wparam: win.WPARAM, lparam: win.LPARAM) {
	new_dpi := win.UINT(win.HIWORD(int(uintptr(wparam))))
	if new_dpi == 0 {
		new_dpi = 96
	}
	old_dpi := w.dpi
	if old_dpi == 0 {
		old_dpi = u32(new_dpi)
	}
	suggested := (^win.RECT)(uintptr(lparam))
	client: win.RECT
	_ = win.GetClientRect(hwnd, &client)
	cw := client.right - client.left
	ch := client.bottom - client.top
	if u32(new_dpi) != old_dpi {
		cw = win.LONG((i64(cw) * i64(new_dpi)) / i64(old_dpi))
		ch = win.LONG((i64(ch) * i64(new_dpi)) / i64(old_dpi))
	}
	fx := title_frame(new_dpi, win.SM_CXFRAME)
	fy := title_frame(new_dpi, win.SM_CYFRAME)
	x, y: win.INT
	if suggested != nil {
		x, y = win.INT(suggested.left), win.INT(suggested.top)
	}
	_ = win.SetWindowPos(hwnd, nil, x, y, win.INT(cw + 2 * fx), win.INT(ch + fy), win.UINT(win.SWP_NOZORDER | win.SWP_NOACTIVATE))
	title_cache(w)
	w.dpi = u32(new_dpi)
}

// title_cache refreshes the pixel facts the hit test reads, and extends
// the frame into the caption when that height changes.
@(private)
title_cache :: proc "contextless" (w: ^Window) {
	if w == nil || !w.title_on || w.hwnd == nil {
		return
	}
	hwnd := title_hwnd(w.hwnd)
	if dpi := win.GetDpiForWindow(hwnd); dpi != 0 {
		w.dpi = u32(dpi)
	}
	cr: win.RECT
	_ = win.GetClientRect(hwnd, &cr)
	w.client_px = {f32(cr.right - cr.left), f32(cr.bottom - cr.top)}
	w.maximized = win.IsZoomed(hwnd) == win.TRUE
	ex := u32(win.GetWindowLongW(hwnd, win.GWL_EXSTYLE))
	w.rtl = ex & u32(win.WS_EX_LAYOUTRTL) != 0
	if !title_has_caption(hwnd) || win.IsIconic(hwnd) == win.TRUE {
		w.buttons_px = {}
		w.border_px = 0
		title_extend(w, hwnd, 0)
		return
	}
	if w.maximized {
		w.border_px = 0
	} else {
		w.border_px = f32(title_frame(title_dpi(hwnd), win.SM_CYFRAME))
	}
	if !title_buttons(w, hwnd) {
		title_buttons_fallback(w, hwnd)
	}
	// Drawn draws its own buttons: the frame is not extended, so DWM has
	// nowhere to draw its own.
	if w.title_mode == .Drawn {
		title_extend(w, hwnd, 0)
		return
	}
	cy := i32(w.buttons_px.y + w.buttons_px.h)
	if cy < 0 {
		cy = 0
	}
	ch := i32(w.client_px.y)
	if ch > 0 && cy > ch {
		cy = ch
	}
	title_extend(w, hwnd, cy)
}

@(private)
title_buttons :: proc "contextless" (w: ^Window, hwnd: win.HWND) -> bool {
	bounds: win.RECT
	hr := win.DwmGetWindowAttribute(
		hwnd,
		win.DWORD(win.DWMWINDOWATTRIBUTE.DWMWA_CAPTION_BUTTON_BOUNDS),
		rawptr(&bounds),
		win.DWORD(size_of(bounds)),
	)
	if hr < 0 || bounds.right <= bounds.left || bounds.bottom <= bounds.top {
		return false
	}
	wr: win.RECT
	if win.GetWindowRect(hwnd, &wr) == win.FALSE {
		return false
	}
	// The attribute is relative to the window's top-left, not the client's.
	origin := win.POINT{wr.left, wr.top}
	if win.ScreenToClient(hwnd, &origin) == win.FALSE {
		return false
	}
	w.buttons_px = {
		f32(bounds.left + origin.x),
		f32(bounds.top + origin.y),
		f32(bounds.right - bounds.left),
		f32(bounds.bottom - bounds.top),
	}
	return true
}

@(private)
title_buttons_fallback :: proc "contextless" (w: ^Window, hwnd: win.HWND) {
	dpi := title_dpi(hwnd)
	h := win.GetSystemMetricsForDpi(win.SM_CYCAPTION, dpi)
	bw := 3 * win.GetSystemMetricsForDpi(win.SM_CXSIZE, dpi)
	if w.rtl {
		w.buttons_px = {0, 0, f32(bw), f32(h)}
		return
	}
	w.buttons_px = {w.client_px.x - f32(bw), 0, f32(bw), f32(h)}
}

@(private)
title_extend :: proc "contextless" (w: ^Window, hwnd: win.HWND, cy: i32) {
	if w.extended == cy {
		return
	}
	margins: win.MARGINS
	margins.cyTopHeight = cy
	if win.DwmExtendFrameIntoClientArea(hwnd, &margins) >= 0 {
		w.extended = cy
	}
}

@(private)
title_has_caption :: proc "contextless" (hwnd: win.HWND) -> bool {
	style := u32(win.GetWindowLongW(hwnd, win.GWL_STYLE))
	return style & u32(win.WS_CAPTION) != 0
}

@(private)
title_dpi :: proc "contextless" (hwnd: win.HWND) -> win.UINT {
	dpi := win.GetDpiForWindow(hwnd)
	if dpi == 0 {
		return 96
	}
	return dpi
}

// title_frame is one resize border at dpi, including the padded border.
// The top of a restored unified window is not part of it: the client
// includes the caption, so callers pass it only for the left, right and
// bottom, and for the in-client top strip.
@(private)
title_frame :: proc "contextless" (dpi: win.UINT, metric: win.INT) -> win.LONG {
	return win.LONG(win.GetSystemMetricsForDpi(metric, dpi) + win.GetSystemMetricsForDpi(win.SM_CXPADDEDBORDER, dpi))
}

// title_keep is whether DefWindowProc's hit stands: a resize edge, and
// unless drawn, the platform's buttons and system menu.
@(private)
title_keep :: proc "contextless" (hit: win.LRESULT, drawn := false) -> bool {
	if hit >= win.HTLEFT && hit <= win.HTBOTTOMRIGHT {
		return true
	}
	if drawn {
		return false
	}
	return hit == win.HTMINBUTTON || hit == win.HTMAXBUTTON || hit == win.HTCLOSE || hit == win.HTSYSMENU
}

@(private)
title_hit_code :: proc "contextless" (h: Title_Hit) -> win.LRESULT {
	switch h {
	case .Client:
		return win.HTCLIENT
	case .Caption:
		return win.HTCAPTION
	case .Top:
		return win.HTTOP
	case .Top_Left:
		return win.HTTOPLEFT
	case .Top_Right:
		return win.HTTOPRIGHT
	case .Minimize:
		return win.HTMINBUTTON
	case .Maximize:
		return win.HTMAXBUTTON
	case .Close:
		return win.HTCLOSE
	}
	return 0
}

@(private)
title_hwnd :: proc "contextless" (p: rawptr) -> win.HWND {
	return win.HWND(win.HANDLE(p))
}

// window_hwnd is the SDL window's HWND, the subclass's copy when it has one.
@(private)
window_hwnd :: proc(w: ^Window) -> win.HWND {
	if w.hwnd != nil {
		return title_hwnd(w.hwnd)
	}
	if w.window == nil {
		return nil
	}
	raw := sdl3.GetPointerProperty(sdl3.GetWindowProperties(w.window), sdl3.PROP_WINDOW_WIN32_HWND_POINTER, nil)
	return title_hwnd(raw)
}

// title_theme paints the caption for a dark or light window. caption is
// the page colour. Under Unified the caption buttons are the system's,
// drawn over a hole in the frame, so that colour is the page showing
// through the hole; under Drawn it colours only the border.
// 19 is the dark-mode attribute before Windows 10 2004; 20 is the one
// after. An unknown attribute fails and is ignored.
@(private)
title_theme :: proc(w: ^Window, dark: bool, caption: [3]u8) {
	hwnd := window_hwnd(w)
	if hwnd == nil {
		return
	}
	use_dark := win.BOOL(dark)
	_ = win.DwmSetWindowAttribute(hwnd, 19, rawptr(&use_dark), win.DWORD(size_of(use_dark)))
	_ = win.DwmSetWindowAttribute(
		hwnd,
		win.DWORD(win.DWMWINDOWATTRIBUTE.DWMWA_USE_IMMERSIVE_DARK_MODE),
		rawptr(&use_dark),
		win.DWORD(size_of(use_dark)),
	)
	page := win.RGB(int(caption[0]), int(caption[1]), int(caption[2]))
	ink := win.RGB(0xF0, 0xEE, 0xE8) if dark else win.RGB(0x1C, 0x1B, 0x1A)
	_ = win.DwmSetWindowAttribute(
		hwnd,
		win.DWORD(win.DWMWINDOWATTRIBUTE.DWMWA_CAPTION_COLOR),
		rawptr(&page),
		win.DWORD(size_of(page)),
	)
	_ = win.DwmSetWindowAttribute(
		hwnd,
		win.DWORD(win.DWMWINDOWATTRIBUTE.DWMWA_TEXT_COLOR),
		rawptr(&ink),
		win.DWORD(size_of(ink)),
	)
	_ = win.DwmSetWindowAttribute(
		hwnd,
		win.DWORD(win.DWMWINDOWATTRIBUTE.DWMWA_BORDER_COLOR),
		rawptr(&page),
		win.DWORD(size_of(page)),
	)
}
