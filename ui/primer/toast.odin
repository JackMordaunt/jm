package primer

import "core:fmt"
import "core:mem"
import "core:strings"
import "jm:ui"
import "jm:ui/design"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// Toast: a short notice stacked in a corner of the window, from Primer
// CSS's Toast (primer/css src/toasts/toasts.scss at 9c20b49, and its
// deprecated-components/Toast stories). @primer/react 38.40.1 exports no
// Toast (index.ts and its experimental, deprecated and next entries), so the
// look is Primer CSS's on today's tokens and the behaviour is Fluent's
// Toaster: the app owns a queue (Toasts), pushes to it from anywhere it
// holds the model, and draws it once a frame with toaster.

// Toast_Variant is a toast's intent: the icon band's fill and its icon
// (toasts.scss:55-95). Default is info; Loading turns a spinner.
Toast_Variant :: enum u8 {
	Default,
	Success,
	Warning,
	Error,
	Loading,
}

// Toast_Position is the window corner or edge a toaster stacks against.
Toast_Position :: enum u8 {
	Bottom_End,
	Bottom_Start,
	Bottom,
	Top_End,
	Top_Start,
	Top,
}

// TOAST_TIMEOUT is how long a toast shows, in seconds, once it has
// entered; TOAST_STICKY keeps it until dismissed. Primer CSS sets no
// timeout; 5s is this package's choice, longer than Fluent's 3s so a
// message of two lines can be read. Error and Loading toasts are sticky
// unless given a timeout.
TOAST_TIMEOUT :: f32(5)
TOAST_STICKY :: f32(-1)

// TOAST_LIMIT is how many toasts show at once when Toasts.limit is 0; a
// push past it dismisses the oldest.
TOAST_LIMIT :: 5

// TOAST_* are the CSS's metrics (toasts.scss:3-53): at most 450px wide
// from the small breakpoint, 16px from the window's edges (8px below
// it), a 48px icon band, content padded 16px and a dismiss button padded
// 16px whose height stops at 54px so its X stays on the first line.
@(private)
TOAST_MAX_WIDTH :: f32(450)
@(private)
TOAST_BAND :: tok.BASE_SIZE_48
@(private)
TOAST_PAD :: tok.BASE_SIZE_16
@(private)
TOAST_MARGIN :: tok.BASE_SIZE_16
@(private)
TOAST_MARGIN_NARROW :: tok.BASE_SIZE_8
@(private)
TOAST_DISMISS_MAX_HEIGHT :: f32(54)
@(private)
TOAST_GLYPH :: tok.BASE_SIZE_16
@(private)
TOAST_SPINNER :: f32(18)
@(private)
TOAST_DETAIL_GAP :: tok.BASE_SIZE_4

// TOAST_ENTER and TOAST_EXIT are the CSS's animations: 180ms, rising from
// a full height below with the opacity, and falling back
// (toasts.scss:97-120). Not tokens.
TOAST_ENTER :: tok.Transition{180, {0.22, 0.61, 0.36, 1}}
TOAST_EXIT :: tok.Transition{180, {0.55, 0.06, 0.68, 0.19}}

// TOAST_DISMISS_HOVER and TOAST_DISMISS_ACTIVE are the dismiss button's
// opacity hovered and pressed (toasts.scss:46-52).
@(private)
TOAST_DISMISS_HOVER :: f32(0.7)
@(private)
TOAST_DISMISS_ACTIVE :: f32(0.5)

// Toast is one queued notice. Its strings belong to the queue, which
// copies them on push and update and frees them when the toast goes.
Toast :: struct {
	id:      int,
	variant: Toast_Variant,
	message: string,
	detail:  string, // a second line in the muted colour: an error's cause
	action:  string, // a link-styled action after the text: "Retry"
	timeout: f32, // seconds, or TOAST_STICKY
	elapsed: f32, // of the timeout, counted once the enter motion ends
	enter:   ui.Tween,
	exit:    ui.Tween,
	leaving: bool,
}

// Toast_Options are a toast's optional parts. timeout 0 takes the
// variant's default (TOAST_TIMEOUT, or sticky for Error and Loading).
Toast_Options :: struct {
	detail:  string,
	action:  string,
	timeout: f32,
}

// Toasts is a toaster's queue. The zero value is ready; it allocates
// from the context allocator of its first push unless allocator is set.
// limit caps the toasts shown, TOAST_LIMIT when 0.
Toasts :: struct {
	items:     [dynamic]Toast,
	next_id:   int,
	limit:     int,
	allocator: mem.Allocator,
}

// Toaster_Event is what happened to a toaster's toasts this frame: the
// id of the toast whose action was pressed, and of the one whose dismiss
// was pressed or that Escape dismissed; 0 for none.
Toaster_Event :: struct {
	action:    int,
	dismissed: int,
}

// toast_push queues a toast and returns its id. It copies the strings.
// When the toasts showing already fill the limit, the oldest of them
// leaves to make room.
toast_push :: proc(
	ts: ^Toasts,
	message: string,
	variant := Toast_Variant.Default,
	opts := Toast_Options{},
) -> int {
	if ts.allocator.procedure == nil {
		ts.allocator = context.allocator
	}
	if ts.items.allocator.procedure == nil {
		ts.items = make([dynamic]Toast, ts.allocator)
	}
	toast_evict(ts)
	ts.next_id += 1
	t := Toast {
		id    = ts.next_id,
		enter = {to = 1, duration = TOAST_ENTER.duration / 1000},
	}
	toast_set(ts, &t, message, variant, opts)
	append(&ts.items, t)
	return t.id
}

// toast_update replaces toast id's message, variant and options in
// place, restarting its clock: a Loading toast turning to Success or
// Error when its job ends. Returns false when the toast has gone or is
// leaving.
toast_update :: proc(
	ts: ^Toasts,
	id: int,
	message: string,
	variant: Toast_Variant,
	opts := Toast_Options{},
) -> bool {
	for &t in ts.items {
		if t.id == id && !t.leaving {
			toast_set(ts, &t, message, variant, opts)
			return true
		}
	}
	return false
}

// toast_dismiss starts toast id's exit; it leaves the queue when that
// ends. An unknown id does nothing.
toast_dismiss :: proc(ts: ^Toasts, id: int) {
	for &t in ts.items {
		if t.id == id && !t.leaving {
			t.leaving = true
			t.exit = {to = 1, duration = TOAST_EXIT.duration / 1000}
		}
	}
}

// toasts_destroy frees the queue and the strings it holds.
toasts_destroy :: proc(ts: ^Toasts) {
	for &t in ts.items {
		toast_free_strings(ts, &t)
	}
	delete(ts.items)
	ts.items = nil
}

// toast_evict dismisses the oldest showing toasts until one more fits
// under the limit.
@(private)
toast_evict :: proc(ts: ^Toasts) {
	limit := ts.limit > 0 ? ts.limit : TOAST_LIMIT
	showing := 0
	for t in ts.items {
		showing += t.leaving ? 0 : 1
	}
	for &t in ts.items {
		if showing < limit {
			return
		}
		if !t.leaving {
			toast_dismiss(ts, t.id)
			showing -= 1
		}
	}
}

// toast_set copies message and opts into t and restarts its clock.
@(private)
toast_set :: proc(
	ts: ^Toasts,
	t: ^Toast,
	message: string,
	variant: Toast_Variant,
	opts: Toast_Options,
) {
	toast_free_strings(ts, t)
	context.allocator = ts.allocator
	t.message = clone_or_empty(message)
	t.detail = clone_or_empty(opts.detail)
	t.action = clone_or_empty(opts.action)
	t.variant = variant
	t.elapsed = 0
	t.timeout = opts.timeout
	if t.timeout == 0 {
		t.timeout = variant == .Error || variant == .Loading ? TOAST_STICKY : TOAST_TIMEOUT
	}
}

@(private)
clone_or_empty :: proc(s: string) -> string {
	return s == "" ? "" : strings.clone(s)
}

@(private)
toast_free_strings :: proc(ts: ^Toasts, t: ^Toast) {
	delete(t.message, ts.allocator)
	delete(t.detail, ts.allocator)
	delete(t.action, ts.allocator)
	t.message, t.detail, t.action = "", "", ""
}

// toast_variant_look is v's band fill and icon (toasts.scss:55-95, and
// the stories' icons: info, check, alert, stop).
@(private)
toast_variant_look :: proc(v: Toast_Variant) -> (band: tok.Role, ic: Icon) {
	switch v {
	case .Default:
		return .Bg_Color_Accent_Emphasis, .Info
	case .Success:
		return .Bg_Color_Success_Emphasis, .Check
	case .Warning:
		return .Bg_Color_Attention_Emphasis, .Alert
	case .Error:
		return .Bg_Color_Danger_Emphasis, .Stop
	case .Loading:
	}
	return .Bg_Color_Neutral_Emphasis, .None
}

// Toast_Layout is a toast measured for this frame: its size, its text
// at the width it wraps to, and its parts' boxes, all from its top-left.
@(private)
Toast_Layout :: struct {
	size:    ops.Size,
	message: ui.Paragraph,
	detail:  ui.Paragraph,
	action:  Text,
	text_x:  f32,
	act:     ops.Rect,
	dismiss: ops.Rect,
	at:      ops.Point, // where the toaster places it, in the window
	alpha:   f32, // its motion's share: its opacity
}

// toast_layout measures t no wider than max_w: as wide as its text needs
// (width: max-content) or, when narrow, max_w whatever the text.
@(private)
toast_layout :: proc(gtx: ^ui.Ctx, t: ^Toast, max_w: f32, narrow: bool) -> (l: Toast_Layout) {
	st := text_style(.Medium)
	font := font_for(gtx, st.weight)
	l.action = design.shape_style(gtx, t.action, st, font)
	act_w := t.action != "" ? l.action.width + TOAST_PAD : 0
	fixed := TOAST_BAND + 2 * TOAST_PAD + act_w + TOAST_BAND
	message_w := design.shape_style(gtx, t.message, st, font).width
	natural := max(message_w, design.shape_style(gtx, t.detail, st, font).width)
	text_w := max(min(natural, max_w - fixed), 1)
	if narrow {
		text_w = max(max_w - fixed, 1)
	}
	l.message = design.layout_style(gtx, t.message, st, font, text_w)
	h := 2 * TOAST_PAD + l.message.height
	if t.detail != "" {
		l.detail = design.layout_style(gtx, t.detail, st, font, text_w)
		h += TOAST_DETAIL_GAP + l.detail.height
	}
	w := fixed + text_w
	l.size = {w, h}
	l.text_x = TOAST_BAND + TOAST_PAD
	l.act = {l.text_x + text_w + TOAST_PAD, TOAST_PAD, l.action.width, st.line_height}
	l.dismiss = {w - TOAST_BAND, 0, TOAST_BAND, min(h, TOAST_DISMISS_MAX_HEIGHT)}
	return
}

// toast_motion advances t's enter or exit and returns how far in it is,
// eased: 0 out of sight, 1 at rest. done is true once its exit ends.
// Reduced motion snaps both, so a toast appears and goes at once.
@(private)
toast_motion :: proc(gtx: ^ui.Ctx, t: ^Toast) -> (k: f32, done: bool) {
	if gtx.reduce_motion {
		t.enter.t, t.exit.t = t.enter.duration, t.exit.duration
	}
	if t.leaving {
		x := ui.tween_update(&t.exit, gtx)
		return 1 - bezier_ease(TOAST_EXIT.easing, x), x >= 1
	}
	return bezier_ease(TOAST_ENTER.easing, ui.tween_update(&t.enter, gtx)), false
}

// toast_tick counts t's timeout down once it has entered, unless held,
// and dismisses it at the end.
@(private)
toast_tick :: proc(gtx: ^ui.Ctx, ts: ^Toasts, t: ^Toast, held: bool) {
	if t.leaving || t.timeout < 0 || held || t.enter.t < t.enter.duration {
		return
	}
	t.elapsed += gtx.dt
	if t.elapsed >= t.timeout {
		toast_dismiss(ts, t.id)
		return
	}
	ui.request_frame(gtx, t.timeout - t.elapsed)
}

// Toast_Stack is a toaster's column this frame: the window it stacks
// in, how far from the edge, how wide a toast may be, and the edge the
// next toast stacks against.
@(private)
Toast_Stack :: struct {
	position: Toast_Position,
	window:   ops.Size,
	narrow:   bool, // under the small breakpoint: toasts fill the width
	top:      bool,
	margin:   f32,
	max_w:    f32,
	edge:     f32,
	id:       ops.Area_Id,
	column:   ops.Area_Id, // the layer's node, each toast's parent
}

@(private)
TOP_POSITIONS :: bit_set[Toast_Position]{.Top_End, .Top_Start, .Top}

// toast_stack is the column at position in gtx's window (toasts.scss
// :3-18): 16px in from the window's edges, toasts at most 450px wide;
// under 544px 8px in, toasts as wide as the window less that.
@(private)
toast_stack :: proc(gtx: ^ui.Ctx, position: Toast_Position) -> (s: Toast_Stack) {
	s.position = position
	s.window = gtx.viewport
	s.narrow = s.window.x < tok.BREAKPOINT_SMALL
	s.top = position in TOP_POSITIONS
	s.margin = s.narrow ? TOAST_MARGIN_NARROW : TOAST_MARGIN
	s.max_w = s.window.x - 2 * s.margin
	if !s.narrow {
		s.max_w = min(TOAST_MAX_WIDTH, s.max_w)
	}
	s.edge = s.top ? s.margin : s.window.y - s.margin
	return
}

// toast_place is where a toast of size goes in s at motion k, and moves
// s's edge past its slot. The slot opens by k of the toast's height and
// margin while the toast rises from (at the top, drops from) a full
// height away, so it enters from the window's edge as the stack makes
// room, and leaves the same way.
@(private)
toast_place :: proc(s: ^Toast_Stack, size: ops.Size, k: f32) -> (at: ops.Point) {
	switch s.position {
	case .Bottom_End, .Top_End:
		at.x = s.window.x - s.margin - size.x
	case .Bottom_Start, .Top_Start:
		at.x = s.margin
	case .Bottom, .Top:
		at.x = (s.window.x - size.x) / 2
	}
	slot := (size.y + s.margin) * k
	if s.top {
		at.y = s.edge - (1 - k) * size.y
		s.edge += slot
	} else {
		at.y = s.edge - k * size.y
		s.edge -= slot
	}
	return
}

// toaster draws ts's toasts stacked at position in the window, on a layer
// over everything else, and runs their clocks. The newest sits nearest
// the edge; each enters by rising its own height while it fades in, and
// leaves the way it came, as the stack closes over its place. A toast's
// clock runs TOAST_TIMEOUT (or its own timeout) after its enter, paused
// while the pointer is over it or focus is in it; Error and Loading wait
// to be dismissed. Its dismiss button, or Escape while focus is in it,
// dismisses it; pressing its action dismisses it too and reports it.
//
// Each toast is Primer CSS's: --bgColor-default with a 1px inset ring of
// --borderColor-default and --shadow-floating-small, 6px corners, at
// most 450px wide (the window less 16px when narrower than 544px); a
// 48px band of the variant's emphasis fill carrying its 16px octicon in
// --fgColor-onEmphasis; the message in 14px body text padded 16px, the
// detail under it in --fgColor-muted, the action as a link, and a 48px
// dismiss button whose X dims to 0.7 hovered and 0.5 pressed. A toast
// is a status live region, an Error toast an alert, its action and
// dismiss buttons under it. Tags: the message for the toast, the action
// label, and "Dismiss <message>".
//
// Departures: Primer CSS has no queue, timeout, stacking, detail line or
// top positions, so these follow Fluent's Toaster; a top toast enters
// from above, mirroring the CSS's rise. A toast filling a narrow window
// keeps its action and X at its end, where the CSS's flex row would pack
// them after the text. The CSS's --shadow-floating-legacy is removed in
// @primer/primitives 11, which names --shadow-floating-small in its
// place (removed.json). The text is not selectable.
toaster :: proc(
	gtx: ^ui.Ctx,
	ts: ^Toasts,
	position := Toast_Position.Bottom_End,
	key: u64 = 0,
	loc := #caller_location,
) -> (
	ev: Toaster_Event,
) {
	if len(ts.items) == 0 {
		return
	}
	s := toast_stack(gtx, position)
	s.id = ui.claim_id(gtx, key, loc)
	o := ui.overlay_open(gtx, cs = ui.loose(s.window), root = true)
	defer ui.close(&o)
	s.column = ui.overlay_semantics(gtx, &o, {role = .Presentation}, 1)
	gone := make([dynamic]int, gtx.allocator)
	#reverse for &t, i in ts.items {
		k, done := toast_motion(gtx, &t)
		if done {
			append(&gone, i)
			continue
		}
		l := toast_layout(gtx, &t, s.max_w, s.narrow)
		l.at, l.alpha = toast_place(&s, l.size, k), k
		parts, e := toast_input(gtx, ts, &t, l, ui.id_mix(s.id, u64(t.id)))
		if e != {} {
			ev = e
		}
		toast_draw(gtx, s.column, &t, l, parts)
	}
	// gone runs newest first, so each removal leaves the next index valid.
	for i in gone {
		toast_free_strings(ts, &ts.items[i])
		ordered_remove(&ts.items, i)
	}
	return
}

// Toast_Parts are a toast's three areas and their state this frame: the
// surface, which only hovers and hears Escape, the action and the X.
@(private)
Toast_Parts :: struct {
	tid, aid, did:          ops.Area_Id,
	surface, action, close: Control,
}

// toast_input reads what reached t's parts since the last frame, runs
// its clock unless the pointer or focus is in it, and dismisses it on
// its X, Escape or its action.
@(private)
toast_input :: proc(
	gtx: ^ui.Ctx,
	ts: ^Toasts,
	t: ^Toast,
	l: Toast_Layout,
	tid: ops.Area_Id,
) -> (
	p: Toast_Parts,
	ev: Toaster_Event,
) {
	p.tid, p.aid, p.did = tid, ui.id_mix(tid, 1), ui.id_mix(tid, 2)
	p.surface = control(gtx, tid, {0, 0, l.size.x, l.size.y}, .Live)
	if t.action != "" {
		p.action = control(gtx, p.aid, l.act, .Live)
	}
	p.close = control(gtx, p.did, l.dismiss, .Live)
	toast_tick(gtx, ts, t, toast_held(p))
	if p.close.clicked || toast_escaped(gtx, p.tid, p.aid, p.did) {
		toast_dismiss(ts, t.id)
		ev.dismissed = t.id
	}
	if p.action.clicked {
		toast_dismiss(ts, t.id)
		ev.action = t.id
	}
	return
}

// toast_held is whether the pointer is over a toast or focus is in it.
@(private)
toast_held :: proc(p: Toast_Parts) -> bool {
	for c in ([3]Control{p.surface, p.action, p.close}) {
		if c.hovered || c.focused {
			return true
		}
	}
	return false
}

// toast_escaped reports an Escape that reached the toast or one of its
// buttons, which only a focused one hears.
@(private)
toast_escaped :: proc(gtx: ^ui.Ctx, ids: ..ops.Area_Id) -> bool {
	for id in ids {
		for e in ui.events(gtx, id) {
			if e.kind == .Key && e.key == .Escape {
				return true
			}
		}
	}
	return false
}

// toast_draw draws t where l places it, faded by l.alpha, and declares
// it under column.
@(private)
toast_draw :: proc(gtx: ^ui.Ctx, column: ops.Area_Id, t: ^Toast, l: Toast_Layout, p: Toast_Parts) {
	ops.transform_push(gtx.scene, ops.translate(l.at.x, l.at.y))
	defer ops.transform_pop(gtx.scene)
	faded := l.alpha < 1
	if faded {
		ops.opacity_push(gtx.scene, max(l.alpha, 0))
	}
	defer if faded {
		ops.opacity_pop(gtx.scene)
	}
	toast_paint(gtx, t, l)
	box := ops.Rect{0, 0, l.size.x, l.size.y}
	message := ui.frame_string(gtx, t.message)
	listen(gtx, p.surface.st, p.tid, ops.Round_Rect{box, tok.BORDER_RADIUS_MEDIUM}, no_tab = true)
	ops.tag(gtx.scene, p.tid, message)
	said := ops.Semantics {
		role        = t.variant == .Error ? .Alert : .Status,
		label       = message,
		description = ui.frame_string(gtx, t.detail),
		states      = t.variant == .Loading ? {.Busy} : {},
	}
	ui.child_semantics(gtx, column, p.tid, box, said)
	if t.action != "" {
		toast_action(gtx, p, t.action, l)
	}
	toast_dismiss_button(gtx, p, message, l.dismiss)
}

// toast_paint draws t's surface, band, icon and text.
@(private)
toast_paint :: proc(gtx: ^ui.Ctx, t: ^Toast, l: Toast_Layout) {
	box := ops.Rect{0, 0, l.size.x, l.size.y}
	rr := ops.Round_Rect{box, tok.BORDER_RADIUS_MEDIUM}
	paint_shadow(gtx, rr, tok.SHADOW_FLOATING_SMALL)
	ops.fill(gtx.scene, rr, color(.Bg_Color_Default))
	stroke_inside(gtx, rr, color(.Border_Color_Default), tok.BORDER_WIDTH_THIN) // inset 0 0 0 1px
	band, ic := toast_variant_look(t.variant)
	r := tok.BORDER_RADIUS_MEDIUM
	ops.fill(gtx.scene, rounded(gtx, {0, 0, TOAST_BAND, l.size.y}, {r, 0, 0, r}), color(band))
	on := color(.Fg_Color_On_Emphasis)
	if t.variant == .Loading {
		s := TOAST_SPINNER
		paint_spinner(gtx, {(TOAST_BAND - s) / 2, (l.size.y - s) / 2}, s, on)
	} else {
		w := icon_width(ic, TOAST_GLYPH)
		icon(gtx, ic, {(TOAST_BAND - w) / 2, (l.size.y - TOAST_GLYPH) / 2}, TOAST_GLYPH, on)
	}
	draw_paragraph(gtx, l.message, {l.text_x, TOAST_PAD}, color(.Fg_Color_Default))
	if t.detail != "" {
		y := TOAST_PAD + l.message.height + TOAST_DETAIL_GAP
		draw_paragraph(gtx, l.detail, {l.text_x, y}, color(.Fg_Color_Muted))
	}
}

// toast_action is the action, drawn as a Link: accent, underlined on
// hover, with a link's focus outline.
@(private)
toast_action :: proc(gtx: ^ui.Ctx, p: Toast_Parts, label: string, l: Toast_Layout) {
	c := p.action
	fg, underline := link_look(c, false, false)
	y := l.act.y + (l.act.h - l.action.height) / 2
	draw_text(gtx, l.action, {l.act.x, y}, fg)
	if underline {
		paint_underline(gtx, {l.act.x, y + baseline_of(l.action)}, l.action.width, fg)
	}
	paint_focus_outline(gtx, c, {l.act, 0}, LINK_FOCUS_OFFSET)
	listen(gtx, c.st, p.aid, l.act, cursor = .Pointer)
	said := ui.frame_string(gtx, label)
	ops.tag(gtx.scene, p.aid, said)
	ui.child_semantics(gtx, p.tid, p.aid, l.act, {role = .Button, label = said})
}

// toast_dismiss_button is the X in r, in the text's colour, dimmed while
// hovered or pressed.
@(private)
toast_dismiss_button :: proc(gtx: ^ui.Ctx, p: Toast_Parts, message: string, r: ops.Rect) {
	c := p.close
	fg := color(.Fg_Color_Default)
	if c.pressed {
		fg = fade(fg, TOAST_DISMISS_ACTIVE)
	} else if c.hovered {
		fg = fade(fg, TOAST_DISMISS_HOVER)
	}
	w := icon_width(.X, TOAST_GLYPH)
	icon(gtx, .X, {r.x + (r.w - w) / 2, r.y + (r.h - TOAST_GLYPH) / 2}, TOAST_GLYPH, fg)
	paint_focus_outline(gtx, c, {r, tok.BORDER_RADIUS_MEDIUM})
	listen(gtx, c.st, p.did, r, cursor = .Pointer)
	ops.tag(gtx.scene, p.did, ui.frame_string(gtx, fmt.tprintf("Dismiss %s", message)))
	ui.child_semantics(gtx, p.tid, p.did, r, {role = .Button, label = "Dismiss"})
}
