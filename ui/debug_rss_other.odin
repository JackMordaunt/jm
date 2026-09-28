#+build !linux
package ui

// process_rss is -1 here: resident memory is read on Linux only so far.
process_rss :: proc() -> int {
	return -1
}
