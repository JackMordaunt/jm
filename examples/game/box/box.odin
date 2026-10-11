// box is the smallest jm:game: a box the arrow keys move.
package main

import "jm:game"
import "jm:ui/ops"

World :: struct {
	box: [2]f32,
}

step :: proc(world: ^World, input: game.Input) {
	world.box.x += 2 * game.axis(input, {.Left, .A}, {.Right, .D})
	world.box.y += 2 * game.axis(input, {.Up, .W}, {.Down, .S})
	world.box = {clamp(world.box.x, 0, 304), clamp(world.box.y, 0, 164)}
}

draw :: proc(world: ^World, canvas: ^game.Canvas) {
	ops.fill(canvas.scene, ops.Rect{world.box.x, world.box.y, 16, 16}, ops.Color{255, 200, 0, 255})
}

main :: proc() {
	world := World{box = {152, 82}}
	game.run(game.Game(World){title = "Box", size = {320, 180}, clear = {30, 30, 46, 255}, step = step, draw = draw}, &world)
}
