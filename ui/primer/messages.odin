package primer

import "base:runtime"

import "jm:ui"
import "jm:ui/design"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// Primer's messages: Banner, InlineMessage, Blankslate and Timeline.
// Banner, Blankslate and Timeline change their layout at their own
// width, a CSS container query; jm:ui hands a widget the width it is
// offered before it lays out its children (gtx.constraints), which is
// that width for a block, so each reads it there.

// Inline_Size is an InlineMessage's text: 12px or 14px body.
Inline_Size :: enum u8 {
	Small,
	Medium,
}

// Inline_Variant is an InlineMessage's intent; None is a neutral note in
// the default foreground.
Inline_Variant :: enum u8 {
	None,
	Critical,
	Warning,
	Success,
	Unavailable,
}

// INLINE_TEXT mixes an InlineMessage's id into its selectable text's.
@(private)
INLINE_TEXT :: u64(0x696e6c696e65)

// INLINE_GAP is the gap between the icon and the message, a hard-coded
// 0.5rem (InlineMessage.module.css:9).
INLINE_GAP :: f32(8)

// inline_variant_look is v's foreground and icon at size
// (InlineMessage.module.css:13-39, InlineMessage.tsx:25-60): the four
// variants take 12px filled icons at small, no variant InfoIcon at 16px
// at both sizes.
@(private)
inline_variant_look :: proc(v: Inline_Variant, size: Inline_Size) -> (fg: tok.Role, ic: Icon, side: f32) {
	small := size == .Small
	side = small ? 12 : 16
	switch v {
	case .None:
		return .Fg_Color_Default, .Info, 16
	case .Critical:
		fg = .Fg_Color_Danger
		ic = small ? .Alert_Fill : .Alert
	case .Warning:
		fg = .Fg_Color_Attention
		ic = small ? .Alert_Fill : .Alert
	case .Success:
		fg = .Fg_Color_Success
		ic = small ? .Check_Circle_Fill : .Check_Circle
	case .Unavailable:
		fg = .Fg_Color_Muted
		ic = small ? .Alert_Fill : .Alert
	}
	return
}

// inline_message is a short status line beside what it describes
// (primer-kit components/inline-message.json, InlineMessage.module.css):
// an icon, then the message wrapping in the rest of the width offered,
// 8px apart, both in the variant's foreground. The icon is centred on
// the first line however many the message takes. leading replaces the
// variant's icon, at 16px at either size as Primer draws a component
// icon. Static: no role beyond its text, no live region.
inline_message :: proc(gtx: ^ui.Ctx, message: string, variant := Inline_Variant.None, size := Inline_Size.Medium, leading := Icon.None, key: u64 = 0, loc := #caller_location) -> ui.Dims {
	p := ui.widget_open(gtx, key, loc)
	fg_role, ic, side := inline_variant_look(variant, size)
	if leading != .None {
		ic, side = leading, 16
	}
	st := text_style(size == .Small ? .Small : .Medium)
	fg := color(fg_role)
	cs := gtx.constraints
	iw := icon_width(ic, side)
	tx := iw + INLINE_GAP
	width: f32 = 0
	if ui.is_finite(cs.max.x) {
		width = max(cs.max.x - tx, 1)
	}
	para := design.layout_style(gtx, message, st, font_for(gtx, st.weight), width)
	sz := ui.constrain(cs, {tx + para.width, max(st.line_height, para.height)})
	icon(gtx, ic, {0, (st.line_height - side) / 2}, side, fg)
	ops.transform_push(gtx.scene, ops.translate(tx, 0))
	// The text's own area, so the widget's tag measures icon and text.
	paint_block(gtx, ui.id_mix(p.id, INLINE_TEXT), para, {sz.x - tx, sz.y}, fg)
	ops.transform_pop(gtx.scene)
	said := ui.frame_string(gtx, message)
	ops.tag(gtx.scene, p.id, said, {0, 0, sz.x, sz.y})
	ui.semantics(gtx, &p, {role = .Text, label = said})
	return ui.widget_close(gtx, &p, {sz, para.lines[0].baseline})
}

// Banner_Variant is a Banner's intent.
Banner_Variant :: enum u8 {
	Info,
	Critical,
	Success,
	Upsell,
	Warning,
}

// Banner_Layout is a Banner's padding: 8px, or 4px compact.
Banner_Layout :: enum u8 {
	Default,
	Compact,
}

// Banner_Actions is where a Banner's actions go: Default beside the
// content when the banner's content box is at least 500px wide, under it
// below that; Inline beside it unless the window is narrow; Stacked
// always under it.
Banner_Actions :: enum u8 {
	Default,
	Inline,
	Stacked,
}

// Banner_Event is what a Banner's user did this frame.
Banner_Event :: enum u8 {
	None,
	Primary,
	Secondary,
	Dismiss,
}

// BANNER_CONTAINER_BREAKPOINT is the content-box width from which a
// default banner puts its actions beside the content, and
// BANNER_ACTIONS_MIN_HEIGHT their row's height there (Banner.module.css
// :223-265, 500 a literal; 500 itself counts as wide).
BANNER_CONTAINER_BREAKPOINT :: f32(500)
BANNER_ACTIONS_MIN_HEIGHT :: tok.BASE_SIZE_32

// banner_roles is v's fill, border and icon colour (Banner.module.css
// :74-102).
@(private)
banner_roles :: proc(v: Banner_Variant) -> (bg, border, fg: tok.Role) {
	switch v {
	case .Info:
		return .Bg_Color_Accent_Muted, .Border_Color_Accent_Muted, .Fg_Color_Accent
	case .Critical:
		return .Bg_Color_Danger_Muted, .Border_Color_Danger_Muted, .Fg_Color_Danger
	case .Success:
		return .Bg_Color_Success_Muted, .Border_Color_Success_Muted, .Fg_Color_Success
	case .Upsell:
		return .Bg_Color_Upsell_Muted, .Border_Color_Upsell_Muted, .Fg_Color_Upsell
	case .Warning:
	}
	return .Bg_Color_Attention_Muted, .Border_Color_Attention_Muted, .Fg_Color_Attention
}

// banner_icon is v's icon; only info and upsell take a custom one
// (Banner.tsx:131,172-174).
@(private)
banner_icon :: proc(v: Banner_Variant, leading: Icon) -> Icon {
	switch v {
	case .Critical:
		return .Stop
	case .Success:
		return .Check_Circle
	case .Warning:
		return .Alert
	case .Info, .Upsell:
	}
	return leading != .None ? leading : .Info
}

// Banner_Placement is where a banner's actions went this frame: beside
// the content (secondary then primary) or under it (primary first), and
// the space under them.
@(private)
Banner_Placement :: struct {
	beside:   bool,
	below:    f32, // the actions' bottom margin
	min_tall: bool, // the 32px row a wide default banner gives them
}

// banner_placement decides the actions' place from the banner's content
// width and the window's (Banner.module.css:18-62,121-125,205-265): a
// dismissible banner with a visible title stacks whatever its width,
// unless Inline, which follows only the window.
@(private)
banner_placement :: proc(gtx: ^ui.Ctx, content_w: f32, layout: Banner_Actions, dismissible, hide_title: bool) -> (pl: Banner_Placement) {
	narrow_window := gtx.viewport.x > 0 && gtx.viewport.x < tok.BREAKPOINT_MEDIUM
	switch {
	case layout == .Inline:
		pl.beside = !narrow_window
		pl.below = tok.BASE_SIZE_2
	case dismissible && !hide_title:
		pl.below = tok.BASE_SIZE_6
	case layout == .Stacked:
		pl.below = tok.BASE_SIZE_2
	case !ui.is_finite(content_w) || content_w >= BANNER_CONTAINER_BREAKPOINT:
		pl.beside, pl.min_tall = true, true
		pl.below = tok.BASE_SIZE_2
	case:
		pl.below = tok.BASE_SIZE_6
	}
	return
}

// Banner_Paint is a banner's surface, painted once its size is known.
@(private)
Banner_Paint :: struct {
	bg, border: ops.Color,
	flush:      bool,
}

@(private)
paint_banner :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, size: ops.Size, user: rawptr) {
	bp := (^Banner_Paint)(user)
	r := ops.Rect{0, 0, size.x, size.y}
	b := tok.BORDER_WIDTH_THIN
	if bp.flush {
		// No side borders and no radius (Banner.module.css:68-72).
		ops.fill(gtx.scene, r, bp.bg)
		ops.fill(gtx.scene, ops.Rect{0, 0, size.x, b}, bp.border)
		ops.fill(gtx.scene, ops.Rect{0, size.y - b, size.x, b}, bp.border)
		return
	}
	rr := ops.Round_Rect{r, tok.BORDER_RADIUS_MEDIUM}
	ops.fill(gtx.scene, rr, bp.bg)
	stroke_inside(gtx, rr, bp.border, b)
}

// Banner_Look is how a banner's parts are drawn this frame.
@(private)
Banner_Look :: struct {
	variant:     Banner_Variant,
	fg:          tok.Role,
	pl:          Banner_Placement,
	has_actions: bool,
	hide_title:  bool,
	level:       u8,
}

// BANNER_GLYPH is the banner icon's glyph, centred in a box 16px wide
// and 20px tall (16 with the title hidden and no actions): the CSS sets
// only the svg's height (Banner.module.css:154-172; banner.json notes
// this is inferred).
@(private)
BANNER_GLYPH :: tok.BASE_SIZE_16

// banner is a page- or section-level message (primer-kit
// components/banner.json, Banner.module.css, Banner.tsx): a bordered,
// tinted block with the variant's icon, a semibold title, a description,
// up to two actions (primary a default Button, secondary an invisible
// one) and, when dismissible, an invisible X button. It is as wide as it
// is offered and chooses where the actions go from that width (see
// Banner_Actions); they are drawn once, in the order that place takes.
// The banner is a region landmark named by its title, which is a heading
// at title_level (2 to 6) and, with hide_title, is told to assistive
// technology but not drawn. leading replaces the info and upsell icon.
// Returns the action taken this frame; the caller removes a dismissed
// banner.
//
// Departures: the description is plain text, where Primer takes any
// children after it; the banner cannot be focused programmatically
// (tabIndex -1), as jm:ui has no focus target that is not a control;
// below a 544px window the content keeps filling the row beside inline
// actions (Banner.module.css:140-144), a case inline never reaches, as
// it stacks below 768px (:49-61, --viewportRange-narrow).
banner :: proc(
	gtx: ^ui.Ctx,
	title: string,
	description := "",
	variant := Banner_Variant.Info,
	leading := Icon.None,
	primary := "",
	secondary := "",
	dismissible := false,
	layout := Banner_Layout.Default,
	actions := Banner_Actions.Default,
	flush := false,
	hide_title := false,
	title_level := 2,
	key: u64 = 0,
	loc := #caller_location,
) -> (event: Banner_Event) {
	pad := layout == .Compact ? tok.BASE_SIZE_4 : tok.BASE_SIZE_8
	edge := pad + tok.BORDER_WIDTH_THIN
	bg, border, fg := banner_roles(variant)
	bp := new(Banner_Paint, gtx.allocator)
	bp^ = {color(bg), color(border), flush}
	box := ui.box_open(gtx, {padding = ui.pad_all(edge), paint = paint_banner, user = bp}, key, loc)
	defer ui.close(&box)
	// Until its first child opens, gtx.constraints is what the banner was
	// offered: its width, less padding and border, is the content box the
	// 500px rule measures.
	content_w := gtx.constraints.max.x - 2 * edge
	look := Banner_Look {
		variant     = variant,
		fg          = fg,
		pl          = banner_placement(gtx, content_w, actions, dismissible, hide_title),
		has_actions = primary != "" || secondary != "",
		hide_title  = hide_title,
		level       = u8(clamp(title_level, 2, 6)),
	}
	ui.container_semantics(gtx, {role = .Region, label = ui.frame_string(gtx, title)})
	row := ui.row_open(gtx)
	defer ui.close(&row)
	banner_icon_cell(gtx, banner_icon(variant, leading), look)
	ui.flexible(gtx, 1)
	event = banner_body(gtx, title, description, primary, secondary, look)
	if dismissible {
		top := look.has_actions ? tok.BASE_SIZE_2 : 0
		in_ := ui.inset_open(gtx, {left = tok.BASE_SIZE_4, top = top})
		defer ui.close(&in_)
		same := State_Roles{fg, fg, fg, .Control_Fg_Color_Disabled}
		r := variant_roles(.Invisible)
		r.visual = same
		if icon_button_in(gtx, .X, "Dismiss banner", .Invisible, .Medium, r, {state = .Live}, 0, #location()) {
			event = .Dismiss
		}
	}
	return
}

// banner_icon_cell is the icon in its 8px-padded cell, centred on the
// title's first line.
@(private)
banner_icon_cell :: proc(gtx: ^ui.Ctx, ic: Icon, look: Banner_Look, loc := #caller_location) {
	p := ui.widget_open(gtx, 0, loc)
	pad := tok.BASE_SIZE_8
	tall := look.hide_title && !look.has_actions ? tok.BASE_SIZE_16 : tok.BASE_SIZE_20
	sz := ops.Size{BANNER_GLYPH + 2 * pad, tall + 2 * pad}
	icon(gtx, ic, {pad, pad + (tall - BANNER_GLYPH) / 2}, BANNER_GLYPH, color(look.fg))
	ui.widget_close(gtx, &p, {size = sz})
}

// banner_body is the content (title, description) and the actions,
// beside or under it as look.pl says, 4px apart.
@(private)
banner_body :: proc(gtx: ^ui.Ctx, title, description, primary, secondary: string, look: Banner_Look) -> (event: Banner_Event) {
	if look.pl.beside {
		r := ui.row_open(gtx, gap = tok.BASE_SIZE_4)
		defer ui.close(&r)
		ui.flexible(gtx, 1)
		banner_content(gtx, title, description, look)
		if look.has_actions {
			event = banner_actions(gtx, primary, secondary, look)
		}
		return
	}
	c := ui.column_open(gtx, gap = tok.BASE_SIZE_4)
	defer ui.close(&c)
	banner_content(gtx, title, description, look)
	if look.has_actions {
		event = banner_actions(gtx, primary, secondary, look)
	}
	return
}

// banner_content is the title and description, 4px apart, with 8px
// above and below (6px with the title hidden and no actions)
// (Banner.module.css:129-150).
@(private)
banner_content :: proc(gtx: ^ui.Ctx, title, description: string, look: Banner_Look) {
	m := look.hide_title && !look.has_actions ? tok.BASE_SIZE_6 : tok.BASE_SIZE_8
	in_ := ui.inset_open(gtx, {top = m, bottom = m})
	defer ui.close(&in_)
	// A column with no gap, the 4px placed by hand: a hidden title or an
	// empty description takes no space, nor a gap.
	col := ui.column_open(gtx)
	defer ui.close(&col)
	body := text_style(.Medium)
	fg := primer_fg()
	if look.hide_title {
		// Told, not drawn: a heading with no box.
		p := ui.widget_open(gtx)
		ui.semantics(gtx, &p, {role = .Heading, label = ui.frame_string(gtx, title), level = look.level})
		ui.widget_close(gtx, &p, {})
	} else {
		title_style := body
		title_style.weight = tok.BASE_TEXT_WEIGHT_SEMIBOLD
		text_block(gtx, title, {style = title_style, color = fg, wrap = true, semantics = {role = .Heading, level = look.level}}, 0, #location())
		if title != "" && description != "" {
			ui.spacer(gtx, tok.BASE_SIZE_4)
		}
	}
	text_block(gtx, description, {style = body, color = fg, wrap = true, semantics = {role = .Text}}, 0, #location())
}

// banner_actions is the action row: 12px apart, centred, 2px above and
// look.pl.below under; beside the content secondary then primary in a
// row at least 32px tall, under it primary first (Banner.module.css
// :194-265).
@(private)
banner_actions :: proc(gtx: ^ui.Ctx, primary, secondary: string, look: Banner_Look) -> (event: Banner_Event) {
	in_ := ui.inset_open(gtx, {top = tok.BASE_SIZE_2, bottom = look.pl.below})
	defer ui.close(&in_)
	min_h := look.pl.min_tall ? BANNER_ACTIONS_MIN_HEIGHT : 0
	box := ui.sized_open(gtx, {min = {0, min_h}})
	defer ui.close(&box)
	r := ui.row_open(gtx, gap = tok.BASE_SIZE_12, align = .Center)
	defer ui.close(&r)
	run_secondary :: proc(gtx: ^ui.Ctx, label: string) -> bool {
		return label != "" && button(gtx, label, .Invisible)
	}
	run_primary :: proc(gtx: ^ui.Ctx, label: string) -> bool {
		return label != "" && button(gtx, label)
	}
	if look.pl.beside {
		if run_secondary(gtx, secondary) {
			event = .Secondary
		}
		if run_primary(gtx, primary) {
			event = .Primary
		}
		return
	}
	if run_primary(gtx, primary) {
		event = .Primary
	}
	if run_secondary(gtx, secondary) {
		event = .Secondary
	}
	return
}

// Blankslate_Size is a Blankslate's type scale and padding.
Blankslate_Size :: enum u8 {
	Small,
	Medium,
	Large,
}

// Blankslate_Event is which of a Blankslate's actions was taken.
Blankslate_Event :: enum u8 {
	None,
	Primary,
	Secondary,
}

// BLANKSLATE_CONTAINER_BREAKPOINT is the offered width at or below which
// every size takes the compact rules, and BLANKSLATE_NARROW_MAX the cap
// narrow sets: literals in the CSS, 34rem (--breakpoint-small, which the
// CSS comment names) and 485px (Blankslate.module.css:16-19,105-106).
BLANKSLATE_CONTAINER_BREAKPOINT :: tok.BREAKPOINT_SMALL
BLANKSLATE_NARROW_MAX :: f32(485)

// Blankslate_Metrics are one size's type and spacing, after the compact
// rules where they apply (Blankslate.module.css:21-57,105-139).
@(private)
Blankslate_Metrics :: struct {
	heading, description: tok.Type_Style,
	pad:                  [2]f32, // block, inline
	heading_above:        f32,
	description_below:    f32,
	visual_cap:           f32, // 0: the visual keeps its own size
	first_action, action: f32, // above the first action, above each later one
	last_below:           f32, // under the last action
	small_button:         bool,
}

@(private)
blankslate_metrics :: proc(size: Blankslate_Size, spacious, compact: bool) -> (m: Blankslate_Metrics) {
	m.first_action, m.action = tok.BASE_SIZE_16, tok.BASE_SIZE_16
	switch size {
	case .Small:
		m.heading, m.description = tok.TEXT_TITLE_SHORTHAND_SMALL, tok.TEXT_BODY_SHORTHAND_MEDIUM
		m.pad = spacious ? {tok.BASE_SIZE_44, tok.BASE_SIZE_28} : {tok.BASE_SIZE_16, tok.BASE_SIZE_16}
		m.visual_cap = tok.BASE_SIZE_24
		m.last_below = tok.BASE_SIZE_12
		m.small_button = true
	case .Medium, .Large:
		m.heading = size == .Large ? tok.TEXT_TITLE_SHORTHAND_LARGE : tok.TEXT_TITLE_SHORTHAND_MEDIUM
		m.description = tok.TEXT_BODY_SHORTHAND_LARGE
		m.pad = spacious ? {tok.BASE_SIZE_80, tok.BASE_SIZE_40} : {tok.BASE_SIZE_32, tok.BASE_SIZE_32}
		m.last_below = tok.BASE_SIZE_16
		if size == .Large {
			m.heading_above, m.description_below = tok.BASE_SIZE_8, tok.BASE_SIZE_8
		}
	}
	if compact {
		m.heading, m.description = tok.TEXT_TITLE_SHORTHAND_SMALL, tok.TEXT_BODY_SHORTHAND_MEDIUM
		switch {
		case spacious:
			m.pad = {tok.BASE_SIZE_44, tok.BASE_SIZE_28}
		case size == .Small:
			m.pad = {tok.BASE_SIZE_16, tok.BASE_SIZE_16}
		case:
			m.pad = {tok.BASE_SIZE_20, tok.BASE_SIZE_20}
		}
		m.visual_cap = tok.BASE_SIZE_24
		m.action = tok.BASE_SIZE_8
		m.last_below = tok.BASE_SIZE_4
	}
	return
}

// Blankslate_Paint is a bordered blankslate's outline.
@(private)
Blankslate_Paint :: struct {
	border: ops.Color,
}

@(private)
paint_blankslate :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, size: ops.Size, user: rawptr) {
	bp := (^Blankslate_Paint)(user)
	stroke_inside(gtx, ops.Round_Rect{{0, 0, size.x, size.y}, tok.BORDER_RADIUS_MEDIUM}, bp.border, tok.BORDER_WIDTH_THIN)
}

// Blankslate_Content is what a blankslate shows.
@(private)
Blankslate_Content :: struct {
	heading, description, primary, secondary: string,
	visual:                                   Icon,
	visual_size:                              f32,
	level:                                    u8,
}

// blankslate is an empty state (primer-kit components/blankslate.json,
// Blankslate.module.css, Blankslate.tsx): a centred column of a muted
// visual, a heading (a heading for assistive technology at
// heading_level, h2 by default), a muted description, a primary Button
// and a secondary link, each line centred and the lines of the heading
// and description balanced. It fills the width it is offered; at 544px
// or less every size takes the compact type and spacing. narrow caps it
// at 485px, centred; border outlines it; spacious pads it more.
// visual_size is the visual's own size, which small and the compact
// rules cap at 24px. Returns the action taken this frame.
//
// Departure: the actions are labels, where Primer takes children and an
// href (Blankslate.tsx:110-137).
blankslate :: proc(
	gtx: ^ui.Ctx,
	heading: string,
	description := "",
	visual := Icon.None,
	visual_size: f32 = 32,
	primary := "",
	secondary := "",
	size := Blankslate_Size.Medium,
	border := false,
	narrow := false,
	spacious := false,
	heading_level := 2,
	key: u64 = 0,
	loc := #caller_location,
) -> (event: Blankslate_Event) {
	outer := ui.stack_open(gtx, key, loc)
	defer ui.close(&outer)
	// Until its first child opens, gtx.constraints is what the blankslate
	// was offered: the width its container query reads.
	offered := gtx.constraints.max.x
	compact := ui.is_finite(offered) && offered <= BLANKSLATE_CONTAINER_BREAKPOINT
	m := blankslate_metrics(size, spacious, compact)
	w := offered
	if narrow {
		w = min(w, BLANKSLATE_NARROW_MAX)
	}
	// The column fills the width offered, so a narrow block centres in it.
	fill := ui.sized_open(gtx, {min = {offered if ui.is_finite(offered) else 0, 0}})
	defer ui.close(&fill)
	centre := ui.column_open(gtx, align = .Center)
	defer ui.close(&centre)
	limit := ui.sized_open(gtx, {max = {w if ui.is_finite(w) else 0, 0}})
	defer ui.close(&limit)
	style := ui.Box_Style {
		padding = {m.pad[1], m.pad[0], m.pad[1], m.pad[0]},
	}
	if border {
		bp := new(Blankslate_Paint, gtx.allocator)
		bp.border = color(.Border_Color_Default)
		style.paint, style.user = paint_blankslate, bp
	}
	box := ui.box_open(gtx, style)
	defer ui.close(&box)
	inner := w - 2 * m.pad[1]
	col_box := ui.sized_open(gtx, {min = {inner if ui.is_finite(inner) else 0, 0}})
	defer ui.close(&col_box)
	col := ui.column_open(gtx, align = .Center)
	defer ui.close(&col)
	c := Blankslate_Content{heading, description, primary, secondary, visual, visual_size, u8(clamp(heading_level, 1, 6))}
	return blankslate_column(gtx, c, m)
}

// blankslate_column is the visual, heading, description and actions,
// top to bottom, with the size's margins between.
@(private)
blankslate_column :: proc(gtx: ^ui.Ctx, c: Blankslate_Content, m: Blankslate_Metrics) -> (event: Blankslate_Event) {
	if c.visual != .None {
		side := m.visual_cap > 0 ? min(c.visual_size, m.visual_cap) : c.visual_size
		p := ui.widget_open(gtx)
		icon(gtx, c.visual, {}, side, color(.Fg_Color_Muted))
		ui.widget_close(gtx, &p, {size = {icon_width(c.visual, side), side}})
		ui.spacer(gtx, tok.BASE_SIZE_8)
	}
	ui.spacer(gtx, m.heading_above)
	text_block(gtx, c.heading, {style = m.heading, color = primer_fg(), wrap = true, balance = true, align = .Center, semantics = {role = .Heading, level = c.level}}, 0, #location())
	ui.spacer(gtx, tok.BASE_SIZE_4)
	text_block(gtx, c.description, {style = m.description, color = color(.Fg_Color_Muted), wrap = true, balance = true, align = .Center, semantics = {role = .Text}}, 0, #location())
	ui.spacer(gtx, m.description_below)
	actions := 0
	if c.primary != "" {
		ui.spacer(gtx, m.first_action)
		if button(gtx, c.primary, .Primary, m.small_button ? .Small : .Medium) {
			event = .Primary
		}
		actions += 1
	}
	if c.secondary != "" {
		ui.spacer(gtx, actions == 0 ? m.first_action : m.action)
		// A Link in the description's type (Blankslate.module.css:94-97).
		if link(gtx, c.secondary, size = m.description.size) {
			event = .Secondary
		}
		actions += 1
	}
	if actions > 0 {
		ui.spacer(gtx, m.last_below)
	}
	return
}

// Timeline_Clip trims the line at the first item's badge, the last
// item's content, or both.
Timeline_Clip :: enum u8 {
	None,
	Start,
	End,
	Both,
}

// Badge_Variant is a timeline badge's emphasis colour; None is a muted
// disc with a muted icon.
Badge_Variant :: enum u8 {
	None,
	Accent,
	Success,
	Attention,
	Severe,
	Danger,
	Done,
	Open,
	Closed,
	Sponsors,
}

// Timeline geometry (Timeline.module.css): items inset 16px with 16px
// above and below, the line 2px, the badge 32px shifted 15px left to
// centre on it with 8px after, the body 5px down, a narrow timeline
// below 480px, a break 24px tall with a 4px rule.
TIMELINE_INSET :: tok.BASE_SIZE_16
TIMELINE_LINE :: f32(2)
TIMELINE_BADGE :: f32(32)
TIMELINE_BADGE_SHIFT :: f32(15)
TIMELINE_BODY_TOP :: tok.BASE_SIZE_4 + 1
TIMELINE_CONTAINER_BREAKPOINT :: f32(480)
TIMELINE_BREAK :: tok.BASE_SIZE_24
// TIMELINE_GUTTER is the avatar's offset left of the line, 40 + 32px.
TIMELINE_GUTTER :: tok.BASE_SIZE_40 + tok.BASE_SIZE_32

// badge_column is the width the badge takes in its row: 32px less the
// 15px it hangs left, plus 8px.
@(private)
BADGE_COLUMN :: TIMELINE_BADGE - TIMELINE_BADGE_SHIFT + tok.BASE_SIZE_8

// Timeline_Memo is a timeline's child count from the frame before, so an
// item can tell it is the last.
@(private)
Timeline_Memo :: struct {
	children: int,
}

// Timeline is an open timeline: its column, width, and the items and
// breaks placed so far.
Timeline :: struct {
	gtx:     ^ui.Ctx,
	col:     ui.Flex,
	clip:    Timeline_Clip,
	width:   f32,
	narrow:  bool,
	index:   int, // the next child's position
	pending: bool, // a break waits for the item after it
	memo:    ^Timeline_Memo,
}

// timeline_open opens a timeline (primer-kit components/timeline.json,
// Timeline.module.css, Timeline.tsx): a column of items and breaks,
// joined by a 2px line in --borderColor-muted. It is as wide as it is
// offered, never sized by its items; below 480px each item's actions
// move under its body. Place items with timeline_item_open and breaks
// with timeline_break, and close it with timeline_close.
//
// Departures: the list semantics Primer puts behind its
// primer_react_timeline_list_semantics flag (Timeline.tsx:17-46) are not
// offered; with the flag off, its default, the timeline is plain
// containers, as here.
timeline_open :: proc(gtx: ^ui.Ctx, clip := Timeline_Clip.None, key: u64 = 0, loc := #caller_location) -> (tl: Timeline) {
	tl.gtx = gtx
	tl.clip = clip
	tl.memo = ui.widget_data(gtx, ui.claim_id(gtx, key, loc), Timeline_Memo)
	tl.col = ui.column_open(gtx, align = .Fill)
	// Until its first child opens, gtx.constraints is what the timeline was
	// offered: the width its container query reads.
	tl.width = gtx.constraints.max.x
	tl.narrow = ui.is_finite(tl.width) && tl.width < TIMELINE_CONTAINER_BREAKPOINT
	return
}

// timeline_close closes the timeline: a break with no item after it
// stands as a band of its own.
timeline_close :: proc(tl: ^Timeline) {
	gtx := tl.gtx
	if tl.pending {
		p := ui.widget_open(gtx)
		w := ui.is_finite(gtx.constraints.max.x) ? gtx.constraints.max.x : 0
		paint_break(gtx, w, 0)
		ui.widget_close(gtx, &p, {size = {w, TIMELINE_BREAK}})
		tl.pending = false
	}
	if tl.memo.children != tl.index {
		// An item laid out as last, or not, from last frame's count:
		// draw again with this one's.
		tl.memo.children = tl.index
		ui.request_frame(gtx)
	}
	ui.close(&tl.col)
}

// paint_break is a break's band at y: --bgColor-default over the line,
// with a 4px --borderColor-default rule along its top, w wide.
@(private)
paint_break :: proc(gtx: ^ui.Ctx, w, y: f32) {
	ops.fill(gtx.scene, ops.Rect{0, y, w, TIMELINE_BREAK}, color(.Bg_Color_Default))
	ops.fill(gtx.scene, ops.Rect{0, y, w, tok.BORDER_WIDTH_THICKER}, color(.Border_Color_Default))
}

// timeline_break marks a gap in time: a 24px band across the whole
// timeline that covers the line and overlaps the next item by 16px
// (12px when that item is condensed). The next item draws it, as it is
// the one that knows whether it is condensed.
timeline_break :: proc(tl: ^Timeline) {
	tl.pending = true
	tl.index += 1
}

// Timeline_Item is an open item: its containers and where its parts sit.
Timeline_Item :: struct {
	tl:                ^Timeline,
	inset:             ui.Inset,
	box:               ui.Box,
	row, body_row:     ui.Flex,
	body_inset:        ui.Inset,
	body:              ui.Flex,
	actions_inset:     ui.Inset,
	actions_box:       ui.Inset,
	actions:           ui.Flex,
	in_actions:        bool,
}

// Item_Paint is an item's line and any break above it, painted under its
// content once its height is known.
@(private)
Item_Paint :: struct {
	top_break:        f32, // the height a break above adds to the item, 8 or 12px, 0 for none
	line_top:         f32, // from the item's top, under any break
	line_len:         f32, // 0: to the item's bottom
	timeline_w:       f32,
}

@(private)
paint_item :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, size: ops.Size, user: rawptr) {
	ip := (^Item_Paint)(user)
	top := ip.top_break + ip.line_top
	h := ip.line_len > 0 ? ip.line_len : size.y - top
	ops.fill(gtx.scene, ops.Rect{0, top, TIMELINE_LINE, h}, color(.Border_Color_Muted))
	if ip.top_break > 0 {
		// The box starts where the break does: the band runs from its top
		// and from the timeline's edge, 16px left of the item, reaching
		// 16px (12px) into the item's own top.
		ops.transform_push(gtx.scene, ops.translate(-TIMELINE_INSET, 0))
		paint_break(gtx, ip.timeline_w, 0)
		ops.transform_pop(gtx.scene)
	}
}

// badge_role is v's disc colour (Timeline.module.css:123-161).
@(private)
badge_role :: proc(v: Badge_Variant) -> tok.Role {
	switch v {
	case .None:
		return .Timeline_Badge_Bg_Color
	case .Accent:
		return .Bg_Color_Accent_Emphasis
	case .Success:
		return .Bg_Color_Success_Emphasis
	case .Attention:
		return .Bg_Color_Attention_Emphasis
	case .Severe:
		return .Bg_Color_Severe_Emphasis
	case .Danger:
		return .Bg_Color_Danger_Emphasis
	case .Done:
		return .Bg_Color_Done_Emphasis
	case .Open:
		return .Bg_Color_Open_Emphasis
	case .Closed:
		return .Bg_Color_Closed_Emphasis
	case .Sponsors:
	}
	return .Bg_Color_Sponsors_Emphasis
}

// timeline_item_open opens one event: badge (the octicon on a 32px disc
// in the variant's colour, ringed 2px in --bgColor-default where it cuts
// the line; condensed, a bare 16px muted icon on a 16px patch) then the
// body, which body's text starts in --fgColor-muted body text and any
// widgets placed before timeline_actions follow. Call timeline_actions
// to place controls at the item's trailing end (under the body on a
// narrow timeline), and timeline_item_close to end it.
timeline_item_open :: proc(gtx: ^ui.Ctx, tl: ^Timeline, badge: Icon, variant := Badge_Variant.None, condensed := false, body := "", key: u64 = 0, loc := #caller_location) -> (it: Timeline_Item) {
	it.tl = tl
	first := tl.index == 0
	last := tl.index == tl.memo.children - 1
	tl.index += 1
	clip_start := first && (tl.clip == .Start || tl.clip == .Both)
	clip_end := last && (tl.clip == .End || tl.clip == .Both)
	ip := new(Item_Paint, gtx.allocator)
	ip.timeline_w = ui.is_finite(tl.width) ? tl.width : 0
	if tl.pending {
		ip.top_break = TIMELINE_BREAK - (condensed ? tok.BASE_SIZE_12 : tok.BASE_SIZE_16)
		tl.pending = false
	}
	pt, pb := tok.BASE_SIZE_16, tok.BASE_SIZE_16
	if condensed {
		pt, pb = tok.BASE_SIZE_4, last ? tok.BASE_SIZE_16 : 0
	}
	if clip_start {
		pt = 0
		if condensed {
			ip.line_top = tok.BASE_SIZE_12
		}
	}
	if clip_end {
		pb = 0
		if condensed {
			ip.line_len = tok.BASE_SIZE_12
		}
	}
	it.inset = ui.inset_open(gtx, {left = TIMELINE_INSET}, key, loc)
	it.box = ui.box_open(gtx, {padding = {top = ip.top_break + pt, bottom = pb}, paint = paint_item, user = ip})
	if tl.narrow {
		it.row = ui.column_open(gtx)
		it.body_row = ui.row_open(gtx)
	} else {
		it.row = ui.row_open(gtx)
	}
	timeline_badge(gtx, badge, variant, condensed)
	ui.flexible(gtx, 1)
	it.body_inset = ui.inset_open(gtx, {top = TIMELINE_BODY_TOP})
	it.body = ui.column_open(gtx)
	if body != "" {
		text_block(gtx, body, {style = text_style(.Medium), color = color(.Fg_Color_Muted), wrap = true, semantics = {role = .Text}}, 0, #location())
	}
	return
}

// timeline_badge draws the badge with the line's left edge at x 0.
@(private)
timeline_badge :: proc(gtx: ^ui.Ctx, ic: Icon, variant: Badge_Variant, condensed: bool, loc := #caller_location) {
	p := ui.widget_open(gtx, 0, loc)
	centre := ops.Point{TIMELINE_LINE / 2, TIMELINE_BADGE / 2}
	icon_side := f32(16)
	ink := color(.Fg_Color_Muted)
	if condensed {
		// A 16px-tall patch of the page with 8px above and below, its
		// corners round, the icon muted whatever the variant
		// (Timeline.module.css:63-78).
		patch := ops.Rect{-TIMELINE_BADGE_SHIFT, tok.BASE_SIZE_8, TIMELINE_BADGE, tok.BASE_SIZE_16}
		ops.fill(gtx.scene, ops.Round_Rect{patch, patch.h / 2}, color(.Bg_Color_Default))
	} else {
		ops.fill(gtx.scene, ui.circle(centre, TIMELINE_BADGE / 2), color(.Bg_Color_Default))
		ops.fill(gtx.scene, ui.circle(centre, TIMELINE_BADGE / 2 - tok.BORDER_WIDTH_THICK), color(badge_role(variant)))
		if variant != .None {
			ink = color(.Fg_Color_On_Emphasis)
		}
	}
	iw := icon_width(ic, icon_side)
	icon(gtx, ic, {centre.x - iw / 2, centre.y - icon_side / 2}, icon_side, ink)
	ui.widget_close(gtx, &p, {size = {BADGE_COLUMN, TIMELINE_BADGE}})
}

// timeline_actions ends the item's body and opens its actions: a row of
// controls 8px apart at the trailing end, at least 32px tall and
// centred on the badge, or, on a narrow timeline, under the body from
// its start, 8px below it.
timeline_actions :: proc(gtx: ^ui.Ctx, it: ^Timeline_Item) {
	if it.in_actions {
		return
	}
	it.in_actions = true
	ui.close(&it.body)
	ui.close(&it.body_inset)
	if it.tl.narrow {
		ui.close(&it.body_row)
		it.actions_inset = ui.inset_open(gtx, {left = BADGE_COLUMN, top = tok.BASE_SIZE_8})
		it.actions = ui.row_open(gtx, gap = tok.BASE_SIZE_8, align = .Center)
		return
	}
	it.actions_box = ui.sized_open(gtx, {min = {0, tok.BASE_SIZE_32}})
	it.actions = ui.row_open(gtx, gap = tok.BASE_SIZE_8, align = .Center)
}

// timeline_item_close ends the item.
timeline_item_close :: proc(it: ^Timeline_Item) {
	if it.in_actions {
		ui.close(&it.actions)
		if it.tl.narrow {
			ui.close(&it.actions_inset)
		} else {
			ui.close(&it.actions_box)
		}
	} else {
		ui.close(&it.body)
		ui.close(&it.body_inset)
		if it.tl.narrow {
			ui.close(&it.body_row)
		}
	}
	ui.close(&it.row)
	ui.close(&it.box)
	ui.close(&it.inset)
}

// timeline_item is timeline_item_open as a guard: `if
// primer.timeline_item(gtx, &tl, .Git_Commit) { … }` closes it at the end of
// the if, or of the block when called as a statement.
@(deferred_in = timeline_item_guard_close)
timeline_item :: proc(
	gtx: ^ui.Ctx,
	tl: ^Timeline,
	badge: Icon,
	variant := Badge_Variant.None,
	condensed := false,
	body := "",
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	ui.guard_hold(gtx, Timeline_Item)^ = timeline_item_open(gtx, tl, badge, variant, condensed, body, key, loc)
	return true
}

@(private = "file")
timeline_item_guard_close :: proc(
	gtx: ^ui.Ctx,
	tl: ^Timeline,
	badge: Icon,
	variant: Badge_Variant,
	condensed: bool,
	body: string,
	key: u64,
	loc: runtime.Source_Code_Location,
) {
	h := ui.guard_take(gtx, Timeline_Item)
	timeline_item_close(h)
}

// timeline_avatar_open opens a layer for the item's actor avatar, size
// px square, in the gutter 72px left of the line, centred on the badge,
// over the line: 56px outside the timeline's left edge, which its parent
// must leave free (timeline.json notes). Call it straight after
// timeline_item_open, draw the avatar from the layer's origin, and close
// it with ui.close.
timeline_avatar_open :: proc(gtx: ^ui.Ctx, it: ^Timeline_Item, size: f32 = tok.BASE_SIZE_40) -> ui.Overlay {
	// The body's origin is BADGE_COLUMN right of the line and 5px below
	// the badge's top, so the badge's centre is 11px down from it.
	centre := TIMELINE_BADGE / 2 - TIMELINE_BODY_TOP
	return ui.overlay_open(gtx, {-BADGE_COLUMN - TIMELINE_GUTTER, centre - size / 2}, ui.exact({size, size}))
}
