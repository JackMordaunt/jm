package primer

import "base:runtime"
import "jm:ui"
import "jm:ui/design"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// Button is Primer's labelled action (primer-kit components/button.json,
// ButtonBase.module.css at the kit's release, cited as
// ButtonBase.module.css:lines). Each variant reads its own component
// tokens per state (--button-<variant>-<property>-<state>), picked by
// color_for and faded by blend over CONTROL_TRANSITION; a press snaps.
//
// A keybinding hint takes the trailing visual's place, in the variant's
// --buttonKeybindingHint-* colours per state, and shortens the end padding
// to 6px (8px at large) (ButtonBase.module.css:28-30,216-218,330-345).
//
// Departures: inactive has no
// semantics of its own, as jm:ui has no aria-disabled-but-focusable
// state; and a link button's underline sits 2px under the baseline
// whether or not it has visuals, where the browser places a bare text
// underline from the font (ButtonBase.module.css:593-599,617-619).

// Button_Variant is a button's emphasis and intent.
Button_Variant :: enum u8 {
	Default, // a neutral fill with a border
	Primary, // the one main action on a surface
	Danger, // a destructive action: red on hover and press
	Invisible, // no fill or border until hovered
	Link, // text that acts, no box
}

// Button_Size is a button's height: 28, 32 or 40px.
Button_Size :: enum u8 {
	Small,
	Medium,
	Large,
}

// Align_Content is where a wide (block) button's content sits.
Align_Content :: enum u8 {
	Center,
	Start,
}

// Unread_Dot is where a button's unread dot sits, if anywhere: on the
// button's top-right corner or on its leading visual's (an IconButton's
// icon).
Unread_Dot :: enum u8 {
	None,
	Button,
	Leading,
}

// Button_Metrics are one size's dimensions (ButtonBase.module.css:2-25,
// 185-219): height, side padding, the gap between parts, the side
// padding when only a leading visual and a count show, and the label.
@(private)
Button_Metrics :: struct {
	height, pad, gap, pad_count: f32,
	style:                       tok.Type_Style,
}

@(private)
button_metrics :: proc(size: Button_Size) -> Button_Metrics {
	body :: proc(size, line_height: f32) -> tok.Type_Style {
		return {weight = tok.BASE_TEXT_WEIGHT_MEDIUM, size = size, line_height = size * line_height}
	}
	switch size {
	case .Small:
		return {
			tok.CONTROL_SMALL_SIZE,
			tok.CONTROL_SMALL_PADDING_INLINE_CONDENSED,
			tok.CONTROL_SMALL_GAP,
			tok.CONTROL_XSMALL_PADDING_INLINE_CONDENSED,
			body(tok.TEXT_BODY_SIZE_SMALL, tok.TEXT_BODY_LINE_HEIGHT_SMALL),
		}
	case .Large:
		return {
			tok.CONTROL_LARGE_SIZE,
			tok.CONTROL_LARGE_PADDING_INLINE_SPACIOUS,
			tok.CONTROL_LARGE_GAP,
			tok.CONTROL_LARGE_PADDING_INLINE_NORMAL,
			body(tok.TEXT_BODY_SIZE_MEDIUM, tok.TEXT_BODY_LINE_HEIGHT_MEDIUM),
		}
	case .Medium:
	}
	return {
		tok.CONTROL_MEDIUM_SIZE,
		tok.CONTROL_MEDIUM_PADDING_INLINE_NORMAL,
		tok.BASE_SIZE_8,
		tok.CONTROL_MEDIUM_PADDING_INLINE_CONDENSED,
		body(tok.TEXT_BODY_SIZE_MEDIUM, tok.TEXT_BODY_LINE_HEIGHT_MEDIUM),
	}
}

// BUTTON_ICON is a visual's size: Primer draws 16px octicons in every
// button size (foundations icons.rules).
BUTTON_ICON :: f32(16)

// Button_Shadow is which resting or pressed shadow a variant casts.
@(private)
Button_Shadow :: enum u8 {
	None,
	Default_Resting, // a 1px offset line (--button-default-shadow-resting)
	Resting_Small,
	Primary_Selected,
	Danger_Selected,
}

// Button_Roles are one variant's colour roles per state for the fill,
// border, label, visuals and counter, and the shadow it casts at rest,
// hovered and pressed.
@(private)
Button_Roles :: struct {
	bg, border, fg, visual: State_Roles,
	counter_bg, counter_fg: State_Roles,
	shadow:                 [3]Button_Shadow, // rest, hover, pressed
}

// variant_roles is v's roles (ButtonBase.module.css:303-629). Where the
// CSS sets no token for a state, the rule that applies is repeated: a
// pressed button is also hovered, so a variant with no -active border
// keeps its -hover one; danger sets no rest border and borrows default's.
@(private)
variant_roles :: proc(v: Button_Variant) -> (r: Button_Roles) {
	same :: proc(role: tok.Role) -> State_Roles {
		return {role, role, role, role}
	}
	switch v {
	case .Default:
		r.bg = {.Button_Default_Bg_Color_Rest, .Button_Default_Bg_Color_Hover, .Button_Default_Bg_Color_Active, .Button_Default_Bg_Color_Disabled}
		r.border = {.Button_Default_Border_Color_Rest, .Button_Default_Border_Color_Hover, .Button_Default_Border_Color_Active, .Button_Default_Border_Color_Disabled}
		r.fg = {.Button_Default_Fg_Color_Rest, .Button_Default_Fg_Color_Rest, .Button_Default_Fg_Color_Rest, .Control_Fg_Color_Disabled}
		r.visual = {.Fg_Color_Muted, .Fg_Color_Muted, .Fg_Color_Muted, .Control_Fg_Color_Disabled}
		r.counter_bg = same(.Button_Counter_Default_Bg_Color_Rest)
		r.counter_fg = {.Fg_Color_Default, .Fg_Color_Default, .Fg_Color_Default, .Control_Fg_Color_Disabled}
		r.shadow = {.Default_Resting, .Default_Resting, .Default_Resting}
	case .Primary:
		r.bg = {.Button_Primary_Bg_Color_Rest, .Button_Primary_Bg_Color_Hover, .Button_Primary_Bg_Color_Active, .Button_Primary_Bg_Color_Disabled}
		r.border = {.Button_Primary_Border_Color_Rest, .Button_Primary_Border_Color_Hover, .Button_Primary_Border_Color_Hover, .Button_Primary_Border_Color_Disabled}
		r.fg = {.Button_Primary_Fg_Color_Rest, .Button_Primary_Fg_Color_Rest, .Button_Primary_Fg_Color_Rest, .Button_Primary_Fg_Color_Disabled}
		r.visual = r.fg
		r.counter_bg = same(.Button_Counter_Primary_Bg_Color_Rest)
		r.counter_fg = r.fg
		r.shadow = {.Resting_Small, .Resting_Small, .Primary_Selected}
	case .Danger:
		r.bg = {.Button_Danger_Bg_Color_Rest, .Button_Danger_Bg_Color_Hover, .Button_Danger_Bg_Color_Active, .Button_Danger_Bg_Color_Disabled}
		r.border = {.Button_Default_Border_Color_Rest, .Button_Danger_Border_Color_Hover, .Button_Danger_Border_Color_Active, .Button_Default_Border_Color_Disabled}
		r.fg = {.Button_Danger_Fg_Color_Rest, .Button_Danger_Fg_Color_Hover, .Button_Danger_Fg_Color_Active, .Button_Danger_Fg_Color_Disabled}
		r.visual = {.Button_Danger_Icon_Color_Rest, .Button_Danger_Icon_Color_Hover, .Button_Danger_Icon_Color_Hover, .Button_Danger_Fg_Color_Disabled}
		r.counter_bg = {.Button_Counter_Danger_Bg_Color_Rest, .Button_Counter_Danger_Bg_Color_Hover, .Button_Counter_Danger_Bg_Color_Hover, .Button_Counter_Danger_Bg_Color_Disabled}
		r.counter_fg = {.Button_Counter_Danger_Fg_Color_Rest, .Button_Counter_Danger_Fg_Color_Hover, .Button_Counter_Danger_Fg_Color_Hover, .Button_Counter_Danger_Fg_Color_Disabled}
		r.shadow = {.Default_Resting, .Resting_Small, .Danger_Selected}
	case .Invisible:
		r.bg = {.Bg_Color_Transparent, .Button_Invisible_Bg_Color_Hover, .Button_Invisible_Bg_Color_Active, .Button_Invisible_Bg_Color_Disabled}
		r.border = {.Button_Invisible_Border_Color_Rest, .Button_Invisible_Border_Color_Hover, .Button_Invisible_Border_Color_Hover, .Button_Invisible_Border_Color_Disabled}
		r.fg = {.Button_Default_Fg_Color_Rest, .Button_Default_Fg_Color_Rest, .Button_Default_Fg_Color_Rest, .Button_Invisible_Fg_Color_Disabled}
		r.visual = {.Button_Invisible_Icon_Color_Rest, .Button_Invisible_Icon_Color_Hover, .Button_Invisible_Icon_Color_Hover, .Button_Invisible_Fg_Color_Disabled}
		r.counter_bg = same(.Button_Counter_Invisible_Bg_Color_Rest)
		r.counter_fg = {.Fg_Color_Default, .Fg_Color_Default, .Fg_Color_Default, .Button_Invisible_Fg_Color_Disabled}
	case .Link:
		r.bg = same(.Bg_Color_Transparent)
		r.border = same(.Bg_Color_Transparent)
		r.fg = {.Fg_Color_Link, .Fg_Color_Link, .Fg_Color_Link, .Control_Fg_Color_Disabled}
		r.visual = r.fg
		r.counter_bg = same(.Bg_Color_Neutral_Muted)
		r.counter_fg = same(.Fg_Color_Default)
	}
	return
}

// inactive_roles is an inactive button's look in every state: its own
// fill and text, the fill as border, no change on hover or press
// (ButtonBase.module.css:674-696).
@(private)
inactive_roles :: proc(r: Button_Roles) -> Button_Roles {
	out := r
	bg := tok.Role.Button_Inactive_Bg_Color
	fg := tok.Role.Button_Inactive_Fg_Color
	out.bg = {bg, bg, bg, bg}
	out.border = out.bg
	out.fg = {fg, fg, fg, fg}
	out.visual = out.fg
	out.counter_fg = out.fg
	out.shadow = {}
	return out
}

@(private)
shadow_token :: proc(s: Button_Shadow) -> (sh: [Theme]tok.Shadow, ok: bool) {
	switch s {
	case .None:
		return
	case .Default_Resting:
		return tok.BUTTON_DEFAULT_SHADOW_RESTING, true
	case .Resting_Small:
		return tok.SHADOW_RESTING_SMALL, true
	case .Primary_Selected:
		return tok.BUTTON_PRIMARY_SHADOW_SELECTED, true
	case .Danger_Selected:
		return tok.BUTTON_DANGER_SHADOW_SELECTED, true
	}
	return
}

// Button_Content is what sits inside a button, measured: the label and
// the count's text, and which visuals show.
@(private)
Button_Content :: struct {
	label, count:              Text,
	leading, trailing, action: Icon,
	has_label, has_count:      bool,
	hint:                      Hint_Layout, // a keybinding hint, in the trailing slot
	has_hint:                  bool,
}

// button_box is a button's side padding and width at rest for its
// content bc at size: the content box, the padding each side
// (ButtonBase.module.css:144-165), and the action's slot.
@(private)
button_box :: proc(bc: Button_Content, size: Button_Size) -> (pad, pad_end, w: f32) {
	mt := button_metrics(size)
	pad = mt.pad
	if bc.has_count && !bc.has_label && bc.leading != .None {
		pad = mt.pad_count
	}
	pad_end = pad
	if bc.has_hint {
		pad_end = size == .Large ? tok.BASE_SIZE_8 : tok.BASE_SIZE_6
	}
	w = pad + pad_end + content_width(bc, mt.gap)
	if bc.action != .None {
		w += mt.gap + BUTTON_ICON - tok.BASE_SIZE_4
	}
	return
}

// button_width is the width a button of size takes at rest around a
// label label_w wide, with leading and action as button draws them: what
// a caller reserves so the button holds its width as its label changes.
button_width :: proc(
	label_w: f32,
	size := Button_Size.Medium,
	leading := Icon.None,
	action := Icon.None,
) -> f32 {
	bc := Button_Content{leading = leading, action = action, has_label = true}
	bc.label.width = label_w
	_, _, w := button_box(bc, size)
	return w
}

// content_width is the content box's width: the parts that show, the
// gap after each but the last (ButtonBase.module.css:144-165).
@(private)
content_width :: proc(bc: Button_Content, gap: f32) -> f32 {
	w: f32
	n := 0
	if bc.leading != .None {
		w += BUTTON_ICON
		n += 1
	}
	if bc.has_label {
		w += bc.label.width
		n += 1
	}
	if bc.has_hint {
		w += bc.hint.size.x
		n += 1
	} else if bc.has_count && bc.trailing == .None {
		w += counter_size(bc.count).x
		n += 1
	} else if bc.trailing != .None {
		w += BUTTON_ICON
		n += 1
	}
	return w + f32(max(n - 1, 0)) * gap
}

// button is one of Primer's buttons. size picks height, padding, gap and
// label size together; leading and trailing are 16px octicons beside the
// label, action one at the far end (a menu button's triangle); count
// shows a CounterLabel after the label unless trailing is set. block
// fills the width offered, align places the content then. loading swaps
// a visual (or the label) for a spinner and ignores clicks while keeping
// focus; inactive looks disabled but stays live. name is what assistive
// technology hears when it differs from the visible label (a "+3" that
// means "Show +3 more"); the label when empty. expanded, when set, says
// the button controls a menu or panel and whether it is open
// (aria-expanded): open, it keeps its pressed fill, border and shadow
// until hovered (ButtonBase.module.css:308-311,360-363,417-422,516-518).
// tab_stop false takes it out of Tab's order (tabindex -1): a press or a
// focus request still focuses it, and it hears keys while focused, as a
// tree row's trailing action does. Returns true on the frame it is
// clicked, or activated by Enter or Space while focused.
button :: proc(
	gtx: ^ui.Ctx,
	label: string,
	variant := Button_Variant.Default,
	size := Button_Size.Medium,
	leading := Icon.None,
	trailing := Icon.None,
	action := Icon.None,
	count := "",
	block := false,
	align := Align_Content.Center,
	loading := false,
	inactive := false,
	dot := Unread_Dot.None,
	name := "",
	expanded: Maybe(bool) = nil,
	tab_stop := true,
	group: ^Button_Group = nil,
	keybinding := "",
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_open(gtx, key, loc)
	mt := button_metrics(size)
	bc := Button_Content {
		leading   = leading,
		trailing  = trailing,
		action    = action,
		has_label = label != "",
		has_count = count != "",
	}
	bc.label = design.shape_style(gtx, label, mt.style, font_for(gtx, mt.style.weight))
	cst := counter_style()
	bc.count = design.shape_style(gtx, count, cst, font_for(gtx, cst.weight))
	if keybinding != "" {
		bc.hint, bc.has_hint = layout_hint(gtx, keybinding, .Condensed, hint_variant(variant), .Normal), true
	}
	pad, pad_end, w := button_box(bc, size)
	cw := content_width(bc, mt.gap)
	h := mt.height
	if variant == .Link {
		w, h = cw, mt.style.line_height
	}
	sz := ui.constrain_min(gtx.constraints, {block ? max(gtx.constraints.max.x, w) : w, h})
	area := ops.Rect{0, 0, sz.x, sz.y}
	c := control(gtx, p.id, area, state)
	r := variant_roles(variant)
	if inactive {
		r = inactive_roles(r)
	}
	open := expanded.? or_else false
	bp := Button_Paint{variant, r, area, mt, bc, align, pad, loading, inactive, dot, open, nil, 0, pad_end}
	if group != nil {
		bp.group, bp.member = group, group_join(group)
	}
	paint_button(gtx, c, bp)
	listen(gtx, c.st, p.id, area, CLICK_KINDS, no_tab = !tab_stop)
	said := ui.frame_string(gtx, label)
	ops.tag(gtx.scene, p.id, said)
	heard := said if name == "" else ui.frame_string(gtx, name)
	ui.semantics(gtx, &p, {role = variant == .Link ? .Link : .Button, label = heard, states = design.state_if(c.disabled || loading, {.Disabled}) + expanded_states(expanded)})
	ui.widget_close(gtx, &p, {sz, (sz.y - bc.label.height) / 2 + baseline_of(bc.label)})
	return c.clicked && !loading
}

// Button_Paint is everything a button is drawn from, resolved: its look,
// its box and side padding, and what sits inside it.
@(private)
Button_Paint :: struct {
	variant:           Button_Variant,
	r:                 Button_Roles,
	area:              ops.Rect,
	mt:                Button_Metrics,
	bc:                Button_Content,
	align:             Align_Content,
	pad:               f32,
	loading, inactive: bool,
	dot:               Unread_Dot,
	expanded:          bool, // it controls an open menu: pressed colours until hovered
	group:             ^Button_Group, // nil unless in a ButtonGroup
	member:            int, // its index there
	pad_end:           f32, // the end padding, less than pad beside a keybinding hint; 0 means pad
}

// expanded_states is aria-expanded as semantic states: none when the
// control opens nothing, else expandable and, while open, expanded.
@(private)
expanded_states :: proc(expanded: Maybe(bool)) -> ops.States {
	open, ok := expanded.?
	if !ok {
		return {}
	}
	return open ? {.Expandable, .Expanded} : {.Expandable}
}

// paint_button draws a button's box, content and focus.
@(private)
paint_button :: proc(gtx: ^ui.Ctx, c: Control, bp: Button_Paint) {
	look := c
	if bp.inactive {
		look.state = .Enabled
	} else if bp.expanded && look.state != .Hovered && look.state != .Disabled {
		look.state = .Pressed
	}
	rr := ops.Round_Rect{bp.area, bp.variant == .Link ? 0 : tok.BORDER_RADIUS_MEDIUM}
	// Slots 0-3: fill, border, label and visuals, the properties the CSS
	// transitions together (ButtonBase.module.css:20-21).
	bg := blend(gtx, look, 0, color_for(bp.r.bg, look))
	border := blend(gtx, look, 1, color_for(bp.r.border, look))
	fg := blend(gtx, look, 2, color_for(bp.r.fg, look))
	visual := blend(gtx, look, 3, color_for(bp.r.visual, look))
	if bp.variant != .Link {
		shadow_index := look.state == .Pressed ? 2 : look.state == .Hovered ? 1 : 0
		if sh, ok := shadow_token(bp.r.shadow[shadow_index]); ok && !look.disabled {
			paint_shadow(gtx, rr, sh)
		}
		if bp.group != nil {
			k := group_corners(bp.member, bp.group.count)
			if ui.painted(bg) {
				ops.fill(gtx.scene, rounded(gtx, bp.area, k), bg)
			}
			paint_group_border(gtx, look, bp.area, k, border)
		} else {
			if ui.painted(bg) {
				ops.fill(gtx.scene, rr, bg)
			}
			if ui.painted(border) {
				stroke_inside(gtx, rr, border, tok.BORDER_WIDTH_THIN)
			}
		}
	}
	cw := content_width(bp.bc, bp.mt.gap)
	pad_end := bp.pad_end if bp.pad_end > 0 else bp.pad
	inner := bp.area.w - bp.pad - pad_end - (bp.bc.action != .None ? bp.mt.gap + BUTTON_ICON - tok.BASE_SIZE_4 : 0)
	x := bp.pad + (bp.align == .Center ? max((inner - cw) / 2, 0) : 0)
	if bp.variant == .Link {
		x = 0
	}
	paint_button_content(gtx, look, bp, x, {fg, visual})
	if bp.dot == .Button {
		paint_dot(gtx, {bp.area.x + bp.area.w + tok.BASE_SIZE_4 / 2 - tok.BASE_SIZE_8, bp.area.y - tok.BASE_SIZE_4 / 2})
	}
	if bp.group != nil && bp.variant != .Link {
		design.paint_focus_visible_ring(gtx, c.base, bp.area, group_corners(bp.member, bp.group.count), focus_outline())
		return
	}
	switch bp.variant {
	case .Primary:
		paint_focus_on_emphasis(gtx, c, rr)
	case .Link:
		paint_focus_outline(gtx, c, rr, LINK_FOCUS_OFFSET)
	case .Default, .Danger, .Invisible:
		paint_focus_outline(gtx, c, rr)
	}
}

// LINK_FOCUS_OFFSET is a link button's outline offset: 2px outside, not
// inside (ButtonBase.module.css:601-604).
LINK_FOCUS_OFFSET :: f32(2)

// paint_button_content draws the leading visual, label, trailing visual
// or count, and trailing action left to right from x, a loading spinner
// taking the first visual's place or, with none, the label's.
@(private)
paint_button_content :: proc(gtx: ^ui.Ctx, c: Control, bp: Button_Paint, x0: f32, ink: [2]ops.Color) {
	fg, visual := ink[0], ink[1]
	x := x0
	icon_y := (bp.area.h - BUTTON_ICON) / 2
	spin_on := bp.loading ? spinner_slot(bp.bc) : Spinner_Slot.None
	if bp.bc.leading != .None {
		paint_visual(gtx, bp.bc.leading, {x, icon_y}, visual, spin_on == .Leading)
		x += BUTTON_ICON + bp.mt.gap
	}
	if bp.bc.has_label {
		ly := (bp.area.h - bp.bc.label.height) / 2
		if spin_on == .Label {
			paint_spinner(gtx, {x + (bp.bc.label.width - BUTTON_ICON) / 2, icon_y}, BUTTON_ICON, fg)
		} else {
			draw_text(gtx, bp.bc.label, {x, ly}, fg)
		}
		if c.hovered && !c.disabled && bp.r.fg.rest == .Fg_Color_Link {
			ul := ly + baseline_of(bp.bc.label) + tok.BASE_SIZE_2
			ops.fill(gtx.scene, ops.Rect{x, ul, bp.bc.label.width, tok.BORDER_WIDTH_THIN}, fg)
		}
		x += bp.bc.label.width + bp.mt.gap
	}
	if bp.bc.has_hint {
		paint_hint(gtx, bp.bc.hint, {x, (bp.area.h - bp.bc.hint.size.y) / 2}, button_hint_colors(bp.variant, c, bp.inactive))
		x += bp.bc.hint.size.x + bp.mt.gap
	} else if bp.bc.trailing != .None {
		paint_visual(gtx, bp.bc.trailing, {x, icon_y}, visual, spin_on == .Trailing)
		x += BUTTON_ICON + bp.mt.gap
	} else if bp.bc.has_count {
		csz := counter_size(bp.bc.count)
		if spin_on == .Trailing {
			paint_spinner(gtx, {x + (csz.x - BUTTON_ICON) / 2, icon_y}, BUTTON_ICON, visual)
		} else {
			paint_counter(gtx, bp.bc.count, {x, (bp.area.h - csz.y) / 2}, {color_for(bp.r.counter_bg, c), color_for(bp.r.counter_fg, c)})
		}
		x += csz.x + bp.mt.gap
	}
	if bp.bc.action != .None {
		// ButtonContent grows to fill the button (flex: 1 0 auto,
		// ButtonBase.module.css:144-145), so the action sits at the end,
		// pulled 4px into the padding (181-183), whatever the content's
		// alignment or the button's width.
		pad_end := bp.pad_end if bp.pad_end > 0 else bp.pad
		ax := bp.area.x + bp.area.w - pad_end - BUTTON_ICON + tok.BASE_SIZE_4
		paint_visual(gtx, bp.bc.action, {ax, icon_y}, visual, spin_on == .Action)
	}
}

// hint_variant is the key-cap colouring a hint in a v button starts from.
@(private)
hint_variant :: proc(v: Button_Variant) -> Hint_Variant {
	return v == .Primary ? .On_Primary : .Normal
}

// button_hint_colors is a keybinding hint's caps in a v button in c's
// state: --buttonKeybindingHint-<variant>-<property>-<state>, rest where a
// variant has no token for the state, the inactive ones for an inactive
// button (ButtonBase.module.css:330-345,386-402,439-502,528-573,691-695).
@(private)
button_hint_colors :: proc(v: Button_Variant, c: Control, inactive: bool) -> Hint_Colors {
	H :: struct {
		bg, fg, border: State_Roles,
	}
	h: H
	switch {
	case inactive:
		h = {
			{.Button_Keybinding_Hint_Inactive_Bg_Color, .Button_Keybinding_Hint_Inactive_Bg_Color, .Button_Keybinding_Hint_Inactive_Bg_Color, .Button_Keybinding_Hint_Inactive_Bg_Color},
			{.Button_Keybinding_Hint_Inactive_Fg_Color, .Button_Keybinding_Hint_Inactive_Fg_Color, .Button_Keybinding_Hint_Inactive_Fg_Color, .Button_Keybinding_Hint_Inactive_Fg_Color},
			{.Button_Keybinding_Hint_Inactive_Border_Color, .Button_Keybinding_Hint_Inactive_Border_Color, .Button_Keybinding_Hint_Inactive_Border_Color, .Button_Keybinding_Hint_Inactive_Border_Color},
		}
	case v == .Primary:
		h = {
			{.Button_Keybinding_Hint_Primary_Bg_Color_Rest, .Button_Keybinding_Hint_Primary_Bg_Color_Rest, .Button_Keybinding_Hint_Primary_Bg_Color_Rest, .Button_Keybinding_Hint_Primary_Bg_Color_Disabled},
			{.Button_Keybinding_Hint_Primary_Fg_Color_Rest, .Button_Keybinding_Hint_Primary_Fg_Color_Rest, .Button_Keybinding_Hint_Primary_Fg_Color_Rest, .Button_Keybinding_Hint_Primary_Fg_Color_Disabled},
			{.Button_Keybinding_Hint_Primary_Border_Color_Rest, .Button_Keybinding_Hint_Primary_Border_Color_Rest, .Button_Keybinding_Hint_Primary_Border_Color_Rest, .Button_Keybinding_Hint_Primary_Border_Color_Disabled},
		}
	case v == .Danger:
		h = {
			{.Button_Keybinding_Hint_Danger_Bg_Color_Rest, .Button_Keybinding_Hint_Danger_Bg_Color_Hover, .Button_Keybinding_Hint_Danger_Bg_Color_Active, .Button_Keybinding_Hint_Danger_Bg_Color_Disabled},
			{.Button_Keybinding_Hint_Danger_Fg_Color_Rest, .Button_Keybinding_Hint_Danger_Fg_Color_Hover, .Button_Keybinding_Hint_Danger_Fg_Color_Active, .Button_Keybinding_Hint_Danger_Fg_Color_Disabled},
			{.Button_Keybinding_Hint_Danger_Border_Color_Rest, .Button_Keybinding_Hint_Danger_Border_Color_Hover, .Button_Keybinding_Hint_Danger_Border_Color_Active, .Button_Keybinding_Hint_Danger_Border_Color_Disabled},
		}
	case v == .Invisible:
		h = {
			{.Button_Keybinding_Hint_Invisible_Bg_Color_Rest, .Button_Keybinding_Hint_Invisible_Bg_Color_Hover, .Button_Keybinding_Hint_Invisible_Bg_Color_Active, .Button_Keybinding_Hint_Invisible_Bg_Color_Disabled},
			{.Button_Keybinding_Hint_Invisible_Fg_Color_Rest, .Button_Keybinding_Hint_Invisible_Fg_Color_Rest, .Button_Keybinding_Hint_Invisible_Fg_Color_Rest, .Button_Keybinding_Hint_Invisible_Fg_Color_Disabled},
			{.Button_Keybinding_Hint_Invisible_Border_Color_Rest, .Button_Keybinding_Hint_Invisible_Border_Color_Rest, .Button_Keybinding_Hint_Invisible_Border_Color_Rest, .Button_Keybinding_Hint_Invisible_Border_Color_Disabled},
		}
	case:
		h = {
			{.Button_Keybinding_Hint_Default_Bg_Color_Rest, .Button_Keybinding_Hint_Default_Bg_Color_Rest, .Button_Keybinding_Hint_Default_Bg_Color_Rest, .Button_Keybinding_Hint_Default_Bg_Color_Disabled},
			{.Button_Keybinding_Hint_Default_Fg_Color_Rest, .Button_Keybinding_Hint_Default_Fg_Color_Rest, .Button_Keybinding_Hint_Default_Fg_Color_Rest, .Button_Keybinding_Hint_Default_Fg_Color_Disabled},
			{.Button_Keybinding_Hint_Default_Border_Color_Rest, .Button_Keybinding_Hint_Default_Border_Color_Rest, .Button_Keybinding_Hint_Default_Border_Color_Rest, .Button_Keybinding_Hint_Default_Border_Color_Disabled},
		}
	}
	return {color_for(h.bg, c), color_for(h.fg, c), color_for(h.border, c)}
}

// Spinner_Slot is which part a loading button's spinner replaces.
@(private)
Spinner_Slot :: enum u8 {
	None,
	Leading,
	Label,
	Trailing,
	Action,
}

// spinner_slot is where a loading button's spinner goes: the leading
// visual, else the trailing visual or count, else the trailing action,
// else over the hidden label (ButtonBase.tsx:139-191).
@(private)
spinner_slot :: proc(bc: Button_Content) -> Spinner_Slot {
	switch {
	case bc.leading != .None:
		return .Leading
	case bc.trailing != .None || bc.has_count:
		return .Trailing
	case bc.action != .None:
		return .Action
	}
	return .Label
}

// paint_visual draws a 16px visual at pos, or a small spinner in its
// place while the button loads.
@(private)
paint_visual :: proc(gtx: ^ui.Ctx, i: Icon, pos: ops.Point, c: ops.Color, spinning: bool) {
	if spinning {
		paint_spinner(gtx, pos, BUTTON_ICON, c)
		return
	}
	icon(gtx, i, pos, BUTTON_ICON, c)
}

// paint_dot draws the unread dot with its top-left at pos: 8px
// of --fgColor-accent ringed 2px in --bgColor-inset, so it cuts itself out
// of what it overlaps (ButtonBase.module.css:52-80).
@(private)
paint_dot :: proc(gtx: ^ui.Ctx, pos: ops.Point) {
	d := tok.BASE_SIZE_8
	ring := tok.BASE_SIZE_4 / 2
	centre := pos + {d / 2, d / 2}
	ops.fill(gtx.scene, ui.circle(centre, d / 2 + ring), color(.Bg_Color_Inset))
	ops.fill(gtx.scene, ui.circle(centre, d / 2), color(.Fg_Color_Accent))
}

// icon_button is a square button whose only content is ic, centred (icon-
// button.json): the size's control height on each side, and name its
// accessible name. The default variant draws its icon in --fgColor-muted,
// invisible in its rest icon colour in every state (the CSS's hover
// colour is set on .Visual, which an IconButton's icon is not wrapped in:
// icon-button.json notes, ButtonBase.module.css:520-526); primary and
// danger in their label colour.
//
// It shows a tooltip (tooltip.json, see tooltip): description when given,
// describing the button, else name, labelling it; 50ms after the pointer
// arrives or at once on keyboard focus, on tooltip_direction's side. A
// disabled button, an empty name or no_tooltip shows none
// (IconButton.tsx:28-80).
//
// expanded and tab_stop are button's. While expanded is true the tooltip
// stays down (IconButton.tsx: a button with aria-haspopup and
// aria-expanded shows none; icon-button.json states).
//
// keybinding is shortcuts its tooltip shows after the name and its label
// says, "Bold (command b)" (IconButton.tsx:65, Tooltip.tsx:390-415).
icon_button :: proc(
	gtx: ^ui.Ctx,
	ic: Icon,
	name: string,
	variant := Button_Variant.Default,
	size := Button_Size.Medium,
	loading := false,
	inactive := false,
	dot := Unread_Dot.None,
	description := "",
	tooltip_direction := Tooltip_Direction.S,
	no_tooltip := false,
	expanded: Maybe(bool) = nil,
	tab_stop := true,
	group: ^Button_Group = nil,
	keybinding: []string = nil,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	r := variant_roles(variant == .Link ? .Default : variant)
	switch variant {
	case .Default, .Link:
		r.visual = {.Fg_Color_Muted, .Fg_Color_Muted, .Fg_Color_Muted, .Control_Fg_Color_Disabled}
	case .Invisible:
		rest := tok.Role.Button_Invisible_Icon_Color_Rest
		r.visual = {rest, rest, rest, .Button_Invisible_Fg_Color_Disabled}
	case .Primary, .Danger:
		r.visual = r.fg
	}
	st := Icon_Button_State{loading, inactive, dot, state, description, tooltip_direction, no_tooltip, expanded, !tab_stop, group, keybinding}
	return icon_button_in(gtx, ic, name, variant, size, r, st, key, loc)
}

// Icon_Button_State is an icon button's flags and forced state.
@(private)
Icon_Button_State :: struct {
	loading, inactive: bool,
	dot:               Unread_Dot,
	state:             Interaction,
	description:       string, // its tooltip's text in place of the name, describing it
	tooltip_direction: Tooltip_Direction,
	no_tooltip:        bool,
	expanded:          Maybe(bool),
	no_tab:            bool, // out of Tab's order: tab_stop false
	group:             ^Button_Group, // nil unless in a ButtonGroup
	keybinding:        []string, // shortcuts its tooltip shows and its label says
}

// icon_button_in is icon_button in roles r: a component that sets an
// icon button's icon colour (Banner's dismiss button takes its variant's
// foreground) passes its own.
@(private)
icon_button_in :: proc(gtx: ^ui.Ctx, ic: Icon, name: string, variant: Button_Variant, size: Button_Size, roles: Button_Roles, st: Icon_Button_State, key: u64, loc: runtime.Source_Code_Location) -> bool {
	p := ui.widget_open(gtx, key, loc)
	side := button_metrics(size).height
	sz := ui.constrain_min(gtx.constraints, {side, side})
	area := ops.Rect{0, 0, sz.x, sz.y}
	c := control(gtx, p.id, area, st.state)
	r := roles
	loading, inactive, dot := st.loading, st.inactive, st.dot
	if inactive {
		r = inactive_roles(r)
	}
	bc := Button_Content{leading = ic}
	pad := (sz.x - BUTTON_ICON) / 2
	open := st.expanded.? or_else false
	bp := Button_Paint{variant == .Link ? .Default : variant, r, area, button_metrics(size), bc, .Center, pad, loading, inactive, .None, open, nil, 0, 0}
	if st.group != nil {
		bp.group, bp.member = st.group, group_join(st.group)
	}
	paint_button(gtx, c, bp)
	// The dot sits 2px outside the top-right corner, or 12px up and right
	// of the centre over the icon (ButtonBase.module.css:67-75).
	d, half := tok.BASE_SIZE_8, tok.BASE_SIZE_4 / 2
	switch dot {
	case .Button:
		paint_dot(gtx, {area.w + half - d, -half})
	case .Leading:
		paint_dot(gtx, {area.w / 2 + tok.BASE_SIZE_12 - d, area.h / 2 - tok.BASE_SIZE_12})
	case .None:
	}
	listen(gtx, c.st, p.id, area, CLICK_KINDS, no_tab = st.no_tab)
	said := ui.frame_string(gtx, name)
	ops.tag(gtx.scene, p.id, said)
	// no_tooltip leaves the trigger's tooltip state alone: a caller that
	// draws its own tooltip on this button shares it, and a hidden one
	// here would hide that one again each frame, restarting its fade.
	if c.st != nil && !st.no_tooltip {
		tip := st.description if st.description != "" else name
		tooltip_run(gtx, p.id, area, tip, st.tooltip_direction, .Short, c.disabled || name == "" || open, false, st.keybinding)
	}
	heard := said if st.description != "" else tooltip_label(gtx, name, st.keybinding)
	ui.semantics(gtx, &p, {role = .Button, label = heard, description = ui.frame_string(gtx, st.description), states = design.state_if(c.disabled || loading, {.Disabled}) + expanded_states(st.expanded)})
	ui.widget_close(gtx, &p, {sz, 0})
	return c.clicked && !loading
}
