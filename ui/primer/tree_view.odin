package primer

import "core:fmt"
import "core:hash"
import "core:strings"
import "core:unicode/utf8"
import "jm:ui"
import "jm:ui/design"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// Tree_Sub_Tree is an item's sub-tree and, when it loads asynchronously,
// where it is (TreeView.SubTree's state). None is no sub-tree, unless the
// item has children, which read as Known.
Tree_Sub_Tree :: enum u8 {
	None,
	Known, // children given synchronously, possibly none
	Initial, // not asked for yet
	Loading,
	Done,
	Error,
}

// Tree_Action is one of an item's secondary actions: an invisible
// IconButton (a Button with a count) at the row's end, outside the tab
// order, also run by Shift+Cmd/Ctrl+U.
Tree_Action :: struct {
	label: string,
	icon:  Icon,
	count: string,
}

// Tree_Item is one item of a tree view and its sub-tree. id must be
// unique in the tree and stable across frames: expanded state, focus and
// hover follow it.
Tree_Item :: struct {
	id, label:        string,
	children:         []Tree_Item,
	sub_tree:         Tree_Sub_Tree,
	count:            int, // while loading: that many skeleton rows instead of a spinner
	current:          bool, // the current item; at most one
	expanded:         ^bool, // controlled: the tree writes it; nil keeps it in the tree
	default_expanded: bool,
	selectable:       bool, // onSelect: activation selects; only the chevron and arrows expand
	leading:          Icon,
	directory:        bool, // the leading visual is a folder that opens with the item
	trailing:         Icon,
	leading_label:    string, // what the leading visual means, for assistive technology
	trailing_label:   string,
	actions:          []Tree_Action,
	error:            string, // the ErrorDialog's message while sub_tree is Error; "" shows none
	error_title:      string, // its title, "Error" when empty
}

// Tree_Event_Kind is what happened in a tree view this frame.
Tree_Event_Kind :: enum u8 {
	None,
	Select, // an item with selectable was activated
	Expand, // an item opened: start loading its sub-tree here
	Collapse,
	Action, // a secondary action ran; Tree_Event.action is its index
	Retry, // the ErrorDialog's Retry
	Dismiss, // the ErrorDialog was dismissed; the item collapsed
}

// Tree_Event is the frame's event in a tree view and the item it was on.
Tree_Event :: struct {
	kind:   Tree_Event_Kind,
	id:     string,
	action: int,
}

// TREE_ROW is a row's height, 2rem: the CSS reaches it only through a
// 20.8px visual box, so a row with no visuals is 31.2px (tree-view.json
// gotchas); TREE_LINE that hard-coded 1.3rem line
// (TreeView.module.css:44-47,151-161,182-190).
TREE_ROW :: tok.BASE_SIZE_32
TREE_LINE :: f32(20.8)

// TREE_TOGGLE is the toggle column, 1rem, half of it the indent per
// level; TREE_CHEVRON the chevron inside it (TreeView.module.css:44-66,
// 128-140).
TREE_TOGGLE :: tok.BASE_SIZE_16
TREE_CHEVRON :: tok.BASE_SIZE_12

// TREE_INDICATOR is the current item's bar, 4x24px, 8px left of the row
// (TreeView.module.css:101-126).
TREE_INDICATOR :: ops.Size{tok.BASE_SIZE_4, tok.BASE_SIZE_24}

// TREE_TYPEAHEAD_RESET is how long type-ahead keeps what was typed, in
// seconds (useTypeahead.ts:78).
TREE_TYPEAHEAD_RESET :: 0.3

// TREE_SKELETON_WIDTHS are a skeleton row's text bar widths, cycling
// down the list (TreeView.module.css:268-287).
TREE_SKELETON_WIDTHS := [5]f32{0.67, 0.47, 0.73, 0.64, 0.50}

// Tree_Row_Kind is what a visible row is: an item, or the placeholder a
// loading or empty sub-tree shows.
@(private)
Tree_Row_Kind :: enum u8 {
	Item,
	Loading,
	Empty,
}

// Tree_Row is one visible row, in document order.
@(private)
Tree_Row :: struct {
	item:       ^Tree_Item, // the item, or the placeholder's parent
	key:        u64,
	kind:       Tree_Row_Kind,
	level:      int, // 1 at the top
	parent:     int, // the parent's row, -1 at the top
	has_sub:    bool, // draws a chevron
	expandable: bool, // reports expanded or collapsed (tree-view.json aria-expanded)
	expanded:   bool,
}

// Tree_Memo is what a tree keeps at its root between frames.
@(private)
Tree_Memo :: struct {
	focus:        u64, // the row that has, or last had, focus
	focus_id:     ops.Area_Id, // its area as last drawn
	ask:          u64, // a row to focus once drawn
	typed:        [64]u8,
	typed_n:      int,
	typed_at:     f64,
	said:         [160]u8, // the latest announcement
	said_n:       int,
	actions_open: bool,
	actions_of:   u64,
	hovered:      int, // rows under the pointer; the tree is hovered while any is
}

// Tree_Item_Memo is what a tree keeps per item id, drawn or not.
@(private)
Tree_Item_Memo :: struct {
	expanded, seeded: bool,
	last:             Tree_Sub_Tree,
	loading_focused:  bool,
	hovered:          bool,
}

// tree_key is an item id's row key.
@(private)
tree_key :: proc(id: string) -> u64 {
	return hash.fnv64a(transmute([]u8)id)
}

// tree_has_sub reports whether it has a sub-tree.
@(private)
tree_has_sub :: proc(it: ^Tree_Item) -> bool {
	return it.sub_tree != .None || len(it.children) > 0
}

// tree_empty reports whether it is known to have no children: a
// synchronous or done sub-tree with none.
@(private)
tree_empty :: proc(it: ^Tree_Item) -> bool {
	return (it.sub_tree == .Known || it.sub_tree == .Done || (it.sub_tree == .None && len(it.children) > 0)) && len(it.children) == 0
}

// tree_item_memo is it's memo under the tree root.
@(private)
tree_item_memo :: proc(gtx: ^ui.Ctx, root: ops.Area_Id, it: ^Tree_Item) -> ^Tree_Item_Memo {
	return ui.widget_data(gtx, ui.id_mix(root, tree_key(it.id)), Tree_Item_Memo)
}

// tree_is_expanded is its expanded state: the caller's when controlled,
// else the tree's, seeded once from default_expanded, then whether it is
// current (TreeView.tsx:279-288).
@(private)
tree_is_expanded :: proc(it: ^Tree_Item, m: ^Tree_Item_Memo) -> bool {
	if it.expanded != nil {
		return it.expanded^
	}
	if !m.seeded {
		m.seeded = true
		m.expanded = it.default_expanded || it.current
	}
	return m.expanded
}

// tree_set_expanded opens or closes it and says so in ev.
@(private)
tree_set_expanded :: proc(it: ^Tree_Item, m: ^Tree_Item_Memo, open: bool, ev: ^Tree_Event) {
	if it.expanded != nil {
		it.expanded^ = open
	}
	m.expanded, m.seeded = open, true
	ev^ = {open ? .Expand : .Collapse, it.id, 0}
}

// tree_touch keeps every item's memo alive, drawn or not, so an item
// under a collapsed one reopens as it was (TreeView.tsx:38-49,297-304),
// and announces each sub-tree's move into and out of loading
// (TreeView.tsx:554-594).
@(private)
tree_touch :: proc(gtx: ^ui.Ctx, root: ops.Area_Id, tm: ^Tree_Memo, items: []Tree_Item) {
	for &it in items {
		m := tree_item_memo(gtx, root, &it)
		open := tree_is_expanded(&it, m)
		if it.sub_tree != m.last {
			switch {
			case it.sub_tree == .Loading:
				tree_announce(tm, it.label, " content loading")
			case m.last == .Loading && it.sub_tree == .Done:
				tree_announce(tm, it.label, len(it.children) > 0 ? " content loaded" : " is empty")
				if m.loading_focused {
					m.loading_focused = false
					tm.ask = len(it.children) > 0 && open ? tree_key(it.children[0].id) : tree_key(it.id)
				}
			}
			m.last = it.sub_tree
		}
		tree_touch(gtx, root, tm, it.children)
	}
}

// tree_announce sets the tree's status text to name then what.
@(private)
tree_announce :: proc(tm: ^Tree_Memo, name, what: string) {
	tm.said_n = 0
	for s in ([]string{name, what}) {
		n := copy(tm.said[tm.said_n:], s)
		tm.said_n += n
	}
}

// tree_rows appends the visible rows under items at level, whose parent
// row is parent.
@(private)
tree_rows :: proc(gtx: ^ui.Ctx, root: ops.Area_Id, rows: ^[dynamic]Tree_Row, items: []Tree_Item, level, parent: int) {
	for &it in items {
		m := tree_item_memo(gtx, root, &it)
		has := tree_has_sub(&it)
		open := has && tree_is_expanded(&it, m)
		empty := tree_empty(&it)
		row := Tree_Row {
			item       = &it,
			key        = tree_key(it.id),
			level      = level,
			parent     = parent,
			has_sub    = has,
			expandable = has && !(empty && !open),
			expanded   = open,
		}
		append(rows, row)
		if !open {
			continue
		}
		me := len(rows) - 1
		if it.sub_tree == .Loading {
			append(rows, Tree_Row{item = &it, key = u64(ui.id_mix(ops.Area_Id(row.key), 1)), kind = .Loading, level = level + 1, parent = me})
			continue
		}
		tree_rows(gtx, root, rows, it.children, level + 1, me)
		if empty {
			append(rows, Tree_Row{item = &it, key = u64(ui.id_mix(ops.Area_Id(row.key), 2)), kind = .Empty, level = level + 1, parent = me})
		}
	}
}

// tree_find is the row with key, -1 when it is not visible.
@(private)
tree_find :: proc(rows: []Tree_Row, key: u64) -> int {
	for r, i in rows {
		if r.key == key {
			return i
		}
	}
	return -1
}

// tree_row_name is what a row is called: its item's label, or the
// placeholder's text.
@(private)
tree_row_name :: proc(gtx: ^ui.Ctx, r: Tree_Row) -> string {
	switch r.kind {
	case .Item:
		return r.item.label
	case .Loading:
		if r.item.count > 0 {
			return fmt.aprintf("Loading %d items", r.item.count, allocator = gtx.allocator)
		}
		return "Loading..."
	case .Empty:
		return "No items found"
	}
	return ""
}

// tree_view is Primer's TreeView (tree-view.json, TreeView.tsx,
// TreeView.module.css): a hierarchy of rows, one current, each 32px with
// a 16px toggle column of 12px chevrons, indented 8px per level, a
// leading visual, the label (one line with an ellipsis, or wrapped with
// truncate false) and a trailing visual 8px apart, then the item's
// secondary actions. Hover fills --control-transparent-bgColor-hover; the
// current item --control-transparent-bgColor-selected with a 4x24px
// --fgColor-accent bar 8px to its left, outside the tree's box. Keyboard
// focus rings the row inside with 2px of --fgColor-accent. Indentation
// lines show in --borderColor-muted while the pointer is over the tree or
// focus is in it. flat drops the indentation and toggle columns.
//
// The tree is one tab stop, entered at the current item, else the last
// focused, else the first. Up and Down move through visible rows, Home and
// End to the ends, Page Up and Down by page_height (the window's height
// when 0) over 32px rows; Right opens a closed item or enters an open
// one, Left closes an open one or goes to the parent, Backspace to the
// parent; Enter, Space or a click selects a selectable item, else toggles
// it; printable characters search labels from the focused row, the
// search clearing 300ms after the last; Shift+Cmd+U (Shift+Ctrl+U off
// Apple) runs an item's only secondary action or lists several in a
// "Supplemental actions" dialog. A loading sub-tree shows a spinner row,
// or count skeleton rows; a known or done empty one "No items found";
// moves into and out of loading are announced through a status node; an
// expanded sub-tree in Error with an error message shows the ErrorDialog,
// Retry and Dismiss reported as events, Dismiss collapsing the item.
//
// Departures: the leading-action slot is not offered; the coarse-pointer
// sizes are not drawn, as jm:ui has no pointer density; the focused row is
// not scrolled into view and Page Up/Down use page_height, not the nearest
// scroll container's, as jm:ui has no scroll-into-view; the item's name is
// its label alone, the shortcut going in its description, so type-ahead
// finds items with secondary actions (the web's two-id aria-labelledby
// leaves them nameless, tree-view.json upstream bugs); the toggle's own
// hover fill is drawn only where the toggle is its own target (a
// selectable item), with rounded left corners only at level 1, as the
// CSS's guard intended (the second upstream bug); the actions dialog lists
// its actions as invisible buttons, not an ActionList; the path to the
// current item is not opened, only the item itself, as the code (not the
// docs) does (tree-view.json contradiction); the action buttons are
// announced although the web hides them.
tree_view :: proc(
	gtx: ^ui.Ctx,
	items: []Tree_Item,
	label: string,
	flat := false,
	truncate := true,
	page_height: f32 = 0,
	key: u64 = 0,
	loc := #caller_location,
) -> (ev: Tree_Event) {
	root := ui.claim_id(gtx, key, loc)
	tm := ui.widget_data(gtx, root, Tree_Memo)
	tree_touch(gtx, root, tm, items)
	rows := make([dynamic]Tree_Row, gtx.allocator)
	tree_rows(gtx, root, &rows, items, 1, -1)
	tree_handle_keys(gtx, root, tm, rows[:], page_height, &ev)
	clear(&rows)
	tree_rows(gtx, root, &rows, items, 1, -1)
	if tree_find(rows[:], tm.focus) < 0 && len(rows) > 0 {
		tm.focus = 0
	}
	inside := tm.focus_id != 0 && ui.focused(gtx) == tm.focus_id
	stop := tree_tab_stop(rows[:], tm, inside)
	col := ui.column_open(gtx, align = .Fill, key = u64(ui.id_mix(root, 1)))
	ui.container_semantics(gtx, {role = .Tree, label = ui.frame_string(gtx, label)})
	shown := Tree_Look{tm.hovered > 0 || inside, flat, truncate}
	tm.hovered = 0
	for r, i in rows {
		sc := ui.scope_open(gtx, r.key)
		tree_row(gtx, root, tm, rows[:], i, i == stop, shown, &ev)
		ui.scope_close(&sc)
	}
	tree_status(gtx, tm, root)
	ui.close(&col)
	tree_dialogs(gtx, root, tm, rows[:], &ev)
	return
}

// Tree_Look is how every row of a tree draws this frame.
@(private)
Tree_Look :: struct {
	lines, flat, truncate: bool,
}

// tree_tab_stop is the row that takes keys: the focused one while focus
// is in the tree, else the current item, else the last focused, else the
// first (useRovingTabIndex.ts:17-71).
@(private)
tree_tab_stop :: proc(rows: []Tree_Row, tm: ^Tree_Memo, inside: bool) -> int {
	if len(rows) == 0 {
		return -1
	}
	if inside {
		if i := tree_find(rows, tm.focus); i >= 0 {
			return i
		}
	}
	for r, i in rows {
		if r.kind == .Item && r.item.current {
			return i
		}
	}
	if i := tree_find(rows, tm.focus); i >= 0 {
		return i
	}
	return 0
}

// tree_handle_keys runs the keys the focused row received: movement, opening
// and closing, type-ahead and the secondary-action shortcut. Enter and
// Space are a row's activation, read with its clicks.
@(private)
tree_handle_keys :: proc(gtx: ^ui.Ctx, root: ops.Area_Id, tm: ^Tree_Memo, rows: []Tree_Row, page_height: f32, ev: ^Tree_Event) {
	if tm.focus_id == 0 {
		return
	}
	at := tree_find(rows, tm.focus)
	if at < 0 {
		return
	}
	shortcut := PLATFORM == .Apple ? ui.Mods{.Shift, .Super} : ui.Mods{.Shift, .Ctrl}
	for e in ui.events(gtx, tm.focus_id) {
		#partial switch e.kind {
		case .Key:
			r := rows[at]
			to := at
			plain := e.mods & {.Alt, .Super} == {}
			#partial switch e.key {
			case .Down:
				to = min(at + 1, len(rows) - 1)
			case .Up:
				to = max(at - 1, 0)
			case .Home:
				to = 0
			case .End:
				to = len(rows) - 1
			case .Page_Down, .Page_Up:
				view := page_height > 0 ? page_height : gtx.viewport.y
				page := max(int(view / TREE_ROW), 1)
				to = e.key == .Page_Down ? min(at + page, len(rows) - 1) : max(at - page, 0)
			case .Backspace:
				to = r.parent >= 0 ? r.parent : at
			case .Right, .Left:
				if plain {
					to = tree_step_sideways(gtx, root, rows, at, e.key == .Right, ev)
				}
			case .U:
				if e.mods == shortcut && r.kind == .Item {
					tree_run_actions(tm, r, ev)
				}
			}
			if to != at {
				tm.focus, tm.ask = rows[to].key, rows[to].key
				at = to
			}
		case .Text:
			if to := tree_typeahead(gtx, tm, rows, at, e.text); to >= 0 && to != at {
				tm.focus, tm.ask = rows[to].key, rows[to].key
				at = to
			}
		}
	}
}

// tree_step_sideways is Right (open) or Left on row at: Right opens a closed
// item or enters an open one; Left closes an open item or goes to the
// parent (useRovingTabIndex.ts:83-106). It is the row focus moves to.
@(private)
tree_step_sideways :: proc(gtx: ^ui.Ctx, root: ops.Area_Id, rows: []Tree_Row, at: int, open: bool, ev: ^Tree_Event) -> int {
	r := rows[at]
	item := r.kind == .Item && r.expandable
	switch {
	case open && item && !r.expanded:
		tree_set_expanded(r.item, tree_item_memo(gtx, root, r.item), true, ev)
	case open && item && at + 1 < len(rows) && rows[at + 1].parent == at:
		return at + 1
	case !open && item && r.expanded:
		tree_set_expanded(r.item, tree_item_memo(gtx, root, r.item), false, ev)
	case !open && r.parent >= 0:
		return r.parent
	}
	return at
}

// tree_run_actions runs a row's only secondary action, or opens the
// dialog that lists several (TreeView.tsx:315-327).
@(private)
tree_run_actions :: proc(tm: ^Tree_Memo, r: Tree_Row, ev: ^Tree_Event) {
	switch len(r.item.actions) {
	case 0:
	case 1:
		ev^ = {.Action, r.item.id, 0}
	case:
		tm.actions_open, tm.actions_of = true, r.key
	}
}

// tree_typeahead adds text to the search, unless it is a space, and is
// the first row from at, wrapping, whose name starts with the search,
// ignoring case; a one-character search starts after at, so a repeated
// letter cycles (useTypeahead.ts:24-98). -1 for no match.
@(private)
tree_typeahead :: proc(gtx: ^ui.Ctx, tm: ^Tree_Memo, rows: []Tree_Row, at: int, text: string) -> int {
	if text == "" || text == " " {
		return -1
	}
	if gtx.time - tm.typed_at > TREE_TYPEAHEAD_RESET {
		tm.typed_n = 0
	}
	tm.typed_at = gtx.time
	if tm.typed_n + len(text) > len(tm.typed) {
		return -1
	}
	tm.typed_n += copy(tm.typed[tm.typed_n:], text)
	search := strings.to_lower(string(tm.typed[:tm.typed_n]), gtx.allocator)
	n := len(rows)
	first := utf8.rune_count(search) == 1 ? 1 : 0
	for k in first ..< n {
		i := (at + k) % n
		if strings.has_prefix(strings.to_lower(tree_row_name(gtx, rows[i]), gtx.allocator), search) {
			return i
		}
	}
	return -1
}

// tree_row draws row i, reporting its activation and its actions in ev.
@(private)
tree_row :: proc(gtx: ^ui.Ctx, root: ops.Area_Id, tm: ^Tree_Memo, rows: []Tree_Row, i: int, stop: bool, shown: Tree_Look, ev: ^Tree_Event) {
	r := rows[i]
	actions := r.kind == .Item ? r.item.actions : nil
	if len(actions) == 0 {
		tree_row_widget(gtx, root, tm, r, i, stop, shown, 0, ev)
		return
	}
	aw: f32
	for a in actions {
		aw += tree_action_width(gtx, a)
	}
	s := ui.stack_open(gtx)
	defer ui.close(&s)
	tree_row_widget(gtx, root, tm, r, i, stop, shown, aw, ev)
	row := ui.row_open(gtx, align = .Center)
	defer ui.close(&row)
	ui.fill_space(gtx)
	for a, k in actions {
		hit: bool
		if a.count != "" {
			hit = button(gtx, "", .Invisible, leading = a.icon, count = a.count, name = a.label, tab_stop = false, key = u64(k + 1))
		} else {
			hit = icon_button_in(gtx, a.icon, a.label, .Invisible, .Medium, tree_action_roles(), {no_tab = true}, u64(k + 1), #location())
		}
		if hit {
			ev^ = {.Action, r.item.id, k}
		}
	}
}

// tree_action_roles is an invisible icon button's roles with its rest
// icon colour in every state, as icon_button sets them.
@(private)
tree_action_roles :: proc() -> Button_Roles {
	r := variant_roles(.Invisible)
	rest := tok.Role.Button_Invisible_Icon_Color_Rest
	r.visual = {rest, rest, rest, .Button_Invisible_Fg_Color_Disabled}
	return r
}

// tree_action_width is a secondary action's button width: a 32px
// IconButton, or an invisible Button of its icon and count.
@(private)
tree_action_width :: proc(gtx: ^ui.Ctx, a: Tree_Action) -> f32 {
	mt := button_metrics(.Medium)
	if a.count == "" {
		return mt.height
	}
	cst := counter_style()
	pill := counter_size(design.shape_style(gtx, a.count, cst, font_for(gtx, cst.weight)))
	return 2 * mt.pad + BUTTON_ICON + mt.gap + pill.x
}

// tree_row_widget is a row's own box: fill, bar, lines, chevron, visuals
// and label, its input and its semantics; aw is the width its actions
// take at its end.
@(private)
tree_row_widget :: proc(gtx: ^ui.Ctx, root: ops.Area_Id, tm: ^Tree_Memo, r: Tree_Row, i: int, stop: bool, shown: Tree_Look, aw: f32, ev: ^Tree_Event) {
	p := ui.widget_open(gtx, r.key)
	w := ui.is_finite(gtx.constraints.max.x) ? gtx.constraints.max.x : 240
	indent := shown.flat ? 0 : f32(r.level - 1) * TREE_TOGGLE / 2
	content_x := indent + (shown.flat ? 0 : TREE_TOGGLE)
	pad := tok.BASE_SIZE_8
	st := style(.Body_Medium)
	name := tree_row_name(gtx, r)
	lead, trail := tree_visuals(r)
	text_x := content_x + pad + (lead != .None || r.kind == .Loading && r.item.count == 0 ? BUTTON_ICON + tok.STACK_GAP_CONDENSED : 0)
	text_r := w - aw - pad - (trail != .None ? BUTTON_ICON + tok.STACK_GAP_CONDENSED : 0)
	para := design.layout_style(gtx, name, st, font_for(gtx, st.weight), max(text_r - text_x, 1), max_lines = shown.truncate ? 1 : 0)
	top := (TREE_ROW - TREE_LINE) / 2
	h := TREE_ROW
	if len(para.lines) > 1 {
		h = max(TREE_ROW, 2 * top + para.height)
	}
	if r.kind == .Loading && r.item.count > 0 {
		h = f32(r.item.count) * TREE_ROW
	}
	area := ops.Rect{0, 0, w, h}
	c := control(gtx, p.id, area, .Live)
	m := r.kind == .Item ? tree_item_memo(gtx, root, r.item) : nil
	hover := ui.id_mix(p.id, 3)
	for e in ui.events(gtx, hover) {
		#partial switch e.kind {
		case .Enter:
			c.st.hovered = true
		case .Leave:
			c.st.hovered = false
		}
	}
	if c.st.hovered {
		tm.hovered += 1
	}
	if c.press {
		tm.focus, tm.ask = r.key, r.key
	}
	for e in ui.events(gtx, p.id) {
		switch {
		case e.kind == .Focus && tm.ask == 0:
			tm.focus = r.key // Tab brought focus here
		case e.kind == .Release && e.button == .Middle && m != nil && r.item.selectable:
			ev^ = {.Select, r.item.id, 0}
		}
	}
	if tm.ask == r.key {
		ui.focus_request(gtx, p.id)
		tm.ask = 0
	}
	if tm.focus == r.key {
		tm.focus_id = p.id
	}
	if r.kind == .Loading && m == nil {
		pm := tree_item_memo(gtx, root, r.item)
		if c.focused {
			pm.loading_focused = true
		}
	}
	toggle := ops.Rect{indent, 0, TREE_TOGGLE, h}
	chevron := ui.id_mix(p.id, 4)
	ct := control(gtx, chevron, toggle, .Live)
	if m != nil && c.clicked {
		if r.item.selectable {
			ev^ = {.Select, r.item.id, 0}
		} else if r.has_sub {
			tree_set_expanded(r.item, m, !r.expanded, ev)
		}
	}
	if m != nil && ct.clicked && r.item.selectable && r.has_sub {
		tree_set_expanded(r.item, m, !r.expanded, ev)
	}
	paint := Tree_Row_Paint{r, area, indent, content_x, text_x, text_r, top, para, lead, trail, c.st.hovered, shown}
	paint_tree_row(gtx, paint, c, ct)
	// Every row hears focus; only the tab stop wants keys, so Tab
	// visits the tree once (a roving tabindex).
	kinds := ops.Event_Kinds{.Press, .Release, .Enter, .Leave, .Move, .Focus, .Blur}
	if stop {
		kinds += {.Key, .Text}
	}
	ops.input_area(gtx.scene, p.id, area, kinds, r.kind == .Loading ? .Default : .Pointer)
	ops.observer_area(gtx.scene, hover, area)
	if m != nil && r.item.selectable && r.has_sub && !shown.flat {
		ops.input_area(gtx.scene, chevron, toggle, design.CLICK_KINDS - {.Key, .Focus, .Blur}, .Pointer)
	}
	said := ui.frame_string(gtx, name)
	ops.tag(gtx.scene, p.id, said, area)
	ui.semantics(gtx, &p, {role = .Tree_Item, label = said, description = tree_description(gtx, r), level = u8(min(r.level, 255)), states = tree_states(r, c.focused)})
	ui.widget_close(gtx, &p, {{w, h}, top + (len(para.lines) > 0 ? para.lines[0].baseline : 0)})
}

// tree_visuals is a row's leading and trailing icons: a directory's
// folder, open while expanded.
@(private)
tree_visuals :: proc(r: Tree_Row) -> (lead, trail: Icon) {
	if r.kind != .Item {
		return
	}
	lead, trail = r.item.leading, r.item.trailing
	if r.item.directory {
		lead = r.expanded ? .File_Directory_Open_Fill : .File_Directory_Fill
	}
	return
}

// tree_states is a row's semantic states: expanded or collapsed when it
// reports either, current, and selected while focused (tree-view.json
// semantics).
@(private)
tree_states :: proc(r: Tree_Row, focused: bool) -> (s: ops.States) {
	if r.expandable {
		s += {.Expandable}
		if r.expanded {
			s += {.Expanded}
		}
	}
	if r.kind == .Item && r.item.current {
		s += {.Current}
	}
	if focused {
		s += {.Selected}
	}
	if r.kind == .Loading {
		s += {.Busy}
	}
	return
}

// tree_description is what a row's visuals mean and, with secondary
// actions, the shortcut that runs them.
@(private)
tree_description :: proc(gtx: ^ui.Ctx, r: Tree_Row) -> string {
	if r.kind != .Item {
		return ""
	}
	parts := make([dynamic]string, gtx.allocator)
	if r.item.leading_label != "" {
		append(&parts, r.item.leading_label)
	}
	if r.item.trailing_label != "" {
		append(&parts, r.item.trailing_label)
	}
	if len(r.item.actions) > 0 {
		append(&parts, PLATFORM == .Apple ? "Press (Shift+Command+U) for more actions." : "Press (Shift+Control+U) for more actions.")
	}
	return strings.join(parts[:], ", ", gtx.allocator)
}

// Tree_Row_Paint is a row's measured layout.
@(private)
Tree_Row_Paint :: struct {
	r:                                       Tree_Row,
	area:                                    ops.Rect,
	indent, content_x, text_x, text_r, top: f32,
	para:                                    ui.Paragraph,
	lead, trail:                             Icon,
	hovered:                                 bool,
	shown:                                   Tree_Look,
}

// paint_tree_row draws a row: fill, the current bar, indentation lines,
// toggle, visuals, label and focus ring (TreeView.module.css).
@(private)
paint_tree_row :: proc(gtx: ^ui.Ctx, tp: Tree_Row_Paint, c, ct: Control) {
	r, area := tp.r, tp.area
	rr := ops.Round_Rect{area, tok.BORDER_RADIUS_MEDIUM}
	current := r.kind == .Item && r.item.current
	switch {
	case current:
		ops.fill(gtx.scene, rr, color(.Control_Transparent_Bg_Color_Selected))
		bar := ops.Rect{-tok.BASE_SIZE_8, area.h / 2 - tok.BASE_SIZE_12, TREE_INDICATOR.x, TREE_INDICATOR.y}
		ops.fill(gtx.scene, ops.Round_Rect{bar, radius(tok.BORDER_RADIUS_MEDIUM, bar)}, color(.Fg_Color_Accent))
	case tp.hovered && r.kind != .Loading:
		ops.fill(gtx.scene, rr, color(.Control_Transparent_Bg_Color_Hover))
	}
	if !tp.shown.flat {
		if tp.shown.lines {
			for l in 1 ..< r.level {
				x := f32(l) * TREE_TOGGLE / 2 - tok.BORDER_WIDTH_THIN
				ops.fill(gtx.scene, ops.Rect{x, 0, tok.BORDER_WIDTH_THIN, area.h}, color(.Border_Color_Muted))
			}
		}
		if r.has_sub {
			if ct.hovered && r.item.selectable {
				left := r.level == 1 ? tok.BORDER_RADIUS_MEDIUM : 0
				cell := ops.Rect{tp.indent, 0, TREE_TOGGLE, area.h}
				ops.fill(gtx.scene, rounded(gtx, cell, {left, 0, 0, left}), color(.Control_Transparent_Bg_Color_Hover))
			}
			chev := r.expanded ? Icon.Chevron_Down : Icon.Chevron_Right
			icon(gtx, chev, {tp.indent + (TREE_TOGGLE - TREE_CHEVRON) / 2, TREE_ROW / 2 - TREE_CHEVRON / 2}, TREE_CHEVRON, color(.Fg_Color_Muted))
		}
	}
	x := tp.content_x + tok.BASE_SIZE_8
	vis_y := tp.top + (TREE_LINE - BUTTON_ICON) / 2
	muted := color(.Fg_Color_Muted)
	switch r.kind {
	case .Loading:
		if r.item.count > 0 {
			paint_tree_skeletons(gtx, x, tp.text_r, r.item.count)
		} else {
			paint_spinner(gtx, {x, vis_y}, BUTTON_ICON, color(.Fg_Color_Accent))
			draw_tree_label(gtx, tp, muted)
		}
	case .Empty:
		draw_tree_label(gtx, tp, muted)
	case .Item:
		if tp.lead != .None {
			lc := r.item.directory ? color(.Tree_View_Item_Leading_Visual_Icon_Color_Rest) : muted
			icon(gtx, tp.lead, {x, vis_y}, BUTTON_ICON, lc)
		}
		draw_tree_label(gtx, tp, color(.Fg_Color_Default))
		if tp.trail != .None {
			icon(gtx, tp.trail, {tp.text_r + tok.STACK_GAP_CONDENSED, vis_y}, BUTTON_ICON, muted)
		}
	}
	if c.focus_visible {
		design.paint_inset_shadow(gtx, rr, {spread = tok.BORDER_WIDTH_THICK, color = color(.Fg_Color_Accent)})
	}
}

// draw_tree_label draws a row's label on its first line box, centred
// in a one-line row.
@(private)
draw_tree_label :: proc(gtx: ^ui.Ctx, tp: Tree_Row_Paint, ink: ops.Color) {
	y := tp.top + (TREE_LINE - tp.para.pitch) / 2
	if len(tp.para.lines) <= 1 {
		y = (TREE_ROW - tp.para.height) / 2
	}
	design.draw_paragraph(gtx, tp.para, {tp.text_x, y}, ink)
}

// paint_tree_skeletons draws n skeleton rows from x: a 16px square and
// a text bar 8px after it, its width cycling (TreeView.module.css
// :258-291).
@(private)
paint_tree_skeletons :: proc(gtx: ^ui.Ctx, x, right: f32, n: int) {
	c := color(.Skeleton_Loader_Bg_Color)
	st := style(.Body_Medium)
	for k in 0 ..< n {
		y := f32(k) * TREE_ROW
		sq := ops.Rect{x, y + (TREE_ROW - BUTTON_ICON) / 2, BUTTON_ICON, BUTTON_ICON}
		paint_shimmer(gtx, ops.Round_Rect{sq, avatar_radius(BUTTON_ICON, true)}, sq, c)
		bx := x + BUTTON_ICON + tok.BASE_SIZE_8
		bar := ops.Rect{bx, y + (TREE_ROW - st.size) / 2, max(right - bx, 0) * TREE_SKELETON_WIDTHS[k % len(TREE_SKELETON_WIDTHS)], st.size}
		paint_shimmer(gtx, ops.Round_Rect{bar, radius(tok.BORDER_RADIUS_SMALL, bar)}, bar, c)
	}
}

// tree_status is the tree's live region: a status node holding the
// latest announcement.
@(private)
tree_status :: proc(gtx: ^ui.Ctx, tm: ^Tree_Memo, root: ops.Area_Id) {
	p := ui.widget_open(gtx, u64(ui.id_mix(root, 2)))
	ui.semantics(gtx, &p, {role = .Status, label = ui.frame_string(gtx, string(tm.said[:tm.said_n]))})
	ui.widget_close(gtx, &p, {})
}

// tree_dialogs draws the Supplemental actions dialog and every visible
// item's ErrorDialog.
@(private)
tree_dialogs :: proc(gtx: ^ui.Ctx, root: ops.Area_Id, tm: ^Tree_Memo, rows: []Tree_Row, ev: ^Tree_Event) {
	if tm.actions_open {
		at := tree_find(rows, tm.actions_of)
		if at < 0 {
			tm.actions_open = false
		}
		dl := dialog_open(gtx, &tm.actions_open, "Supplemental actions", key = u64(ui.id_mix(root, 5)))
		if dl.visible && at >= 0 {
			col := ui.column_open(gtx, align = .Fill)
			for a, k in rows[at].item.actions {
				if button(gtx, a.label, .Invisible, leading = a.icon, count = a.count, block = true, align = .Start, key = u64(k + 1)) {
					ev^ = {.Action, rows[at].item.id, k}
					dialog_dismiss(&dl, .Close_Button)
				}
			}
			ui.close(&col)
		}
		dialog_close(&dl)
	}
	for r in rows {
		if r.kind != .Item || !r.expanded || r.item.sub_tree != .Error || r.item.error == "" {
			continue
		}
		open := true
		title := r.item.error_title != "" ? r.item.error_title : "Error"
		switch confirmation_dialog(gtx, &open, title, r.item.error, cancel_content = "Dismiss", confirm_content = "Retry", key = r.key) {
		case .Confirm:
			ev^ = {.Retry, r.item.id, 0}
		case .Cancel, .Close_Button, .Escape:
			tree_set_expanded(r.item, tree_item_memo(gtx, root, r.item), false, ev)
			ev^ = {.Dismiss, r.item.id, 0}
		case .None:
		}
	}
}
