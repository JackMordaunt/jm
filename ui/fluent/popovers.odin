package fluent

import "base:runtime"
import "core:fmt"
import "jm:ui"
import "jm:ui/design"
import tok "jm:ui/fluent/tokens"
import "jm:ui/ops"

// Anchored surfaces: the popover, the teaching popover built on it, and
// the info label whose button opens one, from the fluent-kit's
// components/popover.json, teaching-popover.json and info-label.json and
// the styles files they cite (usePopoverSurfaceStyles, the
// useTeachingPopover*Styles family, useInfoButtonStyles,
// useInfoLabelStyles). A popover opens a ui.overlay placed from the
// enclosing container's origin, as overlays.odin's menu does, so put the
// trigger and the popover in a ui.stack and pass the trigger's size as
// the anchor. Its machinery (the scrim that closes on a press outside,
// the surface that swallows its own presses and takes focus so Escape
// reaches it, discarding the layer on the frame it closes) is the
// menu's, written again here for a surface whose size and side vary.

// Popover_Appearance is popover.json's appearance.
Popover_Appearance :: enum u8 {
	Normal, // Neutral_Background1, Neutral_Foreground1
	Brand, // Brand_Background, on-brand text
	Inverted, // the static dark pair, the same in every theme
}

// Popover_Position is which side of its anchor the surface opens on.
Popover_Position :: enum u8 {
	Above,
	Below,
	Before,
	After,
}

// Popover_Align is where the surface sits along its anchor's side: centred
// on it, or flush with its start (the info label's above-start).
Popover_Align :: enum u8 {
	Center,
	Start,
}

// POPOVER_PAD and POPOVER_ARROW are the surface's padding and the arrow's
// height per size (popover.json layout box and arrow,
// usePopoverSurfaceStyles.styles.ts:14-18,53-61,82-86).
@(private)
POPOVER_PAD := [Size]f32{.Small = 12, .Medium = 16, .Large = 20}
@(private)
POPOVER_ARROW := [Size]f32{.Small = 6, .Medium = 8, .Large = 8}
// POPOVER_GAP is the space between surface and anchor without an arrow.
// ASSUMPTION: the positioning offset is not in the styles file; this is
// the tooltip's 4px (tooltip.json constants.ts), noted in the proc.
@(private)
POPOVER_GAP :: f32(4)
// POPOVER_SLIDE is how far the surface slides in from its side as it
// opens (popover.json states open).
@(private)
POPOVER_SLIDE :: f32(10)

// Popover is an open popover between popover_open and popover_close.
Popover :: struct {
	visible:    bool,
	overlay:    ui.Overlay,
	box:        ui.Box,
	col:        ui.Flex,
	id:         ops.Area_Id,
	open:       ^bool,
	fg:         ops.Color, // the appearance's text colour, for content
	appearance: Popover_Appearance,
	alpha:      f32,
	look:       ^Popover_Look, // the surface's paint record, which learns its size at close
	slid:       bool, // a slide transform is pushed inside the overlay
}

// Popover_Data is what a popover keeps between frames: its surface's
// size, which paint_popover records as the box closes and popover_close
// hands to placement, and the enter motion.
@(private)
Popover_Data :: struct {
	size:     ops.Size,
	was_open: bool,
	enter:    ui.Tween,
}

// Popover_Look is the surface's paint: the popover's own, or the teaching
// popover's larger corners.
@(private)
Popover_Look :: struct {
	id:       ops.Area_Id,
	data:     ^Popover_Data,
	open:     ^bool,
	fill:     ops.Color,
	radius:   f32,
	arrow:    f32, // 0 for none
	position: Popover_Position, // the side it opened on, which draws the arrow
	anchor:   ops.Size,
	align:    Popover_Align,
	alpha:    f32,
	name:     string,
	shift:    ops.Point, // how far placement moved the surface along its edge last frame
}

// POPOVER_SIDE is a position as the side ui.popup_open places on, and
// POPOVER_POSITION the way back.
@(private)
POPOVER_SIDE := [Popover_Position]ops.Side {
	.Above  = .Above,
	.Below  = .Below,
	.Before = .Before,
	.After  = .After,
}
@(private)
POPOVER_POSITION := [ops.Side]Popover_Position {
	.Above  = .Above,
	.Below  = .Below,
	.Before = .Before,
	.After  = .After,
}

@(private, thread_local)
current_popover: ^Popover

// popover_open shows the surface while open^, beside an anchor of the
// given size at the enclosing container's origin: above it by default,
// centred along that side or flush with its start, 4px away, or the
// arrow's height with the arrow. The surface is the appearance's
// background inside a 1px Transparent_Stroke border with
// borderRadiusMedium corners, padded 12, 16 or 20px by size, in body1,
// under shadow16's two layers. It fades in and slides 10px from its side
// over DURATION_SLOWER on CURVE_DECELERATE_MID; it closes at once, on a
// press outside, or on Escape once the surface has focus. Lay content
// out between open and close, or in the guard's body; popover_fg is the
// colour text inside should take.
//
// It is placed by ui.popup_open: flipped to the opposite side or shifted
// along the edge when the asked one would leave the window, the slide
// and the arrow following the side it opened on.
//
// After a shift along the edge the arrow still points at the anchor's
// centre (ui.placed reports the shift), clamped clear of the corners.
//
// Departures: focus is neither moved in nor trapped (jm:ui has no Tab traversal); hover-,
// context- and scroll-driven opening are not built; the arrow is not
// shadowed (ops.Shadow casts rounded rects only); the 4px gap without an arrow
// is the tooltip's, as the styles file gives none.
popover_open :: proc(
	gtx: ^ui.Ctx,
	open: ^bool,
	anchor: ops.Size,
	position := Popover_Position.Above,
	appearance := Popover_Appearance.Normal,
	size := Size.Medium,
	arrow := false,
	align := Popover_Align.Center,
	max_width: f32 = 0,
	name := "Popover",
	key: u64 = 0,
	loc := #caller_location,
) -> Popover {
	return surface_open(gtx, open, anchor, position, appearance, POPOVER_PAD[size], tok.BORDER_RADIUS_MEDIUM, arrow ? POPOVER_ARROW[size] : 0, align, 0, max_width, name, key, loc)
}

// surface_open is popover_open for any padding, radius and minimum
// width: the teaching popover's surface is the popover's with its own.
@(private)
surface_open :: proc(
	gtx: ^ui.Ctx,
	open: ^bool,
	anchor: ops.Size,
	position: Popover_Position,
	appearance: Popover_Appearance,
	pad, radius, arrow: f32,
	align: Popover_Align,
	min_width, max_width: f32,
	name: string,
	key: u64,
	loc: runtime.Source_Code_Location,
) -> (p: Popover) {
	id := ui.claim_id(gtx, key, loc)
	d := ui.widget_data(gtx, id, Popover_Data)
	if !open^ {
		d.was_open = false
		return
	}
	scrim_id := ui.id_mix(id, 0xffff)
	for e in ui.events(gtx, scrim_id) {
		if e.kind == .Press {
			open^ = false
		}
	}
	// Escape reaches the surface's id by key_interest below whether or
	// not the surface holds focus; paint_popover reads it too when it does.
	for e in ui.events(gtx, id) {
		if e.kind == .Key && e.key == .Escape {
			open^ = false
		}
	}
	if !open^ {
		d.was_open = false
		return
	}
	if !d.was_open {
		d.was_open = true
		d.enter = {to = 1, duration = tok.DURATION_SLOWER / 1000}
		d.size = {}
	}
	t := design.bezier_ease(tok.CURVE_DECELERATE_MID, ui.tween_update(&d.enter, gtx))
	alpha := t
	fill, fg: ops.Color
	switch appearance {
	case .Normal:
		fill, fg = color(.Neutral_Background1), color(.Neutral_Foreground1)
	case .Brand:
		fill, fg = color(.Brand_Background), color(.Neutral_Foreground_On_Brand)
	case .Inverted:
		fill, fg = color(.Neutral_Background_Static), color(.Neutral_Foreground_Static_Inverted)
	}
	gap := arrow > 0 ? arrow : POPOVER_GAP
	asked := POPOVER_SIDE[position]
	placed_side, shift := ui.placed(gtx, id, asked)
	side := POPOVER_POSITION[placed_side]
	// The slide comes from the anchor, on whichever side the surface opened.
	slide: ops.Point
	off := POPOVER_SLIDE * (1 - t)
	switch side {
	case .Above:
		slide = {0, off}
	case .Below:
		slide = {0, -off}
	case .Before:
		slide = {off, 0}
	case .After:
		slide = {-off, 0}
	}
	p.visible = true
	p.id = id
	p.open = open
	p.fg = fg
	p.appearance = appearance
	p.alpha = alpha
	// A surface with a minimum width is laid out at exactly that width, so
	// rows inside can push parts to the end (a flex row fills only a
	// bounded width); any other is its content's width, up to max_width.
	cs := ui.Constraints{max = {max_width > 0 ? max_width : ui.INF, ui.INF}}
	if min_width > 0 {
		cs = ui.exact({min_width, ui.INF})
		cs.min.y = 0
	}
	p.overlay = ui.popup_open(gtx, {0, 0, anchor.x, anchor.y}, id, asked, align == .Start ? .Start : .Center, gap, cs)
	ui.key_interest(gtx, id, .Escape)
	ops.input_area(gtx.scene, scrim_id, ops.Rect{-1e5, -1e5, 2e5, 2e5}, {.Press, .Release, .Move, .Enter, .Leave, .Scroll})
	if slide != {} {
		ops.transform_push(gtx.scene, ops.translate(slide.x, slide.y))
		p.slid = true
	}
	look := new(Popover_Look, gtx.allocator)
	look^ = {id, d, open, fill, radius, arrow, side, anchor, align, alpha, name, shift}
	p.look = look
	p.box = ui.box_open(gtx, {padding = ui.pad_all(pad + tok.STROKE_WIDTH_THIN), paint = paint_popover, user = look}, key = u64(ui.id_mix(id, 1)))
	// The content column fills the surface, so a fixed-width surface's
	// rows span it.
	p.col = ui.column_open(gtx, gap = tok.SPACING_VERTICAL_S, align = .Fill, key = u64(ui.id_mix(id, 2)))
	// A non-modal dialog named as its tag is: the page behind stays live.
	ui.container_semantics(gtx, {role = .Dialog, label = name})
	current_popover = ui.widget_data(gtx, id, Popover)
	current_popover^ = p
	return
}

// popover_close closes a popover opened by popover_open, whether it
// showed or not.
popover_close :: proc(p: ^Popover) {
	if !p.visible {
		return
	}
	ui.close(&p.col)
	ui.close(&p.box)
	// Closed by its content this frame: draw nothing and catch nothing,
	// or the scrim would take the next click.
	if p.slid {
		ops.transform_pop(p.overlay.gtx.scene)
	}
	p.overlay.discard = !p.open^
	ui.popup_close(&p.overlay, p.look.data.size)
	p.visible = false
	current_popover = nil
}

// popover is popover_open as a guard: `if fluent.popover(gtx, &open,
// anchor) { … }` lays the content out only while the surface shows and
// closes it at the end of the if (see ui/guards.odin).
@(deferred_in = popover_guard_close)
popover :: proc(
	gtx: ^ui.Ctx,
	open: ^bool,
	anchor: ops.Size,
	position := Popover_Position.Above,
	appearance := Popover_Appearance.Normal,
	size := Size.Medium,
	arrow := false,
	align := Popover_Align.Center,
	max_width: f32 = 0,
	name := "Popover",
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := popover_open(gtx, open, anchor, position, appearance, size, arrow, align, max_width, name, key, loc)
	return p.visible
}

@(private = "file")
popover_guard_close :: proc(
	gtx: ^ui.Ctx,
	open: ^bool,
	anchor: ops.Size,
	position: Popover_Position,
	appearance: Popover_Appearance,
	size: Size,
	arrow: bool,
	align: Popover_Align,
	max_width: f32,
	name: string,
	key: u64,
	loc: runtime.Source_Code_Location,
) {
	if current_popover != nil {
		popover_close(current_popover)
	}
}

// popover_fg is the open popover's text colour, faded with its enter
// motion; Neutral_Foreground1 outside one.
popover_fg :: proc() -> ops.Color {
	if current_popover != nil {
		return fade(current_popover.fg, current_popover.alpha)
	}
	return color(.Neutral_Foreground1)
}

// paint_popover paints the surface under its content: shadow16's
// geometry in the neutral shadow roles, the fill, the arrow, the border,
// and an input area that swallows presses on the surface and takes
// focus so Escape reaches it. It records the surface's size, which
// popover_close hands to placement.
@(private)
paint_popover :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, size: ops.Size, user: rawptr) {
	lk := (^Popover_Look)(user)
	lk.data.size = size
	area := ops.Rect{0, 0, size.x, size.y}
	rr := ops.Round_Rect{area, lk.radius}
	for e in ui.events(gtx, lk.id) {
		if e.kind == .Key && e.key == .Escape {
			lk.open^ = false
		}
	}
	for l in tok.SHADOW16.layers {
		design.paint_shadow_layer(gtx, rr, l.x, l.y, l.blur, fade(color(l.color), lk.alpha))
	}
	fill := fade(lk.fill, lk.alpha)
	ops.fill(gtx.scene, rr, fill)
	if lk.arrow > 0 {
		a := lk.arrow
		// Keep the arrow clear of the corners (the positioning engine is
		// told a 4px radius: popover.json layout arrow).
		// The arrow points at the anchor's centre: the surface starts flush
		// with the anchor or is centred on it, along the anchored side, then
		// placement may have shifted it by lk.shift, which the arrow undoes.
		arrow_at: f32
		if lk.position == .Above || lk.position == .Below {
			arrow_at = lk.anchor.x / 2 - (lk.align == .Start ? 0 : (lk.anchor.x - size.x) / 2) - lk.shift.x
		} else {
			arrow_at = lk.anchor.y / 2 - (lk.align == .Start ? 0 : (lk.anchor.y - size.y) / 2) - lk.shift.y
		}
		c: f32
		pts: [3]ops.Point
		switch lk.position {
		case .Above:
			c = clamp(arrow_at, a + 4, size.x - a - 4)
			pts = {{c - a, size.y}, {c + a, size.y}, {c, size.y + a}}
		case .Below:
			c = clamp(arrow_at, a + 4, size.x - a - 4)
			pts = {{c - a, 0}, {c + a, 0}, {c, -a}}
		case .Before:
			c = clamp(arrow_at, a + 4, size.y - a - 4)
			pts = {{size.x, c - a}, {size.x, c + a}, {size.x + a, c}}
		case .After:
			c = clamp(arrow_at, a + 4, size.y - a - 4)
			pts = {{0, c - a}, {0, c + a}, {-a, c}}
		}
		ops.fill(gtx.scene, ui.polygon(gtx, pts[:]), fill)
	}
	stroke_inside(gtx, rr, fade(color(.Transparent_Stroke), lk.alpha), tok.STROKE_WIDTH_THIN)
	ops.input_area(gtx.scene, lk.id, rr, {.Press, .Release, .Move, .Enter, .Leave, .Scroll, .Key, .Focus, .Blur})
	ops.tag(gtx.scene, lk.id, ui.frame_string(gtx, lk.name))
}

// popover_text is a paragraph inside a popover: body1 (or role) in the
// popover's text colour, wrapped to width when it is non-zero.
popover_text :: proc(gtx: ^ui.Ctx, s: string, role := Type_Role.Body1, width: f32 = 0, key: u64 = 0, loc := #caller_location) -> ui.Dims {
	return text_block(gtx, s, role, popover_fg(), width, key, loc = loc)
}

// Teaching popovers.

// TEACHING_* are the teaching popover's hard-coded metrics
// (teaching-popover.json layout: useTeachingPopoverSurfaceStyles.
// styles.ts:13-20, useTeachingPopoverBodyStyles.styles.ts:12-49,
// useTeachingPopoverFooterStyles.styles.ts:14-34,
// useTeachingPopoverCarouselNavButtonStyles.styles.ts:19-59).
@(private)
TEACHING_MIN_WIDTH :: f32(320)
@(private)
TEACHING_BODY_PAD :: f32(12)
@(private)
TEACHING_MEDIA_WIDTH :: f32(288)
@(private)
TEACHING_FOOTER_GAP :: f32(8)
@(private)
TEACHING_FOOTER_PAD :: f32(12)
@(private)
TEACHING_BUTTON_MIN :: f32(96)
@(private)
TEACHING_BUTTON_RADIUS :: f32(4)
@(private)
TEACHING_DOT :: f32(8)
@(private)
TEACHING_DOT_SELECTED :: f32(16)
@(private)
TEACHING_DOT_ALPHA :: f32(0.3)

// Teaching_Appearance is the teaching popover's surface: the popover's
// normal one, or brand.
Teaching_Appearance :: enum u8 {
	Normal,
	Brand,
}

// Teaching_Media is the body media's length: its height at the 288px
// body width.
Teaching_Media :: enum u8 {
	Short, // 117px
	Medium, // 176px
	Tall, // 288px, square
}

TEACHING_MEDIA_HEIGHT := [Teaching_Media]f32{.Short = 117, .Medium = 176, .Tall = 288}

// Footer_Layout is how the footer's buttons sit.
Footer_Layout :: enum u8 {
	Horizontal, // side by side at the end, each at least 96px
	Vertical, // stacked, auto width
}

// Teaching_Popover is an open teaching popover: the popover it is, and
// its appearance for the parts inside.
Teaching_Popover :: struct {
	using popover: Popover,
	brand:         bool,
}

@(private, thread_local)
current_teaching: ^Teaching_Popover

// teaching_popover_open is a popover for onboarding: the popover's
// surface padded spacingVerticalL on every side with borderRadiusXLarge
// corners, as wide as the 288px media plus that padding (the spec's
// minimum is 320px; a fixed width lets the footer spread, as jm:ui's
// rows fill only a bounded width), with the arrow by default, in the normal
// or brand appearance, opening below its anchor by default. Its parts
// are teaching_popover_header, teaching_popover_title,
// teaching_popover_body, teaching_popover_media, teaching_popover_footer
// and, for a paged one, teaching_popover_carousel_footer; lay them out
// between open and close in that order. Opening, dismissal and
// placement are popover_open's, with the same departures.
teaching_popover_open :: proc(
	gtx: ^ui.Ctx,
	open: ^bool,
	anchor: ops.Size,
	appearance := Teaching_Appearance.Normal,
	position := Popover_Position.Below,
	arrow := true,
	key: u64 = 0,
	loc := #caller_location,
) -> (tp: Teaching_Popover) {
	brand := appearance == .Brand
	tp.popover = surface_open(
		gtx,
		open,
		anchor,
		position,
		brand ? .Brand : .Normal,
		tok.SPACING_VERTICAL_L,
		tok.BORDER_RADIUS_XLARGE,
		arrow ? POPOVER_ARROW[.Medium] : 0,
		.Center,
		max(TEACHING_MIN_WIDTH, TEACHING_MEDIA_WIDTH + 2 * (tok.SPACING_VERTICAL_L + tok.STROKE_WIDTH_THIN)),
		0,
		"Teaching popover",
		key,
		loc,
	)
	tp.brand = brand
	if tp.visible {
		current_teaching = ui.widget_data(gtx, tp.id, Teaching_Popover)
		current_teaching^ = tp
	}
	return
}

// teaching_popover_close closes a teaching popover.
teaching_popover_close :: proc(tp: ^Teaching_Popover) {
	popover_close(&tp.popover)
	current_teaching = nil
}

// teaching_popover is teaching_popover_open as a guard.
@(deferred_in = teaching_popover_guard_close)
teaching_popover :: proc(
	gtx: ^ui.Ctx,
	open: ^bool,
	anchor: ops.Size,
	appearance := Teaching_Appearance.Normal,
	position := Popover_Position.Below,
	arrow := true,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	tp := teaching_popover_open(gtx, open, anchor, appearance, position, arrow, key, loc)
	return tp.visible
}

@(private = "file")
teaching_popover_guard_close :: proc(gtx: ^ui.Ctx, open: ^bool, anchor: ops.Size, appearance: Teaching_Appearance, position: Popover_Position, arrow: bool, key: u64, loc: runtime.Source_Code_Location) {
	if current_teaching != nil {
		teaching_popover_close(current_teaching)
	}
}

@(private)
is_teaching_brand :: proc() -> bool {
	return current_teaching != nil && current_teaching.brand
}

// teaching_dismiss is the transparent Dismiss icon button the header and
// title end with; its click closes the teaching popover
// (useTeachingPopoverHeaderStyles.styles.ts:31-51).
@(private)
teaching_dismiss :: proc(gtx: ^ui.Ctx, key: u64) {
	fg: State_Roles = is_teaching_brand() ? {.Neutral_Foreground_On_Brand, .Neutral_Foreground_On_Brand, .Neutral_Foreground_On_Brand, .Neutral_Foreground_Disabled} : {.Neutral_Foreground2, .Neutral_Foreground2_Brand_Hover, .Neutral_Foreground2_Brand_Pressed, .Neutral_Foreground_Disabled}
	roles := Button_Roles {
		bg     = {.Transparent_Background, .Transparent_Background_Hover, .Transparent_Background_Pressed, .Transparent_Background},
		border = {.Transparent_Stroke, .Transparent_Stroke, .Transparent_Stroke, .Transparent_Stroke},
		text   = fg,
		icon   = fg,
	}
	if roles_button(gtx, "", roles, ic = .Dismiss, name = "Dismiss", square = 20, key = key) {
		if current_teaching != nil {
			current_teaching.open^ = false
		}
	}
}

// teaching_popover_header is the header line: an optional 12px icon in
// Neutral_Foreground2, text in fontSizeBase200 semibold on a
// lineHeightBase200 line in Neutral_Foreground3, spacingVerticalXS below,
// and with dismiss the close button at the end (all on-brand in the
// brand appearance) (useTeachingPopoverHeaderStyles.styles.ts:15-74).
teaching_popover_header :: proc(gtx: ^ui.Ctx, text: string, ic := Icon.None, dismiss := true, key: u64 = 0, loc := #caller_location) {
	brand := is_teaching_brand()
	r := ui.row_open(gtx, gap = tok.SPACING_HORIZONTAL_XS, align = .Center, key = key, loc = loc)
	defer ui.close(&r)
	st := tok.Type_Style{weight = tok.FONT_WEIGHT_SEMIBOLD, size = tok.FONT_SIZE_BASE200, line_height = tok.LINE_HEIGHT_BASE200}
	if ic != .None {
		icon_widget(gtx, ic, tok.FONT_SIZE_BASE200, color(brand ? .Neutral_Foreground_On_Brand : .Neutral_Foreground2))
	}
	style_text(gtx, text, st, color(brand ? .Neutral_Foreground_On_Brand : .Neutral_Foreground3))
	if dismiss {
		ui.fill_space(gtx)
		teaching_dismiss(gtx, 1)
	}
}

// teaching_popover_title is the title: fontSizeBase400 semibold on a
// lineHeightBase400 line in Neutral_Foreground1 (on-brand in brand),
// with an optional dismiss at the end (useTeachingPopoverTitleStyles.
// styles.ts:14-48).
teaching_popover_title :: proc(gtx: ^ui.Ctx, text: string, dismiss := false, key: u64 = 0, loc := #caller_location) {
	brand := is_teaching_brand()
	if current_teaching != nil {
		// The title names the popover's column, by its handle.
		ui.container_semantics(gtx, {role = .Dialog, label = text}, current_teaching.col.index)
	}
	r := ui.row_open(gtx, align = .Start, key = key, loc = loc)
	defer ui.close(&r)
	st := tok.Type_Style{weight = tok.FONT_WEIGHT_SEMIBOLD, size = tok.FONT_SIZE_BASE400, line_height = tok.LINE_HEIGHT_BASE400}
	style_text(gtx, text, st, color(brand ? .Neutral_Foreground_On_Brand : .Neutral_Foreground1), heading = true)
	if dismiss {
		ui.fill_space(gtx)
		teaching_dismiss(gtx, 2)
	}
}

// teaching_popover_body is the body's text: body1 wrapped to the media
// width (288px), 12px of space below (useTeachingPopoverBodyStyles.
// styles.ts:12-20).
teaching_popover_body :: proc(gtx: ^ui.Ctx, text: string, key: u64 = 0, loc := #caller_location) {
	col := ui.column_open(gtx, key = key, loc = loc)
	defer ui.close(&col)
	popover_text(gtx, text, .Body1, TEACHING_MEDIA_WIDTH)
	ui.spacer(gtx, TEACHING_BODY_PAD)
}

// teaching_popover_media is the body's media frame: 288px wide at the
// length's height, clipped, 12px above the text. jm:ui draws no bitmaps,
// so paint draws its content into the frame's rect; without paint the
// frame is a Neutral_Stencil1 placeholder with the Image icon
// (a departure from teaching-popover.json layout body).
teaching_popover_media :: proc(gtx: ^ui.Ctx, length := Teaching_Media.Medium, paint: proc(gtx: ^ui.Ctx, r: ops.Rect) = nil, key: u64 = 0, loc := #caller_location) {
	p := ui.widget_open(gtx, key, loc)
	sz := ops.Size{TEACHING_MEDIA_WIDTH, TEACHING_MEDIA_HEIGHT[length]}
	r := ops.Rect{0, 0, sz.x, sz.y}
	ops.clip_push(gtx.scene, r)
	if paint != nil {
		paint(gtx, r)
	} else {
		ops.fill(gtx.scene, r, color(.Neutral_Stencil1))
		icon(gtx, .Image, {(sz.x - 32) / 2, (sz.y - 32) / 2}, 32, color(.Neutral_Foreground3))
	}
	ops.clip_pop(gtx.scene)
	ui.semantics(gtx, &p, {role = .Image})
	ui.widget_close(gtx, &p, {size = {sz.x, sz.y + TEACHING_BODY_PAD}})
}

// teaching_primary_roles and teaching_secondary_roles are the footer's
// buttons: the button's primary and secondary appearances, or in brand
// the primary inverted to an on-brand fill with Brand_Foreground1 text
// stepping through Compound_Brand_Foreground1's Hover and Pressed, and the
// secondary a brand fill stepping its Hover and Pressed with an on-brand
// border (teaching-popover.json variants appearance brand, states
// hovered).
@(private)
teaching_primary_roles :: proc(brand: bool) -> Button_Roles {
	if !brand {
		return appearance_roles(.Primary)
	}
	on := State_Roles{.Neutral_Foreground_On_Brand, .Neutral_Foreground_On_Brand, .Neutral_Foreground_On_Brand, .Neutral_Background_Disabled}
	fg := State_Roles{.Brand_Foreground1, .Compound_Brand_Foreground1_Hover, .Compound_Brand_Foreground1_Pressed, .Neutral_Foreground_Disabled}
	return {bg = on, border = {.Transparent_Stroke, .Transparent_Stroke, .Transparent_Stroke, .Transparent_Stroke}, text = fg, icon = fg}
}

@(private)
teaching_secondary_roles :: proc(brand: bool) -> Button_Roles {
	if !brand {
		return appearance_roles(.Secondary)
	}
	fg := State_Roles{.Neutral_Foreground_On_Brand, .Neutral_Foreground_On_Brand, .Neutral_Foreground_On_Brand, .Neutral_Foreground_Disabled}
	return {
		bg = {.Brand_Background, .Brand_Background_Hover, .Brand_Background_Pressed, .Neutral_Background_Disabled},
		border = fg,
		text = fg,
		icon = fg,
	}
}

// teaching_popover_footer is the footer: 12px above, the buttons 8px
// apart, a row at the end with each at least 96px wide or a column of
// auto width, 4px corners (useTeachingPopoverFooterStyles.styles.ts:
// 14-34). secondary, when given, also closes the popover. Returns which
// was clicked.
teaching_popover_footer :: proc(gtx: ^ui.Ctx, primary: string, secondary := "", layout := Footer_Layout.Horizontal, key: u64 = 0, loc := #caller_location) -> (primary_clicked, secondary_clicked: bool) {
	brand := is_teaching_brand()
	col := ui.column_open(gtx, key = key, loc = loc)
	defer ui.close(&col)
	ui.spacer(gtx, TEACHING_FOOTER_PAD)
	min_w: f32 = layout == .Horizontal ? TEACHING_BUTTON_MIN : 0
	if layout == .Horizontal {
		r := ui.row_open(gtx, gap = TEACHING_FOOTER_GAP)
		defer ui.close(&r)
		ui.fill_space(gtx)
		if secondary != "" {
			secondary_clicked = roles_button(gtx, secondary, teaching_secondary_roles(brand), min_width = min_w, key = 1)
		}
		primary_clicked = roles_button(gtx, primary, teaching_primary_roles(brand), min_width = min_w, key = 2)
	} else {
		c := ui.column_open(gtx, gap = TEACHING_FOOTER_GAP, align = .Fill)
		defer ui.close(&c)
		primary_clicked = roles_button(gtx, primary, teaching_primary_roles(brand), key = 2)
		if secondary != "" {
			secondary_clicked = roles_button(gtx, secondary, teaching_secondary_roles(brand), key = 1)
		}
	}
	if secondary_clicked && current_teaching != nil {
		current_teaching.open^ = false
	}
	return
}

// Carousel_Footer_Layout is how a paged teaching popover's footer spreads:
// centered puts previous, the page count and next apart across the row;
// offset puts the count at the start and both buttons at the end
// (useTeachingPopoverCarouselFooterStyles.styles.ts:17-32).
Carousel_Footer_Layout :: enum u8 {
	Centered,
	Offset,
}

// teaching_popover_carousel_footer is a paged teaching popover's nav and
// footer: the nav dots centred on their own row, then 12px below a row
// 8px apart of the previous button (initial_text on the first page,
// which dismisses), the page count ("2 of 4", caption1) and the next
// button (final_text on the last page, which finishes and closes), the
// buttons at least 96px wide. The dots are 8px, round, in
// Brand_Background at 30% (on-brand in brand), the selected one a 16px
// bar with 4px corners at full strength; a click on one, or the
// buttons, moves page^, and Left and Right on a focused dot move it too.
// Returns whether next finished on the last page. There is no page
// motion (teaching-popover.json behaviour no-page-motion).
teaching_popover_carousel_footer :: proc(
	gtx: ^ui.Ctx,
	page: ^int,
	count: int,
	initial_text := "Not now",
	final_text := "Finish",
	next_text := "Next",
	previous_text := "Previous",
	layout := Carousel_Footer_Layout.Centered,
	key: u64 = 0,
	loc := #caller_location,
) -> (finished: bool) {
	brand := is_teaching_brand()
	page^ = clamp(page^, 0, max(count - 1, 0))
	col := ui.column_open(gtx, key = key, loc = loc)
	defer ui.close(&col)
	{
		nav := ui.row_open(gtx, key = 9)
		ui.fill_space(gtx)
		teaching_dots(gtx, page, count, brand, 10)
		ui.fill_space(gtx)
		ui.close(&nav)
	}
	ui.spacer(gtx, TEACHING_FOOTER_PAD)
	r := ui.row_open(gtx, gap = TEACHING_FOOTER_GAP, align = .Center)
	defer ui.close(&r)
	first, last := page^ == 0, page^ == count - 1
	prev_label := first ? initial_text : previous_text
	next_label := last ? final_text : next_text
	back := false
	if layout == .Offset {
		teaching_popover_page_count(gtx, page^, count, key = 11)
		ui.fill_space(gtx)
		back = roles_button(gtx, prev_label, teaching_secondary_roles(brand), min_width = TEACHING_BUTTON_MIN, key = 1)
	} else {
		back = roles_button(gtx, prev_label, teaching_secondary_roles(brand), min_width = TEACHING_BUTTON_MIN, key = 1)
		ui.fill_space(gtx)
		teaching_popover_page_count(gtx, page^, count, key = 11)
		ui.fill_space(gtx)
	}
	if back {
		if first {
			if current_teaching != nil {
				current_teaching.open^ = false
			}
		} else {
			page^ -= 1
		}
	}
	if roles_button(gtx, next_label, teaching_primary_roles(brand), min_width = TEACHING_BUTTON_MIN, key = 2) {
		if last {
			finished = true
			if current_teaching != nil {
				current_teaching.open^ = false
			}
		} else {
			page^ += 1
		}
	}
	return
}

// teaching_popover_page_count is the "n of m" text, caption1 in the
// popover's text colour, centred in its box
// (useTeachingPopoverCarouselPageCountStyles.styles.ts:17-23).
teaching_popover_page_count :: proc(gtx: ^ui.Ctx, page, count: int, key: u64 = 0, loc := #caller_location) {
	text_block(gtx, fmt_of(gtx, page + 1, count), .Caption1, popover_fg(), key = key, loc = loc)
}

// teaching_dots is the nav: one dot per page, spacingHorizontalXS apart.
@(private)
teaching_dots :: proc(gtx: ^ui.Ctx, page: ^int, count: int, brand: bool, key: u64) {
	r := ui.row_open(gtx, gap = tok.SPACING_HORIZONTAL_XS, align = .Center, key = key)
	defer ui.close(&r)
	ui.container_semantics(gtx, {role = .Tab_List})
	for i in 0 ..< count {
		if nav_dot(gtx, i == page^, brand ? .Neutral_Foreground_On_Brand : .Brand_Background, TEACHING_DOT_ALPHA, 1, TEACHING_DOT, TEACHING_DOT_SELECTED, 0, fmt_page(gtx, i, count), page, count, key = u64(i + 1)) {
			page^ = i
		}
	}
}

// fmt_of is "a of b" in frame memory.
@(private)
fmt_of :: proc(gtx: ^ui.Ctx, a, b: int) -> string {
	return ui.frame_string(gtx, tprint_of(a, b))
}

// Info labels.

// INFO_* are the info button's hard-coded metrics (info-label.json
// layout: useInfoButtonStyles.styles.ts:20-36,94-133).
@(private)
INFO_ICON := [Size]f32{.Small = 12, .Medium = 16, .Large = 20}
@(private)
INFO_MAX_WIDTH :: f32(264)

// Info_Data is an info label's popover state when the caller keeps none.
@(private)
Info_Data :: struct {
	open: bool,
}

// info_label is a Label followed by an information button that opens a
// popover of info: label's text in size, weight and required, then the
// button, transparent with a Neutral_Foreground2 Info icon of 12, 16 or
// 20px, padded spacingVerticalXS by spacingHorizontalXS
// (spacingVerticalXXS at large) with borderRadiusMedium corners. Hovered
// it reads Transparent_Background_Hover with the icon in
// Neutral_Foreground2_Brand_Hover and filled, pressed the Pressed pair,
// and while the popover is open the Selected pair with the filled icon;
// nothing transitions. A click, Enter or Space toggles the popover,
// which opens above the button's start with the arrow, at most 264px
// wide, caption1 (body1 at large) at the popover's small size (medium at
// large). open, when given, is the caller's; else the label keeps its
// own. Returns whether the popover is open.
info_label :: proc(
	gtx: ^ui.Ctx,
	text: string,
	info: string,
	size := Size.Medium,
	weight := Weight.Regular,
	required := false,
	open: ^bool = nil,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	// The label's parts share one call site here, so each takes a key
	// derived from the label's own id.
	own := ui.claim_id(gtx, key, loc)
	o := open
	if o == nil {
		o = &ui.widget_data(gtx, own, Info_Data).open
	}
	r := ui.row_open(gtx, gap = tok.SPACING_HORIZONTAL_XXS, align = .Start, key = u64(ui.id_mix(own, 5)), loc = loc)
	defer ui.close(&r)
	label(gtx, text, required, size, weight, key = u64(ui.id_mix(own, 1)))
	st := ui.stack_open(gtx, key = u64(ui.id_mix(own, 2)))
	defer ui.close(&st)
	bsize := info_button(gtx, o, size, state, ui.frame_string(gtx, text), u64(ui.id_mix(own, 3)))
	large := size == .Large
	if popover(gtx, o, bsize, .Above, .Normal, large ? .Medium : .Small, true, .Start, INFO_MAX_WIDTH, "Information", key = u64(ui.id_mix(own, 4))) {
		popover_text(gtx, info, large ? .Body1 : .Caption1, INFO_MAX_WIDTH - 2 * (POPOVER_PAD[large ? .Medium : .Small] + tok.STROKE_WIDTH_THIN))
	}
	return o^
}

// info_button is the info label's button; it toggles open^ and returns
// its size, the popover's anchor.
@(private)
info_button :: proc(gtx: ^ui.Ctx, open: ^bool, size: Size, state: Interaction, owner: string, key: u64, loc := #caller_location) -> ops.Size {
	p := ui.widget_open(gtx, key, loc)
	isz := INFO_ICON[size]
	pad := size == .Large ? ops.Point{tok.SPACING_VERTICAL_XXS, tok.SPACING_VERTICAL_XXS} : ops.Point{tok.SPACING_HORIZONTAL_XS, tok.SPACING_VERTICAL_XS}
	sz := ops.Size{isz + 2 * pad.x, isz + 2 * pad.y}
	area := ops.Rect{0, 0, sz.x, sz.y}
	c := control(gtx, p.id, area, state)
	if c.clicked {
		open^ = !open^
	}
	sel := open^ && !c.disabled
	bg := color_for({sel ? .Transparent_Background_Selected : .Transparent_Background, .Transparent_Background_Hover, .Transparent_Background_Pressed, .Transparent_Background}, c)
	fg := color_for({sel ? .Neutral_Foreground2_Brand_Selected : .Neutral_Foreground2, .Neutral_Foreground2_Brand_Hover, .Neutral_Foreground2_Brand_Pressed, .Neutral_Foreground_Disabled}, c)
	ic := Icon.Info
	if (c.hovered || sel) && !c.disabled {
		ic = .Info_Filled
	}
	rr := ops.Round_Rect{area, tok.BORDER_RADIUS_MEDIUM}
	if ui.painted(bg) {
		ops.fill(gtx.scene, rr, bg)
	}
	icon(gtx, ic, {pad.x, pad.y}, isz, fg)
	paint_focus_outline(gtx, c, rr)
	listen(gtx, c.st, p.id, area)
	said := ui.frame_string(gtx, tprint_info(owner))
	ops.tag(gtx.scene, p.id, said)
	ui.semantics(gtx, &p, {role = .Button, label = said, states = ops.States{.Expandable} + state_if(open^, {.Expanded}) + state_if(c.disabled, {.Disabled})})
	// Pulled up and down by spacingVerticalXXS so it does not stretch the
	// line (useInfoLabelStyles.styles.ts:14-36): laid out that much shorter.
	ui.widget_close(gtx, &p, {size = sz})
	return sz
}

// Shared small widgets.

// Glyph is a mark roles_button can draw that the icon set lacks: the
// carousel's autoplay play and pause.
@(private)
Glyph :: enum u8 {
	None,
	Play,
	Pause,
}

// paint_glyph draws g centred in a size px square at pos.
@(private)
paint_glyph :: proc(gtx: ^ui.Ctx, g: Glyph, pos: ops.Point, size: f32, fg: ops.Color) {
	u := size / 20
	switch g {
	case .None:
	case .Play:
		pts := [3]ops.Point{pos + {6 * u, 4 * u}, pos + {16 * u, 10 * u}, pos + {6 * u, 16 * u}}
		ops.fill(gtx.scene, ui.polygon(gtx, pts[:]), fg)
	case .Pause:
		ops.fill(gtx.scene, ops.Round_Rect{{pos.x + 5 * u, pos.y + 4 * u, 3.5 * u, 12 * u}, u}, fg)
		ops.fill(gtx.scene, ops.Round_Rect{{pos.x + 11.5 * u, pos.y + 4 * u, 3.5 * u, 12 * u}, u}, fg)
	}
}

// roles_button is a medium button in explicit roles: the teaching
// popover's footer and dismiss, a carousel's buttons. It lays out and
// behaves as button does (button.odin) — the size's padding, min width,
// semibold label, colours blended between states, the inset focus ring —
// but reads roles instead of an appearance. square, when non-zero, makes
// it an icon-only square of that side. radius is its corners.
@(private)
roles_button :: proc(
	gtx: ^ui.Ctx,
	label: string,
	roles: Button_Roles,
	ic := Icon.None,
	name := "",
	min_width: f32 = 0,
	square: f32 = 0,
	radius: f32 = TEACHING_BUTTON_RADIUS,
	glyph := Glyph.None,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_open(gtx, key, loc)
	mt := button_metrics(.Medium)
	t := shape_style(gtx, label, mt.style)
	border := tok.STROKE_WIDTH_THIN
	sz: ops.Size
	if square > 0 {
		sz = {square, square}
	} else {
		w := mt.pad_h * 2 + t.width + 2 * border
		if ic != .None {
			w += mt.icon + mt.gap
		}
		sz = {max(w, min_width), mt.height}
	}
	sz = ui.constrain_min(gtx.constraints, sz)
	area := ops.Rect{0, 0, sz.x, sz.y}
	c := control(gtx, p.id, area, state)
	k := corners_all(min(radius, min(sz.x, sz.y) / 2))
	path := rounded(gtx, area, k)
	bg := blend(gtx, c, 0, color_for(roles.bg, c))
	stroke := blend(gtx, c, 1, c.focus_visible && !c.disabled ? color(.Stroke_Focus2) : color_for(roles.border, c))
	fg := blend(gtx, c, 2, color_for(roles.text, c))
	icon_fg := blend(gtx, c, 3, color_for(roles.icon, c))
	if ui.painted(bg) {
		ops.fill(gtx.scene, path, bg)
	}
	if ui.painted(stroke) {
		stroke_inside_corners(gtx, area, k, stroke, border)
	}
	isz: f32 = square > 0 ? min(20, square - 4) : mt.icon
	if label == "" {
		icon(gtx, ic, {(sz.x - isz) / 2, (sz.y - isz) / 2}, isz, icon_fg)
		paint_glyph(gtx, glyph, {(sz.x - isz) / 2, (sz.y - isz) / 2}, isz, icon_fg)
	} else {
		x := (sz.x - t.width - (ic != .None ? mt.icon + mt.gap : 0)) / 2
		if ic != .None {
			icon(gtx, ic, {x, (sz.y - mt.icon) / 2}, mt.icon, icon_fg)
			x += mt.icon + mt.gap
		}
		draw_text(gtx, t, {x, (sz.y - t.height) / 2}, fg)
	}
	paint_focus_inset(gtx, c, area, k, border, paint_border = false)
	listen(gtx, c.st, p.id, area)
	said := ui.frame_string(gtx, label != "" ? label : name)
	ops.tag(gtx.scene, p.id, said)
	ui.semantics(gtx, &p, {role = .Button, label = said, states = state_if(c.disabled, {.Disabled})})
	ui.widget_close(gtx, &p, {sz, (sz.y - t.height) / 2 + baseline_of(t)})
	return c.clicked
}

// nav_dot is one page dot, a button of the glyph plus pad on each side:
// the glyph dot px round (selected_w wide with 4px corners when
// selected) in role at rest_alpha unselected and full when selected,
// the hover and press alphas following the carousel's table when
// hover_alpha is non-zero. A focused dot takes Left and Right to move
// page^ through count. Returns true when clicked.
@(private)
nav_dot :: proc(
	gtx: ^ui.Ctx,
	selected: bool,
	role: tok.Role,
	rest_alpha, hover_alpha: f32,
	dot, selected_w, pad: f32,
	name: string,
	page: ^int,
	count: int,
	pressed_alpha: f32 = 1,
	brand_selected := false,
	selected_pad_x: f32 = -1,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_open(gtx, key, loc)
	gw := selected ? selected_w : dot
	px := selected && selected_pad_x >= 0 ? selected_pad_x : pad
	sz := ops.Size{gw + 2 * px, dot + 2 * pad}
	area := ops.Rect{0, 0, sz.x, sz.y}
	c := control(gtx, p.id, area, .Live)
	if c.st != nil && c.focused {
		for e in ui.events(gtx, p.id) {
			if e.kind == .Key {
				#partial switch e.key {
				case .Left:
					page^ = max(page^ - 1, 0)
				case .Right:
					page^ = min(page^ + 1, count - 1)
				}
			}
		}
	}
	a := selected ? f32(1) : rest_alpha
	if hover_alpha > 0 {
		switch {
		case c.pressed:
			a = selected ? 0.65 : pressed_alpha
		case c.hovered:
			a = hover_alpha
		}
	}
	col := color(role)
	if selected && brand_selected {
		col = color_for({.Compound_Brand_Background, .Compound_Brand_Background_Hover, .Compound_Brand_Background_Pressed, .Compound_Brand_Background}, c)
		a = 1
	}
	g := ops.Round_Rect{{px, pad, gw, dot}, dot / 2}
	ops.fill(gtx.scene, g, fade(col, a))
	paint_focus_outline(gtx, c, {area, tok.BORDER_RADIUS_MEDIUM})
	listen(gtx, c.st, p.id, area)
	ops.tag(gtx.scene, p.id, name)
	ui.semantics(gtx, &p, {role = .Tab, label = name, states = state_if(selected, {.Selected})})
	ui.widget_close(gtx, &p, {size = sz})
	return c.clicked
}

// icon_widget is an icon laid out as a widget of its own size.
@(private)
icon_widget :: proc(gtx: ^ui.Ctx, ic: Icon, size: f32, fg: ops.Color, loc := #caller_location) {
	p := ui.widget_open(gtx, 0, loc)
	icon(gtx, ic, {}, size, fg)
	ui.widget_close(gtx, &p, {size = {size, size}})
}

// style_text is one line of s at a style, as a widget, tagged with s.
@(private)
style_text :: proc(gtx: ^ui.Ctx, s: string, st: tok.Type_Style, fg: ops.Color, heading := false, loc := #caller_location) {
	p := ui.widget_open(gtx, 0, loc)
	t := shape_style(gtx, s, st)
	draw_text(gtx, t, {}, fg)
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, s))
	ui.semantics(gtx, &p, {role = heading ? .Heading : .Text, label = s})
	ui.widget_close(gtx, &p, {{t.width, t.height}, baseline_of(t)})
}

// tprint_of, tprint_info and fmt_page build the small strings the
// popovers show and tag; the caller copies them into frame memory.
@(private)
tprint_of :: proc(a, b: int) -> string {
	return fmt.tprintf("%d of %d", a, b)
}

@(private)
tprint_info :: proc(owner: string) -> string {
	return fmt.tprintf("Information: %s", owner)
}

@(private)
fmt_page :: proc(gtx: ^ui.Ctx, i, count: int) -> string {
	return ui.frame_string(gtx, fmt.tprintf("Page %d of %d", i + 1, count))
}
