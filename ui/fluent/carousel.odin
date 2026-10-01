package fluent

import "base:runtime"
import "jm:ui"
import "jm:ui/design"
import tok "jm:ui/fluent/tokens"
import "jm:ui/ops"

// The carousel, from the fluent-kit's components/carousel.json and the
// styles files it cites (useCarouselStyles, useCarouselViewportStyles,
// useCarouselSliderStyles, useCarouselCardStyles,
// useCarouselNavContainerStyles, useCarouselNavStyles,
// useCarouselNavButtonStyles, useCarouselButtonStyles,
// useCarouselAutoplayButtonStyles). A strip of cards, one page wide,
// moved by previous and next buttons, dot navigation, arrow keys or
// autoplay:
//
//	if fluent.carousel(gtx, &m.page, 3) {
//		for i in 0 ..< 3 {
//			if fluent.carousel_card(gtx, i) { … }
//		}
//	}
//
// A card's body runs only while any of it is in view.

// Carousel_Appearance is carousel.json's appearance.
Carousel_Appearance :: enum u8 {
	Flat, // no spacing, cards unstyled
	Elevated, // room around, gaps between, cards rounded and shadowed
}

// CAROUSEL_AUTOPLAY is the autoplay interval, in seconds (carousel.json
// behaviour defaults: 4000ms, useCarousel.ts).
CAROUSEL_AUTOPLAY :: f32(4)

// CAROUSEL_DOT* are a nav dot's glyph and padding (useCarouselNavButton
// Styles.styles.ts:17-43,65-77): an 8px glyph padded 8px, or selected a
// 16px bar padded 4px across, so every dot is a 24px target.
@(private)
CAROUSEL_DOT :: f32(8)
@(private)
CAROUSEL_DOT_SELECTED :: f32(16)
@(private)
CAROUSEL_DOT_PAD :: f32(8)
@(private)
CAROUSEL_DOT_SELECTED_PAD :: f32(4)
// The glyph's opacities (carousel.json states enabled).
@(private)
CAROUSEL_DOT_REST :: f32(0.6)
@(private)
CAROUSEL_DOT_HOVER :: f32(0.75)
@(private)
CAROUSEL_BUTTON :: f32(32)

// Carousel is an open carousel between carousel_open and carousel_close.
Carousel :: struct {
	visible:    bool,
	id:         ops.Area_Id,
	col:        ui.Flex,
	inset:      ui.Inset,
	clip:       ui.Clip_Box,
	stack:      ui.Stack,
	active:     ^int,
	autoplay:   ^bool,
	count:      int,
	pos:        f32, // the strip's position, in pages
	width:      f32, // a card's width
	gap:        f32,
	appearance: Carousel_Appearance,
	circular:   bool,
	brand:      bool,
}

// Carousel_Data is what a carousel keeps between frames: the strip's
// motion and the autoplay clock.
@(private)
Carousel_Data :: struct {
	from, to: f32,
	tween:    ui.Tween,
	live:     bool,
	elapsed:  f32,
}

@(private, thread_local)
current_carousel: ^Carousel

// carousel_open lays out the strip of count cards, active^ showing, as
// wide as the width offered (400px when unbounded). A change of active^
// slides the strip over DURATION_SLOW on CURVE_DECELERATE_MAX. Elevated
// pads the root spacingVerticalL, puts spacingHorizontalXXL between
// cards and rounds each to borderRadiusXLarge under shadow16. circular
// wraps previous and next at the ends. autoplay, when given, is the
// autoplay toggle's state: while true the carousel advances every
// CAROUSEL_AUTOPLAY seconds, and any press on its controls stops it.
// brand_nav fills the selected dot with Compound_Brand_Background.
//
// Departures: the strip moves on a timed curve, not Embla's attraction
// physics (carousel.json notes: a physics speed has no duration); drag,
// the fade motion, group sizes, alignments and the overlay layouts are
// not built, only inline; the strip clips on both axes inside the
// elevated padding, where the root clips only horizontally; a circular wrap slides back across the strip
// rather than on round; image nav buttons are not built (jm:ui draws no
// bitmaps); page changes are not announced; the autoplay button draws
// its own play and pause marks, which the icon set lacks.
carousel_open :: proc(
	gtx: ^ui.Ctx,
	active: ^int,
	count: int,
	appearance := Carousel_Appearance.Flat,
	circular := false,
	autoplay: ^bool = nil,
	brand_nav := false,
	key: u64 = 0,
	loc := #caller_location,
) -> (c: Carousel) {
	c.id = ui.claim_id(gtx, key, loc)
	d := ui.widget_data(gtx, c.id, Carousel_Data)
	active^ = clamp(active^, 0, max(count - 1, 0))
	if autoplay != nil && autoplay^ && count > 1 {
		d.elapsed += gtx.dt
		if d.elapsed >= CAROUSEL_AUTOPLAY {
			d.elapsed = 0
			active^ = (active^ + 1) % count
		}
		ui.request_frame(gtx, CAROUSEL_AUTOPLAY - d.elapsed)
	} else {
		d.elapsed = 0
	}
	target := f32(active^)
	if !d.live {
		d^ = {from = target, to = target, live = true}
	}
	if target != d.to {
		d.from = carousel_pos(d)
		d.to = target
		d.tween = {to = 1, duration = tok.DURATION_SLOW / 1000}
	}
	ui.tween_update(&d.tween, gtx)
	c.visible = true
	c.pos = carousel_pos(d)
	c.active = active
	c.autoplay = autoplay
	c.count = count
	c.appearance = appearance
	c.circular = circular
	c.brand = brand_nav
	elevated := appearance == .Elevated
	c.gap = elevated ? tok.SPACING_HORIZONTAL_XXL : 0
	room := elevated ? tok.SPACING_VERTICAL_L : 0
	cs := gtx.constraints
	c.width = (ui.is_finite(cs.max.x) ? cs.max.x : 400) - 2 * room
	// Every part is keyed from the carousel's own id: they share call
	// sites here, and two carousels on a page must not share state.
	c.col = ui.column_open(gtx, key = part_key(c.id, 11), loc = loc)
	ui.container_semantics(gtx, {role = .Group, label = "carousel"})
	// The clip is outside the elevated padding, so a card's shadow has
	// that room before it is cut.
	c.clip = ui.clip_box_open(gtx, key = part_key(c.id, 2))
	c.inset = ui.inset_open(gtx, ui.pad_all(room), key = part_key(c.id, 1))
	c.stack = ui.stack_open(gtx, key = part_key(c.id, 3))
	strut(gtx, {c.width, 0}, part_key(c.id, 10))
	current_carousel = ui.widget_data(gtx, c.id, Carousel)
	current_carousel^ = c
	return
}

@(private)
carousel_pos :: proc(d: ^Carousel_Data) -> f32 {
	if d.tween.duration <= 0 {
		return d.to
	}
	return d.from + (d.to - d.from) * design.bezier_ease(tok.CURVE_DECELERATE_MAX, d.tween.t / d.tween.duration)
}

// carousel_close closes the strip and lays out the nav row below it,
// spacingVerticalM down and centred: the previous button, the nav of
// dots on a Neutral_Background_Alpha pill with borderRadiusXLarge
// corners, the next button and, when the carousel has autoplay, its
// toggle. The buttons are 32px circles in Neutral_Foreground2 on
// Neutral_Background_Alpha; a dot is Neutral_Foreground1 at 60%, 75%
// hovered and full pressed, selected full, 75% hovered and 65% pressed.
carousel_close :: proc(c: ^Carousel) {
	if !c.visible {
		return
	}
	gtx := c.col.gtx
	ui.close(&c.stack)
	ui.close(&c.inset)
	ui.close(&c.clip)
	ui.spacer(gtx, tok.SPACING_VERTICAL_M)
	nav := ui.row_open(gtx, gap = tok.SPACING_HORIZONTAL_S, align = .Center, key = part_key(c.id, 4))
	ui.fill_space(gtx)
	btn_fg := State_Roles{.Neutral_Foreground2, .Neutral_Foreground2_Hover, .Neutral_Foreground2_Pressed, .Neutral_Foreground_Disabled}
	roles := Button_Roles {
		bg     = {.Neutral_Background_Alpha, .Neutral_Background1_Hover, .Neutral_Background1_Pressed, .Neutral_Background_Alpha},
		border = {.Transparent_Stroke, .Transparent_Stroke, .Transparent_Stroke, .Transparent_Stroke},
		text   = btn_fg,
		icon   = btn_fg,
	}
	first, last := c.active^ == 0, c.active^ == c.count - 1
	interacted := false
	prev_state: Interaction = first && !c.circular ? .Disabled : .Live
	if roles_button(gtx, "", roles, .Chevron_Left, "Previous", square = CAROUSEL_BUTTON, radius = CAROUSEL_BUTTON / 2, state = prev_state, key = part_key(c.id, 5)) {
		c.active^ = first ? c.count - 1 : c.active^ - 1
		interacted = true
	}
	pill := ui.box_open(gtx, {fill = color(.Neutral_Background_Alpha), radius = tok.BORDER_RADIUS_XLARGE}, key = part_key(c.id, 6))
	dots := ui.row_open(gtx, align = .Center, key = part_key(c.id, 7))
	ui.container_semantics(gtx, {role = .Tab_List})
	for i in 0 ..< c.count {
		before := c.active^
		if nav_dot(
			gtx,
			i == c.active^,
			.Neutral_Foreground1,
			CAROUSEL_DOT_REST,
			CAROUSEL_DOT_HOVER,
			CAROUSEL_DOT,
			CAROUSEL_DOT_SELECTED,
			CAROUSEL_DOT_PAD,
			fmt_page(gtx, i, c.count),
			c.active,
			c.count,
			brand_selected = c.brand,
			selected_pad_x = CAROUSEL_DOT_SELECTED_PAD,
			key = u64(i + 1),
		) {
			c.active^ = i
			interacted = true
		}
		if c.active^ != before {
			interacted = true
		}
	}
	ui.close(&dots)
	ui.close(&pill)
	next_state: Interaction = last && !c.circular ? .Disabled : .Live
	if roles_button(gtx, "", roles, .Chevron_Right, "Next", square = CAROUSEL_BUTTON, radius = CAROUSEL_BUTTON / 2, state = next_state, key = part_key(c.id, 8)) {
		c.active^ = last ? 0 : c.active^ + 1
		interacted = true
	}
	if c.autoplay != nil {
		on := c.autoplay^
		ar := roles
		if on {
			ar.bg = {.Neutral_Background1_Selected, .Neutral_Background1_Hover, .Neutral_Background1_Pressed, .Neutral_Background_Alpha}
		}
		if roles_button(gtx, "", ar, name = "Autoplay", square = CAROUSEL_BUTTON, radius = CAROUSEL_BUTTON / 2, glyph = on ? .Pause : .Play, key = part_key(c.id, 9)) {
			c.autoplay^ = !on
		} else if interacted {
			c.autoplay^ = false
		}
	}
	ui.fill_space(gtx)
	ui.close(&nav)
	ui.close(&c.col)
	c.visible = false
	current_carousel = nil
}

// carousel is carousel_open as a guard: its body lays out the cards, and
// the nav follows at the end of the if.
@(deferred_in = carousel_guard_close)
carousel :: proc(
	gtx: ^ui.Ctx,
	active: ^int,
	count: int,
	appearance := Carousel_Appearance.Flat,
	circular := false,
	autoplay: ^bool = nil,
	brand_nav := false,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	c := carousel_open(gtx, active, count, appearance, circular, autoplay, brand_nav, key, loc)
	return c.visible
}

@(private = "file")
carousel_guard_close :: proc(gtx: ^ui.Ctx, active: ^int, count: int, appearance: Carousel_Appearance, circular: bool, autoplay: ^bool, brand_nav: bool, key: u64, loc: runtime.Source_Code_Location) {
	if current_carousel != nil {
		carousel_close(current_carousel)
	}
}

// Carousel_Card is an open card between carousel_card_open and
// carousel_card_close.
Carousel_Card :: struct {
	visible: bool,
	gtx:     ^ui.Ctx,
	box:     ui.Box,
	col:     ui.Flex,
}

@(private)
Card_Look :: struct {
	elevated: bool,
}

// carousel_card_open opens card i of the carousel at its place in the
// strip, a page wide, while any of it is in view; visible is false, and
// nothing is laid out, when it is not. An elevated card is
// Neutral_Background1 with borderRadiusXLarge corners under shadow16.
carousel_card_open :: proc(gtx: ^ui.Ctx, i: int, key: u64 = 0, loc := #caller_location) -> (card: Carousel_Card) {
	c := current_carousel
	if c == nil {
		return
	}
	off := f32(i) - c.pos
	if abs(off) >= 1 {
		return
	}
	card.visible = true
	card.gtx = gtx
	ops.transform_push(gtx.scene, ops.translate(off * (c.width + c.gap), 0))
	look := new(Card_Look, gtx.allocator)
	look.elevated = c.appearance == .Elevated
	card.box = ui.box_open(gtx, {paint = paint_carousel_card, user = look}, key = part_key(c.id, u64(0x200 + i)), loc = loc)
	ui.container_semantics(gtx, {role = .Group, label = fmt_page(gtx, i, c.count)})
	card.col = ui.column_open(gtx, align = .Fill, key = part_key(c.id, u64(0x300 + i)))
	strut(gtx, {c.width, 0}, part_key(c.id, u64(0x400 + i)))
	return
}

// carousel_card_close closes a card opened by carousel_card_open.
carousel_card_close :: proc(card: ^Carousel_Card) {
	if !card.visible {
		return
	}
	ui.close(&card.col)
	ui.close(&card.box)
	ops.transform_pop(card.gtx.scene)
	card.visible = false
}

@(private, thread_local)
current_card: Carousel_Card

// carousel_card is carousel_card_open as a guard: its body runs only
// while the card is in view.
@(deferred_in = carousel_card_guard_close)
carousel_card :: proc(gtx: ^ui.Ctx, i: int, key: u64 = 0, loc := #caller_location) -> bool {
	current_card = carousel_card_open(gtx, i, key, loc)
	return current_card.visible
}

@(private = "file")
carousel_card_guard_close :: proc(gtx: ^ui.Ctx, i: int, key: u64, loc: runtime.Source_Code_Location) {
	carousel_card_close(&current_card)
}

@(private)
paint_carousel_card :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, size: ops.Size, user: rawptr) {
	lk := (^Card_Look)(user)
	if !lk.elevated {
		return
	}
	rr := ops.Round_Rect{{0, 0, size.x, size.y}, tok.BORDER_RADIUS_XLARGE}
	paint_shadow(gtx, rr, tok.SHADOW16)
	ops.fill(gtx.scene, rr, color(.Neutral_Background1))
}

// strut is an empty widget of size: it holds a container open to a width
// without drawing anything.
@(private)
strut :: proc(gtx: ^ui.Ctx, size: ops.Size, key: u64 = 0, loc := #caller_location) {
	p := ui.widget_open(gtx, key, loc)
	ui.widget_close(gtx, &p, {size = ui.constrain(gtx.constraints, size)})
}

// part_key is the key for a component's part n: its id mixed with n, so
// parts laid out from one call site stay apart across instances.
@(private)
part_key :: proc(owner: ops.Area_Id, n: u64) -> u64 {
	return u64(ui.id_mix(owner, n))
}
