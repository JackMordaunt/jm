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

What is not Material's is jm:ui/design's: the Interaction states and
Control, per-corner geometry, text shaping, the shadow stack, easing and
the Theme/axiom checker. This package aliases what it uses unchanged and
wraps what needs its own tokens (state-layer opacities, the focus ring's
colour, its named springs, its font weights), so a component reads one
namespace. What only Material does — painting states as a translucent
layer of the content colour — stays here.

The scheme lives outside ui.Ctx: jm:ui's Theme is its own small palette and
Ctx has no slot for a design system's tokens, so the active Scheme is a
thread-local set by use.
*/
package material

import "jm:ui"
import "jm:ui/ops"
import "jm:ui/design"
import tok "jm:ui/material/tokens"

// Scheme is M3's colour roles (sys.color), indexed by role.
Scheme :: [tok.Role]ops.Color

// hex is 0xRRGGBB as an opaque Color.
hex :: proc(v: u32) -> ops.Color {
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
color :: proc(r: tok.Role) -> ops.Color {
	return scheme()[r]
}

// theme_for maps s onto a jm:ui Theme so jm:ui's own widgets (label,
// divider, box) sit in the same palette as the material ones around them.
theme_for :: proc(s: ^Scheme, font: ops.Font_Id) -> ui.Theme {
	th := ui.light_theme(font)
	th.bg = s[.Surface]
	th.surface = s[.Surface_Container]
	th.fg = s[.On_Surface]
	th.muted = s[.On_Surface_Variant]
	th.outline = s[.Outline_Variant]
	th.text_size = 14
	return th
}

// Fonts are the faces for the weights M3's type scale uses. jm:ui picks a
// face per run, not a weight, so each weight is its own font file.
Fonts :: struct {
	regular, medium, bold: ops.Font_Id, // 400, 500, 700
}

@(private, thread_local)
fonts: Maybe(Fonts)

// use_fonts sets the faces text is drawn in on this thread. Until it is
// called every weight is drawn in the theme font.
use_fonts :: proc(f: Fonts) {
	fonts = f
}

// font_for is the face for weight w: the nearest of 400, 500 and 700.
font_for :: proc(gtx: ^ui.Ctx, w: f32) -> ops.Font_Id {
	f, ok := fonts.?
	if !ok {
		return gtx.theme.font
	}
	faces := [3]design.Font_Face{{400, f.regular}, {500, f.medium}, {700, f.bold}}
	return design.font_for(faces[:], w, gtx.theme.font)
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
// target along spring s and returns its value: design.animate with the
// active motion scheme's params.
animate :: proc(gtx: ^ui.Ctx, c: Control, slot: int, target: f32, s: Spring, threshold := ui.SPRING_THRESHOLD) -> f32 {
	return design.animate(gtx, c.base, slot, target, spring_params(s), threshold)
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

// Interaction and STATES are design's: Live follows real input; the rest
// force one look and take no input.
Interaction :: design.Interaction
STATES :: design.STATES

// Control is design's resolved interaction plus Material's reading of it:
// the state-layer opacity to paint, 0 for none.
Control :: struct {
	using base: design.Control,
	layer:      f32,
	ripple:     ^Ripple, // nil unless Live
}

// control resolves state for the component with id and bounds (see
// design.control) and picks the state layer for the state it lands in.
control :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, bounds: ops.Rect, state: Interaction) -> (c: Control) {
	c.base = design.control(gtx, id, bounds, state)
	c.layer = state_layer(c.state)
	if c.st != nil {
		c.ripple = ui.widget_data(gtx, id, Ripple)
		if c.press {
			start_ripple(c.ripple, c.press_at)
		}
	}
	return
}

// state_layer is the sys.state opacity for st: a translucent layer of
// the content colour over the container, none when enabled or disabled.
state_layer :: proc(st: Interaction) -> f32 {
	#partial switch st {
	case .Dragged:
		return DRAGGED_OPACITY
	case .Pressed:
		return PRESSED_OPACITY
	case .Focused:
		return FOCUS_OPACITY
	case .Hovered:
		return HOVER_OPACITY
	}
	return 0
}

CLICK_KINDS :: design.CLICK_KINDS

// listen registers id's input area when c is Live.
listen :: proc(gtx: ^ui.Ctx, c: Control, id: ops.Area_Id, shape: ops.Shape, kinds := CLICK_KINDS) {
	design.listen(gtx, c.st, id, shape, kinds)
}

// paint_state_layer paints c's state layer of color over shape, then any ripple.
paint_state_layer :: proc(gtx: ^ui.Ctx, c: Control, shape: ops.Shape, color: ops.Color) {
	if c.disabled {
		return
	}
	if c.layer > 0 {
		ops.fill(gtx.scene, shape, ops.with_alpha(color, c.layer))
	}
	if c.ripple != nil {
		paint_ripple(gtx, c.ripple, shape, color)
	}
}

// Ripple is a component's ink ripple: the tween since the last press and
// where that press landed, local to the widget. It is the component's
// own widget_data, started by control on a press.
Ripple :: struct {
	tween:  ui.Tween,
	origin: ops.Point,
}

// RIPPLE_DURATION is how long the ripple takes to fill the shape; it
// peaks at the pressed state-layer opacity and fades as it grows.
RIPPLE_DURATION :: 0.5
RIPPLE_PEAK_OPACITY :: PRESSED_OPACITY

// start_ripple (re)starts r from origin, overwriting whatever ripple was
// already running: a second click restarts the animation rather than
// showing two ripples at once.
start_ripple :: proc(r: ^Ripple, origin: ops.Point) {
	r.tween = {to = 1, duration = RIPPLE_DURATION}
	r.origin = origin
}

// paint_ripple draws r, if it is still running, as an expanding circle of
// tint clipped to shape, fading as it grows.
paint_ripple :: proc(gtx: ^ui.Ctx, r: ^Ripple, shape: ops.Shape, tint: ops.Color) {
	if r.tween.t >= r.tween.duration {
		return
	}
	t := ui.tween_update(&r.tween, gtx)
	bounds := ops.shape_bounds(gtx.scene, shape)
	rad := t * (bounds.w + bounds.h) // a cheap, safely-oversized bound on the origin-to-farthest-corner distance, without a sqrt
	ops.clip_push(gtx.scene, shape)
	ops.fill(gtx.scene, ops.Ellipse{{r.origin.x - rad, r.origin.y - rad, rad * 2, rad * 2}}, ops.with_alpha(tint, (1 - t) * RIPPLE_PEAK_OPACITY))
	ops.clip_pop(gtx.scene)
}

// FOCUS_RING_WIDTH and FOCUS_RING_OFFSET are the focus ring's stroke and
// its gap outside the component: hand-set from the m3e-kit's
// foundations.json interaction.focusRing, as the token file has none.
FOCUS_RING_WIDTH :: f32(3)
FOCUS_RING_OFFSET :: f32(2)

// focus_ring is the ring in the active scheme: a secondary stroke.
focus_ring :: proc() -> design.Focus_Ring {
	return {FOCUS_RING_WIDTH, FOCUS_RING_OFFSET, scheme()[.Secondary]}
}

// paint_focus_ring is the focus ring outside rr, following its corners.
paint_focus_ring :: proc(gtx: ^ui.Ctx, c: Control, rr: ops.Round_Rect, inward := false) {
	design.paint_focus_ring(gtx, c.base, rr, focus_ring(), inward)
}

// paint_focus_ring_corners is paint_focus_ring for per-corner radii k.
// inward draws it just inside the shape, for controls packed closer than
// the ring's 5dp reach, as md-focus-ring's inward attribute does
// (@material/web focus/internal/focus-ring.ts).
paint_focus_ring_corners :: proc(gtx: ^ui.Ctx, c: Control, r: ops.Rect, k: Corners, inward := false) {
	design.paint_focus_ring_corners(gtx, c.base, r, k, focus_ring(), inward)
}

// disabled_content and disabled_container are M3's disabled treatment:
// on-surface at a fixed alpha, whatever the component's own colours were.
disabled_content :: proc() -> ops.Color {
	return ops.with_alpha(scheme()[.On_Surface], DISABLED_CONTENT_OPACITY)
}

disabled_container :: proc() -> ops.Color {
	return ops.with_alpha(scheme()[.On_Surface], DISABLED_CONTAINER_OPACITY)
}

// paint_elevation paints an approximate shadow for M3 elevation level 0-5 under
// rr (level 1-5 = 1, 3, 6, 8, 12dp). jm:ui has no blur, so it is a stack
// of offset translucent round rects: soft enough to read as a lift, not the
// spec's two-shadow (key + ambient) composite.
paint_elevation :: proc(gtx: ^ui.Ctx, rr: ops.Round_Rect, level: int) {
	DP := [6]f32{0, 1, 3, 6, 8, 12}
	paint_elevation_dp(gtx, rr, DP[clamp(level, 0, 5)])
}

// Text helpers. Every component shapes in the face for its weight at a
// type role; the shaping and drawing are design's.
Text :: design.Text
draw_text :: design.draw_text
baseline_of :: design.baseline_of

// shape_text shapes s at a type role, into the frame allocator.
shape_text :: proc(gtx: ^ui.Ctx, s: string, role: Type_Role) -> Text {
	return shape_style(gtx, s, TYPE_STYLES[role])
}

// shape_style shapes s at a style, in the face for its weight. A
// comp.*-font token is a style, so it takes one directly.
shape_style :: proc(gtx: ^ui.Ctx, s: string, st: tok.Type_Style) -> Text {
	return design.shape_style(gtx, s, st, font_for(gtx, st.weight))
}

// draw_role_text is shape_text then draw_text of s at role, in one call.
draw_role_text :: proc(gtx: ^ui.Ctx, s: string, pos: ops.Point, role: Type_Role, color: ops.Color) -> Text {
	t := shape_text(gtx, s, role)
	draw_text(gtx, t, pos, color)
	return t
}

// draw_style_text is draw_role_text for a style token.
draw_style_text :: proc(gtx: ^ui.Ctx, s: string, pos: ops.Point, st: tok.Type_Style, color: ops.Color) -> Text {
	t := shape_style(gtx, s, st)
	draw_text(gtx, t, pos, color)
	return t
}

// Geometry and paint helpers that are design's unchanged.
stroke_inside :: design.stroke_inside
stroke_inside_corners :: design.stroke_inside_corners
fade :: design.fade
bezier_ease :: design.bezier_ease

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

// MIN_TOUCH is foundations.json interaction.touchTarget.minDp.
MIN_TOUCH :: f32(48)

// touch_target is r grown to at least MIN_TOUCH on each axis, about its centre.
touch_target :: proc(r: ops.Rect) -> ops.Rect {
	return design.touch_target(r, MIN_TOUCH)
}

// paint_elevation_dp is paint_elevation for an elevation in dp rather
// than a level, so a token's value (and a tween between two) paints
// directly. The shadow is black: the m3e-kit's foundations.json,
// color.missingRoles.
paint_elevation_dp :: proc(gtx: ^ui.Ctx, rr: ops.Round_Rect, dp: f32) {
	design.paint_shadow(gtx, rr, dp, {0, 0, 0, 255})
}

// Mode is the baseline schemes' context: the kit ships a light and a dark
// binding of the same roles.
Mode :: enum u8 {
	Light,
	Dark,
}

// baseline_theme is both baseline schemes as one design.Theme, so
// design.check can measure AXIOMS against them.
baseline_theme :: proc() -> (t: design.Theme(tok.Role, Mode)) {
	t.bind[.Light] = light_scheme()
	t.bind[.Dark] = dark_scheme()
	return
}

// AXIOMS are the guarantees M3's colour system makes of any scheme
// (m3.material.io/styles/color/system/how-the-system-works): every on-X
// role reads on X at WCAG 4.5:1 or better, and outline is visible on
// surface at 3:1. A custom scheme that passes check keeps the pairs
// components lean on most readable.
AXIOMS := []design.Axiom(tok.Role) {
	{.Ratio_Min, .On_Primary, .Primary, 4.5},
	{.Ratio_Min, .On_Secondary, .Secondary, 4.5},
	{.Ratio_Min, .On_Tertiary, .Tertiary, 4.5},
	{.Ratio_Min, .On_Error, .Error, 4.5},
	{.Ratio_Min, .On_Primary_Container, .Primary_Container, 4.5},
	{.Ratio_Min, .On_Secondary_Container, .Secondary_Container, 4.5},
	{.Ratio_Min, .On_Tertiary_Container, .Tertiary_Container, 4.5},
	{.Ratio_Min, .On_Error_Container, .Error_Container, 4.5},
	{.Ratio_Min, .On_Surface, .Surface, 4.5},
	{.Ratio_Min, .On_Surface_Variant, .Surface_Variant, 4.5},
	{.Ratio_Min, .On_Background, .Background, 4.5},
	{.Ratio_Min, .Inverse_On_Surface, .Inverse_Surface, 4.5},
	{.Ratio_Min, .Inverse_Primary, .Inverse_Surface, 4.5},
	{.Ratio_Min, .Primary, .Surface, 4.5},
	{.Ratio_Min, .Error, .Surface, 4.5},
	{.Ratio_Min, .Outline, .Surface, 3},
}
