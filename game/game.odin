/*
Package game is a substrate for small 2D games built so an agent can
debug them: the World is plain data, step runs at a fixed tick from one
Input, and every frame is a jm:ui scene, so the tools that make a ui
debuggable headless (probes, dumps, recordings) reach a game too.

	World :: struct {
		box: [2]f32,
	}

	step :: proc(world: ^World, input: game.Input) {
		world.box.x += 2 * game.axis(input, {.Left}, {.Right})
	}

	draw :: proc(world: ^World, canvas: ^game.Canvas) {
		ops.fill(canvas.scene, ops.Rect{world.box.x, world.box.y, 16, 16}, ops.Color{255, 200, 0, 255})
	}

	main :: proc() {
		world: World
		game.run(game.Game(World){title = "Box", size = {320, 180}, step = step, draw = draw}, &world)
	}

A game is three procs over its World. init sets the World up from a seed;
step advances it one tick and is the only thing that changes it; draw
paints it, and changes nothing. step must be deterministic: its only
inputs are the World and the Input, so randomness comes from an Rng kept
in the World (rng.odin), and never from the clock. check_world holds the
World to plain data (world.odin), which is what makes it cheap to copy,
compare, record and keep across a hot reload.

Ticks: the clock turns frame time into whole ticks of Game.dt (clock.odin);
draw runs once a frame after them, and clock_alpha says how far the frame
is towards the next tick.

Units: the game draws in its own units, Game.size, which the window shows
letterboxed at the largest scale that fits; the pointer comes back in the
same units.
*/
package game

import "core:fmt"
import "core:os"

import jm_path "jm:path"
import "jm:ui"
import "jm:ui/ops"
import "jm:ui/shell"

// Game is a game: its procs over the World W and how it runs.
Game :: struct($W: typeid) {
	title:       string,
	size:        [2]f32, // the game's own units, which the window scales to fit
	scale:       f32, // the window opens at size times scale; 0 is 2
	dt:          f64, // seconds a tick stands for; 0 is DEFAULT_DT
	max_ticks:   int, // the most ticks a late frame runs; 0 is DEFAULT_MAX_TICKS
	seed:        u64, // given to init
	clear:       ops.Color, // the game's background; the letterbox is black
	keep_escape: bool, // Escape goes to the game as a key, rather than closing the window
	overlay:     bool, // start with the debug overlay showing (overlay.odin); OVERLAY_KEY turns it on and off
	init:        proc(world: ^W, seed: u64), // optional
	step:        proc(world: ^W, input: Input),
	draw:        proc(world: ^W, canvas: ^Canvas),
}

// Runner runs a Game over its World frame by frame: runner_frame(W) is
// the ui proc, with the Runner as its user. game.run makes one for a
// window; a test makes one for a ui.Probe:
//
//	runner: game.Runner(World)
//	game.runner_init(&runner, my_game, &world)
//	ui.probe_init(&probe, game.runner_frame(World), &runner, {640, 360})
Runner :: struct($W: typeid) {
	world: ^W,
	game:  Game(W),
	core:  Runner_Core,
}

// Runner_Core is the part of a Runner that does not depend on the World:
// one copy of its code serves every game.
@(private)
Runner_Core :: struct {
	size:   [2]f32,
	clear:  ops.Color,
	clock:  Clock,
	gather: Input_Gather,
	writer: Tape_Writer, // where each tick's Input is recorded, when open
	replay: ^Tape, // where the ticks' Input comes from instead of the devices, when set: runner_replay
	overlay: Overlay,
}

// POINTER_AREA is the input area over the game that hears the pointer.
@(private)
POINTER_AREA :: ops.Area_Id(0x6a6d_6761_6d65) // "jmgame"

// runner_init readies runner to run game over world. It does not call init.
runner_init :: proc(runner: ^Runner($W), game: Game(W), world: ^W) {
	runner^ = {
		world = world,
		game = game,
		core = {size = game.size, clear = game.clear, overlay = {on = game.overlay}},
	}
	clock_init(&runner.core.clock, game.dt, game.max_ticks)
}

// runner_destroy frees what runner holds; its World is the caller's.
runner_destroy :: proc(runner: ^Runner($W)) {
	runner_record_stop(runner)
	overlay_destroy(&runner.core.overlay)
}

// runner_frame is the ui proc that runs a Runner(W): the ticks the frame's
// dt is due, then the draw.
runner_frame :: proc($W: typeid) -> ui.UI_Proc {
	return proc(gtx: ^ui.Ctx, user: rawptr) {
		runner := (^Runner(W))(user)
		ticks, first := core_advance(&runner.core, gtx)
		for ii in 0 ..< ticks {
			input := core_input(&runner.core, first + u64(ii)) or_break
			runner.game.step(runner.world, input)
		}
		overlay_target = nil
		canvas := canvas_open(&runner.core, gtx)
		overlay_aim(&runner.core.overlay, &runner.core.overlay.frame)
		runner.game.draw(runner.world, &canvas)
		overlay_target = nil
		overlay_paint(&runner.core.overlay, &canvas, canvas.scale)
		canvas_close(&canvas)
	}
}

// core_advance gathers the frame's input and returns how many ticks its
// dt is due, and the first of them.
@(private)
core_advance :: proc(core: ^Runner_Core, gtx: ^ui.Ctx) -> (ticks: int, first: u64) {
	ui.request_frame(gtx)
	keys := ui.key_state(gtx)
	if OVERLAY_KEY in keys.pressed {
		core.overlay.on = !core.overlay.on
	}
	gather_keys(&core.gather, keys)
	for event in ui.events(gtx, POINTER_AREA) {
		gather_pointer(&core.gather, event)
	}
	ticks = clock_advance(&core.clock, gtx.dt)
	return ticks, core.clock.tick - u64(ticks)
}

// core_input is tick's Input: the replay's when there is one, false once
// it has run out, else the devices'. It is recorded either way.
@(private)
core_input :: proc(core: ^Runner_Core, tick: u64) -> (input: Input, ok: bool) {
	if core.replay != nil {
		input = tape_next(core.replay) or_return
	} else {
		input = take_input(&core.gather, tick)
	}
	tape_write(&core.writer, input)
	overlay_aim(&core.overlay, &core.overlay.tick)
	return input, true
}

// runner_record records runner's ticks from now to a tape at path, with
// its World as it is now, until runner_record_stop.
runner_record :: proc(runner: ^Runner($W), path: string) -> bool {
	return tape_writer_open(&runner.core.writer, path, runner.world, runner.game.seed, runner.core.clock.dt)
}

// runner_record_stop ends the tape runner_record began.
runner_record_stop :: proc(runner: ^Runner($W)) {
	tape_writer_close(&runner.core.writer)
}

// runner_replay plays tape through runner as it would have run live:
// the World becomes the one the tape began with, and each tick takes its
// Input from the tape, until the tape runs out and the game stands still.
// tape must outlive the runner's frames. It is false, and changes
// nothing, when the tape's World is not a W.
runner_replay :: proc(runner: ^Runner($W), tape: ^Tape) -> bool {
	if len(tape.world) != size_of(W) {
		return false
	}
	runner.world^ = (^W)(raw_data(tape.world))^
	runner.core.replay = tape
	return true
}

// canvas_open paints the letterbox and returns a Canvas in the game's
// units, clipped to the game, with the pointer's input area over it.
@(private)
canvas_open :: proc(core: ^Runner_Core, gtx: ^ui.Ctx) -> Canvas {
	transform, covers := letterbox(core.size, gtx.viewport)
	ops.fill(gtx.scene, ops.Rect{0, 0, gtx.viewport.x, gtx.viewport.y}, ops.Color{0, 0, 0, 255})
	ops.fill(gtx.scene, covers, core.clear)
	ops.transform_push(gtx.scene, transform)
	ops.clip_push(gtx.scene, ops.Rect{0, 0, core.size.x, core.size.y})
	ops.input_area(gtx.scene, POINTER_AREA, ops.Rect{0, 0, core.size.x, core.size.y}, {.Press, .Release, .Move})
	return {
		gtx = gtx,
		scene = gtx.scene,
		size = core.size,
		scale = f32(transform.a),
		alpha = clock_alpha(&core.clock),
		tick = core.clock.tick,
	}
}

// canvas_close ends what canvas_open began.
@(private)
canvas_close :: proc(canvas: ^Canvas) {
	ops.clip_pop(canvas.scene)
	ops.transform_pop(canvas.scene)
}

// run checks world is plain data, calls game.init, and plays the game in
// a window until it closes. A World that is not plain data is named on
// stderr, field by field, and nothing runs.
run :: proc(game: Game($W), world: ^W) {
	if !world_is_plain(W) {
		return
	}
	if game.init != nil {
		game.init(world, game.seed)
	}
	runner: Runner(W)
	runner_init(&runner, game, world)
	when ODIN_DEBUG {
		if path, ok := rolling_tape(game.title); ok && runner_record(&runner, path) {
			fmt.eprintln("game: recording to", path)
		}
	}
	play_in_window(runner_frame(W), &runner, game.size, game.title, game.scale, game.keep_escape)
	runner_destroy(&runner)
}

// ROLLING_TAPES is how many of its last runs a debug build keeps.
ROLLING_TAPES :: 3

// rolling_tape is where a debug build records its run: last.tape in the
// game's state directory, with the runs before it moved down to
// last-1.tape and on, the oldest of ROLLING_TAPES dropped.
@(private)
rolling_tape :: proc(title: string) -> (path: string, ok: bool) {
	// The title as a directory name: letters lowered, digits kept, the
	// rest a dash.
	name := make([]byte, len(title), context.temp_allocator)
	for char, ii in transmute([]byte)title {
		switch char {
		case 'a' ..= 'z', '0' ..= '9':
			name[ii] = char
		case 'A' ..= 'Z':
			name[ii] = char - 'A' + 'a'
		case:
			name[ii] = '-'
		}
	}
	dir, err := jm_path.state_dir(fmt.tprintf("jm-game/%s", string(name) if len(name) > 0 else "game"), context.temp_allocator)
	if err != nil || jm_path.mkdirs(dir) != nil {
		return "", false
	}
	tape_name :: proc(dir: string, run: int) -> string {
		return jm_path.join(dir, "last.tape" if run == 0 else fmt.tprintf("last-%d.tape", run), allocator = context.temp_allocator)
	}
	for run := ROLLING_TAPES - 1; run > 0; run -= 1 {
		os.rename(tape_name(dir, run - 1), tape_name(dir, run))
	}
	return tape_name(dir, 0), true
}

// world_is_plain reports whether world passes check_world, and names on
// stderr each field that does not.
@(private)
world_is_plain :: proc(world: typeid) -> bool {
	problems := check_world(world, context.temp_allocator)
	if len(problems) == 0 {
		return true
	}
	fmt.eprintfln("game: %v is not plain data:", world)
	for problem in problems {
		fmt.eprintln("  ", problem)
	}
	return false
}

// play_in_window plays frame over runner in a window of size times scale (0
// is 2) until it closes.
@(private)
play_in_window :: proc(frame: ui.UI_Proc, runner: rawptr, size: [2]f32, title: string, scale: f32, keep_escape: bool) {
	scale := scale if scale > 0 else 2
	shell.run(
		{
			title = title,
			width = int(size.x * scale),
			height = int(size.y * scale),
			ui = frame,
			user = runner,
			fonts = {{0, ui.default_font(), 0}},
			clear = {0, 0, 0, 255},
			keep_escape = keep_escape,
		},
	)
}
