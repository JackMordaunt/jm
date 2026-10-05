package primer

import "core:testing"
import "jm:ui"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// Behaviour of the layout family's simpler parts: the viewport ranges,
// Stack, Card and Header, through ui.Probe by tags.

// block is a tagged box of size, for measuring where a layout puts it.
@(private = "file")
block :: proc(gtx: ^ui.Ctx, name: string, size: ops.Size, key: u64 = 0, loc := #caller_location) {
	p := ui.widget_open(gtx, key, loc)
	sz := ui.constrain(gtx.constraints, size)
	ops.tag(gtx.scene, p.id, name, {0, 0, sz.x, sz.y})
	ui.widget_close(gtx, &p, {size = sz})
}

@(private = "file")
probe_view :: proc(p: ^ui.Probe, view: ui.UI_Proc, user: rawptr, size: ops.Size) {
	ui.probe_init(p, view, user, size, allocator = context.temp_allocator)
}

@(test)
test_the_viewport_range_reads_the_window_not_the_offer :: proc(t: ^testing.T) {
	Seen :: struct {
		rg:                  Viewport_Range,
		only_narrow, picked: int,
	}
	view :: proc(gtx: ^ui.Ctx, user: rawptr) {
		s := (^Seen)(user)
		sz := ui.sized_open(gtx, {max = {200, 100}}) // a narrow container in any window
		defer ui.close(&sz)
		s.rg = viewport_range(gtx)
		s.only_narrow = responsive(gtx, Responsive(int){narrow = 1}, 0)
		s.picked = responsive(gtx, Responsive(int){regular = 2, wide = 3}, 9)
	}
	cases := []struct {
		width:  f32,
		rg:     Viewport_Range,
		picked: int,
	}{{767, .Narrow, 9}, {768, .Regular, 2}, {1399, .Regular, 2}, {1400, .Wide, 3}}
	for c in cases {
		s: Seen
		p: ui.Probe
		probe_view(&p, view, &s, {c.width, 600})
		testing.expectf(t, s.rg == c.rg, "%v wide: %v, want %v", c.width, s.rg, c.rg)
		testing.expect_value(t, s.only_narrow, 1) // a narrow value holds at every width
		testing.expect_value(t, s.picked, c.picked)
		ui.probe_destroy(&p)
	}
	free_all(context.temp_allocator)
}

@(test)
test_stack_spaces_pads_and_justifies_its_children :: proc(t: ^testing.T) {
	view :: proc(gtx: ^ui.Ctx, user: rawptr) {
		col := ui.column_open(gtx, align = .Fill)
		defer ui.close(&col)
		{
			s := stack_open(gtx, gap = .Cozy, padding = .Normal, padding_block = .Tight)
			defer stack_close(&s)
			block(gtx, "a", {40, 10})
			block(gtx, "b", {40, 10})
		}
		{
			s := stack_open(gtx, direction = .Horizontal, justify = .Space_Between, align = .Center)
			defer stack_close(&s)
			block(gtx, "left", {30, 20})
			block(gtx, "right", {30, 10})
		}
		{
			s := stack_open(gtx, gap = .None, direction = .Horizontal)
			defer stack_close(&s)
			block(gtx, "fixed", {50, 10})
			stack_item(gtx)
			block(gtx, "grows", {10, 10})
		}
	}
	p: ui.Probe
	probe_view(&p, view, nil, {300, 400})
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	a, b := ui.probe_bounds(&p, "a"), ui.probe_bounds(&p, "b")
	// padding normal inline (16), padding_block tight (4) wins on its axis
	testing.expect_value(t, a, ops.Rect{16, 4, 300 - 32, 10}) // stretch: as wide as the stack
	testing.expect_value(t, b.y, a.y + 10 + tok.BASE_SIZE_12) // cozy: 12px
	stack2 := a.y + 10 + 12 + 10 + 4
	left, right := ui.probe_bounds(&p, "left"), ui.probe_bounds(&p, "right")
	testing.expect_value(t, left.x, 0)
	testing.expect_value(t, right.x, 300 - 30) // space-between: flush with the end
	testing.expect_value(t, right.y, stack2 + 5) // centred across a 20px row
	grows := ui.probe_bounds(&p, "grows")
	testing.expect_value(t, grows.w, 300 - 50) // a growing item takes the rest
}

@(private = "file")
Card_Model :: struct {
	stars: int,
}

@(private = "file")
cards_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Card_Model)(user)
	col := ui.column_open(gtx, gap = 20, align = .Fill)
	defer ui.close(&col)
	{
		c := card_open(gtx, "Primer", "A design system", icon = .Repo)
		card_metadata_open(&c)
		card_metadata_item(gtx, "Updated today", .Clock)
		card_metadata_close(&c)
		card_action_open(&c)
		if icon_button(gtx, .Star, "Star Primer", .Invisible, .Small) {
			m.stars += 1
		}
		card_action_close(&c)
		card_close(&c)
	}
	{
		c := card_open(gtx, "Compact", "Beside its icon", icon = .Repo, layout = .Compact)
		card_close(&c)
	}
	{
		c := card_open(gtx, "Pictured", image = {7, {400, 100}}, padding = .Condensed)
		card_close(&c)
	}
}

@(test)
test_card_lays_its_parts_out_by_the_css :: proc(t: ^testing.T) {
	m: Card_Model
	p: ui.Probe
	probe_view(&p, cards_view, &m, {400, 900})
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	card := ui.probe_bounds(&p, "Primer")
	testing.expect_value(t, card.w, 400) // a block: the width offered
	pad := tok.STACK_PADDING_SPACIOUS
	desc := ui.probe_bounds(&p, "A design system")
	title_y := pad + CARD_ICON_TILE + tok.STACK_GAP_NORMAL
	testing.expect_value(t, desc.x, pad)
	testing.expect_value(t, desc.y, title_y + style(.Title_Small).line_height + tok.STACK_GAP_CONDENSED)
	meta := ui.probe_bounds(&p, "Updated today")
	testing.expect_value(t, meta.x, pad)
	testing.expect(t, meta.y >= desc.y + desc.h + tok.STACK_GAP_NORMAL)
	testing.expect_value(t, card.h, meta.y + meta.h + pad)
	// The action sits 16px in from the top-right corner, over the content.
	star := ui.probe_bounds(&p, "Star Primer")
	testing.expect_value(t, star, ops.Rect{400 - 16 - tok.CONTROL_SMALL_SIZE, 16, tok.CONTROL_SMALL_SIZE, tok.CONTROL_SMALL_SIZE})
	testing.expect(t, ui.probe_click(&p, "Star Primer"))
	testing.expect_value(t, m.stars, 1)

	// Compact: 16px padding, the bare 16px icon beside the body, 8px apart,
	// the heading at body size drawn 4px high.
	compact := ui.probe_bounds(&p, "Compact")
	beside := ui.probe_bounds(&p, "Beside its icon")
	testing.expect_value(t, beside.x - compact.x, tok.STACK_PADDING_NORMAL + BUTTON_ICON + tok.STACK_GAP_CONDENSED)
	testing.expect_value(t, beside.y - compact.y, tok.STACK_PADDING_NORMAL + style(.Title_Small).line_height + tok.STACK_GAP_CONDENSED)

	// The image runs edge to edge over the 8px padding at the card's width
	// and natural aspect ratio.
	pictured := ui.probe_bounds(&p, "Pictured")
	found := false
	for op in p.scene.ops {
		if im, ok := op.(ops.Image); ok && im.id == 7 {
			found = true
			testing.expect_value(t, im.dst, ops.Rect{-tok.STACK_PADDING_CONDENSED, -tok.STACK_PADDING_CONDENSED, 400, 100})
		}
	}
	testing.expect(t, found)
	testing.expect_value(t, pictured.h, 100 + tok.STACK_GAP_NORMAL + style(.Title_Small).line_height + tok.STACK_PADDING_CONDENSED)
}

@(private = "file")
Header_Model :: struct {
	home: int,
}

@(private = "file")
header_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Header_Model)(user)
	col := ui.column_open(gtx, align = .Fill)
	defer ui.close(&col)
	h := header_open(gtx)
	{
		it := header_item_open(gtx)
		if header_link(gtx, "GitHub", .Mark_Github) {
			m.home += 1
		}
		header_item_close(&it)
	}
	{
		it := header_item_open(gtx, full = true)
		block(gtx, "search", {100, 20})
		header_item_close(&it)
	}
	{
		it := header_item_open(gtx)
		block(gtx, "avatar", {20, 20})
		header_item_close(&it)
	}
	header_close(&h)
	block(gtx, "below", {10, 10})
}

@(test)
test_header_is_a_padded_dark_bar_whose_full_item_pushes_the_rest_right :: proc(t: ^testing.T) {
	m: Header_Model
	p: ui.Probe
	probe_view(&p, header_view, &m, {600, 300})
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	below := ui.probe_bounds(&p, "below")
	testing.expect_value(t, below.y, 32 + 32) // 16px padding round the 32px mark
	bar := false
	for op in p.scene.ops {
		if f, ok := op.(ops.Fill); ok && f.shape == ops.Shape(ops.Rect{0, 0, 600, 64}) {
			bar = is_header_bg(f.paint)
		}
	}
	testing.expect(t, bar)
	logo := ui.probe_bounds(&p, "GitHub")
	testing.expect_value(t, logo.x, 16)
	avatar := ui.probe_bounds(&p, "avatar")
	testing.expect_value(t, avatar.x, 600 - 16 - 16 - 20) // its 16px margin, then the bar's padding
	testing.expect_value(t, avatar.y, 16 + 6) // centred down the 32px row

	testing.expect(t, ui.probe_click(&p, "GitHub"))
	testing.expect_value(t, m.home, 1)
	ui.probe_key(&p, .Enter)
	testing.expect_value(t, m.home, 2)
}

@(private = "file")
is_header_bg :: proc(paint: ops.Paint) -> bool {
	c, ok := paint.(ops.Color)
	return ok && c == color(.Header_Bg_Color)
}

// Hovering the link dims it from the logo colour to the bar's default.
@(test)
test_header_link_dims_on_hover :: proc(t: ^testing.T) {
	m: Header_Model
	p: ui.Probe
	probe_view(&p, header_view, &m, {600, 300})
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	ink :: proc(p: ^ui.Probe) -> ops.Color {
		for op in p.scene.ops {
			if g, ok := op.(ops.Glyphs); ok {
				return g.color
			}
		}
		return {}
	}
	testing.expect_value(t, ink(&p), color(.Header_Fg_Color_Logo))
	c, _ := ui.probe_center(&p, "GitHub")
	ui.probe_move(&p, c.x, c.y)
	ui.probe_frame(&p)
	testing.expect_value(t, ink(&p), color(.Header_Fg_Color_Default))
}

// A bar narrower than its items scrolls them sideways rather than
// squeezing them, and is still as tall as its tallest item.
@(test)
test_header_scrolls_sideways_when_its_items_overflow :: proc(t: ^testing.T) {
	m: Header_Model
	p: ui.Probe
	probe_view(&p, header_view, &m, {150, 300})
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect_value(t, ui.probe_bounds(&p, "below").y, 64)
	avatar := ui.probe_bounds(&p, "avatar")
	testing.expect(t, avatar.x > 150) // past the edge, reachable by scrolling
	c, _ := ui.probe_center(&p, "GitHub")
	ui.router_push(&p.router, {kind = .Scroll, pos = c, scroll = {1, 0}})
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_bounds(&p, "avatar").x < avatar.x)
}
