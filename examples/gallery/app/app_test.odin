package gallery_app

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "core:time"

import "jm:ui"

import "../view"

// The application less the window: the view in a probe, its needs handed
// to the host as the frame loop would, the host's pictures drained back.
// The pipeline, the workers and the files are real.

@(private = "file")
Rig :: struct {
	h:     Host,
	m:     view.Model,
	p:     ui.Probe,
	data:  ui.Data_Host,
	needs: ui.Subscriptions,
}

@(private = "file")
rig_open :: proc(r: ^Rig, cache_budget := CACHE_BUDGET) -> bool {
	if !init(&r.h, cache_budget = cache_budget) {
		return false
	}
	r.data = data_host(&r.h)
	ui.subscriptions_init(&r.needs)
	ui.probe_init(&r.p, view.view, &r.m, {720, 600})
	return true
}

@(private = "file")
rig_close :: proc(r: ^Rig) {
	ui.probe_destroy(&r.p)
	ui.subscriptions_destroy(&r.needs)
	stop(&r.h)
}

@(private = "file")
hand_on :: proc(r: ^Rig) {
	ui.data_after_frame(&r.data, &r.needs, &r.p.router)
}

// settle drains and frames until the host is idle, with a deadline.
@(private = "file")
settle :: proc(r: ^Rig, limit := 30 * time.Second) -> bool {
	deadline := time.tick_now()._nsec + i64(limit)
	for time.tick_now()._nsec < deadline {
		if ui.inbox_pending(&r.h.inbox) {
			ui.inbox_drain(&r.h.inbox, &r.p.layout)
			ui.probe_frame(&r.p)
			hand_on(r)
		}
		if stats(&r.h).pending == 0 && !ui.inbox_pending(&r.h.inbox) {
			ui.probe_frame(&r.p)
			hand_on(r)
			return true
		}
		time.sleep(5 * time.Millisecond)
	}
	return false
}

@(test)
tiles_in_view_are_made_and_drawn :: proc(t: ^testing.T) {
	r: Rig
	testing.expect(t, rig_open(&r))
	defer rig_close(&r)
	hand_on(&r)
	testing.expect(t, stats(&r.h).pending > 0, "the first frame's tiles are in the making")
	testing.expect(t, settle(&r), "every tile in view was made")
	st := stats(&r.h)
	testing.expect(t, st.generated >= 12, "the rows in view were made")
	testing.expect_value(t, st.cancelled, 0)
	dump := ui.probe_dump(&r.p)
	defer delete(dump)
	testing.expect_value(t, strings.count(dump, "image#"), st.generated)
	testing.expect(t, strings.contains(dump, "0 abandoned"), "the header shows the counts")
	testing.expect_value(t, st.open, len(r.needs.live) - 1) // every live need but the stats
	testing.expect_value(t, st.cached, st.generated)
	testing.expect_value(t, st.misses, st.generated)
	testing.expect_value(t, st.hits, 0)
}

@(test)
pictures_come_back_from_the_cache_within_its_budget :: proc(t: ^testing.T) {
	// Two screens of tiles pass a 2 MB budget; the application's 10 MB
	// would hold them both and show no eviction.
	r: Rig
	testing.expect(t, rig_open(&r, 2 * 1024 * 1024))
	defer rig_close(&r)
	hand_on(&r)
	testing.expect(t, settle(&r))
	first := stats(&r.h)
	// Far away: a second screen is made; together they pass the budget,
	// so the least recent of the first go, none of them live.
	r.m.list.offset = 500 * (view.TILE + view.GAP)
	ui.probe_frame(&r.p)
	hand_on(&r)
	testing.expect(t, settle(&r))
	far := stats(&r.h)
	testing.expect(t, far.generated > first.generated)
	testing.expect(t, far.evictions > 0, "the budget let the oldest go")
	testing.expect(t, far.cache_bytes <= 2 * 1024 * 1024)
	// Back at the top: what survived is a hit, the rest are made again.
	r.m.list.offset = 0
	ui.probe_frame(&r.p)
	hand_on(&r)
	testing.expect(t, settle(&r))
	back := stats(&r.h)
	testing.expect(t, back.hits > 0, "some pictures came from the cache")
	testing.expect(t, back.hits + back.misses > far.hits + far.misses)
	testing.expect_value(t, back.open, first.open)
}

@(test)
tiles_scrolled_away_are_abandoned :: proc(t: ^testing.T) {
	r: Rig
	testing.expect(t, rig_open(&r))
	defer rig_close(&r)
	hand_on(&r)
	first := stats(&r.h).pending
	testing.expect(t, first > 0)
	// Scroll far away before any picture can be done: every job for the
	// first rows is cancelled, the rows now in view are made instead.
	r.m.list.offset = 500 * (view.TILE + view.GAP)
	ui.probe_frame(&r.p)
	hand_on(&r)
	testing.expect(t, settle(&r), "the host went idle")
	st := stats(&r.h)
	testing.expect_value(t, st.cancelled, first)
	testing.expect(t, st.generated >= 12)
	dump := ui.probe_dump(&r.p)
	defer delete(dump)
	testing.expect_value(t, strings.count(dump, "image#"), st.generated)
	testing.expect_value(t, len(r.h.jobs), 0)
}

@(test)
the_viewer_streams_patches :: proc(t: ^testing.T) {
	r: Rig
	testing.expect(t, rig_open(&r))
	defer rig_close(&r)
	hand_on(&r)
	testing.expect(t, settle(&r))
	made := stats(&r.h).generated
	testing.expect(t, ui.probe_click(&r.p, "Tile 0"))
	ui.probe_frame(&r.p)
	hand_on(&r)
	testing.expect(t, r.m.open)
	testing.expect(t, stats(&r.h).pending > 0, "the patches in view are in the making")
	testing.expect(t, settle(&r))
	testing.expect(t, stats(&r.h).generated > made, "patches were made")
	path, _ := filepath.join({r.h.dir, "patch-0-1-0-0-256.bmp"}, context.temp_allocator)
	testing.expect(t, os.exists(path), "a level-1 patch was written")
	dump := ui.probe_dump(&r.p)
	defer delete(dump)
	testing.expect(t, strings.count(dump, "image#") >= 5, "the tile and its patches are drawn")
}
