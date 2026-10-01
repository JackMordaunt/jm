package material

import "core:fmt"
import "jm:ui/ops"
import "core:math"
import "jm:ui"
import tok "jm:ui/material/tokens"

// Sliders, progress indicators and the loading indicator, from the
// m3e-kit's components/slider.json, progress-indicator.json and
// loading-indicator.json, which cite Compose's Slider.kt,
// ProgressIndicator.kt, WavyProgressIndicator.kt and LoadingIndicator.kt.

// Slider_Track is how a slider fills: Standard from the track's start to
// the handle, Centered from the track's midpoint toward the handle, for a
// range that straddles a zero such as -100..100.
Slider_Track :: enum u8 {
	Standard,
	Centered,
}

// Value_Indicator is when a slider shows its value in a label above the
// handle, after MDC's labelBehavior: Floating while the handle is pressed
// or dragged, or Always, or Never.
Value_Indicator :: enum u8 {
	Floating,
	Always,
	Never,
}

// slider is M3 Expressive's slider: value^ in [lo, hi] on a 16dp track,
// with a 4dp bar of a handle that narrows to half its width while pressed,
// dragged or focused, and a gap either side of it that widens to match. A
// press jumps the handle there and a drag follows it. step > 0 snaps to
// multiples of step, drawing a stop dot at each, and snaps on every move
// of a drag, not only on release. While focused, arrow keys move by one
// step (1% of the range when continuous), Page Up and Page Down by a
// tenth of the steps (10% when continuous), Home and End to either end.
//
// width is the slider's length, handle included: its height when
// vertical. vertical stands it up with lo at the top, or at the bottom
// when top_to_bottom is false. start_icon and end_icon are inset in the
// track at either end (Standard track only). Returns true when value^
// changed.
//
// Neither the kit nor Compose sizes the value indicator or the inset
// icons, so both are chosen here (see VALUE_INDICATOR_PAD and
// INSET_ICON_SIZE). The kit has one size of slider: MDC's XS to XL sizes
// have no tokens in it, so they are not offered. The focus ring shows on
// any focus, a pointer's too, since jm:ui does not say which gave it.
//
// The slider shows no text of its own, so a reader needs name, or
// labelled_by: the id of the caption that names it. An app draws the
// caption with base.label, keeps the id it returns, and passes that in.
slider :: proc(
	gtx: ^ui.Ctx,
	value: ^f32,
	lo: f32 = 0,
	hi: f32 = 1,
	step: f32 = 0,
	width: f32 = 240,
	track := Slider_Track.Standard,
	vertical := false,
	top_to_bottom := true,
	start_icon := Icon.None,
	end_icon := Icon.None,
	indicator := Value_Indicator.Floating,
	state := Interaction.Live,
	name := "",
	labelled_by: ops.Area_Id = 0,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_open(gtx, key, loc)
	g := slider_geom(width, vertical, top_to_bottom, lo, hi, step)
	size := ui.constrain(gtx.constraints, g.vertical ? ops.Size{g.cross, g.length} : ops.Size{g.length, g.cross})
	g = slider_geom(vertical ? size.y : size.x, vertical, top_to_bottom, lo, hi, step)
	old := value^
	c := slider_state(gtx, p.id, state)
	if c.st != nil {
		vals := [2]^f32{value, nil}
		apply_slider_input(gtx, p.id, c.st, g, vals[:1], lo, hi, step)
		c.hovered, c.pressed, c.focused = c.st.hovered, c.st.pressed, c.st.focused
	}
	icons := track == .Standard ? [2]Icon{start_icon, end_icon} : {}
	paint_slider(gtx, c, g, lo, hi, {value^, value^}, false, track == .Centered, 1, icons, indicator)
	listen(gtx, c, p.id, ops.Rect{0, 0, size.x, size.y}, SLIDER_KINDS)
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, name != "" ? name : "slider"))
	ui.semantics(gtx, &p, {role = .Slider, label = name, labelled_by = labelled_by, value = slider_value_text(gtx, value^, hi - lo), states = states_of(c)})
	ui.widget_close(gtx, &p, {size = size})
	return value^ != old
}

// range_slider is slider with two handles, lo_value^ <= hi_value^. A
// press takes whichever handle is nearer; Tab while focused moves the keys
// to the other handle. Handles meet but never cross: the moving one stops
// at the other. It is horizontal and standard-track only: slider.json's
// orientation input says Compose's VerticalSlider is single-value only,
// and its centered track is a single slider's track slot. name and
// labelled_by name it to a reader, as slider's do.
range_slider :: proc(
	gtx: ^ui.Ctx,
	lo_value, hi_value: ^f32,
	lo: f32 = 0,
	hi: f32 = 1,
	step: f32 = 0,
	width: f32 = 240,
	indicator := Value_Indicator.Floating,
	state := Interaction.Live,
	name := "",
	labelled_by: ops.Area_Id = 0,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_open(gtx, key, loc)
	g := slider_geom(width, false, true, lo, hi, step)
	size := ui.constrain(gtx.constraints, {g.length, g.cross})
	g = slider_geom(size.x, false, true, lo, hi, step)
	old := [2]f32{lo_value^, hi_value^}
	c := slider_state(gtx, p.id, state)
	// Which handle the keys and a drag move is the Range_Handle's to keep.
	// Forced states show the high one active.
	active := 1
	if c.st != nil {
		rh := ui.widget_data(gtx, p.id, Range_Handle)
		vals := [2]^f32{lo_value, hi_value}
		apply_slider_input(gtx, p.id, c.st, g, vals[:], lo, hi, step, rh)
		c.hovered, c.pressed, c.focused = c.st.hovered, c.st.pressed, c.st.focused
		active = rh.active
	}
	paint_slider(gtx, c, g, lo, hi, {lo_value^, hi_value^}, true, false, active, {}, indicator)
	listen(gtx, c, p.id, ops.Rect{0, 0, size.x, size.y}, SLIDER_KINDS)
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, name != "" ? name : "range slider"))
	// One node: the handles share the widget's area and its keys.
	span := hi - lo
	range := fmt.aprintf("%s–%s", slider_value_text(gtx, lo_value^, span), slider_value_text(gtx, hi_value^, span), allocator = gtx.allocator)
	ui.semantics(gtx, &p, {role = .Slider, label = name, labelled_by = labelled_by, value = range, states = states_of(c)})
	ui.widget_close(gtx, &p, {size = size})
	return old != {lo_value^, hi_value^}
}

// Range_Handle is which of a range slider's handles the keys and a drag
// move: 0 the low one, 1 the high one. A press picks the nearer; Tab
// swaps.
@(private = "file")
Range_Handle :: struct {
	active: int,
}

@(private)
SLIDER_KINDS :: ops.Event_Kinds{.Press, .Release, .Move, .Enter, .Leave, .Key, .Focus, .Blur}

// TRACK_INSIDE_CORNER is the radius of a track segment's corner that faces
// a gap: hard-coded in Compose, whatever active-track-shape-leading says
// (slider.json layout, Slider.kt:3350-3351).
@(private)
TRACK_INSIDE_CORNER :: f32(2)

// INSET_ICON_SIZE is an inset icon's size: neither Compose nor the tokens
// give one (slider.json layout, mdc:Slider.md trackIconSize has no
// default), so it is chosen to leave 2dp of the 16dp track either side.
@(private)
INSET_ICON_SIZE :: tok.SLIDER_INACTIVE_TRACK_HEIGHT - 4

// VALUE_INDICATOR_PAD is the value indicator's padding around its label,
// horizontal and vertical. The tokens colour and set its text but do not
// size it (slider.json notes, mdc:Slider.md), so it is chosen: a pill as
// tall as the 44dp handle.
@(private)
VALUE_INDICATOR_PAD :: [2]f32{16, 12}

// Slider_Geom places a slider along its main axis u (x, or y when
// vertical) and across it v. The track runs t0..t0+tw on u, inset by half
// the handle's rest width so the handle stays inside at either end
// (Slider.kt:1066-1072).
@(private)
Slider_Geom :: struct {
	length, cross: f32,
	vertical, flip: bool,
	t0, tw:         f32,
	th:             f32, // track thickness
	n:              int, // intervals when stepped, 0 when continuous
}

@(private)
slider_geom :: proc(length: f32, vertical, top_to_bottom: bool, lo, hi, step: f32) -> Slider_Geom {
	n := 0
	if step > 0 {
		n = max(int(math.round((hi - lo) / step)), 1)
	}
	return {
		length = length,
		cross = max(tok.SLIDER_HANDLE_HEIGHT, MIN_TOUCH),
		vertical = vertical,
		flip = vertical && !top_to_bottom,
		t0 = tok.SLIDER_HANDLE_WIDTH / 2,
		tw = max(length - tok.SLIDER_HANDLE_WIDTH, 1),
		th = tok.SLIDER_INACTIVE_TRACK_HEIGHT,
		n = n,
	}
}

// slider_rect is the widget-space rect spanning u0..u1 along the track and
// v0..v1 across it.
@(private)
slider_rect :: proc(g: Slider_Geom, u0, u1, v0, v1: f32) -> ops.Rect {
	if !g.vertical {
		return {u0, v0, u1 - u0, v1 - v0}
	}
	if g.flip {
		return {v0, g.length - u1, v1 - v0, u1 - u0}
	}
	return {v0, u0, v1 - v0, u1 - u0}
}

// slider_corners gives a track segment's start-side corners radius a and
// its end-side corners b, whichever way the slider runs.
@(private)
slider_corners :: proc(g: Slider_Geom, a, b: f32) -> Corners {
	switch {
	case !g.vertical:
		return {tl = a, tr = b, br = b, bl = a}
	case g.flip:
		return {tl = b, tr = b, br = a, bl = a}
	}
	return {tl = a, tr = a, br = b, bl = b}
}

// slider_point is the widget-space point at u along the track, v across.
@(private)
slider_point :: proc(g: Slider_Geom, u, v: f32) -> ops.Point {
	r := slider_rect(g, u, u, v, v)
	return {r.x, r.y}
}

// handle_u is where a handle at fraction f of the range sits, relative to
// the track's start. A stepped slider's inner stops are inset by the
// track's end radius, so they line up with the stop dots; its first and
// last are not (Slider.kt:1062-1068).
@(private)
handle_u :: proc(g: Slider_Geom, f: f32) -> f32 {
	r := g.th / 2
	if g.n > 0 && f != 0 && f != 1 {
		return r + f * (g.tw - 2 * r)
	}
	return f * g.tw
}

// value_at is the value under widget-space pos: linear over the handle's
// travel, then snapped to the nearest stop.
@(private)
value_at :: proc(g: Slider_Geom, pos: ops.Point, lo, hi, step: f32) -> f32 {
	u := g.vertical ? pos.y : pos.x
	if g.flip {
		u = g.length - u
	}
	t := clamp((u - g.t0) / g.tw, 0, 1)
	return snap(lo + t * (hi - lo), lo, hi, step)
}

@(private)
snap :: proc(v, lo, hi, step: f32) -> f32 {
	if step <= 0 {
		return clamp(v, lo, hi)
	}
	return clamp(lo + math.round((v - lo) / step) * step, lo, hi)
}

// slider_state is the slider's Control: its Widget_State when Live (input
// is read by apply_slider_input), else the forced look. Hover has no look of its
// own and a press draws no ripple (slider.json states), so no state layer
// opacity is set.
@(private)
slider_state :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, state: Interaction) -> Control {
	if state != .Live {
		c := control(gtx, id, {}, state)
		c.layer = 0
		return c
	}
	return {st = ui.widget_state(gtx, id)}
}

// apply_slider_input applies this frame's events to vals, one pointer per
// handle; with two, rh holds which one is active.
@(private = "file")
apply_slider_input :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, st: ^ui.Widget_State, g: Slider_Geom, vals: []^f32, lo, hi, step: f32, rh: ^Range_Handle = nil) {
	two := len(vals) == 2 && rh != nil
	active := two ? clamp(rh.active, 0, 1) : 0
	for e in ui.events(gtx, id) {
		#partial switch e.kind {
		case .Enter:
			st.hovered = true
		case .Leave:
			st.hovered = false
		case .Focus:
			st.focused = true
		case .Blur:
			st.focused = false
		case .Press:
			if e.button != .Left {
				continue
			}
			st.pressed = true
			v := value_at(g, e.pos, lo, hi, step)
			if two {
				a, b := vals[0]^, vals[1]^
				switch {
				case a == b:
					active = v > b ? 1 : 0
				case:
					active = abs(v - a) <= abs(v - b) ? 0 : 1
				}
			}
			set_handle(vals, active, v)
		case .Move:
			if st.pressed {
				set_handle(vals, active, value_at(g, e.pos, lo, hi, step))
			}
		case .Release:
			st.pressed = false
		case .Key:
			if two && e.key == .Tab {
				active = 1 - active
				continue
			}
			// One key step is one stop, or 1% of a continuous range; a page
			// is a tenth of the stops, 1 to 10 of them, or 10 continuous
			// (slider.json behaviour, Slider.kt:1100-1136).
			d := step > 0 ? step : (hi - lo) / 100
			page := step > 0 ? f32(clamp(g.n / 10, 1, 10)) : 10
			v := vals[active]^
			#partial switch e.key {
			case .Left, .Down:
				v -= d
			case .Right, .Up:
				v += d
			case .Page_Down:
				v -= d * page
			case .Page_Up:
				v += d * page
			case .Home:
				v = lo
			case .End:
				v = hi
			case:
				continue
			}
			set_handle(vals, active, snap(v, lo, hi, step))
		}
	}
	if two {
		rh.active = active
	}
}

// set_handle moves handle i to v, stopping at the other handle so a range
// never crosses (slider.json behaviour: coercion only, no separation).
@(private)
set_handle :: proc(vals: []^f32, i: int, v: f32) {
	switch {
	case len(vals) == 1:
		vals[0]^ = v
	case i == 0:
		vals[0]^ = min(v, vals[1]^)
	case:
		vals[1]^ = max(v, vals[0]^)
	}
}

// Slider_Colors are a slider's resolved colours in its current state.
@(private)
Slider_Colors :: struct {
	active, inactive, handle: ops.Color,
}

@(private)
slider_colors :: proc(disabled: bool) -> Slider_Colors {
	if disabled {
		// The disabled handle is composited over the surface so the track
		// does not show through it (slider.json states, Slider.kt:1723-1737).
		return {
			active = ops.with_alpha(color(tok.SLIDER_DISABLED_ACTIVE_TRACK_COLOR), tok.SLIDER_DISABLED_ACTIVE_TRACK_OPACITY),
			inactive = ops.with_alpha(color(tok.SLIDER_DISABLED_INACTIVE_TRACK_COLOR), tok.SLIDER_DISABLED_INACTIVE_TRACK_OPACITY),
			handle = ops.mix(color(.Surface), color(tok.SLIDER_DISABLED_HANDLE_COLOR), tok.SLIDER_DISABLED_HANDLE_OPACITY),
		}
	}
	return {color(tok.SLIDER_ACTIVE_TRACK_COLOR), color(tok.SLIDER_INACTIVE_TRACK_COLOR), color(tok.SLIDER_HANDLE_COLOR)}
}

// paint_slider draws the track as Compose's drawTrack does (Slider.kt:
// 2425-2680): inactive and active segments with a gap either side of each
// handle, outer ends a full stadium and gap-facing corners 2dp, a stop dot
// at each inactive end and at every step outside a gap, then the handles,
// their focus ring and value indicator. values are the two handles' values
// (both the one value for a single slider); active is the handle that
// narrows and takes the ring.
@(private)
paint_slider :: proc(
	gtx: ^ui.Ctx,
	c: Control,
	g: Slider_Geom,
	lo, hi: f32,
	values: [2]f32,
	range, centered: bool,
	active: int,
	icons: [2]Icon,
	indicator: Value_Indicator,
) {
	col := slider_colors(c.disabled)
	span := max(hi - lo, 1e-6)
	f := [2]f32{clamp((values[0] - lo) / span, 0, 1), clamp((values[1] - lo) / span, 0, 1)}

	// One signal narrows the handle and widens its gaps, so the two never
	// mismatch; Compose snaps it, the spec asks for fast-spatial
	// (slider.json behaviour). Slots 0 and 1 are the low and high handle.
	narrow := (c.pressed || c.focused) && !c.disabled
	hw: [2]f32
	for i in 0 ..< 2 {
		target := tok.SLIDER_HANDLE_WIDTH
		if narrow && (i == active || !range) {
			target = tok.SLIDER_HANDLE_WIDTH / 2
		}
		hw[i] = animate(gtx, c, i, target, .Fast_Spatial, 0.1)
	}

	// The handle widths each gap is measured from, in drawTrack's terms.
	gap := tok.SLIDER_ACTIVE_HANDLE_LEADING_SPACE
	ars, are := range ? f[0] : 0, f[1]
	start_w, end_w: f32
	start_gap_on := range || centered
	switch {
	case range:
		start_w, end_w = hw[0], hw[1]
	case centered:
		start_w = f[1] <= 0.5 ? hw[1] : 0
		end_w = f[1] >= 0.5 ? hw[1] : 0
	case:
		end_w = hw[1]
	}
	start_gap := start_gap_on ? start_w / 2 + gap : 0
	end_gap := end_w / 2 + gap

	L := g.tw
	r := g.th / 2
	inside := TRACK_INSIDE_CORNER
	val_start, val_end := handle_u(g, ars), handle_u(g, are)
	mid := L / 2
	shrink := g.n == 0 // corner shrinking: a continuous segment may shorten to nothing
	v0, v1 := (g.cross - g.th) / 2, (g.cross + g.th) / 2
	seg :: proc(gtx: ^ui.Ctx, g: Slider_Geom, u0, u1, v0, v1, a, b: f32, color: ops.Color) {
		if u1 > u0 {
			ops.fill(gtx.scene, rounded(gtx, slider_rect(g, g.t0 + u0, g.t0 + u1, v0, v1), slider_corners(g, a, b)), color)
		}
	}
	dot :: proc(gtx: ^ui.Ctx, g: Slider_Geom, u: f32, color: ops.Color) {
		ops.fill(gtx.scene, ui.circle(slider_point(g, g.t0 + u, g.cross / 2), tok.SLIDER_STOP_INDICATOR_SIZE / 2), color)
	}

	// The inactive segment before the fill: a range's, or a centered
	// slider's left of the midpoint.
	start_thr := start_gap + (shrink ? 0 : r)
	adj_end := centered ? min(val_end, mid) : val_start
	if (centered || range) && adj_end > start_thr {
		seg(gtx, g, 0, adj_end - start_gap, v0, v1, r, inside, col.inactive)
		if icons[0] == .None {
			dot(gtx, g, r, col.active)
		}
	}
	// The inactive segment after the fill.
	end_thr := L - end_gap - (shrink ? 0 : r)
	adj_start := centered ? max(val_end, mid) : val_end
	if adj_start < end_thr {
		seg(gtx, g, adj_start + end_gap, L, v0, v1, inside, r, col.inactive)
		if icons[1] == .None {
			dot(gtx, g, L - r, col.active)
		}
	}
	// The fill.
	a_start, a_end: f32
	switch {
	case centered:
		a_start = adj_end + (adj_end < mid ? start_gap : 0)
		a_end = adj_start - (adj_start > mid ? end_gap : 0)
	case range:
		a_start, a_end = val_start + start_gap, val_end - end_gap
	case:
		a_start, a_end = 0, val_end - end_gap
	}
	sc := centered || range ? inside : r
	if a_end - a_start > (shrink ? 0 : sc) {
		seg(gtx, g, a_start, a_end, v0, v1, sc, inside, col.active)
	}
	// Stop dots at each step, but none in a gap and none on an end that
	// already has one; a dot on the fill takes the inactive colour and
	// the reverse (slider.json states, Slider.kt:2637-2680).
	if g.n > 0 {
		in_gap :: proc(x, c, half: f32) -> bool {
			return x >= c - half && x <= c + half
		}
		end_half := end_gap
		if centered {
			end_half = val_end > mid ? end_gap : start_gap
		}
		for i in 0 ..= g.n {
			if ((centered || range) && i == 0) || i == g.n {
				continue
			}
			x := r + f32(i) / f32(g.n) * (L - 2 * r)
			if centered && in_gap(x, mid, val_end > mid ? start_gap : end_gap) {
				continue
			}
			if (range && in_gap(x, val_start, start_gap)) || in_gap(x, val_end, end_half) {
				continue
			}
			on := x >= a_start && x <= a_end
			dot(gtx, g, x, on ? col.inactive : col.active)
		}
	}
	paint_inset_icons(gtx, c, g, icons, val_end, end_gap)

	paint_slider_handles(gtx, c, g, col.handle, {val_start, val_end}, hw, values, range, active, indicator, hi - lo)
}

// paint_inset_icons draws a standard slider's inset icons, centred in the
// track's end caps, in the content colour of whichever segment they sit
// on, and hides one under the handle's gap (val_end, end_gap).
@(private)
paint_inset_icons :: proc(gtx: ^ui.Ctx, c: Control, g: Slider_Geom, icons: [2]Icon, val_end, end_gap: f32) {
	for ic, i in icons {
		if ic == .None {
			continue
		}
		sz := INSET_ICON_SIZE
		u := i == 0 ? (g.th - sz) / 2 : g.tw - (g.th + sz) / 2
		if u + sz > val_end - end_gap && u < val_end + end_gap {
			continue
		}
		on := u + sz / 2 <= val_end
		ink := color(on ? .On_Primary : .On_Secondary_Container)
		if c.disabled {
			ink = disabled_content()
		}
		box := slider_rect(g, g.t0 + u, g.t0 + u + sz, (g.cross - sz) / 2, (g.cross + sz) / 2)
		icon(gtx, ic, {box.x, box.y}, sz, ink)
	}
}

// paint_slider_handles draws the handles at us along the track, hw wide:
// bars handle-height long across the track, full-rounded, with the focus
// ring and value indicator on the active one.
@(private)
paint_slider_handles :: proc(
	gtx: ^ui.Ctx,
	c: Control,
	g: Slider_Geom,
	handle: ops.Color,
	us, hw, values: [2]f32,
	range: bool,
	active: int,
	indicator: Value_Indicator,
	span: f32,
) {
	for i in 0 ..< 2 {
		if !range && i == 0 {
			continue
		}
		u := g.t0 + us[i]
		hr := slider_rect(g, u - hw[i] / 2, u + hw[i] / 2, (g.cross - tok.SLIDER_HANDLE_HEIGHT) / 2, (g.cross + tok.SLIDER_HANDLE_HEIGHT) / 2)
		k := corners(tok.SLIDER_HANDLE_SHAPE, hr)
		ops.fill(gtx.scene, rounded(gtx, hr, k), handle)
		mine := !range || i == active
		if mine {
			paint_focus_ring_corners(gtx, c, hr, k)
		}
		show := indicator == .Always || (indicator == .Floating && mine && c.pressed)
		if show && !c.disabled {
			paint_value_indicator(gtx, g, hr, values[i], span)
		}
	}
}

// slider_value_text is v as the value indicator shows it, and as a reader
// says it: whole numbers once the value or the range reaches 10, two
// significant figures below. It lives for the frame.
@(private)
slider_value_text :: proc(gtx: ^ui.Ctx, v, span: f32) -> string {
	if abs(v) >= 10 || span >= 10 {
		return fmt.aprintf("%.0f", v, allocator = gtx.allocator)
	}
	return fmt.aprintf("%.2g", v, allocator = gtx.allocator)
}

// paint_value_indicator is the slider's value label: label text in
// inverse-on-surface on an inverse-surface pill, active-bottom-space
// above the handle hr (to its start side when vertical).
@(private)
paint_value_indicator :: proc(gtx: ^ui.Ctx, g: Slider_Geom, hr: ops.Rect, v, span: f32) {
	t := shape_style(gtx, slider_value_text(gtx, v, span), tok.SLIDER_VALUE_INDICATOR_LABEL_TEXT_FONT)
	pad := VALUE_INDICATOR_PAD
	h := t.height + 2 * pad.y
	w := max(t.width + 2 * pad.x, h)
	space := tok.SLIDER_VALUE_INDICATOR_ACTIVE_BOTTOM_SPACE
	// Centred above the handle (to its start when vertical), flipped to the
	// other side or shifted when that would leave the window. It draws
	// nothing toward the handle, so it needs no key to follow a flip.
	o := ui.popup_open(gtx, hr, 0, g.vertical ? .Before : .Above, .Center, space)
	defer ui.popup_close(&o, {w, h})
	ops.fill(gtx.scene, ops.Round_Rect{{0, 0, w, h}, h / 2}, color(tok.SLIDER_VALUE_INDICATOR_CONTAINER_COLOR))
	draw_text(gtx, t, {(w - t.width) / 2, pad.y}, color(tok.SLIDER_VALUE_INDICATOR_LABEL_TEXT_COLOR))
}

// Progress_Style is a progress indicator's look: Plain draws a straight
// line or a circular arc; Wavy draws the active part as a travelling wave,
// more expressive and less legible at very small sizes.
Progress_Style :: enum u8 {
	Plain,
	Wavy,
}

// linear_progress is M3's linear progress indicator, width long: a primary
// active indicator over a secondary-container track, split from it by a
// gap, with a stop dot at the track's end. value in [0, 1] is determinate
// (coerced into range); value < 0 is indeterminate, two lines sweeping
// across on a 1750ms loop. Wavy makes the active line a wave, 10dp tall,
// that moves one wavelength a second; determinate, it flattens below 10%
// and above 95% (amplitude < 0), or holds amplitude in [0, 1]. wavelength
// 0 is the style's token. square gives butt caps and a square stop, and
// the raw gap. at >= 0 freezes the animation that many seconds in.
//
// Value changes are not animated: Compose leaves that to the caller
// (progress-indicator.json behaviour).
linear_progress :: proc(
	gtx: ^ui.Ctx,
	value: f32,
	width: f32 = 240,
	style := Progress_Style.Plain,
	square := false,
	amplitude: f32 = -1,
	wavelength: f32 = 0,
	at: f32 = -1,
	key: u64 = 0,
	loc := #caller_location,
) {
	p := ui.widget_open(gtx, key, loc)
	wavy := style == .Wavy
	size := ui.constrain(gtx.constraints, {width, wavy ? tok.LINEAR_PROGRESS_INDICATOR_WAVE_HEIGHT : tok.LINEAR_PROGRESS_INDICATOR_HEIGHT})
	st := at < 0 ? ui.widget_state(gtx, p.id) : nil
	ramp := st != nil ? ui.widget_data(gtx, p.id, Amplitude_Ramp) : nil
	indeterminate := value < 0

	// segs are the active lines as (tail, head) fractions of the width.
	segs: [2][2]f32
	count := 1
	t: f32 // seconds into the loop
	if indeterminate {
		// Four head and tail sweeps staggered on a 1750ms loop, eased
		// emphasized-accelerate (ProgressIndicator.kt:1049-1063).
		t = progress_clock(gtx, st, 7, at) // 7s: the loop and a 1s wave both repeat
		lt := math.mod(t, 1.75)
		sweep :: proc(t, delay, dur: f32) -> f32 {
			return bezier_ease(tok.SYS_MOTION_EASING_EMPHASIZED_ACCELERATE, clamp((t - delay) / dur, 0, 1))
		}
		segs[0] = {sweep(lt, 0.25, 1), sweep(lt, 0, 1)}
		segs[1] = {sweep(lt, 0.9, 0.85), sweep(lt, 0.65, 0.85)}
		count = 2
	} else {
		segs[0] = {0, clamp(value, 0, 1)}
		if wavy {
			t = progress_clock(gtx, st, 1, at)
		}
	}
	amp: f32
	if wavy {
		amp = amplitude
		if amp < 0 {
			amp = 1
			if !indeterminate && (value <= 0.1 || value >= 0.95) {
				amp = 0 // progress-indicator.json layout: 10% and 95% thresholds
			}
		}
		if !indeterminate {
			amp = amplitude_ramp(gtx, ramp, clamp(amp, 0, 1))
		}
	}
	lambda := wavelength
	if lambda <= 0 {
		lambda = indeterminate ? tok.LINEAR_PROGRESS_INDICATOR_INDETERMINATE_ACTIVE_WAVE_WAVELENGTH : tok.LINEAR_PROGRESS_INDICATOR_ACTIVE_WAVE_WAVELENGTH
	}
	paint_linear_progress(gtx, size, segs[:count], wavy, amp, lambda, math.mod(t, 1), square, indeterminate)
	describe_progress(gtx, &p, value)
	ui.widget_close(gtx, &p, {size = size})
}

// describe_progress declares a progress indicator to a reader: busy while
// indeterminate (value < 0), else its percentage as the reader says it.
@(private)
describe_progress :: proc(gtx: ^ui.Ctx, p: ^ui.Placement, value: f32) {
	if value < 0 {
		ui.semantics(gtx, p, {role = .Progress, states = {.Busy}})
		return
	}
	ui.semantics(gtx, p, {role = .Progress, value = fmt.aprintf("%.0f%%", clamp(value, 0, 1) * 100, allocator = gtx.allocator)})
}

// paint_linear_progress draws the track right to left around the active
// segs, then the segs, then the stop dot, as Compose's linear wavy drawing
// does for both styles (LinearWavyProgressModifiers.kt updateDrawPaths):
// with round caps the visible gap is the gap token plus a cap either side.
@(private)
paint_linear_progress :: proc(
	gtx: ^ui.Ctx,
	size: ops.Size,
	segs: [][2]f32,
	wavy: bool,
	amp, lambda, phase: f32,
	square, indeterminate: bool,
) {
	w, h := size.x, size.y
	cy := h / 2
	stroke := tok.LINEAR_PROGRESS_INDICATOR_ACTIVE_THICKNESS
	track := tok.LINEAR_PROGRESS_INDICATOR_TRACK_THICKNESS
	cap := square ? ops.Line_Cap.Butt : .Round
	capw := square ? 0 : max(stroke, track) / 2
	gap := tok.LINEAR_PROGRESS_INDICATOR_TRACK_ACTIVE_SPACE
	track_col := color(tok.PROGRESS_INDICATOR_TRACK_COLOR)
	active_col := color(tok.PROGRESS_INDICATOR_ACTIVE_INDICATOR_COLOR)
	line :: proc(gtx: ^ui.Ctx, x0, x1, y, width: f32, cap: ops.Line_Cap, col: ops.Color) {
		ops.stroke(gtx.scene, ui.line(gtx, {x0, y}, {x1, y}), col, {width = width, cap = cap})
	}

	next_end := w - capw
	adj_gap := gap
	visible := false
	for sg, i in segs {
		tail, head := sg[0] * w, sg[1] * w
		if i == 0 {
			// The gap shortens as the first line enters, so the track is not
			// cut before the line's cap has room to draw.
			adj_gap = head < capw ? 0 : min(head - capw, gap)
			visible = head >= capw
		}
		ah := clamp(head, capw, w - capw)
		at := clamp(tail, capw, w - capw)
		spacing := visible ? adj_gap + 2 * capw : adj_gap
		if next_end > ah + spacing {
			line(gtx, max(capw, ah + spacing), next_end, cy, track, cap, track_col)
		}
		if head > tail {
			next_end = max(capw, at - spacing)
		}
		if head - tail > 0 {
			if wavy && amp > 0 {
				paint_wave(gtx, at, ah, cy, amp * wave_amplitude(h, stroke), lambda, phase, stroke, cap, active_col)
			} else {
				line(gtx, at, ah, cy, stroke, cap, active_col)
			}
		}
	}
	if next_end > capw {
		line(gtx, capw, next_end, cy, track, cap, track_col)
	}
	if indeterminate {
		return // only determinate progress has a stop (ProgressIndicator.kt, WavyProgressIndicator.kt:106)
	}
	// The stop: no bigger than the track, inset at most stop-trailing-space
	// (ProgressIndicator.kt:876-919). The wavy one shrinks away as the
	// line reaches it (LinearWavyProgressModifiers.kt drawStopIndicator).
	stop := min(tok.LINEAR_PROGRESS_INDICATOR_STOP_SIZE, track)
	x := w - stop - min((track - stop) / 2, tok.LINEAR_PROGRESS_INDICATOR_STOP_TRAILING_SPACE)
	if wavy {
		px := segs[0][1] * w + capw
		if x <= px {
			stop = max(0, stop - (px - x))
			x = px
		}
	}
	if stop <= 0 {
		return
	}
	stop_col := color(tok.PROGRESS_INDICATOR_STOP_COLOR)
	if square {
		ops.fill(gtx.scene, ops.Rect{x, cy - stop / 2, stop, stop}, stop_col)
	} else {
		ops.fill(gtx.scene, ui.circle({x + stop / 2, cy}, stop / 2), stop_col)
	}
}

// wave_amplitude is the linear wave's peak offset: the amplitude token,
// kept inside the container so the stroke is not clipped.
@(private)
wave_amplitude :: proc(h, stroke: f32) -> f32 {
	return min(tok.LINEAR_PROGRESS_INDICATOR_ACTIVE_WAVE_AMPLITUDE, (h - stroke) / 2)
}

// paint_wave strokes a sine of amplitude a and wavelength lambda about y
// from x0 to x1, shifted phase wavelengths along so it travels, first
// half-wave downward. Compose plots the wave as quadratic half-waves
// (LinearWavyProgressModifiers.kt updateFullPaths); this samples a true
// sine every 1.5dp instead, a slightly rounder crest.
@(private)
paint_wave :: proc(gtx: ^ui.Ctx, x0, x1, y, a, lambda, phase, width: f32, cap: ops.Line_Cap, col: ops.Color) {
	n := max(int((x1 - x0) / 1.5), 1) + 1
	pts := make([]ops.Point, n, gtx.allocator)
	for i in 0 ..< n {
		x := x0 + (x1 - x0) * f32(i) / f32(n - 1)
		pts[i] = {x, y + a * math.sin(2 * math.PI * (x / lambda + phase))}
	}
	ops.stroke(gtx.scene, ui.polyline(gtx, pts), col, {width = width, cap = cap, join = .Round})
}

// circular_progress is M3's circular progress indicator: a primary arc from
// 12 o'clock over a secondary-container ring, split from it by a gap either
// side. value in [0, 1] is determinate; value < 0 is indeterminate, on a
// 6000ms loop of three turns, a 90° step every 1500ms and a sweep between
// 10% and 87%. size 0 is the style's token: 40dp Plain, 48dp Wavy. Wavy
// makes the arc a wave around the ring; amplitude, wavelength, square and
// at are as for linear_progress.
//
// The Plain indeterminate indicator has no track, as Compose's default
// track colour for it is transparent (ProgressIndicator.kt,
// circularIndeterminateTrackColor); the Wavy one has one.
circular_progress :: proc(
	gtx: ^ui.Ctx,
	value: f32,
	size: f32 = 0,
	style := Progress_Style.Plain,
	square := false,
	amplitude: f32 = -1,
	wavelength: f32 = 0,
	at: f32 = -1,
	key: u64 = 0,
	loc := #caller_location,
) {
	p := ui.widget_open(gtx, key, loc)
	wavy := style == .Wavy
	d := size
	if d <= 0 {
		d = wavy ? tok.CIRCULAR_PROGRESS_INDICATOR_WAVE_SIZE : tok.CIRCULAR_PROGRESS_INDICATOR_SIZE
	}
	sz := ui.constrain(gtx.constraints, {d, d})
	st := at < 0 ? ui.widget_state(gtx, p.id) : nil
	ramp := st != nil ? ui.widget_data(gtx, p.id, Amplitude_Ramp) : nil
	indeterminate := value < 0
	t: f32
	rot, sweep: f32 // degrees, clockwise from 12 o'clock; fraction of the circle
	if indeterminate {
		t = progress_clock(gtx, st, 6, at)
		rot, sweep = circular_indeterminate(t)
	} else {
		sweep = clamp(value, 0, 1)
		if wavy {
			t = progress_clock(gtx, st, 1, at)
		}
	}
	amp: f32
	if wavy {
		amp = amplitude
		if amp < 0 {
			amp = 1
			if !indeterminate && (value <= 0.1 || value >= 0.95) {
				amp = 0
			}
		}
		if !indeterminate {
			amp = amplitude_ramp(gtx, ramp, clamp(amp, 0, 1))
		}
	}
	paint_circular_progress(gtx, sz, rot, sweep, wavy, amp, wavelength, t, square, indeterminate)
	describe_progress(gtx, &p, value)
	ui.widget_close(gtx, &p, {size = sz})
}

// circular_indeterminate is the indeterminate ring's rotation (degrees) and
// sweep (fraction) at t seconds into its 6000ms loop
// (progress-indicator.json behaviour, ProgressIndicator.kt:930-978).
@(private)
circular_indeterminate :: proc(t: f32) -> (rot, sweep: f32) {
	lt := math.mod(t, 6)
	global := lt / 6 * 1080
	k := math.floor(lt / 1.5)
	step := 90 * k + 90 * bezier_ease(tok.SYS_MOTION_EASING_EMPHASIZED_DECELERATE, clamp((lt - 1.5 * k) / 0.3, 0, 1))
	MIN_SWEEP, MAX_SWEEP :: f32(0.1), f32(0.87)
	if lt < 3 {
		sweep = MIN_SWEEP + (MAX_SWEEP - MIN_SWEEP) * bezier_ease(tok.SYS_MOTION_EASING_STANDARD, lt / 3)
	} else {
		sweep = MAX_SWEEP + (MIN_SWEEP - MAX_SWEEP) * bezier_ease(tok.SYS_MOTION_EASING_STANDARD, (lt - 3) / 3)
	}
	return global + step, sweep
}

// paint_circular_progress draws the ring as Compose's circular indicators
// do: the active arc from rot, sweep of the circle, and the track over the
// rest less a gap each side, the gap widened by the stroke for round caps.
@(private)
paint_circular_progress :: proc(
	gtx: ^ui.Ctx,
	sz: ops.Size,
	rot, sweep: f32,
	wavy: bool,
	amp, wavelength, t: f32,
	square, indeterminate: bool,
) {
	stroke := tok.CIRCULAR_PROGRESS_INDICATOR_ACTIVE_THICKNESS
	track := tok.CIRCULAR_PROGRESS_INDICATOR_TRACK_THICKNESS
	c := sz / 2
	d := min(sz.x, sz.y)
	r := (d - max(stroke, track)) / 2
	cap := square ? ops.Line_Cap.Butt : .Round
	gap := tok.CIRCULAR_PROGRESS_INDICATOR_TRACK_ACTIVE_SPACE
	if !square {
		gap += stroke
	}
	// The gap becomes a sweep against the full diameter's circumference,
	// π·d, as Compose's gapSizeSweep does (ProgressIndicator.kt:546,664).
	gap_sweep := gap / (math.PI * d)
	start := f32(-math.PI / 2) + rot * math.PI / 180
	full := f32(2 * math.PI)
	if !indeterminate || wavy {
		t0 := sweep + min(sweep, gap_sweep)
		ts := 1 - sweep - 2 * min(sweep, gap_sweep)
		if ts > 0 {
			ops.stroke(gtx.scene, arc(gtx, c, r, start + t0 * full, start + (t0 + ts) * full), color(tok.PROGRESS_INDICATOR_TRACK_COLOR), {width = track, cap = cap})
		}
	}
	if sweep <= 0 {
		return
	}
	col := color(tok.PROGRESS_INDICATOR_ACTIVE_INDICATOR_COLOR)
	if !wavy || amp <= 0 {
		ops.stroke(gtx.scene, arc(gtx, c, r, start, start + sweep * full), col, {width = stroke, cap = cap})
		return
	}
	// The wave: n whole waves round the ring, n from the wavelength and
	// at least 5 (CircularWavyProgressModifiers.kt: numVertices), peaks on
	// the track's radius and troughs 2 × amplitude in, turning one wave a
	// second. Compose instead morphs the track's circle into a rounded
	// star with an inner radius of 0.75 (CircularWavyProgressModifiers.kt
	// update); a radial sine as deep as the kit's amplitude token is this
	// port's choice, which keeps the depth a token.
	lambda := wavelength > 0 ? wavelength : tok.CIRCULAR_PROGRESS_INDICATOR_ACTIVE_WAVE_WAVELENGTH
	n := max(f32(5), math.round(2 * math.PI * r / lambda))
	a := amp * tok.CIRCULAR_PROGRESS_INDICATOR_ACTIVE_WAVE_AMPLITUDE
	phase := math.mod(t, 1) / n * full
	count := max(int(sweep * 180), 2)
	pts := make([]ops.Point, count + 1, gtx.allocator)
	for i in 0 ..= count {
		th := start + sweep * full * f32(i) / f32(count)
		rr := r - a + a * math.cos(n * (th - start - phase))
		pts[i] = c + rr * ops.Point{math.cos(th), math.sin(th)}
	}
	ops.stroke(gtx.scene, ui.polyline(gtx, pts), col, {width = stroke, cap = cap, join = .Round})
}

// loading_indicator is M3 Expressive's loading indicator: one filled
// blob morphing through Material shapes in a size-dp box (the container
// tokens, 48dp, when 0), contained in a full-round primary-container
// container when contained. progress < 0 is indeterminate: soft-burst,
// cookie-9, pentagon, pill, sunny, cookie-4, oval and round again, a new
// morph every 650ms on a 0.6-damped, 200-stiffness spring, turning 90° per
// morph plus a full turn every 4666ms. progress in [0, 1] morphs a circle
// into a soft-burst as it rises, turning back 180°. indicator_color and
// container_color override the tokens when set. at >= 0 freezes the
// indeterminate loop that many seconds in.
//
// The morph pairs come pre-matched from the kit (shape_data.odin), so a
// custom shape list, which would need graphics-shapes' matching at run
// time, is not offered.
loading_indicator :: proc(
	gtx: ^ui.Ctx,
	contained := false,
	size: f32 = 0,
	progress: f32 = -1,
	indicator_color := ops.Color{},
	container_color := ops.Color{},
	at: f32 = -1,
	key: u64 = 0,
	loc := #caller_location,
) {
	p := ui.widget_open(gtx, key, loc)
	box := ops.Size{tok.LOADING_INDICATOR_CONTAINER_WIDTH, tok.LOADING_INDICATOR_CONTAINER_HEIGHT}
	if size > 0 {
		box = {size, size}
	}
	sz := ui.constrain(gtx.constraints, box)
	area := ops.Rect{0, 0, sz.x, sz.y}
	col := color(contained ? tok.LOADING_INDICATOR_CONTAINED_ACTIVE_COLOR : tok.LOADING_INDICATOR_ACTIVE_INDICATOR_COLOR)
	if ui.painted(indicator_color) {
		col = indicator_color
	}
	if contained {
		bg := color(tok.LOADING_INDICATOR_CONTAINED_CONTAINER_COLOR)
		if ui.painted(container_color) {
			bg = container_color
		}
		ops.fill(gtx.scene, rounded(gtx, area, corners(tok.LOADING_INDICATOR_CONTAINER_SHAPE, area)), bg)
	}

	seq: ^Loading_Sequence
	morph: int
	t, rot: f32 // morph progress; rotation in degrees, clockwise
	if progress < 0 {
		seq = &LOADING_INDETERMINATE
		st := at < 0 ? ui.widget_state(gtx, p.id) : nil
		n := len(seq.morphs)
		// clock counts whole morphs' time over 4 × n of them, when the
		// step rotation and the shape both come round; turn the 4666ms
		// turn (loading-indicator.json behaviour, LoadingIndicator.kt:
		// 392-434).
		MORPH_S :: f32(0.65)
		clock := progress_clock(gtx, st, MORPH_S * f32(4 * n), at)
		turn := progress_clock(gtx, st, 4.666, at)
		k := int(clock / MORPH_S)
		morph = k % n
		t = morph_spring(clock - f32(k) * MORPH_S)
		rot = t * 90 + f32((90 * (k + 1)) % 360) + turn / 4.666 * 360
	} else {
		// Progress picks the morph and how far through it, and turns the
		// shape back 180° over the whole range (LoadingIndicator.kt:313-330).
		seq = &LOADING_DETERMINATE
		pr := clamp(progress, 0, 1)
		n := f32(len(seq.morphs))
		morph = min(int(n * pr), len(seq.morphs) - 1)
		t = pr >= 1 ? 1 : math.mod(pr * n, 1)
		rot = -pr * 180
	}
	paint_morph(gtx, seq.morphs[morph], t, sz / 2, min(sz.x, sz.y) * seq.draw_scale, rot, col)
	describe_progress(gtx, &p, progress)
	ui.widget_close(gtx, &p, {size = sz})
}

// morph_spring is the indeterminate loading indicator's morph progress tau
// seconds into a morph: a spring from rest at 0 to 1 with damping 0.6 and
// stiffness 200, snapped to 1 once within its 0.1 visibility threshold
// (loading-indicator.json behaviour, LoadingIndicator.kt:400-420). It
// restarts every morph, so it is a closed form of tau with no state.
@(private)
morph_spring :: proc(tau: f32) -> f32 {
	ZETA, K, THRESHOLD :: f32(0.6), f32(200), f32(0.1)
	w := math.sqrt(K)
	wd := w * math.sqrt(1 - ZETA * ZETA)
	decay := math.exp(-ZETA * w * tau)
	// The envelope of x0·cos + (ζω·x0/ωd)·sin with x0 = -1.
	if decay * math.sqrt(1 + (ZETA * w / wd) * (ZETA * w / wd)) < THRESHOLD {
		return 1
	}
	x := decay * (-math.cos(wd * tau) - (ZETA * w / wd) * math.sin(wd * tau))
	return 1 + x
}

// paint_morph fills m at t, scaled to span `scale` dp, its bounds centred
// on c and turned rot degrees clockwise about c, as LoadingIndicator draws
// its morph path every frame (morphs.json notes).
@(private)
paint_morph :: proc(gtx: ^ui.Ctx, m: Shape_Morph, t: f32, c: ops.Point, scale, rot: f32, col: ops.Color) {
	n := len(m.start)
	pts := make([]ops.Point, 1 + 3 * n, gtx.allocator)
	verbs := make([]ops.Path_Verb, n + 2, gtx.allocator)
	lo, hi := ops.Point{math.F32_MAX, math.F32_MAX}, ops.Point{-math.F32_MAX, -math.F32_MAX}
	for i in 0 ..< n {
		a, b := m.start[i], m.end[i]
		q: Shape_Cubic
		for k in 0 ..< 8 {
			q[k] = a[k] + (b[k] - a[k]) * t
		}
		if i == 0 {
			pts[0] = {q[0], q[1]}
		}
		for j in 0 ..< 3 {
			pt := ops.Point{q[2 + 2 * j], q[3 + 2 * j]}
			pts[1 + 3 * i + j] = pt
			lo, hi = {min(lo.x, pt.x), min(lo.y, pt.y)}, {max(hi.x, pt.x), max(hi.y, pt.y)}
		}
	}
	// Centre on the bounding box of the control points (the kit's notes say
	// the path's bounds), then scale and turn about c.
	mid := (lo + hi) / 2
	s, co := math.sincos(rot * math.PI / 180)
	for &pt in pts {
		d := (pt - mid) * scale
		pt = c + ops.Point{d.x * co - d.y * s, d.x * s + d.y * co}
	}
	verbs[0] = .Move
	for i in 0 ..< n {
		verbs[1 + i] = .Cubic
	}
	verbs[n + 1] = .Close
	ops.fill(gtx.scene, ops.Path_Ref{ops.add_path(gtx.scene, {verbs, pts})}, col)
}

// progress_clock is seconds into a loop of period for an animated
// indicator, read from the frame clock (gtx.time), and asks for the next
// frame so it keeps moving. at >= 0 is a fixed time instead, for a still
// frame; so is a nil st, a forced state.
@(private)
progress_clock :: proc(gtx: ^ui.Ctx, st: ^ui.Widget_State, period, at: f32) -> f32 {
	if at >= 0 || st == nil {
		return math.mod(max(at, 0), period)
	}
	ui.request_frame(gtx)
	return f32(math.mod(gtx.time, f64(period)))
}

// Amplitude_Ramp is a wavy indicator's amplitude tween: value the current
// amplitude, from where the tween started, target where it ends, t the
// seconds since it started. started is false until the first frame, which
// sits at its target.
@(private = "file")
Amplitude_Ramp :: struct {
	value, from, target, t: f32,
	started:                bool,
}

// amplitude_ramp eases a wavy indicator's amplitude to target over 500ms
// (sys.motion.duration.long2), standard easing going up and
// emphasized-accelerate coming down (progress-indicator.json layout,
// WavyProgressIndicator.kt:490-511), in s. A nil s, a still frame, is the
// target at once.
@(private = "file")
amplitude_ramp :: proc(gtx: ^ui.Ctx, s: ^Amplitude_Ramp, target: f32) -> f32 {
	if s == nil {
		return target
	}
	if !s.started {
		s^ = {value = target, target = target, started = true}
		return target
	}
	if target != s.target {
		s.from, s.target, s.t = s.value, target, 0
	}
	if s.value == s.target {
		return s.value
	}
	s.t += gtx.dt
	u := min(s.t / (tok.SYS_MOTION_DURATION_LONG2 / 1000), 1)
	e := tok.SYS_MOTION_EASING_STANDARD if s.target > s.from else tok.SYS_MOTION_EASING_EMPHASIZED_ACCELERATE
	s.value = u >= 1 ? s.target : s.from + (s.target - s.from) * bezier_ease(e, u)
	if u < 1 {
		ui.request_frame(gtx)
	}
	return s.value
}
