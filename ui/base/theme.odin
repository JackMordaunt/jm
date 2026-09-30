/*
Package base is the smallest design system on jm:ui: a palette, a type
scale and the plain widgets every page needs — label, text, divider and
panel — for anything that is not a full system's component. It is what
ui itself would have as a look, kept out of ui so the toolkit stays
neutral, and it is an instance of ui/design: Theme binds five colour
roles in a light and a dark context, and AXIOMS say what any binding
must satisfy, checked in its tests.

A full system (ui/material) keeps its own scheme and maps it down to a
base Theme (material.base_theme), so a base label inside a material page
sits in material's colours. The active theme is thread-local, set by use,
the way material.use sets its scheme; until use is called the light
theme applies.
*/
package base

import "jm:ui"
import "jm:ui/design"
import "jm:ui/ops"

// Role is a colour's job in the palette.
Role :: enum u8 {
	Bg, // the window
	Surface, // panels
	Fg, // text and marks
	Muted, // secondary text
	Outline, // borders and dividers
	Selection, // selected text's highlight, where the text has focus
	On_Selection, // selected text over it; Fg keeps the text's colour
	Selection_Inactive, // the highlight where the text has lost focus
	On_Selection_Inactive,
}

// Mode is the context a binding is chosen for.
Mode :: enum u8 {
	Light,
	Dark,
}

// Theme is the palette bound in both modes, the mode in use, the font and
// the measures the widgets read. A zero font is the frame's own (gtx.font).
Theme :: struct {
	colors:       design.Theme(Role, Mode),
	mode:         Mode,
	font:         ops.Font_Id,
	text_size:    f32,
	heading_size: f32,
	radius:       f32,
	spacing:      f32, // a panel's default padding
	stroke:       f32, // outline and divider width
}

// AXIOMS are what a valid base palette guarantees in every mode: text
// reads on the window and on panels at 4.5:1 and secondary text at 3:1,
// WCAG 2's AA ratios for normal and large text, and a border is visible
// on a panel at 1.5:1, this palette's own floor for a hairline.
AXIOMS := []design.Axiom(Role) {
	{.Ratio_Min, .Fg, .Bg, 4.5},
	{.Ratio_Min, .Fg, .Surface, 4.5},
	{.Ratio_Min, .Muted, .Bg, 3},
	{.Ratio_Min, .Muted, .Surface, 3},
	{.Ratio_Min, .Outline, .Surface, 1.5},
	// Selected text reads on its highlight, focused or not, and the
	// highlight shows against the window and panels. 1.15 is this palette's
	// floor for a tint that is seen but does not shout.
	{.Ratio_Min, .On_Selection, .Selection, 4.5},
	{.Ratio_Min, .On_Selection_Inactive, .Selection_Inactive, 4.5},
	{.Ratio_Min, .Selection, .Bg, 1.15},
	{.Ratio_Min, .Selection, .Surface, 1.15},
	{.Ratio_Min, .Selection_Inactive, .Bg, 1.15},
	{.Ratio_Min, .Selection_Inactive, .Surface, 1.15},
}

// palette is jm's own binding: a cool grey in both modes.
palette :: proc() -> (t: design.Theme(Role, Mode)) {
	t.bind[.Light] = {
		.Bg      = {246, 246, 248, 255},
		.Surface = {255, 255, 255, 255},
		.Fg      = {28, 28, 32, 255},
		.Muted   = {110, 110, 120, 255},
		.Outline = {200, 200, 208, 255},
		// A light blue under unchanged text.
		.Selection             = {179, 215, 255, 255},
		.On_Selection          = {28, 28, 32, 255},
		.Selection_Inactive    = {214, 214, 222, 255},
		.On_Selection_Inactive = {28, 28, 32, 255},
	}
	t.bind[.Dark] = {
		.Bg      = {24, 24, 28, 255},
		.Surface = {36, 36, 42, 255},
		.Fg      = {232, 232, 238, 255},
		.Muted   = {150, 150, 162, 255},
		.Outline = {70, 70, 82, 255},
		.Selection             = {38, 79, 120, 255},
		.On_Selection          = {232, 232, 238, 255},
		.Selection_Inactive    = {68, 68, 80, 255},
		.On_Selection_Inactive = {232, 232, 238, 255},
	}
	return
}

// light and dark are the palette in one mode with the default scale.
light :: proc(font: ops.Font_Id = 0) -> Theme {
	return {colors = palette(), mode = .Light, font = font, text_size = 14, heading_size = 20, radius = 6, spacing = 8, stroke = 1}
}

dark :: proc(font: ops.Font_Id = 0) -> Theme {
	th := light(font)
	th.mode = .Dark
	return th
}

@(private = "file", thread_local)
fallback: Theme

@(private = "file", thread_local)
active: ^Theme

// use makes th the theme every base widget on this thread reads. th must
// outlive the frames that use it.
use :: proc(th: ^Theme) {
	active = th
}

// theme is the active theme, the light one if use was never called.
theme :: proc() -> ^Theme {
	if active == nil {
		if fallback.text_size == 0 {
			fallback = light()
		}
		return &fallback
	}
	return active
}

// color is role r in the active theme's mode.
color :: proc(r: Role) -> ops.Color {
	th := theme()
	return th.colors.bind[th.mode][r]
}

// font is the active theme's face, or the frame's when it names none.
font :: proc(gtx: ^ui.Ctx) -> ops.Font_Id {
	if f := theme().font; f != 0 {
		return f
	}
	return gtx.font
}

// selection_paint is s's selection in the active theme's selection
// colours, for design.draw_paragraph: the focused pair while the text has
// focus, the inactive pair when it has not.
selection_paint :: proc(s: ^ui.Text_State, focused: bool) -> design.Selection_Paint {
	lo, hi := ui.text_selection(s)
	return selection_colors(lo, hi, focused)
}

// selection_colors is bytes lo to hi in the active theme's selection
// colours, focused or inactive: what ui.selectable_text returns, ready to
// paint.
selection_colors :: proc(lo, hi: int, focused: bool) -> design.Selection_Paint {
	if focused {
		return {lo, hi, color(.Selection), color(.On_Selection)}
	}
	return {lo, hi, color(.Selection_Inactive), color(.On_Selection_Inactive)}
}
