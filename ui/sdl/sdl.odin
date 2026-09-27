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

Resizing: frames keep running while the window is being resized, from an
event watch on WINDOW_EXPOSED, which SDL documents as safe to redraw from.
On Windows the event loop sees no events until a resize drag ends, but
SDL still sends WINDOW_EXPOSED to watches during it. The
image and textures only grow, with headroom, so a resize in progress draws
into what is already allocated; half a second after the size settles they
shrink to fit.

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

import "base:runtime"
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

// GROW is the headroom, in pixels, the image and textures get when a
// resize outgrows them, and SETTLE how long after the last resize they
// shrink to fit.
@(private)
GROW :: 256
@(private)
SETTLE_MS :: 500

// Window is the SDL state of one running App.
@(private)
Window :: struct {
	window:   ^sdl3.Window,
	renderer: ^sdl3.Renderer,
	textures: [2]^sdl3.Texture, // render targets; front shows, the other takes scrolls
	front:    int,
	stale:    bool, // the textures lost their pixels: upload the whole image
	exposed:  bool, // the window must be shown again though nothing changed
	fresh:    bool, // the image was just allocated and holds nothing drawn
	pixels:   bl.ImageCore, // allocated at cap
	view:     bl.ImageCore, // the part of pixels the window shows, what render draws into
	size:     [2]i32, // device pixels
	cap:      [2]i32, // what pixels and textures are allocated at
	resized:  u64, // ticks, in ms, of the last change of size
	density:  f32,
}

// Loop is everything a running App keeps from frame to frame. step runs one
// frame; the run loop calls it, and so does the event watch that keeps
// frames coming while the window is being resized.
@(private)
Loop :: struct {
	app:           App,
	w:             Window,
	ops:           ui.Ops,
	frames:        [2]ui.Frame, // frames[n % 2] is laid out next, the other is the previous one
	router:        ui.Router,
	layout:        ui.Layout,
	r:             render.Renderer, // only shapes text; the compositor's workers draw
	shaper:        ui.Shaper,
	comp:          render.Compositor,
	theme:         ^ui.Theme,
	default_theme: ui.Theme,
	arenas:        [2]virtual.Arena, // frame allocators, alternating
	events:        virtual.Arena, // text of the events the next frame routes
	n:             u64,
	last:          u64, // ticks, in ns, of the last frame
	in_frame:      bool,
	ctx:           runtime.Context, // for the event watch, which SDL calls without one
	// What the last frame asked of the wait after it.
	wants_frame:   bool,
	frame_after:   f32,
	shown:         bool,
}

// run opens the window and loops until it is closed or Escape is pressed.
// It reports failure to open on stderr and returns.
run :: proc(app: App) {
	if !sdl3.Init({.VIDEO, .EVENTS}) {
		fmt.eprintln("sdl: init:", sdl3.GetError())
		return
	}
	defer sdl3.Quit()

	// The Compositor inside must not move, and the event watch holds l.
	l := new(Loop)
	defer free(l)
	if !loop_init(l, app) {
		return
	}
	defer loop_destroy(l)
	_ = sdl3.AddEventWatch(redraw_on_expose, l)
	defer sdl3.RemoveEventWatch(redraw_on_expose, l)

	for {
		if !poll(&l.w, &l.router, virtual.arena_allocator(&l.events)) {
			break
		}
		step(l)
		settle(&l.w)
		wait(&l.w, l.wants_frame, l.frame_after, l.shown)
	}
}

@(private)
loop_init :: proc(l: ^Loop, app: App) -> bool {
	l.app = app
	l.ctx = context
	if !open(&l.w, app) {
		return false
	}
	ui.ops_init(&l.ops)
	for ref in app.fonts {
		if id := ui.add_font(&l.ops, ref.path); id != ref.id {
			fmt.eprintfln("sdl: font %q registered as %v, not %v", ref.path, id, ref.id)
		}
	}
	ui.frame_init(&l.frames[0])
	ui.frame_init(&l.frames[1])
	ui.router_init(&l.router)
	ui.layout_init(&l.layout)
	render.init(&l.r)
	l.shaper = render.shaper(&l.r, l.ops.fonts[:])
	render.compositor_init(&l.comp, int(app.threads))
	l.default_theme = ui.default_theme(app.fonts[0].id if len(app.fonts) > 0 else 0)
	l.theme = app.theme if app.theme != nil else &l.default_theme
	for &a in l.arenas {
		if err := virtual.arena_init_growing(&a); err != nil {
			fmt.eprintln("sdl: arena:", err)
			return false
		}
	}
	if err := virtual.arena_init_growing(&l.events); err != nil {
		fmt.eprintln("sdl: arena:", err)
		return false
	}
	l.last = sdl3.GetTicksNS()
	return true
}

@(private)
loop_destroy :: proc(l: ^Loop) {
	virtual.arena_destroy(&l.events)
	virtual.arena_destroy(&l.arenas[0])
	virtual.arena_destroy(&l.arenas[1])
	render.compositor_destroy(&l.comp)
	render.destroy(&l.r)
	ui.layout_destroy(&l.layout)
	ui.router_destroy(&l.router)
	ui.frame_destroy(&l.frames[0])
	ui.frame_destroy(&l.frames[1])
	ui.ops_destroy(&l.ops)
	close(&l.w)
}

// step runs one frame: route the events polled so far, run the ui proc,
// flatten, compose and present.
@(private)
step :: proc(l: ^Loop) {
	l.in_frame = true
	defer l.in_frame = false
	arena := &l.arenas[l.n % 2]
	virtual.arena_free_all(arena)
	allocator := virtual.arena_allocator(arena)
	frame, prev := &l.frames[l.n % 2], &l.frames[(l.n + 1) % 2]

	now := sdl3.GetTicksNS()
	dt := min(f32(now - l.last) / 1e9, MAX_DT)
	l.last = now

	w := &l.w
	ui.router_route(&l.router, prev if l.n > 0 else nil)
	ui.ops_reset(&l.ops)
	ui.frame_reset(frame)
	ui.layout_reset(&l.layout)

	logical := ui.Size{f32(w.size.x) / w.density, f32(w.size.y) / w.density}
	gtx := ui.Ctx {
		ops         = &l.ops,
		constraints = ui.exact(logical),
		theme       = l.theme,
		shaper      = l.shaper,
		router      = &l.router,
		layout      = &l.layout,
		frame       = l.n,
		dt          = dt,
		allocator   = allocator,
	}
	scaled := w.density != 1
	if scaled {
		ui.push_transform(&l.ops, ui.scale(w.density, w.density))
	}
	if l.app.ui != nil {
		l.app.ui(&gtx, l.app.user)
	}
	if scaled {
		ui.pop_transform(&l.ops)
	}
	ui.flatten(&l.ops, frame)
	l.shown = present(w, &l.comp, frame, l.app.clear)
	l.wants_frame, l.frame_after = gtx.wants_frame, gtx.frame_after
	free_all(context.temp_allocator)
	// Every event polled before this frame was routed in it.
	virtual.arena_free_all(&l.events)
	l.n += 1
}

// redraw_on_expose runs a frame whenever the window must be redrawn, so a resize
// in progress keeps drawing even while the platform holds the event loop.
@(private)
redraw_on_expose :: proc "c" (userdata: rawptr, e: ^sdl3.Event) -> bool {
	l := (^Loop)(userdata)
	if e.type != .WINDOW_EXPOSED || l.in_frame {
		return true
	}
	context = l.ctx
	if resize(&l.w) {
		step(l)
	}
	return true
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
	bl.image_init(&w.view)
	_ = sdl3.StartTextInput(w.window)
	return resize(w)
}

@(private)
close :: proc(w: ^Window) {
	_ = sdl3.StopTextInput(w.window)
	destroy_textures(w)
	bl.image_destroy(&w.view)
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

// resize reads the output size and density. A size that fits what is
// allocated is drawn into as it is; a bigger one reallocates with GROW
// pixels of headroom. exact reallocates at the size itself.
@(private)
resize :: proc(w: ^Window, exact := false) -> bool {
	size: [2]i32
	sdl3.GetRenderOutputSize(w.renderer, &size.x, &size.y)
	w.density = sdl3.GetWindowPixelDensity(w.window)
	if w.density <= 0 {
		w.density = 1
	}
	if size == w.size && w.textures[0] != nil && !exact {
		return true
	}
	if size != w.size {
		w.resized = sdl3.GetTicks()
	}
	w.size = size
	if size.x <= 0 || size.y <= 0 {
		return true
	}
	fits := w.textures[0] != nil && size.x <= w.cap.x && size.y <= w.cap.y
	if exact || !fits {
		// The first allocation has no resize in progress to leave room for.
		cap := size if exact || w.textures[0] == nil else size + GROW
		destroy_textures(w)
		// ARGB8888 is a native-endian 0xAARRGGBB word: Blend2D's PRGB32
		// layout. Copies between the textures must be exact: no blending,
		// no filtering.
		for &t in w.textures {
			t = sdl3.CreateTexture(w.renderer, .ARGB8888, .TARGET, cap.x, cap.y)
			if t == nil {
				fmt.eprintln("sdl: texture:", sdl3.GetError())
				return false
			}
			sdl3.SetTextureBlendMode(t, sdl3.BLENDMODE_NONE)
			sdl3.SetTextureScaleMode(t, .NEAREST)
		}
		if bl.image_create(&w.pixels, cap.x, cap.y, .PRGB32) != 0 {
			fmt.eprintln("sdl: image: out of memory")
			return false
		}
		w.cap = cap
		w.front = 0
		w.stale = true
		w.fresh = true
	}
	data: bl.ImageData
	if bl.image_get_data(&w.pixels, &data) != 0 {
		return false
	}
	return bl.image_create_from_data(&w.view, size.x, size.y, .PRGB32, data.pixel_data, data.stride, .RW, nil, nil) == 0
}

// settle shrinks the image and textures to the window once its size has
// not changed for SETTLE_MS.
@(private)
settle :: proc(w: ^Window) {
	if w.cap == w.size || w.size.x <= 0 || w.size.y <= 0 || sdl3.GetTicks() - w.resized < SETTLE_MS {
		return
	}
	_ = resize(w, exact = true)
}

// wait blocks until the next frame is due: until input when the ui asked
// for no frame, else for at most the time it asked for. A frame that
// showed nothing did not wait on the display's refresh, so an immediate
// request waits one refresh here instead of spinning.
@(private)
wait :: proc(w: ^Window, wants: bool, after: f32, shown: bool) {
	ms := i32(-1)
	if wants {
		ms = i32(after * 1000)
		if !shown {
			ms = max(ms, refresh_ms(w))
		}
	}
	// Oversized buffers wake the loop in time for settle to shrink them.
	if w.cap != w.size {
		due := i32(max(i64(SETTLE_MS) - i64(sdl3.GetTicks() - w.resized), 0)) + 1
		ms = due if ms < 0 else min(ms, due)
	}
	if ms < 0 {
		_ = sdl3.WaitEvent(nil)
	} else if ms > 0 {
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
	if bl.image_get_data(&w.view, &data) != 0 {
		return false
	}
	if w.fresh {
		// The compositor must not trust what it drew into the old image.
		render.damage_invalidate(&c.damage)
		w.fresh = false
	}
	changed := render.compose(c, f, &w.view, clear)
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
			shown := sdl3.FRect{0, 0, f32(w.size.x), f32(w.size.y)}
			sdl3.RenderTexture(w.renderer, w.textures[w.front], &shown, &shown)
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
	src := sdl3.FRect{0, 0, f32(w.size.x), f32(w.size.y)}
	sdl3.RenderTexture(w.renderer, w.textures[w.front], &src, nil)
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
