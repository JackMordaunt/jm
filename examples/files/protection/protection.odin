/*
Package protection decides which entries the browser will not rename,
move or trash: the places a user's setup depends on, which a slip of the
mouse should not be able to break.
*/
package files_protection

import "core:path/filepath"

Reason :: enum u8 {
	None, // free to change
	Root, // the root of a filesystem
	Home, // the home folder itself
	Place, // a standard folder under home: Desktop, Documents, …
}

// reason answers "may the entry at path be changed, and if not, why?".
// places are the standard folders the sidebar lists.
reason :: proc(path, home: string, places: []string) -> Reason {
	if root(path) {
		return .Root
	}
	if path == home {
		return .Home
	}
	for p in places {
		if path == p {
			return .Place
		}
	}
	return .None
}

// root guards native filesystem roots, including a Windows UNC share.
// A bare drive name is guarded too: it must never become a mutation target.
root :: proc(path: string) -> bool {
	if len(path) == 1 && filepath.is_separator(path[0]) {
		return true
	}
	when ODIN_OS == .Windows {
		volume := filepath.volume_name(path)
		rest := path[len(volume):]
		return volume != "" && (rest == "" || len(rest) == 1 && filepath.is_separator(rest[0]))
	} else {
		return false
	}
}
