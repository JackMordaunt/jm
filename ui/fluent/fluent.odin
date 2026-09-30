/*
Package fluent is Fluent 2 on jm:ui: the Fluent UI React v9 tokens (five
colour themes, the type ramp, spacing, radii, strokes, shadows and
motion) and the components built from them, each a plain immediate-mode
proc like jm:ui's own widgets.

	fluent.use(&scheme) // once per frame, or never for the web light theme
	if fluent.button(gtx, "Save", .Primary) { save(m) }

Every value comes from the Fluent kit (tools/fluent):
tokens from its fluent.resolved.json, generated into package tokens
(imported as tok), and behaviour from its foundations.json and
components/<id>.json specs, which cite Fluent UI React's styles files at
the commit the kit's source/COMMIT records. Where a component departs
from its spec the proc's own comment says so.

What Fluent does differently from Material, and what this package is
shaped by (fluent-kit foundations.json):

  - There are no component tokens. A component's sizes are the numbers
    its styles file hard-codes; they live in the component's own proc.
  - A state is a token, not a layer: hover reads Neutral_Background1_Hover,
    pressed Neutral_Background1_Pressed. State_Roles names a property's
    role per state and color_for picks one from design.Control's state.
  - Colour changes ease over DURATION_FASTER with CURVE_EASY_EASE; blend
    keeps a component's colours between frames to do that. There are no
    springs.
  - Keyboard focus is an outline outside the component (paint_focus_
    outline), except buttons, which draw it inside (paint_focus_inset).
  - Disabled swaps every colour for its Disabled token; nothing dims.
  - A shadow token is two layers, ambient then key, in colour roles.
  - High contrast is a theme like any other: the same roles, bound to the
    Windows system colours the kit's foundations list (highContrast).

Interaction: every interactive component takes state := Interaction.Live.
Live reads real input. Any other value paints that state statically and
ignores input, so a gallery can show a component's states side by side.

What is not Fluent's is jm:ui/design's: Interaction and Control, corner
geometry, text shaping, focus rings, shadow layers, easing and the
Theme/axiom checker. This package aliases what it uses unchanged and
wraps what needs its own tokens. Neutral roles map down to a ui/base
theme in use, so base's label, divider and panel sit in the same theme.

The scheme lives outside ui.Ctx as a thread-local set by use, the way
material's does.
*/
package fluent

import "jm:ui"
import "jm:ui/base"
import "jm:ui/design"
import tok "jm:ui/fluent/tokens"
import "jm:ui/ops"

// Scheme is Fluent's colour roles (the tokens.color* aliases), indexed
// by role.
Scheme :: [tok.Role]ops.Color

// Theme is one of the kit's five bindings of the roles.
Theme :: enum u8 {
	Web_Light,
	Web_Dark,
	High_Contrast,
	Teams_Light,
	Teams_Dark,
}

THEME_NAMES :: [Theme]string {
	.Web_Light     = "Web light",
	.Web_Dark      = "Web dark",
	.High_Contrast = "High contrast",
	.Teams_Light   = "Teams light",
	.Teams_Dark    = "Teams dark",
}

// hex is 0xRRGGBBAA as a Color.
hex :: proc(v: u32) -> ops.Color {
	return {u8(v >> 24), u8(v >> 16), u8(v >> 8), u8(v)}
}

// theme_scheme is theme t's binding from the kit.
theme_scheme :: proc(t: Theme) -> (s: Scheme) {
	table: [tok.Role]u32
	switch t {
	case .Web_Light:
		table = tok.WEB_LIGHT
	case .Web_Dark:
		table = tok.WEB_DARK
	case .High_Contrast:
		table = tok.HIGH_CONTRAST
	case .Teams_Light:
		table = tok.TEAMS_LIGHT
	case .Teams_Dark:
		table = tok.TEAMS_DARK
	}
	for v, r in table {
		s[r] = hex(v)
	}
	return
}

// mode_of is the base mode a theme reads as: the dark themes and high
// contrast (black canvas) are dark.
mode_of :: proc(t: Theme) -> base.Mode {
	return t == .Web_Light || t == .Teams_Light ? .Light : .Dark
}

@(private = "file", thread_local)
fallback: Scheme

@(private = "file", thread_local)
active: ^Scheme

@(private = "file", thread_local)
base_of: base.Theme

// use makes s the scheme every component on this thread reads, and maps
// it onto the base theme in mode for base's widgets. s must outlive the
// frames that use it.
use :: proc(s: ^Scheme, mode: base.Mode = .Light) {
	active = s
	base_of = base_theme(s, mode)
	base.use(&base_of)
}

// scheme is the active scheme, the web light theme if use was never called.
scheme :: proc() -> ^Scheme {
	if active == nil {
		if fallback[.Neutral_Background1] == {} {
			fallback = theme_scheme(.Web_Light)
		}
		return &fallback
	}
	return active
}

// color is role r in the active scheme.
color :: proc(r: tok.Role) -> ops.Color {
	return scheme()[r]
}

// base_theme maps s onto a base Theme in mode: the page is Background 2
// and panels Background 1 (foundations color.levels), text Foreground 1
// and 2, borders Stroke 1, with Fluent's medium radius, thin stroke,
// body size and M spacing.
base_theme :: proc(s: ^Scheme, mode: base.Mode = .Light) -> base.Theme {
	th := base.light()
	th.mode = mode
	th.colors.bind[mode] = {
		.Bg      = s[.Neutral_Background2],
		.Surface = s[.Neutral_Background1],
		.Fg      = s[.Neutral_Foreground1],
		.Muted   = s[.Neutral_Foreground2],
		.Outline = s[.Neutral_Stroke1],
		// The fluent-kit tokens no text selection (ui/fluent/tokens has no
		// selection role). Our choice, after Windows' accent highlight: the
		// brand background with its on-brand foreground. Unfocused, the
		// text's own colour at 16% over the canvas: a grey in every theme.
		.Selection             = s[.Brand_Background],
		.On_Selection          = s[.Neutral_Foreground_On_Brand],
		.Selection_Inactive    = ops.mix(s[.Neutral_Background2], s[.Neutral_Foreground1], 0.16),
		.On_Selection_Inactive = s[.Neutral_Foreground1],
	}
	th.text_size = tok.FONT_SIZE_BASE300
	th.heading_size = tok.FONT_SIZE_BASE500
	th.radius = tok.BORDER_RADIUS_MEDIUM
	th.spacing = tok.SPACING_HORIZONTAL_M
	th.stroke = tok.STROKE_WIDTH_THIN
	return th
}

// Fonts are the faces for the weights the type ramp uses: regular 400,
// semibold 600 and bold 700 (foundations typography.weights, which
// calls medium rarely read). Segoe UI is proprietary; Selawik is the stand-in the
// kit's foundations name (typography.standIn, which records its licence
// and its metric match to Segoe).
Fonts :: struct {
	regular, semibold, bold: ops.Font_Id,
}

// faces is the active Fonts as design's weight-to-face table; until
// use_fonts is called it is empty and every weight draws in the frame's
// font.
@(private, thread_local)
faces: [3]design.Font_Face

@(private, thread_local)
loaded: bool

// use_fonts sets the faces text is drawn in on this thread.
use_fonts :: proc(f: Fonts) {
	faces = {{tok.FONT_WEIGHT_REGULAR, f.regular}, {tok.FONT_WEIGHT_SEMIBOLD, f.semibold}, {tok.FONT_WEIGHT_BOLD, f.bold}}
	loaded = true
}

@(private)
font_faces :: proc() -> []design.Font_Face {
	return faces[:] if loaded else nil
}

// font_for is the face for weight w: the nearest of 400, 600 and 700.
font_for :: proc(gtx: ^ui.Ctx, w: f32) -> ops.Font_Id {
	return design.font_for(font_faces(), w, gtx.font)
}

// Type_Role is one of the ramp's 17 named styles (typographyStyles).
Type_Role :: enum u8 {
	Caption2,
	Caption2_Strong,
	Caption1,
	Caption1_Strong,
	Caption1_Stronger,
	Body1,
	Body1_Strong,
	Body1_Stronger,
	Body2,
	Subtitle2,
	Subtitle2_Stronger,
	Subtitle1,
	Title3,
	Title2,
	Title1,
	Large_Title,
	Display,
}

TYPE_STYLES := [Type_Role]tok.Type_Style {
	.Caption2           = tok.TYPOGRAPHY_STYLES_CAPTION2,
	.Caption2_Strong    = tok.TYPOGRAPHY_STYLES_CAPTION2_STRONG,
	.Caption1           = tok.TYPOGRAPHY_STYLES_CAPTION1,
	.Caption1_Strong    = tok.TYPOGRAPHY_STYLES_CAPTION1_STRONG,
	.Caption1_Stronger  = tok.TYPOGRAPHY_STYLES_CAPTION1_STRONGER,
	.Body1              = tok.TYPOGRAPHY_STYLES_BODY1,
	.Body1_Strong       = tok.TYPOGRAPHY_STYLES_BODY1_STRONG,
	.Body1_Stronger     = tok.TYPOGRAPHY_STYLES_BODY1_STRONGER,
	.Body2              = tok.TYPOGRAPHY_STYLES_BODY2,
	.Subtitle2          = tok.TYPOGRAPHY_STYLES_SUBTITLE2,
	.Subtitle2_Stronger = tok.TYPOGRAPHY_STYLES_SUBTITLE2_STRONGER,
	.Subtitle1          = tok.TYPOGRAPHY_STYLES_SUBTITLE1,
	.Title3             = tok.TYPOGRAPHY_STYLES_TITLE3,
	.Title2             = tok.TYPOGRAPHY_STYLES_TITLE2,
	.Title1             = tok.TYPOGRAPHY_STYLES_TITLE1,
	.Large_Title        = tok.TYPOGRAPHY_STYLES_LARGE_TITLE,
	.Display            = tok.TYPOGRAPHY_STYLES_DISPLAY,
}

// Size is the density every control comes in (foundations
// layout.controlHeights); medium is the default.
Size :: enum u8 {
	Small,
	Medium,
	Large,
}

// CONTROL_HEIGHT is a control's height per size, in px.
CONTROL_HEIGHT :: [Size]f32{.Small = 24, .Medium = 32, .Large = 40}

// control_style is the text style a control sets directly rather than
// through a named style (foundations typography.ramp.controlLabel): the
// size's base font size and line height at weight.
control_style :: proc(size: Size, weight: f32) -> tok.Type_Style {
	switch size {
	case .Small:
		return {weight = weight, size = tok.FONT_SIZE_BASE200, line_height = tok.LINE_HEIGHT_BASE200}
	case .Medium:
		return {weight = weight, size = tok.FONT_SIZE_BASE300, line_height = tok.LINE_HEIGHT_BASE300}
	case .Large:
		return {weight = weight, size = tok.FONT_SIZE_BASE400, line_height = tok.LINE_HEIGHT_BASE400}
	}
	return {}
}

// Text helpers. Every component shapes in the face for its weight at a
// style; the shaping and drawing are design's.
Text :: design.Text
draw_text :: design.draw_text
baseline_of :: design.baseline_of

// style is role's composite style from the ramp.
style :: proc(role: Type_Role) -> tok.Type_Style {
	return TYPE_STYLES[role]
}

// shape_text shapes s at a type role, into the frame allocator.
shape_text :: proc(gtx: ^ui.Ctx, s: string, role: Type_Role) -> Text {
	return shape_style(gtx, s, style(role))
}

// shape_style shapes s at a style, in the face nearest its weight.
shape_style :: proc(gtx: ^ui.Ctx, s: string, st: tok.Type_Style) -> Text {
	return design.shape_style(gtx, s, st, design.font_for(font_faces(), st.weight, gtx.font))
}

draw_paragraph :: design.draw_paragraph

// selection_paint is a Text_State's selection in the base theme's
// selection colours, which this system maps in base_theme.
selection_paint :: base.selection_paint
selection_colors :: base.selection_colors

// layout_style lays s out at a style in the face nearest its weight,
// wrapped at width when width > 0; see design.layout_style.
layout_style :: proc(gtx: ^ui.Ctx, s: string, st: tok.Type_Style, width: f32 = 0) -> ui.Paragraph {
	return design.layout_style(gtx, s, st, design.font_for(font_faces(), st.weight, gtx.font), width)
}

// text_stops is s's caret and word stops at a style, for ui.text_edit.
text_stops :: proc(gtx: ^ui.Ctx, s: ^ui.Text_State, st: tok.Type_Style) -> ui.Text_Stops {
	return ui.text_stops(gtx, s, design.font_for(font_faces(), st.weight, gtx.font), st.size)
}

// Interaction and STATES are design's: Live follows real input; the rest
// force one look and take no input.
Interaction :: design.Interaction
STATES :: design.STATES

// Control is design's resolved interaction plus Fluent's reading of it:
// the colours the component is easing between, kept in its widget data
// so a change of state transitions rather than snaps (see blend).
Control :: struct {
	using base: design.Control,
	fades:      ^Fades, // nil unless Live
}

// control resolves state for the component with id and bounds (see
// design.control) and fetches its colour transitions when Live.
control :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, bounds: ops.Rect, state: Interaction) -> (c: Control) {
	c.base = design.control(gtx, id, bounds, state)
	if c.st != nil {
		c.fades = ui.widget_data(gtx, id, Fades)
	}
	return
}

// State_Roles is one property's colour in each state it can be painted
// in: the rest token and its Hover, Pressed and Disabled twins
// (foundations tokens.rules: states are separate tokens, never blends).
// A property with no token for a state repeats its rest role there.
State_Roles :: struct {
	rest, hover, pressed, disabled: tok.Role,
}

// role_for is the role s binds for c's state: disabled, then pressed,
// then hovered (foundations interaction.states.priority); focused and
// enabled read the rest role, as the only focus colour tokens are the
// ring's own, Stroke_Focus1 and 2 (foundations interaction.focus).
role_for :: proc(s: State_Roles, c: Control) -> tok.Role {
	#partial switch c.state {
	case .Disabled:
		return s.disabled
	case .Pressed, .Dragged:
		return s.pressed
	case .Hovered:
		return s.hover
	}
	return s.rest
}

// color_for is role_for's role in the active scheme.
color_for :: proc(s: State_Roles, c: Control) -> ops.Color {
	return color(role_for(s, c))
}

// Fades are a component's colour transitions: one per property it
// eases, numbered by the component like design's spring slots.
Fades :: struct {
	slots: [4]Fade,
}

Fade :: struct {
	from, to: ops.Color,
	tween:    ui.Tween,
	live:     bool, // a value has been seen; until then there is nothing to ease from
}

// blend is target eased from the colour slot last showed: a change of
// target starts a transition of duration ms along curve, the defaults
// being every control's colour transition (foundations motion.rules).
// A forced state (c.fades nil) has no retained colour, so it is target
// at once, as is the first frame of a live one.
blend :: proc(gtx: ^ui.Ctx, c: Control, slot: int, target: ops.Color, duration := tok.DURATION_FASTER, curve := tok.CURVE_EASY_EASE) -> ops.Color {
	if c.fades == nil {
		return target
	}
	f := &c.fades.slots[slot]
	if !f.live {
		f^ = {from = target, to = target, live = true}
		return target
	}
	if target != f.to {
		f.from = fade_value(f, curve)
		f.to = target
		f.tween = {to = 1, duration = duration / 1000}
	}
	ui.tween_update(&f.tween, gtx)
	return fade_value(f, curve)
}

@(private = "file")
fade_value :: proc(f: ^Fade, curve: tok.Bezier) -> ops.Color {
	if f.tween.duration <= 0 {
		return f.to
	}
	return ops.mix(f.from, f.to, design.bezier_ease(curve, f.tween.t / f.tween.duration))
}

CLICK_KINDS :: design.CLICK_KINDS

// listen is design's: it registers id's input area when the control's
// st is live, so a component passes c.st.
listen :: design.listen

// FOCUS_OUTLINE_WIDTH is the default indicator's stroke (foundations
// interaction.focus.outline.widthPx, createFocusOutlineStyle.ts); the
// outline sits just outside the component, its outer edge that far out.
FOCUS_OUTLINE_WIDTH :: f32(2)

// focus_outline is the default indicator in the active scheme.
focus_outline :: proc() -> design.Focus_Ring {
	return {FOCUS_OUTLINE_WIDTH, 0, color(.Stroke_Focus2)}
}

// paint_focus_outline is the default keyboard focus indicator: a 2px
// Stroke_Focus2 outline just outside rr, following its corners.
paint_focus_outline :: proc(gtx: ^ui.Ctx, c: Control, rr: ops.Round_Rect) {
	design.paint_focus_ring(gtx, c.base, rr, focus_outline())
}

// paint_focus_outline_corners is paint_focus_outline for per-corner radii.
paint_focus_outline_corners :: proc(gtx: ^ui.Ctx, c: Control, r: ops.Rect, k: Corners) {
	design.paint_focus_ring_corners(gtx, c.base, r, k, focus_outline())
}

// paint_focus_inset is a button's focus indicator, drawn inside its box
// (foundations interaction.focus.inset, useButtonStyles.styles.ts): the
// border, border px wide, turns Stroke_Focus2 and a 1px ring of the
// same colour sits just inside it, so packed buttons never overlap
// rings. A caller that has already painted its border in the focus
// colour passes paint_border = false and gets only the ring. inner,
// when non-zero, is a further ring of inner_color inside that (the
// primary button's on-brand ring, strokeWidthThick wide).
paint_focus_inset :: proc(gtx: ^ui.Ctx, c: Control, r: ops.Rect, k: Corners, border: f32 = tok.STROKE_WIDTH_THIN, paint_border := true, inner: f32 = 0, inner_color := ops.Color{}) {
	if !c.focused || c.disabled {
		return
	}
	fc := color(.Stroke_Focus2)
	if paint_border {
		design.stroke_inside_corners(gtx, r, k, fc, border)
	}
	design.stroke_inside_corners(gtx, shrink(r, border), design.grow_corners(k, -border), fc, tok.STROKE_WIDTH_THIN)
	if inner > 0 {
		w := border + tok.STROKE_WIDTH_THIN
		design.stroke_inside_corners(gtx, shrink(r, w), design.grow_corners(k, -w), inner_color, inner)
	}
}

// shrink is r inset by d on every side.
shrink :: proc(r: ops.Rect, d: f32) -> ops.Rect {
	return {r.x + d, r.y + d, r.w - 2 * d, r.h - 2 * d}
}

// paint_shadow paints shadow token sh under rr: its ambient layer then
// its key layer, each in its role's colour from the active scheme.
paint_shadow :: proc(gtx: ^ui.Ctx, rr: ops.Round_Rect, sh: tok.Shadow) {
	for l in sh.layers {
		design.paint_shadow_layer(gtx, rr, l.x, l.y, l.blur, color(l.color))
	}
}

// Geometry and paint helpers that are design's unchanged.
Corners :: design.Corners
corners_all :: design.corners_all
rounded :: design.rounded
stroke_inside :: design.stroke_inside
stroke_inside_corners :: design.stroke_inside_corners
fade :: design.fade
bezier_ease :: design.bezier_ease

// radius resolves a radius token for r: BORDER_RADIUS_CIRCULAR (10000px)
// means a pill, half the shorter side.
radius :: proc(token: f32, r: ops.Rect) -> f32 {
	return min(token, min(r.w, r.h) / 2)
}

// bindings is every theme as one design.Theme, so design.check can
// measure AXIOMS against all five.
bindings :: proc() -> (t: design.Theme(tok.Role, Theme)) {
	for th in Theme {
		t.bind[th] = theme_scheme(th)
	}
	return
}

// AXIOMS are the pairings the kit's foundations say hold in every theme
// (color.pairing, color.strokes, interaction.focus), as WCAG 2 ratios:
// a foreground reads on the background of its family and level at 4.5:1,
// secondary and tertiary text still at 4.5:1 on Background 1, brand text
// and links on Background 1 at 4.5:1, and the accessible stroke and the
// focus stroke are visible on Background 1 at 3:1. Stroke 1, a resting
// border, is only ever a hairline: 1.5:1, base's floor.
AXIOMS := []design.Axiom(tok.Role) {
	{.Ratio_Min, .Neutral_Foreground1, .Neutral_Background1, 4.5},
	{.Ratio_Min, .Neutral_Foreground2, .Neutral_Background1, 4.5},
	{.Ratio_Min, .Neutral_Foreground3, .Neutral_Background1, 4.5},
	{.Ratio_Min, .Neutral_Foreground4, .Neutral_Background1, 4.5},
	{.Ratio_Min, .Neutral_Foreground1, .Neutral_Background2, 4.5},
	{.Ratio_Min, .Neutral_Foreground1, .Neutral_Background3, 4.5},
	{.Ratio_Min, .Neutral_Foreground2, .Neutral_Background2, 4.5},
	{.Ratio_Min, .Neutral_Foreground1_Hover, .Neutral_Background1_Hover, 4.5},
	{.Ratio_Min, .Neutral_Foreground1_Pressed, .Neutral_Background1_Pressed, 4.5},
	{.Ratio_Min, .Neutral_Foreground_On_Brand, .Brand_Background, 4.5},
	{.Ratio_Min, .Neutral_Foreground_On_Brand, .Brand_Background_Hover, 4.5},
	{.Ratio_Min, .Neutral_Foreground_On_Brand, .Brand_Background_Pressed, 4.5},
	{.Ratio_Min, .Brand_Foreground1, .Neutral_Background1, 4.5},
	{.Ratio_Min, .Brand_Foreground_Link, .Neutral_Background1, 4.5},
	{.Ratio_Min, .Status_Danger_Foreground1, .Status_Danger_Background1, 4.5},
	{.Ratio_Min, .Status_Success_Foreground1, .Status_Success_Background1, 4.5},
	{.Ratio_Min, .Status_Warning_Foreground1, .Status_Warning_Background1, 4.5},
	{.Ratio_Min, .Neutral_Stroke_Accessible, .Neutral_Background1, 3},
	{.Ratio_Min, .Stroke_Focus2, .Neutral_Background1, 3},
	{.Ratio_Min, .Neutral_Stroke1, .Neutral_Background1, 1.5},
}
