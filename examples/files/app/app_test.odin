package files_app

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

// A real folder: a picture, a text file and a subfolder with a file.
@(private = "file")
fixture :: proc() -> string {
	tmp, _ := os.temp_directory(context.temp_allocator)
	dir, _ := filepath.join({tmp, "jm-files-app"}, context.temp_allocator)
	_ = os.make_directory(dir)
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
	testing.expect_value(t, st.open, 4) // the listing and the sidebar's three; the thumbnail's need went with the old folder
}

@(test)
the_sidebar_fills_from_the_store_and_follows_pins :: proc(t: ^testing.T) {
	dir := fixture()
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
	testing.expect(t, ui.probe_tagged(&r.p, "jm-files-app"), "the pinned folder is listed")
}

@(test)
a_change_refreshes_pins_but_not_the_recent_snapshot :: proc(t: ^testing.T) {
	r: Route
	r.live = make(map[ui.Need_Key]store.Kind, context.temp_allocator)
	r.out = make([dynamic]store.Input, context.temp_allocator)
	testing.expect_value(t, len(route(&r, Need_Event{true, 1, .Recent})), 1)
	testing.expect_value(t, len(route(&r, Need_Event{true, 2, .Pins})), 1)
	again := route(&r, store.Change_Batch{count = 1})
	testing.expect_value(t, len(again), 1)
	q, ok := again[0].(store.Query)
	testing.expect(t, ok)
	testing.expect_value(t, q.kind, store.Kind.Pins)
}
