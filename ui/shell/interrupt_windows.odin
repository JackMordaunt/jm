package shell

// Windows has no SIGINT to catch the same way: a console's Ctrl-C arrives
// through a console control handler, and a windowed app usually has no
// console. Until that is wired, run keeps SDL's own behaviour there.

@(private)
interrupt_start :: proc() -> bool {
	return false
}

@(private)
interrupt_stop :: proc() {}

// interrupted reports whether a signal ended the last run: never, here.
interrupted :: proc() -> bool {
	return false
}
