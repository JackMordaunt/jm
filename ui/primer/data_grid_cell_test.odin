package primer

import "core:fmt"
import "core:testing"
import "jm:ui"
import "jm:ui/datagrid"
import "jm:ui/ops"

// A caller's cell slot on a Primer data grid: the grid's own skin, set
// every frame, leaves it in place, and a button it draws takes its own
// presses.

@(private = "file")
Roster :: struct {
	rows:   [][2]string,
	bumped: [dynamic]string,
	g:      Data_Grid, // not first, so a ^Data_Grid passed as user is no ^Roster
}

@(private = "file")
ROSTER_COLS := []datagrid.Column{{id = "name", title = "Name"}, {id = "act", title = "Act"}}

@(private = "file")
roster_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	text :: proc(user: rawptr, row, col: int) -> string {
		return (^Roster)(user).rows[row][col]
	}
	m := (^Roster)(user)
	data_grid(gtx, &m.g, ROSTER_COLS, {user = m, rows = len(m.rows), text = text}, "Roster")
}

// bump_cell draws a Bump button in each Act cell, noting whose was
// clicked.
@(private = "file")
bump_cell :: proc(gtx: ^ui.Ctx, c: ^datagrid.Cell, user: rawptr) -> bool {
	if c.col != 1 {
		return false
	}
	m := (^Roster)(user)
	who := m.rows[c.row][0]
	if button(gtx, fmt.tprintf("Bump %s", who), .Default, .Small) {
		append(&m.bumped, who)
	}
	return true
}

@(test)
test_a_button_in_a_cell_takes_its_press_and_leaves_the_row :: proc(t: ^testing.T) {
	m := new(Roster, context.temp_allocator)
	m.rows = {{"Ada", "a"}, {"Grace", "g"}}
	m.bumped = make([dynamic]string, context.temp_allocator)
	data_grid_init(&m.g, ROSTER_COLS)
	m.g.skin.cell, m.g.skin.cell_user = bump_cell, m
	p: ui.Probe
	ui.probe_init(&p, roster_view, m, ops.Size{600, 300}, allocator = context.temp_allocator)
	defer {
		ui.probe_destroy(&p)
		data_grid_destroy(&m.g)
		free_all(context.temp_allocator)
	}

	testing.expect(t, ui.probe_click(&p, "Bump Grace"))
	testing.expect_value(t, len(m.bumped), 1)
	testing.expect(t, len(m.bumped) == 1 && m.bumped[0] == "Grace", fmt.tprint(m.bumped[:]))
	testing.expect(t, !datagrid.selected(&m.g.grid.sel, 1), "the row stays unselected")
	testing.expect(t, ui.probe_click(&p, "Grace"), "a press on the row's name")
	testing.expect(t, datagrid.selected(&m.g.grid.sel, 1), "selects it")
	testing.expect_value(t, len(m.bumped), 1)
}
