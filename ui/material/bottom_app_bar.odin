package material

import "jm:ui"
import "jm:ui/ops"
import tok "jm:ui/material/tokens"

// Bottom_Bar_Arrangement is how a flexible bottom app bar spreads its
// actions (bottom-app-bar.json flexible-arrangements). The fixed bar
// always packs them at the start.
Bottom_Bar_Arrangement :: enum u8 {
	Space_Between, // pushed to the two ends, evenly apart; the flexible default
	Fixed_Centered, // centred, at most container-max-spacing apart
}

// BOTTOM_BAR_CONTENT_PADDING is the fixed bar's content padding, sized so a
// 48dp icon button's 24dp icon sits 16dp from the edge; hard-coded
// upstream (bottom-app-bar.json fixed-content-padding, AppBar.kt:2651-2652).
BOTTOM_BAR_CONTENT_PADDING :: f32(4)

// BOTTOM_BAR_FAB_PADDING is the fixed bar's FAB inset, horizontal and
// vertical, inside the content padding (bottom-app-bar.json
// fixed-fab-padding, AppBar.kt:2655-2656).
BOTTOM_BAR_FAB_PADDING :: [2]f32{12, 8}

// bottom_app_bar is M3's bottom app bar, deprecated in Expressive:
// replacedBy toolbar (a docked toolbar), per MDC. Full width (width, or
// the constraints), square, surface-container, actions as standard icon
// buttons.
//
// Fixed is 80dp with the actions packed from the start and an optional
// secondary-container FAB at the top end, overlapping nothing: there is
// no cradle. Flexible takes the docked toolbar's metrics, 64dp tall (or
// height), padded 16dp at the ends only, with the actions spread by
// arrangement and any FAB just the last of them.
//
// height_offset is the scroll behaviour's heightOffset, 0 to -height: the
// bar tracks scroll 1:1 and shows max(height + height_offset, 0), clipped
// from the bottom, so a fully hidden bar takes no space
// (bottom-app-bar.json live-height). The caller drives it from scroll.
// Neither bar draws a shadow: the fixed bar's level-2 token is dead and
// the flexible one reads the top app bar's level 0 (bottom-app-bar.json
// notes). A forced state applies to the first action. Returns the
// clicked action's index, TOOLBAR_FAB for the FAB, or -1.
bottom_app_bar :: proc(
	gtx: ^ui.Ctx,
	actions: []Icon,
	fab := Icon.None,
	flexible := false,
	arrangement := Bottom_Bar_Arrangement.Space_Between,
	height: f32 = 0,
	width: f32 = 0,
	height_offset: f32 = 0,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> int {
	p := ui.widget_open(gtx, key, loc)
	ui.semantics(gtx, &p, {role = .Toolbar})
	h := tok.BOTTOM_APP_BAR_CONTAINER_HEIGHT
	if flexible {
		h = height > 0 ? height : tok.DOCKED_TOOLBAR_CONTAINER_HEIGHT
	}
	w := width > 0 ? width : (gtx.constraints.max.x < ui.INF ? gtx.constraints.max.x : 412)
	shown := clamp(h + height_offset, 0, h)
	size := ui.constrain(gtx.constraints, {w, shown})
	w = size.x
	clicked := -1
	if shown <= 0 {
		ui.widget_close(gtx, &p, {size = size})
		return clicked
	}
	bar := ops.Rect{0, 0, w, h}
	// Clip to what shows; popped before widget_close, inside its transform.
	ops.clip_push(gtx.scene, ops.Rect{0, 0, w, shown})
	ops.fill(gtx.scene, rounded(gtx, bar, corners(tok.BOTTOM_APP_BAR_CONTAINER_SHAPE, bar)), color(tok.BOTTOM_APP_BAR_CONTAINER_COLOR))

	// The actions are standard icon buttons: no container of their own.
	col := Toolbar_Colors {
		container   = color(tok.BOTTOM_APP_BAR_CONTAINER_COLOR),
		content     = color(tok.STANDARD_ICON_BUTTON_COLOR),
		sel_content = color(tok.STANDARD_ICON_BUTTON_SELECTED_COLOR),
	}
	fab_d := tok.FAB_BASELINE_CONTAINER_WIDTH
	fab_c, fab_i := color(tok.FAB_SECONDARY_CONTAINER_CONTAINER_COLOR), color(tok.FAB_SECONDARY_CONTAINER_ICON_COLOR)
	fab_st := state
	if state != .Live && state != .Disabled {
		fab_st = .Enabled // the forced state is the first action's
	}
	n := len(actions)
	y := (h - ACTION_SLOT) / 2

	if !flexible {
		x := BOTTOM_BAR_CONTENT_PADDING
		for g, i in actions {
			if toolbar_action(gtx, ui.id_mix(p.id, u64(i)), {x, y, ACTION_SLOT, ACTION_SLOT}, g, false, col, action_state(state, i, 0), 1, &p) {
				clicked = i
			}
			x += ACTION_SLOT
		}
		if fab != .None {
			// Top-start in a box at the row's end, inset so the FAB's own
			// margins net out (AppBar.kt:2655-2656).
			pad := BOTTOM_BAR_FAB_PADDING
			fr := ops.Rect{w - BOTTOM_BAR_CONTENT_PADDING - pad[0] - fab_d, BOTTOM_BAR_CONTENT_PADDING + pad[1], fab_d, fab_d}
			if paint_fab_at(gtx, ui.id_mix(p.id, 0xfab), fr, tok.FAB_BASELINE_CONTAINER_SHAPE.radii[0], fab, tok.FAB_BASELINE_ICON_SIZE, fab_c, fab_i, tok.FAB_SECONDARY_CONTAINER_CONTAINER_ELEVATION, fab_st, &p) {
				clicked = TOOLBAR_FAB
			}
		}
		ops.clip_pop(gtx.scene)
		ui.widget_close(gtx, &p, {size = size})
		return clicked
	}

	// Flexible: the FAB, if any, is one more item at the row's end.
	items := n + (fab != .None ? 1 : 0)
	ext := proc(i, n: int, fab_d: f32) -> f32 {
		return i < n ? ACTION_SLOT : fab_d
	}
	run: f32
	for i in 0 ..< items {
		run += ext(i, n, fab_d)
	}
	inner := w - tok.DOCKED_TOOLBAR_CONTAINER_LEADING_SPACE - tok.DOCKED_TOOLBAR_CONTAINER_TRAILING_SPACE
	g: f32
	x := tok.DOCKED_TOOLBAR_CONTAINER_LEADING_SPACE
	if items > 1 {
		g = max((inner - run) / f32(items - 1), 0)
	}
	switch arrangement {
	case .Space_Between:
		if items == 1 {
			x += (inner - run) / 2
		}
	case .Fixed_Centered:
		// At most 32dp apart (AppBar.kt:2359-2361), the group centred.
		g = min(g, tok.DOCKED_TOOLBAR_CONTAINER_MAX_SPACING)
		x += (inner - run - g * f32(max(items - 1, 0))) / 2
	}
	for i in 0 ..< items {
		e := ext(i, n, fab_d)
		if i < n {
			if toolbar_action(gtx, ui.id_mix(p.id, u64(i)), {x, y, ACTION_SLOT, ACTION_SLOT}, actions[i], false, col, action_state(state, i, 0), 1, &p) {
				clicked = i
			}
		} else {
			fr := ops.Rect{x, (h - fab_d) / 2, fab_d, fab_d}
			if paint_fab_at(gtx, ui.id_mix(p.id, 0xfab), fr, tok.FAB_BASELINE_CONTAINER_SHAPE.radii[0], fab, tok.FAB_BASELINE_ICON_SIZE, fab_c, fab_i, tok.FAB_SECONDARY_CONTAINER_CONTAINER_ELEVATION, fab_st, &p) {
				clicked = TOOLBAR_FAB
			}
		}
		x += e + g
	}
	ops.clip_pop(gtx.scene)
	ui.widget_close(gtx, &p, {size = size})
	return clicked
}
