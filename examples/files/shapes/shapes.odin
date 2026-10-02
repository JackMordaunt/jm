/*
Package shapes is the file browser's contract: a folder's listing and a
file's thumbnail as the ui needs them, the statistics for its header, and
the one command the application processes, opening a file.
*/
package files_shapes

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

// Recent is the folders entered and files opened lately, newest first,
// as of when it was first asked for: a snapshot the sidebar keeps still
// while the application runs, not a list that jumps with every click.
Recent :: struct {}

Recent_Result :: struct {
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

// Open asks the system to open a file with its default application.
Open :: struct {
	path: string,
}

// Visited says a folder was entered or a file opened, for Recent.
Visited :: struct {
	path: string,
	name: string,
	dir:  bool,
}

// Pin adds a folder to the sidebar; Unpin takes it off.
Pin :: struct {
	path: string,
	name: string,
}

Unpin :: struct {
	path: string,
}
