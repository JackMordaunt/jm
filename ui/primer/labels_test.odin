package primer

import "core:fmt"
import "core:strings"
import "core:testing"
import "jm:ui"
import "jm:ui/design"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// Behaviour of the label family, driven through ui.Probe by tags.

@(private = "file")
shaped :: proc(p: ^ui.Probe, s: string, st: tok.Type_Style) -> Text {
	gtx := ui.Ctx{shaper = p.shaper, allocator = context.temp_allocator}
	return design.shape_style(&gtx, s, st, font_for(&gtx, st.weight))
}

@(private = "file")
solid :: proc(p: ops.Paint, c: ops.Color) -> bool {
	got, ok := p.(ops.Color)
	return ok && got == c
}

// fills_of counts the scene's fills in c.
@(private)
fills_of :: proc(p: ^ui.Probe, c: ops.Color) -> (n: int) {
	for op in p.scene.ops {
		if f, ok := op.(ops.Fill); ok && solid(f.paint, c) {
			n += 1
		}
	}
	return
}

// strokes_of counts the scene's strokes in c.
@(private = "file")
strokes_of :: proc(p: ^ui.Probe, c: ops.Color) -> (n: int) {
	for op in p.scene.ops {
		if s, ok := op.(ops.Stroke); ok && solid(s.paint, c) {
			n += 1
		}
	}
	return
}

@(private = "file")
Statics :: struct {}

@(private = "file")
statics :: proc(gtx: ^ui.Ctx, user: rawptr) {
	col := ui.column_open(gtx, gap = 8)
	defer ui.close(&col)
	label(gtx, "Beta")
	label(gtx, "Private", .Primary, .Large)
	state_label(gtx, "Merged", .Pull_Merged)
	state_label(gtx, "Open", .Open, .Small)
	state_label(gtx, "Fixed", .Alert_Fixed, .Small)
	issue_label(gtx, "bug", .Red)
	topic_tag(gtx, "odin", .Span)
	branch_name(gtx, "main", false)
	circle_badge(gtx, .Rocket, "Launch", .Small)
}

@(test)
test_static_labels_follow_the_css_geometry :: proc(t: ^testing.T) {
	p: ui.Probe
	ui.probe_init(&p, statics, nil, {600, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	small := tok.Type_Style{weight = tok.BASE_TEXT_WEIGHT_MEDIUM, size = 12, line_height = 12}
	beta := ui.probe_bounds(&p, "Beta")
	testing.expect_value(t, beta.h, 20)
	testing.expect_value(t, beta.w, shaped(&p, "Beta", small).width + 2 * 6)
	private := ui.probe_bounds(&p, "Private")
	testing.expect_value(t, private.h, 24)
	testing.expect_value(t, private.w, shaped(&p, "Private", small).width + 2 * 8)

	// StateLabel: padding around a 16px line; the icon 4px before the text.
	medium := tok.Type_Style{weight = tok.BASE_TEXT_WEIGHT_SEMIBOLD, size = 14, line_height = 16}
	merged := ui.probe_bounds(&p, "Merged")
	testing.expect_value(t, merged.h, 32)
	testing.expect_value(t, merged.w, 2 * 12 + 16 + 4 + shaped(&p, "Merged", medium).width)
	semi12 := tok.Type_Style{weight = tok.BASE_TEXT_WEIGHT_SEMIBOLD, size = 12, line_height = 16}
	open := ui.probe_bounds(&p, "Open")
	testing.expect_value(t, open.h, 24)
	testing.expect_value(t, open.w, 2 * 8 + shaped(&p, "Open", semi12).width) // open has no icon
	fixed := ui.probe_bounds(&p, "Fixed")
	testing.expect_value(t, fixed.w, 2 * 8 + 12 + 4 + shaped(&p, "Fixed", semi12).width) // a 12px icon at small

	testing.expect_value(t, ui.probe_bounds(&p, "bug").h, 20) // 19.5px line, 20px minimum
	testing.expect_value(t, ui.probe_bounds(&p, "odin").h, 12 * 1.625 + 2 * 2 + 2) // 25.5
	testing.expect_value(t, ui.probe_bounds(&p, "main").h, 18 + 2 * 2) // an 18px line in 2px padding
	launch := ui.probe_bounds(&p, "Launch")
	testing.expect_value(t, launch, ops.Rect{launch.x, launch.y, 56, 56})
}

@(test)
test_a_state_label_says_the_object_before_its_state :: proc(t: ^testing.T) {
	p: ui.Probe
	ui.probe_init(&p, statics, nil, {600, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	sem := ui.probe_semantics(&p, context.temp_allocator)
	testing.expectf(t, strings.contains(sem, `"Pull request Merged"`), "semantics: %s", sem)
	testing.expectf(t, strings.contains(sem, `"Open"`), "open has no icon, so no object: %s", sem)
	// closed and issueClosed are done, not closed (state-label.json notes).
	testing.expect_value(t, state_look(.Closed).fill, tok.Role.Bg_Color_Done_Emphasis)
	testing.expect_value(t, state_look(.Pull_Closed).fill, tok.Role.Bg_Color_Closed_Emphasis)
	testing.expect_value(t, state_look(.Unavailable).name, "")
}

@(test)
test_a_hex_label_reads_black_or_white_by_wcag_luminance :: proc(t: ^testing.T) {
	BLACK :: ops.Color{0, 0, 0, 255}
	WHITE :: ops.Color{255, 255, 255, 255}
	testing.expect_value(t, readable_text(ops.rgba(0xffffffff)), BLACK)
	testing.expect_value(t, readable_text(ops.rgba(0x000000ff)), WHITE)
	// The threshold, 0.179, between two greys: 0x76 is 0.1812, 0x75 0.1779.
	testing.expect_value(t, readable_text(ops.rgba(0x767676ff)), BLACK)
	testing.expect_value(t, readable_text(ops.rgba(0x757575ff)), WHITE)
	// GitHub's bug red is 0.1797, just above: black, not white.
	testing.expect_value(t, readable_text(ops.rgba(0xd73a4aff)), BLACK)
	testing.expect_value(t, readable_text(ops.rgba(0x0075caff)), WHITE)
}

@(test)
test_hsl_rounds_as_the_css_variables_do :: proc(t: ^testing.T) {
	testing.expect_value(t, to_hsl(ops.rgba(0xd73a4aff)), HSL{354, 66, 54})
	testing.expect_value(t, to_hsl(ops.rgba(0xa2eeefff)), HSL{181, 71, 79})
	testing.expect_value(t, to_hsl(ops.rgba(0x808080ff)), HSL{0, 0, 50})
	testing.expect_value(t, from_hsl({354, 66, 49}), ops.Color{207, 42, 59, 255})
	testing.expect_value(t, from_hsl({0, 0, 120}), ops.Color{255, 255, 255, 255}) // lightness clamps
	testing.expect_value(t, from_hsl({0, 0, -5}), ops.Color{0, 0, 0, 255})
	// At exactly the threshold CSS's 1/0 is infinity, clamped to 1.
	testing.expect_value(t, lightness_switch(0.453, 0.453), 1)
	testing.expect_value(t, lightness_switch(0.5, 0.453), 0)
	testing.expect_value(t, lightness_switch(0.452, 0.453), 1)
}

@(test)
test_issue_label_token_colours_follow_the_light_and_dark_formulas :: proc(t: ^testing.T) {
	red := ops.rgba(0xd73a4aff) // P 0.363, hsl(354, 66%, 54%)
	lk := issue_label_token_look(red, .Light, false, false)
	testing.expect_value(t, lk.fill, red)
	testing.expect_value(t, lk.text, ops.Color{255, 255, 255, 255}) // below 0.453: white
	testing.expect_value(t, lk.border[3], 0) // only near white gets a border
	sel := issue_label_token_look(red, .Light, true, false)
	testing.expect_value(t, sel.fill, ops.Color{207, 42, 59, 255}) // hsl(354, 66%, 49%)
	testing.expect_value(t, sel.ring, red)
	hov := issue_label_token_look(red, .Light, false, true)
	testing.expect_value(t, hov.fill, ops.mix(red, {0, 0, 0, 255}, 0.15))
	testing.expect(t, hov.lift)

	cyan := ops.rgba(0xa2eeefff) // P 0.870: black text in light
	testing.expect_value(t, issue_label_token_look(cyan, .Light, false, false).text, ops.Color{0, 0, 0, 255})
	near_white := issue_label_token_look(ops.rgba(0xfefefeff), .Light, false, false)
	testing.expect_value(t, near_white.border, ops.Color{191, 191, 191, 255}) // hsl(0, 0%, 75%), alpha 1

	dark := issue_label_token_look(red, .Dark, false, false)
	testing.expect_value(t, dark.fill, ops.Color{0xd7, 0x3a, 0x4a, 46}) // 18%
	testing.expect_value(t, dark.text, ops.Color{236, 161, 168, 255}) // l 54 + (0.6 - 0.363) x 100
	testing.expect_value(t, dark.border, ops.Color{236, 161, 168, 77}) // the text at 30%
	testing.expect_value(t, issue_label_token_look(red, .Dark, true, false).ring, dark.text)
	testing.expect_value(t, issue_label_token_look(red, .Dark, false, true).fill, ops.Color{224, 103, 115, 77})
	// Above 0.6 the switch is 0: the text is the fill's own lightness.
	testing.expect_value(t, issue_label_token_look(cyan, .Dark, false, false).text, from_hsl({181, 71, 79}))
}

@(private = "file")
Clicks :: struct {
	bugs, links, branches, spans, texts: int,
}

@(private = "file")
clickables :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Clicks)(user)
	col := ui.column_open(gtx, gap = 8)
	defer ui.close(&col)
	if issue_label(gtx, "bug", .Red, interactive = true) {
		m.bugs += 1
	}
	if topic_tag(gtx, "react") {
		m.links += 1
	}
	if topic_tag(gtx, "odin", .Span) {
		m.spans += 1
	}
	if branch_name(gtx, "main") {
		m.branches += 1
	}
	if branch_name(gtx, "dev", false) {
		m.texts += 1
	}
	issue_label(gtx, "static", .Blue)
}

@(test)
test_interactive_labels_activate_by_pointer_and_keyboard :: proc(t: ^testing.T) {
	m: Clicks
	p: ui.Probe
	ui.probe_init(&p, clickables, &m, {400, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect(t, ui.probe_click(&p, "bug"))
	testing.expect_value(t, m.bugs, 1)
	ui.probe_key(&p, .Enter)
	testing.expect_value(t, m.bugs, 2)
	testing.expect(t, ui.probe_click(&p, "react"))
	ui.probe_key(&p, .Space)
	testing.expect_value(t, m.links, 2)
	testing.expect(t, ui.probe_click(&p, "main"))
	testing.expect_value(t, m.branches, 1)
	// A span tag, a text branch and a static issue label take no click.
	testing.expect(t, ui.probe_click(&p, "odin")) // a hover-only area answers
	testing.expect_value(t, m.spans, 0)
	ui.probe_click(&p, "dev") // a text branch and a static label are tagged, but take no input
	testing.expect_value(t, m.texts, 0)
	testing.expect(t, ui.probe_tagged(&p, "static"))
}

@(test)
test_a_span_topic_tag_still_fills_on_hover :: proc(t: ^testing.T) {
	m: Clicks
	p: ui.Probe
	ui.probe_init(&p, clickables, &m, {400, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	before := fills_of(&p, color(.Bg_Color_Accent_Emphasis))
	c, _ := ui.probe_center(&p, "odin")
	ui.probe_move(&p, c.x, c.y)
	ui.probe_frame(&p)
	testing.expect_value(t, fills_of(&p, color(.Bg_Color_Accent_Emphasis)), before + 1)
}

@(test)
test_an_issue_labels_focus_outline_sits_2px_outside :: proc(t: ^testing.T) {
	m: Clicks
	p: ui.Probe
	ui.probe_init(&p, clickables, &m, {400, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	ui.probe_click(&p, "bug")
	ui.probe_frame(&p)
	testing.expect_value(t, strokes_of(&p, color(.Focus_Outline_Color)), 0) // a click shows no outline
	ui.probe_key(&p, .Tab) // jm:ui has no Tab traversal: a key turns focus visible
	ui.probe_frame(&p)
	bug := ui.probe_bounds(&p, "bug")
	found := false
	for op in p.scene.ops {
		s, ok := op.(ops.Stroke)
		if !ok || !solid(s.paint, color(.Focus_Outline_Color)) {
			continue
		}
		found = true
		r := ops.shape_bounds(&p.scene, s.shape)
		// The stroke's centre line is 1px into a 2px outline whose inner
		// edge is 2px outside the pill: 3px out.
		testing.expect_value(t, r.w, bug.w + 2 * 3)
		testing.expect_value(t, r.h, bug.h + 2 * 3)
	}
	testing.expect(t, found)
}

@(private = "file")
Tokens :: struct {
	clicks, removes, plain_removes, standalone_removes: int,
}

@(private = "file")
tokens :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Tokens)(user)
	col := ui.column_open(gtx, gap = 8)
	defer ui.close(&col)
	r := token(gtx, "two", removable = true, interactive = true)
	m.clicks += int(r.clicked)
	m.removes += int(r.removed)
	r = token(gtx, "plain", removable = true, hide_remove = true, interactive = true)
	m.plain_removes += int(r.removed)
	r = token(gtx, "alone", .Large, removable = true)
	m.standalone_removes += int(r.removed)
	token(gtx, "small", .Small, leading = .Git_Branch)
}

@(test)
test_a_token_with_two_targets_keeps_them_apart :: proc(t: ^testing.T) {
	m: Tokens
	p: ui.Probe
	ui.probe_init(&p, tokens, &m, {400, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	two := ui.probe_bounds(&p, "two")
	// The remove target is the token's last height-wide square.
	ui.probe_move(&p, two.x + two.w - two.h / 2, two.y + two.h / 2)
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_click(&p, "two")) // the centre: the token's own target
	testing.expect_value(t, m.clicks, 1)
	testing.expect_value(t, m.removes, 0)
	// Backspace or Delete on the focused token removes it.
	ui.probe_key(&p, .Backspace)
	testing.expect_value(t, m.removes, 1)
	ui.probe_key(&p, .Delete)
	testing.expect_value(t, m.removes, 2)
	ui.probe_key(&p, .A)
	testing.expect_value(t, m.removes, 2)
	// A hidden remove button keeps keyboard removal.
	testing.expect(t, ui.probe_click(&p, "plain"))
	ui.probe_key(&p, .Backspace)
	testing.expect_value(t, m.plain_removes, 1)
	testing.expect(t, !ui.probe_tagged(&p, "Remove plain"))
}

@(test)
test_a_tokens_remove_button_removes_without_activating_it :: proc(t: ^testing.T) {
	m: Tokens
	p: ui.Probe
	ui.probe_init(&p, tokens, &m, {400, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	two := ui.probe_bounds(&p, "two")
	ui.router_push(&p.router, {kind = .Press, pos = {two.x + two.w - two.h / 2, two.y + two.h / 2}, button = .Left})
	ui.router_push(&p.router, {kind = .Release, pos = {two.x + two.w - two.h / 2, two.y + two.h / 2}, button = .Left})
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	testing.expect_value(t, m.removes, 1)
	testing.expect_value(t, m.clicks, 0)
	// With two targets the remove target takes clicks, not focus: a
	// click on it leaves the token unfocused, so Backspace does nothing.
	ui.probe_key(&p, .Backspace)
	testing.expect_value(t, m.removes, 1)
	// A token that is not interactive has a real, focusable remove button
	// named "Remove token"; Enter or Backspace on it removes.
	ui.probe_click(&p, "alone") // the token itself takes no input
	testing.expect_value(t, m.standalone_removes, 0)
	testing.expect(t, ui.probe_click(&p, "Remove alone"))
	testing.expect_value(t, m.standalone_removes, 1)
	ui.probe_key(&p, .Enter)
	testing.expect_value(t, m.standalone_removes, 2)
	ui.probe_key(&p, .Delete)
	testing.expect_value(t, m.standalone_removes, 3)
	sem := ui.probe_semantics(&p, context.temp_allocator)
	testing.expectf(t, strings.contains(sem, `"Remove token"`), "semantics: %s", sem)
	testing.expectf(t, strings.contains(sem, `"two (press backspace or delete to remove)"`), "semantics: %s", sem)
}

@(test)
test_token_geometry_follows_the_size :: proc(t: ^testing.T) {
	m: Tokens
	p: ui.Probe
	ui.probe_init(&p, tokens, &m, {400, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	semi :: proc(size: f32) -> tok.Type_Style {
		return {weight = tok.BASE_TEXT_WEIGHT_SEMIBOLD, size = size, line_height = size}
	}
	// Small: 16px, 4px sides, no leading visual even when given one.
	small := ui.probe_bounds(&p, "small")
	testing.expect_value(t, small.h, 16)
	testing.expect_value(t, small.w, 2 + 2 * 4 + shaped(&p, "small", semi(12)).width)
	// Large with a remove button: no end padding; 6px, then a 24px target
	// over the right border.
	alone := ui.probe_bounds(&p, "alone")
	testing.expect_value(t, alone.w, 1 + 8 + shaped(&p, "alone", semi(14)).width + 6 + 24)
}

@(private = "file")
Group_Model :: struct {
	width:      f32,
	truncation: Label_Group_Truncation,
	count:      int,
	overflow:   Label_Group_Overflow,
	items:      int,
}

@(private = "file")
GROUP_ITEMS := [?]string{"one", "two", "three", "four", "five", "six"}

@(private = "file")
group_items :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Group_Model)(user)
	for s in GROUP_ITEMS[:m.items] {
		label(gtx, s)
	}
}

@(private = "file")
group :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Group_Model)(user)
	col := ui.column_open(gtx)
	defer ui.close(&col)
	sz := ui.sized_open(gtx, {max = {m.width, 0}})
	defer ui.close(&sz)
	label_group(gtx, group_items, m, m.truncation, m.count, m.overflow)
}

@(test)
test_label_group_count_shows_the_first_n_and_inline_expands :: proc(t: ^testing.T) {
	m := Group_Model{width = 500, truncation = .Count, count = 2, overflow = .Inline, items = 6}
	p: ui.Probe
	ui.probe_init(&p, group, &m, {600, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect(t, ui.probe_tagged(&p, "two"))
	testing.expect(t, !ui.probe_tagged(&p, "three"))
	plus := ui.probe_bounds(&p, "+4")
	two := ui.probe_bounds(&p, "two")
	testing.expect_value(t, plus.x, two.x + two.w + LABEL_GROUP_GAP)
	testing.expect_value(t, plus.h, LABEL_GROUP_ROW)
	sem := ui.probe_semantics(&p, context.temp_allocator)
	testing.expectf(t, strings.contains(sem, `"Show +4 more"`), "the toggle's spoken name: %s", sem)

	// +4: every item shows and the toggle, keeping its id and so focus,
	// says Show less; Enter on it collapses the row again.
	testing.expect(t, ui.probe_click(&p, "+4"))
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "six"))
	testing.expect(t, ui.probe_tagged(&p, "Show less"))
	ui.probe_key(&p, .Enter)
	ui.probe_frame(&p)
	testing.expect(t, !ui.probe_tagged(&p, "six"))
	testing.expect(t, ui.probe_tagged(&p, "+4"))

	// A count at or past the total hides nothing: no toggle.
	m.count = 6
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "six"))
	testing.expect(t, !ui.probe_tagged(&p, "+0"))
}

@(test)
test_label_group_auto_fits_a_prefix_beside_the_toggle :: proc(t: ^testing.T) {
	m := Group_Model{width = 1000, truncation = .Auto, items = 6}
	p: ui.Probe
	ui.probe_init(&p, group, &m, {1200, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect(t, ui.probe_tagged(&p, "six")) // all fit: no toggle
	one, three := ui.probe_bounds(&p, "one"), ui.probe_bounds(&p, "three")
	// Narrow the group to end inside "four": the toggle for "+6" (the
	// widest it can read) must fit after "three" with its gap.
	toggle := label_group_width_for(&p, 6)
	m.width = three.x + three.w - one.x + LABEL_GROUP_GAP + toggle
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "three"))
	testing.expect(t, !ui.probe_tagged(&p, "four"))
	testing.expect(t, ui.probe_tagged(&p, "+3"))
	m.width -= 1
	ui.probe_frame(&p)
	testing.expect(t, !ui.probe_tagged(&p, "three"))
	testing.expect(t, ui.probe_tagged(&p, "+4"))
	// No items: nothing to hide, no toggle.
	m.items = 0
	ui.probe_frame(&p)
	testing.expect(t, !ui.probe_tagged(&p, "+0"))
}

// label_group_width_for is the small invisible button reading "+n": its
// 8px sides around medium 12px text (ButtonBase.module.css:185-219).
@(private = "file")
label_group_width_for :: proc(p: ^ui.Probe, n: int) -> f32 {
	st := tok.Type_Style{weight = tok.BASE_TEXT_WEIGHT_MEDIUM, size = 12, line_height = 12 * tok.TEXT_BODY_LINE_HEIGHT_SMALL}
	return shaped(p, fmt.tprintf("+%d", n), st).width + 2 * tok.CONTROL_SMALL_PADDING_INLINE_CONDENSED
}

@(test)
test_label_group_overlay_opens_with_every_item_and_closes :: proc(t: ^testing.T) {
	m := Group_Model{width = 500, truncation = .Count, count = 1, overflow = .Overlay, items = 4}
	p: ui.Probe
	ui.probe_init(&p, group, &m, {600, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect(t, !ui.probe_tagged(&p, "four"))
	testing.expect(t, ui.probe_click(&p, "+3"))
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "four")) // the overlay holds every item
	testing.expect(t, ui.probe_tagged(&p, "Close"))
	sem := ui.probe_semantics(&p, context.temp_allocator)
	testing.expectf(t, strings.contains(sem, `"All 4 labels"`), "the dialog's name counts every item: %s", sem)
	// The dialog reaches 8px past the toggle's right edge; inside its 8px
	// padding, the Close button ends where the toggle does.
	plus, closer := ui.probe_bounds(&p, "+3"), ui.probe_bounds(&p, "Close")
	testing.expect_value(t, closer.x + closer.w, plus.x + plus.w)
	testing.expect(t, ui.probe_click(&p, "Close"))
	ui.probe_frame(&p)
	testing.expect(t, !ui.probe_tagged(&p, "four"))
	// Escape closes it too, and a press outside.
	testing.expect(t, ui.probe_click(&p, "+3"))
	ui.probe_frame(&p)
	ui.probe_key(&p, .Escape)
	ui.probe_frame(&p)
	testing.expect(t, !ui.probe_tagged(&p, "Close"))
	testing.expect(t, ui.probe_click(&p, "+3"))
	ui.probe_frame(&p)
	ui.router_push(&p.router, {kind = .Press, pos = {590, 390}, button = .Left})
	ui.router_push(&p.router, {kind = .Release, pos = {590, 390}, button = .Left})
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	testing.expect(t, !ui.probe_tagged(&p, "Close"))
}
