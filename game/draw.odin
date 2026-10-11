package game

import "jm:ui"
import "jm:ui/ops"

// Canvas is what a game's draw proc paints with: the scene, already scaled
// so the game's own units fill the window, and where the frame falls
// between ticks. A game draws with jm:ui/ops on scene, which is in its
// units; every shape lands there as data, so a dump or a probe reads what
// was drawn. This package adds a draw call only where ops has none.
//
//	ops.fill(canvas.scene, ops.Rect{world.box.x, world.box.y, 16, 16}, ops.Color{255, 200, 0, 255})
Canvas :: struct {
	gtx:   ^ui.Ctx,
	scene: ^ops.Scene,
	size:  [2]f32, // the game's size in its own units
	alpha: f32, // how far the frame is between the last tick and the next, 0 to 1: see clock_alpha
	tick:  u64, // the ticks run so far
}

// letterbox is the transform that fits a game of size into view, centred
// and as large as it goes without changing shape, and the rect of view it
// covers.
@(private)
letterbox :: proc(size, view: [2]f32) -> (transform: ops.Affine, covers: ops.Rect) {
	if size.x <= 0 || size.y <= 0 {
		return ops.IDENTITY, {0, 0, view.x, view.y}
	}
	scale := min(view.x / size.x, view.y / size.y)
	covers = {(view.x - size.x * scale) / 2, (view.y - size.y * scale) / 2, size.x * scale, size.y * scale}
	return ops.mul(ops.scale(scale, scale), ops.translate(covers.x, covers.y)), covers
}
