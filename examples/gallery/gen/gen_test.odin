package gallery_gen

import "core:os"
import "core:path/filepath"
import "core:sync"
import "core:testing"

@(test)
the_same_index_gives_the_same_picture_and_indices_differ :: proc(t: ^testing.T) {
	a := make([]u32, 16 * 16)
	defer delete(a)
	b := make([]u32, 16 * 16)
	defer delete(b)
	c := make([]u32, 16 * 16)
	defer delete(c)
	testing.expect(t, render(7, 16, a, nil))
	testing.expect(t, render(7, 16, b, nil))
	testing.expect(t, render(8, 16, c, nil))
	same, differ := true, false
	for ii in 0 ..< len(a) {
		same &&= a[ii] == b[ii]
		differ ||= a[ii] != c[ii]
	}
	testing.expect(t, same, "deterministic")
	testing.expect(t, differ, "varies by index")
}

@(test)
a_set_cancel_flag_stops_the_work :: proc(t: ^testing.T) {
	px := make([]u32, 32 * 32)
	defer delete(px)
	for &p in px {
		p = 0xDEADBEEF
	}
	cancel := true
	testing.expect(t, !render(1, 32, px, &cancel))
	testing.expect(t, px[len(px) - 1] == 0xDEADBEEF, "the last row was never reached")
	sync.atomic_store(&cancel, false)
	testing.expect(t, render(1, 32, px, &cancel))
}

@(test)
the_bmp_has_its_header_and_the_right_size :: proc(t: ^testing.T) {
	// A folder of its own: one file shared by name was written by every run
	// on the machine at once.
	dir, err := os.make_directory_temp("", "jm-gallery-gen-*", context.temp_allocator)
	testing.expect(t, err == nil)
	defer os.remove_all(dir)
	path, _ := filepath.join({dir, "gallery-gen-test.bmp"}, context.temp_allocator)
	cancel := false
	testing.expect(t, tile(3, 8, path, &cancel))
	data, rerr := os.read_entire_file(path, context.temp_allocator)
	testing.expect(t, rerr == nil)
	testing.expect_value(t, len(data), 54 + 8 * 8 * 4)
	testing.expect(t, data[0] == 'B' && data[1] == 'M')
	testing.expect_value(t, data[28], u8(32))
}

@(test)
a_patch_refines_the_square_it_covers :: proc(t: ^testing.T) {
	// Level 0 at 2px and level 1's four 1px patches sample the same points.
	whole := make([]u32, 4)
	defer delete(whole)
	testing.expect(t, render(11, 2, whole, nil))
	for y in 0 ..< 2 {
		for x in 0 ..< 2 {
			one := make([]u32, 1)
			defer delete(one)
			testing.expect(t, region(11, 1, -1.5 + f64(x) * 1.5, -1.5 + f64(y) * 1.5, 1.5, one, nil))
			testing.expect_value(t, one[0], whole[y * 2 + x])
		}
	}
}
