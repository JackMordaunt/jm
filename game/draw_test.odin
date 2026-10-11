package game

import "core:strings"
import "core:testing"

import "jm:ui"
import "jm:ui/ops"

@(private = "file")
HERO :: Sheet {
	path    = "hero.png",
	frame   = {16, 16},
	columns = 4,
}

// Hero is a World of one sprite the tests place and turn.
@(private = "file")
Hero :: struct {
	at:    [2]f32,
	frame: int,
	flip:  Flips,
}

@(private = "file")
hero_step :: proc(world: ^Hero, input: Input) {}

@(private = "file")
hero_draw :: proc(world: ^Hero, canvas: ^Canvas) {
	bounds := ops.Rect{world.at.x, world.at.y, 16, 16}
	sprite(canvas, HERO, world.frame, bounds, world.flip)
	ops.tag(canvas.scene, 0, "hero", bounds)
}

@(private = "file")
HERO_GAME :: Game(Hero) {
	size = {100, 50},
	step = hero_step,
	draw = hero_draw,
}

// image_op is the scene's one Image op.
@(private = "file")
image_op :: proc(probe: ^ui.Probe) -> (found: ops.Image) {
	for op in probe.scene.ops {
		if image, ok := op.(ops.Image); ok {
			found = image
		}
	}
	return
}

@(test)
a_frame_is_cut_from_the_sheets_grid_and_drawn_pixelated :: proc(t: ^testing.T) {
	world := Hero{at = {10, 20}, frame = 6}
	runner: Runner(Hero)
	runner_init(&runner, HERO_GAME, &world)
	probe: ui.Probe
	ui.probe_init(&probe, runner_frame(Hero), &runner, {200, 100})
	defer ui.probe_destroy(&probe)

	image := image_op(&probe)
	testing.expect_value(t, image.src, ops.Rect{32, 16, 16, 16}) // the third of the second row
	testing.expect_value(t, image.dst, ops.Rect{10, 20, 16, 16})
	testing.expect(t, image.pixelated)
	testing.expect_value(t, len(probe.scene.images), 1)
	ui.probe_frame(&probe)
	testing.expect_value(t, len(probe.scene.images), 1) // registered once, not once a frame
}

@(test)
a_flipped_sprite_stays_where_it_was :: proc(t: ^testing.T) {
	transform := mirror({10, 20, 16, 8}, {.X, .Y})
	testing.expect_value(t, ops.transform_rect(transform, {10, 20, 16, 8}), ops.Rect{10, 20, 16, 8})
	testing.expect_value(t, ops.apply(transform, {10, 20}), ops.Point{26, 28}) // the corners swap
}

@(test)
an_entity_tagged_is_found_by_name_where_it_was_drawn :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	world := Hero{at = {10, 20}}
	runner: Runner(Hero)
	runner_init(&runner, HERO_GAME, &world)
	probe: ui.Probe
	// Twice the game's size: the tool sees the hero in the window's pixels.
	ui.probe_init(&probe, runner_frame(Hero), &runner, {200, 100})
	defer ui.probe_destroy(&probe)

	testing.expect_value(t, ui.probe_bounds(&probe, "hero"), ops.Rect{20, 40, 32, 32})
	dump := ui.probe_dump(&probe)
	defer delete(dump)
	testing.expect(t, strings.contains(dump, `tag 0 "hero"`), dump)
}
