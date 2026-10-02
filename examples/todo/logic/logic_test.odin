package todo_logic

import "core:strings"
import "core:testing"

import "jm:ui"

import "../shapes"

@(test)
add_trims_and_writes_an_insert :: proc(t: ^testing.T) {
	l: Logic
	out := process(&l, {kind = .Add, title = text_make("  buy milk ")})
	testing.expect(t, out.has_write)
	testing.expect(t, !out.has_problem)
	testing.expect_value(t, out.write.op, Op.Insert)
	testing.expect_value(t, text_of(&out.write.title), "buy milk")
}

@(test)
add_refuses_a_blank_title_with_a_numbered_problem :: proc(t: ^testing.T) {
	l: Logic
	out := process(&l, {kind = .Add, title = text_make("   ")})
	testing.expect(t, !out.has_write)
	testing.expect(t, out.has_problem)
	testing.expect(t, out.problem.add)
	testing.expect_value(t, out.problem.id, u64(1))
	testing.expect_value(t, text_of(&out.problem.message), "A todo needs a title.")
	again := process(&l, {kind = .Add})
	testing.expect_value(t, again.problem.id, u64(2))
}

@(test)
add_refuses_a_title_that_filled_the_buffer :: proc(t: ^testing.T) {
	l: Logic
	long := strings.repeat("x", MAX_TITLE + 5)
	defer delete(long)
	out := process(&l, {kind = .Add, title = text_make(long)})
	testing.expect(t, out.has_problem)
	testing.expect(t, !out.has_write)
	testing.expect_value(t, text_of(&out.problem.message), "That title is too long to keep.")
}

@(test)
edit_to_nothing_removes_and_otherwise_retitles :: proc(t: ^testing.T) {
	l: Logic
	gone := process(&l, {kind = .Edit, id = 7, title = text_make(" ")})
	testing.expect_value(t, gone.write.op, Op.Remove)
	testing.expect_value(t, gone.write.id, i64(7))
	kept := process(&l, {kind = .Edit, id = 7, title = text_make("new")})
	testing.expect_value(t, kept.write.op, Op.Set_Title)
	testing.expect_value(t, text_of(&kept.write.title), "new")
}

@(test)
plain_commands_map_to_their_writes :: proc(t: ^testing.T) {
	l: Logic
	toggle := process(&l, {kind = .Toggle, id = 3}).write
	testing.expect_value(t, toggle.op, Op.Set_Done)
	testing.expect_value(t, toggle.id, i64(3))
	all := process(&l, {kind = .Toggle_All, done = true}).write
	testing.expect_value(t, all.op, Op.Set_All)
	testing.expect(t, all.done)
	remove := process(&l, {kind = .Delete, id = 3}).write
	testing.expect_value(t, remove.op, Op.Remove)
	testing.expect_value(t, remove.id, i64(3))
	testing.expect_value(t, process(&l, {kind = .Clear_Completed}).write.op, Op.Remove_Done)
	dismiss := process(&l, {kind = .Dismiss, problem = 9})
	testing.expect(t, dismiss.has_problem && !dismiss.problem.add)
	testing.expect_value(t, dismiss.problem.id, u64(9))
}

@(test)
request_decodes_the_contracts_commands_and_refuses_others :: proc(t: ^testing.T) {
	// A frame's command, as the loop hands it on: kind and cbor bytes.
	p: ui.Probe
	ui.probe_init(&p, proc(gtx: ^ui.Ctx, user: rawptr) {
			ui.command(gtx, shapes.Edit{id = 4, title = "four"})
			ui.command(gtx, shapes.Clear_Completed{})
			ui.command(gtx, shapes.Todos{})
		}, nil, {10, 10})
	defer ui.probe_destroy(&p)
	cmds := ui.probe_commands(&p)
	testing.expect_value(t, len(cmds), 3)
	r, ok := request(cmds[0])
	testing.expect(t, ok)
	testing.expect_value(t, r.kind, Kind.Edit)
	testing.expect_value(t, r.id, i64(4))
	testing.expect_value(t, text_of(&r.title), "four")
	r, ok = request(cmds[1])
	testing.expect(t, ok && r.kind == .Clear_Completed)
	_, ok = request(cmds[2])
	testing.expect(t, !ok)
}
