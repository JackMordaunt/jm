/*
Package sdl runs a ui proc in an SDL3 window. It owns the window, the event
loop and presentation; ui/render turns each Frame into pixels, and nothing
here knows how.

	main :: proc() {
		sdl.run({
			title  = "hello",
			width  = 640,
			height = 480,
			fonts  = {{0, "/usr/share/fonts/liberation/LiberationSans-Regular.ttf"}},
			clear  = {250, 250, 250, 255},
			ui     = proc(gtx: ^ui.Ctx, _: rawptr) {
				ui.fill(gtx.ops, ui.Rect{20, 20, 100, 40}, ui.Color{51, 102, 255, 255})
			},
		})
	}

Each frame: poll SDL events into the Router, route them against the previous
frame, reset Ops, run the ui proc, flatten, repaint what changed into a
CPU-side image (render.Compositor), bring the texture up to date, present
if anything changed, swap frames. Then wait: for input, or for as long as
the ui asked with ui.request_frame. An idle window spends no CPU; wake
runs a frame from any thread.

Render never targets a locked texture: the Direct3D renderers map it as
write-combined memory, which is slow to read, and blending reads it.

The texture follows the image without uploading it whole. A scroll the
compositor applied to the image is applied on the GPU too, by drawing the
front texture, moved, into the back one; only the repainted rects are
uploaded. On the machine this was written on, a whole 4K upload cost 12 to
16 ms a frame on Direct3D 11, OpenGL and Vulkan alike; the move and the
strip it uncovers cost under 1 ms.

Coordinates: the ui proc lays out in logical units (window points).
On a HiDPI display a root scale transform by the pixel density maps them to
device pixels, so a Frame, its hits and the Raw_Events fed to the router are
all in device pixels, as package ui requires.

Memory: gtx.allocator is one of two arenas that alternate by frame, so
everything the previous frame allocated (paths, glyph runs, event text)
stays valid while its hits are routed, then is freed wholesale a frame
later. context.temp_allocator is freed at the end of every frame, so the
ui proc may use it for anything that frame needs. Everything else is
released when run returns.

Threads: run blocks the calling thread, which must be the main thread.
App.threads workers, the main thread among them, repaint changed regions in
parallel.
*/
package sdl

import "core:fmt"
import "core:mem/virtual"
import "core:strings"

import "jm:ui"
import "jm:ui/render"
import bl "jm:ui/blend2d"
import sdl3 "vendor:sdl3"

// Ui_Proc builds one frame: it records into gtx.ops and reads events from
// gtx.router. user is App.user, passed through untouched.
Ui_Proc :: proc(gtx: ^ui.Ctx, user: rawptr)

// Inside App the field named ui shadows the package, so its other field
// types are spelled through these aliases.
@(private)
Theme :: ui.Theme
@(private)
Font_Ref :: ui.Font_Ref
@(private)
Color :: ui.Color

// App describes a window and the ui proc that fills it.
App :: struct {
	title:         string,
	width, height: int, // initial size in logical units
	ui:            Ui_Proc,
	user:          rawptr,
	theme:         ^Theme, // nil uses ui.default_theme with the first font
	fonts:         []Font_Ref, // registered into Ops in order before the first frame
	clear:         Color,
	threads:       u32, // workers repainting changed regions; 0 or 1 repaints on the main thread
}

// wake runs a frame soon, as input would. Any thread may call it, for
// instance when work the ui shows has finished.
wake :: proc() {
	e: sdl3.Event
	e.type = .USER
	_ = sdl3.PushEvent(&e)
}

// MAX_DT caps ui.Ctx.dt, so an animation that starts after an idle wait
// does not jump by the whole wait.
@(private)
MAX_DT :: 0.1

// Window is the SDL state of one running App.
@(private)
Window :: struct {
	window:   ^sdl3.Window,
	renderer: ^sdl3.Renderer,
	textures: [2]^sdl3.Texture, // render targets; front shows, the other takes scrolls
	front:    int,
	stale:    bool, // the textures lost their pixels: upload the whole image
	exposed:  bool, // the window must be shown again though nothing changed
	pixels:   bl.ImageCore, // what render draws into
	size:     [2]i32, // device pixels
	density:  f32,
}

// run opens the window and loops until it is closed or Escape is pressed.
// It reports failure to open on stderr and returns.
run :: proc(app: App) {
	if !sdl3.Init({.VIDEO, .EVENTS}) {
		fmt.eprintln("sdl: init:", sdl3.GetError())
		return
	}
	defer sdl3.Quit()

	w: Window
	if !open(&w, app) {
		return
	}
	defer close(&w)

	ops: ui.Ops
	ui.ops_init(&ops)
	defer ui.ops_destroy(&ops)
	for ref in app.fonts {
		if id := ui.add_font(&ops, ref.path); id != ref.id {
			fmt.eprintfln("sdl: font %q registered as %v, not %v", ref.path, id, ref.id)
		}
	}

	frames: [2]ui.Frame
	ui.frame_init(&frames[0])
	ui.frame_init(&frames[1])
	defer ui.frame_destroy(&frames[0])
	defer ui.frame_destroy(&frames[1])
	frame, prev := &frames[0], &frames[1]

	router: ui.Router
	ui.router_init(&router)
	defer ui.router_destroy(&router)

	layout: ui.Layout
	ui.layout_init(&layout)
	defer ui.layout_destroy(&layout)

	// r only shapes text; the compositor's workers draw.
	r: render.Renderer
	render.init(&r)
	defer render.destroy(&r)
	shaper := render.shaper(&r, ops.fonts[:])
	comp: render.Compositor
	render.compositor_init(&comp, int(app.threads))
	defer render.compositor_destroy(&comp)

	theme := app.theme
	default_theme := ui.default_theme(app.fonts[0].id if len(app.fonts) > 0 else 0)
	if theme == nil {
		theme = &default_theme
	}

	arenas: [2]virtual.Arena
	for &a in arenas {
		if err := virtual.arena_init_growing(&a); err != nil {
			fmt.eprintln("sdl: arena:", err)
			return
		}
	}
	defer virtual.arena_destroy(&arenas[0])
	defer virtual.arena_destroy(&arenas[1])

	last := sdl3.GetTicksNS()
	for n: u64 = 0;; n += 1 {
		arena := &arenas[n % 2]
		virtual.arena_free_all(arena)
		allocator := virtual.arena_allocator(arena)

		if !poll(&w, &router, allocator) {
			break
		}
		now := sdl3.GetTicksNS()
		dt := min(f32(now - last) / 1e9, MAX_DT)
		last = now

		ui.router_route(&router, prev if n > 0 else nil)
		ui.ops_reset(&ops)
		ui.frame_reset(frame)
		ui.layout_reset(&layout)

		logical := ui.Size{f32(w.size.x) / w.density, f32(w.size.y) / w.density}
		gtx := ui.Ctx {
			ops         = &ops,
			constraints = ui.exact(logical),
			theme       = theme,
			shaper      = shaper,
			router      = &router,
			layout      = &layout,
			frame       = n,
			dt          = dt,
			allocator   = allocator,
		}
		scaled := w.density != 1
		if scaled {
			ui.push_transform(&ops, ui.scale(w.density, w.density))
		}
		if app.ui != nil {
			app.ui(&gtx, app.user)
		}
		if scaled {
			ui.pop_transform(&ops)
		}
		ui.flatten(&ops, frame)
		shown := present(&w, &comp, frame, app.clear)
		frame, prev = prev, frame
		free_all(context.temp_allocator)
		wait(&w, gtx.wants_frame, gtx.frame_after, shown)
	}
}

@(private)
open :: proc(w: ^Window, app: App) -> bool {
	title := strings.clone_to_cstring(app.title if app.title != "" else "ui", context.temp_allocator)
	width, height := app.width, app.height
	if width <= 0 {
		width = 800
	}
	if height <= 0 {
		height = 600
	}
	w.window = sdl3.CreateWindow(title, i32(width), i32(height), {.RESIZABLE, .HIGH_PIXEL_DENSITY})
	if w.window == nil {
		fmt.eprintln("sdl: window:", sdl3.GetError())
		return false
	}
	w.renderer = sdl3.CreateRenderer(w.window, nil)
	if w.renderer == nil {
		fmt.eprintln("sdl: renderer:", sdl3.GetError())
		sdl3.DestroyWindow(w.window)
		return false
	}
	sdl3.SetRenderVSync(w.renderer, 1)
	bl.image_init(&w.pixels)
	_ = sdl3.StartTextInput(w.window)
	return resize(w)
}

@(private)
close :: proc(w: ^Window) {
	_ = sdl3.StopTextInput(w.window)
	destroy_textures(w)
	bl.image_destroy(&w.pixels)
	sdl3.DestroyRenderer(w.renderer)
	sdl3.DestroyWindow(w.window)
	w^ = {}
}

@(private)
destroy_textures :: proc(w: ^Window) {
	for &t in w.textures {
		if t != nil {
			sdl3.DestroyTexture(t)
			t = nil
		}
	}
}

// resize reads the output size and density and remakes the textures to
// match.
@(private)
resize :: proc(w: ^Window) -> bool {
	size: [2]i32
	sdl3.GetRenderOutputSize(w.renderer, &size.x, &size.y)
	w.density = sdl3.GetWindowPixelDensity(w.window)
	if w.density <= 0 {
		w.density = 1
	}
	if size == w.size && w.textures[0] != nil {
		return true
	}
	destroy_textures(w)
	w.size = size
	if size.x <= 0 || size.y <= 0 {
		return true
	}
	// ARGB8888 is a native-endian 0xAARRGGBB word: Blend2D's PRGB32 layout.
	// Copies between the textures must be exact: no blending, no filtering.
	for &t in w.textures {
		t = sdl3.CreateTexture(w.renderer, .ARGB8888, .TARGET, size.x, size.y)
		if t == nil {
			fmt.eprintln("sdl: texture:", sdl3.GetError())
			return false
		}
		sdl3.SetTextureBlendMode(t, sdl3.BLENDMODE_NONE)
		sdl3.SetTextureScaleMode(t, .NEAREST)
	}
	w.front = 0
	w.stale = true
	if bl.image_create(&w.pixels, size.x, size.y, .PRGB32) != 0 {
		fmt.eprintln("sdl: image: out of memory")
		return false
	}
	return true
}

// wait blocks until the next frame is due: until input when the ui asked
// for no frame, else for at most the time it asked for. A frame that
// showed nothing did not wait on the display's refresh, so an immediate
// request waits one refresh here instead of spinning.
@(private)
wait :: proc(w: ^Window, wants: bool, after: f32, shown: bool) {
	if !wants {
		_ = sdl3.WaitEvent(nil)
		return
	}
	ms := i32(after * 1000)
	if !shown {
		ms = max(ms, refresh_ms(w))
	}
	if ms > 0 {
		_ = sdl3.WaitEventTimeout(nil, ms)
	}
}

// refresh_ms is one refresh of the display showing w, 60 Hz when unknown.
@(private)
refresh_ms :: proc(w: ^Window) -> i32 {
	if mode := sdl3.GetCurrentDisplayMode(sdl3.GetDisplayForWindow(w.window)); mode != nil && mode.refresh_rate > 0 {
		return max(i32(1000 / mode.refresh_rate), 1)
	}
	return 16
}

// present repaints what f changed in the window's image and brings the
// front texture up to date. It shows the texture and reports true when
// anything changed or the window must be shown again.
@(private)
present :: proc(w: ^Window, c: ^render.Compositor, f: ^ui.Frame, clear: ui.Color) -> bool {
	if w.textures[0] == nil {
		return false
	}
	data: bl.ImageData
	if bl.image_get_data(&w.pixels, &data) != 0 {
		return false
	}
	changed := render.compose(c, f, &w.pixels, clear)
	if !w.stale && !w.exposed && len(changed) == 0 {
		return false
	}
	w.exposed = false
	if w.stale {
		upload(w.textures[w.front], &data, {0, 0, f32(w.size.x), f32(w.size.y)})
		w.stale = false
	} else if len(changed) > 0 {
		if scrolls := c.damage.scrolls[:]; len(scrolls) > 0 {
			// Draw the front texture into the back one, then each scrolled
			// region again, moved, from the front: the source never
			// overlaps what is being written.
			back := w.textures[1 - w.front]
			sdl3.SetRenderTarget(w.renderer, back)
			sdl3.RenderTexture(w.renderer, w.textures[w.front], nil, nil)
			for s in scrolls {
				src, dst, ok := scroll_copy(s)
				if ok {
					sdl3.RenderTexture(w.renderer, w.textures[w.front], &src, &dst)
				}
			}
			sdl3.SetRenderTarget(w.renderer, nil)
			w.front = 1 - w.front
		}
		for r in c.damage.rects {
			upload(w.textures[w.front], &data, r)
		}
	}
	sdl3.RenderClear(w.renderer)
	sdl3.RenderTexture(w.renderer, w.textures[w.front], nil, nil)
	sdl3.RenderPresent(w.renderer)
	return true
}

// upload copies r of the image into the same place in t.
@(private)
upload :: proc(t: ^sdl3.Texture, data: ^bl.ImageData, r: ui.Rect) {
	area := sdl3.Rect{i32(r.x), i32(r.y), i32(r.w), i32(r.h)}
	px := rawptr(uintptr(data.pixel_data) + uintptr(int(r.y) * int(data.stride) + int(r.x) * 4))
	sdl3.UpdateTexture(t, &area, px, i32(data.stride))
}

// scroll_copy is where s takes pixels from and puts them, as render's
// compositor moves them in the image: what stays inside s.rect after the
// move.
@(private)
scroll_copy :: proc(s: render.Scroll) -> (src, dst: sdl3.FRect, ok: bool) {
	dx, dy := f32(s.delta.x), f32(s.delta.y)
	w, h := s.rect.w - abs(dx), s.rect.h - abs(dy)
	if w <= 0 || h <= 0 {
		return {}, {}, false
	}
	src = {s.rect.x + max(-dx, 0), s.rect.y + max(-dy, 0), w, h}
	dst = {s.rect.x + max(dx, 0), s.rect.y + max(dy, 0), w, h}
	return src, dst, true
}

// poll drains SDL's queue into the router. Text is cloned into allocator.
// It returns false when the app should quit.
@(private)
poll :: proc(w: ^Window, router: ^ui.Router, allocator := context.allocator) -> bool {
	d := w.density
	e: sdl3.Event
	for sdl3.PollEvent(&e) {
		#partial switch e.type {
		case .QUIT, .WINDOW_CLOSE_REQUESTED:
			return false
		case .WINDOW_PIXEL_SIZE_CHANGED, .WINDOW_RESIZED, .WINDOW_DISPLAY_SCALE_CHANGED:
			if !resize(w) {
				return false
			}
			d = w.density
		case .WINDOW_EXPOSED:
			w.exposed = true
		case .RENDER_TARGETS_RESET:
			w.stale = true
		case .RENDER_DEVICE_RESET:
			destroy_textures(w)
			if !resize(w) {
				return false
			}
		case .MOUSE_MOTION:
			ui.router_push(router, {kind = .Move, pos = {e.motion.x * d, e.motion.y * d}, mods = mods(sdl3.GetModState())})
		case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP:
			btn, ok := button(e.button.button)
			if !ok {
				continue
			}
			kind: ui.Event_Kind = .Press if e.type == .MOUSE_BUTTON_DOWN else .Release
			ui.router_push(router, {kind = kind, pos = {e.button.x * d, e.button.y * d}, button = btn, mods = mods(sdl3.GetModState())})
		case .MOUSE_WHEEL:
			// Positive y scrolls down (toward the user), like a scroll offset.
			s := [2]f32{e.wheel.x, -e.wheel.y}
			if e.wheel.direction == .FLIPPED {
				s = -s
			}
			ui.router_push(router, {kind = .Scroll, pos = {e.wheel.mouse_x * d, e.wheel.mouse_y * d}, scroll = s, mods = mods(sdl3.GetModState())})
		case .KEY_DOWN:
			k := key(e.key.key)
			if k == .Escape {
				return false
			}
			if k != .None {
				ui.router_push(router, {kind = .Key, key = k, mods = mods(e.key.mod)})
			}
		case .TEXT_INPUT:
			text := strings.clone_from_cstring(e.text.text, allocator)
			ui.router_push(router, {kind = .Text, text = text, mods = mods(sdl3.GetModState())})
		}
	}
	return true
}

@(private)
button :: proc(b: u8) -> (ui.Button, bool) {
	switch b {
	case sdl3.BUTTON_LEFT:
		return .Left, true
	case sdl3.BUTTON_RIGHT:
		return .Right, true
	case sdl3.BUTTON_MIDDLE:
		return .Middle, true
	}
	return .Left, false
}

@(private)
mods :: proc(m: sdl3.Keymod) -> ui.Mods {
	out: ui.Mods
	if m & sdl3.KMOD_SHIFT != {} {
		out += {.Shift}
	}
	if m & sdl3.KMOD_CTRL != {} {
		out += {.Ctrl}
	}
	if m & sdl3.KMOD_ALT != {} {
		out += {.Alt}
	}
	if m & sdl3.KMOD_GUI != {} {
		out += {.Super}
	}
	return out
}

// key maps an SDL keycode to ui.Key; keys outside the enum map to None.
@(private)
key :: proc(k: sdl3.Keycode) -> ui.Key {
	switch k {
	case sdl3.K_RETURN, sdl3.K_KP_ENTER:
		return .Enter
	case sdl3.K_ESCAPE:
		return .Escape
	case sdl3.K_TAB:
		return .Tab
	case sdl3.K_BACKSPACE:
		return .Backspace
	case sdl3.K_DELETE:
		return .Delete
	case sdl3.K_LEFT:
		return .Left
	case sdl3.K_RIGHT:
		return .Right
	case sdl3.K_UP:
		return .Up
	case sdl3.K_DOWN:
		return .Down
	case sdl3.K_HOME:
		return .Home
	case sdl3.K_END:
		return .End
	case sdl3.K_PAGEUP:
		return .Page_Up
	case sdl3.K_PAGEDOWN:
		return .Page_Down
	case sdl3.K_SPACE:
		return .Space
	case sdl3.K_A ..= sdl3.K_Z:
		return ui.Key(int(ui.Key.A) + int(k - sdl3.K_A))
	case sdl3.K_0 ..= sdl3.K_9:
		return ui.Key(int(ui.Key.N0) + int(k - sdl3.K_0))
	}
	return .None
}
