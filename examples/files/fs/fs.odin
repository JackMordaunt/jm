/*
Package fs is the file browser's work: reading a folder, making a
thumbnail, and opening a file with the system. It knows nothing of the
ui or the pipeline, so it is tested on temporary folders.
*/
package files_fs

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:sync"
import "core:time"

import bl "jm:ui/blend2d"

import "../../common"
import "../shapes"

// list reads the folder at path: folders first, each group by name
// ignoring case. Strings are in allocator. A folder that cannot be read
// gives an error message instead.
list :: proc(path: string, allocator := context.allocator) -> (entries: []shapes.Entry, error: string) {
	infos, err := os.read_all_directory_by_path(path, allocator)
	if err != nil {
		return nil, fmt.aprintf("cannot read %s: %v", path, err, allocator = allocator)
	}
	out := make([dynamic]shapes.Entry, 0, len(infos), allocator)
	for fi in infos {
		if strings.has_prefix(fi.name, ".") {
			continue
		}
		dir := fi.type == .Directory
		append(&out, shapes.Entry{
			name = fi.name,
			path = fi.fullpath,
			dir = dir,
			image = !dir && is_image(fi.name),
			size = fi.size,
			modified = time.time_to_unix(fi.modification_time),
		})
	}
	slice.sort_by(out[:], proc(a, b: shapes.Entry) -> bool {
		if a.dir != b.dir {
			return a.dir
		}
		return strings.compare(strings.to_lower(a.name, context.temp_allocator), strings.to_lower(b.name, context.temp_allocator)) < 0
	})
	return out[:], ""
}

// is_image says whether a file is a picture the thumbnailer can read, by
// its extension.
is_image :: proc(name: string) -> bool {
	ext := strings.to_lower(filepath.ext(name), context.temp_allocator)
	switch ext {
	case ".png", ".jpg", ".jpeg", ".bmp", ".qoi":
		return true
	}
	return false
}

// thumbnail reads the picture at src, scales it to fit px by px keeping
// its shape, on white, and writes the result to dst as a BMP. False when
// cancel^ was set, the picture could not be read, or dst could not be
// written. Blend2D does the decoding, so a worker may call it beside
// others.
thumbnail :: proc(src, dst: string, px: int, cancel: ^bool = nil) -> bool {
	if cancel != nil && sync.atomic_load(cancel) {
		return false
	}
	img: bl.ImageCore
	bl.image_init(&img)
	defer bl.image_destroy(&img)
	if bl.image_read_from_file(&img, strings.clone_to_cstring(src, context.temp_allocator), nil) != 0 {
		return false
	}
	bl.image_convert(&img, .PRGB32)
	data: bl.ImageData
	if bl.image_get_data(&img, &data) != 0 || data.size.w == 0 || data.size.h == 0 {
		return false
	}
	if cancel != nil && sync.atomic_load(cancel) {
		return false
	}
	// Fit inside the square, centred.
	w, h := f64(data.size.w), f64(data.size.h)
	scale := min(f64(px) / w, f64(px) / h)
	fit := bl.Rect{(f64(px) - w * scale) / 2, (f64(px) - h * scale) / 2, w * scale, h * scale}
	out: bl.ImageCore
	bl.image_init(&out)
	defer bl.image_destroy(&out)
	if bl.image_create(&out, i32(px), i32(px), .PRGB32) != 0 {
		return false
	}
	ctx: bl.ContextCore
	bl.context_init(&ctx)
	defer bl.context_destroy(&ctx)
	if bl.context_begin(&ctx, &out, nil) != 0 {
		return false
	}
	bl.context_fill_all_rgba32(&ctx, 0xFFFFFFFF)
	bl.context_blit_scaled_image_d(&ctx, &fit, &img, nil)
	bl.context_end(&ctx)
	odata: bl.ImageData
	if bl.image_get_data(&out, &odata) != 0 {
		return false
	}
	if cancel != nil && sync.atomic_load(cancel) {
		return false
	}
	pixels := make([]u32, px * px, context.temp_allocator)
	for row in 0 ..< px {
		line := ([^]u32)(rawptr(uintptr(odata.pixel_data) + uintptr(row) * uintptr(odata.stride)))
		copy(pixels[row * px:][:px], line[:px])
	}
	return common.write_bmp(dst, px, px, pixels)
}

// open_default asks the system to open path with the application it has
// for it, and waits for the opener to hand off, which on every system is
// quick: it runs on a worker, never the frame's thread.
open_default :: proc(path: string) -> bool {
	command: []string
	when ODIN_OS == .Windows {
		command = {"cmd", "/c", "start", "", path}
	} else when ODIN_OS == .Darwin {
		command = {"open", path}
	} else {
		command = {"xdg-open", path}
	}
	process, err := os.process_start({command = command})
	if err != nil {
		fmt.eprintln("files: open:", path, err)
		return false
	}
	state, _ := os.process_wait(process)
	return state.exit_code == 0
}
