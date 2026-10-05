/*
Package files is what the file browser's ui may ask the application to
do: the Command union, holding only what the ui knows when it asks. A
command names paths from a listing that may already be stale; whether
what it asks is still possible, and what it comes to, is the
application's to find out and decide. The view emits these, the host
decodes them, and examples/files/logic decides them. It imports nothing.

Commands are values with fixed buffers, not strings, because they cross
stream edges by copy between threads. Each buffer holds one byte more
than the longest value allowed, so a value that filled it is known to
have been cut short.
*/
package files

// MAX_PATH is the longest path a command carries, in bytes.
MAX_PATH :: 1024

// MAX_NAME is the longest name a command carries, in bytes: the limit
// every supported filesystem puts on one component.
MAX_NAME :: 255

Path :: struct {
	buf: [MAX_PATH + 1]u8,
	len: int,
}

Name :: struct {
	buf: [MAX_NAME + 1]u8,
	len: int,
}

path_make :: proc(s: string) -> (p: Path) {
	p.len = copy(p.buf[:], s)
	return
}

path_of :: proc(p: ^Path) -> string {
	return string(p.buf[:p.len])
}

// path_fits says whether p holds the whole path it was made from.
path_fits :: proc(p: ^Path) -> bool {
	return p.len <= MAX_PATH
}

name_make :: proc(s: string) -> (n: Name) {
	n.len = copy(n.buf[:], s)
	return
}

name_of :: proc(n: ^Name) -> string {
	return string(n.buf[:n.len])
}

// Mode is what a paste does with its source.
Mode :: enum u8 {
	Copy,
	Move,
}

// Choice answers the question a paste asks when its name is taken.
Choice :: enum u8 {
	Replace, // the one there goes to the Trash
	Keep_Both, // the pasted one takes a free name
	Skip,
}

Command :: union {
	Open,
	Visited,
	Pin,
	Unpin,
	Rename,
	New_Folder,
	Trash,
	Paste,
	Resolve,
	Cancel,
	Undo,
	Dismiss,
}

// Open asks the system to open a file with its default application.
Open :: struct {
	path: Path,
}

// Visited says a folder was entered or a file opened, for Recent.
Visited :: struct {
	path: Path,
	name: Name,
	dir:  bool,
}

// Pin adds a folder to the sidebar; Unpin takes it off.
Pin :: struct {
	path: Path,
	name: Name,
}

Unpin :: struct {
	path: Path,
}

// Rename gives the entry at path a new name in the same folder.
Rename :: struct {
	path: Path,
	name: Name,
}

// New_Folder makes a folder in parent, called name or, if that is
// taken, the next free name after it.
New_Folder :: struct {
	parent: Path,
	name:   Name,
}

// Trash moves the entry at path to the system's Trash.
Trash :: struct {
	path: Path,
}

// Paste copies or moves source into the folder dest.
Paste :: struct {
	source: Path,
	dest:   Path,
	mode:   Mode,
}

// Resolve answers the question operation op asked.
Resolve :: struct {
	op:     u64,
	choice: Choice,
}

// Cancel stops operation op: a copy where it is, a question unanswered.
Cancel :: struct {
	op: u64,
}

// Undo reverses the last change the application made, if the world
// still allows it.
Undo :: struct {}

// Dismiss drops a problem from query.Activity.
Dismiss :: struct {
	id: u64,
}
