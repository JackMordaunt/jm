/*
Package path is the file-system vocabulary a script reaches for: expand a
home-relative path, make a directory tree, read and write whole files, list
or walk a tree, and find the per-user state, config, cache and log folders on
every platform.

Every proc that can fail returns an os.Error so `must` composes:

	cfg  := must(path.read(path.expand("~/.config/tool/cfg.json")))
	must(path.mkdirs(path.state_dir("tool")))
	must(path.write(out, rendered))

Pure helpers (expand, join, base, dir, ext, stem, same) never fail.
*/
package path

import "base:runtime"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"

// Re-exports, so a script needs one import for path work.
base     :: filepath.base
dir      :: filepath.dir
ext      :: filepath.ext
stem     :: filepath.stem
clean    :: filepath.clean
is_abs   :: filepath.is_abs
exists   :: os.exists
is_dir   :: os.is_dir
is_file  :: os.is_file
remove   :: os.remove
rename   :: os.rename
copy     :: os.copy_file
glob     :: os.glob
remove_all :: os.remove_all

SEPARATOR :: filepath.SEPARATOR

// home returns the current user's home directory.
home :: proc(allocator := context.allocator) -> string {
	h, err := os.user_home_dir(allocator)
	if err != nil {
		return ""
	}
	return h
}

// expand replaces a leading "~" or "~/" with the home directory and cleans
// the result. Other paths come back cleaned.
expand :: proc(p: string, allocator := context.allocator) -> string {
	if p == "~" {
		return home(allocator)
	}
	if strings.has_prefix(p, "~/") || strings.has_prefix(p, `~\`) {
		return join(home(context.temp_allocator), p[2:], allocator = allocator)
	}
	cleaned, _ := filepath.clean(p, allocator)
	return cleaned
}

// join joins path elements with the platform separator and cleans the result.
join :: proc(elems: ..string, allocator := context.allocator) -> string {
	s, _ := filepath.join(elems, allocator)
	return s
}

// abs makes p absolute against the working directory.
abs :: proc(p: string, allocator := context.allocator) -> (string, os.Error) {
	return filepath.abs(p, allocator)
}

// mkdirs creates p and every missing parent. An existing directory is not
// an error.
mkdirs :: proc(p: string) -> os.Error {
	err := os.make_directory_all(p)
	if err == os.General_Error.Exist && os.is_dir(p) {
		return nil
	}
	return err
}

// read returns the whole file as a string.
read :: proc(p: string, allocator := context.allocator) -> (string, os.Error) {
	data, err := os.read_entire_file_from_path(p, allocator)
	return string(data), err
}

// read_lines returns the file split into lines, without line endings.
read_lines :: proc(p: string, allocator := context.allocator) -> ([]string, os.Error) {
	text, err := read(p, allocator)
	if err != nil {
		return nil, err
	}
	trimmed := strings.trim_right(text, "\r\n")
	if trimmed == "" {
		return nil, nil
	}
	parts, _ := strings.split_lines(trimmed, allocator)
	for &part in parts {
		part = strings.trim_right(part, "\r")
	}
	return parts, nil
}

// write replaces the file's contents, creating parents as needed.
write :: proc(p: string, data: string) -> os.Error {
	if err := mkdirs(filepath.dir(p)); err != nil {
		return err
	}
	return os.write_entire_file(p, data)
}

// append_file adds data to the end of the file, creating it if needed.
append_file :: proc(p: string, data: string) -> os.Error {
	if err := mkdirs(filepath.dir(p)); err != nil {
		return err
	}
	f, err := os.open(p, {.Write, .Append, .Create}, os.Permissions_Read_All + {.Write_User})
	if err != nil {
		return err
	}
	defer os.close(f)
	_, werr := os.write_string(f, data)
	return werr
}

// list returns the names in a directory, sorted.
list :: proc(p: string, allocator := context.allocator) -> ([]string, os.Error) {
	infos, err := os.read_all_directory_by_path(p, context.temp_allocator)
	if err != nil {
		return nil, err
	}
	names := make([]string, len(infos), allocator)
	for info, i in infos {
		names[i] = strings.clone(info.name, allocator)
	}
	slice.sort(names)
	return names, nil
}

// walk returns the full path of every regular file under root, depth first,
// sorted. Directories are descended but not listed.
walk :: proc(root: string, allocator := context.allocator) -> ([]string, os.Error) {
	w := os.walker_create(root)
	defer os.walker_destroy(&w)
	files := make([dynamic]string, allocator)
	for info in os.walker_walk(&w) {
		if info.type == .Regular {
			append(&files, strings.clone(info.fullpath, allocator))
		}
	}
	if _, err := os.walker_error(&w); err != nil {
		return files[:], err
	}
	slice.sort(files[:])
	return files[:], nil
}

// temp_dir creates a fresh directory under the system temp location. The
// caller removes it with remove_all.
temp_dir :: proc(prefix := "odin-", allocator := context.allocator) -> (string, os.Error) {
	pattern := strings.concatenate({prefix, "*"}, context.temp_allocator)
	return os.make_directory_temp("", pattern, allocator)
}

// same reports whether two paths name the same location after cleaning. Case
// is folded on Windows and macOS, whose default file systems (NTFS, APFS as
// shipped) are case-insensitive; other volumes on those systems may differ.
same :: proc(a, b: string) -> bool {
	ca, _ := filepath.clean(a, context.temp_allocator)
	cb, _ := filepath.clean(b, context.temp_allocator)
	when ODIN_OS == .Windows || ODIN_OS == .Darwin {
		return strings.equal_fold(ca, cb)
	} else {
		return ca == cb
	}
}

// Per-user application directories, created on first use. The base folders
// come from core:os user_*_dir, whose doc comments in core/os/user.odin give:
//
//	             Linux                 macOS                          Windows
//	state_dir    ~/.local/state/app    ~/Library/Application Support  %LOCALAPPDATA%\app
//	config_dir   ~/.config/app         ~/Library/Application Support  %LOCALAPPDATA%\app
//	cache_dir    ~/.cache/app          ~/Library/Caches/app           %LOCALAPPDATA%\app
//	log_dir      ~/.local/state/app    ~/Library/Logs/app             %LOCALAPPDATA%\app
state_dir :: proc(app: string, allocator := context.allocator) -> (string, os.Error) {
	return app_dir(os.user_state_dir, app, allocator)
}

config_dir :: proc(app: string, allocator := context.allocator) -> (string, os.Error) {
	base_dir, err := os.user_config_dir(context.temp_allocator)
	if err != nil {
		return "", err
	}
	return ensure(join(base_dir, app, allocator = allocator))
}

cache_dir :: proc(app: string, allocator := context.allocator) -> (string, os.Error) {
	return app_dir(os.user_cache_dir, app, allocator)
}

log_dir :: proc(app: string, allocator := context.allocator) -> (string, os.Error) {
	return app_dir(os.user_log_dir, app, allocator)
}

// ---- internals ----------------------------------------------------------

Dir_Proc :: #type proc(allocator: runtime.Allocator) -> (string, os.Error)

app_dir :: proc(base_of: Dir_Proc, app: string, allocator: runtime.Allocator) -> (string, os.Error) {
	base_dir, err := base_of(context.temp_allocator)
	if err != nil {
		return "", err
	}
	return ensure(join(base_dir, app, allocator = allocator))
}

ensure :: proc(p: string) -> (string, os.Error) {
	if err := mkdirs(p); err != nil {
		return p, err
	}
	return p, nil
}
