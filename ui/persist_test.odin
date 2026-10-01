package ui

import "core:strings"
import "core:testing"

@(private = "file")
Mode :: enum u8 {
	Light,
	Dark,
}

@(private = "file")
Session :: struct {
	page:   int,
	dark:   bool,
	mode:   Mode,
	zoom:   f32,
	title:  string,
	scroll: [3]Scroll_Offset,
	count:  u16,
	skip:   []int, // not a persistable kind: never written, never read
}

@(private = "file")
Session_Model :: struct {
	s:        Session,
	restored: bool,
	frames:   int,
}

@(private = "file")
session_view :: proc(gtx: ^Ctx, user: rawptr) {
	m := (^Session_Model)(user)
	if restore_struct(gtx, &m.s, context.temp_allocator) {
		m.restored = true
	}
	m.frames += 1
	persist_struct(gtx, m.s)
}

@(test)
persist_struct_writes_keyed_lines_and_restore_reads_them :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	m: Session_Model
	m.s = {page = 3, dark = true, mode = .Dark, zoom = 1.5, title = "Settings \"q\"", count = 7}
	m.s.scroll[1] = {0, 240}
	p: Probe
	probe_init(&p, session_view, &m, {100, 100})
	defer probe_destroy(&p)
	text := string(probe_persisted(&p))
	testing.expect_value(t, text, "page 3\ndark true\nmode Dark\nzoom 1.5\ntitle \"Settings \\\"q\\\"\"\nscroll[0].x 0\nscroll[0].y 0\nscroll[1].x 0\nscroll[1].y 240\nscroll[2].x 0\nscroll[2].y 0\ncount 7\n")

	// A fresh model restored from that text has every field back.
	fresh: Session_Model
	q: Probe
	probe_init(&q, session_view, &fresh, {100, 100})
	defer probe_destroy(&q)
	testing.expect(t, !fresh.restored)
	probe_restore(&q, transmute([]byte)text)
	probe_frame(&q)
	testing.expect(t, fresh.restored)
	testing.expect_value(t, fresh.s.page, 3)
	testing.expect_value(t, fresh.s.dark, true)
	testing.expect_value(t, fresh.s.mode, Mode.Dark)
	testing.expect_value(t, fresh.s.zoom, f32(1.5))
	testing.expect_value(t, fresh.s.title, "Settings \"q\"")
	testing.expect_value(t, fresh.s.scroll[1], Scroll_Offset{0, 240})
	testing.expect_value(t, fresh.s.count, u16(7))
	// Restore is for one frame only.
	probe_frame(&q)
	testing.expect_value(t, fresh.frames, 3)
}

@(test)
persist_struct_sends_only_changes :: proc(t: ^testing.T) {
	m: Session_Model
	p: Probe
	probe_init(&p, session_view, &m, {100, 100})
	defer probe_destroy(&p)
	testing.expect(t, strings.has_prefix(string(probe_persisted(&p)), "page 0\n"))
	testing.expect_value(t, p.persists, 1)
	probe_frame(&p) // the same session: nothing sent
	testing.expect_value(t, p.persists, 1)
	m.s.page = 2
	probe_frame(&p)
	testing.expect_value(t, p.persists, 2)
	testing.expect(t, strings.has_prefix(string(probe_persisted(&p)), "page 2\n"))
}

@(test)
restore_struct_survives_a_blob_from_another_build :: proc(t: ^testing.T) {
	m: Session_Model
	m.s = {page = 1, zoom = 2}
	p: Probe
	probe_init(&p, session_view, &m, {100, 100})
	defer probe_destroy(&p)
	// An old field, a renamed one, a bad value, a bad index and a bad
	// path: each skipped, and the rest still lands.
	probe_restore(&p, transmute([]byte)string("gone 5\npage x\nscroll[9].y 1\nscroll[0].z 1\nzoom.x 3\nmode Dusk\ndark true\nscroll[2].y 12"))
	probe_frame(&p)
	testing.expect_value(t, m.s.page, 1) // kept: "x" is not a page
	testing.expect_value(t, m.s.zoom, f32(2))
	testing.expect_value(t, m.s.mode, Mode.Light)
	testing.expect_value(t, m.s.dark, true)
	testing.expect_value(t, m.s.scroll[2].y, f32(12))
}
