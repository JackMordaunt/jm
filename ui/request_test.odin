package ui

import "core:testing"
import jdebug "jm:debug"
import "jm:ui/ops"

// Board is a test ui: two focusable text areas, "a" over the left half
// and "b" over the right, that copy "a says hi" on SHORTCUT+C, ask for
// the clipboard on SHORTCUT+V, and keep what a Paste brings.
@(private = "file")
Board :: struct {
	pasted:     [2]string,
	both_read:  bool, // V makes both areas ask, to check each is answered
	write_last: string, // borrowed literal; when set, C writes twice, this second
	clicks:     u8,
	focus_b:    bool, // ask for b's focus this frame
	events:     [2][dynamic]Event,
}

@(private = "file")
BOARD_KINDS :: ops.Event_Kinds{.Press, .Release, .Key, .Text, .Focus, .Blur, .Paste}

@(private = "file")
board :: proc(gtx: ^Ctx, user: rawptr) {
	b := (^Board)(user)
	ids := [2]ops.Area_Id{101, 102}
	for id, i in ids {
		ops.input_area(gtx.scene, id, ops.Rect{f32(i) * 50, 0, 50, 50}, BOARD_KINDS, .Text)
		ops.tag(gtx.scene, id, "a" if i == 0 else "b")
		for e in events(gtx, id) {
			append(&b.events[i], e)
			#partial switch e.kind {
			case .Press:
				b.clicks = e.clicks
			case .Key:
				if e.mods != {SHORTCUT} {
					continue
				}
				#partial switch e.key {
				case .C:
					clipboard_write(gtx, "a says hi")
					if b.write_last != "" {
						clipboard_write(gtx, b.write_last)
					}
				case .V:
					clipboard_read(gtx, id)
					if b.both_read {
						clipboard_read(gtx, ids[1 - i])
					}
				}
			case .Paste:
				b.pasted[i] = clone_string(e.text, context.allocator)
			}
		}
	}
	if b.focus_b {
		focus_request(gtx, ids[1])
		b.focus_b = false
	}
}

@(private = "file")
board_destroy :: proc(b: ^Board) {
	for s in b.pasted {
		delete(s)
	}
	for e in b.events {
		delete(e)
	}
}

@(test)
test_copy_writes_the_clipboard :: proc(t: ^testing.T) {
	b: Board
	defer board_destroy(&b)
	p: Probe
	probe_init(&p, board, &b, {100, 50})
	defer probe_destroy(&p)
	testing.expect(t, probe_click(&p, "a"))
	probe_key(&p, .C, {SHORTCUT})
	testing.expect_value(t, probe_clipboard(&p), "a says hi")
}

@(test)
test_a_frames_last_clipboard_write_wins :: proc(t: ^testing.T) {
	b := Board{write_last = "second"}
	defer board_destroy(&b)
	p: Probe
	probe_init(&p, board, &b, {100, 50})
	defer probe_destroy(&p)
	probe_click(&p, "a")
	probe_key(&p, .C, {SHORTCUT})
	testing.expect_value(t, probe_clipboard(&p), "second")
}

@(test)
test_paste_reaches_the_area_that_asked :: proc(t: ^testing.T) {
	b: Board
	defer board_destroy(&b)
	p: Probe
	probe_init(&p, board, &b, {100, 50})
	defer probe_destroy(&p)
	probe_set_clipboard(&p, "from elsewhere")
	probe_click(&p, "b")
	probe_key(&p, .V, {SHORTCUT})
	// The read is answered after the frame that asked; the Paste lands in
	// the next one.
	probe_frame(&p)
	testing.expect_value(t, b.pasted[1], "from elsewhere")
	testing.expect_value(t, b.pasted[0], "")
	testing.expect_value(t, len(p.router.readers), 0)
}

@(test)
test_one_paste_answers_every_asker :: proc(t: ^testing.T) {
	b := Board{both_read = true}
	defer board_destroy(&b)
	p: Probe
	probe_init(&p, board, &b, {100, 50})
	defer probe_destroy(&p)
	probe_set_clipboard(&p, "shared")
	probe_click(&p, "a")
	probe_key(&p, .V, {SHORTCUT})
	probe_frame(&p)
	testing.expect_value(t, b.pasted[0], "shared")
	testing.expect_value(t, b.pasted[1], "shared")
}

@(test)
test_a_paste_nobody_asked_for_is_dropped :: proc(t: ^testing.T) {
	b: Board
	defer board_destroy(&b)
	p: Probe
	probe_init(&p, board, &b, {100, 50})
	defer probe_destroy(&p)
	router_push(&p.router, {kind = .Paste, text = "stray", mime = TEXT_MIME})
	probe_frame(&p)
	testing.expect_value(t, b.pasted, [2]string{})
}

@(test)
test_focus_request_moves_focus_at_the_next_route :: proc(t: ^testing.T) {
	b: Board
	defer board_destroy(&b)
	p: Probe
	probe_init(&p, board, &b, {100, 50})
	defer probe_destroy(&p)
	probe_click(&p, "a")
	testing.expect_value(t, p.router.focus, ops.Area_Id(101))
	b.focus_b = true
	probe_frame(&p) // asks
	probe_frame(&p) // granted, before this frame's events are routed
	testing.expect_value(t, p.router.focus, ops.Area_Id(102))
	blurred, focused := false, false
	for e in b.events[0] {
		blurred |= e.kind == .Blur
	}
	for e in b.events[1] {
		focused |= e.kind == .Focus
	}
	testing.expect(t, blurred && focused, "a is blurred and b focused, as a press would")
}

@(test)
test_focus_is_visible_from_a_key_until_the_next_press :: proc(t: ^testing.T) {
	b: Board
	defer board_destroy(&b)
	p: Probe
	probe_init(&p, board, &b, {100, 50})
	defer probe_destroy(&p)
	testing.expect(t, !p.router.keyboard)
	probe_click(&p, "a")
	testing.expect(t, !p.router.keyboard)
	probe_key(&p, .Tab)
	testing.expect(t, p.router.keyboard)
	probe_frame(&p)
	testing.expect(t, p.router.keyboard) // a frame without input keeps it
	probe_click(&p, "b")
	testing.expect(t, !p.router.keyboard)
}

@(test)
test_press_carries_the_os_click_count :: proc(t: ^testing.T) {
	b: Board
	defer board_destroy(&b)
	p: Probe
	probe_init(&p, board, &b, {100, 50})
	defer probe_destroy(&p)
	router_push(&p.router, {kind = .Press, pos = {10, 10}, clicks = 2})
	router_push(&p.router, {kind = .Release, pos = {10, 10}, clicks = 2})
	probe_frame(&p)
	testing.expect_value(t, b.clicks, 2)
}

@(test)
test_cursor_is_the_topmost_areas :: proc(t: ^testing.T) {
	f: Frame
	frame_init(&f)
	defer frame_destroy(&f)
	// Text under a button: over the button the arrow shows, since the
	// topmost area decides and the button set none.
	append(&f.hits, Hit{area = 1, kinds = {.Press}, shape = ops.Rect{0, 0, 100, 100}, transform = ops.IDENTITY, clip = NO_CLIP, cursor = .Text})
	append(&f.hits, Hit{area = 2, kinds = {.Press, .Release}, shape = ops.Rect{0, 0, 20, 20}, transform = ops.IDENTITY, clip = NO_CLIP, order = 1})
	r: Router
	router_init(&r)
	defer router_destroy(&r)
	router_route(&r, &f)
	testing.expect_value(t, router_cursor(&r), ops.Cursor.Default) // no pointer yet
	router_push(&r, {kind = .Move, pos = {50, 50}})
	router_route(&r, &f)
	testing.expect_value(t, router_cursor(&r), ops.Cursor.Text)
	router_push(&r, {kind = .Move, pos = {10, 10}})
	router_route(&r, &f)
	testing.expect_value(t, router_cursor(&r), ops.Cursor.Default)
	router_push(&r, {kind = .Move, pos = {500, 500}})
	router_route(&r, &f)
	testing.expect_value(t, router_cursor(&r), ops.Cursor.Default)
}

@(test)
test_a_grab_keeps_its_cursor :: proc(t: ^testing.T) {
	f: Frame
	frame_init(&f)
	defer frame_destroy(&f)
	append(&f.hits, Hit{area = 1, kinds = {.Press, .Release, .Move}, shape = ops.Rect{0, 0, 20, 20}, transform = ops.IDENTITY, clip = NO_CLIP, cursor = .Resize_EW})
	r: Router
	router_init(&r)
	defer router_destroy(&r)
	router_push(&r, {kind = .Press, pos = {10, 10}})
	router_push(&r, {kind = .Move, pos = {300, 10}}) // dragged well off the handle
	router_route(&r, &f)
	testing.expect_value(t, router_cursor(&r), ops.Cursor.Resize_EW)
	router_push(&r, {kind = .Release, pos = {300, 10}})
	router_route(&r, &f)
	testing.expect_value(t, router_cursor(&r), ops.Cursor.Default)
}

@(test)
test_clearing_requests_releases_their_copies :: proc(t: ^testing.T) {
	da: jdebug.Allocator
	jdebug.init(&da, context.allocator)
	defer jdebug.destroy(&da)
	r: Router
	router_init(&r, jdebug.allocator(&da))
	defer router_destroy(&r)
	ctx := Ctx{router = &r}
	// The queues' own storage lives as long as the router; the claim is
	// about what each request copies.
	reserve(&r.requests, 4)
	reserve(&r.readers, 4)
	before := jdebug.snapshot(&da)
	clipboard_write(&ctx, "one")
	clipboard_write(&ctx, "two") // replaces one, freeing it
	clipboard_read(&ctx, 7)
	testing.expect_value(t, len(router_requests(&r)), 2)
	router_requests_clear(&r)
	clear(&r.readers)
	testing.expect(t, jdebug.expect_released(&da, before), "every request's copies are freed")
	testing.expect_value(t, jdebug.issue_count(&da), 0)
}
