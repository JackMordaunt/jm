package plot

import "core:fmt"
import "core:math"
import "core:mem"
import "core:slice"
import "core:strings"
import "core:testing"
import "jm:ui"
import "jm:ui/ops"

// Page is a chart under test: one line, bar or box chart filling a
// window, over data the tests set.
@(private = "file")
Page :: struct {
	style:       Plot_Style,
	kind:        enum {
		Line,
		Bar,
		Box,
	},
	line:        Line_Chart,
	bar:         Bar_Chart,
	box:         Box_Chart,
	// allocations is how many allocations the charts asked of the
	// context's allocators while counted, for the steady-state check.
	counted:     bool,
	allocations: int,
}

@(private = "file")
page :: proc(gtx: ^ui.Ctx, user: rawptr) {
	pg := (^Page)(user)
	track: mem.Tracking_Allocator
	if pg.counted {
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)
		context.temp_allocator = context.allocator
	}
	switch pg.kind {
	case .Line:
		line_chart(gtx, &pg.line, &pg.style)
	case .Bar:
		bar_chart(gtx, &pg.bar, &pg.style)
	case .Box:
		box_chart(gtx, &pg.box, &pg.style)
	}
	if pg.counted {
		pg.allocations += int(track.total_allocation_count)
		mem.tracking_allocator_destroy(&track)
	}
}

@(private = "file")
NAMES := []string{"Norway", "Paraguay", "Wisconsin"}

// three_lines is three series over ten days, the second with a gap.
@(private = "file")
three_lines :: proc(pg: ^Page) {
	xs := make([]f64, 10, context.temp_allocator)
	series := make([]Line_Series, 3, context.temp_allocator)
	for s in 0 ..< 3 {
		ys := make([]f64, 10, context.temp_allocator)
		for i in 0 ..< 10 {
			ys[i] = f64((s + 1) * 100 + i)
		}
		series[s] = {
			name = NAMES[s],
			ys   = ys,
		}
	}
	series[1].ys[4] = math.nan_f64()
	for i in 0 ..< 10 {
		xs[i] = 1767225600 + f64(i) * DAY
	}
	pg.style = default_style()
	pg.kind = .Line
	pg.line = {
		label = "Hashrate",
		xs = xs,
		series = series,
		x = {kind = .Time},
		y = {format = {unit = "TH/s", space = true}},
	}
}

@(private = "file")
open :: proc(p: ^ui.Probe, pg: ^Page) {
	ui.probe_init(p, page, pg, {800, 400}, allocator = context.temp_allocator)
}

@(private = "file")
semantics :: proc(p: ^ui.Probe) -> string {
	return ui.probe_semantics(p, context.temp_allocator)
}

@(test)
test_hovering_shows_every_series_at_the_nearest_x :: proc(t: ^testing.T) {
	pg: Page
	three_lines(&pg)
	p: ui.Probe
	open(&p, &pg)
	defer ui.probe_destroy(&p)
	testing.expect(
		t,
		!strings.contains(semantics(&p), "tooltip"),
		"no readout before the pointer comes",
	)
	plot := ui.probe_bounds(&p, "Hashrate")
	// A quarter of the way along ten days is day 2.25: the nearest is day 2.
	ui.probe_move(&p, plot.x + plot.w * 0.25, plot.y + plot.h / 2)
	ui.probe_frame(&p)
	sem := semantics(&p)
	testing.expectf(
		t,
		strings.contains(sem, `tooltip "Sat Jan 3, 2026"`),
		"the readout names the x:\n%s",
		sem,
	)
	testing.expectf(
		t,
		strings.contains(sem, "102 TH/s Norway; 202 TH/s Paraguay; 302 TH/s Wisconsin"),
		"and lists every series there:\n%s",
		sem,
	)
	// At the gap, the series with none says so rather than dropping out.
	ui.probe_move(&p, plot.x + plot.w * 4 / 9, plot.y + plot.h / 2)
	ui.probe_frame(&p)
	testing.expectf(
		t,
		strings.contains(semantics(&p), `\u2013 Paraguay`),
		"a gap reads as a dash:\n%s",
		semantics(&p),
	)
	ui.probe_move(&p, 2, 2)
	ui.probe_frame(&p)
	testing.expect(
		t,
		!strings.contains(semantics(&p), "tooltip"),
		"the readout goes with the pointer",
	)
}

@(test)
test_the_legend_toggles_a_series :: proc(t: ^testing.T) {
	pg: Page
	three_lines(&pg)
	p: ui.Probe
	open(&p, &pg)
	defer ui.probe_destroy(&p)
	testing.expectf(
		t,
		strings.contains(semantics(&p), `checkbox "Paraguay" checked`),
		"shown to begin with:\n%s",
		semantics(&p),
	)
	testing.expect(t, ui.probe_click(&p, "Paraguay"), "the legend entry is there to click")
	ui.probe_frame(&p)
	testing.expectf(
		t,
		strings.contains(semantics(&p), `checkbox "Paraguay"`) &&
		!strings.contains(semantics(&p), `checkbox "Paraguay" checked`),
		"unchecked once clicked:\n%s",
		semantics(&p),
	)
	plot := ui.probe_bounds(&p, "Hashrate")
	ui.probe_move(&p, plot.x + plot.w * 0.25, plot.y + plot.h / 2)
	ui.probe_frame(&p)
	sem := semantics(&p)
	testing.expectf(
		t,
		strings.contains(sem, "102 TH/s Norway; 302 TH/s Wisconsin"),
		"a hidden series leaves the readout:\n%s",
		sem,
	)
	testing.expect(t, ui.probe_click(&p, "Paraguay"), "and clicks back")
	ui.probe_frame(&p)
	testing.expect(
		t,
		strings.contains(semantics(&p), `checkbox "Paraguay" checked`),
		"shown again",
	)
}

@(test)
test_a_caller_can_keep_the_hidden_series :: proc(t: ^testing.T) {
	pg: Page
	three_lines(&pg)
	hidden: Series_Set
	pg.line.chart.hidden = &hidden
	p: ui.Probe
	open(&p, &pg)
	defer ui.probe_destroy(&p)
	ui.probe_click(&p, "Wisconsin")
	ui.probe_frame(&p)
	testing.expect_value(t, hidden, Series_Set{2})
}

@(test)
test_the_keyboard_walks_points_and_series :: proc(t: ^testing.T) {
	pg: Page
	three_lines(&pg)
	p: ui.Probe
	open(&p, &pg)
	defer ui.probe_destroy(&p)
	// Tab reaches the legend's entries, one stop, then the plot.
	ui.probe_key(&p, .Tab)
	ui.probe_frame(&p)
	ui.probe_key(&p, .Tab)
	ui.probe_frame(&p)
	sem := semantics(&p)
	testing.expectf(
		t,
		strings.contains(sem, `active "Norway, Thu Jan 1, 2026: 100 TH/s"`),
		"focus lands on the first point:\n%s",
		sem,
	)
	ui.probe_key(&p, .Right)
	ui.probe_frame(&p)
	ui.probe_key(&p, .Down)
	ui.probe_frame(&p)
	sem = semantics(&p)
	testing.expectf(
		t,
		strings.contains(sem, `active "Paraguay, Fri Jan 2, 2026: 201 TH/s"`),
		"right then down:\n%s",
		sem,
	)
	testing.expect(t, strings.contains(sem, "tooltip"), "the readout follows the keyboard")
	ui.probe_key(&p, .End)
	ui.probe_frame(&p)
	testing.expect(
		t,
		strings.contains(semantics(&p), "Paraguay, Sat Jan 10, 2026: 209 TH/s"),
		"End goes to the last point",
	)
	ui.probe_key(&p, .Up)
	ui.probe_frame(&p)
	ui.probe_key(&p, .Up)
	ui.probe_frame(&p)
	testing.expectf(
		t,
		strings.contains(semantics(&p), "Wisconsin, Sat Jan 10, 2026"),
		"Up wraps round the series:\n%s",
		semantics(&p),
	)
}

@(test)
test_the_keyboard_skips_a_hidden_series :: proc(t: ^testing.T) {
	pg: Page
	three_lines(&pg)
	hidden := Series_Set{1}
	pg.line.chart.hidden = &hidden
	p: ui.Probe
	open(&p, &pg)
	defer ui.probe_destroy(&p)
	ui.probe_key(&p, .Tab)
	ui.probe_frame(&p)
	ui.probe_key(&p, .Tab)
	ui.probe_frame(&p)
	ui.probe_key(&p, .Down)
	ui.probe_frame(&p)
	testing.expectf(
		t,
		strings.contains(semantics(&p), `active "Wisconsin, Thu Jan 1, 2026`),
		"Down passes Paraguay by:\n%s",
		semantics(&p),
	)
}

@(test)
test_plain_states_say_what_is_wrong :: proc(t: ^testing.T) {
	pg: Page
	three_lines(&pg)
	pg.line.status = .Error
	pg.line.message = "The pool API timed out"
	p: ui.Probe
	open(&p, &pg)
	defer ui.probe_destroy(&p)
	testing.expectf(
		t,
		strings.contains(semantics(&p), `alert "The pool API timed out"`),
		"an error:\n%s",
		semantics(&p),
	)
	pg.line.status = .Loading
	ui.probe_frame(&p)
	testing.expect(
		t,
		!strings.contains(semantics(&p), "status"),
		"loading with data keeps drawing it",
	)
	pg.line.series = nil
	ui.probe_frame(&p)
	testing.expectf(
		t,
		strings.contains(semantics(&p), `status "Loading\u2026"`),
		"loading with none:\n%s",
		semantics(&p),
	)
	pg.line.status = .Ready
	ui.probe_frame(&p)
	testing.expect(
		t,
		strings.contains(semantics(&p), `status "The pool API timed out"`),
		"message stands in for No data",
	)
	pg.line.message = ""
	ui.probe_frame(&p)
	testing.expectf(
		t,
		strings.contains(semantics(&p), `status "No data"`),
		"and none at all:\n%s",
		semantics(&p),
	)
}

@(test)
test_bars_read_their_category :: proc(t: ^testing.T) {
	pg: Page
	pg.style = default_style()
	pg.kind = .Bar
	a := []f64{10, -4, 7}
	b := []f64{5, 6, math.nan_f64()}
	series := []Bar_Series{{name = "Invoices", values = a}, {name = "Refunds", values = b}}
	pg.bar = {
		label = "Sales",
		categories = {"Jan", "Feb", "Mar"},
		series = series,
		stacked = true,
		value = {format = {prefix = "$"}},
	}
	p: ui.Probe
	open(&p, &pg)
	defer ui.probe_destroy(&p)
	plot := ui.probe_bounds(&p, "Sales")
	ui.probe_move(&p, plot.x + plot.w / 2, plot.y + plot.h / 2)
	ui.probe_frame(&p)
	sem := semantics(&p)
	testing.expectf(
		t,
		strings.contains(sem, `tooltip "Feb"`) &&
		strings.contains(sem, `\u2212$4.00 Invoices; $6.00 Refunds; $2.00 Total`),
		"the middle category:\n%s",
		sem,
	)
}

@(test)
test_boxes_read_their_summary_and_name_an_outlier :: proc(t: ^testing.T) {
	pg: Page
	pg.style = default_style()
	pg.kind = .Box
	boxes := make([]Box_Stats, 1, context.temp_allocator)
	boxes[0] = box_stats({1, 2, 3, 4, 5, 6, 7, 8, 9, 100}, context.temp_allocator)
	names := [][]string{{"rig 7"}}
	series := []Box_Series{{name = "Rigs", boxes = boxes, outlier_names = names}}
	pg.box = {
		label      = "Efficiency",
		categories = {"Norway"},
		series     = series,
	}
	p: ui.Probe
	open(&p, &pg)
	defer ui.probe_destroy(&p)
	plot := ui.probe_bounds(&p, "Efficiency")
	ui.probe_move(&p, plot.x + plot.w / 2, plot.y + plot.h * 0.95)
	ui.probe_frame(&p)
	sem := semantics(&p)
	testing.expectf(
		t,
		strings.contains(
			sem,
			`5.50 Rigs; 3.25 \u2013 7.75 middle half; 1.00 \u2013 9.00 whiskers`,
		),
		"the summary:\n%s",
		sem,
	)
	// The outlier, 100, sits at the top of the plot.
	ui.probe_move(&p, plot.x + plot.w / 2, plot.y + 1)
	ui.probe_frame(&p)
	sem = semantics(&p)
	testing.expectf(t, strings.contains(sem, "100 rig 7"), "the outlier by name:\n%s", sem)
}

@(test)
test_a_steady_frame_asks_no_allocator :: proc(t: ^testing.T) {
	pg: Page
	three_lines(&pg)
	p: ui.Probe
	open(&p, &pg)
	defer ui.probe_destroy(&p)
	plot := ui.probe_bounds(&p, "Hashrate")
	ui.probe_move(&p, plot.x + plot.w / 2, plot.y + plot.h / 2)
	ui.probe_frame(&p) // the first frames make the chart's retained state
	pg.counted = true
	for _ in 0 ..< 3 {
		ui.probe_frame(&p)
	}
	testing.expectf(
		t,
		pg.allocations == 0,
		"the charts asked context's allocators %d times; a frame's work belongs on gtx.allocator",
		pg.allocations,
	)
	testing.expect(
		t,
		strings.contains(semantics(&p), "tooltip"),
		"with the readout showing, so its work was counted too",
	)
}

@(test)
test_ten_thousand_points_draw_as_columns :: proc(t: ^testing.T) {
	pg: Page
	pg.style = default_style()
	pg.kind = .Line
	n := 10_000
	xs := make([]f64, n, context.temp_allocator)
	series := make([]Line_Series, 5, context.temp_allocator)
	for s in 0 ..< 5 {
		ys := make([]f64, n, context.temp_allocator)
		for i in 0 ..< n {
			ys[i] = math.sin(f64(i) * 0.01 + f64(s)) * 100 + f64(i % 7)
		}
		series[s] = {
			name = NAMES[s % 3],
			ys   = ys,
		}
	}
	for i in 0 ..< n {
		xs[i] = f64(i)
	}
	pg.line = {
		label  = "Dense",
		xs     = xs,
		series = series,
	}
	p: ui.Probe
	open(&p, &pg)
	defer ui.probe_destroy(&p)
	points := 0
	for path in p.scene.paths {
		points += len(path.points)
	}
	plot := ui.probe_bounds(&p, "Dense")
	testing.expect(t, plot.w > 100, "the plot is there")
	// Four a column a series at most, besides the axes' few paths; and the
	// wave crosses every column, so each series keeps at least two there.
	testing.expectf(
		t,
		points < 5 * 4 * int(plot.w + 2) + 200,
		"%d points drawn for 50,000 over %v columns",
		points,
		plot.w,
	)
	testing.expectf(
		t,
		points > 5 * 2 * int(plot.w),
		"%d points drawn: the lines are not all there",
		points,
	)
}

@(test)
test_x_ticks_stand_inside_the_plot :: proc(t: ^testing.T) {
	pg: Page
	three_lines(&pg)
	p: ui.Probe
	open(&p, &pg)
	defer ui.probe_destroy(&p)
	plot := ui.probe_bounds(&p, "Hashrate")
	marks := 0
	for op in p.scene.ops {
		f, ok := op.(ops.Fill)
		r, is_rect := f.shape.(ops.Rect)
		// A tick mark is a hairline 4 units tall under the plot.
		if !ok || !is_rect || r.h != 4 || r.y < plot.y + plot.h - 1 {
			continue
		}
		marks += 1
		testing.expectf(
			t,
			r.x >= plot.x - 1 && r.x <= plot.x + plot.w + 1,
			"a tick mark at %v, outside the plot %v",
			r.x,
			plot,
		)
	}
	testing.expect(t, marks >= 2, "the axis has tick marks to check")
}

// series_path is the points of the longest path stroked in color: a
// series' line, which a legend key's short stroke in the same colour
// would otherwise stand in for.
@(private = "file")
series_path :: proc(p: ^ui.Probe, color: ops.Color) -> (pts: []ops.Point) {
	for op in p.scene.ops {
		s, ok := op.(ops.Stroke)
		ref, is_path := s.shape.(ops.Path_Ref)
		c, solid := s.paint.(ops.Color)
		if ok && is_path && solid && c == color && len(p.scene.paths[ref.id].points) > len(pts) {
			pts = p.scene.paths[ref.id].points
		}
	}
	return
}

@(private = "file")
one_line :: proc(pg: ^Page, ys: []f64) {
	xs := make([]f64, len(ys), context.temp_allocator)
	for i in 0 ..< len(ys) {
		xs[i] = f64(i)
	}
	series := make([]Line_Series, 1, context.temp_allocator)
	series[0] = {
		name = "Hashrate",
		ys   = ys,
	}
	pg.style = default_style()
	pg.kind = .Line
	pg.line = {
		label  = "Line",
		xs     = xs,
		series = series,
	}
}

@(test)
test_a_log_axis_spaces_decades_evenly :: proc(t: ^testing.T) {
	pg: Page
	one_line(&pg, {1, 10, 100, 1000})
	pg.line.y.scale = .Log
	p: ui.Probe
	open(&p, &pg)
	defer ui.probe_destroy(&p)
	pts := series_path(&p, pg.style.series[0].color)
	testing.expect_value(t, len(pts), 4)
	if len(pts) == 4 {
		d0, d1, d2 := pts[1].y - pts[0].y, pts[2].y - pts[1].y, pts[3].y - pts[2].y
		testing.expectf(t, d0 < 0, "the line rises: %v", pts)
		testing.expectf(t, abs(d1 - d0) < 0.5 && abs(d2 - d0) < 0.5, "decades apart: %v", pts)
	}
}

@(test)
test_a_step_line_turns_at_each_point :: proc(t: ^testing.T) {
	pg: Page
	one_line(&pg, {1, 3, 2})
	pg.line.step = .After
	p: ui.Probe
	open(&p, &pg)
	defer ui.probe_destroy(&p)
	pts := series_path(&p, pg.style.series[0].color)
	// Each point after the first is reached level, then up or down.
	testing.expectf(t, len(pts) == 5, "a corner before each later point: %v", pts)
	if len(pts) == 5 {
		testing.expect(t, pts[1].y == pts[0].y && pts[1].x == pts[2].x, "level, then up")
		testing.expect(t, pts[3].y == pts[2].y && pts[3].x == pts[4].x, "level, then down")
	}
}

@(test)
test_an_area_fills_a_wash_under_its_line :: proc(t: ^testing.T) {
	pg: Page
	one_line(&pg, {1, 3, 2})
	pg.line.fill = .Area
	p: ui.Probe
	open(&p, &pg)
	defer ui.probe_destroy(&p)
	wash := ops.with_alpha(pg.style.series[0].color, pg.style.area_alpha)
	found := false
	plot := ui.probe_bounds(&p, "Line")
	for op in p.scene.ops {
		f, ok := op.(ops.Fill)
		ref, is_path := f.shape.(ops.Path_Ref)
		c, solid := f.paint.(ops.Color)
		if !ok || !is_path || !solid || c != wash {
			continue
		}
		found = true
		pts := p.scene.paths[ref.id].points
		bottom := pts[len(pts) - 1].y
		testing.expectf(
			t,
			abs(bottom - (plot.y + plot.h)) < 1,
			"down to zero, the plot's foot: %v",
			pts,
		)
	}
	testing.expect(t, found, "the area is filled in a wash of the line's colour")
}

@(private = "file")
two_axes :: proc(pg: ^Page) {
	xs := make([]f64, 4, context.temp_allocator)
	for i in 0 ..< 4 {
		xs[i] = f64(i)
	}
	sales, rigs := [4]f64{12000, 18000, 9000, 20000}, [4]f64{3, 5, 2, 6}
	series := make([]Line_Series, 2, context.temp_allocator)
	series[0] = {
		name = "Total sales",
		ys   = slice.clone(sales[:], context.temp_allocator),
	}
	series[1] = {
		name  = "Rig count",
		ys    = slice.clone(rigs[:], context.temp_allocator),
		right = true,
	}
	pg.style = default_style()
	pg.kind = .Line
	pg.line = {
		label = "Sales",
		xs = xs,
		series = series,
		y = {title = "Sales", format = {prefix = "$", short = .Finance}},
		y2 = {title = "Rigs", format = {digits = 1}},
	}
}

@(test)
test_a_second_axis_reads_its_own_series :: proc(t: ^testing.T) {
	pg: Page
	two_axes(&pg)
	p: ui.Probe
	open(&p, &pg)
	defer ui.probe_destroy(&p)
	plot := ui.probe_bounds(&p, "Sales")
	right := 0
	for op in p.scene.ops {
		if g, ok := op.(ops.Glyphs); ok && g.origin.x > plot.x + plot.w {
			right += 1
		}
	}
	testing.expectf(t, right >= 2, "the right axis has %d labels", right)
	// Both lines span the plot's height, each on its own scale.
	for s in 0 ..< 2 {
		pts := series_path(&p, pg.style.series[s].color)
		lo, hi := max(f32), min(f32)
		for q in pts {
			lo, hi = min(lo, q.y), max(hi, q.y)
		}
		testing.expectf(t, hi - lo > plot.h / 3, "series %d spans %v of %v", s, hi - lo, plot.h)
	}
	ui.probe_move(&p, plot.x + plot.w / 3, plot.y + plot.h / 2)
	ui.probe_frame(&p)
	sem := semantics(&p)
	testing.expectf(
		t,
		strings.contains(sem, "$18.0k Total sales; 5 Rig count"),
		"each in its format:\n%s",
		sem,
	)
}

@(private = "file")
bars :: proc(pg: ^Page, categories: []string, series: []Bar_Series) {
	pg.style = default_style()
	pg.kind = .Bar
	pg.bar = {
		label      = "Bars",
		categories = categories,
		series     = series,
	}
}

@(test)
test_horizontal_bars_read_the_category_under_the_pointer :: proc(t: ^testing.T) {
	pg: Page
	rigs := []Bar_Series{{name = "Rigs", values = {212, 1046, 588}}}
	bars(&pg, {"Ethiopia", "Norway", "Paraguay"}, rigs)
	pg.bar.horizontal = true
	p: ui.Probe
	open(&p, &pg)
	defer ui.probe_destroy(&p)
	plot := ui.probe_bounds(&p, "Bars")
	ui.probe_move(&p, plot.x + 10, plot.y + plot.h / 2)
	ui.probe_frame(&p)
	sem := semantics(&p)
	testing.expectf(t, strings.contains(sem, `tooltip "Norway"`), "the middle row:\n%s", sem)
	testing.expectf(
		t,
		strings.contains(sem, "1.05k Rigs") || strings.contains(sem, "1046 Rigs"),
		"%s",
		sem,
	)
}

@(test)
test_grouped_bars_walk_bar_by_bar :: proc(t: ^testing.T) {
	pg: Page
	series := []Bar_Series {
		{name = "Invoices", values = {10, 12}},
		{name = "Refunds", values = {-2, -3}},
	}
	bars(&pg, {"Jan", "Feb"}, series)
	p: ui.Probe
	open(&p, &pg)
	defer ui.probe_destroy(&p)
	ui.probe_key(&p, .Tab) // the legend
	ui.probe_frame(&p)
	ui.probe_key(&p, .Tab) // the plot
	ui.probe_frame(&p)
	ui.probe_key(&p, .Right)
	ui.probe_frame(&p)
	ui.probe_key(&p, .Down)
	ui.probe_frame(&p)
	sem := semantics(&p)
	testing.expectf(
		t,
		strings.contains(sem, `active "Refunds, Feb: \u22123.00"`),
		"the second bar of the second group:\n%s",
		sem,
	)
}

@(test)
test_a_crowded_category_axis_turns_and_thins_its_labels :: proc(t: ^testing.T) {
	pg: Page
	n :: 60
	names := make([]string, n, context.temp_allocator)
	values := make([]f64, n, context.temp_allocator)
	for i in 0 ..< n {
		names[i] = fmt.aprintf("Client account %02d", i, allocator = context.temp_allocator)
		values[i] = f64(i)
	}
	bars(&pg, names, {{name = "Rigs", values = values}})
	p: ui.Probe
	open(&p, &pg)
	defer ui.probe_destroy(&p)
	turned, labels := 0, 0
	for op in p.scene.ops {
		#partial switch v in op {
		case ops.Push_Transform:
			turned += 1
		case ops.Glyphs:
			labels += 1
		}
	}
	testing.expect(t, turned > 0, "the labels turn")
	testing.expectf(t, labels < n, "%d labels drawn for %d categories: they thin", labels, n)
	// Twelve short ones fit level.
	bars(&pg, names[:12], {{name = "Rigs", values = values[:12]}})
	for &name, i in names[:12] {
		name = fmt.aprintf("%d", i, allocator = context.temp_allocator)
	}
	ui.probe_frame(&p)
	turned, labels = 0, 0
	for op in p.scene.ops {
		#partial switch v in op {
		case ops.Push_Transform:
			turned += 1
		case ops.Glyphs:
			labels += 1
		}
	}
	testing.expect_value(t, turned, 0)
	testing.expectf(t, labels >= 12, "%d labels drawn: every category's is there", labels)
}
