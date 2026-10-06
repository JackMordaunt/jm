package plot

import "base:runtime"
import "core:fmt"
import "jm:ui"
import "jm:ui/design"
import "jm:ui/ops"

// Status is whether a chart's data is there to draw.
Status :: enum u8 {
	Ready,
	Loading, // fetching: a chart with data keeps drawing it, faded, until the new data lands
	Error, // the fetch failed: message says why
}

// Chart is what every chart takes besides its data.
Chart :: struct {
	label:   string, // what the chart shows, "Hashrate per facility": a screen reader's name for it
	height:  f32, // 0 takes the height offered, or DEFAULT_HEIGHT when that is unbounded
	status:  Status,
	message: string, // an error's text, or what to say in place of "No data"
	hidden:  ^Series_Set, // the series the legend hid, kept by the caller; nil keeps them in the chart
}

// DEFAULT_HEIGHT and DEFAULT_WIDTH are a chart's size where the space
// offered is unbounded, as in a scroll box.
DEFAULT_HEIGHT :: 280
DEFAULT_WIDTH :: 560

// Plot_State is what a chart keeps between frames: the pointer, focus,
// the point the keyboard is on, and which series are hidden when the
// caller keeps none.
Plot_State :: struct {
	hidden:   Series_Set,
	pointer:  ops.Point,
	hovering: bool,
	focused:  bool,
	keyed:    bool, // the keyboard moved last: the readout shows at index, not under the pointer
	index:    int, // the point or category the keyboard is on
	series:   int, // and the series
}

// Frame is one chart while it draws: where it is, its state, and the
// plotting area its axes leave.
@(private)
Frame :: struct {
	gtx:     ^ui.Ctx,
	style:   ^Plot_Style,
	chart:   ^Chart,
	place:   ui.Placement,
	plot_id: ops.Area_Id,
	size:    ops.Size,
	st:      ^Plot_State,
	hidden:  ^Series_Set,
	top:     f32, // where the legend ends
	plot:    ops.Rect, // the plotting area
	faded:   bool,
	point:   ops.Area_Id, // the focused point's semantic node, 0 for none
}

// frame_open opens the chart's widget and sizes it from what it is offered.
@(private)
frame_open :: proc(gtx: ^ui.Ctx, c: ^Chart, style: ^Plot_Style, key: u64, loc: runtime.Source_Code_Location) -> (f: Frame) {
	f.gtx, f.style, f.chart = gtx, style, c
	f.place = ui.widget_open(gtx, key, loc)
	f.plot_id = ui.id_mix(f.place.id, 1)
	cs := gtx.constraints
	f.size.x = cs.max.x if ui.is_finite(cs.max.x) else DEFAULT_WIDTH
	f.size.y = c.height
	if f.size.y <= 0 {
		f.size.y = cs.max.y if ui.is_finite(cs.max.y) else DEFAULT_HEIGHT
	}
	f.size = ui.constrain(cs, f.size)
	f.st = ui.widget_data(gtx, f.place.id, Plot_State)
	f.hidden = c.hidden if c.hidden != nil else &f.st.hidden
	return
}

// frame_close closes the chart's widget, a group named for the chart, and
// reports its size. The summary goes on the plot, which takes focus; a
// chart with no plot to show has none.
@(private)
frame_close :: proc(f: ^Frame) -> ui.Dims {
	if f.faded {
		ops.opacity_pop(f.gtx.scene)
	}
	ui.semantics(f.gtx, &f.place, {role = .Group, label = f.chart.label})
	return ui.widget_close(f.gtx, &f.place, {size = f.size})
}

// FADED is how strongly a chart still loading new data draws its old.
FADED :: 0.45

// show_status draws the chart's message in place of a plot when there is
// none to draw: an error, a load with nothing yet, or no data. It reports
// whether the plot should be drawn; a load with data fades it.
@(private)
show_status :: proc(f: ^Frame, has_data: bool) -> bool {
	c := f.chart
	msg, color := "", f.style.muted
	switch {
	case c.status == .Error:
		msg, color = c.message if c.message != "" else "Couldn’t load the data", f.style.error
	case c.status == .Loading && !has_data:
		msg = "Loading…"
	case !has_data:
		msg = c.message if c.message != "" else "No data"
	}
	if msg == "" {
		if c.status == .Loading {
			ops.opacity_push(f.gtx.scene, FADED)
			f.faded = true
		}
		return true
	}
	area := ops.Rect{0, f.top, f.size.x, f.size.y - f.top}
	r := shape_fit(f.gtx, msg, f.style.label_size, f.style.font, area.w - 16)
	draw_run(f.gtx, r, {area.x + (area.w - r.width) / 2, area.y + (area.h - run_height(r)) / 2}, color)
	role := ops.Role.Alert if c.status == .Error else .Status
	ui.part_semantics(f.gtx, &f.place, ui.id_mix(f.place.id, 2), area, {role = role, label = ui.frame_string(f.gtx, msg)})
	return false
}

// shown is whether series i is drawn.
@(private)
shown :: proc(f: ^Frame, i: int) -> bool {
	return !(i in f.hidden^)
}

// PLOT_KINDS is what the plotting area listens for: the pointer for the
// crosshair, and focus and keys to walk the points.
@(private)
PLOT_KINDS :: ops.Event_Kinds{.Move, .Enter, .Leave, .Press, .Key, .Focus, .Blur}

// Walk is how many points or categories, and series, the keyboard walks.
@(private)
Walk :: struct {
	count, series: int,
}

// read_plot_events reads the plotting area's input: the pointer's position,
// focus, and the arrow keys, which move the keyboard's point (Left and
// Right, Home and End) and series (Up and Down, skipping hidden ones).
@(private)
read_plot_events :: proc(f: ^Frame, w: Walk) {
	st := f.st
	for e in ui.events(f.gtx, f.plot_id) {
		#partial switch e.kind {
		case .Move, .Enter:
			st.pointer, st.hovering = e.pos, true
			st.keyed = false
		case .Leave:
			st.hovering = false
		case .Focus:
			st.focused = true
			st.keyed = e.key != .None
		case .Blur:
			st.focused, st.keyed = false, false
		case .Key:
			walk_key(f, e.key, w)
		}
	}
	st.index = clamp(st.index, 0, max(w.count - 1, 0))
	if !shown(f, st.series) {
		st.series = next_shown(f, st.series, 1, w.series)
	}
}

// walk_key moves the keyboard's point for key.
@(private)
walk_key :: proc(f: ^Frame, key: ui.Key, w: Walk) {
	st := f.st
	#partial switch key {
	case .Left:
		st.index -= 1
	case .Right:
		st.index += 1
	case .Home:
		st.index = 0
	case .End:
		st.index = w.count - 1
	case .Up:
		st.series = next_shown(f, st.series, -1, w.series)
	case .Down:
		st.series = next_shown(f, st.series, 1, w.series)
	case .Escape:
		st.keyed = false
		return
	case:
		return
	}
	st.keyed = true
}

// next_shown is the series dir steps from from that is shown, wrapping;
// from itself when none other is.
@(private)
next_shown :: proc(f: ^Frame, from, dir, n: int) -> int {
	if n <= 0 {
		return 0
	}
	for k in 1 ..= n {
		i := ((from + dir * k) % n + n) % n
		if shown(f, i) {
			return i
		}
	}
	return clamp(from, 0, n - 1)
}

// plot_listen records the plotting area's input area, and its focus ring
// when the keyboard put focus there.
@(private)
plot_listen :: proc(f: ^Frame) {
	if f.faded {
		return // a chart loading new data takes no input until it lands
	}
	ops.input_area(f.gtx.scene, f.plot_id, f.plot, PLOT_KINDS)
	ops.tag(f.gtx.scene, f.plot_id, f.chart.label, f.plot)
	if f.st.focused && ui.focus_visible(f.gtx) {
		ring := design.Focus_Ring{width = f.style.focus_width, offset = 2, color = f.style.focus}
		c := design.Control{focused = true}
		design.paint_focus_ring(f.gtx, c, {f.plot, 4}, ring)
	}
}

// active is where the readout shows: under the pointer, else at the
// keyboard's point while the plot has focus, else nowhere.
@(private)
Active :: enum u8 {
	None,
	Pointer,
	Keyboard,
}

@(private)
active :: proc(f: ^Frame) -> Active {
	st := f.st
	switch {
	case f.faded:
		return .None
	case st.keyed && st.focused:
		return .Keyboard
	case st.hovering && ops.rect_contains(grow(f.plot, 1), st.pointer):
		return .Pointer
	}
	return .None
}

// point_semantics describes the point the keyboard is on to a screen
// reader, as the plotting area's active descendant: label is what it
// reads, "Norway, Mar 5 2026: 1.2 PH/s".
@(private)
point_semantics :: proc(f: ^Frame, label: string, rect: ops.Rect) {
	f.point = ui.id_mix(f.place.id, 3)
	ui.part_semantics(f.gtx, &f.place, f.point, rect, {role = .Text, label = label}, under = f.plot_id)
}

// plot_semantics describes the plotting area: the chart's name, its
// summary, and the point the keyboard is on.
@(private)
plot_semantics :: proc(f: ^Frame, summary: string) {
	s := ops.Semantics {
		role              = .Group,
		label             = fmt.aprintf("%s, plot", f.chart.label, allocator = f.gtx.allocator),
		description       = summary,
		active_descendant = f.point,
	}
	ui.part_semantics(f.gtx, &f.place, f.plot_id, f.plot, s)
}

grow :: ops.rect_outset
