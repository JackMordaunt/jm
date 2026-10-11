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

// Runner runs a Game's World frame by frame: runner_frame is the ui proc,
// with the Runner as its user. game.run makes one for a window; a test
// makes one for a ui.Probe:
//
//	runner: game.Runner
//	game.runner_init(&runner, my_game, &world)
//	ui.probe_init(&probe, game.runner_frame, &runner, {640, 360})
//
// It holds the Game's procs with the World's type erased, so one
// non-generic ui proc runs any game.
Runner :: struct {
	world:       rawptr,
	world_type:  typeid,
	step:        proc(world: rawptr, input: Input),
	draw:        proc(world: rawptr, canvas: ^Canvas),
	size:        [2]f32,
	clear:       ops.Color,
	clock:       Clock,
	gather:      Input_Gather,
}

// POINTER_AREA is the input area over the game that hears the pointer.
@(private)
POINTER_AREA :: ops.Area_Id(0x6a6d_6761_6d65) // "jmgame"

// runner_init readies runner to run game over world. It does not call init.
runner_init :: proc(runner: ^Runner, game: Game($W), world: ^W) {
	runner^ = {
		world      = world,
		world_type = W,
		step       = auto_cast game.step,
		draw       = auto_cast game.draw,
		size       = game.size,
		clear      = game.clear,
	}
	clock_init(&runner.clock, game.dt, game.max_ticks)
}

// runner_frame is the ui proc that runs a Runner: the ticks the frame's dt
// is due, then the draw.
runner_frame :: proc(gtx: ^ui.Ctx, user: rawptr) {
	runner := (^Runner)(user)
	ui.request_frame(gtx)
	gather_keys(&runner.gather, ui.key_state(gtx))
	for event in ui.events(gtx, POINTER_AREA) {
		gather_pointer(&runner.gather, event)
	}

	ticks := clock_advance(&runner.clock, gtx.dt)
	first := runner.clock.tick - u64(ticks)
	for ii in 0 ..< ticks {
		runner.step(runner.world, take_input(&runner.gather, first + u64(ii)))
	}

	transform, covers := letterbox(runner.size, gtx.viewport)
	ops.fill(gtx.scene, ops.Rect{0, 0, gtx.viewport.x, gtx.viewport.y}, ops.Color{0, 0, 0, 255})
	ops.fill(gtx.scene, covers, runner.clear)
	ops.transform_push(gtx.scene, transform)
	ops.clip_push(gtx.scene, ops.Rect{0, 0, runner.size.x, runner.size.y})
	ops.input_area(gtx.scene, POINTER_AREA, ops.Rect{0, 0, runner.size.x, runner.size.y}, {.Press, .Release, .Move})
	canvas := Canvas {
		gtx   = gtx,
		scene = gtx.scene,
		size  = runner.size,
		alpha = clock_alpha(&runner.clock),
		tick  = runner.clock.tick,
	}
	runner.draw(runner.world, &canvas)
	ops.clip_pop(gtx.scene)
	ops.transform_pop(gtx.scene)
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
	runner: Runner
	runner_init(&runner, game, world)
	open_window(&runner, game.title, game.scale, game.keep_escape)
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

// open_window plays runner in a window of runner.size times scale (0 is 2) until
// it closes.
@(private)
open_window :: proc(runner: ^Runner, title: string, scale: f32, keep_escape: bool) {
	scale := scale if scale > 0 else 2
	shell.run(
		{
			title = title,
			width = int(runner.size.x * scale),
			height = int(runner.size.y * scale),
			ui = runner_frame,
			user = runner,
			fonts = {{0, ui.default_font(), 0}},
			clear = {0, 0, 0, 255},
			keep_escape = keep_escape,
		},
	)
}
