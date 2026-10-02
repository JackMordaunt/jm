package primer

import "jm:ui"
import "jm:ui/design"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// AVATAR_SIZE is an avatar's default side (Avatar.tsx:7).
AVATAR_SIZE :: f32(20)

// avatar_radius is a square avatar's corner: clamp(4px, size - 24px,
// --borderRadius-medium), 4px to 28px and 6px from 30px
// (Avatar.module.css:13-16); a round one's is half its side.
avatar_radius :: proc(size: f32, square: bool) -> f32 {
	if !square {
		return size / 2
	}
	return clamp(size - 24, 4, tok.BORDER_RADIUS_MEDIUM)
}

// Avatar_Paint is one avatar's picture: its image (a path; "" for none),
// its box, shape and opacity.
@(private)
Avatar_Paint :: struct {
	src:    string,
	box:    ops.Rect,
	square: bool,
	alpha:  f32,
}

// paint_avatar draws a: the --avatar-bgColor placeholder clipped to the
// shape, then the image over it, scaled to fill the box, at a's alpha.
@(private)
paint_avatar :: proc(gtx: ^ui.Ctx, a: Avatar_Paint) {
	rr := ops.Round_Rect{a.box, avatar_radius(a.box.w, a.square)}
	ops.fill(gtx.scene, rr, fade(color(.Avatar_Bg_Color), a.alpha))
	if a.src == "" {
		return
	}
	ops.clip_push(gtx.scene, rr)
	ops.image(gtx.scene, ops.add_image(gtx.scene, a.src), a.box, alpha = u8(clamp(a.alpha, 0, 1) * 255 + 0.5))
	ops.clip_pop(gtx.scene)
}

// avatar is Primer's Avatar: a picture of a person or an organisation,
// size px square, clipped to a circle or, square, to a rounded square,
// with a 1px --avatar-borderColor ring just outside its edge that takes
// no space (primer-kit avatar.json, Avatar.module.css:1-34). src is an
// image file jm:ui's renderer loads (ops.add_image); the picture is
// stretched to the box, as the img's default object-fit is (avatar.json
// notes). alt is what a reader hears; empty leaves it decorative, for an
// avatar beside a name.
//
// Departures: the web draws nothing before the image loads; this paints
// --avatar-bgColor, which no module reads (avatar.json notes, web-only
// and dead-token), under it, so an avatar without src, or whose file
// fails to load, is a pale disc in its ring. A responsive {narrow,
// regular, wide} size is not offered.
avatar :: proc(gtx: ^ui.Ctx, src := "", size := AVATAR_SIZE, square := false, alt := "", key: u64 = 0, loc := #caller_location) {
	p := ui.widget_open(gtx, key, loc)
	sz := ui.constrain_min(gtx.constraints, {size, size})
	box := ops.Rect{0, (sz.y - size) / 2, size, size}
	rr := ops.Round_Rect{box, avatar_radius(size, square)}
	design.paint_box_shadow(gtx, rr, {spread = tok.BORDER_WIDTH_THIN, color = color(.Avatar_Border_Color)})
	paint_avatar(gtx, {src, box, square, 1})
	said := ui.frame_string(gtx, alt)
	if said != "" {
		ops.tag(gtx.scene, p.id, said, box)
		ui.semantics(gtx, &p, {role = .Image, label = said})
	}
	ui.widget_close(gtx, &p, {sz, 0})
}

// skeleton_avatar is Primer's SkeletonAvatar: an avatar's box, size px
// square, round or square as an Avatar, filled with the shimmering
// --skeletonLoader-bgColor and no ring (primer-kit skeleton-avatar.json,
// SkeletonAvatar.module.css:1-32), so swapping it for the Avatar keeps the
// layout.
skeleton_avatar :: proc(gtx: ^ui.Ctx, size := AVATAR_SIZE, square := false, key: u64 = 0, loc := #caller_location) {
	p := ui.widget_open(gtx, key, loc)
	sz := ui.constrain_min(gtx.constraints, {size, size})
	box := ops.Rect{0, (sz.y - size) / 2, size, size}
	paint_shimmer(gtx, ops.Round_Rect{box, avatar_radius(size, square)}, box, color(.Skeleton_Loader_Bg_Color))
	ops.tag(gtx.scene, p.id, "skeleton avatar", box)
	ui.widget_close(gtx, &p, {sz, 0})
}

// Avatar_Source is one avatar in a stack: its image file ("" for the
// placeholder) and what a reader hears.
Avatar_Source :: struct {
	src, alt: string,
}

// Avatar_Stack_Variant is how a stack overlaps: Cascade overlaps the
// third and later avatars more and fades them; Stack overlaps evenly at
// full opacity.
Avatar_Stack_Variant :: enum u8 {
	Cascade,
	Stack,
}

// AVATAR_STACK_SHOWN is how many avatars a collapsed stack draws; the
// rest show when it expands (AvatarStack.module.css:223-247).
AVATAR_STACK_SHOWN :: 5

// AVATAR_STACK_GAP is the cut-out ring's width, and the gap that
// separates each avatar from the one it overlaps (AvatarStack.module.css:3-5).
AVATAR_STACK_GAP :: f32(1)

// AVATAR_STACK_EXPAND is the fan-out: margins, opacity and the mask move
// over 200ms ease-in-out both ways (AvatarStack.module.css:135-139).
AVATAR_STACK_EXPAND :: tok.Transition{200, {0.42, 0, 0.58, 1}}

// stack_overlap is how far avatar k (0-based) overlaps the one before it:
// 55% of the size for the second; for the third and later 85% in a
// cascade, 55% in a stack (avatar-stack.json layout overlap).
stack_overlap :: proc(v: Avatar_Stack_Variant, k: int, size: f32) -> f32 {
	if k >= 2 && v == .Cascade {
		return 0.85 * size
	}
	return 0.55 * size
}

// stack_opacity is avatar k's (0-based) opacity at rest: a cascade fades
// the third to fifth to 70, 55 and 40% (AvatarStack.module.css:203-221).
stack_opacity :: proc(v: Avatar_Stack_Variant, k: int) -> f32 {
	if v == .Stack || k < 2 {
		return 1
	}
	if k >= AVATAR_STACK_SHOWN {
		return 0
	}
	return 1 - 0.15 * f32(k)
}

// stack_offset is where avatar k (0-based) starts along a collapsed
// stack: each the size less its overlap after the one before. One past
// the fifth sits under the fifth.
stack_offset :: proc(v: Avatar_Stack_Variant, k: int, size: f32) -> (x: f32) {
	for i in 1 ..= min(k, AVATAR_STACK_SHOWN - 1) {
		x += size - stack_overlap(v, i, size)
	}
	return
}

// stack_width is a collapsed stack's width with n avatars: to the end of
// the last one drawn, at most the fifth. The CSS's min-width counts four
// and lets the fifth overhang what follows (avatar-stack.json notes);
// this reserves it.
stack_width :: proc(v: Avatar_Stack_Variant, n: int, size: f32) -> f32 {
	if n <= 0 {
		return 0
	}
	return stack_offset(v, min(n, AVATAR_STACK_SHOWN) - 1, size) + size
}

// Avatar_Stack_State is a stack's fan-out, 0 collapsed to 1 expanded, and
// the clock it moves on.
@(private)
Avatar_Stack_State :: struct {
	t:        f32,
	expanded: bool,
}

// avatar_stack is Primer's AvatarStack: avatars overlapping in a row, the
// first on top (primer-kit avatar-stack.json, AvatarStack.module.css). In
// a cascade the second overlaps the first by 55% of the size and the rest
// their predecessor by 85%, fading the third to fifth to 70, 55 and 40%;
// a stack overlaps 55% at full opacity. At most five show. Each avatar
// after the first has a disc 1px wider than the one before it cut out of
// it, so the page shows through a 1px gap. Hovered or keyboard-focused
// (unless disable_expand), the stack fans out over 200ms to every avatar
// side by side, 4px apart, at full opacity, laid over what follows it
// rather than pushing it; the cut-outs slide off as the avatars part.
// align_right anchors it at its right edge, overlapping leftwards.
//
// Departures: the stack reserves the fifth avatar's overhang, which the
// CSS's four-avatar min-width does not; a square stack is cut out like a
// round one, a rounded square 1px larger, where the web's square mask is
// invalid CSS and it falls back to a hard-coded white edge
// (avatar-stack.json notes); avatars are images, not interactive
// children, so the stack itself is the tab stop; a responsive size is not
// offered.
avatar_stack :: proc(
	gtx: ^ui.Ctx,
	avatars: []Avatar_Source,
	variant := Avatar_Stack_Variant.Cascade,
	size := AVATAR_SIZE,
	square := false,
	align_right := false,
	disable_expand := false,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) {
	p := ui.widget_open(gtx, key, loc)
	n := len(avatars)
	rest := stack_width(variant, n, size)
	sz := ui.constrain_min(gtx.constraints, {rest, size})
	c := control(gtx, p.id, {0, 0, rest, size}, state)
	t := advance_stack_expansion(gtx, p.id, c, disable_expand || n < 2)
	open := f32(n) * size + f32(max(n - 1, 0)) * tok.BASE_SIZE_4
	span := rest + (open - rest) * t
	origin := align_right ? sz.x - span : 0
	if t > 0 {
		// Fanned out it lies over what follows, so it draws, and is hit,
		// on top.
		ov := ui.overlay_open(gtx, {origin, (sz.y - size) / 2})
		paint_stack(gtx, avatars, variant, size, square, align_right, t, span)
		listen(gtx, c.st, p.id, ops.Rect{0, 0, span, size}, design.CLICK_KINDS)
		paint_focus_outline(gtx, c, {{0, 0, span, size}, avatar_radius(size, square)}, tok.FOCUS_OUTLINE_OFFSET)
		ui.overlay_close(&ov)
	} else {
		ops.transform_push(gtx.scene, ops.translate(origin, (sz.y - size) / 2))
		paint_stack(gtx, avatars, variant, size, square, align_right, 0, span)
		if !disable_expand {
			listen(gtx, c.st, p.id, ops.Rect{0, 0, span, size})
		}
		ops.transform_pop(gtx.scene)
	}
	box := ops.Rect{origin, (sz.y - size) / 2, rest, size}
	ops.tag(gtx.scene, p.id, "avatar stack", box)
	for a, i in avatars {
		if a.alt != "" && (i < AVATAR_STACK_SHOWN || t > 0) {
			ui.part_semantics(gtx, &p, ui.id_mix(p.id, u64(i) + 1), box, {role = .Image, label = ui.frame_string(gtx, a.alt)})
		}
	}
	ui.widget_close(gtx, &p, {sz, 0})
}

// advance_stack_expansion advances a stack's fan-out toward expanded while it is
// hovered or focused, eased over AVATAR_STACK_EXPAND, and returns it.
// A forced state paints that state's end: hovered or focused expanded.
@(private)
advance_stack_expansion :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, c: Control, disabled: bool) -> f32 {
	want := !disabled && !c.disabled && (c.hovered || c.focused)
	if c.st == nil {
		return want ? 1 : 0
	}
	s := ui.widget_data(gtx, id, Avatar_Stack_State)
	step := gtx.dt * 1000 / AVATAR_STACK_EXPAND.duration
	if want {
		s.t = min(s.t + step, 1)
	} else {
		s.t = max(s.t - step, 0)
	}
	if s.t > 0 && s.t < 1 {
		ui.request_frame(gtx)
	}
	return bezier_ease(AVATAR_STACK_EXPAND.easing, s.t)
}

// paint_stack draws the avatars at fan-out t, last first so the first
// lands on top, each from its collapsed to its expanded place, each after
// the first cut by a disc 1px wider than the avatar before it, centred
// on that avatar where it is now.
@(private)
paint_stack :: proc(gtx: ^ui.Ctx, avatars: []Avatar_Source, v: Avatar_Stack_Variant, size: f32, square, right: bool, t, span: f32) {
	n := len(avatars)
	shown := t > 0 ? n : min(n, AVATAR_STACK_SHOWN)
	place :: proc(v: Avatar_Stack_Variant, k: int, size, t, span: f32, right: bool) -> f32 {
		rest := stack_offset(v, k, size)
		open := f32(k) * (size + tok.BASE_SIZE_4)
		x := rest + (open - rest) * t
		return right ? span - size - x : x
	}
	for k := shown - 1; k >= 0; k -= 1 {
		x := place(v, k, size, t, span, right)
		box := ops.Rect{x, 0, size, size}
		alpha := stack_opacity(v, k) + (1 - stack_opacity(v, k)) * t
		if alpha <= 0 {
			continue
		}
		cut := k > 0
		if cut {
			px := place(v, k - 1, size, t, span, right)
			g := AVATAR_STACK_GAP
			hole := ops.Rect{px - g, -g, size + 2 * g, size + 2 * g}
			outer := ops.Rect{min(x, hole.x) - 1, hole.y - 1, max(x + size, hole.x + hole.w) - min(x, hole.x) + 2, hole.h + 2}
			ops.clip_push(gtx.scene, design.ring_path(gtx, outer, {}, hole, corners_all(avatar_radius(size, square) + g)))
		}
		paint_avatar(gtx, {avatars[k].src, box, square, alpha})
		if cut {
			ops.clip_pop(gtx.scene)
		}
	}
}
