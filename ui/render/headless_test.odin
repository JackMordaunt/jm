package render

import "core:os"
import "jm:ui/ops"
import "core:strings"
import "core:testing"

import bl "jm:ui/blend2d"
import "jm:ui"

// headless_view fills the top 50px of the window and counts its frames.
@(private = "file")
headless_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	(^int)(user)^ += 1
	ops.fill(gtx.scene, ops.Rect{0, 0, gtx.constraints.max.x, 50}, ops.Color{200, 0, 0, 255})
}

@(test)
test_headless_full_trims_and_steps_share_one_session :: proc(t: ^testing.T) {
	os.make_directory("build/test")
	path := "build/test/headless_full.png"
	defer os.remove(path)
	frames := 0
	h: Headless
	headless_init(&h, headless_view, &frames, {120, 300}, nil, full = true)
	defer headless_destroy(&h)
	args := []string{"-advance", "3", "-png", path, "-page", "x"}
	i := 0
	for i < 4 {
		handled, ok := headless_step(&h, args, &i)
		testing.expect(t, handled && ok)
		i += 1
	}
	testing.expect_value(t, frames, 2 + 3) // init's two frames, then three more
	handled, _ := headless_step(&h, args, &i)
	testing.expect(t, !handled) // -page is the caller's own flag

	// Laid out FULL_HEIGHT tall, written 50 rows of content plus the margin.
	img: bl.ImageCore
	bl.image_init(&img)
	defer bl.image_destroy(&img)
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	testing.expect_value(t, bl.image_read_from_file(&img, cpath, nil), bl.Result(0))
	data: bl.ImageData
	bl.image_get_data(&img, &data)
	testing.expect_value(t, data.size.h, i32(50 + 24))
}
