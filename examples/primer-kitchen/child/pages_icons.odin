package main

import "core:fmt"
import "core:slice"
import "core:strings"
import "jm:ui"
import "jm:ui/base"
import "jm:ui/ops"
import "jm:ui/primer"

// Icons is the octicon page's state: the search text, and every icon
// with its octicon name in name order, built the first time the page
// draws.
Icons :: struct {
	search: ui.Text_State,
	sorted: [len(primer.Icon) - 1]Named_Icon,
	seeded: bool,
}

Named_Icon :: struct {
	name: string,
	icon: primer.Icon,
}

ICON_TILE_W :: f32(168)
ICON_GAP    :: f32(8)
ICON_GLYPH  :: f32(24)

// icons_seed names every icon as octicons does, Arrow_Down as
// arrow-down, and sorts them by that name.
icons_seed :: proc(ic: ^Icons) {
	if ic.seeded {
		return
	}
	ic.seeded = true
	for i in primer.Icon {
		if i == .None {
			continue
		}
		name := strings.to_lower(fmt.tprint(i))
		for &c in transmute([]u8)name {
			if c == '_' {
				c = '-'
			}
		}
		ic.sorted[int(i) - 1] = {name, i}
	}
	slice.sort_by(ic.sorted[:], proc(a, b: Named_Icon) -> bool {
		return a.name < b.name
	})
}

// fuzzy_match reports whether every character of query, spaces aside,
// appears in name in order, ignoring case: "arwdn" finds arrow-down.
fuzzy_match :: proc(name, query: string) -> bool {
	at := 0
	for q in transmute([]u8)query {
		if q == ' ' {
			continue
		}
		for at < len(name) && lower(name[at]) != lower(q) {
			at += 1
		}
		if at == len(name) {
			return false
		}
		at += 1
	}
	return true
}

@(private = "file")
lower :: proc(c: u8) -> u8 {
	return c + 32 if c >= 'A' && c <= 'Z' else c
}

// Icon_Grid is what a row of the octicon list draws from: the icons the
// search leaves, and how many fit across.
@(private = "file")
Icon_Grid :: struct {
	m:       ^Model,
	shown:   []Named_Icon,
	columns: int,
}

// The octicon page: every primer.Icon in name order, each tile its
// glyph, octicon name and enum number, filtered as the search is typed.
// The search stays put above a list of tile rows that scrolls itself and
// lays out only the rows in view, so the ~390 tiles cost what a screenful
// does.
page_octicons :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ic := &m.icons
	icons_seed(ic)
	col := ui.column_open(gtx, gap = 16, align = .Fill)
	defer ui.close(&col)
	edit := primer.text_input(
		gtx,
		&ic.search,
		"Filter icons",
		leading = .Search,
		block = true,
		name = "Filter icons",
	)
	query := ui.text_string(&ic.search)
	shown := make([dynamic]Named_Icon, 0, len(ic.sorted), gtx.allocator)
	for n in ic.sorted {
		if fuzzy_match(n.name, query) {
			append(&shown, n)
		}
	}
	base.label(
		gtx,
		fmt.tprintf("%d of %d icons", len(shown), len(ic.sorted)),
		{size = 12, color = m.scheme[.Fg_Color_Muted]},
	)
	grid := Icon_Grid {
		m,
		shown[:],
		max(int((gtx.constraints.max.x + ICON_GAP) / (ICON_TILE_W + ICON_GAP)), 1),
	}
	scroll := &m.scroll[m.page]
	if edit.changed {
		scroll.y = 0
	}
	list := ui.List_State{scroll.y}
	ui.flexible(gtx, 1)
	ui.list(gtx, &list, (len(shown) + grid.columns - 1) / grid.columns, icon_row, &grid)
	scroll.y = list.offset
}

// icon_row is row i of the octicon list: up to a row's worth of tiles,
// and the gap below them.
@(private = "file")
icon_row :: proc(gtx: ^ui.Ctx, i: int, user: rawptr) {
	g := (^Icon_Grid)(user)
	pad := ui.inset_open(gtx, {0, 0, 0, 16})
	defer ui.close(&pad)
	r := ui.row_open(gtx, gap = ICON_GAP)
	defer ui.close(&r)
	for n in g.shown[i * g.columns:min((i + 1) * g.columns, len(g.shown))] {
		icon_tile(gtx, g.m, n)
	}
}

// icon_tile is one icon centred over its name and number.
@(private = "file")
icon_tile :: proc(gtx: ^ui.Ctx, m: ^Model, n: Named_Icon) {
	tile := ui.sized_open(
		gtx,
		{min = {ICON_TILE_W, 0}, max = {ICON_TILE_W, ui.INF}},
		key = u64(n.icon),
	)
	defer ui.close(&tile)
	col := ui.column_open(gtx, gap = 6, align = .Center)
	defer ui.close(&col)
	icon_glyph(gtx, n.icon, m.scheme[.Fg_Color_Default])
	base.label(gtx, n.name, {size = 12})
	base.label(gtx, fmt.tprint(int(n.icon)), {size = 12, color = m.scheme[.Fg_Color_Muted]})
}

// icon_glyph lays i out as a leaf its drawn width wide.
@(private = "file")
icon_glyph :: proc(gtx: ^ui.Ctx, i: primer.Icon, color: ops.Color, loc := #caller_location) {
	w := ui.widget_open(gtx, 0, loc)
	size := ops.Size{primer.icon_width(i, ICON_GLYPH), ICON_GLYPH}
	primer.icon(gtx, i, {}, ICON_GLYPH, color)
	ui.widget_close(gtx, &w, {size, ICON_GLYPH})
}
