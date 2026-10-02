package primer

import "base:runtime"
import "jm:ui"
import "jm:ui/design"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// Dialogs: Dialog and ConfirmationDialog (primer-kit components/dialog.json,
// confirmation-dialog.json, Dialog/Dialog.module.css and Dialog.tsx), on
// overlays.odin's dismissal and focus.

// Dialog_Width is a dialog's width step: 296, 320, 480 or 640px
// (Dialog.module.css:135,147-158), names that mean other widths in Overlay
// and Popover. dialog_open's custom_width overrides it.
Dialog_Width :: enum u8 {
	Small,
	Medium,
	Large,
	XLarge,
}

@(private)
DIALOG_WIDTHS := [Dialog_Width]f32 {
	.Small  = 296,
	.Medium = 320,
	.Large  = 480,
	.XLarge = 640,
}

// Dialog_Height is a dialog's height: its content's, or 480 or 640px
// (Dialog.module.css:160-166).
Dialog_Height :: enum u8 {
	Auto,
	Small,
	Large,
}

@(private)
DIALOG_HEIGHTS := [Dialog_Height]f32 {
	.Auto  = 0,
	.Small = 480,
	.Large = 640,
}

// Dialog_Position is where a dialog sits at regular widths: floating in
// the middle, or a full-height sheet on the left or right edge.
Dialog_Position :: enum u8 {
	Center,
	Left,
	Right,
}

// Dialog_Narrow_Position is where a dialog sits below NARROW_WIDTH: floating in the
// middle, a sheet on the bottom edge, or filling the window.
Dialog_Narrow_Position :: enum u8 {
	Center,
	Bottom,
	Fullscreen,
}

// Dialog_Align is where a centred dialog sits vertically: in the middle,
// or 64px from the top or bottom.
Dialog_Align :: enum u8 {
	Center,
	Top,
	Bottom,
}

// Dialog_Button is one of a dialog's footer buttons: its label, its
// variant (Default, Primary or Danger; Primer's normal is Default),
// whether it takes focus as the dialog opens, its loading and disabled
// states, and clicked, set true on the frame it is activated. The dialog
// does not close on a footer button (Dialog.tsx:514-528).
Dialog_Button :: struct {
	content:    string,
	type:       Button_Variant,
	auto_focus: bool,
	loading:    bool,
	disabled:   bool,
	clicked:    ^bool,
}

// DIALOG_MIN_WIDTH, DIALOG_VIEWPORT_INSET and the short-viewport pair are
// a dialog's size bounds: at least 296px, at most the window less 64px
// each way, less 12px in a narrow window under 280px tall
// (Dialog.module.css:132-139,242-245).
DIALOG_MIN_WIDTH :: f32(296)
DIALOG_VIEWPORT_INSET :: tok.BASE_SIZE_64
DIALOG_SHORT_HEIGHT :: f32(280)
DIALOG_SHORT_INSET :: f32(12)

// DIALOG_START_SCALE is the scale a centred dialog enters from, with a
// fade, over OVERLAY_ENTER; a sheet slides in from off the window over
// DIALOG_SHEET instead (Dialog.module.css:24-52,168-211,262-283).
DIALOG_START_SCALE :: f32(0.5)
DIALOG_SHEET :: tok.Transition{250, {0.33, 1, 0.68, 1}}

// DIALOG_HEADER_MAX is the most of the window's height the header takes
// before it scrolls (Dialog.module.css:323-331).
DIALOG_HEADER_MAX :: f32(0.35)

// Dialog_Mode is how a dialog is laid out in its window, its position
// for the window's width resolved.
@(private)
Dialog_Mode :: enum u8 {
	Center,
	Left,
	Right,
	Bottom,
	Fullscreen,
}

// Dialog is an open dialog between dialog_open and dialog_close.
Dialog :: struct {
	visible:   bool,
	id:        ops.Area_Id,
	dismissed: Dismissal, // Escape for Escape and a backdrop click, Close_Button for the header's X
	open:      ^bool,
	gtx:       ^ui.Ctx,
	data:      ^Overlay_Data,
	layer:     ui.Overlay,
	moved:     bool, // a scale or slide is pushed
	faded:     bool,
	place:     ui.Flex,
	sized:     ui.Inset,
	box:       ui.Box,
	col:       ui.Flex,
	cap:       ui.Inset,
	body:      ui.Scroll_Box,
	pad:       ui.Inset,
	footer:    []Dialog_Button,
	mode:      Dialog_Mode,
	align:     Dialog_Align,
}

// dialog_open shows a modal dialog while open^ (dialog.json): a backdrop
// of --overlay-backdrop-bgColor over the whole window, fading in over
// 200ms, and the window: --overlay-bgColor under --shadow-floating-small
// with --borderRadius-large corners, a column of header, body and footer.
// The header pads 8px round the title (14px semibold) and subtitle (12px
// --fgColor-muted, 4px under it), each block padded 6px by 8px, and an
// invisible Close button; a 1px --borderColor-default rule runs under it.
// The body pads 16px and scrolls; the footer pads 16px round footer's
// buttons, 8px apart, at its end, wrapping, with a 1px rule over it while
// the body scrolls. The window is width wide (or custom_width), at least
// 296px and at most the window less 64px; its height is its content's or
// height's step, at most the window less 64px. It floats centred, or
// 64px from the top or bottom by align, or is a full-height sheet on the
// left or right by position; below NARROW_WIDTH narrow decides: centred,
// a bottom sheet, or the whole window. A floating dialog scales in from
// 0.5 and fades over OVERLAY_ENTER; a sheet slides in from off the window
// over DIALOG_SHEET.
//
// Escape (after any overlay or tooltip above it), the Close button, or a
// primary press on the backdrop then its release closes it; dismissed
// says which (a backdrop click reports Escape, as Primer's does). Nothing
// under the backdrop takes the pointer or the wheel; focus is trapped in
// the window, starts on focus.initial, else the first auto_focus footer
// button, else the Close button, and goes back on close. Arrow keys move
// between footer buttons. Lay the body out between open and close.
//
// Departures: alert dialogs read as modal dialogs (jm:ui has no
// alertdialog role); the footer wraps where Primer switches to one
// scrolling row once wrapping would leave the body under 48px
// (Dialog.tsx:364-389); the body
// is not a focusable scroll region; Tab into the footer does not pick
// the button nearest the direction of travel; a sheet's shadow keeps its rounded corners on the edge it
// touches; and a body taller than its share is capped by the header and
// footer heights measured the frame before.
dialog_open :: proc(
	gtx: ^ui.Ctx,
	open: ^bool,
	title: string,
	subtitle := "",
	footer: []Dialog_Button = nil,
	width := Dialog_Width.XLarge,
	custom_width: f32 = 0,
	height := Dialog_Height.Auto,
	position := Dialog_Position.Center,
	narrow := Dialog_Narrow_Position.Center,
	align := Dialog_Align.Center,
	focus := Overlay_Focus{},
	key: u64 = 0,
	loc := #caller_location,
) -> (dl: Dialog) {
	dl.id = ui.claim_id(gtx, key, loc)
	dl.open = open
	dl.gtx = gtx
	dl.footer = footer
	d := ui.widget_data(gtx, dl.id, Overlay_Data)
	dl.data = d
	backdrop := ui.id_mix(dl.id, 6)
	if open^ {
		dl.dismissed = dialog_events(gtx, dl.id, backdrop, open)
	}
	opening := open^ && !d.was_open
	first := dl.id
	for b in footer {
		if b.auto_focus {
			first = ui.id_mix(dl.id, 9)
			break
		}
	}
	if !overlay_focus(gtx, dl.id, d, open^, focus, first) {
		return
	}
	dl.visible = true
	vw, vh := gtx.viewport.x, gtx.viewport.y
	dl.mode = dialog_mode(gtx.viewport, position, narrow)
	dl.align = align
	if opening && (dl.mode == .Left || dl.mode == .Right || dl.mode == .Bottom) {
		d.slide.duration = DIALOG_SHEET.duration / 1000
	}
	dl.layer = ui.overlay_open(gtx, cs = ui.exact(gtx.viewport), root = true, cover = true)
	shade := bezier_ease(OVERLAY_ENTER.easing, ui.tween_update(&d.fade, gtx))
	ops.fill(gtx.scene, ops.Rect{0, 0, vw, vh}, fade(color(.Overlay_Backdrop_Bg_Color), shade))
	ops.input_area(gtx.scene, backdrop, ops.Rect{0, 0, vw, vh}, {.Press, .Release, .Move, .Enter, .Leave, .Scroll})
	ui.focus_scope_open(gtx, dl.id, trap = true)
	ui.key_interest(gtx, dl.id, .Escape, topmost = true)
	limits, radius := dialog_limits(gtx.viewport, dl.mode, width, custom_width, height)
	push_dialog_motion(&dl, limits)
	dl.place = dialog_place_open(gtx, dl.mode, align)
	look := new(Surface_Look, gtx.allocator)
	look^ = {dl.id, d, radius, .Overlay_Bg_Color, true, ui.frame_string(gtx, title)}
	dl.sized = ui.sized_open(gtx, limits, key = u64(ui.id_mix(dl.id, 2)))
	dl.box = ui.box_open(gtx, {paint = paint_surface, user = look}, key = u64(ui.id_mix(dl.id, 3)))
	ui.container_semantics(gtx, {role = .Dialog, label = ui.frame_string(gtx, title), description = ui.frame_string(gtx, subtitle), states = {.Modal}})
	dl.col = ui.column_open(gtx, align = .Fill, key = u64(ui.id_mix(dl.id, 4)))
	dialog_header(gtx, &dl, title, subtitle)
	header_h := ui.last_widget(gtx).size.y
	// The body takes what the header and footer leave: all of a fixed
	// height, or up to the cap of an auto one.
	fixed := limits.min.y == limits.max.y
	if fixed {
		ui.flexible(gtx, 1)
	}
	room := max(limits.max.y - header_h - d.body.y, 0)
	dl.cap = ui.sized_open(gtx, {max = {0, fixed ? 0 : room}}, key = u64(ui.id_mix(dl.id, 10)))
	dl.body = ui.scroll_box_open(gtx, key = u64(ui.id_mix(dl.id, 11)), fit = !fixed)
	dl.pad = ui.inset_open(gtx, ui.pad_all(tok.BASE_SIZE_16), key = u64(ui.id_mix(dl.id, 12)))
	return
}

// dialog_events reads a dialog's dismiss gestures: Escape on its id, and
// a primary release on the backdrop (Dialog.tsx:306-316). The backdrop
// hears a release only when it took the press, as the router sends a
// release to the area its press grabbed: a drag from the window out onto
// the backdrop releases on the window. Either closes open.
@(private)
dialog_events :: proc(gtx: ^ui.Ctx, id, backdrop: ops.Area_Id, open: ^bool) -> (g: Dismissal) {
	for e in ui.events(gtx, id) {
		if e.kind == .Key && e.key == .Escape {
			g = .Escape
		}
	}
	for e in ui.events(gtx, backdrop) {
		if e.kind == .Release && e.button == .Left {
			g = .Escape
		}
	}
	if g != .None {
		open^ = false
	}
	return
}

// dialog_mode is the layout a dialog takes in a window: its narrow
// position below NARROW_WIDTH, its regular one above.
@(private)
dialog_mode :: proc(window: ops.Size, position: Dialog_Position, narrow: Dialog_Narrow_Position) -> Dialog_Mode {
	if window.x < NARROW_WIDTH {
		switch narrow {
		case .Bottom:
			return .Bottom
		case .Fullscreen:
			return .Fullscreen
		case .Center:
		}
		return .Center
	}
	switch position {
	case .Left:
		return .Left
	case .Right:
		return .Right
	case .Center:
	}
	return .Center
}

// dialog_limits are a dialog window's size bounds and corners in a window
// for its mode (Dialog.module.css:132-285).
@(private)
dialog_limits :: proc(window: ops.Size, mode: Dialog_Mode, width: Dialog_Width, custom: f32, height: Dialog_Height) -> (l: ui.Size_Limits, c: Corners) {
	inset := DIALOG_VIEWPORT_INSET
	if window.x < NARROW_WIDTH && window.y <= DIALOG_SHORT_HEIGHT {
		inset = DIALOG_SHORT_INSET
	}
	w := custom if custom > 0 else DIALOG_WIDTHS[width]
	// min-width wins over max-width, as in CSS.
	w = max(min(w, window.x - inset), DIALOG_MIN_WIDTH)
	cap := max(window.y - inset, 0)
	h := DIALOG_HEIGHTS[height]
	r := tok.BORDER_RADIUS_LARGE
	c = corners_all(r)
	l = {min = {w, 0}, max = {w, cap}}
	if h > 0 {
		l.min.y, l.max.y = min(h, cap), min(h, cap)
	}
	switch mode {
	case .Center:
	case .Left:
		l.min.y, l.max.y = window.y, window.y
		c.tl, c.bl = 0, 0
	case .Right:
		l.min.y, l.max.y = window.y, window.y
		c.tr, c.br = 0, 0
	case .Bottom:
		l.min.x, l.max.x = window.x, window.x
		l.min.y, l.max.y = 0, max(window.y - DIALOG_VIEWPORT_INSET, 0)
		c.bl, c.br = 0, 0
	case .Fullscreen:
		l = {min = window, max = window}
		c = {}
	}
	return
}

// push_dialog_motion pushes a dialog's entry: a scale from 0.5 with a fade
// about the window's centre, or a sheet's slide in from off its edge.
@(private)
push_dialog_motion :: proc(dl: ^Dialog, limits: ui.Size_Limits) {
	gtx, d := dl.gtx, dl.data
	t := bezier_ease(OVERLAY_ENTER.easing, ui.tween_update(&d.slide, gtx))
	// Reduced motion stills the window; the backdrop's fade is not gated
	// (Dialog.module.css:70,168-170).
	if t >= 1 || gtx.reduce_motion {
		return
	}
	window := gtx.viewport
	size := d.size
	if size == {} {
		size = {limits.max.x, limits.max.y}
	}
	switch dl.mode {
	case .Center, .Fullscreen:
		ops.opacity_push(gtx.scene, t)
		dl.faded = true
		c := ops.Point{window.x / 2, window.y / 2}
		if dl.mode == .Center && dl.align == .Top {
			c.y = DIALOG_VIEWPORT_INSET + size.y / 2
		} else if dl.mode == .Center && dl.align == .Bottom {
			c.y = window.y - DIALOG_VIEWPORT_INSET - size.y / 2
		}
		k := DIALOG_START_SCALE + (1 - DIALOG_START_SCALE) * t
		ops.transform_push(gtx.scene, {f64(k), 0, 0, f64(k), f64(c.x * (1 - k)), f64(c.y * (1 - k))})
	case .Left:
		ops.transform_push(gtx.scene, ops.translate(-size.x * (1 - t), 0))
	case .Right:
		ops.transform_push(gtx.scene, ops.translate(size.x * (1 - t), 0))
	case .Bottom:
		ops.transform_push(gtx.scene, ops.translate(0, size.y * (1 - t)))
	}
	dl.moved = true
}

// dialog_place_open opens the flex that places the window in the
// backdrop for its mode and align; dialog_close closes it.
@(private)
dialog_place_open :: proc(gtx: ^ui.Ctx, mode: Dialog_Mode, align: Dialog_Align) -> ui.Flex {
	switch mode {
	case .Left, .Right:
		f := ui.row_open(gtx)
		if mode == .Right {
			ui.fill_space(gtx)
		}
		return f
	case .Bottom, .Fullscreen:
		f := ui.column_open(gtx, align = .Center)
		ui.fill_space(gtx)
		return f
	case .Center:
	}
	f := ui.column_open(gtx, align = .Center)
	switch align {
	case .Top:
		ui.spacer(gtx, DIALOG_VIEWPORT_INSET)
	case .Center, .Bottom:
		ui.fill_space(gtx)
	}
	return f
}

// dialog_header draws the title bar: the title and subtitle block, the
// Close button, and the rule under them.
@(private)
dialog_header :: proc(gtx: ^ui.Ctx, dl: ^Dialog, title, subtitle: string) {
	cap := ui.sized_open(gtx, {max = {0, gtx.viewport.y * DIALOG_HEADER_MAX}}, key = u64(ui.id_mix(dl.id, 20)))
	defer ui.close(&cap)
	box := ui.box_open(gtx, {padding = ui.pad_all(tok.BASE_SIZE_8), paint = paint_header_rule}, key = u64(ui.id_mix(dl.id, 21)))
	defer ui.close(&box)
	row := ui.row_open(gtx, key = u64(ui.id_mix(dl.id, 22)))
	defer ui.close(&row)
	ui.flexible(gtx, 1)
	{
		block := ui.inset_open(gtx, {tok.BASE_SIZE_8, tok.BASE_SIZE_6, tok.BASE_SIZE_8, tok.BASE_SIZE_6}, key = u64(ui.id_mix(dl.id, 23)))
		defer ui.close(&block)
		col := ui.column_open(gtx, gap = tok.BASE_SIZE_4, key = u64(ui.id_mix(dl.id, 24)))
		defer ui.close(&col)
		title_style := tok.Type_Style {
			weight      = tok.TEXT_TITLE_WEIGHT_LARGE,
			size        = tok.TEXT_BODY_SIZE_MEDIUM,
			line_height = tok.TEXT_BODY_SIZE_MEDIUM * tok.TEXT_BODY_LINE_HEIGHT_MEDIUM,
		}
		// Untagged: the window carries the title as its tag.
		dialog_text(gtx, title, title_style, color(.Fg_Color_Default), heading = true, tag = false, key = u64(ui.id_mix(dl.id, 25)))
		if subtitle != "" {
			sub := style(.Body_Small)
			sub.weight = tok.BASE_TEXT_WEIGHT_NORMAL
			dialog_text(gtx, subtitle, sub, color(.Fg_Color_Muted), heading = true, key = u64(ui.id_mix(dl.id, 26)))
		}
	}
	if icon_button(gtx, .X, "Close", .Invisible, key = u64(ui.id_mix(dl.id, 27))) {
		dialog_dismiss(dl, .Close_Button)
	}
	// Escape on the focused Close button closes the dialog, though the
	// button's tooltip would take it first (Dialog.tsx:222-238).
	for e in ui.events(gtx, ui.last_widget(gtx).id) {
		if e.kind == .Key && e.key == .Escape {
			dialog_dismiss(dl, .Escape)
		}
	}
}

// dialog_dismiss closes dl from inside its own layout, for gesture.
@(private)
dialog_dismiss :: proc(dl: ^Dialog, gesture: Dismissal) {
	dl.open^ = false
	if dl.dismissed == .None {
		dl.dismissed = gesture
	}
}

// paint_header_rule draws the 1px --borderColor-default line just under a
// header of size: its box-shadow 0 1px 0 (Dialog.module.css:329).
@(private)
paint_header_rule :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, size: ops.Size, user: rawptr) {
	ops.fill(gtx.scene, ops.Rect{0, size.y, size.x, tok.BORDER_WIDTH_THIN}, color(.Border_Color_Default))
}

// dialog_close closes a dialog opened by dialog_open: the body, then the
// footer and its buttons. A footer button's clicked is set here.
dialog_close :: proc(dl: ^Dialog) {
	if !dl.visible {
		return
	}
	dl.visible = false
	gtx := dl.gtx
	ui.close(&dl.pad)
	content := ui.last_widget(gtx).size.y
	ui.close(&dl.body)
	shown := ui.last_widget(gtx).size.y
	ui.close(&dl.cap)
	if len(dl.footer) > 0 {
		if content > shown + 0.5 {
			// The body scrolls: a rule between it and the footer
			// (Dialog.module.css:302-321).
			p := ui.widget_open(gtx, u64(ui.id_mix(dl.id, 30)))
			w := gtx.constraints.max.x
			ops.fill(gtx.scene, ops.Rect{0, 0, w, tok.BORDER_WIDTH_THIN}, color(.Border_Color_Default))
			ui.widget_close(gtx, &p, {size = {w, tok.BORDER_WIDTH_THIN}})
		}
		dialog_footer(gtx, dl)
		dl.data.body.y = ui.last_widget(gtx).size.y
	} else {
		dl.data.body.y = 0
	}
	ui.close(&dl.col)
	ui.close(&dl.box)
	ui.close(&dl.sized)
	if dl.mode == .Center {
		if dl.align == .Bottom {
			ui.spacer(gtx, DIALOG_VIEWPORT_INSET)
		} else {
			ui.fill_space(gtx)
		}
	}
	ui.close(&dl.place)
	if dl.moved {
		ops.transform_pop(gtx.scene)
	}
	if dl.faded {
		ops.opacity_pop(gtx.scene)
	}
	ui.focus_scope_close(gtx)
	dl.layer.discard = !dl.open^
	ui.overlay_close(&dl.layer)
}

// dialog_footer draws the footer buttons, the first auto_focus one in the
// scope dialog_open focuses first, with ArrowLeft and ArrowRight moving
// between them (Dialog.tsx:254-264, a focus zone that stops at the ends).
@(private)
dialog_footer :: proc(gtx: ^ui.Ctx, dl: ^Dialog) {
	pad := ui.inset_open(gtx, ui.pad_all(tok.BASE_SIZE_16), key = u64(ui.id_mix(dl.id, 31)))
	defer ui.close(&pad)
	row := ui.wrap_open(gtx, gap = tok.BASE_SIZE_8, justify = .End, key = u64(ui.id_mix(dl.id, 32)))
	defer ui.close(&row)
	ids := make([]ops.Area_Id, len(dl.footer), gtx.allocator)
	focused := false
	for b, i in dl.footer {
		// The scope goes inside a stack of its own: recorded between the
		// wrap's children it would not wrap the button, which the wrap
		// places later.
		scoped := b.auto_focus && !focused
		holder: ui.Stack
		if scoped {
			holder = ui.stack_open(gtx, key = u64(ui.id_mix(dl.id, 33)))
			ui.focus_scope_open(gtx, ui.id_mix(dl.id, 9))
			focused = true
		}
		st := Interaction.Disabled if b.disabled else Interaction.Live
		variant := b.type
		if variant != .Primary && variant != .Danger {
			variant = .Default
		}
		if button(gtx, b.content, variant, loading = b.loading, state = st, key = u64(ui.id_mix(dl.id, u64(40 + i)))) && b.clicked != nil {
			b.clicked^ = true
		}
		ids[i] = ui.last_widget(gtx).id
		if scoped {
			ui.focus_scope_close(gtx)
			ui.close(&holder)
		}
	}
	for id, i in ids {
		for e in ui.events(gtx, id) {
			if e.kind != .Key {
				continue
			}
			if e.key == .Left && i > 0 {
				ui.focus_request(gtx, ids[i - 1])
			} else if e.key == .Right && i + 1 < len(ids) {
				ui.focus_request(gtx, ids[i + 1])
			}
		}
	}
}

// dialog is dialog_open as a guard: `if primer.dialog(gtx, &open, "Title")
// { … }` lays the body out while the dialog shows and closes it, footer
// and all, at the end of the if.
@(deferred_in = dialog_guard_close)
dialog :: proc(
	gtx: ^ui.Ctx,
	open: ^bool,
	title: string,
	subtitle := "",
	footer: []Dialog_Button = nil,
	width := Dialog_Width.XLarge,
	custom_width: f32 = 0,
	height := Dialog_Height.Auto,
	position := Dialog_Position.Center,
	narrow := Dialog_Narrow_Position.Center,
	align := Dialog_Align.Center,
	focus := Overlay_Focus{},
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	h := ui.guard_hold(gtx, Dialog)
	h^ = dialog_open(gtx, open, title, subtitle, footer, width, custom_width, height, position, narrow, align, focus, key, loc)
	return h.visible
}

@(private = "file")
dialog_guard_close :: proc(
	gtx: ^ui.Ctx,
	open: ^bool,
	title: string,
	subtitle: string,
	footer: []Dialog_Button,
	width: Dialog_Width,
	custom_width: f32,
	height: Dialog_Height,
	position: Dialog_Position,
	narrow: Dialog_Narrow_Position,
	align: Dialog_Align,
	focus: Overlay_Focus,
	key: u64,
	loc: runtime.Source_Code_Location,
) {
	dialog_close(ui.guard_take(gtx, Dialog))
}

// Confirmation dialogs.

// Confirmation is how a confirmation dialog closed, on the frame it did.
Confirmation :: enum u8 {
	None,
	Confirm,
	Cancel,
	Close_Button,
	Escape, // Escape or a backdrop click
}

// Confirm_Focus forces which button a confirmation dialog focuses first.
Confirm_Focus :: enum u8 {
	Default, // confirm, or cancel when confirm is danger
	Cancel,
	Confirm,
}

// confirmation_dialog asks one question while open^ and closes on its
// answer (confirmation-dialog.json): a Dialog, medium (320px) wide by
// default, titled title, with content as its body text and a footer of
// cancel then confirm, confirm in confirm_type's variant. Focus starts on
// confirm, or on cancel when confirm is Danger, unless override_focus
// says otherwise; a loading button keeps focus and ignores activation. It
// returns the gesture on the frame it closes: Confirm, Cancel, the
// header's Close_Button, or Escape for Escape and a backdrop click.
//
// Departures: Dialog's; and it reads as a modal dialog with its content
// as text, where Primer's is an alertdialog.
confirmation_dialog :: proc(
	gtx: ^ui.Ctx,
	open: ^bool,
	title: string,
	content: string,
	cancel_content := "Cancel",
	confirm_content := "OK",
	confirm_type := Button_Variant.Default,
	cancel_loading := false,
	confirm_loading := false,
	override_focus := Confirm_Focus.Default,
	width := Dialog_Width.Medium,
	height := Dialog_Height.Auto,
	key: u64 = 0,
	loc := #caller_location,
) -> (answer: Confirmation) {
	cancelled, confirmed := false, false
	focus_cancel := confirm_type == .Danger
	switch override_focus {
	case .Cancel:
		focus_cancel = true
	case .Confirm:
		focus_cancel = false
	case .Default:
	}
	buttons := [2]Dialog_Button {
		{content = cancel_content, type = .Default, auto_focus = focus_cancel, loading = cancel_loading, clicked = &cancelled},
		{content = confirm_content, type = confirm_type, auto_focus = !focus_cancel, loading = confirm_loading, clicked = &confirmed},
	}
	dl := dialog_open(gtx, open, title, footer = buttons[:], width = width, height = height, key = key, loc = loc)
	if dl.visible {
		dialog_text(gtx, content, style(.Body_Medium), color(.Fg_Color_Default), key = u64(ui.id_mix(dl.id, 50)))
	}
	dialog_close(&dl)
	switch {
	case confirmed:
		answer = .Confirm
	case cancelled:
		answer = .Cancel
	case dl.dismissed == .Close_Button:
		answer = .Close_Button
	case dl.dismissed == .Escape:
		answer = .Escape
	}
	if answer == .Confirm || answer == .Cancel {
		// Closed after it was drawn: hand focus back now, as a close the
		// dialog saw itself would.
		open^ = false
		overlay_focus(gtx, dl.id, dl.data, false, {})
	}
	return
}

// dialog_text is text in st and c wrapped at the width offered: a dialog's
// title, subtitle and body text. With heading it reads as a heading.
@(private)
dialog_text :: proc(gtx: ^ui.Ctx, text: string, st: tok.Type_Style, c: ops.Color, heading := false, tag := true, key: u64 = 0, loc := #caller_location) {
	p := ui.widget_open(gtx, key, loc)
	w := gtx.constraints.max.x
	para := design.layout_style(gtx, text, st, font_for(gtx, st.weight), w if ui.is_finite(w) else 0)
	design.draw_paragraph(gtx, para, {}, c)
	said := ui.frame_string(gtx, text)
	if tag {
		ops.tag(gtx.scene, p.id, said, {0, 0, para.width, para.height})
	}
	ui.semantics(gtx, &p, {role = heading ? .Heading : .Text, label = said})
	ui.widget_close(gtx, &p, {{para.width, para.height}, para.lines[0].baseline if len(para.lines) > 0 else 0})
}
