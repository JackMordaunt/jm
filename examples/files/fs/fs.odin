/*
Package fs is the file browser's client of the filesystem: reading a
folder and the facts about an entry, making a thumbnail, opening a file
with the system, and the changes the application makes: renaming
without replacing, making a folder, copying a tree, and moving to and
restoring from the Trash. It decides nothing and knows nothing of the
ui or the pipeline, so it is tested on temporary folders. What differs
by system is in platform_*.odin.
*/
package files_fs

import "core:fmt"
import "core:io"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:sync"
import "core:time"

import bl "jm:ui/blend2d"

import "../../common"
import "../query"

// list reads the folder at path: folders first, each group by name
// ignoring case. Strings are in allocator. A folder that cannot be read
// gives an error message instead.
list :: proc(path: string, allocator := context.allocator) -> (entries: []query.Entry, error: string) {
	infos, err := os.read_all_directory_by_path(path, allocator)
	if err != nil {
		return nil, fmt.aprintf("cannot read %s: %v", path, err, allocator = allocator)
	}
	out := make([dynamic]query.Entry, 0, len(infos), allocator)
	for fi in infos {
		if strings.has_prefix(fi.name, ".") {
			continue
		}
		dir := fi.type == .Directory
		// The path under the folder as it was asked for, not fullpath,
		// which the system may have resolved through a link (/var is
		// /private/var on macOS): every path the application compares,
		// pins and places among them, must be spelled one way.
		child, _ := filepath.join({path, fi.name}, allocator)
		append(&out, query.Entry{
			name = fi.name,
			path = child,
			dir = dir,
			image = !dir && is_image(fi.name),
			size = fi.size,
			modified = time.time_to_unix(fi.modification_time),
		})
	}
	slice.sort_by(out[:], proc(a, b: query.Entry) -> bool {
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

// --- facts ----------------------------------------------------------------

// Info is what the application asks of an entry before deciding on it.
Info :: struct {
	exists: bool,
	is_dir: bool,
	volume: u64, // which filesystem it is on; equal for two entries on one
}

// info is path's facts. A path that cannot be read counts as missing.
info :: proc(path: string) -> (i: Info) {
	fi, err := os.lstat(path, context.temp_allocator)
	if err != nil {
		return
	}
	return {exists = true, is_dir = fi.type == .Directory, volume = volume_of(path)}
}

// names is every name in folder, hidden ones too, in allocator: what a
// new name must not collide with.
names :: proc(folder: string, allocator := context.allocator) -> []string {
	infos, err := os.read_all_directory_by_path(folder, allocator)
	if err != nil {
		return nil
	}
	out := make([]string, len(infos), allocator)
	for fi, ii in infos {
		out[ii] = fi.name
	}
	return out
}

// is_empty says whether path is a folder with nothing in it.
is_empty :: proc(path: string) -> bool {
	infos, err := os.read_all_directory_by_path(path, context.temp_allocator)
	return err == nil && len(infos) == 0
}

// modified is when the entry at path last changed, in nanoseconds since
// the epoch, or 0 when it cannot be read. A folder's changes when an
// entry in it is added, removed or renamed.
modified :: proc(path: string) -> i64 {
	fi, err := os.stat(path, context.temp_allocator)
	if err != nil {
		return 0
	}
	return time.to_unix_nanoseconds(fi.modification_time)
}

// --- changes ----------------------------------------------------------------

// Error is why a change failed, in the few kinds the application tells
// apart.
Error :: enum u8 {
	None,
	Exists, // the name is taken
	Missing, // the entry is gone
	Denied,
	Cross_Device, // a rename between filesystems
	Cancelled,
	Unsupported, // this system cannot do it
	Other,
}

// describe is an error as the end of a sentence for the ui.
describe :: proc(e: Error) -> string {
	switch e {
	case .None:
		return "it worked."
	case .Exists:
		return "something by that name is there now."
	case .Missing:
		return "it is no longer there."
	case .Denied:
		return "permission was denied."
	case .Cross_Device:
		return "it is on another drive."
	case .Cancelled:
		return "it was cancelled."
	case .Unsupported:
		return "this system can't do that."
	case .Other:
	}
	return "the system refused."
}

// error_of is an os error as an Error.
error_of :: proc(err: os.Error) -> Error {
	if err == nil {
		return .None
	}
	#partial switch e in err {
	case os.General_Error:
		#partial switch e {
		case .Exist:
			return .Exists
		case .Not_Exist:
			return .Missing
		}
	case io.Error:
		#partial switch e {
		case .Permission_Denied:
			return .Denied
		case .Unsupported:
			return .Unsupported
		}
	case os.Platform_Error:
		return platform_error(i32(e))
	}
	return .Other
}

// make_folder makes the folder at path, failing if anything is there.
make_folder :: proc(path: string) -> Error {
	return error_of(os.make_directory(path))
}

// restore puts back what the Trash holds at trashed, at to, failing
// rather than replacing what is at to by now.
restore :: proc(trashed, to: string) -> Error {
	if err := rename_noreplace(trashed, to); err != .None {
		return err
	}
	restored(trashed)
	return .None
}

// Progress is told how many bytes of a copy are done of how many.
Progress :: proc(user: rawptr, done, total: i64)

COPY_CHUNK :: 1 << 20

@(private)
Copier :: struct {
	cancel:   ^bool,
	progress: Progress,
	user:     rawptr,
	done:     i64,
	total:    i64,
	buf:      []u8,
}

// copy_tree copies the file, link or folder at from to to, which must
// not exist: nothing at to is ever replaced. It counts the bytes first
// and reports progress after every chunk; it stops at the first failure
// or when cancel^ is set, leaving what it made for the caller to clear.
copy_tree :: proc(from, to: string, cancel: ^bool = nil, progress: Progress = nil, user: rawptr = nil) -> Error {
	c := Copier{cancel = cancel, progress = progress, user = user}
	c.total = tree_size(from)
	c.buf = make([]u8, COPY_CHUNK, context.temp_allocator)
	if c.progress != nil {
		c.progress(c.user, 0, c.total)
	}
	return copy_entry(&c, from, to)
}

// tree_size is the bytes of the files under path, path itself if a file.
tree_size :: proc(path: string) -> (total: i64) {
	fi, err := os.lstat(path, context.temp_allocator)
	if err != nil {
		return 0
	}
	if fi.type != .Directory {
		return fi.size
	}
	infos, _ := os.read_all_directory_by_path(path, context.temp_allocator)
	for child in infos {
		total += tree_size(child.fullpath)
	}
	return
}

@(private)
copy_entry :: proc(c: ^Copier, from, to: string) -> Error {
	if c.cancel != nil && sync.atomic_load(c.cancel) {
		return .Cancelled
	}
	fi, err := os.lstat(from, context.temp_allocator)
	if err != nil {
		return error_of(err)
	}
	#partial switch fi.type {
	case .Directory:
		make_folder(to) or_return
		infos, rerr := os.read_all_directory_by_path(from, context.temp_allocator)
		if rerr != nil {
			return error_of(rerr)
		}
		for child in infos {
			target, _ := filepath.join({to, child.name}, context.temp_allocator)
			copy_entry(c, child.fullpath, target) or_return
		}
		return .None
	case .Symlink:
		link, lerr := os.read_link(from, context.temp_allocator)
		if lerr != nil {
			return error_of(lerr)
		}
		return error_of(os.symlink(link, to))
	}
	return copy_file(c, from, to)
}

@(private)
copy_file :: proc(c: ^Copier, from, to: string) -> Error {
	src, err := os.open(from)
	if err != nil {
		return error_of(err)
	}
	defer os.close(src)
	dst, derr := os.open(to, {.Write, .Create, .Excl})
	if derr != nil {
		return error_of(derr)
	}
	defer os.close(dst)
	for {
		if c.cancel != nil && sync.atomic_load(c.cancel) {
			return .Cancelled
		}
		n, rerr := os.read(src, c.buf)
		if n > 0 {
			if _, werr := os.write(dst, c.buf[:n]); werr != nil {
				return error_of(werr)
			}
			c.done += i64(n)
			if c.progress != nil {
				c.progress(c.user, c.done, c.total)
			}
		}
		if rerr == .EOF || (rerr == nil && n == 0) {
			return .None
		}
		if rerr != nil {
			return error_of(rerr)
		}
	}
}
