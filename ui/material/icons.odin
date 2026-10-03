package material

import "core:reflect"
import "jm:ui"
import "jm:ui/design"
import "jm:ui/ops"

// icon_name is i's name as a reader says it for an icon-only control, the
// enum's own: "Search", "More_Vert". The string is the one in the enum's
// base:runtime Type_Info_Enum.names table, so it outlives the frame.
icon_name :: proc(i: Icon) -> string {
	name, _ := reflect.enum_name_from_value(i)
	return name
}

// Icons are Material Symbols (Outlined, and the _fill1 variants), drawn as
// vector paths through design's Icon_Set: icon_data.odin holds each
// symbol's SVG path data in the symbols' 960-unit space, icon_path parses
// it once per thread, and icon scales that to the requested size.

@(private = "file", thread_local)
icons: design.Icon_Set(Icon)

// icon_source is each symbol's path data and box; a 960 box's viewBox
// starts at y = -960, so its points move down by that.
@(private = "file")
icon_source :: proc(i: Icon) -> (paths: design.Icon_Paths, box: f32, offset: ops.Point) {
	paths.d[0], box = icon_svg(i)
	if box == 960 {
		offset.y = 960
	}
	return
}

// icon_path is i's outline in a box-unit square with its origin at the
// top-left (box is 960 for current symbols, 24 for a few older ones),
// parsed on first use and kept for the life of the thread.
icon_path :: proc(i: Icon) -> (path: ops.Path, box: f32) {
	paths: []ops.Path
	paths, box = design.icon_paths(&icons, icon_source, i)
	if len(paths) > 0 {
		path = paths[0] // a symbol is one path
	}
	return
}

// icon fills i at size pixels with its top-left at pos.
icon :: proc(gtx: ^ui.Ctx, i: Icon, pos: ops.Point, size: f32, color: ops.Color) {
	if i == .None {
		return
	}
	design.paint_icon(gtx, &icons, icon_source, i, pos, size, color)
}

// parse_svg_path is design's: SVG path data as an ops.Path.
parse_svg_path :: design.parse_svg_path
