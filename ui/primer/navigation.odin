package primer

import "core:fmt"
import "core:math"
import "jm:ui"
import "jm:ui/design"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// Navigation: Pagination, SubNav, UnderlinePanels, UnderlineNav,
// Breadcrumbs and NavList (primer-kit components/pagination.json,
// sub-nav.json, underline-panels.json, underline-nav.json,
// breadcrumbs.json, nav-list.json). TreeView is in tree_view.odin.

// Viewport_Ranges is the ranges a responsive prop switches off in, as
// Pagination's hide_pages takes them.
Viewport_Ranges :: bit_set[Viewport_Range]

// --- Pagination ---------------------------------------------------------

// Page_Kind is what a pagination entry is.
Page_Kind :: enum u8 {
	Previous,
	Next,
	Number,
	Break, // an ellipsis standing for hidden pages
}

// Page_Entry is one entry of the pagination model: num is the page it
// goes to (1-based), selected the current page, precedes_break the page
// just before an ellipsis.
Page_Entry :: struct {
	kind:                               Page_Kind,
	num:                                int,
	disabled, selected, precedes_break: bool,
}

// pagination_model is the entries Pagination shows for page current of
// count (model.tsx:8-109): Previous, then with show_pages every page when
// they fit in 2 x (margin + surrounding) + 3 entries, else margin pages at
// each end, surrounding pages either side of current and an ellipsis for
// each run hidden (never for a single page), keeping that many entries;
// then Next. Previous is disabled on page 1, Next on the last page and
// whenever count is 0 or less. current is not clamped.
pagination_model :: proc(count, current: int, show_pages: bool, margin, surrounding: int, allocator := context.allocator) -> []Page_Entry {
	out := make([dynamic]Page_Entry, allocator)
	append(&out, Page_Entry{kind = .Previous, num = current - 1, disabled = current == 1})
	next := Page_Entry{kind = .Next, num = current + 1, disabled = current == count}
	switch {
	case !show_pages:
	case count <= 0:
		next.disabled = true
	case:
		append_page_numbers(&out, count, current, margin, surrounding)
	}
	append(&out, next)
	return out[:]
}

// append_page_numbers appends the numbers and ellipses between Previous and
// Next (model.tsx:20-109).
@(private)
append_page_numbers :: proc(out: ^[dynamic]Page_Entry, count, current, margin, surrounding: int) {
	add :: proc(out: ^[dynamic]Page_Entry, from, to, current: int, before_break: bool) {
		for i in from ..= to {
			append(out, Page_Entry{kind = .Number, num = i, selected = i == current, precedes_break = i == to && before_break})
		}
	}
	gap := surrounding + margin
	if count <= 2 * gap + 3 {
		add(out, 1, count, current, false)
		return
	}
	start_gap, start_offset, end_gap, end_offset := 0, 0, 0, 0
	if current - gap - 1 <= 1 {
		start_offset = current - gap - 2
	} else {
		start_gap = current - gap - 1
	}
	if count - current - gap <= 1 {
		end_offset = count - current - gap - 1
	} else {
		end_gap = count - current - gap
	}
	add(out, 1, margin, current, start_gap > 0)
	if start_gap > 0 {
		append(out, Page_Entry{kind = .Break, num = margin + 1})
	}
	last := count - start_offset - end_gap - margin
	add(out, margin + start_gap + end_offset + 1, last, current, end_gap > 0)
	if end_gap > 0 {
		append(out, Page_Entry{kind = .Break, num = last + 1})
	}
	add(out, count - margin + 1, count, current, false)
}

// PAGE_ENTRY is an entry's box: at least 32px wide and exactly 32px tall,
// padded (32 - 20) / 2 = 6px at the sides, 4px after it; PAGE_ICON_GAP
// the 4px between a chevron and its text (Pagination.module.css:1-41).
PAGE_ENTRY :: tok.BASE_SIZE_32
PAGE_PAD :: (tok.BASE_SIZE_32 - tok.BASE_SIZE_20) / 2
PAGE_GAP :: tok.BASE_SIZE_4

// PAGINATION_MARGIN is the container's hard-coded 20px top and 15px
// bottom margin (Pagination.module.css:88-94).
PAGINATION_MARGIN :: [2]f32{20, 15}

// PAGE_FADE_IN and PAGE_FADE_OUT are the hover fill's fades: 100ms in,
// 200ms back out, on cubic-bezier(0.3, 0, 0.5, 1)
// (Pagination.module.css:18,43-49).
PAGE_FADE_IN :: tok.Transition{tok.BASE_DURATION_100, {0.3, 0, 0.5, 1}}
PAGE_FADE_OUT :: tok.Transition{tok.BASE_DURATION_200, {0.3, 0, 0.5, 1}}

// page_style is an entry's text: the medium body size it inherits at
// line height 1 (Pagination.module.css:8).
@(private)
page_style :: proc() -> tok.Type_Style {
	return {weight = tok.BASE_TEXT_WEIGHT_NORMAL, size = tok.TEXT_BODY_SIZE_MEDIUM, line_height = tok.TEXT_BODY_SIZE_MEDIUM}
}

// Page_Shape is an entry measured: its text and box width.
@(private)
Page_Shape :: struct {
	text: Text,
	w:    f32,
}

@(private)
page_text :: proc(gtx: ^ui.Ctx, e: Page_Entry) -> string {
	switch e.kind {
	case .Previous:
		return "Previous"
	case .Next:
		return "Next"
	case .Break:
		return "…"
	case .Number:
	}
	return fmt.aprintf("%d", e.num, allocator = gtx.allocator)
}

// page_name is what assistive technology calls an entry
// (pagination.json semantics).
@(private)
page_name :: proc(gtx: ^ui.Ctx, e: Page_Entry) -> string {
	switch e.kind {
	case .Previous:
		return "Previous Page"
	case .Next:
		return "Next Page"
	case .Break:
		return "…"
	case .Number:
	}
	return fmt.aprintf("Page %d%s", e.num, e.precedes_break ? "..." : "", allocator = gtx.allocator)
}

// pagination is Primer's Pagination (pagination.json, Pagination.tsx,
// Pagination.module.css, model.tsx): Previous and Next links around the
// pages pagination_model gives for page^ of page_count, centred in the
// width offered with 20px above and 15px below. Each entry is a box at
// least 32px square, 4px apart: page numbers in --fgColor-default,
// Previous and Next in --fgColor-accent beside a 1em chevron, the
// current page filled --bgColor-accent-emphasis with --fgColor-onEmphasis
// text, ellipses and the disabled ends in --fgColor-disabled. Hover, and
// focus by any means, fade --control-transparent-bgColor-hover in over
// 100ms and out over 200ms; keyboard focus outlines an entry 2px in
// --bgColor-accent-emphasis inside its edge, the current page with a 3px
// --fgColor-onEmphasis ring inside that. Activating an entry sets page^ to
// its page and returns true. show_pages false keeps only Previous and
// Next; hide_pages hides the numbers in those viewport ranges, Previous
// and Next then touching. state forces the first page that is not the
// current one.
//
// The ranges are Narrow below 768px, Regular from 768 to 1399px and Wide
// from 1400px: the CSS's regular range also matches wide windows, so
// hiding the numbers for regular hides them on wide ones too
// (pagination.json upstream bug); here each range stands alone.
//
// Departures: there are no hrefs or renderPage, onPageChange being the
// activation; Space activates an entry as Enter does; the disabled ends
// are left out of the semantic tree, as aria-hidden does, but drawn.
pagination :: proc(
	gtx: ^ui.Ctx,
	page: ^int,
	page_count: int,
	margin_count := 1,
	surrounding_count := 2,
	show_pages := true,
	hide_pages := Viewport_Ranges{},
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_open(gtx, key, loc)
	entries := pagination_model(page_count, page^, show_pages, margin_count, surrounding_count, gtx.allocator)
	hidden := viewport_range(gtx) in hide_pages
	st := page_style()
	shapes := make([]Page_Shape, len(entries), gtx.allocator)
	total: f32
	shown := 0
	for e, i in entries {
		if hidden && (e.kind == .Number || e.kind == .Break) {
			continue
		}
		t := design.shape_style(gtx, page_text(gtx, e), st, font_for(gtx, st.weight))
		content := t.width
		if e.kind == .Previous || e.kind == .Next {
			content += st.size + PAGE_GAP
		}
		shapes[i] = {t, max(PAGE_ENTRY, 2 * PAGE_PAD + content)}
		total += shapes[i].w
		shown += 1
	}
	if !hidden {
		total += f32(max(shown - 1, 0)) * PAGE_GAP
	}
	cs := gtx.constraints
	w := ui.is_finite(cs.max.x) ? max(cs.max.x, total) : total
	sz := ui.constrain(cs, {w, PAGINATION_MARGIN[0] + PAGE_ENTRY + PAGINATION_MARGIN[1]})
	ui.semantics(gtx, &p, {role = .Navigation, label = "Pagination"})
	x := (sz.x - total) / 2
	forced := false
	changed := false
	for e, i in entries {
		if hidden && (e.kind == .Number || e.kind == .Break) {
			continue
		}
		r := ops.Rect{x, PAGINATION_MARGIN[0], shapes[i].w, PAGE_ENTRY}
		x += r.w + (hidden ? 0 : PAGE_GAP)
		es := Interaction.Live if state == .Live else .Enabled
		if state != .Live && !forced && e.kind == .Number && !e.selected {
			es, forced = state, true
		}
		if draw_page_entry(gtx, &p, e, shapes[i].text, r, i, es) {
			page^ = e.num
			changed = true
		}
	}
	ops.tag(gtx.scene, p.id, "Pagination", {0, 0, sz.x, sz.y})
	ui.widget_close(gtx, &p, {sz, 0})
	return changed
}

// draw_page_entry draws entry e in r and reports its activation.
@(private)
draw_page_entry :: proc(gtx: ^ui.Ctx, p: ^ui.Placement, e: Page_Entry, t: Text, r: ops.Rect, i: int, state: Interaction) -> bool {
	id := ui.id_mix(p.id, u64(i) + 1)
	inert := e.kind == .Break || e.disabled
	c := control(gtx, id, r, inert ? .Disabled : state)
	rr := ops.Round_Rect{r, tok.BORDER_RADIUS_MEDIUM}
	fg := tok.Role.Fg_Color_Default
	fill := tok.Role.Bg_Color_Transparent
	switch {
	case inert:
		fg = .Fg_Color_Disabled
	case e.selected:
		fg, fill = .Fg_Color_On_Emphasis, .Bg_Color_Accent_Emphasis
	case:
		if e.kind != .Number {
			fg = .Fg_Color_Accent
		}
		if c.hovered || c.focused || c.pressed {
			fill = .Control_Transparent_Bg_Color_Hover
		}
	}
	fade := fill == .Control_Transparent_Bg_Color_Hover ? PAGE_FADE_IN : PAGE_FADE_OUT
	bg := design.blend(gtx, c.fades, 0, color(fill), e.selected ? 0 : fade.duration, fade.easing)
	if ui.painted(bg) {
		ops.fill(gtx.scene, rr, bg)
	}
	ink := color(fg)
	chev := page_style().size
	x := r.x + (r.w - t.width - (e.kind == .Previous || e.kind == .Next ? chev + PAGE_GAP : 0)) / 2
	cy := r.y + (r.h - chev) / 2
	if e.kind == .Previous {
		icon(gtx, .Chevron_Left, {x, cy}, chev, ink)
		x += chev + PAGE_GAP
	}
	draw_text(gtx, t, {x, r.y + (r.h - t.height) / 2}, ink)
	if e.kind == .Next {
		icon(gtx, .Chevron_Right, {x + t.width + PAGE_GAP, cy}, chev, ink)
	}
	if e.selected && c.focus_visible {
		design.paint_inset_shadow(gtx, rr, {spread = ON_EMPHASIS_RING, color = color(.Fg_Color_On_Emphasis)})
	}
	design.paint_focus_visible_ring(gtx, c.base, r, corners_all(tok.BORDER_RADIUS_MEDIUM), {tok.BASE_SIZE_2, -tok.BASE_SIZE_2, color(.Bg_Color_Accent_Emphasis)})
	listen(gtx, c.st, id, r, cursor = .Pointer)
	name := ui.frame_string(gtx, page_name(gtx, e))
	ops.tag(gtx.scene, id, name, r)
	if !inert {
		ui.part_semantics(gtx, p, id, r, {role = .Link, label = name, states = design.state_if(e.selected, {.Current_Page})})
	}
	return c.clicked && !inert
}

// --- SubNav -------------------------------------------------------------

// Sub_Nav_Link is one of a SubNav's links; selected marks the current
// view.
Sub_Nav_Link :: struct {
	label:    string,
	selected: bool,
}

// SUB_NAV_LINK is a link's minimum height and SUB_NAV_LINE its line
// height, both custom to SubNav (SubNav.module.css:28-43).
SUB_NAV_LINK :: f32(34)
SUB_NAV_LINE :: f32(20)

// SUB_NAV_FADE is the hover fill's 200ms ease (SubNav.module.css:56-61).
SUB_NAV_FADE :: tok.Transition{tok.BASE_DURATION_200, tok.BASE_EASING_EASE}

// Sub_Nav is an open SubNav: clicked is the link activated this frame,
// -1 for none.
Sub_Nav :: struct {
	clicked: int,
	row:     ui.Flex,
}

// sub_nav_open opens Primer's SubNav (sub-nav.json, SubNav.tsx,
// SubNav.module.css): a navigation landmark named label, its links joined
// into one segmented box at the start of a row, the caller's actions
// (drawn before sub_nav_close) centred at its end. Each link is at least
// 34px tall, 16px padded, medium-weight medium body text on a 20px line in
// --fgColor-default, sharing 1px --borderColor-default borders with its
// neighbours, the outer corners rounded --borderRadius-medium. Hover, and
// focus by any means, fade --bgColor-muted in over 200ms; the selected
// link fills --bgColor-accent-emphasis, its text --fgColor-onEmphasis and
// its borders the accent. The box hangs 1px below the row, so its bottom
// border can sit on a rule under the SubNav. state forces the first link
// that is not selected.
//
// Departures: the module draws no focus ring, only the hover fill; this
// draws Primer's 2px --focus-outline-color outline for keyboard focus too,
// as sub-nav.json advises. align and full are not built: Primer documents
// them but implements neither (sub-nav.json upstream bug).
sub_nav_open :: proc(gtx: ^ui.Ctx, label: string, links: []Sub_Nav_Link, state := Interaction.Live, key: u64 = 0, loc := #caller_location) -> (s: Sub_Nav) {
	s.clicked = -1
	s.row = ui.row_open(gtx, align = .Center, key = key, loc = loc)
	ui.container_semantics(gtx, {role = .Navigation, label = ui.frame_string(gtx, label)})
	s.clicked = draw_sub_nav_links(gtx, links, state)
	ui.fill_space(gtx)
	return
}

// sub_nav_close closes a SubNav after its actions.
sub_nav_close :: proc(s: ^Sub_Nav) {
	ui.close(&s.row)
}

// draw_sub_nav_links draws the link group and reports the link activated.
@(private)
draw_sub_nav_links :: proc(gtx: ^ui.Ctx, links: []Sub_Nav_Link, state: Interaction, loc := #caller_location) -> (clicked: int) {
	clicked = -1
	p := ui.widget_open(gtx, 0, loc)
	st := tok.Type_Style{weight = tok.BASE_TEXT_WEIGHT_MEDIUM, size = tok.TEXT_BODY_SIZE_MEDIUM, line_height = SUB_NAV_LINE}
	b := tok.BORDER_WIDTH_THIN
	x: f32
	forced := false
	for l, i in links {
		t := design.shape_style(gtx, l.label, st, font_for(gtx, st.weight))
		first, last := i == 0, i == len(links) - 1
		w := (first ? b : 0) + 2 * tok.BASE_SIZE_16 + t.width + b
		r := ops.Rect{x, 0, w, SUB_NAV_LINK}
		x += w
		ls := Interaction.Live if state == .Live else .Enabled
		if state != .Live && !forced && !l.selected {
			ls, forced = state, true
		}
		id := ui.id_mix(p.id, u64(i) + 1)
		c := control(gtx, id, r, ls)
		left := first ? tok.BORDER_RADIUS_MEDIUM : 0
		right := last ? tok.BORDER_RADIUS_MEDIUM : 0
		corners := Corners{left, right, right, left}
		fill := tok.Role.Bg_Color_Transparent
		if c.hovered || c.focused || c.pressed {
			fill = .Bg_Color_Muted
		}
		edge := tok.Role.Border_Color_Default
		fg := tok.Role.Fg_Color_Default
		if l.selected {
			fill, edge, fg = .Bg_Color_Accent_Emphasis, .Bg_Color_Accent_Emphasis, .Fg_Color_On_Emphasis
		}
		bg := design.blend(gtx, c.fades, 0, color(fill), l.selected ? 0 : SUB_NAV_FADE.duration, SUB_NAV_FADE.easing)
		if ui.painted(bg) {
			ops.fill(gtx.scene, rounded(gtx, r, corners), bg)
		}
		paint_sub_nav_borders(gtx, r, corners, first, color(edge))
		draw_text(gtx, t, {r.x + (first ? b : 0) + tok.BASE_SIZE_16, (SUB_NAV_LINK - t.height) / 2}, color(fg))
		design.paint_focus_visible_ring(gtx, c.base, r, corners, focus_outline())
		listen(gtx, c.st, id, r, cursor = .Pointer)
		said := ui.frame_string(gtx, l.label)
		ops.tag(gtx.scene, id, said, r)
		ui.part_semantics(gtx, &p, id, r, {role = .Link, label = said, states = design.state_if(l.selected, {.Current})})
		if c.clicked {
			clicked = i
		}
	}
	// The box hangs 1px below the row: its margin-bottom is -1px
	// (SubNav.module.css:6-9).
	ui.widget_close(gtx, &p, {{x, SUB_NAV_LINK - b}, 0})
	return
}

// paint_sub_nav_borders draws a link's top, right and bottom borders,
// and its left one when first, following its rounded corners.
@(private)
paint_sub_nav_borders :: proc(gtx: ^ui.Ctx, r: ops.Rect, c: Corners, first: bool, ink: ops.Color) {
	b := tok.BORDER_WIDTH_THIN
	if first {
		stroke_inside_corners(gtx, r, c, ink, b)
		return
	}
	// Clip off the left edge: the neighbour's right border is the divider.
	ops.clip_push(gtx.scene, ops.Rect{r.x + b, r.y, r.w - b, r.h})
	stroke_inside_corners(gtx, {r.x - b, r.y, r.w + b, r.h}, c, ink, b)
	ops.clip_pop(gtx.scene)
}

// --- Underline tabs ------------------------------------------------------

// Underline_Tab is a tab of UnderlinePanels or an item of UnderlineNav:
// its label, a leading 16px icon and a counter.
Underline_Tab :: struct {
	label:   string,
	icon:    Icon,
	counter: string,
}

// UNDERLINE_STRIP is the strip's height, --control-xlarge-size, padded
// 8px on top and --stack-padding-normal at the sides; UNDERLINE_TAB a
// tab's 32px height, 8px inline padding and 8px margin below
// (UnderlineTabbedInterface.module.css:1-14,55-77).
UNDERLINE_STRIP :: tok.CONTROL_XLARGE_SIZE
UNDERLINE_TAB :: tok.BASE_SIZE_32
UNDERLINE_TAB_PAD :: tok.BASE_SIZE_8

// UNDERLINE_HOVER is the hover fill's 120ms ease-out
// (UnderlineTabbedInterface.module.css:79-85).
UNDERLINE_HOVER :: tok.Transition{120, {0, 0, 0.58, 1}}

// UNDERLINE_PULSE is a loading counter's opacity swing, 1 to 0.2 and
// back, 1.2s each way, ease-in-out (UnderlineTabbedInterface.module.css
// :161-181).
UNDERLINE_PULSE :: tok.Transition{1200, {0.42, 0, 0.58, 1}}

// UNDERLINE_LOADING is the loading counter's 24x16px pill.
UNDERLINE_LOADING :: ops.Size{tok.BASE_SIZE_24, tok.BASE_SIZE_16}

// Underline_Shape is a tab measured: its label at rest and selected, its
// counter, and its width, which reserves the semibold label's.
@(private)
Underline_Shape :: struct {
	label, bold, count: Text,
	w:                  f32,
}

// underline_style is a tab's label: medium body text, semibold when
// selected.
@(private)
underline_style :: proc(semibold: bool) -> tok.Type_Style {
	return {
		weight      = semibold ? tok.BASE_TEXT_WEIGHT_SEMIBOLD : tok.BASE_TEXT_WEIGHT_NORMAL,
		size        = tok.TEXT_BODY_SIZE_MEDIUM,
		line_height = tok.TEXT_BODY_SIZE_MEDIUM * tok.TEXT_BODY_LINE_HEIGHT_MEDIUM,
	}
}

// measure_underline_tab is t's shape: 8px each side of the icon and 8px,
// the semibold label, and 8px and the counter (or the loading pill).
@(private)
measure_underline_tab :: proc(gtx: ^ui.Ctx, t: Underline_Tab, loading: bool) -> (s: Underline_Shape) {
	reg, semi := underline_style(false), underline_style(true)
	s.label = design.shape_style(gtx, t.label, reg, font_for(gtx, reg.weight))
	s.bold = design.shape_style(gtx, t.label, semi, font_for(gtx, semi.weight))
	cst := counter_style()
	s.count = design.shape_style(gtx, t.counter, cst, font_for(gtx, cst.weight))
	s.w = 2 * UNDERLINE_TAB_PAD + s.bold.width
	if t.icon != .None {
		s.w += BUTTON_ICON + tok.BASE_SIZE_8
	}
	switch {
	case loading:
		s.w += tok.BASE_SIZE_8 + UNDERLINE_LOADING.x
	case t.counter != "":
		s.w += tok.BASE_SIZE_8 + counter_size(s.count).x
	}
	return
}

// paint_underline_tab draws tab t, shaped s, in r: hover fill, icon,
// label (semibold when selected), counter or loading pill, the 2px
// --underlineNav-borderColor-active underline 8px below the tab when
// selected, and the 2px --fgColor-accent inset focus ring
// (UnderlineTabbedInterface.module.css:55-181).
@(private)
paint_underline_tab :: proc(gtx: ^ui.Ctx, c: Control, t: Underline_Tab, s: Underline_Shape, r: ops.Rect, selected, loading: bool) {
	rr := ops.Round_Rect{r, tok.BORDER_RADIUS_MEDIUM}
	fill := tok.Role.Bg_Color_Transparent
	if c.hovered && !c.disabled {
		fill = .Bg_Color_Neutral_Muted
	}
	bg := design.blend(gtx, c.fades, 0, color(fill), UNDERLINE_HOVER.duration, UNDERLINE_HOVER.easing)
	if ui.painted(bg) {
		ops.fill(gtx.scene, rr, bg)
	}
	x := r.x + UNDERLINE_TAB_PAD
	if t.icon != .None {
		icon(gtx, t.icon, {x, r.y + (r.h - BUTTON_ICON) / 2}, BUTTON_ICON, color(.Fg_Color_Muted))
		x += BUTTON_ICON + tok.BASE_SIZE_8
	}
	text := selected ? s.bold : s.label
	draw_text(gtx, text, {x + (s.bold.width - text.width) / 2, r.y + (r.h - text.height) / 2}, color(.Fg_Color_Default))
	x += s.bold.width
	switch {
	case loading:
		pill := ops.Rect{x + tok.BASE_SIZE_8, r.y + (r.h - UNDERLINE_LOADING.y) / 2, UNDERLINE_LOADING.x, UNDERLINE_LOADING.y}
		ops.fill(gtx.scene, ops.Round_Rect{pill, radius(COUNTER_RADIUS, pill)}, fade(color(.Bg_Color_Neutral_Muted), underline_pulse(gtx)))
	case t.counter != "":
		csz := counter_size(s.count)
		paint_counter(gtx, s.count, {x + tok.BASE_SIZE_8, r.y + (r.h - csz.y) / 2}, counter_colors(.Secondary))
	}
	if selected {
		ops.fill(gtx.scene, ops.Rect{r.x, r.y + r.h + tok.BASE_SIZE_8 - tok.BORDER_WIDTH_THICK, r.w, tok.BORDER_WIDTH_THICK}, color(.Underline_Nav_Border_Color_Active))
	}
	if c.focus_visible {
		design.paint_inset_shadow(gtx, rr, {spread = tok.BORDER_WIDTH_THICK, color = color(.Fg_Color_Accent)})
	}
}

// underline_pulse is the loading pill's opacity now; it holds at 1 under
// reduced motion.
@(private)
underline_pulse :: proc(gtx: ^ui.Ctx) -> f32 {
	if gtx.reduce_motion {
		return 1
	}
	period := f64(UNDERLINE_PULSE.duration) / 1000
	phase := math.mod(gtx.time, 2 * period) / period
	u := f32(phase if phase <= 1 else 2 - phase)
	ui.request_frame(gtx)
	return 1 - 0.8 * bezier_ease(UNDERLINE_PULSE.easing, u)
}

// paint_underline_strip draws the strip's 1px --borderColor-muted bottom
// line, an inset shadow in the CSS (UnderlineTabbedInterface.module.css
// :12-14).
@(private)
paint_underline_strip :: proc(gtx: ^ui.Ctx, w: f32) {
	ops.fill(gtx.scene, ops.Rect{0, UNDERLINE_STRIP - tok.BORDER_WIDTH_THIN, w, tok.BORDER_WIDTH_THIN}, color(.Border_Color_Muted))
}

// --- UnderlinePanels -----------------------------------------------------

// Activation_Mode is when a focused tab is selected: at once
// (Automatic), or only on Enter, Space or a press (Manual).
Activation_Mode :: enum u8 {
	Automatic,
	Manual,
}

// Underline_Panels is an open UnderlinePanels between
// underline_panels_open and underline_panels_close: changed is set on the
// frame the selection changes, by any means; selected_by is the tab whose
// onSelect fires (a press, Enter or Space; never arrows), -1 for none.
Underline_Panels :: struct {
	changed:     bool,
	selected_by: int,
	gtx:         ^ui.Ctx,
	col:         ui.Flex,
	panel:       ui.Flex,
}

// Underline_Panels_Memo is the tab a manual tab list's arrows last
// focused, which holds the tab stop until something is selected.
@(private)
Underline_Panels_Memo :: struct {
	focus: int,
	moved: bool, // arrows moved focus this frame: focus it once drawn
}

// underline_panels_open opens Primer's UnderlinePanels
// (underline-panels.json, UnderlinePanels.tsx,
// UnderlineTabbedInterface.module.css): a full-width strip at least 48px
// tall, padded 8px on top and 16px at the sides, over a 1px
// --borderColor-muted line, holding one row of tabs 8px apart; then the
// selected tab's panel, which the caller draws before
// underline_panels_close. A tab is 32px tall with 8px side padding and
// medium radius: a 16px --fgColor-muted icon and 8px, the label
// (semibold when selected, its width reserved so selection never shifts
// the row), and 8px and a CounterLabel, or with loading_counters a 24x16px
// pulsing pill. The selected tab carries a 2px
// --underlineNav-borderColor-active underline on the strip's bottom
// edge; hover fades --bgColor-neutral-muted in over 120ms; keyboard focus
// rings the tab inside with 2px of --fgColor-accent. The strip scrolls
// sideways when the tabs are wider than it.
//
// The tab list is one tab stop, at the selected tab (in Manual mode the
// tab arrows last reached, until something is selected). Right and Left
// move between tabs, wrapping, Home and End to the ends; in Automatic mode
// they select too. A primary press selects on the way down; Enter or
// Space selects. selected^ is the selected tab's index; an index that
// names no tab reads as the first. state forces the first unselected tab.
//
// A tab that arrows focus scrolls into view.
//
// Departures: tabs and panels pair by index, not by value. Icons
// always show: Primer measures when they should hide and nothing reads
// the result (underline-panels.json upstream bug).
underline_panels_open :: proc(
	gtx: ^ui.Ctx,
	label: string,
	tabs: []Underline_Tab,
	selected: ^int,
	mode := Activation_Mode.Automatic,
	loading_counters := false,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> (up: Underline_Panels) {
	up.gtx = gtx
	up.selected_by = -1
	id := ui.claim_id(gtx, key, loc)
	if selected^ < 0 || selected^ >= len(tabs) {
		selected^ = 0
	}
	up.col = ui.column_open(gtx, align = .Fill, key = u64(ui.id_mix(id, 1)))
	w := gtx.constraints.max.x
	if !ui.is_finite(w) {
		w = 0
	}
	shapes := make([]Underline_Shape, len(tabs), gtx.allocator)
	total := 2 * tok.STACK_PADDING_NORMAL
	for t, i in tabs {
		shapes[i] = measure_underline_tab(gtx, t, loading_counters)
		total += shapes[i].w + (i > 0 ? tok.STACK_GAP_CONDENSED : 0)
	}
	strip_w := max(w, total)
	box := ui.sized_open(gtx, {min = {w, UNDERLINE_STRIP}, max = {w, UNDERLINE_STRIP}}, key = u64(ui.id_mix(id, 2)))
	paint_underline_strip(gtx, w)
	sb := ui.scroll_box_open(gtx, key = u64(ui.id_mix(id, 3)), wide = true)
	before := selected^
	up.selected_by = draw_underline_tabs(gtx, id, label, tabs, shapes, selected, mode, loading_counters, strip_w, state)
	up.changed = selected^ != before
	ui.close(&sb)
	ui.close(&box)
	up.panel = ui.column_open(gtx, align = .Fill, key = u64(ui.id_mix(id, 4)))
	panel_label := len(tabs) > 0 ? tabs[selected^].label : ""
	ui.container_semantics(gtx, {role = .Tab_Panel, label = ui.frame_string(gtx, panel_label)})
	return
}

// underline_panels_close closes the panel and the component.
underline_panels_close :: proc(up: ^Underline_Panels) {
	ui.close(&up.panel)
	ui.close(&up.col)
}

// draw_underline_tabs draws the tab row strip_w wide and runs its keys and
// presses; it returns the tab whose onSelect fires, -1 for none.
@(private)
draw_underline_tabs :: proc(
	gtx: ^ui.Ctx,
	id: ops.Area_Id,
	label: string,
	tabs: []Underline_Tab,
	shapes: []Underline_Shape,
	selected: ^int,
	mode: Activation_Mode,
	loading: bool,
	strip_w: f32,
	state: Interaction,
) -> (fired: int) {
	fired = -1
	p := ui.widget_open(gtx, u64(ui.id_mix(id, 5)))
	m := ui.widget_data(gtx, id, Underline_Panels_Memo)
	n := len(tabs)
	stop := mode == .Manual && m.focus >= 0 && m.focus < n ? m.focus : selected^
	if mode == .Automatic {
		m.focus = selected^
	}
	ui.semantics(gtx, &p, {role = .Tab_List, label = ui.frame_string(gtx, label)})
	x := tok.STACK_PADDING_NORMAL
	forced := false
	for t, i in tabs {
		r := ops.Rect{x, tok.BASE_SIZE_8, shapes[i].w, UNDERLINE_TAB}
		x += r.w + tok.STACK_GAP_CONDENSED
		tid := ui.id_mix(p.id, u64(i) + 1)
		ts := Interaction.Live if state == .Live else .Enabled
		if state != .Live && !forced && i != selected^ {
			ts, forced = state, true
		}
		c := control(gtx, tid, r, ts)
		if c.st != nil && underline_tab_events(gtx, tid, i, n, selected, mode, m) {
			fired = i
		}
		paint_underline_tab(gtx, c, t, shapes[i], r, i == selected^, loading)
		kinds := CLICK_KINDS
		if i != stop {
			kinds -= {.Key}
		}
		listen(gtx, c.st, tid, r, kinds, .Pointer)
		said := ui.frame_string(gtx, t.label)
		ops.tag(gtx.scene, tid, said, r)
		ui.part_semantics(gtx, &p, tid, r, {role = .Tab, label = said, description = ui.frame_string(gtx, t.counter), states = design.state_if(i == selected^, {.Selected})})
	}
	if m.moved {
		// Focus moves to the tab: bring it into view, as the web's
		// focus() does (useTabList.ts:47-71).
		m.moved = false
		ui.focus_request(gtx, ui.id_mix(p.id, u64(m.focus) + 1))
		at := tok.STACK_PADDING_NORMAL
		for s in shapes[:m.focus] {
			at += s.w + tok.STACK_GAP_CONDENSED
		}
		ui.scroll_into_view(gtx, {at, tok.BASE_SIZE_8, shapes[m.focus].w, UNDERLINE_TAB})
	}
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, label), {0, 0, strip_w, UNDERLINE_STRIP})
	ui.widget_close(gtx, &p, {{strip_w, UNDERLINE_STRIP}, 0})
	return
}

// underline_tab_events runs tab i of n's input: a primary press without
// Ctrl selects on the way down (useTab.ts:25-31), Enter or Space selects,
// arrows move focus (selecting in Automatic mode), and in Automatic mode
// gaining focus selects. It reports whether the tab's onSelect fires.
@(private)
underline_tab_events :: proc(gtx: ^ui.Ctx, tid: ops.Area_Id, i, n: int, selected: ^int, mode: Activation_Mode, m: ^Underline_Panels_Memo) -> (fired: bool) {
	for e in ui.events(gtx, tid) {
		#partial switch e.kind {
		case .Press:
			if e.button == .Left && .Ctrl not_in e.mods {
				fired = true
				selected^, m.focus = i, i
				// Only the tab stop wants keys, so a press on another
				// does not focus it by itself.
				ui.focus_request(gtx, tid)
			}
		case .Key:
			to := underline_step(e.key, i, n)
			switch {
			case to >= 0 && to != i:
				m.focus, m.moved = to, true
				if mode == .Automatic {
					selected^ = to
				}
			case e.key == .Enter || e.key == .Space:
				fired = true
				selected^, m.focus = i, i
			}
		case .Focus:
			if mode == .Automatic {
				selected^ = i
			}
		}
	}
	return
}

// underline_step is the tab key moves focus to from at of n: Right and
// Left wrap, Home and End go to the ends (useTabList.ts:19-72); -1 for
// any other key.
@(private)
underline_step :: proc(key: ui.Key, at, n: int) -> int {
	#partial switch key {
	case .Right:
		return (at + 1) % n
	case .Left:
		return (at + n - 1) % n
	case .Home:
		return 0
	case .End:
		return n - 1
	}
	return -1
}

// --- Breadcrumbs ---------------------------------------------------------

// Breadcrumb is one crumb; selected marks the current page.
Breadcrumb :: struct {
	label:    string,
	selected: bool,
}

// Breadcrumbs_Overflow is what a trail too long for its row does: wrap
// onto more lines, fold its leading crumbs into a menu, or fold the
// crumbs after the root, which stays.
Breadcrumbs_Overflow :: enum u8 {
	Wrap,
	Menu,
	Menu_With_Root,
}

// Breadcrumbs_Variant is a crumb's look: link-coloured text, or
// default-coloured padded boxes that fill on hover.
Breadcrumbs_Variant :: enum u8 {
	Normal,
	Spacious,
}

// CRUMB_RULE is the wrap separator's em geometry at the medium body size:
// a 0.1em rule 0.8em tall, rotated 15 degrees and nudged 0.0625em down,
// with 0.5em either side (Breadcrumbs.module.css:31-57).
@(private)
CRUMB_RULE :: struct {
	stroke, height, margin, nudge, angle: f32,
} {
	0.1 * tok.TEXT_BODY_SIZE_MEDIUM,
	0.8 * tok.TEXT_BODY_SIZE_MEDIUM,
	0.5 * tok.TEXT_BODY_SIZE_MEDIUM,
	0.0625 * tok.TEXT_BODY_SIZE_MEDIUM,
	15,
}

// CRUMB_GLYPH is the menu modes' 16px slash separator, and
// CRUMB_ALLOWANCE the flat 16px the fold adds per crumb for it
// (Breadcrumbs.tsx:191,364-372).
CRUMB_GLYPH :: tok.BASE_SIZE_16
CRUMB_ALLOWANCE :: tok.BASE_SIZE_16

// CRUMB_NARROW is the width below which the menu mode keeps one crumb
// (Breadcrumbs.tsx:180).
CRUMB_NARROW :: tok.BREAKPOINT_SMALL

// Crumb_Separator is what follows a crumb.
@(private)
Crumb_Separator :: enum u8 {
	None,
	Rule, // the wrap mode's rotated rule
	Glyph, // the menu modes' slash
}

// crumb_style is a crumb's text: medium body, semibold for the current
// spacious crumb (Breadcrumbs.module.css:59-106).
@(private)
crumb_style :: proc(variant: Breadcrumbs_Variant, selected: bool) -> tok.Type_Style {
	st := style(.Body_Medium)
	if variant == .Spacious && selected {
		st.weight = tok.BASE_TEXT_WEIGHT_SEMIBOLD
	}
	return st
}

// crumb_pad is a crumb's padding: none, or 6px inline and 4px block when
// spacious.
@(private)
crumb_pad :: proc(variant: Breadcrumbs_Variant) -> ops.Size {
	return variant == .Spacious ? {tok.BASE_SIZE_6, tok.BASE_SIZE_4} : {}
}

// breadcrumbs_fold is how many crumbs fold into the menu, given each
// crumb's width as the unfolded pass measured it (its separator rule
// included, the last's excluded), the width available and the menu
// button's (Breadcrumbs.tsx:161-219): fold leading crumbs while they need
// more than avail, each with a flat 16px for its separator and the button
// once anything folded, or while more remain than the minimum (3 after
// the root, else 4, or 1 when avail is under 544px and there are more
// than two); when one remains and still does not fit, the root is hidden
// too. With root the root stays first and is never folded.
//
// The web folds the root first in menu-with-root, counting it twice and,
// with exactly one crumb folded, showing an empty menu
// (Breadcrumbs.tsx:179,190-216,310-321); here the root is set aside before folding.
breadcrumbs_fold :: proc(widths: []f32, avail, button: f32, with_root: bool) -> (folded: int, hide_root: bool) {
	hide_root = !with_root
	if len(widths) == 0 || avail <= 0 {
		return
	}
	root := with_root ? widths[0] : 0
	list := with_root ? widths[1:] : widths
	least := with_root ? 3 : 4
	if !with_root && avail < CRUMB_NARROW && len(widths) > 2 {
		least = 1
	}
	need :: proc(list: []f32, root: f32, hide_root: bool) -> (w: f32) {
		for x in list {
			w += x + CRUMB_ALLOWANCE
		}
		return w + (hide_root ? 0 : root)
	}
	total := need(list, root, hide_root)
	for total > avail || len(list) - folded > least {
		if len(list) - folded <= 1 {
			// Only the last crumb is left to show: the root goes into the
			// menu when it still does not fit.
			hide_root = hide_root || total > avail
			break
		}
		folded += 1
		total = need(list[folded:], root, hide_root) + button
		if len(list) - folded == 1 && total > avail {
			hide_root = true
			break
		}
	}
	return
}

// Breadcrumbs_Memo is whether the overflow menu is open.
@(private)
Breadcrumbs_Memo :: struct {
	open: bool,
}

// breadcrumbs is Primer's Breadcrumbs (breadcrumbs.json, Breadcrumbs.tsx,
// Breadcrumbs.module.css): a navigation landmark named "Breadcrumbs"
// holding a trail of links from the root to the current page. Normal
// crumbs are --fgColor-link text that underlines on hover, the current one
// --fgColor-default; spacious crumbs are --fgColor-default boxes padded 6px
// by 4px that fill --control-transparent-bgColor-hover on hover, the
// current one semibold. Keyboard focus outlines a crumb 2px outside. Wrap
// separates crumbs with a rotated --fgColor-muted rule and wraps the
// trail; Menu and Menu_With_Root keep one row, separate crumbs with a
// 16px slash and fold leading crumbs (after the root, for
// Menu_With_Root) into a small invisible kebab IconButton named "<n> more
// breadcrumb items" whose menu lists them (breadcrumbs_fold). It returns
// the crumb activated, in the trail or the menu, or -1.
//
// Departures: the menu lists its crumbs as invisible buttons until
// ActionList lands; it is at most the auto overlay width, not the small
// 320px; crumbs have no hrefs, the activation being the caller's.
breadcrumbs :: proc(
	gtx: ^ui.Ctx,
	items: []Breadcrumb,
	overflow := Breadcrumbs_Overflow.Wrap,
	variant := Breadcrumbs_Variant.Normal,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> (clicked: int) {
	clicked = -1
	id := ui.claim_id(gtx, key, loc)
	if overflow == .Wrap {
		row := ui.wrap_open(gtx, align = .Center, key = u64(ui.id_mix(id, 1)))
		ui.container_semantics(gtx, {role = .Navigation, label = "Breadcrumbs"})
		for it, i in items {
			if crumb(gtx, it, variant, i < len(items) - 1 ? .Rule : .None, crumb_state(state, it, i, items), u64(i + 1)) {
				clicked = i
			}
		}
		ui.close(&row)
		return
	}
	avail := ui.offer(gtx).max.x
	widths := make([]f32, len(items), gtx.allocator)
	for it, i in items {
		widths[i] = crumb_width(gtx, it, variant) + (i < len(items) - 1 ? 2 * CRUMB_RULE.margin + CRUMB_RULE.stroke : 0)
	}
	with_root := overflow == .Menu_With_Root
	folded, hide_root := breadcrumbs_fold(widths, ui.is_finite(avail) ? avail : 0, button_metrics(.Small).height, with_root)
	first := with_root ? 1 : 0 // the first crumb that can fold
	row := ui.row_open(gtx, align = .Center, key = u64(ui.id_mix(id, 1)))
	defer ui.close(&row)
	ui.container_semantics(gtx, {role = .Navigation, label = "Breadcrumbs"})
	if with_root && !hide_root {
		if crumb(gtx, items[0], variant, .Glyph, crumb_state(state, items[0], 0, items), 1) {
			clicked = 0
		}
	}
	if folded > 0 || (with_root && hide_root) {
		lo := with_root && hide_root ? 0 : first
		if at := breadcrumbs_menu(gtx, id, items[lo:first + folded], variant); at >= 0 {
			clicked = lo + at
		}
	}
	for i in first + folded ..< len(items) {
		sep := i < len(items) - 1 ? Crumb_Separator.Glyph : .None
		if crumb(gtx, items[i], variant, sep, crumb_state(state, items[i], i, items), u64(i + 1)) {
			clicked = i
		}
	}
	return
}

// crumb_state is the state crumb i shows: a forced state shows on the
// first crumb that is not the current page.
@(private)
crumb_state :: proc(state: Interaction, it: Breadcrumb, i: int, items: []Breadcrumb) -> Interaction {
	if state == .Live {
		return .Live
	}
	for c, k in items {
		if !c.selected {
			return k == i ? state : .Enabled
		}
	}
	return .Enabled
}

// crumb_width is a crumb's box width without its separator.
@(private)
crumb_width :: proc(gtx: ^ui.Ctx, it: Breadcrumb, variant: Breadcrumbs_Variant) -> f32 {
	st := crumb_style(variant, it.selected)
	return design.shape_style(gtx, it.label, st, font_for(gtx, st.weight)).width + 2 * crumb_pad(variant).x
}

// crumb draws one crumb and the separator after it, and reports its
// activation.
@(private)
crumb :: proc(gtx: ^ui.Ctx, it: Breadcrumb, variant: Breadcrumbs_Variant, sep: Crumb_Separator, state: Interaction, key: u64, loc := #caller_location) -> bool {
	p := ui.widget_open(gtx, key, loc)
	st := crumb_style(variant, it.selected)
	t := design.shape_style(gtx, it.label, st, font_for(gtx, st.weight))
	pad := crumb_pad(variant)
	box := ops.Rect{0, 0, t.width + 2 * pad.x, st.line_height + 2 * pad.y}
	sep_w: f32
	switch sep {
	case .None:
	case .Rule:
		sep_w = 2 * CRUMB_RULE.margin + CRUMB_RULE.stroke
	case .Glyph:
		sep_w = CRUMB_GLYPH
	}
	sz := ops.Size{box.w + sep_w, max(box.h, sep == .Glyph ? CRUMB_GLYPH : 0)}
	box.y = (sz.y - box.h) / 2
	c := control(gtx, p.id, box, state)
	rr := ops.Round_Rect{box, tok.BORDER_RADIUS_MEDIUM}
	fg := color(.Fg_Color_Default)
	underline := false
	switch variant {
	case .Normal:
		if !it.selected {
			fg = color(.Fg_Color_Link)
			underline = c.hovered && !c.focus_visible
		}
	case .Spacious:
		if c.hovered || c.pressed {
			ops.fill(gtx.scene, rr, color(.Control_Transparent_Bg_Color_Hover))
		}
	}
	at := ops.Point{box.x + pad.x, box.y + pad.y + (st.line_height - t.height) / 2}
	draw_text(gtx, t, at, fg)
	if underline {
		paint_underline(gtx, {at.x, at.y + baseline_of(t)}, t.width, fg)
	}
	paint_crumb_separator(gtx, sep, {box.x + box.w, 0, sep_w, sz.y})
	paint_focus_outline(gtx, c, {box, tok.BORDER_RADIUS_SMALL}, LINK_FOCUS_OFFSET)
	listen(gtx, c.st, p.id, box, cursor = .Pointer)
	said := ui.frame_string(gtx, it.label)
	ops.tag(gtx.scene, p.id, said, box)
	ui.semantics(gtx, &p, {role = .Link, label = said, states = design.state_if(it.selected, {.Current_Page})})
	ui.widget_close(gtx, &p, {sz, at.y + baseline_of(t)})
	return c.clicked
}

// paint_crumb_separator draws sep in r, centred down it.
@(private)
paint_crumb_separator :: proc(gtx: ^ui.Ctx, sep: Crumb_Separator, r: ops.Rect) {
	ink := color(.Fg_Color_Muted)
	switch sep {
	case .None:
	case .Rule:
		// A vertical rule, rotated about its centre.
		a := CRUMB_RULE.angle * math.PI / 180
		half := CRUMB_RULE.height / 2
		cx := r.x + r.w / 2
		cy := r.y + r.h / 2 + CRUMB_RULE.nudge
		d := ops.Point{math.sin(a) * half, -math.cos(a) * half}
		ops.stroke(gtx.scene, ui.line(gtx, {cx - d.x, cy - d.y}, {cx + d.x, cy + d.y}), ink, {width = CRUMB_RULE.stroke})
	case .Glyph:
		// The slash's own path (Breadcrumbs.tsx:364-372), in a 16px box.
		o := ops.Point{r.x + (r.w - CRUMB_GLYPH) / 2, r.y + (r.h - CRUMB_GLYPH) / 2}
		pts := make([]ops.Point, 4, gtx.allocator)
		pts[0], pts[1], pts[2], pts[3] = o + {10.956, 1.28}, o + {6.064, 14.72}, o + {5, 14.72}, o + {9.892, 1.28}
		ops.fill(gtx.scene, ui.polygon(gtx, pts), ink)
	}
}

// breadcrumbs_menu is the overflow button, its separator and, while open,
// its menu of folded; it returns the folded crumb chosen, or -1.
@(private)
breadcrumbs_menu :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, folded: []Breadcrumb, variant: Breadcrumbs_Variant) -> (chosen: int) {
	chosen = -1
	m := ui.widget_data(gtx, id, Breadcrumbs_Memo)
	row := ui.row_open(gtx, align = .Center, key = u64(ui.id_mix(id, 2)))
	defer ui.close(&row)
	st := ui.stack_open(gtx, key = u64(ui.id_mix(id, 3)))
	name := fmt.aprintf("%d more breadcrumb items", len(folded), allocator = gtx.allocator)
	if icon_button(gtx, .Kebab_Horizontal, name, .Invisible, .Small, tooltip_direction = .E, key = u64(ui.id_mix(id, 4))) {
		m.open = !m.open
	}
	anchor := ui.last_widget(gtx)
	a := anchored_overlay_open(gtx, &m.open, anchor, focus = {prevent = true}, trap = false, role = .List, name = "Breadcrumbs", key = u64(ui.id_mix(id, 5)))
	if a.visible {
		pad := ui.inset_open(gtx, ui.pad_all(tok.BASE_SIZE_8))
		col := ui.column_open(gtx, align = .Fill)
		for it, i in folded {
			if nav_menu_item(gtx, it.label, it.selected, "", u64(i + 1)) {
				chosen = i
				m.open = false
			}
		}
		ui.close(&col)
		ui.close(&pad)
	}
	anchored_overlay_close(&a)
	ui.close(&st)
	crumb_separator_widget(gtx)
	return
}

// crumb_separator_widget is a 16px slash separator as a widget of its own.
@(private)
crumb_separator_widget :: proc(gtx: ^ui.Ctx, loc := #caller_location) {
	p := ui.widget_open(gtx, 0, loc)
	paint_crumb_separator(gtx, .Glyph, {0, 0, CRUMB_GLYPH, CRUMB_GLYPH})
	ui.widget_close(gtx, &p, {size = {CRUMB_GLYPH, CRUMB_GLYPH}})
}

// nav_menu_item is one entry of a navigation component's overflow menu:
// a link, semibold when current, with an optional trailing counter.
// It stands in for ActionList.LinkItem until the lists family's ActionList
// lands.
@(private)
nav_menu_item :: proc(gtx: ^ui.Ctx, label: string, current: bool, counter: string, key: u64) -> bool {
	return button(gtx, label, .Invisible, count = counter, block = true, align = .Start, key = key)
}

// --- UnderlineNav --------------------------------------------------------

// Underline_Nav_Variant is the row's sides: inset pads them 16px, flush
// starts the first item at the edge.
Underline_Nav_Variant :: enum u8 {
	Inset,
	Flush,
}

// Hide_Icons is the component width below which UnderlineNav hides its
// row's icons (UnderlineNav.module.css:24-70); Never always shows them.
Hide_Icons :: enum u8 {
	Never,
	XSmall,
	Small,
	Medium,
	Large,
	XLarge,
	XXLarge,
}

// HIDE_ICONS_BELOW is each breakpoint in px: 20, 34, 48, 63.25, 80 and
// 87.5rem.
HIDE_ICONS_BELOW := [Hide_Icons]f32 {
	.Never   = 0,
	.XSmall  = 320,
	.Small   = 544,
	.Medium  = 768,
	.Large   = 1012,
	.XLarge  = 1280,
	.XXLarge = 1400,
}

// UNDERLINE_MORE_RULE is the More container's divider: 1px wide, 24px
// tall, 4px either side (UnderlineNav.module.css:78-81,100-106).
UNDERLINE_MORE_RULE :: ops.Size{tok.BORDER_WIDTH_THIN, tok.BASE_SIZE_24}

// Underline_Nav_Memo is whether the More menu is open.
@(private)
Underline_Nav_Memo :: struct {
	open: bool,
}

// underline_nav is Primer's UnderlineNav (underline-nav.json,
// UnderlineNav.tsx, UnderlineTabbedInterface.module.css): a navigation
// landmark named label holding a row of links, items[current] marked
// with a 2px --underlineNav-borderColor-active underline on the row's
// bottom edge. The row is 48px: 8px above 32px items with 8px under them,
// a 1px --borderColor-muted line along its bottom, padded 16px at the
// sides unless flush. Items are UnderlinePanels' tabs (see
// underline_panels_open), each its own tab stop; their icons hide while
// the width offered is under hide_icons' breakpoint.
//
// Items that do not fit on the first line move, in order, into a More
// menu at the end, after a 1px --borderColor-muted divider 24px tall:
// the items are laid out without More and, if any breaks, again with it
// reserved (ui.flex_fit), so the visible items are always a leading run,
// possibly none. The More button is an invisible Button reading "More"
// ("More items", or "More items, including current item" when the
// current item moved), carrying the current item's underline when it
// holds it. It returns the item activated, in the row
// or the menu, or -1.
//
// Departures: the More button's label is Button's medium weight, not
// normal, nor semibold when it holds the current item
// (UnderlineNav.module.css:108-123); its menu lists the items as invisible buttons, the current one
// semibold without its left bar, until ActionMenu lands; an item counts
// as overflowed when it does not fit whole, where the web allows 5% of it
// to be clipped (OverflowObserverProvider.tsx:43-53,114-121); items have no hrefs, the activation being the caller's.
underline_nav :: proc(
	gtx: ^ui.Ctx,
	label: string,
	items: []Underline_Tab,
	current := -1,
	variant := Underline_Nav_Variant.Inset,
	hide_icons := Hide_Icons.Medium,
	loading_counters := false,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> (clicked: int) {
	clicked = -1
	id := ui.claim_id(gtx, key, loc)
	offer := ui.offer(gtx).max.x
	w := ui.is_finite(offer) ? offer : 0
	side := variant == .Inset ? tok.STACK_PADDING_NORMAL : 0
	icons := w >= HIDE_ICONS_BELOW[hide_icons]
	box := ui.sized_open(gtx, {min = {w, UNDERLINE_STRIP}, max = {w, UNDERLINE_STRIP}}, key = u64(ui.id_mix(id, 1)))
	defer ui.close(&box)
	paint_underline_strip(gtx, w)
	ui.container_semantics(gtx, {role = .Navigation, label = ui.frame_string(gtx, label)})
	pad := ui.inset_open(gtx, {side, tok.BASE_SIZE_8, side, 0}, key = u64(ui.id_mix(id, 2)))
	defer ui.close(&pad)
	outer := ui.row_open(gtx, align = .Start, key = u64(ui.id_mix(id, 3)))
	defer ui.close(&outer)
	list := ui.overflow_row_open(gtx, tok.STACK_GAP_CONDENSED, key = u64(ui.id_mix(id, 4)))
	ui.container_semantics(gtx, {role = .List}, list.index)
	forced := false
	for t, i in items {
		tab := t
		if !icons {
			tab.icon = .None
		}
		ts := Interaction.Live if state == .Live else .Enabled
		if state != .Live && !forced && i != current {
			ts, forced = state, true
		}
		if underline_nav_item(gtx, tab, i == current, loading_counters, ts, u64(i + 1)) {
			clicked = i
		}
	}
	more := more_button_width(gtx)
	// The More container sits right after the list, no gap between: take
	// the gap flex_fit leaves before what it reserves back out.
	dropped := ui.flex_fit(&list, 2 * tok.BASE_SIZE_4 + UNDERLINE_MORE_RULE.x + more - tok.STACK_GAP_CONDENSED)
	ui.close(&list)
	m := ui.widget_data(gtx, id, Underline_Nav_Memo)
	if dropped == 0 {
		m.open = false
		return
	}
	first := len(items) - dropped
	if at := underline_more(gtx, id, m, items[first:], current - first, loading_counters); at >= 0 {
		clicked = first + at
	}
	return
}

// more_button_width is the More button's width: an invisible medium
// Button of "More" and its trailing triangle.
@(private)
more_button_width :: proc(gtx: ^ui.Ctx) -> f32 {
	mt := button_metrics(.Medium)
	t := design.shape_style(gtx, "More", mt.style, font_for(gtx, mt.style.weight))
	return 2 * mt.pad + t.width + mt.gap + BUTTON_ICON - tok.BASE_SIZE_4
}

// underline_nav_item is one item: a 32px tab with 8px below it, its own
// tab stop and link.
@(private)
underline_nav_item :: proc(gtx: ^ui.Ctx, t: Underline_Tab, current, loading: bool, state: Interaction, key: u64, loc := #caller_location) -> bool {
	p := ui.widget_open(gtx, key, loc)
	s := measure_underline_tab(gtx, t, loading)
	r := ops.Rect{0, 0, s.w, UNDERLINE_TAB}
	c := control(gtx, p.id, r, state)
	paint_underline_tab(gtx, c, t, s, r, current, loading)
	listen(gtx, c.st, p.id, r, cursor = .Pointer)
	said := ui.frame_string(gtx, t.label)
	ops.tag(gtx.scene, p.id, said, r)
	ui.semantics(gtx, &p, {role = .Link, label = said, description = ui.frame_string(gtx, t.counter), states = design.state_if(current, {.Current_Page})})
	ui.widget_close(gtx, &p, {{s.w, UNDERLINE_TAB + tok.BASE_SIZE_8}, 0})
	return c.clicked
}

// underline_more is the More container and its menu of moved items; at is
// the current item among them, if any. It returns the item chosen, or -1.
@(private)
underline_more :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, m: ^Underline_Nav_Memo, moved: []Underline_Tab, at: int, loading: bool) -> (chosen: int) {
	chosen = -1
	holds := at >= 0 && at < len(moved)
	row := ui.row_open(gtx, align = .Center, key = u64(ui.id_mix(id, 5)))
	defer ui.close(&row)
	{
		p := ui.widget_open(gtx, u64(ui.id_mix(id, 6)))
		rule := ops.Rect{tok.BASE_SIZE_4, 0, UNDERLINE_MORE_RULE.x, UNDERLINE_MORE_RULE.y}
		ops.fill(gtx.scene, rule, color(.Border_Color_Muted))
		ui.widget_close(gtx, &p, {size = {2 * tok.BASE_SIZE_4 + UNDERLINE_MORE_RULE.x, UNDERLINE_MORE_RULE.y}})
	}
	st := ui.stack_open(gtx, key = u64(ui.id_mix(id, 7)))
	defer ui.close(&st)
	name := holds ? "More items, including current item" : "More items"
	if button(gtx, "More", .Invisible, action = .Triangle_Down, name = name, key = u64(ui.id_mix(id, 8))) {
		m.open = !m.open
	}
	anchor := ui.last_widget(gtx)
	if holds {
		// The underline the current item would carry, its bottom 9px
		// below the button's (8px and its 1px border), clipped, as the
		// row clips at 48px (UnderlineNav.module.css:117-139).
		y := anchor.size.y + tok.BASE_SIZE_8 + tok.BORDER_WIDTH_THIN - tok.BORDER_WIDTH_THICK
		bottom := UNDERLINE_STRIP - tok.BASE_SIZE_8
		ops.fill(gtx.scene, ops.Rect{0, y, anchor.size.x, max(min(tok.BORDER_WIDTH_THICK, bottom - y), 0)}, color(.Underline_Nav_Border_Color_Active))
	}
	a := anchored_overlay_open(gtx, &m.open, anchor, align = .End, role = .Menu, name = "More items", key = u64(ui.id_mix(id, 9)))
	if a.visible {
		pad := ui.inset_open(gtx, ui.pad_all(tok.BASE_SIZE_8))
		col := ui.column_open(gtx, align = .Fill)
		for t, i in moved {
			if nav_menu_item(gtx, t.label, i == at, loading ? "" : t.counter, u64(i + 1)) {
				chosen = i
				m.open = false
			}
		}
		ui.close(&col)
		ui.close(&pad)
	}
	anchored_overlay_close(&a)
	return
}

// --- NavList -------------------------------------------------------------

// Nav_Item is one NavList item: a link, or with children a disclosure
// button over a sub-navigation (at most four levels deep). current marks
// the page shown; inactive_text makes the item muted and inert and says
// why.
Nav_Item :: struct {
	label:             string,
	current:           bool,
	leading:           Icon,
	trailing:          Icon,
	trailing_text:     string, // a count, in place of a trailing icon
	description:       string,
	block_description: bool, // under the label, the label semibold; else inline after it
	inactive_text:     string,
	children:          []Nav_Item,
	default_open:      bool,
}

// Nav_Group is a run of NavList items: under a heading when title is set,
// after a divider unless hide_divider, with more revealed by a "Show more"
// row in more_pages steps (0: all at once).
Nav_Group :: struct {
	title:        string,
	items:        []Nav_Item,
	hide_divider: bool,
	filled:       bool, // the heading on a --bgColor-muted band
	more:         []Nav_Item,
	more_label:   string, // "Show more" when empty
	more_pages:   int,
}

// NAV_ROW_LINE is a label's and visual's hard-coded 20px line, so a one-
// line row is 32px; NAV_DESCRIPTION_LINE a description's 16px line; and
// NAV_GROUP_LINE a group heading's 18px (ActionList.module.css:513,682,
// 693,707; Group.module.css:20).
NAV_ROW_LINE :: tok.BASE_SIZE_20
NAV_DESCRIPTION_LINE :: tok.BASE_SIZE_16
NAV_GROUP_LINE :: f32(18)

// NAV_INDENT is a sub-item's indent per level, and NAV_MAX_DEPTH the
// deepest sub-navigation drawn (ActionList.module.css:614; NavList.tsx
// :309-314).
NAV_INDENT :: tok.BASE_SIZE_8
NAV_MAX_DEPTH :: 4

// NAV_FADE is a row's 33.333ms linear background transition
// (ActionList.module.css:513).
NAV_FADE :: tok.Transition{33.333, {0, 0, 1, 1}}

// Nav_Item_Memo is whether a parent is open, and whether its sub-tree held
// the current item last frame.
@(private)
Nav_Item_Memo :: struct {
	open, seeded, held: bool,
}

// Nav_Group_Memo is how many times a group's Show more was pressed.
@(private)
Nav_Group_Memo :: struct {
	pressed: int,
	focus:   int, // the revealed item to focus once drawn, -1 for none
}

// nav_holds_current reports whether items, at any depth, hold the current
// item (NavList.tsx:221-265).
@(private)
nav_holds_current :: proc(items: []Nav_Item) -> bool {
	for it in items {
		if it.current || nav_holds_current(it.children) {
			return true
		}
	}
	return false
}

// Nav_List_Ctx is what every row of one NavList shares.
@(private)
Nav_List_Ctx :: struct {
	root:    ops.Area_Id,
	chosen:  ^Nav_Item,
	w:       f32,
	focus_next: bool, // focus the next row drawn: an item Show more revealed
}

// nav_list is Primer's NavList (nav-list.json, NavList.tsx, ActionList's
// inset list): a navigation landmark named by label, else title (a small
// heading at heading_level, 16px in, 8px above the list), holding
// groups of 32px rows inset 8px from each side. A row is rounded, padded
// 6px by 8px: a 16px --fgColor-muted leading visual and 8px, the label in
// medium body text on a 20px line (sub-items small), wrapping, an inline
// or block description in small muted text, and a trailing icon or count.
// Hover fills --control-transparent-bgColor-hover with a 1px inset
// --control-transparent-borderColor-active ring, a press
// --control-transparent-bgColor-active; keyboard focus outlines the row
// 2px. The current item fills --control-transparent-bgColor-selected, its
// label semibold in --control-fgColor-rest, with a 4px
// --borderColor-accent-emphasis line 8px to its left (activeIndicatorLine
// .css). An item with children is a button toggling them, with a
// chevron; it opens on default_open or when it holds the current item,
// and while closed holding it, takes the current treatment itself.
// Sub-items indent 8px a level. A group draws a 1px --borderColor-muted
// divider before itself (7px above, 8px below) unless it is first or
// hide_divider, then its title in small semibold muted text (a heading a
// level below the NavList's, at most h4), its items, and a Show more row
// for its more items. It returns the leaf item activated, or nil.
//
// Departures: rows are drawn here until the lists family's ActionList
// lands, which NavList is built on; trailing actions and tooltips are not
// offered; the 2px item gap behind a feature flag is not drawn; an
// inactive item is not focusable, as jm:ui has no focusable disabled
// state; Show more reports itself collapsed only until it is pressed
// (the web says false always, nav-list.json upstream bug).
nav_list :: proc(
	gtx: ^ui.Ctx,
	groups: []Nav_Group,
	title := "",
	heading_level := 2,
	label := "",
	key: u64 = 0,
	loc := #caller_location,
) -> ^Nav_Item {
	id := ui.claim_id(gtx, key, loc)
	nc := Nav_List_Ctx{root = id}
	col := ui.column_open(gtx, align = .Fill, key = u64(ui.id_mix(id, 1)))
	defer ui.close(&col)
	name := label != "" ? label : title
	ui.container_semantics(gtx, {role = .Navigation, label = ui.frame_string(gtx, name)})
	nc.w = gtx.constraints.max.x
	if !ui.is_finite(nc.w) {
		nc.w = 240
	}
	if title != "" {
		pad := ui.inset_open(gtx, {tok.CONTROL_MEDIUM_PADDING_INLINE_CONDENSED + tok.BASE_SIZE_8, 0, 0, tok.BASE_SIZE_8}, key = u64(ui.id_mix(id, 2)))
		heading(gtx, title, clamp(heading_level, 1, 6), .Small, key = u64(ui.id_mix(id, 3)))
		ui.close(&pad)
	}
	list := ui.inset_open(gtx, {0, tok.BASE_SIZE_8, 0, tok.BASE_SIZE_8}, key = u64(ui.id_mix(id, 4)))
	defer ui.close(&list)
	rows := ui.column_open(gtx, align = .Fill, key = u64(ui.id_mix(id, 5)))
	defer ui.close(&rows)
	ui.container_semantics(gtx, {role = .List})
	group_level := u8(clamp(title != "" ? heading_level + 1 : 3, 1, 4))
	for &g, gi in groups {
		sc := ui.scope_open(gtx, gi + 1)
		nav_group(gtx, &nc, &g, gi, group_level)
		ui.scope_close(&sc)
	}
	return nc.chosen
}

// nav_group draws group g, the gi-th.
@(private)
nav_group :: proc(gtx: ^ui.Ctx, nc: ^Nav_List_Ctx, g: ^Nav_Group, gi: int, level: u8) {
	if gi > 0 && !g.hide_divider {
		p := ui.widget_open(gtx, 1)
		ops.fill(gtx.scene, ops.Rect{0, tok.BASE_SIZE_8 - tok.BORDER_WIDTH_THIN, nc.w, tok.BORDER_WIDTH_THIN}, color(.Border_Color_Muted))
		ui.semantics(gtx, &p, {role = .Separator})
		ui.widget_close(gtx, &p, {size = {nc.w, 2 * tok.BASE_SIZE_8}})
	} else if gi > 0 {
		ui.spacer(gtx, tok.BASE_SIZE_8)
	}
	if g.title != "" {
		nav_group_title(gtx, g, gi, nc.w, level)
	}
	for &it, i in g.items {
		nav_item(gtx, nc, &it, 0, u64(i + 1), tree_key(g.title))
	}
	if len(g.more) > 0 {
		nav_more(gtx, nc, g, gi)
	}
}

// nav_group_title is a group's heading: small semibold muted text on an
// 18px line, padded 6px by 16px, on a muted band between rules when
// filled (Group.module.css:13-51).
@(private)
nav_group_title :: proc(gtx: ^ui.Ctx, g: ^Nav_Group, gi: int, w: f32, level: u8) {
	p := ui.widget_open(gtx, 2)
	st := tok.Type_Style{weight = tok.BASE_TEXT_WEIGHT_SEMIBOLD, size = tok.TEXT_BODY_SIZE_SMALL, line_height = NAV_GROUP_LINE}
	para := design.layout_style(gtx, g.title, st, font_for(gtx, st.weight), max(w - 2 * tok.BASE_SIZE_16, 1))
	h := para.height + 2 * tok.BASE_SIZE_6
	y: f32
	if g.filled {
		// 7px above (none when first), the band and its rules, 8px below.
		if gi > 0 {
			y = tok.BASE_SIZE_8 - tok.BORDER_WIDTH_THIN
		}
		b := tok.BORDER_WIDTH_THIN
		ops.fill(gtx.scene, ops.Rect{0, y, w, h + 2 * b}, color(.Bg_Color_Muted))
		ops.fill(gtx.scene, ops.Rect{0, y, w, b}, color(.Border_Color_Muted))
		ops.fill(gtx.scene, ops.Rect{0, y + h + b, w, b}, color(.Border_Color_Muted))
		y += b
	}
	design.draw_paragraph(gtx, para, {tok.BASE_SIZE_16, y + tok.BASE_SIZE_6}, color(.Fg_Color_Muted))
	total := y + h + (g.filled ? tok.BORDER_WIDTH_THIN + tok.BASE_SIZE_8 : 0)
	said := ui.frame_string(gtx, g.title)
	ops.tag(gtx.scene, p.id, said, {0, y, w, h})
	ui.semantics(gtx, &p, {role = .Heading, label = said, level = level})
	ui.widget_close(gtx, &p, {size = {w, total}})
}

// nav_item draws it at depth and, while open, its children; path names
// its parents, so its open state follows its place in the list.
@(private)
nav_item :: proc(gtx: ^ui.Ctx, nc: ^Nav_List_Ctx, it: ^Nav_Item, depth: int, key, path: u64) {
	if depth >= NAV_MAX_DEPTH {
		return
	}
	sc := ui.scope_open(gtx, key)
	defer ui.scope_close(&sc)
	parent := len(it.children) > 0
	here := u64(ui.id_mix(ops.Area_Id(path), tree_key(it.label)))
	m := ui.widget_data(gtx, ui.id_mix(nc.root, here), Nav_Item_Memo)
	holds := parent && nav_holds_current(it.children)
	if parent && (!m.seeded || holds && !m.held) {
		m.open = m.open || it.default_open || holds
		m.seeded = true
	}
	m.held = holds
	look := Nav_Row{it = it, depth = depth, parent = parent, open = parent && m.open}
	look.current = it.current || (parent && !m.open && holds)
	if nav_row(gtx, nc, look) {
		switch {
		case parent:
			m.open = !m.open
		case:
			nc.chosen = it
		}
	}
	if parent && m.open {
		for &c, i in it.children {
			nav_item(gtx, nc, &c, depth + 1, u64(i + 1), here)
		}
	}
}

// nav_more is a group's Show more row and the items it has revealed:
// pages 0 reveals all at the first press; with N pages each press
// reveals ceil(count / N x presses), the row going after the Nth; focus
// moves to the first item revealed (NavList.tsx:448-528).
@(private)
nav_more :: proc(gtx: ^ui.Ctx, nc: ^Nav_List_Ctx, g: ^Nav_Group, gi: int) {
	gm := ui.widget_data(gtx, ui.id_mix(nc.root, u64(7000 + gi)), Nav_Group_Memo)
	n := len(g.more)
	shown := nav_more_shown(n, g.more_pages, gm.pressed)
	for &it, i in g.more[:shown] {
		if gm.pressed > 0 && i == gm.focus {
			nc.focus_next = true
			gm.focus = -1
		}
		nav_item(gtx, nc, &it, 0, u64(1000 + i), tree_key(g.title))
	}
	if gm.pressed > 0 && (g.more_pages == 0 || gm.pressed >= g.more_pages) {
		return
	}
	label := g.more_label != "" ? g.more_label : "Show more"
	more := Nav_Item{label = label, trailing = .Plus}
	if nav_row(gtx, nc, {it = &more, more = true}) {
		gm.pressed += 1
		gm.focus = 0
		if gm.pressed > 1 {
			gm.focus = nav_more_shown(n, g.more_pages, gm.pressed) - n / g.more_pages
		}
	}
}

// nav_more_shown is how many of n hidden items show after pressed presses
// of Show more in pages steps: all once pressed with pages 0, else
// ceil(n / pages x pressed) (NavList.tsx:453-455).
@(private)
nav_more_shown :: proc(n, pages, pressed: int) -> int {
	if pressed <= 0 {
		return 0
	}
	if pages <= 0 {
		return n
	}
	return min(int(math.ceil(f32(n) / f32(pages) * f32(pressed))), n)
}

// Nav_Row is how one row draws.
@(private)
Nav_Row :: struct {
	it:                    ^Nav_Item,
	depth:                 int,
	parent, open, current: bool,
	more:                  bool, // the Show more row: a button
}

// nav_row draws a row and reports its activation.
@(private)
nav_row :: proc(gtx: ^ui.Ctx, nc: ^Nav_List_Ctx, r: Nav_Row, loc := #caller_location) -> bool {
	it := r.it
	p := ui.widget_open(gtx, 0, loc)
	inactive := it.inactive_text != ""
	// Every row sits 8px in: a sub-item has no margin of its own, but its
	// list lies inside its top-level ancestor's.
	margin := tok.BASE_SIZE_8
	w := nc.w - 2 * tok.BASE_SIZE_8
	box := ops.Rect{0, 0, w, 0}
	x := tok.CONTROL_MEDIUM_PADDING_INLINE_CONDENSED + f32(r.depth) * NAV_INDENT
	if r.depth > 0 {
		x += tok.CONTROL_MEDIUM_GAP
	}
	label_x := x + (it.leading != .None ? BUTTON_ICON + tok.CONTROL_MEDIUM_GAP : 0)
	trail := it.trailing
	if r.parent {
		trail = r.open ? .Chevron_Up : .Chevron_Down
	}
	trail_text := design.shape_style(gtx, it.trailing_text, style(.Body_Small), font_for(gtx, tok.BASE_TEXT_WEIGHT_NORMAL))
	trail_w: f32
	switch {
	case trail != .None:
		trail_w = BUTTON_ICON
	case it.trailing_text != "":
		trail_w = trail_text.width
	}
	right := w - tok.CONTROL_MEDIUM_PADDING_INLINE_CONDENSED - (trail_w > 0 ? trail_w + tok.CONTROL_MEDIUM_GAP : 0)
	semibold := r.current || it.description != "" && it.block_description
	size := r.depth > 0 ? tok.TEXT_BODY_SIZE_SMALL : tok.TEXT_BODY_SIZE_MEDIUM
	st := tok.Type_Style{weight = semibold ? tok.BASE_TEXT_WEIGHT_SEMIBOLD : tok.BASE_TEXT_WEIGHT_NORMAL, size = size, line_height = NAV_ROW_LINE}
	label := design.layout_style(gtx, it.label, st, font_for(gtx, st.weight), max(right - label_x, 1))
	dst := tok.Type_Style{weight = tok.BASE_TEXT_WEIGHT_NORMAL, size = tok.TEXT_BODY_SIZE_SMALL, line_height = NAV_DESCRIPTION_LINE}
	under := it.inactive_text if inactive else (it.block_description ? it.description : "")
	sub := design.layout_style(gtx, under, dst, font_for(gtx, dst.weight), max(right - label_x, 1))
	content := label.height
	if under != "" {
		content += tok.BASE_SIZE_4 + sub.height
	}
	box.h = 2 * tok.CONTROL_MEDIUM_PADDING_BLOCK + max(content, NAV_ROW_LINE)
	box.x = margin
	c := control(gtx, p.id, box, inactive ? .Disabled : .Live)
	if nc.focus_next && !r.more {
		ui.focus_request(gtx, p.id)
		nc.focus_next = false
	}
	paint_nav_row(gtx, c, r, box)
	ink := color(inactive ? .Fg_Color_Muted : (r.current ? .Control_Fg_Color_Rest : .Fg_Color_Default))
	muted := color(.Fg_Color_Muted)
	top := box.y + tok.CONTROL_MEDIUM_PADDING_BLOCK
	if it.leading != .None {
		icon(gtx, it.leading, {box.x + x, top + (NAV_ROW_LINE - BUTTON_ICON) / 2}, BUTTON_ICON, muted)
	}
	design.draw_paragraph(gtx, label, {box.x + label_x, top}, ink)
	if it.description != "" && !it.block_description && !inactive && len(label.lines) > 0 {
		// Inline: 8px after the label, on its last line's baseline.
		last := label.lines[len(label.lines) - 1]
		d := design.shape_style(gtx, it.description, dst, font_for(gtx, dst.weight))
		dx := box.x + label_x + last.width + tok.BASE_SIZE_8
		draw_text(gtx, d, {dx, top + last.baseline - baseline_of(d)}, muted)
	}
	if under != "" {
		design.draw_paragraph(gtx, sub, {box.x + label_x, top + label.height + tok.BASE_SIZE_4}, muted)
	}
	switch {
	case trail != .None:
		icon(gtx, trail, {box.x + w - tok.CONTROL_MEDIUM_PADDING_INLINE_CONDENSED - BUTTON_ICON, top + (NAV_ROW_LINE - BUTTON_ICON) / 2}, BUTTON_ICON, muted)
	case it.trailing_text != "":
		draw_text(gtx, trail_text, {box.x + w - tok.CONTROL_MEDIUM_PADDING_INLINE_CONDENSED - trail_text.width, top + (NAV_ROW_LINE - trail_text.height) / 2}, muted)
	}
	listen(gtx, c.st, p.id, box, cursor = .Pointer)
	said := ui.frame_string(gtx, it.label)
	ops.tag(gtx.scene, p.id, said, box)
	states: ops.States
	role := ops.Role.Link
	if r.parent || r.more {
		role = .Button
		states += {.Expandable}
		if r.open {
			states += {.Expanded}
		}
	}
	if it.current {
		states += {.Current_Page}
	}
	if inactive {
		states += {.Disabled}
	}
	desc := it.description if !inactive else it.inactive_text
	ui.semantics(gtx, &p, {role = role, label = said, value = ui.frame_string(gtx, it.trailing_text), description = ui.frame_string(gtx, desc), states = states})
	ui.widget_close(gtx, &p, {{nc.w, box.h}, 0})
	return c.clicked && !inactive
}

// paint_nav_row draws a row's fill, ring, current line and focus outline
// (ActionList.module.css:111-245; activeIndicatorLine.css).
@(private)
paint_nav_row :: proc(gtx: ^ui.Ctx, c: Control, r: Nav_Row, box: ops.Rect) {
	rr := ops.Round_Rect{box, tok.BORDER_RADIUS_MEDIUM}
	inert := c.disabled
	fill := tok.Role.Control_Transparent_Bg_Color_Rest
	ring := false
	switch {
	case inert:
	case c.pressed:
		fill, ring = .Control_Transparent_Bg_Color_Active, !r.current
	case c.hovered:
		fill, ring = .Control_Transparent_Bg_Color_Hover, !r.current && !c.focus_visible
	case r.current:
		fill = .Control_Transparent_Bg_Color_Selected
	}
	bg := design.blend(gtx, c.fades, 0, color(fill), NAV_FADE.duration, NAV_FADE.easing)
	if ui.painted(bg) {
		ops.fill(gtx.scene, rr, bg)
	}
	if ring {
		design.paint_inset_shadow(gtx, rr, {spread = tok.BORDER_WIDTH_THIN, color = color(.Control_Transparent_Border_Color_Active)})
	}
	if r.current {
		line := ops.Rect{box.x - tok.BASE_SIZE_8, box.y + tok.BASE_SIZE_4, tok.BASE_SIZE_4, box.h - tok.BASE_SIZE_8}
		ops.fill(gtx.scene, ops.Round_Rect{line, radius(tok.BORDER_RADIUS_MEDIUM, line)}, color(.Border_Color_Accent_Emphasis))
	}
	paint_focus_outline(gtx, c, rr, 0)
}
