/*
Package child runs a ui proc as the subprocess half of the hot-reload
split: it owns the Model, the ui proc, Router and Layout, and knows
nothing about a window. Each cycle it reads one ui/wire Input from its own
stdin, routes the queued events against the previous frame, runs the ui
proc, flattens, and writes back one Reply — the encoded Ops plus whether
and when it wants another frame — to its own stdout. run blocks until the
host closes the pipe (EOF), which is this process's cue to exit 0.

	child.run(diagram_ui, &model, {{0, sdl.default_font()}})

The host side is ui/sdl's run_host; ui/wire is the byte layout on the
pipe, ui/ipc the framing underneath that.
*/
package child

import "core:os"
import "jm:ui/ops"
import t "core:time"

import "jm:ui"
import "jm:ui/ipc"
import "jm:ui/render"

// Ui_Proc is ui.Ui_Proc, run once per Input.
Ui_Proc :: ui.Ui_Proc

// Inside App the field named ui shadows the package, so its other field
// types are spelled through these aliases (as ui/sdl's App does).
@(private)
Theme :: ui.Theme
@(private)
Font_Ref :: ops.Font_Ref

// App describes the ui proc to run and what it needs. size and density
// come from the host with every Input, not from App: the subprocess never
// owns a window and does not decide its own size.
App :: struct {
	ui:    Ui_Proc,
	user:  rawptr,
	theme: ^Theme, // nil uses ui.default_theme with the first font
	fonts: []Font_Ref, // registered into the Scene in order before the first frame
}

// run drives app until the host closes stdin, then returns. It is meant
// to be the whole of a subprocess's main.
run :: proc(app: App) {
	sc: ops.Scene
	ops.init(&sc)
	defer ops.destroy(&sc)
	for ref in app.fonts {
		ops.add_font(&sc, ref.path)
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

	// r only shapes text (never rasterizes: the host's own Renderer, inside
	// its Compositor, does that), so r.threads is never set.
	r: render.Renderer
	render.init(&r)
	defer render.destroy(&r)
	shaper := render.shaper(&r, sc.fonts[:])

	theme := app.theme
	default_theme := ui.default_theme(app.fonts[0].id if len(app.fonts) > 0 else 0)
	if theme == nil {
		theme = &default_theme
	}

	arenas: [2]ops.Frame_Arena
	for &a in arenas {
		if err := ops.frame_arena_init(&a); err != nil {
			return
		}
	}
	defer ops.frame_arena_destroy(&arenas[0])
	defer ops.frame_arena_destroy(&arenas[1])

	env_debug := ui.debug_from_env()
	tray: ui.Debug_Tray // ui.DEBUG_TOGGLE_KEY opens it
	ui.debug_tray_init(&tray)
	time: f64
	for n: u64 = 0;; n += 1 {
		arena := &arenas[n % 2]
		ops.frame_arena_reset(arena)
		allocator := ops.frame_arena_allocator(arena)

		payload, ok := ipc.read_frame(os.stdin, allocator)
		if !ok {
			return // the host closed the pipe: exit clean
		}
		size, density, raw_dt, events, host, dok := ui.decode_input(payload, allocator)
		if !dok {
			return // a corrupt request; nothing salvageable
		}

		for e in events {
			ui.router_push(&router, e)
		}
		if ui.debug_take_toggles(&router) {
			tray.open = !tray.open
		}
		debug := env_debug | ui.debug_tray_flags(&tray)
		dt := ui.debug_dt(debug, raw_dt)
		time += f64(dt)
		ui.router_route(&router, prev if n > 0 else nil)
		ui.debug_tray_log(&tray, &router, prev if n > 0 else nil, n)
		ops.reset(&sc)
		sc.outline_areas = .Bounds in debug
		ui.frame_reset(frame)
		ui.layout_reset(&layout)

		gtx := ui.Ctx {
			scene         = &sc,
			constraints = ui.exact(size),
			theme       = theme,
			shaper      = shaper,
			router      = &router,
			layout      = &layout,
			frame       = n,
			dt          = dt,
			time        = time,
			allocator   = allocator,
			debug       = debug,
		}
		scaled := density != 1
		if scaled {
			ops.transform_push(&sc, ops.scale(density, density))
		}
		ui_start := t.tick_now()
		if app.ui != nil {
			app.ui(&gtx, app.user)
		}
		ui_ms := ui.ms(ui_start)
		if scaled {
			ops.transform_pop(&sc)
		}
		ui.debug_inspect(&gtx, debug, &tray, prev if n > 0 else nil, router.pointer, density)
		// The tray last, so it sits over the inspector's highlight too.
		if scaled {
			ops.transform_push(&sc, ops.scale(density, density))
		}
		ui.debug_tray(&gtx, &tray)
		if scaled {
			ops.transform_pop(&sc)
		}
		build_start := t.tick_now()
		ui.flatten(&sc, frame)

		ops_bytes := ops.encode(&sc, allocator)
		// host is what the host said presenting the frame before cost.
		ui.debug_tray_record(&tray, ui.frame_stats(&gtx, frame, ui_ms, ui.ms(build_start), int(arena.arena.total_used), host))
		keep_out: [2]ops.Rect
		reply := ui.encode_reply(
			gtx.wants_frame || tray.open,
			gtx.frame_after,
			ops_bytes,
			allocator,
			ui.debug_tray_wants_full_frames(&tray),
			ui.debug_tray_wants_flash(&tray),
			ui.debug_tray_overlays(&tray, density, &keep_out),
		)
		if !ipc.write_frame(os.stdout, reply) {
			return // the host is gone
		}

		frame, prev = prev, frame
		free_all(context.temp_allocator)
	}
}
