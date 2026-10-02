package primer

import "base:runtime"
import "core:fmt"
import "core:math"
import "jm:ui"
import "jm:ui/design"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// Spinner_Size is a spinner's square side (primer-kit spinner.json,
// Spinner.tsx:12-16): 16, 32 or 64px.
Spinner_Size :: enum u8 {
	Small,
	Medium,
	Large,
}

@(rodata)
SPINNER_SIDE := [Spinner_Size]f32{.Small = 16, .Medium = 32, .Large = 64}

// SPINNER_PERIOD is one turn, in seconds: every spinner reads the same
// clock, so all on screen show one angle (spinner.json behaviour).
SPINNER_PERIOD :: 1.0

// SPINNER_DELAY is how long a delayed spinner waits before it shows, in
// seconds, for delay short and long (Spinner.tsx: 300ms and 1000ms).
@(rodata)
SPINNER_DELAY := [Spinner_Delay]f64{.None = 0, .Short = 0.3, .Long = 1}

// Spinner_Delay is how long a spinner stays hidden after it first appears.
Spinner_Delay :: enum u8 {
	None,
	Short,
	Long,
}

@(private)
Spinner_Start :: struct {
	since: f64,
	set:   bool,
}

// spinner is Primer's indeterminate loading indicator: a quarter arc
// turning over a faint ring, in tint (the colour of the text it sits
// in, --fgColor-default when zero: spinner.json layout says it strokes
// currentColor and has no token of its own). Strokes stay 2px at every
// size while the radius scales (spinner.json layout). A delayed
// spinner takes no space until its delay has passed. label is what
// assistive technology hears.
spinner :: proc(gtx: ^ui.Ctx, size := Spinner_Size.Medium, tint := ops.Color{}, delay := Spinner_Delay.None, label := "Loading", key: u64 = 0, loc := #caller_location) {
	p := ui.widget_open(gtx, key, loc)
	if delay != .None {
		seen := ui.widget_data(gtx, p.id, Spinner_Start)
		if !seen.set {
			seen^ = {gtx.time, true}
		}
		wait := SPINNER_DELAY[delay] - (gtx.time - seen.since)
		if wait > 0 {
			ui.request_frame(gtx, f32(wait))
			ui.widget_close(gtx, &p, {})
			return
		}
	}
	side := SPINNER_SIDE[size]
	sz := ui.constrain_min(gtx.constraints, {side, side})
	paint_spinner(gtx, {(sz.x - side) / 2, (sz.y - side) / 2}, side, ui.or_color(tint, color(.Fg_Color_Default)))
	ui.semantics(gtx, &p, {role = .Progress, label = ui.frame_string(gtx, label)})
	ui.widget_close(gtx, &p, {sz, 0})
}

// paint_spinner draws a spinner side px square at pos in c, at the
// shared clock's angle: the track at 25% and the arc from 3 to 12
// o'clock, rotated (spinner.json anatomy). It asks for the next frame,
// as a turning spinner always needs one.
@(private)
paint_spinner :: proc(gtx: ^ui.Ctx, pos: ops.Point, side: f32, c: ops.Color) {
	TRACK_ALPHA :: 0.25
	STROKE :: 2
	k := side / 16
	centre := pos + {8 * k, 8 * k}
	r := 7 * k
	turn := f32(math.mod(gtx.time, SPINNER_PERIOD) / SPINNER_PERIOD) * 2 * math.PI
	ops.stroke(gtx.scene, design.arc(gtx, centre, r, 0, 2 * math.PI), fade(c, TRACK_ALPHA), {width = STROKE})
	ops.stroke(gtx.scene, design.arc(gtx, centre, r, turn, turn - math.PI / 2), c, {width = STROKE, cap = .Round})
	ui.request_frame(gtx)
}

// Counter_Variant is a CounterLabel's emphasis.
Counter_Variant :: enum u8 {
	Secondary,
	Primary,
}

// Counter_Colors is a pill's fill and text; a Button supplies its own.
@(private)
Counter_Colors :: struct {
	fill, text: ops.Color,
}

// counter_colors is variant's pill colours (counter-label.json variants).
@(private)
counter_colors :: proc(variant: Counter_Variant) -> Counter_Colors {
	switch variant {
	case .Primary:
		return {color(.Bg_Color_Neutral_Emphasis), color(.Fg_Color_On_Emphasis)}
	case .Secondary:
	}
	return {color(.Bg_Color_Neutral_Muted), color(.Fg_Color_Default)}
}

// COUNTER_RADIUS is the pill's hard-coded 20px radius, more than half its
// 18px height, so its ends are round (counter-label.json notes).
COUNTER_RADIUS :: f32(20)

// counter_style is a pill's text: small body size at semibold, its line
// box one font size tall (CounterLabel.module.css:1-8, line-height 1).
@(private)
counter_style :: proc() -> tok.Type_Style {
	return {weight = tok.BASE_TEXT_WEIGHT_SEMIBOLD, size = tok.TEXT_BODY_SIZE_SMALL, line_height = tok.TEXT_BODY_SIZE_SMALL}
}

// counter_size is the pill around t: 2px above and below and 6px each
// side, plus a 1px border (counter-label.json layout).
@(private)
counter_size :: proc(t: Text) -> ops.Size {
	PAD_X :: 6
	PAD_Y :: 2
	b := tok.BORDER_WIDTH_THIN
	return {t.width + 2 * (PAD_X + b), t.height + 2 * (PAD_Y + b)}
}

// paint_counter draws the pill for t at pos in colors, its border the
// --counter-borderColor that only the high-contrast themes make visible
// (counter-label.json notes: transparent in the others).
@(private)
paint_counter :: proc(gtx: ^ui.Ctx, t: Text, pos: ops.Point, colors: Counter_Colors) {
	sz := counter_size(t)
	box := ops.Rect{pos.x, pos.y, sz.x, sz.y}
	rr := ops.Round_Rect{box, radius(COUNTER_RADIUS, box)}
	ops.fill(gtx.scene, rr, colors.fill)
	if border := color(.Counter_Border_Color); ui.painted(border) {
		stroke_inside(gtx, rr, border, tok.BORDER_WIDTH_THIN)
	}
	draw_text(gtx, t, {pos.x + (sz.x - t.width) / 2, pos.y + (sz.y - t.height) / 2}, colors.text)
}

// counter_label is a small pill showing count beside a tab, button or
// heading. An empty count draws nothing and takes no space; "0" is a
// count (counter-label.json notes).
counter_label :: proc(gtx: ^ui.Ctx, count: string, variant := Counter_Variant.Secondary, key: u64 = 0, loc := #caller_location) {
	p := ui.widget_open(gtx, key, loc)
	if count == "" {
		ui.widget_close(gtx, &p, {})
		return
	}
	st := counter_style()
	t := design.shape_style(gtx, count, st, font_for(gtx, st.weight))
	sz := ui.constrain_min(gtx.constraints, counter_size(t))
	paint_counter(gtx, t, {0, (sz.y - counter_size(t).y) / 2}, counter_colors(variant))
	said := ui.frame_string(gtx, count)
	ui.semantics(gtx, &p, {role = .Text, label = said})
	ui.widget_close(gtx, &p, {sz, (sz.y - t.height) / 2 + baseline_of(t)})
}

// SHIMMER is the loading shimmer's sweep: one pass a second
// (--base-duration-1000) on CSS's default ease, cubic-bezier(0.25, 0.1,
// 0.25, 1) (SkeletonBox.module.css:1-24, ProgressBar.module.css:1-28).
SHIMMER :: tok.Transition{tok.BASE_DURATION_1000, {0.25, 0.1, 0.25, 1}}

// shimmer_alpha is the shimmer mask's opacity at u in [0, 1) of its tile:
// opaque to 0.3, falling linearly to 0.65 at 0.8 and 0.65 to the end.
shimmer_alpha :: proc(u: f32) -> f32 {
	switch {
	case u <= 0.3:
		return 1
	case u >= 0.8:
		return 0.65
	}
	return 1 - 0.35 * (u - 0.3) / 0.5
}

// shimmer_stops are the gradient stops that mask c across a box at eased
// progress e through the sweep: alpha(x) = g(((x / w - 2e) mod 2) / 2), a
// tile twice the box's width moving right (skeleton-box.json behaviour
// shimmer). The 75deg tilt is dropped: on a box 5 to 40px tall it moves a
// band by under 11px. The tile's seam, where 0.65 meets 1, is a hard edge
// of two stops at one offset.
shimmer_stops :: proc(gtx: ^ui.Ctx, c: ops.Color, e: f32) -> []ops.Gradient_Stop {
	at :: proc(t, e: f32) -> f32 {
		v := math.mod(t - 2 * e, 2)
		if v < 0 {
			v += 2
		}
		return shimmer_alpha(v / 2)
	}
	stop :: proc(c: ops.Color, t, a: f32) -> ops.Gradient_Stop {
		return {t, {c[0], c[1], c[2], u8(math.round(f32(c[3]) * a))}}
	}
	out := make([dynamic]ops.Gradient_Stop, 0, 12, gtx.allocator)
	append(&out, stop(c, 0, at(0, e)))
	// Each tile, offset 2k, has its bends at v = 0.6 and 1.6 and its seam
	// at v = 0; a box spans at most two tiles.
	for k in -2 ..= 1 {
		base := 2 * e + 2 * f32(k)
		for v in ([3]f32{0, 0.6, 1.6}) {
			t := base + v
			if t <= 0 || t >= 1 {
				continue
			}
			if v == 0 {
				append(&out, stop(c, t, 0.65), stop(c, t, 1))
			} else {
				append(&out, stop(c, t, shimmer_alpha(v / 2)))
			}
		}
	}
	// The right end takes its left-hand limit, where a seam falls exactly
	// on it.
	append(&out, stop(c, 1, at(1 - 1e-4, e)))
	// Ascending by offset; a stable sort keeps a seam's two stops in order.
	for i in 1 ..< len(out) {
		for j := i; j > 0 && out[j - 1].t > out[j].t; j -= 1 {
			out[j - 1], out[j] = out[j], out[j - 1]
		}
	}
	return out[:]
}

// paint_shimmer fills shape over box in c, masked by the shimmer at the
// shared clock's phase and asking for the next frame; under reduced motion
// (gtx.reduce_motion) it fills c plainly, as the CSS animates only under
// prefers-reduced-motion: no-preference (SkeletonBox.module.css:16-24,
// ProgressBar.module.css:20-28).
@(private)
paint_shimmer :: proc(gtx: ^ui.Ctx, shape: ops.Shape, box: ops.Rect, c: ops.Color) {
	if gtx.reduce_motion || box.w <= 0 {
		ops.fill(gtx.scene, shape, c)
		return
	}
	period := f64(SHIMMER.duration) / 1000
	e := bezier_ease(SHIMMER.easing, f32(math.mod(gtx.time, period) / period))
	ops.fill(gtx.scene, shape, ops.Linear_Gradient{{box.x, 0}, {box.x + box.w, 0}, shimmer_stops(gtx, c, e)})
	ui.request_frame(gtx)
}

// skeleton_box is Primer's SkeletonBox: a placeholder block of
// --skeletonLoader-bgColor, a translucent neutral that tints what it sits
// on, with --borderRadius-small corners, shimmering
// (primer-kit skeleton-box.json, SkeletonBox.module.css:1-29). width 0
// fills the width offered; height defaults to 16px (1rem). A delayed box
// takes no space until its delay has passed. It says nothing to assistive
// technology: the region around it should.
//
// Departures: delay takes short (300ms) or long (1000ms), not any number
// of ms; the forced-colours outline is not drawn.
skeleton_box :: proc(gtx: ^ui.Ctx, width: f32 = 0, height: f32 = 16, delay := Spinner_Delay.None, key: u64 = 0, loc := #caller_location) {
	p := ui.widget_open(gtx, key, loc)
	if still_waiting(gtx, p.id, delay) {
		ui.widget_close(gtx, &p, {})
		return
	}
	w := width > 0 ? width : fill_width(gtx)
	sz := ui.constrain_min(gtx.constraints, {w, height})
	box := ops.Rect{0, 0, w, height}
	paint_shimmer(gtx, ops.Round_Rect{box, radius(tok.BORDER_RADIUS_SMALL, box)}, box, color(.Skeleton_Loader_Bg_Color))
	ops.tag(gtx.scene, p.id, "skeleton", box)
	ui.widget_close(gtx, &p, {sz, 0})
}

// fill_width is the width a block fills: the offered maximum, or the
// minimum when that is unbounded.
@(private)
fill_width :: proc(gtx: ^ui.Ctx) -> f32 {
	if gtx.constraints.max.x < ui.INF {
		return gtx.constraints.max.x
	}
	return gtx.constraints.min.x
}

// still_waiting is whether a component with a delay is still waiting, asking
// for the frame that ends the wait (Spinner.tsx, SkeletonBox.tsx:22-39).
@(private)
still_waiting :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, delay: Spinner_Delay) -> bool {
	if delay == .None {
		return false
	}
	seen := ui.widget_data(gtx, id, Spinner_Start)
	if !seen.set {
		seen^ = {gtx.time, true}
	}
	wait := SPINNER_DELAY[delay] - (gtx.time - seen.since)
	if wait > 0 {
		ui.request_frame(gtx, f32(wait))
		return true
	}
	return false
}

// SKELETON_LAST_MIN and SKELETON_LAST_SHARE bound a multi-line
// SkeletonText's last bar: at least 50px, at most 65% of the block
// (SkeletonText.module.css:19-23).
SKELETON_LAST_MIN :: f32(50)
SKELETON_LAST_SHARE :: f32(0.65)

// skeleton_text is Primer's SkeletonText: bars standing in for lines of
// text at role's size (primer-kit skeleton-text.json,
// SkeletonText.module.css:1-70). For the role's font size F and line
// height F x H, each bar is F tall and the leading L = F x H - F. One line
// occupies one line box, its bar L/2 down; several sit 2L apart (the CSS's
// collapsed margins), the last at most 65% wide and at least 50px, the
// block L/2 + n F + (n - 1) 2L tall. Corners are --borderRadius-small,
// medium for Display and Title_Large. max_width caps the width (0 for
// none). Each bar shimmers as a SkeletonBox.
skeleton_text :: proc(gtx: ^ui.Ctx, role := Type_Role.Body_Medium, lines := 1, max_width: f32 = 0, key: u64 = 0, loc := #caller_location) {
	p := ui.widget_open(gtx, key, loc)
	st := style(role)
	f := st.size
	lead := st.line_height - f
	w := fill_width(gtx)
	if max_width > 0 {
		w = min(w, max_width)
	}
	r := tok.BORDER_RADIUS_SMALL
	if role == .Display || role == .Title_Large {
		r = tok.BORDER_RADIUS_MEDIUM
	}
	n := max(lines, 1)
	h := n == 1 ? st.line_height : lead / 2 + f32(n) * f + f32(n - 1) * 2 * lead
	sz := ui.constrain_min(gtx.constraints, {w, h})
	c := color(.Skeleton_Loader_Bg_Color)
	for i in 0 ..< n {
		bw := w
		if n > 1 && i == n - 1 {
			bw = max(min(w * SKELETON_LAST_SHARE, w), min(SKELETON_LAST_MIN, w))
		}
		bar := ops.Rect{0, lead / 2 + f32(i) * (f + 2 * lead), bw, f}
		paint_shimmer(gtx, ops.Round_Rect{bar, min(r, bar.h / 2)}, bar, c)
	}
	ops.tag(gtx.scene, p.id, "skeleton text", {0, 0, w, h})
	ui.widget_close(gtx, &p, {sz, 0})
}

// Progress_Size is a ProgressBar's height: 5, 8 or 10px
// (ProgressBar.module.css:44-54).
Progress_Size :: enum u8 {
	Small,
	Default,
	Large,
}

@(rodata)
PROGRESS_HEIGHT := [Progress_Size]f32{.Small = 5, .Default = 8, .Large = 10}

// PROGRESS_GAP is the gap between a bar's segments (ProgressBar.module.css:36).
PROGRESS_GAP :: f32(2)

// Progress_Item is one segment of a multi-part bar: its percent of the
// track, its fill role (a --bgColor-<role>-<strength> token, emphasis
// by default upstream) and what a reader hears for it.
Progress_Item :: struct {
	progress: f32,
	bg:       tok.Role,
	label:    string,
}

// progress_bar is Primer's ProgressBar with one fill: progress percent
// (0-100) of the track in bg, by default --bgColor-success-emphasis
// (primer-kit progress-bar.json, ProgressBar.module.css:1-67). The track
// is --progressBar-track-bgColor with a 1px --progressBar-track-
// borderColor outline inside its edge and --borderRadius-small corners,
// which clip the fill. width 0 fills the width offered. animated
// shimmers the fill unless the platform asks for reduced motion. Progress
// is not clamped: below 0 draws nothing, past 100 is clipped by the
// track. label is what a reader hears; the value is the rounded percent.
progress_bar :: proc(
	gtx: ^ui.Ctx,
	progress: f32,
	bg := tok.Role.Bg_Color_Success_Emphasis,
	size := Progress_Size.Default,
	animated := false,
	label := "",
	width: f32 = 0,
	key: u64 = 0,
	loc := #caller_location,
) {
	item := [1]Progress_Item{{progress, bg, label}}
	progress_track(gtx, item[:], size, width, animated, key, loc)
}

// progress_bar_items is a ProgressBar of several segments laid side by
// side 2px apart, each as wide as its percent of the track and each a
// progressbar to a reader. Widths are not normalised: segments summing
// to 100 plus their gaps overflow, and the track clips the last.
// Segments never shimmer.
progress_bar_items :: proc(gtx: ^ui.Ctx, items: []Progress_Item, size := Progress_Size.Default, width: f32 = 0, key: u64 = 0, loc := #caller_location) {
	progress_track(gtx, items, size, width, false, key, loc)
}

// progress_track is progress_bar and progress_bar_items.
@(private)
progress_track :: proc(gtx: ^ui.Ctx, items: []Progress_Item, size: Progress_Size, width: f32, animated: bool, key: u64, loc: runtime.Source_Code_Location) {
	p := ui.widget_open(gtx, key, loc)
	h := PROGRESS_HEIGHT[size]
	w := width > 0 ? width : fill_width(gtx)
	sz := ui.constrain_min(gtx.constraints, {w, h})
	y := (sz.y - h) / 2
	track := ops.Rect{0, y, w, h}
	rr := ops.Round_Rect{track, radius(tok.BORDER_RADIUS_SMALL, track)}
	ops.fill(gtx.scene, rr, color(.Progress_Bar_Track_Bg_Color))
	ops.clip_push(gtx.scene, rr)
	x: f32
	for it, i in items {
		if i > 0 {
			x += PROGRESS_GAP
		}
		sw := w * it.progress / 100
		if sw <= 0 {
			continue
		}
		seg := ops.Rect{x, y, sw, h}
		if animated {
			paint_shimmer(gtx, seg, seg, color(it.bg))
		} else {
			ops.fill(gtx.scene, seg, color(it.bg))
		}
		x += sw
	}
	ops.clip_pop(gtx.scene)
	if border := color(.Progress_Bar_Track_Border_Color); ui.painted(border) {
		stroke_inside(gtx, rr, border, 1)
	}
	tag := "progress"
	if len(items) == 1 && items[0].label != "" {
		tag = items[0].label
	}
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, tag), track)
	sx: f32
	for it, i in items {
		sw := max(w * it.progress / 100, 0)
		value := fmt.aprintf("%d%%", int(math.round(max(it.progress, 0))), allocator = gtx.allocator)
		ui.part_semantics(gtx, &p, ui.id_mix(p.id, u64(i) + 1), {sx, y, sw, h}, {role = .Progress, label = ui.frame_string(gtx, it.label), value = value})
		sx += sw + PROGRESS_GAP
	}
	ui.widget_close(gtx, &p, {sz, 0})
}
