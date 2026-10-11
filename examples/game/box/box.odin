// box is the smallest jm:game: a box the arrow keys move. Run it from the
// repository's root (just game box), where its sheet's path starts.
package main

import "jm:game"
import "jm:ui/ops"

BOX :: game.Sheet{path = "examples/game/box/box.png", frame = {16, 16}, columns = 2}

World :: struct {
	box:    [2]f32,
	moving: bool,
	left:   bool, // facing left
}

step :: proc(world: ^World, input: game.Input) {
	move := [2]f32{game.axis(input, {.Left, .A}, {.Right, .D}), game.axis(input, {.Up, .W}, {.Down, .S})}
	world.box = {clamp(world.box.x + 2 * move.x, 0, 304), clamp(world.box.y + 2 * move.y, 0, 164)}
	world.moving = move != {}
	world.left = move.x < 0 || (world.left && move.x == 0)
}

draw :: proc(world: ^World, canvas: ^game.Canvas) {
	at := ops.Rect{world.box.x, world.box.y, 16, 16}
	game.sprite(canvas, BOX, int(world.moving && canvas.tick / 8 % 2 == 1), at, {.X} if world.left else {})
	ops.tag(canvas.scene, 0, "box", at)
}

main :: proc() {
	world := World{box = {152, 82}}
	game.run(game.Game(World){title = "Box", size = {320, 180}, clear = {30, 30, 46, 255}, step = step, draw = draw}, &world)
}
