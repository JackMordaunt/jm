package game

import "core:testing"

import "jm:ui"
import "jm:ui/ops"

// Ball is a World whose step draws its hitbox and velocity, and whose
// draw labels it.
@(private = "file")
Ball :: struct {
	at:  [2]f32,
	vel: [2]f32,
	rng: Rng,
}

@(private = "file")
ball_step :: proc(world: ^Ball, input: Input) {
	world.vel.x = 2 * axis(input, {.Left}, {.Right})
	world.vel.y = rng_float(&world.rng) - 0.5
	world.at += world.vel
	debug_rect({world.at.x, world.at.y, 8, 8})
	debug_arrow(world.at, world.at + world.vel * 4)
	debug_line({0, 40}, {100, 40}) // the floor
}

@(private = "file")
ball_draw :: proc(world: ^Ball, canvas: ^Canvas) {
	debug_text(world.at, "ball")
}

@(private = "file")
BALL :: Game(Ball) {
	size = {100, 50},
	step = ball_step,
	draw = ball_draw,
}

// count_overlay counts the frame's strokes and glyph runs: what the overlay
// draws, since the game itself draws none.
@(private = "file")
count_overlay :: proc(probe: ^ui.Probe) -> (lines, texts: int) {
	for op in probe.scene.ops {
		#partial switch _ in op {
		case ops.Stroke:
			lines += 1
		case ops.Glyphs:
			texts += 1
		}
	}
	return
}

@(test)
the_overlay_draws_what_step_and_draw_asked_only_while_on :: proc(t: ^testing.T) {
	world := Ball{at = {50, 20}, rng = rng_seed(1)}
	runner: Runner(Ball)
	runner_init(&runner, BALL, &world)
	defer runner_destroy(&runner)
	probe: ui.Probe
	ui.probe_init(&probe, runner_frame(Ball), &runner, {200, 100})
	defer ui.probe_destroy(&probe)

	lines, texts := count_overlay(&probe)
	testing.expect_value(t, lines + texts, 0) // off until asked

	ui.probe_key(&probe, OVERLAY_KEY)
	lines, texts = count_overlay(&probe)
	testing.expect_value(t, lines, 4) // the hitbox, the arrow's shaft and head, the floor
	testing.expect_value(t, texts, 1)
	ui.probe_frame(&probe)
	lines, texts = count_overlay(&probe)
	testing.expect_value(t, lines, 4) // last tick's, not every tick's
	testing.expect_value(t, texts, 1)

	ui.probe_key(&probe, OVERLAY_KEY)
	lines, texts = count_overlay(&probe)
	testing.expect_value(t, lines + texts, 0)
}

@(test)
debug_calls_outside_a_runner_do_nothing :: proc(t: ^testing.T) {
	world := Ball{at = {50, 20}, rng = rng_seed(1)}
	game := BALL
	game.overlay = true
	runner: Runner(Ball)
	runner_init(&runner, game, &world)
	defer runner_destroy(&runner)
	probe: ui.Probe
	ui.probe_init(&probe, runner_frame(Ball), &runner, {200, 100})
	defer ui.probe_destroy(&probe)

	// Between frames the Runner points the debug_ procs nowhere, so a
	// step called outside it (a unit test of step) adds to no list.
	testing.expect(t, overlay_target == nil)
	shapes := len(runner.core.overlay.tick.shapes) + len(runner.core.overlay.frame.shapes)
	testing.expect_value(t, shapes, 4) // the hitbox, arrow and floor from step, the label from draw
	ball_step(&world, {})
	testing.expect_value(t, len(runner.core.overlay.tick.shapes) + len(runner.core.overlay.frame.shapes), shapes)
}

@(test)
the_overlay_cannot_change_a_run :: proc(t: ^testing.T) {
	// The same 120 ticks with the overlay on and off end in the same World.
	play :: proc(on: bool) -> (world: Ball) {
		world = {at = {50, 20}, rng = rng_seed(9)}
		game := BALL
		game.overlay = on
		runner: Runner(Ball)
		runner_init(&runner, game, &world)
		defer runner_destroy(&runner)
		probe: ui.Probe
		ui.probe_init(&probe, runner_frame(Ball), &runner, {200, 100})
		defer ui.probe_destroy(&probe)
		ui.probe_key_down(&probe, .Right)
		ui.probe_advance(&probe, 60, 1.0 / 60)
		ui.probe_key_up(&probe, .Right)
		ui.probe_advance(&probe, 59, 1.0 / 60)
		return
	}
	with, without := play(true), play(false)
	testing.expect(t, transmute([size_of(Ball)]u8)with == transmute([size_of(Ball)]u8)without)
}

// Distant_World is a World far from the origin, looked at through a camera.
@(private = "file")
Distant_World :: struct {
	at: [2]f32,
}

@(test)
the_overlay_lies_over_the_world_through_the_camera :: proc(t: ^testing.T) {
	far_step :: proc(world: ^Distant_World, input: Input) {
		debug_rect({world.at.x - 5, world.at.y - 5, 10, 10})
	}
	far_draw :: proc(world: ^Distant_World, canvas: ^Canvas) {
		camera(canvas, world.at)
	}
	world := Distant_World{at = {1000, -400}}
	runner: Runner(Distant_World)
	runner_init(&runner, Game(Distant_World){size = {100, 50}, overlay = true, step = far_step, draw = far_draw}, &world)
	defer runner_destroy(&runner)
	probe: ui.Probe
	ui.probe_init(&probe, runner_frame(Distant_World), &runner, {200, 100})
	defer ui.probe_destroy(&probe)

	// The outline round the World's point lies round the window's middle.
	found := false
	for draw in ui.probe_current(&probe).draws {
		if stroke, ok := draw.cmd.(ops.Stroke); ok {
			bounds := ops.transform_rect(draw.transform, ops.shape_bounds(&probe.scene, stroke.shape))
			testing.expect(t, abs(bounds.x + bounds.w / 2 - 100) < 1 && abs(bounds.y + bounds.h / 2 - 50) < 1, "the outline is centred")
			found = true
		}
	}
	testing.expect(t, found)
}
