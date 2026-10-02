package primer

import "core:strings"
import "core:testing"
import "jm:ui"
import "jm:ui/design"
import tok "jm:ui/primer/tokens"

// Heading, Text and Truncate, measured through probes. The probe's stub
// shaper advances every rune 0.6 of the font size.

@(private = "file")
width_of :: proc(p: ^ui.Probe, s: string, st: tok.Type_Style) -> f32 {
	gtx := ui.Ctx{shaper = p.shaper, allocator = context.temp_allocator}
	return design.shape_style(&gtx, s, st, font_for(&gtx, st.weight)).width
}

@(private = "file")
headings :: proc(gtx: ^ui.Ctx, user: rawptr) {
	col := ui.column_open(gtx, gap = 8)
	defer ui.close(&col)
	heading(gtx, "Title")
	heading(gtx, "Small", level = 3, variant = .Small)
	heading(gtx, "Medium", level = 9, variant = .Medium)
	heading(gtx, "")
	box := ui.sized_open(gtx, {max = {100, 0}})
	defer ui.close(&box)
	heading(gtx, "A heading long enough to wrap", variant = .Small)
}

@(test)
test_heading_sets_the_title_presets_and_tells_its_level :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	p: ui.Probe
	ui.probe_init(&p, headings, nil, {600, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	title := ui.probe_bounds(&p, "Title")
	testing.expect_value(t, title.h, 48) // 32px at the page's 1.5
	testing.expect_value(t, title.w, width_of(&p, "Title", heading_style(.Default)))
	testing.expect_value(t, ui.probe_bounds(&p, "Small").h, tok.TEXT_TITLE_SHORTHAND_SMALL.line_height) // 24
	testing.expect_value(t, ui.probe_bounds(&p, "Medium").h, tok.TEXT_TITLE_SHORTHAND_MEDIUM.line_height) // 32.5
	// 8px apart: the empty heading took no space, not even a gap's worth of line.
	testing.expect_value(t, ui.probe_bounds(&p, "Medium").y, 48 + 8 + 24 + 8)
	wrapped := ui.probe_bounds(&p, "A heading long enough to wrap")
	testing.expect(t, wrapped.w <= 100)
	testing.expect_value(t, wrapped.h, 4 * tok.TEXT_TITLE_SHORTHAND_SMALL.line_height) // 9.6px a rune: ten fit a line
	sem := ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(t, strings.contains(sem, "heading \"Title\" level 2 at"), sem) // h2 by default
	testing.expect(t, strings.contains(sem, "heading \"Small\" level 3 at"), sem)
	testing.expect(t, strings.contains(sem, "heading \"Medium\" level 6 at"), sem) // past h6 is h6
}

@(private = "file")
texts :: proc(gtx: ^ui.Ctx, user: rawptr) {
	col := ui.column_open(gtx)
	defer ui.close(&col)
	text(gtx, "small", .Small)
	text(gtx, "medium")
	text(gtx, "large", .Large, .Semibold)
	box := ui.sized_open(gtx, {max = {60, 0}})
	defer ui.close(&box)
	inner := ui.column_open(gtx)
	defer ui.close(&inner)
	text(gtx, "wraps  at  sixty", key = 1)
	text(gtx, "never  wraps  here", white_space = .Nowrap, key = 2)
	text(gtx, "two\nlines   kept", white_space = .Pre, key = 3)
}

@(test)
test_text_sizes_and_white_space :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	p: ui.Probe
	ui.probe_init(&p, texts, nil, {600, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	testing.expect_value(t, ui.probe_bounds(&p, "small").h, 19.5)
	testing.expect_value(t, ui.probe_bounds(&p, "medium").h, 21)
	testing.expect_value(t, ui.probe_bounds(&p, "large").h, 24)
	// Normal collapses the double spaces and wraps at 60px, seven runes of
	// 8.4px: "wraps", "at", "sixty".
	testing.expect(t, ui.probe_tagged(&p, "wraps at sixty"))
	testing.expect_value(t, ui.probe_bounds(&p, "wraps at sixty").h, 3 * 21)
	// Nowrap collapses too but keeps one line, clipped to the box.
	nowrap := ui.probe_bounds(&p, "never wraps here")
	testing.expect_value(t, nowrap.h, 21)
	testing.expect_value(t, nowrap.w, 60)
	// Pre keeps the spaces and the break, and does not wrap.
	testing.expect_value(t, ui.probe_bounds(&p, "two\nlines   kept").h, 2 * 21)
}

@(private = "file")
Truncate_Model :: struct {
	clicks: int,
}

@(private = "file")
truncates :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Truncate_Model)(user)
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	truncate(gtx, "short")
	truncate(gtx, "a branch name far too long to show", title = "the full branch name")
	truncate(gtx, "tiny", inline = true, key = 1)
	truncate(gtx, "an inline name far too long", inline = true, key = 2)
	// A button under an expandable name keeps its hover.
	s := ui.stack_open(gtx)
	defer ui.close(&s)
	if button(gtx, "Go", .Invisible, block = true) {
		m.clicks += 1
	}
	truncate(gtx, "expands to show the whole of this", expandable = true, inline = true, key = 3)
}

@(test)
test_truncate_cuts_one_line_and_expands_on_hover_alone :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	m: Truncate_Model
	p: ui.Probe
	ui.probe_init(&p, truncates, &m, {600, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	body := text_style()
	// A block fills its parent up to 125px; inline hugs its text up to it.
	testing.expect_value(t, ui.probe_bounds(&p, "short").w, TRUNCATE_MAX_WIDTH)
	testing.expect_value(t, ui.probe_bounds(&p, "a branch name far too long to show").w, TRUNCATE_MAX_WIDTH)
	testing.expect_value(t, ui.probe_bounds(&p, "tiny").w, width_of(&p, "tiny", body))
	long := ui.probe_bounds(&p, "an inline name far too long")
	testing.expect_value(t, long.w, TRUNCATE_MAX_WIDTH)
	testing.expect_value(t, long.h, body.line_height) // one line
	ellipses := 0
	for run in p.scene.runs {
		for g in run.glyphs {
			if g.id == u32('…') {
				ellipses += 1
			}
		}
	}
	testing.expect_value(t, ellipses, 3) // the two long ones and the unexpanded one
	sem := ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(t, strings.contains(sem, "text \"a branch name far too long to show\" desc \"the full branch name\""), sem)

	// Hovering the expandable one lifts its cap; the button under it
	// still has the hover and the click.
	exp := ui.probe_bounds(&p, "expands to show the whole of this")
	testing.expect_value(t, exp.w, TRUNCATE_MAX_WIDTH)
	ui.probe_move(&p, exp.x + 10, exp.y + 5)
	ui.probe_frame(&p)
	full := width_of(&p, "expands to show the whole of this", body)
	testing.expect_value(t, ui.probe_bounds(&p, "expands to show the whole of this").w, full)
	go, _ := ui.probe_find(&p, "Go")
	testing.expect_value(t, p.router.hover, go.area)
	testing.expect(t, ui.probe_click(&p, "Go"))
	testing.expect_value(t, m.clicks, 1)
	// Leaving collapses it again.
	ui.probe_move(&p, 590, 390)
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_bounds(&p, "expands to show the whole of this").w, TRUNCATE_MAX_WIDTH)
}

@(test)
test_truncate_never_expands_wider_than_it_is_offered :: proc(t: ^testing.T) {
	view :: proc(gtx: ^ui.Ctx, user: rawptr) {
		col := ui.column_open(gtx) // loosens the window's exact size
		defer ui.close(&col)
		box := ui.sized_open(gtx, {max = {200, 0}})
		defer ui.close(&box)
		truncate(gtx, "expands to show the whole of this and more", expandable = true, inline = true)
	}
	defer free_all(context.temp_allocator)
	p: ui.Probe
	ui.probe_init(&p, view, nil, {600, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	r := ui.probe_bounds(&p, "expands to show the whole of this and more")
	testing.expect_value(t, r.w, TRUNCATE_MAX_WIDTH) // inline, cut at 125 before the hover
	ui.probe_move(&p, r.x + 5, r.y + 5)
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_bounds(&p, "expands to show the whole of this and more").w, 200)
}
