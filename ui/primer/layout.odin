package primer

import "jm:ui"
import "jm:ui/design"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// Viewport_Range is the window's width class, which Primer's layouts
// switch on (stack.json, page-layout.json layout): Narrow below 768px
// (--breakpoint-medium), Regular from 768px, Wide from 1400px
// (--breakpoint-xxlarge). Wide is a subset of Regular in the CSS: a rule
// for Regular also holds at Wide unless a Wide value overrides it.
Viewport_Range :: enum u8 {
	Narrow,
	Regular,
	Wide,
}

// viewport_range is the range of the window gtx was laid out for
// (gtx.viewport): the window, never the space a container offers, as the
// CSS media queries read the window. A frame from a host that did not
// say reads Regular.
viewport_range :: proc(gtx: ^ui.Ctx) -> Viewport_Range {
	w := gtx.viewport.x
	switch {
	case w <= 0:
		return .Regular
	case w >= tok.BREAKPOINT_XXLARGE:
		return .Wide
	case w >= tok.BREAKPOINT_MEDIUM:
		return .Regular
	}
	return .Narrow
}

// Responsive is a value given per viewport range, as Primer's responsive
// props take {narrow, regular, wide}; an unset range has no value.
Responsive :: struct($T: typeid) {
	narrow, regular, wide: Maybe(T),
}

// responsive is r's value at the window's range, by the CSS's cascade
// (stack.json notes): wide if set and the window is wide, else regular if
// set and the window is regular or wide, else narrow if set (the narrow
// rule sits outside any media query, so it holds at every width), else
// fallback.
responsive :: proc(gtx: ^ui.Ctx, r: Responsive($T), fallback: T) -> T {
	rg := viewport_range(gtx)
	if v, ok := r.wide.?; ok && rg == .Wide {
		return v
	}
	if v, ok := r.regular.?; ok && rg != .Narrow {
		return v
	}
	if v, ok := r.narrow.?; ok {
		return v
	}
	return fallback
}

// Stack_Space is a step of the stack spacing scale, for gap and padding:
// 0, 4, 8, 12, 16 or 24px (stack.json layout).
Stack_Space :: enum u8 {
	None,
	Tight,
	Condensed,
	Cozy,
	Normal,
	Spacious,
}

// STACK_GAP is the gap per step: --base-size-4, --stack-gap-condensed,
// --base-size-12, --stack-gap-normal, --stack-gap-spacious
// (Stack.module.css:60-88).
@(rodata)
STACK_GAP := [Stack_Space]f32 {
	.None      = 0,
	.Tight     = tok.BASE_SIZE_4,
	.Condensed = tok.STACK_GAP_CONDENSED,
	.Cozy      = tok.BASE_SIZE_12,
	.Normal    = tok.STACK_GAP_NORMAL,
	.Spacious  = tok.STACK_GAP_SPACIOUS,
}

// STACK_PADDING is the padding per step, from the --stack-padding-*
// tokens (Stack.module.css:8-48).
@(rodata)
STACK_PADDING := [Stack_Space]f32 {
	.None      = 0,
	.Tight     = tok.BASE_SIZE_4,
	.Condensed = tok.STACK_PADDING_CONDENSED,
	.Cozy      = tok.BASE_SIZE_12,
	.Normal    = tok.STACK_PADDING_NORMAL,
	.Spacious  = tok.STACK_PADDING_SPACIOUS,
}

// Stack_Direction is a stack's main axis.
Stack_Direction :: enum u8 {
	Vertical,
	Horizontal,
}

// Stack_Align is where children sit across a stack's main axis.
Stack_Align :: enum u8 {
	Stretch,
	Start,
	Center,
	End,
	Baseline,
}

// Stack_Justify is how children share a stack's main axis: start,
// center, end, space-between or space-evenly (no space-around).
Stack_Justify :: ui.Justify

// Stack is an open stack: its padding and its flex.
Stack :: struct {
	inset: ui.Inset,
	flex:  ui.Flex,
}

// stack_open is Primer's Stack (stack.json, Stack.module.css): children
// in a column or a row, gap apart, aligned across and justified along,
// optionally wrapping, inside padding. paddingBlock and paddingInline
// win over padding on their axis. It draws nothing. A responsive value
// is the caller's to resolve: pass responsive(gtx, {narrow = ...}, ...).
// Close it with stack_close.
//
// Departures: unset gap means normal; the web inherits the nearest
// ancestor Stack's gap, which the spec records as an upstream bug.
// Children do not shrink below what they are offered in turn: jm:ui
// offers each child what the ones before it left, where CSS shrinks
// every item in proportion (flex-shrink 1, min-inline-size 0); a
// stack_item that grows takes the free space as flex-grow does. A
// vertical stack does not wrap: jm:ui's wrap runs along rows only.
stack_open :: proc(
	gtx: ^ui.Ctx,
	gap := Stack_Space.Normal,
	direction := Stack_Direction.Vertical,
	align := Stack_Align.Stretch,
	justify := Stack_Justify.Start,
	wrap := false,
	padding := Stack_Space.None,
	padding_block: Maybe(Stack_Space) = nil,
	padding_inline: Maybe(Stack_Space) = nil,
	key: u64 = 0,
	loc := #caller_location,
) -> (s: Stack) {
	block := STACK_PADDING[padding_block.? or_else padding]
	inline := STACK_PADDING[padding_inline.? or_else padding]
	s.inset = ui.inset_open(gtx, {inline, block, inline, block}, key, loc)
	g := STACK_GAP[gap]
	a := stack_flex_align(align)
	switch {
	case wrap && direction == .Horizontal:
		s.flex = ui.wrap_open(gtx, gap = g, align = a, justify = justify)
	case direction == .Horizontal:
		s.flex = ui.row_open(gtx, gap = g, align = a, justify = justify)
	case:
		s.flex = ui.column_open(gtx, gap = g, align = a, justify = justify)
	}
	return
}

// stack_close closes a stack.
stack_close :: proc(s: ^Stack) {
	ui.close(&s.flex)
	ui.close(&s.inset)
}

// stack_flex_align maps a stack's align onto jm:ui's: stretch is Fill.
@(private)
stack_flex_align :: proc(a: Stack_Align) -> ui.Align {
	switch a {
	case .Stretch:
		return .Fill
	case .Start:
		return .Start
	case .Center:
		return .Center
	case .End:
		return .End
	case .Baseline:
		return .Baseline
	}
	return .Fill
}

// stack_item makes the innermost stack's next child a Stack.Item that
// grows: it takes a share of the main-axis space the others leave
// (Stack.module.css:548-560). Without grow it does nothing, as a plain
// child already keeps its content size.
stack_item :: proc(gtx: ^ui.Ctx, grow := true) {
	if grow {
		ui.flexible(gtx, 1)
	}
}

// Card_Padding is a card's inner padding: 24px (16px compact), 8px or 0.
Card_Padding :: enum u8 {
	Normal,
	Condensed,
	None,
}

// Card_Radius is a card's corner radius: large (12px) or medium (6px).
Card_Radius :: enum u8 {
	Large,
	Medium,
}

// Card_Layout is default (header over body, the icon in a 32px tile) or
// compact (the bare icon beside the body, a smaller heading).
Card_Layout :: enum u8 {
	Default,
	Compact,
}

// Card_Image is an edge-to-edge header image: its id and natural size,
// which sets its aspect ratio.
Card_Image :: struct {
	id:   ops.Image_Id,
	size: ops.Size,
}

// Card is an open card.
Card :: struct {
	gtx:           ^ui.Ctx,
	place:         ui.Placement,
	rec:           ui.Recording,
	inset:         ui.Inset,
	outer, body:   ui.Flex,
	compact:       bool,
	radius:        f32,
	standalone:    bool,
	action:        ops.Macro_Id,
	action_size:   ops.Size,
	has_action:    bool,
	action_rec:    ui.Recording,
	metadata:      ui.Flex,
	heading:       string,
}

// card_padding is the padding for p in layout l (Card.module.css:19-42).
@(private)
card_padding :: proc(p: Card_Padding, l: Card_Layout) -> f32 {
	switch p {
	case .Normal:
		return l == .Compact ? tok.STACK_PADDING_NORMAL : tok.STACK_PADDING_SPACIOUS
	case .Condensed:
		return tok.STACK_PADDING_CONDENSED
	case .None:
	}
	return 0
}

// CARD_ICON_TILE is the default layout's icon tile, --base-size-32, with
// a 16px octicon centred in it (Card.module.css:71-84).
CARD_ICON_TILE :: tok.BASE_SIZE_32

// card_open opens Primer's Card (card.json, Card.module.css): a bordered,
// raised box on --bgColor-default with --shadow-resting-small, clipping
// its content to its rounded edge. In the default layout an image runs
// edge to edge across the top, else an icon sits in a muted tile; then
// the heading (title small) and description (muted body), then whatever
// the caller adds: card_metadata_open's row, or free content. A card
// action (card_action_open) sits 16px from the top-right corner over the
// content. The card fills the width it is offered, as a block does, or
// hugs its content where the width is unbounded. A standalone card is a
// region named by its heading. Close it with card_close.
//
// Departures: the image's edge-to-edge pull uses the card's own padding;
// the web always pulls by --stack-padding-spacious, which overshoots and
// crops with condensed, none or compact padding (card.json upstream-bug).
card_open :: proc(
	gtx: ^ui.Ctx,
	heading: string,
	description := "",
	icon := Icon.None,
	image := Card_Image{},
	padding := Card_Padding.Normal,
	radius := Card_Radius.Large,
	layout := Card_Layout.Default,
	standalone := false,
	key: u64 = 0,
	loc := #caller_location,
) -> (c: Card) {
	c.gtx = gtx
	c.place = ui.widget_open(gtx, key, loc)
	c.compact = layout == .Compact
	c.radius = radius == .Large ? tok.BORDER_RADIUS_LARGE : tok.BORDER_RADIUS_MEDIUM
	c.standalone = standalone
	c.heading = heading
	pad := card_padding(padding, layout)
	cs := gtx.constraints
	width := ui.is_finite(cs.max.x) ? cs.max.x : 0
	body_cs := ui.Constraints{max = {ui.INF, ui.INF}}
	if width > 0 {
		body_cs = {min = {width, 0}, max = {width, ui.INF}}
	}
	c.rec = ui.record_open(gtx, body_cs)
	c.inset = ui.inset_open(gtx, {pad, pad, pad, pad})
	if c.compact {
		c.outer = ui.row_open(gtx, gap = tok.STACK_GAP_CONDENSED, align = .Start)
		if icon != .None {
			card_icon(gtx, icon, false)
		}
		ui.flexible(gtx, 1)
	} else {
		c.outer = ui.column_open(gtx, gap = tok.STACK_GAP_NORMAL, align = .Fill)
		switch {
		case image.size.x > 0:
			card_image(gtx, image, pad, width)
		case icon != .None:
			card_icon(gtx, icon, true)
		}
	}
	c.body = ui.column_open(gtx, gap = tok.STACK_GAP_NORMAL, align = .Fill)
	if heading != "" || description != "" {
		content := ui.column_open(gtx, gap = tok.STACK_GAP_CONDENSED, align = .Fill)
		if heading != "" {
			st := style(.Title_Small)
			if c.compact {
				st.size = tok.TEXT_BODY_SIZE_MEDIUM
			}
			layout_text(gtx, heading, st, color(.Fg_Color_Default), .Heading, lift = c.compact ? tok.BASE_SIZE_4 : 0, tagged = false)
		}
		if description != "" {
			layout_text(gtx, description, style(.Body_Medium), color(.Fg_Color_Muted), .Text)
		}
		ui.close(&content)
	}
	return
}

// card_close closes the card: it paints the box under the content, clips
// the content to it, then places the action over it.
card_close :: proc(c: ^Card) {
	gtx := c.gtx
	ui.close(&c.body)
	ui.close(&c.outer)
	ui.close(&c.inset)
	body, d := ui.record_close(&c.rec)
	size := ui.constrain(c.place.given, d.size)
	rr := ops.Round_Rect{{0, 0, size.x, size.y}, c.radius}
	paint_shadow(gtx, rr, tok.SHADOW_RESTING_SMALL)
	ops.fill(gtx.scene, rr, color(.Bg_Color_Default))
	b := tok.BORDER_WIDTH_THIN
	ops.clip_push(gtx.scene, ops.Round_Rect{{b, b, size.x - 2 * b, size.y - 2 * b}, max(c.radius - b, 0)})
	ops.call(gtx.scene, body)
	ops.clip_pop(gtx.scene)
	stroke_inside(gtx, rr, color(.Border_Color_Default), b)
	if c.has_action {
		at := ops.Point{size.x - tok.BASE_SIZE_16 - c.action_size.x, tok.BASE_SIZE_16}
		ops.transform_push(gtx.scene, ops.translate(at.x, at.y))
		ops.call(gtx.scene, c.action)
		ops.transform_pop(gtx.scene)
	}
	if c.standalone {
		ui.semantics(gtx, &c.place, {role = .Region, label = ui.frame_string(gtx, c.heading)})
	}
	ops.tag(gtx.scene, c.place.id, ui.frame_string(gtx, c.heading), {0, 0, size.x, size.y})
	ui.widget_close(gtx, &c.place, {size, d.baseline})
}

// card_action_open starts the card's one action, a control the caller
// lays out (an icon button labelled with the card's name) up to
// card_action_close. It sits 16px from the card's top and right edges,
// above the content, whatever the padding; nothing reserves room for it
// (card.json gotcha).
card_action_open :: proc(c: ^Card) {
	c.action_rec = ui.record_open(c.gtx, {max = {ui.INF, ui.INF}})
}

// card_action_close ends the card's action.
card_action_close :: proc(c: ^Card) {
	m, d := ui.record_close(&c.action_rec)
	c.action, c.action_size, c.has_action = m, d.size, true
}

// card_metadata_open opens the card's metadata row: items centred,
// --stack-gap-normal apart (Card.module.css:118-131). Fill it with
// card_metadata_item or any small control; close it with
// card_metadata_close.
card_metadata_open :: proc(c: ^Card) {
	c.metadata = ui.row_open(c.gtx, gap = tok.STACK_GAP_NORMAL, align = .Center)
}

// card_metadata_close closes the metadata row.
card_metadata_close :: proc(c: ^Card) {
	ui.close(&c.metadata)
}

// card_metadata_item is one metadata item: an optional 16px octicon then
// text, --stack-gap-condensed apart, in small muted body text.
card_metadata_item :: proc(gtx: ^ui.Ctx, text: string, ic := Icon.None, key: u64 = 0, loc := #caller_location) {
	p := ui.widget_open(gtx, key, loc)
	st := style(.Body_Small)
	t := design.shape_style(gtx, text, st, font_for(gtx, st.weight))
	h := max(t.height, BUTTON_ICON)
	x: f32
	muted := color(.Fg_Color_Muted)
	if ic != .None {
		icon(gtx, ic, {0, (h - BUTTON_ICON) / 2}, BUTTON_ICON, muted)
		x = BUTTON_ICON + tok.STACK_GAP_CONDENSED
	}
	draw_text(gtx, t, {x, (h - t.height) / 2}, muted)
	size := ui.constrain(gtx.constraints, {x + t.width, h})
	said := ui.frame_string(gtx, text)
	ops.tag(gtx.scene, p.id, said, {0, 0, size.x, size.y})
	ui.semantics(gtx, &p, {role = .Text, label = said})
	ui.widget_close(gtx, &p, {size, (h - t.height) / 2 + baseline_of(t)})
}

// card_icon is the card's icon: in a 32px --bgColor-muted tile with
// medium corners in the default layout, bare in compact, --fgColor-muted.
@(private)
card_icon :: proc(gtx: ^ui.Ctx, ic: Icon, tile: bool, loc := #caller_location) {
	p := ui.widget_open(gtx, 0, loc)
	side := tile ? CARD_ICON_TILE : BUTTON_ICON
	if tile {
		ops.fill(gtx.scene, ops.Round_Rect{{0, 0, side, side}, tok.BORDER_RADIUS_MEDIUM}, color(.Bg_Color_Muted))
	}
	at := (side - BUTTON_ICON) / 2
	icon(gtx, ic, {at, at}, BUTTON_ICON, color(.Fg_Color_Muted))
	ui.widget_close(gtx, &p, {size = {side, side}})
}

// card_image is the edge-to-edge image: as wide as the card, at its
// natural aspect ratio, pulled out over the padding at the top and
// sides; it takes its height less the top padding in the column.
@(private)
card_image :: proc(gtx: ^ui.Ctx, img: Card_Image, pad, card_width: f32, loc := #caller_location) {
	p := ui.widget_open(gtx, 0, loc)
	w := card_width > 0 ? card_width : img.size.x
	h := w * img.size.y / img.size.x
	ops.image(gtx.scene, img.id, ops.Rect{-pad, -pad, w, h})
	ui.semantics(gtx, &p, {role = .Image})
	ui.widget_close(gtx, &p, {size = {max(w - 2 * pad, 0), max(h - pad, 0)}})
}

// layout_text is a block of text in st and ink, wrapped at the width
// offered, announced as role; lift draws it that much above its box,
// as CSS's position: relative with a negative top moves a box without
// moving what follows. It is tagged by its text unless its container
// already is (a card by its heading).
@(private)
layout_text :: proc(gtx: ^ui.Ctx, s: string, st: tok.Type_Style, ink: ops.Color, role: ops.Role, lift: f32 = 0, tagged := true, spoken := "", key: u64 = 0, loc := #caller_location) -> ui.Dims {
	p := ui.widget_open(gtx, key, loc)
	cs := gtx.constraints
	wrap := ui.is_finite(cs.max.x) ? cs.max.x : 0
	para := design.layout_style(gtx, s, st, font_for(gtx, st.weight), wrap)
	draw_paragraph(gtx, para, {0, -lift}, ink)
	size := ui.constrain(cs, {para.width, para.height})
	said := ui.frame_string(gtx, s)
	if tagged {
		ops.tag(gtx.scene, p.id, said, {0, -lift, size.x, size.y})
	}
	ui.semantics(gtx, &p, {role = role, label = spoken != "" ? ui.frame_string(gtx, spoken) : said})
	base: f32
	if len(para.lines) > 0 {
		base = (para.pitch - para.metrics.ascent - para.metrics.descent) / 2 + para.metrics.ascent - lift
	}
	return ui.widget_close(gtx, &p, {size, base})
}

// Header is an open Header bar.
Header :: struct {
	gtx:   ^ui.Ctx,
	rec:   ui.Recording,
	row:   ui.Flex,
	width: f32,
	key:   u64,
}

// HEADER_LINE is the bar's line height: --text-body-size-medium at
// --text-title-lineHeight-large, 21px (Header.module.css:1-12).
HEADER_LINE :: tok.TEXT_BODY_SIZE_MEDIUM * tok.TEXT_TITLE_LINE_HEIGHT_LARGE

// header_open opens Primer's Header (header.json, Header.module.css):
// GitHub's dark global bar on --header-bgColor in every theme, a
// non-wrapping row of items centred down it, 16px padding all round,
// scrolling sideways when its items overflow it. Add items with
// header_item_open; close it with header_close.
header_open :: proc(gtx: ^ui.Ctx, key: u64 = 0, loc := #caller_location) -> (h: Header) {
	h.gtx = gtx
	h.key = key
	cs := ui.offer(gtx)
	h.width = ui.is_finite(cs.max.x) ? cs.max.x : 0
	pad := tok.BASE_SIZE_16
	inner := max(h.width - 2 * pad, 0)
	h.rec = ui.record_open(gtx, {min = {inner, 0}, max = {ui.INF, ui.INF}}, key, loc)
	h.row = ui.row_open(gtx, align = .Center)
	return
}

// header_close closes the bar: it lays the recorded row out in a box
// that scrolls sideways when the row is wider than the bar.
header_close :: proc(h: ^Header, loc := #caller_location) {
	gtx := h.gtx
	ui.close(&h.row)
	row, d := ui.record_close(&h.rec)
	pad := tok.BASE_SIZE_16
	height := d.size.y + 2 * pad
	width := h.width > 0 ? h.width : d.size.x + 2 * pad
	bar := ui.sized_open(gtx, {min = {width, height}, max = {width, height}}, h.key, loc)
	defer ui.close(&bar)
	ops.fill(gtx.scene, ops.Rect{0, 0, width, height}, color(.Header_Bg_Color))
	ui.container_semantics(gtx, {role = .Group, label = "Header"})
	sb := ui.scroll_box_open(gtx, key = h.key, wide = true)
	defer ui.close(&sb)
	place_recording(gtx, row, d.size + {2 * pad, 2 * pad}, {pad, pad})
}

// place_recording is a widget size big that calls a recorded run at at.
@(private)
place_recording :: proc(gtx: ^ui.Ctx, m: ops.Macro_Id, size: ops.Size, at: ops.Point, key: u64 = 0, loc := #caller_location) {
	p := ui.widget_open(gtx, key, loc)
	ops.transform_push(gtx.scene, ops.translate(at.x, at.y))
	ops.call(gtx.scene, m)
	ops.transform_pop(gtx.scene)
	ui.widget_close(gtx, &p, {size = size})
}

// Header_Item is an open header item.
Header_Item :: struct {
	inset: ui.Inset,
	row:   ui.Flex,
	gtx:   ^ui.Ctx,
	full:  bool,
}

// header_item_open opens one Header.Item: its content centred in a row,
// 16px after it, the last item too (Header.module.css:14-24). A full
// item takes the bar's free width, pushing later items to the end.
// Close it with header_item_close.
header_item_open :: proc(gtx: ^ui.Ctx, full := false, key: u64 = 0, loc := #caller_location) -> (it: Header_Item) {
	it.gtx, it.full = gtx, full
	it.inset = ui.inset_open(gtx, {0, 0, tok.BASE_SIZE_16, 0}, key, loc)
	it.row = ui.row_open(gtx, gap = tok.BASE_SIZE_8, align = .Center)
	return
}

// header_item_close closes a header item.
header_item_close :: proc(it: ^Header_Item) {
	ui.close(&it.row)
	ui.close(&it.inset)
	if it.full {
		ui.fill_space(it.gtx)
	}
}

// header_link is a Header.Link: a 16px-tall-text link of an optional
// octicon (icon_size px) then label, at --text-title-weight-large in
// --header-fgColor-logo, dimming to --header-fgColor-default while hovered
// or focused (Header.module.css:26-38). Returns true on the frame it is
// activated by a click, Enter or Space.
//
// Departures: the icon is followed by 8px (--base-size-8); the module
// sets no gap and leaves spacing to the caller. A keyboard focus draws
// Primer's focus outline, which the module leaves to GitHub's global
// styles (header.json inferred).
header_link :: proc(gtx: ^ui.Ctx, label: string, ic := Icon.None, icon_size: f32 = 32, state := Interaction.Live, key: u64 = 0, loc := #caller_location) -> bool {
	p := ui.widget_open(gtx, key, loc)
	st := tok.Type_Style{weight = tok.TEXT_TITLE_WEIGHT_LARGE, size = tok.TEXT_BODY_SIZE_MEDIUM, line_height = HEADER_LINE}
	t := design.shape_style(gtx, label, st, font_for(gtx, st.weight))
	w, h := t.width, max(HEADER_LINE, ic != .None ? icon_size : 0)
	x: f32
	if ic != .None {
		x = icon_width(ic, icon_size) + (label != "" ? tok.BASE_SIZE_8 : 0)
		w += x
	}
	sz := ui.constrain_min(gtx.constraints, {w, h})
	area := ops.Rect{0, 0, sz.x, sz.y}
	c := control(gtx, p.id, area, state)
	dim := c.state == .Hovered || c.state == .Focused || c.state == .Pressed
	ink := color(dim ? .Header_Fg_Color_Default : .Header_Fg_Color_Logo)
	if ic != .None {
		icon(gtx, ic, {0, (sz.y - icon_size) / 2}, icon_size, ink)
	}
	draw_text(gtx, t, {x, (sz.y - t.height) / 2}, ink)
	paint_focus_outline(gtx, c, {area, tok.BORDER_RADIUS_SMALL})
	listen(gtx, c.st, p.id, area, cursor = .Pointer)
	said := ui.frame_string(gtx, label)
	ops.tag(gtx.scene, p.id, said)
	ui.semantics(gtx, &p, {role = .Link, label = said, states = design.state_if(c.disabled, {.Disabled})})
	ui.widget_close(gtx, &p, {sz, (sz.y - t.height) / 2 + baseline_of(t)})
	return c.clicked
}
