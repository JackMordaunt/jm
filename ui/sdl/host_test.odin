package sdl

import "core:mem/virtual"
import "core:os"
import "core:testing"

import "jm:ui"
import "jm:ui/ipc"

// CHILD_EXE is where `just test`'s hot-counter-child recipe (a
// prerequisite of test itself, so this runs there) puts
// examples/hot-counter/child, relative to the repo root — the working
// directory odin test ran from in every invocation observed in this
// session, `just test` and a plain `odin test ui/sdl` from the root
// alike. This test drives that real built binary, not a stub, so a
// missing one fails loudly (`just hot-counter-child` builds it) rather
// than silently reporting a round trip it never actually tried.
@(private = "file")
CHILD_EXE :: "build/debug/hot-counter-child.exe" when ODIN_OS == .Windows else "build/debug/hot-counter-child"

// test_host_child_round_trip_moves_a_click_across_the_pipe spawns the real
// hot-counter child, asks for a frame, finds the "+" button the same way
// ui.Probe would, clicks it (Move+Press, a reply, then Release, as
// probe_click does), and checks the label's text changed. If the click
// never crossed the pipe — wrong routing, a wire encoding bug, anything —
// the label would still read "count 0".
@(test)
test_host_child_round_trip_moves_a_click_across_the_pipe :: proc(t: ^testing.T) {
	if !os.exists(CHILD_EXE) {
		testing.expect(t, false, "hot-counter-child not built; run `just hot-counter-child` (or `just test`)")
		return
	}
	c, ok := ipc.spawn({CHILD_EXE})
	testing.expect(t, ok)
	defer ipc.kill(&c)

	// ops holds a Reply's decoded strings and slices for as long as this
	// test reads them, same as ui/sdl and ui/child hold theirs for a
	// frame: a wholesale-freed arena, not one leak-tracked allocation per
	// decode that nothing here would otherwise individually free.
	arena: virtual.Arena
	defer virtual.arena_destroy(&arena)
	size := ui.Size{360, 200}
	ops: ui.Ops
	ui.ops_init(&ops, virtual.arena_allocator(&arena))

	ask :: proc(t: ^testing.T, c: ^ipc.Child, size: ui.Size, events: []ui.Raw_Event, ops: ^ui.Ops) -> ^ui.Frame {
		input := ui.encode_input(size, 1, 1.0 / 60, events, context.temp_allocator)
		testing.expect(t, ipc.write_frame(c.stdin, input))
		reply, rok := ipc.read_frame(c.stdout, context.temp_allocator)
		testing.expect(t, rok)
		_, _, ops_bytes, dok := ui.decode_reply(reply)
		testing.expect(t, dok)
		testing.expect(t, ui.decode(ops_bytes, ops))
		f := new(ui.Frame, context.temp_allocator)
		ui.frame_init(f, context.temp_allocator)
		ui.flatten(ops, f)
		return f
	}

	f := ask(t, &c, size, nil, &ops)
	before := shows_label(f, "count 0")
	testing.expect(t, before)

	plus, found := find_center(f, &ops, "+")
	testing.expect(t, found)

	f = ask(t, &c, size, []ui.Raw_Event{{kind = .Move, pos = plus}, {kind = .Press, pos = plus}}, &ops)
	f = ask(t, &c, size, []ui.Raw_Event{{kind = .Release, pos = plus}}, &ops)
	// The click landed during this very frame's ui(): counter_ui's label
	// reads m.count before the "+" button that increments it, so this
	// frame still renders the pre-click value — one more, with no new
	// input, is what shows the click actually took.
	f = ask(t, &c, size, nil, &ops)
	testing.expect(t, shows_label(f, "count 1"))
}

@(private = "file")
find_center :: proc(f: ^ui.Frame, ops: ^ui.Ops, name: string) -> (p: ui.Point, ok: bool) {
	for tg in f.tags {
		if tg.name != name {
			continue
		}
		#reverse for h in f.hits {
			if h.area != tg.id {
				continue
			}
			r := ui.transform_rect(h.transform, ui.shape_bounds(ops, h.shape))
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
