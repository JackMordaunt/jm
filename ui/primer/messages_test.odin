package primer

import "core:strings"
import "core:testing"
import "jm:ui"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// Banner, InlineMessage, Blankslate and Timeline, through probes.

@(private = "file")
Banner_Model :: struct {
	last:   Banner_Event,
	events: int,
	width:  f32, // the box the banner is offered; 0 for the window
	layout: Banner_Actions,
	dismiss: bool,
}

@(private = "file")
banner_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Banner_Model)(user)
	col := ui.column_open(gtx)
	defer ui.close(&col)
	box := ui.sized_open(gtx, {max = {m.width, 0}})
	defer ui.close(&box)
	if e := banner(gtx, "Update available", "A new version is ready.", primary = "Update", secondary = "Later", dismissible = m.dismiss, actions = m.layout); e != .None {
		m.last = e
		m.events += 1
	}
}

@(test)
test_banner_puts_its_actions_beside_or_under_by_its_own_width :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	m := Banner_Model{width = 800}
	p: ui.Probe
	ui.probe_init(&p, banner_view, &m, {1000, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	ui.probe_frame(&p) // the flexible body takes its share from the first frame's totals
	title := ui.probe_bounds(&p, "Update available")
	upd, later := ui.probe_bounds(&p, "Update"), ui.probe_bounds(&p, "Later")
	// Wide (an 800px banner's content box is 782px): secondary then
	// primary, beside the content, on the title's row, primary at the end.
	testing.expect(t, later.x < upd.x)
	testing.expect_value(t, upd.x + upd.w, 800 - 9 - 0) // flush with the content box's end
	testing.expect_value(t, upd.y, 9 + tok.BASE_SIZE_2) // 2px under the content box's top
	testing.expect(t, upd.y < title.y + title.h)
	// 518px wide leaves a 500px content box: still beside (500 counts as wide).
	m.width = 518
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_bounds(&p, "Later").x < ui.probe_bounds(&p, "Update").x)
	// 517px: under the content, primary first.
	m.width = 517
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	desc := ui.probe_bounds(&p, "A new version is ready.")
	upd, later = ui.probe_bounds(&p, "Update"), ui.probe_bounds(&p, "Later")
	testing.expect(t, upd.x < later.x)
	testing.expect_value(t, upd.x, 9 + 32) // under the content, past the icon cell
	testing.expect_value(t, upd.y, desc.y + desc.h + tok.BASE_SIZE_8 + tok.BASE_SIZE_4 + tok.BASE_SIZE_2)
	sem := ui.probe_semantics(&p, context.temp_allocator)
	// 9 + 8 + 21 + 4 + 21 + 8 + 4 + 2 + 32 + 6 + 9 tall: the narrow rule's 6px under the actions.
	testing.expect(t, strings.contains(sem, "region \"Update available\" at 0,0 517x124\n"), sem)
	testing.expect(t, strings.contains(sem, "  heading \"Update available\" level 2 at"), sem)
}

@(test)
test_a_dismissible_banner_stacks_and_reports_each_action :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	m := Banner_Model{width = 800, dismiss = true}
	p: ui.Probe
	ui.probe_init(&p, banner_view, &m, {1000, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	ui.probe_frame(&p)
	title := ui.probe_bounds(&p, "Update available")
	testing.expect(t, ui.probe_bounds(&p, "Update").y > title.y + title.h) // wide, but stacked
	testing.expect(t, ui.probe_bounds(&p, "Update").x < ui.probe_bounds(&p, "Later").x)
	x := ui.probe_bounds(&p, "Dismiss banner")
	testing.expect_value(t, x, ops.Rect{800 - 9 - 32, 9 + tok.BASE_SIZE_2, 32, 32}) // 2px down beside actions
	testing.expect(t, ui.probe_click(&p, "Update"))
	testing.expect_value(t, m.last, Banner_Event.Primary)
	// Each takes the keyboard once a press has focused it.
	testing.expect(t, ui.probe_click(&p, "Later"))
	ui.probe_key(&p, .Enter)
	testing.expect_value(t, m.last, Banner_Event.Secondary)
	testing.expect(t, ui.probe_click(&p, "Dismiss banner"))
	testing.expect_value(t, m.last, Banner_Event.Dismiss)
	ui.probe_key(&p, .Space)
	testing.expect_value(t, m.events, 5)
}

@(test)
test_an_inline_banner_follows_the_window_not_its_width :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	m := Banner_Model{width = 300, layout = .Inline}
	p: ui.Probe
	ui.probe_init(&p, banner_view, &m, {800, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_bounds(&p, "Later").x < ui.probe_bounds(&p, "Update").x) // a 300px banner, but beside
	q: ui.Probe
	ui.probe_init(&q, banner_view, &m, {700, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&q)
	ui.probe_frame(&q)
	testing.expect(t, ui.probe_bounds(&q, "Update").x < ui.probe_bounds(&q, "Later").x) // a window under 768px: under
}

@(test)
test_a_banner_without_actions_is_its_content_tall :: proc(t: ^testing.T) {
	view :: proc(gtx: ^ui.Ctx, user: rawptr) {
		col := ui.column_open(gtx, gap = 10)
		defer ui.close(&col)
		banner(gtx, "Saved", "All changes are saved.", .Success)
		banner(gtx, "Hidden", "Only this shows.", hide_title = true, layout = .Compact)
	}
	defer free_all(context.temp_allocator)
	p: ui.Probe
	ui.probe_init(&p, view, nil, {600, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	sem := ui.probe_semantics(&p, context.temp_allocator)
	// 1 + 8 + 8 + 21 + 4 + 21 + 8 + 8 + 1.
	testing.expect(t, strings.contains(sem, "region \"Saved\" at 0,0 600x80\n"), sem)
	// Compact with the title hidden: 1 + 4 + 6 + 21 + 6 + 4 + 1, and the
	// heading still told, with no box.
	testing.expect(t, strings.contains(sem, "region \"Hidden\" at 0,90 600x43\n  heading \"Hidden\" level 2 at"), sem)
	testing.expect(t, !ui.probe_tagged(&p, "Hidden"))
	testing.expect_value(t, ui.probe_bounds(&p, "Only this shows.").y, 90 + 5 + 6)
}

@(test)
test_inline_message_sets_its_icon_on_the_first_line :: proc(t: ^testing.T) {
	view :: proc(gtx: ^ui.Ctx, user: rawptr) {
		col := ui.column_open(gtx, gap = 10)
		defer ui.close(&col)
		inline_message(gtx, "Saved", .Success)
		inline_message(gtx, "Taken", .Critical, .Small)
		box := ui.sized_open(gtx, {max = {100, 0}})
		defer ui.close(&box)
		inline_message(gtx, "A message long enough to wrap", .Warning)
	}
	defer free_all(context.temp_allocator)
	p: ui.Probe
	ui.probe_init(&p, view, nil, {600, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	saved := ui.probe_bounds(&p, "Saved")
	testing.expect_value(t, saved.h, 21)
	testing.expect_value(t, saved.w, 16 + INLINE_GAP + 5 * 0.6 * 14) // the icon, the gap, the text
	taken := ui.probe_bounds(&p, "Taken")
	testing.expect_value(t, taken.h, 19.5)
	testing.expect_value(t, taken.w, 12 + INLINE_GAP + 5 * 0.6 * 12) // a 12px filled icon at small
	wrapped := ui.probe_bounds(&p, "A message long enough to wrap")
	testing.expect(t, wrapped.w <= 100)
	testing.expect(t, wrapped.h > 21)
	// The text and the icon are the variant's colour.
	danger, success := color(.Fg_Color_Danger), color(.Fg_Color_Success)
	fills, glyphs := 0, 0
	for op in p.scene.ops {
		#partial switch v in op {
		case ops.Fill:
			if c, ok := v.paint.(ops.Color); ok && (c == danger || c == success) {
				fills += 1
			}
		case ops.Glyphs:
			if v.color == danger || v.color == success {
				glyphs += 1
			}
		}
	}
	testing.expect_value(t, fills, 2)
	testing.expect_value(t, glyphs, 2)
}

@(private = "file")
Blank_Model :: struct {
	width: f32,
	last:  Blankslate_Event,
}

@(private = "file")
blank_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Blank_Model)(user)
	col := ui.column_open(gtx)
	defer ui.close(&col)
	box := ui.sized_open(gtx, {max = {m.width, 0}})
	defer ui.close(&box)
	if e := blankslate(gtx, "Nothing here", "Add one", .Inbox, primary = "Add", secondary = "Learn", heading_level = 3); e != .None {
		m.last = e
	}
}

@(test)
test_blankslate_centres_its_column_and_compacts_at_544 :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	m := Blank_Model{width = 800}
	p: ui.Probe
	ui.probe_init(&p, blank_view, &m, {1000, 800}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	h := ui.probe_bounds(&p, "Nothing here")
	testing.expect_value(t, h.h, tok.TEXT_TITLE_SHORTHAND_MEDIUM.line_height)
	testing.expect_value(t, h.x + h.w / 2, 400) // centred in the 800px it was offered
	// 32px padding, a 32px visual and 8px, then the heading.
	testing.expect_value(t, h.y, 32 + 32 + 8)
	d := ui.probe_bounds(&p, "Add one")
	testing.expect_value(t, d.y, h.y + h.h + 4)
	testing.expect_value(t, d.h, tok.TEXT_BODY_SHORTHAND_LARGE.line_height)
	add := ui.probe_bounds(&p, "Add")
	testing.expect_value(t, add.y, d.y + d.h + 16)
	testing.expect_value(t, add.h, tok.CONTROL_MEDIUM_SIZE)
	testing.expect_value(t, ui.probe_bounds(&p, "Learn").y, add.y + add.h + 16)
	testing.expect(t, ui.probe_click(&p, "Add"))
	testing.expect_value(t, m.last, Blankslate_Event.Primary)
	testing.expect(t, ui.probe_click(&p, "Learn"))
	testing.expect_value(t, m.last, Blankslate_Event.Secondary)
	sem := ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(t, strings.contains(sem, "heading \"Nothing here\" level 3"), sem)
	// 544 is compact: title-small, body-medium, 20px padding, a 24px
	// visual, later actions 8px apart.
	m.width = 544
	ui.probe_frame(&p)
	h = ui.probe_bounds(&p, "Nothing here")
	testing.expect_value(t, h.h, tok.TEXT_TITLE_SHORTHAND_SMALL.line_height)
	testing.expect_value(t, h.x + h.w / 2, 272)
	testing.expect_value(t, h.y, 20 + 24 + 8)
	testing.expect_value(t, ui.probe_bounds(&p, "Add one").h, tok.TEXT_BODY_SHORTHAND_MEDIUM.line_height)
	add = ui.probe_bounds(&p, "Add")
	testing.expect_value(t, ui.probe_bounds(&p, "Learn").y, add.y + add.h + 8)
	m.width = 545
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_bounds(&p, "Nothing here").h, tok.TEXT_TITLE_SHORTHAND_MEDIUM.line_height)
}

@(test)
test_a_narrow_blankslate_caps_and_centres_and_balances :: proc(t: ^testing.T) {
	view :: proc(gtx: ^ui.Ctx, user: rawptr) {
		col := ui.column_open(gtx)
		defer ui.close(&col)
		blankslate(gtx, "Narrow", "aaaa bbbb cccc dddd eeee ffff gggg hhhh iiii jjjj kkkk llll mmmm nnnn oooo pppp qqqq rrrr ssss tttt uuuu", narrow = true)
	}
	defer free_all(context.temp_allocator)
	p: ui.Probe
	ui.probe_init(&p, view, nil, {1000, 800}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	d := ui.probe_bounds(&p, "aaaa bbbb cccc dddd eeee ffff gggg hhhh iiii jjjj kkkk llll mmmm nnnn oooo pppp qqqq rrrr ssss tttt uuuu")
	testing.expect_value(t, d.x + d.w / 2, 500) // centred in the window
	// 485 less 64px padding is 421px: greedy takes 8 words (378px) a line,
	// 8 + 8 + 5; balanced evens them to 7 a line, 7 x 4 + 6 x 1 runes.
	testing.expect_value(t, d.h, 3 * tok.TEXT_BODY_SHORTHAND_LARGE.line_height)
	testing.expectf(t, abs(d.w - 34 * 0.6 * 16) < 0.01, "balanced width %v", d.w)
}

@(private = "file")
Timeline_Model :: struct {
	width:   f32,
	clip:    Timeline_Clip,
	replies: int,
}

@(private = "file")
timeline_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Timeline_Model)(user)
	col := ui.column_open(gtx)
	defer ui.close(&col)
	gutter := ui.inset_open(gtx, {left = 100})
	defer ui.close(&gutter)
	box := ui.sized_open(gtx, {max = {m.width, 0}})
	defer ui.close(&box)
	tl := timeline_open(gtx, m.clip)
	defer timeline_close(&tl)
	{
		it := timeline_item_open(gtx, &tl, .Eye, body = "reviewed")
		defer timeline_item_close(&it)
		av := timeline_avatar_open(gtx, &it)
		p := ui.widget_open(gtx)
		ops.tag(gtx.scene, p.id, "avatar", {0, 0, 40, 40})
		ui.widget_close(gtx, &p, {size = {40, 40}})
		ui.close(&av)
		timeline_actions(gtx, &it)
		if button(gtx, "Reply", size = .Small) {
			m.replies += 1
		}
	}
	timeline_break(&tl)
	{
		it := timeline_item_open(gtx, &tl, .Git_Commit, condensed = true, body = "committed")
		timeline_item_close(&it)
	}
	{
		it := timeline_item_open(gtx, &tl, .Git_Merge, .Done, body = "merged")
		timeline_item_close(&it)
	}
}

@(private = "file")
line_rects :: proc(p: ^ui.Probe) -> (out: [dynamic]ops.Rect) {
	out = make([dynamic]ops.Rect, context.temp_allocator)
	muted := color(.Border_Color_Muted)
	for op in p.scene.ops {
		if f, ok := op.(ops.Fill); ok {
			if c, solid := f.paint.(ops.Color); solid && c == muted {
				if r, is_rect := f.shape.(ops.Rect); is_rect {
					append(&out, r)
				}
			}
		}
	}
	return
}

@(test)
test_timeline_lays_items_on_one_line_with_a_break :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	m := Timeline_Model{width = 600}
	p: ui.Probe
	ui.probe_init(&p, timeline_view, &m, {1000, 800}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	testing.expect(t, p.wants_frame) // the first frame did not know the last item
	ui.probe_frame(&p)
	reviewed := ui.probe_bounds(&p, "reviewed")
	// 100px gutter + 16px inset + 25px badge column; 16px padding + 5px.
	testing.expect_value(t, reviewed.x, 100 + 16 + 25)
	testing.expect_value(t, reviewed.y, 16 + 5)
	reply := ui.probe_bounds(&p, "Reply")
	testing.expect_value(t, reply.x + reply.w, 100 + 600) // at the trailing end
	testing.expect_value(t, reply.y, 16 + (32 - tok.CONTROL_SMALL_SIZE) / 2) // centred on the badge
	// The avatar hangs 72px left of the line, centred on the badge.
	testing.expect_value(t, ui.probe_bounds(&p, "avatar"), ops.Rect{100 + 16 - 72, 32 - 20, 40, 40})
	// Item one is 16 + 32 + 16 tall; the break adds 8 before a condensed
	// item, 12; condensed: 4px above, a 32px badge row, nothing below.
	committed := ui.probe_bounds(&p, "committed")
	testing.expect_value(t, committed.y, 64 + 12 + 4 + 5)
	merged := ui.probe_bounds(&p, "merged")
	testing.expect_value(t, merged.y, 64 + 12 + 4 + 32 + 16 + 5)
	// Each item's 2px line at the item's left edge, the condensed one's
	// under the break's band.
	lines := line_rects(&p)
	testing.expect_value(t, len(lines), 3)
	testing.expect_value(t, lines[0], ops.Rect{0, 0, 2, 64})
	testing.expect_value(t, lines[1].y, 12)
	testing.expect(t, ui.probe_click(&p, "Reply"))
	testing.expect_value(t, m.replies, 1)
}

@(test)
test_a_narrow_clipped_timeline_moves_actions_under_and_trims_its_line :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	m := Timeline_Model{width = 479, clip = .Both}
	p: ui.Probe
	ui.probe_init(&p, timeline_view, &m, {1000, 800}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	ui.probe_frame(&p)
	reviewed := ui.probe_bounds(&p, "reviewed")
	testing.expect_value(t, reviewed.y, 5) // clipped at the start: no padding above the first badge
	reply := ui.probe_bounds(&p, "Reply")
	testing.expect_value(t, reply.x, 100 + 16 + 25) // under the body, from its start
	testing.expect_value(t, reply.y, TIMELINE_BADGE + 8) // 8px under the badge and body's row
	lines := line_rects(&p)
	last := lines[len(lines) - 1]
	testing.expect_value(t, last, ops.Rect{0, 0, 2, 16 + TIMELINE_BADGE}) // the last item ends at its content: no padding below
	m.width = 480
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_bounds(&p, "Reply").x + ui.probe_bounds(&p, "Reply").w, 100 + 480) // 480 is wide
}
