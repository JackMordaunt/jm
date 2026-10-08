/*
Package view is the gallery's ui: a grid of tiles that scrolls, each a
picture the application makes on demand. A tile is needed only while its
row is laid out, and ui.list lays out only the rows in view, so scrolling
a tile away releases its need and the application stops making it. The
header shows how many tiles were made, abandoned and are in the making.
*/
package gallery_view

import "core:fmt"
import "core:math"

import "jm:ui"
import "jm:ui/fluent"
import "jm:ui/ops"

import "../../common"
import "../shapes"

TILE :: 160 // the pixel size layout asks each picture at
PATCH :: 256 // the pixel size of a viewer patch
MAX_PATCHES :: 64 // the most squares one level is asked for in a frame
MARGIN :: 24 // around the viewer
HEADER :: 40 // the viewer's title row
ZOOM_STEP :: 1.25 // per wheel unit
GAP :: 8
TILES :: 10_000 // enough to scroll for a long time
MAX_COLUMNS :: 6


Model :: struct {
	theme:   fluent.Theme,
	scheme:  fluent.Scheme,
	list:    ui.List_State, // the grid's scroll offset; a test sets it to scroll
	columns: int, // tiles per row at the width the frame has; see view
	width:   f32, // the grid's width: the columns and their gaps
	open:    bool, // the viewer is up
	shown:   int, // the tile in it
	window:  ops.Size,
	viewer:  Viewer,
}

// Viewer is the full-window view of one picture, with a map's zoom and
// pan: the plane point at the middle, the plane units a pixel covers,
// and the level whose patches were last complete, kept needed while the
// current level's are still coming so a zoom never shows a gap.
Viewer :: struct {
	center:   [2]f64,
	scale:    f64, // plane units per pixel; 0 until opened
	drag:     ui.Drag,
	sling:    ui.Sling, // the pan a fast release carries on
	shown:    int, // the level fully drawn last
	level:    int, // the level wanted now
}

// Wait is a tile's own memory of when it began waiting for its picture.
@(private)
Wait :: struct {
	since: f64,
	set:   bool,
}

view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Model)(user)
	m.scheme = fluent.theme_scheme(m.theme)
	fluent.use(&m.scheme, fluent.mode_of(m.theme))
	fluent.use_fonts({0, 1, 2})
	s := &m.scheme
	ops.fill(gtx.scene, ops.Rect{0, 0, gtx.constraints.max.x, gtx.constraints.max.y}, s[.Neutral_Background3])

	// As many columns as the width holds, up to MAX_COLUMNS: the grid
	// reflows rather than scrolls sideways. The page is as tall as the
	// window, so the list below the header has a viewport and lays out
	// only the rows in it.
	m.columns = clamp(int((gtx.constraints.max.x - 2 * GAP + GAP) / (TILE + GAP)), 1, MAX_COLUMNS)
	m.width = f32(m.columns * TILE + (m.columns - 1) * GAP)
	m.window = gtx.constraints.max
	// The lightbox first, outside every container: its overlay is placed
	// from the window, and the window's size is what it is given.
	lightbox(gtx, m)
	// The list spans the window, so its scroll bar sits at the window's
	// edge; each row centres its tiles in that width, and the header is
	// centred above it to match.
	ui.column(gtx, gap = 12, align = .Fill)
	{
		ui.column(gtx, align = .Center)
		ui.sized(gtx, {min = {m.width, 0}, max = {m.width, ui.INF}})
		header(gtx, m, m.width)
	}
	ui.list(gtx, &m.list, (TILES + m.columns - 1) / m.columns, row, m)
}

// lightbox is the tile clicked, filling the window, zoomed by the wheel
// about the pointer and panned by dragging, a fast release gliding on as
// a map does (ui.Sling); Escape or the button closes
// it. The picture is drawn as a map is: the small tile scaled under
// everything, then the patches of the level that matches the zoom, each
// a need of its own made on a worker as it comes into view and given up
// as it leaves, so a deep zoom streams in square by square, down to a
// cap of 48 levels, where f64 still tells a patch's points apart.
@(private)
lightbox :: proc(gtx: ^ui.Ctx, m: ^Model) {
	if !m.open {
		m.viewer.scale = 0
		return
	}
	s := &m.scheme
	w, h := m.window.x, m.window.y
	vp := ops.Rect{MARGIN, MARGIN + HEADER, w - 2 * MARGIN, h - 2 * MARGIN - HEADER}
	v := &m.viewer
	if v.scale == 0 {
		v.center = {0, 0}
		v.scale = 3 / f64(min(vp.w, vp.h))
		v.drag, v.sling = {}, {}
		v.shown, v.level = 0, 0
	}

	ui.overlay(gtx, {0, 0}, cs = ui.loose(m.window), root = true, cover = true)
	ui.scope(gtx, m.shown)
	id := ui.claim_id(gtx)
	ops.fill(gtx.scene, ops.Rect{0, 0, w, h}, s[.Neutral_Background1])
	ops.input_area(gtx.scene, id, vp, {.Press, .Release, .Move, .Scroll})
	ops.tag(gtx.scene, id, "Viewer")
	ui.key_interest(gtx, id, .Escape)
	mid := [2]f64{f64(vp.w) / 2, f64(vp.h) / 2}
	for e in ui.events(gtx, id) {
		#partial switch e.kind {
		case .Key:
			if e.key == .Escape {
				m.open = false
			}
		case .Scroll:
			// Wheel up (negative) zooms in; the plane point under the
			// pointer stays under it.
			factor := math.pow(ZOOM_STEP, f64(e.scroll.y))
			at := [2]f64{f64(e.pos.x), f64(e.pos.y)} - mid
			v.center += at * v.scale * (1 - factor)
			v.scale *= factor
		}
	}
	// A drag pans; a fast release glides on, and a press catches it.
	ui.drag_update(&v.drag, ui.events(gtx, id))
	if v.drag.phase != .Idle {
		ui.sling_stop(&v.sling)
	}
	if v.drag.released {
		ui.sling_start(&v.sling, v.drag.velocity, gtx.time)
	}
	glide, gliding := ui.sling_step(&v.sling, gtx.time)
	pan := v.drag.delta + glide
	v.center -= [2]f64{f64(pan.x), f64(pan.y)} * v.scale
	if gliding {
		ui.request_frame(gtx)
	}

	// The level whose patches cover PATCH to 2 PATCH pixels on screen.
	v.level = clamp(int(math.floor(math.log2(3 / (f64(PATCH) * v.scale)))), 0, 48)
	ops.clip_push(gtx.scene, vp)
	if base, ok := ui.need(gtx, shapes.Tile{index = m.shown, px = TILE}, shapes.Tile_Result); ok == .Ready || ok == .Stale {
		bid := ops.add_image(gtx.scene, base.path)
		ops.image(gtx.scene, bid, plane_rect(vp, v, -1.5, -1.5, 3))
	}
	complete := true
	if v.shown != v.level {
		patches(gtx, m, vp, v.shown)
	}
	complete = patches(gtx, m, vp, v.level)
	if complete {
		v.shown = v.level
	}
	ops.clip_pop(gtx.scene)
	viewer_header(gtx, m, w)
}

// patches needs and draws the squares of level that show in vp, and
// reports whether every one of them was drawn.
@(private)
patches :: proc(gtx: ^ui.Ctx, m: ^Model, vp: ops.Rect, level: int) -> (complete: bool) {
	v := &m.viewer
	count := 1 << uint(level)
	size := 3 / f64(count)
	x0 := v.center.x - f64(vp.w) / 2 * v.scale
	y0 := v.center.y - f64(vp.h) / 2 * v.scale
	x1 := v.center.x + f64(vp.w) / 2 * v.scale
	y1 := v.center.y + f64(vp.h) / 2 * v.scale
	ix0 := clamp(int(math.floor((x0 + 1.5) / size)), 0, count - 1)
	ix1 := clamp(int(math.floor((x1 + 1.5) / size)), 0, count - 1)
	iy0 := clamp(int(math.floor((y0 + 1.5) / size)), 0, count - 1)
	iy1 := clamp(int(math.floor((y1 + 1.5) / size)), 0, count - 1)
	if (ix1 - ix0 + 1) * (iy1 - iy0 + 1) > MAX_PATCHES {
		// A level far finer than the zoom, the one kept while zooming
		// out: its squares in view would run to thousands. Nothing is
		// asked; the tile under everything stands in.
		return false
	}
	complete = true
	for iy in iy0 ..= iy1 {
		for ix in ix0 ..= ix1 {
			res, status := ui.need(gtx, shapes.Patch{m.shown, level, ix, iy, PATCH}, shapes.Tile_Result)
			if status != .Ready && status != .Stale {
				complete = false
				continue
			}
			pid := ops.add_image(gtx.scene, res.path)
			ops.image(gtx.scene, pid, plane_rect(vp, v, -1.5 + f64(ix) * size, -1.5 + f64(iy) * size, size))
		}
	}
	return
}

// plane_rect is where the square of the plane at x, y of side size lands
// in vp under the viewer's centre and scale.
@(private)
plane_rect :: proc(vp: ops.Rect, v: ^Viewer, x, y, size: f64) -> ops.Rect {
	sx := f64(vp.x) + f64(vp.w) / 2 + (x - v.center.x) / v.scale
	sy := f64(vp.y) + f64(vp.h) / 2 + (y - v.center.y) / v.scale
	side := size / v.scale
	return {f32(sx), f32(sy), f32(side), f32(side)}
}

@(private)
viewer_header :: proc(gtx: ^ui.Ctx, m: ^Model, w: f32) {
	s := &m.scheme
	v := &m.viewer
	ui.inset(gtx, ui.pad_all(MARGIN))
	ui.row(gtx, align = .Center)
	if common.cell(gtx, w - 2 * MARGIN - 120, .Start) {
		fluent.text(gtx, fmt.tprintf("tile %d · level %d · scroll to zoom, drag to pan", m.shown, v.level), s[.Neutral_Foreground2], .S300, selectable = false)
	}
	if common.cell(gtx, 120, .End) {
		if fluent.button(gtx, "Close", .Subtle, .Dismiss, .Small) {
			m.open = false
		}
	}
}

@(private)
header :: proc(gtx: ^ui.Ctx, m: ^Model, width: f32) {
	s := &m.scheme
	ui.row(gtx, align = .Baseline)
	if common.cell(gtx, 120, .Start) {
		fluent.text(gtx, "gallery", s[.Brand_Foreground1], .S900, .Semibold, selectable = false)
	}
	if common.cell(gtx, width - 120, .End) {
		stats, status := ui.need(gtx, shapes.Stats{}, shapes.Stats_Result)
		line := "every tile is made as it comes into view"
		if status == .Ready || status == .Stale {
			line = fmt.tprintf(
				"%d open · %d made · %d abandoned · %d pending · cache %d images %d KB · %d hits · %d misses · %d evicted",
				stats.open,
				stats.generated,
				stats.cancelled,
				stats.pending,
				stats.cached,
				stats.cache_bytes / 1024,
				stats.hits,
				stats.misses,
				stats.evictions,
			)
		}
		fluent.text(gtx, line, s[.Neutral_Foreground3], .S200, selectable = false, truncate = true, key = 1)
	}
}


// row is one line of the grid: a tile per column, centred, and the gap
// below. Every tile is TILE square whatever it shows, so every row is as
// tall as the one ui.list measures (see its doc).
@(private)
row :: proc(gtx: ^ui.Ctx, index: int, user: rawptr) {
	m := (^Model)(user)
	ui.column(gtx, align = .Center)
	r := ui.row_open(gtx, gap = GAP)
	for c in 0 ..< m.columns {
		if t := index * m.columns + c; t < TILES {
			tile(gtx, m, t)
		}
	}
	ui.close(&r)
	ui.spacer(gtx, GAP)
}

// tile needs its picture and draws it, or what stands in for it: nothing
// for the first common.LOADING_DELAY, then a skeleton.
@(private)
tile :: proc(gtx: ^ui.Ctx, m: ^Model, index: int) {
	ui.scope(gtx, index)
	res, status := ui.need(gtx, shapes.Tile{index = index, px = TILE}, shapes.Tile_Result)
	if status == .Ready || status == .Stale {
		// The picture is a button: an input area its own size under it,
		// so the row keeps the footprint a blank tile has. A release in
		// it opens the lightbox.
		box := ui.sized_open(gtx, {min = {TILE, TILE}, max = {TILE, TILE}})
		area := ui.claim_id(gtx)
		ops.input_area(gtx.scene, area, ops.Rect{0, 0, TILE, TILE}, {.Press, .Release})
		ops.tag(gtx.scene, area, fmt.tprintf("Tile %d", index))
		id := ops.add_image(gtx.scene, res.path)
		fluent.image(gtx, {TILE, TILE}, shape = .Rounded, paint = paint_tile, user = &id)
		ui.close(&box)
		for e in ui.events(gtx, area) {
			if e.kind == .Release {
				m.open, m.shown = true, index
			}
		}
		return
	}
	id := ui.claim_id(gtx)
	w := ui.widget_data(gtx, id, Wait)
	if !w.set {
		w.since, w.set = gtx.time, true
	}
	waited := gtx.time - w.since
	if waited < common.LOADING_DELAY {
		ui.request_frame(gtx, f32(common.LOADING_DELAY - waited))
		blank := ui.sized_open(gtx, {min = {TILE, TILE}, max = {TILE, TILE}})
		ui.close(&blank)
		return
	}
	fluent.skeleton_item(gtx, TILE, .Square)
}

@(private)
paint_tile :: proc(gtx: ^ui.Ctx, rect: ops.Rect, user: rawptr) {
	ops.image(gtx.scene, (^ops.Image_Id)(user)^, rect)
}
