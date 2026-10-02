package primer

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
