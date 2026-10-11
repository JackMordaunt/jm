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
//
// An entity is named for the tools with a tag of id 0 and its bounds:
// ui.probe_bounds and the dump then find "player" where it was drawn. A
// tag whose id is an input area's would be found as that area instead
// (ui/probe.odin probe_find looks for a hit of the tag's id first).
//
//	ops.tag(canvas.scene, 0, "player", ops.Rect{world.player.x, world.player.y, 16, 16})
Canvas :: struct {
	gtx:   ^ui.Ctx,
	scene: ^ops.Scene,
	size:  [2]f32, // the game's size in its own units
	scale: f32, // device pixels a game unit is drawn at
	alpha: f32, // how far the frame is between the last tick and the next, 0 to 1: see clock_alpha
	tick:  u64, // the ticks run so far
	world: ops.Affine, // the last camera's transform from the World's units to the game's: what the overlay draws through
}

// camera_open looks at the World from at: until camera_close, what is
// drawn at at lands in the middle of the game, zoom times its size. The
// overlay draws through the last camera opened, so what step outlined
// in the World's units lies over what draw drew there; a HUD drawn after
// camera_close stays put. A game without a camera draws in the game's
// units, which are then the World's.
//
//	game.camera_open(canvas, world.player.at)
//	// the field, the enemies, the player
//	game.camera_close(canvas)
//	// the HUD
camera_open :: proc(canvas: ^Canvas, at: [2]f32, zoom: f32 = 1) {
	middle := canvas.size / 2
	canvas.world = ops.mul(ops.mul(ops.translate(-at.x, -at.y), ops.scale(zoom, zoom)), ops.translate(middle.x, middle.y))
	ops.transform_push(canvas.scene, canvas.world)
}

// camera_close ends what camera_open began.
camera_close :: proc(canvas: ^Canvas) {
	ops.transform_pop(canvas.scene)
}

// camera is camera_open as a guard: the camera closes at the end of the
// if, or of the block the call is in, as ui's guards do (ui/guards.odin).
//
//	if game.camera(canvas, world.player.at) { ... }
@(deferred_in = camera_guard_close)
camera :: proc(canvas: ^Canvas, at: [2]f32, zoom: f32 = 1) -> bool {
	camera_open(canvas, at, zoom)
	return true
}

@(private)
camera_guard_close :: proc(canvas: ^Canvas, at: [2]f32, zoom: f32 = 1) {
	camera_close(canvas)
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

// Sheet is a sprite sheet: one image cut into a grid of equal frames,
// numbered from 0 along each row, then down. Pixel art is its default: a
// frame scales by nearest neighbour, each pixel a hard-edged block.
//
//	HERO :: game.Sheet{path = "art/hero.png", frame = {16, 16}, columns = 4}
Sheet :: struct {
	path:    string,
	frame:   [2]f32, // a frame's size, in the image's pixels
	columns: int, // frames across the image
	smooth:  bool, // scale smoothly instead, as a painted image wants
}

// Flip mirrors a sprite: X left for right, Y top for bottom.
Flip :: enum u8 {
	X,
	Y,
}

Flips :: bit_set[Flip;u8]

// sprite draws frame of sheet into dst, mirrored by flip within dst.
sprite :: proc(canvas: ^Canvas, sheet: Sheet, frame: int, dst: ops.Rect, flip: Flips = {}) {
	id := ops.add_image(canvas.scene, sheet.path)
	columns := max(sheet.columns, 1)
	src := ops.Rect{f32(frame % columns) * sheet.frame.x, f32(frame / columns) * sheet.frame.y, sheet.frame.x, sheet.frame.y}
	if flip == {} {
		ops.image(canvas.scene, id, dst, src, pixelated = !sheet.smooth)
		return
	}
	ops.transform_push(canvas.scene, mirror(dst, flip))
	ops.image(canvas.scene, id, dst, src, pixelated = !sheet.smooth)
	ops.transform_pop(canvas.scene)
}

// mirror is the transform that flips the plane across the centre lines of
// bounds that flip names, leaving bounds where they were.
@(private)
mirror :: proc(bounds: ops.Rect, flip: Flips) -> ops.Affine {
	transform := ops.IDENTITY
	if .X in flip {
		transform.a, transform.e = -1, f64(2 * bounds.x + bounds.w)
	}
	if .Y in flip {
		transform.d, transform.f = -1, f64(2 * bounds.y + bounds.h)
	}
	return transform
}
