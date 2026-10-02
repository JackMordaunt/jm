package primer

import "core:testing"
import "jm:ui"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

@(test)
test_a_hint_sorts_modifiers_first_and_keeps_the_rest_in_order :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	chords, lens, n := hint_chords("Shift+K+Control g Mod+Alt+i")
	testing.expect_value(t, n, 3)
	testing.expect_value(t, lens[0], 3)
	testing.expect_value(t, chords[0][0], "control")
	testing.expect_value(t, chords[0][1], "shift")
	testing.expect_value(t, chords[0][2], "k")
	testing.expect_value(t, chords[1][0], "g")
	// mod has no priority, so it stays among the other keys, after alt.
	testing.expect_value(t, chords[2][0], "alt")
	testing.expect_value(t, chords[2][1], "mod")
	testing.expect_value(t, chords[2][2], "i")
}

@(test)
test_keys_are_named_per_platform_as_key_names_ts_says :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	testing.expect_value(t, key_label("mod", .Condensed, .Apple), "⌘")
	testing.expect_value(t, key_label("mod", .Condensed, .Windows), "⌃") // ⌃ everywhere but apple
	testing.expect_value(t, key_label("meta", .Condensed, .Windows), "Win")
	testing.expect_value(t, key_label("meta", .Full, .Other), "Meta")
	testing.expect_value(t, key_label("alt", .Full, .Apple), "Option")
	testing.expect_value(t, key_label("arrowup", .Condensed), "↑")
	testing.expect_value(t, key_label("pagedown", .Full), "Page Down")
	testing.expect_value(t, key_label("k", .Condensed), "K")
	testing.expect_value(t, key_label("escape", .Condensed), "Esc")
	testing.expect_value(t, spoken_hint("Mod+Shift+/ g i", .Apple), "shift command forward slash then g then i") // mod sorts after the ranked modifiers
	testing.expect_value(t, spoken_hint("Alt+.", .Windows), "alt period")
}

@(private = "file")
Links :: struct {
	opened, picked: int,
}

@(private = "file")
links_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Links)(user)
	col := ui.column_open(gtx, gap = 12, align = .Start)
	defer ui.close(&col)
	if link(gtx, "Open the issue") {
		m.opened += 1
	}
	keybinding_hint(gtx, "Mod+K", key = 1)
	keybinding_hint(gtx, "Mod+K", size = .Small, key = 2)
	box := ui.sized_open(gtx, {max = {160, ui.INF}})
	defer ui.close(&box)
	text := "See the contributing guide for how a change is reviewed before merge."
	if i := prose(gtx, text, {{8, 34}}); i >= 0 {
		m.picked = i + 1
	}
}

@(test)
test_a_link_activates_and_a_prose_link_is_hit_on_every_line :: proc(t: ^testing.T) {
	m: Links
	p: ui.Probe
	ui.probe_init(&p, links_view, &m, {400, 300}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect(t, ui.probe_click(&p, "Open the issue"))
	testing.expect_value(t, m.opened, 1)
	ui.probe_key(&p, .Enter)
	testing.expect_value(t, m.opened, 2)
	// "contributing guide for how a" wraps at 160px: the one link has a hit
	// area on each line it reaches, under one id; nothing else has two.
	f := ui.probe_current(&p)
	tops := make([dynamic]f32, context.temp_allocator)
	for h in f.hits {
		n := 0
		for g in f.hits {
			n += int(g.area == h.area)
		}
		if n >= 2 {
			r := h.shape.(ops.Rect)
			append(&tops, r.y + f32(h.transform.f))
		}
	}
	testing.expect_value(t, len(tops), 2) // one link, two fragments
	if len(tops) == 2 {
		testing.expect(t, tops[1] > tops[0] + 10, "the fragments are on different lines")
	}
}

@(test)
test_hint_caps_are_the_css_sizes :: proc(t: ^testing.T) {
	gtx_probe: ui.Probe
	view :: proc(gtx: ^ui.Ctx, user: rawptr) {}
	ui.probe_init(&gtx_probe, view, nil, {10, 10}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&gtx_probe)
	defer free_all(context.temp_allocator)
	gtx := ui.Ctx{shaper = gtx_probe.shaper, allocator = context.temp_allocator}
	normal := layout_hint(&gtx, "K", .Condensed, .Normal, .Normal)
	testing.expect_value(t, normal.size.y, 20) // 10px line, 4px padding, 1px border
	testing.expect(t, normal.widths[0] >= tok.BASE_SIZE_20) // a single key is at least square
	small := layout_hint(&gtx, "K", .Condensed, .Normal, .Small)
	testing.expect_value(t, small.size.y, 14)
	testing.expect(t, small.widths[0] >= tok.BASE_SIZE_16)
	seq := layout_hint(&gtx, "g i", .Condensed, .Normal, .Normal)
	testing.expect_value(t, seq.n, 2)
	testing.expect_value(t, seq.size.x, seq.widths[0] + seq.space + seq.widths[1])
	full := layout_hint(&gtx, "Mod+K", .Full, .Normal, .Normal)
	cond := layout_hint(&gtx, "Mod+K", .Condensed, .Normal, .Normal)
	testing.expect(t, full.widths[0] > cond.widths[0]) // words and a + are wider than symbols
}
