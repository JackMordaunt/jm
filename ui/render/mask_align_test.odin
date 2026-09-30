package render

import "core:mem"
import "core:testing"
import "jm:ui"
import "jm:ui/ops"
import bl "jm:ui/blend2d"

// Blend2D's A8 mask fill paints outside the clip when a mask buffer does
// not start on a 16-byte boundary. malloc gives one, aligning for C's
// max_align_t (16 bytes on 64-bit targets); an arena need not, so a Renderer on an allocator that packs byte buffers at odd
// addresses must draw exactly what one on the heap draws.
@(test)
test_mask_buffer_alignment :: proc(t: ^testing.T) {
	backing: mem.Dynamic_Arena
	mem.dynamic_arena_init(&backing)
	defer mem.dynamic_arena_destroy(&backing)
	arena := mem.dynamic_arena_allocator(&backing)

	sc: ops.Scene
	ops.init(&sc)
	defer ops.destroy(&sc)
	f: ui.Frame
	ui.frame_init(&f)
	defer ui.frame_destroy(&f)
	f.scene = &sc
	turn := ops.Affine{0.92, 0.39, -0.39, 0.92, 10, 18}
	append(&f.clips, ui.Clip{ui.NO_CLIP, ops.Ellipse{{0, 0, 181, 79}}, turn})
	append(&f.draws, ui.Draw{ops.IDENTITY, 0, ops.Fill{ops.Rect{0, 0, 200, 150}, RED}})

	want, got: bl.ImageCore
	for img in ([]^bl.ImageCore{&want, &got}) {
		bl.image_init(img)
		bl.image_create(img, 200, 150, .PRGB32)
	}
	defer bl.image_destroy(&want)
	defer bl.image_destroy(&got)

	heap: Renderer
	init(&heap)
	defer destroy(&heap)
	render(&heap, &f, &want, WHITE)
	testing.expect_value(t, pixel(&want, 90, 60), RED) // inside the ellipse
	testing.expect_value(t, pixel(&want, 2, 140), WHITE) // outside it

	odd: Renderer
	init(&odd, misaligning_allocator(&arena))
	defer destroy(&odd)
	render(&odd, &f, &got, WHITE)

	for y in 0 ..< 150 {
		for x in 0 ..< 200 {
			if pixel(&got, x, y) != pixel(&want, x, y) {
				testing.expectf(t, false, "pixel %v differs: %v, want %v", [2]int{x, y}, pixel(&got, x, y), pixel(&want, x, y))
				return
			}
		}
	}
}

// misaligning_allocator allocates from backing but places every allocation that
// asks for less than 16-byte alignment one byte past a 16-byte boundary,
// the worst placement its request allows. It never frees; backing does.
@(private = "file")
misaligning_allocator :: proc(backing: ^mem.Allocator) -> mem.Allocator {
	return {data = backing, procedure = proc(data: rawptr, mode: mem.Allocator_Mode, size, alignment: int, old: rawptr, old_size: int, loc := #caller_location) -> (res: []byte, err: mem.Allocator_Error) {
		b := (^mem.Allocator)(data)^
		#partial switch mode {
		case .Alloc, .Alloc_Non_Zeroed, .Resize, .Resize_Non_Zeroed:
			if size == 0 {
				return nil, nil
			}
			if alignment >= 16 {
				p := mem.alloc_bytes(size, alignment, b, loc) or_return
				copy(p, mem.byte_slice(old, min(old_size, size)))
				return p, nil
			}
			p := mem.alloc_bytes(size + 1, 16, b, loc) or_return
			copy(p[1:], mem.byte_slice(old, min(old_size, size)))
			return p[1:], nil
		case .Free, .Free_All:
			return nil, nil
		}
		return nil, .Mode_Not_Implemented
	}}
}
