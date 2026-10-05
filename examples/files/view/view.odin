/*
Package view is the file browser's ui, built from Fluent's own parts: a
toolbar with the folder's breadcrumb, the actions on entries and a
search box, a table of the entries that sorts by its columns, a details
card for the selected one, and the application's activity: copies under
way, questions it asks, and problems. The folder's listing, every
thumbnail and the activity are needs the application answers; the ui
holds the path, the selection, the sort, the search and what was copied
or cut, and turns clicks into files.Commands. It decides nothing about
the files themselves: whether a name is free, or a paste would collide,
is the application's to find out.
*/
package files_view

import "core:fmt"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:time"

import "jm:ui"
import "jm:ui/design"
import "jm:ui/fluent"
import "jm:ui/ops"

import "../../common"
import "../files"
import "../query"

THUMB :: 32 // in a row
// The window is never smaller than MIN_WIDTH by MIN_HEIGHT points
// (main.odin); every size from there up lays out whole.
MIN_WIDTH :: 480
MIN_HEIGHT :: 360
SIDEBAR_FROM :: 760 // the window width from which the sidebar sits beside the content
DETAILS_FROM :: 760 // the width, less the sidebar, from which the details pane shows
SIZE_FROM :: 380 // the content width from which the table shows the Size column
MODIFIED_FROM :: 520 // and the Modified column
SEARCH_W :: 200 // the search box, open
TITLE_MIN :: 72 // narrower than this, the folder's name leaves the toolbar
PATH_H :: 28 // the path bar, pinned under the content
STATUS_H :: 24 // the status line under it
ACTIVITY_SHARE :: 0.4 // the most of the content's height the activity may take
PREVIEW :: 200 // in the details card
DETAILS :: 300
SIDEBAR :: 240 // the sidebar's width until it is dragged
SIDEBAR_MIN :: 160 // narrower than this, a drag collapses it
CONTENT_MIN :: 360 // the sidebar is never dragged wider than leaves the content this
HANDLE_W :: 6 // the sidebar's resize handle, inside its trailing edge
TOOLBAR_H :: 44
HISTORY :: 64 // folders remembered for back and forward
SEP :: filepath.SEPARATOR_STRING

Column :: enum u8 {
	Name,
	Size,
	Modified,
}

Model :: struct {
	theme:        fluent.Theme,
	scheme:       fluent.Scheme,
	path:         [common.MAX_PATH]u8, // the folder shown
	path_len:     int,
	// The folders visited, with the one shown at history_at: back and
	// forward walk it, and a new folder cuts off what was forward.
	history:      [HISTORY][common.MAX_PATH]u8,
	history_lens: [HISTORY]int,
	history_n:    int,
	history_at:   int,
	shown:        [common.MAX_PATH]u8, // the folder whose listing was drawn last; see listing_of
	shown_len:    int,
	waiting:      f64,
	list:         ui.List_State,
	selected:     [common.MAX_PATH]u8, // the entry selected, by path, so it survives a sort
	selected_len: int,
	search:       ui.Text_State,
	sort:         [Column]fluent.Sort_Direction,
	window:       ops.Size,
	clip:         [common.MAX_PATH]u8, // what Copy or Cut took, for Paste
	clip_len:     int,
	clip_mode:    files.Mode,
	renaming:     bool, // the rename bar edits the selected entry's name
	new_name:     ui.Text_State,
	sidebar_off:  bool, // hidden by the toolbar's toggle or a drag, at a width it would fit
	sidebar_w:    f32, // the width dragged to, 0 for SIDEBAR
	folding:      bool, // a drag has taken the sidebar below SIDEBAR_MIN: it lets go collapsed
	sidebar_over: bool, // shown over the content, at a width it would not fit
	search_open:  bool, // the search box opened from its button
	search_held:  bool, // and since then it has had focus
	more_open:    bool, // the toolbar's overflow menu
	crumb_hover:  int, // the path bar's crumb under the pointer last frame, -1 for none
	// The context menu: open, for which entry ("" for the folder shown),
	// and where, in the coordinates of what opened it.
	menu_open:    bool,
	menu_for:     [common.MAX_PATH]u8,
	menu_for_len: int,
	menu_at:      ops.Point,
	menu_drawn:   bool, // this frame: an open menu its row did not draw, scrolled away, closes
	// This frame's, for the rows: the listing, the entries in order after
	// the sort and the search, and the open table.
	listing:      ^query.Listing_Result,
	order:        []int,
	table:        fluent.Table,
	columns:      bit_set[Column],
	listing_w:    f32, // the content's width
}

model_init :: proc(m: ^Model, path: string) {
	m.sort[.Name] = .Ascending
	m.crumb_hover = -1
	navigate(m, path)
}

model_destroy :: proc(m: ^Model) {
	ui.text_destroy(&m.search)
	ui.text_destroy(&m.new_name)
}

// navigate makes path the folder shown, from its top, with nothing
// selected and no search, and remembers it: what was forward is gone.
navigate :: proc(m: ^Model, path: string) {
	if m.history_n > 0 {
		m.history_n = m.history_at + 1
	}
	if m.history_n == HISTORY {
		copy(m.history[:], m.history[1:])
		copy(m.history_lens[:], m.history_lens[1:])
		m.history_n -= 1
	}
	m.history_lens[m.history_n] = copy(m.history[m.history_n][:], path)
	m.history_at = m.history_n
	m.history_n += 1
	show(m, path)
}

// show makes path the folder shown without touching the history.
@(private)
show :: proc(m: ^Model, path: string) {
	m.path_len = copy(m.path[:], path)
	m.list.offset = 0
	m.selected_len = 0
	m.renaming = false
	ui.text_set(&m.search, "")
}

can_go_back :: proc(m: ^Model) -> bool {
	return m.history_at > 0
}

can_go_forward :: proc(m: ^Model) -> bool {
	return m.history_at + 1 < m.history_n
}

// go_back shows the folder visited before this one, as the mouse's back
// button, Alt with Left or the toolbar's button ask.
go_back :: proc(m: ^Model) {
	if can_go_back(m) {
		m.history_at -= 1
		show(m, string(m.history[m.history_at][:m.history_lens[m.history_at]]))
	}
}

go_forward :: proc(m: ^Model) {
	if can_go_forward(m) {
		m.history_at += 1
		show(m, string(m.history[m.history_at][:m.history_lens[m.history_at]]))
	}
}

path_of :: proc(m: ^Model) -> string {
	return string(m.path[:m.path_len])
}

selected_path :: proc(m: ^Model) -> string {
	return string(m.selected[:m.selected_len])
}

clip_path :: proc(m: ^Model) -> string {
	return string(m.clip[:m.clip_len])
}

view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Model)(user)
	m.scheme = fluent.theme_scheme(m.theme)
	fluent.use(&m.scheme, fluent.mode_of(m.theme))
	fluent.use_fonts({0, 1, 2})
	s := &m.scheme
	m.window = gtx.constraints.max
	ops.fill(gtx.scene, ops.Rect{0, 0, m.window.x, m.window.y}, s[.Neutral_Background2])

	// Back and forward, from the mouse's side buttons or Alt with an
	// arrow, wherever the pointer is: keys the frame asks for app-wide.
	nav := ui.claim_id(gtx)
	ui.key_interest(gtx, nav, .Browser_Back)
	ui.key_interest(gtx, nav, .Browser_Forward)
	ui.key_interest(gtx, nav, .Left, {.Alt})
	ui.key_interest(gtx, nav, .Right, {.Alt})
	for e in ui.events(gtx, nav) {
		if e.kind != .Key {
			continue
		}
		#partial switch e.key {
		case .Browser_Back:
			go_back(m)
		case .Browser_Forward:
			go_forward(m)
		case .Left:
			go_back(m)
		case .Right:
			go_forward(m)
		}
	}

	lay := layout_of(m)
	m.menu_drawn = false
	defer if m.menu_open && !m.menu_drawn {
		m.menu_open = false
	}
	ui.column(gtx, align = .Fill)
	toolbar(gtx, m, lay)
	listing, have, loading := listing_of(gtx, m)
	m.listing = listing
	body_h := max(m.window.y - TOOLBAR_H, 0)
	ui.row(gtx, align = .Fill)
	if lay.sidebar {
		sidebar(gtx, m, body_h, lay.sidebar_w)
	}
	content(gtx, m, lay, body_h, listing, have, loading)
	if lay.details {
		fluent.divider(gtx, vertical = true)
		details(gtx, m, listing if have else nil)
	}
	// At a width the sidebar does not fit, its toggle shows it over the
	// content, as a drawer.
	if !lay.sidebar && m.sidebar_over {
		if fluent.nav(gtx, &m.sidebar_over, m.window, width = min(sidebar_width(m), m.window.x - 48)) {
			sidebar_rows(gtx, m)
		}
	}
}

// Layout is what fits at the window's width: the frame's plan, made
// before anything is drawn, so every width lays out whole.
Layout :: struct {
	sidebar:   bool, // beside the content
	sidebar_w: f32,
	details:   bool,
	content_w: f32,
	columns:   bit_set[Column],
}

layout_of :: proc(m: ^Model) -> (lay: Layout) {
	w := m.window.x
	lay.sidebar = !m.sidebar_off && w >= SIDEBAR_FROM
	if lay.sidebar {
		m.sidebar_over = false
		// The width dragged to, as far as the window allows: narrowing the
		// window narrows the sidebar, but never changes the width chosen.
		lay.sidebar_w = HANDLE_W if m.folding else clamp(sidebar_width(m), SIDEBAR_MIN, w - CONTENT_MIN)
	}
	rest := w - lay.sidebar_w
	lay.details = rest >= DETAILS_FROM
	lay.content_w = rest - (DETAILS + 1 if lay.details else 0)
	lay.columns = {.Name}
	if lay.content_w >= SIZE_FROM {
		lay.columns += {.Size}
	}
	if lay.content_w >= MODIFIED_FROM {
		lay.columns += {.Modified}
	}
	return
}

// content is the folder's side of the body: the rename bar and the
// activity over the table, and the path bar and status line pinned
// under them. The table's region is given its height exactly, so the
// bars sit at the bottom from the first frame.
@(private)
content :: proc(gtx: ^ui.Ctx, m: ^Model, lay: Layout, h: f32, listing: ^query.Listing_Result, have, loading: bool) {
	w := lay.content_w
	m.listing_w = w
	ui.sized(gtx, {min = {w, h}, max = {w, h}})
	ui.column(gtx, align = .Fill)
	{
		region := max(h - PATH_H - STATUS_H, 0)
		ui.sized(gtx, {min = {w, region}, max = {w, region}})
		ui.clip_box(gtx)
		// Behind everything in the region, so the rows' own areas are on
		// top of it: what a click on no entry reaches.
		ui.stack(gtx)
		background(gtx, m, w, region)
		ui.column(gtx, align = .Fill)
		rename_bar(gtx, m, listing if have else nil)
		activity(gtx, m, region * ACTIVITY_SHARE)
		switch {
		case have && listing.error != "":
			ui.inset(gtx, ui.pad_all(16))
			fluent.message_bar(gtx, .Error, "", listing.error)
		case have:
			entries(gtx, m, listing, lay.columns)
		case loading:
			skeleton_rows(gtx, m)
		}
	}
	path_bar(gtx, m, w)
	status(gtx, m, listing, have, w)
}

// Action is a command on the folder or the selected entry the toolbar
// offers, in the order it shows them.
Action :: enum u8 {
	New_Folder,
	Rename,
	Copy,
	Cut,
	Paste,
	Trash,
	Undo,
}

@(private)
ACTION_LABELS := [Action]string{.New_Folder = "New folder", .Rename = "Rename", .Copy = "Copy", .Cut = "Cut", .Paste = "Paste", .Trash = "Move to Trash", .Undo = "Undo"}

@(private)
ACTION_ICONS := [Action]fluent.Icon{.New_Folder = .Add, .Rename = .Edit, .Copy = .Copy, .Cut = .None, .Paste = .Clipboard, .Trash = .Delete, .Undo = .None}

// KEPT is the order actions keep their place in the toolbar as it
// narrows: the last fold into the overflow menu first.
@(private)
KEPT := [len(Action)]Action{.New_Folder, .Trash, .Undo, .Paste, .Copy, .Cut, .Rename}

// toolbar is the top strip: the sidebar's toggle, back and forward, the
// folder's name, the actions that fit with an overflow menu for the
// rest, and search, a box when there is room and a button that opens
// one when there is not. Nothing in it is drawn wider than the window.
@(private)
toolbar :: proc(gtx: ^ui.Ctx, m: ^Model, lay: Layout) {
	s := &m.scheme
	// The strip's surface, at its own height: a painted box would take
	// the height it is offered, which here is the window's.
	ops.fill(gtx.scene, ops.Rect{0, 0, m.window.x, TOOLBAR_H}, s[.Neutral_Background1])
	ops.fill(gtx.scene, ops.Rect{0, TOOLBAR_H - 1, m.window.x, 1}, s[.Neutral_Stroke2])
	ui.sized(gtx, {min = {m.window.x, TOOLBAR_H}, max = {m.window.x, TOOLBAR_H}})
	ui.inset(gtx, {left = 8, right = 8, top = 6, bottom = 6})
	fluent.toolbar(gtx, .Small)
	if fluent.toolbar_button(gtx, "", .Navigation, name = "Sidebar") {
		if m.window.x >= SIDEBAR_FROM {
			m.sidebar_off = !m.sidebar_off
		} else {
			m.sidebar_over = !m.sidebar_over
		}
	}
	if fluent.toolbar_button(gtx, "", .Arrow_Left, name = "Back", state = .Live if can_go_back(m) else .Disabled) {
		go_back(m)
	}
	if fluent.toolbar_button(gtx, "", .Arrow_Right, name = "Forward", state = .Live if can_go_forward(m) else .Disabled) {
		go_forward(m)
	}
	// The room left for the rest: the window less this inset, the
	// toolbar's own padding, and the three buttons above.
	icon := fluent.button_size(gtx, "", .Add, .Small).x
	pad := fluent.toolbar_padding(.Small, false)
	room := m.window.x - 16 - pad.left - pad.right - 3 * icon
	fit := plan_toolbar(gtx, m, room, icon)
	if fit.title > 0 {
		if common.cell(gtx, fit.title, .Start) {
			fluent.text(gtx, folder_name(path_of(m)), s[.Neutral_Foreground1], .S300, .Semibold, width = fit.title - 8, truncate = true, selectable = false)
		}
	} else if fit.spare > 0 {
		ui.spacer(gtx, fit.spare)
	}
	undo := undo_label(gtx)
	for a in Action {
		if a in fit.shown && fluent.toolbar_button(gtx, ACTION_LABELS[a] if ACTION_ICONS[a] == .None else "", ACTION_ICONS[a], name = ACTION_LABELS[a], state = action_state(m, a, undo)) {
			act_on(gtx, m, a)
		}
	}
	more: ops.Area_Id
	if card(fit.shown) < len(Action) {
		ui.stack(gtx)
		if fluent.toolbar_button(gtx, "", .More_Horizontal, name = "More") {
			m.more_open = !m.more_open
		}
		more = ui.last_widget(gtx).id
		if fluent.menu(gtx, &m.more_open, {0, 0, 0, TOOLBAR_H - 12}, has_icons = true) {
			for a in Action {
				if a not_in fit.shown && fluent.menu_item(gtx, ACTION_LABELS[a], ACTION_ICONS[a], disabled = action_state(m, a, undo) == .Disabled, key = u64(a)) {
					act_on(gtx, m, a)
				}
			}
		}
	}
	search(gtx, m, fit.search_box, more)
}

// Toolbar_Fit is what the toolbar shows at its width.
Toolbar_Fit :: struct {
	shown:      bit_set[Action], // in the toolbar; the rest are in the overflow menu
	search_box: bool, // the search box, not its button
	title:      f32, // the width the folder's name has, 0 for none
	spare:      f32, // the width left, which pushes the tools to the end
}

// plan_toolbar decides what the toolbar shows in room points: search
// first, a box if it was opened or there is room for it beside every
// action, else its button; then the actions in the order they are kept,
// leaving room for the overflow button once one does not fit; then the
// folder's name in what is left.
plan_toolbar :: proc(gtx: ^ui.Ctx, m: ^Model, room: f32, icon: f32) -> (fit: Toolbar_Fit) {
	widths: [Action]f32
	all: f32
	for a in Action {
		widths[a] = fluent.button_size(gtx, ACTION_LABELS[a] if ACTION_ICONS[a] == .None else "", ACTION_ICONS[a], .Small).x
		all += widths[a]
	}
	open := m.search_open || ui.text_string(&m.search) != ""
	fit.search_box = open || room >= SEARCH_W + all + TITLE_MIN
	left := room - (SEARCH_W if fit.search_box else icon)
	for a, ii in KEPT {
		// Once what follows will not all fit, the overflow button must.
		need := widths[a]
		if widths[a] + sum_after(widths, KEPT[ii + 1:]) > left {
			need += icon
		}
		if need > left {
			break
		}
		fit.shown += {a}
		left -= widths[a]
	}
	if card(fit.shown) < len(Action) {
		left -= icon
	}
	if left >= TITLE_MIN {
		fit.title = left
	} else {
		fit.spare = max(left, 0)
	}
	return
}

@(private)
sum_after :: proc(widths: [Action]f32, rest: []Action) -> (total: f32) {
	for a in rest {
		total += widths[a]
	}
	return
}

// search is the search box, or the button that opens it. Opened, the box
// asks for focus until it has it; left empty after that, it folds back
// into its button, unless focus went to the overflow menu it filled. Focus
// moves at the next input, so nothing here counts frames.
@(private)
search :: proc(gtx: ^ui.Ctx, m: ^Model, box: bool, more: ops.Area_Id) {
	if !box {
		if fluent.toolbar_button(gtx, "", .Search, name = "Search") {
			m.search_open = true
			m.search_held = false
		}
		return
	}
	e := fluent.search_box(gtx, &m.search, "Search this folder", size = .Small, width = SEARCH_W, name = "Search")
	if !m.search_open {
		return
	}
	if e.focused {
		m.search_held = true
	} else if !m.search_held {
		ui.focus_request(gtx, e.id)
	} else if ui.text_string(&m.search) == "" && !m.more_open && (more == 0 || ui.focused(gtx) != more) {
		// Not while the overflow menu is open, or its button is being
		// pressed to open it: the room the box takes is what put the
		// actions there, and folding would take the button away under it.
		m.search_open = false
	}
}

// undo_label is what Undo would undo, "" for nothing.
@(private)
undo_label :: proc(gtx: ^ui.Ctx) -> string {
	act, status := ui.need(gtx, query.Activity{}, query.Activity_Result)
	return act.undo if status == .Ready || status == .Stale else ""
}

@(private)
action_state :: proc(m: ^Model, a: Action, undo: string) -> fluent.Interaction {
	switch a {
	case .New_Folder:
		return .Live
	case .Rename, .Copy, .Cut, .Trash:
		return .Live if m.selected_len > 0 else .Disabled
	case .Paste:
		return .Live if m.clip_len > 0 else .Disabled
	case .Undo:
		return .Live if undo != "" else .Disabled
	}
	return .Disabled
}

// act_on carries out an action. Each only asks: whether it can be done
// is the application's to find out, and a refusal comes back as a
// problem in the activity.
@(private)
act_on :: proc(gtx: ^ui.Ctx, m: ^Model, a: Action) {
	folder := path_of(m)
	selected := selected_path(m)
	switch a {
	case .New_Folder:
		ui.command(gtx, files.Command(files.New_Folder{parent = files.path_make(folder), name = files.name_make("New folder")}))
	case .Rename:
		start_rename(m)
	case .Copy:
		take(m, selected, .Copy)
	case .Cut:
		take(m, selected, .Move)
	case .Paste:
		paste_into(gtx, m, folder)
	case .Trash:
		ui.command(gtx, files.Command(files.Trash{path = files.path_make(selected)}))
		m.selected_len = 0
	case .Undo:
		ui.command(gtx, files.Command(files.Undo{}))
	}
}

// take remembers path for Paste, to copy or to move.
@(private)
take :: proc(m: ^Model, path: string, mode: files.Mode) {
	m.clip_len = copy(m.clip[:], path)
	m.clip_mode = mode
}

@(private)
start_rename :: proc(m: ^Model) {
	m.renaming = true
	ui.text_set(&m.new_name, filepath.base(selected_path(m)))
}

// activity is what the application is doing and what went wrong: each
// question a paste asks, with its answers; each copy under way, with its
// progress and a way to stop it; and each problem until dismissed. It
// takes at most max_h, scrolling past it, so the table always keeps the
// rest.
@(private)
activity :: proc(gtx: ^ui.Ctx, m: ^Model, max_h: f32) {
	act, status := ui.need(gtx, query.Activity{}, query.Activity_Result)
	if status != .Ready && status != .Stale || (len(act.operations) == 0 && len(act.problems) == 0) {
		return
	}
	s := &m.scheme
	ui.sized(gtx, {max = {ui.INF, max_h}})
	ui.scroll_box(gtx, fit = true)
	ui.inset(gtx, {left = 16, right = 16, top = 8, bottom = 8})
	ui.column(gtx, gap = 6, align = .Fill)
	for op in act.operations {
		ui.scope(gtx, op.id)
		if op.question != "" {
			picked, _ := fluent.message_bar(gtx, .Warning, op.label, op.question, actions = ANSWERS[:])
			if picked >= 0 {
				ui.command(gtx, files.Command(files.Resolve{op = op.id, choice = files.Choice(picked)}))
			}
			continue
		}
		ui.row(gtx, gap = 8, align = .Center)
		// The label and the bar share what the Stop button leaves.
		share := max(m.window.x * 0.25, 80)
		fluent.text(gtx, op.label, s[.Neutral_Foreground2], .S200, selectable = false, width = share, truncate = true)
		fraction: f32 = -1 // indeterminate until the bytes are counted
		if op.total > 0 {
			fraction = f32(op.done) / f32(op.total)
		}
		fluent.progress_bar(gtx, fraction, width = min(share, 160), name = op.label)
		if fluent.button(gtx, "Stop", .Subtle, size = .Small, name = "Stop") {
			ui.command(gtx, files.Command(files.Cancel{op = op.id}))
		}
	}
	for p in act.problems {
		ui.scope(gtx, p.id)
		_, dismissed := fluent.message_bar(gtx, .Error, "", p.message, dismissable = true)
		if dismissed {
			ui.command(gtx, files.Command(files.Dismiss{id = p.id}))
		}
	}
}

// ANSWERS are a paste's answers, in files.Choice's order.
@(private)
ANSWERS := [len(files.Choice)]string{int(files.Choice.Replace) = "Replace", int(files.Choice.Keep_Both) = "Keep both", int(files.Choice.Skip) = "Skip"}

// status is the line under the path bar: how many entries, how many
// match, and what the application is doing, cut to the content's width.
@(private)
status :: proc(gtx: ^ui.Ctx, m: ^Model, listing: ^query.Listing_Result, have: bool, w: f32) {
	s := &m.scheme
	ui.sized(gtx, {min = {w, STATUS_H}, max = {w, STATUS_H}})
	ui.inset(gtx, {left = 12, right = 12, top = 4})
	line: string
	if have && listing.error == "" {
		n := len(listing.entries)
		if ui.text_string(&m.search) != "" {
			line = fmt.tprintf("%d of %d items match", len(m.order), n)
		} else {
			line = fmt.tprintf("%d item%s", n, "" if n == 1 else "s")
		}
	}
	stats, status := ui.need(gtx, query.Stats{}, query.Stats_Result)
	if status == .Ready || status == .Stale {
		if stats.pending > 0 {
			line = fmt.tprintf("%s · %d thumbnail%s on the way", line, stats.pending, "" if stats.pending == 1 else "s")
		}
		line = fmt.tprintf("%s · %d open · %d folders read · %d thumbnails made · %d abandoned", line, stats.open, stats.listings, stats.thumbs, stats.cancelled)
	}
	fluent.text(gtx, line, s[.Neutral_Foreground3], .S200, selectable = false, width = max(w - 24, 0), truncate = true)
}

// path_bar is the folder's path, pinned under the content as the
// Finder's is: a crumb per folder from the root, each its icon and
// name. When they do not all fit, crumbs from the root fold to their
// icon; a folded crumb shows its name while the pointer is on it, the
// crumbs after it, not before, making room, so it stays under the
// pointer. A click goes to that folder.
@(private)
path_bar :: proc(gtx: ^ui.Ctx, m: ^Model, w: f32) {
	s := &m.scheme
	ops.fill(gtx.scene, ops.Rect{0, 0, w, 1}, s[.Neutral_Stroke2])
	ui.sized(gtx, {min = {w, PATH_H}, max = {w, PATH_H}})
	ui.clip_box(gtx)
	ui.inset(gtx, {left = 6, right = 6, top = 2})
	ui.row(gtx, align = .Center)
	crumbs := crumbs_of(path_of(m), gtx.allocator)
	n := len(crumbs)
	if n == 0 {
		return
	}
	full := make([]bool, n, gtx.allocator)
	fold_crumbs(gtx, crumbs, full, m.crumb_hover, w - 12)
	hovered := -1
	for c, ii in crumbs {
		if ii > 0 {
			fluent.breadcrumb_divider(gtx, .Small, key = u64(1000 + ii))
		}
		label := crumb_label(c) if full[ii] else ""
		if fluent.breadcrumb_button(gtx, label, crumb_icon(m, crumbs, ii), .Small, current = ii == n - 1, name = crumb_label(c), key = u64(ii)) {
			navigate(m, crumb_path(crumbs, ii, gtx.allocator))
		}
		if ui.widget_state(gtx, ui.last_widget(gtx).id).hovered {
			hovered = ii
		}
	}
	if hovered != m.crumb_hover {
		m.crumb_hover = hovered
		ui.request_frame(gtx, 0)
	}
}

// fold_crumbs decides which crumbs show their name in room points: all,
// if they fit; else crumbs fold to their icon from the root on, never the
// last, the folder shown. A hovered crumb keeps its name, and the room it
// takes comes from the crumbs after it, so nothing before it moves.
@(private)
fold_crumbs :: proc(gtx: ^ui.Ctx, crumbs: []string, full: []bool, hover: int, room: f32) {
	n := len(crumbs)
	named := make([]f32, n, context.temp_allocator)
	folded := make([]f32, n, context.temp_allocator)
	total := f32(n - 1) * fluent.breadcrumb_divider_size(.Small).x
	for c, ii in crumbs {
		current := ii == n - 1
		named[ii] = fluent.breadcrumb_button_size(gtx, crumb_label(c), .Folder, .Small, current).x
		folded[ii] = fluent.breadcrumb_button_size(gtx, "", .Folder, .Small, current).x
		full[ii] = true
		total += named[ii]
	}
	// Without the hover: fold from the root until it fits.
	at_rest := make([]bool, n, context.temp_allocator)
	copy(at_rest, full)
	rest_total := total
	for ii := 0; ii < n - 1 && rest_total > room; ii += 1 {
		at_rest[ii] = false
		rest_total -= named[ii] - folded[ii]
	}
	copy(full, at_rest)
	if hover < 0 || hover >= n || at_rest[hover] {
		return
	}
	// The hovered crumb opens; the crumbs after it fold to pay for it.
	full[hover] = true
	over := rest_total + named[hover] - folded[hover] - room
	for ii := hover + 1; ii < n - 1 && over > 0; ii += 1 {
		if full[ii] {
			full[ii] = false
			over -= named[ii] - folded[ii]
		}
	}
}

@(private)
crumb_label :: proc(c: string) -> string {
	return "Computer" if c == SEP else c
}

@(private)
crumb_icon :: proc(m: ^Model, crumbs: []string, ii: int) -> fluent.Icon {
	if ii == 0 && crumbs[0] == SEP {
		return .Grid
	}
	return .Folder
}

// rename_bar edits the selected entry's name, over the table at any
// width: Enter asks the application to rename it, Cancel leaves it as it
// is.
@(private)
rename_bar :: proc(gtx: ^ui.Ctx, m: ^Model, listing: ^query.Listing_Result) {
	if !m.renaming {
		return
	}
	e, have := selected_entry(m, listing)
	if !have {
		m.renaming = false
		return
	}
	s := &m.scheme
	ui.inset(gtx, {left = 16, right = 16, top = 8, bottom = 4})
	ui.row(gtx, gap = 8, align = .Center)
	fluent.text(gtx, "Rename to", s[.Neutral_Foreground2], .S200, selectable = false)
	field := max(min(m.listing_w - 32 - 72 - 72 - 24, 320), 120)
	edit := fluent.input(gtx, &m.new_name, "Name", size = .Small, width = field, name = "New name")
	if edit.submitted {
		ui.command(gtx, files.Command(files.Rename{path = files.path_make(e.path), name = files.name_make(ui.text_string(&m.new_name))}))
		m.renaming = false
	}
	if fluent.button(gtx, "Cancel", .Subtle, size = .Small, name = "Cancel rename") {
		m.renaming = false
	}
}

// listing_of is the listing to draw: the folder shown once it has
// arrived, and until then the last one drawn, which stays needed so it
// is not released under us. A wait is reported only once it has lasted
// common.LOADING_DELAY, with a frame asked for at the deadline.
@(private)
listing_of :: proc(gtx: ^ui.Ctx, m: ^Model) -> (listing: ^query.Listing_Result, ok: bool, loading: bool) {
	now, status := ui.need(gtx, query.Listing{path = path_of(m)}, query.Listing_Result)
	if status == .Ready || status == .Stale {
		m.shown_len = copy(m.shown[:], path_of(m))
		m.waiting = 0
		return now, true, false
	}
	if m.waiting == 0 {
		m.waiting = gtx.time
	}
	waited := gtx.time - m.waiting
	if waited < common.LOADING_DELAY {
		ui.request_frame(gtx, f32(common.LOADING_DELAY - waited))
	} else {
		loading = true
	}
	shown := string(m.shown[:m.shown_len])
	if shown != "" && shown != path_of(m) {
		last, lstatus := ui.need(gtx, query.Listing{path = shown}, query.Listing_Result)
		if lstatus == .Ready || lstatus == .Stale {
			return last, true, loading
		}
	}
	return nil, false, loading
}

// entries is the table: a header that sorts, and the rows that match
// the search, in a virtual list so a large folder costs only its
// visible rows. columns are the ones the width has room for.
@(private)
entries :: proc(gtx: ^ui.Ctx, m: ^Model, listing: ^query.Listing_Result, columns: bit_set[Column]) {
	s := &m.scheme
	m.order = ordered(m, listing, gtx.allocator)
	m.columns = columns
	widths := make([dynamic]f32, gtx.allocator)
	for col in Column {
		if col in columns {
			append(&widths, COLUMN_WIDTHS[col])
		}
	}
	m.table = fluent.table_open(gtx, widths[:], .Medium)
	defer fluent.table_close(&m.table)
	h := fluent.table_header_open(gtx, &m.table)
	for col in Column {
		if col not_in columns {
			continue
		}
		before := m.sort[col]
		if fluent.table_header_cell(gtx, &h, COLUMN_NAMES[col], &m.sort[col], key = u64(col)) {
			for other in Column {
				if other != col {
					m.sort[other] = .None
				}
			}
			if before == .None {
				m.sort[col] = .Ascending
			}
		}
	}
	fluent.table_header_close(&h)
	if len(m.order) == 0 {
		ui.inset(gtx, ui.pad_all(24))
		fluent.text(gtx, "Nothing here" if ui.text_string(&m.search) == "" else "Nothing matches", s[.Neutral_Foreground3], selectable = false)
		return
	}
	ui.list(gtx, &m.list, len(m.order), row, m)
}

// COLUMN_WIDTHS are each column's width; the name takes what is left.
@(private)
COLUMN_WIDTHS := [Column]f32{.Name = 0, .Size = 110, .Modified = 130}

@(private)
COLUMN_NAMES := [Column]string{.Name = "Name", .Size = "Size", .Modified = "Modified"}


// ordered is the entries' indices after the search and the sort.
@(private)
ordered :: proc(m: ^Model, listing: ^query.Listing_Result, allocator := context.allocator) -> []int {
	query := strings.to_lower(ui.text_string(&m.search), allocator)
	out := make([dynamic]int, 0, len(listing.entries), allocator)
	for e, ii in listing.entries {
		if query == "" || strings.contains(strings.to_lower(e.name, allocator), query) {
			append(&out, ii)
		}
	}
	col, dir := Column.Name, fluent.Sort_Direction.Ascending
	for c in Column {
		if m.sort[c] != .None {
			col, dir = c, m.sort[c]
		}
	}
	Sorting :: struct {
		entries: []query.Entry,
		col:     Column,
		desc:    bool,
	}
	sorting := Sorting{listing.entries, col, dir == .Descending}
	context.user_ptr = &sorting
	slice.sort_by(out[:], proc(a, b: int) -> bool {
		so := (^Sorting)(context.user_ptr)
		x, y := so.entries[a], so.entries[b]
		if x.dir != y.dir {
			return x.dir // folders first, whatever the sort
		}
		less: bool
		switch so.col {
		case .Name:
			less = strings.compare(strings.to_lower(x.name, context.temp_allocator), strings.to_lower(y.name, context.temp_allocator)) < 0
		case .Size:
			less = x.size < y.size
		case .Modified:
			less = x.modified < y.modified
		}
		return less != so.desc
	})
	return out[:]
}

// row is one entry: its thumbnail or icon with its name, its size and
// its date, in a table row that selects on a click and acts on a
// double click.
@(private)
row :: proc(gtx: ^ui.Ctx, index: int, user: rawptr) {
	m := (^Model)(user)
	e := m.listing.entries[m.order[index]]
	ui.scope(gtx, e.path)
	selected := e.path == selected_path(m)
	clicked, double, asked := false, false, false
	at: ops.Point
	r := fluent.table_row_open(gtx, &m.table, &selected, &clicked, .Neutral, name = e.name, double_clicked = &double, context_clicked = &asked, context_at = &at)
	fluent.table_cell_layout(gtx, &r, e.name, media = media_of(gtx, e, THUMB))
	if .Size in m.columns {
		fluent.table_cell(gtx, &r, e.dir ? "" : size_text(e.size), color = m.scheme[.Neutral_Foreground3])
	}
	if .Modified in m.columns {
		fluent.table_cell(gtx, &r, date_text(e.modified), color = m.scheme[.Neutral_Foreground3])
	}
	fluent.table_row_close(&r)
	if clicked {
		m.selected_len = copy(m.selected[:], e.path)
	}
	if double {
		act(gtx, m, e)
	}
	// A right click selects the entry, as the Finder does, and opens its
	// menu under the pointer: the row's own coordinates are current here.
	if asked {
		m.selected_len = copy(m.selected[:], e.path)
		open_menu(m, e.path, at)
	}
	if m.menu_open && menu_for(m) == e.path {
		entry_menu(gtx, m, e)
	}
}

@(private)
open_menu :: proc(m: ^Model, path: string, at: ops.Point) {
	m.menu_open = true
	m.menu_for_len = copy(m.menu_for[:], path)
	m.menu_at = at
	m.more_open = false
}

@(private)
menu_for :: proc(m: ^Model) -> string {
	return string(m.menu_for[:m.menu_for_len])
}

// entry_menu is a file or folder's context menu: what can be done to it,
// grouped as the Finder groups them. Each item asks, as the toolbar's do.
@(private)
entry_menu :: proc(gtx: ^ui.Ctx, m: ^Model, e: query.Entry) {
	m.menu_drawn = true
	// The items go inside the if: a guard called in an if's condition
	// closes at the end of that if, so items after it would lie outside
	// the menu.
	if fluent.menu(gtx, &m.menu_open, {m.menu_at.x, m.menu_at.y, 0, 0}, has_icons = true, key = 7) {
		if fluent.menu_item(gtx, "Open", .Open) {
			act(gtx, m, e)
		}
		fluent.menu_divider(gtx)
		if fluent.menu_item(gtx, "Cut") {
			take(m, e.path, .Move)
		}
		if fluent.menu_item(gtx, "Copy", .Copy) {
			take(m, e.path, .Copy)
		}
		if e.dir && fluent.menu_item(gtx, "Paste into folder", .Clipboard, disabled = m.clip_len == 0) {
			paste_into(gtx, m, e.path)
		}
		if fluent.menu_item(gtx, "Duplicate") {
			// A copy into the folder it is in: the application gives it a
			// free name beside it.
			ui.command(gtx, files.Command(files.Paste{source = files.path_make(e.path), dest = files.path_make(path_of(m)), mode = .Copy}))
		}
		if fluent.menu_item(gtx, "Rename", .Edit) {
			start_rename(m)
		}
		if fluent.menu_item(gtx, "Copy path", .Link) {
			ui.clipboard_write(gtx, e.path)
		}
		if e.dir {
			pinned := is_pinned(gtx, e.path)
			if fluent.menu_item(gtx, "Unpin from sidebar" if pinned else "Pin to sidebar", .Star) {
				if pinned {
					ui.command(gtx, files.Command(files.Unpin{path = files.path_make(e.path)}))
				} else {
					ui.command(gtx, files.Command(files.Pin{path = files.path_make(e.path), name = files.name_make(e.name)}))
				}
			}
		}
		fluent.menu_divider(gtx)
		if fluent.menu_item(gtx, "Move to Trash", .Delete) {
			ui.command(gtx, files.Command(files.Trash{path = files.path_make(e.path)}))
			m.selected_len = 0
		}
	}
}

// folder_menu is the context menu of the folder shown, for a right click
// on no entry: what can be made or put there.
@(private)
folder_menu :: proc(gtx: ^ui.Ctx, m: ^Model) {
	m.menu_drawn = true
	// The items go inside the if: a guard called in an if's condition
	// closes at the end of that if, so items after it would lie outside
	// the menu.
	if fluent.menu(gtx, &m.menu_open, {m.menu_at.x, m.menu_at.y, 0, 0}, has_icons = true, key = 8) {
		if fluent.menu_item(gtx, "New folder", .Add) {
			act_on(gtx, m, .New_Folder)
		}
		if fluent.menu_item(gtx, "Paste", .Clipboard, disabled = m.clip_len == 0) {
			act_on(gtx, m, .Paste)
		}
		fluent.menu_divider(gtx)
		if fluent.menu_item(gtx, "Copy path", .Link) {
			ui.clipboard_write(gtx, path_of(m))
		}
	}
}

// paste_into pastes what was copied or cut into folder.
@(private)
paste_into :: proc(gtx: ^ui.Ctx, m: ^Model, folder: string) {
	ui.command(gtx, files.Command(files.Paste{source = files.path_make(clip_path(m)), dest = files.path_make(folder), mode = m.clip_mode}))
	if m.clip_mode == .Move {
		m.clip_len = 0 // a cut is pasted once
	}
}

// is_pinned says whether folder is in the sidebar's pins.
@(private)
is_pinned :: proc(gtx: ^ui.Ctx, folder: string) -> bool {
	pins, status := ui.need(gtx, query.Pins{}, query.Pins_Result)
	if status != .Ready && status != .Stale {
		return false
	}
	for pl in pins.items {
		if pl.path == folder {
			return true
		}
	}
	return false
}

// background is the table's region behind the rows: a left click there
// clears the selection, a right click opens the folder's menu.
@(private)
background :: proc(gtx: ^ui.Ctx, m: ^Model, w, h: f32) {
	p := ui.widget_open(gtx, 9)
	for e in ui.events(gtx, p.id) {
		if e.kind != .Press {
			continue
		}
		if fluent.context_press(e) {
			m.selected_len = 0
			open_menu(m, "", e.pos)
		} else if e.button == .Left {
			m.selected_len = 0
			m.renaming = false
		}
	}
	ops.input_area(gtx.scene, p.id, ops.Rect{0, 0, w, h}, {.Press, .Release})
	if m.menu_open && m.menu_for_len == 0 {
		folder_menu(gtx, m)
	}
	ui.widget_close(gtx, &p, {size = {w, h}})
}

// act enters a folder or opens a file, and tells the application it was
// visited, for the sidebar's Recent.
@(private)
act :: proc(gtx: ^ui.Ctx, m: ^Model, e: query.Entry) {
	visit(gtx, m, e.path, e.name, e.dir)
}

// visit is navigate or Open, as a Visited the application remembers
// for Recent, unless the place is a well-known one, which Recent never
// lists.
@(private)
visit :: proc(gtx: ^ui.Ctx, m: ^Model, path, name: string, dir: bool) {
	m.sidebar_over = false
	if dir {
		navigate(m, path)
	} else {
		ui.command(gtx, files.Command(files.Open{path = files.path_make(path)}))
	}
	if !well_known(gtx, path) {
		ui.command(gtx, files.Command(files.Visited{path = files.path_make(path), name = files.name_make(name), dir = dir}))
	}
}

// well_known says whether path is one of the sidebar's Places.
@(private)
well_known :: proc(gtx: ^ui.Ctx, path: string) -> bool {
	places, status := ui.need(gtx, query.Places{}, query.Places_Result)
	if status != .Ready && status != .Stale {
		return false
	}
	for pl in places.items {
		if pl.path == path {
			return true
		}
	}
	return false
}

// sidebar is the nav on the left: the standard places, the folders
// pinned, with a row that pins or unpins the folder shown, and the
// places visited lately. Each list is a need the application keeps
// fresh from its store.
@(private)
sidebar :: proc(gtx: ^ui.Ctx, m: ^Model, h, w: f32) {
	ui.sized(gtx, {min = {w, h}, max = {w, h}})
	ui.stack(gtx)
	// Dragged below its minimum, the sidebar shows collapsed while the drag
	// lasts: only the handle stays, so the drag can bring it back.
	if !m.folding {
		if fluent.nav(gtx, width = w) {
			sidebar_rows(gtx, m)
		}
	}
	sidebar_handle(gtx, m, w, h)
}

// sidebar_width is the width chosen for the sidebar.
sidebar_width :: proc(m: ^Model) -> f32 {
	return m.sidebar_w if m.sidebar_w > 0 else SIDEBAR
}

// Handle_Drag is a drag of the sidebar's handle: the width it began at
// and how far the pointer has gone since.
@(private)
Handle_Drag :: struct {
	dragging: bool,
	start:    f32,
	pull:     f32,
}

// sidebar_handle is the sidebar's trailing edge, dragged to set its width
// from SIDEBAR_MIN up to what leaves the content CONTENT_MIN. Dragged
// below the minimum, the sidebar folds away; let go there, it stays
// collapsed and the toggle brings it back at the width it had. A double
// click restores the default; with focus, the arrows step it.
@(private)
sidebar_handle :: proc(gtx: ^ui.Ctx, m: ^Model, w, h: f32) {
	p := ui.widget_open(gtx, 1)
	area := ops.Rect{w - HANDLE_W, 0, HANDLE_W, h}
	c := design.control(gtx, p.id, area, .Live)
	drag := ui.widget_data(gtx, p.id, Handle_Drag)
	most := m.window.x - CONTENT_MIN
	before := sidebar_width(m)
	for e in ui.events(gtx, p.id) {
		#partial switch e.kind {
		case .Press:
			if e.clicks >= 2 {
				m.sidebar_w = 0
				continue
			}
			drag^ = {dragging = true, start = w}
		case .Move:
			if !drag.dragging || !c.pressed {
				continue
			}
			drag.pull += e.travel.x
			wanted := drag.start + drag.pull
			m.folding = wanted < SIDEBAR_MIN
			if !m.folding {
				m.sidebar_w = clamp(wanted, SIDEBAR_MIN, most)
			}
		case .Release, .Cancel:
			if drag.dragging && m.folding {
				m.sidebar_off = true
				m.sidebar_w = drag.start
			}
			m.folding = false
			drag.dragging = false
			m.sidebar_w = f32(int(m.sidebar_w + 0.5))
		case .Key:
			#partial switch e.key {
			case .Left:
				m.sidebar_w = clamp(sidebar_width(m) - 16, SIDEBAR_MIN, most)
			case .Right:
				m.sidebar_w = clamp(sidebar_width(m) + 16, SIDEBAR_MIN, most)
			}
		}
	}
	if sidebar_width(m) != before || m.folding != (w == HANDLE_W) {
		ui.request_frame(gtx, 0) // laid out at the old width
	}
	s := &m.scheme
	if drag.dragging || c.hovered {
		ops.fill(gtx.scene, ops.Rect{w - 2, 0, 2, h}, s[.Brand_Stroke1] if drag.dragging else s[.Neutral_Stroke1])
	}
	design.listen(gtx, c.st, p.id, area, design.CLICK_KINDS, .Resize_EW)
	ops.tag(gtx.scene, p.id, "Resize sidebar")
	ui.semantics(gtx, &p, {role = .Slider, label = "Resize sidebar", value = fmt.tprintf("%d points", int(w))})
	ui.widget_close(gtx, &p, {size = {w, h}})
}

// sidebar_rows are the sidebar's rows, beside the content or over it. A
// visit from the drawer closes it.
@(private)
sidebar_rows :: proc(gtx: ^ui.Ctx, m: ^Model) {
	// The rows scroll when they are taller than the window, as Fluent's
	// NavDrawerBody does.
	fluent.nav_body(gtx)
	current := path_of(m)
	fluent.nav_section_header(gtx, "Places")
	if places, status := ui.need(gtx, query.Places{}, query.Places_Result); status == .Ready || status == .Stale {
		for pl in places.items {
			ui.scope(gtx, pl.path)
			ic: fluent.Icon = .Folder
			switch pl.name {
			case "Home":
				ic = .Home
			case "Pictures":
				ic = .Image
			}
			if fluent.nav_item(gtx, pl.name, pl.path, &current, ic) {
				visit(gtx, m, pl.path, pl.name, true)
			}
		}
	}
	fluent.nav_section_header(gtx, "Quick access")
	pinned := false
	if pins, status := ui.need(gtx, query.Pins{}, query.Pins_Result); status == .Ready || status == .Stale {
		for pl in pins.items {
			ui.scope(gtx, pl.path)
			if pl.path == current {
				pinned = true
			}
			if fluent.nav_item(gtx, pl.name, pl.path, &current, .Star) {
				visit(gtx, m, pl.path, pl.name, true)
			}
		}
	}
	none: string
	if pinned {
		if fluent.nav_item(gtx, "Unpin this folder", "", &none, .Dismiss, key = 1) {
			ui.command(gtx, files.Command(files.Unpin{path = files.path_make(current)}))
		}
	} else if fluent.nav_item(gtx, "Pin this folder", "", &none, .Add, key = 2) {
		ui.command(gtx, files.Command(files.Pin{path = files.path_make(current), name = files.name_make(folder_name(current))}))
	}
	// Recent is the snapshot the application took when the sidebar first
	// asked, less the well-known places, which have rows of their own.
	fluent.nav_section_header(gtx, "Recent")
	if recent, status := ui.need(gtx, query.Recent_Places{}, query.Recent_Places_Result); status == .Ready || status == .Stale {
		for pl in recent.items {
			if well_known(gtx, pl.path) {
				continue
			}
			ui.scope(gtx, pl.path)
			if fluent.nav_item(gtx, pl.name, pl.path, &current, .Folder if pl.dir else .Document) {
				visit(gtx, m, pl.path, pl.name, pl.dir)
			}
		}
	}
}

// folder_name is what a folder is called in the sidebar: its last part,
// or the path itself at the root.
folder_name :: proc(path: string) -> string {
	crumbs := crumbs_of(path, context.temp_allocator)
	return crumbs[len(crumbs) - 1] if len(crumbs) > 0 else path
}

// media_of is the entry's picture at px, needed while the row is in
// view, or its icon until it comes.
@(private)
media_of :: proc(gtx: ^ui.Ctx, e: query.Entry, px: f32) -> fluent.Cell_Media {
	if e.image {
		if thumb, status := ui.need(gtx, query.Thumb{path = e.path, px = int(px)}, query.Thumb_Result); status == .Ready || status == .Stale {
			return {image = ops.add_image(gtx.scene, thumb.image), has_image = true, size = px}
		}
		return {icon = .Image, size = px}
	}
	return {icon = .Folder if e.dir else .Document, size = px}
}

// skeleton_rows stand in for a listing still on its way.
@(private)
skeleton_rows :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.inset(gtx, {left = 16, right = 16, top = 8, bottom = 8})
	ui.column(gtx, gap = 12, align = .Fill)
	for ii in 0 ..< 6 {
		fluent.skeleton_item(gtx, 32, .Rectangle, key = u64(ii))
	}
}

// details is the card on the right: the selected entry's picture large,
// its name and facts, and a button that acts on it.
@(private)
details :: proc(gtx: ^ui.Ctx, m: ^Model, listing: ^query.Listing_Result) {
	s := &m.scheme
	ui.sized(gtx, {min = {DETAILS, 0}, max = {DETAILS, ui.INF}})
	ui.inset(gtx, ui.pad_all(16))
	e, have := selected_entry(m, listing)
	if !have {
		ui.column(gtx, align = .Center)
		ui.spacer(gtx, 48)
		fluent.text(gtx, "Select an item to see its details", s[.Neutral_Foreground3], .S200, selectable = false)
		return
	}
	// The card sits at the top of the pane at its content's height: a
	// painted box takes what it is offered, so it is offered no height.
	ui.column(gtx, align = .Fill)
	fluent.card(gtx, .Filled, .Medium)
	ui.column(gtx, gap = 12, align = .Center)
	preview(gtx, m, e)
	fluent.text(gtx, e.name, s[.Neutral_Foreground1], .S400, .Semibold, width = DETAILS - 64, truncate = true, selectable = false)
	facts := ui.column_open(gtx, gap = 4, align = .Fill)
	fact(gtx, m, "Kind", e.dir ? "Folder" : (e.image ? "Picture" : "File"))
	if !e.dir {
		fact(gtx, m, "Size", size_text(e.size))
	}
	fact(gtx, m, "Modified", date_text(e.modified))
	ui.close(&facts)
	if common.cell(gtx, DETAILS - 64, .Center) {
		ui.row(gtx, gap = 8)
		if fluent.button(gtx, e.dir ? "Open folder" : "Open", .Primary, .Open, .Small, name = "Open") {
			act(gtx, m, e)
		}
		if !m.renaming && fluent.button(gtx, "Rename", .Secondary, .Edit, .Small) {
			start_rename(m)
		}
	}
}

@(private)
fact :: proc(gtx: ^ui.Ctx, m: ^Model, label, value: string) {
	s := &m.scheme
	ui.row(gtx, align = .Baseline)
	if common.cell(gtx, 80, .Start) {
		fluent.text(gtx, label, s[.Neutral_Foreground3], .S200, selectable = false)
	}
	if common.cell(gtx, DETAILS - 64 - 80, .Start) {
		fluent.text(gtx, value, s[.Neutral_Foreground1], .S200, selectable = false, truncate = true)
	}
}

// preview is the selected picture at PREVIEW, a need of its own, or
// the entry's icon large.
@(private)
preview :: proc(gtx: ^ui.Ctx, m: ^Model, e: query.Entry) {
	s := &m.scheme
	ui.sized(gtx, {min = {PREVIEW, PREVIEW}, max = {PREVIEW, PREVIEW}})
	if e.image {
		if thumb, status := ui.need(gtx, query.Thumb{path = e.path, px = PREVIEW}, query.Thumb_Result); status == .Ready || status == .Stale {
			id := ops.add_image(gtx.scene, thumb.image)
			ops.clip_push(gtx.scene, ops.Round_Rect{{0, 0, PREVIEW, PREVIEW}, 8})
			ops.image(gtx.scene, id, ops.Rect{0, 0, PREVIEW, PREVIEW})
			ops.clip_pop(gtx.scene)
			return
		}
		fluent.skeleton_item(gtx, PREVIEW, .Square)
		return
	}
	fluent.icon(gtx, e.dir ? .Folder : .Document, {(PREVIEW - 96) / 2, (PREVIEW - 96) / 2}, 96, s[.Neutral_Foreground3])
}

@(private)
selected_entry :: proc(m: ^Model, listing: ^query.Listing_Result) -> (e: query.Entry, ok: bool) {
	if listing == nil || m.selected_len == 0 {
		return
	}
	for entry in listing.entries {
		if entry.path == selected_path(m) {
			return entry, true
		}
	}
	return
}

// crumbs_of is the path as its components, the root first.
crumbs_of :: proc(path: string, allocator := context.allocator) -> []string {
	out := make([dynamic]string, allocator)
	if strings.has_prefix(path, SEP) {
		append(&out, SEP)
	}
	for part in strings.split(path, SEP, allocator) {
		if part != "" {
			append(&out, part)
		}
	}
	return out[:]
}

// crumb_path is the path down to crumb index.
crumb_path :: proc(crumbs: []string, index: int, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	for c, ii in crumbs[:index + 1] {
		if c == SEP {
			strings.write_string(&b, SEP)
			continue
		}
		if ii > 0 && crumbs[ii - 1] != SEP {
			strings.write_string(&b, SEP)
		}
		strings.write_string(&b, c)
	}
	return strings.to_string(b)
}



@(private)
size_text :: proc(size: i64) -> string {
	switch {
	case size >= 1 << 30:
		return fmt.tprintf("%.1f GB", f64(size) / (1 << 30))
	case size >= 1 << 20:
		return fmt.tprintf("%.1f MB", f64(size) / (1 << 20))
	case size >= 1 << 10:
		return fmt.tprintf("%d KB", size / (1 << 10))
	}
	return fmt.tprintf("%d B", size)
}

@(private)
date_text :: proc(unix: i64) -> string {
	year, month, day := time.date(time.unix(unix, 0))
	return fmt.tprintf("%04d-%02d-%02d", year, int(month), day)
}
