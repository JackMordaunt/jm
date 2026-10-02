/*
Package primer is GitHub's Primer on jm:ui: the @primer/primitives tokens
(14 colour themes, the type scale, control sizes, radii, borders,
shadows and motion), Octicons, and the Primer React components built from
them, each a plain immediate-mode proc like jm:ui's own widgets.

	primer.use(&scheme, .Dark) // once per frame, or never for light
	if primer.button(gtx, "Save", .Primary) { save(m) }

Every value comes from the primer-kit (tools/primer): tokens from its
primer.resolved.json, generated into package tokens (imported as tok),
icons from @primer/octicons, and behaviour from its foundations.json and
components/<id>.json specs, which cite Primer React's CSS modules and
components at the release the kit's source/VERSIONS records. Where a
component departs from its spec the proc's own comment says so.

What Primer does differently, and what this package is shaped by
(primer-kit foundations.json):

  - A state is a token: --button-default-bgColor-hover, not a layer over
    rest. State_Roles names a property's role per state, as in Fluent;
    some components have their own token tier (button, control, label),
    the rest compose functional tokens (fgColor, bgColor, borderColor).
  - Colour changes are short fades, mostly the 80ms curve Button's CSS
    hard-codes (CONTROL_TRANSITION); a press snaps. There are no springs.
  - Keyboard focus is a 2px outline drawn inside the control's edge
    (paint_focus_outline), shown only for keyboard focus; on an emphasis
    fill a 3px inset ring of onEmphasis sits inside it.
  - Disabled swaps every colour for its disabled token and drops the
    resting shadow; nothing dims.
  - A shadow is a CSS box-shadow list per theme: up to five layers with
    spread and inset, a 1px spread ring often standing in for a border.
  - Fourteen themes bind one vocabulary: light, dark and dark dimmed, each
    with high-contrast, colorblind and tritanopia variants.

Interaction: every interactive component takes state := Interaction.Live.
Live reads real input. Any other value paints that state statically and
ignores input, so a gallery can show a component's states side by side.

What is not Primer's is jm:ui/design's: Interaction and Control, per-state
roles and colour fades, corner geometry, text shaping, focus rings,
shadow layers, easing and the Theme/axiom checker. This package aliases
what it uses unchanged and wraps what needs its own tokens. Its roles map
down to a ui/base theme in use, so base's label, divider and panel sit in
the same theme. The scheme and theme live outside ui.Ctx as thread-locals
set by use, the way the other systems' do.
*/
package primer

import "jm:ui"
import "jm:ui/base"
import "jm:ui/design"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// Scheme is Primer's colour roles, indexed by role: every functional and
// component colour token, and one role per shadow layer.
Scheme :: [tok.Role]ops.Color

// Theme is one of the kit's 14 bindings of the roles, in the order of the
// generated role tables.
Theme :: tok.Mode

THEME_NAMES :: [Theme]string {
	.Light                          = "Light",
	.Dark                           = "Dark",
	.Dark_Dimmed                    = "Dark dimmed",
	.Light_High_Contrast            = "Light high contrast",
	.Dark_High_Contrast             = "Dark high contrast",
	.Dark_Dimmed_High_Contrast      = "Dark dimmed high contrast",
	.Light_Colorblind               = "Light colorblind",
	.Dark_Colorblind                = "Dark colorblind",
	.Light_Colorblind_High_Contrast = "Light colorblind high contrast",
	.Dark_Colorblind_High_Contrast  = "Dark colorblind high contrast",
	.Light_Tritanopia               = "Light tritanopia",
	.Dark_Tritanopia                = "Dark tritanopia",
	.Light_Tritanopia_High_Contrast = "Light tritanopia high contrast",
	.Dark_Tritanopia_High_Contrast  = "Dark tritanopia high contrast",
}

// THEME_COLORS is each theme's colour per role, as the generated tables
// write it, 0xRRGGBBAA.
@(private, rodata)
THEME_COLORS := [Theme][tok.Role]u32 {
	.Light                          = tok.LIGHT,
	.Dark                           = tok.DARK,
	.Dark_Dimmed                    = tok.DARK_DIMMED,
	.Light_High_Contrast            = tok.LIGHT_HIGH_CONTRAST,
	.Dark_High_Contrast             = tok.DARK_HIGH_CONTRAST,
	.Dark_Dimmed_High_Contrast      = tok.DARK_DIMMED_HIGH_CONTRAST,
	.Light_Colorblind               = tok.LIGHT_COLORBLIND,
	.Dark_Colorblind                = tok.DARK_COLORBLIND,
	.Light_Colorblind_High_Contrast = tok.LIGHT_COLORBLIND_HIGH_CONTRAST,
	.Dark_Colorblind_High_Contrast  = tok.DARK_COLORBLIND_HIGH_CONTRAST,
	.Light_Tritanopia               = tok.LIGHT_TRITANOPIA,
	.Dark_Tritanopia                = tok.DARK_TRITANOPIA,
	.Light_Tritanopia_High_Contrast = tok.LIGHT_TRITANOPIA_HIGH_CONTRAST,
	.Dark_Tritanopia_High_Contrast  = tok.DARK_TRITANOPIA_HIGH_CONTRAST,
}

// theme_scheme is theme t's binding from the kit.
theme_scheme :: proc(t: Theme) -> (s: Scheme) {
	for v, r in THEME_COLORS[t] {
		s[r] = ops.rgba(v)
	}
	return
}

// mode_of is the base mode a theme reads as: the dark and dark dimmed
// families are dark.
mode_of :: proc(t: Theme) -> base.Mode {
	#partial switch t {
	case .Light, .Light_High_Contrast, .Light_Colorblind, .Light_Colorblind_High_Contrast, .Light_Tritanopia, .Light_Tritanopia_High_Contrast:
		return .Light
	}
	return .Dark
}

@(private = "file", thread_local)
fallback: Scheme

@(private = "file", thread_local)
active: ^Scheme

@(private = "file", thread_local)
active_theme: Theme

@(private = "file", thread_local)
base_of: base.Theme

// use makes s the scheme every component on this thread reads, t the
// theme whose shadow geometry they cast (a shadow token is per theme:
// tok.SHADOW_RESTING_SMALL's second layer blurs 2px in light, 3px dark),
// and maps s onto a base theme for base's widgets. s must outlive the
// frames that use it. use(nil) goes back to the light theme.
use :: proc(s: ^Scheme, t: Theme = .Light) {
	active = s
	active_theme = t if s != nil else .Light
	base_of = base_theme(scheme(), mode_of(active_theme))
	base.use(&base_of)
}

// scheme is the active scheme, the light theme if use was never called.
scheme :: proc() -> ^Scheme {
	if active == nil {
		if fallback[.Fg_Color_Default] == {} {
			fallback = theme_scheme(.Light)
		}
		return &fallback
	}
	return active
}

// theme is the active theme, light if use was never called.
theme :: proc() -> Theme {
	return active_theme
}

// color is role r in the active scheme.
color :: proc(r: tok.Role) -> ops.Color {
	return scheme()[r]
}

// base_theme maps s onto a base Theme in mode: the page is bgColor
// default and panels bgColor muted (foundations color.pairing), text
// fgColor default and muted, borders borderColor default, with Primer's
// medium radius, thin border, body-medium size and 8px spacing. Primer
// tokens its text selection (--selection-bgColor) under unchanged text;
// unfocused there is no token, so the text's own colour at 16% over the
// page, as fluent does, which base's axioms check reads in every theme.
base_theme :: proc(s: ^Scheme, mode: base.Mode = .Light) -> base.Theme {
	th := base.light()
	th.mode = mode
	th.colors.bind[mode] = {
		.Bg                    = s[.Bg_Color_Default],
		.Surface               = s[.Bg_Color_Muted],
		.Fg                    = s[.Fg_Color_Default],
		.Muted                 = s[.Fg_Color_Muted],
		.Outline               = s[.Border_Color_Default],
		.Selection             = over(s[.Bg_Color_Default], s[.Selection_Bg_Color]),
		.On_Selection          = s[.Fg_Color_Default],
		.Selection_Inactive    = ops.mix(s[.Bg_Color_Default], s[.Fg_Color_Default], 0.16),
		.On_Selection_Inactive = s[.Fg_Color_Default],
	}
	th.text_size = tok.TEXT_BODY_SIZE_MEDIUM
	th.heading_size = tok.TEXT_TITLE_SIZE_MEDIUM
	th.radius = tok.BORDER_RADIUS_MEDIUM
	th.spacing = tok.BASE_SIZE_8
	th.stroke = tok.BORDER_WIDTH_THIN
	return th
}

// over is c composited over an opaque bg: the colour a translucent token
// shows on the page, which contrast is measured on.
@(private)
over :: proc(bg, c: ops.Color) -> ops.Color {
	return ops.mix(bg, {c[0], c[1], c[2], 255}, f32(c[3]) / 255)
}

// Fonts are the faces for the weights Primer sets: normal 400, medium 500
// (control labels) and semibold 600 (titles, selected segments). The kit
// names Mona Sans then the platform's UI face; jm:ui draws in whatever
// the app gives it, the platform sans by default.
Fonts :: struct {
	normal, medium, semibold: ops.Font_Id,
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
	faces = {
		{tok.BASE_TEXT_WEIGHT_NORMAL, f.normal},
		{tok.BASE_TEXT_WEIGHT_MEDIUM, f.medium},
		{tok.BASE_TEXT_WEIGHT_SEMIBOLD, f.semibold},
	}
	loaded = true
}

@(private)
font_faces :: proc() -> []design.Font_Face {
	return faces[:] if loaded else nil
}

// font_for is the face for weight w: the nearest of 400, 500 and 600.
font_for :: proc(gtx: ^ui.Ctx, w: f32) -> ops.Font_Id {
	return design.font_for(font_faces(), w, gtx.font)
}

// Type_Role is one of the type scale's shorthand styles (foundations
// typography.ramp). Inline code is sized relative to the text around it
// (TEXT_CODE_INLINE_SIZE, an Em), so it has no role of its own.
Type_Role :: enum u8 {
	Caption,
	Body_Small,
	Body_Medium,
	Body_Large,
	Subtitle,
	Title_Small,
	Title_Medium,
	Title_Large,
	Display,
	Code_Block,
}

TYPE_STYLES := [Type_Role]tok.Type_Style {
	.Caption      = tok.TEXT_CAPTION_SHORTHAND,
	.Body_Small   = tok.TEXT_BODY_SHORTHAND_SMALL,
	.Body_Medium  = tok.TEXT_BODY_SHORTHAND_MEDIUM,
	.Body_Large   = tok.TEXT_BODY_SHORTHAND_LARGE,
	.Subtitle     = tok.TEXT_SUBTITLE_SHORTHAND,
	.Title_Small  = tok.TEXT_TITLE_SHORTHAND_SMALL,
	.Title_Medium = tok.TEXT_TITLE_SHORTHAND_MEDIUM,
	.Title_Large  = tok.TEXT_TITLE_SHORTHAND_LARGE,
	.Display      = tok.TEXT_DISPLAY_SHORTHAND,
	.Code_Block   = tok.TEXT_CODE_BLOCK_SHORTHAND,
}

// Size is a control's size (foundations layout.controlSizes); medium is
// the default. Button and IconButton offer small, medium and large.
Size :: enum u8 {
	XSmall,
	Small,
	Medium,
	Large,
	XLarge,
}

// CONTROL_HEIGHT is a control's height per size, in px.
CONTROL_HEIGHT :: [Size]f32 {
	.XSmall = tok.CONTROL_XSMALL_SIZE,
	.Small  = tok.CONTROL_SMALL_SIZE,
	.Medium = tok.CONTROL_MEDIUM_SIZE,
	.Large  = tok.CONTROL_LARGE_SIZE,
	.XLarge = tok.CONTROL_XLARGE_SIZE,
}

// Text helpers. A component shapes at a style in the face for its weight
// through design (design.shape_style, layout_style, text_stops) with
// font_for; the drawing is design's too.
Text :: design.Text
draw_text :: design.draw_text
baseline_of :: design.baseline_of
draw_paragraph :: design.draw_paragraph

// style is role's composite style from the scale.
style :: proc(role: Type_Role) -> tok.Type_Style {
	return TYPE_STYLES[role]
}

// shape_text shapes s at a type role, in the face for its weight, into
// the frame allocator.
shape_text :: proc(gtx: ^ui.Ctx, s: string, role: Type_Role) -> Text {
	st := style(role)
	return design.shape_style(gtx, s, st, font_for(gtx, st.weight))
}

// selection_paint is a Text_State's selection in the base theme's
// selection colours, which this system maps in base_theme.
selection_paint :: base.selection_paint
selectable_paragraph :: base.selectable_paragraph
selection_colors :: base.selection_colors

// Interaction and STATES are design's: Live follows real input; the rest
// force one look and take no input.
Interaction :: design.Interaction
STATES :: design.STATES

// Control is design's resolved interaction plus the colours the
// component is fading between, kept in its widget data so a change of
// state transitions rather than snaps (see blend).
Control :: struct {
	using base: design.Control,
	fades:      ^design.Fades, // nil unless Live
}

// control resolves state for the component with id and bounds (see
// design.control) and fetches its colour fades when Live.
control :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, bounds: ops.Rect, state: Interaction) -> (c: Control) {
	c.base = design.control(gtx, id, bounds, state)
	if c.st != nil {
		c.fades = ui.widget_data(gtx, id, design.Fades)
	}
	return
}

// State_Roles is one property's colour in each state: the -rest token
// and its -hover, -active (pressed) and -disabled twins, repeating rest
// where a property has no token for a state.
State_Roles :: design.State_Roles(tok.Role)

// role_for is the role s binds for c's state: disabled, then pressed,
// then hovered; focused reads rest, as focus is an outline.
role_for :: proc(s: State_Roles, c: Control) -> tok.Role {
	return design.role_for(s, c.base)
}

// color_for is role_for's role in the active scheme.
color_for :: proc(s: State_Roles, c: Control) -> ops.Color {
	return color(role_for(s, c))
}

// CONTROL_TRANSITION is the colour fade Button's CSS hard-codes and most
// controls copy: 80ms cubic-bezier(0.65, 0, 0.35, 1) (ButtonBase.module.css
// :20-21, foundations motion.rules); it is not a token.
CONTROL_TRANSITION :: tok.Transition{80, {0.65, 0, 0.35, 1}}

// blend is design.blend over c's fades. A press snaps (ButtonBase.module.css
// :40-42, transition: none on :active), so pressed targets arrive at once.
blend :: proc(gtx: ^ui.Ctx, c: Control, slot: int, target: ops.Color, transition := CONTROL_TRANSITION) -> ops.Color {
	duration := transition.duration
	if c.state == .Pressed {
		duration = 0
	}
	return design.blend(gtx, c.fades, slot, target, duration, transition.easing)
}

CLICK_KINDS :: design.CLICK_KINDS

// listen is design's: it registers id's input area when the control's st
// is live, so a component passes c.st.
listen :: design.listen

// focus_outline is the focus indicator's look: 2px of --focus-outline-color, offset
// -2px so it lies inside the control's border box (focusOutline.css).
// offset may be overridden: a link button's outline sits 2px outside
// (ButtonBase.module.css:601-604).
focus_outline :: proc(offset := tok.FOCUS_OUTLINE_OFFSET) -> design.Focus_Ring {
	return {tok.FOCUS_OUTLINE_WIDTH, offset, color(.Focus_Outline_Color)}
}

// paint_focus_outline is Primer's keyboard focus indicator on rr: shown
// only while c.focus_visible (:focus-visible), never after a click.
paint_focus_outline :: proc(gtx: ^ui.Ctx, c: Control, rr: ops.Round_Rect, offset := tok.FOCUS_OUTLINE_OFFSET) {
	b := c.base
	b.focused = b.focus_visible
	design.paint_focus_ring(gtx, b, rr, focus_outline(offset))
}

// ON_EMPHASIS_RING is the inset ring an emphasis fill's focus adds inside
// the outline (focusOutlineOnEmphasis.css: inset 0 0 0 3px).
ON_EMPHASIS_RING :: f32(3)

// paint_focus_on_emphasis is the focus indicator on an emphasis fill (a
// primary button): an inset 3px --fgColor-onEmphasis ring, then the
// outline over its outer 2px, so a light line shows between the outline
// and the fill (focusOutlineOnEmphasis.css).
paint_focus_on_emphasis :: proc(gtx: ^ui.Ctx, c: Control, rr: ops.Round_Rect) {
	if !c.focus_visible || c.disabled {
		return
	}
	design.paint_inset_shadow(gtx, rr, {spread = ON_EMPHASIS_RING, color = color(.Fg_Color_On_Emphasis)})
	paint_focus_outline(gtx, c, rr)
}

// paint_shadow paints shadow token sh under rr in the active theme. CSS
// paints the first listed layer on top, so layers are painted last first;
// an inset layer is cast inside rr.
paint_shadow :: proc(gtx: ^ui.Ctx, rr: ops.Round_Rect, sh: [Theme]tok.Shadow) {
	s := sh[active_theme]
	for i := s.count - 1; i >= 0; i -= 1 {
		l := s.layers[i]
		layer := design.Box_Shadow{l.x, l.y, l.blur, l.spread, color(l.color)}
		if l.inset {
			design.paint_inset_shadow(gtx, rr, layer)
		} else {
			design.paint_box_shadow(gtx, rr, layer)
		}
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

// radius resolves a radius token for r: --borderRadius-full (9999px)
// means a pill, half the shorter side.
radius :: proc(token: f32, r: ops.Rect) -> f32 {
	return min(token, min(r.w, r.h) / 2)
}

// bindings is every theme as one design.Theme, so design.check can
// measure AXIOMS against all 14. A translucent role is measured as it
// shows on the page, composited over --bgColor-default: Primer's muted
// tints are translucent in the dark and high-contrast themes
// (--bgColor-done-muted is #bf8fff26 in dark tritanopia high contrast),
// and design's contrast ignores alpha.
bindings :: proc() -> (t: design.Theme(tok.Role, Theme)) {
	for th in Theme {
		s := theme_scheme(th)
		page := s[.Bg_Color_Default]
		for &c in s {
			if c[3] < 255 {
				c = over(page, c)
			}
		}
		t.bind[th] = s
	}
	return
}

// AXIOMS are the pairings the kit's foundations say hold in every theme
// (color.pairing, color.rules), as WCAG 2 ratios: default and muted text
// on the page and on muted panels at 4.5:1; onEmphasis text on every
// emphasis fill and a semantic role's text on its muted tint at 4.5:1;
// links at 4.5:1; the focus outline visible on the page at 3:1; button
// labels on their fills at 4.5:1.
AXIOMS := []design.Axiom(tok.Role) {
	{.Ratio_Min, .Fg_Color_Default, .Bg_Color_Default, 4.5},
	{.Ratio_Min, .Fg_Color_Muted, .Bg_Color_Default, 4.5},
	{.Ratio_Min, .Fg_Color_Default, .Bg_Color_Muted, 4.5},
	{.Ratio_Min, .Fg_Color_Default, .Bg_Color_Inset, 4.5},
	{.Ratio_Min, .Fg_Color_Accent, .Bg_Color_Default, 4.5},
	{.Ratio_Min, .Fg_Color_Link, .Bg_Color_Default, 4.5},
	{.Ratio_Min, .Fg_Color_On_Emphasis, .Bg_Color_Accent_Emphasis, 4.5},
	{.Ratio_Min, .Fg_Color_On_Emphasis, .Bg_Color_Success_Emphasis, 4.5},
	{.Ratio_Min, .Fg_Color_On_Emphasis, .Bg_Color_Danger_Emphasis, 4.5},
	{.Ratio_Min, .Fg_Color_On_Emphasis, .Bg_Color_Done_Emphasis, 4.5},
	{.Ratio_Min, .Fg_Color_On_Emphasis, .Bg_Color_Neutral_Emphasis, 4.5},
	{.Ratio_Min, .Fg_Color_Accent, .Bg_Color_Accent_Muted, 4.5},
	{.Ratio_Min, .Fg_Color_Success, .Bg_Color_Success_Muted, 4.5},
	{.Ratio_Min, .Fg_Color_Danger, .Bg_Color_Danger_Muted, 4.5},
	{.Ratio_Min, .Fg_Color_Attention, .Bg_Color_Attention_Muted, 4.5},
	{.Ratio_Min, .Fg_Color_Done, .Bg_Color_Done_Muted, 4.5},
	{.Ratio_Min, .Focus_Outline_Color, .Bg_Color_Default, 3},
	{.Ratio_Min, .Button_Default_Fg_Color_Rest, .Button_Default_Bg_Color_Rest, 4.5},
	{.Ratio_Min, .Button_Primary_Fg_Color_Rest, .Button_Primary_Bg_Color_Rest, 4.5},
	{.Ratio_Min, .Button_Danger_Fg_Color_Rest, .Button_Danger_Bg_Color_Rest, 4.5},
}
