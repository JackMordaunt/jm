package game

import "core:math/linalg"
import "core:strings"

import "jm:ui"
import "jm:ui/ops"

// The overlay is what a game's logic draws about itself: a hitbox where
// step tests it, a velocity where step sets it, a state's name over the
// body in it. step has no Canvas, so the debug_ procs reach the overlay
// of the Runner running the tick, through the thread: outside a Runner's
// frame (a headless tape_replay, a unit test of step), or with the
// overlay off, they do nothing. They never read or change the World, so
// whether the overlay is on cannot change a run.
//
//	game.debug_rect({world.at.x, world.at.y, 16, 16})
//	game.debug_arrow(world.at, world.at + world.vel * 8)
//	game.debug_text(world.at, "jumping")
//
// What step draws shows until the next tick, what draw draws for its
// frame; both above the game. OVERLAY_KEY turns it on and off live;
// Game.overlay starts it on.

// OVERLAY_KEY turns the overlay on and off in a running game.
OVERLAY_KEY :: ui.Key.F3

// DEBUG_COLOR is the overlay's colour when a call names none.
DEBUG_COLOR :: ops.Color{255, 0, 200, 255}

// debug_rect outlines rect, in the game's units.
debug_rect :: proc(rect: ops.Rect, color := DEBUG_COLOR) {
	if list := overlay_target; list != nil {
		append(&list.shapes, Overlay_Shape{kind = .Rect, from = {rect.x, rect.y}, to = {rect.x + rect.w, rect.y + rect.h}, color = color})
	}
}

// debug_line draws a line from from to to.
debug_line :: proc(from, to: [2]f32, color := DEBUG_COLOR) {
	if list := overlay_target; list != nil {
		append(&list.shapes, Overlay_Shape{kind = .Line, from = from, to = to, color = color})
	}
}

// debug_arrow draws an arrow from from to to: a velocity, a ray.
debug_arrow :: proc(from, to: [2]f32, color := DEBUG_COLOR) {
	if list := overlay_target; list != nil {
		append(&list.shapes, Overlay_Shape{kind = .Arrow, from = from, to = to, color = color})
	}
}

// debug_text writes text with its top left at at; the text is copied.
debug_text :: proc(at: [2]f32, text: string, color := DEBUG_COLOR) {
	if list := overlay_target; list != nil {
		start := len(list.text.buf)
		strings.write_string(&list.text, text)
		append(&list.shapes, Overlay_Shape{kind = .Text, from = at, color = color, text = {start, len(list.text.buf)}})
	}
}

@(private)
Overlay_Shape :: struct {
	kind:     enum u8 {
		Rect,
		Line,
		Arrow,
		Text,
	},
	from, to: [2]f32,
	color:    ops.Color,
	text:     [2]int, // Text: its bytes in the list's text
}

// Overlay_List is the shapes of one tick or one frame.
@(private)
Overlay_List :: struct {
	shapes: [dynamic]Overlay_Shape,
	text:   strings.Builder,
}

// Overlay is a Runner's overlay: whether it shows, the last tick's shapes
// and this frame's draw's.
@(private)
Overlay :: struct {
	on:    bool,
	tick:  Overlay_List,
	frame: Overlay_List,
}

// overlay_target is the list the debug_ procs add to on this thread; nil
// when none should.
@(private, thread_local)
overlay_target: ^Overlay_List

// overlay_aim points the debug_ procs at list, emptied, while overlay is
// on, and nowhere while it is off.
@(private)
overlay_aim :: proc(overlay: ^Overlay, list: ^Overlay_List) {
	if !overlay.on {
		overlay_target = nil
		return
	}
	clear(&list.shapes)
	strings.builder_reset(&list.text)
	overlay_target = list
}

@(private)
overlay_destroy :: proc(overlay: ^Overlay) {
	for list in ([]^Overlay_List{&overlay.tick, &overlay.frame}) {
		delete(list.shapes)
		strings.builder_destroy(&list.text)
	}
}

// overlay_paint draws overlay's shapes into canvas, whose units are the
// game's at scale device pixels each.
@(private)
overlay_paint :: proc(overlay: ^Overlay, canvas: ^Canvas, scale: f32) {
	if !overlay.on {
		return
	}
	pixel := 1 / max(scale, 1e-3)
	style := ops.Stroke_Style{width = pixel, cap = .Round, join = .Round}
	for list in ([]^Overlay_List{&overlay.tick, &overlay.frame}) {
		for shape in list.shapes {
			switch shape.kind {
			case .Rect:
				// Inset half a pixel, so the outline covers whole pixels
				// inside the rect rather than half of two.
				half := pixel / 2
				outline := ops.Rect{shape.from.x + half, shape.from.y + half, shape.to.x - shape.from.x - pixel, shape.to.y - shape.from.y - pixel}
				ops.stroke(canvas.scene, outline, shape.color, style)
			case .Line:
				ops.stroke(canvas.scene, ui.line(canvas.gtx, shape.from, shape.to), shape.color, style)
			case .Arrow:
				ops.stroke(canvas.scene, ui.line(canvas.gtx, shape.from, shape.to), shape.color, style)
				along := shape.to - shape.from
				if length := linalg.length(along); length > 0 {
					back := along / length * min(6 * pixel, length / 2)
					side := [2]f32{-back.y, back.x} / 2
					head := ui.polyline(canvas.gtx, {shape.to - back + side, shape.to, shape.to - back - side})
					ops.stroke(canvas.scene, head, shape.color, style)
				}
			case .Text:
				text := string(list.text.buf[shape.text[0]:shape.text[1]])
				ui.draw_text(canvas.gtx, ui.frame_string(canvas.gtx, text), shape.from, 11 * pixel, shape.color)
			}
		}
	}
}
