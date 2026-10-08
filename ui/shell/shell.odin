/*
Package shell joins the operating system, the ui stack and the app. SDL3
supplies the window, events and renderer; native APIs fill in what SDL
lacks (assistive technology through AccessKit, macOS scroll momentum). It
owns the window, the event loop and presentation; ui/render turns each
Frame into pixels, and nothing here knows how. run calls the app's ui proc
in this process; run_host drives one in a subprocess instead.

	main :: proc() {
		shell.run({
			title  = "hello",
			width  = 640,
			height = 480,
			fonts  = {{0, "/usr/share/fonts/liberation/LiberationSans-Regular.ttf"}},
			clear  = {250, 250, 250, 255},
			ui     = proc(gtx: ^ui.Ctx, _: rawptr) {
				ops.fill(gtx.scene, ops.Rect{20, 20, 100, 40}, ops.Color{51, 102, 255, 255})
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
shrink to fit. While resizing, vsync is off and, on Windows, each frame
waits for the desktop compositor, so the window does not show its new size
with the previous frame's content in it.

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
package shell

import "base:builtin"
import "base:runtime"
import "core:fmt"
import "core:mem/virtual"
import "core:strings"
import "core:time"

import "jm:ui"
import bl "jm:ui/blend2d"
import "jm:ui/ops"
import "jm:ui/render"
import sdl3 "vendor:sdl3"

// Ui_Proc is ui.UI_Proc.
Ui_Proc :: ui.UI_Proc

// Inside App the field named ui shadows the package, so its other field
// types are spelled through these aliases.
@(private)
Font_Ref :: ops.Font_Ref
@(private)
Data_Host :: ui.Data_Host
@(private)
Color :: ops.Color

// App describes a window and the ui proc that fills it.
App :: struct {
	title:                 string,
	width, height:         int, // initial size in logical units
	min_width, min_height: int, // the smallest the window may be made, in logical units; 0 for no limit
	ui:                    Ui_Proc,
	user:                  rawptr,
	fonts:                 []Font_Ref, // registered into the Scene under their own ids before the first frame
	fallbacks:             []ops.Font_Id, // font ids tried in order for a rune the font asked for lacks
	clear:                 Color,
	threads:               u32, // workers repainting changed regions; 0 or 1 repaints on the main thread
	no_accessibility:      bool, // leave assistive technology unserved: no bridge (a11y_linux.odin) is made
	data:                  Data_Host, // where the frames' needs and commands go, and where shapes come back from; see ui/need.odin
}

// default_font is ui.default_font: kept here too since every existing
// caller in this codebase spells it shell.default_font.
default_font :: ui.default_font

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
// shrink to fit. LIVE_MS is how long after the last resize vsync stays off.
@(private)
GROW :: 256
@(private)
SETTLE_MS :: 500
@(private)
LIVE_MS :: 100

// Window is the SDL state of one running App.
@(private)
Window :: struct {
	window:       ^sdl3.Window,
	renderer:     ^sdl3.Renderer,
	textures:     [2]^sdl3.Texture, // render targets; front shows, the other takes scrolls
	front:        int,
	stale:        bool, // the textures lost their pixels: upload the whole image
	exposed:      bool, // the window must be shown again though nothing changed
	fresh:        bool, // the image was just allocated and holds nothing drawn
	pixels:       bl.ImageCore, // allocated at cap
	view:         bl.ImageCore, // the part of pixels the window shows, what render draws into
	size:         [2]i32, // device pixels
	cap:          [2]i32, // what pixels and textures are allocated at
	resized:      u64, // ticks, in ms, of the last change of size
	live:         bool, // a resize is in progress, and vsync is off for it
	live_at:      u64, // ticks, in ms, of the last frame that kept it live
	sized:        bool, // the frame being drawn is for a new size
	density:      f32,
	flashes:      [dynamic]Flash, // repaint flashes still fading, for the debug tray
	cursors:      [ops.Cursor]^sdl3.Cursor, // made on first use, see show_cursor
	cursor_shown: ops.Cursor,
	cursor_set:   bool, // cursor_shown has been applied
	a11y:         ^Bridge, // the loop's bridge to assistive technology, for window events; nil without one
	ime:          ui.Text_Input, // what the input method was last set to; off until a text area takes focus
	composing:    bool, // the input method holds a preedit: it owns the keys
}

// Flash is one repainted rect tinted over the window until FLASH_MS after
// it was drawn: the debug tray's repaint flash.
Flash :: struct {
	r:  sdl3.FRect, // device pixels
	at: u64, // SDL ticks, in ms, when it was repainted
}

// FLASH_MS is how long a repaint flash takes to fade.
FLASH_MS :: 400

// FLASH_FILL_ALPHA and FLASH_EDGE_ALPHA are a fresh flash's fill and
// outline opacity, out of 255: faint enough over the fill to read the ui
// beneath it, strong enough at the edge to see where the repaint ended.
FLASH_FILL_ALPHA :: 45
FLASH_EDGE_ALPHA :: 140

// draw_flashes tints each live flash's rect over the presented frame,
// fading with age, and drops the ones that have faded. It draws on the
// renderer, over the texture, never into w.view: render.Compositor keeps
// that image from frame to frame and repaints only what changed, so a tint
// drawn into it would stay.
@(private)
draw_flashes :: proc(w: ^Window) {
	if len(w.flashes) == 0 {
		return
	}
	now := sdl3.GetTicks()
	sdl3.SetRenderDrawBlendMode(w.renderer, sdl3.BLENDMODE_BLEND)
	kept := 0
	for fl in w.flashes {
		age := f32(now - fl.at) / FLASH_MS
		if age >= 1 {
			continue
		}
		// A faint fill and a stronger edge: the ui stays readable under a
		// region that repaints every frame, whose flash never gets to fade.
		fade := 1 - age
		r := fl.r
		sdl3.SetRenderDrawColor(w.renderer, 255, 40, 160, u8(FLASH_FILL_ALPHA * fade))
		sdl3.RenderFillRect(w.renderer, &r)
		sdl3.SetRenderDrawColor(w.renderer, 255, 40, 160, u8(FLASH_EDGE_ALPHA * fade))
		sdl3.RenderRect(w.renderer, &r)
		w.flashes[kept] = fl
		kept += 1
	}
	builtin.resize(&w.flashes, kept) // this package's own resize shadows the builtin
}

// flash_outside adds a flash for each part of r outside every rect in
// keep_out.
@(private)
flash_outside :: proc(w: ^Window, r: ops.Rect, keep_out: []ops.Rect, at: u64) {
	if r.w <= 0 || r.h <= 0 {
		return
	}
	for k, i in keep_out {
		cut := ops.rect_intersect(r, k)
		if cut.w <= 0 || cut.h <= 0 {
			continue
		}
		// The parts of r above, below, left and right of the cut, each
		// checked against the rest of keep_out.
		rest := keep_out[i + 1:]
		flash_outside(w, {r.x, r.y, r.w, cut.y - r.y}, rest, at)
		flash_outside(w, {r.x, cut.y + cut.h, r.w, r.y + r.h - cut.y - cut.h}, rest, at)
		flash_outside(w, {r.x, cut.y, cut.x - r.x, cut.h}, rest, at)
		flash_outside(w, {cut.x + cut.w, cut.y, r.x + r.w - cut.x - cut.w, cut.h}, rest, at)
		return
	}
	append(&w.flashes, Flash{{r.x, r.y, r.w, r.h}, at})
}

// flashing reports whether repaint flashes are still fading, so the loop
// keeps presenting until they are gone.
@(private)
flashing :: proc(w: ^Window) -> bool {
	return len(w.flashes) > 0
}

// Loop is everything a running App keeps from frame to frame. step runs one
// frame; the run loop calls it, and so does the event watch that keeps
// frames coming while the window is being resized.
@(private)
Loop :: struct {
	app:         App,
	w:           Window,
	rec:         ui.Recorder, // every frame's input, when ui.RECORD_ENV names a file
	a11y:        Bridge, // what assistive technology reads, unless App.no_accessibility
	scene:       ops.Scene,
	frames:      [2]ui.Frame, // frames[n % 2] is laid out next, the other is the previous one
	router:      ui.Router,
	layout:      ui.Layout,
	subs:        ui.Subscriptions, // the needs of the last frame, to diff the next against
	r:           render.Renderer, // only shapes text; the compositor's workers draw
	shaper:      ui.Shaper,
	comp:        render.Compositor,
	font:        ops.Font_Id, // the toolkit's face: the first font
	arenas:      [2]ops.Frame_Arena, // frame allocators, alternating
	events:      virtual.Arena, // text of the events the next frame routes
	n:           u64,
	last:        u64, // ticks, in ns, of the last frame
	time:        f64, // ui.Ctx.time: the frames' dt so far
	tray:        ui.Debug_Tray, // ui.DEBUG_TOGGLE_KEY opens it
	in_frame:    bool,
	ctx:         runtime.Context, // for the event watch, which SDL calls without one
	// What the last frame asked of the wait after it.
	wants_frame: bool,
	frame_after: f32,
	shown:       bool,
}

// set_hints sets what SDL must know before SDL_Init. On macOS a trackpad
// flick goes on scrolling after the fingers lift, as momentum-phase
// scroll events the system sends; SDL drops those unless asked, so a
// scroll stopped dead where the fingers left (SDL_HINT_MAC_SCROLL_MOMENTUM,
// "0" by default). Elsewhere the hint does nothing.
//
// An input method's composition is drawn by the field it is for, inline
// and underlined (ui.text_display), so SDL is told the app renders it:
// "composition" in SDL_HINT_IME_IMPLEMENTED_UI (SDL_hints.h), which leaves
// the candidate list out of the app's hands.
@(private)
set_hints :: proc() {
	sdl3.SetHint(sdl3.HINT_MAC_SCROLL_MOMENTUM, "1")
	sdl3.SetHint(sdl3.HINT_IME_IMPLEMENTED_UI, "composition")
}

// run opens the window and loops until it is closed, Escape is pressed, or
// the process is sent SIGINT or SIGTERM (interrupt_posix.odin); each
// returns the same way, so the caller's shutdown runs after any of them.
// It reports failure to open on stderr and returns.
run :: proc(app: App) {
	set_hints()
	interrupt_start()
	defer interrupt_stop()
	if !sdl3.Init({.VIDEO, .EVENTS}) {
		fmt.eprintln("shell: init:", sdl3.GetError())
		return
	}
	defer sdl3.Quit()
	scroll_watch_start()
	defer scroll_watch_stop()

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
		bridge_take_actions(&l.a11y, &l.frames[(l.n + 1) % 2], router_sink, &l.router)
		if !poll(&l.w, router_sink, &l.router, virtual.arena_allocator(&l.events)) {
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
	ui.subscriptions_init(&l.subs)
	ops.init(&l.scene)
	ops.add_fonts(&l.scene, app.fonts)
	ui.frame_init(&l.frames[0])
	ui.frame_init(&l.frames[1])
	ui.router_init(&l.router)
	ui.layout_init(&l.layout)
	render.init(&l.r)
	l.shaper = render.shaper(&l.r, l.scene.fonts[:], app.fallbacks)
	render.compositor_init(&l.comp, int(app.threads))
	// The window's image is a view into one buffer that only reallocates
	// when a resize outgrows it, and then present invalidates the damage.
	l.comp.damage.resize_in_place = true
	l.font = app.fonts[0].id if len(app.fonts) > 0 else 0
	for &a in l.arenas {
		if err := ops.frame_arena_init(&a); err != nil {
			fmt.eprintln("shell: arena:", err)
			return false
		}
	}
	if err := virtual.arena_init_growing(&l.events); err != nil {
		fmt.eprintln("shell: arena:", err)
		return false
	}
	l.last = sdl3.GetTicksNS()
	ui.debug_tray_init(&l.tray)
	ui.recorder_from_env(&l.rec)
	if !app.no_accessibility && bridge_init(&l.a11y, l.w.window, app.title) {
		l.w.a11y = &l.a11y
	}
	sdl3.ShowWindow(l.w.window)
	return true
}

@(private)
loop_destroy :: proc(l: ^Loop) {
	bridge_destroy(&l.a11y)
	ui.recorder_close(&l.rec)
	virtual.arena_destroy(&l.events)
	ops.frame_arena_destroy(&l.arenas[0])
	ops.frame_arena_destroy(&l.arenas[1])
	render.compositor_destroy(&l.comp)
	render.destroy(&l.r)
	ui.layout_destroy(&l.layout)
	ui.router_destroy(&l.router)
	ui.subscriptions_destroy(&l.subs)
	ui.frame_destroy(&l.frames[0])
	ui.frame_destroy(&l.frames[1])
	ops.destroy(&l.scene)
	close(&l.w)
}

// step runs one frame: route the events polled so far, run the ui proc,
// flatten, compose and present.
@(private)
step :: proc(l: ^Loop) {
	l.in_frame = true
	defer l.in_frame = false
	arena := &l.arenas[l.n % 2]
	ops.frame_arena_reset(arena)
	allocator := ops.frame_arena_allocator(arena)
	frame, prev := &l.frames[l.n % 2], &l.frames[(l.n + 1) % 2]

	now := sdl3.GetTicksNS()
	if ui.debug_take_toggles(&l.router) {
		l.tray.open = !l.tray.open
	}
	debug := ui.debug_from_env() | ui.debug_tray_flags(&l.tray)
	raw_dt := min(f32(now - l.last) / 1e9, MAX_DT)
	dt := ui.debug_dt(debug, raw_dt)
	l.last = now
	l.time += f64(dt)

	w := &l.w
	if l.rec.f != nil {
		// The frame's input as the hot-reload host would have sent it.
		logical := ops.Size{f32(w.size.x) / w.density, f32(w.size.y) / w.density}
		ui.recorder_write(
			&l.rec,
			ui.encode_input(logical, w.density, raw_dt, l.router.queue[:], context.temp_allocator),
		)
	}
	ui.router_route(&l.router, prev if l.n > 0 else nil)
	ui.debug_tray_log(&l.tray, &l.router, prev if l.n > 0 else nil, l.n)
	ops.reset(&l.scene)
	l.scene.outline_areas = .Bounds in debug
	ui.frame_reset(frame)
	ui.layout_reset(&l.layout)
	if l.app.data.inbox != nil {
		// The shapes the application answered since the last frame.
		ui.inbox_drain(l.app.data.inbox, &l.layout)
	}

	logical := ops.Size{f32(w.size.x) / w.density, f32(w.size.y) / w.density}
	gtx := ui.Ctx {
		scene         = &l.scene,
		constraints   = ui.exact(logical),
		viewport      = logical,
		density       = w.density,
		font          = l.font,
		shaper        = l.shaper,
		router        = &l.router,
		layout        = &l.layout,
		frame         = l.n,
		dt            = dt,
		time          = l.time,
		allocator     = allocator,
		debug         = debug,
		reduce_motion = ui.reduce_motion_preferred(),
	}
	scaled := w.density != 1
	if scaled {
		ops.transform_push(&l.scene, ops.scale(w.density, w.density))
	}
	ui_start := time.tick_now()
	if l.app.ui != nil {
		l.app.ui(&gtx, l.app.user)
	}
	ui_ms := ui.ms(ui_start)
	if scaled {
		ops.transform_pop(&l.scene)
	}
	ui.debug_inspect(&gtx, debug, &l.tray, prev if l.n > 0 else nil, l.router.pointer, w.density)
	// The tray last, so it sits over the inspector's highlight too.
	if scaled {
		ops.transform_push(&l.scene, ops.scale(w.density, w.density))
	}
	ui.debug_tray(&gtx, &l.tray)
	if scaled {
		ops.transform_pop(&l.scene)
	}
	// What the frame needs and asks goes to the application now: the set
	// is whole once the frame is built, and a request should not wait on
	// the frame flattening and presenting.
	ui.data_after_frame(&l.app.data, &l.subs, &l.router)
	build_start := time.tick_now()
	ui.flatten(
		&l.scene,
		frame,
		{0, 0, f32(w.size.x), f32(w.size.y)},
		ops.scale(w.density, w.density),
	)
	build_ms := ui.ms(build_start)
	ui.text_input_update(&l.router, frame)
	present_start := time.tick_now()
	host: ui.Host_Stats
	keep_out: [2]ops.Rect
	l.shown, host.repaint_rects, host.repaint_px = present(
		w,
		&l.comp,
		frame,
		l.app.clear,
		ui.debug_tray_wants_full_frames(&l.tray),
		ui.debug_tray_wants_flash(&l.tray),
		ui.debug_tray_overlays(&l.tray, w.density, &keep_out),
	)
	host.present_ms = ui.ms(present_start)
	bridge_frame(&l.a11y, frame, l.router.focus)
	ui.debug_tray_record(
		&l.tray,
		ui.frame_stats(&gtx, frame, ui_ms, build_ms, ops.frame_arena_used(arena), host),
	)
	l.wants_frame, l.frame_after = gtx.wants_frame || l.tray.open || flashing(w), gtx.frame_after
	// The cursor and clipboard, once the frame is done; a clipboard read
	// queues its Paste, so a frame must follow to deliver it.
	reqs := ui.router_requests(&l.router)
	for q in reqs {
		if _, reads := q.(ui.Clipboard_Read); reads {
			l.wants_frame, l.frame_after = true, 0
		}
	}
	apply_platform(w, ui.router_cursor(&l.router), true, reqs, router_sink, &l.router)
	ui.router_requests_clear(&l.router)
	// An answer that landed while the frame rendered wants a frame to
	// show it.
	if l.app.data.inbox != nil && ui.inbox_pending(l.app.data.inbox) {
		l.wants_frame, l.frame_after = true, 0
	}
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
	if resize_for_new_size(&l.w) {
		step(l)
	}
	return true
}

// resize_for_new_size is redraw_on_expose's (and its Host_Loop
// counterpart's) shared body: it applies whatever WINDOW_EXPOSED implies
// for w and reports whether that was worth a frame for. A move exposes
// the window too, but its content is still right; draw only for a new
// size, on the assumption that presenting during a move is slow enough to
// itself hold the move back, which redrawing on every such expose would
// make worse. An animation pauses while the window moves.
@(private)
resize_for_new_size :: proc(w: ^Window) -> bool {
	size := w.size
	if !resize(w) {
		return false
	}
	return w.size != size
}

// go_live turns vsync off for frames drawn while the window is being
// resized; settle turns it back on once they stop.
@(private)
go_live :: proc(w: ^Window) {
	w.live_at = sdl3.GetTicks()
	if !w.live {
		sdl3.SetRenderVSync(w.renderer, 0)
		w.live = true
	}
}

@(private)
open :: proc(w: ^Window, app: App) -> bool {
	title := strings.clone_to_cstring(
		app.title if app.title != "" else "ui",
		context.temp_allocator,
	)
	width, height := app.width, app.height
	if width <= 0 {
		width = 800
	}
	if height <= 0 {
		height = 600
	}
	// Hidden until the loop has its bridge to assistive technology: the
	// Windows adapter must attach before the window is first shown.
	w.window = sdl3.CreateWindow(
		title,
		i32(width),
		i32(height),
		{.RESIZABLE, .HIGH_PIXEL_DENSITY, .HIDDEN},
	)
	if w.window == nil {
		fmt.eprintln("shell: window:", sdl3.GetError())
		return false
	}
	if app.min_width > 0 || app.min_height > 0 {
		_ = sdl3.SetWindowMinimumSize(w.window, i32(app.min_width), i32(app.min_height))
	}
	w.renderer = sdl3.CreateRenderer(w.window, nil)
	if w.renderer == nil {
		fmt.eprintln("shell: renderer:", sdl3.GetError())
		sdl3.DestroyWindow(w.window)
		return false
	}
	sdl3.SetRenderVSync(w.renderer, 1)
	bl.image_init(&w.pixels)
	bl.image_init(&w.view)
	// Text input is off, as SDL starts a window ("Text input events are not
	// received by default", SDL_keyboard.h), until a text area takes focus
	// (apply_text_input).
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
	destroy_cursors(w)
	delete(w.flashes)
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
		// The window shows its new size before a frame for it arrives: the
		// old frame, cropped when shrinking. Waiting for vsync to present
		// the new one keeps that on screen up to a refresh longer.
		if !exact && w.textures[0] != nil {
			go_live(w)
			w.sized = true
		}
	}
	w.size = size
	if size.x <= 0 || size.y <= 0 {
		return true
	}
	fits := w.textures[0] != nil && size.x <= w.cap.x && size.y <= w.cap.y
	if exact || !fits {
		// The first allocation has no resize in progress to leave room for.
		// A resize that outgrows the buffers grows them to the display, so
		// the rest of the drag draws into what is allocated.
		cap := size
		if !exact && w.textures[0] != nil {
			d := display_pixels(w)
			cap = {max(size.x + GROW, d.x), max(size.y + GROW, d.y)}
		}
		destroy_textures(w)
		// ARGB8888 is a native-endian 0xAARRGGBB word: Blend2D's PRGB32
		// layout. Copies between the textures must be exact: no blending,
		// no filtering.
		for &t in w.textures {
			t = sdl3.CreateTexture(w.renderer, .ARGB8888, .TARGET, cap.x, cap.y)
			if t == nil {
				fmt.eprintln("shell: texture:", sdl3.GetError())
				return false
			}
			sdl3.SetTextureBlendMode(t, sdl3.BLENDMODE_NONE)
			sdl3.SetTextureScaleMode(t, .NEAREST)
		}
		if bl.image_create(&w.pixels, cap.x, cap.y, .PRGB32) != 0 {
			fmt.eprintln("shell: image: out of memory")
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
	return(
		bl.image_create_from_data(
			&w.view,
			size.x,
			size.y,
			.PRGB32,
			data.pixel_data,
			data.stride,
			.RW,
			nil,
			nil,
		) ==
		0 \
	)
}

// display_pixels is the size, in pixels, of the display showing w.
@(private)
display_pixels :: proc(w: ^Window) -> [2]i32 {
	mode := sdl3.GetCurrentDisplayMode(sdl3.GetDisplayForWindow(w.window))
	if mode == nil {
		return {}
	}
	d := mode.pixel_density if mode.pixel_density > 0 else 1
	return {i32(f32(mode.w) * d), i32(f32(mode.h) * d)}
}

// settle turns vsync back on once the size has not changed for LIVE_MS,
// and shrinks the image and textures to the window once it has not changed
// for SETTLE_MS.
@(private)
settle :: proc(w: ^Window) {
	since := sdl3.GetTicks() - w.resized
	if w.live && sdl3.GetTicks() - w.live_at >= LIVE_MS {
		sdl3.SetRenderVSync(w.renderer, 1)
		w.live = false
	}
	if w.cap == w.size || w.size.x <= 0 || w.size.y <= 0 || since < SETTLE_MS {
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
	// A resize in progress, or oversized buffers, wake the loop in time for
	// settle.
	if w.live || w.cap != w.size {
		now := sdl3.GetTicks()
		due_live := i64(LIVE_MS) - i64(now - w.live_at)
		due_settle := i64(SETTLE_MS) - i64(now - w.resized)
		left := due_live if w.live else due_settle
		if w.live && w.cap != w.size {
			left = min(due_live, due_settle)
		}
		due := i32(max(left, 0)) + 1
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
	if mode := sdl3.GetCurrentDisplayMode(sdl3.GetDisplayForWindow(w.window));
	   mode != nil && mode.refresh_rate > 0 {
		return max(i32(1000 / mode.refresh_rate), 1)
	}
	return 16
}

// present repaints what f changed in the window's image and brings the
// front texture up to date. It shows the texture and reports true when
// anything changed or the window must be shown again.
@(private)
present :: proc(
	w: ^Window,
	c: ^render.Compositor,
	f: ^ui.Frame,
	clear: ops.Color,
	full := false,
	flash := false,
	keep_out: []ops.Rect = nil,
) -> (
	shown: bool,
	repaint_rects, repaint_px: int,
) {
	if w.textures[0] == nil {
		return
	}
	data: bl.ImageData
	if bl.image_get_data(&w.view, &data) != 0 {
		return
	}
	if full {
		// The debug tray's full frames: redraw and upload all of it, as if
		// the image were new, to rule the damage tracker out of a glitch.
		w.fresh, w.stale = true, true
	}
	if w.fresh {
		// The compositor must not trust what it drew into the old image.
		render.damage_invalidate(&c.damage)
		w.fresh = false
	}
	changed := render.compose(c, f, &w.view, clear)
	repaint_rects = len(changed)
	for r in changed {
		repaint_px += int(r.w * r.h)
	}
	if flash {
		// Never over keep_out, the debug panels: they repaint every frame,
		// and their own flash would hide them.
		at := sdl3.GetTicks()
		for r in changed {
			flash_outside(w, r, keep_out, at)
		}
	}
	if !w.stale && !w.exposed && len(changed) == 0 && len(w.flashes) == 0 {
		return
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
	draw_flashes(w)
	sdl3.RenderPresent(w.renderer)
	if w.sized {
		// Hold the resize until this frame is on screen, so the window is
		// never shown at a size its content was not drawn for.
		wait_for_compositor()
		w.sized = false
	}
	return true, repaint_rects, repaint_px
}

// upload copies r of the image into the same place in t.
@(private)
upload :: proc(t: ^sdl3.Texture, data: ^bl.ImageData, r: ops.Rect) {
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

// Event_Sink receives one Raw_Event polled off SDL's queue: ui.router_push
// for a single-process App, or a batch append for a host/subprocess split.
// user is whatever poll's caller passed it.
@(private)
Event_Sink :: proc(user: rawptr, e: ui.Raw_Event)

// poll drains SDL's queue, translating input events to sink (text cloned
// into allocator first) and handling window/render-target events itself.
// It returns false when the app should quit.
@(private)
poll :: proc(w: ^Window, sink: Event_Sink, user: rawptr, allocator := context.allocator) -> bool {
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
			bridge_window_bounds(w.a11y)
		case .WINDOW_EXPOSED:
			w.exposed = true
		case .WINDOW_FOCUS_GAINED:
			bridge_window_focus(w.a11y, true)
		case .WINDOW_FOCUS_LOST:
			bridge_window_focus(w.a11y, false)
		case .WINDOW_MOVED, .WINDOW_SHOWN, .WINDOW_MAXIMIZED, .WINDOW_RESTORED:
			bridge_window_bounds(w.a11y)
		case .RENDER_TARGETS_RESET:
			w.stale = true
		case .RENDER_DEVICE_RESET:
			destroy_textures(w)
			if !resize(w) {
				return false
			}
		case .MOUSE_MOTION:
			sink(
				user,
				{
					kind = .Move,
					pos = {e.motion.x * d, e.motion.y * d},
					mods = mods(sdl3.GetModState()),
				},
			)
		case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP:
			// The side buttons are navigation keys, as a browser takes
			// them: pressed, not released, and routed to whatever asks
			// for the key app-wide rather than to what is under the pointer.
			if e.button.button == sdl3.BUTTON_X1 || e.button.button == sdl3.BUTTON_X2 {
				if e.type == .MOUSE_BUTTON_DOWN {
					sink(
						user,
						{
							kind = .Key,
							key = .Browser_Back if e.button.button == sdl3.BUTTON_X1 else .Browser_Forward,
							mods = mods(sdl3.GetModState()),
						},
					)
				}
				continue
			}
			btn, ok := button(e.button.button)
			if !ok {
				continue
			}
			kind: ops.Event_Kind = .Press if e.type == .MOUSE_BUTTON_DOWN else .Release
			// clicks is SDL's count of rapid presses ("1 for single-click, 2
			// for double-click", sdl3_events.odin), which SDL takes from the
			// system's double-click setting where it has one.
			sink(
				user,
				{
					kind = kind,
					pos = {e.button.x * d, e.button.y * d},
					button = btn,
					mods = mods(sdl3.GetModState()),
					clicks = e.button.clicks,
				},
			)
		case .MOUSE_WHEEL:
			// Positive y scrolls down (toward the user), like a scroll offset.
			precise := wheel_precise(e.wheel.x, e.wheel.y)
			s := [2]f32{e.wheel.x, -e.wheel.y}
			if e.wheel.direction == .FLIPPED {
				s = -s
			}
			// A trackpad's delta is points: as steps of ui.SCROLL_STEP,
			// the content moves exactly as far as the fingers, and the
			// momentum after them (see scroll_darwin.odin).
			if precise {
				s *= PRECISE_POINTS / ui.SCROLL_STEP
			}
			sink(
				user,
				{
					kind = .Scroll,
					pos = {e.wheel.mouse_x * d, e.wheel.mouse_y * d},
					scroll = s,
					mods = mods(sdl3.GetModState()),
				},
			)
		case .KEY_DOWN:
			// While an input method composes, no key reaches the ui: a
			// Backspace or Escape there edits or cancels the composition,
			// never the field or the window.
			if w.composing {
				continue
			}
			k := key(e.key.key)
			if k == .Escape {
				return false
			}
			if k != .None {
				sink(user, {kind = .Key, key = k, mods = mods(e.key.mod)})
			}
		case .TEXT_INPUT:
			w.composing = false
			text := strings.clone_from_cstring(e.text.text, allocator)
			sink(user, {kind = .Text, text = text, mods = mods(sdl3.GetModState())})
		case .TEXT_EDITING:
			text := strings.clone_from_cstring(e.edit.text, allocator)
			w.composing = len(text) > 0
			sink(user, {kind = .Compose, text = text, span = compose_span(text, e.edit.start, e.edit.length)})
		}
	}
	return true
}

// compose_span is an input method's caret or selection, start and length
// in characters as SDL gives them (SDL_TextEditingEvent; -1 when unset),
// as byte offsets lo, hi into text; unset is the end of text.
@(private)
compose_span :: proc(text: string, start, length: i32) -> [2]int {
	if start < 0 {
		return {len(text), len(text)}
	}
	lo := byte_of_rune(text, int(start))
	hi := lo
	if length > 0 {
		hi = lo + byte_of_rune(text[lo:], int(length))
	}
	return {lo, hi}
}

// byte_of_rune is the byte offset of rune n in text, len(text) past its end.
@(private)
byte_of_rune :: proc(text: string, n: int) -> int {
	count := 0
	for _, at in text {
		if count == n {
			return at
		}
		count += 1
	}
	return len(text)
}

// router_sink is poll's Event_Sink for a single-process App: user is the
// App's own ^ui.Router.
@(private)
router_sink :: proc(user: rawptr, e: ui.Raw_Event) {
	ui.router_push((^ui.Router)(user), e)
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
	case sdl3.K_F11:
		return .F11
	}
	return .None
}
