package files_view

import "core:fmt"
import "core:testing"

import "jm:ui"
import "jm:ui/ops"
import "jm:ui/fluent"

import "../files"
import "../query"

// command_of decodes a frame's command as the host does; nil if it is
// not a files.Command.
@(private = "file")
command_of :: proc(c: ui.Command) -> files.Command {
	cmd, _ := ui.command_as(c, files.Command)
	return cmd
}

@(private = "file")
fixture_entries :: []query.Entry {
	{name = "docs", path = "/home/me/docs", dir = true},
	{name = "cat.png", path = "/home/me/cat.png", image = true, size = 2048},
	{name = "notes.txt", path = "/home/me/notes.txt", size = 100},
}

@(private = "file")
open :: proc(m: ^Model) -> ui.Probe {
	model_init(m, "/home/me")
	p: ui.Probe
	ui.probe_init(&p, view, m, {1200, 600})
	return p
}

@(private = "file")
double_click :: proc(p: ^ui.Probe, name: string) -> bool {
	c, ok := ui.probe_center(p, name)
	if !ok {
		return false
	}
	// The press is the double click; the frame that routes it is the one
	// whose commands are read, so the release waits for the caller's
	// next frame.
	ui.router_push(&p.router, {kind = .Move, pos = c})
	ui.router_push(&p.router, {kind = .Press, pos = c, button = .Left, clicks = 2})
	ui.router_push(&p.router, {kind = .Release, pos = c, button = .Left})
	ui.probe_frame(p)
	return true
}

@(test)
the_folder_is_needed_and_its_entries_drawn_with_thumbnails_for_pictures :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := open(&m)
	defer ui.probe_destroy(&p)
	testing.expect(t, ui.probe_needs_q(&p, query.Listing{path = "/home/me"}))
	ui.probe_deliver(&p, query.Listing{path = "/home/me"}, query.Listing_Result{entries = fixture_entries})
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "docs"))
	testing.expect(t, ui.probe_tagged(&p, "cat.png"))
	testing.expect(t, ui.probe_needs_q(&p, query.Thumb{path = "/home/me/cat.png", px = THUMB}))
	testing.expect(t, !ui.probe_needs_q(&p, query.Thumb{path = "/home/me/notes.txt", px = THUMB}))
	ui.probe_deliver(&p, query.Thumb{path = "/home/me/cat.png", px = THUMB}, query.Thumb_Result{image = "/tmp/cat-thumb.bmp"})
	ui.probe_frame(&p)
	dump := ui.probe_dump(&p)
	defer delete(dump)
	testing.expect(t, strings_contains(dump, "image#0"), "the thumbnail is drawn")
	testing.expect(t, ui.probe_tagged(&p, "Name") && ui.probe_tagged(&p, "Size"), "the header's columns")
	testing.expect(t, !ui.probe_tagged(&p, "Open"), "no details until something is selected")
}

@(test)
a_click_selects_and_the_details_show_it_large :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := open(&m)
	defer ui.probe_destroy(&p)
	ui.probe_deliver(&p, query.Listing{path = "/home/me"}, query.Listing_Result{entries = fixture_entries})
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_click(&p, "cat.png"))
	ui.probe_frame(&p)
	testing.expect_value(t, selected_path(&m), "/home/me/cat.png")
	testing.expect(t, ui.probe_tagged(&p, "Open"))
	testing.expect(t, ui.probe_needs_q(&p, query.Thumb{path = "/home/me/cat.png", px = PREVIEW}))
	testing.expect(t, ui.probe_tagged(&p, "Picture"))
}

@(test)
the_header_sorts_and_the_search_filters :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := open(&m)
	defer ui.probe_destroy(&p)
	ui.probe_deliver(&p, query.Listing{path = "/home/me"}, query.Listing_Result{entries = fixture_entries})
	ui.probe_frame(&p)
	// The table's first column is weighted, so its first frame asks for
	// another, which the probe runs by hand.
	testing.expect(t, p.wants_frame)
	ui.probe_frame(&p)
	// By name: the folder first, then cat before notes.
	testing.expect(t, ui.probe_bounds(&p, "cat.png").y < ui.probe_bounds(&p, "notes.txt").y)
	// By size, descending on the second click: cat (2048) before notes (100), the folder still first.
	testing.expect(t, ui.probe_click(&p, "Size"))
	testing.expect(t, ui.probe_click(&p, "Size"))
	ui.probe_frame(&p)
	testing.expect_value(t, m.sort[.Size], fluent.Sort_Direction.Descending)
	testing.expect_value(t, m.sort[.Name], fluent.Sort_Direction.None)
	testing.expect(t, ui.probe_bounds(&p, "docs").y < ui.probe_bounds(&p, "cat.png").y)
	testing.expect(t, ui.probe_bounds(&p, "cat.png").y < ui.probe_bounds(&p, "notes.txt").y)
	// The search keeps what matches.
	testing.expect(t, ui.probe_click(&p, "Search"))
	ui.probe_type(&p, "note")
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "notes.txt"))
	testing.expect(t, !ui.probe_tagged(&p, "cat.png"))
	testing.expect_value(t, len(m.order), 1)
}

@(test)
a_double_click_enters_a_folder_or_opens_a_file :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := open(&m)
	defer ui.probe_destroy(&p)
	ui.probe_deliver(&p, query.Listing{path = "/home/me"}, query.Listing_Result{entries = fixture_entries})
	ui.probe_frame(&p)
	testing.expect(t, double_click(&p, "notes.txt"))
	cmds := ui.probe_commands(&p)
	testing.expect_value(t, len(cmds), 2) // Open, and the Visited the sidebar's Recent is kept from
	o, ok := command_of(cmds[0]).(files.Open)
	testing.expect(t, ok)
	testing.expect_value(t, files.path_of(&o.path), "/home/me/notes.txt")
	_, visited := command_of(cmds[1]).(files.Visited)
	testing.expect(t, visited)
	testing.expect_value(t, path_of(&m), "/home/me")

	testing.expect(t, double_click(&p, "docs"))
	testing.expect_value(t, path_of(&m), "/home/me/docs")
	v, vok := command_of(ui.probe_commands(&p)[0]).(files.Visited)
	testing.expect(t, vok && v.dir)
	testing.expect_value(t, files.name_of(&v.name), "docs")
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_needs_q(&p, query.Listing{path = "/home/me/docs"}))
	// The old listing stays drawn and needed until the new one lands.
	testing.expect(t, ui.probe_needs_q(&p, query.Listing{path = "/home/me"}))
	testing.expect(t, ui.probe_tagged(&p, "docs"))
	ui.probe_deliver(&p, query.Listing{path = "/home/me/docs"}, query.Listing_Result{entries = {{name = "a.txt", path = "/home/me/docs/a.txt"}}})
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "a.txt"))
	testing.expect(t, !ui.probe_tagged(&p, "cat.png"), "the old listing's rows are gone")
	testing.expect(t, !ui.probe_needs_q(&p, query.Listing{path = "/home/me"}))
}

@(test)
the_path_bar_goes_back_out :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := open(&m)
	defer ui.probe_destroy(&p)
	navigate(&m, "/home/me/docs/work")
	ui.probe_frame(&p)
	// The path bar, pinned under the content: a crumb per folder. (The
	// folder's own name is the toolbar's title too, so a parent is
	// looked up.)
	docs := ui.probe_bounds(&p, "docs")
	testing.expect(t, docs.y >= 600 - PATH_H - STATUS_H, "the path bar is at the bottom")
	testing.expect(t, docs.y + docs.h <= 600 - STATUS_H, "and above the status line")
	testing.expect(t, ui.probe_click(&p, "docs"))
	testing.expect_value(t, path_of(&m), "/home/me/docs")
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_click(&p, "Computer"))
	testing.expect_value(t, path_of(&m), "/")
	// Back walks the folders visited.
	testing.expect(t, ui.probe_click(&p, "Back"))
	testing.expect_value(t, path_of(&m), "/home/me/docs")
}

@(test)
an_unreadable_folder_shows_its_error :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := open(&m)
	defer ui.probe_destroy(&p)
	ui.probe_deliver(&p, query.Listing{path = "/home/me"}, query.Listing_Result{error = "cannot read /home/me: permission denied"})
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "cannot read /home/me: permission denied"))
}

@(private = "file")
strings_contains :: proc(s, sub: string) -> bool {
	for ii in 0 ..= len(s) - len(sub) {
		if s[ii:ii + len(sub)] == sub {
			return true
		}
	}
	return false
}

@(test)
back_and_forward_walk_the_folders_visited :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := open(&m)
	defer ui.probe_destroy(&p)
	testing.expect(t, !can_go_back(&m))
	navigate(&m, "/home/me/docs")
	navigate(&m, "/home/me/docs/work")
	ui.probe_frame(&p)
	testing.expect(t, can_go_back(&m) && !can_go_forward(&m))
	// The mouse's back button arrives as a key, from wherever the pointer is.
	ui.probe_key(&p, .Browser_Back)
	testing.expect_value(t, path_of(&m), "/home/me/docs")
	ui.probe_key(&p, .Left, {.Alt})
	testing.expect_value(t, path_of(&m), "/home/me")
	testing.expect(t, !can_go_back(&m) && can_go_forward(&m))
	ui.probe_key(&p, .Browser_Forward)
	testing.expect_value(t, path_of(&m), "/home/me/docs")
	// The toolbar's buttons do the same, and a new folder cuts the forward.
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_click(&p, "Forward"))
	testing.expect_value(t, path_of(&m), "/home/me/docs/work")
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_click(&p, "Back"))
	testing.expect_value(t, path_of(&m), "/home/me/docs")
	navigate(&m, "/tmp")
	testing.expect(t, !can_go_forward(&m))
	ui.probe_key(&p, .Browser_Forward)
	testing.expect_value(t, path_of(&m), "/tmp")
	ui.probe_key(&p, .Right, {.Alt})
	testing.expect_value(t, path_of(&m), "/tmp")
}

@(test)
the_sidebar_lists_places_pins_and_recent_and_pins_the_folder_shown :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := open(&m)
	defer ui.probe_destroy(&p)
	testing.expect(t, ui.probe_needs_q(&p, query.Places{}))
	testing.expect(t, ui.probe_needs_q(&p, query.Pins{}))
	testing.expect(t, ui.probe_needs_q(&p, query.Recent_Places{}))
	ui.probe_deliver(&p, query.Places{}, query.Places_Result{items = {{"Home", "/home/me", true}, {"Pictures", "/home/me/Pictures", true}}})
	ui.probe_deliver(&p, query.Pins{}, query.Pins_Result{items = {{"work", "/home/me/work", true}}})
	ui.probe_deliver(&p, query.Recent_Places{}, query.Recent_Places_Result{items = {{"cat.png", "/home/me/cat.png", false}, {"Pictures", "/home/me/Pictures", true}}})
	ui.probe_frame(&p)
	for name in ([]string{"Home", "Pictures", "work", "cat.png", "Pin this folder"}) {
		testing.expect(t, ui.probe_tagged(&p, name), name)
	}
	// A well-known place is not listed again under Recent: one Pictures row.
	hits := 0
	for n in ui.probe_names(&p) {
		if n == "Pictures" {
			hits += 1
		}
	}
	testing.expect_value(t, hits, 1)
	// Pinning the folder shown is a command; shown pinned, the row unpins.
	testing.expect(t, ui.probe_click(&p, "Pin this folder"))
	cmds := ui.probe_commands(&p)
	testing.expect_value(t, len(cmds), 1)
	pin, ok := command_of(cmds[0]).(files.Pin)
	testing.expect(t, ok)
	testing.expect_value(t, files.path_of(&pin.path), "/home/me")
	testing.expect_value(t, files.name_of(&pin.name), "me")
	ui.probe_deliver(&p, query.Pins{}, query.Pins_Result{items = {{"work", "/home/me/work", true}, {"me", "/home/me", true}}})
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "Unpin this folder"))
	// A place goes there with no visit to remember; a recent file opens
	// and is a visit.
	testing.expect(t, ui.probe_click(&p, "Pictures"))
	testing.expect_value(t, path_of(&m), "/home/me/Pictures")
	testing.expect_value(t, len(ui.probe_commands(&p)), 0)
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_click(&p, "cat.png"))
	cmds = ui.probe_commands(&p)
	testing.expect_value(t, len(cmds), 2)
	_, opens := command_of(cmds[0]).(files.Open)
	_, visits := command_of(cmds[1]).(files.Visited)
	testing.expect(t, opens && visits)
}

// More pins than the window is tall: the sidebar's rows scroll, under the
// pointer, while the table beside it stays put.
@(test)
the_sidebar_scrolls_when_its_rows_outgrow_the_window :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := open(&m)
	defer ui.probe_destroy(&p)
	pins := make([]query.Place, 40, context.temp_allocator)
	for &pl, ii in pins {
		name := fmt.tprintf("pin %02d", ii)
		pl = {name, fmt.tprintf("/home/me/%s", name), true}
	}
	ui.probe_deliver(&p, query.Listing{path = "/home/me"}, query.Listing_Result{entries = fixture_entries})
	ui.probe_deliver(&p, query.Pins{}, query.Pins_Result{items = pins})
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	before := ui.probe_bounds(&p, "pin 05")
	row := ui.probe_bounds(&p, "notes.txt")
	testing.expect(t, ui.probe_scroll(&p, "pin 05", 3))
	ui.probe_frame(&p)
	after := ui.probe_bounds(&p, "pin 05")
	testing.expect(t, after.y < before.y, "the sidebar's rows moved up")
	testing.expect_value(t, ui.probe_bounds(&p, "notes.txt"), row)
	// The last pin, below the window at first, can be scrolled to: scrolls
	// at one point in the sidebar until the rows stop moving.
	at := ops.Point{before.x + before.w / 2, before.y + before.h / 2}
	for _ in 0 ..< 20 {
		ui.router_push(&p.router, {kind = .Scroll, pos = at, scroll = {0, 3}})
		ui.probe_frame(&p)
	}
	last := ui.probe_bounds(&p, "pin 39")
	testing.expect(t, last.y + last.h <= 600 + 0.5, "the last pin is inside the window")
}

// --- every size the window can be ------------------------------------------------

// at_size is a frame of the view at size, with a folder deep enough that
// its path cannot fit a narrow window, an entry selected, and the
// sidebar's lists delivered.
@(private = "file")
at_size :: proc(m: ^Model, size: ops.Size) -> ui.Probe {
	model_init(m, "/home/me/projects/client/archive/2026/reports")
	p: ui.Probe
	ui.probe_init(&p, view, m, size)
	dir :: "/home/me/projects/client/archive/2026/reports"
	ui.probe_deliver(&p, query.Listing{path = dir}, query.Listing_Result{entries = {{name = "summary.txt", path = dir + "/summary.txt", size = 10}}})
	ui.probe_deliver(&p, query.Places{}, query.Places_Result{items = {{"Home", "/home/me", true}}})
	ui.probe_deliver(&p, query.Pins{}, query.Pins_Result{})
	ui.probe_deliver(&p, query.Recent_Places{}, query.Recent_Places_Result{})
	ui.probe_frame(&p)
	ui.probe_click(&p, "summary.txt")
	ui.probe_frame(&p)
	return p
}

// From the smallest window up, the toolbar never runs past the window's
// edge, and search, the overflow menu when actions are folded, the path
// bar and the status line are always there.
@(test)
every_width_lays_out_whole :: proc(t: ^testing.T) {
	for height in ([]f32{MIN_HEIGHT, 720}) {
		for width := f32(MIN_WIDTH); width <= 1600; width += 20 {
			m: Model
			p := at_size(&m, {width, height})
			// Every control in the toolbar, by its hit area (a tag carries no
			// bounds of its own), and at least the ones always there.
			f := ui.probe_current(&p)
			measured := 0
			for tg in f.tags {
				b := ui.probe_bounds(&p, tg.name)
				if b.w > 0 && b.y < TOOLBAR_H {
					measured += 1
					testing.expectf(t, b.x >= -0.5 && b.x + b.w <= width + 0.5, "%vx%v: %q at %v runs past the window", width, height, tg.name, b)
				}
			}
			testing.expectf(t, measured >= 5, "%vx%v: the toolbar's controls were measured (%d)", width, height, measured)
			for n in f.nodes {
				if n.rect.w > 0 && n.rect.y < TOOLBAR_H {
					testing.expectf(t, n.rect.x >= -0.5 && n.rect.x + n.rect.w <= width + 0.5, "%vx%v: %q at %v runs past the window", width, height, n.semantics.label, n.rect)
				}
			}
			search := ui.probe_bounds(&p, "Search")
			testing.expectf(t, search.w > 0 && search.x + search.w <= width + 0.5, "%vx%v: search is in the window, at %v", width, height, search)
			// Every action is in reach: a control in the toolbar, inside the
			// window, or an item in the overflow menu.
			folded: [dynamic]string
			defer delete(folded)
			for a in Action {
				b := node_bounds(&p, ACTION_LABELS[a])
				if !(b.w > 0 && b.y < TOOLBAR_H && b.x + b.w <= width + 0.5) {
					append(&folded, ACTION_LABELS[a])
					continue
				}
				// Shown, it has its whole size: a row squeezes what does
				// not fit rather than push it out, so a squeezed control
				// is one that should have folded.
				if ACTION_ICONS[a] != .None {
					testing.expectf(t, abs(b.w - b.h) < 0.5, "%vx%v: %q is squeezed to %v", width, height, ACTION_LABELS[a], b)
				} else {
					testing.expectf(t, b.w >= 30, "%vx%v: %q is squeezed to %v", width, height, ACTION_LABELS[a], b)
				}
			}
			// Open, the box's node is its field, a few points inside it.
			box := node_bounds(&p, "Search")
			testing.expectf(t, abs(box.w - box.h) < 0.5 || box.w >= SEARCH_W - 10, "%vx%v: search is squeezed to %v", width, height, box)
			if len(folded) > 0 {
				testing.expectf(t, ui.probe_click(&p, "More"), "%vx%v: %v are folded, so More is there", width, height, folded[:])
				ui.probe_frame(&p)
				ui.probe_frame(&p)
				for name in folded {
					b := node_bounds(&p, name)
					testing.expectf(t, b.w > 0 && b.y >= TOOLBAR_H, "%vx%v: %q is in the overflow menu, at %v", width, height, name, b)
				}
			}
			testing.expectf(t, ui.probe_tagged(&p, "Back"), "%vx%v: back is there", width, height)
			reports := ui.probe_bounds(&p, "2026")
			testing.expectf(t, reports.y >= height - PATH_H - STATUS_H && reports.x + reports.w <= width, "%vx%v: the path bar is pinned under the content, at %v", width, height, reports)
			testing.expectf(t, ui.probe_tagged(&p, "1 item"), "%vx%v: the status line is there", width, height)
			ui.probe_destroy(&p)
			model_destroy(&m)
		}
	}
}

@(test)
narrow_windows_drop_panes_and_columns :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	narrow := at_size(&m, {MIN_WIDTH, MIN_HEIGHT})
	defer ui.probe_destroy(&narrow)
	testing.expect(t, !ui.probe_tagged(&narrow, "Places"), "no sidebar beside the content")
	testing.expect(t, !ui.probe_tagged(&narrow, "Modified"), "no Modified column")
	testing.expect(t, ui.probe_tagged(&narrow, "Size"))
	testing.expect(t, !ui.probe_tagged(&narrow, "Kind"), "no details pane")
	wide_m: Model
	defer model_destroy(&wide_m)
	wide := at_size(&wide_m, {1400, 720})
	defer ui.probe_destroy(&wide)
	testing.expect(t, ui.probe_tagged(&wide, "Places"))
	testing.expect(t, ui.probe_tagged(&wide, "Modified"))
	testing.expect(t, ui.probe_tagged(&wide, "Kind"))
}

// At a width the sidebar does not fit, its toggle shows it over the
// content, and a visit from it closes it.
@(test)
the_sidebar_opens_over_a_narrow_window :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := at_size(&m, {600, 480})
	defer ui.probe_destroy(&p)
	testing.expect(t, !ui.probe_tagged(&p, "Places"))
	testing.expect(t, ui.probe_click(&p, "Sidebar"))
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_needs_q(&p, query.Places{}), "the drawer needs the places")
	ui.probe_deliver(&p, query.Places{}, query.Places_Result{items = {{"Home", "/home/me", true}}})
	ui.probe_advance(&p, 20, 0.05) // the drawer slides in
	testing.expect(t, ui.probe_tagged(&p, "Places"), "the drawer shows the sidebar")
	testing.expect(t, ui.probe_click(&p, "Home"))
	testing.expect_value(t, path_of(&m), "/home/me")
	ui.probe_frame(&p)
	testing.expect(t, !m.sidebar_over, "a visit closes the drawer")
	// Wide, the toggle hides and shows the sidebar beside the content.
	wm: Model
	defer model_destroy(&wm)
	wide := at_size(&wm, {1200, 700})
	defer ui.probe_destroy(&wide)
	testing.expect(t, ui.probe_click(&wide, "Sidebar"))
	ui.probe_frame(&wide)
	testing.expect(t, !ui.probe_tagged(&wide, "Places"))
}

// Narrow, search is a button; opened, it is a box that takes the room,
// and the actions it displaces move into the overflow menu.
@(test)
narrow_search_opens_and_displaces_actions :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := at_size(&m, {MIN_WIDTH, MIN_HEIGHT})
	defer ui.probe_destroy(&p)
	testing.expect(t, ui.probe_bounds(&p, "Search").w < 40, "search is a button")
	shown_before := 0
	for a in Action {
		if toolbar_has(&p, ACTION_LABELS[a]) {
			shown_before += 1
		}
	}
	testing.expect(t, ui.probe_click(&p, "Search"))
	// Many frames with no input: the box stays open, waiting for focus.
	for _ in 0 ..< 10 {
		ui.probe_frame(&p)
	}
	testing.expect(t, node_bounds(&p, "Search").w >= SEARCH_W - 10, "the box opened, and stays open")
	ui.probe_move(&p, 10, 200) // the next input moves focus into it
	ui.probe_frame(&p)
	testing.expect(t, m.search_held, "the box took focus")
	shown_after := 0
	for a in Action {
		if toolbar_has(&p, ACTION_LABELS[a]) {
			shown_after += 1
		}
	}
	testing.expect(t, shown_after < shown_before, "the box displaced actions")
	testing.expect(t, ui.probe_click(&p, "More"))
	ui.probe_move(&p, 10, 200)
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	testing.expect(t, m.search_open, "the box stays while its overflow menu is open")
	testing.expect(t, ui.probe_tagged(&p, "New folder") || ui.probe_tagged(&p, "Rename"), "the displaced actions are in the menu")
	// Left empty, the box folds back into its button.
	ui.probe_key(&p, .Escape)
	testing.expect(t, ui.probe_click(&p, "summary.txt"))
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	testing.expect(t, !m.search_open, "empty and left, search folds")
	testing.expect(t, abs(node_bounds(&p, "Search").w - node_bounds(&p, "Search").h) < 0.5, "back to a button")
}

// node_bounds is where the control a reader knows as label is, first
// found: disabled controls have no hit area, but every control has a
// semantic node.
@(private = "file")
node_bounds :: proc(p: ^ui.Probe, label: string) -> ops.Rect {
	for n in ui.probe_current(p).nodes {
		if n.semantics.label == label && n.rect.w > 0 {
			return n.rect
		}
	}
	return {}
}

@(private = "file")
toolbar_has :: proc(p: ^ui.Probe, name: string) -> bool {
	for tg in ui.probe_current(p).tags {
		if tg.name == name && tg.bounds.y < TOOLBAR_H {
			return true
		}
	}
	return false
}

// Hovering a folded crumb shows its name; the crumbs before it do not
// move, so it stays under the pointer.
@(test)
a_folded_crumb_opens_under_the_pointer :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := at_size(&m, {MIN_WIDTH, MIN_HEIGHT})
	defer ui.probe_destroy(&p)
	// The first folded crumb after the root, and the crumbs before it.
	crumbs := []string{"Computer", "home", "me", "projects", "client", "archive", "2026"}
	at := -1
	for c, ii in crumbs[1:] {
		if ui.probe_bounds(&p, c).w < 40 {
			at = ii + 1
			break
		}
	}
	testing.expect(t, at > 0, "a crumb is folded to its icon at the smallest width")
	if at <= 0 {
		return
	}
	folded := ui.probe_bounds(&p, crumbs[at])
	before := ui.probe_bounds(&p, crumbs[at - 1])
	ui.probe_move(&p, folded.x + folded.w / 2, folded.y + folded.h / 2)
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	open := ui.probe_bounds(&p, crumbs[at])
	testing.expect(t, open.w > folded.w + 10, "it shows its name")
	testing.expect_value(t, open.x, folded.x)
	testing.expect_value(t, ui.probe_bounds(&p, crumbs[at - 1]), before)
}

// --- the sidebar's width -------------------------------------------------------

@(private = "file")
sidebar_w_now :: proc(p: ^ui.Probe) -> f32 {
	h := node_bounds(p, "Resize sidebar")
	return h.x + h.w if h.w > 0 else 0
}

@(test)
the_sidebar_drags_wider_up_to_the_contents_minimum :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := at_size(&m, {1000, 700})
	defer ui.probe_destroy(&p)
	testing.expect_value(t, sidebar_w_now(&p), f32(SIDEBAR))
	testing.expect(t, ui.probe_drag(&p, "Resize sidebar", 80, 0))
	ui.probe_frame(&p)
	testing.expect_value(t, sidebar_w_now(&p), f32(SIDEBAR + 80))
	// Far right: no wider than leaves the content its minimum.
	testing.expect(t, ui.probe_drag(&p, "Resize sidebar", 900, 0))
	ui.probe_frame(&p)
	testing.expect_value(t, sidebar_w_now(&p), f32(1000 - CONTENT_MIN))
	// A narrower window narrows it, but the width chosen stays.
	chosen := m.sidebar_w
	ui.probe_destroy(&p)
	p = ui.Probe{}
	ui.probe_init(&p, view, &m, {800, 700})
	ui.probe_frame(&p)
	testing.expect_value(t, sidebar_w_now(&p), f32(800 - CONTENT_MIN))
	testing.expect_value(t, m.sidebar_w, chosen)
	// A double click restores the default.
	testing.expect(t, ui.probe_click(&p, "Resize sidebar", clicks = 2))
	ui.probe_frame(&p)
	testing.expect_value(t, sidebar_w_now(&p), f32(SIDEBAR))
}

@(test)
dragged_below_its_minimum_the_sidebar_collapses :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := at_size(&m, {1000, 700})
	defer ui.probe_destroy(&p)
	testing.expect(t, ui.probe_drag(&p, "Resize sidebar", 40, 0))
	ui.probe_frame(&p)
	width := sidebar_w_now(&p)
	testing.expect_value(t, width, f32(SIDEBAR + 40))
	// Down to the minimum it narrows; past it, it collapses on release.
	testing.expect(t, ui.probe_drag(&p, "Resize sidebar", SIDEBAR_MIN - width + 10, 0))
	ui.probe_frame(&p)
	testing.expect_value(t, sidebar_w_now(&p), f32(SIDEBAR_MIN + 10))
	testing.expect(t, ui.probe_drag(&p, "Resize sidebar", -120, 0))
	ui.probe_frame(&p)
	testing.expect(t, m.sidebar_off, "let go below the minimum, it collapsed")
	testing.expect(t, !ui.probe_tagged(&p, "Places"))
	testing.expect(t, !ui.probe_tagged(&p, "Resize sidebar"))
	// The toggle brings it back at the width it had when the drag began.
	testing.expect(t, ui.probe_click(&p, "Sidebar"))
	ui.probe_frame(&p)
	testing.expect_value(t, sidebar_w_now(&p), f32(SIDEBAR_MIN + 10))
}

// --- context menus -----------------------------------------------------------

@(private = "file")
menu_item_bounds :: proc(p: ^ui.Probe, label: string) -> ops.Rect {
	for n in ui.probe_current(p).nodes {
		if n.semantics.role == .Menu_Item && n.semantics.label == label {
			return n.rect
		}
	}
	return {}
}

// pick clicks the open menu's item: the toolbar and the details card
// have controls by the same names.
@(private = "file")
pick :: proc(p: ^ui.Probe, label: string) -> bool {
	b := menu_item_bounds(p, label)
	if b.w == 0 {
		return false
	}
	c := ops.Point{b.x + b.w / 2, b.y + b.h / 2}
	ui.router_push(&p.router, {kind = .Move, pos = c})
	ui.router_push(&p.router, {kind = .Press, pos = c, button = .Left})
	ui.probe_frame(p)
	ui.router_push(&p.router, {kind = .Release, pos = c, button = .Left})
	ui.probe_frame(p)
	return true
}

@(private = "file")
right_click :: proc(p: ^ui.Probe, at: ops.Point) {
	ui.router_push(&p.router, {kind = .Move, pos = at})
	ui.router_push(&p.router, {kind = .Press, pos = at, button = .Right})
	ui.probe_frame(p)
	ui.router_push(&p.router, {kind = .Release, pos = at, button = .Right})
	ui.probe_frame(p)
	ui.probe_advance(p, 10, 0.05) // the menu fades and slides in
}

@(test)
a_right_click_on_an_entry_opens_its_menu_under_the_pointer :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := open(&m)
	defer ui.probe_destroy(&p)
	ui.probe_deliver(&p, query.Listing{path = "/home/me"}, query.Listing_Result{entries = fixture_entries})
	ui.probe_frame(&p)
	row := ui.probe_bounds(&p, "notes.txt")
	at := ops.Point{row.x + 40, row.y + row.h / 2}
	right_click(&p, at)
	testing.expect_value(t, selected_path(&m), "/home/me/notes.txt")
	for item in ([]string{"Open", "Cut", "Copy", "Duplicate", "Rename", "Copy path", "Move to Trash"}) {
		testing.expectf(t, menu_item_bounds(&p, item).w > 0, "the menu offers %q", item)
	}
	testing.expect(t, menu_item_bounds(&p, "Paste into folder").w == 0, "a file is not pasted into")
	// The details card has an Open button too: the menu's is its item.
	open_ := menu_item_bounds(&p, "Open")
	testing.expectf(t, abs(open_.x - at.x) < 24 && open_.y >= at.y - 1 && open_.y < at.y + 40, "the menu is under the pointer at %v: %v", at, open_)

	// Duplicate is a copy into the folder it is in.
	testing.expect(t, pick(&p, "Duplicate"))
	cmds := ui.probe_commands(&p)
	testing.expect_value(t, len(cmds), 1)
	dup, ok := command_of(cmds[0]).(files.Paste)
	testing.expect(t, ok && dup.mode == .Copy)
	testing.expect_value(t, files.path_of(&dup.source), "/home/me/notes.txt")
	testing.expect_value(t, files.path_of(&dup.dest), "/home/me")
	ui.probe_frame(&p)
	testing.expect(t, menu_item_bounds(&p, "Duplicate").w == 0, "a pick closes the menu")

	// Copy path puts the path on the clipboard; Move to Trash asks for it.
	right_click(&p, at)
	testing.expect(t, pick(&p, "Copy path"))
	testing.expect_value(t, ui.probe_clipboard(&p), "/home/me/notes.txt")
	right_click(&p, at)
	testing.expect(t, pick(&p, "Move to Trash"))
	trash, tok := command_of(ui.probe_commands(&p)[0]).(files.Trash)
	testing.expect(t, tok)
	testing.expect_value(t, files.path_of(&trash.path), "/home/me/notes.txt")
}

@(test)
a_folder_offers_to_be_pinned_and_pasted_into :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := open(&m)
	defer ui.probe_destroy(&p)
	ui.probe_deliver(&p, query.Listing{path = "/home/me"}, query.Listing_Result{entries = fixture_entries})
	ui.probe_frame(&p)
	take(&m, "/home/me/notes.txt", .Copy)
	row := ui.probe_bounds(&p, "docs")
	right_click(&p, {row.x + 40, row.y + row.h / 2})
	testing.expect(t, menu_item_bounds(&p, "Pin to sidebar").w > 0)
	testing.expect(t, pick(&p, "Paste into folder"))
	paste, ok := command_of(ui.probe_commands(&p)[0]).(files.Paste)
	testing.expect(t, ok)
	testing.expect_value(t, files.path_of(&paste.dest), "/home/me/docs")
}

@(test)
a_right_click_on_no_entry_opens_the_folders_menu :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := open(&m)
	defer ui.probe_destroy(&p)
	ui.probe_deliver(&p, query.Listing{path = "/home/me"}, query.Listing_Result{entries = fixture_entries})
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_click(&p, "notes.txt"))
	ui.probe_frame(&p)
	// Below the last row.
	last := ui.probe_bounds(&p, "notes.txt")
	empty := ops.Point{last.x + 60, 600 - PATH_H - STATUS_H - 40}
	right_click(&p, empty)
	testing.expect_value(t, m.selected_len, 0)
	testing.expect(t, menu_item_bounds(&p, "New folder").w > 0)
	testing.expect(t, menu_item_bounds(&p, "Duplicate").w == 0, "the folder's menu, not an entry's")
	ui.probe_key(&p, .Escape)
	ui.probe_frame(&p)
	testing.expect(t, !m.menu_open, "Escape closes it")
	// A left click on no entry clears the selection.
	testing.expect(t, ui.probe_click(&p, "notes.txt"))
	ui.probe_frame(&p)
	testing.expect(t, m.selected_len > 0)
	ui.router_push(&p.router, {kind = .Press, pos = empty, button = .Left})
	ui.router_push(&p.router, {kind = .Release, pos = empty, button = .Left})
	ui.probe_frame(&p)
	testing.expect_value(t, m.selected_len, 0)
}
