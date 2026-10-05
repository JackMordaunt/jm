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

// root says whether path is a filesystem's root: "/" or a Windows
// drive's "C:\".
root :: proc(path: string) -> bool {
	if path == filepath.SEPARATOR_STRING {
		return true
	}
	return len(path) <= 3 && len(path) >= 2 && path[1] == ':'
}
