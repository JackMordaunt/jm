package primer

import "jm:ui"
import "jm:ui/design"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// Segment is one of a SegmentedControl's buttons: a label, an optional
// 16px leading icon and count, or, with icon_only, just its icon, the
// label then being its accessible name. disabled greys it and ignores
// presses; divider puts a SegmentedControl.Divider before it, which only
// the subtle variant draws.
Segment :: struct {
	label:     string,
	icon:      Icon,
	count:     string,
	icon_only: bool,
	disabled:  bool,
	divider:   bool,
}

// Segmented_Variant is a SegmentedControl's look: default draws a track
// with a sliding knob under the selection; subtle draws no track and a
// muted pill.
Segmented_Variant :: enum u8 {
	Default,
	Subtle,
}

// Segmented_Size is a SegmentedControl's height: 32px or 28px.
Segmented_Size :: enum u8 {
	Medium,
	Small,
}

// SEGMENT_PAD is a segment's inline padding inside its content box, and
// SEGMENT_INSET how far an unselected segment's content sits inside it
// (--segmented-control-button-inner-padding and -bg-inset,
// SegmentedControl.module.css:471-489): 12px and 4px, literals.
@(private)
SEGMENT_PAD :: tok.BASE_SIZE_12
@(private)
SEGMENT_INSET :: tok.BASE_SIZE_4

// SEGMENT_ICON_WIDTH is an icon-only segment's width at either size
// (--segmented-control-icon-width, SegmentedControl.module.css:99-100).
@(private)
SEGMENT_ICON_WIDTH :: tok.BASE_SIZE_32

// SEGMENT_SLIDE is the knob's slide and the hover fill's fade: 200ms
// --base-easing-easeInOut (SegmentedControl.module.css:115-134,560).
@(private)
SEGMENT_SLIDE :: tok.Transition{tok.BASE_DURATION_200, tok.BASE_EASING_EASE_IN_OUT}

// Segment_Knob is the knob's travel between frames: the rect it slides
// from and to.
@(private)
Segment_Knob :: struct {
	from, to, at: ops.Rect,
	live:         bool,
	tween:        ui.Tween,
	count:        int, // segments last frame: a change suppresses the slide
}

// segment_style is a segment's label: body text at the control's size,
// semibold when selected (SegmentedControl.module.css:471-494,572-580).
@(private)
segment_style :: proc(size: Segmented_Size, semibold: bool) -> tok.Type_Style {
	sz := size == .Small ? tok.TEXT_BODY_SIZE_SMALL : tok.TEXT_BODY_SIZE_MEDIUM
	return {weight = semibold ? tok.BASE_TEXT_WEIGHT_SEMIBOLD : tok.BASE_TEXT_WEIGHT_NORMAL, size = sz, line_height = sz * 1.5}
}

// Segment_Content is one segment's measured content.
@(private)
Segment_Content :: struct {
	label, bold, count: Text,
	w:                  f32, // icon, 4px, the semibold label, 8px, count
}

@(private)
measure_segment :: proc(gtx: ^ui.Ctx, s: Segment, size: Segmented_Size, hide_labels: bool) -> (sc: Segment_Content) {
	reg, semi := segment_style(size, false), segment_style(size, true)
	sc.label = design.shape_style(gtx, s.label, reg, font_for(gtx, reg.weight))
	sc.bold = design.shape_style(gtx, s.label, semi, font_for(gtx, semi.weight))
	cst := counter_style()
	sc.count = design.shape_style(gtx, s.count, cst, font_for(gtx, cst.weight))
	if s.icon != .None {
		sc.w += BUTTON_ICON
	}
	if !hide_labels {
		if s.icon != .None {
			sc.w += tok.BASE_SIZE_4
		}
		sc.w += sc.bold.width
	}
	if s.count != "" {
		sc.w += tok.BASE_SIZE_8 + counter_size(sc.count).x
	}
	return
}

// segmented_control is Primer's SegmentedControl (segmented-control.json):
// two to five mutually exclusive buttons for how content is viewed, one
// always selected. selected^ is the index; a press, Enter or Space on an
// enabled segment sets it, and the control returns true on that frame,
// even when it was already selected (SegmentedControl.tsx:226-237). Each
// segment is as wide as its content set in semibold plus 12px each side
// and its 1px content border, so selecting never changes its width; an
// icon-only one is 32px. full_width grows every segment equally into the
// width offered. In the default variant the knob (--controlKnob-bgColor
// -rest, bordered, medium radius) slides between segments over 200ms,
// 1px separators show between unselected neighbours and an unselected
// segment's inset content fills --controlTrack-bgColor-hover on hover.
// Keyboard focus outlines a segment 2px in --fgColor-accent at -1px.
// name is the control's accessible name; each segment is a toggle
// button, its own tab stop, arrow keys doing nothing. hide_labels draws
// only the icons.
//
// Departures: the dropdown variant, per-viewport-range values and the
// trailing action are not built (a page composes an IconButton beside
// it); icon-only segments show no tooltip; the coarse-pointer 44px target
// is not drawn; segments are announced as buttons with a selected state,
// as ops has no pressed state.
segmented_control :: proc(
	gtx: ^ui.Ctx,
	segments: []Segment,
	selected: ^int,
	name := "",
	size := Segmented_Size.Medium,
	variant := Segmented_Variant.Default,
	full_width := false,
	hide_labels := false,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_open(gtx, key, loc)
	n := len(segments)
	subtle := variant == .Subtle
	h: f32 = size == .Small ? tok.CONTROL_SMALL_SIZE : tok.CONTROL_MEDIUM_SIZE
	// The track's border, which segments overlap by 1px at the top,
	// bottom and outer ends; subtle has none (SegmentedControl.module.css
	// :409-450).
	b: f32 = subtle ? 0 : tok.BORDER_WIDTH_THIN
	content := make([]Segment_Content, n, gtx.allocator)
	widths := make([]f32, n, gtx.allocator)
	total: f32
	for s, i in segments {
		content[i] = measure_segment(gtx, s, size, hide_labels)
		if s.icon_only || (hide_labels && s.icon != .None) {
			widths[i] = SEGMENT_ICON_WIDTH
		} else {
			// Content, 12px each side, and the content's 1px border in the
			// default variant (subtle drops it).
			widths[i] = content[i].w + 2 * SEGMENT_PAD + (subtle ? 0 : 2 * tok.BORDER_WIDTH_THIN)
		}
		total += widths[i]
		if i > 0 {
			total += 1 // the 1px each segment but the last keeps after it
			if subtle && s.divider {
				total += 2 * tok.BASE_SIZE_8 // 8px, the 1px rule, 7px
			}
		}
	}
	natural := total + 2 * b - 2 * (b > 0 ? 1 : 0)
	cs := gtx.constraints
	sz := ui.constrain(cs, {full_width && ui.is_finite(cs.max.x) ? cs.max.x : natural, h})
	if sz.x > natural && n > 0 {
		extra := (sz.x - natural) / f32(n)
		for &w in widths {
			w += extra
		}
	}
	track := ops.Rect{0, 0, sz.x, h}
	if !subtle {
		rr := ops.Round_Rect{track, tok.BORDER_RADIUS_MEDIUM}
		ops.fill(gtx.scene, rr, color(.Control_Track_Bg_Color_Rest))
		stroke_inside(gtx, rr, color(.Control_Track_Border_Color_Rest), b)
	}
	rects := make([]ops.Rect, n, gtx.allocator)
	x := b - (b > 0 ? 1 : 0)
	for s, i in segments {
		if i > 0 && subtle && s.divider {
			ops.fill(gtx.scene, ops.Rect{x + tok.BASE_SIZE_8, tok.BASE_SIZE_8, 1, h - 2 * tok.BASE_SIZE_8}, color(.Border_Color_Default))
			x += 2 * tok.BASE_SIZE_8
		}
		rects[i] = {x, b - (b > 0 ? 1 : 0), widths[i], h - 2 * b + 2 * (b > 0 ? 1 : 0)}
		x += widths[i] + 1
	}
	sel := clamp(selected^, 0, max(n - 1, 0))
	pressed := -1
	if n > 0 && !subtle {
		paint_knob(gtx, p.id, rects[sel], n, state)
	}
	said := ui.frame_string(gtx, name)
	ui.semantics(gtx, &p, {role = .List, label = said})
	// A forced state shows on the first unselected segment: hover and
	// press have no look on the selected one.
	shown := sel == 0 ? 1 : 0
	for s, i in segments {
		st := state
		if state != .Live && i != shown {
			st = .Enabled
		}
		if segment_button(gtx, &p, s, content[i], rects[i], i == sel, i, size, variant, hide_labels, st) {
			pressed = i
		}
		// A separator 1px past the gap after a segment, inset 8px top and
		// bottom, unless the segment or the next is selected.
		if !subtle && i < n - 1 && i != sel && i + 1 != sel {
			r := rects[i]
			ops.fill(gtx.scene, ops.Rect{r.x + r.w + 1, r.y + tok.BASE_SIZE_8, 1, r.h - 2 * tok.BASE_SIZE_8}, color(.Border_Color_Default))
		}
	}
	if pressed >= 0 {
		selected^ = pressed
	}
	ops.tag(gtx.scene, p.id, said != "" ? said : "segmented control", track)
	ui.widget_close(gtx, &p, {sz, 0})
	return pressed >= 0
}

// paint_knob draws the default variant's knob under the selected segment
// at to, sliding there from where it was over SEGMENT_SLIDE; it jumps
// when the number of segments changed (SegmentedControl.tsx:58-72) or
// the state is forced.
@(private)
paint_knob :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, to: ops.Rect, n: int, state: Interaction) {
	at := to
	if state == .Live {
		k := ui.widget_data(gtx, ui.id_mix(id, 0x6b0b), Segment_Knob)
		if !k.live || k.count != n {
			k^ = {from = to, to = to, at = to, live = true, count = n}
		} else if to != k.to {
			k.from, k.to = k.at, to
			k.tween = {to = 1, duration = SEGMENT_SLIDE.duration / 1000}
		}
		e := design.bezier_ease(SEGMENT_SLIDE.easing, ui.tween_update(&k.tween, gtx))
		k.at = {
			k.from.x + (k.to.x - k.from.x) * e,
			k.from.y + (k.to.y - k.from.y) * e,
			k.from.w + (k.to.w - k.from.w) * e,
			k.from.h + (k.to.h - k.from.h) * e,
		}
		at = k.at
	}
	rr := ops.Round_Rect{at, tok.BORDER_RADIUS_MEDIUM}
	ops.fill(gtx.scene, rr, color(.Control_Knob_Bg_Color_Rest))
	stroke_inside(gtx, rr, color(.Control_Knob_Border_Color_Rest), tok.BORDER_WIDTH_THIN)
}

// segment_button draws one segment in r and reports a press on it.
@(private)
segment_button :: proc(gtx: ^ui.Ctx, p: ^ui.Placement, s: Segment, sc: Segment_Content, r: ops.Rect, selected: bool, i: int, size: Segmented_Size, variant: Segmented_Variant, hide_labels: bool, state: Interaction) -> bool {
	id := ui.id_mix(p.id, u64(i) + 1)
	c := control(gtx, id, r, s.disabled ? .Disabled : state)
	subtle := variant == .Subtle
	// The content box: inset 4px unless selected or subtle; its radius
	// the outer less half the inset (SegmentedControl.module.css:549-570).
	inset := selected || subtle ? 0 : SEGMENT_INSET
	box := ops.Rect{r.x + inset, r.y + inset, r.w - 2 * inset, r.h - 2 * inset}
	radius := subtle ? tok.BORDER_RADIUS_LARGE - SEGMENT_INSET / 2 : tok.BORDER_RADIUS_MEDIUM - inset / 2
	fill := tok.Role.Bg_Color_Transparent
	if subtle && selected {
		fill = .Bg_Color_Muted
	} else if !selected && !c.disabled {
		fill = role_for({.Bg_Color_Transparent, .Control_Track_Bg_Color_Hover, .Control_Track_Bg_Color_Active, .Bg_Color_Transparent}, c)
	}
	bg := design.blend(gtx, c.fades, 0, color(fill), c.pressed ? 0 : SEGMENT_SLIDE.duration, SEGMENT_SLIDE.easing)
	if ui.painted(bg) {
		ops.fill(gtx.scene, ops.Round_Rect{box, radius}, bg)
	}
	fg, ic := tok.Role.Fg_Color_Default, tok.Role.Fg_Color_Muted
	switch {
	case c.disabled && !selected:
		fg, ic = .Fg_Color_Disabled, .Fg_Color_Disabled
	case subtle && !selected:
		fg = .Fg_Color_Muted
	}
	icon_only := s.icon_only || (hide_labels && s.icon != .None)
	text := selected ? sc.bold : sc.label
	cw := icon_only ? BUTTON_ICON : sc.w
	x := r.x + (r.w - cw) / 2
	if s.icon != .None {
		icon(gtx, s.icon, {x, r.y + (r.h - BUTTON_ICON) / 2}, BUTTON_ICON, color(ic))
		x += BUTTON_ICON + tok.BASE_SIZE_4
	}
	if !icon_only && !hide_labels {
		// The label is centred in the semibold width it reserves.
		draw_text(gtx, text, {x + (sc.bold.width - text.width) / 2, r.y + (r.h - text.height) / 2}, color(fg))
		x += sc.bold.width
	}
	if s.count != "" && !icon_only {
		csz := counter_size(sc.count)
		paint_counter(gtx, sc.count, {x + tok.BASE_SIZE_8, r.y + (r.h - csz.y) / 2}, counter_colors(.Secondary))
	}
	if c.focus_visible && !c.disabled {
		design.paint_focus_ring(gtx, c.base, {r, radius + inset / 2}, {tok.BASE_SIZE_2, -tok.BORDER_WIDTH_THIN, color(.Fg_Color_Accent)})
	}
	listen(gtx, c.st, id, r, cursor = .Pointer)
	said := ui.frame_string(gtx, s.label)
	ops.tag(gtx.scene, id, said)
	ui.part_semantics(gtx, p, id, r, {role = .Button, label = said, states = design.state_if(selected, {.Selected}) + design.state_if(c.disabled, {.Disabled})})
	return c.clicked && !c.disabled
}
