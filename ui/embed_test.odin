package ui

import "core:strings"
import "core:testing"
import "jm:ui/ops"

// embedded_view draws a square, a triangle inside a clip and faded, and
// an area to press: what embed_frame copies, and what it leaves out.
@(private = "file")
embedded_view :: proc(gtx: ^Ctx, user: rawptr) {
	ops.fill(gtx.scene, ops.Rect{0, 0, 40, 40}, ops.Color{200, 0, 0, 255})
	ops.transform_push(gtx.scene, ops.translate(10, 5))
	ops.clip_push(gtx.scene, ops.Rect{0, 0, 30, 30})
	ops.opacity_push(gtx.scene, 0.5)
	verbs := make([]ops.Path_Verb, 4, gtx.allocator)
	verbs[0], verbs[1], verbs[2], verbs[3] = .Move, .Line, .Line, .Close
	points := make([]ops.Point, 3, gtx.allocator)
	points[0], points[1], points[2] = {0, 0}, {20, 0}, {0, 20}
	ops.fill(gtx.scene, ops.Path_Ref{ops.add_path(gtx.scene, {verbs = verbs, points = points})}, ops.Color{0, 0, 200, 255})
	ops.opacity_pop(gtx.scene)
	ops.clip_pop(gtx.scene)
	ops.transform_pop(gtx.scene)
	ops.input_area(gtx.scene, 7, ops.Rect{0, 0, 40, 40}, {.Press})
	ops.semantic(gtx.scene, 7, 0, {role = .Button, label = "Go"}, ops.Rect{0, 0, 40, 40})
	ops.key_interest(gtx.scene, 7, .Escape)
}

// Host_Model is the frame host_view embeds.
@(private = "file")
Host_Model :: struct {
	frame: ^Frame,
}

@(private = "file")
host_view :: proc(gtx: ^Ctx, user: rawptr) {
	embed_frame(gtx, (^Host_Model)(user).frame)
}

// draws_dump is frame's draws and clips as dump_frame prints them: each
// draw's transform, clip, shape, paint and fade, in order.
@(private = "file")
draws_dump :: proc(frame: ^Frame) -> string {
	sb := strings.builder_make(context.temp_allocator)
	write_frame_draws(&sb, frame)
	write_frame_clips(&sb, frame)
	return strings.to_string(sb)
}

@(test)
an_embedded_frame_draws_the_same_and_takes_no_input :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	source: Probe
	probe_init(&source, embedded_view, nil, {100, 100})
	defer probe_destroy(&source)
	shown := probe_current(&source)
	testing.expect_value(t, len(shown.draws), 2)

	model := Host_Model{shown}
	host: Probe
	probe_init(&host, host_view, &model, {100, 100})
	defer probe_destroy(&host)
	embedded := probe_current(&host)
	testing.expect_value(t, draws_dump(embedded), draws_dump(shown))
	testing.expect_value(t, len(embedded.hits), 0)
	testing.expect_value(t, len(embedded.nodes), 0)
	testing.expect_value(t, len(embedded.keys), 0)
}
