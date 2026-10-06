package files_fs

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:testing"
import "core:time"

import bl "jm:ui/blend2d"

import "../../common"

@(test)
list_puts_folders_first_then_names_and_marks_pictures :: proc(t: ^testing.T) {
	dir := fresh("list")
	defer os.remove_all(dir)
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
	dir := fresh("thumb")
	defer os.remove_all(dir)
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

// fresh is an empty folder of its own for one test, under the temp folder.
// One shared by name was rewritten by every run on the machine at once, so
// a listing could see a file another run had just truncated.
@(private = "file")
fresh :: proc(name: string) -> string {
	tmp, _ := os.temp_directory(context.temp_allocator)
	dir, _ := filepath.join({tmp, fmt.tprintf("jm-files-%s-%d", name, time.now()._nsec)}, context.temp_allocator)
	_ = os.make_directory_all(dir)
	return dir
}

@(private = "file")
put :: proc(dir, name, body: string) -> string {
	p, _ := filepath.join({dir, name}, context.temp_allocator)
	_ = os.write_entire_file(p, transmute([]u8)body)
	return p
}

@(private = "file")
body_of :: proc(path: string) -> string {
	data, err := os.read_entire_file(path, context.temp_allocator)
	return string(data) if err == nil else "<unreadable>"
}

@(test)
rename_noreplace_never_replaces :: proc(t: ^testing.T) {
	dir := fresh("rename")
	defer os.remove_all(dir)
	a := put(dir, "a", "A")
	b := put(dir, "b", "B")
	testing.expect_value(t, rename_noreplace(a, b), Error.Exists)
	testing.expect_value(t, body_of(b), "B")
	testing.expect_value(t, body_of(a), "A")
	c, _ := filepath.join({dir, "c"}, context.temp_allocator)
	testing.expect_value(t, rename_noreplace(a, c), Error.None)
	testing.expect_value(t, body_of(c), "A")
	testing.expect(t, !os.exists(a))
	testing.expect_value(t, rename_noreplace(a, c), Error.Missing)
	testing.expect_value(t, make_folder(c), Error.Exists)
}

@(test)
facts_of_entries_and_folders :: proc(t: ^testing.T) {
	dir := fresh("facts")
	defer os.remove_all(dir)
	f := put(dir, "file", "x")
	_ = put(dir, ".hidden", "x")
	sub, _ := filepath.join({dir, "sub"}, context.temp_allocator)
	testing.expect_value(t, make_folder(sub), Error.None)
	fi, di := info(f), info(sub)
	testing.expect(t, fi.exists && !fi.is_dir)
	testing.expect(t, di.exists && di.is_dir)
	testing.expect(t, fi.volume != 0 && fi.volume == di.volume)
	testing.expect(t, !info(filepath.join({dir, "none"}, context.temp_allocator) or_else "").exists)
	testing.expect_value(t, len(names(dir, context.temp_allocator)), 3) // hidden ones count
	testing.expect(t, is_empty(sub))
	testing.expect(t, !is_empty(dir))
	testing.expect(t, modified(dir) != 0)
}

@(test)
copy_tree_copies_everything_and_replaces_nothing :: proc(t: ^testing.T) {
	dir := fresh("copy")
	defer os.remove_all(dir)
	src, _ := filepath.join({dir, "src"}, context.temp_allocator)
	nested, _ := filepath.join({src, "nested"}, context.temp_allocator)
	_ = os.make_directory_all(nested)
	_ = put(src, "one", "first")
	_ = put(nested, "two", "second!")
	Seen :: struct {
		done, total: i64,
		calls:       int,
	}
	seen: Seen
	dst, _ := filepath.join({dir, "dst"}, context.temp_allocator)
	err := copy_tree(src, dst, nil, proc(user: rawptr, done, total: i64) {
			s := (^Seen)(user)
			s.done, s.total = done, total
			s.calls += 1
		}, &seen)
	testing.expect_value(t, err, Error.None)
	testing.expect_value(t, body_of(filepath.join({dst, "one"}, context.temp_allocator) or_else ""), "first")
	testing.expect_value(t, body_of(filepath.join({dst, "nested", "two"}, context.temp_allocator) or_else ""), "second!")
	testing.expect_value(t, seen.total, i64(12))
	testing.expect_value(t, seen.done, seen.total)
	testing.expect(t, seen.calls >= 3) // the count, then a chunk per file

	// A file in the way is never written over.
	blocked, _ := filepath.join({dir, "blocked"}, context.temp_allocator)
	_ = os.make_directory(blocked)
	_ = put(blocked, "one", "keep me")
	one, _ := filepath.join({src, "one"}, context.temp_allocator)
	in_way, _ := filepath.join({blocked, "one"}, context.temp_allocator)
	testing.expect_value(t, copy_tree(one, in_way), Error.Exists)
	testing.expect_value(t, body_of(in_way), "keep me")

	cancel := true
	stopped, _ := filepath.join({dir, "stopped"}, context.temp_allocator)
	testing.expect_value(t, copy_tree(src, stopped, &cancel), Error.Cancelled)
}

// The real Trash: what this puts there it takes back out again.
@(test)
trash_and_restore_round_trip :: proc(t: ^testing.T) {
	dir := fresh("trash")
	defer os.remove_all(dir)
	f := put(dir, "jm-files-trash-test.txt", "bye")
	trashed, err := trash(f, context.temp_allocator)
	testing.expect_value(t, err, Error.None)
	testing.expect(t, !os.exists(f))
	when ODIN_OS == .Windows {
		testing.expect_value(t, trashed, "")
	} else {
		testing.expect(t, trashed != "" && os.exists(trashed), "the Trash says where it went")
		testing.expect_value(t, restore(trashed, f), Error.None)
		testing.expect_value(t, body_of(f), "bye")
		testing.expect(t, !os.exists(trashed))
	}
	_, gone := trash(filepath.join({dir, "never"}, context.temp_allocator) or_else "", context.temp_allocator)
	testing.expect(t, gone != .None)
}
