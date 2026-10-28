/*
Package windows is the Windows 11 window chrome on jm:ui: the caption
buttons a frame draws itself when the shell's title bar is Drawn
(ui.Title_Bar_Mode), so the caption can be any height.

	if gtx.title_bar.drawn {
		windows.caption_buttons(gtx, height, dark)
	}

Every number was measured from Windows 11 23H2's own caption buttons at
100% scaling: their slots, fills and colours from screen captures, and
their glyphs fitted to the captured coverage through jm's renderer, to
within 16 of 255 in any channel (windows_test.odin holds the captures).
Other scales round the same geometry to device pixels.
*/
package windows

import "core:math"

import "jm:ui"
import "jm:ui/ops"

// BUTTON_WIDTH is one caption button's slot. Its fill leaves the slot's
// first column bare, as the system's does.
BUTTON_WIDTH :: f32(46)

// GLYPH is the glyphs' box. It sits GLYPH_X into its slot (minimize one
// further) and centred in the button's height.
GLYPH :: f32(10)
GLYPH_X :: f32(18)

// The ink and fills for a light caption and a dark one. A fill is drawn
// over the caption; an inactive window's glyphs are faded until hovered.
INK_LIGHT :: ops.Color{0, 0, 0, 255}
INK_DARK :: ops.Color{255, 255, 255, 255}
INACTIVE_ALPHA :: u8(102)
HOVER_LIGHT :: ops.Color{0, 0, 0, 10}
PRESSED_LIGHT :: ops.Color{0, 0, 0, 6}
HOVER_DARK :: ops.Color{255, 255, 255, 15}
PRESSED_DARK :: ops.Color{255, 255, 255, 11}

// Close is red under the pointer in either theme, its glyph white.
CLOSE_HOVER :: ops.Color{0xC4, 0x2B, 0x1C, 255}
CLOSE_PRESSED :: ops.Color{0xC4, 0x2B, 0x1C, 230}
CLOSE_INK :: ops.Color{255, 255, 255, 255}

// caption_buttons draws minimize, maximize (restore while maximized) and
// close in a row, height tall and 3 × BUTTON_WIDTH wide, for a caption
// that is dark or light. Each is recorded with ui.window_button, so the
// shell hit-tests and performs it; hover, pressed, active and maximized
// come from gtx.title_bar. Place it at the caption's top right, its right
// edge on the window's.
caption_buttons :: proc(gtx: ^ui.Ctx, height: f32, dark: bool, loc := #caller_location) {
	p := ui.widget_open(gtx, loc = loc)
	paint_caption_buttons(gtx, p.id, {}, height, dark)
	ui.widget_close(gtx, &p, {size = {caption_width(gtx), height}})
}

// caption_width is the buttons' width at gtx's density.
caption_width :: proc(gtx: ^ui.Ctx) -> f32 {
	return 3 * snap(BUTTON_WIDTH, gtx.density if gtx.density > 0 else 1)
}

// paint_caption_buttons is caption_buttons drawn at at, in the current
// space, outside layout: for a frame that puts them over its own content
// at the window's corner. id names their tags.
paint_caption_buttons :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, at: ops.Point, height: f32, dark: bool) {
	d := gtx.density if gtx.density > 0 else 1
	slot := snap(BUTTON_WIDTH, d)
	bar := gtx.title_bar
	order := [3]ops.Caption_Button{.Minimize, .Maximize, .Close}
	for b, i in order {
		r := ops.Rect{at.x + f32(i) * slot, at.y, slot, height}
		ui.window_button(gtx, r, b)
		name := button_name(b, bar.maximized)
		ops.tag(gtx.scene, ui.id_mix(id, u64(i + 1)), name, r)

		hovered := bar.hover == b
		pressed := hovered && bar.pressed == b
		ink := INK_DARK if dark else INK_LIGHT
		if !bar.active && !hovered {
			ink.a = INACTIVE_ALPHA
		}
		fill: ops.Color
		if b == .Close && hovered {
			fill = CLOSE_PRESSED if pressed else CLOSE_HOVER
			ink = CLOSE_INK
		} else if pressed {
			fill = PRESSED_DARK if dark else PRESSED_LIGHT
		} else if hovered {
			fill = HOVER_DARK if dark else HOVER_LIGHT
		}
		if fill.a > 0 {
			bare := snap(1, d)
			ops.fill(gtx.scene, ops.Rect{r.x + bare, r.y, slot - bare, height}, fill)
		}

		box := snap(GLYPH, d)
		gx := r.x + snap(GLYPH_X + (1 if b == .Minimize else 0), d)
		gy := r.y + snap((height - GLYPH) / 2, d)
		glyph(gtx, b, bar.maximized, {gx, gy}, box / GLYPH, ink)
	}
}

// button_name is the tag a caption button carries.
@(private)
button_name :: proc(b: ops.Caption_Button, maximized: bool) -> string {
	switch b {
	case .None:
	case .Minimize:
		return "Minimize"
	case .Maximize:
		return "Restore" if maximized else "Maximize"
	case .Close:
		return "Close"
	}
	return ""
}

// snap is v points rounded to whole device pixels at density d.
@(private)
snap :: proc(v, d: f32) -> f32 {
	return math.round(v * d) / d
}

// The glyphs, in GLYPH units from the box's top left. A ring is RING
// thick on its top and left and RING_FAR on its right and bottom, its
// corners RING_RADIUS outside and RING_INNER inside.
@(private)
RING :: f32(1.07)
@(private)
RING_FAR :: f32(1.01)
@(private)
RING_RADIUS :: f32(1.25)
@(private)
RING_INNER :: f32(0.5)
// The close glyph's diagonals are CROSS wide across.
@(private)
CROSS :: f32(0.7)
// The restore glyph's back square shows its top edge from BACK_START and
// its right edge down to BACK_END, round at the corner by BACK_RADIUS
// outside and BACK_INNER inside.
@(private)
BACK_START :: f32(2.4)
@(private)
BACK_END :: f32(7.6)
@(private)
BACK_RADIUS :: f32(2.8)
@(private)
BACK_INNER :: f32(1.75)

// glyph fills button's glyph at at, s points to a GLYPH unit, in ink.
@(private)
glyph :: proc(gtx: ^ui.Ctx, button: ops.Caption_Button, maximized: bool, at: ops.Point, s: f32, ink: ops.Color) {
	pb := Path_Builder {
		verbs  = make([dynamic]ops.Path_Verb, gtx.allocator),
		points = make([dynamic]ops.Point, gtx.allocator),
		at     = at,
		s      = s,
	}
	rule := ops.Fill_Rule.Even_Odd
	switch button {
	case .None:
		return
	case .Minimize:
		ops.fill(gtx.scene, ops.Rect{at.x, at.y + 5 * s, GLYPH * s, s}, ink)
		return
	case .Maximize:
		if maximized {
			ring(&pb, 0, 2, 8)
			corner(&pb)
		} else {
			ring(&pb, 0, 0, GLYPH)
		}
	case .Close:
		cross(&pb)
		rule = .Non_Zero
	}
	path := ops.Path{pb.verbs[:], pb.points[:], rule}
	ops.fill(gtx.scene, ops.Path_Ref{ops.add_path(gtx.scene, path)}, ink)
}

@(private)
Path_Builder :: struct {
	verbs:  [dynamic]ops.Path_Verb,
	points: [dynamic]ops.Point,
	at:     ops.Point,
	s:      f32,
}

@(private)
K :: f32(0.5522847) // a quarter circle's cubic handle, as a fraction of its radius

@(private)
pt :: proc(b: ^Path_Builder, x, y: f32) -> ops.Point {
	return {b.at.x + x * b.s, b.at.y + y * b.s}
}

@(private)
move :: proc(b: ^Path_Builder, x, y: f32) {
	append(&b.verbs, ops.Path_Verb.Move)
	append(&b.points, pt(b, x, y))
}

@(private)
line :: proc(b: ^Path_Builder, x, y: f32) {
	append(&b.verbs, ops.Path_Verb.Line)
	append(&b.points, pt(b, x, y))
}

@(private)
cubic :: proc(b: ^Path_Builder, x1, y1, x2, y2, x, y: f32) {
	append(&b.verbs, ops.Path_Verb.Cubic)
	append(&b.points, pt(b, x1, y1), pt(b, x2, y2), pt(b, x, y))
}

@(private)
close :: proc(b: ^Path_Builder) {
	append(&b.verbs, ops.Path_Verb.Close)
}

// round_rect adds a closed rounded rect of radius radius.
@(private)
round_rect :: proc(b: ^Path_Builder, x, y, w, h, radius: f32) {
	r := min(radius, w / 2, h / 2)
	k := r * (1 - K)
	move(b, x + r, y)
	line(b, x + w - r, y)
	cubic(b, x + w - k, y, x + w, y + k, x + w, y + r)
	line(b, x + w, y + h - r)
	cubic(b, x + w, y + h - k, x + w - k, y + h, x + w - r, y + h)
	line(b, x + r, y + h)
	cubic(b, x + k, y + h, x, y + h - k, x, y + h - r)
	line(b, x, y + r)
	cubic(b, x, y + k, x + k, y, x + r, y)
	close(b)
}

// ring adds a square outline n units wide at x, y, for an even-odd fill.
@(private)
ring :: proc(b: ^Path_Builder, x, y, n: f32) {
	round_rect(b, x, y, n, n, RING_RADIUS)
	in_n := n - RING - RING_FAR
	round_rect(b, x + RING, y + RING, in_n, in_n, RING_INNER)
}

// corner adds the restore glyph's back square: its top edge and its right
// edge, behind the front square's ring.
@(private)
corner :: proc(b: ^Path_Builder) {
	x1 := GLYPH
	k := BACK_RADIUS * (1 - K)
	move(b, BACK_START, 0)
	line(b, x1 - BACK_RADIUS, 0)
	cubic(b, x1 - k, 0, x1, k, x1, BACK_RADIUS)
	line(b, x1, BACK_END)
	xi, yi := x1 - RING_FAR, RING
	ri := BACK_INNER
	ki := ri * (1 - K)
	line(b, xi, BACK_END)
	line(b, xi, yi + ri)
	// The handles as fitted: the inside corner is a little flatter than a
	// quarter circle.
	cubic(b, xi, yi + ki, xi - (ri - ki), yi, xi - ri, yi)
	line(b, BACK_START, yi)
	close(b)
}

// cross adds the close glyph: both diagonals of the box as one outline,
// so the crossing is covered once.
@(private)
cross :: proc(b: ^Path_Builder) {
	a, s := CROSS, GLYPH
	h := s / 2
	move(b, 0, 0)
	line(b, a, 0)
	line(b, h, h - a)
	line(b, s - a, 0)
	line(b, s, 0)
	line(b, s, a)
	line(b, h + a, h)
	line(b, s, s - a)
	line(b, s, s)
	line(b, s - a, s)
	line(b, h, h + a)
	line(b, a, s)
	line(b, 0, s)
	line(b, 0, s - a)
	line(b, h - a, h)
	line(b, 0, a)
	close(b)
}
