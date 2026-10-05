/*
Package common is what the example applications share: the fonts a
Fluent window opens with, the delay before a wait is reported, and a
cell, a column of a given width that places its one child, which the
examples' rows are made of so a weighted child never comes before an
unweighted one (see ui.flexible).
*/
package example_common

import "base:runtime"

import "core:os"
import "core:strings"

import "jm:ui"
import "jm:ui/ops"

// MAX_PATH is the longest path a message between threads carries.
MAX_PATH :: 1024

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
		out[ii] = {id = ops.Font_Id(ii), path = os.exists(p) ? p : ui.default_font()}
	}
	return out
}

// cell is a column of exactly width that places its one child by align
// across it, as a guard: `if common.cell(gtx, 120, .End) { … }` closes it
// at the end of the if.
@(deferred_in = cell_close)
cell :: proc(gtx: ^ui.Ctx, width: f32, align: ui.Align, loc := #caller_location) -> bool {
	ui.sized_open(gtx, {min = {width, 0}, max = {width, ui.INF}}, loc = loc)
	ui.column_open(gtx, align = align, loc = loc)
	return true
}

@(private = "file")
cell_close :: proc(gtx: ^ui.Ctx, width: f32, align: ui.Align, loc: runtime.Source_Code_Location) {
	ui.innermost_close(gtx, .Flex)
	ui.innermost_close(gtx, .Inset)
}
