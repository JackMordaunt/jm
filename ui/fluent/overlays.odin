package fluent

import "base:runtime"
import "core:strings"
import "jm:ui"
import "jm:ui/design"
import tok "jm:ui/fluent/tokens"
import "jm:ui/ops"

// Components that paint above the page: menus, dialogs and tooltips, from
// the fluent-kit's components/menu.json, dialog.json and tooltip.json and
// the styles files they cite (useMenuPopoverStyles, useMenuItemStyles,
// useDialogSurfaceStyles, useTooltipStyles and their siblings). Each
// opens a ui.overlay, so it draws last and takes no space in the layout
// around it. To anchor a menu to a widget, put both in a ui.stack: the
// overlay is placed from the stack's origin.
//
// A menu and a dialog come in both of ui's forms: the explicit pair
// (menu_open with menu_close, dialog_open with dialog_close) and the
// guard (`if fluent.menu(gtx, &open) { fluent.menu_item(gtx, "Cut") }`),
// whose body runs only while the popup shows and which closes itself at
// the end of the if (see ui/guards.odin). The handle lives in the
// widget's own data slot between open and close.

// MENU_* are the popover's and items' hard-coded metrics (menu.json
// layout: useMenuPopoverStyles.styles.ts:12-26, useMenuListStyles.
// styles.ts:11-20, useMenuItemStyles.styles.ts:22-39,83-123).
@(private)
MENU_MIN_WIDTH :: f32(138)
@(private)
MENU_MAX_WIDTH :: f32(300)
@(private)
MENU_PAD :: f32(4)
@(private)
MENU_GAP :: f32(2)
@(private)
MENU_ITEM_MIN_H :: f32(32)
@(private)
MENU_ITEM_GAP :: f32(4)
@(private)
MENU_ICON :: f32(20)
@(private)
MENU_CONTENT_PAD :: f32(2)
@(private)
MENU_DIVIDER_PAD :: f32(4)
@(private)
MENU_HEADER_H :: f32(32)
@(private)
MENU_HEADER_PAD :: f32(8)
// MENU_SLIDE is how far the popover slides in as it opens (menu.json
// states.open, MenuSurfaceMotion.ts:8-42).
@(private)
MENU_SLIDE :: f32(10)

// Menu is an open menu between menu_open and menu_close: the overlay and
// containers to close, and the width every item lays out at.
Menu :: struct {
	visible: bool,
	overlay: ui.Overlay,
	box:     ui.Box,
	col:     ui.Flex,
	id:      ops.Area_Id,
	open:    ^bool,
	width:   f32, // the items' content width this frame
	alpha:   f32,
	paint:   ^Menu_Paint, // the popover's paint record, which learns its size at close
	slid:    bool, // a slide transform is pushed inside the overlay
}

// Menu_Data is what a menu keeps between frames: the widest item seen
// last frame, which sizes the popover this frame (an immediate-mode
// menu cannot measure its items before laying them out), and the enter
// motion.
@(private)
Menu_Data :: struct {
	width, seen: f32,
	was_open:    bool,
	enter:       ui.Tween,
}

@(private)
Menu_Paint :: struct {
	id:    ops.Area_Id,
	alpha: f32,
	size:  ops.Size, // the popover's size, set when its box closes
}

@(private, thread_local)
current_menu: ^Menu

// MENU_TRIGGER_GAP is the space between a menu and its trigger.
@(private)
MENU_TRIGGER_GAP :: f32(4)

// menu_open opens the popover while open^ from anchor, its trigger's
// rect in the enclosing container (a 32px trigger at the origin by
// default, as in a stack with its menu button): below it, MENU_TRIGGER_GAP
// away, flush with its start, flipped above or shifted along the edge
// when that would leave the window (ui.popup_open). The popover is Neutral_Background1 inside a 1px
// Transparent_Stroke border with borderRadiusMedium corners and shadow16,
// 4px of padding around a column of items 2px apart, between 138 and
// 300px wide. It enters by fading in and sliding 10px into place over
// DURATION_SLOWER with CURVE_DECELERATE_MID and closes at once. A press
// outside closes it; a click on an item closes it unless the item
// persists. It slides in from the anchor's side, whichever side it
// opened on. Returns visible false, and lays nothing out, when closed.
//
// Not done, for want of jm:ui support: arrow-key travel between items,
// Home/End and typeahead (jm:ui moves focus only by press; a focused
// item still takes Enter, Space and Escape), hover- and context-opened
// menus, and submenus (an item can show the chevron; the caller
// composes the second menu).
menu_open :: proc(gtx: ^ui.Ctx, open: ^bool, anchor := ops.Rect{0, 0, 0, 32}, key: u64 = 0, loc := #caller_location) -> (m: Menu) {
	id := ui.claim_id(gtx, key, loc)
	d := ui.widget_data(gtx, id, Menu_Data)
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
	// Escape reaches the menu's own id by key_interest below, whether or
	// not an item holds focus.
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
		d.width = 0
	}
	t := design.bezier_ease(tok.CURVE_DECELERATE_MID, ui.tween_update(&d.enter, gtx))
	m.visible = true
	m.id = id
	m.open = open
	m.alpha = t
	m.width = clamp(d.seen, MENU_MIN_WIDTH - 2 * (MENU_PAD + tok.STROKE_WIDTH_THIN), MENU_MAX_WIDTH - 2 * (MENU_PAD + tok.STROKE_WIDTH_THIN))
	d.width = d.seen
	d.seen = 0

	m.overlay = ui.popup_open(gtx, anchor, id, .Below, .Start, MENU_TRIGGER_GAP)
	ui.key_interest(gtx, id, .Escape)
	// Scrim: an invisible catch-all under the popover; a press on it closes.
	ops.input_area(gtx.scene, scrim_id, ops.Rect{-1e5, -1e5, 2e5, 2e5}, {.Press, .Release, .Move, .Enter, .Leave, .Scroll})
	// The slide comes from the anchor: down into place below it, up into
	// place above it.
	dir: f32 = ui.placed_side(gtx, id, .Below) == .Above ? 1 : -1
	if slide := MENU_SLIDE * (1 - t); slide > 0 {
		ops.transform_push(gtx.scene, ops.translate(0, dir * slide))
		m.slid = true
	}
	mp := new(Menu_Paint, gtx.allocator)
	mp^ = {id = id, alpha = t}
	m.paint = mp
	m.box = ui.box_open(gtx, {padding = ui.pad_all(MENU_PAD + tok.STROKE_WIDTH_THIN), paint = paint_menu, user = mp}, key = 1)
	m.col = ui.column_open(gtx, gap = MENU_GAP, key = 2)
	ui.container_semantics(gtx, {role = .Menu})
	current_menu = ui.widget_data(gtx, id, Menu)
	current_menu^ = m
	return
}

// menu_close closes a menu opened by menu_open, whether it showed or not.
menu_close :: proc(m: ^Menu) {
	if !m.visible {
		return
	}
	ui.close(&m.col)
	ui.close(&m.box)
	// Closed by an item this frame: draw nothing and catch nothing, or
	// the scrim would take the next click (input routes against the
	// last frame's hits).
	if m.slid {
		ops.transform_pop(m.overlay.gtx.scene)
	}
	m.overlay.discard = !m.open^
	ui.popup_close(&m.overlay, m.paint.size)
	m.visible = false
	current_menu = nil
}

// menu is menu_open as a guard: `if fluent.menu(gtx, &open) { … }` lays
// the items out only while the menu shows and closes it at the end of
// the if (see ui/guards.odin).
@(deferred_in = menu_guard_close)
menu :: proc(gtx: ^ui.Ctx, open: ^bool, anchor := ops.Rect{0, 0, 0, 32}, key: u64 = 0, loc := #caller_location) -> bool {
	m := menu_open(gtx, open, anchor, key, loc)
	return m.visible
}

@(private = "file")
menu_guard_close :: proc(gtx: ^ui.Ctx, open: ^bool, anchor: ops.Rect, key: u64, loc: runtime.Source_Code_Location) {
	if current_menu != nil {
		menu_close(current_menu)
	}
}

// paint_menu paints the popover under its items: shadow16, the fill, the
// border, and an input area so presses on the popover's own padding
// never reach the scrim.
@(private)
paint_menu :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, size: ops.Size, user: rawptr) {
	mp := (^Menu_Paint)(user)
	mp.size = size
	area := ops.Rect{0, 0, size.x, size.y}
	rr := ops.Round_Rect{area, tok.BORDER_RADIUS_MEDIUM}
	for l in tok.SHADOW16.layers {
		design.paint_shadow_layer(gtx, rr, l.x, l.y, l.blur, fade(color(l.color), mp.alpha))
	}
	ops.fill(gtx.scene, rr, fade(color(.Neutral_Background1), mp.alpha))
	stroke_inside(gtx, rr, fade(color(.Transparent_Stroke), mp.alpha), tok.STROKE_WIDTH_THIN)
	ops.input_area(gtx.scene, ui.id_mix(mp.id, 0xfffe), rr, {.Press, .Release, .Move, .Enter, .Leave, .Scroll})
}

// Menu_Check is an item's checkmark column: none, a checkbox that
// toggles checked^ on click, or a radio the caller selects from the click.
Menu_Check :: enum u8 {
	None,
	Checkbox,
	Radio,
}

// menu_item is one command in an open menu: a 32px row of the popover's
// width with an optional 20px icon, the label, secondary content (a
// shortcut) at the end in caption1, and a chevron when it opens a
// submenu the caller composes. Rest is Neutral_Background1 with
// Neutral_Foreground2 text and icon; hovered and pressed step to their
// Hover and Pressed tokens with the icon turning Neutral_Foreground2_
// Brand_Selected and filled; nothing transitions (menu.json states).
// check adds the checkmark column, showing Icon.Checkmark while checked^.
// A click returns true and closes the menu unless persist; Escape on a
// focused item closes it too. Under a subtext the label and subtext
// stack (menu.json layout multiline).
menu_item :: proc(
	gtx: ^ui.Ctx,
	label: string,
	ic := Icon.None,
	secondary := "",
	subtext := "",
	check := Menu_Check.None,
	checked: ^bool = nil,
	submenu := false,
	persist := false,
	disabled := false,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	m := current_menu
	p := ui.widget_open(gtx, key, loc)
	st := state
	if disabled {
		st = .Disabled
	}
	t := shape_style(gtx, label, style(.Body1))
	sub := shape_style(gtx, subtext, style(.Caption2))
	sec := shape_style(gtx, secondary, style(.Caption1))
	sec.height = tok.LINE_HEIGHT_BASE300 // shares the label's 20px line (styles.ts:90-95)
	// Natural width: 4px of item padding a side, the columns 4px apart,
	// the content padded 2px.
	w := 2 * tok.SPACING_VERTICAL_SNUDGE + 2 * MENU_CONTENT_PAD + max(t.width, sub.width)
	if check != .None {
		w += MENU_ICON + MENU_ITEM_GAP
	}
	if ic != .None {
		w += MENU_ICON + MENU_ITEM_GAP
	}
	if secondary != "" {
		w += MENU_ITEM_GAP + 2 * MENU_CONTENT_PAD + sec.width
	}
	if submenu {
		w += MENU_ITEM_GAP + MENU_ICON
	}
	if m != nil {
		d := ui.widget_data(gtx, m.id, Menu_Data)
		d.seen = max(d.seen, w)
		w = max(w, m.width)
	}
	w = min(w, MENU_MAX_WIDTH - 2 * (MENU_PAD + tok.STROKE_WIDTH_THIN))
	h := max(MENU_ITEM_MIN_H, 2 * tok.SPACING_VERTICAL_SNUDGE + t.height + (subtext != "" ? sub.height : 0))
	sz := ui.constrain(gtx.constraints, {w, h})
	area := ops.Rect{0, 0, sz.x, sz.y}
	c := control(gtx, p.id, area, st)
	if c.clicked {
		if check == .Checkbox && checked != nil {
			checked^ = !checked^
		}
		if !persist && m != nil {
			m.open^ = false
		}
	}
	if c.st != nil && c.focused {
		for e in ui.events(gtx, p.id) {
			if e.kind == .Key && e.key == .Escape && m != nil {
				m.open^ = false
			}
		}
	}
	alpha: f32 = m != nil ? m.alpha : 1
	bg := color_for({.Neutral_Background1, .Neutral_Background1_Hover, .Neutral_Background1_Pressed, .Neutral_Background1}, c)
	fg := color_for({.Neutral_Foreground2, .Neutral_Foreground2_Hover, .Neutral_Foreground2_Pressed, .Neutral_Foreground_Disabled}, c)
	dim := color_for({.Neutral_Foreground3, .Neutral_Foreground3_Hover, .Neutral_Foreground3_Pressed, .Neutral_Foreground_Disabled}, c)
	icon_color := color_for({.Neutral_Foreground2, .Neutral_Foreground2_Brand_Selected, .Neutral_Foreground2_Brand_Selected, .Neutral_Foreground_Disabled}, c)
	shown := (c.hovered || c.pressed) && !c.disabled ? filled(ic) : ic
	ops.fill(gtx.scene, ops.Round_Rect{area, tok.BORDER_RADIUS_MEDIUM}, fade(bg, alpha))
	x := tok.SPACING_VERTICAL_SNUDGE
	top := tok.SPACING_VERTICAL_SNUDGE
	if check != .None {
		if checked != nil && checked^ {
			// 2px down, so it centres on the first text line (styles.ts:131-133).
			icon(gtx, .Checkmark, {x + 2, top + 2}, 16, fade(fg, alpha))
		}
		x += MENU_ICON + MENU_ITEM_GAP
	}
	if ic != .None {
		icon(gtx, shown, {x, top}, MENU_ICON, fade(icon_color, alpha))
		x += MENU_ICON + MENU_ITEM_GAP
	}
	x += MENU_CONTENT_PAD
	draw_text(gtx, t, {x, top}, fade(fg, alpha))
	if subtext != "" {
		draw_text(gtx, sub, {x, top + t.height}, fade(dim, alpha))
	}
	end := sz.x - tok.SPACING_VERTICAL_SNUDGE
	if submenu {
		end -= MENU_ICON
		icon(gtx, .Chevron_Right, {end, (sz.y - MENU_ICON) / 2}, MENU_ICON, fade(icon_color, alpha))
		end -= MENU_ITEM_GAP
	}
	if secondary != "" {
		end -= MENU_CONTENT_PAD + sec.width
		draw_text(gtx, sec, {end, subtext != "" ? (sz.y - sec.height) / 2 : top}, fade(dim, alpha))
	}
	paint_focus_outline(gtx, c, {area, tok.BORDER_RADIUS_MEDIUM})
	listen(gtx, c.st, p.id, area)
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, label))
	ui.semantics(
		gtx,
		&p,
		{
			role = .Menu_Item,
			label = label,
			value = secondary,
			description = subtext,
			states = state_if(check != .None && checked != nil && checked^, {.Checked}) + state_if(submenu, {.Expandable}) + state_if(c.disabled, {.Disabled}),
		},
	)
	ui.widget_close(gtx, &p, {sz, top + baseline_of(t)})
	return c.clicked
}

// menu_divider is the 1px Neutral_Stroke2 rule between items, 4px above
// and below. It spans the items, not the popover's padding: the styles
// file's -5px margin (useMenuDividerStyles.styles.ts:14) has no
// equivalent in a column.
menu_divider :: proc(gtx: ^ui.Ctx, key: u64 = 0, loc := #caller_location) {
	p := ui.widget_open(gtx, key, loc)
	w := current_menu != nil ? current_menu.width : MENU_MIN_WIDTH
	sz := ui.constrain(gtx.constraints, {w, 2 * MENU_DIVIDER_PAD + tok.STROKE_WIDTH_THIN})
	ops.fill(gtx.scene, ops.Rect{0, MENU_DIVIDER_PAD, sz.x, tok.STROKE_WIDTH_THIN}, color(.Neutral_Stroke2))
	ui.semantics(gtx, &p, {role = .Separator})
	ui.widget_close(gtx, &p, {size = sz})
}

// menu_header is a group's heading: a 32px row padded 8px, caption1
// semibold in Neutral_Foreground3 (useMenuGroupHeaderStyles.styles.ts:12-23).
menu_header :: proc(gtx: ^ui.Ctx, text: string, key: u64 = 0, loc := #caller_location) {
	p := ui.widget_open(gtx, key, loc)
	t := shape_style(gtx, text, style(.Caption1_Strong))
	w := current_menu != nil ? current_menu.width : MENU_MIN_WIDTH
	sz := ui.constrain(gtx.constraints, {max(w, t.width + 2 * MENU_HEADER_PAD), MENU_HEADER_H})
	draw_text(gtx, t, {MENU_HEADER_PAD, (sz.y - t.height) / 2}, color(.Neutral_Foreground3))
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, text))
	ui.semantics(gtx, &p, {role = .Text, label = text})
	ui.widget_close(gtx, &p, {sz, (sz.y - t.height) / 2 + baseline_of(t)})
}

// Dialog_Kind is dialog.json's modalType.
Dialog_Kind :: enum u8 {
	Modal, // a dimmed backdrop; Escape and a backdrop click close it
	Alert, // as modal, but only an action or Escape closes it
	Non_Modal, // no backdrop; the title carries a close button
}

// DIALOG_* are the surface's constants (dialog.json layout, constants.ts).
@(private)
DIALOG_MAX_WIDTH :: f32(600)
@(private)
DIALOG_PAD :: f32(24)
@(private)
DIALOG_GAP :: f32(8)
@(private)
DIALOG_NARROW_WIDTH :: f32(480)
// DIALOG_SCALE is the scale the surface enters from (Scale.ts:20-31).
@(private)
DIALOG_SCALE :: f32(0.85)

// Dialog is an open dialog between dialog_open and dialog_close.
Dialog :: struct {
	visible:  bool,
	overlay:  ui.Overlay,
	centered: ui.Centered,
	box:      ui.Box,
	col:      ui.Flex,
	id:       ops.Area_Id,
	open:     ^bool,
	kind:     Dialog_Kind,
	width:    f32, // the content width inside the padding
	scaled:   bool,
}

@(private)
Dialog_Data :: struct {
	was_open: bool,
	enter:    ui.Tween,
	backdrop: ui.Tween,
}

@(private)
Dialog_Paint :: struct {
	open: ^bool,
}

@(private, thread_local)
current_dialog: ^Dialog

// dialog_open shows the surface while open^, centred over window (the
// root constraints) behind the backdrop: Neutral_Background1 inside a 1px
// Transparent_Stroke border, borderRadiusXLarge corners, shadow64, 24px
// of padding, as wide as the window up to 600px (the whole window at
// 480px and under). The surface scales in from 0.85 over
// DURATION_GENTLE with CURVE_DECELERATE_MID while the backdrop fades in
// over the same with CURVE_EASY_EASE. A backdrop press closes a modal
// dialog, not an alert; Escape closes any once the surface has focus.
// Lay the body out with dialog_title, text_block and dialog_actions
// between open and close, or as the guard's body.
//
// Departures: the surface and body do not fade with the scale, and the
// exit is instant (jm:ui's ops have no group alpha, and a closed dialog
// takes no input); a non-modal dialog's title close button comes from
// dialog_title; focus is not trapped (jm:ui has no Tab traversal).
dialog_open :: proc(gtx: ^ui.Ctx, open: ^bool, window: ops.Size, kind := Dialog_Kind.Modal, key: u64 = 0, loc := #caller_location) -> (d: Dialog) {
	id := ui.claim_id(gtx, key, loc)
	data := ui.widget_data(gtx, id, Dialog_Data)
	if !open^ {
		data.was_open = false
		return
	}
	// A backdrop press closes a modal dialog; Escape, sent to the
	// dialog's id by key_interest below, closes any kind, focused or not.
	for e in ui.events(gtx, id) {
		if e.kind == .Press && kind == .Modal {
			open^ = false
		}
		if e.kind == .Key && e.key == .Escape {
			open^ = false
		}
	}
	if !open^ {
		data.was_open = false
		return
	}
	if !data.was_open {
		data.was_open = true
		data.enter = {to = 1, duration = tok.DURATION_GENTLE / 1000}
		data.backdrop = {to = 1, duration = tok.DURATION_GENTLE / 1000}
	}
	k := DIALOG_SCALE + (1 - DIALOG_SCALE) * design.bezier_ease(tok.CURVE_DECELERATE_MID, ui.tween_update(&data.enter, gtx))
	shade := design.bezier_ease(tok.CURVE_EASY_EASE, ui.tween_update(&data.backdrop, gtx))

	d.visible = true
	d.id = id
	d.open = open
	d.kind = kind
	// The overlay is the surface's column: as wide as the window up to
	// 600px, centred; the backdrop is painted back out to the window's
	// edges from there.
	max_w := window.x <= DIALOG_NARROW_WIDTH ? window.x : min(window.x, DIALOG_MAX_WIDTH)
	left := (window.x - max_w) / 2
	d.width = max_w - 2 * (DIALOG_PAD + tok.STROKE_WIDTH_THIN)
	d.overlay = ui.overlay_open(gtx, {left, 0}, cs = ui.loose({max_w, window.y}), root = true)
	ui.key_interest(gtx, id, .Escape)
	if kind != .Non_Modal {
		ops.fill(gtx.scene, ops.Rect{-left, 0, window.x, window.y}, fade(color(.Background_Overlay), shade))
		ops.input_area(gtx.scene, id, ops.Rect{-left, 0, window.x, window.y}, {.Press, .Release, .Move, .Enter, .Leave, .Scroll})
	}
	if k < 1 {
		ops.transform_push(gtx.scene, scale_about({max_w / 2, window.y / 2}, k))
		d.scaled = true
	}
	d.centered = ui.centered_open(gtx, key = 1)
	dp := new(Dialog_Paint, gtx.allocator)
	dp.open = open
	d.box = ui.box_open(gtx, {padding = ui.pad_all(DIALOG_PAD + tok.STROKE_WIDTH_THIN), paint = paint_dialog, user = dp}, key = 2)
	d.col = ui.column_open(gtx, gap = DIALOG_GAP, align = .Fill, key = 3)
	// Unlabelled until dialog_title names it: the title is a child laid
	// out after the column opens.
	ui.container_semantics(gtx, {role = .Dialog, states = state_if(kind != .Non_Modal, {.Modal})})
	current_dialog = ui.widget_data(gtx, id, Dialog)
	current_dialog^ = d
	return
}

// dialog_close closes a dialog opened by dialog_open.
dialog_close :: proc(d: ^Dialog) {
	if !d.visible {
		return
	}
	ui.close(&d.col)
	ui.close(&d.box)
	ui.close(&d.centered)
	if d.scaled {
		ops.transform_pop(d.overlay.gtx.scene)
	}
	d.overlay.discard = !d.open^ // closed by an action this frame
	ui.close(&d.overlay)
	d.visible = false
	current_dialog = nil
}

// dialog is dialog_open as a guard: `if fluent.dialog(gtx, &open, window)
// { … }` lays the body out while the dialog shows and closes it at the
// end of the if.
@(deferred_in = dialog_guard_close)
dialog :: proc(gtx: ^ui.Ctx, open: ^bool, window: ops.Size, kind := Dialog_Kind.Modal, key: u64 = 0, loc := #caller_location) -> bool {
	d := dialog_open(gtx, open, window, kind, key, loc)
	return d.visible
}

@(private = "file")
dialog_guard_close :: proc(gtx: ^ui.Ctx, open: ^bool, window: ops.Size, kind: Dialog_Kind, key: u64, loc: runtime.Source_Code_Location) {
	if current_dialog != nil {
		dialog_close(current_dialog)
	}
}

@(private)
paint_dialog :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, size: ops.Size, user: rawptr) {
	dp := (^Dialog_Paint)(user)
	area := ops.Rect{0, 0, size.x, size.y}
	rr := ops.Round_Rect{area, tok.BORDER_RADIUS_XLARGE}
	for e in ui.events(gtx, id) {
		if e.kind == .Key && e.key == .Escape {
			dp.open^ = false
		}
	}
	paint_shadow(gtx, rr, tok.SHADOW64)
	ops.fill(gtx.scene, rr, color(.Neutral_Background1))
	stroke_inside(gtx, rr, color(.Transparent_Stroke), tok.STROKE_WIDTH_THIN)
	// The surface swallows its own presses so they do not reach the
	// backdrop, and takes focus on one so Escape reaches it.
	ops.input_area(gtx.scene, id, rr, {.Press, .Release, .Move, .Enter, .Leave, .Scroll, .Key})
}

// dialog_title is the title row: subtitle1 text, and for a non-modal
// dialog (or when close is asked for) a transparent close button at the
// end that closes the dialog (useDialogTitleStyles.styles.ts:17-62).
dialog_title :: proc(gtx: ^ui.Ctx, text: string, close := false, key: u64 = 0, loc := #caller_location) {
	d := current_dialog
	if d != nil {
		// The title names the dialog's column, by its handle.
		ui.container_semantics(gtx, {role = .Dialog, label = text, states = state_if(d.kind != .Non_Modal, {.Modal})}, d.col.index)
	}
	r := ui.row_open(gtx, align = .Start, key = key, loc = loc)
	defer ui.close(&r)
	text_block(gtx, text, .Subtitle1, color(.Neutral_Foreground1), d != nil ? d.width - 32 - DIALOG_GAP : 0, heading = true)
	if d != nil && (close || d.kind == .Non_Modal) {
		ui.fill_space(gtx)
		if button(gtx, "", .Transparent, .Dismiss, name = "Close", key = 1) {
			d.open^ = false
		}
	}
}

// dialog_actions_open is the actions row: buttons DIALOG_GAP apart,
// hugging the end edge (or the start), or spanning the width when
// fluid (useDialogActionsStyles.styles.ts:15-72).
dialog_actions_open :: proc(gtx: ^ui.Ctx, start := false, fluid := false, key: u64 = 0, loc := #caller_location) -> ui.Flex {
	r := ui.row_open(gtx, gap = DIALOG_GAP, align = fluid ? .Fill : .Center, key = key, loc = loc)
	if !start && !fluid {
		ui.fill_space(gtx)
	}
	return r
}

// dialog_actions is dialog_actions_open as a guard.
@(deferred_in = dialog_actions_guard_close)
dialog_actions :: proc(gtx: ^ui.Ctx, start := false, fluid := false, key: u64 = 0, loc := #caller_location) -> bool {
	dialog_actions_open(gtx, start, fluid, key, loc)
	return true
}

@(private = "file")
dialog_actions_guard_close :: proc(gtx: ^ui.Ctx, start: bool, fluid: bool, key: u64, loc: runtime.Source_Code_Location) {
	ui.innermost_close(gtx, .Flex)
}

// Tooltip_Appearance is tooltip.json's appearance: the theme's top
// surface, or the static dark bubble that is the same in every theme.
Tooltip_Appearance :: enum u8 {
	Normal,
	Inverted,
}

// Tooltip_Position is which side of its anchor the bubble sits on.
Tooltip_Position :: enum u8 {
	Above,
	Below,
}

// TOOLTIP_* are the bubble's constants (tooltip.json layout,
// useTooltipStyles.styles.ts:18-36,53; constants.ts:1-4).
@(private)
TOOLTIP_MAX_WIDTH :: f32(240)
@(private)
TOOLTIP_PAD :: ui.Padding{11, 4, 11, 6}
@(private)
TOOLTIP_ARROW :: f32(6)
// TOOLTIP_GAP is the space between the bubble and its anchor without an
// arrow (the positioning offset, constants.ts).
@(private)
TOOLTIP_GAP :: f32(4)

// TOOLTIP_SHOW_DELAY and TOOLTIP_HIDE_DELAY are showDelay and hideDelay
// (tooltip.json behaviour, Tooltip.types.ts:61-66,98-103), in seconds.
TOOLTIP_SHOW_DELAY :: f32(0.25)
TOOLTIP_HIDE_DELAY :: f32(0.25)

// Tooltip_Timer is a tooltip's retained state: how long its anchor has
// been hovered or focused, how long since it stopped, and whether the
// bubble is up.
Tooltip_Timer :: struct {
	over, gone: f32,
	shown:      bool,
	dismissed:  bool, // Escape hid it; stays until the anchor is left
}

// tooltip shows text in a bubble beside the anchor of size box whose
// control is c, after TOOLTIP_SHOW_DELAY of hover or keyboard focus, and
// hides it TOOLTIP_HIDE_DELAY after both end, or at once on Escape. Call
// it from inside the anchor widget after control, with the anchor's id;
// the timer lives in the anchor's widget data. The bubble is caption1
// text padded 4/11/6px inside a 1px Transparent_Stroke border with
// borderRadiusMedium corners, at most 240px wide, on Neutral_Background1
// with Neutral_Foreground1 text (or the static inverted pair), under a
// shadow of shadow8's geometry, centred above or below the anchor 4px
// away, or 6px with the arrow, flipped to the other side or shifted
// along the edge when that would leave the window, the arrow following
// (ui.popup_open). There is no enter or exit motion (tooltip.json
// behaviour no-motion).
tooltip :: proc(
	gtx: ^ui.Ctx,
	id: ops.Area_Id,
	c: Control,
	text: string,
	box: ops.Size,
	appearance := Tooltip_Appearance.Normal,
	position := Tooltip_Position.Above,
	arrow := false,
) {
	if text == "" || c.st == nil {
		return
	}
	tm := ui.widget_data(gtx, ui.id_mix(id, 0x7100), Tooltip_Timer)
	// The bubble's own hover counts: moving onto it within the hide
	// delay keeps it open (tooltip.json behaviour hide).
	bubble_id := ui.id_mix(id, 0x7101)
	over := ((c.hovered || c.focused) && !c.disabled) || (tm.shown && ui.widget_state(gtx, bubble_id).hovered)
	if over {
		for e in ui.events(gtx, id) {
			if e.kind == .Key && e.key == .Escape {
				tm.dismissed = true
			}
		}
		tm.gone = 0
		tm.over += gtx.dt
		if tm.over >= TOOLTIP_SHOW_DELAY && !tm.dismissed {
			tm.shown = true
		} else if !tm.shown && !tm.dismissed {
			ui.request_frame(gtx, TOOLTIP_SHOW_DELAY - tm.over)
		}
	} else {
		tm.over = 0
		tm.dismissed = false
		if tm.shown {
			tm.gone += gtx.dt
			if tm.gone >= TOOLTIP_HIDE_DELAY {
				tm.shown = false
			} else {
				ui.request_frame(gtx, TOOLTIP_HIDE_DELAY - tm.gone)
			}
		}
	}
	if !tm.shown {
		return
	}
	lines := wrap(gtx, text, style(.Caption1), TOOLTIP_MAX_WIDTH - TOOLTIP_PAD.left - TOOLTIP_PAD.right - 2 * tok.STROKE_WIDTH_THIN)
	tw, th := lines_size(lines)
	w := tw + TOOLTIP_PAD.left + TOOLTIP_PAD.right + 2 * tok.STROKE_WIDTH_THIN
	h := th + TOOLTIP_PAD.top + TOOLTIP_PAD.bottom + 2 * tok.STROKE_WIDTH_THIN
	gap := arrow ? TOOLTIP_ARROW : TOOLTIP_GAP
	asked := position == .Above ? ops.Side.Above : ops.Side.Below
	o := ui.popup_open(gtx, {0, 0, box.x, box.y}, bubble_id, asked, .Center, gap)
	defer ui.popup_close(&o, {w, h})
	// The bubble as a widget of the popup, so it can declare itself.
	bp := ui.widget_open(gtx, 0x7102)
	defer ui.widget_close(gtx, &bp, {size = {w, h}})
	side, shift := ui.placed(gtx, bubble_id, asked)
	fill := color(appearance == .Inverted ? .Neutral_Background_Static : .Neutral_Background1)
	fg := color(appearance == .Inverted ? .Neutral_Foreground_Static_Inverted : .Neutral_Foreground1)
	rr := ops.Round_Rect{{0, 0, w, h}, tok.BORDER_RADIUS_MEDIUM}
	paint_shadow(gtx, rr, tok.SHADOW8)
	ops.fill(gtx.scene, rr, fill)
	if arrow {
		// At the anchor's centre, undoing any shift placement made, clear
		// of the rounded corners.
		cx := clamp(w / 2 - shift.x, TOOLTIP_ARROW + tok.BORDER_RADIUS_MEDIUM, w - TOOLTIP_ARROW - tok.BORDER_RADIUS_MEDIUM)
		pts: [3]ops.Point
		if side == .Above {
			pts = {{cx - TOOLTIP_ARROW, h}, {cx + TOOLTIP_ARROW, h}, {cx, h + TOOLTIP_ARROW}}
		} else {
			pts = {{cx - TOOLTIP_ARROW, 0}, {cx + TOOLTIP_ARROW, 0}, {cx, -TOOLTIP_ARROW}}
		}
		ops.fill(gtx.scene, ui.polygon(gtx, pts[:]), fill)
	}
	stroke_inside(gtx, rr, color(.Transparent_Stroke), tok.STROKE_WIDTH_THIN)
	y := tok.STROKE_WIDTH_THIN + TOOLTIP_PAD.top
	for l in lines {
		draw_text(gtx, l, {tok.STROKE_WIDTH_THIN + TOOLTIP_PAD.left, y}, fg)
		y += l.height
	}
	ops.input_area(gtx.scene, bubble_id, rr, {.Enter, .Leave, .Move})
	ops.tag(gtx.scene, bubble_id, ui.frame_string(gtx, text))
	ui.part_semantics(gtx, &bp, bubble_id, rr.rect, {role = .Tooltip, label = text})
}

// wrap breaks s into shaped lines no wider than width, a word at a
// time: each word is shaped once and joined to its line by the space's
// advance, and a word wider than width keeps a line to itself. Lines
// are shaped whole at the end, so their glyphs are the style's. Built
// on gtx.allocator, like everything a frame shapes.
@(private)
wrap :: proc(gtx: ^ui.Ctx, s: string, st: tok.Type_Style, width: f32) -> []Text {
	out := make([dynamic]Text, gtx.allocator)
	if s == "" {
		return out[:]
	}
	space := shape_style(gtx, " ", st).width
	words := strings.split(s, " ", gtx.allocator)
	line_start, line_w := 0, f32(0)
	for w, i in words {
		ww := shape_style(gtx, w, st).width
		if i > line_start && line_w + space + ww > width + 0.5 {
			append(&out, shape_style(gtx, strings.join(words[line_start:i], " ", gtx.allocator), st))
			line_start, line_w = i, ww
			continue
		}
		line_w = i == line_start ? ww : line_w + space + ww
	}
	append(&out, shape_style(gtx, strings.join(words[line_start:], " ", gtx.allocator), st))
	return out[:]
}

// lines_size is the widest line and the lines' total height.
@(private)
lines_size :: proc(lines: []Text) -> (w, h: f32) {
	for l in lines {
		w = max(w, l.width)
		h += l.height
	}
	return
}

// text_block lays s out wrapped to width (or unwrapped when 0) at a type
// role, as one widget: dialog content, a card's body. Lines are
// start-aligned. The text is selectable unless selectable is false.
text_block :: proc(gtx: ^ui.Ctx, s: string, role: Type_Role, color: ops.Color, width: f32 = 0, key: u64 = 0, selectable := true, heading := false, loc := #caller_location) -> ui.Dims {
	p := ui.widget_open(gtx, key, loc)
	para := layout_style(gtx, s, style(role), width)
	sz := ui.constrain(gtx.constraints, {width > 0 ? max(width, para.width) : para.width, para.height})
	if selectable {
		selectable_paragraph(gtx, p.id, para, {}, color, {0, 0, sz.x, sz.y})
	} else {
		draw_paragraph(gtx, para, {}, color)
	}
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, s))
	ui.semantics(gtx, &p, {role = heading ? .Heading : .Text, label = s})
	return ui.widget_close(gtx, &p, {sz, para.lines[0].baseline})
}

// scale_about is a scale by k about point c: the scale, then the shift
// that puts c back where it was.
@(private)
scale_about :: proc(c: ops.Point, k: f32) -> ops.Affine {
	return {f64(k), 0, 0, f64(k), f64(c.x * (1 - k)), f64(c.y * (1 - k))}
}
