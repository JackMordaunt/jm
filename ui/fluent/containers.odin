package fluent

import "base:runtime"
import "core:math"
import "jm:ui"
import "jm:ui/design"
import tok "jm:ui/fluent/tokens"
import "jm:ui/ops"

// Containers: card, divider, tab list, toolbar and accordion (fluent-kit
// components/card.json, divider.json, tab-list.json, toolbar.json,
// accordion.json; the styles files at the kit's commit are cited as
// use<Name>Styles.styles.ts:lines). Each container comes in both of
// ui's forms: the explicit pair (card_open and ui.close, toolbar_open
// and toolbar_close, accordion_item_open and accordion_item_close) and
// the bare-noun guard, `if fluent.card(gtx) { … }`, which closes itself
// at the end of the if (ui/guards.odin).

// Card

// Card_Appearance is a card's surface treatment.
Card_Appearance :: enum u8 {
	Filled, // Background 1 with shadow4
	Filled_Alternative, // Background 2 with shadow4
	Outline, // transparent with a Stroke 1 border
	Subtle, // transparent, tinted on hover
}

// Card_Paint is what paint_card needs of the card that opened it.
@(private)
Card_Paint :: struct {
	appearance:  Card_Appearance,
	size:        Size,
	interactive: bool,
	selected:    ^bool, // nil unless selectable
	clicked:     ^bool, // set on the frame the card is clicked
	name:        string, // the tag, so a probe can find it
	state:       Interaction,
}

// card_spacing is the size's one spacing value, used for the card's
// padding and meant for the gap between its children
// (useCardStyles.styles.ts:159-170), and its radius token.
@(private)
card_spacing :: proc(size: Size) -> (spacing, radius: f32) {
	switch size {
	case .Small:
		return 8, tok.BORDER_RADIUS_SMALL
	case .Medium:
		return 12, tok.BORDER_RADIUS_MEDIUM
	case .Large:
		return 16, tok.BORDER_RADIUS_LARGE
	}
	return 12, tok.BORDER_RADIUS_MEDIUM
}

// card_open opens a card: a box padded by the size's spacing whose
// surface, shadow, border, focus ring and input area paint_card draws
// under the body. A plain card is static; interactive reacts to hover
// and press and reports a click through clicked; selected non-nil makes
// it selectable, a click flipping selected^. name is what its tag
// carries. Close it with ui.close. The card's text colour does not reach
// its children, which pick their own: jm:ui has no inherited colour.
card_open :: proc(
	gtx: ^ui.Ctx,
	appearance := Card_Appearance.Filled,
	size := Size.Medium,
	interactive := false,
	selected: ^bool = nil,
	clicked: ^bool = nil,
	name := "",
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> ui.Box {
	cp := new(Card_Paint, gtx.allocator)
	cp^ = {appearance, size, interactive, selected, clicked, name, state}
	spacing, _ := card_spacing(size)
	return ui.box_open(gtx, {padding = ui.pad_all(spacing), paint = paint_card, user = cp}, key, loc)
}

// card is card_open as a guard: `if fluent.card(gtx, .Outline) { … }`
// lays the block out inside the card and closes it at the end of the if.
@(deferred_in = card_guard_close)
card :: proc(
	gtx: ^ui.Ctx,
	appearance := Card_Appearance.Filled,
	size := Size.Medium,
	interactive := false,
	selected: ^bool = nil,
	clicked: ^bool = nil,
	name := "",
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	card_open(gtx, appearance, size, interactive, selected, clicked, name, state, key, loc)
	return true
}

@(private = "file")
card_guard_close :: proc(gtx: ^ui.Ctx, appearance: Card_Appearance, size: Size, interactive: bool, selected: ^bool, clicked: ^bool, name: string, state: Interaction, key: u64, loc: runtime.Source_Code_Location) {
	ui.innermost_close(gtx, .Box)
}

// Card_Roles are one appearance's background and border per state, its
// selected pair, and whether it casts a shadow.
@(private)
Card_Roles :: struct {
	bg, border:               State_Roles,
	selected_bg:              tok.Role,
	shadow:                   bool,
	disabled_bg_transparent:  bool, // outline keeps a transparent background when disabled
}

// card_roles is a's roles (useCardStyles.styles.ts:178-352).
@(private)
card_roles :: proc(a: Card_Appearance) -> (r: Card_Roles) {
	NO_STROKE :: State_Roles{.Transparent_Stroke, .Transparent_Stroke, .Transparent_Stroke, .Neutral_Stroke_Disabled}
	switch a {
	case .Filled:
		r.bg = {.Neutral_Background1, .Neutral_Background1_Hover, .Neutral_Background1_Pressed, .Neutral_Background_Disabled}
		r.selected_bg = .Neutral_Background1_Selected
		r.border = NO_STROKE
		r.shadow = true
	case .Filled_Alternative:
		r.bg = {.Neutral_Background2, .Neutral_Background2_Hover, .Neutral_Background2_Pressed, .Neutral_Background_Disabled}
		r.selected_bg = .Neutral_Background2_Selected
		r.border = NO_STROKE
		r.shadow = true
	case .Outline:
		r.bg = {.Transparent_Background, .Transparent_Background_Hover, .Transparent_Background_Pressed, .Transparent_Background}
		r.selected_bg = .Transparent_Background_Selected
		r.border = {.Neutral_Stroke1, .Neutral_Stroke1_Hover, .Neutral_Stroke1_Pressed, .Neutral_Stroke_Disabled}
		r.disabled_bg_transparent = true
	case .Subtle:
		r.bg = {.Subtle_Background, .Subtle_Background_Hover, .Subtle_Background_Pressed, .Neutral_Background_Disabled}
		r.selected_bg = .Subtle_Background_Selected
		r.border = NO_STROKE
	}
	return
}

// paint_card paints the card's surface under its body: shadow4 at rest
// and shadow8 while hovered or pressed for the filled appearances,
// shadow2 when disabled (useCardStyles.styles.ts:72-90,172-202), the
// appearance's background and border per state, the Selected background
// and Stroke 1 Selected border of a selected card, and on keyboard focus
// a strokeWidthThick Stroke_Focus2 ring flush inside the edge
// (styles.ts:34-38, the -2px offset). Colours change at once: the styles
// file declares no transition. Only an interactive or selectable card
// reads input.
@(private)
paint_card :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, size: ops.Size, user: rawptr) {
	cp := (^Card_Paint)(user)
	_, radius := card_spacing(cp.size)
	area := ops.Rect{0, 0, size.x, size.y}
	rr := ops.Round_Rect{area, radius}
	r := card_roles(cp.appearance)
	live := cp.interactive || cp.selected != nil
	c: Control
	if live {
		c = control(gtx, id, area, cp.state)
		if c.clicked && cp.selected != nil {
			cp.selected^ = !cp.selected^
		}
		if cp.clicked != nil {
			cp.clicked^ = c.clicked
		}
	} else if cp.state == .Disabled {
		c.disabled = true
		c.state = .Disabled
	}
	on := cp.selected != nil && cp.selected^
	bg := color_for(r.bg, c)
	border := color_for(r.border, c)
	if on && !c.disabled {
		bg = color(r.selected_bg)
		border = color(.Neutral_Stroke1_Selected)
	}
	if c.disabled && r.disabled_bg_transparent {
		bg = color(.Transparent_Background)
	}
	if r.shadow || c.disabled {
		switch {
		case c.disabled && !r.disabled_bg_transparent:
			paint_shadow(gtx, rr, tok.SHADOW2)
		case c.disabled:
		case c.hovered || c.pressed:
			paint_shadow(gtx, rr, tok.SHADOW8)
		case:
			paint_shadow(gtx, rr, tok.SHADOW4)
		}
	}
	if ui.painted(bg) {
		ops.fill(gtx.scene, rr, bg)
	}
	if ui.painted(border) {
		stroke_inside(gtx, rr, border, tok.STROKE_WIDTH_THIN)
	}
	if c.focused && !c.disabled {
		stroke_inside(gtx, rr, color(.Stroke_Focus2), tok.STROKE_WIDTH_THICK)
	}
	if live {
		listen(gtx, c.st, id, rr)
	}
	if cp.name != "" {
		ops.tag(gtx.scene, id, ui.frame_string(gtx, cp.name))
	}
}

// Divider

// Divider_Appearance is a divider's emphasis: strong > default > subtle,
// brand for accent.
Divider_Appearance :: enum u8 {
	Default,
	Subtle,
	Strong,
	Brand,
}

// Divider_Align is where a labelled divider's text sits along the line.
Divider_Align :: enum u8 {
	Start,
	Center,
	End,
}

// DIVIDER_GAP is the 12px between a segment and the label, DIVIDER_STUB
// the 8px a start- or end-aligned label leaves before it, DIVIDER_INSET
// the 12px inset pulls the line in at each end, and the vertical
// minimums are 20px, 84px with a label (useDividerStyles.styles.ts:
// 13-16,129-130,191-193,215-217; the horizontal minimum is read as 8px
// from the file's malformed '8px;', divider.json's upstream-bug note).
@(private)
DIVIDER_GAP :: f32(12)
@(private)
DIVIDER_STUB :: f32(8)
@(private)
DIVIDER_INSET :: f32(12)
@(private)
DIVIDER_MIN_VERTICAL :: f32(20)
@(private)
DIVIDER_MIN_VERTICAL_LABEL :: f32(84)

// divider_roles is a's line and label roles (useDividerStyles.styles.ts:81-124).
@(private)
divider_roles :: proc(a: Divider_Appearance) -> (line, label: tok.Role) {
	switch a {
	case .Default:
		return .Neutral_Stroke2, .Neutral_Foreground2
	case .Subtle:
		return .Neutral_Stroke3, .Neutral_Foreground3
	case .Strong:
		return .Neutral_Stroke1, .Neutral_Foreground1
	case .Brand:
		return .Brand_Stroke1, .Brand_Foreground1
	}
	return .Neutral_Stroke2, .Neutral_Foreground2
}

// divider is a strokeWidthThin line across the space it is given: the
// width it is offered when horizontal (its height the caption line
// when labelled, else the stroke), the height it is offered when
// vertical, at least 20px, or 84 with a label. text sits in the line
// with 12px either side, centred or near the start or end; inset pulls
// the line 12px in at each end (as padding when horizontal, so the box
// keeps its width; as a shorter box when vertical). length, when
// given, is the line's extent instead of the offered space, for a
// container that sizes to its content. It takes no input.
divider :: proc(
	gtx: ^ui.Ctx,
	text := "",
	appearance := Divider_Appearance.Default,
	vertical := false,
	align := Divider_Align.Center,
	inset := false,
	length: f32 = 0,
	key: u64 = 0,
	loc := #caller_location,
) -> ui.Dims {
	p := ui.widget_open(gtx, key, loc)
	cs := gtx.constraints
	line_role, label_role := divider_roles(appearance)
	w := tok.STROKE_WIDTH_THIN
	labelled := text != ""
	t: Text
	if labelled {
		t = shape_style(gtx, text, tok.Type_Style{weight = tok.FONT_WEIGHT_REGULAR, size = tok.FONT_SIZE_BASE200, line_height = tok.LINE_HEIGHT_BASE200})
	}
	size: ops.Size
	if vertical {
		h := length > 0 ? length : ui.is_finite(cs.max.y) ? cs.max.y : cs.min.y
		h = max(h, labelled ? DIVIDER_MIN_VERTICAL_LABEL : DIVIDER_MIN_VERTICAL)
		size = {labelled ? max(t.width, w) : w, h}
	} else {
		width := length > 0 ? length : ui.is_finite(cs.max.x) ? cs.max.x : cs.min.x
		size = {width, labelled ? t.height : w}
	}
	size = ui.constrain(cs, size)
	// The line runs along the main axis from a to b, through the cross
	// axis's centre; the label breaks it.
	a, b: f32 = 0, vertical ? size.y : size.x
	if inset {
		a += DIVIDER_INSET
		b -= DIVIDER_INSET
	}
	mid := vertical ? size.x / 2 : size.y / 2
	line := color(line_role)
	seg :: proc(gtx: ^ui.Ctx, vertical: bool, from, to, mid, w: f32, c: ops.Color) {
		if to - from <= 0 || !ui.painted(c) {
			return
		}
		if vertical {
			ops.fill(gtx.scene, ops.Rect{mid - w / 2, from, w, to - from}, c)
		} else {
			ops.fill(gtx.scene, ops.Rect{from, mid - w / 2, to - from, w}, c)
		}
	}
	if !labelled {
		seg(gtx, vertical, a, b, mid, w, line)
		return ui.widget_close(gtx, &p, {size = size})
	}
	extent := vertical ? t.height : t.width
	// Where the label starts along the axis: a stub from the near end,
	// or the centre.
	start: f32
	switch align {
	case .Start:
		start = a + DIVIDER_STUB + DIVIDER_GAP
	case .Center:
		start = (a + b - extent) / 2
	case .End:
		start = b - DIVIDER_STUB - DIVIDER_GAP - extent
	}
	seg(gtx, vertical, a, start - DIVIDER_GAP, mid, w, line)
	seg(gtx, vertical, start + extent + DIVIDER_GAP, b, mid, w, line)
	if vertical {
		draw_text(gtx, t, {(size.x - t.width) / 2, start}, color(label_role))
	} else {
		draw_text(gtx, t, {start, 0}, color(label_role))
	}
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, text))
	return ui.widget_close(gtx, &p, {size, baseline_of(t)})
}

// Tab list

// Tab_Appearance is how a tab list marks its tabs: an indicator bar under
// transparent or subtle tabs, or a filled pill for the circular ones.
Tab_Appearance :: enum u8 {
	Transparent,
	Subtle,
	Subtle_Circular,
	Filled_Circular,
}

// Tab_Metrics are one size and orientation's tab geometry
// (useTabStyles.styles.ts:64-90,180-199,434-517,523-554).
@(private)
Tab_Metrics :: struct {
	pad_v, pad_h, icon, gap: f32,
	bar, bar_inset:          f32, // the indicator's thickness and inset from each end
	label, selected_label:   tok.Type_Style,
}

@(private)
tab_metrics :: proc(size: Size, vertical, circular: bool) -> (m: Tab_Metrics) {
	m.icon = size == .Large ? 24 : 20
	m.gap = size == .Small ? tok.SPACING_HORIZONTAL_XXS : tok.SPACING_HORIZONTAL_SNUDGE
	m.label = tok.TYPOGRAPHY_STYLES_BODY1
	m.selected_label = tok.TYPOGRAPHY_STYLES_BODY1_STRONG
	if size == .Large {
		m.label, m.selected_label = tok.TYPOGRAPHY_STYLES_BODY2, tok.TYPOGRAPHY_STYLES_SUBTITLE2
	}
	// Block padding: the vertical list's values, which circular tabs use
	// in either orientation, less their border.
	block := [Size]f32{.Small = tok.SPACING_VERTICAL_XXS, .Medium = tok.SPACING_VERTICAL_SNUDGE, .Large = tok.SPACING_VERTICAL_S}
	if !vertical && !circular {
		block = {.Small = tok.SPACING_VERTICAL_SNUDGE, .Medium = tok.SPACING_VERTICAL_M, .Large = tok.SPACING_VERTICAL_L}
	}
	m.pad_v = block[size]
	if circular {
		m.pad_v -= tok.STROKE_WIDTH_THIN
	}
	m.pad_h = size == .Small ? tok.SPACING_HORIZONTAL_SNUDGE : tok.SPACING_HORIZONTAL_MNUDGE
	if vertical {
		m.bar = tok.STROKE_WIDTH_THICKER
		insets := [Size]f32{.Small = tok.SPACING_VERTICAL_XS, .Medium = tok.SPACING_VERTICAL_S, .Large = tok.SPACING_VERTICAL_MNUDGE}
		m.bar_inset = insets[size]
	} else {
		m.bar = size == .Small ? tok.STROKE_WIDTH_THICK : tok.STROKE_WIDTH_THICKER
		m.bar_inset = size == .Small ? tok.SPACING_HORIZONTAL_SNUDGE : tok.SPACING_HORIZONTAL_M
	}
	return
}

// Tab_Indicator is the selection bar's slide: the rect it left and the
// one it is heading to, over DURATION_SLOW with CURVE_DECELERATE_MAX
// (useTabAnimatedIndicator.styles.ts:22-48).
@(private)
Tab_Indicator :: struct {
	from, to: ops.Rect,
	tween:    ui.Tween,
	live:     bool,
}

// tab_indicator_rect is where the bar sits this frame: at target when
// the list is forced or first seen, else eased from where it was.
@(private)
tab_indicator_rect :: proc(gtx: ^ui.Ctx, ind: ^Tab_Indicator, target: ops.Rect) -> ops.Rect {
	if ind == nil {
		return target
	}
	if !ind.live {
		ind^ = {from = target, to = target, live = true}
		return target
	}
	if target != ind.to {
		ind.from = tab_indicator_now(ind)
		ind.to = target
		ind.tween = {to = 1, duration = tok.DURATION_SLOW / 1000}
	}
	ui.tween_update(&ind.tween, gtx)
	return tab_indicator_now(ind)
}

@(private)
tab_indicator_now :: proc(ind: ^Tab_Indicator) -> ops.Rect {
	if ind.tween.duration <= 0 {
		return ind.to
	}
	t := design.bezier_ease(tok.CURVE_DECELERATE_MAX, ind.tween.t / ind.tween.duration)
	a, b := ind.from, ind.to
	return {a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.w + (b.w - a.w) * t, a.h + (b.h - a.h) * t}
}

// Tab_Colors are one tab's resolved colours this frame.
@(private)
Tab_Colors :: struct {
	bg, border, text, icon_color, bar: ops.Color,
	hover_bar:                         ops.Color, // the pending indicator under a hovered tab
}

// tab_colors is a tab's colours for appearance a, selected or not, in
// c's state (useTabStyles.styles.ts:91-304,345-452,555-583).
@(private)
tab_colors :: proc(a: Tab_Appearance, on: bool, c: Control) -> (k: Tab_Colors) {
	switch a {
	case .Transparent, .Subtle:
		bg := State_Roles{.Transparent_Background, .Transparent_Background_Hover, .Transparent_Background_Pressed, .Transparent_Background}
		if a == .Subtle {
			bg = {.Subtle_Background, .Subtle_Background_Hover, .Subtle_Background_Pressed, .Subtle_Background}
		}
		k.bg = color_for(bg, c)
		// A borderless button: no stroke at all, not the transparent
		// stroke token, which high contrast binds to a visible colour.
		text := State_Roles{.Neutral_Foreground2, .Neutral_Foreground2_Hover, .Neutral_Foreground2_Pressed, .Neutral_Foreground_Disabled}
		k.text = color_for(text, c)
		k.icon_color = k.text
		// The pending indicator shows only while hovered or pressed
		// (styles.ts:347-358); at rest there is none.
		if !c.disabled && (c.hovered || c.pressed) {
			k.hover_bar = color(c.pressed ? .Neutral_Stroke1_Pressed : .Neutral_Stroke1_Hover)
		}
		if on {
			k.text = color_for({.Neutral_Foreground1, .Neutral_Foreground1_Hover, .Neutral_Foreground1_Pressed, .Neutral_Foreground_Disabled}, c)
			k.icon_color = color_for({.Compound_Brand_Foreground1, .Compound_Brand_Foreground1_Hover, .Compound_Brand_Foreground1_Pressed, .Neutral_Foreground_Disabled}, c)
			k.bar = color_for({.Compound_Brand_Stroke, .Compound_Brand_Stroke_Hover, .Compound_Brand_Stroke_Pressed, .Neutral_Foreground_Disabled}, c)
		}
	case .Subtle_Circular:
		k.bg = color_for({.Subtle_Background, .Subtle_Background_Hover, .Subtle_Background_Pressed, .Subtle_Background}, c)
		k.border = color_for({.Transparent_Stroke, .Neutral_Stroke1_Hover, .Neutral_Stroke1_Pressed, .Transparent_Stroke}, c)
		k.text = color_for({.Neutral_Foreground2, .Neutral_Foreground2_Hover, .Neutral_Foreground2_Pressed, .Neutral_Foreground_Disabled}, c)
		if on {
			k.bg = color_for({.Brand_Background2, .Brand_Background2_Hover, .Brand_Background2_Pressed, .Neutral_Background_Disabled}, c)
			k.border = color_for({.Compound_Brand_Stroke, .Compound_Brand_Stroke_Hover, .Compound_Brand_Stroke_Pressed, .Neutral_Stroke_Disabled}, c)
			k.text = color_for({.Brand_Foreground2, .Brand_Foreground2_Hover, .Brand_Foreground2_Pressed, .Neutral_Foreground_Disabled}, c)
		}
		k.icon_color = k.text
	case .Filled_Circular:
		k.bg = color_for({.Neutral_Background3, .Neutral_Background3_Hover, .Neutral_Background3_Pressed, .Neutral_Background_Disabled}, c)
		k.text = color_for({.Neutral_Foreground2, .Neutral_Foreground2_Hover, .Neutral_Foreground2_Pressed, .Neutral_Foreground_Disabled}, c)
		if on {
			k.bg = color_for({.Brand_Background, .Brand_Background_Hover, .Brand_Background_Pressed, .Neutral_Background_Disabled}, c)
			k.text = color_for({.Neutral_Foreground_On_Brand, .Neutral_Foreground_On_Brand, .Neutral_Foreground_On_Brand, .Neutral_Foreground_Disabled}, c)
		}
		k.icon_color = k.text
	}
	return
}

// tab_list is a row (or column when vertical) of tabs, one selected.
// Clicking a tab, or Enter or Space on the focused one, selects it;
// Left and Right (Up and Down when vertical) on the focused tab move the
// selection, since jm:ui moves keyboard focus only by Tab. icons, when
// given, pair with labels; a selected tab shows its icon's filled twin.
// The indicator bar of the transparent and subtle appearances slides
// between tabs; the circular ones fill the selected pill instead.
// Colours change at once: the styles file declares no colour transition.
// Returns true on the frame the selection changes. Departures: no
// reserveSelectedTabSpace (a tab is as wide as its current label, so
// the row shifts a little on selection at the default sizes) and no
// focus ring shadow4 under the ring.
tab_list :: proc(
	gtx: ^ui.Ctx,
	labels: []string,
	selected: ^int,
	appearance := Tab_Appearance.Transparent,
	size := Size.Medium,
	vertical := false,
	icons: []Icon = nil,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_open(gtx, key, loc)
	circular := appearance == .Subtle_Circular || appearance == .Filled_Circular
	m := tab_metrics(size, vertical, circular)
	// The circular appearances space their pills; the bar ones sit edge
	// to edge (useTabListStyles.styles.ts:47-54).
	list_gap: f32 = 0
	if circular {
		list_gap = size == .Small ? tok.SPACING_HORIZONTAL_SNUDGE : tok.SPACING_HORIZONTAL_S
	}
	n := len(labels)
	texts := make([]Text, n, gtx.allocator)
	sizes := make([]ops.Size, n, gtx.allocator)
	total: ops.Size
	for label, i in labels {
		on := i == selected^
		texts[i] = shape_style(gtx, label, on ? m.selected_label : m.label)
		w := m.pad_h * 2 + texts[i].width + tok.SPACING_HORIZONTAL_XXS * 2 // the label's own inline padding (styles.ts:568-580)
		h := m.pad_v * 2 + max(texts[i].height, m.icon)
		if icons != nil && icons[i] != .None {
			w += m.icon + m.gap
		}
		if circular {
			w += 2 * tok.STROKE_WIDTH_THIN
			h += 2 * tok.STROKE_WIDTH_THIN
		}
		sizes[i] = {w, h}
		if vertical {
			total.x = max(total.x, w)
			total.y += h + (i > 0 ? list_gap : 0)
		} else {
			total.x += w + (i > 0 ? list_gap : 0)
			total.y = max(total.y, h)
		}
	}
	sz := ui.constrain(gtx.constraints, total)
	changed := false
	ind := ui.widget_data(gtx, p.id, Tab_Indicator) if state == .Live else nil
	pos: f32 = 0
	bar_target: ops.Rect
	bar_color: ops.Color
	for label, i in labels {
		// A vertical list stretches every tab across its width, a
		// horizontal one across its height (useTabListStyles.styles.ts:15-37).
		rect: ops.Rect
		if vertical {
			rect = {0, pos, sz.x, sizes[i].y}
		} else {
			rect = {pos, 0, sizes[i].x, sz.y}
		}
		pos += (vertical ? sizes[i].y : sizes[i].x) + list_gap
		id := ui.id_mix(p.id, u64(i))
		c := control(gtx, id, rect, state)
		if c.clicked && selected^ != i {
			selected^ = i
			changed = true
		}
		if c.st != nil && c.focused {
			for e in ui.events(gtx, id) {
				if e.kind != .Key {
					continue
				}
				step := 0
				#partial switch e.key {
				case .Left, .Up:
					step = -1
				case .Right, .Down:
					step = 1
				}
				if vertical ? (e.key == .Left || e.key == .Right) : (e.key == .Up || e.key == .Down) {
					step = 0
				}
				if step != 0 {
					selected^ = (selected^ + step + n) % n
					changed = true
				}
			}
		}
		on := i == selected^
		k := tab_colors(appearance, on, c)
		rad := circular ? radius(tok.BORDER_RADIUS_CIRCULAR, rect) : tok.BORDER_RADIUS_MEDIUM
		rr := ops.Round_Rect{rect, rad}
		if ui.painted(k.bg) {
			ops.fill(gtx.scene, rr, k.bg)
		}
		if ui.painted(k.border) {
			stroke_inside(gtx, rr, k.border, tok.STROKE_WIDTH_THIN)
		}
		// Content: centred when horizontal, start-aligned when vertical.
		t := texts[i]
		content_w := t.width
		has_icon := icons != nil && icons[i] != .None
		if has_icon {
			content_w += m.icon + m.gap
		}
		x := vertical ? rect.x + m.pad_h + (circular ? tok.STROKE_WIDTH_THIN : 0) : rect.x + (rect.w - content_w) / 2
		if has_icon {
			glyph := icons[i]
			if on {
				glyph = filled(glyph)
			}
			icon(gtx, glyph, {x, rect.y + (rect.h - m.icon) / 2}, m.icon, k.icon_color)
			x += m.icon + m.gap
		}
		draw_text(gtx, t, {x, rect.y + (rect.h - t.height) / 2}, k.text)
		if !circular {
			bar := bar_rect(rect, m, vertical)
			if on {
				bar_target = bar
				bar_color = k.bar
			} else if ui.painted(k.hover_bar) {
				// The pending indicator, under the selection bar's path.
				ops.fill(gtx.scene, ops.Round_Rect{bar, min(bar.w, bar.h) / 2}, k.hover_bar)
			}
		}
		if c.focused && !c.disabled {
			paint_focus_outline(gtx, c, rr)
			if circular {
				stroke_inside(gtx, rr, color(.Neutral_Stroke_On_Brand), tok.STROKE_WIDTH_THIN)
			}
		}
		listen(gtx, c.st, id, rect)
		ops.tag(gtx.scene, id, ui.frame_string(gtx, label))
	}
	if !circular {
		if bar_target.w > 0 && ui.painted(bar_color) {
			bar := tab_indicator_rect(gtx, ind, bar_target)
			ops.fill(gtx.scene, ops.Round_Rect{bar, min(bar.w, bar.h) / 2}, bar_color)
		}
	}
	ui.widget_close(gtx, &p, {size = sz})
	return changed
}

// bar_rect is the indicator's rect for a tab at rect: along the bottom
// edge inset from each end when horizontal, along the left edge inset
// from top and bottom when vertical, with pill ends.
@(private)
bar_rect :: proc(rect: ops.Rect, m: Tab_Metrics, vertical: bool) -> ops.Rect {
	if vertical {
		return {rect.x, rect.y + m.bar_inset, m.bar, rect.h - 2 * m.bar_inset}
	}
	return {rect.x + m.bar_inset, rect.y + rect.h - m.bar, rect.w - 2 * m.bar_inset, m.bar}
}

// Toolbar

// Toolbar is an open toolbar: its padding inset and its row or column.
Toolbar :: struct {
	inset: ui.Inset,
	flex:  ui.Flex,
}

// toolbar_sizes is the stack of open toolbars' sizes on this thread, so
// an item inside sizes itself to the toolbar (Toolbar.types.ts:74-77).
@(private, thread_local)
toolbar_sizes: [8]Size
@(private, thread_local)
toolbar_depth: int

// toolbar_item_size is the innermost open toolbar's size, medium outside one.
toolbar_item_size :: proc() -> Size {
	if toolbar_depth == 0 {
		return .Medium
	}
	return toolbar_sizes[toolbar_depth - 1]
}

// toolbar_padding is the toolbar's padding by size: 0 by 4, 4 by 8 and
// 4 by 20px, or the base 4 by 8 at any size when vertical
// (useToolbarStyles.styles.ts:14-27,36-44).
@(private)
toolbar_padding :: proc(size: Size, vertical: bool) -> ui.Padding {
	if vertical {
		return ui.pad_xy(8, 4)
	}
	switch size {
	case .Small:
		return ui.pad_xy(4, 0)
	case .Medium:
		return ui.pad_xy(8, 4)
	case .Large:
		return ui.pad_xy(20, 4)
	}
	return ui.pad_xy(8, 4)
}

// toolbar_open opens a toolbar: a row (a column when vertical) of items
// edge to edge, centred on the cross axis, inside the size's padding,
// with no background, border or shadow of its own. Items placed inside
// read toolbar_item_size; toolbar_button and toolbar_divider do. Close
// it with toolbar_close.
toolbar_open :: proc(gtx: ^ui.Ctx, size := Size.Medium, vertical := false, key: u64 = 0, loc := #caller_location) -> Toolbar {
	if toolbar_depth < len(toolbar_sizes) {
		toolbar_sizes[toolbar_depth] = size
	}
	toolbar_depth += 1
	t: Toolbar
	t.inset = ui.inset_open(gtx, toolbar_padding(size, vertical), key, loc)
	if vertical {
		t.flex = ui.column_open(gtx, align = .Center)
	} else {
		t.flex = ui.row_open(gtx, align = .Center)
	}
	return t
}

toolbar_close :: proc(t: ^Toolbar) {
	ui.close(&t.flex)
	ui.close(&t.inset)
	toolbar_depth = max(toolbar_depth - 1, 0)
}

// toolbar is toolbar_open as a guard: `if fluent.toolbar(gtx) { … }`.
@(deferred_in = toolbar_guard_close)
toolbar :: proc(gtx: ^ui.Ctx, size := Size.Medium, vertical := false, key: u64 = 0, loc := #caller_location) -> bool {
	toolbar_open(gtx, size, vertical, key, loc)
	return true
}

@(private = "file")
toolbar_guard_close :: proc(gtx: ^ui.Ctx, size: Size, vertical: bool, key: u64, loc: runtime.Source_Code_Location) {
	ui.innermost_close(gtx, .Flex)
	ui.innermost_close(gtx, .Inset)
	toolbar_depth = max(toolbar_depth - 1, 0)
}

// toolbar_button is a button sized to the toolbar it sits in, subtle
// by default (useToolbarButtonStyles.styles.ts; the appearance and size
// are inferred, see toolbar.json notes).
toolbar_button :: proc(
	gtx: ^ui.Ctx,
	label: string,
	ic := Icon.None,
	appearance := Appearance.Subtle,
	name := "",
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	return button(gtx, label, appearance, ic, toolbar_item_size(), name = name, state = state, key = key, loc = loc)
}

// toolbar_divider is the divider between toolbar items: a vertical
// Stroke 2 line at least 20px tall with 12px each side, or a horizontal
// one in a vertical toolbar (useToolbarDividerStyles.styles.ts:7-31),
// as long as the toolbar's items are tall, since a fit-content column
// cannot offer it a width.
toolbar_divider :: proc(gtx: ^ui.Ctx, key: u64 = 0, loc := #caller_location) {
	axis, in_flex := ui.parent_axis(gtx)
	vertical := !in_flex || axis == .Horizontal
	pad := vertical ? ui.pad_xy(DIVIDER_INSET, 0) : ui.pad_xy(0, DIVIDER_INSET)
	inset := ui.inset_open(gtx, pad, key, loc)
	heights := CONTROL_HEIGHT
	divider(gtx, vertical = vertical, length = vertical ? 0 : heights[toolbar_item_size()])
	ui.close(&inset)
}

// Accordion

// Accordion_Size is a header's height and type: 32px minimum with
// fontSizeBase200 at small, else 44px with body1, fontSizeBase400 on
// lineHeightBase400, or fontSizeBase500 on lineHeightBase500
// (useAccordionHeaderStyles.styles.ts:56-67,129-131).
Accordion_Size :: enum u8 {
	Small,
	Medium,
	Large,
	Extra_Large,
}

@(private)
accordion_metrics :: proc(size: Accordion_Size) -> (min_height: f32, style: tok.Type_Style) {
	switch size {
	case .Small:
		return 32, {weight = tok.FONT_WEIGHT_REGULAR, size = tok.FONT_SIZE_BASE200, line_height = tok.LINE_HEIGHT_BASE300}
	case .Medium:
		return 44, tok.TYPOGRAPHY_STYLES_BODY1
	case .Large:
		return 44, {weight = tok.FONT_WEIGHT_REGULAR, size = tok.FONT_SIZE_BASE400, line_height = tok.LINE_HEIGHT_BASE400}
	case .Extra_Large:
		return 44, {weight = tok.FONT_WEIGHT_REGULAR, size = tok.FONT_SIZE_BASE500, line_height = tok.LINE_HEIGHT_BASE500}
	}
	return 44, tok.TYPOGRAPHY_STYLES_BODY1
}

// ACCORDION_GLYPH is the expand icon's and icon's glyph size, fontSizeBase500.
@(private)
ACCORDION_GLYPH :: tok.FONT_SIZE_BASE500

// Accordion_Item is an open accordion item: its column, the panel inset
// when the item is open, and whether it is.
Accordion_Item :: struct {
	column: ui.Flex,
	panel:  ui.Inset,
	open:   bool,
}

// accordion_item_open opens one item: a column holding the header, a
// full-width button with the chevron (pointing to the end, down when
// open), an optional icon and the label, and then, only while open^,
// the panel padded spacingHorizontalM at each side for the body. A
// click, or Enter or Space while focused, flips open^; single-open and
// collapsible rules are the caller's, who owns the open flags. The
// header has no hover or press colour and no transition, by the spec.
// Close it with accordion_item_close, which closes the panel only if it
// was opened. Departure: the panel's Collapse motion (height and
// opacity over durationNormal) is not applied; jm:ui has no group
// opacity, so the panel appears at once.
accordion_item_open :: proc(
	gtx: ^ui.Ctx,
	header: string,
	open: ^bool,
	ic := Icon.None,
	size := Accordion_Size.Medium,
	icon_end := false,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> Accordion_Item {
	it: Accordion_Item
	it.column = ui.column_open(gtx, align = .Fill, key = key, loc = loc)
	accordion_header(gtx, header, open, ic, size, icon_end, state, key, loc)
	it.open = open^
	if it.open {
		it.panel = ui.inset_open(gtx, ui.pad_xy(tok.SPACING_HORIZONTAL_M, 0))
	}
	return it
}

accordion_item_close :: proc(it: ^Accordion_Item) {
	if it.open {
		ui.close(&it.panel)
	}
	ui.close(&it.column)
}

// accordion_item is accordion_item_open as a guard: the if body is the
// panel and runs only while the item is open; the item closes at the
// end of the if. The handle lives in the widget's data slot between.
@(deferred_in = accordion_item_guard_close)
accordion_item :: proc(
	gtx: ^ui.Ctx,
	header: string,
	open: ^bool,
	ic := Icon.None,
	size := Accordion_Size.Medium,
	icon_end := false,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	it := ui.guard_hold(gtx, Accordion_Item)
	it^ = accordion_item_open(gtx, header, open, ic, size, icon_end, state, key, loc)
	return it.open
}

@(private = "file")
accordion_item_guard_close :: proc(gtx: ^ui.Ctx, header: string, open: ^bool, ic: Icon, size: Accordion_Size, icon_end: bool, state: Interaction, key: u64, loc: runtime.Source_Code_Location) {
	accordion_item_close(ui.guard_take(gtx, Accordion_Item))
}

// accordion_header is the item's button (useAccordionHeaderStyles.
// styles.ts:18-105): as wide as it is offered, at least min_height tall,
// padded spacingHorizontalMNudge at the chevron's end and
// spacingHorizontalM at the other (spacingHorizontalM at both when the
// chevron is at the end and there is no icon), the chevron and icon
// 20px with spacingHorizontalS after (before, for an end chevron).
// ACCORDION_HEADER_KEY tells the header's id from its item's column's.
@(private)
ACCORDION_HEADER_KEY :: u64(0x4865616465720001)

@(private)
accordion_header :: proc(gtx: ^ui.Ctx, header: string, open: ^bool, ic: Icon, size: Accordion_Size, icon_end: bool, state: Interaction, key: u64, loc: runtime.Source_Code_Location) {
	p := ui.widget_open(gtx, key ~ ACCORDION_HEADER_KEY, loc)
	min_height, style := accordion_metrics(size)
	t := shape_style(gtx, header, style)
	pad_start, pad_end := tok.SPACING_HORIZONTAL_MNUDGE, tok.SPACING_HORIZONTAL_M
	if icon_end {
		pad_start, pad_end = ic == .None ? tok.SPACING_HORIZONTAL_M : tok.SPACING_HORIZONTAL_MNUDGE, tok.SPACING_HORIZONTAL_MNUDGE
	}
	cs := gtx.constraints
	content := pad_start + ACCORDION_GLYPH + tok.SPACING_HORIZONTAL_S + t.width + pad_end
	if ic != .None {
		content += ACCORDION_GLYPH + tok.SPACING_HORIZONTAL_S
	}
	w := ui.is_finite(cs.max.x) ? cs.max.x : content
	sz := ui.constrain(cs, {max(w, content), max(min_height, t.height)})
	area := ops.Rect{0, 0, sz.x, sz.y}
	c := control(gtx, p.id, area, state)
	if c.clicked {
		open^ = !open^
	}
	fg := color(c.disabled ? .Neutral_Foreground_Disabled : .Neutral_Foreground1)
	y_glyph := (sz.y - ACCORDION_GLYPH) / 2
	x := pad_start
	if !icon_end {
		chevron(gtx, {x, y_glyph}, open^, fg)
		x += ACCORDION_GLYPH + tok.SPACING_HORIZONTAL_S
	}
	if ic != .None {
		icon(gtx, ic, {x, y_glyph}, ACCORDION_GLYPH, fg)
		x += ACCORDION_GLYPH + tok.SPACING_HORIZONTAL_S
	}
	draw_text(gtx, t, {x, (sz.y - t.height) / 2}, fg)
	if icon_end {
		chevron(gtx, {sz.x - pad_end - ACCORDION_GLYPH, y_glyph}, open^, fg)
	}
	paint_focus_outline(gtx, c, {area, tok.BORDER_RADIUS_MEDIUM})
	listen(gtx, c.st, p.id, area)
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, header))
	ui.widget_close(gtx, &p, {sz, (sz.y - t.height) / 2 + baseline_of(t)})
}

// chevron is Chevron_Right at pos, turned a quarter turn about its
// centre to point down when open.
@(private)
chevron :: proc(gtx: ^ui.Ctx, pos: ops.Point, open: bool, c: ops.Color) {
	if !open {
		icon(gtx, .Chevron_Right, pos, ACCORDION_GLYPH, c)
		return
	}
	cx, cy := pos.x + ACCORDION_GLYPH / 2, pos.y + ACCORDION_GLYPH / 2
	ops.transform_push(gtx.scene, ops.mul(ops.mul(ops.translate(-cx, -cy), ops.rotate(math.PI / 2)), ops.translate(cx, cy)))
	icon(gtx, .Chevron_Right, pos, ACCORDION_GLYPH, c)
	ops.transform_pop(gtx.scene)
}
