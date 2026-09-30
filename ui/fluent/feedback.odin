package fluent

import "core:math"
import "core:strconv"
import "core:strings"
import "jm:ui"
import "jm:ui/design"
import tok "jm:ui/fluent/tokens"
import "jm:ui/ops"

// Feedback: badge, counter and presence badges, avatar, progress bar and
// spinner (fluent-kit components/badge.json, avatar.json,
// progress-bar.json, spinner.json, and the styles files they cite at the
// kit's commit). None of these takes input or focus; each paints from
// its tokens and the constants its styles file hard-codes, cited as
// use<Name>Styles.styles.ts:lines where they are used.

// Badge.

// Badge_Appearance is how a badge carries its colour.
Badge_Appearance :: enum u8 {
	Filled, // solid colour, contrasting text
	Ghost, // coloured text, no fill or border
	Outline, // coloured text and border, no fill
	Tint, // pale fill, darker text, matching border
}

// Badge_Color is the semantic colour; a counter badge offers the first four.
Badge_Color :: enum u8 {
	Brand,
	Danger,
	Important,
	Informative,
	Severe,
	Subtle,
	Success,
	Warning,
}

// Badge_Size is the height: 6, 10, 16, 20, 24 or 32px. Tiny and
// Extra_Small are dots too small for text.
Badge_Size :: enum u8 {
	Tiny,
	Extra_Small,
	Small,
	Medium,
	Large,
	Extra_Large,
}

// Badge_Shape is the corner treatment: a pill or circle, the size's
// radius, or none.
Badge_Shape :: enum u8 {
	Circular,
	Rounded,
	Square,
}

// BADGE_HEIGHT is each size's height and minimum width
// (useBadgeStyles.styles.ts:47-86).
BADGE_HEIGHT := [Badge_Size]f32{.Tiny = 6, .Extra_Small = 10, .Small = 16, .Medium = 20, .Large = 24, .Extra_Large = 32}

// Badge_Metrics are one size's dimensions: side padding (the size's
// token plus the spacingHorizontalXXS text allowance), the icon glyph,
// the icon-to-text gap, the rounded radius and the text style
// (useBadgeStyles.styles.ts:14-95,255-343).
@(private)
Badge_Metrics :: struct {
	height, pad, icon, gap, radius: f32,
	style:                          tok.Type_Style,
}

@(private)
badge_metrics :: proc(size: Badge_Size) -> Badge_Metrics {
	allowance := tok.SPACING_HORIZONTAL_XXS
	switch size {
	case .Tiny:
		// A 6px dot: font 4px, no padding (styles.ts:306-313).
		return {height = 6, icon = 6, radius = tok.BORDER_RADIUS_SMALL, style = {weight = tok.FONT_WEIGHT_SEMIBOLD, size = 4, line_height = 6}}
	case .Extra_Small:
		return {height = 10, icon = 10, radius = tok.BORDER_RADIUS_SMALL, style = {weight = tok.FONT_WEIGHT_SEMIBOLD, size = 6, line_height = 10}}
	case .Small:
		return {height = 16, pad = tok.SPACING_HORIZONTAL_XXS + allowance, icon = 12, gap = tok.SPACING_HORIZONTAL_XXS + allowance, radius = tok.BORDER_RADIUS_SMALL, style = tok.TYPOGRAPHY_STYLES_CAPTION2_STRONG}
	case .Medium:
	case .Large:
		return {height = 24, pad = tok.SPACING_HORIZONTAL_XS + allowance, icon = 16, gap = tok.SPACING_HORIZONTAL_XXS + allowance, radius = tok.BORDER_RADIUS_MEDIUM, style = tok.TYPOGRAPHY_STYLES_CAPTION1_STRONG}
	case .Extra_Large:
		return {height = 32, pad = tok.SPACING_HORIZONTAL_SNUDGE + allowance, icon = 20, gap = tok.SPACING_HORIZONTAL_XS + allowance, radius = tok.BORDER_RADIUS_MEDIUM, style = tok.TYPOGRAPHY_STYLES_CAPTION1_STRONG}
	}
	return {height = 20, pad = tok.SPACING_HORIZONTAL_XS + allowance, icon = 12, gap = tok.SPACING_HORIZONTAL_XXS + allowance, radius = tok.BORDER_RADIUS_MEDIUM, style = tok.TYPOGRAPHY_STYLES_CAPTION1_STRONG}
}

// Badge_Roles are one appearance and colour's fill, text and border
// roles; a role of Transparent_Background or Transparent_Stroke paints
// nothing (the root's border colour stays Transparent_Stroke so forced
// colours can still outline it).
Badge_Roles :: struct {
	bg, fg, border: tok.Role,
}

// badge_roles is the appearance-colour table of useBadgeStyles.styles.ts:
// 106-253, copied token for token: several colours read a token from
// another role (filled important fills with Neutral_Foreground1), and
// ghost and outline subtle write Neutral_Foreground_Static_Inverted,
// white in every theme, for dark surfaces.
badge_roles :: proc(a: Badge_Appearance, c: Badge_Color) -> (r: Badge_Roles) {
	r = {.Transparent_Background, .Neutral_Foreground1, .Transparent_Stroke}
	switch a {
	case .Filled:
		switch c {
		case .Brand:
			r.bg, r.fg = .Brand_Background, .Neutral_Foreground_On_Brand
		case .Danger:
			r.bg, r.fg = .Palette_Red_Background3, .Neutral_Foreground_On_Brand
		case .Important:
			r.bg, r.fg = .Neutral_Foreground1, .Neutral_Background1
		case .Informative:
			r.bg, r.fg = .Neutral_Background5, .Neutral_Foreground3
		case .Severe:
			r.bg, r.fg = .Palette_Dark_Orange_Background3, .Neutral_Foreground_On_Brand
		case .Subtle:
			r.bg, r.fg = .Neutral_Background1, .Neutral_Foreground1
		case .Success:
			r.bg, r.fg = .Palette_Green_Background3, .Neutral_Foreground_On_Brand
		case .Warning:
			r.bg, r.fg = .Palette_Yellow_Background3, .Neutral_Foreground1_Static
		}
	case .Ghost, .Outline:
		switch c {
		case .Brand:
			r.fg = .Brand_Foreground1
		case .Danger:
			r.fg = .Palette_Red_Foreground3
		case .Important:
			r.fg = a == .Outline ? .Neutral_Foreground3 : .Neutral_Foreground1
		case .Informative:
			r.fg = .Neutral_Foreground3
		case .Severe:
			r.fg = .Palette_Dark_Orange_Foreground3
		case .Subtle:
			r.fg = .Neutral_Foreground_Static_Inverted
		case .Success:
			r.fg = .Palette_Green_Foreground3
		case .Warning:
			r.fg = .Palette_Yellow_Foreground2
		}
		if a == .Outline {
			// The border is the text colour (currentColor) unless the
			// colour names its own.
			r.border = r.fg
			#partial switch c {
			case .Danger:
				r.border = .Palette_Red_Border2
			case .Important:
				r.border = .Neutral_Stroke_Accessible
			case .Informative:
				r.border = .Neutral_Stroke2
			case .Success:
				r.border = .Palette_Green_Border2
			}
		}
	case .Tint:
		switch c {
		case .Brand:
			r = {.Brand_Background2, .Brand_Foreground2, .Brand_Stroke2}
		case .Danger:
			r = {.Palette_Red_Background1, .Palette_Red_Foreground1, .Palette_Red_Border1}
		case .Important:
			r = {.Neutral_Foreground3, .Neutral_Background1, .Transparent_Stroke}
		case .Informative:
			r = {.Neutral_Background4, .Neutral_Foreground3, .Neutral_Stroke2}
		case .Severe:
			r = {.Palette_Dark_Orange_Background1, .Palette_Dark_Orange_Foreground1, .Palette_Dark_Orange_Border1}
		case .Subtle:
			r = {.Neutral_Background1, .Neutral_Foreground3, .Neutral_Stroke2}
		case .Success:
			r = {.Palette_Green_Background1, .Palette_Green_Foreground1, .Palette_Green_Border1}
		case .Warning:
			r = {.Palette_Yellow_Background1, .Palette_Yellow_Foreground1, .Palette_Yellow_Border1}
		}
	}
	return
}

// badge_radius is shape's radius for a badge of size in area
// (useBadgeStyles.styles.ts:88-95,314-315).
@(private)
badge_radius :: proc(shape: Badge_Shape, mt: Badge_Metrics, area: ops.Rect) -> f32 {
	switch shape {
	case .Circular:
		return radius(tok.BORDER_RADIUS_CIRCULAR, area)
	case .Rounded:
		return mt.radius
	case .Square:
	}
	return tok.BORDER_RADIUS_NONE
}

// badge is a small non-interactive label with a colour meaning: text, an
// icon, or both, centred in a box of the size's height and at least as
// wide (useBadgeStyles.styles.ts:14-44). The border is strokeWidthThin,
// drawn inside so it adds no size. Tiny and extra-small draw a dot and
// no text. It records a Tag with the text so a probe can find it, and
// returns its Dims. No state: a badge has no hover, press, focus or
// disabled look.
badge :: proc(
	gtx: ^ui.Ctx,
	text: string,
	color := Badge_Color.Brand,
	appearance := Badge_Appearance.Filled,
	size := Badge_Size.Medium,
	shape := Badge_Shape.Circular,
	ic := Icon.None,
	icon_position := Icon_Position.Before,
	key: u64 = 0,
	loc := #caller_location,
) -> ui.Dims {
	p := ui.widget_open(gtx, key, loc)
	mt := badge_metrics(size)
	dot := size == .Tiny || size == .Extra_Small
	has_text := text != "" && !dot
	has_icon := ic != .None
	t: Text
	if has_text {
		t = shape_style(gtx, text, mt.style)
	}
	content := has_text ? t.width : 0
	if has_icon {
		content += mt.icon + (has_text ? mt.gap : 0)
	}
	// An icon beside no text cancels the text allowance (styles.ts:255-263).
	pad := mt.pad
	if has_icon && !has_text {
		pad = max(pad - tok.SPACING_HORIZONTAL_XXS, 0)
	}
	w := dot ? mt.height : max(pad * 2 + content, mt.height)
	sz := ui.constrain(gtx.constraints, {w, mt.height})
	area := ops.Rect{0, 0, sz.x, sz.y}
	r := badge_roles(appearance, color)
	rr := ops.Round_Rect{area, badge_radius(shape, mt, area)}
	if bg := role_color(r.bg); ui.painted(bg) {
		ops.fill(gtx.scene, rr, bg)
	}
	if border := role_color(r.border); ui.painted(border) {
		stroke_inside(gtx, rr, border, tok.STROKE_WIDTH_THIN)
	}
	fg := role_color(r.fg)
	x := (sz.x - content) / 2
	if has_icon && icon_position == .Before {
		icon(gtx, ic, {x, (sz.y - mt.icon) / 2}, mt.icon, fg)
		x += mt.icon + (has_text ? mt.gap : 0)
	}
	if has_text {
		draw_text(gtx, t, {x, (sz.y - t.height) / 2}, fg)
		x += t.width
	}
	if has_icon && icon_position == .After {
		x += has_text ? mt.gap : 0
		icon(gtx, ic, {x, (sz.y - mt.icon) / 2}, mt.icon, fg)
	}
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, text))
	return ui.widget_close(gtx, &p, {sz, has_text ? (sz.y - t.height) / 2 + baseline_of(t) : sz.y})
}

// COUNTER_DOT is a counter badge's dot: a 6px square
// (useCounterBadgeStyles.styles.ts:14-37).
COUNTER_DOT :: f32(6)

// counter_text is count as a counter badge shows it: capped at overflow
// with a plus beyond it (CounterBadge.types.ts:19-47).
counter_text :: proc(count, overflow: int, allocator := context.allocator) -> string {
	buf: [24]u8
	if count > overflow {
		return strings.concatenate({strconv.write_int(buf[:], i64(overflow), 10), "+"}, allocator)
	}
	return strings.clone(strconv.write_int(buf[:], i64(count), 10), allocator)
}

// counter_badge is a badge showing a number, or an unread dot, on
// another element: count capped at overflow with a plus beyond it. A
// zero count lays out nothing unless show_zero; dot replaces the number
// with a 6px dot. Fluent offers it in brand, danger, important and
// informative, circular or rounded; nothing here enforces that.
counter_badge :: proc(
	gtx: ^ui.Ctx,
	count: int,
	overflow := 99,
	show_zero := false,
	dot := false,
	color := Badge_Color.Brand,
	appearance := Badge_Appearance.Filled,
	size := Badge_Size.Medium,
	shape := Badge_Shape.Circular,
	key: u64 = 0,
	loc := #caller_location,
) -> ui.Dims {
	if count == 0 && !show_zero && !dot {
		p := ui.widget_open(gtx, key, loc)
		return ui.widget_close(gtx, &p, {})
	}
	if dot {
		p := ui.widget_open(gtx, key, loc)
		sz := ui.constrain(gtx.constraints, {COUNTER_DOT, COUNTER_DOT})
		r := badge_roles(appearance, color)
		if bg := role_color(r.bg); ui.painted(bg) {
			ops.fill(gtx.scene, ops.Round_Rect{{0, 0, sz.x, sz.y}, shape == .Circular ? sz.y / 2 : tok.BORDER_RADIUS_SMALL}, bg)
		}
		ops.tag(gtx.scene, p.id, "dot")
		return ui.widget_close(gtx, &p, {sz, sz.y})
	}
	return badge(gtx, counter_text(count, overflow, gtx.allocator), color, appearance, size, shape, key = key, loc = loc)
}

// role_color is color for a role: the same lookup, named so a proc whose
// parameter is called color (a badge's, an avatar's) can still read the
// scheme.
@(private)
role_color :: proc(r: tok.Role) -> ops.Color {
	return scheme()[r]
}

// Presence_Status is a person's availability.
Presence_Status :: enum u8 {
	Available,
	Away,
	Busy,
	Do_Not_Disturb,
	Offline,
	Out_Of_Office,
	Blocked,
	Unknown,
}

// PRESENCE_SIZE is the presence disc's diameter per badge size: 6, 20
// and 28px are forced (usePresenceBadgeStyles.styles.ts:76-103); the
// rest are the icon's own 10, 12 and 16px.
PRESENCE_SIZE := [Badge_Size]f32{.Tiny = 6, .Extra_Small = 10, .Small = 12, .Medium = 16, .Large = 20, .Extra_Large = 28}

// presence_role is status's colour (usePresenceBadgeStyles.styles.ts:
// 44-74,118-130): busy, do-not-disturb and blocked share the busy red;
// out of office turns away and offline berry.
presence_role :: proc(status: Presence_Status, out_of_office := false) -> tok.Role {
	switch status {
	case .Available:
		return .Palette_Light_Green_Foreground3
	case .Busy, .Do_Not_Disturb, .Blocked:
		return .Palette_Red_Background3
	case .Away:
		return out_of_office ? .Palette_Berry_Foreground3 : .Palette_Marigold_Background3
	case .Out_Of_Office:
		return .Palette_Berry_Foreground3
	case .Offline:
		return out_of_office ? .Palette_Berry_Foreground3 : .Neutral_Foreground3
	case .Unknown:
	}
	return .Neutral_Foreground3
}

// presence_badge is a person's availability as a disc: the status's
// colour on a Neutral_Background1 disc 1px larger (styles.ts:22-42), and
// the status glyph in it. Departure: the glyphs are Fluent's presence
// icons drawn as strokes here (a check, clock hands, a dash, a cross, an
// arrow, a slash), as @fluentui/react-icons' presence set is not in
// the kit; out of office draws each as its outlined variant.
presence_badge :: proc(
	gtx: ^ui.Ctx,
	status: Presence_Status,
	out_of_office := false,
	size := Badge_Size.Medium,
	key: u64 = 0,
	loc := #caller_location,
) -> ui.Dims {
	p := ui.widget_open(gtx, key, loc)
	d := PRESENCE_SIZE[size]
	sz := ui.constrain(gtx.constraints, {d, d})
	paint_presence(gtx, {0, 0, sz.x, sz.y}, status, out_of_office)
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, PRESENCE_NAMES[status]))
	return ui.widget_close(gtx, &p, {sz, sz.y})
}

PRESENCE_NAMES := [Presence_Status]string {
	.Available      = "available",
	.Away           = "away",
	.Busy           = "busy",
	.Do_Not_Disturb = "do not disturb",
	.Offline        = "offline",
	.Out_Of_Office  = "out of office",
	.Blocked        = "blocked",
	.Unknown        = "unknown",
}

// paint_presence draws status's disc and glyph in r: the disc on a
// Neutral_Background1 disc, which is what separates it from whatever it
// sits on (an avatar's corner). Available, busy, do-not-disturb and
// away fill; the rest, and every out-of-office variant, are rings.
paint_presence :: proc(gtx: ^ui.Ctx, r: ops.Rect, status: Presence_Status, out_of_office := false) {
	c := role_color(presence_role(status, out_of_office))
	ops.fill(gtx.scene, ops.Ellipse{r}, role_color(.Neutral_Background1))
	inner := ops.Rect{r.x + 1, r.y + 1, r.w - 2, r.h - 2}
	if r.w <= 6 {
		inner = r // tiny unclips (styles.ts:79-87)
	}
	d := inner.w
	w := max(d / 8, 1) // the glyph's stroke, about the icon's own
	ring := out_of_office || status == .Offline || status == .Out_Of_Office || status == .Blocked || status == .Unknown
	if ring {
		ops.stroke(gtx.scene, ops.Ellipse{{inner.x + w / 2, inner.y + w / 2, d - w, d - w}}, c, {width = w})
	} else {
		ops.fill(gtx.scene, ops.Ellipse{inner}, c)
	}
	if d < 10 {
		return // a tiny or extra-small disc is colour alone
	}
	mark := ring ? c : role_color(.Neutral_Background1)
	cx, cy := inner.x + d / 2, inner.y + d / 2
	st := ops.Stroke_Style{width = w, cap = .Round}
	switch status {
	case .Available:
		ops.stroke(gtx.scene, ui.polyline(gtx, {{cx - d * 0.22, cy}, {cx - d * 0.06, cy + d * 0.16}, {cx + d * 0.24, cy - d * 0.16}}), mark, st)
	case .Away:
		ops.stroke(gtx.scene, ui.polyline(gtx, {{cx, cy - d * 0.25}, {cx, cy}, {cx + d * 0.2, cy + d * 0.12}}), mark, st)
	case .Busy:
	case .Do_Not_Disturb:
		ops.stroke(gtx.scene, ui.line(gtx, {cx - d * 0.24, cy}, {cx + d * 0.24, cy}), mark, st)
	case .Offline:
		k := d * 0.18
		ops.stroke(gtx.scene, ui.line(gtx, {cx - k, cy - k}, {cx + k, cy + k}), mark, st)
		ops.stroke(gtx.scene, ui.line(gtx, {cx + k, cy - k}, {cx - k, cy + k}), mark, st)
	case .Out_Of_Office:
		k := d * 0.22
		ops.stroke(gtx.scene, ui.line(gtx, {cx - k, cy}, {cx + k, cy}), mark, st)
		ops.stroke(gtx.scene, ui.polyline(gtx, {{cx + k * 0.3, cy - k * 0.7}, {cx + k, cy}, {cx + k * 0.3, cy + k * 0.7}}), mark, st)
	case .Blocked:
		k := d * 0.28
		ops.stroke(gtx.scene, ui.line(gtx, {cx - k, cy + k}, {cx + k, cy - k}), mark, st)
	case .Unknown:
	}
}

// Avatar.

// Avatar_Size is the square's side in px.
Avatar_Size :: enum u8 {
	S16,
	S20,
	S24,
	S28,
	S32,
	S36,
	S40,
	S48,
	S56,
	S64,
	S72,
	S96,
	S120,
	S128,
}

AVATAR_PX := [Avatar_Size]f32{.S16 = 16, .S20 = 20, .S24 = 24, .S28 = 28, .S32 = 32, .S36 = 36, .S40 = 40, .S48 = 48, .S56 = 56, .S64 = 64, .S72 = 72, .S96 = 96, .S120 = 120, .S128 = 128}

Avatar_Shape :: enum u8 {
	Circular,
	Square,
}

// Avatar_Color is the disc and initials colour: neutral grey, the
// static brand colour, one of the 30 named palette colours, or Colorful,
// which hashes the name to one of those 30 so a person always gets the
// same colour. The named members follow Fluent's order, which the hash
// indexes (Avatar.types.ts:62-93).
Avatar_Color :: enum u8 {
	Neutral,
	Brand,
	Colorful,
	Dark_Red,
	Cranberry,
	Red,
	Pumpkin,
	Peach,
	Marigold,
	Gold,
	Brass,
	Brown,
	Forest,
	Seafoam,
	Dark_Green,
	Light_Teal,
	Teal,
	Steel,
	Blue,
	Royal_Blue,
	Cornflower,
	Navy,
	Lavender,
	Purple,
	Grape,
	Lilac,
	Pink,
	Magenta,
	Plum,
	Beige,
	Mink,
	Platinum,
	Anchor,
}

// Avatar_Active is the active decoration: none, the ring and/or shadow,
// or the shrunken, faded inactive look.
Avatar_Active :: enum u8 {
	Unset,
	Active,
	Inactive,
}

Avatar_Appearance :: enum u8 {
	Ring,
	Shadow,
	Ring_Shadow,
}

// Avatar_Roles are a colour's initials, disc and ring roles.
Avatar_Roles :: struct {
	fg, bg, ring: tok.Role,
}

// AVATAR_NAMED are the 30 named colours' roles, Foreground2 on
// Background2 with BorderActive for the ring, in Avatar_Color order
// from Dark_Red (useAvatarStyles.styles.ts:253-380).
@(private)
AVATAR_NAMED := [30]Avatar_Roles {
	{.Palette_Dark_Red_Foreground2, .Palette_Dark_Red_Background2, .Palette_Dark_Red_Border_Active},
	{.Palette_Cranberry_Foreground2, .Palette_Cranberry_Background2, .Palette_Cranberry_Border_Active},
	{.Palette_Red_Foreground2, .Palette_Red_Background2, .Palette_Red_Border_Active},
	{.Palette_Pumpkin_Foreground2, .Palette_Pumpkin_Background2, .Palette_Pumpkin_Border_Active},
	{.Palette_Peach_Foreground2, .Palette_Peach_Background2, .Palette_Peach_Border_Active},
	{.Palette_Marigold_Foreground2, .Palette_Marigold_Background2, .Palette_Marigold_Border_Active},
	{.Palette_Gold_Foreground2, .Palette_Gold_Background2, .Palette_Gold_Border_Active},
	{.Palette_Brass_Foreground2, .Palette_Brass_Background2, .Palette_Brass_Border_Active},
	{.Palette_Brown_Foreground2, .Palette_Brown_Background2, .Palette_Brown_Border_Active},
	{.Palette_Forest_Foreground2, .Palette_Forest_Background2, .Palette_Forest_Border_Active},
	{.Palette_Seafoam_Foreground2, .Palette_Seafoam_Background2, .Palette_Seafoam_Border_Active},
	{.Palette_Dark_Green_Foreground2, .Palette_Dark_Green_Background2, .Palette_Dark_Green_Border_Active},
	{.Palette_Light_Teal_Foreground2, .Palette_Light_Teal_Background2, .Palette_Light_Teal_Border_Active},
	{.Palette_Teal_Foreground2, .Palette_Teal_Background2, .Palette_Teal_Border_Active},
	{.Palette_Steel_Foreground2, .Palette_Steel_Background2, .Palette_Steel_Border_Active},
	{.Palette_Blue_Foreground2, .Palette_Blue_Background2, .Palette_Blue_Border_Active},
	{.Palette_Royal_Blue_Foreground2, .Palette_Royal_Blue_Background2, .Palette_Royal_Blue_Border_Active},
	{.Palette_Cornflower_Foreground2, .Palette_Cornflower_Background2, .Palette_Cornflower_Border_Active},
	{.Palette_Navy_Foreground2, .Palette_Navy_Background2, .Palette_Navy_Border_Active},
	{.Palette_Lavender_Foreground2, .Palette_Lavender_Background2, .Palette_Lavender_Border_Active},
	{.Palette_Purple_Foreground2, .Palette_Purple_Background2, .Palette_Purple_Border_Active},
	{.Palette_Grape_Foreground2, .Palette_Grape_Background2, .Palette_Grape_Border_Active},
	{.Palette_Lilac_Foreground2, .Palette_Lilac_Background2, .Palette_Lilac_Border_Active},
	{.Palette_Pink_Foreground2, .Palette_Pink_Background2, .Palette_Pink_Border_Active},
	{.Palette_Magenta_Foreground2, .Palette_Magenta_Background2, .Palette_Magenta_Border_Active},
	{.Palette_Plum_Foreground2, .Palette_Plum_Background2, .Palette_Plum_Border_Active},
	{.Palette_Beige_Foreground2, .Palette_Beige_Background2, .Palette_Beige_Border_Active},
	{.Palette_Mink_Foreground2, .Palette_Mink_Background2, .Palette_Mink_Border_Active},
	{.Palette_Platinum_Foreground2, .Palette_Platinum_Background2, .Palette_Platinum_Border_Active},
	{.Palette_Anchor_Foreground2, .Palette_Anchor_Background2, .Palette_Anchor_Border_Active},
}

// avatar_roles is c's roles; Colorful is resolved first by avatar_color.
avatar_roles :: proc(c: Avatar_Color) -> Avatar_Roles {
	switch c {
	case .Neutral, .Colorful:
		return {.Neutral_Foreground3, .Neutral_Background6, .Brand_Stroke1}
	case .Brand:
		return {.Neutral_Foreground_Static_Inverted, .Brand_Background_Static, .Brand_Stroke1}
	case .Dark_Red, .Cranberry, .Red, .Pumpkin, .Peach, .Marigold, .Gold, .Brass, .Brown, .Forest, .Seafoam, .Dark_Green, .Light_Teal, .Teal, .Steel, .Blue, .Royal_Blue, .Cornflower, .Navy, .Lavender, .Purple, .Grape, .Lilac, .Pink, .Magenta, .Plum, .Beige, .Mink, .Platinum, .Anchor:
		return AVATAR_NAMED[int(c) - int(Avatar_Color.Dark_Red)]
	}
	return {}
}

// avatar_color resolves Colorful to the named colour name hashes to,
// with Fluent's own hash (react-avatar's useAvatar.tsx:233-241 at the
// kit's commit, not a vendored file: from the last UTF-16 unit back,
// each unit rotated within a byte by its index mod 8 and xored in), so
// this and a Fluent app give one person one colour. Any other colour is
// itself.
avatar_color :: proc(c: Avatar_Color, name: string) -> Avatar_Color {
	if c != .Colorful {
		return c
	}
	h: i32
	units := make([dynamic]u16, context.temp_allocator)
	for r in name {
		if r >= 0x10000 {
			v := u32(r) - 0x10000
			append(&units, u16(0xD800 + (v >> 10)), u16(0xDC00 + (v & 0x3FF)))
		} else {
			append(&units, u16(r))
		}
	}
	for i := len(units) - 1; i >= 0; i -= 1 {
		ch := i32(units[i])
		shift := u32(i % 8)
		h ~= (ch << shift) + (ch >> (8 - shift))
	}
	return Avatar_Color(int(Avatar_Color.Dark_Red) + int(h % 30))
}

// initials is name's initials as an avatar shows them: the first
// letter of its first and last word, upper-cased; at 16px only the
// first (Avatar.types.ts:22-44). Allocated on allocator.
initials :: proc(name: string, first_only := false, allocator := context.allocator) -> string {
	words := strings.fields(name, context.temp_allocator)
	b := strings.builder_make(allocator)
	if len(words) == 0 {
		return strings.to_string(b)
	}
	first := strings.to_upper(words[0][:1], context.temp_allocator)
	strings.write_string(&b, first)
	if !first_only && len(words) > 1 {
		last := words[len(words) - 1]
		strings.write_string(&b, strings.to_upper(last[:1], context.temp_allocator))
	}
	return strings.to_string(b)
}

// Avatar_Metrics are one size's text size, icon glyph, square radius,
// ring width, shadow and badge size (useAvatarStyles.styles.ts:
// 113-122,152-167,226-232,493-554).
@(private)
Avatar_Metrics :: struct {
	px, text, icon, square_radius, ring: f32,
	shadow:                              tok.Shadow,
	badge:                               Badge_Size,
}

@(private)
avatar_metrics :: proc(size: Avatar_Size) -> (m: Avatar_Metrics) {
	px := AVATAR_PX[size]
	m.px = px
	switch {
	case px <= 24:
		m.text = tok.FONT_SIZE_BASE100
	case px <= 28:
		m.text = tok.FONT_SIZE_BASE200
	case px <= 40:
		m.text = tok.FONT_SIZE_BASE300
	case px <= 56:
		m.text = tok.FONT_SIZE_BASE400
	case px <= 96:
		m.text = tok.FONT_SIZE_BASE500
	case:
		m.text = tok.FONT_SIZE_BASE600
	}
	switch {
	case px <= 16:
		m.icon = 12
	case px <= 24:
		m.icon = 16
	case px <= 40:
		m.icon = 20
	case px <= 48:
		m.icon = 24
	case px <= 56:
		m.icon = 28
	case px <= 72:
		m.icon = 32
	case:
		m.icon = 48
	}
	switch {
	case px <= 24:
		m.square_radius = tok.BORDER_RADIUS_SMALL
	case px <= 48:
		m.square_radius = tok.BORDER_RADIUS_MEDIUM
	case px <= 72:
		m.square_radius = tok.BORDER_RADIUS_LARGE
	case:
		m.square_radius = tok.BORDER_RADIUS_XLARGE
	}
	switch {
	case px <= 48:
		m.ring = tok.STROKE_WIDTH_THICK
	case px <= 64:
		m.ring = tok.STROKE_WIDTH_THICKER
	case:
		m.ring = tok.STROKE_WIDTH_THICKEST
	}
	switch {
	case px <= 28:
		m.shadow = tok.SHADOW4
	case px <= 48:
		m.shadow = tok.SHADOW8
	case px <= 64:
		m.shadow = tok.SHADOW16
	case:
		m.shadow = tok.SHADOW28
	}
	// The badge size by avatar size is useAvatar's own rule, not the
	// styles file's: tiny to 24, extra-small to 40, small to 56, medium
	// to 72, large to 96, else extra-large.
	switch {
	case px <= 24:
		m.badge = .Tiny
	case px <= 40:
		m.badge = .Extra_Small
	case px <= 56:
		m.badge = .Small
	case px <= 72:
		m.badge = .Medium
	case px <= 96:
		m.badge = .Large
	case:
		m.badge = .Extra_Large
	}
	return
}

// AVATAR_BADGE_RADIUS is the cutout around a badge per badge size
// (useAvatarStyles.styles.ts:181-224); the gap beyond it is
// strokeWidthThin up to medium and strokeWidthThick above.
AVATAR_BADGE_RADIUS := [Badge_Size]f32{.Tiny = 3, .Extra_Small = 5, .Small = 6, .Medium = 8, .Large = 10, .Extra_Large = 14}

// AVATAR_INACTIVE_OPACITY and AVATAR_INACTIVE_SCALE are the inactive
// look (useAvatarStyles.styles.ts:169-179).
AVATAR_INACTIVE_OPACITY :: f32(0.8)
AVATAR_INACTIVE_SCALE :: f32(0.875)

// Avatar_Motion is an avatar's active transition, kept in its widget
// data: the progress from inactive (0) to active (1) it last showed.
Avatar_Motion :: struct {
	tween: ui.Tween,
	live:  bool,
}

// avatar is a person or entity: their initials from name (or a person
// icon when there are none) on a coloured disc or square, an optional
// presence badge at the bottom-right corner, and the active ring or
// shadow. The widget lays out size square; the ring overhangs it by 2 x
// ringWidth, as Fluent's negative margins do. Between active states the
// ring and shadow grow out and fade in while the avatar scales back to
// full size over DURATION_ULTRA_SLOW on CURVE_EASY_EASE_MAX (opacity is
// eased along with them, not on its own linear track).
//
// Departures: no image slot, as jm:ui draws no bitmaps; the badge's
// cutout is a Neutral_Background1 ring behind the badge rather than a
// transparent mask; the presence glyphs are presence_badge's strokes.
avatar :: proc(
	gtx: ^ui.Ctx,
	name: string,
	size := Avatar_Size.S32,
	shape := Avatar_Shape.Circular,
	color := Avatar_Color.Neutral,
	active := Avatar_Active.Unset,
	appearance := Avatar_Appearance.Ring,
	ic := Icon.Person,
	presence := false,
	status := Presence_Status.Available,
	out_of_office := false,
	key: u64 = 0,
	loc := #caller_location,
) -> ui.Dims {
	p := ui.widget_open(gtx, key, loc)
	mt := avatar_metrics(size)
	sz := ui.constrain(gtx.constraints, {mt.px, mt.px})
	roles := avatar_roles(avatar_color(color, name))

	// Slot: the active progress, 1 at rest when unset.
	prog: f32 = 1
	if active != .Unset {
		mo := ui.widget_data(gtx, p.id, Avatar_Motion)
		target: f32 = active == .Active ? 1 : 0
		if !mo.live {
			mo^ = {tween = {from = target, to = target}, live = true}
		} else if mo.tween.to != target {
			mo.tween = {from = mo.tween.from + (mo.tween.to - mo.tween.from) * (mo.tween.duration > 0 ? mo.tween.t / mo.tween.duration : 1), to = target, duration = tok.DURATION_ULTRA_SLOW / 1000}
		}
		prog = design.bezier_ease(tok.CURVE_EASY_EASE_MAX, ui.tween_update(&mo.tween, gtx))
		if mo.tween.duration > 0 {
			prog = mo.tween.from + (mo.tween.to - mo.tween.from) * prog
		} else {
			prog = mo.tween.to
		}
	}
	scale := active == .Unset ? 1 : AVATAR_INACTIVE_SCALE + (1 - AVATAR_INACTIVE_SCALE) * prog
	alpha := active == .Unset ? 1 : AVATAR_INACTIVE_OPACITY + (1 - AVATAR_INACTIVE_OPACITY) * prog
	side := sz.x * scale
	box := ops.Rect{(sz.x - side) / 2, (sz.y - side) / 2, side, side}
	rad := shape == .Circular ? side / 2 : mt.square_radius

	// The ring and shadow layers sit 2 x ringWidth outside the avatar,
	// growing out from its edge as prog rises (styles.ts:135-167).
	if active != .Unset && prog > 0 {
		ext := 2 * mt.ring * prog
		layer := ops.Rect{box.x - ext, box.y - ext, box.w + 2 * ext, box.h + 2 * ext}
		layer_rad := shape == .Circular ? layer.w / 2 : rad + ext
		if appearance != .Ring {
			for l in mt.shadow.layers {
				design.paint_shadow_layer(gtx, {layer, layer_rad}, l.x, l.y, l.blur, fade(role_color(l.color), prog))
			}
		}
		if appearance != .Shadow {
			stroke_inside(gtx, {layer, layer_rad}, fade(role_color(roles.ring), prog), mt.ring)
		}
	}
	bg := fade(role_color(roles.bg), alpha)
	fg := fade(role_color(roles.fg), alpha)
	ops.fill(gtx.scene, ops.Round_Rect{box, rad}, bg)
	// The strokeWidthThin Transparent_Stroke border of the initials and
	// icon layers (styles.ts:60-89): nothing in most themes, and the
	// outline that keeps the disc visible where high contrast drops its
	// background, since that theme binds Transparent_Stroke to CanvasText.
	if border := role_color(.Transparent_Stroke); ui.painted(border) {
		stroke_inside(gtx, {box, rad}, fade(border, alpha), tok.STROKE_WIDTH_THIN)
	}
	text := initials(name, size == .S16, gtx.allocator)
	if text != "" {
		st := tok.Type_Style{weight = tok.FONT_WEIGHT_SEMIBOLD, size = mt.text * scale, line_height = mt.text * scale}
		t := shape_style(gtx, text, st)
		draw_text(gtx, t, {box.x + (box.w - t.width) / 2, box.y + (box.h - t.height) / 2}, fg)
	} else if ic != .None {
		g := mt.icon * scale
		icon(gtx, ic, {box.x + (box.w - g) / 2, box.y + (box.h - g) / 2}, g, fg)
	}
	if presence {
		bs := mt.badge
		d := PRESENCE_SIZE[bs]
		br := ops.Rect{sz.x - d, sz.y - d, d, d}
		gap := bs >= .Large ? tok.STROKE_WIDTH_THICK : tok.STROKE_WIDTH_THIN
		cut := AVATAR_BADGE_RADIUS[bs] + gap
		cx, cy := br.x + d / 2, br.y + d / 2
		ops.fill(gtx.scene, ops.Ellipse{{cx - cut, cy - cut, 2 * cut, 2 * cut}}, role_color(.Neutral_Background1))
		paint_presence(gtx, br, status, out_of_office)
	}
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, name))
	return ui.widget_close(gtx, &p, {sz, sz.y})
}

// Progress bar.

Progress_Thickness :: enum u8 {
	Medium, // 2px
	Large, // 4px
}

Progress_Shape :: enum u8 {
	Rounded,
	Square,
}

// Progress_Color is a determinate bar's colour; an indeterminate bar is
// always brand. The status colours read palette tokens, not the status
// aliases (progress-bar.json notes).
Progress_Color :: enum u8 {
	Brand,
	Success,
	Warning,
	Error,
}

PROGRESS_HEIGHT := [Progress_Thickness]f32{.Medium = 2, .Large = 4}

// PROGRESS_TRANSITION is the width transition of a determinate bar above
// PROGRESS_ZERO: 300ms on the CSS ease curve
// (useProgressBarStyles.styles.ts:13-15,61-65); at or below the
// threshold it jumps, so a reset to 0 is not animated.
PROGRESS_TRANSITION :: f32(300)
PROGRESS_EASE :: tok.Bezier{0.25, 0.1, 0.25, 1}
PROGRESS_ZERO :: f32(0.01)

// PROGRESS_INDETERMINATE_WIDTH is the moving segment's share of the
// track (styles.ts:66-79); PROGRESS_INDETERMINATE_PERIOD is one pass of
// it, the styles file naming none: Fluent's motion slot supplies the
// travel, and this is the 3s of its former CSS keyframes.
PROGRESS_INDETERMINATE_WIDTH :: f32(0.33)
PROGRESS_INDETERMINATE_PERIOD :: f32(3)

// Progress_Motion is a determinate bar's width transition, or an
// indeterminate one's travel, kept in its widget data.
Progress_Motion :: struct {
	tween: ui.Tween,
	live:  bool,
}

progress_role :: proc(c: Progress_Color) -> tok.Role {
	switch c {
	case .Brand:
		return .Compound_Brand_Background
	case .Success:
		return .Palette_Green_Background3
	case .Warning:
		return .Palette_Dark_Orange_Background3
	case .Error:
		return .Palette_Red_Background3
	}
	return .Compound_Brand_Background
}

// progress_bar is a thin bar on a Neutral_Background6 track: with a
// value from 0 to max, the bar fills that share, easing width changes
// over 300ms; with a negative value it is indeterminate, a 33% brand
// segment fading at both ends that crosses the track forever. The
// track spans its container's width, or width when that is given (and
// when the container is unbounded, 200). name is the tag a probe finds
// it by.
progress_bar :: proc(
	gtx: ^ui.Ctx,
	value: f32 = -1,
	max_value: f32 = 1,
	thickness := Progress_Thickness.Medium,
	shape := Progress_Shape.Rounded,
	color := Progress_Color.Brand,
	width: f32 = 0,
	name := "progress",
	key: u64 = 0,
	loc := #caller_location,
) -> ui.Dims {
	p := ui.widget_open(gtx, key, loc)
	cs := gtx.constraints
	h := PROGRESS_HEIGHT[thickness]
	w := width > 0 ? width : ui.is_finite(cs.max.x) ? cs.max.x : 200
	sz := ui.constrain(cs, {w, h})
	track := ops.Rect{0, 0, sz.x, sz.y}
	rad := shape == .Rounded ? min(tok.BORDER_RADIUS_MEDIUM, sz.y / 2) : 0
	ops.fill(gtx.scene, ops.Round_Rect{track, rad}, role_color(.Neutral_Background6))
	mo := ui.widget_data(gtx, p.id, Progress_Motion)
	if value < 0 {
		// Indeterminate: the segment's left edge runs from -33% to 100%.
		if !mo.live || !mo.tween.loop {
			mo^ = {tween = {to = 1, duration = PROGRESS_INDETERMINATE_PERIOD, loop = true}, live = true}
		}
		t := ui.tween_update(&mo.tween, gtx)
		seg := sz.x * PROGRESS_INDETERMINATE_WIDTH
		x := -seg + (sz.x + seg) * t
		ops.clip_push(gtx.scene, ops.Round_Rect{track, rad})
		brand := role_color(.Compound_Brand_Background)
		ops.fill(gtx.scene, ops.Round_Rect{{x, 0, seg, sz.y}, rad}, brand)
		// The gradient Background6, Transparent_Background at 50%,
		// Background6 over it, so the segment fades in and out at its
		// ends (useProgressBarStyles.styles.ts:69-74).
		bg6 := role_color(.Neutral_Background6)
		stops := make([]ops.Gradient_Stop, 3, gtx.allocator)
		stops[0], stops[1], stops[2] = {0, bg6}, {0.5, role_color(.Transparent_Background)}, {1, bg6}
		ops.fill(gtx.scene, ops.Round_Rect{{x, 0, seg, sz.y}, rad}, ops.Linear_Gradient{{x, 0}, {x + seg, 0}, stops})
		ops.clip_pop(gtx.scene)
	} else {
		frac := clamp(value / max(max_value, 1e-6), 0, 1)
		if !mo.live || mo.tween.loop {
			mo^ = {tween = {from = frac, to = frac}, live = true}
		} else if mo.tween.to != frac {
			cur := progress_value(mo)
			if frac <= PROGRESS_ZERO || cur <= PROGRESS_ZERO {
				mo.tween = {from = frac, to = frac} // a jump: at or below the threshold nothing eases
			} else {
				mo.tween = {from = cur, to = frac, duration = PROGRESS_TRANSITION / 1000}
			}
		}
		ui.tween_update(&mo.tween, gtx)
		ops.fill(gtx.scene, ops.Round_Rect{{0, 0, sz.x * progress_value(mo), sz.y}, rad}, role_color(progress_role(color)))
	}
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, name))
	return ui.widget_close(gtx, &p, {sz, sz.y})
}

// progress_value is the eased fraction mo shows now.
@(private)
progress_value :: proc(mo: ^Progress_Motion) -> f32 {
	tw := mo.tween
	if tw.duration <= 0 {
		return tw.to
	}
	return tw.from + (tw.to - tw.from) * design.bezier_ease(PROGRESS_EASE, tw.t / tw.duration)
}

// Spinner.

// Spinner_Size is the ring's diameter, 16 to 44px in 4px steps.
Spinner_Size :: enum u8 {
	Extra_Tiny,
	Tiny,
	Extra_Small,
	Small,
	Medium,
	Large,
	Extra_Large,
	Huge,
}

SPINNER_PX := [Spinner_Size]f32{.Extra_Tiny = 16, .Tiny = 20, .Extra_Small = 24, .Small = 28, .Medium = 32, .Large = 36, .Extra_Large = 40, .Huge = 44}

Spinner_Appearance :: enum u8 {
	Primary, // brand on a light track
	Inverted, // for brand or dark surfaces
}

Label_Position :: enum u8 {
	After,
	Before,
	Above,
	Below,
}

// SPINNER_PERIOD is one turn and one breath of the arc: 1.5s, the
// styles file's constant (useSpinnerStyles.styles.ts:58-64,92-113).
SPINNER_PERIOD :: f32(1.5)
SPINNER_GAP :: f32(8)
SPINNER_MIN_ARC :: f32(30) // degrees (styles.ts:71-90)
SPINNER_MAX_ARC :: f32(255)

// Spinner_Motion is the spinner's phase, kept in its widget data.
Spinner_Motion :: struct {
	tween: ui.Tween,
	live:  bool,
}

@(private)
spinner_stroke :: proc(size: Spinner_Size) -> f32 {
	switch size {
	case .Extra_Tiny, .Tiny, .Extra_Small, .Small:
		return tok.STROKE_WIDTH_THICK
	case .Medium, .Large, .Extra_Large:
		return tok.STROKE_WIDTH_THICKER
	case .Huge:
	}
	return tok.STROKE_WIDTH_THICKEST
}

@(private)
spinner_label_style :: proc(size: Spinner_Size) -> tok.Type_Style {
	switch size {
	case .Extra_Tiny, .Tiny, .Extra_Small, .Small:
		return tok.TYPOGRAPHY_STYLES_BODY1
	case .Medium, .Large, .Extra_Large:
		return tok.TYPOGRAPHY_STYLES_SUBTITLE2
	case .Huge:
	}
	return tok.TYPOGRAPHY_STYLES_SUBTITLE1
}

// spinner is an indeterminate loading ring: a track with an arc that
// spins one turn every 1.5s while it grows from 30° to 255° and back on
// CURVE_EASY_EASE, with an optional label 8px away. The label's colour
// is Neutral_Foreground1 for primary (Fluent's inherits from the page)
// and Neutral_Foreground_Static_Inverted for inverted. It asks for a
// frame every frame while shown. Departures: no delay before showing,
// and the arc's ends are square, as the conic segments' are, without
// the 1px soft edge the CSS mask adds.
spinner :: proc(
	gtx: ^ui.Ctx,
	label := "",
	size := Spinner_Size.Medium,
	appearance := Spinner_Appearance.Primary,
	label_position := Label_Position.After,
	key: u64 = 0,
	loc := #caller_location,
) -> ui.Dims {
	p := ui.widget_open(gtx, key, loc)
	d := SPINNER_PX[size]
	t: Text
	if label != "" {
		t = shape_style(gtx, label, spinner_label_style(size))
	}
	vertical := label_position == .Above || label_position == .Below
	total := ops.Size{d, d}
	if label != "" {
		if vertical {
			total = {max(d, t.width), d + SPINNER_GAP + t.height}
		} else {
			total = {d + SPINNER_GAP + t.width, max(d, t.height)}
		}
	}
	sz := ui.constrain(gtx.constraints, total)
	// Where the ring and label sit.
	ring := ops.Rect{0, 0, d, d}
	lp: ops.Point
	if label != "" {
		switch label_position {
		case .After:
			ring.y = (sz.y - d) / 2
			lp = {d + SPINNER_GAP, (sz.y - t.height) / 2}
		case .Before:
			ring = {t.width + SPINNER_GAP, (sz.y - d) / 2, d, d}
			lp = {0, (sz.y - t.height) / 2}
		case .Above:
			ring.x = (sz.x - d) / 2
			ring.y = t.height + SPINNER_GAP
			lp = {(sz.x - t.width) / 2, 0}
		case .Below:
			ring.x = (sz.x - d) / 2
			lp = {(sz.x - t.width) / 2, d + SPINNER_GAP}
		}
	}
	track, arc_color, label_color: ops.Color
	switch appearance {
	case .Primary:
		track, arc_color, label_color = role_color(.Brand_Stroke2_Contrast), role_color(.Brand_Stroke1), role_color(.Neutral_Foreground1)
	case .Inverted:
		track, arc_color, label_color = role_color(.Neutral_Stroke_Alpha2), role_color(.Neutral_Stroke_On_Brand2), role_color(.Neutral_Foreground_Static_Inverted)
	}
	w := spinner_stroke(size)
	mo := ui.widget_data(gtx, p.id, Spinner_Motion)
	if !mo.live {
		mo^ = {tween = {to = 1, duration = SPINNER_PERIOD, loop = true}, live = true}
	}
	phase := ui.tween_update(&mo.tween, gtx)
	// The track turns linearly; the tail's rotation and the arc's length
	// follow the eased phase: -135° to 225° and 30° to 255° and back.
	spin := phase * 2 * math.PI
	e := design.bezier_ease(tok.CURVE_EASY_EASE, phase)
	tail := (-135 + 360 * e) * math.PI / 180
	breath := 1 - abs(2 * e - 1)
	sweep := (SPINNER_MIN_ARC + (SPINNER_MAX_ARC - SPINNER_MIN_ARC) * breath) * math.PI / 180
	c := ops.Point{ring.x + d / 2, ring.y + d / 2}
	r := d / 2 - w / 2
	ops.stroke(gtx.scene, ops.Ellipse{{ring.x + w / 2, ring.y + w / 2, d - w, d - w}}, track, {width = w})
	a0 := spin + tail - math.PI / 2
	ops.stroke(gtx.scene, design.arc(gtx, c, r, a0, a0 + sweep), arc_color, {width = w, cap = .Butt})
	if label != "" {
		draw_text(gtx, t, lp, label_color)
	}
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, label != "" ? label : "spinner"))
	return ui.widget_close(gtx, &p, {sz, label != "" ? lp.y + baseline_of(t) : sz.y})
}
