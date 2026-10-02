package primer

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
source_12 :: proc(i: Icon) -> (string, f32, ops.Point) {
	return ICON_12[i], 12, {}
}

@(private = "file")
source_16 :: proc(i: Icon) -> (string, f32, ops.Point) {
	return ICON_16[i], 16, {}
}

@(private = "file")
source_24 :: proc(i: Icon) -> (string, f32, ops.Point) {
	return ICON_24[i], 24, {}
}

@(private = "file")
SOURCES := [3]proc(i: Icon) -> (string, f32, ops.Point){source_12, source_16, source_24}

@(private = "file")
has_height :: proc(i: Icon, n: int) -> bool {
	switch n {
	case 0:
		return ICON_12[i] != ""
	case 1:
		return ICON_16[i] != ""
	}
	return ICON_24[i] != ""
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

// icon_path is i's outline at the natural height drawn for size, in that
// height's units with the origin at the top-left, and that height.
icon_path :: proc(i: Icon, size: f32) -> (path: ops.Path, height: f32) {
	n := natural_index(i, size)
	if n < 0 {
		return
	}
	return design.icon_path(&sets[n], SOURCES[n], i)
}

// icon_width is i's drawn width at size: size for a square icon, wider
// for the few that are not (logo-gist, feed-issue-reopen).
icon_width :: proc(i: Icon, size: f32) -> f32 {
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
	n := natural_index(i, size)
	if n < 0 {
		return
	}
	design.paint_icon(gtx, &sets[n], SOURCES[n], i, pos, size, color)
}
