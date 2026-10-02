package primer

import "jm:ui"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// ButtonGroup joins buttons into one strip whose borders touch (primer-kit
// button-group.json, ButtonGroup.module.css): no gap, each item over the
// next by 1px so a joint is one border, the first item's start corners and
// the last item's end corners rounded and every other corner square. A
// hovered or pressed item draws its border over its neighbours'. As a
// toolbar, Left and Right move focus among its buttons and wrap.
//
//	g := primer.button_group_open(gtx, 3, "Formatting")
//	primer.button(gtx, "Bold", group = &g)
//	...
//	primer.button_group_close(&g)
//
// count is how many buttons follow: the caller knows it, where the web
// counts its DOM children, and an empty child is left out rather than
// given a slot (button-group.json notes).
//
// Departures: each button is its own Tab stop in a toolbar too, where
// focus-zone makes the web's one (button-group.json notes, inferred).

// MAX_GROUP_BUTTONS bounds a group's buttons.
MAX_GROUP_BUTTONS :: 16

Button_Group :: struct {
	gtx:     ^ui.Ctx,
	row:     ui.Flex,
	count:   int,
	joined:  int,
	toolbar: bool,
	ids:     [MAX_GROUP_BUTTONS]ops.Area_Id,
	from:    int, // the member an arrow key was pressed on, with move
	move:    int,
}

// button_group_open starts a group of count buttons, labelled label for
// assistive technology; toolbar makes it a toolbar whose arrows move
// focus. Close it with button_group_close.
button_group_open :: proc(gtx: ^ui.Ctx, count: int, label := "", toolbar := false, key: u64 = 0, loc := #caller_location) -> Button_Group {
	assert(count >= 1 && count <= MAX_GROUP_BUTTONS, "primer: a button group holds 1 to MAX_GROUP_BUTTONS buttons")
	g := Button_Group {
		gtx     = gtx,
		count   = count,
		toolbar = toolbar,
	}
	g.row = ui.row_open(gtx, gap = -tok.BORDER_WIDTH_THIN, align = .Center, key = key, loc = loc)
	ui.container_semantics(gtx, {role = toolbar ? .Toolbar : .Group, label = ui.frame_string(gtx, label)})
	return g
}

// button_group_close ends g, moving focus if an arrow key asked to.
button_group_close :: proc(g: ^Button_Group) {
	// The last item's -1px end margin too: the group's box ends 1px inside
	// its last button (ButtonGroup.module.css:6-9).
	ui.spacer(g.gtx, -tok.BORDER_WIDTH_THIN)
	ui.close(&g.row)
	if g.move != 0 && g.joined > 0 {
		n := g.joined
		ui.focus_request(g.gtx, g.ids[((g.from + g.move) % n + n) % n])
	}
}

// group_join enrols the button with id in g and returns its index.
@(private)
group_join :: proc(g: ^Button_Group, id: ops.Area_Id) -> int {
	assert(g.joined < g.count, "primer: more buttons than the group's count")
	i := g.joined
	g.ids[i] = id
	g.joined += 1
	return i
}

// group_corners is item i's corners in a group of n: the first rounds its
// start, the last its end, one alone all four (ButtonGroup.module.css:11-31).
@(private)
group_corners :: proc(i, n: int) -> Corners {
	r := tok.BORDER_RADIUS_MEDIUM
	k: Corners
	if i == 0 {
		k.tl, k.bl = r, r
	}
	if i == n - 1 {
		k.tr, k.br = r, r
	}
	return k
}

// read_group_keys reads a toolbar member's arrow keys: Left and Right ask the
// group to move focus from item i when the button closes the group.
@(private)
read_group_keys :: proc(gtx: ^ui.Ctx, g: ^Button_Group, id: ops.Area_Id, i: int) {
	if !g.toolbar {
		return
	}
	for e in ui.events(gtx, id) {
		if e.kind != .Key || e.mods != {} {
			continue
		}
		#partial switch e.key {
		case .Left:
			g.from, g.move = i, -1
		case .Right:
			g.from, g.move = i, 1
		}
	}
}

// paint_group_border draws a grouped item's border in k, and again above
// the frame when it is hovered or pressed, so its colour wins the 1px it
// shares with a neighbour drawn after it (ButtonGroup.module.css:33-41).
@(private)
paint_group_border :: proc(gtx: ^ui.Ctx, c: Control, r: ops.Rect, k: Corners, border: ops.Color) {
	if !ui.painted(border) {
		return
	}
	stroke_inside_corners(gtx, r, k, border, tok.BORDER_WIDTH_THIN)
	if (c.state == .Hovered || c.state == .Pressed) && !c.disabled {
		m := ops.macro_open(gtx.scene)
		stroke_inside_corners(gtx, r, k, border, tok.BORDER_WIDTH_THIN)
		ops.macro_close(gtx.scene, m)
		ops.defer_call(gtx.scene, m)
	}
}
