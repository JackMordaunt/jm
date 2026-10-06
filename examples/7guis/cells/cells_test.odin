package main

import "core:fmt"
import "core:log"
import "core:testing"

import "jm:ui"

SIZE :: [2]f32{720, 480}

@(private = "file")
open :: proc(m: ^Model) -> ui.Probe {
	model_init(m)
	p: ui.Probe
	ui.probe_init(&p, view, m, SIZE)
	return p
}

// type_into double-clicks a cell, types text over its source and ends
// with key.
@(private = "file")
type_into :: proc(p: ^ui.Probe, name, text: string, key := ui.Key.Enter) {
	ui.probe_click(p, name, clicks = 2)
	ui.probe_frame(p) // the editor takes focus
	ui.probe_key(p, .A, {ui.SHORTCUT})
	ui.probe_type(p, text)
	ui.probe_key(p, key)
	ui.probe_frame(p)
}

@(test)
a_double_click_edits_and_enter_keeps_it :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := open(&m)
	defer ui.probe_destroy(&p)

	type_into(&p, "A0", "5")
	type_into(&p, "B0", "=A0 * 2")
	testing.expect_value(t, shown(m.sheet, {1, 0}), "10")
	testing.expect(t, m.editing == nil)

	// Re-editing shows the source, not the value.
	ui.probe_click(&p, "B0", clicks = 2)
	ui.probe_frame(&p)
	testing.expect_value(t, ui.text_string(&m.edit), "=A0 * 2")
	ui.probe_key(&p, .Escape)
	ui.probe_frame(&p)

	type_into(&p, "A0", "21")
	testing.expect_value(t, shown(m.sheet, {1, 0}), "42")
}

@(test)
escape_drops_the_edit_and_a_click_elsewhere_keeps_it :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := open(&m)
	defer ui.probe_destroy(&p)

	type_into(&p, "A1", "7", .Escape)
	testing.expect_value(t, m.sheet.source[1][0], "")
	testing.expect(t, m.editing == nil)

	ui.probe_click(&p, "A1", clicks = 2)
	ui.probe_frame(&p)
	ui.probe_type(&p, "8")
	ui.probe_click(&p, "C3")
	ui.probe_frame(&p)
	testing.expect_value(t, m.sheet.source[1][0], "8")

	// A double click on another cell keeps this edit and starts that one.
	ui.probe_click(&p, "A1", clicks = 2)
	ui.probe_frame(&p)
	ui.probe_key(&p, .A, {ui.SHORTCUT})
	ui.probe_type(&p, "9")
	ui.probe_click(&p, "A0", clicks = 2)
	ui.probe_frame(&p)
	testing.expect_value(t, m.sheet.source[1][0], "9")
	testing.expect(t, m.editing == Cell{0, 0})
}

@(test)
the_sheet_scrolls_down_to_its_last_row :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := open(&m)
	defer ui.probe_destroy(&p)

	testing.expect(t, ui.probe_bounds(&p, "A99").y > SIZE.y) // laid out, below the window
	for _ in 0 ..< 100 {
		ui.router_push(&p.router, {kind = .Scroll, pos = SIZE / 2, scroll = {0, 10}})
		ui.probe_frame(&p)
	}
	last := ui.probe_bounds(&p, "A99")
	testing.expect(t, last.y > 0 && last.y + last.h <= SIZE.y)
}

// A frame lays out all 2,727 cells, so it must stay cheap. What a frame
// costs is what it records for each cell, so this counts that rather
// than timing it, which a loaded machine can stretch past any bound.
@(test)
a_frame_of_the_whole_sheet_is_cheap :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := open(&m)
	defer ui.probe_destroy(&p)
	for r in 0 ..< ROWS {
		for c in 0 ..< COLS {
			sheet_set(m.sheet, {c, r}, fmt.tprint(r * COLS + c))
		}
	}

	ui.probe_frame(&p)
	first := p.tray.last
	ui.probe_frame(&p)
	s := p.tray.last
	log.infof("frame: %v", s)
	WIDGETS :: (ROWS + 1) * (COLS + 1)
	testing.expectf(t, s.ops <= 16 * WIDGETS, "%d ops for %d widgets", s.ops, WIDGETS)
	testing.expectf(t, s.draws <= 4 * WIDGETS, "%d draws for %d widgets", s.draws, WIDGETS)
	testing.expectf(t, s.hits <= WIDGETS, "%d hit areas for %d widgets", s.hits, WIDGETS)
	testing.expectf(t, s.arena_bytes <= 128 * WIDGETS, "%d arena bytes", s.arena_bytes)
	testing.expectf(t, s.states + s.data <= 8, "%d retained states", s.states + s.data)
	// A frame like the one before costs the same: nothing accumulates.
	testing.expect_value(t, s.ops, first.ops)
	testing.expect_value(t, s.arena_bytes, first.arena_bytes)
}
