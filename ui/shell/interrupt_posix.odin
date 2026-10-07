#+build !windows
package shell

// Ctrl-C and SIGTERM end the app the way closing its window does: run
// returns, and whatever the app does after run — closing its database,
// flushing its files — runs too. A second signal, for an app whose shutdown
// is stuck, exits at once with the shell convention's 128 + signal.
//
// SDL has a SIGINT handler of its own, but it only marks a quit as pending
// for the next time the queue is pumped (SDL_quit.c, SDL_HandleSIG: "Send a
// quit event next time the event loop pumps"), and an idle window is parked in
// SDL_WaitEvent with nothing to pump it: the signal sat unanswered until
// the window happened to get an event, such as being brought onto the
// current desktop. Here the handler writes a byte to a pipe — one of the
// few things a signal handler may safely do — and a watcher thread reads
// it and posts SDL's quit event, which wakes the wait.
//
// Masking the signals and waiting on them with sigwait would be simpler,
// and does not work on macOS: the system's dispatch worker threads start
// with every signal unmasked, so a signal sent to the process may be
// delivered to one of them instead of the waiting thread.

import "core:sync"
import "core:sys/posix"
import "core:thread"
import sdl3 "vendor:sdl3"

// INTERRUPT_SIGNALS are the requests to stop that a terminal and a process
// manager send.
@(private)
INTERRUPT_SIGNALS :: [2]posix.Signal{.SIGINT, .SIGTERM}

// The two bytes the pipe carries: a signal arrived, or the watch is
// stopping and the watcher should return.
@(private = "file")
BYTE_INTERRUPT :: 1
@(private = "file")
BYTE_STOP :: 2

@(private = "file")
pipe_fds: [2]posix.FD

// signals counts the signals caught since the watch started, read by the
// handler to tell the first from the second.
@(private = "file")
signals: i32

@(private = "file")
watcher: ^thread.Thread

@(private = "file")
previous: [len(INTERRUPT_SIGNALS)]posix.sigaction_t

// interrupt_action is what the watcher does on the first signal: post a
// quit. A test replaces it to watch the mechanism without a window.
@(private)
interrupt_action: proc() = post_quit

@(private = "file")
post_quit :: proc() {
	e: sdl3.Event
	e.type = .QUIT
	_ = sdl3.PushEvent(&e)
}

// interrupted reports whether a signal, not the window, ended the last
// run. An app that wants the shell's exit status for it exits 130.
interrupted :: proc() -> bool {
	return sync.atomic_load(&signals) > 0
}

// interrupt_start installs the handler and starts the watcher. It must
// come before SDL_Init, which installs SDL's own handler when it finds
// the default one; SDL is also told not to. It reports false, and leaves
// the signals as they were, when the pipe cannot be made.
@(private)
interrupt_start :: proc() -> bool {
	sdl3.SetHint(sdl3.HINT_NO_SIGNAL_HANDLERS, "1")
	sync.atomic_store(&signals, 0)
	if posix.pipe(&pipe_fds) != .OK {
		return false
	}
	watcher = thread.create_and_start(watch)
	act: posix.sigaction_t
	act.sa_handler = on_signal
	posix.sigemptyset(&act.sa_mask)
	for sig, i in INTERRUPT_SIGNALS {
		posix.sigaction(sig, &act, &previous[i])
	}
	return true
}

// interrupt_stop puts the signals back as they were, so a signal during
// the app's own shutdown does what it did before run, and ends the
// watcher.
@(private)
interrupt_stop :: proc() {
	if watcher == nil {
		return
	}
	for sig, i in INTERRUPT_SIGNALS {
		posix.sigaction(sig, &previous[i], nil)
	}
	stop := [1]byte{BYTE_STOP}
	_ = posix.write(pipe_fds[1], raw_data(stop[:]), 1)
	thread.join(watcher)
	thread.destroy(watcher)
	watcher = nil
	posix.close(pipe_fds[0])
	posix.close(pipe_fds[1])
}

// on_signal runs in whatever thread the system chose, between any two
// instructions, so it touches nothing but an atomic, the pipe and _exit,
// and leaves errno as it found it.
@(private = "file")
on_signal :: proc "c" (sig: posix.Signal) {
	saved := posix.errno()
	defer posix.errno(saved)
	if sync.atomic_add(&signals, 1) > 0 {
		posix._exit(128 + i32(sig))
	}
	b := [1]byte{BYTE_INTERRUPT}
	_ = posix.write(pipe_fds[1], raw_data(b[:]), 1)
}

// watch waits on the pipe and acts on what arrives, until told to stop.
@(private = "file")
watch :: proc() {
	for {
		b: [1]byte
		n := posix.read(pipe_fds[0], raw_data(b[:]), 1)
		if n < 0 && posix.errno() == .EINTR {
			continue
		}
		if n <= 0 || b[0] == BYTE_STOP {
			return
		}
		interrupt_action()
	}
}
