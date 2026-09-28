/*
Package material is Material 3 on jm:ui: the M3 system tokens (colour
scheme, type scale, shape, state opacities) and the components built from
them, each a plain immediate-mode proc like jm:ui's own widgets.

	material.use(&scheme) // once per frame, or never for the baseline light scheme
	if material.button(gtx, "Save") { save(m) }
	material.checkbox(gtx, &m.agree)

Every value comes from the M3 Expressive kit (~/Source/Personal/m3e-kit):
tokens from its m3e.resolved.json, generated into package tokens (imported
as tok), and behaviour from its foundations.json and components/<id>.json
specs, which cite Jetpack Compose. Where a component departs from its spec
the proc's own comment says so.

Motion: Expressive components animate with springs (sys.motion.spring),
kept per widget in ui.Widget_State.springs through animate. use_motion
picks the Expressive or Standard spring set; use_fonts gives the faces for
the type scale's 400, 500 and 700 weights.

Interaction: every interactive component takes state := Interaction.Live.
Live reads real input. Any other value paints that state statically and
ignores input — the kitchen uses this to show a component's enabled,
hovered, focused, pressed and disabled looks side by side, as the spec's
own state diagrams do.

The scheme lives outside ui.Ctx: jm:ui's Theme is its own small palette and
Ctx has no slot for a design system's tokens, so the active Scheme is a
thread-local set by use.
*/
package material

import "jm:ui"
import tok "jm:ui/material/tokens"

// Scheme is M3's colour roles (sys.color), indexed by role.
Scheme :: [tok.Role]ui.Color

// hex is 0xRRGGBB as an opaque Color.
hex :: proc(v: u32) -> ui.Color {
	return {u8(v >> 16), u8(v >> 8), u8(v), 255}
}

// light_scheme is the kit's baseline light scheme.
light_scheme :: proc() -> (s: Scheme) {
	for v, r in tok.LIGHT {
		s[r] = hex(v)
	}
	return
}

// dark_scheme is the kit's baseline dark scheme.
dark_scheme :: proc() -> (s: Scheme) {
	for v, r in tok.DARK {
		s[r] = hex(v)
	}
	return
}

@(private = "file", thread_local)
baseline: Scheme

@(private = "file", thread_local)
active: ^Scheme

// use makes s the scheme every component on this thread reads. s must
// outlive the frames that use it.
use :: proc(s: ^Scheme) {
	active = s
}

// scheme is the active scheme, the baseline light one if use was never called.
scheme :: proc() -> ^Scheme {
	if active == nil {
		if baseline[.Surface] == {} {
			baseline = light_scheme()
		}
		return &baseline
	}
	return active
}

// color is role r in the active scheme; a comp colour token is a Role, so
// color(tok.FILLED_BUTTON_CONTAINER_COLOR) is that button's container.
color :: proc(r: tok.Role) -> ui.Color {
	return scheme()[r]
}

// theme_for maps s onto a jm:ui Theme so jm:ui's own widgets (label,
// divider, box) sit in the same palette as the material ones around them.
theme_for :: proc(s: ^Scheme, font: ui.Font_Id) -> ui.Theme {
	th := ui.light_theme(font)
	th.bg = s[.Surface]
	th.surface = s[.Surface_Container]
	th.surface_hover = s[.Surface_Container_High]
	th.surface_active = s[.Surface_Container_Highest]
	th.fg = s[.On_Surface]
	th.muted = s[.On_Surface_Variant]
	th.accent = s[.Primary]
	th.on_accent = s[.On_Primary]
	th.outline = s[.Outline_Variant]
	th.danger = s[.Error]
	th.primary_container = s[.Primary_Container]
	th.on_primary_container = s[.On_Primary_Container]
	th.secondary_container = s[.Secondary_Container]
	th.on_secondary_container = s[.On_Secondary_Container]
	th.text_size = 14
	return th
}

// Fonts are the faces for the weights M3's type scale uses. jm:ui picks a
// face per run, not a weight, so each weight is its own font file.
Fonts :: struct {
	regular, medium, bold: ui.Font_Id, // 400, 500, 700
}

@(private, thread_local)
fonts: Maybe(Fonts)

// use_fonts sets the faces text is drawn in on this thread. Until it is
// called every weight is drawn in the theme font.
use_fonts :: proc(f: Fonts) {
	fonts = f
}

// font_for is the face for weight w: the nearest of 400, 500 and 700.
font_for :: proc(gtx: ^ui.Ctx, w: f32) -> ui.Font_Id {
	f, ok := fonts.?
	if !ok {
		return gtx.theme.font
	}
	switch {
	case w >= 600:
		return f.bold
	case w >= 450:
		return f.medium
	}
	return f.regular
}

// Motion_Scheme is the app-wide spring set: Expressive overshoots on
// spatial moves; Standard is calmer, for productivity apps.
Motion_Scheme :: enum u8 {
	Expressive,
	Standard,
}

@(private = "file", thread_local)
motion: Motion_Scheme

// use_motion sets the spring set components on this thread animate with.
use_motion :: proc(m: Motion_Scheme) {
	motion = m
}

// Spring is one of sys.motion.spring's six named springs.
Spring :: enum u8 {
	Fast_Spatial,
	Default_Spatial,
	Slow_Spatial,
	Fast_Effects,
	Default_Effects,
	Slow_Effects,
}

// spring_params is s's damping and stiffness in the active motion scheme.
spring_params :: proc(s: Spring) -> ui.Spring_Params {
	std := motion == .Standard
	switch s {
	case .Fast_Spatial:
		return std ? {tok.SYS_MOTION_SPRING_FAST_SPATIAL_DAMPING_STANDARD, tok.SYS_MOTION_SPRING_FAST_SPATIAL_STIFFNESS_STANDARD} : {tok.SYS_MOTION_SPRING_FAST_SPATIAL_DAMPING, tok.SYS_MOTION_SPRING_FAST_SPATIAL_STIFFNESS}
	case .Default_Spatial:
		return std ? {tok.SYS_MOTION_SPRING_DEFAULT_SPATIAL_DAMPING_STANDARD, tok.SYS_MOTION_SPRING_DEFAULT_SPATIAL_STIFFNESS_STANDARD} : {tok.SYS_MOTION_SPRING_DEFAULT_SPATIAL_DAMPING, tok.SYS_MOTION_SPRING_DEFAULT_SPATIAL_STIFFNESS}
	case .Slow_Spatial:
		return std ? {tok.SYS_MOTION_SPRING_SLOW_SPATIAL_DAMPING_STANDARD, tok.SYS_MOTION_SPRING_SLOW_SPATIAL_STIFFNESS_STANDARD} : {tok.SYS_MOTION_SPRING_SLOW_SPATIAL_DAMPING, tok.SYS_MOTION_SPRING_SLOW_SPATIAL_STIFFNESS}
	case .Fast_Effects:
		return std ? {tok.SYS_MOTION_SPRING_FAST_EFFECTS_DAMPING_STANDARD, tok.SYS_MOTION_SPRING_FAST_EFFECTS_STIFFNESS_STANDARD} : {tok.SYS_MOTION_SPRING_FAST_EFFECTS_DAMPING, tok.SYS_MOTION_SPRING_FAST_EFFECTS_STIFFNESS}
	case .Default_Effects:
		return std ? {tok.SYS_MOTION_SPRING_DEFAULT_EFFECTS_DAMPING_STANDARD, tok.SYS_MOTION_SPRING_DEFAULT_EFFECTS_STIFFNESS_STANDARD} : {tok.SYS_MOTION_SPRING_DEFAULT_EFFECTS_DAMPING, tok.SYS_MOTION_SPRING_DEFAULT_EFFECTS_STIFFNESS}
	case .Slow_Effects:
		return std ? {tok.SYS_MOTION_SPRING_SLOW_EFFECTS_DAMPING_STANDARD, tok.SYS_MOTION_SPRING_SLOW_EFFECTS_STIFFNESS_STANDARD} : {tok.SYS_MOTION_SPRING_SLOW_EFFECTS_DAMPING, tok.SYS_MOTION_SPRING_SLOW_EFFECTS_STIFFNESS}
	}
	return {1, 1600}
}

// animate moves c's spring slot (0-3, numbered by the component) toward
// target along spring s and returns its value. A forced state (c.st nil)
// has no retained state, so it is the target at once. threshold is the
// settle distance in the value's own unit: 0.01 for a 0-1 fraction, 0.1 for dp.
animate :: proc(gtx: ^ui.Ctx, c: Control, slot: int, target: f32, s: Spring, threshold := ui.SPRING_THRESHOLD) -> f32 {
	if c.st == nil {
		return target
	}
	return ui.spring_update(&c.st.springs[slot], gtx, target, spring_params(s), threshold)
}

// Shape scale (sys.shape.corner), in dp. Full has no value: it is half
// the shorter side, so resolve a Shape with corners.
CORNER_NONE :: tok.SYS_SHAPE_CORNER_VALUE_NONE
CORNER_EXTRA_SMALL :: tok.SYS_SHAPE_CORNER_VALUE_EXTRA_SMALL
CORNER_SMALL :: tok.SYS_SHAPE_CORNER_VALUE_SMALL
CORNER_MEDIUM :: tok.SYS_SHAPE_CORNER_VALUE_MEDIUM
CORNER_LARGE :: tok.SYS_SHAPE_CORNER_VALUE_LARGE
CORNER_LARGE_INCREASED :: tok.SYS_SHAPE_CORNER_VALUE_LARGE_INCREASED
CORNER_EXTRA_LARGE :: tok.SYS_SHAPE_CORNER_VALUE_EXTRA_LARGE
CORNER_EXTRA_LARGE_INCREASED :: tok.SYS_SHAPE_CORNER_VALUE_EXTRA_LARGE_INCREASED
CORNER_EXTRA_EXTRA_LARGE :: tok.SYS_SHAPE_CORNER_VALUE_EXTRA_EXTRA_LARGE

// Type_Role is one entry of sys.typography: the 15 baseline styles and
// their emphasized twins.
Type_Role :: enum u8 {
	Display_Large,
	Display_Medium,
	Display_Small,
	Headline_Large,
	Headline_Medium,
	Headline_Small,
	Title_Large,
	Title_Medium,
	Title_Small,
	Body_Large,
	Body_Medium,
	Body_Small,
	Label_Large,
	Label_Medium,
	Label_Small,
	Display_Large_Emphasized,
	Display_Medium_Emphasized,
	Display_Small_Emphasized,
	Headline_Large_Emphasized,
	Headline_Medium_Emphasized,
	Headline_Small_Emphasized,
	Title_Large_Emphasized,
	Title_Medium_Emphasized,
	Title_Small_Emphasized,
	Body_Large_Emphasized,
	Body_Medium_Emphasized,
	Body_Small_Emphasized,
	Label_Large_Emphasized,
	Label_Medium_Emphasized,
	Label_Small_Emphasized,
}

TYPE_STYLES := [Type_Role]tok.Type_Style {
	.Display_Large              = tok.SYS_TYPOGRAPHY_DISPLAY_LARGE,
	.Display_Medium             = tok.SYS_TYPOGRAPHY_DISPLAY_MEDIUM,
	.Display_Small              = tok.SYS_TYPOGRAPHY_DISPLAY_SMALL,
	.Headline_Large             = tok.SYS_TYPOGRAPHY_HEADLINE_LARGE,
	.Headline_Medium            = tok.SYS_TYPOGRAPHY_HEADLINE_MEDIUM,
	.Headline_Small             = tok.SYS_TYPOGRAPHY_HEADLINE_SMALL,
	.Title_Large                = tok.SYS_TYPOGRAPHY_TITLE_LARGE,
	.Title_Medium               = tok.SYS_TYPOGRAPHY_TITLE_MEDIUM,
	.Title_Small                = tok.SYS_TYPOGRAPHY_TITLE_SMALL,
	.Body_Large                 = tok.SYS_TYPOGRAPHY_BODY_LARGE,
	.Body_Medium                = tok.SYS_TYPOGRAPHY_BODY_MEDIUM,
	.Body_Small                 = tok.SYS_TYPOGRAPHY_BODY_SMALL,
	.Label_Large                = tok.SYS_TYPOGRAPHY_LABEL_LARGE,
	.Label_Medium               = tok.SYS_TYPOGRAPHY_LABEL_MEDIUM,
	.Label_Small                = tok.SYS_TYPOGRAPHY_LABEL_SMALL,
	.Display_Large_Emphasized   = tok.SYS_TYPOGRAPHY_DISPLAY_LARGE_EMPHASIZED,
	.Display_Medium_Emphasized  = tok.SYS_TYPOGRAPHY_DISPLAY_MEDIUM_EMPHASIZED,
	.Display_Small_Emphasized   = tok.SYS_TYPOGRAPHY_DISPLAY_SMALL_EMPHASIZED,
	.Headline_Large_Emphasized  = tok.SYS_TYPOGRAPHY_HEADLINE_LARGE_EMPHASIZED,
	.Headline_Medium_Emphasized = tok.SYS_TYPOGRAPHY_HEADLINE_MEDIUM_EMPHASIZED,
	.Headline_Small_Emphasized  = tok.SYS_TYPOGRAPHY_HEADLINE_SMALL_EMPHASIZED,
	.Title_Large_Emphasized     = tok.SYS_TYPOGRAPHY_TITLE_LARGE_EMPHASIZED,
	.Title_Medium_Emphasized    = tok.SYS_TYPOGRAPHY_TITLE_MEDIUM_EMPHASIZED,
	.Title_Small_Emphasized     = tok.SYS_TYPOGRAPHY_TITLE_SMALL_EMPHASIZED,
	.Body_Large_Emphasized      = tok.SYS_TYPOGRAPHY_BODY_LARGE_EMPHASIZED,
	.Body_Medium_Emphasized     = tok.SYS_TYPOGRAPHY_BODY_MEDIUM_EMPHASIZED,
	.Body_Small_Emphasized      = tok.SYS_TYPOGRAPHY_BODY_SMALL_EMPHASIZED,
	.Label_Large_Emphasized     = tok.SYS_TYPOGRAPHY_LABEL_LARGE_EMPHASIZED,
	.Label_Medium_Emphasized    = tok.SYS_TYPOGRAPHY_LABEL_MEDIUM_EMPHASIZED,
	.Label_Small_Emphasized     = tok.SYS_TYPOGRAPHY_LABEL_SMALL_EMPHASIZED,
}

// type_scale is role's font size and line height.
type_scale :: proc(role: Type_Role) -> (size, line_height: f32) {
	st := TYPE_STYLES[role]
	return st.size, st.line_height
}

// State opacities: the sys.state tokens (m3e-kit foundations.json,
// deltaFromMaterialWebV0192: focus and pressed are 0.10, not 0.12).
HOVER_OPACITY :: tok.SYS_STATE_HOVER_STATE_LAYER_OPACITY
FOCUS_OPACITY :: tok.SYS_STATE_FOCUS_STATE_LAYER_OPACITY
PRESSED_OPACITY :: tok.SYS_STATE_PRESSED_STATE_LAYER_OPACITY
DRAGGED_OPACITY :: tok.SYS_STATE_DRAGGED_STATE_LAYER_OPACITY
// The disabled defaults (foundations.json interaction.disabled) for a
// component whose spec names no disabled-*-opacity token of its own.
DISABLED_CONTAINER_OPACITY :: f32(0.12)
DISABLED_CONTENT_OPACITY :: f32(0.38)

// Interaction is the state a component paints. Live follows real input;
// the rest force one look and take no input.
Interaction :: enum u8 {
	Live,
	Enabled,
	Hovered,
	Focused,
	Pressed,
	Dragged,
	Disabled,
}

// STATES is every forced Interaction, in the order the spec shows them.
STATES :: [?]Interaction{.Enabled, .Hovered, .Focused, .Pressed, .Disabled}

// Control is one frame's interaction outcome for a component: whether it
// was activated, and what to paint.
Control :: struct {
	st:       ^ui.Widget_State, // nil unless Live
	clicked:  bool,
	layer:    f32, // state-layer opacity, 0 for none
	hovered:  bool,
	pressed:  bool,
	focused:  bool, // paint a focus ring
	disabled: bool,
}

// control resolves state for the component with id and bounds. Live reads
// this frame's events, so a click or an Enter/Space while focused sets
// clicked; the forced states only set what to paint.
control :: proc(gtx: ^ui.Ctx, id: ui.Area_Id, bounds: ui.Rect, state: Interaction) -> Control {
	c: Control
	switch state {
	case .Live:
		c.st = ui.widget_state(gtx, id)
		c.clicked = ui.click_from_events(gtx, id, c.st, bounds)
		c.hovered, c.pressed, c.focused = c.st.hovered, c.st.pressed, c.st.focused
	case .Enabled:
	case .Hovered:
		c.hovered = true
	case .Focused:
		c.focused = true
	case .Pressed, .Dragged:
		c.pressed = true
	case .Disabled:
		c.disabled = true
	}
	switch {
	case state == .Dragged:
		c.layer = DRAGGED_OPACITY
	case c.pressed:
		c.layer = PRESSED_OPACITY
	case c.focused:
		c.layer = FOCUS_OPACITY
	case c.hovered:
		c.layer = HOVER_OPACITY
	}
	return c
}

// CLICK_KINDS is what a clickable component's input area asks for.
CLICK_KINDS :: ui.Event_Kinds{.Press, .Release, .Enter, .Leave, .Move, .Key, .Focus, .Blur}

// listen registers id's input area when c is Live.
listen :: proc(gtx: ^ui.Ctx, c: Control, id: ui.Area_Id, shape: ui.Shape, kinds := CLICK_KINDS) {
	if c.st != nil {
		ui.input_area(gtx.ops, id, shape, kinds)
	}
}

// paint_state_layer paints c's state layer of color over shape, then any ripple.
paint_state_layer :: proc(gtx: ^ui.Ctx, c: Control, shape: ui.Shape, color: ui.Color) {
	if c.disabled {
		return
	}
	if c.layer > 0 {
		ui.fill(gtx.ops, shape, ui.with_alpha(color, c.layer))
	}
	if c.st != nil {
		ui.paint_ripple(gtx, c.st, shape, color)
	}
}

// FOCUS_RING_WIDTH and FOCUS_RING_OFFSET are the focus ring's stroke and
// its gap outside the component: hand-set from the m3e-kit's
// foundations.json interaction.focusRing, as the token file has none.
FOCUS_RING_WIDTH :: f32(3)
FOCUS_RING_OFFSET :: f32(2)

// paint_focus_ring is the focus ring: a secondary stroke outside rr,
// following its corners.
paint_focus_ring :: proc(gtx: ^ui.Ctx, c: Control, rr: ui.Round_Rect, inward := false) {
	paint_focus_ring_corners(gtx, c, rr.rect, corners_all(rr.radius), inward)
}

// paint_focus_ring_corners is paint_focus_ring for per-corner radii k.
//
// inward draws the ring just inside the shape instead, its outer edge on
// the shape's: for controls packed closer than the ring's 5dp reach
// (connected groups, segments, list and menu rows, tabs, calendar days),
// where an outward ring would cross into the neighbours. Material Web
// does the same: md-focus-ring's inward attribute (@material/web
// focus/internal/focus-ring.ts).
paint_focus_ring_corners :: proc(gtx: ^ui.Ctx, c: Control, r: ui.Rect, k: Corners, inward := false) {
	if !c.focused || c.disabled {
		return
	}
	o := inward ? -FOCUS_RING_WIDTH / 2 : FOCUS_RING_OFFSET + FOCUS_RING_WIDTH / 2
	ring := ui.Rect{r.x - o, r.y - o, r.w + 2 * o, r.h + 2 * o}
	ui.stroke(gtx.ops, rounded(gtx, ring, grow_corners(k, o)), scheme()[.Secondary], {width = FOCUS_RING_WIDTH})
}

// disabled_content and disabled_container are M3's disabled treatment:
// on-surface at a fixed alpha, whatever the component's own colours were.
disabled_content :: proc() -> ui.Color {
	return ui.with_alpha(scheme()[.On_Surface], DISABLED_CONTENT_OPACITY)
}

disabled_container :: proc() -> ui.Color {
	return ui.with_alpha(scheme()[.On_Surface], DISABLED_CONTAINER_OPACITY)
}

// paint_elevation paints an approximate shadow for M3 elevation level 0-5 under
// rr (level 1-5 = 1, 3, 6, 8, 12dp). jm:ui has no blur, so it is a stack
// of offset translucent round rects: soft enough to read as a lift, not the
// spec's two-shadow (key + ambient) composite.
paint_elevation :: proc(gtx: ^ui.Ctx, rr: ui.Round_Rect, level: int) {
	DP := [6]f32{0, 1, 3, 6, 8, 12}
	paint_elevation_dp(gtx, rr, DP[clamp(level, 0, 5)])
}

// Text helpers. Every component shapes in the theme font at a type role.

// Text :: a shaped run with the metrics needed to place it.
Text :: struct {
	run:     ui.Glyph_Run,
	metrics: ui.Font_Metrics,
	width:   f32,
	height:  f32, // the role's line height, not the font's
}

// shape_text shapes s at a type role or style, in the face for its
// weight, into the frame allocator. jm:ui has no tracking, so a style's
// letter spacing is dropped.
// A comp.*-font token is a style, so shape_style takes it directly.
shape_text :: proc(gtx: ^ui.Ctx, s: string, role: Type_Role) -> Text {
	return shape_style(gtx, s, TYPE_STYLES[role])
}

shape_style :: proc(gtx: ^ui.Ctx, s: string, st: tok.Type_Style) -> Text {
	font := font_for(gtx, st.weight)
	run := ui.shape(gtx.shaper, font, st.size, s, gtx.allocator)
	m := ui.metrics(gtx.shaper, font, st.size)
	return {run, m, run.advance, st.line_height}
}

// draw_text draws t with its line box's top-left at pos, vertically
// centring the font's ascent+descent in the role's line height.
draw_text :: proc(gtx: ^ui.Ctx, t: Text, pos: ui.Point, color: ui.Color) {
	if color[3] == 0 || len(t.run.glyphs) == 0 {
		return
	}
	glyph_h := t.metrics.ascent + t.metrics.descent
	y := pos.y + (t.height - glyph_h) / 2 + t.metrics.ascent
	ui.glyphs(gtx.ops, ui.add_run(gtx.ops, t.run), {pos.x, y}, color)
}

// baseline_of is where draw_text puts t's baseline, relative to its top.
baseline_of :: proc(t: Text) -> f32 {
	return (t.height - t.metrics.ascent - t.metrics.descent) / 2 + t.metrics.ascent
}

// draw_role_text is shape_text then draw_text of s at role, in one call.
draw_role_text :: proc(gtx: ^ui.Ctx, s: string, pos: ui.Point, role: Type_Role, color: ui.Color) -> Text {
	t := shape_text(gtx, s, role)
	draw_text(gtx, t, pos, color)
	return t
}

// draw_style_text is draw_role_text for a style token.
draw_style_text :: proc(gtx: ^ui.Ctx, s: string, pos: ui.Point, st: tok.Type_Style, color: ui.Color) -> Text {
	t := shape_style(gtx, s, st)
	draw_text(gtx, t, pos, color)
	return t
}

// stroke_inside strokes the inside edge of rr at width w.
stroke_inside :: proc(gtx: ^ui.Ctx, rr: ui.Round_Rect, color: ui.Color, w: f32 = 1) {
	h := w / 2
	r := rr.rect
	ui.stroke(gtx.ops, ui.Round_Rect{{r.x + h, r.y + h, r.w - w, r.h - w}, max(rr.radius - h, 0)}, color, {width = w})
}

// elevation_level is the sys.elevation level (0-5) for an elevation token
// in dp: the highest level at or below it. paint_elevation takes levels.
elevation_level :: proc(dp: f32) -> int {
	LEVELS := [6]f32 {
		tok.SYS_ELEVATION_LEVEL0,
		tok.SYS_ELEVATION_LEVEL1,
		tok.SYS_ELEVATION_LEVEL2,
		tok.SYS_ELEVATION_LEVEL3,
		tok.SYS_ELEVATION_LEVEL4,
		tok.SYS_ELEVATION_LEVEL5,
	}
	level := 0
	for v, i in LEVELS {
		if dp >= v {
			level = i
		}
	}
	return level
}

// fade is c with its alpha scaled by t, for content fading in or out.
fade :: proc(c: ui.Color, t: f32) -> ui.Color {
	return ui.with_alpha(c, f32(c[3]) / 255 * clamp(t, 0, 1))
}

// MIN_TOUCH is foundations.json interaction.touchTarget.minDp.
MIN_TOUCH :: f32(48)

// touch_target is r grown to at least MIN_TOUCH on each axis, about its centre.
touch_target :: proc(r: ui.Rect) -> ui.Rect {
	dw, dh := max(MIN_TOUCH - r.w, 0), max(MIN_TOUCH - r.h, 0)
	return {r.x - dw / 2, r.y - dh / 2, r.w + dw, r.h + dh}
}

// stroke_inside_corners strokes the inside edge of r with per-corner
// radii k at width w: stroke_inside for a shape a Round_Rect cannot hold.
stroke_inside_corners :: proc(gtx: ^ui.Ctx, r: ui.Rect, k: Corners, color: ui.Color, w: f32) {
	h := w / 2
	ui.stroke(gtx.ops, rounded(gtx, {r.x + h, r.y + h, r.w - w, r.h - w}, grow_corners(k, -h)), color, {width = w})
}

// bezier_ease is a CSS cubic-bezier easing b at x in [0, 1]: it solves
// the curve's x for its parameter, then returns y there.
bezier_ease :: proc(b: tok.Bezier, x: f32) -> f32 {
	if x <= 0 {
		return 0
	}
	if x >= 1 {
		return 1
	}
	curve :: proc(p1, p2, u: f32) -> f32 {
		v := 1 - u
		return 3 * v * v * u * p1 + 3 * v * u * u * p2 + u * u * u
	}
	// Bisection: x(u) rises monotonically for any easing whose control
	// points' x lie in [0, 1], and 24 halvings are finer than f32.
	lo, hi: f32 = 0, 1
	for _ in 0 ..< 24 {
		mid := (lo + hi) / 2
		if curve(b[0], b[2], mid) < x {
			lo = mid
		} else {
			hi = mid
		}
	}
	return curve(b[1], b[3], (lo + hi) / 2)
}

// paint_elevation_dp is paint_elevation for an elevation in dp rather
// than a level, so a token's value (and a tween between two) paints
// directly: the same stack of offset translucent round rects.
paint_elevation_dp :: proc(gtx: ^ui.Ctx, rr: ui.Round_Rect, dp: f32) {
	if dp <= 0 {
		return
	}
	sh := ui.Color{0, 0, 0, 255} // foundations.json color.missingRoles: shadow is black
	steps := 4
	for i in 0 ..< steps {
		t := f32(i + 1) / f32(steps)
		spread := dp * 0.5 * t
		y := dp * 0.5 * t
		r := rr.rect
		ui.fill(
			gtx.ops,
			ui.Round_Rect{{r.x - spread + dp * 0.25, r.y - spread + y + dp * 0.25, r.w + 2 * spread - dp * 0.5, r.h + 2 * spread - dp * 0.5}, rr.radius + spread},
			ui.with_alpha(sh, 0.10 / f32(steps) * (2 - t)),
		)
	}
}
