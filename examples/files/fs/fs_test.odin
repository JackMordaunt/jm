package files_fs

import "core:os"
import "core:path/filepath"
import "core:testing"

import bl "jm:ui/blend2d"

import "../../common"

@(private = "file")
scratch :: proc(name: string) -> string {
	tmp, _ := os.temp_directory(context.temp_allocator)
	dir, _ := filepath.join({tmp, name}, context.temp_allocator)
	_ = os.make_directory(dir)
	return dir
}

@(test)
list_puts_folders_first_then_names_and_marks_pictures :: proc(t: ^testing.T) {
	dir := scratch("jm-files-list")
	sub, _ := filepath.join({dir, "zeta"}, context.temp_allocator)
	_ = os.make_directory(sub)
	for n in ([]string{"Beta.txt", "alpha.png", ".hidden"}) {
		p, _ := filepath.join({dir, n}, context.temp_allocator)
		_ = os.write_entire_file(p, []byte{1})
	}
	entries, err := list(dir, context.temp_allocator)
	testing.expect_value(t, err, "")
	testing.expect_value(t, len(entries), 3)
	testing.expect_value(t, entries[0].name, "zeta")
	testing.expect(t, entries[0].dir)
	testing.expect_value(t, entries[1].name, "alpha.png")
	testing.expect(t, entries[1].image)
	testing.expect_value(t, entries[2].name, "Beta.txt")
	testing.expect(t, !entries[2].image)
	testing.expect_value(t, entries[2].size, i64(1))
	_, bad := list("/nowhere/at/all", context.temp_allocator)
	testing.expect(t, bad != "")
}

@(test)
thumbnail_fits_a_picture_in_the_square :: proc(t: ^testing.T) {
	dir := scratch("jm-files-thumb")
	src, _ := filepath.join({dir, "wide.bmp"}, context.temp_allocator)
	dst, _ := filepath.join({dir, "wide-thumb.bmp"}, context.temp_allocator)
	// A 4x2 red picture: the thumbnail is 4x4, red across the middle rows
	// and white above and below.
	pixels := make([]u32, 8, context.temp_allocator)
	for &p in pixels {
		p = 0xFFFF0000
	}
	testing.expect(t, common.write_bmp(src, 4, 2, pixels))
	testing.expect(t, thumbnail(src, dst, 4))
	img: bl.ImageCore
	bl.image_init(&img)
	defer bl.image_destroy(&img)
	testing.expect(t, bl.image_read_from_file(&img, "", nil) != 0)
	cpath := make([]byte, len(dst) + 1, context.temp_allocator)
	copy(cpath, dst)
	testing.expect(t, bl.image_read_from_file(&img, cstring(raw_data(cpath)), nil) == 0)
	bl.image_convert(&img, .PRGB32)
	data: bl.ImageData
	bl.image_get_data(&img, &data)
	testing.expect_value(t, data.size.w, i32(4))
	px := ([^]u32)(data.pixel_data)
	stride := int(data.stride) / 4
	testing.expect_value(t, px[0] & 0xFFFFFF, u32(0xFFFFFF)) // top row white
	testing.expect_value(t, px[1 * stride] & 0xFFFFFF, u32(0xFF0000)) // middle red
	cancel := true
	testing.expect(t, !thumbnail(src, dst, 4, &cancel))
}
