package files_view

import "core:testing"

import "jm:ui"
import "jm:ui/fluent"

import "../shapes"

@(private = "file")
listing :: []shapes.Entry {
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
	testing.expect(t, ui.probe_needs_q(&p, shapes.Listing{path = "/home/me"}))
	ui.probe_deliver(&p, shapes.Listing{path = "/home/me"}, shapes.Listing_Result{entries = listing})
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "docs"))
	testing.expect(t, ui.probe_tagged(&p, "cat.png"))
	testing.expect(t, ui.probe_needs_q(&p, shapes.Thumb{path = "/home/me/cat.png", px = THUMB}))
	testing.expect(t, !ui.probe_needs_q(&p, shapes.Thumb{path = "/home/me/notes.txt", px = THUMB}))
	ui.probe_deliver(&p, shapes.Thumb{path = "/home/me/cat.png", px = THUMB}, shapes.Thumb_Result{image = "/tmp/cat-thumb.bmp"})
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
	ui.probe_deliver(&p, shapes.Listing{path = "/home/me"}, shapes.Listing_Result{entries = listing})
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_click(&p, "cat.png"))
	ui.probe_frame(&p)
	testing.expect_value(t, selected_path(&m), "/home/me/cat.png")
	testing.expect(t, ui.probe_tagged(&p, "Open"))
	testing.expect(t, ui.probe_needs_q(&p, shapes.Thumb{path = "/home/me/cat.png", px = PREVIEW}))
	testing.expect(t, ui.probe_tagged(&p, "Picture"))
}

@(test)
the_header_sorts_and_the_search_filters :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := open(&m)
	defer ui.probe_destroy(&p)
	ui.probe_deliver(&p, shapes.Listing{path = "/home/me"}, shapes.Listing_Result{entries = listing})
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
	ui.probe_deliver(&p, shapes.Listing{path = "/home/me"}, shapes.Listing_Result{entries = listing})
	ui.probe_frame(&p)
	testing.expect(t, double_click(&p, "notes.txt"))
	cmds := ui.probe_commands(&p)
	testing.expect_value(t, len(cmds), 2) // Open, and the Visited the sidebar's Recent is kept from
	o, ok := ui.command_as(cmds[0], shapes.Open)
	testing.expect(t, ok)
	testing.expect_value(t, o.path, "/home/me/notes.txt")
	testing.expect(t, ui.command_is(cmds[1], shapes.Visited))
	testing.expect_value(t, path_of(&m), "/home/me")

	testing.expect(t, double_click(&p, "docs"))
	testing.expect_value(t, path_of(&m), "/home/me/docs")
	v, vok := ui.command_as(ui.probe_commands(&p)[0], shapes.Visited)
	testing.expect(t, vok && v.dir)
	testing.expect_value(t, v.name, "docs")
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_needs_q(&p, shapes.Listing{path = "/home/me/docs"}))
	// The old listing stays drawn and needed until the new one lands.
	testing.expect(t, ui.probe_needs_q(&p, shapes.Listing{path = "/home/me"}))
	testing.expect(t, ui.probe_tagged(&p, "docs"))
	ui.probe_deliver(&p, shapes.Listing{path = "/home/me/docs"}, shapes.Listing_Result{entries = {{name = "a.txt", path = "/home/me/docs/a.txt"}}})
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "a.txt"))
	testing.expect(t, !ui.probe_tagged(&p, "cat.png"), "the old listing's rows are gone")
	testing.expect(t, !ui.probe_needs_q(&p, shapes.Listing{path = "/home/me"}))
}

@(test)
the_breadcrumb_and_up_go_back_out :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := open(&m)
	defer ui.probe_destroy(&p)
	navigate(&m, "/home/me/docs/work")
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_click(&p, "Up"))
	testing.expect_value(t, path_of(&m), "/home/me/docs")
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_click(&p, "home"))
	testing.expect_value(t, path_of(&m), "/home")
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_click(&p, "/"))
	testing.expect_value(t, path_of(&m), "/")
	crumbs := crumbs_of("/a/b", context.temp_allocator)
	testing.expect_value(t, len(crumbs), 3)
	testing.expect_value(t, crumb_path(crumbs, 2, context.temp_allocator), "/a/b")
	testing.expect_value(t, crumb_path(crumbs, 0, context.temp_allocator), "/")
}

@(test)
an_unreadable_folder_shows_its_error :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := open(&m)
	defer ui.probe_destroy(&p)
	ui.probe_deliver(&p, shapes.Listing{path = "/home/me"}, shapes.Listing_Result{error = "cannot read /home/me: permission denied"})
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
	testing.expect(t, ui.probe_needs_q(&p, shapes.Places{}))
	testing.expect(t, ui.probe_needs_q(&p, shapes.Pins{}))
	testing.expect(t, ui.probe_needs_q(&p, shapes.Recent{}))
	ui.probe_deliver(&p, shapes.Places{}, shapes.Places_Result{items = {{"Home", "/home/me", true}, {"Pictures", "/home/me/Pictures", true}}})
	ui.probe_deliver(&p, shapes.Pins{}, shapes.Pins_Result{items = {{"work", "/home/me/work", true}}})
	ui.probe_deliver(&p, shapes.Recent{}, shapes.Recent_Result{items = {{"cat.png", "/home/me/cat.png", false}, {"Pictures", "/home/me/Pictures", true}}})
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
	pin, ok := ui.command_as(cmds[0], shapes.Pin)
	testing.expect(t, ok)
	testing.expect_value(t, pin.path, "/home/me")
	testing.expect_value(t, pin.name, "me")
	ui.probe_deliver(&p, shapes.Pins{}, shapes.Pins_Result{items = {{"work", "/home/me/work", true}, {"me", "/home/me", true}}})
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
	testing.expect(t, ui.command_is(cmds[0], shapes.Open))
	testing.expect(t, ui.command_is(cmds[1], shapes.Visited))
}
