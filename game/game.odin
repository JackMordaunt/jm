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
}

// POINTER_AREA is the input area over the game that hears the pointer.
@(private)
POINTER_AREA :: ops.Area_Id(0x6a6d_6761_6d65) // "jmgame"

// runner_init readies runner to run game over world. It does not call init.
runner_init :: proc(runner: ^Runner($W), game: Game(W), world: ^W) {
	runner^ = {
		world = world,
		game = game,
		core = {size = game.size, clear = game.clear},
	}
	clock_init(&runner.core.clock, game.dt, game.max_ticks)
}

// runner_frame is the ui proc that runs a Runner(W): the ticks the frame's
// dt is due, then the draw.
runner_frame :: proc($W: typeid) -> ui.UI_Proc {
	return proc(gtx: ^ui.Ctx, user: rawptr) {
		runner := (^Runner(W))(user)
		ticks, first := core_advance(&runner.core, gtx)
		for ii in 0 ..< ticks {
			runner.game.step(runner.world, take_input(&runner.core.gather, first + u64(ii)))
		}
		canvas := canvas_open(&runner.core, gtx)
		runner.game.draw(runner.world, &canvas)
		canvas_close(&canvas)
	}
}

// core_advance gathers the frame's input and returns how many ticks its
// dt is due, and the first of them.
@(private)
core_advance :: proc(core: ^Runner_Core, gtx: ^ui.Ctx) -> (ticks: int, first: u64) {
	ui.request_frame(gtx)
	gather_keys(&core.gather, ui.key_state(gtx))
	for event in ui.events(gtx, POINTER_AREA) {
		gather_pointer(&core.gather, event)
	}
	ticks = clock_advance(&core.clock, gtx.dt)
	return ticks, core.clock.tick - u64(ticks)
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
	play_in_window(runner_frame(W), &runner, game.size, game.title, game.scale, game.keep_escape)
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
