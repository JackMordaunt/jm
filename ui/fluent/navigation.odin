package fluent

import "base:runtime"
import "core:math"
import "core:strings"
import "jm:ui"
import "jm:ui/design"
import tok "jm:ui/fluent/tokens"
import "jm:ui/ops"

// Navigation and layout: the nav drawer, the drawer, the breadcrumb and
// the tree, on the fluent-kit's nav.json, drawer.json, breadcrumb.json
// and tree.json and the styles files they cite at the kit's commit
// (source/COMMIT). Every colour is a token per state; every number the
// styles file hard-codes is cited as file:lines where it is used.
//
// Departures shared by the group: jm:ui has no group opacity, so the
// fades that ride with the slide and collapse motions (a drawer's
// surface, a nav category's sub-item group, a tree's subtree) are
// skipped and only the geometry moves; and jm:ui moves focus only by
// a press, so the roving arrow-key focus of nav, breadcrumb and tree is
// not built (Up, Down, Left and Right act on the focused row instead).

// --- Drawer -----------------------------------------------------------

// Drawer_Kind is drawer.json's type: floating over the page behind a
// backdrop, or in the flow beside the content.
Drawer_Kind :: enum u8 {
	Overlay,
	Inline,
}

// Drawer_Position is the edge a drawer is anchored to.
Drawer_Position :: enum u8 {
	Start,
	End,
	Bottom,
}

// Drawer_Size is the drawer's width (height at the bottom): 320, 592 or
// 940px, or the whole window (useDrawerBaseStyles.styles.ts:56-96).
Drawer_Size :: enum u8 {
	Small,
	Medium,
	Large,
	Full,
}

@(private)
DRAWER_EXTENT := [Drawer_Size]f32{.Small = 320, .Medium = 592, .Large = 940, .Full = 0}

// drawer_duration is the size's motion duration (drawerMotions.ts:14-19).
@(private)
drawer_duration :: proc(size: Drawer_Size) -> f32 {
	switch size {
	case .Small:
		return tok.DURATION_GENTLE
	case .Medium:
		return tok.DURATION_SLOW
	case .Large:
		return tok.DURATION_SLOWER
	case .Full:
		return tok.DURATION_ULTRA_SLOW
	}
	return tok.DURATION_GENTLE
}

// DRAWER_PAD is the header, body and footer side padding,
// spacingHorizontalXXL; DRAWER_EDGE_EXTRA the 1px a body adds at its
// top or bottom edge (useDrawerBodyStyles.styles.ts:16-31).
@(private)
DRAWER_PAD :: tok.SPACING_HORIZONTAL_XXL
@(private)
DRAWER_EDGE_EXTRA :: f32(1)

// Drawer is an open drawer between drawer_open and drawer_close.
Drawer :: struct {
	visible:  bool,
	kind:     Drawer_Kind,
	overlay:  ui.Overlay,
	box:      ui.Box,
	col:      ui.Flex,
	id:       ops.Area_Id,
	open:     ^bool,
	extent:   f32, // the surface's width (height at the bottom)
	position: Drawer_Position,
	window:   ops.Size,
	fixed:    Fixed_Surface, // an inline drawer's place in the flow
	modal:    bool, // an overlay drawer behind a backdrop: a dialog to a reader
}

@(private)
Drawer_Data :: struct {
	was_open: bool,
	slide:    ui.Tween, // 0 closed, 1 open
	closing:  bool,
}

@(private)
Drawer_Paint :: struct {
	open:      ^bool,
	kind:      Drawer_Kind,
	position:  Drawer_Position,
	separator: bool,
	modal:     bool,
	fill:      ops.Color,
	shade:     f32, // the overlay's motion progress, for its shadow
	fixed:     ops.Area_Id, // an inline drawer's Fixed_Surface, to record its height
}

@(private, thread_local)
current_drawer: ^Drawer

// drawer_open shows a drawer while open^. An overlay drawer floats over
// window (the root constraints) behind a Background_Overlay backdrop,
// pinned to its edge, slides in over its size's duration on
// CURVE_DECELERATE_MID and back out on CURVE_ACCELERATE_MIN, under
// shadow64; a press on the backdrop closes a modal one (not an alert),
// and Escape closes it once the surface has focus. An inline drawer sits
// in the flow, its width (height at the bottom) growing from 0 over the
// same motion, with a 1px Neutral_Background3 separator on the edge that
// meets the content when separator is set. The surface is
// Neutral_Background1 with a strokeWidthThin Transparent_Stroke border
// on its inner side (useDrawerBaseStyles.styles.ts:18-54,
// useOverlayDrawerStyles.styles.ts:20-40, useInlineDrawerStyles.styles.
// ts:14-70). fill overrides the surface colour (the nav drawer's
// Background 4). Lay the body out with drawer_header, drawer_body and
// drawer_footer between open and close, or as the guard's body.
//
// Departures: the surface does not fade with its slide (no group
// alpha); the header and footer scroll lines are not drawn; focus is
// not trapped.
drawer_open :: proc(
	gtx: ^ui.Ctx,
	open: ^bool,
	window: ops.Size,
	kind := Drawer_Kind.Overlay,
	position := Drawer_Position.Start,
	size := Drawer_Size.Small,
	separator := false,
	modal := Dialog_Kind.Modal,
	fill := ops.Color{},
	key: u64 = 0,
	loc := #caller_location,
) -> (d: Drawer) {
	id := ui.claim_id(gtx, key, loc)
	data := ui.widget_data(gtx, id, Drawer_Data)
	dur := drawer_duration(size) / 1000
	if open^ && kind == .Overlay {
		// A backdrop press closes a modal drawer; Escape, sent to the
		// drawer's id by key_interest below, closes any overlay one,
		// focused or not.
		for e in ui.events(gtx, id) {
			if e.kind == .Press && modal == .Modal {
				open^ = false
			}
			if e.kind == .Key && e.key == .Escape {
				open^ = false
			}
		}
	}
	if open^ != data.was_open {
		data.was_open = open^
		data.slide = {from = data.slide.from + (data.slide.to - data.slide.from) * (data.slide.duration > 0 ? data.slide.t / data.slide.duration : 1), to = open^ ? 1 : 0, duration = dur}
		data.closing = !open^
	}
	t := ui.tween_update(&data.slide, gtx)
	if t <= 0 && !open^ {
		return
	}
	prog := data.closing ? 1 - design.bezier_ease(tok.CURVE_ACCELERATE_MIN, 1 - t) : design.bezier_ease(tok.CURVE_DECELERATE_MID, t)

	d.visible = true
	d.kind = kind
	d.id = id
	d.open = open
	d.position = position
	d.window = window
	full := size == .Full
	at_bottom := position == .Bottom
	extent := full ? (at_bottom ? window.y : window.x) : DRAWER_EXTENT[size]
	if at_bottom {
		extent = min(extent, window.y)
	} else {
		extent = min(extent, window.x)
	}
	d.extent = extent
	dp := new(Drawer_Paint, gtx.allocator)
	dp^ = {open = open, kind = kind, position = position, separator = separator, modal = modal != .Non_Modal, fill = ui.or_color(fill, color(.Neutral_Background1)), shade = prog}

	surface: ops.Size
	switch kind {
	case .Overlay:
		// The slide: the surface's edge moves in from off-screen by its
		// extent (drawerMotions.ts:24-46).
		off := extent * (1 - prog)
		at: ops.Point
		switch position {
		case .Start:
			at = {-off, 0}
			surface = {extent, window.y}
		case .End:
			at = {window.x - extent + off, 0}
			surface = {extent, window.y}
		case .Bottom:
			at = {0, window.y - extent + off}
			surface = {window.x, extent}
		}
		d.overlay = ui.overlay_open(gtx, at, cs = ui.exact(surface), root = true)
		if open^ {
			ui.key_interest(gtx, id, .Escape)
		}
		if dp.modal {
			ops.fill(gtx.scene, ops.Rect{-at.x, -at.y, window.x, window.y}, fade(color(.Background_Overlay), prog))
			if open^ {
				ops.input_area(gtx.scene, id, ops.Rect{-at.x, -at.y, window.x, window.y}, {.Press, .Release, .Move, .Enter, .Leave, .Scroll})
			}
		}
	case .Inline:
		// Laid out at its full size in place, the space it takes (and the
		// part shown) growing with the motion.
		cs := gtx.constraints
		if at_bottom {
			d.fixed = fixed_open(gtx, ui.is_finite(cs.max.x) ? cs.max.x : extent, extent, prog, bottom = true, key = u64(ui.id_mix(id, 1)), loc = loc)
		} else {
			d.fixed = fixed_open(gtx, extent, reveal = prog, key = u64(ui.id_mix(id, 1)), loc = loc)
		}
		dp.fixed = d.fixed.p.id
	}
	d.box = ui.box_open(gtx, {paint = paint_drawer, user = dp}, key = 2)
	d.col = ui.column_open(gtx, align = .Fill, key = 3)
	// A modal overlay drawer is a dialog; an inline or non-modal one is
	// a navigation region. drawer_header_title names it.
	d.modal = kind == .Overlay && dp.modal
	ui.container_semantics(gtx, drawer_semantics(d, ""))
	current_drawer = ui.widget_data(gtx, id, Drawer)
	current_drawer^ = d
	return
}

// drawer_close closes a drawer opened by drawer_open.
drawer_close :: proc(d: ^Drawer) {
	if !d.visible {
		return
	}
	ui.close(&d.col)
	ui.close(&d.box)
	if d.kind == .Overlay {
		ui.close(&d.overlay)
	} else {
		fixed_close(d.fixed.overlay.gtx, &d.fixed)
	}
	d.visible = false
	current_drawer = nil
}

// drawer is drawer_open as a guard: `if fluent.drawer(gtx, &open, window)
// { … }` lays the body out while the drawer shows (or slides) and closes
// it at the end of the if.
@(deferred_in = drawer_guard_close)
drawer :: proc(
	gtx: ^ui.Ctx,
	open: ^bool,
	window: ops.Size,
	kind := Drawer_Kind.Overlay,
	position := Drawer_Position.Start,
	size := Drawer_Size.Small,
	separator := false,
	modal := Dialog_Kind.Modal,
	fill := ops.Color{},
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	d := drawer_open(gtx, open, window, kind, position, size, separator, modal, fill, key, loc)
	return d.visible
}

@(private = "file")
drawer_guard_close :: proc(gtx: ^ui.Ctx, open: ^bool, window: ops.Size, kind: Drawer_Kind, position: Drawer_Position, size: Drawer_Size, separator: bool, modal: Dialog_Kind, fill: ops.Color, key: u64, loc: runtime.Source_Code_Location) {
	if current_drawer != nil {
		drawer_close(current_drawer)
	}
}

@(private)
paint_drawer :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, size: ops.Size, user: rawptr) {
	dp := (^Drawer_Paint)(user)
	area := ops.Rect{0, 0, size.x, size.y}
	record_fixed_height(gtx, dp.fixed, size.y)
	for e in ui.events(gtx, id) {
		if e.kind == .Key && e.key == .Escape && dp.kind == .Overlay {
			dp.open^ = false
		}
	}
	if dp.kind == .Overlay {
		// The shadow grows with the motion (drawerMotions.ts:85-116).
		sh := tok.SHADOW64
		for &l in sh.layers {
			design.paint_shadow_layer(gtx, {area, 0}, l.x, l.y, l.blur, fade(color(l.color), dp.shade))
		}
	}
	ops.fill(gtx.scene, area, dp.fill)
	// The border on the side facing the content: transparent at rest,
	// visible under high contrast; an inline separator is Background 3.
	line := color(.Transparent_Stroke)
	if dp.kind == .Inline && dp.separator {
		line = color(.Neutral_Background3)
	}
	w := tok.STROKE_WIDTH_THIN
	switch dp.position {
	case .Start:
		ops.fill(gtx.scene, ops.Rect{size.x - w, 0, w, size.y}, line)
	case .End:
		ops.fill(gtx.scene, ops.Rect{0, 0, w, size.y}, line)
	case .Bottom:
		if dp.kind == .Inline && dp.separator {
			ops.fill(gtx.scene, ops.Rect{0, 0, size.x, w}, line)
		}
	}
	if dp.kind == .Overlay {
		// The surface swallows its own presses and takes focus, so Escape
		// reaches it.
		ops.input_area(gtx.scene, id, area, {.Press, .Release, .Move, .Enter, .Leave, .Scroll, .Key})
	}
}

// drawer_semantics is what d's column says: a modal dialog, or a
// navigation region, named label.
@(private)
drawer_semantics :: proc(d: Drawer, label: string) -> ops.Semantics {
	if d.modal {
		return {role = .Dialog, label = label, states = {.Modal}}
	}
	return {role = .Navigation, label = label}
}

// drawer_header_open is the header: a column padded spacingVerticalXXL
// above, spacingHorizontalXXL at the sides and spacingVerticalS below,
// spacingHorizontalS between its rows (useDrawerHeaderStyles.styles.ts:
// 18-29). Put drawer_header_title in it.
drawer_header_open :: proc(gtx: ^ui.Ctx, key: u64 = 0, loc := #caller_location) -> Drawer_Part {
	part: Drawer_Part
	part.inset = ui.inset_open(gtx, {DRAWER_PAD, tok.SPACING_VERTICAL_XXL, DRAWER_PAD, tok.SPACING_VERTICAL_S}, key, loc)
	part.col = ui.column_open(gtx, gap = tok.SPACING_HORIZONTAL_S, align = .Fill)
	return part
}

// Drawer_Part is an open header, body or footer.
Drawer_Part :: struct {
	inset:  ui.Inset,
	col:    ui.Flex,
	scroll: ui.Scroll_Box,
	body:   bool,
}

drawer_part_close :: proc(part: ^Drawer_Part) {
	ui.close(&part.col)
	if part.body {
		ui.close(&part.scroll)
	}
	ui.close(&part.inset)
}

// drawer_header is drawer_header_open as a guard.
@(deferred_in = drawer_part_guard_close)
drawer_header :: proc(gtx: ^ui.Ctx, key: u64 = 0, loc := #caller_location) -> bool {
	part := ui.guard_hold(gtx, Drawer_Part)
	part^ = drawer_header_open(gtx, key, loc)
	return true
}

@(private = "file")
drawer_part_guard_close :: proc(gtx: ^ui.Ctx, key: u64, loc: runtime.Source_Code_Location) {
	drawer_part_close(ui.guard_take(gtx, Drawer_Part))
}

// drawer_header_title is the title row: subtitle1 text in
// Neutral_Foreground1 and, with close non-nil, a subtle Dismiss button
// at the end that clears close^, pulled spacingHorizontalS into the
// padding so its edge meets the header's (useDrawerHeaderTitleStyles.
// styles.ts:19-56).
drawer_header_title :: proc(gtx: ^ui.Ctx, text: string, close: ^bool = nil, key: u64 = 0, loc := #caller_location) {
	if d := current_drawer; d != nil {
		// The title names the drawer's column, two containers up, by
		// its handle.
		ui.container_semantics(gtx, drawer_semantics(d^, text), d.col.index)
	}
	r := ui.row_open(gtx, align = .Center, key = key, loc = loc)
	defer ui.close(&r)
	base_label(gtx, text, .Subtitle1, color(.Neutral_Foreground1), heading = true)
	if close != nil {
		ui.fill_space(gtx)
		if button(gtx, "", .Subtle, .Dismiss, name = "Close") {
			close^ = false
		}
	}
}

// drawer_body_open is the body: the part that takes the remaining
// height and scrolls, padded spacingHorizontalXXL at the sides and that
// plus 1px above and below as the drawer's first or last child
// (useDrawerBodyStyles.styles.ts:16-31).
drawer_body_open :: proc(gtx: ^ui.Ctx, key: u64 = 0, loc := #caller_location) -> Drawer_Part {
	part: Drawer_Part
	part.body = true
	ui.flexible(gtx, 1)
	part.scroll = ui.scroll_box_open(gtx, key, loc = loc)
	part.inset = ui.inset_open(gtx, {DRAWER_PAD, DRAWER_PAD + DRAWER_EDGE_EXTRA, DRAWER_PAD, DRAWER_PAD + DRAWER_EDGE_EXTRA})
	part.col = ui.column_open(gtx, gap = tok.SPACING_VERTICAL_S, align = .Fill)
	return part
}

// drawer_body is drawer_body_open as a guard.
@(deferred_in = drawer_body_guard_close)
drawer_body :: proc(gtx: ^ui.Ctx, key: u64 = 0, loc := #caller_location) -> bool {
	part := ui.guard_hold(gtx, Drawer_Part)
	part^ = drawer_body_open(gtx, key, loc)
	return true
}

@(private = "file")
drawer_body_guard_close :: proc(gtx: ^ui.Ctx, key: u64, loc: runtime.Source_Code_Location) {
	part := ui.guard_take(gtx, Drawer_Part)
	ui.close(&part.col)
	ui.close(&part.inset)
	ui.close(&part.scroll)
}

// drawer_footer_open is the footer: a row of its items centred, with
// spacingHorizontalS between, padded spacingVerticalL above,
// spacingHorizontalXXL at the sides and spacingVerticalXXL below
// (useDrawerFooterStyles.styles.ts:18-29).
drawer_footer_open :: proc(gtx: ^ui.Ctx, key: u64 = 0, loc := #caller_location) -> Drawer_Part {
	part: Drawer_Part
	part.inset = ui.inset_open(gtx, {DRAWER_PAD, tok.SPACING_VERTICAL_L, DRAWER_PAD, tok.SPACING_VERTICAL_XXL}, key, loc)
	part.col = ui.row_open(gtx, gap = tok.SPACING_HORIZONTAL_S, align = .Center)
	return part
}

// drawer_footer is drawer_footer_open as a guard.
@(deferred_in = drawer_part_guard_close)
drawer_footer :: proc(gtx: ^ui.Ctx, key: u64 = 0, loc := #caller_location) -> bool {
	part := ui.guard_hold(gtx, Drawer_Part)
	part^ = drawer_footer_open(gtx, key, loc)
	return true
}

// base_label is one line of s at role in color, as a widget with its
// tag, for the plain text the containers here hold.
@(private)
base_label :: proc(gtx: ^ui.Ctx, s: string, role: Type_Role, color: ops.Color, key: u64 = 0, heading := false, loc := #caller_location) {
	p := ui.widget_open(gtx, key, loc)
	t := shape_text(gtx, s, role)
	sz := ui.constrain(gtx.constraints, {t.width, t.height})
	draw_text(gtx, t, {0, 0}, color)
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, s))
	ui.semantics(gtx, &p, {role = heading ? .Heading : .Text, label = s})
	ui.widget_close(gtx, &p, {sz, baseline_of(t)})
}

// Fixed_Surface is a surface laid out at a fixed size in the flow: jm:ui has no
// sized container, so the widget reserves its space and lays its body
// in a non-root overlay at its own origin under exact constraints (the
// inline nav and the inline drawer). height < 0 takes the height
// offered, or when that is unbounded lays the body out at its natural
// height and reserves what its paint recorded last frame (record_fixed_height).
// reveal < 1 reserves and shows only that fraction of the width (of the
// height, when bottom), for a surface sliding open in place.
@(private)
Fixed_Surface :: struct {
	p:       ui.Placement,
	overlay: ui.Overlay,
	size:    ops.Size, // the space reserved
	clip:    bool,
}

@(private)
Fixed_Data :: struct {
	height: f32, // the body's painted height last frame
}

@(private)
fixed_open :: proc(gtx: ^ui.Ctx, width: f32, height: f32 = -1, reveal: f32 = 1, bottom := false, key: u64 = 0, loc := #caller_location) -> (f: Fixed_Surface) {
	f.p = ui.widget_open(gtx, key, loc)
	cs := gtx.constraints
	data := ui.widget_data(gtx, f.p.id, Fixed_Data)
	bounded := height >= 0 || ui.is_finite(cs.max.y)
	h := height >= 0 ? height : (ui.is_finite(cs.max.y) ? cs.max.y : data.height)
	body := ui.Constraints{min = {width, bounded ? h : 0}, max = {width, bounded ? h : ui.INF}}
	reserve := ops.Size{width, h}
	if bottom {
		reserve.y *= reveal
	} else {
		reserve.x *= reveal
	}
	f.size = ui.constrain(cs, reserve)
	f.overlay = ui.overlay_open(gtx, cs = body)
	if reveal < 1 {
		ops.clip_push(gtx.scene, ops.Rect{0, 0, reserve.x, bottom || bounded ? reserve.y : 1e6})
		f.clip = true
	}
	return
}

// record_fixed_height records the body's painted height for an unbounded
// fixed_open's next frame; id is the Fixed_Surface's placement id.
@(private)
record_fixed_height :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, h: f32) {
	if id != 0 {
		ui.widget_data(gtx, id, Fixed_Data).height = h
	}
}

@(private)
fixed_close :: proc(gtx: ^ui.Ctx, f: ^Fixed_Surface) {
	if f.clip {
		ops.clip_pop(gtx.scene)
	}
	ui.close(&f.overlay)
	ui.widget_close(gtx, &f.p, {size = f.size})
}

// --- Nav ---------------------------------------------------------------

// Nav_Density is nav.json's density: medium rows pad
// spacingVerticalMNudge above and below, small spacingVerticalXS
// (sharedNavStyles.styles.ts:33-57,69-73).
Nav_Density :: enum u8 {
	Medium,
	Small,
}

// NAV_* are the nav's constants (nav.json layout notes: hard-coded in
// the styles files).
@(private)
NAV_WIDTH :: f32(260) // useNavDrawerStyles.styles.ts:36-41
@(private)
NAV_ICON :: f32(20) // sharedNavStyles.styles.ts:118-136
@(private)
NAV_GAP :: tok.SPACING_VERTICAL_L // between a row's children
@(private)
NAV_INDICATOR_W :: f32(4) // sharedNavStyles.styles.ts:9-13
@(private)
NAV_INDICATOR_H :: f32(20)
@(private)
NAV_INDICATOR_OFFSET :: f32(16) // the gutter before the row's padding edge
@(private)
NAV_SUB_INDENT_MEDIUM :: f32(46) // useNavSubItemStyles.styles.ts:21-33
@(private)
NAV_SUB_INDENT_SMALL :: f32(40)
@(private)
NAV_SECTION_MARGIN_START :: f32(10) // useNavSectionHeaderStyles.styles.ts:15-21
@(private)
NAV_SECTION_MARGIN_BLOCK :: f32(8)
@(private)
NAV_DIVIDER_MARGIN :: f32(4) // useNavDividerStyles.styles.ts:13-19
@(private)
NAV_APP_GAP :: f32(10) // useAppItemStyles.styles.ts:17-35
@(private)
NAV_APP_SMALL_PAD :: f32(14)
@(private)
NAV_APP_NO_ICON_PAD :: f32(16)
@(private)
NAV_HEADER_PAD_START :: f32(14) // useNavDrawerHeaderStyles.styles.ts:16-22
@(private)
NAV_HEADER_PAD_BLOCK :: f32(5)

// Nav is an open nav drawer between nav_open and nav_close.
Nav :: struct {
	visible: bool,
	drawer:  Drawer,
	inline:  bool,
	fixed:   Fixed_Surface,
	box:     ui.Box,
	col:     ui.Flex,
	density: Nav_Density,
}

@(private, thread_local)
current_nav: ^Nav

@(private, thread_local)
nav_density: Nav_Density

// nav_open is a NavDrawer: a drawer filled Neutral_Background4, 260px
// wide unless width says otherwise, whose body is a column of rows with
// spacingVerticalXXS between, padded spacingHorizontalMNudge at the
// start and spacingHorizontalXS at the end (useNavDrawerStyles.styles.ts:
// 16-41, useNavDrawerBodyStyles.styles.ts:16-33). With open nil it is an
// inline drawer always shown; otherwise an overlay drawer over window
// while open^. Lay nav_item, nav_category, nav_section_header,
// nav_divider, app_item and hamburger out inside, or as the guard's body.
nav_open :: proc(gtx: ^ui.Ctx, open: ^bool = nil, window: ops.Size = {}, density := Nav_Density.Medium, width: f32 = NAV_WIDTH, key: u64 = 0, loc := #caller_location) -> (n: Nav) {
	n.density = density
	nav_density = density
	fill := color(.Neutral_Background4)
	id := ui.claim_id(gtx, key, loc)
	if open == nil {
		n.inline = true
		n.visible = true
		// Exactly width wide; as tall as offered when that is bounded, else
		// as tall as its rows.
		n.fixed = fixed_open(gtx, width, key = u64(ui.id_mix(id, 1)), loc = loc)
		np := new(Nav_Paint, gtx.allocator)
		np^ = {fill = fill, fixed = n.fixed.p.id}
		n.box = ui.box_open(gtx, {padding = nav_padding(), paint = paint_nav, user = np}, u64(ui.id_mix(id, 2)), loc)
	} else {
		n.drawer = drawer_open(gtx, open, window, .Overlay, .Start, .Small, fill = fill, key = u64(ui.id_mix(id, 3)), loc = loc)
		n.visible = n.drawer.visible
		if !n.visible {
			return
		}
	}
	n.col = ui.column_open(gtx, gap = tok.SPACING_VERTICAL_XXS, align = .Fill, key = u64(ui.id_mix(id, 4)))
	ui.container_semantics(gtx, {role = .Navigation})
	current_nav = ui.widget_data(gtx, id, Nav)
	current_nav^ = n
	return
}

nav_close :: proc(n: ^Nav) {
	if !n.visible {
		return
	}
	ui.close(&n.col)
	if n.inline {
		ui.close(&n.box)
		fixed_close(n.fixed.overlay.gtx, &n.fixed)
	} else {
		drawer_close(&n.drawer)
	}
	n.visible = false
	current_nav = nil
}

// nav is nav_open as a guard: `if fluent.nav(gtx) { … }` for an inline
// nav, `if fluent.nav(gtx, &open, window) { … }` for the overlay one.
@(deferred_in = nav_guard_close)
nav :: proc(gtx: ^ui.Ctx, open: ^bool = nil, window: ops.Size = {}, density := Nav_Density.Medium, width: f32 = NAV_WIDTH, key: u64 = 0, loc := #caller_location) -> bool {
	n := nav_open(gtx, open, window, density, width, key, loc)
	return n.visible
}

@(private = "file")
nav_guard_close :: proc(gtx: ^ui.Ctx, open: ^bool, window: ops.Size, density: Nav_Density, width: f32, key: u64, loc: runtime.Source_Code_Location) {
	if current_nav != nil {
		nav_close(current_nav)
	}
}

@(private)
Nav_Paint :: struct {
	fill:  ops.Color,
	fixed: ops.Area_Id,
}

// paint_nav fills an inline nav's surface and records its height.
@(private)
paint_nav :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, size: ops.Size, user: rawptr) {
	np := (^Nav_Paint)(user)
	record_fixed_height(gtx, np.fixed, size.y)
	ops.fill(gtx.scene, ops.Rect{0, 0, size.x, size.y}, np.fill)
}

// nav_padding is a nav drawer's body padding: MNudge at the start, XS
// at the end, none above or below.
@(private)
nav_padding :: proc() -> ui.Padding {
	return {tok.SPACING_HORIZONTAL_MNUDGE, 0, tok.SPACING_HORIZONTAL_XS, 0}
}

// nav_row_pad_v is a row's vertical padding at the active density.
@(private)
nav_row_pad_v :: proc() -> f32 {
	return nav_density == .Small ? tok.SPACING_VERTICAL_XS : tok.SPACING_VERTICAL_MNUDGE
}

// Nav_Row_Kind tells the rows apart for their indent and look.
@(private)
Nav_Row_Kind :: enum u8 {
	Item,
	Sub_Item,
	Category,
}

// nav_category_data is what a category header needs from last frame:
// whether a sub-item inside it was selected, so a closed header shows
// the selected look (useNavCategoryItem.styles.ts:52-62).
@(private)
Nav_Category_Data :: struct {
	holds_selected: bool,
	seen_selected:  bool, // this frame's finding, copied at close
	open_column:    ui.Flex,
	open:           bool,
}

@(private, thread_local)
current_category: ^Nav_Category_Data

// nav_row is every nav row (sharedNavStyles.styles.ts:33-57, 87-103,
// 118-165): full width, padded spacingHorizontalMNudge at the start
// (46px or 40px for a sub-item) and spacingHorizontalS at the end, the
// density's vertical padding, a 20px icon slot and the label in body1
// Neutral_Foreground2 with spacingVerticalL between; filled
// Neutral_Background4, its Hover twin while hovered (easing over
// DURATION_FASTER on CURVE_LINEAR), rounded borderRadiusMedium. Selected,
// the label is body1Strong, the icon its filled twin in
// Neutral_Foreground2_Brand_Selected, and the 4 by 20px
// Compound_Brand_Foreground1 indicator stands 16px before the padding
// edge. A category row puts a chevron at its end. Returns the click.
@(private)
nav_row :: proc(gtx: ^ui.Ctx, label: string, ic: Icon, kind: Nav_Row_Kind, selected, open: bool, state: Interaction, key: u64, loc: runtime.Source_Code_Location) -> bool {
	p := ui.widget_open(gtx, key, loc)
	pad_v := nav_row_pad_v()
	pad_start := tok.SPACING_HORIZONTAL_MNUDGE
	if kind == .Sub_Item {
		pad_start = nav_density == .Small ? NAV_SUB_INDENT_SMALL : NAV_SUB_INDENT_MEDIUM
	}
	pad_end := tok.SPACING_HORIZONTAL_S
	t := shape_style(gtx, label, selected ? tok.TYPOGRAPHY_STYLES_BODY1_STRONG : tok.TYPOGRAPHY_STYLES_BODY1)
	content := pad_start + t.width + pad_end
	if ic != .None {
		content += NAV_ICON + NAV_GAP
	}
	if kind == .Category {
		content += NAV_GAP + NAV_ICON
	}
	cs := gtx.constraints
	w := ui.is_finite(cs.max.x) ? cs.max.x : content
	h := pad_v * 2 + max(t.height, NAV_ICON)
	sz := ui.constrain(cs, {max(w, content), h})
	area := ops.Rect{0, 0, sz.x, sz.y}
	c := control(gtx, p.id, area, state)
	bg_roles := State_Roles{.Neutral_Background4, .Neutral_Background4_Hover, .Neutral_Background4, .Neutral_Background4}
	bg := blend(gtx, c, 0, color_for(bg_roles, c), tok.DURATION_FASTER, tok.CURVE_LINEAR)
	fg := color(c.disabled ? .Neutral_Foreground_Disabled : .Neutral_Foreground2)
	k := corners_all(tok.BORDER_RADIUS_MEDIUM)
	ops.fill(gtx.scene, rounded(gtx, area, k), bg)
	if selected {
		// Every row's pill stands in the same gutter: an item's 16px before
		// its MNudge padding, a sub-item's 52px before its 46 (useNavSubItem
		// Styles.styles.ts:49-59), both 6px before the row.
		ind := ops.Rect{tok.SPACING_HORIZONTAL_MNUDGE - NAV_INDICATOR_OFFSET, (sz.y - NAV_INDICATOR_H) / 2, NAV_INDICATOR_W, NAV_INDICATOR_H}
		ops.fill(gtx.scene, ops.Round_Rect{ind, NAV_INDICATOR_W / 2}, color(.Compound_Brand_Foreground1))
	}
	x := pad_start
	if ic != .None {
		shown := selected ? filled(ic) : ic
		icon(gtx, shown, {x, (sz.y - NAV_ICON) / 2}, NAV_ICON, selected ? color(.Neutral_Foreground2_Brand_Selected) : fg)
		x += NAV_ICON + NAV_GAP
	}
	draw_text(gtx, t, {x, (sz.y - t.height) / 2}, fg)
	if kind == .Category {
		chevron_at(gtx, {sz.x - pad_end - NAV_ICON, (sz.y - NAV_ICON) / 2}, NAV_ICON, open, fg)
	}
	// Focus: a strokeWidthThick Stroke_Focus2 outline inset by the same,
	// inside the row's edge (sharedNavStyles.styles.ts:62-66).
	if c.focus_visible && !c.disabled {
		inset := tok.STROKE_WIDTH_THICK
		design.stroke_inside_corners(gtx, shrink(area, inset), design.grow_corners(k, -inset), color(.Stroke_Focus2), tok.STROKE_WIDTH_THICK)
	}
	listen(gtx, c.st, p.id, area)
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, label))
	states := state_if(selected, {.Selected}) + state_if(c.disabled, {.Disabled})
	if kind == .Category {
		states += {.Expandable} + state_if(open, {.Expanded})
	}
	ui.semantics(gtx, &p, {role = .Tab, label = label, states = states})
	ui.widget_close(gtx, &p, {sz, (sz.y - t.height) / 2 + baseline_of(t)})
	return c.clicked
}

// chevron_at is Chevron_Right at pos and size, turned a quarter turn
// about its centre to point down when open.
@(private)
chevron_at :: proc(gtx: ^ui.Ctx, pos: ops.Point, size: f32, open: bool, c: ops.Color) {
	if !open {
		icon(gtx, .Chevron_Right, pos, size, c)
		return
	}
	cx, cy := pos.x + size / 2, pos.y + size / 2
	ops.transform_push(gtx.scene, ops.mul(ops.mul(ops.translate(-cx, -cy), ops.rotate(math.PI / 2)), ops.translate(cx, cy)))
	icon(gtx, .Chevron_Right, pos, size, c)
	ops.transform_pop(gtx.scene)
}

// nav_item is a top-level item: a row that, clicked (or Enter or Space
// while focused), sets selected^ to value and returns true. It shows the
// selected look while selected^ == value (useNavItem.ts:54-79).
nav_item :: proc(gtx: ^ui.Ctx, label, value: string, selected: ^string, ic := Icon.None, state := Interaction.Live, key: u64 = 0, loc := #caller_location) -> bool {
	on := selected != nil && selected^ == value
	clicked := nav_row(gtx, label, ic, .Item, on, false, state, key, loc)
	if clicked && selected != nil {
		selected^ = value
	}
	return clicked
}

// nav_sub_item is an item inside a category: indented 46px (40px at
// small density) and otherwise an item. It tells its category that it
// is selected, so the closed header can show the look.
nav_sub_item :: proc(gtx: ^ui.Ctx, label, value: string, selected: ^string, state := Interaction.Live, key: u64 = 0, loc := #caller_location) -> bool {
	on := selected != nil && selected^ == value
	if on && current_category != nil {
		current_category.seen_selected = true
	}
	clicked := nav_row(gtx, label, .None, .Sub_Item, on, false, state, key, loc)
	if clicked && selected != nil {
		selected^ = value
	}
	return clicked
}

// Nav_Category is an open category between nav_category_open and
// nav_category_close.
Nav_Category :: struct {
	open: bool,
	data: ^Nav_Category_Data,
	prev: ^Nav_Category_Data,
}

// nav_category_open is a category: its header row with the chevron at
// the end, which a click flips open^ (useNav.ts:38-48,137-144), and then,
// only while open^, the sub-item group where nav_sub_item rows go. A
// closed header shows the selected look when one of its sub-items was
// selected last frame, and an open one hands it to the sub-item
// (useNavCategoryItem.styles.ts:52-62). Single-open is the caller's rule,
// who owns the open flags. Departure: the group's Collapse motion is
// not applied; the sub-items appear at once.
nav_category_open :: proc(gtx: ^ui.Ctx, label: string, open: ^bool, ic := Icon.None, state := Interaction.Live, key: u64 = 0, loc := #caller_location) -> (cat: Nav_Category) {
	id := ui.claim_id(gtx, key, loc)
	data := ui.widget_data(gtx, id, Nav_Category_Data)
	if nav_row(gtx, label, ic, .Category, data.holds_selected && !open^, open^, state, u64(ui.id_mix(id, 1)), loc) {
		open^ = !open^
	}
	cat.open = open^
	cat.data = data
	cat.prev = current_category
	data.seen_selected = false
	current_category = data
	if cat.open {
		data.open_column = ui.column_open(gtx, gap = tok.SPACING_VERTICAL_XXS, align = .Fill, key = u64(ui.id_mix(id, 2)), loc = loc)
	}
	return
}

nav_category_close :: proc(cat: ^Nav_Category) {
	if cat.open {
		ui.close(&cat.data.open_column)
	}
	cat.data.holds_selected = cat.data.seen_selected
	current_category = cat.prev
}

// nav_category is nav_category_open as a guard: the if body is the
// sub-item group and runs only while the category is open.
@(deferred_in = nav_category_guard_close)
nav_category :: proc(gtx: ^ui.Ctx, label: string, open: ^bool, ic := Icon.None, state := Interaction.Live, key: u64 = 0, loc := #caller_location) -> bool {
	cat := ui.guard_hold(gtx, Nav_Category)
	cat^ = nav_category_open(gtx, label, open, ic, state, key, loc)
	return cat.open
}

@(private = "file")
nav_category_guard_close :: proc(gtx: ^ui.Ctx, label: string, open: ^bool, ic: Icon, state: Interaction, key: u64, loc: runtime.Source_Code_Location) {
	nav_category_close(ui.guard_take(gtx, Nav_Category))
}

// nav_section_header is caption1Strong text 10px in from the start with
// 8px above and below (useNavSectionHeaderStyles.styles.ts:15-21).
nav_section_header :: proc(gtx: ^ui.Ctx, text: string, key: u64 = 0, loc := #caller_location) {
	in_ := ui.inset_open(gtx, {NAV_SECTION_MARGIN_START, NAV_SECTION_MARGIN_BLOCK, 0, NAV_SECTION_MARGIN_BLOCK}, key, loc)
	defer ui.close(&in_)
	base_label(gtx, text, .Caption1_Strong, color(.Neutral_Foreground2))
}

// nav_divider is the divider's default rule with 4px above and below
// (useNavDividerStyles.styles.ts:13-19).
nav_divider :: proc(gtx: ^ui.Ctx, key: u64 = 0, loc := #caller_location) {
	in_ := ui.inset_open(gtx, {0, NAV_DIVIDER_MARGIN, 0, NAV_DIVIDER_MARGIN}, key, loc)
	defer ui.close(&in_)
	divider(gtx)
}

// app_item is the app title row: subtitle2 text with a 10px gap after its
// icon, padded spacingVerticalS above and below, spacingHorizontalMNudge
// at the start (14px with a 14px gap at small density, 16px without an
// icon) and spacingHorizontalS at the end, its width its content's
// (useAppItemStyles.styles.ts:17-55). It is a row like any other unless
// static, when it has no hover or press look and takes no input.
app_item :: proc(gtx: ^ui.Ctx, label: string, ic := Icon.None, static := false, state := Interaction.Live, key: u64 = 0, loc := #caller_location) -> bool {
	p := ui.widget_open(gtx, key, loc)
	t := shape_style(gtx, label, tok.TYPOGRAPHY_STYLES_SUBTITLE2)
	pad_start, gap := tok.SPACING_HORIZONTAL_MNUDGE, NAV_APP_GAP
	if nav_density == .Small {
		pad_start, gap = NAV_APP_SMALL_PAD, NAV_APP_SMALL_PAD
	}
	if ic == .None {
		pad_start = NAV_APP_NO_ICON_PAD
	}
	w := pad_start + t.width + tok.SPACING_HORIZONTAL_S
	if ic != .None {
		w += NAV_ICON + gap
	}
	h := tok.SPACING_VERTICAL_S * 2 + max(t.height, NAV_ICON)
	sz := ui.constrain(gtx.constraints, {w, h})
	area := ops.Rect{0, 0, sz.x, sz.y}
	c := control(gtx, p.id, area, static ? .Enabled : state)
	fg := color(.Neutral_Foreground2)
	if !static {
		bg_roles := State_Roles{.Neutral_Background4, .Neutral_Background4_Hover, .Neutral_Background4_Pressed, .Neutral_Background4}
		ops.fill(gtx.scene, ops.Round_Rect{area, tok.BORDER_RADIUS_MEDIUM}, blend(gtx, c, 0, color_for(bg_roles, c), tok.DURATION_FASTER, tok.CURVE_LINEAR))
	}
	x := pad_start
	if ic != .None {
		icon(gtx, ic, {x, (sz.y - NAV_ICON) / 2}, NAV_ICON, fg)
		x += NAV_ICON + gap
	}
	draw_text(gtx, t, {x, (sz.y - t.height) / 2}, fg)
	if !static {
		paint_focus_outline(gtx, c, {area, tok.BORDER_RADIUS_MEDIUM})
		listen(gtx, c.st, p.id, area)
	}
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, label))
	ui.semantics(gtx, &p, {role = static ? .Text : .Button, label = label, states = state_if(c.disabled, {.Disabled})})
	ui.widget_close(gtx, &p, {sz, (sz.y - t.height) / 2 + baseline_of(t)})
	return c.clicked && !static
}

// hamburger is the button that opens or closes the nav: the button spec's
// subtle icon-only button with the Navigation icon and no border, on
// Neutral_Background4, pressed Neutral_Background4_Pressed
// (useHamburgerStyles.styles.ts:18-36). Returns true when clicked.
hamburger :: proc(gtx: ^ui.Ctx, state := Interaction.Live, key: u64 = 0, loc := #caller_location) -> bool {
	p := ui.widget_open(gtx, key, loc)
	sz := ui.constrain(gtx.constraints, {CONTROL_HEIGHT[.Medium], CONTROL_HEIGHT[.Medium]})
	area := ops.Rect{0, 0, sz.x, sz.y}
	c := control(gtx, p.id, area, state)
	bg_roles := State_Roles{.Neutral_Background4, .Neutral_Background4_Hover, .Neutral_Background4_Pressed, .Neutral_Background4}
	k := corners_all(tok.BORDER_RADIUS_MEDIUM)
	ops.fill(gtx.scene, rounded(gtx, area, k), blend(gtx, c, 0, color_for(bg_roles, c), tok.DURATION_FASTER, tok.CURVE_LINEAR))
	fg := color(c.disabled ? .Neutral_Foreground_Disabled : .Neutral_Foreground2)
	icon(gtx, .Navigation, {(sz.x - NAV_ICON) / 2, (sz.y - NAV_ICON) / 2}, NAV_ICON, fg)
	paint_focus_inset(gtx, c, area, k, paint_border = true)
	listen(gtx, c.st, p.id, area)
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, "Navigation"))
	ui.semantics(gtx, &p, {role = .Button, label = "Navigation", states = state_if(c.disabled, {.Disabled})})
	ui.widget_close(gtx, &p, {size = sz})
	return c.clicked
}

// nav_header_open is the nav drawer's header: the drawer header with its
// margin removed, padded 14px at the start and 5px above and below
// (useNavDrawerHeaderStyles.styles.ts:16-31); the hamburger and app item
// go here.
nav_header_open :: proc(gtx: ^ui.Ctx, key: u64 = 0, loc := #caller_location) -> Drawer_Part {
	part: Drawer_Part
	part.inset = ui.inset_open(gtx, {NAV_HEADER_PAD_START, NAV_HEADER_PAD_BLOCK, tok.SPACING_HORIZONTAL_XS, NAV_HEADER_PAD_BLOCK}, key, loc)
	part.col = ui.row_open(gtx, gap = tok.SPACING_HORIZONTAL_S, align = .Center)
	return part
}

// nav_header is nav_header_open as a guard.
@(deferred_in = drawer_part_guard_close)
nav_header :: proc(gtx: ^ui.Ctx, key: u64 = 0, loc := #caller_location) -> bool {
	part := ui.guard_hold(gtx, Drawer_Part)
	part^ = nav_header_open(gtx, key, loc)
	return true
}

// nav_body_open is the nav drawer's body: the rows, with spacingVerticalXXS
// between, padded MNudge at the start and XS at the end, scrolling
// (useNavDrawerBodyStyles.styles.ts:16-33).
nav_body_open :: proc(gtx: ^ui.Ctx, key: u64 = 0, loc := #caller_location) -> Drawer_Part {
	part: Drawer_Part
	part.body = true
	ui.flexible(gtx, 1)
	part.scroll = ui.scroll_box_open(gtx, key, loc = loc)
	part.inset = ui.inset_open(gtx, nav_padding())
	part.col = ui.column_open(gtx, gap = tok.SPACING_VERTICAL_XXS, align = .Fill)
	return part
}

// nav_body is nav_body_open as a guard.
@(deferred_in = drawer_body_guard_close)
nav_body :: proc(gtx: ^ui.Ctx, key: u64 = 0, loc := #caller_location) -> bool {
	part := ui.guard_hold(gtx, Drawer_Part)
	part^ = nav_body_open(gtx, key, loc)
	return true
}

// nav_footer_open is the nav drawer's footer: rows with spacingVerticalXXS
// between, padded XXS above and below, MNudge at the start and XS at the
// end (useNavDrawerFooterStyles.styles.ts:16-32, the padding the spec's
// upstream-bug note reads from its malformed shorthand).
nav_footer_open :: proc(gtx: ^ui.Ctx, key: u64 = 0, loc := #caller_location) -> Drawer_Part {
	part: Drawer_Part
	part.inset = ui.inset_open(gtx, {tok.SPACING_HORIZONTAL_MNUDGE, tok.SPACING_VERTICAL_XXS, tok.SPACING_HORIZONTAL_XS, tok.SPACING_VERTICAL_XXS}, key, loc)
	part.col = ui.column_open(gtx, gap = tok.SPACING_VERTICAL_XXS, align = .Fill)
	return part
}

// nav_footer is nav_footer_open as a guard.
@(deferred_in = drawer_part_guard_close)
nav_footer :: proc(gtx: ^ui.Ctx, key: u64 = 0, loc := #caller_location) -> bool {
	part := ui.guard_hold(gtx, Drawer_Part)
	part^ = nav_footer_open(gtx, key, loc)
	return true
}

// --- Breadcrumb ----------------------------------------------------------

// Breadcrumb_Metrics are one size's button height, padding, text styles,
// icon and divider glyph sizes and ring radius (useBreadcrumbButtonStyles.
// styles.ts:26-46,67-86,122-136; useBreadcrumbDividerStyles.styles.ts:
// 14-28).
@(private)
Breadcrumb_Metrics :: struct {
	height, pad, glyph, ring: f32,
	style, current:           tok.Type_Style,
}

@(private)
breadcrumb_metrics :: proc(size: Size) -> Breadcrumb_Metrics {
	switch size {
	case .Small:
		return {24, tok.SPACING_HORIZONTAL_SNUDGE, 12, tok.BORDER_RADIUS_SMALL, tok.TYPOGRAPHY_STYLES_CAPTION1, tok.TYPOGRAPHY_STYLES_CAPTION1_STRONG}
	case .Medium:
	case .Large:
		return {40, tok.SPACING_HORIZONTAL_S, 20, tok.BORDER_RADIUS_LARGE, tok.TYPOGRAPHY_STYLES_BODY2, tok.TYPOGRAPHY_STYLES_SUBTITLE2}
	}
	return {32, tok.SPACING_HORIZONTAL_SNUDGE, 16, tok.BORDER_RADIUS_MEDIUM, tok.TYPOGRAPHY_STYLES_BODY1, tok.TYPOGRAPHY_STYLES_BODY1_STRONG}
}

// BREADCRUMB_MAX_SHOWN and BREADCRUMB_OVERFLOW_INDEX are the overflow
// defaults (partitionBreadcrumbItems.ts:1-60).
BREADCRUMB_MAX_SHOWN :: 6
BREADCRUMB_OVERFLOW_INDEX :: 1

// BREADCRUMB_MAX_NAME is the length a name is cut to (truncateBreadcrumb.ts:1-22).
@(private)
BREADCRUMB_MAX_NAME :: 30

// breadcrumb is the trail: items from the top of the hierarchy to the
// current page, the last, with a chevron between each pair. Every item
// but the last is the button spec's subtle rounded button at the size
// with its minimum width removed (useBreadcrumbButton.ts:31-36); the
// last is the size's strong style with no hover, press or input, so it
// reads as text. With more than max_shown items, the first
// overflow_index stay, the run after them collapses into a "…" button
// whose menu lists them, and the rest follow. Names longer than 30
// characters are cut with an ellipsis. Returns the index of the item
// clicked, or -1. icons, when given, sit before each item's label.
//
// Departures: the arrow focus mode is not built (jm:ui moves focus by
// press only); the tooltip on a truncated name is the caller's.
breadcrumb :: proc(
	gtx: ^ui.Ctx,
	items: []string,
	size := Size.Medium,
	icons: []Icon = nil,
	max_shown := BREADCRUMB_MAX_SHOWN,
	overflow_index := BREADCRUMB_OVERFLOW_INDEX,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> int {
	m := breadcrumb_metrics(size)
	id := ui.claim_id(gtx, key, loc)
	r := ui.row_open(gtx, align = .Center, key = u64(ui.id_mix(id, 1)), loc = loc)
	defer ui.close(&r)
	ui.container_semantics(gtx, {role = .Navigation})
	clicked := -1
	n := len(items)
	// partitionBreadcrumbItems.ts:23-56: the first overflow_index items,
	// the hidden run, then the rest.
	head, hidden_end := n, n
	if n > max_shown {
		idx := clamp(overflow_index, 0, max_shown - 1)
		head = idx
		hidden_end = n - (max_shown - idx)
	}
	menu_data := ui.widget_data(gtx, id, Breadcrumb_Overflow)
	for i in 0 ..< n {
		if i >= head && i < hidden_end {
			if i == head {
				if i > 0 {
					breadcrumb_divider(gtx, m, u64(1000 + i))
				}
				// The overflow button and its menu of the hidden run.
				if crumb_button(gtx, "", .More_Horizontal, m, false, state, u64(2000 + i), loc, "More items") {
					menu_data.open = !menu_data.open
				}
				if menu(gtx, &menu_data.open, {0, 0, 0, m.height}, key = u64(3000 + i)) {
					for j in head ..< hidden_end {
						if menu_item(gtx, crumb_name(gtx, items[j]), key = u64(j)) {
							clicked = j
						}
					}
				}
			}
			continue
		}
		if i > 0 {
			breadcrumb_divider(gtx, m, u64(1000 + i))
		}
		ic := Icon.None
		if i < len(icons) {
			ic = icons[i]
		}
		current := i == n - 1
		if crumb_button(gtx, crumb_name(gtx, items[i]), ic, m, current, state, u64(i), loc, items[i]) {
			clicked = i
		}
	}
	return clicked
}

@(private)
Breadcrumb_Overflow :: struct {
	open: bool,
}

// crumb_name is s cut to BREADCRUMB_MAX_NAME characters plus an ellipsis.
@(private)
crumb_name :: proc(gtx: ^ui.Ctx, s: string) -> string {
	if len(s) <= BREADCRUMB_MAX_NAME {
		return s
	}
	cut := BREADCRUMB_MAX_NAME
	for cut > 0 && s[cut] & 0xC0 == 0x80 { // do not split a rune
		cut -= 1
	}
	return strings.concatenate({s[:cut], "…"}, gtx.allocator)
}

// breadcrumb_divider is the chevron between items, at the size's glyph
// size in the item colour, Neutral_Foreground2 (useBreadcrumbDividerStyles.
// styles.ts:14-28).
@(private)
breadcrumb_divider :: proc(gtx: ^ui.Ctx, m: Breadcrumb_Metrics, key: u64) {
	p := ui.widget_open(gtx, key)
	sz := ui.constrain(gtx.constraints, {m.glyph, m.height})
	icon(gtx, .Chevron_Right, {0, (sz.y - m.glyph) / 2}, m.glyph, color(.Neutral_Foreground2))
	ui.widget_close(gtx, &p, {size = sz})
}

// crumb_button is one item: the subtle button's colours per state over a
// height, padding, style and icon size the trail's metrics give, with no
// minimum width (useBreadcrumbButtonStyles.styles.ts:48-106); current
// paints the strong style and Transparent_Background in every state and
// takes no input.
@(private)
crumb_button :: proc(gtx: ^ui.Ctx, label: string, ic: Icon, m: Breadcrumb_Metrics, current: bool, state: Interaction, key: u64, loc: runtime.Source_Code_Location, tag: string) -> bool {
	p := ui.widget_open(gtx, key, loc)
	t := shape_style(gtx, label, current ? m.current : m.style)
	has_icon := ic != .None
	icon_only := has_icon && label == ""
	w := m.pad * 2 + (icon_only ? m.glyph : t.width)
	if has_icon && !icon_only {
		w += m.glyph + tok.SPACING_HORIZONTAL_XS
	}
	sz := ui.constrain(gtx.constraints, {w, m.height})
	area := ops.Rect{0, 0, sz.x, sz.y}
	c := control(gtx, p.id, area, current ? .Enabled : state)
	r := appearance_roles(.Subtle)
	k := corners_all(tok.BORDER_RADIUS_MEDIUM)
	bg, fg, ic_color: ops.Color
	if current {
		bg = color(.Transparent_Background)
		fg = color(.Neutral_Foreground2)
		ic_color = fg
	} else {
		bg = blend(gtx, c, 0, color_for(r.bg, c))
		fg = blend(gtx, c, 2, color_for(r.text, c))
		ic_color = blend(gtx, c, 3, color_for(r.icon, c))
	}
	if ui.painted(bg) {
		ops.fill(gtx.scene, rounded(gtx, area, k), bg)
	}
	shown := ic
	if !current && (c.hovered || c.pressed) && !c.disabled {
		shown = filled(ic)
	}
	x := m.pad
	if has_icon {
		icon(gtx, shown, {x, (sz.y - m.glyph) / 2}, m.glyph, ic_color)
		x += m.glyph + (icon_only ? 0 : tok.SPACING_HORIZONTAL_XS)
	}
	if !icon_only {
		draw_text(gtx, t, {x, (sz.y - t.height) / 2}, fg)
	}
	if !current {
		paint_focus_inset(gtx, c, area, corners_all(m.ring))
		listen(gtx, c.st, p.id, area)
	}
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, tag))
	// The overflow button is a button; every crumb is a link, the
	// current page the selected one.
	role: ops.Role = icon_only ? .Button : .Link
	ui.semantics(gtx, &p, {role = role, label = tag, states = state_if(current, {.Selected}) + state_if(c.disabled, {.Disabled})})
	ui.widget_close(gtx, &p, {sz, (sz.y - t.height) / 2 + baseline_of(t)})
	return c.clicked && !current
}

// --- Tree ---------------------------------------------------------------

// Tree_Appearance is tree.json's appearance: which hover and press family
// a row reads.
Tree_Appearance :: enum u8 {
	Subtle,
	Subtle_Alpha,
	Transparent,
}

// Tree_Size is the row: 32px in body1 at medium, 24px in caption1 at small.
Tree_Size :: enum u8 {
	Medium,
	Small,
}

// TREE_* are the tree's constants (useTreeItemLayoutStyles.styles.ts:
// 22-27,56-62,111-120; useTreeItemStyles.styles.ts:26-47).
@(private)
TREE_ROW_MEDIUM :: f32(32)
@(private)
TREE_ROW_SMALL :: f32(24)
@(private)
TREE_CHEVRON_BOX :: f32(24)
@(private)
TREE_INDENT :: tok.SPACING_HORIZONTAL_XXL
@(private)
TREE_GLYPH :: tok.FONT_SIZE_BASE500
@(private)
TREE_FOCUS_WIDTH :: f32(2)

@(private)
tree_row_roles :: proc(a: Tree_Appearance) -> State_Roles {
	switch a {
	case .Subtle:
		return {.Subtle_Background, .Subtle_Background_Hover, .Subtle_Background_Pressed, .Subtle_Background}
	case .Subtle_Alpha:
		return {.Subtle_Background, .Subtle_Background_Light_Alpha_Hover, .Subtle_Background_Light_Alpha_Pressed, .Subtle_Background}
	case .Transparent:
		return {.Transparent_Background, .Transparent_Background_Hover, .Transparent_Background_Pressed, .Transparent_Background}
	}
	return {}
}

// Tree_Item is an open item between tree_item_open and tree_item_close.
Tree_Item :: struct {
	open:   bool,
	column: ui.Flex,
	body:   ui.Flex,
	branch: bool,
}

// tree_item_open is one row of a tree at level (1 at the top): a branch
// when open is non-nil, whose chevron (Chevron_Right, down when open)
// stands in a 24px box after (level - 1) indent steps of
// spacingHorizontalXXL, or a leaf indented level steps; then the
// selector when checked is non-nil (a checkbox, mixed while mixed), the
// before icon, the label in the size's style with spacingHorizontalXXS
// at each side, a caption description under it, the after icon, and the
// aside text pushed to the end. The row is at least 32px (24px at small)
// tall, fills the appearance's rest, hover and pressed tokens at once
// (nothing transitions), Neutral_Foreground2 text and a
// Neutral_Foreground3 chevron, and draws a 2px Stroke_Focus2 outline
// when focused. A click on a branch row, or Enter while focused, flips
// open^; Right opens and Left closes it. Only while open^ does the
// subtree column (spacingVerticalXXS between rows, XXS above) lay out;
// the children are tree_item rows at level + 1. Returns the row's
// click. Departure: the subtree's Collapse motion is not applied.
tree_item_open :: proc(
	gtx: ^ui.Ctx,
	label: string,
	open: ^bool = nil,
	level := 1,
	size := Tree_Size.Medium,
	appearance := Tree_Appearance.Subtle,
	icon_before := Icon.None,
	icon_after := Icon.None,
	description := "",
	aside := "",
	checked: ^bool = nil,
	mixed := false,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> (it: Tree_Item, clicked: bool) {
	it.column = ui.column_open(gtx, gap = tok.SPACING_VERTICAL_XXS, align = .Fill, key = key, loc = loc)
	it.branch = open != nil
	clicked = tree_row(gtx, label, open, level, size, appearance, icon_before, icon_after, description, aside, checked, mixed, state, key, loc)
	it.open = open != nil && open^
	if it.open {
		it.body = ui.column_open(gtx, gap = tok.SPACING_VERTICAL_XXS, align = .Fill, key = key ~ 0x5375627472656501, loc = loc)
		ui.container_semantics(gtx, {role = .List})
	}
	return
}

tree_item_close :: proc(it: ^Tree_Item) {
	if it.open {
		ui.close(&it.body)
	}
	ui.close(&it.column)
}

// tree_item is tree_item_open as a guard: the if body is the subtree and
// runs only while the branch is open.
@(deferred_in = tree_item_guard_close)
tree_item :: proc(
	gtx: ^ui.Ctx,
	label: string,
	open: ^bool = nil,
	level := 1,
	size := Tree_Size.Medium,
	appearance := Tree_Appearance.Subtle,
	icon_before := Icon.None,
	icon_after := Icon.None,
	description := "",
	aside := "",
	checked: ^bool = nil,
	mixed := false,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	it := ui.guard_hold(gtx, Tree_Item)
	it^, _ = tree_item_open(gtx, label, open, level, size, appearance, icon_before, icon_after, description, aside, checked, mixed, state, key, loc)
	return it.open
}

@(private = "file")
tree_item_guard_close :: proc(gtx: ^ui.Ctx, label: string, open: ^bool, level: int, size: Tree_Size, appearance: Tree_Appearance, icon_before, icon_after: Icon, description, aside: string, checked: ^bool, mixed: bool, state: Interaction, key: u64, loc: runtime.Source_Code_Location) {
	tree_item_close(ui.guard_take(gtx, Tree_Item))
}

@(private)
TREE_ROW_KEY :: u64(0x54726565526f7701)

// tree_row is the item's layout row (see tree_item_open).
@(private)
tree_row :: proc(gtx: ^ui.Ctx, label: string, open: ^bool, level: int, size: Tree_Size, appearance: Tree_Appearance, icon_before, icon_after: Icon, description, aside: string, checked: ^bool, mixed: bool, state: Interaction, key: u64, loc: runtime.Source_Code_Location) -> bool {
	p := ui.widget_open(gtx, key ~ TREE_ROW_KEY, loc)
	branch := open != nil
	min_h := size == .Small ? TREE_ROW_SMALL : TREE_ROW_MEDIUM
	st := size == .Small ? tok.TYPOGRAPHY_STYLES_CAPTION1 : tok.TYPOGRAPHY_STYLES_BODY1
	icon_pad := size == .Small ? tok.SPACING_HORIZONTAL_XXS : tok.SPACING_HORIZONTAL_XS
	t := shape_style(gtx, label, st)
	desc: Text
	if description != "" {
		desc = shape_style(gtx, description, tok.TYPOGRAPHY_STYLES_CAPTION1)
	}
	side: Text
	if aside != "" {
		side = shape_style(gtx, aside, tok.TYPOGRAPHY_STYLES_CAPTION1)
	}
	// useTreeItemLayoutStyles.styles.ts:49-55: a leaf pads level steps, a
	// branch level - 1 and its chevron box fills the step.
	indent := f32(branch ? level - 1 : level) * TREE_INDENT
	content := indent
	if branch {
		content += TREE_CHEVRON_BOX
	}
	if checked != nil {
		content += 16 + tok.SPACING_HORIZONTAL_XS
	}
	if icon_before != .None {
		content += TREE_GLYPH + icon_pad
	}
	content += tok.SPACING_HORIZONTAL_XXS + max(t.width, desc.width) + tok.SPACING_HORIZONTAL_XXS
	if icon_after != .None {
		content += icon_pad + TREE_GLYPH
	}
	if aside != "" {
		content += tok.SPACING_HORIZONTAL_M * 2 + side.width
	}
	text_h := t.height + (description != "" ? desc.height : 0)
	cs := gtx.constraints
	w := ui.is_finite(cs.max.x) ? cs.max.x : content
	sz := ui.constrain(cs, {max(w, content), max(min_h, text_h)})
	area := ops.Rect{0, 0, sz.x, sz.y}
	c := control(gtx, p.id, area, state)
	if branch {
		if c.clicked {
			open^ = !open^
		}
		if c.st != nil {
			for e in ui.events(gtx, p.id) {
				if e.kind != .Key {
					continue
				}
				#partial switch e.key {
				case .Right:
					open^ = true
				case .Left:
					open^ = false
				}
			}
		}
	}
	bg := color_for(tree_row_roles(appearance), c)
	if ui.painted(bg) {
		ops.fill(gtx.scene, ops.Round_Rect{area, tok.BORDER_RADIUS_MEDIUM}, bg)
	}
	fg := color_for({.Neutral_Foreground2, .Neutral_Foreground2_Hover, .Neutral_Foreground2_Pressed, .Neutral_Foreground_Disabled}, c)
	x := indent
	if branch {
		ch := color_for({.Neutral_Foreground3, .Neutral_Foreground3_Hover, .Neutral_Foreground3_Pressed, .Neutral_Foreground_Disabled}, c)
		chevron_at(gtx, {x + (TREE_CHEVRON_BOX - TREE_GLYPH) / 2, (sz.y - TREE_GLYPH) / 2}, TREE_GLYPH, open^, ch)
		x += TREE_CHEVRON_BOX
	}
	if checked != nil {
		// The selector: the checkbox's 16px box, drawn by the checkbox
		// itself at its own id so it takes its own click.
		// A label-less checkbox is its 16px box in CONTROL_MARGIN on every
		// side, so it is placed a margin out.
		hit := 16 + 2 * CONTROL_MARGIN
		sel := ui.overlay_open(gtx, {x - CONTROL_MARGIN, (sz.y - hit) / 2}, cs = ui.loose({hit, hit}))
		checkbox(gtx, checked, mixed = mixed, state = state, key = key ~ 0x53656c6563746f72, loc = loc)
		ui.close(&sel)
		x += 16 + tok.SPACING_HORIZONTAL_XS
	}
	if icon_before != .None {
		icon(gtx, icon_before, {x, (sz.y - TREE_GLYPH) / 2}, TREE_GLYPH, fg)
		x += TREE_GLYPH + icon_pad
	}
	x += tok.SPACING_HORIZONTAL_XXS
	y := (sz.y - text_h) / 2
	draw_text(gtx, t, {x, y}, fg)
	if description != "" {
		draw_text(gtx, desc, {x, y + t.height}, color(.Neutral_Foreground3))
	}
	x += max(t.width, desc.width) + tok.SPACING_HORIZONTAL_XXS
	if icon_after != .None {
		x += icon_pad
		icon(gtx, icon_after, {x, (sz.y - TREE_GLYPH) / 2}, TREE_GLYPH, fg)
	}
	if aside != "" {
		draw_text(gtx, side, {sz.x - tok.SPACING_HORIZONTAL_M - side.width, (sz.y - side.height) / 2}, color(.Neutral_Foreground3))
	}
	if c.focus_visible && !c.disabled {
		design.paint_focus_ring(gtx, c.base, {area, tok.BORDER_RADIUS_MEDIUM}, {TREE_FOCUS_WIDTH, 0, color(.Stroke_Focus2)})
	}
	listen(gtx, c.st, p.id, area)
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, label))
	states := state_if(c.disabled, {.Disabled})
	if branch {
		states += {.Expandable} + state_if(open^, {.Expanded})
	}
	ui.semantics(gtx, &p, {role = .List_Item, label = label, value = aside, description = description, states = states})
	ui.widget_close(gtx, &p, {sz, y + baseline_of(t)})
	return c.clicked
}
