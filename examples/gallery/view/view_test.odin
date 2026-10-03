package gallery_view

import "core:strings"
import "core:testing"

import "jm:ui"

import "../shapes"

@(private = "file")
open :: proc(m: ^Model) -> ui.Probe {
	p: ui.Probe
	ui.probe_init(&p, view, m, {720, 600})
	return p
}

@(test)
only_the_rows_in_view_are_needed :: proc(t: ^testing.T) {
	m: Model
	p := open(&m)
	defer ui.probe_destroy(&p)
	// 720 wide holds four columns; the header leaves about 500px: three
	// rows plus a sliver of a fourth, so sixteen tiles, and the stats.
	testing.expect_value(t, m.columns, 4)
	testing.expect(t, ui.probe_needs_q(&p, shapes.Tile{index = 0, px = TILE}))
	testing.expect(t, ui.probe_needs_q(&p, shapes.Tile{index = 15, px = TILE}))
	testing.expect(t, !ui.probe_needs_q(&p, shapes.Tile{index = 40, px = TILE}))
	testing.expect(t, ui.probe_needs_q(&p, shapes.Stats{}))
	testing.expect(t, len(ui.probe_needs(&p)) < 30)
}

@(test)
scrolling_away_releases_tiles_and_needs_new_ones :: proc(t: ^testing.T) {
	m: Model
	p := open(&m)
	defer ui.probe_destroy(&p)
	before := len(ui.probe_needs(&p))
	m.list.offset = 100 * (TILE + GAP) // a hundred rows down
	ui.probe_frame(&p)
	testing.expect(t, !ui.probe_needs_q(&p, shapes.Tile{index = 0, px = TILE}))
	testing.expect(t, ui.probe_needs_q(&p, shapes.Tile{index = 100 * 4, px = TILE}))
	testing.expect(t, len(ui.probe_dropped(&p)) >= 12, "the first rows' tiles were released")
	testing.expect(t, len(ui.probe_added(&p)) >= 12, "the new rows' tiles were asked for")
	testing.expect_value(t, len(ui.probe_needs(&p)), before)
}

@(test)
the_header_shows_the_counts :: proc(t: ^testing.T) {
	m: Model
	p := open(&m)
	defer ui.probe_destroy(&p)
	ui.probe_deliver(&p, shapes.Stats{}, shapes.Stats_Result{open = 16, generated = 9, cached = 9, cache_bytes = 900 * 1024, hits = 3, misses = 9})
	ui.probe_frame(&p)
	dump := ui.probe_dump(&p)
	defer delete(dump)
	testing.expect(t, strings.contains(dump, "16 open"), "streams open")
	testing.expect(t, strings.contains(dump, "cache 9 images 900 KB"), "the cache's size")
	testing.expect(t, strings.contains(dump, "3 hits"), "hits")
}

@(test)
a_narrow_window_has_fewer_columns :: proc(t: ^testing.T) {
	m: Model
	p: ui.Probe
	ui.probe_init(&p, view, &m, {400, 600})
	defer ui.probe_destroy(&p)
	testing.expect_value(t, m.columns, 2)
	testing.expect(t, ui.probe_needs_q(&p, shapes.Tile{index = 7, px = TILE}))
	testing.expect(t, !ui.probe_needs_q(&p, shapes.Tile{index = 12, px = TILE}))
}

@(test)
a_click_opens_the_viewer_which_zooms_and_pans_by_patches :: proc(t: ^testing.T) {
	m: Model
	p := open(&m)
	defer ui.probe_destroy(&p)
	ui.probe_deliver(&p, shapes.Tile{index = 5, px = TILE}, shapes.Tile_Result{path = "/tmp/tile-5.bmp"})
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_click(&p, "Tile 5"))
	ui.probe_frame(&p)
	testing.expect(t, m.open)
	// The viewer is 512px tall at this window, two patches' worth: level
	// 1, four patches, over the small tile drawn under them and a scrim
	// that covers the window.
	testing.expect_value(t, m.viewer.level, 1)
	testing.expect(t, ui.probe_needs_q(&p, shapes.Patch{5, 1, 0, 0, PATCH}))
	testing.expect(t, ui.probe_needs_q(&p, shapes.Patch{5, 1, 1, 1, PATCH}))
	testing.expect(t, ui.probe_needs_q(&p, shapes.Tile{index = 5, px = TILE}))
	dump := ui.probe_dump(&p)
	defer delete(dump)
	testing.expect(t, strings.contains(dump, "fill rect 0 0 720 600"), "the scrim covers the window")
	testing.expect_value(t, strings.count(dump, "image#0"), 2)

	// Four notches in wants level 2: its patches in view, with the last
	// complete level, still 0 since nothing has landed, kept needed until
	// every one of them is drawn.
	testing.expect(t, ui.probe_scroll(&p, "Viewer", -4 * ui.SCROLL_STEP))
	ui.probe_frame(&p)
	testing.expect_value(t, m.viewer.level, 2)
	testing.expect(t, ui.probe_needs_q(&p, shapes.Patch{5, 2, 1, 1, PATCH}))
	testing.expect(t, ui.probe_needs_q(&p, shapes.Patch{5, 0, 0, 0, PATCH}))
	testing.expect(t, !ui.probe_needs_q(&p, shapes.Patch{5, 1, 0, 0, PATCH}))
	for y in 0 ..< 4 {
		for x in 0 ..< 4 {
			ui.probe_deliver(&p, shapes.Patch{5, 2, x, y, PATCH}, shapes.Tile_Result{path = "/tmp/p.bmp"})
		}
	}
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	testing.expect_value(t, m.viewer.shown, 2)
	testing.expect(t, !ui.probe_needs_q(&p, shapes.Patch{5, 0, 0, 0, PATCH}))

	// A drag moves the centre by the pointer's travel in plane units.
	before := m.viewer.center
	testing.expect(t, ui.probe_drag(&p, "Viewer", 100, 0))
	testing.expect(t, m.viewer.center.x < before.x)
	testing.expect(t, abs(m.viewer.center.x - before.x + 100 * m.viewer.scale) < 1e-9)

	// Escape closes it and every patch need goes.
	ui.probe_key(&p, .Escape)
	ui.probe_frame(&p)
	testing.expect(t, !m.open)
	testing.expect(t, !ui.probe_needs_q(&p, shapes.Patch{5, 2, 1, 1, PATCH}))
}

@(test)
a_delivered_tile_draws_its_image_and_a_wait_shows_a_skeleton_late :: proc(t: ^testing.T) {
	m: Model
	p := open(&m)
	defer ui.probe_destroy(&p)
	// Nothing yet: blank tiles, a frame asked for at the deadline.
	blank := ui.probe_dump(&p)
	defer delete(blank)
	testing.expect(t, !strings.contains(blank, "image#"))
	testing.expect(t, p.wants_frame)
	ui.probe_deliver(&p, shapes.Tile{index = 5, px = TILE}, shapes.Tile_Result{path = "/tmp/tile-5.bmp"})
	ui.probe_frame(&p)
	dump := ui.probe_dump(&p)
	defer delete(dump)
	testing.expect(t, strings.contains(dump, "image#0"), "tile 5 draws its image")
	testing.expect_value(t, strings.count(dump, "image#"), 1)
	// The others are still waiting; past the delay they show skeletons.
	ui.probe_advance(&p, 4, 0.05)
	after := ui.probe_dump(&p)
	defer delete(after)
	testing.expect(t, strings.count(after, "image#") == 1)
	testing.expect(t, len(after) > len(dump), "skeletons add ops the blank tiles did not")
}

@(test)
zooming_out_past_a_fine_level_asks_for_nothing_of_it :: proc(t: ^testing.T) {
	m: Model
	p := open(&m)
	defer ui.probe_destroy(&p)
	ui.probe_deliver(&p, shapes.Tile{index = 5, px = TILE}, shapes.Tile_Result{path = "/tmp/tile-5.bmp"})
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_click(&p, "Tile 5"))
	ui.probe_frame(&p)
	// Deep in, past level 8, and call that level shown as if its squares
	// had all landed.
	testing.expect(t, ui.probe_scroll(&p, "Viewer", -32 * ui.SCROLL_STEP))
	ui.probe_frame(&p)
	testing.expect(t, m.viewer.level >= 8)
	m.viewer.shown = m.viewer.level
	// Far out again in one go: level 1 is wanted, and the shown level
	// would have thousands of squares in view. A frame asks for level 1
	// and the tile, nothing of the fine level.
	testing.expect(t, ui.probe_scroll(&p, "Viewer", 32 * ui.SCROLL_STEP))
	ui.probe_frame(&p)
	testing.expect_value(t, m.viewer.level, 1)
	testing.expect(t, len(ui.probe_needs(&p)) < 40)
	for n in ui.probe_needs(&p) {
		if q, is := ui.need_as(n, shapes.Patch); is {
			testing.expect(t, q.level <= 1, "no fine-level patch is asked for")
		}
	}
}
