package files_app

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "core:time"

import "jm:sqlite3"
import "jm:ui"

import "../../common"

import "../store"

import "../view"

@(private = "file")
Rig :: struct {
	h:     Host,
	m:     view.Model,
	p:     ui.Probe,
	data:  ui.Data_Host,
	needs: ui.Subscriptions,
}

@(private = "file")
rig_open :: proc(r: ^Rig, path: string) -> bool {
	if !init(&r.h, db_path = sqlite3.MEMORY) {
		return false
	}
	r.data = data_host(&r.h)
	ui.subscriptions_init(&r.needs)
	view.model_init(&r.m, path)
	ui.probe_init(&r.p, view.view, &r.m, {1200, 600})
	return true
}

@(private = "file")
rig_close :: proc(r: ^Rig) {
	ui.probe_destroy(&r.p)
	ui.subscriptions_destroy(&r.needs)
	view.model_destroy(&r.m)
	stop(&r.h)
}

@(private = "file")
hand_on :: proc(r: ^Rig) {
	ui.data_after_frame(&r.data, &r.needs, &r.p.router)
}

@(private = "file")
settle :: proc(r: ^Rig, limit := 10 * time.Second) -> bool {
	deadline := time.tick_now()._nsec + i64(limit)
	for time.tick_now()._nsec < deadline {
		if ui.inbox_pending(&r.h.inbox) {
			ui.inbox_drain(&r.h.inbox, &r.p.layout)
			ui.probe_frame(&r.p)
			hand_on(r)
		}
		if stats(&r.h).pending == 0 && !ui.inbox_pending(&r.h.inbox) {
			// A frame more, and any it asks for, as the loop would run.
			for ii := 0; ii == 0 || (r.p.wants_frame && ii < 4); ii += 1 {
				ui.probe_frame(&r.p)
				hand_on(r)
			}
			if stats(&r.h).pending > 0 || ui.inbox_pending(&r.h.inbox) {
				continue
			}
			return true
		}
		time.sleep(5 * time.Millisecond)
	}
	return false
}

// A real folder: a picture, a text file and a subfolder with a file. Each
// call makes a folder of its own. One shared folder was rewritten by every
// test that asked for it, in parallel and by other test runs on the machine,
// so a thumbnail could read the picture half written and fail.
@(private = "file")
fixture :: proc() -> string {
	dir, _ := os.make_directory_temp("", "jm-files-app-*", context.temp_allocator)
	sub, _ := filepath.join({dir, "inner"}, context.temp_allocator)
	_ = os.make_directory(sub)
	pixels := make([]u32, 16, context.temp_allocator)
	for &p in pixels {
		p = 0xFF00FF00
	}
	pic, _ := filepath.join({dir, "green.bmp"}, context.temp_allocator)
	_ = common.write_bmp(pic, 4, 4, pixels)
	txt, _ := filepath.join({dir, "readme.txt"}, context.temp_allocator)
	_ = os.write_entire_file(txt, "hello")
	deep, _ := filepath.join({sub, "deep.txt"}, context.temp_allocator)
	_ = os.write_entire_file(deep, "x")
	return dir
}

@(test)
a_folder_is_read_and_its_picture_thumbnailed :: proc(t: ^testing.T) {
	dir := fixture()
	defer os.remove_all(dir)
	r: Rig
	testing.expect(t, rig_open(&r, dir))
	defer rig_close(&r)
	hand_on(&r)
	testing.expect(t, settle(&r), "the listing and the thumbnail arrived")
	testing.expect(t, ui.probe_tagged(&r.p, "inner"))
	testing.expect(t, ui.probe_tagged(&r.p, "green.bmp"))
	testing.expect(t, ui.probe_tagged(&r.p, "readme.txt"))
	st := stats(&r.h)
	testing.expect_value(t, st.listings, 1)
	testing.expect_value(t, st.thumbs, 1)
	dump := ui.probe_dump(&r.p)
	defer delete(dump)
	testing.expect(t, strings.contains(dump, "image#0"), "the thumbnail is drawn")
	thumbs, _ := os.read_all_directory_by_path(r.h.dir, context.temp_allocator)
	testing.expect_value(t, len(thumbs), 1)
}

@(test)
entering_a_folder_reads_it_and_releases_the_old :: proc(t: ^testing.T) {
	dir := fixture()
	defer os.remove_all(dir)
	r: Rig
	testing.expect(t, rig_open(&r, dir))
	defer rig_close(&r)
	hand_on(&r)
	testing.expect(t, settle(&r))
	sub, _ := filepath.join({dir, "inner"}, context.temp_allocator)
	view.navigate(&r.m, sub)
	ui.probe_frame(&r.p)
	hand_on(&r)
	testing.expect(t, settle(&r))
	testing.expect(t, ui.probe_tagged(&r.p, "deep.txt"))
	testing.expect(t, !ui.probe_tagged(&r.p, "green.bmp"))
	st := stats(&r.h)
	testing.expect_value(t, st.listings, 2)
	testing.expect_value(t, st.open, 5) // the listing, the sidebar's three and the activity; the thumbnail's need went with the old folder
}

@(test)
the_sidebar_fills_from_the_store_and_follows_pins :: proc(t: ^testing.T) {
	dir := fixture()
	defer os.remove_all(dir)
	r: Rig
	testing.expect(t, rig_open(&r, dir))
	defer rig_close(&r)
	hand_on(&r)
	testing.expect(t, settle(&r))
	testing.expect(t, ui.probe_tagged(&r.p, "Home"), "the places came from the worker")
	testing.expect(t, ui.probe_tagged(&r.p, "Pin this folder"))
	// Pinning commits a row; the hook's change re-runs the live Pins
	// query and the sidebar shows the folder.
	testing.expect(t, ui.probe_click(&r.p, "Pin this folder"))
	hand_on(&r)
	deadline := time.tick_now()._nsec + i64(5 * time.Second)
	for !ui.probe_tagged(&r.p, "Unpin this folder") && time.tick_now()._nsec < deadline {
		if ui.inbox_pending(&r.h.inbox) {
			ui.inbox_drain(&r.h.inbox, &r.p.layout)
			ui.probe_frame(&r.p)
			hand_on(&r)
		}
		time.sleep(5 * time.Millisecond)
	}
	testing.expect(t, ui.probe_tagged(&r.p, "Unpin this folder"), "the pin came back from the store")
	testing.expect(t, ui.probe_tagged(&r.p, filepath.base(dir)), "the pinned folder is listed")
}

@(test)
a_change_refreshes_pins_but_not_the_recent_snapshot :: proc(t: ^testing.T) {
	r: Route
	r.live = make(map[ui.Need_Key]Read_Kind, context.temp_allocator)
	r.out = make([dynamic]Desk_In, context.temp_allocator)
	testing.expect_value(t, len(route(&r, Need_Event{true, 1, .Recent})), 1)
	testing.expect_value(t, len(route(&r, Need_Event{true, 2, .Pins})), 1)
	testing.expect_value(t, len(route(&r, Need_Event{true, 3, .Activity})), 1)
	again := route(&r, store.Change_Batch{count = 1})
	testing.expect_value(t, len(again), 1)
	q, ok := again[0].(Read)
	testing.expect(t, ok)
	testing.expect_value(t, q.kind, Read_Kind.Pins)
}

// --- changes through the ui -----------------------------------------------------

// own_fixture is fixture's folder under a name of this test's own, so a
// test that changes it changes nothing another test reads.
@(private = "file")
own_fixture :: proc(name: string) -> string {
	tmp, _ := os.temp_directory(context.temp_allocator)
	dir, _ := filepath.join({tmp, fmt.tprintf("jm-files-%s-%d", name, time.now()._nsec)}, context.temp_allocator)
	_ = os.make_directory(dir)
	sub, _ := filepath.join({dir, "inner"}, context.temp_allocator)
	_ = os.make_directory(sub)
	_ = os.write_entire_file(filepath.join({dir, "readme.txt"}, context.temp_allocator) or_else "", "hello")
	return dir
}

// until runs frames, as the loop would whenever the inbox fills, until
// name is tagged (or not), or the deadline passes.
@(private = "file")
until :: proc(r: ^Rig, name: string, present := true, limit := 5 * time.Second) -> bool {
	deadline := time.tick_now()._nsec + i64(limit)
	for time.tick_now()._nsec < deadline {
		if ui.inbox_pending(&r.h.inbox) {
			ui.inbox_drain(&r.h.inbox, &r.p.layout)
		}
		ui.probe_frame(&r.p)
		hand_on(r)
		if ui.probe_tagged(&r.p, name) == present {
			return true
		}
		time.sleep(5 * time.Millisecond)
	}
	return false
}

@(private = "file")
path_in :: proc(dir: string, names: ..string) -> string {
	parts := make([dynamic]string, context.temp_allocator)
	append(&parts, dir)
	append(&parts, ..names)
	p, _ := filepath.join(parts[:], context.temp_allocator)
	return p
}

// select clicks an entry's row, and runs the frame after, which draws
// the toolbar and the details card for the selection.
@(private = "file")
select :: proc(r: ^Rig, name: string) -> bool {
	if !ui.probe_click(&r.p, name) {
		return false
	}
	ui.probe_frame(&r.p)
	hand_on(r)
	return true
}

// rename_selected renames the selected entry: the toolbar's Rename opens
// the details card's field.
@(private = "file")
rename_selected :: proc(r: ^Rig, name: string) -> bool {
	if !ui.probe_click(&r.p, "Rename") {
		return false
	}
	ui.probe_frame(&r.p)
	if !ui.probe_click(&r.p, "New name") {
		return false
	}
	ui.text_set(&r.m.new_name, name)
	ui.probe_key(&r.p, .Enter)
	hand_on(r)
	return true
}

@(test)
a_rename_renames_on_disk_relists_and_undoes :: proc(t: ^testing.T) {
	dir := own_fixture("rename")
	defer os.remove_all(dir)
	r: Rig
	testing.expect(t, rig_open(&r, dir))
	defer rig_close(&r)
	hand_on(&r)
	testing.expect(t, until(&r, "readme.txt"))
	testing.expect(t, select(&r, "readme.txt"))
	testing.expect(t, rename_selected(&r, "notes.txt"))
	testing.expect(t, until(&r, "notes.txt"), "the folder was read again after the rename")
	testing.expect(t, os.exists(path_in(dir, "notes.txt")))
	testing.expect(t, !os.exists(path_in(dir, "readme.txt")))

	// Undo checks the world still matches, then reverses it.
	testing.expect(t, ui.probe_click(&r.p, "Undo"))
	hand_on(&r)
	testing.expect(t, until(&r, "readme.txt"))
	testing.expect(t, os.exists(path_in(dir, "readme.txt")))
	testing.expect(t, !os.exists(path_in(dir, "notes.txt")))
}

@(test)
a_refused_rename_is_a_problem_that_dismisses :: proc(t: ^testing.T) {
	dir := own_fixture("refuse")
	defer os.remove_all(dir)
	r: Rig
	testing.expect(t, rig_open(&r, dir))
	defer rig_close(&r)
	hand_on(&r)
	testing.expect(t, until(&r, "readme.txt"))
	testing.expect(t, select(&r, "readme.txt"))
	testing.expect(t, rename_selected(&r, "inner"))
	testing.expect(t, until(&r, "Dismiss"), "the collision came back as a problem")
	testing.expect(t, os.exists(path_in(dir, "readme.txt")), "nothing was renamed")
	testing.expect(t, ui.probe_click(&r.p, "Dismiss"))
	hand_on(&r)
	testing.expect(t, until(&r, "Dismiss", present = false))
}

@(test)
pins_follow_a_renamed_folder :: proc(t: ^testing.T) {
	dir := own_fixture("pins")
	defer os.remove_all(dir)
	r: Rig
	testing.expect(t, rig_open(&r, dir))
	defer rig_close(&r)
	hand_on(&r)
	view.navigate(&r.m, path_in(dir, "inner"))
	testing.expect(t, until(&r, "Pin this folder"))
	testing.expect(t, ui.probe_click(&r.p, "Pin this folder"))
	hand_on(&r)
	testing.expect(t, until(&r, "Unpin this folder"))
	view.navigate(&r.m, dir)
	testing.expect(t, until(&r, "readme.txt"))
	testing.expect(t, select(&r, "inner"))
	testing.expect(t, rename_selected(&r, "outer"))
	testing.expect(t, until(&r, "outer"))
	view.navigate(&r.m, path_in(dir, "outer"))
	testing.expect(t, until(&r, "Unpin this folder"), "the pin moved with the folder")
}

@(test)
new_folders_take_free_names_and_trash_undoes :: proc(t: ^testing.T) {
	dir := own_fixture("folders")
	defer os.remove_all(dir)
	r: Rig
	testing.expect(t, rig_open(&r, dir))
	defer rig_close(&r)
	hand_on(&r)
	testing.expect(t, until(&r, "readme.txt"))
	testing.expect(t, ui.probe_click(&r.p, "New folder"))
	hand_on(&r)
	testing.expect(t, until(&r, "New folder"))
	testing.expect(t, ui.probe_click(&r.p, "New folder"))
	hand_on(&r)
	testing.expect(t, until(&r, "New folder 2"), "the second takes the next free name")
	// The Trash is the machine's (see trash_and_restore_round_trip in fs):
	// with six runs at once, one run's Undo found its "New folder 2" gone
	// from the Trash. The folder goes there under a name of this run's own,
	// the run folder's, which the path bar shows too, so with a prefix.
	own := fmt.tprintf("trash-%s", filepath.base(dir))
	testing.expect(t, select(&r, "New folder 2"))
	testing.expect(t, rename_selected(&r, own))
	testing.expect(t, until(&r, own))
	testing.expect(t, select(&r, own))
	testing.expect(t, ui.probe_click(&r.p, "Move to Trash"))
	hand_on(&r)
	testing.expect(t, until(&r, own, present = false))
	testing.expect(t, !os.exists(path_in(dir, own)))
	when ODIN_OS != .Windows {
		testing.expect(t, ui.probe_click(&r.p, "Undo"))
		hand_on(&r)
		testing.expect(t, until(&r, own), "the folder came back from the Trash")
		testing.expect(t, os.exists(path_in(dir, own)))
	}
}

@(test)
a_paste_that_collides_asks_and_keeps_both :: proc(t: ^testing.T) {
	dir := own_fixture("paste")
	defer os.remove_all(dir)
	_ = os.write_entire_file(path_in(dir, "inner", "readme.txt"), "already here")
	r: Rig
	testing.expect(t, rig_open(&r, dir))
	defer rig_close(&r)
	hand_on(&r)
	testing.expect(t, until(&r, "readme.txt"))
	testing.expect(t, select(&r, "readme.txt"))
	testing.expect(t, ui.probe_click(&r.p, "Copy"))
	view.navigate(&r.m, path_in(dir, "inner"))
	testing.expect(t, until(&r, "readme.txt"))
	testing.expect(t, ui.probe_click(&r.p, "Paste"))
	hand_on(&r)
	testing.expect(t, until(&r, "Keep both"), "the paste asked what to do")
	testing.expect(t, ui.probe_click(&r.p, "Keep both"))
	hand_on(&r)
	testing.expect(t, until(&r, "readme 2.txt"), "the copy took a free name")
	data, _ := os.read_entire_file(path_in(dir, "inner", "readme 2.txt"), context.temp_allocator)
	testing.expect_value(t, string(data), "hello")
	kept, _ := os.read_entire_file(path_in(dir, "inner", "readme.txt"), context.temp_allocator)
	testing.expect_value(t, string(kept), "already here")
}

@(test)
a_change_made_elsewhere_shows_within_a_poll :: proc(t: ^testing.T) {
	dir := own_fixture("watch")
	defer os.remove_all(dir)
	r: Rig
	testing.expect(t, rig_open(&r, dir))
	defer rig_close(&r)
	hand_on(&r)
	testing.expect(t, until(&r, "readme.txt"))
	// Another application writes a file: no command, only the watcher.
	_ = os.write_entire_file(path_in(dir, "from-elsewhere.txt"), "hi")
	testing.expect(t, until(&r, "from-elsewhere.txt", limit = 3 * time.Second), "the poll saw the folder change")
}
