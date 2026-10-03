package primer

import "base:runtime"
import "jm:ui"
import "jm:ui/ops"

// ActionMenu (primer-kit components/action-menu.json): a floating menu of
// actions, an ActionList with menu semantics in an anchored overlay,
// opened from a button and focus-trapped while open.

// Action_Menu is an open menu between action_menu_open and
// action_menu_close.
Action_Menu :: struct {
	gtx:      ^ui.Ctx,
	open:     ^bool,
	visible:  bool,
	overlay:  Anchored_Overlay,
	list:     Action_List,
	data:     ^Menu_Data,
	parent:   ^Action_Menu,
	chosen:   bool, // an item was chosen this frame, which closes the menu and its parents
	subs:     [dynamic]Submenu_Ref,
	pushed:   bool, // a submenu's translation to its anchor item
	narrow:   bool, // fullscreen on a narrow window: Tab does not close it
}

// Menu_Data is what a menu keeps between frames: its scroll, kept so a
// focused item can be scrolled into view.
@(private)
Menu_Data :: struct {
	scroll: ui.Scroll_Offset,
}

// Submenu_Ref is an item that opens a submenu: its index in the list, the
// submenu's open flag, and how the item opened it this frame.
@(private)
Submenu_Ref :: struct {
	index:    int,
	open:     ^bool,
	focus_to: List_Focus_To,
}

// action_menu_button is ActionMenu.Button: a button with a trailing
// triangle-down that toggles open^ and reports its menu's state
// (aria-expanded), keeping its pressed colours while the menu is open.
// Returns true on the frame it toggles. Draw the menu right after it, in
// the same ui.stack, with ui.last_widget as its anchor.
action_menu_button :: proc(
	gtx: ^ui.Ctx,
	label: string,
	open: ^bool,
	leading := Icon.None,
	variant := Button_Variant.Default,
	size := Button_Size.Medium,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	if button(gtx, label, variant, size, leading, action = .Triangle_Down, expanded = open^, state = state, key = key, loc = loc) {
		open^ = !open^
		return true
	}
	return false
}

// action_menu_open shows a menu while open^ (action-menu.json), hanging
// from anchor, the button just drawn (ui.last_widget), on side aligned by
// align, 4px off it; at least 192px wide, as wide as its widest item up
// to the window less 32px, as tall as its items up to max_height (or the
// window), then scrolling. Declare its items with action_menu_item and
// the rest, then close it with action_menu_close. selection makes its
// items menu item radios (Single) or checkboxes (Multiple), with a
// checkmark column. Below NARROW_WIDTH, narrow Fullscreen covers the
// window with a Close button.
//
// How it opened decides where focus goes (useMenuInitialFocus.ts:14-76):
// a click on the anchor leaves it on the anchor; Enter, Space or
// ArrowDown on the anchor focus the first item, ArrowUp the last; any
// other opening (the caller setting open^) the first. While it is open
// with focus on the anchor, ArrowDown and ArrowUp move focus to the
// first and last item. Inside, Up and Down move focus and wrap, Home,
// End and the Page keys jump to the ends, and a letter or digit moves to
// the next item starting with it; focus is trapped. Choosing an item
// closes the menu and every menu above it; Escape closes this one and
// returns focus to its anchor; Tab or Shift+Tab in it or on its anchor
// closes the whole stack (useMenuKeyboardNavigation.ts:28-113). A press
// outside closes it; the anchor's own click toggles it.
//
// Departures: closing on Tab returns focus to the anchor where Primer
// lets it move on past it; jm:ui has no aria-haspopup; anchorRef (a menu
// anchored to something it was not opened from) is the anchor argument;
// the menu re-places itself every frame it is open.
action_menu_open :: proc(
	gtx: ^ui.Ctx,
	open: ^bool,
	anchor: ui.Last_Widget,
	selection := Selection_Variant.None,
	side := Anchor_Side.Outside_Bottom,
	align := Anchor_Align.Start,
	width := Overlay_Width.Auto,
	max_height := Overlay_Height.Auto,
	narrow := Narrow_Variant.Anchored,
	name := "",
	key: u64 = 0,
	loc := #caller_location,
) -> (m: Action_Menu) {
	return menu_open(gtx, open, anchor, selection, side, align, width, max_height, narrow, name, .None, nil, key, loc)
}

// menu_open is action_menu_open for a menu or, with parent, a submenu
// whose opening item asked for focus_to.
@(private)
menu_open :: proc(
	gtx: ^ui.Ctx,
	open: ^bool,
	anchor: ui.Last_Widget,
	selection: Selection_Variant,
	side: Anchor_Side,
	align: Anchor_Align,
	width: Overlay_Width,
	max_height: Overlay_Height,
	narrow: Narrow_Variant,
	name: string,
	sub_focus: List_Focus_To,
	parent: ^Action_Menu,
	key: u64,
	loc: runtime.Source_Code_Location,
) -> (m: Action_Menu) {
	m.gtx = gtx
	m.open = open
	m.parent = parent
	was := open^
	focus_to := List_Focus_To.None
	if parent == nil {
		focus_to = anchor_gesture(gtx, open, anchor.id, was)
	}
	ov_anchor := anchor
	focus := Overlay_Focus{prevent = true}
	if parent != nil {
		// The item is not the overlay's to listen to: its arrows move
		// focus in the parent, and only Right opens the submenu.
		ov_anchor.id = 0
		focus.return_to = anchor.id
		focus_to = sub_focus
	}
	id := ui.claim_id(gtx, key, loc)
	m.data = ui.widget_data(gtx, id, Menu_Data)
	m.overlay = anchored_overlay_open(gtx, open, ov_anchor, side, align, width = width, narrow = narrow, focus = focus, max_height = max_height, scroll = &m.data.scroll, key = u64(ui.id_mix(id, 1)), loc = loc)
	if parent == nil {
		ui.widget_data(gtx, ui.id_mix(anchor.id, 0x3e9), Anchor_Memo).open = open^
	}
	if m.overlay.opened == .Anchor_Key_Press {
		// ArrowDown or ArrowUp on the closed anchor (AnchoredOverlay.tsx
		// :218-246) picks the first or last item.
		focus_to = anchor_arrow(gtx, anchor.id)
	}
	if !open^ {
		m.data.scroll = {}
	}
	m.visible = m.overlay.visible
	if !m.visible {
		return
	}
	m.narrow = narrow == .Fullscreen && gtx.viewport.x < NARROW_WIDTH
	m.subs = make([dynamic]Submenu_Ref, gtx.allocator)
	view := m.overlay.surface.look.data.size.y
	m.list = action_list_open(
		gtx,
		.Inset,
		selection,
		.Menu,
		.Roving,
		wrap = true,
		typeahead = true,
		name = name,
		focus_to = focus_to,
		scroll = {&m.data.scroll, view, 0, 0},
		key = u64(ui.id_mix(id, 2)),
	)
	return
}

// anchor_gesture reads how the anchor opened or steers an open menu this
// frame: a click opening it leaves focus where it is, Enter or Space
// opening it focuses the first item, ArrowDown or ArrowUp on the anchor
// of an open menu the first or last, Tab on it closes the menu
// (useMenuInitialFocus.ts:14-76, useMenuKeyboardNavigation.ts:28-113).
// An opening with no gesture on the anchor focuses the first item.
@(private)
anchor_gesture :: proc(gtx: ^ui.Ctx, open: ^bool, anchor: ops.Area_Id, was: bool) -> List_Focus_To {
	d := ui.widget_data(gtx, ui.id_mix(anchor, 0x3e9), Anchor_Memo)
	keyed, pressed := false, false
	to := List_Focus_To.None
	for e in ui.events(gtx, anchor) {
		#partial switch e.kind {
		case .Press, .Release:
			pressed = true
		case .Key:
			#partial switch e.key {
			case .Enter, .Space:
				keyed = true
			case .Down:
				to = .First
			case .Up:
				to = .Last
			case .Tab:
				if was {
					open^ = false
				}
			}
		}
	}
	if open^ && !d.open {
		switch {
		case keyed:
			return .First
		case pressed:
			return .None
		case to != .None:
			return to
		}
		return .First
	}
	if was && open^ {
		return to
	}
	return .None
}

// Anchor_Memo is whether the anchor's menu was open last frame, so an
// opening by the caller is told from one already shown.
@(private)
Anchor_Memo :: struct {
	open: bool,
}

// anchor_arrow is the item the arrow key on anchor this frame asks for.
@(private)
anchor_arrow :: proc(gtx: ^ui.Ctx, anchor: ops.Area_Id) -> List_Focus_To {
	for e in ui.events(gtx, anchor) {
		if e.kind == .Key && e.key == .Up {
			return .Last
		}
	}
	return .First
}

// action_menu_item declares a menu item: action_list_item's item, which
// closes the menu (and the menus above it) when chosen unless keep_open.
// submenu makes it open a submenu instead, flagged by submenu^: it
// shows a chevron-right, and choosing it or ArrowRight opens the
// submenu, which action_menu_submenu_open then draws. Returns true on
// the frame it is chosen.
action_menu_item :: proc(
	m: ^Action_Menu,
	label: string,
	description := "",
	description_variant := Description_Variant.Inline,
	leading := Icon.None,
	trailing := Icon.None,
	trailing_text := "",
	hint := "",
	variant := List_Item_Variant.Default,
	selected := false,
	disabled := false,
	inactive := "",
	loading := false,
	keep_open := false,
	submenu: ^bool = nil,
	state := Interaction.Live,
) -> bool {
	if !m.visible {
		return false
	}
	trail := trailing
	if submenu != nil && trail == .None && trailing_text == "" && hint == "" {
		trail = .Chevron_Right
	}
	index := m.list.n
	chosen := action_list_item(
		&m.list,
		label,
		description,
		description_variant,
		leading = leading,
		trailing = trail,
		trailing_text = trailing_text,
		hint = hint,
		variant = variant,
		selected = selected,
		disabled = disabled,
		inactive = inactive,
		loading = loading,
		expanded = submenu != nil ? Maybe(bool)(submenu^) : nil,
		state = state,
	)
	if submenu != nil {
		ref := Submenu_Ref{index = index, open = submenu}
		id := action_list_item_id(m.list.base, index)
		by_key := ui.focused(m.gtx) == id && ui.focus_visible(m.gtx)
		if m.list.key == .Right && m.list.keyed == index {
			submenu^ = true
			ref.focus_to = .First
		}
		if chosen {
			submenu^ = true
			ref.focus_to = by_key ? .First : .None
		}
		append(&m.subs, ref)
		return chosen
	}
	if chosen && !keep_open {
		m.chosen = true
	}
	return chosen
}

// action_menu_divider declares a divider between items.
action_menu_divider :: proc(m: ^Action_Menu) {
	if m.visible {
		action_list_divider(&m.list)
	}
}

// action_menu_group_open opens a group of items under heading, with
// selection overriding the menu's.
action_menu_group_open :: proc(m: ^Action_Menu, heading: string, variant := Group_Heading_Variant.Subtle, selection: Maybe(Selection_Variant) = nil) {
	if m.visible {
		action_list_group_open(&m.list, heading, variant, selection = selection)
	}
}

// action_menu_group_close closes the open group.
action_menu_group_close :: proc(m: ^Action_Menu) {
	if m.visible {
		action_list_group_close(&m.list)
	}
}

// action_menu_submenu_open draws the submenu that the item declared with
// submenu = open opens, to the right of that item (outside-right,
// ActionMenu/ActionMenu.tsx:204-251,357), while open^; call it after
// every item of parent and before action_menu_close(parent). It is a
// menu like any other; ArrowLeft in it closes it and returns focus to its
// item (useMenuKeyboardNavigation.ts:55-76).
action_menu_submenu_open :: proc(
	parent: ^Action_Menu,
	open: ^bool,
	selection := Selection_Variant.None,
	max_height := Overlay_Height.Auto,
	name := "",
	key: u64 = 0,
	loc := #caller_location,
) -> (m: Action_Menu) {
	if !parent.visible {
		// Closed with its parent: nothing hands focus back to its item.
		open^ = false
		return
	}
	action_list_close(&parent.list)
	ref: Submenu_Ref
	found := false
	for r in parent.subs {
		if r.open == open {
			ref, found = r, true
		}
	}
	if !found || ref.index >= len(parent.list.rows) {
		open^ = false
		return
	}
	row := parent.list.rows[ref.index]
	gtx := parent.gtx
	ops.transform_push(gtx.scene, ops.translate(row.rect.x, row.rect.y))
	m = menu_open(gtx, open, {row.id, {row.rect.w, row.rect.h}}, selection, .Outside_Right, .Start, .Auto, max_height, .Anchored, name != "" ? name : row.label, ref.focus_to, parent, key, loc)
	m.pushed = true
	return
}

// action_menu_close closes a menu opened by action_menu_open or
// action_menu_submenu_open: its list, then its overlay. A choice or Tab
// closes the menus above it too, and a closing menu closes its submenus.
action_menu_close :: proc(m: ^Action_Menu) {
	if m.visible {
		action_list_close(&m.list)
		l := &m.list
		switch {
		case l.key == .Tab && !m.narrow:
			m.chosen = true
		case l.key == .Left && m.parent != nil:
			m.open^ = false
		}
		if m.chosen {
			m.open^ = false
			for p := m.parent; p != nil; p = p.parent {
				p.chosen = true
				p.open^ = false
			}
		}
		if !m.open^ {
			for r in m.subs {
				r.open^ = false
			}
			// Focus goes back now, not as the overlay notices it closed
			// next frame, so it outranks the press that focused an item.
			if back := m.overlay.surface.look.data.return_to; back != 0 {
				ui.focus_request(m.gtx, back)
			}
		}
	}
	anchored_overlay_close(&m.overlay)
	if m.pushed {
		ops.transform_pop(m.gtx.scene)
		m.pushed = false
	}
}
