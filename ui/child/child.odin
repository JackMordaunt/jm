/*
Package child runs a ui proc as the subprocess half of the hot-reload
split: it owns the Model, the ui proc, Router and Layout, and knows
nothing about a window. Each cycle it reads one ui/wire Input from its own
stdin, routes the queued events against the previous frame, runs the ui
proc, flattens, and writes back one Reply — the encoded Ops plus whether
and when it wants another frame — to its own stdout. run blocks until the
host closes the pipe (EOF), which is this process's cue to exit 0.

	child.run(diagram_ui, &model, {{0, shell.default_font()}})

The host side is ui/shell's run_host; ui/wire is the byte layout on the
pipe, ui/ipc the framing underneath that.
*/
package child

import "core:fmt"
import "core:os"
import t "core:time"
import "jm:ui/ops"

import "jm:ui"
import "jm:ui/ipc"
import "jm:ui/render"

// Ui_Proc is ui.UI_Proc, run once per Input.
Ui_Proc :: ui.UI_Proc

// Inside App the field named ui shadows the package, so its other field
// types are spelled through these aliases (as ui/shell's App does).
@(private)
Font_Ref :: ops.Font_Ref
@(private)
Data_Host :: ui.Data_Host

// App describes the ui proc to run and what it needs. size and density
// come from the host with every Input, not from App: the subprocess never
// owns a window and does not decide its own size.
App :: struct {
	ui:        Ui_Proc,
	user:      rawptr,
	fonts:     []Font_Ref, // registered into the Scene under their own ids before the first frame
	// fallbacks are font ids, of fonts, tried in order for a rune the font
	// asked for lacks.
	fallbacks: []ops.Font_Id,
	// Where the frames' needs and commands go. Left empty, they go over
	// the wire to the host's Host_App.data, and the host's answers come
	// back with each input. Given, the application is in this process:
	// the needs and commands are dispatched here and the inbox is drained
	// here, and the wire carries none of it. See ui/need.odin.
	data:      Data_Host,
}

// run drives app until the host closes stdin, then returns. It is meant
// to be the whole of a subprocess's main.
run :: proc(app: App) {
	app := app
	sc: ops.Scene
	ops.init(&sc)
	defer ops.destroy(&sc)
	ops.add_fonts(&sc, app.fonts)

	frames: [2]ui.Frame
	ui.frame_init(&frames[0])
	ui.frame_init(&frames[1])
	defer ui.frame_destroy(&frames[0])
	defer ui.frame_destroy(&frames[1])
	frame, prev := &frames[0], &frames[1]
	sent_cursor: ops.Cursor // the host starts with the default arrow

	router: ui.Router
	ui.router_init(&router)
	defer ui.router_destroy(&router)

	layout: ui.Layout
	ui.layout_init(&layout)
	defer ui.layout_destroy(&layout)

	subs: ui.Subscriptions
	ui.subscriptions_init(&subs)
	defer ui.subscriptions_destroy(&subs)
	local := app.data.on_need != nil || app.data.on_command != nil || app.data.inbox != nil

	// r only shapes text (never rasterizes: the host's own Renderer, inside
	// its Compositor, does that), so r.threads is never set.
	r: render.Renderer
	render.init(&r)
	defer render.destroy(&r)
	shaper := render.shaper(&r, sc.fonts[:], app.fallbacks)

	font := app.fonts[0].id if len(app.fonts) > 0 else 0

	arenas: [2]ops.Frame_Arena
	for &a in arenas {
		if err := ops.frame_arena_init(&a); err != nil {
			return
		}
	}
	defer ops.frame_arena_destroy(&arenas[0])
	defer ops.frame_arena_destroy(&arenas[1])

	env_debug := ui.debug_from_env()
	rec: ui.Recorder // every input, when ui.RECORD_ENV names a file
	ui.recorder_from_env(&rec)
	defer ui.recorder_close(&rec)
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
		shapes: []ui.Delivery
		size, density, raw_dt, events, host, restore, dok := ui.decode_input(
			payload,
			allocator,
			&shapes,
		)
		if !dok {
			// A host built from other sources is the usual cause: say so,
			// since the host sees only that its child went away.
			if v, vok := ui.input_version(payload); vok && v != ui.INPUT_VERSION {
				fmt.eprintfln("ui/child: the host sends input version %d, this child reads %d: rebuild the host", v, ui.INPUT_VERSION)
			}
			return // a corrupt request; nothing salvageable
		}
		// With the application here, its answers since the last frame
		// join the host's, so a recording has them all.
		local_shapes: []ui.Delivery
		if app.data.inbox != nil {
			local_shapes = ui.inbox_take(app.data.inbox, allocator)
		}
		if len(local_shapes) == 0 {
			ui.recorder_write(&rec, payload)
		} else if rec.f != nil {
			all := make([]ui.Delivery, len(shapes) + len(local_shapes), allocator)
			copy(all, shapes)
			copy(all[len(shapes):], local_shapes)
			ui.recorder_write(&rec, ui.encode_input(size, density, raw_dt, events, allocator, host, restore, all))
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
		for d in shapes {
			ui.deliver(&layout, d.key, d.data, d.status)
		}
		for shape in local_shapes {
			ui.deliver(&layout, shape.key, shape.data, shape.status)
		}

		gtx := ui.Ctx {
			scene         = &sc,
			constraints   = ui.exact(size),
			viewport      = size,
			density       = density,
			font          = font,
			shaper        = shaper,
			router        = &router,
			layout        = &layout,
			frame         = n,
			dt            = dt,
			time          = time,
			allocator     = allocator,
			debug         = debug,
			restored      = restore,
			reduce_motion = ui.reduce_motion_preferred(),
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
		// With the application here, what the frame needs and asks goes
		// to it now, before the frame is flattened and sent.
		if local {
			ui.data_after_frame(&app.data, &subs, &router)
		}
		build_start := t.tick_now()
		ui.flatten(
			&sc,
			frame,
			{0, 0, size.x * density, size.y * density},
			ops.scale(density, density),
		)
		ui.text_input_update(&router, frame)

		ops_bytes := ops.encode(&sc, allocator)
		// host is what the host said presenting the frame before cost.
		ui.debug_tray_record(
			&tray,
			ui.frame_stats(
				&gtx,
				frame,
				ui_ms,
				ui.ms(build_start),
				ops.frame_arena_used(arena),
				host,
			),
		)
		keep_out: [2]ops.Rect
		// The platform block: the cursor when it changed, and what the
		// frame asked of the clipboard, which the host carries out.
		platform: ^ui.Reply_Platform
		p: ui.Reply_Platform
		cursor := ui.router_cursor(&router)
		reqs := ui.router_requests(&router)
		if cursor != sent_cursor || len(reqs) > 0 {
			p.cursor = cursor
			for q in reqs[:min(len(reqs), len(p.requests_buf))] {
				p.requests_buf[p.requests_n] = q
				p.requests_n += 1
			}
			platform = &p
			sent_cursor = cursor
		}
		// The data block: what the frame began and stopped needing, and
		// its commands, for the host's application; or, with the
		// application here, dispatched already and not sent.
		rd: ui.Reply_Data
		wants := gtx.wants_frame || tray.open
		if local {
			if app.data.inbox != nil && ui.inbox_pending(app.data.inbox) {
				wants = true
			}
		} else {
			rd.added, rd.dropped = ui.subscriptions_update(&subs, ui.router_needs(&router))
			rd.commands = ui.router_commands(&router)
		}
		reply := ui.encode_reply(
			wants,
			gtx.frame_after,
			ops_bytes,
			allocator,
			ui.debug_tray_wants_full_frames(&tray),
			ui.debug_tray_wants_flash(&tray),
			ui.debug_tray_overlays(&tray, density, &keep_out),
			platform,
			gtx.persist,
			router.focus,
			&rd,
		)
		ui.router_requests_clear(&router)
		ui.router_needs_clear(&router)
		ui.router_commands_clear(&router)
		if !ipc.write_frame(os.stdout, reply) {
			return // the host is gone
		}

		frame, prev = prev, frame
		free_all(context.temp_allocator)
	}
}
