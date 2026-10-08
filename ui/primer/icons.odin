package primer

import "core:mem/virtual"

import "jm:ui"
import "jm:ui/design"
import "jm:ui/ops"

// Icons are Octicons drawn as vector paths through design's Icon_Set.
// An octicon is designed at a few natural heights, 12, 16 and 24px here,
// whose paths differ in detail, so each height has its own data and its
// own parsed-path cache, and a size is drawn from the natural height
// octicons-react picks for it (natural_index), scaled.

@(private = "file", thread_local)
sets: [3]design.Icon_Set(Icon)

@(private = "file", rodata)
NATURAL := [3]f32{12, 16, 24}

@(private = "file")
source_12 :: proc(i: Icon) -> (design.Icon_Paths, f32, ops.Point) {
	return ICON_12[i], 12, {}
}

@(private = "file")
source_16 :: proc(i: Icon) -> (design.Icon_Paths, f32, ops.Point) {
	return ICON_16[i], 16, {}
}

@(private = "file")
source_24 :: proc(i: Icon) -> (design.Icon_Paths, f32, ops.Point) {
	return ICON_24[i], 24, {}
}

@(private = "file")
SOURCES := [3]proc(i: Icon) -> (design.Icon_Paths, f32, ops.Point){source_12, source_16, source_24}

@(private = "file")
has_height :: proc(i: Icon, n: int) -> bool {
	switch n {
	case 0:
		return ICON_12[i].d[0] != ""
	case 1:
		return ICON_16[i].d[0] != ""
	}
	return ICON_24[i].d[0] != ""
}

// natural_index is the index into NATURAL of the design i is drawn from
// at size: the largest natural height at or below size, or the smallest
// i has when size is below them all: closestNaturalHeight in
// octicons-react's renderOcticon.tsx (primer/octicons main, read
// 2026-10-02; the 19.38.0 release has no tag to read it at). -1 when i
// has no design at all (None).
@(private = "file")
natural_index :: proc(i: Icon, size: f32) -> int {
	pick := -1
	for n in 0 ..< len(NATURAL) {
		if !has_height(i, n) {
			continue
		}
		if pick < 0 || NATURAL[n] <= size {
			pick = n
		}
	}
	return pick
}

// An app's own icons, beside the octicons. register_icon gives one an
// Icon past the last octicon, which every proc taking an Icon draws: a
// nav item's, a button's, a label's. Its paths are parsed once, when it
// is registered, so registration happens before the frames that draw
// it, as an app starts; drawing only reads them.

// Custom_Icon is a registered icon: its parsed paths in its own units,
// and the height and width those units are drawn at.
@(private = "file")
Custom_Icon :: struct {
	paths:         []ops.Path,
	height, width: f32,
}

@(private = "file")
customs: [dynamic]Custom_Icon

@(private = "file")
custom_arena: virtual.Arena

// register_icon adds an icon drawn from data, SVG paths in a box height
// units tall and width wide (height when 0), as an octicon's are, and is
// the Icon that draws it. Not safe to call while another thread draws.
register_icon :: proc(data: design.Icon_Paths, height: f32 = 16, width: f32 = 0) -> Icon {
	a := virtual.arena_allocator(&custom_arena)
	paths := make([dynamic]ops.Path, 0, design.ICON_MAX_PATHS, a)
	for d, n in data.d {
		if d == "" {
			continue
		}
		p, _ := design.parse_svg_path(d, a)
		if n in data.even_odd {
			p.rule = .Even_Odd
		}
		append(&paths, p)
	}
	if customs == nil {
		customs = make([dynamic]Custom_Icon, a)
	}
	append(&customs, Custom_Icon{paths[:], height, width > 0 ? width : height})
	return Icon(u16(max(Icon)) + u16(len(customs)))
}

// custom_of is the registered icon i is, if it is one.
@(private = "file")
custom_of :: proc(i: Icon) -> (c: ^Custom_Icon, ok: bool) {
	n := int(u16(i)) - int(u16(max(Icon))) - 1
	if n < 0 || n >= len(customs) {
		return nil, false
	}
	return &customs[n], true
}

// icon_paths is i's outline at the natural height drawn for size, one
// path per <path> of its design, in that height's units with the origin
// at the top-left, and that height.
icon_paths :: proc(i: Icon, size: f32) -> (paths: []ops.Path, height: f32) {
	if c, ok := custom_of(i); ok {
		return c.paths, c.height
	}
	n := natural_index(i, size)
	if n < 0 {
		return
	}
	return design.icon_paths(&sets[n], SOURCES[n], i)
}

// icon_width is i's drawn width at size: size for a square icon, wider
// for the few that are not (logo-gist, feed-issue-reopen).
icon_width :: proc(i: Icon, size: f32) -> f32 {
	if c, ok := custom_of(i); ok {
		return size * c.width / c.height
	}
	n := natural_index(i, size)
	if n < 0 {
		return 0
	}
	w: u8
	switch n {
	case 0:
		w = ICON_WIDTH_12[i]
	case 1:
		w = ICON_WIDTH_16[i]
	case 2:
		w = ICON_WIDTH_24[i]
	}
	if w == 0 {
		return size
	}
	return size * f32(w) / NATURAL[n]
}

// icon fills i at size pixels tall with its top-left at pos; None draws
// nothing.
icon :: proc(gtx: ^ui.Ctx, i: Icon, pos: ops.Point, size: f32, color: ops.Color) {
	if c, ok := custom_of(i); ok {
		if !ui.painted(color) || len(c.paths) == 0 {
			return
		}
		k := size / c.height
		ops.transform_push(gtx.scene, ops.mul(ops.scale(k, k), ops.translate(pos.x, pos.y)))
		for p in c.paths {
			ops.fill(gtx.scene, ops.Path_Ref{ops.add_path(gtx.scene, p)}, color)
		}
		ops.transform_pop(gtx.scene)
		return
	}
	n := natural_index(i, size)
	if n < 0 {
		return
	}
	design.paint_icon(gtx, &sets[n], SOURCES[n], i, pos, size, color)
}
