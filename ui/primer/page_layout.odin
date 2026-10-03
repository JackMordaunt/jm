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

// Sidebar_Variant is a sidebar's look below 768px: Default keeps it
// beside the container, Fullscreen makes it cover the window.
Sidebar_Variant :: enum u8 {
	Default,
	Fullscreen,
}

// Sidebar is a page layout's sidebar's options (page-layout.json inputs
// sidebar*): its side, width preset or custom bounds, resizing, divider
// (none or line), stickiness and narrow variant. width is as Pane.width:
// the caller's record of a resizable sidebar's width, nil keeping it for
// the session only.
Sidebar :: struct {
	position:  Pane_Position,
	preset:    Pane_Width,
	custom:    Pane_Custom,
	min_width: f32, // a resizable preset sidebar's floor; 0 means 256
	resizable: bool,
	width:     ^f32,
	sticky:    bool,
	divider:   Pane_Divider,
	variant:   Sidebar_Variant,
	hidden:    bool,
	label:     string, // the drag handle's accessible name
}

// PANE_MIN_WIDTH is a resizable preset pane's default floor (paneMinWidth).
PANE_MIN_WIDTH :: f32(256)

// SIDEBAR_MAX_DIFF is how much narrower than the window a resizable
// sidebar's max is, at every width (PageLayout.module.css:7-8,36-37).
SIDEBAR_MAX_DIFF :: f32(256)

// PANE_KEY_STEP is how far an arrow key moves the drag handle
// (DragHandle.tsx:6-8).
PANE_KEY_STEP :: f32(3)

// PANE_HANDLE_OUTSET is how far the handle reaches past each side of the
// divider (PageLayout.module.css:715-723).
PANE_HANDLE_OUTSET :: f32(2)

// PANE_HOVER_FADE is the handle's hover fill fade: 150ms ease
// (PageLayout.module.css:725-739).
PANE_HOVER_FADE :: tok.Transition{150, {0.25, 0.1, 0.25, 1}}

// Side is one of the two regions with a width of their own, the pane and
// the sidebar, which share width presets, resizing, the vertical divider
// and its drag handle.
@(private)
Side :: enum u8 {
	Pane,
	Sidebar,
}

// Side_Rules is what that shared machinery reads from a Pane or Sidebar.
@(private)
Side_Rules :: struct {
	side:      Side,
	position:  Pane_Position,
	preset:    Pane_Width,
	custom:    Pane_Custom,
	min_width: f32,
	resizable: bool,
	width:     ^f32,
	divider:   Pane_Divider,
	label:     string,
}

// pane_default is a side's width with nothing stored: a resizable preset
// starts at its wide value, a custom one at its default.
@(private)
pane_default :: proc(p: Side_Rules) -> f32 {
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

// pane_bounds is a resizable side's [min, max] in a window vw wide. A
// pane preset's max is the window less 511px, less 959px from 1280px; a
// custom pane's bounds are its own. A sidebar's max is the window less
// 256px at every width, which caps a custom max too. No max falls below
// min (usePaneWidth.ts:135-138,235-243).
@(private)
pane_bounds :: proc(p: Side_Rules, vw: f32) -> (lo, hi: f32) {
	custom := p.preset == .Custom
	lo = custom ? p.custom.min : (p.min_width > 0 ? p.min_width : PANE_MIN_WIDTH)
	if p.side == .Sidebar {
		hi = max(vw - SIDEBAR_MAX_DIFF, lo)
		if custom {
			hi = max(min(p.custom.max, hi), lo)
		}
		return
	}
	if custom {
		return lo, max(p.custom.max, lo)
	}
	diff := vw >= tok.BREAKPOINT_XLARGE ? f32(959) : f32(511)
	return lo, max(vw - diff, lo)
}

// pane_preset_width is a non-resizable side's width from 768px: 240, 256
// or 256px, then 256, 296 or 320px from 1012px; a custom one's default
// (PageLayout.module.css:30-49).
@(private)
pane_preset_width :: proc(p: Side_Rules, vw: f32) -> f32 {
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
	Sidebar,
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
	sidebar:            Sidebar,
	has_sidebar:        bool,
	fullscreen:         bool, // the sidebar covers the window
	sides:              [Side]Side_Rules,
	narrow:             bool,
	vw, vh:             f32,
	width, container:   f32, // the offered width and the container's
	room_x, room:       f32, // where the container's row starts, and its width
	pad, row, column:   f32,
	pane_w, content_w:  f32,
	sidebar_w:          f32,
	regions:            [Page_Region]Region_Run,
	options:            [Page_Region]Region_Options,
	open:               Page_Region,
	rec:                ui.Recording,
	inset:              ui.Inset,
	settled:            bool,
}

// Pane_Drag is a resizable side's handle state between frames: the width
// it holds when the caller keeps none, and the press on the handle.
@(private)
Pane_Drag :: struct {
	width: f32,
	drag:  ui.Drag,
	fades: design.Fades,
}

// page_layout_open opens Primer's PageLayout (page-layout.json,
// PageLayout.module.css): a padded root holding a centred container,
// capped at container_width, of an optional header, a content row of
// content and an optional pane, and an optional footer, row_gap apart;
// the pane sits column_gap from a divider between it and the content, or
// below 768px stacks above (start) or below (end) the content at full
// width. A sidebar sits outside the container, beside header, content
// and footer alike, at the start or end of the root's row, column_gap
// from its divider, the container shrinking to the rest. Fill regions
// with page_layout_region_open and close each with
// page_layout_region_close, in any order; page_layout_close places them
// and returns true on the frame a resizable pane's or sidebar's width
// settles (a drag ends, an arrow key moves it, a double-click resets
// it), when the caller saves *pane.width and *sidebar.width.
//
// A resizable pane or sidebar has a 5px handle over its line divider:
// drag it, or focus it and press arrows to step 3px, double-click to
// reset; its width is clamped between its min (256px) and the window less
// 511px (959px from 1280px) for a pane, 256px for a sidebar. A sticky
// pane pins offset_header below the top of the scroll box it scrolls in,
// no taller than the window, scrolling its own overflow; a sticky sidebar
// pins at that top exactly the window's height. Below 768px a fullscreen
// sidebar covers the window on --bgColor-default, above the page and
// without a divider, taking no room in the row (PageLayout.module.css:
// 753-861).
//
// Departures: the widths live in the caller's Pane.width and
// Sidebar.width, so two panes never share the web's default 'paneWidth'
// storage key (page-layout.json gotcha). Arrow keys mirror for an end
// pane, Left growing it, as the sidebar's do (the pane's do not:
// page-layout.json contradiction). The pane's position is a plain value,
// so the web's drag-direction bug with a responsive position cannot arise
// (page-layout.json upstream-bug). Pane.hidden, Sidebar.hidden and the
// region's hidden are plain values the caller resolves per range
// (responsive). Below 768px an inline sidebar keeps its 768px width; the
// CSS gives it 100% of a shrink-to-fit box, its content's max-content
// width, which a paragraph stretches until the container is squeezed to
// nothing (PageLayout.module.css:30-33,840-851). An overflowing pane or
// sidebar is not made a focusable region, and jm:ui has no banner, main
// or contentinfo landmarks.
page_layout_open :: proc(
	gtx: ^ui.Ctx,
	container_width := Container_Width.XLarge,
	padding := Layout_Spacing.Normal,
	row_gap := Layout_Spacing.Normal,
	column_gap := Layout_Spacing.Normal,
	pane: Maybe(Pane) = nil,
	sidebar: Maybe(Sidebar) = nil,
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
	p, has := pane.?
	l.pane, l.has_pane = p, has && !p.hidden
	l.sides[.Pane] = {.Pane, p.position, p.preset, p.custom, p.min_width, p.resizable, p.width, p.divider, p.label}
	b, has_b := sidebar.?
	l.sidebar, l.has_sidebar = b, has_b && !b.hidden
	l.sides[.Sidebar] = {.Sidebar, b.position, b.preset, b.custom, b.min_width, b.resizable, b.width, b.divider, b.label}
	l.fullscreen = l.has_sidebar && l.narrow && b.variant == .Fullscreen
	l.room_x, l.room = l.pad, max(l.width - 2 * l.pad, 0)
	if l.fullscreen {
		l.sidebar_w = l.vw
	} else if l.has_sidebar {
		l.sidebar_w = side_width(&l, .Sidebar)
		take := l.sidebar_w + side_gutter(&l, .Sidebar)
		l.room = max(l.room - take, 0)
		if b.position == .Start {
			l.room_x += take
		}
	}
	l.container = min(l.room, container_cap(container_width))
	l.content_w = l.container
	if l.has_pane {
		l.pane_w = l.container
		if !l.narrow {
			l.pane_w = side_width(&l, .Pane)
			l.content_w = max(l.container - l.pane_w - side_gutter(&l, .Pane), 1)
		}
	}
	return
}

// side_gutter is the space between a side and the content or container
// beside it: column_gap, or a visible divider centred in twice it.
@(private)
side_gutter :: proc(l: ^Page_Layout, s: Side) -> f32 {
	d := side_divider(l, s)
	if d == .None {
		return l.column
	}
	return 2 * l.column + divider_thickness(d)
}

// side_divider is a side's vertical divider: a resizable side always
// draws a line, the pane only at regular widths, where it has one
// (PageLayout.tsx:244,687-746); a fullscreen sidebar draws none
// (PageLayout.module.css:853-861).
@(private)
side_divider :: proc(l: ^Page_Layout, s: Side) -> Pane_Divider {
	r := l.sides[s]
	switch {
	case s == .Sidebar && l.fullscreen:
		return .None
	case r.resizable && (s == .Sidebar || !l.narrow):
		return .Line
	}
	return r.divider
}

// side_width is a side's width beside the content: a resizable side's
// current width clamped to its bounds, else its preset.
@(private)
side_width :: proc(l: ^Page_Layout, s: Side) -> f32 {
	r := l.sides[s]
	if !r.resizable {
		return pane_preset_width(r, l.vw)
	}
	lo, hi := pane_bounds(r, l.vw)
	return clamp(side_current(l, s)^, lo, hi)
}

// side_current is where a side's width is kept: the caller's, else the
// layout's own state; it starts at the default.
@(private)
side_current :: proc(l: ^Page_Layout, s: Side) -> ^f32 {
	r := l.sides[s]
	w := r.width
	if w == nil {
		w = &ui.widget_data(l.gtx, side_id(l, s, 0x7e), Pane_Drag).width
	}
	if w^ <= 0 {
		w^ = pane_default(r)
	}
	return w
}

// side_id is an id for a side's state (0x7e) or handle (0x7f), the pane's
// at the ids it always had.
@(private)
side_id :: proc(l: ^Page_Layout, s: Side, what: u64) -> ops.Area_Id {
	return ui.id_mix(l.id, 0x9a00 + 0x100 * u64(s) + what)
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
	l.regions[r].shown = !hidden && (r != .Pane || l.has_pane) && (r != .Sidebar || l.has_sidebar)
	w := l.container
	pad := layout_spacing(padding, l.vw)
	switch r {
	case .Content:
		w = min(l.content_w, container_cap(width))
	case .Pane:
		w = l.pane_w
		pad = layout_spacing(l.pane.padding, l.vw)
	case .Sidebar:
		w = l.sidebar_w
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

// Placed_Pane is where a side, its divider and handle go in the root.
@(private)
Placed_Pane :: struct {
	at:       ops.Point,
	h:        f32, // shown height: capped at the window when sticky
	divider:  ops.Rect,
	room:     f32, // how far a sticky side may move down its row
	sticky:   bool,
	top:      f32, // how far below the scroll box's top a sticky side pins
}

// page_layout_close places every region, paints the dividers, runs the
// drag handles and closes the layout. It returns true on the frame the
// pane's or sidebar's width settles.
page_layout_close :: proc(l: ^Page_Layout) -> bool {
	gtx := l.gtx
	x0 := l.room_x + max(l.room - l.container, 0) / 2
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
	side: Placed_Pane
	side_shown := l.has_sidebar && region_shown(l, .Sidebar)
	if side_shown && !l.fullscreen {
		y = l.pad + place_sidebar(l, y - l.pad, &side)
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
		place_side(l, .Pane, pane)
	}
	if region_shown(l, .Footer) {
		paint_divider(gtx, l.options[.Footer].divider, footer_div, false)
		place_at(gtx, l.regions[.Footer].macro, footer_at)
	}
	switch {
	case side_shown && l.fullscreen:
		place_fullscreen(l)
	case side_shown:
		place_side(l, .Sidebar, side)
	}
	return l.settled
}

// place_sidebar sets an inline sidebar at the start or end of the root's
// row, beside the container's column stack_h tall, and returns the row's
// height. A sidebar runs the row's full height; a sticky one is exactly
// the window's height, scrolling its overflow (PageLayout.module.css:
// 753-802).
@(private)
place_sidebar :: proc(l: ^Page_Layout, stack_h: f32, pp: ^Placed_Pane) -> f32 {
	row_h := max(stack_h, l.regions[.Sidebar].size.y)
	pp.h = row_h
	if l.sidebar.sticky && l.vh > 0 {
		row_h = max(stack_h, l.vh)
		pp.h = l.vh
		pp.sticky = true
		pp.room = row_h - l.vh
	}
	start := l.sidebar.position == .Start
	x := start ? l.pad : l.width - l.pad - l.sidebar_w
	pp.at = {x, l.pad}
	t := divider_thickness(side_divider(l, .Sidebar))
	dx := start ? x + l.sidebar_w + l.column : x - l.column - t
	pp.divider = {dx, l.pad, t, pp.h}
	return row_h
}

// place_fullscreen lays the sidebar over the whole window from its
// top-left, on --bgColor-default above the rest of the page, taking the
// window's presses and scrolling what overflows it
// (PageLayout.module.css:804-823).
@(private)
place_fullscreen :: proc(l: ^Page_Layout) {
	gtx := l.gtx
	r := l.regions[.Sidebar]
	size := ops.Size{l.vw, l.vh > 0 ? l.vh : r.size.y}
	whole := ops.Rect{0, 0, size.x, size.y}
	layer := ui.overlay_open(gtx, cs = ui.exact(size), root = true, cover = true)
	defer ui.overlay_close(&layer)
	ops.fill(gtx.scene, whole, color(.Bg_Color_Default))
	ops.input_area(gtx.scene, side_id(l, .Sidebar, 0x7d), whole, {.Press, .Release, .Move, .Enter, .Leave, .Scroll})
	box := ui.sized_open(gtx, {min = size, max = size})
	defer ui.close(&box)
	sb := ui.scroll_box_open(gtx)
	defer ui.close(&sb)
	place_recording(gtx, r.macro, r.size, {})
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
		cx = x0 + l.pane_w + side_gutter(l, .Pane)
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
	t := divider_thickness(side_divider(l, .Pane))
	dx := l.pane.position == .Start ? px + l.pane_w + l.column : px - l.column - t
	wrapper_h := l.pane.sticky ? shown_h : row_h
	pane.divider = {dx, y, t, wrapper_h}
	pane.h = shown_h
	if l.pane.sticky {
		pane.sticky = true
		pane.top = l.pane.offset_header
		pane.room = row_h - shown_h
	}
	return row_h
}

// place_side draws a pane or inline sidebar, scrolling its overflow, with
// its divider and drag handle, pinned when sticky. The pane's divider and
// handle run across it below 768px, the sidebar's always down its side.
@(private)
place_side :: proc(l: ^Page_Layout, s: Side, pp: Placed_Pane) {
	gtx := l.gtx
	pp := pp
	if pp.sticky {
		// Pinning measures the origin, so the run starts at the side's top.
		ops.transform_push(gtx.scene, ops.translate(0, pp.at.y))
		ops.sticky_push(gtx.scene, pp.top, pp.room)
		pp.divider.y -= pp.at.y
		pp.at.y = 0
	}
	defer if pp.sticky {
		ops.transform_pop(gtx.scene)
		ops.transform_pop(gtx.scene)
	}
	r := l.regions[s == .Pane ? Page_Region.Pane : .Sidebar]
	if pp.h < r.size.y {
		at := ui.inset_open(gtx, {pp.at.x, pp.at.y, 0, 0})
		box := ui.sized_open(gtx, {min = {r.size.x, pp.h}, max = {r.size.x, pp.h}})
		sb := ui.scroll_box_open(gtx, key = u64(side_id(l, s, 0x7c)))
		place_recording(gtx, r.macro, r.size, {})
		ui.close(&sb)
		ui.close(&box)
		ui.close(&at)
	} else {
		place_at(gtx, r.macro, pp.at)
	}
	vertical := s == .Sidebar || !l.narrow
	paint_divider(gtx, side_divider(l, s), pp.divider, vertical)
	if l.sides[s].resizable && vertical {
		side_handle(l, s, pp.divider)
	}
}

// side_handle is the drag handle over the vertical divider: 2px past it
// each side, a --bgColor-neutral-muted fill fading in on hover, a
// --bgColor-accent-emphasis fill while dragged. It reads the drag, arrow
// keys and a double-click, and moves side s's width.
@(private)
side_handle :: proc(l: ^Page_Layout, s: Side, div: ops.Rect) {
	gtx := l.gtx
	rules := l.sides[s]
	id := side_id(l, s, 0x7f)
	area := ops.Rect{div.x - PANE_HANDLE_OUTSET, div.y, div.w + 2 * PANE_HANDLE_OUTSET, div.h}
	c := design.control(gtx, id, area, .Live)
	drag := ui.widget_data(gtx, id, Pane_Drag)
	w := side_current(l, s)
	lo, hi := pane_bounds(rules, l.vw)
	sign: f32 = rules.position == .Start ? 1 : -1
	before := w^
	// The width follows the handle from its first pixel and settles on a
	// whole one when the press ends, dragged or not.
	ui.drag_update(&drag.drag, ui.events(gtx, id), .Horizontal, slop = 0)
	ended := false
	for e in ui.events(gtx, id) {
		#partial switch e.kind {
		case .Press:
			if e.clicks >= 2 {
				w^ = pane_default(rules)
				l.settled = true
			}
		case .Release, .Cancel:
			ended = true
		case .Key:
			step: f32
			#partial switch e.key {
			case .Left, .Down:
				step = -PANE_KEY_STEP
			case .Right, .Up:
				step = PANE_KEY_STEP
			}
			if rules.position == .End && (e.key == .Left || e.key == .Right) {
				step = -step
			}
			if step != 0 {
				w^ = clamp(w^ + step, lo, hi)
				l.settled = true
			}
		}
	}
	if drag.drag.delta.x != 0 {
		w^ = clamp(w^ + sign * drag.drag.delta.x, lo, hi)
	}
	if ended {
		w^ = f32(int(w^ + 0.5))
		l.settled = true
	}
	if w^ != before {
		ui.request_frame(gtx) // the regions were laid out at the old width
	}
	fill: ops.Color
	switch {
	case drag.drag.phase != .Idle:
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
	name := rules.label != "" ? rules.label : "Draggable pane splitter"
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
	return page_layout_open(gtx, .Full, .None, .None, .None, pane, key = key, loc = loc)
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
	case .Pane, .Sidebar:
		page_layout_region_open(l, r, hidden = hidden, loc = loc)
	}
}
