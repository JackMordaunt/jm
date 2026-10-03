package primer

import "base:runtime"
import "jm:ui"
import "jm:ui/design"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// The floating surfaces: Overlay, AnchoredOverlay, Popover, Tooltip and
// Details (primer-kit components/overlay.json, anchored-overlay.json,
// popover.json, tooltip.json, details.json; dialog.odin has the dialogs).
// An overlay draws in a layer of its own above the page (ui.overlay_open
// or ui.popup_place), so it takes no space where it is called and no clip
// from the containers around it; layers stack in the order they are
// drawn, the last on top, as Primer's portal layers do (Portal.tsx:70-104).
//
// Dismissal is jm:ui's overlay stack, which is that order: Escape reaches
// only the top-most overlay (a topmost ui.key_interest), and a primary
// press walks the overlays from the top, closing each it lands outside,
// until one holds it (ops.Event_Kind.Outside); the press still lands
// (useOnEscapePress.ts:7-15,53-80; useOnOutsideClick.tsx:44-83). Focus
// moves into an overlay as it opens (ui.focus_first) and back as it
// closes; an anchored overlay and a dialog also trap it (a trapping
// ui.focus_scope_open), a newer trap suspending an older.
//
// Every overlay is controlled through open, as jm:ui's widgets are: it
// closes itself on its own dismiss gestures and names the gesture in its
// handle's dismissed, where Primer calls onEscape or onClose and leaves
// the closing to the caller. Call its open proc every frame, open or not,
// so it can hand focus back on the frame it closes.

// Dismissal is the gesture that closed an overlay, on the frame it did.
Dismissal :: enum u8 {
	None,
	Escape, // Escape while it was the top-most overlay; a dialog's backdrop click reports this too (Dialog.tsx:306-316)
	Click_Outside, // a primary press outside it and its anchor
	Close_Button, // the close button it drew
}

// Anchor_Side is the edge of the anchor an anchored overlay attaches to
// (anchored-overlay.json side): outside it, or inside its box against
// that edge; Inside_Center centres it across the anchor.
Anchor_Side :: enum u8 {
	Outside_Bottom,
	Outside_Top,
	Outside_Left,
	Outside_Right,
	Inside_Top,
	Inside_Bottom,
	Inside_Left,
	Inside_Right,
	Inside_Center,
}

// Anchor_Align is where an anchored overlay sits along its anchor's edge.
Anchor_Align :: enum u8 {
	Start,
	Center,
	End,
}

// Overlay_Width is Overlay's width step: hug content, or 256, 320, 480,
// 640 or 960px (Overlay.module.css:148-169; Overlay/constants.ts:12-19).
// The names mean other widths in Popover and Dialog.
Overlay_Width :: enum u8 {
	Auto,
	Small,
	Medium,
	Large,
	XLarge,
	XXLarge,
}

// Overlay_Height is Overlay's height step: hug content, or 192, 256,
// 320, 432 or 600px (Overlay.module.css:75-102).
Overlay_Height :: enum u8 {
	Auto,
	XSmall,
	Small,
	Medium,
	Large,
	XLarge,
}

@(private)
OVERLAY_WIDTHS := [Overlay_Width]f32 {
	.Auto    = 0,
	.Small   = 256,
	.Medium  = 320,
	.Large   = 480,
	.XLarge  = 640,
	.XXLarge = 960,
}

@(private)
OVERLAY_HEIGHTS := [Overlay_Height]f32 {
	.Auto   = 0,
	.XSmall = 192,
	.Small  = 256,
	.Medium = 320,
	.Large  = 432,
	.XLarge = 600,
}

// OVERLAY_MIN_WIDTH and OVERLAY_VIEWPORT_INSET bound an auto-width
// overlay: at least 192px, at most the viewport less 2rem
// (Overlay.module.css:13-15).
OVERLAY_MIN_WIDTH :: f32(192)
OVERLAY_VIEWPORT_INSET :: f32(32)

// OVERLAY_ENTER is the entry every overlay plays: 200ms on
// cubic-bezier(0.33, 1, 0.68, 1), a fade (Overlay.module.css:1-9,234-238)
// and, from a known side, an 8px slide (Overlay.tsx:25,178-179,198-212).
// Neither is a token. There is no exit motion.
OVERLAY_ENTER :: tok.Transition{200, {0.33, 1, 0.68, 1}}
OVERLAY_SLIDE :: f32(8)

// NARROW_WIDTH is where the narrow viewport range ends: below it a
// fullscreen variant covers the window (--viewportRange-narrow, max-width
// 767.98px; Overlay.module.css:203-224).
NARROW_WIDTH :: tok.BREAKPOINT_MEDIUM

// Overlay_Focus is how an overlay moves focus: to initial on open (an
// area's id), else to its first focusable area unless prevent; back to
// return_to on close, else to what had focus when it opened
// (useOpenAndCloseFocus.ts:18-35).
Overlay_Focus :: struct {
	initial:   ops.Area_Id,
	return_to: ops.Area_Id,
	prevent:   bool,
}

// Overlay_Data is what an overlay keeps between frames.
@(private)
Overlay_Data :: struct {
	was_open:  bool,
	fade:      ui.Tween,
	slide:     ui.Tween,
	side:      Anchor_Side, // the side the slide last came from
	return_to: ops.Area_Id,
	size:      ops.Size, // the surface's size, as its paint saw it this frame
	body:      ops.Size, // a dialog's footer height last frame, in y
}

// Surface is an open overlay surface: the layer, the box that paints it
// and the scroll that holds its content, and what was pushed around them.
@(private)
Surface :: struct {
	gtx:    ^ui.Ctx,
	layer:  ui.Overlay,
	sized:  ui.Inset,
	box:    ui.Box,
	scroll: ui.Scroll_Box,
	look:   ^Surface_Look,
	slid:   bool,
	faded:  bool,
	scoped: bool,
}

// Surface_Look is how a surface paints itself, read by paint_surface as
// its box closes.
@(private)
Surface_Look :: struct {
	id:     ops.Area_Id, // the overlay's: its Outside area
	data:   ^Overlay_Data,
	radius: Corners,
	fill:   tok.Role,
	shadow: bool,
	name:   string, // tags the surface for probes, when set
}

// Surface_Spec is what a surface is opened with.
@(private)
Surface_Spec :: struct {
	limits: ui.Size_Limits,
	radius: Corners,
	slide:  ops.Point, // where it slides from, in px, at the start
	trap:   bool,
	scroll: bool, // its content scrolls inside it, hugging up to its height
	offset: ^ui.Scroll_Offset, // where that scroll is kept, when its owner moves it; nil keeps it in the box
	name:   string,
}

// overlay_events reads the dismiss gestures sent to an overlay's id:
// Escape, and a primary press outside. A gesture closes open.
@(private)
overlay_events :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, open: ^bool) -> (g: Dismissal) {
	for e in ui.events(gtx, id) {
		#partial switch e.kind {
		case .Key:
			if e.key == .Escape {
				g = .Escape
			}
		case .Outside:
			// Secondary and middle buttons never dismiss (useOnOutsideClick.tsx:44-50).
			if e.button == .Left && g == .None {
				g = .Click_Outside
			}
		}
	}
	if g != .None {
		open^ = false
	}
	return
}

// overlay_focus runs an overlay's focus across a frame: on the frame it
// opens it remembers where focus goes back to and asks for its initial
// focus; on the frame it closes it gives focus back. It reports whether
// the overlay shows.
// first names the focus scope whose first area takes focus, the
// overlay's own (id) by default.
@(private)
overlay_focus :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, d: ^Overlay_Data, open: bool, f: Overlay_Focus, first: ops.Area_Id = 0) -> bool {
	if !open {
		if d.was_open && d.return_to != 0 {
			ui.focus_request(gtx, d.return_to)
		}
		d.was_open = false
		return false
	}
	if !d.was_open {
		d.was_open = true
		d.fade = {to = 1, duration = OVERLAY_ENTER.duration / 1000}
		d.slide = {to = 1, duration = OVERLAY_ENTER.duration / 1000}
		d.return_to = f.return_to if f.return_to != 0 else ui.focused(gtx)
		if f.initial != 0 {
			ui.focus_request(gtx, f.initial)
		} else if !f.prevent {
			ui.focus_first(gtx, first if first != 0 else id)
		}
	}
	return true
}

// surface_open opens a surface in layer, which the caller has just
// opened: a focus scope named id, Escape for id, the fade and slide, and
// the sized box that paints the surface, its content in a scroll that
// hugs it up to the box's height. Close it with surface_close.
@(private)
surface_open :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, d: ^Overlay_Data, layer: ui.Overlay, spec: Surface_Spec) -> (s: Surface) {
	s.gtx = gtx
	s.layer = layer
	ui.focus_scope_open(gtx, id, spec.trap)
	s.scoped = true
	ui.key_interest(gtx, id, .Escape, topmost = true)
	// Reduced motion skips the fade; the slide is a script animation
	// Primer does not gate, so it still runs (Overlay.module.css:234-238).
	alpha := bezier_ease(OVERLAY_ENTER.easing, ui.tween_update(&d.fade, gtx))
	if alpha < 1 && !gtx.reduce_motion {
		ops.opacity_push(gtx.scene, alpha)
		s.faded = true
	}
	if spec.slide != {} {
		k := 1 - bezier_ease(OVERLAY_ENTER.easing, ui.tween_update(&d.slide, gtx))
		if k > 0 {
			ops.transform_push(gtx.scene, ops.translate(spec.slide.x * k, spec.slide.y * k))
			s.slid = true
		}
	}
	look := new(Surface_Look, gtx.allocator)
	look^ = {id, d, spec.radius, .Overlay_Bg_Color, true, ui.frame_string(gtx, spec.name)}
	s.look = look
	s.sized = ui.sized_open(gtx, spec.limits, key = u64(ui.id_mix(id, 2)))
	s.box = ui.box_open(gtx, {paint = paint_surface, user = look}, key = u64(ui.id_mix(id, 3)))
	if spec.scroll {
		s.scroll = ui.scroll_box_open(gtx, key = u64(ui.id_mix(id, 4)), offset = spec.offset, fit = true)
	}
	return
}

// surface_close closes what surface_open opened and schedules the layer:
// placed by its placement when it is a popup, at the surface's size.
@(private)
surface_close :: proc(s: ^Surface, discard: bool) {
	gtx := s.gtx
	if s.scroll.gtx != nil {
		ui.close(&s.scroll)
	}
	ui.close(&s.box)
	ui.close(&s.sized)
	if s.slid {
		ops.transform_pop(gtx.scene)
	}
	if s.faded {
		ops.opacity_pop(gtx.scene)
	}
	if s.scoped {
		ui.focus_scope_close(gtx)
	}
	s.layer.discard = discard
	if s.layer.place.set {
		ui.popup_close(&s.layer, s.look.data.size)
	} else {
		ui.overlay_close(&s.layer)
	}
}

// paint_surface paints an overlay's surface at size: --shadow-floating-
// small (whose first layer is a 1px ring standing in for a border,
// overlay.json anatomy) under
// the fill, then an area that keeps presses and hover from what lies
// under it and the area that counts presses on it as inside. The body
// draws over both.
@(private)
paint_surface :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, size: ops.Size, user: rawptr) {
	look := (^Surface_Look)(user)
	look.data.size = size
	area := ops.Rect{0, 0, size.x, size.y}
	shape := surface_shape(gtx, area, look.radius)
	if look.shadow {
		paint_shadow(gtx, ops.Round_Rect{area, max(look.radius.tl, look.radius.br)}, tok.SHADOW_FLOATING_SMALL)
	}
	ops.fill(gtx.scene, shape, color(look.fill))
	ops.input_area(gtx.scene, ui.id_mix(look.id, 1), shape, {.Press, .Release, .Move, .Enter, .Leave})
	ops.outside_area(gtx.scene, look.id, shape)
	if look.name != "" {
		ops.tag(gtx.scene, ui.id_mix(look.id, 1), look.name, area)
	}
}

// surface_shape is area with corners c: a round rect when they agree, a
// path when a sheet squares the edge it touches.
@(private)
surface_shape :: proc(gtx: ^ui.Ctx, area: ops.Rect, c: Corners) -> ops.Shape {
	if c.tl == c.tr && c.tl == c.br && c.tl == c.bl {
		return ops.Round_Rect{area, c.tl}
	}
	return rounded(gtx, area, c)
}

// SLIDE_FROM is where an overlay slides in from for each side it opened
// on: 8px back toward the anchor (Overlay.tsx:27-39), none for
// Inside_Center.
@(private)
SLIDE_FROM := [Anchor_Side]ops.Point {
	.Outside_Bottom = {0, -OVERLAY_SLIDE},
	.Outside_Top    = {0, OVERLAY_SLIDE},
	.Outside_Left   = {OVERLAY_SLIDE, 0},
	.Outside_Right  = {-OVERLAY_SLIDE, 0},
	.Inside_Top     = {0, OVERLAY_SLIDE},
	.Inside_Bottom  = {0, -OVERLAY_SLIDE},
	.Inside_Left    = {OVERLAY_SLIDE, 0},
	.Inside_Right   = {-OVERLAY_SLIDE, 0},
	.Inside_Center  = {},
}

// overlay_limits are an overlay's size bounds in a window: a width step,
// else 192px up to the window less 32px; a height step, else up to the
// window's height (Overlay.module.css:11-21,75-169).
@(private)
overlay_limits :: proc(window: ops.Size, width: Overlay_Width, height: Overlay_Height) -> (l: ui.Size_Limits) {
	widest := max(window.x - OVERLAY_VIEWPORT_INSET, OVERLAY_MIN_WIDTH)
	l.min.x = OVERLAY_MIN_WIDTH
	l.max.x = widest
	if w := OVERLAY_WIDTHS[width]; w > 0 {
		l.min.x = max(min(w, widest), OVERLAY_MIN_WIDTH)
		l.max.x = l.min.x
	}
	l.max.y = window.y
	if h := OVERLAY_HEIGHTS[height]; h > 0 {
		l.min.y = min(h, window.y)
		l.max.y = l.min.y
	}
	return
}

// Overlay is an open overlay between overlay_open and overlay_close.
Overlay :: struct {
	visible:   bool,
	id:        ops.Area_Id,
	dismissed: Dismissal, // the gesture that closed it this frame
	open:      ^bool,
	surface:   Surface,
}

// overlay_open shows a floating surface while open^ (overlay.json):
// --overlay-bgColor under --shadow-floating-small with --borderRadius-large
// corners and no padding, at at from the enclosing container's origin
// (Primer's top and left, from the page). Its width is a step or hugs
// its content between 192px and the window less 32px; its height is a
// step or hugs its content up to the window's height, scrolling beyond.
// It fades in over OVERLAY_ENTER, unless gtx.reduce_motion, and, given
// the side of an anchor it hangs from, slides 8px in from that side. Escape while it is the
// top-most overlay, or a primary press outside it and outside ignore (a
// rect in the caller's space: its trigger), closes it. Focus moves to
// its first focusable area, or focus.initial, as it opens and back as it
// closes; it is not trapped. With fullscreen it covers the window below
// NARROW_WIDTH, square-cornered. role and name describe the surface to a
// reader. Lay content out between open and close; nothing is laid out,
// and visible is false, while it is closed.
//
// Departures: height initial (frozen at its first measure) and
// fit-content are auto, preventOverflow is not offered (it changes
// nothing, overlay.json notes), visibility hidden is not offered as an
// immediate-mode overlay is placed on the frame it is drawn, the fade dims
// each draw on its own rather than the surface as a group (ops.Push_Opacity),
// content is clipped to the surface's rect rather than its rounded
// corners, and the fullscreen variant pads no safe-area inset.
overlay_open :: proc(
	gtx: ^ui.Ctx,
	open: ^bool,
	at := ops.Point{},
	width := Overlay_Width.Auto,
	height := Overlay_Height.Auto,
	slide: Maybe(Anchor_Side) = nil,
	ignore := ops.Rect{},
	focus := Overlay_Focus{},
	fullscreen := false,
	role := ops.Role.Unknown,
	name := "",
	key: u64 = 0,
	loc := #caller_location,
) -> (o: Overlay) {
	o.id = ui.claim_id(gtx, key, loc)
	o.open = open
	d := ui.widget_data(gtx, o.id, Overlay_Data)
	if open^ {
		o.dismissed = overlay_events(gtx, o.id, open)
	}
	if !overlay_focus(gtx, o.id, d, open^, focus) {
		return
	}
	if ignore != {} {
		ops.outside_area(gtx.scene, o.id, ignore)
	}
	o.visible = true
	spec := Surface_Spec {
		limits = overlay_limits(gtx.viewport, width, height),
		radius = corners_all(tok.BORDER_RADIUS_LARGE),
		scroll = true,
		name   = name,
	}
	if side, ok := slide.?; ok {
		spec.slide = SLIDE_FROM[side]
	}
	layer: ui.Overlay
	if fullscreen && gtx.viewport.x < NARROW_WIDTH {
		layer = ui.overlay_open(gtx, cs = ui.exact(gtx.viewport), root = true)
		spec.limits = {min = gtx.viewport, max = gtx.viewport}
		spec.radius = {}
	} else {
		layer = ui.overlay_open(gtx, at)
	}
	o.surface = surface_open(gtx, o.id, d, layer, spec)
	overlay_semantics(gtx, role, name)
	return
}

// overlay_semantics declares the surface's role and name on the open
// box, which every node inside it then nests under; Unknown, the
// default, declares nothing (role none, overlay.json accessibility).
@(private)
overlay_semantics :: proc(gtx: ^ui.Ctx, role: ops.Role, name: string, states := ops.States{}) {
	if role != .Unknown || name != "" {
		ui.container_semantics(gtx, {role = role, label = ui.frame_string(gtx, name), states = states})
	}
}

// overlay_close closes an overlay opened by overlay_open, shown or not.
overlay_close :: proc(o: ^Overlay) {
	if !o.visible {
		return
	}
	o.visible = false
	surface_close(&o.surface, !o.open^)
}

// overlay is overlay_open as a guard: `if primer.overlay(gtx, &open) {
// … }` lays its content out while it shows and closes it at the end of
// the if.
@(deferred_in = overlay_guard_close)
overlay :: proc(
	gtx: ^ui.Ctx,
	open: ^bool,
	at := ops.Point{},
	width := Overlay_Width.Auto,
	height := Overlay_Height.Auto,
	slide: Maybe(Anchor_Side) = nil,
	ignore := ops.Rect{},
	focus := Overlay_Focus{},
	fullscreen := false,
	role := ops.Role.Unknown,
	name := "",
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	h := ui.guard_hold(gtx, Overlay)
	h^ = overlay_open(gtx, open, at, width, height, slide, ignore, focus, fullscreen, role, name, key, loc)
	return h.visible
}

@(private = "file")
overlay_guard_close :: proc(
	gtx: ^ui.Ctx,
	open: ^bool,
	at: ops.Point,
	width: Overlay_Width,
	height: Overlay_Height,
	slide: Maybe(Anchor_Side),
	ignore: ops.Rect,
	focus: Overlay_Focus,
	fullscreen: bool,
	role: ops.Role,
	name: string,
	key: u64,
	loc: runtime.Source_Code_Location,
) {
	overlay_close(ui.guard_take(gtx, Overlay))
}

// Anchored overlays.

// Open_Gesture is what opened an anchored overlay on the frame it did.
Open_Gesture :: enum u8 {
	None,
	Anchor_Key_Press, // ArrowDown or ArrowUp on the focused anchor
}

// Narrow_Variant is how an anchored overlay shows below NARROW_WIDTH:
// still hanging off its anchor, or covering the window with a close
// button.
Narrow_Variant :: enum u8 {
	Anchored,
	Fullscreen,
}

// ANCHOR_OFFSET is the gap between anchor and overlay, and
// INSIDE_ALIGNMENT_OFFSET the nudge in from the aligned edge for an inside
// side not centred: @primer/behaviors' defaults (anchored-position.mjs:
// 91-111), which --overlay-offset agrees with.
ANCHOR_OFFSET :: tok.OVERLAY_OFFSET
INSIDE_ALIGNMENT_OFFSET :: f32(4)

// Anchored_Overlay is an open anchored overlay between
// anchored_overlay_open and anchored_overlay_close.
Anchored_Overlay :: struct {
	using overlay: Overlay,
	opened:        Open_Gesture, // the gesture that opened it this frame
	side:          Anchor_Side, // the side it sits on: asked, or where it flipped to last frame
	align:         Anchor_Align,
	centre:        f32, // Inside_Center: the vertical offset still to resolve from the size
	inside_center: bool,
}

// anchored_overlay_open shows an overlay hanging from anchor while open^
// (anchored-overlay.json): the trigger just drawn, read with
// ui.last_widget, in the same ui.stack as this call, so both share an
// origin. It sits on side of the anchor, anchor_offset away (4px; 0 for
// Inside_Center), aligned along that edge by align and nudged
// alignment_offset in from it (0; 4px for an inside side not centred).
// When it would be clipped it tries the other sides in Primer's order,
// then the other alignments, then is clamped into the window, and with
// every side clipped it hangs off the bottom unless display_in_viewport
// (getAnchoredPosition, anchored-position.mjs:1-11,112-176). It is
// Overlay's surface, sized by width and height, and slides in from the
// side it settled on, again when that changes. Below NARROW_WIDTH the
// Fullscreen variant covers the window with a Close button 8px from its
// top-right corner (close_button).
//
// ArrowDown or ArrowUp on the anchor while it is closed opens it (opened
// says so); the caller toggles it on the anchor's own activation (a
// primer.button's click), and a press on the anchor is not an outside
// press. Escape or a press outside closes it. Focus is trapped inside
// (unless trap is false, Primer's focusTrapSettings), starts on
// focus.initial or its first focusable area, and returns to the anchor
// as it closes.
//
// Departures: the anchor's aria-expanded is the anchor's to declare
// (button's and icon_button's expanded), and jm:ui has no aria-haspopup;
// the arrow-key focus zone between items is the list's that fills it;
// pinPosition is not offered; Inside_Center keeps its alignment where
// Primer would walk the alignments on a horizontal overflow; an overlay
// wider than the window ends flush left where Primer's ends flush right;
// it is re-placed every frame against the window rather than the nearest
// clipping ancestor; and Overlay's departures apply.
//
// max_height caps an auto height at a height step (a menu's maxHeight,
// ActionMenu.module.css:26-65) where height fixes it; scroll keeps the
// content's scroll offset where its owner can move it (to keep a focused
// item in view); scrolls false leaves the scrolling to the content (a
// panel whose header stays while its list scrolls).
anchored_overlay_open :: proc(
	gtx: ^ui.Ctx,
	open: ^bool,
	anchor: ui.Last_Widget,
	side := Anchor_Side.Outside_Bottom,
	align := Anchor_Align.Start,
	anchor_offset: Maybe(f32) = nil,
	alignment_offset: Maybe(f32) = nil,
	display_in_viewport := false,
	width := Overlay_Width.Auto,
	height := Overlay_Height.Auto,
	narrow := Narrow_Variant.Anchored,
	close_button := true,
	close_label := "Close",
	focus := Overlay_Focus{},
	trap := true,
	role := ops.Role.Unknown,
	name := "",
	max_height := Overlay_Height.Auto,
	scroll: ^ui.Scroll_Offset = nil,
	scrolls := true,
	key: u64 = 0,
	loc := #caller_location,
) -> (a: Anchored_Overlay) {
	a.id = ui.claim_id(gtx, key, loc)
	a.open = open
	d := ui.widget_data(gtx, a.id, Overlay_Data)
	if !open^ {
		for e in ui.events(gtx, anchor.id) {
			if e.kind == .Key && (e.key == .Down || e.key == .Up) {
				open^ = true
				a.opened = .Anchor_Key_Press
			}
		}
	} else {
		a.dismissed = overlay_events(gtx, a.id, open)
	}
	f := focus
	if f.return_to == 0 {
		f.return_to = anchor.id
	}
	if !overlay_focus(gtx, a.id, d, open^, f) {
		return
	}
	a.visible = true
	rect := ops.Rect{0, 0, anchor.size.x, anchor.size.y}
	ops.outside_area(gtx.scene, a.id, rect)
	spec := Surface_Spec {
		limits = overlay_limits(gtx.viewport, width, height),
		radius = corners_all(tok.BORDER_RADIUS_LARGE),
		trap   = trap,
		scroll = scrolls,
		offset = scroll,
		name   = name,
	}
	if cap := OVERLAY_HEIGHTS[max_height]; cap > 0 && height == .Auto {
		spec.limits.max.y = min(cap, gtx.viewport.y)
	}
	if narrow == .Fullscreen && gtx.viewport.x < NARROW_WIDTH {
		layer := ui.overlay_open(gtx, cs = ui.exact(gtx.viewport), root = true)
		spec.limits = {min = gtx.viewport, max = gtx.viewport}
		spec.radius = {}
		a.surface = surface_open(gtx, a.id, d, layer, spec)
		overlay_semantics(gtx, role, name)
		if close_button {
			anchored_close_button(gtx, &a, close_label)
		}
		return
	}
	place := anchored_placement(a.id, rect, side, align, anchor_offset, alignment_offset, display_in_viewport)
	a.side, a.align = side, align
	if p, ok := ui.last_placed(gtx, a.id); ok && side != .Inside_Center {
		// Inside_Center's placed alignment is the horizontal centring, not
		// the asked one, which places it vertically.
		a.side, a.align = anchor_side_of(p.side, side), ANCHOR_ALIGN_OF[p.align]
	}
	if a.side != d.side {
		// A flip replays the slide from the new side (Overlay.tsx:198-212).
		d.side = a.side
		d.slide = {to = 1, duration = OVERLAY_ENTER.duration / 1000}
	}
	spec.slide = SLIDE_FROM[a.side]
	a.inside_center = side == .Inside_Center
	if a.inside_center {
		a.centre = place.gap
	}
	layer := ui.popup_place(gtx, place)
	a.surface = surface_open(gtx, a.id, d, layer, spec)
	overlay_semantics(gtx, role, name)
	return
}

// anchored_close_button is the fullscreen variant's Close button: an
// invisible IconButton with the X octicon, 8px from the surface's top
// and right, before the content (AnchoredOverlay.module.css:1-14).
@(private = "file")
anchored_close_button :: proc(gtx: ^ui.Ctx, a: ^Anchored_Overlay, label: string) {
	side := button_metrics(.Medium).height
	at := ops.Point{gtx.viewport.x - tok.BASE_SIZE_8 - side, tok.BASE_SIZE_8}
	o := ui.overlay_open(gtx, at, cs = ui.loose({side, side}))
	if icon_button(gtx, .X, label, .Invisible, key = u64(ui.id_mix(a.id, 5))) {
		a.open^ = false
		a.dismissed = .Close_Button
	}
	ui.overlay_close(&o)
}

// anchored_placement is anchored-overlay.json's placement as a
// Placement: the side and its alternates (anchored-position.mjs:1-6), the
// alignment and its alternates (7-11), the offsets and their defaults
// (99-111), and the bottom left unclamped once the sides run out unless
// in_viewport (162-176). Inside_Center is inside-top centred across the
// anchor, its vertical offset (gap) finished by anchored_overlay_close
// once the size is known.
@(private)
anchored_placement :: proc(key: ops.Area_Id, anchor: ops.Rect, side: Anchor_Side, align: Anchor_Align, anchor_offset, alignment_offset: Maybe(f32), in_viewport: bool) -> ops.Placement {
	ALIGN := [Anchor_Align]ops.Side_Align {
		.Start  = .Start,
		.Center = .Center,
		.End    = .End,
	}
	inside := side >= .Inside_Top
	gap := anchor_offset.? or_else (side == .Inside_Center ? 0 : ANCHOR_OFFSET)
	nudge := alignment_offset.? or_else (align != .Center && inside ? INSIDE_ALIGNMENT_OFFSET : 0)
	p := ops.Placement {
		key         = key,
		anchor      = anchor,
		align       = ALIGN[align],
		gap         = gap,
		nudge       = nudge,
		inside      = inside,
		overhang    = !in_viewport,
		align_count = 2,
	}
	switch align {
	case .Start:
		p.aligns = {.End, .Center}
	case .Center:
		p.aligns = {.End, .Start}
	case .End:
		p.aligns = {.Start, .Center}
	}
	switch side {
	case .Outside_Bottom:
		p.side, p.sides = .Below, {.Above, .After, .Before, .Below}
	case .Outside_Top:
		p.side, p.sides = .Above, {.Below, .After, .Before, .Below}
	case .Outside_Left:
		p.side, p.sides = .Before, {.After, .Below, .Above, .Below}
	case .Outside_Right:
		p.side, p.sides = .After, {.Before, .Below, .Above, .Below}
	case .Inside_Top:
		p.side = .Above
	case .Inside_Bottom:
		p.side = .Below
	case .Inside_Left:
		p.side = .Before
	case .Inside_Right:
		p.side = .After
	case .Inside_Center:
		// Centred across: inside-top with the anchor offset as the nudge
		// and the alignment offset, for now, as the gap from the top.
		p.side, p.align, p.nudge, p.gap = .Above, .Center, gap, nudge
		p.align_count = 0
	}
	if !inside {
		p.side_count = 4
	}
	return p
}

@(private)
ANCHOR_ALIGN_OF := [ops.Side_Align]Anchor_Align {
	.Start  = .Start,
	.Center = .Center,
	.End    = .End,
}

// anchor_side_of is the Anchor_Side for the side flatten placed on, given
// the side asked (which says whether it is inside).
@(private)
anchor_side_of :: proc(s: ops.Side, asked: Anchor_Side) -> Anchor_Side {
	if asked == .Inside_Center {
		return asked
	}
	inside := asked >= .Inside_Top
	switch s {
	case .Below:
		return inside ? .Inside_Bottom : .Outside_Bottom
	case .Above:
		return inside ? .Inside_Top : .Outside_Top
	case .Before:
		return inside ? .Inside_Left : .Outside_Left
	case .After:
		return inside ? .Inside_Right : .Outside_Right
	}
	return asked
}

// anchored_overlay_close closes an anchored overlay opened by
// anchored_overlay_open, shown or not.
anchored_overlay_close :: proc(a: ^Anchored_Overlay) {
	if !a.visible {
		return
	}
	if a.inside_center && a.surface.layer.place.set {
		// inside-center's vertical offset by alignment, now the height is
		// known (anchored-position.mjs:244-253).
		h := a.surface.look.data.size.y
		ah := a.surface.layer.place.anchor.h
		switch a.align {
		case .Start:
			a.surface.layer.place.gap = a.centre
		case .Center:
			a.surface.layer.place.gap = (ah - h) / 2 + a.centre
		case .End:
			a.surface.layer.place.gap = ah - h - a.centre
		}
	}
	overlay_close(&a.overlay)
}

// anchored_overlay is anchored_overlay_open as a guard.
@(deferred_in = anchored_overlay_guard_close)
anchored_overlay :: proc(
	gtx: ^ui.Ctx,
	open: ^bool,
	anchor: ui.Last_Widget,
	side := Anchor_Side.Outside_Bottom,
	align := Anchor_Align.Start,
	anchor_offset: Maybe(f32) = nil,
	alignment_offset: Maybe(f32) = nil,
	display_in_viewport := false,
	width := Overlay_Width.Auto,
	height := Overlay_Height.Auto,
	narrow := Narrow_Variant.Anchored,
	close_button := true,
	close_label := "Close",
	focus := Overlay_Focus{},
	trap := true,
	role := ops.Role.Unknown,
	name := "",
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	h := ui.guard_hold(gtx, Anchored_Overlay)
	h^ = anchored_overlay_open(gtx, open, anchor, side, align, anchor_offset, alignment_offset, display_in_viewport, width, height, narrow, close_button, close_label, focus, trap, role, name, key = key, loc = loc)
	return h.visible
}

@(private = "file")
anchored_overlay_guard_close :: proc(
	gtx: ^ui.Ctx,
	open: ^bool,
	anchor: ui.Last_Widget,
	side: Anchor_Side,
	align: Anchor_Align,
	anchor_offset: Maybe(f32),
	alignment_offset: Maybe(f32),
	display_in_viewport: bool,
	width: Overlay_Width,
	height: Overlay_Height,
	narrow: Narrow_Variant,
	close_button: bool,
	close_label: string,
	focus: Overlay_Focus,
	trap: bool,
	role: ops.Role,
	name: string,
	key: u64,
	loc: runtime.Source_Code_Location,
) {
	anchored_overlay_close(ui.guard_take(gtx, Anchored_Overlay))
}

// Popover.

// Popover_Caret is the edge a popover's caret sits on, then where along
// it: Top_Left is on the top edge near the left, Left_Top on the left
// edge near the top (popover.json caret).
Popover_Caret :: enum u8 {
	Top,
	Bottom,
	Left,
	Right,
	Top_Left,
	Top_Right,
	Bottom_Left,
	Bottom_Right,
	Left_Top,
	Left_Bottom,
	Right_Top,
	Right_Bottom,
}

// Popover_Width is a popover's width from the --overlay-width-* tokens
// (192, 320, 480, 640 or 960px; Popover.module.css:208-226), or its
// content's.
Popover_Width :: enum u8 {
	XSmall,
	Small,
	Medium,
	Large,
	XLarge,
	Auto,
}

// Popover_Height is a popover's height from the --overlay-height-*
// tokens (256, 320, 432 or 600px; Popover.module.css:228-254), or its
// content's.
Popover_Height :: enum u8 {
	Small,
	Medium,
	Large,
	XLarge,
	Fit_Content,
	Auto,
}

@(private)
POPOVER_WIDTHS := [Popover_Width]f32 {
	.XSmall = tok.OVERLAY_WIDTH_XSMALL,
	.Small  = tok.OVERLAY_WIDTH_SMALL,
	.Medium = tok.OVERLAY_WIDTH_MEDIUM,
	.Large  = tok.OVERLAY_WIDTH_LARGE,
	.XLarge = tok.OVERLAY_WIDTH_XLARGE,
	.Auto   = 0,
}

@(private)
POPOVER_HEIGHTS := [Popover_Height]f32 {
	.Small       = tok.OVERLAY_HEIGHT_SMALL,
	.Medium      = tok.OVERLAY_HEIGHT_MEDIUM,
	.Large       = tok.OVERLAY_HEIGHT_LARGE,
	.XLarge      = tok.OVERLAY_HEIGHT_XLARGE,
	.Fit_Content = 0,
	.Auto        = 0,
}

// POPOVER_CARET_SHIFT is how far a corner caret moves the card toward
// its side, so the tip still lands where the caller aimed
// (Popover.module.css:79-120).
POPOVER_CARET_SHIFT :: f32(9)

// Popover is an open popover between popover_open and popover_close.
Popover :: struct {
	visible:   bool,
	id:        ops.Area_Id,
	dismissed: Dismissal,
	open:      ^bool,
	gtx:       ^ui.Ctx,
	layer:     ui.Overlay,
	layered:   bool,
	shifted:   bool,
	sized:     ui.Inset,
	box:       ui.Box,
	col:       ui.Flex,
}

// Popover_Look is a popover card's paint.
@(private)
Popover_Look :: struct {
	id:    ops.Area_Id,
	caret: Popover_Caret,
}

// popover_open shows a card with a caret pointing out of it while open^
// (popover.json): --overlay-bgColor under --shadow-floating-small with
// --borderRadius-medium corners and 24px of padding, width a step
// (--overlay-width-small, 320px, by default) and height a step or its
// content's. The caret is two stacked triangles on the caret's edge, an
// outer 16 by 8px in --borderColor-default and an inner 14 by 7px in the
// card's fill, both centred 1px before the edge's midpoint, or 24px from
// the left or top, 20px from the right, 16px from the bottom for a corner
// caret, which also moves the card 9px toward that corner. It sits at at
// from the enclosing container's origin, above the page, as Primer's
// absolutely placed container does; relative lays it out in the flow
// instead. Escape while it is the top-most overlay, or a primary press
// outside it and outside ignore, closes it. It does not move or trap
// focus, and does not fade or slide.
//
// Departures: it closes itself on Escape and outside presses where
// Primer calls back and leaves that to the caller; and it escapes the
// clip of the containers around it, as every jm:ui overlay does, where
// Primer's is clipped by its positioned ancestor.
popover_open :: proc(
	gtx: ^ui.Ctx,
	open: ^bool,
	at := ops.Point{},
	caret := Popover_Caret.Top,
	width := Popover_Width.Small,
	height := Popover_Height.Fit_Content,
	relative := false,
	ignore := ops.Rect{},
	key: u64 = 0,
	loc := #caller_location,
) -> (p: Popover) {
	p.id = ui.claim_id(gtx, key, loc)
	p.open = open
	p.gtx = gtx
	if !open^ {
		return
	}
	p.dismissed = overlay_events(gtx, p.id, open)
	if !open^ {
		return
	}
	p.visible = true
	if ignore != {} {
		ops.outside_area(gtx.scene, p.id, ignore)
	}
	if !relative {
		p.layer = ui.overlay_open(gtx, at)
		p.layered = true
	}
	ui.key_interest(gtx, p.id, .Escape, topmost = true)
	shift: f32
	#partial switch caret {
	case .Top_Left, .Bottom_Left:
		shift = -POPOVER_CARET_SHIFT
	case .Top_Right, .Bottom_Right:
		shift = POPOVER_CARET_SHIFT
	}
	if shift != 0 {
		ops.transform_push(gtx.scene, ops.translate(shift, 0))
		p.shifted = true
	}
	limits: ui.Size_Limits
	if w := POPOVER_WIDTHS[width]; w > 0 {
		limits.min.x, limits.max.x = w, w
	}
	if h := POPOVER_HEIGHTS[height]; h > 0 {
		limits.min.y, limits.max.y = h, h
	}
	look := new(Popover_Look, gtx.allocator)
	look^ = {p.id, caret}
	p.sized = ui.sized_open(gtx, limits, key = u64(ui.id_mix(p.id, 2)))
	p.box = ui.box_open(gtx, {padding = ui.pad_all(tok.BASE_SIZE_24), paint = paint_popover, user = look}, key = u64(ui.id_mix(p.id, 3)))
	// The card's children stack as blocks do.
	p.col = ui.column_open(gtx, key = u64(ui.id_mix(p.id, 4)))
	return
}

// paint_popover paints a popover's card at size, its caret, and the areas
// that keep presses from the page and count them as inside.
@(private)
paint_popover :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, size: ops.Size, user: rawptr) {
	look := (^Popover_Look)(user)
	rr := ops.Round_Rect{{0, 0, size.x, size.y}, tok.BORDER_RADIUS_MEDIUM}
	paint_shadow(gtx, rr, tok.SHADOW_FLOATING_SMALL)
	ops.fill(gtx.scene, rr, color(.Overlay_Bg_Color))
	outer, inner := popover_caret(look.caret, size)
	ops.fill(gtx.scene, ui.polygon(gtx, outer[:]), color(.Border_Color_Default))
	ops.fill(gtx.scene, ui.polygon(gtx, inner[:]), color(.Overlay_Bg_Color))
	ops.input_area(gtx.scene, ui.id_mix(look.id, 1), rr, {.Press, .Release, .Move, .Enter, .Leave})
	ops.outside_area(gtx.scene, look.id, rr)
}

// popover_caret is the caret's outer and inner triangles on a card of
// size: base on the edge, tip out (Popover.module.css:24-206, CSS border
// triangles: a 16px box with an 8px border draws a 16 by 8 triangle in
// the coloured border's half).
@(private)
popover_caret :: proc(c: Popover_Caret, size: ops.Size) -> (outer, inner: [3]ops.Point) {
	w, h := size.x, size.y
	OUT, IN :: tok.BASE_SIZE_8, f32(7)
	// along is the tip's position along its edge; the triangles share it.
	along: f32
	switch c {
	case .Top, .Bottom:
		along = w / 2 - 1
	case .Top_Left, .Bottom_Left:
		along = tok.BASE_SIZE_24 + OUT
	case .Top_Right, .Bottom_Right:
		along = w - 20 - OUT
	case .Left, .Right:
		along = h / 2 - 1
	case .Left_Top, .Right_Top:
		along = tok.BASE_SIZE_24 - 1
	case .Left_Bottom, .Right_Bottom:
		along = h - tok.BASE_SIZE_16 - OUT
	}
	switch c {
	case .Top, .Top_Left, .Top_Right:
		outer = {{along - OUT, 0}, {along + OUT, 0}, {along, -OUT}}
		inner = {{along - IN, 0}, {along + IN, 0}, {along, -IN}}
	case .Bottom, .Bottom_Left, .Bottom_Right:
		outer = {{along - OUT, h}, {along + OUT, h}, {along, h + OUT}}
		inner = {{along - IN, h}, {along + IN, h}, {along, h + IN}}
	case .Left, .Left_Top, .Left_Bottom:
		outer = {{0, along - OUT}, {0, along + OUT}, {-OUT, along}}
		inner = {{0, along - IN}, {0, along + IN}, {-IN, along}}
	case .Right, .Right_Top, .Right_Bottom:
		outer = {{w, along - OUT}, {w, along + OUT}, {w + OUT, along}}
		inner = {{w, along - IN}, {w, along + IN}, {w + IN, along}}
	}
	return
}

// popover_close closes a popover opened by popover_open, shown or not.
popover_close :: proc(p: ^Popover) {
	if !p.visible {
		return
	}
	p.visible = false
	ui.close(&p.col)
	ui.close(&p.box)
	ui.close(&p.sized)
	if p.shifted {
		ops.transform_pop(p.gtx.scene)
	}
	if p.layered {
		p.layer.discard = !p.open^
		ui.overlay_close(&p.layer)
	}
}

// popover is popover_open as a guard.
@(deferred_in = popover_guard_close)
popover :: proc(
	gtx: ^ui.Ctx,
	open: ^bool,
	at := ops.Point{},
	caret := Popover_Caret.Top,
	width := Popover_Width.Small,
	height := Popover_Height.Fit_Content,
	relative := false,
	ignore := ops.Rect{},
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	h := ui.guard_hold(gtx, Popover)
	h^ = popover_open(gtx, open, at, caret, width, height, relative, ignore, key, loc)
	return h.visible
}

@(private = "file")
popover_guard_close :: proc(
	gtx: ^ui.Ctx,
	open: ^bool,
	at: ops.Point,
	caret: Popover_Caret,
	width: Popover_Width,
	height: Popover_Height,
	relative: bool,
	ignore: ops.Rect,
	key: u64,
	loc: runtime.Source_Code_Location,
) {
	popover_close(ui.guard_take(gtx, Popover))
}

// Details.

// Details is an open disclosure between details_open and details_close.
Details :: struct {
	gtx:      ^ui.Ctx,
	id:       ops.Area_Id,
	open:     ^bool,
	toggled:  bool, // its summary toggled it this frame
	outside:  bool, // close_on_outside
	stack:    ui.Stack,
	col:      ui.Flex,
}

// details_open opens a disclosure (details.json): a summary, then content
// laid out only while open^. It draws nothing of its own. Draw the
// summary first and hand its activation to details_summary, then the
// content when it returns true:
//
//	d := primer.details_open(gtx, &open)
//	if primer.details_summary(&d, primer.button(gtx, "More", trailing = .Triangle_Down)) {
//		…content…
//	}
//	primer.details_close(&d)
//
// With close_on_outside, a primary press outside the whole disclosure
// while it is open closes it (useDetails.tsx:15-39).
//
// Departures: the outside press closes on the press, as Overlay's does,
// where useDetails waits for the click's release; a press inside a nested
// disclosure counts as inside, where useDetails' test counts it outside
// (details.json notes, an upstream bug); and the expanded state is on the
// disclosure's group node, as the summary's semantics are its own.
details_open :: proc(gtx: ^ui.Ctx, open: ^bool, close_on_outside := false, key: u64 = 0, loc := #caller_location) -> (d: Details) {
	d.gtx = gtx
	d.id = ui.claim_id(gtx, key, loc)
	d.open = open
	d.outside = close_on_outside
	if open^ && close_on_outside {
		for e in ui.events(gtx, d.id) {
			if e.kind == .Outside && e.button == .Left {
				open^ = false
			}
		}
	}
	d.stack = ui.stack_open(gtx, key = u64(ui.id_mix(d.id, 1)))
	d.col = ui.column_open(gtx, key = u64(ui.id_mix(d.id, 2)))
	ui.container_semantics(gtx, {role = .Group, states = design.state_if(open^, {.Expandable, .Expanded}) + {.Expandable}})
	return
}

// details_summary toggles d on its summary's activation, activated (the
// value the summary control returned), and reports whether the content
// shows.
details_summary :: proc(d: ^Details, activated: bool) -> bool {
	if activated {
		d.open^ = !d.open^
		d.toggled = true
	}
	return d.open^
}

// details_close closes a disclosure opened by details_open.
details_close :: proc(d: ^Details) {
	ui.close(&d.col)
	if d.open^ && d.outside {
		size := ui.last_widget(d.gtx).size
		ops.outside_area(d.gtx.scene, d.id, ops.Rect{0, 0, size.x, size.y})
	}
	ui.close(&d.stack)
}

// Tooltip.

// Tooltip_Type is what a tooltip's text is to its trigger: a description
// of a trigger that has a name, or the trigger's name (tooltip.json type).
Tooltip_Type :: enum u8 {
	Description,
	Label,
}

// Tooltip_Direction is the side and alignment a tooltip prefers: N is
// above and centred, NE above from the trigger's left edge, NW above to
// its right edge, and so on round the compass; E and W are centred
// beside it (TooltipV2/Tooltip.tsx:60-70).
Tooltip_Direction :: enum u8 {
	N,
	NE,
	E,
	SE,
	S,
	SW,
	W,
	NW,
}

// Tooltip_Delay is how long a pointer must rest on the trigger before
// its tooltip shows: 50, 400 or 1200ms (TooltipV2/Tooltip.tsx:94-100).
Tooltip_Delay :: enum u8 {
	Short,
	Medium,
	Long,
}

@(private)
TOOLTIP_DELAYS := [Tooltip_Delay]f64 {
	.Short  = 0.05,
	.Medium = 0.4,
	.Long   = 1.2,
}

// TOOLTIP_MAX_WIDTH is the widest a bubble grows before its text wraps,
// TOOLTIP_SIDE_BRIDGE the width of the strip that bridges the gap beside
// the trigger, and TOOLTIP_FADE its entry: 100ms ease-in
// (TooltipV2/Tooltip.module.css:1-10,19,84,95,102-123). None is a token.
TOOLTIP_MAX_WIDTH :: f32(250)
TOOLTIP_SIDE_BRIDGE :: f32(8)
TOOLTIP_FADE :: tok.Transition{100, {0.42, 0, 1, 1}}

// TOOLTIP_PLACE is each direction as an anchored placement.
@(private)
TOOLTIP_PLACE := [Tooltip_Direction]struct {
	side:  Anchor_Side,
	align: Anchor_Align,
} {
	.N  = {.Outside_Top, .Center},
	.NE = {.Outside_Top, .Start},
	.E  = {.Outside_Right, .Center},
	.SE = {.Outside_Bottom, .Start},
	.S  = {.Outside_Bottom, .Center},
	.SW = {.Outside_Bottom, .End},
	.W  = {.Outside_Left, .Center},
	.NW = {.Outside_Top, .End},
}

// Tooltip_Data is a tooltip's state between frames.
@(private)
Tooltip_Data :: struct {
	hovered:   bool, // the pointer is on the trigger
	since:     f64, // gtx.time it arrived
	on_bubble: bool, // the pointer is on the bubble or the bridge to it
	shown:     bool,
	dismissed: bool, // hidden by Escape, a press or another tooltip, until the trigger is left
	fade:      ui.Tween,
}

// tooltip_owner is the trigger whose tooltip showed last: only one shows
// at a time (TooltipV2/Tooltip.tsx:278-286, the browser's popover=auto).
@(private, thread_local)
tooltip_owner: ops.Area_Id

// tooltip shows text in a bubble by the trigger just drawn, read with
// ui.last_widget, in the same ui.stack as this call (tooltip.json): after
// delay with the pointer on the trigger, or at once while the trigger
// holds keyboard focus (a click's focus does not count). It hides as the
// pointer leaves the trigger, unless onto the bubble or the strip
// bridging the gap to it, as focus leaves, on Escape (which goes no
// further, so a dialog round it stays open) and on a press outside it;
// only one shows at a time. The bubble is --tooltip-bgColor with
// --borderRadius-medium corners, 4px by 8px of padding, and
// --tooltip-fgColor body-small text centred in balanced lines up to 250px
// wide; it sits on direction's side, 4px away, flipping and clamping as
// an anchored overlay does, and fades in over 100ms. It is drawn while it
// shows: true then. A Description tooltip reaches a reader as a tooltip
// node; a Label tooltip names its trigger, which the trigger declares.
//
// Departures: keybinding hints are not drawn (KeybindingHint is not
// built); a touch's press-and-hold is not distinguished from a tap
// (jm:ui has no touch events); the bubble follows its trigger while it shows, where Primer places it once;
// and a Description tooltip is its own node beside the trigger, as jm:ui
// cannot add a description to a node it did not draw.
tooltip :: proc(
	gtx: ^ui.Ctx,
	text: string,
	trigger: ui.Last_Widget,
	type := Tooltip_Type.Description,
	direction := Tooltip_Direction.S,
	delay := Tooltip_Delay.Short,
	disabled := false,
) -> bool {
	return tooltip_run(gtx, trigger.id, {0, 0, trigger.size.x, trigger.size.y}, text, direction, delay, disabled, type == .Description)
}

// tooltip_run runs the tooltip of trigger, whose box is area in the space
// current at the call: an observer over area tracks the pointer without
// taking hover from the trigger. With node, the bubble is a tooltip node.
@(private)
tooltip_run :: proc(
	gtx: ^ui.Ctx,
	trigger: ops.Area_Id,
	area: ops.Rect,
	text: string,
	direction: Tooltip_Direction,
	delay: Tooltip_Delay,
	disabled, node: bool,
) -> bool {
	watch := ui.id_mix(trigger, 0x7700)
	bubble := ui.id_mix(trigger, 0x7701)
	// Its own id for Escape and Outside: one id's areas should agree on
	// their kinds, or the router's last-seen hit of it may lack the one
	// an event needs.
	dismiss := ui.id_mix(trigger, 0x7702)
	d := ui.widget_data(gtx, bubble, Tooltip_Data)
	for e in ui.events(gtx, watch) {
		#partial switch e.kind {
		case .Enter:
			d.hovered, d.since = true, gtx.time
		case .Leave:
			d.hovered = false
		}
	}
	for e in ui.events(gtx, bubble) {
		#partial switch e.kind {
		case .Enter:
			d.on_bubble = true
		case .Leave:
			d.on_bubble = false
		}
	}
	for e in ui.events(gtx, dismiss) {
		#partial switch e.kind {
		case .Key:
			if e.key == .Escape {
				d.dismissed = true
			}
		case .Outside:
			if e.button == .Left {
				d.dismissed = true
			}
		}
	}
	ops.observer_area(gtx.scene, watch, area)
	focus := ui.focused(gtx) == trigger && ui.focus_visible(gtx)
	wait := TOOLTIP_DELAYS[delay] - (gtx.time - d.since)
	rested := d.hovered && wait <= 0
	if d.hovered && !rested && !d.shown {
		ui.request_frame(gtx, f32(wait))
	}
	want := rested || (d.shown && d.on_bubble) || focus
	if !d.hovered && !d.on_bubble && !focus {
		d.dismissed = false
	}
	if disabled || text == "" || d.dismissed {
		want = false
	}
	if want && d.shown && tooltip_owner != trigger {
		// Another tooltip showed since: this one stays down until its
		// trigger is left.
		d.dismissed = true
		want = false
	}
	if want && !d.shown {
		tooltip_owner = trigger
		d.fade = {to = 1, duration = TOOLTIP_FADE.duration / 1000}
	}
	d.shown = want
	if !want {
		d.on_bubble = false
		return false
	}
	paint_tooltip(gtx, d, bubble, dismiss, area, text, direction, node)
	return true
}

// paint_tooltip draws a shown tooltip's bubble in a popup placed against
// area, with the bridge to it and the areas that dismiss it.
@(private)
paint_tooltip :: proc(gtx: ^ui.Ctx, d: ^Tooltip_Data, bubble, dismiss: ops.Area_Id, area: ops.Rect, text: string, direction: Tooltip_Direction, node: bool) {
	pad := ops.Point{tok.OVERLAY_PADDING_CONDENSED, tok.OVERLAY_PADDING_BLOCK_CONDENSED}
	para := tooltip_text(gtx, text, TOOLTIP_MAX_WIDTH - 2 * pad.x)
	w, h := para.width + 2 * pad.x, para.height + 2 * pad.y
	at := TOOLTIP_PLACE[direction]
	place := anchored_placement(bubble, area, at.side, at.align, nil, nil, false)
	side := place.side
	if p, ok := ui.last_placed(gtx, bubble); ok {
		side = p.side
	}
	o := ui.popup_place(gtx, place)
	if node {
		ui.overlay_semantics(gtx, &o, {role = .Tooltip, label = ui.frame_string(gtx, text)}, id = ui.id_mix(bubble, 1))
	}
	alpha := bezier_ease(TOOLTIP_FADE.easing, ui.tween_update(&d.fade, gtx))
	if gtx.reduce_motion {
		alpha = 1
	}
	if alpha < 1 {
		ops.opacity_push(gtx.scene, alpha)
	}
	rr := ops.Round_Rect{{0, 0, w, h}, tok.BORDER_RADIUS_MEDIUM}
	ops.fill(gtx.scene, rr, color(.Tooltip_Bg_Color))
	design.draw_paragraph(gtx, para, pad, color(.Tooltip_Fg_Color))
	// The bridge fills the gap to the trigger, so the pointer can cross it
	// (TooltipV2/Tooltip.module.css:56-100).
	gap := place.gap
	bridge: ops.Rect
	switch side {
	case .Above:
		bridge = {0, h, w, gap}
	case .Below:
		bridge = {0, -gap, w, gap}
	case .After:
		bridge = {-TOOLTIP_SIDE_BRIDGE, 0, TOOLTIP_SIDE_BRIDGE, h}
	case .Before:
		bridge = {w, 0, TOOLTIP_SIDE_BRIDGE, h}
	}
	kinds := ops.Event_Kinds{.Enter, .Leave, .Move}
	ops.input_area(gtx.scene, bubble, bridge, kinds)
	ops.input_area(gtx.scene, bubble, rr, kinds)
	ops.outside_area(gtx.scene, dismiss, rr)
	ops.tag(gtx.scene, bubble, ui.frame_string(gtx, text), {0, 0, w, h})
	ui.key_interest(gtx, dismiss, .Escape, topmost = true)
	if alpha < 1 {
		ops.opacity_pop(gtx.scene)
	}
	ui.popup_close(&o, {w, h})
}

// tooltip_text lays text out as a tooltip's: body small, wrapped by word
// at width and then as narrow as keeps the same number of lines, which
// balances them (text-wrap: balance), each line centred.
@(private)
tooltip_text :: proc(gtx: ^ui.Ctx, text: string, width: f32) -> ui.Paragraph {
	st := style(.Body_Small)
	font := font_for(gtx, st.weight)
	para := design.layout_style(gtx, text, st, font, width)
	if n := len(para.lines); n > 1 {
		lo, hi := f32(0), width
		for _ in 0 ..< 8 {
			mid := (lo + hi) / 2
			if len(design.layout_style(gtx, text, st, font, mid).lines) > n {
				lo = mid
			} else {
				hi = mid
			}
		}
		para = design.layout_style(gtx, text, st, font, hi)
	}
	for &ln in para.lines {
		ln.x = (para.width - ln.width) / 2
	}
	return para
}
