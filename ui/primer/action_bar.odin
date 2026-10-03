package primer

import "jm:ui"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// ActionBar (primer-kit components/action-bar.json): a one-row toolbar of
// invisible IconButtons and Buttons, split by dividers and groups, that
// moves whatever does not fit into a trailing "More items" menu.

// Action_Bar_Gap is the space between items: --stack-gap-condensed, or
// none, which pads dividers 8px instead (ActionBar.module.css:44-55).
Action_Bar_Gap :: enum u8 {
	Condensed,
	None,
}

// ACTION_BAR_DIVIDER is a divider's line: 1px by 20px
// (ActionBar.module.css:83-94).
ACTION_BAR_DIVIDER :: tok.BASE_SIZE_20

// Action_Bar is an open toolbar between action_bar_open and
// action_bar_close.
Action_Bar :: struct {
	gtx:     ^ui.Ctx,
	id:      ops.Area_Id,
	size:    Button_Size,
	gap:     Action_Bar_Gap,
	data:    ^Action_Bar_Data,
	outer:   ui.Inset,
	justify: ui.Flex,
	row:     ui.Flex,
	group:   ui.Flex,
	grouped: bool,
	entries: [dynamic]Bar_Entry,
	children: int, // children of the row so far, the spacer included
}

// Bar_Entry is one item as declared: what the More menu shows for it.
@(private)
Bar_Entry :: struct {
	kind:     Bar_Entry_Kind,
	ic:       Icon,
	label:    string,
	disabled: bool,
	child:    int, // the row child it is in: a group's items share one
}

@(private)
Bar_Entry_Kind :: enum u8 {
	Icon_Button,
	Button,
	Divider,
}

// Action_Bar_Data is what a bar keeps between frames.
@(private)
Action_Bar_Data :: struct {
	more:    bool, // the More button showed
	menu:    bool, // its menu is open
	chosen:  int, // one more than the entry chosen in the More menu, which reports it next frame; 0 for none
}

// action_bar_open opens a toolbar (action-bar.json) named name. size is
// the row's height, 28, 32 or 40px, and every item's; gap the space
// between items; flush drops the 16px side padding. The bar sits at the
// end of its container. Declare its items with action_bar_icon_button,
// action_bar_button, action_bar_divider and groups, then close it.
//
// The items are laid out at their widths in one row; those that do not
// fit, from the end, move into a "More items" menu behind a kebab button
// after the row (the More button's width coming out of the row, which can
// push one more item out; it hides again only once everything fits with
// it shown). A group overflows as a unit. The toolbar is one roving
// focus scope, so one tab stop: ArrowLeft and ArrowRight move between
// its items and the More button, wrapping, Home and End go to the ends
// (focus-zone.mjs:46-79, ActionBar.tsx:218-225).
//
// Departures: an item fits when all of it does, not 95% (action-bar.json
// notes allow a strict fit); an item chosen from the More menu reports
// its activation from its own call on the next frame; a disabled item is
// disabled, out of the arrows' ring, where Primer's is aria-disabled and
// stays focusable (ActionBar.tsx:357-374), as jm:ui's disabled always
// means unfocusable; ActionBar.Menu
// (an item with its own menu) is not offered; the -1px bottom margin is
// not reproduced.
action_bar_open :: proc(
	gtx: ^ui.Ctx,
	name: string,
	size := Button_Size.Medium,
	gap := Action_Bar_Gap.Condensed,
	flush := false,
	key: u64 = 0,
	loc := #caller_location,
) -> (b: Action_Bar) {
	b.gtx = gtx
	b.id = ui.claim_id(gtx, key, loc)
	b.size, b.gap = size, gap
	b.data = ui.widget_data(gtx, b.id, Action_Bar_Data)
	b.entries = make([dynamic]Bar_Entry, gtx.allocator)
	side: f32 = flush ? 0 : tok.BASE_SIZE_16
	b.outer = ui.inset_open(gtx, {left = side, right = side}, key = u64(ui.id_mix(b.id, 1)))
	ui.focus_scope_open(gtx, b.id, rove = .Horizontal, wrap = true)
	b.justify = ui.row_open(gtx, align = .Center, justify = .End, key = u64(ui.id_mix(b.id, 2)))
	b.row = ui.overflow_row_open(gtx, bar_gap(gap), .Start, key = u64(ui.id_mix(b.id, 3)))
	ui.container_semantics(gtx, {role = .Toolbar, label = ui.frame_string(gtx, name)}, b.row.index)
	// The zero-width first child lets the first real item overflow too,
	// and the gap after it opens 8px before the items (ActionBar.tsx:240-242).
	ui.spacer(gtx, 0)
	b.children = 1
	return
}

// bar_gap is the gap between items.
@(private)
bar_gap :: proc(g: Action_Bar_Gap) -> f32 {
	return g == .Condensed ? tok.STACK_GAP_CONDENSED : 0
}

// bar_item records the next item: at the top level each is a child
// of the row; in a group, of the group's row.
@(private)
bar_item :: proc(b: ^Action_Bar, e: Bar_Entry) -> (index: int) {
	index = len(b.entries)
	entry := e
	entry.child = b.children
	if !b.grouped {
		b.children += 1
	}
	append(&b.entries, entry)
	return
}

// bar_chosen reports whether the More menu chose entry index last frame.
@(private)
bar_chosen :: proc(b: ^Action_Bar, index: int) -> bool {
	if b.data.chosen == index + 1 {
		b.data.chosen = 0
		return true
	}
	return false
}

// action_bar_icon_button declares an invisible icon button named name at
// the bar's size, with its tooltip; disabled greys it in the invisible
// variant's disabled colours and ignores it. Returns true on the frame
// it is activated, or the frame after it is chosen from the More menu.
action_bar_icon_button :: proc(b: ^Action_Bar, ic: Icon, name: string, disabled := false) -> bool {
	index := bar_item(b, {kind = .Icon_Button, ic = ic, label = ui.frame_string(b.gtx, name), disabled = disabled})
	clicked := icon_button(b.gtx, ic, name, .Invisible, b.size, state = disabled ? .Disabled : .Live, key = u64(ui.id_mix(b.id, 0x100 + u64(index))))
	return clicked || bar_chosen(b, index)
}

// action_bar_button declares an invisible button with label and an
// optional leading visual at the bar's size (ActionBar.tsx:403-420).
action_bar_button :: proc(b: ^Action_Bar, label: string, leading := Icon.None, disabled := false) -> bool {
	index := bar_item(b, {kind = .Button, ic = leading, label = ui.frame_string(b.gtx, label), disabled = disabled})
	clicked := button(b.gtx, label, .Invisible, b.size, leading, state = disabled ? .Disabled : .Live, key = u64(ui.id_mix(b.id, 0x100 + u64(index))))
	return clicked || bar_chosen(b, index)
}

// action_bar_divider declares a divider: a 1px by 20px --borderColor-muted
// line centred in the row, padded 8px each side when the gap is none
// (ActionBar.module.css:44-51,83-94). It hides from a reader.
action_bar_divider :: proc(b: ^Action_Bar) {
	index := bar_item(b, {kind = .Divider})
	gtx := b.gtx
	pad: f32 = b.gap == .None ? tok.BASE_SIZE_8 : 0
	row := button_metrics(b.size).height
	p := ui.widget_open(gtx, u64(ui.id_mix(b.id, 0x100 + u64(index))))
	ops.fill(gtx.scene, ops.Rect{pad, (row - ACTION_BAR_DIVIDER) / 2, tok.BORDER_WIDTH_THIN, ACTION_BAR_DIVIDER}, color(.Border_Color_Muted))
	ui.widget_close(gtx, &p, {{2 * pad + tok.BORDER_WIDTH_THIN, row}, 0})
}

// action_bar_group_open opens a group: its items overflow together, as
// one (ActionBar.tsx:428-443).
action_bar_group_open :: proc(b: ^Action_Bar) {
	if b.grouped {
		return
	}
	b.group = ui.row_open(b.gtx, gap = bar_gap(b.gap), align = .Center, key = u64(ui.id_mix(b.id, 0x5000 + u64(b.children))))
	b.grouped = true
}

// action_bar_group_close closes the open group.
action_bar_group_close :: proc(b: ^Action_Bar) {
	if !b.grouped {
		return
	}
	ui.close(&b.group)
	b.grouped = false
	b.children += 1
}

// action_bar_close fits the row and, when some entries overflow, adds
// the More button and its menu of them (ActionBar.tsx:240-310): an icon
// button becomes an item with its icon and name, a button its label and
// leading icon, a divider a menu divider; choosing one reports it from
// its own call next frame.
action_bar_close :: proc(b: ^Action_Bar) {
	gtx := b.gtx
	d := b.data
	action_bar_group_close(b)
	more_w := button_metrics(b.size).height + bar_gap(b.gap)
	dropped: int
	if d.more {
		dropped = ui.flex_fit(&b.row, more_w)
	} else {
		dropped = ui.flex_fit(&b.row, 0)
		if dropped > 0 {
			dropped += ui.flex_fit(&b.row, more_w)
		}
	}
	kept := ui.flex_count(&b.row) // the spacer included
	d.more = dropped > 0
	if !d.more {
		d.menu = false
	}
	if d.more {
		bar_more(b, kept)
	}
	ui.close(&b.row)
	ui.close(&b.justify)
	ui.focus_scope_close(gtx)
	ui.close(&b.outer)
}

// bar_more is the More button, an invisible kebab icon button labelled
// "More items" at the bar's size, and its menu of the entries from the
// first child the row dropped (ActionBar.tsx:211-216,238-310).
@(private)
bar_more :: proc(b: ^Action_Bar, kept: int) {
	gtx := b.gtx
	d := b.data
	st := ui.stack_open(gtx, key = u64(ui.id_mix(b.id, 4)))
	if icon_button(gtx, .Kebab_Horizontal, "More items", .Invisible, b.size, expanded = d.menu, key = u64(ui.id_mix(b.id, 5))) {
		d.menu = !d.menu
	}
	more := ui.last_widget(gtx)
	m := action_menu_open(gtx, &d.menu, more, name = "More items", key = u64(ui.id_mix(b.id, 6)))
	for e, i in b.entries {
		if e.child < kept {
			continue
		}
		switch e.kind {
		case .Divider:
			action_menu_divider(&m)
		case .Icon_Button, .Button:
			if action_menu_item(&m, e.label, leading = e.ic, disabled = e.disabled) {
				d.chosen = i + 1
				ui.request_frame(gtx)
			}
		}
	}
	action_menu_close(&m)
	ui.close(&st)
}
