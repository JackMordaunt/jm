package primer

import "base:runtime"
import "core:fmt"
import "jm:ui"
import "jm:ui/design"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// PageHeader, PageLayout and SplitPageLayout: the page frame and the
// page's own heading block. Each records the regions the caller lays out
// (ui.record_open), then places them by the CSS once every size is
// known, so regions may be laid out in any order and a title wraps
// beside actions measured before it.

// Title_Variant is a page header title's size: medium 20px semibold,
// large 32px normal, subtitle 20px normal (PageHeader.module.css:41-63).
Title_Variant :: enum u8 {
	Medium,
	Large,
	Subtitle,
}

// title_style is variant v's title font: its size, weight and the title
// line height that every action and visual box is as tall as.
title_style :: proc(v: Title_Variant) -> tok.Type_Style {
	switch v {
	case .Large:
		return {weight = tok.BASE_TEXT_WEIGHT_NORMAL, size = tok.TEXT_TITLE_SIZE_LARGE, line_height = tok.TEXT_TITLE_SIZE_LARGE * tok.TEXT_TITLE_LINE_HEIGHT_LARGE}
	case .Subtitle:
		return {weight = tok.BASE_TEXT_WEIGHT_NORMAL, size = tok.TEXT_TITLE_SIZE_MEDIUM, line_height = tok.TEXT_TITLE_SIZE_MEDIUM * tok.TEXT_TITLE_LINE_HEIGHT_MEDIUM}
	case .Medium:
	}
	return {weight = tok.BASE_TEXT_WEIGHT_SEMIBOLD, size = tok.TEXT_TITLE_SIZE_MEDIUM, line_height = tok.TEXT_TITLE_SIZE_MEDIUM * tok.TEXT_TITLE_LINE_HEIGHT_MEDIUM}
}

// Header_Slot is one of a page header's caller-filled regions.
Header_Slot :: enum u8 {
	Parent_Link,
	Context_Bar,
	Context_Actions,
	Leading_Action,
	Breadcrumbs,
	Trailing_Action,
	Actions,
	Description,
	Navigation,
}

// slot_shown_by_default is the code's default visibility at range rg
// (PageHeader.tsx:27-39,186-200): the context area's parts only below
// 768px, the leading and trailing actions only from 768px, the rest
// always.
@(private)
slot_shown_by_default :: proc(s: Header_Slot, rg: Viewport_Range) -> bool {
	#partial switch s {
	case .Parent_Link, .Context_Bar, .Context_Actions:
		return rg == .Narrow
	case .Leading_Action, .Trailing_Action:
		return rg != .Narrow
	}
	return true
}

// Region_Run is one region a layout recorded: its macro and size, and
// whether it was recorded and shows.
@(private)
Region_Run :: struct {
	macro: ops.Macro_Id,
	size:  ops.Size,
	base:  f32,
	set:   bool,
	shown: bool,
}

// Page_Header is an open page header.
Page_Header :: struct {
	gtx:             ^ui.Ctx,
	title:           string,
	variant:         Title_Variant,
	leading_visual:  Icon,
	trailing_visual: Icon,
	has_border:      bool,
	key:             u64,
	loc:             runtime.Source_Code_Location,
	width:           f32,
	slots:           [Header_Slot]Region_Run,
	open:            Header_Slot,
	rec:             ui.Recording,
	row:             ui.Flex,
}

// page_header_open opens Primer's PageHeader (page-header.json,
// PageHeader.module.css): a title in its variant's size with optional
// leading and trailing octicons; the caller fills the other regions with
// page_header_slot_open/close (and page_header_parent_link), in any
// order, before page_header_close places them. Row 1 is the context area
// (parent link, context bar, context actions pushed to the end, 8px
// below); row 2 the leading action, breadcrumbs, title area, trailing
// action and actions, each action and visual exactly one title line
// tall, the actions taking the rest of the row and the title wrapping
// beside them; row 3 the description and row 4 the navigation, 8px
// apart. has_border draws a 1px rule 8px under it when no navigation
// shows.
//
// Departures: visibility follows the code, not the docs (page-header.json
// contradiction): the context area's parts show only below 768px, the
// leading and trailing actions only from 768px; a slot's hidden, resolved
// by the caller (responsive), replaces that. The visuals are octicons, not
// arbitrary content. jm:ui has no landmark roles, so the header is no
// landmark; the title is a heading.
page_header_open :: proc(
	gtx: ^ui.Ctx,
	title: string,
	variant := Title_Variant.Medium,
	leading_visual := Icon.None,
	trailing_visual := Icon.None,
	has_border := false,
	key: u64 = 0,
	loc := #caller_location,
) -> (h: Page_Header) {
	h.gtx, h.title, h.variant = gtx, title, variant
	h.leading_visual, h.trailing_visual, h.has_border = leading_visual, trailing_visual, has_border
	h.key, h.loc = key, loc
	cs := ui.offer(gtx)
	h.width = ui.is_finite(cs.max.x) ? cs.max.x : 0
	return
}

// page_header_slot_open starts slot s, which the caller lays out up to
// page_header_slot_close: a row of controls, centred, 8px apart. hidden,
// when given, overrides the slot's default visibility at this width.
page_header_slot_open :: proc(h: ^Page_Header, s: Header_Slot, hidden: Maybe(bool) = nil, loc := #caller_location) {
	gtx := h.gtx
	shown := !(hidden.? or_else !slot_shown_by_default(s, viewport_range(gtx)))
	h.open = s
	h.slots[s].shown = shown
	w := h.width > 0 ? h.width : ui.INF
	h.rec = ui.record_open(gtx, {max = {w, ui.INF}}, u64(ui.id_mix(ops.Area_Id(h.key), u64(s) + 1)), loc)
	h.row = ui.row_open(gtx, gap = tok.STACK_GAP_CONDENSED, align = .Center)
}

// page_header_slot_close ends the slot page_header_slot_open began.
page_header_slot_close :: proc(h: ^Page_Header) {
	ui.close(&h.row)
	m, d := ui.record_close(&h.rec)
	r := &h.slots[h.open]
	r.macro, r.size, r.base, r.set = m, d.size, d.baseline, true
}

// page_header_parent_link fills the parent link: an arrow-left octicon
// and label, 8px apart, in --fgColor-muted turning --fgColor-accent on
// hover (page-header.json, Link.module.css:34-41). Returns true on the
// frame it is activated.
page_header_parent_link :: proc(h: ^Page_Header, label: string, hidden: Maybe(bool) = nil, state := Interaction.Live, loc := #caller_location) -> bool {
	page_header_slot_open(h, .Parent_Link, hidden, loc)
	defer page_header_slot_close(h)
	return parent_link(h.gtx, label, state)
}

@(private)
parent_link :: proc(gtx: ^ui.Ctx, label: string, state: Interaction, loc := #caller_location) -> bool {
	p := ui.widget_open(gtx, 0, loc)
	st := style(.Body_Medium)
	t := design.shape_style(gtx, label, st, font_for(gtx, st.weight))
	h := max(t.height, BUTTON_ICON)
	sz := ui.constrain_min(gtx.constraints, {BUTTON_ICON + tok.STACK_GAP_CONDENSED + t.width, h})
	area := ops.Rect{0, 0, sz.x, sz.y}
	c := control(gtx, p.id, area, state)
	ink := color(c.state == .Hovered || c.state == .Pressed ? .Fg_Color_Accent : .Fg_Color_Muted)
	icon(gtx, .Arrow_Left, {0, (h - BUTTON_ICON) / 2}, BUTTON_ICON, ink)
	draw_text(gtx, t, {BUTTON_ICON + tok.STACK_GAP_CONDENSED, (h - t.height) / 2}, ink)
	paint_focus_outline(gtx, c, {area, tok.BORDER_RADIUS_SMALL})
	listen(gtx, c.st, p.id, area, cursor = .Pointer)
	said := ui.frame_string(gtx, label)
	ops.tag(gtx.scene, p.id, said)
	ui.semantics(gtx, &p, {role = .Link, label = said})
	ui.widget_close(gtx, &p, {sz, (h - t.height) / 2 + baseline_of(t)})
	return c.clicked
}

// slot_shown is whether slot s was laid out and shows.
@(private)
slot_shown :: proc(h: ^Page_Header, s: Header_Slot) -> bool {
	return h.slots[s].set && h.slots[s].shown
}

// place_at calls a recorded run with its top-left at pos.
@(private)
place_at :: proc(gtx: ^ui.Ctx, m: ops.Macro_Id, pos: ops.Point) {
	ops.transform_push(gtx.scene, ops.translate(pos.x, pos.y))
	ops.call(gtx.scene, m)
	ops.transform_pop(gtx.scene)
}

// page_header_close places every region and the title and closes the
// header.
page_header_close :: proc(h: ^Page_Header) {
	gtx := h.gtx
	gap := tok.STACK_GAP_CONDENSED
	ts := title_style(h.variant)
	line := ts.line_height
	// Row 2's widths, before the title: what it leaves for the title.
	lead_w, crumbs_w, trail_w, actions_w: f32
	if slot_shown(h, .Leading_Action) {
		lead_w = h.slots[.Leading_Action].size.x + tok.BASE_SIZE_8
	}
	if slot_shown(h, .Breadcrumbs) {
		crumbs_w = h.slots[.Breadcrumbs].size.x + tok.BASE_SIZE_8
	}
	if slot_shown(h, .Trailing_Action) {
		trail_w = h.slots[.Trailing_Action].size.x + tok.BASE_SIZE_8
	}
	if slot_shown(h, .Actions) {
		actions_w = h.slots[.Actions].size.x + tok.BASE_SIZE_8
	}
	visuals: f32
	for v in ([2]Icon{h.leading_visual, h.trailing_visual}) {
		if v != .None {
			visuals += icon_width(v, BUTTON_ICON) + gap
		}
	}
	room := h.width > 0 ? max(h.width - lead_w - crumbs_w - trail_w - actions_w - visuals, 1) : 0
	para := design.layout_style(gtx, h.title, ts, font_for(gtx, ts.weight), room)
	title_w := para.width + visuals
	row2 := max(para.height, line)
	for s in ([?]Header_Slot{.Leading_Action, .Breadcrumbs, .Trailing_Action, .Actions}) {
		if slot_shown(h, s) {
			row2 = max(row2, h.slots[s].size.y)
		}
	}
	width := h.width > 0 ? h.width : lead_w + crumbs_w + title_w + trail_w + actions_w
	context_h: f32
	has_context := slot_shown(h, .Parent_Link) || slot_shown(h, .Context_Bar) || slot_shown(h, .Context_Actions)
	if has_context {
		for s in ([?]Header_Slot{.Parent_Link, .Context_Bar, .Context_Actions}) {
			if slot_shown(h, s) {
				context_h = max(context_h, h.slots[s].size.y)
			}
		}
	}
	y: f32
	if has_context {
		y = context_h + tok.BASE_SIZE_8
	}
	row2_y := y
	y += row2
	desc_y, nav_y: f32
	if slot_shown(h, .Description) {
		desc_y = y + tok.BASE_SIZE_8
		y = desc_y + h.slots[.Description].size.y
	}
	if slot_shown(h, .Navigation) {
		nav_y = y + tok.BASE_SIZE_8
		y = nav_y + h.slots[.Navigation].size.y
	}
	border := h.has_border && !slot_shown(h, .Navigation)
	if border {
		y += tok.BASE_SIZE_8 + tok.BORDER_WIDTH_THIN
	}

	p := ui.widget_open(gtx, h.key, h.loc)
	size := ui.constrain(gtx.constraints, {width, y})
	if has_context {
		x: f32
		for s in ([?]Header_Slot{.Parent_Link, .Context_Bar}) {
			if slot_shown(h, s) {
				r := h.slots[s]
				place_at(gtx, r.macro, {x, (context_h - r.size.y) / 2})
				x += r.size.x + gap
			}
		}
		if slot_shown(h, .Context_Actions) {
			r := h.slots[.Context_Actions]
			place_at(gtx, r.macro, {max(size.x - r.size.x, x), (context_h - r.size.y) / 2})
		}
	}
	// Each action box is one title line tall, its content centred in it;
	// breadcrumbs centre down the row.
	centre_in :: proc(r: Region_Run, box: f32) -> f32 {
		return (box - r.size.y) / 2
	}
	x: f32
	if slot_shown(h, .Leading_Action) {
		r := h.slots[.Leading_Action]
		place_at(gtx, r.macro, {x, row2_y + centre_in(r, line)})
		x += lead_w
	}
	if slot_shown(h, .Breadcrumbs) {
		r := h.slots[.Breadcrumbs]
		place_at(gtx, r.macro, {x, row2_y + centre_in(r, row2)})
		x += crumbs_w
	}
	ink := color(.Fg_Color_Default)
	if h.leading_visual != .None {
		icon(gtx, h.leading_visual, {x, row2_y + (line - BUTTON_ICON) / 2}, BUTTON_ICON, ink)
		x += icon_width(h.leading_visual, BUTTON_ICON) + gap
	}
	title_id := ui.id_mix(p.id, 1)
	draw_paragraph(gtx, para, {x, row2_y}, ink)
	said := ui.frame_string(gtx, h.title)
	ops.tag(gtx.scene, title_id, said, {x, row2_y, para.width, para.height})
	ui.child_semantics(gtx, p.id, title_id, {x, row2_y, para.width, para.height}, {role = .Heading, label = said})
	x += para.width
	if h.trailing_visual != .None {
		x += gap
		icon(gtx, h.trailing_visual, {x, row2_y + (line - BUTTON_ICON) / 2}, BUTTON_ICON, ink)
		x += icon_width(h.trailing_visual, BUTTON_ICON)
	}
	if slot_shown(h, .Trailing_Action) {
		r := h.slots[.Trailing_Action]
		place_at(gtx, r.macro, {x + tok.BASE_SIZE_8, row2_y + centre_in(r, line)})
		x += trail_w
	}
	if slot_shown(h, .Actions) {
		r := h.slots[.Actions]
		place_at(gtx, r.macro, {max(size.x - r.size.x, x + tok.BASE_SIZE_8), row2_y + centre_in(r, line)})
	}
	if slot_shown(h, .Description) {
		place_at(gtx, h.slots[.Description].macro, {0, desc_y})
	}
	if slot_shown(h, .Navigation) {
		place_at(gtx, h.slots[.Navigation].macro, {0, nav_y})
	}
	if border {
		ops.fill(gtx.scene, ops.Rect{0, size.y - tok.BORDER_WIDTH_THIN, size.x, tok.BORDER_WIDTH_THIN}, color(.Border_Color_Default))
	}
	ui.semantics(gtx, &p, {role = .Group, label = said})
	ui.widget_close(gtx, &p, {size, row2_y + (len(para.lines) > 0 ? (para.pitch - para.metrics.ascent - para.metrics.descent) / 2 + para.metrics.ascent : 0)})
}

// Layout_Spacing is a page layout's padding or gap: none 0, condensed
// 16px, normal 16px below 1012px and 24px from 1012px
// (PageLayout.module.css:21-28).
Layout_Spacing :: enum u8 {
	None,
	Condensed,
	Normal,
}

// layout_spacing is s in a window vw wide.
@(private)
layout_spacing :: proc(s: Layout_Spacing, vw: f32) -> f32 {
	switch s {
	case .None:
		return 0
	case .Condensed:
		return tok.BASE_SIZE_16
	case .Normal:
		return vw >= tok.BREAKPOINT_LARGE ? tok.BASE_SIZE_24 : tok.BASE_SIZE_16
	}
	return 0
}

// Container_Width caps a page layout's container, or its content's inner
// box: none, 768, 1012 or 1280px (PageLayout.module.css:72-96).
Container_Width :: enum u8 {
	Full,
	Medium,
	Large,
	XLarge,
}

@(private)
container_cap :: proc(w: Container_Width) -> f32 {
	switch w {
	case .Medium:
		return tok.BREAKPOINT_MEDIUM
	case .Large:
		return tok.BREAKPOINT_LARGE
	case .XLarge:
		return tok.BREAKPOINT_XLARGE
	case .Full:
	}
	return ui.INF
}

// Pane_Position is the pane's side: at regular widths before or after
// the content, at narrow widths above or below it.
Pane_Position :: enum u8 {
	Start,
	End,
}

// Pane_Width is a pane width preset, or Custom for Pane.custom; Medium,
// the default, is first so a zero Pane has it.
Pane_Width :: enum u8 {
	Medium,
	Small,
	Large,
	Custom,
}

// Pane_Divider is a divider's look: none, a 1px --borderColor-default
// line, or an 8px --bgColor-inset band edged with lines.
Pane_Divider :: enum u8 {
	None,
	Line,
	Filled,
}

// Pane_Custom is a custom pane width: its bounds and default, in px.
Pane_Custom :: struct {
	min, default, max: f32,
}

// Pane is a page layout's side pane's options (page-layout.json inputs
// pane*). width points at the caller's own record of a resizable pane's
// width, 0 until set: the layout reads and writes it, and the caller
// persists it under a name of its own (ui.persist_struct). nil keeps the
// width in the layout's own state for the session.
Pane :: struct {
	position:      Pane_Position,
	preset:        Pane_Width,
	custom:        Pane_Custom,
	min_width:     f32, // a resizable preset pane's floor; 0 means 256
	resizable:     bool,
	width:         ^f32,
	sticky:        bool,
	offset_header: f32,
	padding:       Layout_Spacing,
	divider:       Pane_Divider,
	hidden:        bool,
	label:         string, // the drag handle's and the pane's accessible name
}

// PANE_MIN_WIDTH is a resizable preset pane's default floor (paneMinWidth).
PANE_MIN_WIDTH :: f32(256)

// PANE_KEY_STEP is how far an arrow key moves the drag handle
// (DragHandle.tsx:6-8).
PANE_KEY_STEP :: f32(3)

// PANE_HANDLE_OUTSET is how far the handle reaches past each side of the
// divider (PageLayout.module.css:715-723).
PANE_HANDLE_OUTSET :: f32(2)

// PANE_HOVER_FADE is the handle's hover fill fade: 150ms ease
// (PageLayout.module.css:725-739).
PANE_HOVER_FADE :: tok.Transition{150, {0.25, 0.1, 0.25, 1}}

// pane_default is a pane's width with nothing stored: a resizable preset
// starts at its wide value, a custom pane at its default.
@(private)
pane_default :: proc(p: Pane) -> f32 {
	switch p.preset {
	case .Small:
		return 256
	case .Medium:
		return 296
	case .Large:
		return 320
	case .Custom:
		return p.custom.default
	}
	return 296
}

// pane_bounds is a resizable pane's [min, max] in a window vw wide: a
// preset's max is the window less 511px, less 959px from 1280px, never
// below min; a custom pane's bounds are its own (usePaneWidth.ts:135-138).
@(private)
pane_bounds :: proc(p: Pane, vw: f32) -> (lo, hi: f32) {
	if p.preset == .Custom {
		return p.custom.min, max(p.custom.max, p.custom.min)
	}
	lo = p.min_width > 0 ? p.min_width : PANE_MIN_WIDTH
	diff := vw >= tok.BREAKPOINT_XLARGE ? f32(959) : f32(511)
	return lo, max(vw - diff, lo)
}

// pane_preset_width is a non-resizable preset pane's regular width: 240,
// 256 or 256px from 768px, 256, 296 or 320px from 1012px
// (PageLayout.module.css:30-49).
@(private)
pane_preset_width :: proc(p: Pane, vw: f32) -> f32 {
	wide := vw >= tok.BREAKPOINT_LARGE
	switch p.preset {
	case .Small:
		return wide ? 256 : 240
	case .Medium:
		return wide ? 296 : 256
	case .Large:
		return wide ? 320 : 256
	case .Custom:
		return p.custom.default
	}
	return 256
}

// Page_Region is one of a page layout's caller-filled regions.
Page_Region :: enum u8 {
	Header,
	Content,
	Pane,
	Footer,
}

// Region_Options are a region's padding, divider and visibility, and for
// content its inner box's cap.
@(private)
Region_Options :: struct {
	padding: Layout_Spacing,
	divider: Pane_Divider,
	width:   Container_Width,
}

// Page_Layout is an open page layout.
Page_Layout :: struct {
	gtx:                ^ui.Ctx,
	id:                 ops.Area_Id, // claimed at open: the handle's state hangs off it
	key:                u64,
	loc:                runtime.Source_Code_Location,
	pane:               Pane,
	has_pane:           bool,
	narrow:             bool,
	vw, vh:             f32,
	width, container:   f32, // the offered width and the container's
	pad, row, column:   f32,
	pane_w, content_w:  f32,
	regions:            [Page_Region]Region_Run,
	options:            [Page_Region]Region_Options,
	open:               Page_Region,
	rec:                ui.Recording,
	inset:              ui.Inset,
	settled:            bool,
}

// Pane_Drag is a resizable pane's handle state between frames: the width
// it holds when the caller keeps none, and a press's start.
@(private)
Pane_Drag :: struct {
	width:    f32,
	dragging: bool,
	fades:    design.Fades,
}

// page_layout_open opens Primer's PageLayout (page-layout.json,
// PageLayout.module.css): a padded root holding a centred container,
// capped at container_width, of an optional header, a content row of
// content and an optional pane, and an optional footer, row_gap apart;
// the pane sits column_gap from a divider between it and the content, or
// below 768px stacks above (start) or below (end) the content at full
// width. Fill regions with page_layout_region_open and close each with
// page_layout_region_close, in any order; page_layout_close places them
// and returns true on the frame a resizable pane's width settles (a drag
// ends, an arrow key moves it, a double-click resets it), when the
// caller saves *pane.width.
//
// A resizable pane has a 5px handle over its line divider: drag it, or
// focus it and press arrows to step 3px, double-click to reset; its width
// is clamped between its min (256px) and the window less 511px (959px
// from 1280px). A sticky pane pins offset_header below the top of the
// scroll box it scrolls in, no taller than the window, scrolling its own
// overflow.
//
// Departures: the width lives in the caller's Pane.width, so two panes
// never share the web's default 'paneWidth' storage key (page-layout.json
// gotcha). Arrow keys mirror for an end pane, Left growing it, as the
// sidebar's do (the pane's do not: page-layout.json contradiction). The
// pane's position is a plain value, so the web's drag-direction bug with a
// responsive position cannot arise (page-layout.json upstream-bug).
// Pane.hidden and the region's hidden
// are plain values the caller resolves per range (responsive). There is no
// Sidebar: the full-height column outside the container is not built. An
// overflowing pane is not made a focusable region, and jm:ui has no
// banner, main or contentinfo landmarks.
page_layout_open :: proc(
	gtx: ^ui.Ctx,
	container_width := Container_Width.XLarge,
	padding := Layout_Spacing.Normal,
	row_gap := Layout_Spacing.Normal,
	column_gap := Layout_Spacing.Normal,
	pane: Maybe(Pane) = nil,
	key: u64 = 0,
	loc := #caller_location,
) -> (l: Page_Layout) {
	l.gtx, l.key, l.loc = gtx, key, loc
	l.id = ui.claim_id(gtx, key, loc)
	l.vw, l.vh = gtx.viewport.x, gtx.viewport.y
	cs := ui.offer(gtx)
	l.width = ui.is_finite(cs.max.x) ? cs.max.x : l.vw
	if l.vw <= 0 {
		l.vw = l.width
	}
	l.narrow = viewport_range(gtx) == .Narrow
	l.pad = layout_spacing(padding, l.vw)
	l.row = layout_spacing(row_gap, l.vw)
	l.column = layout_spacing(column_gap, l.vw)
	l.container = min(max(l.width - 2 * l.pad, 0), container_cap(container_width))
	p, has := pane.?
	l.pane, l.has_pane = p, has && !p.hidden
	l.content_w = l.container
	if l.has_pane {
		l.pane_w = l.container
		if !l.narrow {
			l.pane_w = pane_width(&l)
			l.content_w = max(l.container - l.pane_w - pane_gutter(&l), 1)
		}
	}
	return
}

// pane_gutter is the space between pane and content at regular widths:
// column_gap, or a visible divider centred in twice it.
@(private)
pane_gutter :: proc(l: ^Page_Layout) -> f32 {
	d := pane_divider(l)
	if d == .None {
		return l.column
	}
	return 2 * l.column + (d == .Filled ? tok.BASE_SIZE_8 : tok.BORDER_WIDTH_THIN)
}

// pane_divider is the pane's divider at the current width: a resizable
// pane always draws a line at regular widths (PageLayout.tsx:687-746).
@(private)
pane_divider :: proc(l: ^Page_Layout) -> Pane_Divider {
	if l.pane.resizable && !l.narrow {
		return .Line
	}
	return l.pane.divider
}

// pane_width is the pane's regular width: a resizable pane's current
// width clamped to its bounds, else its preset.
@(private)
pane_width :: proc(l: ^Page_Layout) -> f32 {
	if !l.pane.resizable {
		return pane_preset_width(l.pane, l.vw)
	}
	lo, hi := pane_bounds(l.pane, l.vw)
	return clamp(pane_current(l)^, lo, hi)
}

// pane_current is where the pane's width is kept: the caller's, else the
// layout's own state; it starts at the default.
@(private)
pane_current :: proc(l: ^Page_Layout) -> ^f32 {
	w := l.pane.width
	if w == nil {
		w = &ui.widget_data(l.gtx, ui.id_mix(l.id, 0x9a7e), Pane_Drag).width
	}
	if w^ <= 0 {
		w^ = pane_default(l.pane)
	}
	return w
}

// page_layout_region_open starts region r, which the caller lays out up
// to page_layout_region_close, padded by padding. A header or footer
// draws divider between it and the content row; content caps its inner
// box at width, centred. A hidden region is laid out but not shown.
page_layout_region_open :: proc(
	l: ^Page_Layout,
	r: Page_Region,
	padding := Layout_Spacing.None,
	divider := Pane_Divider.None,
	width := Container_Width.Full,
	hidden := false,
	loc := #caller_location,
) {
	gtx := l.gtx
	l.open = r
	l.options[r] = {padding, divider, width}
	l.regions[r].shown = !hidden && (r != .Pane || l.has_pane)
	w := l.container
	pad := layout_spacing(padding, l.vw)
	switch r {
	case .Content:
		w = min(l.content_w, container_cap(width))
	case .Pane:
		w = l.pane_w
		pad = layout_spacing(l.pane.padding, l.vw)
	case .Header, .Footer:
	}
	l.rec = ui.record_open(gtx, {min = {w, 0}, max = {w, ui.INF}}, u64(ui.id_mix(l.id, u64(r) + 1)), loc)
	l.inset = ui.inset_open(gtx, {pad, pad, pad, pad})
}

// page_layout_region_close ends the region page_layout_region_open began.
page_layout_region_close :: proc(l: ^Page_Layout) {
	ui.close(&l.inset)
	m, d := ui.record_close(&l.rec)
	g := &l.regions[l.open]
	g.macro, g.size, g.set = m, d.size, true
}

// region_shown is whether region r was laid out and shows.
@(private)
region_shown :: proc(l: ^Page_Layout, r: Page_Region) -> bool {
	return l.regions[r].set && l.regions[r].shown
}

// divider_thickness is a horizontal or vertical divider's thickness.
@(private)
divider_thickness :: proc(d: Pane_Divider) -> f32 {
	switch d {
	case .Line:
		return tok.BORDER_WIDTH_THIN
	case .Filled:
		return tok.BASE_SIZE_8
	case .None:
	}
	return 0
}

// paint_divider draws d over r: a line fills it, a filled band adds 1px
// --borderColor-default edges along its long sides.
@(private)
paint_divider :: proc(gtx: ^ui.Ctx, d: Pane_Divider, r: ops.Rect, vertical: bool) {
	switch d {
	case .None:
	case .Line:
		ops.fill(gtx.scene, r, color(.Border_Color_Default))
	case .Filled:
		ops.fill(gtx.scene, r, color(.Bg_Color_Inset))
		edge := color(.Border_Color_Default)
		b := tok.BORDER_WIDTH_THIN
		if vertical {
			ops.fill(gtx.scene, ops.Rect{r.x, r.y, b, r.h}, edge)
			ops.fill(gtx.scene, ops.Rect{r.x + r.w - b, r.y, b, r.h}, edge)
		} else {
			ops.fill(gtx.scene, ops.Rect{r.x, r.y, r.w, b}, edge)
			ops.fill(gtx.scene, ops.Rect{r.x, r.y + r.h - b, r.w, b}, edge)
		}
	}
}

// Placed_Pane is where the pane, its divider and handle go in the root.
@(private)
Placed_Pane :: struct {
	at:       ops.Point,
	h:        f32, // shown height: capped at the window when sticky
	divider:  ops.Rect,
	room:     f32, // how far a sticky pane may move down its row
}

// page_layout_close places every region, paints the dividers, runs the
// drag handle and closes the layout. It returns true on the frame the
// pane's width settles.
page_layout_close :: proc(l: ^Page_Layout) -> bool {
	gtx := l.gtx
	x0 := l.pad + max(l.width - 2 * l.pad - l.container, 0) / 2
	y := l.pad
	header_at, footer_at, content_at: ops.Point
	header_div, footer_div: ops.Rect
	if region_shown(l, .Header) {
		header_at = {x0, y}
		y += l.regions[.Header].size.y
		if d := l.options[.Header].divider; d != .None {
			y += l.row
			header_div = {x0, y, l.container, divider_thickness(d)}
			y += header_div.h
		}
		y += l.row
	}
	pane: Placed_Pane
	pane_shown := l.has_pane && region_shown(l, .Pane)
	content_h := region_shown(l, .Content) ? l.regions[.Content].size.y : 0
	pane_h := pane_shown ? l.regions[.Pane].size.y : 0
	row_h: f32
	if l.narrow {
		row_h = place_narrow(l, x0, y, content_h, pane_h, pane_shown, &content_at, &pane)
	} else {
		row_h = place_regular(l, x0, y, content_h, pane_h, pane_shown, &content_at, &pane)
	}
	y += row_h
	if region_shown(l, .Footer) {
		y += l.row
		if d := l.options[.Footer].divider; d != .None {
			footer_div = {x0, y, l.container, divider_thickness(d)}
			y += footer_div.h + l.row
		}
		footer_at = {x0, y}
		y += l.regions[.Footer].size.y
	}
	y += l.pad

	root := ui.sized_open(gtx, {min = {l.width, y}, max = {l.width, y}}, u64(l.id), l.loc)
	defer ui.close(&root)
	st := ui.stack_open(gtx)
	defer ui.close(&st)
	if region_shown(l, .Header) {
		place_at(gtx, l.regions[.Header].macro, header_at)
		paint_divider(gtx, l.options[.Header].divider, header_div, false)
	}
	if region_shown(l, .Content) {
		place_at(gtx, l.regions[.Content].macro, content_at)
	}
	if pane_shown {
		place_pane(l, pane)
	}
	if region_shown(l, .Footer) {
		paint_divider(gtx, l.options[.Footer].divider, footer_div, false)
		place_at(gtx, l.regions[.Footer].macro, footer_at)
	}
	return l.settled
}

// place_narrow stacks the pane above (start) or below (end) the content,
// row_gap either side of its horizontal divider, which reaches past the
// root's padding to the page's edges; it returns the stack's height.
@(private)
place_narrow :: proc(l: ^Page_Layout, x0, y, content_h, pane_h: f32, pane_shown: bool, content_at: ^ops.Point, pane: ^Placed_Pane) -> f32 {
	content_at^ = {x0 + (l.container - l.regions[.Content].size.x) / 2, y}
	if !pane_shown {
		return content_h
	}
	d := l.pane.divider
	t := divider_thickness(d)
	between := l.row + (d != .None ? t + l.row : 0)
	div_x, div_w := x0 - l.pad, l.container + 2 * l.pad
	if l.pane.position == .Start {
		pane.at = {x0, y}
		pane.divider = {div_x, y + pane_h + l.row, div_w, t}
		content_at.y = y + pane_h + between
	} else {
		pane.at = {x0, y + content_h + between}
		pane.divider = {div_x, y + content_h + l.row, div_w, t}
	}
	pane.h = pane_h
	return content_h + pane_h + between
}

// place_regular sets the pane and content side by side, the divider
// centred in the gutter, and returns the row's height: the taller of the
// content and the pane, a sticky pane counting at most the window's
// height less its offset.
@(private)
place_regular :: proc(l: ^Page_Layout, x0, y, content_h, pane_h: f32, pane_shown: bool, content_at: ^ops.Point, pane: ^Placed_Pane) -> f32 {
	cx := x0
	if pane_shown && l.pane.position == .Start {
		cx = x0 + l.pane_w + pane_gutter(l)
	}
	inner := l.regions[.Content].size.x
	content_at^ = {cx + max(l.content_w - inner, 0) / 2, y}
	if !pane_shown {
		return content_h
	}
	shown_h := pane_h
	if l.pane.sticky && l.vh > 0 {
		shown_h = min(pane_h, max(l.vh - l.pane.offset_header, 0))
	}
	row_h := max(content_h, shown_h)
	px := l.pane.position == .Start ? x0 : x0 + l.container - l.pane_w
	pane.at = {px, y}
	d := pane_divider(l)
	t := divider_thickness(d)
	dx := l.pane.position == .Start ? px + l.pane_w + l.column : px - l.column - t
	wrapper_h := l.pane.sticky ? shown_h : row_h
	pane.divider = {dx, y, t, wrapper_h}
	pane.h = shown_h
	if l.pane.sticky {
		pane.room = row_h - shown_h
	}
	return row_h
}

// place_pane draws the pane, scrolling its overflow, with its divider and
// drag handle, pinned when sticky.
@(private)
place_pane :: proc(l: ^Page_Layout, pp: Placed_Pane) {
	gtx := l.gtx
	sticky := l.pane.sticky && !l.narrow
	pp := pp
	if sticky {
		// Pinning measures the origin, so the run starts at the pane's top.
		ops.transform_push(gtx.scene, ops.translate(0, pp.at.y))
		ops.sticky_push(gtx.scene, l.pane.offset_header, pp.room)
		pp.divider.y -= pp.at.y
		pp.at.y = 0
	}
	defer if sticky {
		ops.transform_pop(gtx.scene)
		ops.transform_pop(gtx.scene)
	}
	r := l.regions[.Pane]
	if pp.h < r.size.y {
		at := ui.inset_open(gtx, {pp.at.x, pp.at.y, 0, 0})
		box := ui.sized_open(gtx, {min = {r.size.x, pp.h}, max = {r.size.x, pp.h}})
		sb := ui.scroll_box_open(gtx)
		place_recording(gtx, r.macro, r.size, {})
		ui.close(&sb)
		ui.close(&box)
		ui.close(&at)
	} else {
		place_at(gtx, r.macro, pp.at)
	}
	d := l.narrow ? l.pane.divider : pane_divider(l)
	paint_divider(gtx, d, pp.divider, !l.narrow)
	if l.pane.resizable && !l.narrow {
		pane_handle(l, pp.divider)
	}
}

// pane_handle is the drag handle over the vertical divider: 2px past it
// each side, a --bgColor-neutral-muted fill fading in on hover, a
// --bgColor-accent-emphasis fill while dragged. It reads the drag, arrow
// keys and a double-click, and moves the pane's width.
@(private)
pane_handle :: proc(l: ^Page_Layout, div: ops.Rect) {
	gtx := l.gtx
	id := ui.id_mix(l.id, 0x9a7f)
	area := ops.Rect{div.x - PANE_HANDLE_OUTSET, div.y, div.w + 2 * PANE_HANDLE_OUTSET, div.h}
	c := design.control(gtx, id, area, .Live)
	drag := ui.widget_data(gtx, id, Pane_Drag)
	w := pane_current(l)
	lo, hi := pane_bounds(l.pane, l.vw)
	sign: f32 = l.pane.position == .Start ? 1 : -1
	before := w^
	for e in ui.events(gtx, id) {
		#partial switch e.kind {
		case .Press:
			if e.clicks >= 2 {
				w^ = pane_default(l.pane)
				l.settled = true
			}
			drag.dragging = true
		case .Move:
			if drag.dragging && c.st.pressed {
				w^ = clamp(w^ + sign * e.travel.x, lo, hi)
			}
		case .Release, .Cancel:
			if drag.dragging {
				w^ = f32(int(w^ + 0.5))
				l.settled = true
			}
			drag.dragging = false
		case .Key:
			step: f32
			#partial switch e.key {
			case .Left, .Down:
				step = -PANE_KEY_STEP
			case .Right, .Up:
				step = PANE_KEY_STEP
			}
			if l.pane.position == .End && (e.key == .Left || e.key == .Right) {
				step = -step
			}
			if step != 0 {
				w^ = clamp(w^ + step, lo, hi)
				l.settled = true
			}
		}
	}
	if w^ != before {
		ui.request_frame(gtx) // the regions were laid out at the old width
	}
	fill: ops.Color
	switch {
	case drag.dragging:
		fill = color(.Bg_Color_Accent_Emphasis)
	case:
		target := c.hovered ? color(.Bg_Color_Neutral_Muted) : ops.with_alpha(color(.Bg_Color_Neutral_Muted), 0)
		fill = design.blend(gtx, &drag.fades, 0, target, PANE_HOVER_FADE.duration, PANE_HOVER_FADE.easing)
	}
	if ui.painted(fill) {
		ops.fill(gtx.scene, area, fill)
	}
	b := c
	b.focused = c.focus_visible
	design.paint_focus_ring(gtx, b, {area, 0}, focus_outline(0))
	design.listen(gtx, c.st, id, area, design.CLICK_KINDS, .Resize_EW)
	name := l.pane.label != "" ? l.pane.label : "Draggable pane splitter"
	said := ui.frame_string(gtx, name)
	ops.tag(gtx.scene, id, said)
	ui.child_semantics(gtx, 0, id, area, {role = .Slider, label = said, value = pane_value_text(gtx, w^)})
}

// pane_value_text is "Pane width N pixels", the handle's value text.
@(private)
pane_value_text :: proc(gtx: ^ui.Ctx, w: f32) -> string {
	return fmt.aprintf("Pane width %d pixels", int(w + 0.5), allocator = gtx.allocator)
}

// split_page_layout_open opens Primer's SplitPageLayout
// (split-page-layout.json): a page layout with no padding or gaps and a
// full-width container, its pane at the start, sticky, padded normal with
// a line divider unless pane says otherwise. Fill it as a page layout;
// split_page_layout_region_open gives each region the split defaults.
split_page_layout_open :: proc(gtx: ^ui.Ctx, pane: Maybe(Pane) = SPLIT_PANE, key: u64 = 0, loc := #caller_location) -> Page_Layout {
	return page_layout_open(gtx, .Full, .None, .None, .None, pane, key, loc)
}

// SPLIT_PANE is a split page layout's pane: start, sticky, padding
// normal, a line divider (SplitPageLayout.tsx:73-90).
SPLIT_PANE :: Pane {
	position = .Start,
	sticky   = true,
	padding  = .Normal,
	divider  = .Line,
}

// split_page_layout_region_open is page_layout_region_open with the split
// defaults: a header or footer padded normal with a line divider, content
// padded normal with its inner box capped at 1012px
// (SplitPageLayout.tsx:42-64,122-129).
split_page_layout_region_open :: proc(l: ^Page_Layout, r: Page_Region, hidden := false, loc := #caller_location) {
	switch r {
	case .Header, .Footer:
		page_layout_region_open(l, r, .Normal, .Line, hidden = hidden, loc = loc)
	case .Content:
		page_layout_region_open(l, r, .Normal, width = .Large, hidden = hidden, loc = loc)
	case .Pane:
		page_layout_region_open(l, r, hidden = hidden, loc = loc)
	}
}
