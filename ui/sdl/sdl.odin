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
frame, reset Ops, run the ui proc, flatten, render into a CPU-side
image, upload it to the streaming texture, present, swap frames.

Render never targets the locked texture: the Direct3D renderers map it as
write-combined memory, which is slow to read, and blending reads it.

Coordinates: the ui proc lays out in logical units (window points).
On a HiDPI display a root scale transform by the pixel density maps them to
device pixels, so a Frame, its hits and the Raw_Events fed to the router are
all in device pixels, as package ui requires.

Memory: gtx.allocator is one of two arenas that alternate by frame, so
everything the previous frame allocated (paths, glyph runs, event text)
stays valid while its hits are routed, then is freed wholesale a frame
later. Everything else is released when run returns.

Threads: run blocks the calling thread, which must be the main thread.
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
	threads:       u32, // Blend2D render workers; 0 renders on the main thread
}

// Window is the SDL state of one running App.
@(private)
Window :: struct {
	window:   ^sdl3.Window,
	renderer: ^sdl3.Renderer,
	texture:  ^sdl3.Texture,
	pixels:   bl.ImageCore, // what render draws into; uploaded each frame
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

	r: render.Renderer
	render.init(&r)
	defer render.destroy(&r)
	r.threads = app.threads
	shaper := render.shaper(&r, ops.fonts[:])

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
		dt := f32(now - last) / 1e9
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
		present(&w, &r, frame, app.clear)
		frame, prev = prev, frame
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
	if w.texture != nil {
		sdl3.DestroyTexture(w.texture)
	}
	bl.image_destroy(&w.pixels)
	sdl3.DestroyRenderer(w.renderer)
	sdl3.DestroyWindow(w.window)
	w^ = {}
}

// resize reads the output size and density and remakes the texture to match.
@(private)
resize :: proc(w: ^Window) -> bool {
	size: [2]i32
	sdl3.GetRenderOutputSize(w.renderer, &size.x, &size.y)
	w.density = sdl3.GetWindowPixelDensity(w.window)
	if w.density <= 0 {
		w.density = 1
	}
	if size == w.size && w.texture != nil {
		return true
	}
	if w.texture != nil {
		sdl3.DestroyTexture(w.texture)
		w.texture = nil
	}
	w.size = size
	if size.x <= 0 || size.y <= 0 {
		return true
	}
	// ARGB8888 is a native-endian 0xAARRGGBB word: Blend2D's PRGB32 layout.
	w.texture = sdl3.CreateTexture(w.renderer, .ARGB8888, .STREAMING, size.x, size.y)
	if w.texture == nil {
		fmt.eprintln("sdl: texture:", sdl3.GetError())
		return false
	}
	sdl3.SetTextureBlendMode(w.texture, sdl3.BLENDMODE_NONE)
	if bl.image_create(&w.pixels, size.x, size.y, .PRGB32) != 0 {
		fmt.eprintln("sdl: image: out of memory")
		return false
	}
	return true
}

// present renders f into the window's image, uploads it and shows it.
@(private)
present :: proc(w: ^Window, r: ^render.Renderer, f: ^ui.Frame, clear: ui.Color) {
	if w.texture == nil {
		return
	}
	render.render(r, f, &w.pixels, clear)
	data: bl.ImageData
	if bl.image_get_data(&w.pixels, &data) != 0 {
		return
	}
	if !sdl3.UpdateTexture(w.texture, nil, data.pixel_data, i32(data.stride)) {
		return
	}
	sdl3.RenderClear(w.renderer)
	sdl3.RenderTexture(w.renderer, w.texture, nil, nil)
	sdl3.RenderPresent(w.renderer)
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
