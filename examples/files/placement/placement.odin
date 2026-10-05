/*
Package placement decides how a pasted entry reaches the folder it is
pasted into: whether it can go there at all, whether it would collide,
and whether a move is a rename or a copy then a trash.
*/
package files_placement

import "core:path/filepath"
import "core:strings"

import "../files"

// Facts are what the method of a paste turns on. Paths are as the
// listing gave them: absolute and clean.
Facts :: struct {
	source:        string,
	dest:          string, // the folder pasted into
	mode:          files.Mode,
	source_is_dir: bool,
	same_volume:   bool, // source and dest are on one filesystem
	name_taken:    bool, // the source's name is taken in dest
}

Method :: enum u8 {
	Into_Itself, // a folder into itself or a folder inside it
	Already_There, // a move into the folder it is in
	Duplicate, // a copy into the folder it is in: beside it, under a free name
	Conflict, // the name is taken: the user decides
	Rename, // a move on one filesystem
	Copy,
	Copy_Then_Trash, // a move across filesystems
}

// method answers "how does this entry get there?".
method :: proc(f: Facts) -> Method {
	if f.source_is_dir && inside(f.dest, f.source) {
		return .Into_Itself
	}
	if filepath.dir(f.source) == f.dest {
		return .Already_There if f.mode == .Move else .Duplicate
	}
	if f.name_taken {
		return .Conflict
	}
	switch f.mode {
	case .Copy:
		return .Copy
	case .Move:
		return .Rename if f.same_volume else .Copy_Then_Trash
	}
	return .Copy
}

// inside says whether path is folder or lies anywhere under it.
inside :: proc(path, folder: string) -> bool {
	if path == folder {
		return true
	}
	return strings.has_prefix(path, folder) &&
		len(path) > len(folder) &&
		(path[len(folder)] == filepath.SEPARATOR || strings.has_suffix(folder, filepath.SEPARATOR_STRING))
}
