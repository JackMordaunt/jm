package shell

import "core:fmt"
import "jm:ui/ops"
import "core:mem/virtual"
import "core:os"
import "core:testing"
import "core:thread"
import "core:time"

import "jm:sh"
import "jm:ui"
import "jm:ui/ipc"

// CHILD_EXE is where examples/hot-counter/child gets built to, relative
// to the repo root — the working directory odin test ran from in every
// invocation observed in this session, `just test` and a plain `odin
// test ui/shell` from the root alike.
@(private = "file")
CHILD_EXE :: "build/debug/hot-counter-child.exe" when ODIN_OS == .Windows else "build/debug/hot-counter-child"

// require_child_exe makes every test in this file that drives the real
// hot-counter-child binary self-sufficient: `just test`'s
// hot-counter-child recipe builds it ahead of time so this is normally
// an already-true check, but a bare `odin test ui/shell` (run often enough
// while working on this package that it should not depend on going
// through just first) builds it here instead of finding it missing.
// Only an actual build failure fails t.
@(private = "file")
require_child_exe :: proc(t: ^testing.T) -> bool {
	if os.exists(CHILD_EXE) {
		return true
	}
	code, ok := sh.run(fmt.tprintf("odin build examples/hot-counter/child -collection:jm=. -out:%s", CHILD_EXE))
	if !ok {
		testing.expectf(t, false, "hot-counter-child build failed (exit %d)", code)
		return false
	}
	return true
}

// test_host_child_round_trip_moves_a_click_across_the_pipe spawns the real
// hot-counter child, asks for a frame, finds the "+" button the same way
// ui.Probe would, clicks it (Move+Press, a reply, then Release, as
// probe_click does), and checks the label's text changed. If the click
// never crossed the pipe — wrong routing, a wire encoding bug, anything —
// the label would still read "count 0".
@(test)
test_host_child_round_trip_moves_a_click_across_the_pipe :: proc(t: ^testing.T) {
	if !require_child_exe(t) {
		return
	}
	c, ok := ipc.spawn({CHILD_EXE})
	testing.expect(t, ok)
	defer ipc.kill(&c)

	// sc holds a Reply's decoded strings and slices for as long as this
	// test reads them, same as ui/shell and ui/child hold theirs for a
	// frame: a wholesale-freed arena, not one leak-tracked allocation per
	// decode that nothing here would otherwise individually free.
	arena: virtual.Arena
	defer virtual.arena_destroy(&arena)
	size := ops.Size{360, 200}
	sc: ops.Scene
	ops.init(&sc, virtual.arena_allocator(&arena))

	f := ask(t, &c, size, nil, &sc)
	before := shows_label(f, "count 0")
	testing.expect(t, before)

	plus, found := find_center(f, &sc, "+")
	testing.expect(t, found)

	f = ask(t, &c, size, []ui.Raw_Event{{kind = .Move, pos = plus}, {kind = .Press, pos = plus}}, &sc)
	f = ask(t, &c, size, []ui.Raw_Event{{kind = .Release, pos = plus}}, &sc)
	// The click landed during this very frame's ui(): counter_ui's label
	// reads m.count before the "+" button that increments it, so this
	// frame still renders the pre-click value — one more, with no new
	// input, is what shows the click actually took.
	f = ask(t, &c, size, nil, &sc)
	testing.expect(t, shows_label(f, "count 1"))
}

// test_maybe_respawn_follows_the_watch_pointer_file drives host_maybe_respawn
// directly against a real spawned child, with no Window: none of the
// fields it touches (app, child, child_dead, child_path) need one. A
// rebuild is simulated the way it matters to host_maybe_respawn — the pointer
// file's content names something new — with a second copy of CHILD_EXE
// standing in for a fresh build's own path; content is irrelevant here,
// only the path string host_maybe_respawn compares against is. Everything this
// test allocates uses context.temp_allocator, including what
// resolve_child_path/host_maybe_respawn clone internally, so there is nothing
// left to free by hand.
@(test)
test_maybe_respawn_follows_the_watch_pointer_file :: proc(t: ^testing.T) {
	if !require_child_exe(t) {
		return
	}
	context.allocator = context.temp_allocator

	copy_path := fmt.tprintf("%s.copy%s", CHILD_EXE, ".exe" when ODIN_OS == .Windows else "")
	data, rerr := os.read_entire_file(CHILD_EXE, context.temp_allocator)
	testing.expect(t, rerr == nil)
	// Executable, or the respawn below cannot start it; removed first, since
	// open(2) applies the mode only when it creates the file.
	os.remove(copy_path)
	testing.expect(t, os.write_entire_file(copy_path, data, os.Permissions_Read_All + os.Permissions_Execute_All + {.Write_User}) == nil)
	defer os.remove(copy_path)

	pointer := "build/debug/host_test.pointer"
	defer os.remove(pointer)
	testing.expect(t, os.write_entire_file(pointer, CHILD_EXE) == nil)

	l: Host_Loop
	l.app = {watch = pointer}
	path, pok := resolve_child_path(&l.app)
	testing.expect(t, pok)
	testing.expect_value(t, path, CHILD_EXE)
	child, ok := ipc.spawn(child_argv(&l.app, path))
	testing.expect(t, ok)
	l.child = child
	l.child_path = path
	defer ipc.kill(&l.child)
	first_pid := l.child.process.pid

	host_maybe_respawn(&l) // pointer unchanged: same child, still alive
	testing.expect_value(t, l.child.process.pid, first_pid)
	testing.expect(t, !l.child_dead)

	testing.expect(t, os.write_entire_file(pointer, copy_path) == nil)
	host_maybe_respawn(&l) // pointer moved: a new process replaces it
	testing.expect(t, !l.child_dead)
	testing.expect(t, l.child.process.pid != first_pid)

	// The new child is a live process, not just a new pid: it answers.
	input := ui.encode_input({100, 100}, 1, 0, nil, context.temp_allocator)
	testing.expect(t, ipc.write_frame(l.child.stdin, input))
	_, rok := ipc.read_frame(l.child.stdout, context.temp_allocator)
	testing.expect(t, rok)
}

// ask runs one round trip with c, as host_step does: events (and, once,
// what a previous child persisted) go in, the reply's scene comes back
// flattened; persist, when given, receives what the child asked to keep.
@(private = "file")
ask :: proc(t: ^testing.T, c: ^ipc.Child, size: ops.Size, events: []ui.Raw_Event, sc: ^ops.Scene, restore: []byte = nil, persist: ^[]byte = nil) -> ^ui.Frame {
	input := ui.encode_input(size, 1, 1.0 / 60, events, context.temp_allocator, restore = restore)
	testing.expect(t, ipc.write_frame(c.stdin, input))
	reply, rok := ipc.read_frame(c.stdout, context.temp_allocator)
	testing.expect(t, rok)
	_, _, ops_bytes, dok := ui.decode_reply(reply, persist = persist)
	testing.expect(t, dok)
	testing.expect(t, ops.decode(ops_bytes, sc))
	f := new(ui.Frame, context.temp_allocator)
	ui.frame_init(f, context.temp_allocator)
	ui.flatten(sc, f)
	return f
}

// test_a_respawned_child_starts_from_what_the_last_persisted clicks the
// counter up in one child, takes what its reply asks to persist (as
// host_step keeps it in Host_Loop.saved), and hands it to a fresh child
// with its first input, the way host_step does after host_maybe_respawn:
// the new process shows the old count, not zero.
@(test)
test_a_respawned_child_starts_from_what_the_last_persisted :: proc(t: ^testing.T) {
	if !require_child_exe(t) {
		return
	}
	arena: virtual.Arena
	defer virtual.arena_destroy(&arena)
	size := ops.Size{360, 200}
	sc: ops.Scene
	ops.init(&sc, virtual.arena_allocator(&arena))

	first, ok := ipc.spawn({CHILD_EXE})
	testing.expect(t, ok)
	f := ask(t, &first, size, nil, &sc)
	plus, found := find_center(f, &sc, "+")
	testing.expect(t, found)
	ask(t, &first, size, []ui.Raw_Event{{kind = .Move, pos = plus}, {kind = .Press, pos = plus}}, &sc)
	// The click lands in this frame, and persist_struct sends the model
	// the moment it changes: the reply to the release carries it.
	persisted: []byte
	ask(t, &first, size, []ui.Raw_Event{{kind = .Release, pos = plus}}, &sc, persist = &persisted)
	testing.expect_value(t, string(persisted), "count 1\n")
	f = ask(t, &first, size, nil, &sc)
	testing.expect(t, shows_label(f, "count 1"))
	saved := make([]byte, len(persisted), context.temp_allocator) // host_step copies it out of the reply
	copy(saved, persisted)
	ipc.kill(&first)

	second, sok := ipc.spawn({CHILD_EXE})
	testing.expect(t, sok)
	defer ipc.kill(&second)
	f = ask(t, &second, size, nil, &sc, restore = saved)
	testing.expect(t, shows_label(f, "count 1"))
	// Only the first input restores; the count then lives in the child.
	f = ask(t, &second, size, nil, &sc)
	testing.expect(t, shows_label(f, "count 1"))
}

@(private = "file")
find_center :: proc(f: ^ui.Frame, sc: ^ops.Scene, name: string) -> (p: ops.Point, ok: bool) {
	for tg in f.tags {
		if tg.name != name {
			continue
		}
		#reverse for h in f.hits {
			if h.area != tg.id {
				continue
			}
			r := ops.transform_rect(h.transform, ops.shape_bounds(sc, h.shape))
			return {r.x + r.w / 2, r.y + r.h / 2}, true
		}
	}
	return {}, false
}

@(private = "file")
shows_label :: proc(f: ^ui.Frame, name: string) -> bool {
	for tg in f.tags {
		if tg.name == name {
			return true
		}
	}
	return false
}

// test_wait_for_child_outlasts_the_first_build waits on a pointer file
// another thread writes 200ms later, as hot-watch's first build does
// after the recipe starts the host; a name with no child and no watch
// fails without waiting.
@(test)
test_wait_for_child_outlasts_the_first_build :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	pointer := "build/debug/host_test.wait"
	os.remove(pointer)
	defer os.remove(pointer)
	writer := thread.create_and_start_with_data(rawptr(uintptr(0)), proc(_: rawptr) {
		time.sleep(200 * time.Millisecond)
		_ = os.write_entire_file("build/debug/host_test.wait", CHILD_EXE)
	})
	defer thread.destroy(writer)
	app := Host_App{watch = pointer}
	start := time.tick_now()
	path, ok := wait_for_child(&app, 5 * time.Second)
	testing.expect(t, ok)
	testing.expect_value(t, path, CHILD_EXE)
	testing.expect(t, time.tick_since(start) >= 200 * time.Millisecond)
	thread.join(writer)

	none := Host_App{}
	_, ok = wait_for_child(&none, 5 * time.Second)
	testing.expect(t, !ok)
	os.remove(pointer)
	gone := Host_App{watch = pointer}
	start = time.tick_now()
	_, ok = wait_for_child(&gone, 600 * time.Millisecond) // one poll, then the deadline
	testing.expect(t, !ok)
	testing.expect(t, time.tick_since(start) < 3 * time.Second)
}

@(test)
test_a_host_argument_ending_watch_is_the_pointer_file :: proc(t: ^testing.T) {
	base := Host_App{title = "t", child = {"stale"}}
	watched := host_app_for(base, {"build/debug/x.watch"})
	testing.expect_value(t, watched.watch, "build/debug/x.watch")
	testing.expect_value(t, watched.child[0], "stale")
	fixed := host_app_for(base, {"build/debug/x-child"})
	testing.expect_value(t, fixed.watch, "")
	testing.expect_value(t, len(fixed.child), 1)
	testing.expect_value(t, fixed.child[0], "build/debug/x-child")
}
