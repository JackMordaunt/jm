package ui

import "jm:ui/ops"

// Selectable text: read-only text a user can select and copy, as a
// browser lets a page's ordinary text be. A label calls selectable_text with
// its laid-out paragraph and paints what it returns; the toolkit keeps one
// selection for the whole app, as a page has one, so only the label that
// owns it holds any state.
//
// The label's area yields (ops.Input_Area.yields): inside a clickable card
// or list row a click still clicks the card, and only a drag, or a double
// or triple click, starting on the text selects it. The label takes focus
// when it takes the press, so SHORTCUT+C and SHORTCUT+A reach it, but Tab
// passes it by (no_tab); a press anywhere else, or a change to its text,
// drops the selection.

// Label_Selection is the one selection in read-only text: the label that
// owns it, and a copy of its text with the caret and anchor in it.
Label_Selection :: struct {
	owner: ops.Area_Id,
	state: Text_State,
}

// LABEL_KINDS is what selectable text's area asks for.
LABEL_KINDS :: ops.Event_Kinds{.Press, .Release, .Move, .Key, .Focus, .Blur}

// selectable_text makes paragraph p selectable: its area covers bounds
// in the widget's space, p is drawn with its top-left at at, and id is the
// widget's own Area_Id. It returns the selected byte range of p.text to
// highlight (lo == hi when nothing is) and whether the label has focus,
// for the focused or inactive highlight.
selectable_text :: proc(gtx: ^Ctx, id: ops.Area_Id, p: Paragraph, at: ops.Point, bounds: ops.Rect) -> (lo, hi: int, focused: bool) {
	if gtx.layout == nil || gtx.router == nil {
		return
	}
	sel := &gtx.layout.selection
	for e in events(gtx, id) {
		#partial switch e.kind {
		case .Press:
			if sel.owner != id {
				sel.owner = id
				text_set(&sel.state, p.text)
				text_move(&sel.state, 0)
			}
			text_follow_pointer(&sel.state, p, e, e.pos - at, text_stops(gtx, &sel.state, p.font, p.size))
		case .Move, .Release:
			if sel.owner == id {
				text_follow_pointer(&sel.state, p, e, e.pos - at, text_stops(gtx, &sel.state, p.font, p.size))
			}
		case .Key:
			if sel.owner == id {
				text_edit(gtx, &sel.state, id, e, text_stops(gtx, &sel.state, p.font, p.size), read_only = true)
			}
		}
	}
	if sel.owner == id {
		r := gtx.router
		if (r.press_seen && r.pressed_at != id) || text_string(&sel.state) != p.text {
			sel.owner = 0
			text_move(&sel.state, 0)
		}
	}
	ops.input_area(gtx.scene, id, bounds, LABEL_KINDS, .Text, yields = true, no_tab = true)
	if sel.owner != id {
		return
	}
	lo, hi = text_selection(&sel.state)
	return lo, hi, gtx.router.focus == id
}

// label_selection is the text the app's selected label has selected, ""
// when none does.
label_selection :: proc(gtx: ^Ctx) -> string {
	if gtx.layout == nil || gtx.layout.selection.owner == 0 {
		return ""
	}
	return text_selected(&gtx.layout.selection.state)
}
