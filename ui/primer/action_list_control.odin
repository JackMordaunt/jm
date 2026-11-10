package primer

import "jm:ui"
import "jm:ui/design"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// An item's inline control (Item_Control): a small switch or segmented
// control in the trailing slot. Primer's ActionList has no such slot; this
// is jm's, so a menu row can carry the setting it opens. The control's boxes
// are read as last laid out (Item_Memo.action), as a trailing action's are.

// INLINE_HEIGHT is the inline control's height, and SEGMENT_WIDTH an icon
// segment's width: 24px and 28px, a switch's track and a segment's
// icon with 6px each side.
@(private)
INLINE_HEIGHT :: tok.CONTROL_XSMALL_SIZE
@(private)
SEGMENT_WIDTH :: f32(28)

// INLINE_SWITCH_WIDTH is the inline switch's track width: 40px, a slimmer
// track than the stand-alone small switch's 48, so it is no bulkier than
// the segmented control beside it at the same 24px height.
@(private)
INLINE_SWITCH_WIDTH :: f32(40)

// control_widths is the inline control's width and each segment's, a
// segment with an icon being SEGMENT_WIDTH and one with only a label that
// label's width with 8px each side. Segments are inset 1px by the track's
// border.
@(private)
control_widths :: proc(gtx: ^ui.Ctx, c: Item_Control) -> (total: f32, each: []f32) {
	switch c.kind {
	case .None:
		return 0, nil
	case .Switch:
		return INLINE_SWITCH_WIDTH, nil
	case .Segmented:
	}

	//review:ignore odin-allocator-parameter the frame's allocator is gtx.allocator, as in every proc of this file
	each = make([]f32, len(c.segments), gtx.allocator)
	total = 2 * tok.BORDER_WIDTH_THIN
	st := tok.Type_Style{weight = tok.BASE_TEXT_WEIGHT_NORMAL, size = tok.TEXT_BODY_SIZE_SMALL, line_height = LIST_SMALL_LINE}
	for s, i in c.segments {
		each[i] = SEGMENT_WIDTH
		if s.icon == .None {
			each[i] = design.shape_style(gtx, s.label, st, font_for(gtx, st.weight)).width + 2 * tok.BASE_SIZE_8
		}
		total += each[i]
	}
	return
}

// segment_rect is segment i's box inside the control's box r.
@(private)
segment_rect :: proc(r: ops.Rect, each: []f32, i: int) -> ops.Rect {
	b := tok.BORDER_WIDTH_THIN
	x := r.x + b
	for w in each[:i] {
		x += w
	}
	return {x, r.y + b, each[i], r.h - 2 * b}
}

// item_control_copy is c with what it points at kept for the frame: the
// list lays its items out when it closes, after the caller's slice or
// string may be gone. A control with nothing to bind is no control.
@(private)
item_control_copy :: proc(gtx: ^ui.Ctx, c: Item_Control) -> (k: Item_Control) {
	switch {
	case c.kind == .Switch && c.on != nil:
	case c.kind == .Segmented && c.selected != nil && len(c.segments) > 0:
	case:
		return
	}
	k = c
	k.name = ui.frame_string(gtx, c.name)
	if c.kind == .Segmented {
		//review:ignore odin-allocator-parameter the frame's allocator is gtx.allocator, as in every proc of this file
		k.segments = make([]Segment, len(c.segments), gtx.allocator)
		for s, i in c.segments {
			k.segments[i] = s
			k.segments[i].label = ui.frame_string(gtx, s.label)
		}
	}
	return
}

// item_control_events reads what reached an item's control this frame
// against the box it had last frame: a press on the switch or a segment,
// and ArrowLeft or ArrowRight the item heard, which it takes from the owner.
@(private)
item_control_events :: proc(l: ^Action_List, it: ^List_Item, memo: ^Item_Memo, dead: bool, state: Interaction) {
	gtx := l.gtx
	c := it.control
	if c.kind == .None {
		return
	}
	step := 0
	if !dead && l.keyed == it.index && (l.key == .Left || l.key == .Right) {
		step = l.key == .Right ? 1 : -1
		l.key, l.mods, l.keyed = .None, {}, -1
	}

	id := ui.id_mix(it.id, ITEM_ACTION)
	changed, pressed, hovered := false, false, false
	switch c.kind {
	case .None:
	case .Switch:
		it.ctl = control(gtx, id, memo.action, state)
		want := c.on^
		if it.ctl.clicked && !dead {
			want = !want
		}
		if step != 0 {
			want = step > 0
		}
		changed = want != c.on^
		c.on^ = want
		it.value = int(want)
		pressed, hovered = it.ctl.press, it.ctl.hovered
	case .Segmented:
		_, each := control_widths(gtx, c)
		//review:ignore odin-allocator-parameter the frame's allocator is gtx.allocator, as in every proc of this file
		it.segs = make([]Control, len(c.segments), gtx.allocator)
		want := clamp(c.selected^, 0, len(c.segments) - 1)
		for i in 0 ..< len(c.segments) {
			sc := control(gtx, ui.id_mix(id, u64(i + 1)), segment_rect(memo.action, each, i), state if !c.segments[i].disabled else .Disabled)
			it.segs[i] = sc
			if sc.clicked && !sc.disabled && !dead {
				want = i
			}
			pressed |= sc.press
			hovered |= sc.hovered
		}
		if step != 0 {
			want = clamp(want + step, 0, len(c.segments) - 1)
		}
		changed = want != c.selected^
		c.selected^ = want
		it.value = want
	}

	if changed && c.changed != nil {
		c.changed^ = true
	}

	if pressed && !dead {
		// The control is not a focus target: the item keeps focus, so the
		// arrows go on moving through the list.
		ui.focus_request(gtx, it.id)
	}

	if hovered && !it.c.hovered {
		// The control takes the pointer from the item, which stays lit.
		it.c.hovered = true
		it.c.state = design.effective_state(it.c.base)
	}
}

// paint_item_control draws and declares an item's control at g.action, after
// the item's own input area so that a press on it lands on the control.
@(private)
paint_item_control :: proc(l: ^Action_List, it: ^List_Item, g: Item_Geom, dead: bool) {
	gtx := l.gtx
	c := it.control
	r := g.action
	id := ui.id_mix(it.id, ITEM_ACTION)
	kinds := ops.Event_Kinds{.Press, .Release, .Enter, .Leave, .Move}
	switch c.kind {
	case .None:
	case .Switch:
		ctl := it.ctl
		if dead {
			ctl.disabled, ctl.state = true, .Disabled
		}
		paint_switch(gtx, ctl, id, r, it.value == 1, true)
		listen(gtx, ctl.st, id, r, kinds, .Not_Allowed if dead else .Pointer)
		said := ui.frame_string(gtx, c.name)
		ops.tag(gtx.scene, id, said != "" ? said : "toggle switch", r)
		ui.part_semantics(gtx, &l.p, id, r, {role = .Switch, label = said, states = design.state_if(it.value == 1, {.Checked}) + design.state_if(ctl.disabled, {.Disabled})})
	case .Segmented:
		_, each := control_widths(gtx, c)
		rr := ops.Round_Rect{r, tok.BORDER_RADIUS_MEDIUM}
		ops.fill(gtx.scene, rr, color(.Control_Track_Bg_Color_Rest))
		stroke_inside(gtx, rr, color(.Control_Track_Border_Color_Rest), tok.BORDER_WIDTH_THIN)

		st := tok.Type_Style{weight = tok.BASE_TEXT_WEIGHT_NORMAL, size = tok.TEXT_BODY_SIZE_SMALL, line_height = LIST_SMALL_LINE}
		for s, i in c.segments {
			sc := it.segs[i]
			on := i == it.value
			box := segment_rect(r, each, i)
			srr := ops.Round_Rect{box, tok.BORDER_RADIUS_MEDIUM - tok.BORDER_WIDTH_THIN}
			switch {
			case on:
				ops.fill(gtx.scene, srr, color(.Control_Knob_Bg_Color_Rest))
				stroke_inside(gtx, srr, color(.Control_Knob_Border_Color_Rest), tok.BORDER_WIDTH_THIN)
			case sc.hovered && !sc.disabled:
				ops.fill(gtx.scene, srr, color(.Control_Track_Bg_Color_Hover))
			}

			ink := color(on ? .Fg_Color_Default : .Fg_Color_Muted)
			if sc.disabled || dead {
				ink = color(.Control_Fg_Color_Disabled)
			}
			if s.icon != .None {
				icon(gtx, s.icon, {box.x + (box.w - BUTTON_ICON) / 2, box.y + (box.h - BUTTON_ICON) / 2}, BUTTON_ICON, ink)
			} else {
				if on {
					st.weight = tok.BASE_TEXT_WEIGHT_SEMIBOLD
				}
				t := design.shape_style(gtx, s.label, st, font_for(gtx, st.weight))
				draw_text(gtx, t, {box.x + (box.w - t.width) / 2, box.y + (box.h - t.height) / 2}, ink)
				st.weight = tok.BASE_TEXT_WEIGHT_NORMAL
			}

			sid := ui.id_mix(id, u64(i + 1))
			listen(gtx, sc.st, sid, srr, kinds, .Not_Allowed if sc.disabled || dead else .Pointer)
			label := ui.frame_string(gtx, s.label)
			ops.tag(gtx.scene, sid, label, box)
			ui.part_semantics(gtx, &l.p, sid, box, {role = .Radio, label = label, states = design.state_if(on, {.Checked}) + design.state_if(sc.disabled || dead, {.Disabled})})

			if sc.st != nil && s.icon != .None && label != "" {
				tooltip_run(gtx, sid, box, label, .S, .Short, false, false)
			}
		}
	}
}
