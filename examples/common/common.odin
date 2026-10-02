/*
Package common is what the example applications share: the fonts a
Fluent window opens with, the delay before a wait is reported, and a
cell, a column of a given width that places its one child, which the
examples' rows are made of so a weighted child never comes before an
unweighted one (see ui.flexible).
*/
package example_common

import "core:os"
import "core:strings"

import "jm:ui"
import "jm:ui/ops"

// LOADING_DELAY is how long a wait lasts before a page says so, in
// seconds. A shape that arrives sooner was never missed, so nothing
// flashes.
LOADING_DELAY :: 0.15

// fonts is Selawik at regular, semibold and bold, the Fluent kit's open
// stand-in for Segoe UI, from the user's font directory (just
// fluent-fonts fetches it), or jm:ui's default font for all three.
fonts :: proc(allocator := context.allocator) -> []ops.Font_Ref {
	dir := strings.concatenate({os.get_env("HOME", allocator), "/.local/share/fonts/selawik/"}, allocator)
	names := [3]string{"selawk.ttf", "selawksb.ttf", "selawkb.ttf"}
	out := make([]ops.Font_Ref, 3, allocator)
	for n, ii in names {
		p := strings.concatenate({dir, n}, allocator)
		out[ii] = {ops.Font_Id(ii), os.exists(p) ? p : ui.default_font()}
	}
	return out
}

// cell_open opens a column of exactly width that places its one child by
// align across it; cell_close ends it.
cell_open :: proc(gtx: ^ui.Ctx, width: f32, align: ui.Align) {
	sized := ui.guard_hold(gtx, ui.Inset)
	sized^ = ui.sized_open(gtx, {min = {width, 0}, max = {width, ui.INF}})
	col := ui.guard_hold(gtx, ui.Flex)
	col^ = ui.column_open(gtx, align = align)
}

cell_close :: proc(gtx: ^ui.Ctx) {
	ui.close(ui.guard_take(gtx, ui.Flex))
	ui.close(ui.guard_take(gtx, ui.Inset))
}
