package datagrid

import "core:fmt"
import "core:testing"
import "jm:ui"
import "jm:ui/ops"

// The cell slot through ui.Probe: a widget a skin draws in a cell takes
// its own presses, and the row under it is left as it was.

@(private = "file")
Bumps :: struct {
	g:      Grid,
	skin:   Skin,
	rows:   [3][2]string,
	ev:     Events,
	bumps:  int,
	bumped: Row_Key,
}

@(private = "file")
BUMP_COLS := []Column{{id = "serial", title = "Serial"}, {id = "bump", title = "Bump"}}

// bump_cell draws a Bump button over the bump column's cells, counting
// its clicks by row, and leaves the other cells to the grid.
@(private = "file")
bump_cell :: proc(gtx: ^ui.Ctx, c: ^Cell, user: rawptr) -> bool {
	if c.col != 1 {
		return false
	}
	m := (^Bumps)(user)
	id := ui.id_mix(ops.Area_Id(0xb0b), u64(c.key))
	ops.input_area(gtx.scene, id, ops.Rect{0, 0, c.size.x, c.size.y}, {.Press, .Release})
	ops.tag(gtx.scene, id, fmt.tprintf("Bump %s", c.text))
	for e in ui.events(gtx, id) {
		if e.kind == .Release {
			m.bumps += 1
			m.bumped = c.key
		}
	}
	return true
}

@(private = "file")
bumps_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	text :: proc(user: rawptr, row, col: int) -> string {
		return (^Bumps)(user).rows[row][col]
	}
	m := (^Bumps)(user)
	src := Source {
		user = m,
		rows = len(m.rows),
		text = text,
	}
	m.ev = grid(gtx, &m.g, BUMP_COLS, src, &m.skin, "Rigs")
}

@(test)
test_a_widget_in_a_cell_takes_its_own_press_and_leaves_the_row :: proc(t: ^testing.T) {
	m := new(Bumps)
	defer free(m)
	m.rows = {{"SN-0", "b0"}, {"SN-1", "b1"}, {"SN-2", "b2"}}
	grid_init(&m.g, BUMP_COLS)
	defer grid_destroy(&m.g)
	m.skin = {
		style     = DEFAULT_STYLE,
		cell      = bump_cell,
		cell_user = m,
	}
	p: ui.Probe
	ui.probe_init(&p, bumps_view, m, {400, 300})
	defer ui.probe_destroy(&p)

	testing.expect(t, ui.probe_click(&p, "Bump b1"))
	testing.expect_value(t, m.bumps, 1)
	testing.expect_value(t, m.bumped, source_key(Source{}, 1))
	testing.expect(t, !selected(&m.g.sel, source_key(Source{}, 1)), "the row stays unselected")
	testing.expect(t, ui.probe_click(&p, "SN-1"), "a press beside the button")
	testing.expect(t, selected(&m.g.sel, source_key(Source{}, 1)), "selects the row")
	testing.expect_value(t, m.bumps, 1)
}
