package fluent

import "jm:ui"
import "jm:ui/design"
import "jm:ui/ops"

// Icons are Fluent UI System Icons at 20px, regular and filled, drawn as
// vector paths through design's Icon_Set: icon_data.odin holds each
// icon's SVG path data in its 20-unit viewBox, icon_path parses it once
// per thread, and icon scales that to the requested size. A 24px slot
// (a large button's) draws the 20px path scaled, not the 24px asset.

@(private = "file", thread_local)
icons: design.Icon_Set(Icon)

@(private = "file")
icon_source :: proc(i: Icon) -> (paths: design.Icon_Paths, box: f32, offset: ops.Point) {
	paths.d[0], box = icon_svg(i)
	return
}

// icon_path is i's outline in its 20-unit square with the origin at the
// top-left, parsed on first use and kept for the life of the thread.
icon_path :: proc(i: Icon) -> (path: ops.Path, box: f32) {
	paths: []ops.Path
	paths, box = design.icon_paths(&icons, icon_source, i)
	if len(paths) > 0 {
		path = paths[0] // icon-data refuses an icon of several paths
	}
	return
}

// icon fills i at size pixels with its top-left at pos; None, whose
// path is empty, draws nothing.
icon :: proc(gtx: ^ui.Ctx, i: Icon, pos: ops.Point, size: f32, color: ops.Color) {
	design.paint_icon(gtx, &icons, icon_source, i, pos, size, color)
}

// filled is i's filled twin, which follows it in Icon, or i itself when
// it is already filled: subtle and transparent buttons swap a regular
// icon for its filled one while hovered or pressed (button.json
// behaviour icon-swap).
filled :: proc(i: Icon) -> Icon {
	if i == .None || is_filled(i) {
		return i
	}
	return Icon(int(i) + 1)
}

// is_filled reports whether i is a _Filled member: every regular icon's
// filled twin follows it, so the filled ones sit at even positions.
is_filled :: proc(i: Icon) -> bool {
	return i != .None && int(i) % 2 == 0
}
