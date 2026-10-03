package primer

import "core:strings"
import "core:unicode"
import "core:unicode/utf8"
import "jm:ui"
import "jm:ui/design"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// ActionList (primer-kit components/action-list.json, ActionList.module.css
// at the kit's release, cited as ActionList.module.css:lines): a vertical
// list of rows, each an action, a link or a selectable option. ActionMenu,
// SelectPanel and Autocomplete fill one and give it their own role and
// focus model.
//
// A list is one widget whose items are its parts. action_list_item and
// the other declarations record what each row is; action_list_close lays
// the rows out once it knows them all, at the width of the widest when
// its container lets it hug (an overlay) and at the width offered
// otherwise, paints them and declares their semantics. So an item's
// activation is read against the box it had last frame, and only rows
// that Primer's slots allow can go in a list: text, octicons, a
// keybinding hint, a spinner.
//
// Focus is one of three models (List_Focus): every item its own tab
// stop (a plain list of buttons); a roving tab stop that arrow keys move
// (a menu or listbox: @primer/behaviors' focus-zone); or none, where the
// owner keeps focus in a text field and the list draws the item it names
// as the active descendant (SelectPanel, Autocomplete).

// Action_List_Variant is how the list sits in its container: Inset pads
// it 8px top and bottom and each item 8px from the sides, so hover fills
// are tiles inside the surface; Horizontal_Inset keeps the sides and pads
// only the bottom; Full lays rows flush (ActionList.module.css:14-27).
Action_List_Variant :: enum u8 {
	Inset,
	Horizontal_Inset,
	Full,
}

// Selection_Variant adds a leading selection column: a checkmark
// (Single), a radio (Radio) or a checkbox (Multiple; a checkmark in a
// menu). None makes items actions, not options.
Selection_Variant :: enum u8 {
	None,
	Single,
	Radio,
	Multiple,
}

// List_Role is the list's role to assistive technology, which sets its
// items': buttons or links in a List, options in a Listbox, menu items
// (checkable by the selection) in a Menu.
List_Role :: enum u8 {
	List,
	Listbox,
	Menu,
}

// List_Focus is how keyboard focus moves among the items (see the file
// comment).
List_Focus :: enum u8 {
	Tab,
	Roving,
	Descendant,
}

// List_Focus_To asks a roving list to move focus to its first or last
// item at close: a menu opened by a key.
List_Focus_To :: enum u8 {
	None,
	First,
	Last,
}

// List_Item_Variant is an item's intent: Danger colours the label,
// leading visual and selection red and fills red on hover.
List_Item_Variant :: enum u8 {
	Default,
	Danger,
}

// List_Item_Size is a one-line row's height: 32 or 40px.
List_Item_Size :: enum u8 {
	Medium,
	Large,
}

// Description_Variant sets a description beside the label on its
// baseline (Inline) or on its own line under it (Block).
Description_Variant :: enum u8 {
	Inline,
	Block,
}

// Group_Heading_Variant is a group heading's look: muted text alone, or
// on a muted band between two rules.
Group_Heading_Variant :: enum u8 {
	Subtle,
	Filled,
}

// List_Scroll is the scroll box a list sits in, for keeping the focused
// or highlighted item in view: its offset, its visible height, where the
// list's top is in its content, and the margin to keep below the item
// (8px for SelectPanel and Autocomplete, FilteredActionList.tsx:27; 0,
// the browser's own scroll on focus(), for a menu).
List_Scroll :: struct {
	offset:     ^ui.Scroll_Offset,
	view:       f32,
	top:        f32,
	end_margin: f32,
}

// The list's hard-coded measures (action-list.json notes hard-coded):
// the 20px label and visual line, the 16px description and warning line,
// the 18px group heading line, 8px per nesting level, and the 7px a
// divider sits above an item's text.
LIST_LINE :: tok.BASE_SIZE_20
LIST_SMALL_LINE :: tok.BASE_SIZE_16
LIST_GROUP_LINE :: f32(18)
LIST_DEPTH_STEP :: tok.BASE_SIZE_8
LIST_DIVIDER_ABOVE :: f32(7)
LIST_VISUAL :: f32(16)

// WRAP_SLACK is added to a width text wraps at, so text measured at its
// natural width does not wrap from rounding.
@(private)
WRAP_SLACK :: f32(0.01)

// LOADING_SUFFIX is what a loading item's name ends in (ActionList/Item.tsx
// :368-370, a visually hidden "Loading").
LOADING_SUFFIX :: "Loading"

// Action_List is an open list between action_list_open and
// action_list_close. After the close, rows holds every item's id and box
// and the result fields what the frame did.
Action_List :: struct {
	gtx:        ^ui.Ctx,
	p:          ui.Placement,
	base:       ops.Area_Id, // items are id_mix(base, index + 1)
	cs:         ui.Constraints,
	o:          List_Opts,
	data:       ^List_Data,
	entries:    [dynamic]List_Entry,
	n:          int, // items so far
	sel:        Selection_Variant, // the selection in force: the open group's, else the list's
	in_group:   bool,
	move:       List_Move,
	// What the frame did.
	hovered:    int, // Descendant: the item the pointer moved onto, -1
	activated:  int, // the item activated, -1
	key:        ui.Key, // a key the focused item heard that the list leaves to its owner (Left, Right, Tab), else None
	mods:       ui.Mods,
	keyed:      int, // the item that heard key
	moved:      bool, // the keyboard moved focus or the highlight
	rows:       []List_Row, // after close
	closed:     bool,
}

// List_Row is an item as laid out: its id, its box in the list's space,
// its label and whether it is disabled.
List_Row :: struct {
	id:       ops.Area_Id,
	rect:     ops.Rect,
	label:    string,
	disabled: bool,
}

@(private)
List_Opts :: struct {
	variant:       Action_List_Variant,
	selection:     Selection_Variant,
	role:          List_Role,
	focus:         List_Focus,
	wrap:          bool,
	dividers:      bool,
	typeahead:     bool,
	heading:       string,
	heading_level: int,
	name:          string,
	active:        int,
	activate:      bool,
	follow:        bool,
	focus_to:      List_Focus_To,
	scroll:        List_Scroll,
}

// List_Data is what a list keeps between frames: the item holding a
// roving list's tab stop.
@(private)
List_Data :: struct {
	focus: int,
}

// List_Move is a keyboard move a focused item asked for, resolved at
// close once the list knows its items.
@(private)
List_Move :: struct {
	to:     List_Move_To,
	from:   int,
	letter: rune,
}

@(private)
List_Move_To :: enum u8 {
	None,
	Next,
	Previous,
	First,
	Last,
	Letter,
}

@(private)
List_Entry_Kind :: enum u8 {
	Item,
	Divider,
	Group_Open,
	Group_Close,
}

@(private)
List_Entry :: struct {
	kind:  List_Entry_Kind,
	item:  List_Item,
	group: List_Group,
}

// List_Item is one declared item and its state this frame.
@(private)
List_Item :: struct {
	label, description, trailing_text, hint, inactive, action_name: string,
	desc_variant:                                                   Description_Variant,
	truncate:                                                       bool,
	leading, trailing, action:                                      Icon,
	variant:                                                        List_Item_Variant,
	size:                                                           List_Item_Size,
	selected, active, disabled, loading, link:                      bool,
	expanded:                                                       Maybe(bool),
	depth:                                                          int,
	selection:                                                      Selection_Variant,
	index:                                                          int,
	id, group:                                                      ops.Area_Id,
	c, ac:                                                          Control,
}

@(private)
List_Group :: struct {
	heading, auxiliary: string,
	variant:            Group_Heading_Variant,
	id:                 ops.Area_Id,
}

// Item_Memo is an item's boxes as last laid out, which this frame's
// events are read against.
@(private)
Item_Memo :: struct {
	rect, action: ops.Rect,
}

@(private)
ITEM_MEMO :: 0x11e
@(private)
ITEM_ACTION :: 0xac7
@(private)
ITEM_INACTIVE :: 0x1a7

// action_list_open opens a list (action-list.json). variant insets it;
// selection adds the selection column to every item (a group may
// override it); role is what it is to a reader; focus how the keyboard
// moves among its items, wrapping past the ends when wrap (a menu, a
// SelectPanel), stopping otherwise. dividers draws a rule above each
// item's text but the first's (showDividers). heading labels the list
// with a heading at heading_level, 8px above it and lined up with the
// item text; name labels it when there is none. typeahead lets a letter
// or digit move a roving list's focus to the next item starting with it
// (useMnemonics.ts:33-80). The Descendant model reads active, the item
// the owner highlights, activate, to activate it this frame (the owner's
// Enter), and follow, to scroll it into view; focus_to moves a roving
// list's focus to its first or last item; scroll is the box to keep the
// moved item in. id_base, when set, is what item ids derive from, so an
// owner can name an item before the list is drawn.
//
// Departures: the item gap behind the primer_react_action_list_item_gap
// flag is not drawn; a trailing action is an icon button, not a text
// button or a link; tablist is not a role; a sub-item's 33ms content
// fill transition is instant, as every other fill is.
action_list_open :: proc(
	gtx: ^ui.Ctx,
	variant := Action_List_Variant.Inset,
	selection := Selection_Variant.None,
	role := List_Role.List,
	focus := List_Focus.Tab,
	wrap := false,
	dividers := false,
	typeahead := false,
	heading := "",
	heading_level := 2,
	name := "",
	active := -1,
	activate := false,
	follow := false,
	focus_to := List_Focus_To.None,
	scroll := List_Scroll{},
	id_base: ops.Area_Id = 0,
	key: u64 = 0,
	loc := #caller_location,
) -> (l: Action_List) {
	l.gtx = gtx
	l.p = ui.widget_open(gtx, key, loc)
	l.cs = gtx.constraints
	l.base = id_base if id_base != 0 else l.p.id
	l.o = {variant, selection, role, focus, wrap, dividers, typeahead, heading, heading_level, name, active, activate, follow, focus_to, scroll}
	l.data = ui.widget_data(gtx, l.p.id, List_Data)
	l.entries = make([dynamic]List_Entry, gtx.allocator)
	l.sel = selection
	l.hovered, l.activated, l.keyed = -1, -1, -1
	return
}

// action_list_item_id is the id of l's item at index, for an owner that
// points at it (an active descendant) or moves focus to it.
action_list_item_id :: proc(base: ops.Area_Id, index: int) -> ops.Area_Id {
	return ui.id_mix(base, u64(index + 1))
}

// action_list_item declares the next item (action-list.json inputs
// item*). label wraps by word; description sits beside it (Inline) or
// under it (Block), in small muted type, cut to one line with an
// ellipsis and shown whole in a tooltip when truncate and it is cut.
// leading is a 16px octicon before the text; trailing an octicon,
// trailing_text short text, or hint a keybinding hint after it, read as
// part of the name. variant, size, selected (with a selection in force),
// active (the current item: selected fill, semibold label, accent bar),
// disabled, inactive (the reason it is unavailable: an alert icon with
// the reason as a tooltip in a plain list, the reason under the label in
// a menu or listbox), loading (a spinner in a visual's place) and link
// (a link item) are the item's state; disabled, inactive and loading
// items ignore activation. expanded, when set, makes it a parent of
// sub-items, open or not, with an expand chevron; depth nests it. action
// is a trailing invisible icon button named action_name, which sets
// action_clicked; menus and listboxes take none. Returns true on the
// frame it is activated: a click, Enter or Space while focused, or the
// owner's activate while it is the active descendant.
action_list_item :: proc(
	l: ^Action_List,
	label: string,
	description := "",
	description_variant := Description_Variant.Inline,
	truncate := false,
	leading := Icon.None,
	trailing := Icon.None,
	trailing_text := "",
	hint := "",
	variant := List_Item_Variant.Default,
	size := List_Item_Size.Medium,
	selected := false,
	active := false,
	disabled := false,
	inactive := "",
	loading := false,
	link := false,
	expanded: Maybe(bool) = nil,
	depth := 0,
	action := Icon.None,
	action_name := "",
	action_clicked: ^bool = nil,
	state := Interaction.Live,
) -> bool {
	gtx := l.gtx
	i := l.n
	l.n += 1
	id := action_list_item_id(l.base, i)
	memo := ui.widget_data(gtx, ui.id_mix(id, ITEM_MEMO), Item_Memo)
	it := List_Item {
		label         = ui.frame_string(gtx, label),
		description   = ui.frame_string(gtx, description),
		desc_variant  = description_variant,
		truncate      = truncate,
		leading       = leading,
		trailing      = trailing,
		trailing_text = ui.frame_string(gtx, trailing_text),
		hint          = ui.frame_string(gtx, hint),
		variant       = variant,
		size          = size,
		selected      = selected,
		active        = active,
		disabled      = disabled,
		inactive      = ui.frame_string(gtx, inactive),
		loading       = loading,
		link          = link,
		expanded      = expanded,
		depth         = depth,
		selection     = l.sel,
		index         = i,
		id            = id,
		action        = l.o.role == .List ? action : .None,
		action_name   = ui.frame_string(gtx, action_name),
	}
	it.c = control(gtx, id, memo.rect, state)
	if disabled {
		it.c.disabled = true
		it.c.state = .Disabled
	}
	dead := disabled || inactive != "" || loading
	if it.c.st != nil {
		list_item_events(l, &it)
	}
	activated := it.c.clicked && !dead
	if l.o.focus == .Descendant && l.o.activate && i == l.o.active && !dead {
		activated = true
	}
	if activated {
		l.activated = i
	}
	if it.action != .None {
		it.ac = control(gtx, ui.id_mix(id, ITEM_ACTION), memo.action, disabled ? .Disabled : state)
		if it.ac.clicked && action_clicked != nil {
			action_clicked^ = true
		}
	}
	append(&l.entries, List_Entry{kind = .Item, item = it})
	return activated
}

// list_item_events reads what reached a live item this frame beyond a
// click: the pointer moving onto it (a Descendant list's highlight), a
// press or focus that makes it a roving list's tab stop, and the keys a
// focused item hears.
@(private)
list_item_events :: proc(l: ^Action_List, it: ^List_Item) {
	gtx := l.gtx
	if l.o.focus == .Roving && ui.focused(gtx) == it.id {
		l.data.focus = it.index
	}
	for e in ui.events(gtx, it.id) {
		#partial switch e.kind {
		case .Enter, .Move:
			if l.o.focus == .Descendant {
				l.hovered = it.index
			}
		case .Press:
			if e.button == .Left && l.o.focus == .Roving && ui.focused(gtx) != it.id {
				// A press focuses a tabindex -1 item too.
				ui.focus_request(gtx, it.id)
				l.data.focus = it.index
			}
		case .Key:
			list_item_key(l, it.index, e.key, e.mods)
		}
	}
}

// list_item_key handles a key the focused item at index heard: the focus
// zone's moves in a roving list (focus-zone.mjs:46-79: Up and Down step,
// Home, End, Page Up, Page Down and the platform's command key with an
// arrow jump to an end), a letter or digit for type-ahead, and anything
// else but activation reported for the owner.
@(private)
list_item_key :: proc(l: ^Action_List, index: int, k: ui.Key, mods: ui.Mods) {
	if k == .Enter || k == .Space {
		return
	}
	if l.o.focus == .Roving {
		jump := mods - {.Shift} == {ui.SHORTCUT}
		to := List_Move_To.None
		#partial switch k {
		case .Down:
			to = jump ? .Last : .Next
		case .Up:
			to = jump ? .First : .Previous
		case .Home, .Page_Up:
			to = .First
		case .End, .Page_Down:
			to = .Last
		}
		if to != .None {
			l.move = {to, index, 0}
			return
		}
		if r, ok := key_rune(k); ok && l.o.typeahead && mods & {.Ctrl, .Alt, .Super} == {} {
			l.move = {.Letter, index, r}
			return
		}
	}
	l.key, l.mods, l.keyed = k, mods, index
}

// key_rune is the lower-case letter or digit k types.
@(private)
key_rune :: proc(k: ui.Key) -> (rune, bool) {
	switch {
	case k >= .A && k <= .Z:
		return 'a' + rune(int(k) - int(ui.Key.A)), true
	case k >= .N0 && k <= .N9:
		return '0' + rune(int(k) - int(ui.Key.N0)), true
	}
	return 0, false
}

// action_list_divider declares a rule between items (ActionList/Divider
// .tsx): 1px of --borderColor-muted, 7px below what precedes it and 8px
// above what follows. A list's first child draws no divider.
action_list_divider :: proc(l: ^Action_List) {
	append(&l.entries, List_Entry{kind = .Divider})
}

// action_list_group_open opens a group of the items declared until
// action_list_group_close (Group.module.css): 8px below what precedes
// it, under heading in small semibold muted type padded 6px by 16px,
// on a muted band between rules when Filled, with auxiliary text under
// the heading. selection overrides the list's for the group's items.
// In a plain list the heading is a heading a reader can reach; in a menu
// or listbox it names the group.
action_list_group_open :: proc(l: ^Action_List, heading: string, variant := Group_Heading_Variant.Subtle, auxiliary := "", selection: Maybe(Selection_Variant) = nil) {
	if l.in_group {
		action_list_group_close(l)
	}
	l.in_group = true
	l.sel = selection.? or_else l.o.selection
	g := List_Group {
		heading   = ui.frame_string(l.gtx, heading),
		auxiliary = ui.frame_string(l.gtx, auxiliary),
		variant   = variant,
		id        = ui.id_mix(l.base, 0x6000 + u64(len(l.entries))),
	}
	append(&l.entries, List_Entry{kind = .Group_Open, group = g})
}

// action_list_group_close closes the group action_list_group_open opened.
action_list_group_close :: proc(l: ^Action_List) {
	if !l.in_group {
		return
	}
	l.in_group = false
	l.sel = l.o.selection
	append(&l.entries, List_Entry{kind = .Group_Close})
}

// List_Metrics are the measures one list lays out with.
@(private)
List_Metrics :: struct {
	w:          f32, // the list's width
	margin:     f32, // an item's inline margin
	pad_top:    f32,
	pad_bottom: f32,
	mixed:      bool, // some items have descriptions and some not: labels stay normal weight
	menu:       bool,
}

// Item_Geom is an item laid out, in the list's space.
@(private)
Item_Geom :: struct {
	rect, action:                        ops.Rect,
	pad_y:                               f32,
	sel_x, lead_x, text_x, text_r:       f32, // text_r: the text block's right edge
	label, desc, warn:                   ui.Paragraph,
	label_pos, desc_pos, warn_pos:       ops.Point,
	label_st:                            tok.Type_Style,
	trail:                               Trail,
	trail_x:                             f32,
	desc_cut:                            bool,
	lead:                                Lead,
}

// Lead is what the leading visual's slot shows.
@(private)
Lead :: enum u8 {
	None,
	Icon,
	Spinner,
	Inactive,
}

// Trail is what the trailing visual's slot shows.
@(private)
Trail :: struct {
	kind: Trail_Kind,
	text: Text,
	hint: Hint_Layout,
	w:    f32,
}

@(private)
Trail_Kind :: enum u8 {
	None,
	Icon,
	Text,
	Hint,
	Spinner,
	Inactive,
	Expand,
}

// label_style is an item's label type: body medium (small in a sub-group)
// on a 20px line, semibold with a description unless the list mixes
// described and undescribed items, and when active
// (ActionList.module.css:101-106,216-226,640-713,715-718).
@(private)
label_style :: proc(it: List_Item, mixed: bool) -> tok.Type_Style {
	weight := tok.BASE_TEXT_WEIGHT_NORMAL
	if (it.description != "" && !mixed) || it.active {
		weight = tok.BASE_TEXT_WEIGHT_SEMIBOLD
	}
	size := it.depth > 0 ? tok.TEXT_BODY_SIZE_SMALL : tok.TEXT_BODY_SIZE_MEDIUM
	return {weight = weight, size = size, line_height = LIST_LINE}
}

// small_style is the description's, inactive warning's and auxiliary
// text's type: body small on a 16px line.
@(private)
small_style :: proc() -> tok.Type_Style {
	return {weight = tok.BASE_TEXT_WEIGHT_NORMAL, size = tok.TEXT_BODY_SIZE_SMALL, line_height = LIST_SMALL_LINE}
}

// lead_of is what an item's leading slot shows: a loading spinner or, in
// a plain list, the inactive alert take the leading visual's place when
// there is one (Visuals.tsx:44-87).
@(private)
lead_of :: proc(it: List_Item, menu: bool) -> Lead {
	if it.leading == .None {
		return .None
	}
	switch {
	case it.inactive != "" && !menu:
		return .Inactive
	case it.loading:
		return .Spinner
	}
	return .Icon
}

// trail_of shapes what an item's trailing slot shows: the spinner or
// inactive alert when there is no leading visual, the expand chevron of
// a parent, else the trailing visual, text or hint.
@(private)
trail_of :: proc(gtx: ^ui.Ctx, it: List_Item, menu: bool) -> (t: Trail) {
	switch {
	case it.leading == .None && it.inactive != "" && !menu:
		t.kind, t.w = .Inactive, LIST_VISUAL
	case it.leading == .None && it.loading:
		t.kind, t.w = .Spinner, LIST_VISUAL
	case it.expanded != nil && it.trailing == .None:
		t.kind, t.w = .Expand, LIST_VISUAL
	case it.trailing != .None:
		t.kind, t.w = .Icon, LIST_VISUAL
	case it.hint != "":
		t.kind = .Hint
		t.hint = layout_hint(gtx, it.hint, .Condensed, .Normal, .Normal)
		t.w = t.hint.size.x
	case it.trailing_text != "":
		st := tok.Type_Style{weight = tok.BASE_TEXT_WEIGHT_NORMAL, size = tok.TEXT_BODY_SIZE_MEDIUM, line_height = LIST_LINE}
		t.kind = .Text
		t.text = design.shape_style(gtx, it.trailing_text, st, font_for(gtx, st.weight))
		t.w = t.text.width
	}
	return
}

// item_pad is the content's block padding: 6px, 10px for large
// (ActionList.module.css:515-517,538-541).
@(private)
item_pad :: proc(s: List_Item_Size) -> f32 {
	return s == .Large ? tok.CONTROL_LARGE_PADDING_BLOCK : tok.CONTROL_MEDIUM_PADDING_BLOCK
}

// columns_width is the width of the item's columns before its text:
// padding, depth spacer, selection and leading visual, each present one
// with the 8px gap after it (ActionList.module.css:500-529).
@(private)
columns_width :: proc(it: List_Item, menu: bool) -> f32 {
	gap := tok.CONTROL_MEDIUM_GAP
	x := tok.CONTROL_MEDIUM_PADDING_INLINE_CONDENSED
	if it.depth > 0 {
		x += LIST_DEPTH_STEP * f32(it.depth)
	}
	if it.selection != .None {
		x += LIST_VISUAL + gap
	}
	if lead_of(it, menu) != .None {
		x += LIST_VISUAL + gap
	}
	return x
}

// item_natural is an item's width with nothing wrapped.
@(private)
item_natural :: proc(gtx: ^ui.Ctx, it: List_Item, m: List_Metrics) -> f32 {
	st := label_style(it, m.mixed)
	label := design.shape_style(gtx, it.label, st, font_for(gtx, st.weight)).width
	text := label
	sm := small_style()
	if it.description != "" {
		d := design.shape_style(gtx, it.description, sm, font_for(gtx, sm.weight)).width
		text = it.desc_variant == .Block ? max(label, d) : label + tok.BASE_SIZE_8 + d
	}
	if it.inactive != "" && m.menu {
		text = max(text, design.shape_style(gtx, it.inactive, sm, font_for(gtx, sm.weight)).width)
	}
	w := columns_width(it, m.menu) + text + tok.CONTROL_MEDIUM_PADDING_INLINE_CONDENSED
	if t := trail_of(gtx, it, m.menu); t.kind != .None {
		w += tok.CONTROL_MEDIUM_GAP + t.w
	}
	if it.action != .None {
		w += tok.CONTROL_MEDIUM_SIZE
	}
	return w + 2 * m.margin
}

// layout_item lays it out at y across the list's width (ActionList
// .module.css:500-713): the columns top-aligned, visuals in a 20px box on
// the first line, the label wrapping in what the trailing visual leaves,
// a description beside it on a shared baseline or 4px under it, the
// inactive warning on a row of its own in a menu or listbox.
@(private)
layout_item :: proc(gtx: ^ui.Ctx, it: List_Item, y: f32, m: List_Metrics) -> (g: Item_Geom) {
	// A sub-item's own li has no inline margin, but it sits inside its
	// top-level ancestor's, which does (ActionList.module.css:715-723).
	margin := m.margin
	gap := tok.CONTROL_MEDIUM_GAP
	pad_x := tok.CONTROL_MEDIUM_PADDING_INLINE_CONDENSED
	g.pad_y = item_pad(it.size)
	iw := max(m.w - 2 * margin, 0)
	cw := iw - (it.action != .None ? tok.CONTROL_MEDIUM_SIZE : 0)
	x := margin + pad_x
	// Every spacer under an item with sub-items shows, a leaf's as much
	// as a parent's (ActionList.module.css:319-339,612-616).
	if it.depth > 0 {
		x += LIST_DEPTH_STEP * f32(it.depth)
	}
	if it.selection != .None {
		g.sel_x = x
		x += LIST_VISUAL + gap
	}
	g.lead = lead_of(it, m.menu)
	if g.lead != .None {
		g.lead_x = x
		x += LIST_VISUAL + gap
	}
	g.text_x = x
	g.text_r = margin + cw - pad_x
	g.trail = trail_of(gtx, it, m.menu)
	label_r := g.text_r
	if g.trail.kind != .None {
		g.trail_x = g.text_r - g.trail.w
		label_r = g.trail_x - gap
	}
	// The slack keeps a label laid out at its own measured width, as a
	// hugging list lays it, on one line.
	room := max(label_r - g.text_x, 0) + WRAP_SLACK
	top := y + g.pad_y
	g.label_st = label_style(it, m.mixed)
	sm := small_style()
	h: f32
	if it.description != "" && it.desc_variant == .Inline {
		h = layout_inline(gtx, it, &g, room, top)
	} else {
		g.label = design.layout_style(gtx, it.label, g.label_st, font_for(gtx, g.label_st.weight), room)
		g.label_pos = {g.text_x, top}
		h = g.label.height
		if it.description != "" {
			g.desc = design.layout_style(gtx, it.description, sm, font_for(gtx, sm.weight), room)
			g.desc_pos = {g.text_x, top + h + tok.BASE_SIZE_4}
			h += tok.BASE_SIZE_4 + g.desc.height
		}
	}
	if it.inactive != "" && m.menu {
		g.warn = design.layout_style(gtx, it.inactive, sm, font_for(gtx, sm.weight), room)
		g.warn_pos = {g.text_x, top + h}
		h += g.warn.height
	}
	row := max(h, LIST_LINE) + 2 * g.pad_y
	g.rect = {margin, y, iw, row}
	if it.action != .None {
		g.action = {margin + cw, y, tok.CONTROL_MEDIUM_SIZE, row}
	}
	return
}

// layout_inline lays out a label with an inline description in room: a
// row 8px apart on the label's first baseline, each shrinking in
// proportion to its width when they do not fit (flex-shrink 1), a
// truncated description keeping one line with an ellipsis. It returns the
// row's height.
@(private)
layout_inline :: proc(gtx: ^ui.Ctx, it: List_Item, g: ^Item_Geom, room, top: f32) -> f32 {
	sm := small_style()
	lf, df := font_for(gtx, g.label_st.weight), font_for(gtx, sm.weight)
	lw := design.shape_style(gtx, it.label, g.label_st, lf).width
	dw := design.shape_style(gtx, it.description, sm, df).width
	gap := tok.BASE_SIZE_8
	if over := lw + gap + dw - room; over > 0 {
		if it.truncate {
			lw = min(lw, room)
			dw = max(room - lw - gap, 0)
		} else {
			lw, dw = lw - over * lw / (lw + dw), dw - over * dw / (lw + dw)
		}
	}
	g.label = design.layout_style(gtx, it.label, g.label_st, lf, max(lw, 1) + WRAP_SLACK)
	if it.truncate {
		g.desc = design.layout_style(gtx, it.description, sm, df, max(dw, 1) + WRAP_SLACK, max_lines = 1)
		g.desc_cut = g.desc.truncated
	} else {
		g.desc = design.layout_style(gtx, it.description, sm, df, max(dw, 1) + WRAP_SLACK)
	}
	g.label_pos = {g.text_x, top}
	base := len(g.label.lines) > 0 ? g.label.lines[0].baseline : 0
	db := len(g.desc.lines) > 0 ? g.desc.lines[0].baseline : 0
	g.desc_pos = {g.text_x + g.label.width + gap, top + base - db}
	return max(g.label.height, g.desc_pos.y - top + g.desc.height)
}

// group_heading_height is a group heading's height: the 18px line padded
// 6px each way, the auxiliary text under it, and a filled band's rules
// and the 8px under it (Group.module.css:13-41).
@(private)
group_heading_height :: proc(gtx: ^ui.Ctx, g: List_Group, w: f32) -> (h: f32, aux: ui.Paragraph) {
	if g.heading == "" && g.auxiliary == "" {
		return
	}
	h = LIST_GROUP_LINE + 2 * tok.BASE_SIZE_6
	if g.auxiliary != "" {
		sm := small_style()
		aux = design.layout_style(gtx, g.auxiliary, sm, font_for(gtx, sm.weight), max(w - 2 * tok.BASE_SIZE_16, 1))
		h += aux.height
	}
	if g.variant == .Filled {
		h += 2 * tok.BORDER_WIDTH_THIN + tok.BASE_SIZE_8
	}
	return
}

// Laid_Entry is an entry with its place: an item's geometry, a group's
// band and span, a divider's line.
@(private)
Laid_Entry :: struct {
	y, h: f32,
	geom: Item_Geom,
	aux:  ui.Paragraph,
	span: f32, // a group's height through its last item
	skip: bool, // a divider that is the list's first child
}

// action_list_close lays out, paints and declares the list's items, and
// resolves the frame's keyboard moves (action-list.json layout, states).
action_list_close :: proc(l: ^Action_List) {
	if l.closed {
		return
	}
	if l.in_group {
		action_list_group_close(l)
	}
	l.closed = true
	gtx := l.gtx
	m := list_metrics(l)
	heading: Text
	heading_h: f32
	if l.o.heading != "" {
		st := style(.Title_Small)
		heading = design.shape_style(gtx, l.o.heading, st, font_for(gtx, st.weight))
		heading_h = heading.height + tok.BASE_SIZE_8
	}
	laid := make([]Laid_Entry, len(l.entries), gtx.allocator)
	rows := make([dynamic]List_Row, gtx.allocator)
	y := heading_h + m.pad_top
	groups := make([dynamic]int, gtx.allocator)
	for &e, i in l.entries {
		le := &laid[i]
		le.y = y
		switch e.kind {
		case .Item:
			le.geom = layout_item(gtx, e.item, y, m)
			le.h = le.geom.rect.h
			append(&rows, List_Row{e.item.id, le.geom.rect, e.item.label, e.item.disabled})
		case .Divider:
			if i == 0 {
				le.skip = true
				continue
			}
			le.h = LIST_DIVIDER_ABOVE + tok.BORDER_WIDTH_THIN + tok.BASE_SIZE_8
		case .Group_Open:
			if i > 0 {
				y += tok.BASE_SIZE_8
				le.y = y
			}
			le.h, le.aux = group_heading_height(gtx, e.group, m.w)
			append(&groups, i)
		case .Group_Close:
			if n := len(groups); n > 0 {
				open := groups[n - 1]
				laid[open].span = y - laid[open].y
				pop(&groups)
			}
		}
		y += le.h
	}
	h := y + m.pad_bottom
	l.rows = rows[:]
	list_resolve_focus(l)
	paint_list(l, m, laid, heading)
	sz := ui.constrain(l.cs, {m.w, h})
	role := LIST_ROLES[l.o.role]
	labelled: ops.Area_Id
	if l.o.heading != "" {
		labelled = ui.id_mix(l.base, 0x4ead)
		indent := l.o.variant == .Full ? tok.BASE_SIZE_8 : tok.CONTROL_MEDIUM_PADDING_INLINE_CONDENSED + tok.BASE_SIZE_8
		draw_text(gtx, heading, {indent, 0}, color(.Fg_Color_Default))
		ui.part_semantics(gtx, &l.p, labelled, {indent, 0, heading.width, heading.height}, {role = .Heading, label = l.o.heading, level = u8(clamp(l.o.heading_level, 1, 6))})
	}
	ui.semantics(gtx, &l.p, {role = role, label = ui.frame_string(gtx, l.o.name), labelled_by = labelled})
	ui.widget_close(gtx, &l.p, {sz, 0})
}

@(private)
LIST_ROLES := [List_Role]ops.Role {
	.List    = .List,
	.Listbox = .List_Box,
	.Menu    = .Menu,
}

// list_metrics are l's measures: its width, the widest item's when its
// container lets it hug, else what it is offered; its insets; whether its
// items mix described and undescribed (ActionList.module.css:14-27,
// 101-106).
@(private)
list_metrics :: proc(l: ^Action_List) -> (m: List_Metrics) {
	gtx := l.gtx
	m.menu = l.o.role != .List
	if l.o.variant != .Full {
		m.margin = tok.BASE_SIZE_8
	}
	switch l.o.variant {
	case .Inset:
		m.pad_top, m.pad_bottom = tok.BASE_SIZE_8, tok.BASE_SIZE_8
	case .Horizontal_Inset:
		m.pad_bottom = tok.BASE_SIZE_8
	case .Full:
	}
	described, plain := false, false
	for e in l.entries {
		if e.kind == .Item {
			described |= e.item.description != ""
			plain |= e.item.description == ""
		}
	}
	m.mixed = described && plain
	natural: f32
	for e in l.entries {
		#partial switch e.kind {
		case .Item:
			natural = max(natural, item_natural(gtx, e.item, m))
		case .Group_Open:
			st := tok.Type_Style{weight = tok.BASE_TEXT_WEIGHT_SEMIBOLD, size = tok.TEXT_BODY_SIZE_SMALL, line_height = LIST_GROUP_LINE}
			hw := design.shape_style(gtx, e.group.heading, st, font_for(gtx, st.weight)).width
			natural = max(natural, hw + 2 * tok.BASE_SIZE_16)
		}
	}
	if l.o.heading != "" {
		st := style(.Title_Small)
		natural = max(natural, design.shape_style(gtx, l.o.heading, st, font_for(gtx, st.weight)).width + tok.BASE_SIZE_16)
	}
	m.w = natural
	if ui.is_finite(l.cs.max.x) {
		m.w = min(m.w, l.cs.max.x)
	}
	m.w = max(m.w, l.cs.min.x)
	return
}

// list_resolve_focus resolves the frame's keyboard move and focus_to in
// a roving list, and the highlight to follow in a Descendant one: moves
// focus (focus-zone.mjs:486-512, wrapping when the list wraps, stopping
// at the ends otherwise; disabled items are visited, as the focus zone
// takes every focusable element), and scrolls the item into view
// (scroll-into-view.mjs).
@(private)
list_resolve_focus :: proc(l: ^Action_List) {
	n := len(l.rows)
	if n == 0 {
		return
	}
	gtx := l.gtx
	to := -1
	if l.o.focus == .Roving {
		if l.data.focus >= n {
			l.data.focus = n - 1
			ui.request_frame(gtx)
		}
		mv := l.move
		switch mv.to {
		case .None:
		case .Next:
			to = mv.from + 1
			if to >= n {
				to = l.o.wrap ? 0 : n - 1
			}
		case .Previous:
			to = mv.from - 1
			if to < 0 {
				to = l.o.wrap ? n - 1 : 0
			}
		case .First:
			to = 0
		case .Last:
			to = n - 1
		case .Letter:
			to = typeahead_target(l.rows, mv.from, mv.letter)
		}
		switch l.o.focus_to {
		case .None:
		case .First:
			to = 0
		case .Last:
			to = n - 1
		}
		if to >= 0 {
			l.data.focus = to
			ui.focus_request(gtx, l.rows[to].id)
			l.moved = true
		}
	} else if l.o.focus == .Descendant && l.o.follow && l.o.active >= 0 && l.o.active < n {
		to = l.o.active
	}
	if to >= 0 {
		scroll_into_view(gtx, l.o.scroll, l.rows[to].rect)
	}
}

// typeahead_target is the next item after from whose label starts with
// letter, cycling back to the first match after the last; -1 for none
// (useMnemonics.ts:33-80).
@(private)
typeahead_target :: proc(rows: []List_Row, from: int, letter: rune) -> int {
	first, after := -1, -1
	for r, i in rows {
		c, _ := utf8.decode_rune_in_string(strings.trim_left_space(r.label))
		if unicode.to_lower(c) != letter {
			continue
		}
		if first < 0 {
			first = i
		}
		if i > from && after < 0 {
			after = i
		}
	}
	return after if after >= 0 else first
}

// scroll_into_view moves s's offset so rect, a box in the list's space,
// shows: its top no higher than the view's, its bottom end_margin above
// the view's bottom (scroll-into-view.mjs:1-21).
@(private)
scroll_into_view :: proc(gtx: ^ui.Ctx, s: List_Scroll, rect: ops.Rect) {
	if s.offset == nil || s.view <= 0 {
		return
	}
	top := s.top + rect.y
	bottom := top + rect.h
	at := s.offset.y
	switch {
	case top < at:
		at = top
	case bottom > at + s.view - s.end_margin:
		at = bottom + s.end_margin - s.view
	}
	if at != s.offset.y {
		s.offset.y = max(at, 0)
		ui.request_frame(gtx)
	}
}

// paint_list paints every laid-out entry and declares its semantics.
@(private)
paint_list :: proc(l: ^Action_List, m: List_Metrics, laid: []Laid_Entry, heading: Text) {
	gtx := l.gtx
	group: ops.Area_Id
	prev_lit := true // the item before is hovered, focused or active, or there is none: no rule above the next
	for &e, i in l.entries {
		le := laid[i]
		switch e.kind {
		case .Item:
			it := &e.item
			lit := paint_list_item(l, it, le.geom, m, group, prev_lit)
			prev_lit = lit
		case .Divider:
			prev_lit = true
			if le.skip {
				continue
			}
			ops.fill(gtx.scene, ops.Rect{0, le.y + LIST_DIVIDER_ABOVE, m.w, tok.BORDER_WIDTH_THIN}, color(.Border_Color_Muted))
		case .Group_Open:
			prev_lit = true
			group = e.group.id
			paint_group_heading(l, e.group, le, m)
		case .Group_Close:
			group = 0
		}
	}
}

// paint_group_heading paints a group's heading and declares the group:
// in a menu or listbox a group named by its heading, in a plain list a
// group labelled by a heading node (ActionList/Group.tsx:99-127,180-236).
@(private)
paint_group_heading :: proc(l: ^Action_List, g: List_Group, le: Laid_Entry, m: List_Metrics) {
	gtx := l.gtx
	y := le.y
	band := ops.Rect{0, y, m.w, le.h}
	if g.variant == .Filled && le.h > 0 {
		band.h -= tok.BASE_SIZE_8
		ops.fill(gtx.scene, band, color(.Bg_Color_Muted))
		ops.fill(gtx.scene, ops.Rect{0, band.y, m.w, tok.BORDER_WIDTH_THIN}, color(.Border_Color_Muted))
		ops.fill(gtx.scene, ops.Rect{0, band.y + band.h - tok.BORDER_WIDTH_THIN, m.w, tok.BORDER_WIDTH_THIN}, color(.Border_Color_Muted))
		y += tok.BORDER_WIDTH_THIN
	}
	st := tok.Type_Style{weight = tok.BASE_TEXT_WEIGHT_SEMIBOLD, size = tok.TEXT_BODY_SIZE_SMALL, line_height = LIST_GROUP_LINE}
	t := design.shape_style(gtx, g.heading, st, font_for(gtx, st.weight))
	at := ops.Point{tok.BASE_SIZE_16, y + tok.BASE_SIZE_6}
	fg := color(.Fg_Color_Muted)
	if g.heading != "" {
		draw_text(gtx, t, at, fg)
	}
	if g.auxiliary != "" {
		design.draw_paragraph(gtx, le.aux, {at.x, at.y + LIST_GROUP_LINE}, fg)
	}
	span := ops.Rect{0, le.y, m.w, le.span}
	if l.o.role == .List && g.heading != "" {
		hid := ui.id_mix(g.id, 1)
		ui.part_semantics(gtx, &l.p, hid, {at.x, at.y, t.width, t.height}, {role = .Heading, label = g.heading, level = u8(clamp(l.o.heading_level + 1, 1, 6))})
		ui.part_semantics(gtx, &l.p, g.id, span, {role = .Group, labelled_by = hid})
	} else {
		ui.part_semantics(gtx, &l.p, g.id, span, {role = .Group, label = g.heading})
	}
}

// Item_Ink is an item's colours this frame.
@(private)
Item_Ink :: struct {
	bg:                                 ops.Color,
	ring, bar:                          bool,
	label, visual, desc, trail, select: ops.Color,
	hint_fill:                          ops.Color,
}

// item_ink is an item's colours for its state (action-list.json states;
// ActionList.module.css:111-301,342-383): the hover and pressed fills
// with a 1px ring, none while disabled or inactive; the selected fill and
// accent bar while active or the active descendant; danger's red text and
// fills; disabled, loading and inactive text.
@(private)
item_ink :: proc(it: ^List_Item, highlighted: bool) -> (k: Item_Ink) {
	c := it.c
	quiet := it.disabled || it.inactive != ""
	danger := it.variant == .Danger
	hovered := c.hovered && !quiet
	pressed := c.pressed && !quiet
	bg := tok.Role.Control_Transparent_Bg_Color_Rest
	switch {
	case pressed:
		bg = danger ? .Control_Danger_Bg_Color_Active : .Control_Transparent_Bg_Color_Active
	case hovered:
		bg = danger ? .Control_Danger_Bg_Color_Hover : .Control_Transparent_Bg_Color_Hover
	case highlighted || it.active:
		bg = .Control_Transparent_Bg_Color_Selected
	}
	k.bg = color(bg)
	k.ring = (hovered || pressed) && !it.active && !c.focus_visible
	k.bar = highlighted || it.active
	k.label = color(.Fg_Color_Default)
	k.visual = color(.Fg_Color_Muted)
	k.desc = color(.Fg_Color_Muted)
	k.trail = color(.Fg_Color_Muted)
	k.select = color(.Control_Fg_Color_Rest)
	k.hint_fill = color(.Bg_Color_Transparent)
	if it.active {
		k.label = color(.Control_Fg_Color_Rest)
	}
	if danger {
		red := color(hovered || pressed ? .Control_Danger_Fg_Color_Hover : .Control_Danger_Fg_Color_Rest)
		k.label, k.visual, k.select = red, red, red
		if hovered || pressed {
			k.hint_fill = color(.Bg_Color_Default)
		}
	}
	if it.loading || it.inactive != "" {
		muted := color(.Fg_Color_Muted)
		k.label, k.visual, k.desc, k.trail, k.select = muted, muted, muted, muted, muted
	}
	if it.disabled {
		off := color(.Control_Fg_Color_Disabled)
		k.label, k.visual, k.desc, k.trail, k.select = off, off, off, off, off
	}
	return
}

// paint_list_item paints one item and declares it; it returns whether the
// item is hovered, keyboard-focused or active, which hides the divider
// rule above the next item (ActionList.module.css:166-173,234-239,303-316).
@(private)
paint_list_item :: proc(l: ^Action_List, it: ^List_Item, g: Item_Geom, m: List_Metrics, group: ops.Area_Id, prev_lit: bool) -> bool {
	gtx := l.gtx
	memo := ui.widget_data(gtx, ui.id_mix(it.id, ITEM_MEMO), Item_Memo)
	memo.rect, memo.action = g.rect, g.action
	highlighted := l.o.focus == .Descendant && it.index == l.o.active
	k := item_ink(it, highlighted)
	rr := ops.Round_Rect{g.rect, tok.BORDER_RADIUS_MEDIUM}
	if ui.painted(k.bg) {
		ops.fill(gtx.scene, rr, k.bg)
	}
	if k.ring {
		stroke_inside(gtx, rr, color(.Control_Transparent_Border_Color_Active), tok.BORDER_WIDTH_THIN)
	}
	if k.bar {
		// activeIndicatorLine.css: 4px wide, 8px left of the item, 4px in
		// from its top and bottom.
		bar := ops.Rect{g.rect.x - tok.BASE_SIZE_8, g.rect.y + tok.BASE_SIZE_4, tok.BASE_SIZE_4, g.rect.h - tok.BASE_SIZE_8}
		ops.fill(gtx.scene, ops.Round_Rect{bar, radius(tok.BORDER_RADIUS_MEDIUM, bar)}, color(.Border_Color_Accent_Emphasis))
	}
	lit := it.c.hovered || it.c.focus_visible || it.active
	if l.o.dividers && !prev_lit && !lit {
		ops.fill(gtx.scene, ops.Rect{g.text_x, g.rect.y + g.pad_y - LIST_DIVIDER_ABOVE, g.text_r - g.text_x, tok.BORDER_WIDTH_THIN}, color(.Border_Color_Muted))
	}
	line := g.rect.y + g.pad_y // the first line's top
	icon_y := line + (LIST_LINE - LIST_VISUAL) / 2
	if it.selection != .None {
		paint_selection(gtx, it, {g.sel_x, icon_y}, k, l.o.role == .Menu)
	}
	switch g.lead {
	case .None:
	case .Icon:
		icon(gtx, it.leading, {g.lead_x, icon_y}, LIST_VISUAL, k.visual)
	case .Spinner:
		paint_spinner(gtx, {g.lead_x, icon_y}, LIST_VISUAL, k.visual)
	case .Inactive:
		paint_inactive(gtx, it, {g.lead_x, icon_y, LIST_VISUAL, LIST_VISUAL}, k.visual)
	}
	design.draw_paragraph(gtx, g.label, g.label_pos, k.label)
	if it.description != "" {
		design.draw_paragraph(gtx, g.desc, g.desc_pos, k.desc)
	}
	if it.inactive != "" && m.menu {
		design.draw_paragraph(gtx, g.warn, g.warn_pos, color(.Fg_Color_Attention))
	}
	paint_trail(gtx, it, g, {g.trail_x, line}, k)
	if it.action != .None {
		paint_trailing_action(l, it, g)
	}
	paint_focus_outline(gtx, it.c, rr, 0)
	kinds := CLICK_KINDS
	switch l.o.focus {
	case .Tab:
	case .Roving:
		if it.index != l.data.focus {
			kinds -= {.Key}
		}
	case .Descendant:
		kinds = {.Press, .Release, .Enter, .Leave, .Move}
	}
	dead := it.disabled || it.inactive != "" || it.loading
	listen(gtx, it.c.st, it.id, rr, kinds, dead ? .Not_Allowed : .Pointer)
	ops.tag(gtx.scene, it.id, it.label, g.rect)
	if it.truncate && g.desc_cut && it.c.st != nil {
		tooltip_run(gtx, it.id, g.rect, it.description, .E, .Medium, false, true)
	}
	ui.part_semantics(gtx, &l.p, it.id, g.rect, item_semantics(gtx, l, it, g), under = group)
	return lit
}

// paint_selection draws an item's selection indicator at pos: a
// checkmark for Single, or Multiple in a menu, shown only when selected;
// a radio's ring and dot; a checkbox whose check is revealed as it fills
// (ActionList.module.css:407-496, Selection.tsx:12-53).
@(private)
paint_selection :: proc(gtx: ^ui.Ctx, it: ^List_Item, pos: ops.Point, k: Item_Ink, menu: bool) {
	box := ops.Rect{pos.x, pos.y, LIST_VISUAL, LIST_VISUAL}
	switch {
	case it.selection == .Single || (it.selection == .Multiple && menu):
		if it.selected {
			icon(gtx, .Check, pos, LIST_VISUAL, k.select)
		}
	case it.selection == .Radio:
		ring, fill := tok.Role.Control_Border_Color_Emphasis, tok.Role.Bg_Color_Default
		width := tok.BORDER_WIDTH_THIN
		if it.selected {
			ring, fill, width = .Control_Checked_Bg_Color_Rest, .Control_Checked_Fg_Color_Rest, RADIO_RING_CHECKED
		}
		if it.disabled {
			ring = it.selected ? .Control_Checked_Bg_Color_Disabled : .Control_Border_Color_Disabled
			fill = it.selected ? .Control_Checked_Fg_Color_Disabled : .Control_Bg_Color_Disabled
		}
		centre := ops.Point{pos.x + LIST_VISUAL / 2, pos.y + LIST_VISUAL / 2}
		ops.fill(gtx.scene, ui.circle(centre, LIST_VISUAL / 2), color(ring))
		ops.fill(gtx.scene, ui.circle(centre, LIST_VISUAL / 2 - width), color(fill))
	case it.selection == .Multiple:
		paint_list_checkbox(gtx, it, box)
	case:
	}
}

// paint_list_checkbox is the multiple-selection checkbox: 16px, a 1px
// --control-borderColor-emphasis border at the small radius on
// --bgColor-default, filling --control-checked-bgColor-rest when selected
// with a --control-checked-fgColor-rest check revealed over 80ms after an
// 80ms delay; disabled greys it (ActionList.module.css:342-383,407-496).
// The fill snaps and the border fades, as the CSS's transition list does
// (action-list.json notes upstream-bug).
@(private)
paint_list_checkbox :: proc(gtx: ^ui.Ctx, it: ^List_Item, box: ops.Rect) {
	on := it.selected
	fill, border, glyph: tok.Role
	switch {
	case it.disabled && on:
		fill, border, glyph = .Control_Checked_Bg_Color_Disabled, .Control_Checked_Bg_Color_Disabled, .Control_Checked_Fg_Color_Disabled
	case it.disabled:
		fill, border = .Control_Bg_Color_Disabled, .Control_Border_Color_Disabled
	case on:
		fill, border, glyph = .Control_Checked_Bg_Color_Rest, .Control_Checked_Border_Color_Rest, .Control_Checked_Fg_Color_Rest
	case:
		fill, border = .Bg_Color_Default, .Control_Border_Color_Emphasis
	}
	rr := ops.Round_Rect{box, tok.BORDER_RADIUS_SMALL}
	ops.fill(gtx.scene, rr, color(fill))
	stroke_inside(gtx, rr, design.blend(gtx, it.c.fades, 0, color(border), CHECK_REVEAL.duration, on ? CHECK_BORDER_IN : CHECK_BORDER_OUT), tok.BORDER_WIDTH_THIN)
	shown := check_reveal(gtx, it.c, ui.id_mix(it.id, 0xc4ec), on)
	if shown > 0 {
		ops.clip_push(gtx.scene, ops.Rect{box.x, box.y + LIST_VISUAL * (1 - shown), LIST_VISUAL, LIST_VISUAL * shown})
		mark := color(glyph) if on else color(.Control_Checked_Fg_Color_Rest)
		paint_svg(gtx, CHECK_MARK, 12, {box.x + (LIST_VISUAL - CHECK_GLYPH) / 2, box.y + (LIST_VISUAL - 9) / 2}, CHECK_GLYPH, mark)
		ops.clip_pop(gtx.scene)
	}
}

// paint_inactive draws a plain list's inactive indicator in r: the alert
// octicon, whose tooltip gives the reason (Visuals.tsx:69-80).
@(private)
paint_inactive :: proc(gtx: ^ui.Ctx, it: ^List_Item, r: ops.Rect, c: ops.Color) {
	icon(gtx, .Alert, {r.x, r.y}, LIST_VISUAL, c)
	if it.c.st != nil {
		tooltip_run(gtx, ui.id_mix(it.id, ITEM_INACTIVE), r, it.inactive, .S, .Short, false, true)
	}
}

// paint_trail draws the trailing slot with its first line's top-left at
// pos: an icon or spinner in the 20px visual box, text on the label's
// line, a keybinding hint centred on it, a parent's chevron flipped while
// open (ActionList.module.css:543-558,626-629,686-699).
@(private)
paint_trail :: proc(gtx: ^ui.Ctx, it: ^List_Item, g: Item_Geom, pos: ops.Point, k: Item_Ink) {
	iy := pos.y + (LIST_LINE - LIST_VISUAL) / 2
	switch g.trail.kind {
	case .None:
	case .Icon:
		icon(gtx, it.trailing, {pos.x, iy}, LIST_VISUAL, k.trail)
	case .Spinner:
		paint_spinner(gtx, {pos.x, iy}, LIST_VISUAL, k.trail)
	case .Inactive:
		paint_inactive(gtx, it, {pos.x, iy, LIST_VISUAL, LIST_VISUAL}, k.trail)
	case .Expand:
		open := it.expanded.? or_else false
		icon(gtx, open ? .Chevron_Up : .Chevron_Down, {pos.x, iy}, LIST_VISUAL, k.trail)
	case .Text:
		draw_text(gtx, g.trail.text, {pos.x, pos.y + (LIST_LINE - g.trail.text.height) / 2}, k.trail)
	case .Hint:
		colors := hint_colors(.Normal)
		colors.fill = k.hint_fill
		paint_hint(gtx, g.trail.hint, {pos.x, pos.y + (LIST_LINE - g.trail.hint.size.y) / 2}, colors)
	}
}

// paint_trailing_action draws an item's trailing action: an invisible
// medium icon button as tall as the row, square on its left
// (ActionList.module.css:725-749, TrailingAction.tsx:32-77), its own
// tab stop.
@(private)
paint_trailing_action :: proc(l: ^Action_List, it: ^List_Item, g: Item_Geom) {
	gtx := l.gtx
	c := it.ac
	r := g.action
	rad := tok.BORDER_RADIUS_MEDIUM
	shape := rounded(gtx, r, {0, rad, rad, 0})
	roles := variant_roles(.Invisible)
	if bg := color_for(roles.bg, c); ui.painted(bg) {
		ops.fill(gtx.scene, shape, bg)
	}
	icon(gtx, it.action, {r.x + (r.w - LIST_VISUAL) / 2, r.y + (r.h - LIST_VISUAL) / 2}, LIST_VISUAL, color_for({.Button_Invisible_Icon_Color_Rest, .Button_Invisible_Icon_Color_Hover, .Button_Invisible_Icon_Color_Hover, .Button_Invisible_Fg_Color_Disabled}, c))
	paint_focus_outline(gtx, c, {r, rad})
	id := ui.id_mix(it.id, ITEM_ACTION)
	listen(gtx, c.st, id, r, cursor = .Pointer)
	ops.tag(gtx.scene, id, it.action_name, r)
	ui.part_semantics(gtx, &l.p, id, r, {role = .Button, label = it.action_name, states = design.state_if(c.disabled, {.Disabled})})
}

// item_semantics is what an item says (action-list.json accessibility):
// its role from the list's, its label with its trailing text or hint and
// "Loading" while it loads, its description and, in a menu or listbox,
// its inactive reason, and its states.
@(private)
item_semantics :: proc(gtx: ^ui.Ctx, l: ^Action_List, it: ^List_Item, g: Item_Geom) -> (s: ops.Semantics) {
	switch l.o.role {
	case .List:
		s.role = it.link ? .Link : .Button
		if it.selection != .None {
			s.role = .Option
		}
	case .Listbox:
		s.role = .Option
	case .Menu:
		#partial switch it.selection {
		case .Single, .Radio:
			s.role = .Menu_Item_Radio
		case .Multiple:
			s.role = .Menu_Item_Checkbox
		case:
			s.role = .Menu_Item
		}
	}
	label := it.label
	#partial switch g.trail.kind {
	case .Text:
		label = join_words(gtx, label, it.trailing_text)
	case .Hint:
		label = join_words(gtx, label, spoken_hint(it.hint, PLATFORM, gtx.allocator))
	}
	if it.loading && it.inactive == "" {
		label = join_words(gtx, label, LOADING_SUFFIX)
	}
	s.label = label
	s.description = it.description
	if it.inactive != "" && l.o.role != .List {
		s.description = join_words(gtx, s.description, it.inactive)
	}
	if it.selection != .None && it.selected {
		s.states += {s.role == .Option ? .Selected : .Checked}
	}
	s.states += design.state_if(it.disabled, {.Disabled}) + expanded_states(it.expanded)
	if it.active && it.link {
		// An active link is the page shown (aria-current="page", as
		// NavList sets it, NavList.tsx:183-196).
		s.states += {.Current_Page}
	}
	return
}
