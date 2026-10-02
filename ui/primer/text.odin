package primer

import "base:runtime"
import "jm:ui"
import "jm:ui/design"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// Primer's text components: Heading and Text set type from the scale,
// Truncate clips one line. CSS gives each its style by inheritance and
// jm:ui has none, so where Primer inherits (Text with no size, a
// Heading's line height, every colour) these take the page's own
// default: 14px body text at BaseStyles' 1.5 line height in
// --fgColor-default (BaseStyles.module.css:56-60), which a caller
// overrides with the size and color parameters.

// BASE_LINE_HEIGHT is the page's line height, a ratio of the font size:
// BaseStyles sets 1.5 (BaseStyles.module.css:58), the normal base token.
BASE_LINE_HEIGHT :: tok.BASE_TEXT_LINE_HEIGHT_NORMAL

// Text_Align is where a text block's lines sit across its box.
Text_Align :: enum u8 {
	Start,
	Center,
}

// Text_Block is how text_block lays out and describes a run of text.
@(private)
Text_Block :: struct {
	style:     tok.Type_Style,
	color:     ops.Color,
	wrap:      bool, // wrap at the width offered
	balance:   bool, // even the lines out (text-wrap: balance)
	align:     Text_Align,
	semantics: ops.Semantics, // the role and level; the label is the text
}

// text_block is one paragraph of s as a widget: wrapped at the width
// offered when b.wrap, as wide as its widest line, its lines aligned by
// b.align, selectable, tagged with s and described by b.semantics. Empty
// text takes no space, as an empty element has no line box.
@(private)
text_block :: proc(gtx: ^ui.Ctx, s: string, b: Text_Block, key: u64, loc: runtime.Source_Code_Location) -> ui.Dims {
	p := ui.widget_open(gtx, key, loc)
	if s == "" {
		return ui.widget_close(gtx, &p, {})
	}
	cs := gtx.constraints
	width := ui.is_finite(cs.max.x) && b.wrap ? cs.max.x : 0
	para := design.layout_style(gtx, s, b.style, font_for(gtx, b.style.weight), width, balance = b.balance)
	sz := ui.constrain(cs, {para.width, para.height})
	if b.align == .Center {
		for &ln in para.lines {
			ln.x = (sz.x - ln.width) / 2
		}
	}
	paint_block(gtx, p.id, para, sz, b.color)
	said := ui.frame_string(gtx, s)
	ops.tag(gtx.scene, p.id, said, {0, 0, sz.x, sz.y})
	sem := b.semantics
	sem.label = said
	ui.semantics(gtx, &p, sem)
	return ui.widget_close(gtx, &p, {sz, para.lines[0].baseline})
}

// paint_block draws para selectable in color inside a box sz, clipped to
// it when the text runs past (a word wider than the box, a line that
// does not wrap).
@(private)
paint_block :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, para: ui.Paragraph, sz: ops.Size, color: ops.Color) {
	clipped := para.width > sz.x + 0.5 || para.height > sz.y + 0.5
	if clipped {
		ops.clip_push(gtx.scene, ops.Rect{0, 0, sz.x, sz.y})
	}
	lo, hi, focused := ui.selectable_text(gtx, id, para, {}, {0, 0, sz.x, sz.y})
	draw_paragraph(gtx, para, {}, color, selection_colors(lo, hi, focused))
	if clipped {
		ops.clip_pop(gtx.scene)
	}
}

// Heading_Variant is a heading's title preset (heading.json variants).
// Default is 32px semibold at the page's line height; Large is the same
// size and weight at the title-large line box, 48px, which BaseStyles'
// 1.5 also makes, so the two differ only in the family the web sets.
Heading_Variant :: enum u8 {
	Default,
	Large,
	Medium,
	Small,
}

// heading_style is v's type (Heading.module.css:1-16).
heading_style :: proc(v: Heading_Variant) -> tok.Type_Style {
	switch v {
	case .Large:
		return tok.TEXT_TITLE_SHORTHAND_LARGE
	case .Medium:
		return tok.TEXT_TITLE_SHORTHAND_MEDIUM
	case .Small:
		return tok.TEXT_TITLE_SHORTHAND_SMALL
	case .Default:
	}
	size := tok.TEXT_TITLE_SIZE_LARGE
	return {weight = tok.BASE_TEXT_WEIGHT_SEMIBOLD, size = size, line_height = size * BASE_LINE_HEIGHT}
}

// heading is a section title (primer-kit components/heading.json,
// Heading.module.css:1-17): text in a title preset with no margin,
// wrapping at the width offered. level (1 to 6, h2 by default) is its
// place in the page's outline, told to assistive technology; variant is
// its look, chosen apart from the level. color defaults to
// --fgColor-default, the colour a heading inherits on the page.
heading :: proc(gtx: ^ui.Ctx, s: string, level := 2, variant := Heading_Variant.Default, color := ops.Color{}, key: u64 = 0, loc := #caller_location) -> ui.Dims {
	lv := u8(clamp(level, 1, 6))
	b := Text_Block {
		style = heading_style(variant),
		color = ui.or_color(color, primer_fg()),
		wrap = true,
		semantics = {role = .Heading, level = lv},
	}
	return text_block(gtx, s, b, key, loc)
}

// primer_fg is the page's text colour, which Primer's text inherits.
@(private)
primer_fg :: proc() -> ops.Color {
	return color(.Fg_Color_Default)
}

// Text_Size is a body size: 12px over 19.5, 14px over 21 or 16px over 24
// (text.json variants).
Text_Size :: enum u8 {
	Small,
	Medium,
	Large,
}

// Text_Weight is a weight on the base scale: 300, 400, 500 or 600. jm:ui
// draws in the faces use_fonts gives, so light draws in the nearest, the
// normal face, as a browser falls back without a 300 face (text.json
// notes).
Text_Weight :: enum u8 {
	Normal,
	Light,
	Medium,
	Semibold,
}

// White_Space is ui's: CSS's five white-space modes.
White_Space :: ui.White_Space

// text_style is the type for a body size at a weight (Text.module.css
// :2-32): the size's font size and line height, set from the separate
// tokens rather than a shorthand.
text_style :: proc(size := Text_Size.Medium, weight := Text_Weight.Normal) -> tok.Type_Style {
	st: tok.Type_Style
	switch size {
	case .Small:
		st = {size = tok.TEXT_BODY_SIZE_SMALL, line_height = tok.TEXT_BODY_SIZE_SMALL * tok.TEXT_BODY_LINE_HEIGHT_SMALL}
	case .Medium:
		st = {size = tok.TEXT_BODY_SIZE_MEDIUM, line_height = tok.TEXT_BODY_SIZE_MEDIUM * tok.TEXT_BODY_LINE_HEIGHT_MEDIUM}
	case .Large:
		st = {size = tok.TEXT_BODY_SIZE_LARGE, line_height = tok.TEXT_BODY_SIZE_LARGE * tok.TEXT_BODY_LINE_HEIGHT_LARGE}
	}
	switch weight {
	case .Normal:
		st.weight = tok.BASE_TEXT_WEIGHT_NORMAL
	case .Light:
		st.weight = tok.BASE_TEXT_WEIGHT_LIGHT
	case .Medium:
		st.weight = tok.BASE_TEXT_WEIGHT_MEDIUM
	case .Semibold:
		st.weight = tok.BASE_TEXT_WEIGHT_SEMIBOLD
	}
	return st
}

// text is a run of body text (primer-kit components/text.json,
// Text.module.css): a size, a weight and a white-space mode, in color
// (--fgColor-default unless given). It is as wide as its widest line,
// wrapping at the width offered unless white_space is Nowrap or Pre.
//
// Departures: Primer's Text inherits any unset size, weight and colour
// from its parent; jm:ui has no inherited text style, so an unset one is
// the page's (body medium, normal, --fgColor-default). The element it
// renders as (span, p) is not modelled: it changes neither the look nor
// the semantics here, which are plain text.
text :: proc(
	gtx: ^ui.Ctx,
	s: string,
	size := Text_Size.Medium,
	weight := Text_Weight.Normal,
	white_space := White_Space.Normal,
	color := ops.Color{},
	key: u64 = 0,
	loc := #caller_location,
) -> ui.Dims {
	b := Text_Block {
		style = text_style(size, weight),
		color = ui.or_color(color, primer_fg()),
		wrap = ui.white_space_wraps(white_space),
		semantics = {role = .Text},
	}
	return text_block(gtx, ui.white_space_text(s, white_space, gtx.allocator), b, key, loc)
}

// TRUNCATE_MAX_WIDTH is Truncate's default cap, 125px, and
// TRUNCATE_EXPANDED its cap while an expandable one is hovered, 10000px:
// literals with no token (Truncate.tsx:14, Truncate.module.css:9).
TRUNCATE_MAX_WIDTH :: f32(125)
TRUNCATE_EXPANDED :: f32(10000)

// Truncate_Hover is whether the pointer is over an expandable Truncate.
@(private)
Truncate_Hover :: struct {
	over: bool,
}

// TRUNCATE_OBSERVER mixes a Truncate's id into its hover observer's: the
// widget's own id is its selectable text's area.
@(private)
TRUNCATE_OBSERVER :: u64(0x7472756e63617465)

// truncate is one line of s cut to max_width with an ellipsis (primer-kit
// components/truncate.json, Truncate.module.css): spaces and line breaks
// collapse and the line never wraps. As a block it is as wide as it is
// offered up to max_width; inline it hugs its text up to max_width. An
// expandable one lifts the cap to 10000px while the pointer is over it,
// at once, so the whole line shows; it watches the pointer through an
// observer, so the control or text under it keeps its hover, and the
// keyboard never expands it. title is the full text a reader is told as
// the description. Assistive technology reads all of s; the cut is
// visual only. The text takes size and weight in color, the page's body
// text by default.
//
// Departures: the title's native hover tooltip is not drawn: Primer's
// Tooltip is not built yet and jm:ui has no platform tooltip, so the
// title reaches only assistive technology. max_width is pixels; for a
// CSS length such as 100%, pass ui.INF and the offered width caps it.
truncate :: proc(
	gtx: ^ui.Ctx,
	s: string,
	title := "",
	max_width := TRUNCATE_MAX_WIDTH,
	inline := false,
	expandable := false,
	size := Text_Size.Medium,
	weight := Text_Weight.Normal,
	color := ops.Color{},
	key: u64 = 0,
	loc := #caller_location,
) -> ui.Dims {
	p := ui.widget_open(gtx, key, loc)
	cs := gtx.constraints
	watch := ui.id_mix(p.id, TRUNCATE_OBSERVER)
	hover := ui.widget_data(gtx, p.id, Truncate_Hover)
	for e in ui.events(gtx, watch) {
		#partial switch e.kind {
		case .Enter:
			hover.over = true
		case .Leave:
			hover.over = false
		}
	}
	limit := expandable && hover.over ? TRUNCATE_EXPANDED : max_width
	if ui.is_finite(cs.max.x) {
		limit = min(limit, cs.max.x)
	}
	st := text_style(size, weight)
	line := ui.white_space_text(s, .Nowrap, gtx.allocator)
	para := design.layout_style(gtx, line, st, font_for(gtx, st.weight), limit if ui.is_finite(limit) else 0, max_lines = 1)
	w := para.truncated || !inline ? limit : para.width
	if !ui.is_finite(w) {
		w = para.width
	}
	sz := ui.constrain(cs, {w, para.height})
	paint_block(gtx, p.id, para, sz, ui.or_color(color, primer_fg()))
	if expandable {
		ops.observer_area(gtx.scene, watch, ops.Rect{0, 0, sz.x, sz.y})
	}
	said := ui.frame_string(gtx, s)
	ops.tag(gtx.scene, p.id, said, {0, 0, sz.x, sz.y})
	ui.semantics(gtx, &p, {role = .Text, label = said, description = ui.frame_string(gtx, title)})
	return ui.widget_close(gtx, &p, {sz, para.lines[0].baseline})
}
