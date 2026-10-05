package kitchen

import "core:os"
import "core:slice"
import "core:testing"
import "jm:ui"
import "jm:ui/design"
import "jm:ui/ops"

@(private = "file")
grid_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: design.Interaction, key: u64) {
		p := ui.widget_open(gtx, key)
		sz := ui.constrain_min(gtx.constraints, {40, 20})
		ops.tag(gtx.scene, p.id, ui.frame_string(gtx, STATE_NAMES[key % 16]))
		ops.input_area(gtx.scene, p.id, ops.Rect{0, 0, sz.x, sz.y}, {.Press})
		ui.widget_close(gtx, &p, {sz, 0})
	}
	ui.column(gtx)
	state_header(gtx)
	state_row(gtx, user, "Variant", cell, 1)
}

@(private = "file")
cell_rects :: proc(p: ^ui.Probe) -> (r: [len(design.STATES)]ops.Rect) {
	for name, i in STATE_NAMES {
		r[i] = ui.probe_bounds(p, name)
	}
	return
}

@(test)
test_a_state_row_lays_its_cells_in_columns_where_they_fit :: proc(t: ^testing.T) {
	p: ui.Probe
	ui.probe_init(&p, grid_view, nil, {LABEL_W + 5 * CELL_W + 50, 300}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	r := cell_rects(&p)
	for i in 1 ..< len(r) {
		testing.expect_value(t, r[i].y, r[0].y) // one row
		testing.expect(t, r[i].x > r[i - 1].x)
	}
	testing.expect(t, r[0].x >= LABEL_W) // after the label column
}

@(test)
test_a_state_row_stacks_where_its_cells_do_not_fit :: proc(t: ^testing.T) {
	p: ui.Probe
	ui.probe_init(&p, grid_view, nil, {LABEL_W + 2 * CELL_W, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect(t, grid_stacked(&{constraints = {max = {LABEL_W + 2 * CELL_W, 400}}}, CELL_W))
	r := cell_rects(&p)
	testing.expect(t, r[0].x < LABEL_W, "a stacked row puts its cells under the label")
}

@(private = "file")
Kept :: struct {
	page, theme: int,
	scroll:      [MAX_PAGES]ui.Scroll_Offset,
}

@(private = "file")
kept_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	k := (^Kept)(user)
	restore(gtx, &k.page, &k.theme, &k.scroll, 10, 3)
	persist(gtx, k.page, k.theme, &k.scroll)
}

@(test)
test_the_session_survives_a_respawn_clamped_to_what_exists :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	before := Kept{page = 7, theme = 2}
	before.scroll[7].y = 240
	a: ui.Probe
	ui.probe_init(&a, kept_view, &before, {100, 100}, allocator = context.temp_allocator)
	saved := slice.clone(ui.probe_persisted(&a), context.temp_allocator) // the probe's own copy dies with it
	ui.probe_destroy(&a)

	after: Kept
	b: ui.Probe
	ui.probe_init(&b, kept_view, &after, {100, 100}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&b)
	ui.probe_restore(&b, saved)
	ui.probe_frame(&b)
	testing.expect_value(t, after.page, 7)
	testing.expect_value(t, after.theme, 2)
	testing.expect_value(t, after.scroll[7].y, 240)

	// A kitchen with fewer pages or themes than the session names clamps.
	few := Kept{}
	c: ui.Probe
	small :: proc(gtx: ^ui.Ctx, user: rawptr) {
		k := (^Kept)(user)
		restore(gtx, &k.page, &k.theme, &k.scroll, 5, 2)
	}
	ui.probe_init(&c, small, &few, {100, 100}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&c)
	ui.probe_restore(&c, saved)
	ui.probe_frame(&c)
	testing.expect_value(t, few.page, 4)
	testing.expect_value(t, few.theme, 1)
}

@(private = "file")
Flag_Model :: struct {
	page, theme: int,
	open:        bool,
}

@(private = "file")
apply_own_flag :: proc(user: rawptr, args: []string, i: ^int) -> bool {
	f := (^Flag_Model)(user)
	switch args[i^] {
	case "-dark":
		f.theme = 1
	case "-open":
		f.open = true
	case:
		return false
	}
	return true
}

@(test)
test_a_kitchens_own_flags_run_beside_page_and_theme :: proc(t: ^testing.T) {
	f: Flag_Model
	app := App {
		user   = &f,
		pages  = {"Buttons", "Chips"},
		themes = {"Light", "Dark"},
		page   = &f.page,
		theme  = &f.theme,
		flag   = apply_own_flag,
	}
	args := []string{"-dark", "-page", "chips", "-open", "-png"}
	size: ops.Size
	debug: ui.Debug_Flags
	full: bool
	i := 0
	for ; i < len(args); i += 1 {
		if !setting(args, &i, app, false, &size, &debug, &full) {
			break
		}
	}
	testing.expect_value(t, i, 4) // -png is a step, not a setting
	testing.expect_value(t, f.theme, 1)
	testing.expect_value(t, f.page, 1)
	testing.expect(t, f.open)

	// Without a flag proc, a kitchen's own flag is no setting.
	app.flag = nil
	j := 0
	testing.expect(t, !setting(args, &j, app, false, &size, &debug, &full))
}

@(private = "file")
count_frames :: proc(gtx: ^ui.Ctx, user: rawptr) {
	(^int)(user)^ += 1
}

// frames_run is how many frames run draws for the command line args.
@(private = "file")
frames_run :: proc(args: ..string) -> (frames: int) {
	saved := os.args
	defer os.args = saved
	os.args = slice.concatenate([][]string{{"kitchen"}, args}, context.temp_allocator)
	run({ui = count_frames, user = &frames, size = {100, 100}, page = new(int, context.temp_allocator), theme = new(int, context.temp_allocator)})
	return
}

@(test)
test_a_step_runs_only_the_frames_it_needs :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	one := frames_run("-advance", "3")
	two := frames_run("-advance", "3", "-advance", "3")
	testing.expect_value(t, two - one, 3) // no extra frame after a step, as a capture would see
}
