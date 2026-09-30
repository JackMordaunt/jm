package fluent

import "core:fmt"
import "core:strings"
import "jm:ui"
import "jm:ui/design"
import tok "jm:ui/fluent/tokens"
import "jm:ui/ops"

// Notifications: the toast a Toaster dispatches into a corner of the
// window and the message bar a page keeps inline, from the fluent-kit's
// components/toast.json and message-bar.json and the styles files they
// cite (useToasterStyles, useToastContainerStyles, useToastStyles,
// useToastTitleStyles, useToastBodyStyles, useMessageBarStyles and their
// siblings).

// Intent is the status a toast or message bar carries: which icon it
// shows and, for a bar, which colours it takes.
Intent :: enum u8 {
	Info,
	Success,
	Warning,
	Error,
}

// intent_icon is the filled icon an intent shows by default
// (message-bar.json behaviour default-icon): Info, CheckmarkCircle,
// Warning and, for error, Error_Circle in place of DiamondDismiss, which
// the icon set does not carry.
@(private)
intent_icon :: proc(i: Intent) -> Icon {
	switch i {
	case .Info:
		return .Info_Filled
	case .Success:
		return .Checkmark_Circle_Filled
	case .Warning:
		return .Warning_Filled
	case .Error:
		return .Error_Circle_Filled
	}
	return .None
}

// Toast_Position is which edge and corner of the window a toaster's
// column sits in.
Toast_Position :: enum u8 {
	Bottom_End,
	Bottom_Start,
	Top_End,
	Top_Start,
	Top,
	Bottom,
}

// Toast_Appearance is the toast's surface: the theme's top surface, or
// the inverted one.
Toast_Appearance :: enum u8 {
	Normal,
	Inverted,
}

// TOAST_* are the column's and the toast's hard-coded metrics
// (toast.json layout: useToasterStyles.styles.ts:15-25,
// getPositionStyles.ts:10-69, useToastContainerStyles.styles.ts:14-22,
// useToastStyles.styles.ts:12-24, useToastTitleStyles.styles.ts:14-36,
// useToastBodyStyles.styles.ts:13-32).
@(private)
TOAST_WIDTH :: f32(292)
@(private)
TOAST_OFFSET_V :: f32(16)
@(private)
TOAST_OFFSET_H :: f32(20)
@(private)
TOAST_GAP :: f32(16)
@(private)
TOAST_PAD :: f32(12)
@(private)
TOAST_TITLE_LINE :: f32(20)
@(private)
TOAST_MEDIA :: f32(16)
@(private)
TOAST_MEDIA_PAD_TOP :: f32(2)
@(private)
TOAST_MEDIA_PAD_RIGHT :: f32(8)
@(private)
TOAST_ACTION_PAD :: f32(12)
@(private)
TOAST_BODY_PAD :: f32(6)
@(private)
TOAST_SUBTITLE_PAD :: f32(4)
@(private)
TOAST_DISMISS :: f32(20)

// TOAST_TIMEOUT is the default timeout, in seconds (toast.json behaviour
// defaults); TOAST_STICKY keeps a toast until dismissed.
TOAST_TIMEOUT :: f32(3)
TOAST_STICKY :: f32(-1)

// Toast is one dispatched notification and its life: its text and
// intent, its timeout clock, and the enter and exit motions.
Toast :: struct {
	id:       int,
	title:    string, // the caller's, kept as long as the toast shows
	body:     string,
	subtitle: string,
	intent:   Intent,
	timeout:  f32, // seconds, TOAST_STICKY for none
	elapsed:  f32, // of the timeout, once the enter motion is done
	enter:    ui.Tween,
	exit:     ui.Tween,
	leaving:  bool,
}

// Toasts is a toaster's queue: the caller owns it, toast_push adds to it
// and toaster draws it, dropping toasts whose exit motion has finished.
Toasts :: struct {
	items:   [dynamic]Toast,
	next_id: int,
}

// toast_push queues a toast and returns its id. The strings must outlive
// the toast: literals, or the caller's own storage, never frame memory.
toast_push :: proc(ts: ^Toasts, title: string, body := "", intent := Intent.Info, timeout := TOAST_TIMEOUT, subtitle := "") -> int {
	ts.next_id += 1
	append(
		&ts.items,
		Toast {
			id = ts.next_id,
			title = title,
			body = body,
			subtitle = subtitle,
			intent = intent,
			timeout = timeout,
			enter = {to = 1, duration = (tok.DURATION_NORMAL + tok.DURATION_SLOWER) / 1000},
		},
	)
	return ts.next_id
}

// toast_dismiss starts toast id's exit motion; it leaves the queue when
// that ends. An unknown id does nothing.
toast_dismiss :: proc(ts: ^Toasts, id: int) {
	for &t in ts.items {
		if t.id == id && !t.leaving {
			t.leaving = true
			t.exit = {to = 1, duration = (tok.DURATION_NORMAL + tok.DURATION_SLOWER) / 1000}
		}
	}
}

// toast_dismiss_all dismisses every toast, as Escape in a toaster does.
toast_dismiss_all :: proc(ts: ^Toasts) {
	for t in ts.items {
		toast_dismiss(ts, t.id)
	}
}

// toasts_destroy frees the queue.
toasts_destroy :: proc(ts: ^Toasts) {
	delete(ts.items)
}

// toast_progress is a toast's enter or exit motion this frame: the
// height's share, over DURATION_NORMAL on CURVE_EASY_EASE_MAX, and the
// opacity's, over DURATION_SLOWER after that stagger (toast.json states
// open; CollapseDelayed). Both are 1 for a toast at rest.
@(private)
toast_progress :: proc(gtx: ^ui.Ctx, t: ^Toast) -> (height, alpha: f32) {
	normal := tok.DURATION_NORMAL / 1000
	slower := tok.DURATION_SLOWER / 1000
	tw := t.leaving ? &t.exit : &t.enter
	ui.tween_update(tw, gtx)
	e := tw.t
	if t.leaving {
		// The reverse: opacity first, then the height.
		alpha = 1 - design.bezier_ease(tok.CURVE_EASY_EASE_MAX, clamp(e / slower, 0, 1))
		height = 1 - design.bezier_ease(tok.CURVE_EASY_EASE_MAX, clamp((e - slower) / normal, 0, 1))
		return
	}
	height = design.bezier_ease(tok.CURVE_EASY_EASE_MAX, clamp(e / normal, 0, 1))
	alpha = design.bezier_ease(tok.CURVE_EASY_EASE_MAX, clamp((e - normal) / slower, 0, 1))
	return
}

// toaster draws ts's toasts in a column at position in a window of the
// given size, on an overlay over everything else, and advances their
// clocks: a toast times out timeout seconds after its enter motion ends,
// or never when TOAST_STICKY; hovering one pauses its clock when
// pause_on_hover; its dismiss button, or Delete while it has focus,
// dismisses it, and Escape dismisses them all. limit, when set, caps the
// toasts shown at once; the rest wait their turn. Each toast is a
// 292px-wide surface of Neutral_Background1 (or the inverted one) inside
// a 1px Transparent_Stroke border with borderRadiusMedium corners and
// shadow8, padded 12px: the intent's 16px icon, the title in
// fontSizeBase300 semibold on a 20px line, the dismiss button in the last
// column, then the body in body1 6px below and the subtitle in
// fontSizeBase200 4px below that; the dismiss button is tagged
// "Dismiss <title>". Toasts are 16px apart, the newest
// nearest the window's edge. Returns the id of the toast whose dismiss
// was pressed this frame, or 0.
//
// Departures: footer actions and the update-in-place, priority and
// window-blur pausing are not built; the toast's own focus does not
// keep the clock paused, only its hover; an exiting toast's height
// collapses in the column but the surface below it is not clipped.
toaster :: proc(
	gtx: ^ui.Ctx,
	ts: ^Toasts,
	window: ops.Size,
	position := Toast_Position.Bottom_End,
	appearance := Toast_Appearance.Normal,
	pause_on_hover := false,
	limit := 0,
	key: u64 = 0,
	loc := #caller_location,
) -> int {
	if len(ts.items) == 0 {
		return 0
	}
	id := ui.claim_id(gtx, key, loc)
	pressed := 0
	x: f32
	switch position {
	case .Bottom_End, .Top_End:
		x = window.x - TOAST_OFFSET_H - TOAST_WIDTH
	case .Bottom_Start, .Top_Start:
		x = TOAST_OFFSET_H
	case .Top, .Bottom:
		x = (window.x - TOAST_WIDTH) / 2
	}
	top := position == .Top || position == .Top_End || position == .Top_Start
	o := ui.overlay_open(gtx, {x, 0}, cs = ui.loose({TOAST_WIDTH, window.y}), root = true)
	defer ui.close(&o)
	// Both columns place the newest nearest their edge (toast.json
	// behaviour stacking): a top column stacks down from it, a bottom one
	// up, each walking the queue newest first. With a limit the oldest
	// limit toasts show and the rest wait their turn.
	y: f32 = top ? TOAST_OFFSET_V : window.y - TOAST_OFFSET_V
	gone := make([dynamic]int, gtx.allocator)
	n := len(ts.items)
	for k in 0 ..< n {
		i := n - 1 - k
		t := &ts.items[i]
		if limit > 0 && i >= limit {
			continue
		}
		h_share, alpha := toast_progress(gtx, t)
		if t.leaving && h_share <= 0 && t.exit.t >= t.exit.duration {
			append(&gone, i)
			continue
		}
		tid := ui.id_mix(id, u64(t.id))
		st := ui.widget_state(gtx, tid)
		a := ui.activate_from_events(gtx, tid, st, {})
		_ = a
		for e in ui.events(gtx, tid) {
			if e.kind == .Key && st.focused {
				if e.key == .Delete {
					toast_dismiss(ts, t.id)
				} else if e.key == .Escape {
					toast_dismiss_all(ts)
				}
			}
		}
		full := toast_height(gtx, t^)
		h := full * h_share
		if !t.leaving && t.enter.t >= t.enter.duration && t.timeout >= 0 {
			if !(pause_on_hover && st.hovered) {
				t.elapsed += gtx.dt
				if t.elapsed >= t.timeout {
					toast_dismiss(ts, t.id)
				} else {
					ui.request_frame(gtx, t.timeout - t.elapsed)
				}
			}
		}
		at: ops.Point
		if top {
			at = {0, y}
			y += h + TOAST_GAP
		} else {
			y -= h
			at = {0, y}
			y -= TOAST_GAP
		}
		if h > 0 {
			if paint_toast(gtx, t, tid, st, at, full, alpha, appearance) {
				pressed = t.id
				toast_dismiss(ts, t.id)
			}
		}
	}
	#reverse for i in gone {
		ordered_remove(&ts.items, i)
	}
	return pressed
}

// toast_lines are a toast's wrapped body and subtitle at the content
// width: the surface less its padding, border and the icon column.
@(private)
toast_content_width :: proc() -> f32 {
	return TOAST_WIDTH - 2 * (TOAST_PAD + tok.STROKE_WIDTH_THIN) - TOAST_MEDIA - TOAST_MEDIA_PAD_RIGHT - TOAST_ACTION_PAD - TOAST_DISMISS
}

@(private)
toast_height :: proc(gtx: ^ui.Ctx, t: Toast) -> f32 {
	w := toast_content_width()
	h := 2 * (TOAST_PAD + tok.STROKE_WIDTH_THIN)
	title := wrap(gtx, t.title, control_style(.Medium, tok.FONT_WEIGHT_SEMIBOLD), w)
	h += f32(max(len(title), 1)) * TOAST_TITLE_LINE
	if t.body != "" {
		_, bh := lines_size(wrap(gtx, t.body, style(.Body1), w))
		h += TOAST_BODY_PAD + bh
	}
	if t.subtitle != "" {
		sub := control_style(.Small, tok.FONT_WEIGHT_REGULAR)
		sub.line_height = tok.FONT_SIZE_BASE200 // the subtitle's line is its font size (toast.json notes)
		_, sh := lines_size(wrap(gtx, t.subtitle, sub, w))
		h += TOAST_SUBTITLE_PAD + sh
	}
	return h
}

// paint_toast draws t at pos in the column with its full height, faded
// by alpha, and its dismiss button; returns true when that button is
// pressed.
@(private)
paint_toast :: proc(gtx: ^ui.Ctx, t: ^Toast, tid: ops.Area_Id, st: ^ui.Widget_State, pos: ops.Point, h, alpha: f32, appearance: Toast_Appearance) -> bool {
	inverted := appearance == .Inverted
	bg := color(inverted ? .Neutral_Background_Inverted : .Neutral_Background1)
	fg := color(inverted ? .Neutral_Foreground_Inverted2 : .Neutral_Foreground1)
	sub_fg := color(inverted ? .Neutral_Foreground_Inverted2 : .Neutral_Foreground2)
	media: ops.Color
	switch t.intent {
	case .Info:
		media = color(inverted ? .Neutral_Foreground_Inverted : .Neutral_Foreground2)
	case .Success:
		media = color(inverted ? .Status_Success_Foreground_Inverted : .Status_Success_Foreground1)
	case .Warning:
		media = color(inverted ? .Status_Warning_Foreground_Inverted : .Status_Warning_Foreground1)
	case .Error:
		media = color(inverted ? .Status_Danger_Foreground_Inverted : .Status_Danger_Foreground1)
	}
	area := ops.Rect{pos.x, pos.y, TOAST_WIDTH, h}
	rr := ops.Round_Rect{area, tok.BORDER_RADIUS_MEDIUM}
	for l in tok.SHADOW8.layers {
		design.paint_shadow_layer(gtx, rr, l.x, l.y, l.blur, fade(color(l.color), alpha))
	}
	ops.fill(gtx.scene, rr, fade(bg, alpha))
	stroke_inside(gtx, rr, fade(color(.Transparent_Stroke), alpha), tok.STROKE_WIDTH_THIN)
	// The toast itself, under its dismiss button: focusable and
	// hoverable, so Delete and the hover pause reach it.
	ops.input_area(gtx.scene, tid, rr, CLICK_KINDS)
	ops.tag(gtx.scene, tid, ui.frame_string(gtx, t.title))
	pad := TOAST_PAD + tok.STROKE_WIDTH_THIN
	x := pos.x + pad
	y := pos.y + pad
	icon(gtx, intent_icon(t.intent), {x, y + TOAST_MEDIA_PAD_TOP}, TOAST_MEDIA, fade(media, alpha))
	x += TOAST_MEDIA + TOAST_MEDIA_PAD_RIGHT
	w := toast_content_width()
	title := wrap(gtx, t.title, control_style(.Medium, tok.FONT_WEIGHT_SEMIBOLD), w)
	for l in title {
		draw_text(gtx, l, {x, y}, fade(fg, alpha))
		y += TOAST_TITLE_LINE
	}
	if t.body != "" {
		y += TOAST_BODY_PAD
		for l in wrap(gtx, t.body, style(.Body1), w) {
			draw_text(gtx, l, {x, y}, fade(fg, alpha))
			y += l.height
		}
	}
	if t.subtitle != "" {
		y += TOAST_SUBTITLE_PAD
		sub := control_style(.Small, tok.FONT_WEIGHT_REGULAR)
		sub.line_height = tok.FONT_SIZE_BASE200
		for l in wrap(gtx, t.subtitle, sub, w) {
			draw_text(gtx, l, {x, y}, fade(sub_fg, alpha))
			y += l.height
		}
	}
	// The dismiss button in the last column, padded 12px from the text.
	dx := pos.x + TOAST_WIDTH - pad - TOAST_DISMISS
	dismiss := ops.Rect{dx, pos.y + pad, TOAST_DISMISS, TOAST_DISMISS}
	did := ui.id_mix(tid, 0x71)
	dst := ui.widget_state(gtx, did)
	act := ui.activate_from_events(gtx, did, dst, dismiss)
	dc := Control{}
	dc.st = dst
	dc.hovered, dc.pressed, dc.focused = dst.hovered, dst.pressed, dst.focused
	dc.focus_visible = dc.focused && ui.focus_visible(gtx)
	dc.state = design.effective_state(dc.base)
	dfg := color_for({inverted ? .Neutral_Foreground_Inverted : .Neutral_Foreground2, .Neutral_Foreground2_Brand_Hover, .Neutral_Foreground2_Brand_Pressed, .Neutral_Foreground_Disabled}, dc)
	icon(gtx, .Dismiss, {dismiss.x + 2, dismiss.y + 2}, 16, fade(dfg, alpha))
	paint_focus_outline(gtx, dc, {dismiss, tok.BORDER_RADIUS_MEDIUM})
	ops.input_area(gtx.scene, did, dismiss, CLICK_KINDS)
	ops.tag(gtx.scene, did, ui.frame_string(gtx, fmt.tprintf("Dismiss %s", t.title)))
	c := Control{}
	c.st = st
	c.focus_visible = st.focused && ui.focus_visible(gtx)
	paint_focus_outline(gtx, c, rr)
	return act.clicked
}

// Message_Bar_Layout is how a bar arranges itself: on one line while it
// fits and two when it does not (auto), or always one or the other.
Message_Bar_Layout :: enum u8 {
	Auto,
	Single_Line,
	Multiline,
}

// Message_Bar_Shape is the bar's corners: rounded for an inline bar,
// square for one spanning the page.
Message_Bar_Shape :: enum u8 {
	Rounded,
	Square,
}

// MESSAGE_BAR_MIN_HEIGHT is the bar's minimum height, the styles file's
// one constant (message-bar.json layout grid,
// useMessageBarStyles.styles.ts:14-27).
@(private)
MESSAGE_BAR_MIN_HEIGHT :: f32(36)
@(private)
MESSAGE_BAR_ICON :: f32(20)

// Message_Bar_Memo is what a bar keeps between frames: whether its single
// line fit last frame, which decides an auto layout this frame (an
// immediate-mode bar cannot measure its content before laying it out).
@(private)
Message_Bar_Memo :: struct {
	multiline: bool,
	single_w:  f32, // the width the single line needed when it last fit
}

// message_bar is the inline status strip: the intent's icon (or ic), a
// body of a body1Strong title running into body1 text, action buttons,
// and, when dismissable, a transparent Dismiss button as the container
// action. On one line the row is icon, body, actions, dismiss, centred
// vertically, at least 36px tall, padded spacingHorizontalM on the left
// and the same after the body and between actions; on two lines the
// body wraps, the dismiss keeps the first row's end, and the actions
// row follows right-aligned with spacingVerticalMNudge above and
// spacingVerticalS below. Auto picks two lines once the single line
// would overflow the width offered. The bar takes the intent's
// background and border with a strokeWidthThin border and
// borderRadiusMedium corners (none when square). Returns the index of the
// action clicked, or -1, and whether the dismiss was pressed.
//
// Departures: the bar does not announce; MessageBarGroup's enter and
// exit fades are the caller's to do (jm:ui has no group alpha); the
// auto layout lags a frame behind a width change.
message_bar :: proc(
	gtx: ^ui.Ctx,
	intent: Intent,
	title: string,
	text: string,
	actions: []string = nil,
	dismissable := false,
	layout := Message_Bar_Layout.Auto,
	shape := Message_Bar_Shape.Rounded,
	ic := Icon.None,
	key: u64 = 0,
	loc := #caller_location,
) -> (action: int, dismissed: bool) {
	action = -1
	p := ui.widget_open(gtx, key, loc)
	memo := ui.widget_data(gtx, p.id, Message_Bar_Memo)
	cs := gtx.constraints
	width := ui.is_finite(cs.max.x) ? cs.max.x : 0
	bg, border, ic_color: ops.Color
	switch intent {
	case .Info:
		bg, border, ic_color = color(.Neutral_Background3), color(.Neutral_Stroke1), color(.Neutral_Foreground3)
	case .Error:
		bg, border, ic_color = color(.Status_Danger_Background1), color(.Status_Danger_Border1), color(.Status_Danger_Foreground1)
	case .Warning:
		bg, border, ic_color = color(.Status_Warning_Background1), color(.Status_Warning_Border1), color(.Status_Warning_Foreground3)
	case .Success:
		bg, border, ic_color = color(.Status_Success_Background1), color(.Status_Success_Border1), color(.Status_Success_Foreground1)
	}
	shown := ic != .None ? ic : intent_icon(intent)
	strong := shape_style(gtx, title, style(.Body1_Strong))
	space := shape_style(gtx, " ", style(.Body1)).width
	// The actions' and dismiss's widths, to know what the body may take.
	acts := make([]Text, len(actions), gtx.allocator)
	acts_w: f32
	for a, i in actions {
		acts[i] = shape_style(gtx, a, control_style(.Medium, tok.FONT_WEIGHT_SEMIBOLD))
		acts_w += max(acts[i].width + 2 * tok.SPACING_HORIZONTAL_M + 2 * tok.STROKE_WIDTH_THIN, 96) + tok.SPACING_HORIZONTAL_M
	}
	dismiss_w: f32 = dismissable ? 32 + tok.SPACING_HORIZONTAL_M : 0
	lead := tok.STROKE_WIDTH_THIN + tok.SPACING_HORIZONTAL_M + MESSAGE_BAR_ICON + tok.SPACING_HORIZONTAL_S
	body_text := shape_style(gtx, text, style(.Body1))
	single_w := lead + strong.width + (title != "" && text != "" ? space : 0) + body_text.width + tok.SPACING_HORIZONTAL_M + acts_w + dismiss_w + tok.STROKE_WIDTH_THIN
	multiline := layout == .Multiline
	if layout == .Auto && width > 0 {
		if memo.multiline {
			multiline = width < memo.single_w
		} else {
			multiline = single_w > width + 0.5
			memo.single_w = single_w
		}
		memo.multiline = multiline
	}
	rad := shape == .Rounded ? tok.BORDER_RADIUS_MEDIUM : tok.BORDER_RADIUS_NONE
	// Layout.
	body_w := (width > 0 ? width : single_w) - lead - tok.SPACING_HORIZONTAL_M - tok.STROKE_WIDTH_THIN - dismiss_w
	if !multiline {
		body_w -= acts_w
	}
	lines: []Bar_Line
	body_h: f32
	if multiline {
		lines = wrap_prefixed(gtx, title, text, max(body_w, 40))
		// Lines at x > 0 share the previous line (the title's).
		for l, i in lines {
			if i == 0 || l.x == 0 {
				body_h += l.t.height
			}
		}
	} else {
		body_h = body_text.height
	}
	if !multiline && title != "" {
		body_h = max(body_h, strong.height)
	}
	h: f32
	if multiline {
		h = tok.STROKE_WIDTH_THIN + tok.SPACING_VERTICAL_MNUDGE + body_h
		if len(actions) > 0 {
			h += tok.SPACING_VERTICAL_MNUDGE + 32
		}
		h += tok.SPACING_VERTICAL_S + tok.STROKE_WIDTH_THIN
	} else {
		h = max(MESSAGE_BAR_MIN_HEIGHT, body_h + 2 * (tok.STROKE_WIDTH_THIN + tok.SPACING_VERTICAL_XS))
	}
	sz := ui.constrain(cs, {width > 0 ? width : single_w, h})
	area := ops.Rect{0, 0, sz.x, sz.y}
	rr := ops.Round_Rect{area, rad}
	ops.fill(gtx.scene, rr, bg)
	stroke_inside(gtx, rr, border, tok.STROKE_WIDTH_THIN)
	// Icon, at the first line (multiline) or centred (single).
	icon_y := multiline ? tok.STROKE_WIDTH_THIN + tok.SPACING_VERTICAL_MNUDGE : (sz.y - MESSAGE_BAR_ICON) / 2
	icon(gtx, shown, {tok.STROKE_WIDTH_THIN + tok.SPACING_HORIZONTAL_M, icon_y}, MESSAGE_BAR_ICON, ic_color)
	fg := color(.Neutral_Foreground1)
	x := lead
	y := multiline ? icon_y : (sz.y - body_h) / 2
	if multiline {
		for l, i in lines {
			if i > 0 && l.x == 0 {
				y += lines[i - 1].t.height
			}
			draw_text(gtx, l.t, {x + l.x, y}, fg)
		}
		if len(lines) > 0 {
			y += lines[len(lines) - 1].t.height
		}
	} else {
		if title != "" {
			draw_text(gtx, strong, {x, y}, fg)
			x += strong.width + (text != "" ? space : 0)
		}
		draw_text(gtx, body_text, {x, y}, fg)
	}
	// Actions: single line after the body; multiline on their own row at
	// the end.
	ax := multiline ? sz.x - tok.STROKE_WIDTH_THIN - tok.SPACING_VERTICAL_M - dismiss_w + (dismissable ? tok.SPACING_HORIZONTAL_M : 0) : sz.x - tok.STROKE_WIDTH_THIN - dismiss_w
	ay := multiline ? sz.y - tok.STROKE_WIDTH_THIN - tok.SPACING_VERTICAL_S - 32 : (sz.y - 32) / 2
	#reverse for a, i in actions {
		bw := max(acts[i].width + 2 * tok.SPACING_HORIZONTAL_M + 2 * tok.STROKE_WIDTH_THIN, 96)
		ax -= bw + tok.SPACING_HORIZONTAL_M
		if message_bar_button(gtx, p.id, u64(i + 1), a, acts[i], {ax, ay, bw, 32}, .Secondary) {
			action = i
		}
	}
	if dismissable {
		dr := ops.Rect{sz.x - tok.STROKE_WIDTH_THIN - tok.SPACING_HORIZONTAL_M - 32, multiline ? tok.STROKE_WIDTH_THIN + tok.SPACING_VERTICAL_XXS : (sz.y - 32) / 2, 32, 32}
		dismissed = message_bar_button(gtx, p.id, 0x7f, "Dismiss", {}, dr, .Transparent, .Dismiss)
	}
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, title != "" ? title : text))
	ui.widget_close(gtx, &p, {sz, y})
	return
}

// Bar_Line is one line of a wrapped message bar body: a shaped run and
// its x offset from the body's start.
@(private)
Bar_Line :: struct {
	t: Text,
	x: f32,
}

// wrap_prefixed wraps a bold title running into regular text: the title
// heads the first line in body1Strong and the text's words follow it in
// body1 while they fit, then wrap at the full width. The title is not
// broken; a word wider than width keeps a line to itself.
@(private)
wrap_prefixed :: proc(gtx: ^ui.Ctx, title, text: string, width: f32) -> []Bar_Line {
	out := make([dynamic]Bar_Line, gtx.allocator)
	st := style(.Body1)
	space := shape_style(gtx, " ", st).width
	x: f32
	if title != "" {
		strong := shape_style(gtx, title, style(.Body1_Strong))
		append(&out, Bar_Line{strong, 0})
		x = strong.width + space
	}
	if text == "" {
		return out[:]
	}
	words := strings.split(text, " ", gtx.allocator)
	start, line_w := 0, f32(0)
	line_x := x
	emit :: proc(gtx: ^ui.Ctx, out: ^[dynamic]Bar_Line, words: []string, st: tok.Type_Style, x: f32) {
		append(out, Bar_Line{shape_style(gtx, strings.join(words, " ", gtx.allocator), st), x})
	}
	for w, i in words {
		ww := shape_style(gtx, w, st).width
		room := width - line_x
		if i > start && line_w + space + ww > room + 0.5 {
			emit(gtx, &out, words[start:i], st, line_x)
			start, line_w, line_x = i, ww, 0
			continue
		}
		if i == start && line_x > 0 && ww > room + 0.5 {
			// Not even one word fits beside the title: start below it.
			line_x = 0
		}
		line_w = i == start ? ww : line_w + space + ww
	}
	emit(gtx, &out, words[start:], st, line_x)
	return out[:]
}

// message_bar_button is one of a bar's buttons, laid at r inside the
// bar's own widget (the bar is one widget, so its buttons are areas of
// its own id): the secondary appearance for an action, the transparent
// one with an icon for the dismiss. Returns true when clicked.
@(private)
message_bar_button :: proc(gtx: ^ui.Ctx, owner: ops.Area_Id, key: u64, name: string, t: Text, r: ops.Rect, appearance: Appearance, ic := Icon.None) -> bool {
	bid := ui.id_mix(owner, key)
	st := ui.widget_state(gtx, bid)
	act := ui.activate_from_events(gtx, bid, st, r)
	c := Control{}
	c.st = st
	c.hovered, c.pressed, c.focused = st.hovered, st.pressed, st.focused
	c.state = design.effective_state(c.base)
	roles := appearance_roles(appearance)
	k := corners_all(tok.BORDER_RADIUS_MEDIUM)
	ops.fill(gtx.scene, rounded(gtx, r, k), color_for(roles.bg, c))
	border := c.focused && ui.focus_visible(gtx) ? color(.Stroke_Focus2) : color_for(roles.border, c)
	stroke_inside_corners(gtx, r, k, border, tok.STROKE_WIDTH_THIN)
	if ic != .None {
		icon(gtx, ic, {r.x + (r.w - 20) / 2, r.y + (r.h - 20) / 2}, 20, color_for(roles.icon, c))
	} else {
		draw_text(gtx, t, {r.x + (r.w - t.width) / 2, r.y + (r.h - t.height) / 2}, color_for(roles.text, c))
	}
	paint_focus_inset(gtx, c, r, k, paint_border = false)
	ops.input_area(gtx.scene, bid, r, CLICK_KINDS)
	ops.tag(gtx.scene, bid, ui.frame_string(gtx, name))
	return act.clicked
}
