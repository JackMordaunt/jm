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
	if c.focus_visible {
		design.paint_focus_ring(gtx, c.base, rr, {tok.BASE_SIZE_2, -tok.BASE_SIZE_2, color(.Bg_Color_Accent_Emphasis)})
	}
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
		if c.focus_visible {
			design.paint_focus_ring(gtx, c.base, {r, max(left, right)}, focus_outline())
		}
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
// Departures: the focused tab is not scrolled into view, as jm:ui has no
// scroll-into-view; tabs and panels pair by index, not by value. Icons
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
		m.moved = false
		ui.focus_request(gtx, ui.id_mix(p.id, u64(m.focus) + 1))
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
