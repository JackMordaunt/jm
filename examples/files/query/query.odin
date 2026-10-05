/*
Package query is what the file browser's ui may read: each query is a
pair, the params a need asks with and the result it is answered with,
named Name and Name_Result. The view needs these; the host answers them
from the filesystem, the store, or the application's memory. It imports
nothing.
*/
package files_query

// Listing is the entries of a folder.
Listing :: struct {
	path: string,
}

Entry :: struct {
	name:     string,
	path:     string,
	dir:      bool,
	image:    bool, // a picture by its extension: the ui needs a thumbnail
	size:     i64,
	modified: i64, // unix seconds
}

// Listing_Result answers Listing: the entries, folders first, or why not.
Listing_Result :: struct {
	entries: []Entry,
	error:   string,
}

// Thumb is a picture's thumbnail at a pixel size.
Thumb :: struct {
	path: string,
	px:   int,
}

// Thumb_Result answers Thumb: an image file the renderer reads by path.
Thumb_Result :: struct {
	image: string,
}

// Place is a folder or file the sidebar lists: a standard folder, a
// pinned one, or one visited lately.
Place :: struct {
	name: string,
	path: string,
	dir:  bool,
}

// Places is the standard folders under the home folder that exist.
Places :: struct {}

Places_Result :: struct {
	items: []Place,
}

// Pins is the folders pinned to the sidebar, in the order pinned.
Pins :: struct {}

Pins_Result :: struct {
	items: []Place,
}

// Recent_Places is the folders entered and files opened lately, newest first,
// as of when it was first asked for: a snapshot the sidebar keeps still
// while the application runs, not a list that jumps with every click.
Recent_Places :: struct {}

Recent_Places_Result :: struct {
	items: []Place,
}

Stats :: struct {}

Stats_Result :: struct {
	open:      int, // needs live now: listings and thumbnails
	listings:  int, // folders read
	thumbs:    int, // thumbnails made
	cancelled: int, // thumbnails abandoned before they were done
	pending:   int,
}

// Activity is what the application is doing and what went wrong: the
// operations running or waiting on an answer, the problems not yet
// dismissed, and what Undo would undo.
Activity :: struct {}

// Operation is a long copy or move, or a question a paste asked.
Operation :: struct {
	id:       u64,
	label:    string,
	done:     i64, // bytes copied so far
	total:    i64, // bytes to copy, 0 until counted
	question: string, // set while the operation waits on a files.Resolve
}

Problem :: struct {
	id:      u64,
	message: string,
}

Activity_Result :: struct {
	operations: []Operation,
	problems:   []Problem,
	undo:       string, // what Undo would undo, "" for nothing
}
