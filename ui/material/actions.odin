package material

import "core:reflect"
import "jm:ui/ops"
import "jm:ui"
import tok "jm:ui/material/tokens"

// M3 Expressive's actions: button groups, toolbars and the FAB menu, each
// built from its m3e-kit spec (components/button-group.json, toolbar.json,
// fab-menu.json), which cite Compose's ButtonGroup.kt, FloatingToolbar.kt
// and FloatingActionButtonMenu.kt.
//
// Keyboard: jm:ui focuses an area only on a press and has no Tab
// traversal or programmatic focus, so the specs' focus rules (a
// single-select group as one Tab stop moved by arrows, the FAB menu
// trapping Tab into its items) cannot be built here; Enter and Space
// activate whatever is focused, as for every other component.

// Group_Style is the colour token group a button group's children read:
// the group itself has no colours (button-group.json anatomy).
Group_Style :: enum u8 {
	Filled, // comp.filled-button: surface-container unselected, primary selected
	Tonal, // comp.tonal-button: secondary-container unselected, secondary selected
}

// GROUP_EXPANDED_RATIO is how much of its own width a pressed child
// grows by, taken from its neighbours (button-group.json layout,
// ButtonGroup.kt:718-762).
GROUP_EXPANDED_RATIO :: f32(0.15)

// GROUP_MAX :: the most children a button group lays out, so its per-child
// scratch lives on the stack.
GROUP_MAX :: 16

// button_group is M3 Expressive's button group: a row of small buttons
// that squeeze their neighbours when pressed. Standard children keep
// their own toggle-button shape (round, square once selected, tighter
// while pressed) 12dp apart; connected children sit 2dp apart as one
// pill, with full outer corners, 8dp inner ones and a full circle once
// selected. Every shape change springs (fast-spatial).
//
// selected is caller-owned, one bool per label; nil makes the children
// plain action buttons. single makes a click select only that child.
// icons, disabled and weights are per child and optional; an empty label
// with an icon is an icon-only child. With width > 0 the row is that wide
// and weighted children share what the unweighted ones leave. With
// overflow non-nil and too little room, children from the end move into
// a menu behind a "More options" icon button, open while overflow^.
//
// A forced Hovered, Focused or Pressed applies to the second child (the
// first when alone), as a pointer would, so the neighbour squeeze shows;
// a forced Disabled applies to every child. Returns the clicked index, or -1.
button_group :: proc(
	gtx: ^ui.Ctx,
	labels: []string,
	selected: []bool,
	connected := false,
	single := true,
	icons: []Icon = nil,
	style := Group_Style.Filled,
	disabled: []bool = nil,
	weights: []f32 = nil,
	width: f32 = 0,
	expanded_ratio := GROUP_EXPANDED_RATIO,
	overflow: ^bool = nil,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> int {
	p := ui.widget_open(gtx, key, loc)
	ui.semantics(gtx, &p, {role = .Group})
	toggles := selected != nil
	n := min(toggles ? min(len(labels), len(selected)) : len(labels), GROUP_MAX)
	// The group's height tokens are dead (button-group.json notes): the
	// children are small buttons, so the row is their height.
	H :: tok.BUTTON_SMALL_CONTAINER_HEIGHT
	gap := connected ? tok.CONNECTED_BUTTON_GROUP_SMALL_BETWEEN_SPACE : tok.BUTTON_GROUP_SMALL_BETWEEN_SPACE

	texts: [GROUP_MAX]Text
	base: [GROUP_MAX]f32 // intrinsic width
	limit: [GROUP_MAX]f32 // how far a neighbour's press may compress it: its end padding (ButtonGroup.kt:1089-1101)
	for i in 0 ..< n {
		g := len(icons) > i ? icons[i] : .None
		if labels[i] == "" && g != .None {
			base[i] = tok.SMALL_ICON_BUTTON_DEFAULT_LEADING_SPACE + tok.SMALL_ICON_BUTTON_ICON_SIZE + tok.SMALL_ICON_BUTTON_DEFAULT_TRAILING_SPACE
			limit[i] = tok.SMALL_ICON_BUTTON_DEFAULT_TRAILING_SPACE
			continue
		}
		texts[i] = shape_text(gtx, labels[i], .Label_Large)
		base[i] = tok.BUTTON_SMALL_LEADING_SPACE + texts[i].width + tok.BUTTON_SMALL_TRAILING_SPACE
		if g != .None {
			base[i] += tok.BUTTON_SMALL_ICON_SIZE + tok.BUTTON_SMALL_ICON_LABEL_SPACE
		}
		limit[i] = tok.BUTTON_SMALL_TRAILING_SPACE
	}

	// Overflow: reserve the indicator, then drop children from the end
	// until the rest fit (ButtonGroup.kt:673-706).
	avail := width > 0 ? width : gtx.constraints.max.x
	shown := n
	ind_w: f32 = tok.SMALL_ICON_BUTTON_CONTAINER_HEIGHT // a default-width small icon button is square
	if overflow != nil && avail < ui.INF {
		total: f32
		for i in 0 ..< n {
			total += base[i] + (i > 0 ? gap : 0)
		}
		if total > avail {
			used := ind_w
			shown = 0
			for i in 0 ..< n {
				if used + base[i] + gap > avail {
					break
				}
				used += base[i] + gap
				shown += 1
			}
		}
	}
	has_ind := shown < n

	// Weighted children share what the rest leave (ButtonGroup.kt:826-836).
	if width > 0 && len(weights) > 0 {
		rigid := f32(max(shown - 1, 0)) * gap + (has_ind ? ind_w + gap : 0)
		sum: f32
		for i in 0 ..< shown {
			if len(weights) > i && weights[i] > 0 {
				sum += weights[i]
			} else {
				rigid += base[i]
			}
		}
		if sum > 0 {
			for i in 0 ..< shown {
				if len(weights) > i && weights[i] > 0 {
					base[i] = max(width - rigid, 0) * weights[i] / sum
				}
			}
		}
	}

	// The pressed child grows into its neighbours, each giving up at most
	// its own end padding; a middle child takes half the ratio from each
	// side (ButtonGroup.kt:718-762). Live reads last frame's press, which
	// this frame's events may have ended: a frame late, like all input.
	pi := -1
	child_state :: proc(state: Interaction, i, shown: int, disabled: []bool) -> Interaction {
		if len(disabled) > i && disabled[i] {
			return .Disabled
		}
		switch state {
		case .Hovered, .Focused, .Pressed, .Dragged:
			return i == min(1, shown - 1) ? state : .Enabled
		case .Live, .Enabled, .Disabled:
		}
		return state
	}
	for i in 0 ..< shown {
		cs := child_state(state, i, shown, disabled)
		if cs == .Pressed || (cs == .Live && ui.widget_state(gtx, ui.id_mix(p.id, u64(i))).pressed) {
			pi = i
		}
	}
	delta: [GROUP_MAX]f32
	if pi >= 0 && shown > 1 {
		edge := pi == 0 || pi == shown - 1
		share := expanded_ratio * base[pi] * (edge ? 1 : 0.5)
		if pi > 0 {
			g := min(share, limit[pi - 1])
			delta[pi] += g
			delta[pi - 1] -= g
		}
		if pi < shown - 1 {
			g := min(share, limit[pi + 1])
			delta[pi] += g
			delta[pi + 1] -= g
		}
	}

	changed := -1
	x: f32
	for i in 0 ..< shown {
		id := ui.id_mix(p.id, u64(i))
		cs := child_state(state, i, shown, disabled)
		// Width springs toward its press target (fast-spatial, ButtonGroup.kt:138).
		w := base[i] + delta[i]
		if cs == .Live {
			st := ui.widget_state(gtx, id)
			w = base[i] + ui.spring_update(&st.springs[0], gtx, delta[i], spring_params(.Fast_Spatial), 0.1)
		}
		w = max(w, 0)
		r := ops.Rect{x, 0, w, H}
		// The hit area is at least 48dp tall, centred on the button (foundations touchTarget).
		hit := ops.Rect{x, (H - 48) / 2, w, 48}
		c := control(gtx, id, hit, cs)
		if c.clicked {
			changed = i
			if toggles {
				if single {
					for j in 0 ..< n {
						selected[j] = j == i
					}
				} else {
					selected[i] = !selected[i]
				}
			}
		}
		on := toggles && selected[i]
		sel_t := animate(gtx, c, 1, on ? 1 : 0, .Fast_Spatial)
		press_t := animate(gtx, c, 2, c.pressed ? 1 : 0, .Fast_Spatial)
		col_t := animate(gtx, c, 3, on ? 1 : 0, .Fast_Effects)

		k := lerp_corners(lerp_corners(group_rest_corners(r, i, shown, connected), group_selected_corners(r, connected), sel_t), group_pressed_corners(r, i, shown, connected), press_t)
		shape := rounded(gtx, r, k)
		container, content := group_colors(style, toggles, col_t, c.disabled)
		ops.fill(gtx.scene, shape, container)
		paint_state_layer(gtx, c, shape, content)

		g := len(icons) > i ? icons[i] : .None
		cw := texts[i].width
		isz := labels[i] == "" ? tok.SMALL_ICON_BUTTON_ICON_SIZE : tok.BUTTON_SMALL_ICON_SIZE
		if g != .None {
			cw += isz + (labels[i] == "" ? 0 : tok.BUTTON_SMALL_ICON_LABEL_SPACE)
		}
		tx := r.x + (r.w - cw) / 2 // a widened or squeezed child keeps its content centred
		if g != .None {
			icon(gtx, g, {tx, (H - isz) / 2}, isz, content)
			tx += isz + tok.BUTTON_SMALL_ICON_LABEL_SPACE
		}
		if labels[i] != "" {
			draw_text(gtx, texts[i], {tx, (H - texts[i].height) / 2}, content)
		}
		paint_focus_ring_corners(gtx, c, r, k, inward = connected)
		listen(gtx, c, id, hit)
		name := labels[i]
		if name == "" {
			name, _ = reflect.enum_name_from_value(g)
		}
		ops.tag(gtx.scene, id, ui.frame_string(gtx, name))
		ui.part_semantics(gtx, &p, id, r, {role = .Button, label = name, states = states_of(c, on)})
		x += w + gap
	}

	if has_ind {
		// The overflow indicator: a filled icon button with a "more" glyph
		// (button-group.json anatomy), opening a menu of the rest.
		id := ui.id_mix(p.id, 0xff)
		r := ops.Rect{x, 0, ind_w, H}
		hit := ops.Rect{x, (H - 48) / 2, ind_w, 48}
		c := control(gtx, id, hit, state == .Disabled ? .Disabled : .Live)
		if c.clicked {
			overflow^ = !overflow^
		}
		rr := ops.Round_Rect{r, H / 2}
		container := c.disabled ? ops.with_alpha(color(tok.FILLED_ICON_BUTTON_DISABLED_CONTAINER_COLOR), tok.FILLED_ICON_BUTTON_DISABLED_CONTAINER_OPACITY) : color(tok.FILLED_ICON_BUTTON_CONTAINER_COLOR)
		content := c.disabled ? ops.with_alpha(color(tok.FILLED_ICON_BUTTON_DISABLED_COLOR), tok.FILLED_ICON_BUTTON_DISABLED_OPACITY) : color(tok.FILLED_ICON_BUTTON_COLOR)
		ops.fill(gtx.scene, rr, container)
		paint_state_layer(gtx, c, rr, content)
		isz := tok.SMALL_ICON_BUTTON_ICON_SIZE
		icon(gtx, .More_Vert, {r.x + (ind_w - isz) / 2, (H - isz) / 2}, isz, content)
		paint_focus_ring(gtx, c, rr)
		listen(gtx, c, id, hit)
		ops.tag(gtx.scene, id, "More options")
		ui.part_semantics(gtx, &p, id, r, {role = .Button, label = "More options", states = states_of(c) + {.Expandable} + (overflow^ ? {.Expanded} : {})})
		x += ind_w + gap

		items := make([]Menu_Item, n - shown, gtx.allocator)
		for j in shown ..< n {
			items[j - shown] = {label = labels[j], leading = len(icons) > j ? icons[j] : .None, disabled = len(disabled) > j && disabled[j]}
			if toggles && selected[j] {
				items[j - shown].leading = .Check
			}
		}
		if picked := menu(gtx, overflow, items, offset = {r.x, H + 4}, key = u64(p.id)); picked >= 0 {
			i := shown + picked
			changed = i
			if toggles {
				if single {
					for j in 0 ..< n {
						selected[j] = j == i
					}
				} else {
					selected[i] = !selected[i]
				}
			}
		}
	}

	natural := ops.Size{max(x - gap, 0), H}
	if width > 0 {
		natural.x = width
	}
	ui.widget_close(gtx, &p, {size = ui.constrain_min(gtx.constraints, natural)})
	return changed
}

// group_rest_corners is child i of shown at rest. A standard child keeps
// its own round shape; a connected one is full on the row's outer edge,
// inner-corner-corner-size facing a neighbour, and sys.shape.corner.small
// all round in the middle (ButtonGroup.kt:196-266; button-group.json notes
// why not the md's inner size).
@(private)
group_rest_corners :: proc(r: ops.Rect, i, shown: int, connected: bool) -> Corners {
	full := min(r.w, r.h) / 2
	if !connected || shown == 1 {
		return corners(tok.BUTTON_SMALL_CONTAINER_SHAPE_ROUND, r)
	}
	in_ := tok.CONNECTED_BUTTON_GROUP_SMALL_INNER_CORNER_CORNER_SIZE
	switch i {
	case 0:
		return {full, in_, in_, full}
	case shown - 1:
		return {in_, full, full, in_}
	}
	return corners(tok.SYS_SHAPE_CORNER_SMALL, r)
}

// group_pressed_corners is child i while pressed: a standard child takes
// its button's pressed shape; a connected one swaps only its inward
// corners to pressed-inner-corner-corner-size (ButtonGroup.kt:205-266).
@(private)
group_pressed_corners :: proc(r: ops.Rect, i, shown: int, connected: bool) -> Corners {
	if !connected || shown == 1 {
		return corners(tok.BUTTON_SMALL_PRESSED_CONTAINER_SHAPE, r)
	}
	full := min(r.w, r.h) / 2
	in_ := tok.CONNECTED_BUTTON_GROUP_SMALL_PRESSED_INNER_CORNER_CORNER_SIZE
	switch i {
	case 0:
		return {full, in_, in_, full}
	case shown - 1:
		return {in_, full, full, in_}
	}
	return corners_all(in_)
}

// group_selected_corners is a selected child: a standard toggle squares
// off to its selected shape; a connected one goes fully round, a
// hard-coded 50% rather than the dead selected-inner-corner-corner-size-
// percent token (button-group.json states, ButtonGroup.kt:240).
@(private)
group_selected_corners :: proc(r: ops.Rect, connected: bool) -> Corners {
	if connected {
		return corners_all(min(r.w, r.h) / 2)
	}
	return corners(tok.BUTTON_SMALL_SELECTED_CONTAINER_SHAPE_SQUARE, r)
}

// group_colors is a child's container and content at selection progress
// t (0 unselected, 1 selected). A non-toggle child uses its style's plain
// action colours.
@(private)
group_colors :: proc(style: Group_Style, toggles: bool, t: f32, disabled: bool) -> (container, content: ops.Color) {
	switch style {
	case .Filled:
		if disabled {
			return ops.with_alpha(color(tok.FILLED_BUTTON_DISABLED_CONTAINER_COLOR), tok.FILLED_BUTTON_DISABLED_CONTAINER_OPACITY), ops.with_alpha(color(tok.FILLED_BUTTON_DISABLED_LABEL_TEXT_COLOR), tok.FILLED_BUTTON_DISABLED_LABEL_TEXT_OPACITY)
		}
		if !toggles {
			return color(tok.FILLED_BUTTON_CONTAINER_COLOR), color(tok.FILLED_BUTTON_LABEL_TEXT_COLOR)
		}
		container = ops.mix(color(tok.FILLED_BUTTON_UNSELECTED_CONTAINER_COLOR), color(tok.FILLED_BUTTON_SELECTED_CONTAINER_COLOR), t)
		content = ops.mix(color(tok.FILLED_BUTTON_LABEL_TEXT_UNSELECTED_COLOR), color(tok.FILLED_BUTTON_LABEL_TEXT_SELECTED_COLOR), t)
	case .Tonal:
		if disabled {
			return ops.with_alpha(color(tok.TONAL_BUTTON_DISABLED_CONTAINER_COLOR), tok.TONAL_BUTTON_DISABLED_CONTAINER_OPACITY), ops.with_alpha(color(tok.TONAL_BUTTON_DISABLED_LABEL_TEXT_COLOR), tok.TONAL_BUTTON_DISABLED_LABEL_TEXT_OPACITY)
		}
		if !toggles {
			return color(tok.TONAL_BUTTON_CONTAINER_COLOR), color(tok.TONAL_BUTTON_LABEL_TEXT_COLOR)
		}
		container = ops.mix(color(tok.TONAL_BUTTON_UNSELECTED_CONTAINER_COLOR), color(tok.TONAL_BUTTON_SELECTED_CONTAINER_COLOR), t)
		content = ops.mix(color(tok.TONAL_BUTTON_UNSELECTED_LABEL_TEXT_COLOR), color(tok.TONAL_BUTTON_SELECTED_LABEL_TEXT_COLOR), t)
	}
	return
}

// Toolbar_Kind picks M3 Expressive's toolbar forms: docked (full width,
// square) or floating (a pill), each in standard or vibrant colours.
Toolbar_Kind :: enum u8 {
	Docked, // comp.docked-toolbar, surface-container
	Floating, // comp.floating-toolbar standard, surface-container
	Floating_Vibrant, // comp.floating-toolbar vibrant, primary-container
	Docked_Vibrant, // comp.docked-toolbar with the floating toolbar's vibrant colours
}

// TOOLBAR_FAB is what toolbar and bottom_app_bar return when their FAB,
// not an action, was clicked.
TOOLBAR_FAB :: -2

// TOOLBAR_FAB_GAP is the space between a floating toolbar and its paired
// FAB: hard-coded upstream, not a token (toolbar.json floating-fab-gap,
// FloatingToolbar.kt:1160).
TOOLBAR_FAB_GAP :: f32(8)

// ACTION_SLOT is one toolbar action's slot: a small icon button's 40dp
// visual inside its 48dp touch target (foundations touchTarget).
@(private)
ACTION_SLOT :: MIN_TOUCH

// toolbar is M3 Expressive's toolbar: actions as small icon buttons,
// the selected one squaring off from a circle (fast-spatial).
//
// Docked spans width (or the constraints) at 64dp, square, the actions
// centred with a gap between container-min-spacing and -max-spacing.
// Floating is a 64dp pill, actions container-between-space apart,
// horizontal or vertical. Floating toolbars expand and collapse on
// expanded, a fast-spatial spring: the first leading and last trailing
// actions show only while expanded. With fab set, a paired FAB sits
// TOOLBAR_FAB_GAP after the toolbar (before it with fab_leading): as the
// toolbar collapses away the FAB grows from baseline to medium, and back.
//
// Floating elevation is level 0: Compose's defaults are literally Level0
// pending tokens (toolbar.json notes); the vibrant or tonal container is
// what sets it apart. A forced state applies to the selected action (the
// first when none), as a pointer would. Returns the clicked action's
// index, TOOLBAR_FAB for the FAB, or -1.
toolbar :: proc(
	gtx: ^ui.Ctx,
	actions: []Icon,
	kind := Toolbar_Kind.Floating,
	selected := -1,
	width: f32 = 0,
	key: u64 = 0,
	vertical := false,
	expanded := true,
	leading := 0,
	trailing := 0,
	fab := Icon.None,
	fab_leading := false,
	state := Interaction.Live,
	loc := #caller_location,
) -> int {
	p := ui.widget_open(gtx, key, loc)
	ui.semantics(gtx, &p, {role = .Toolbar})
	n := len(actions)
	docked := kind == .Docked || kind == .Docked_Vibrant
	vibrant := kind == .Floating_Vibrant || kind == .Docked_Vibrant
	col := toolbar_colors(vibrant, docked)

	// One 0..1 expand progress drives the side groups, the toolbar's size
	// and the paired FAB together (toolbar.json states, FloatingToolbar.kt:693-696).
	e: f32 = 1
	if !docked {
		tc := Control{st = state == .Live ? ui.widget_state(gtx, p.id) : nil}
		e = animate(gtx, tc, 0, expanded ? 1 : 0, .Fast_Spatial)
	}
	shown := clamp(e, 0, 1)
	forced := selected >= 0 && selected < n ? selected : 0
	clicked := -1

	if docked {
		DH :: tok.DOCKED_TOOLBAR_CONTAINER_HEIGHT
		w := width > 0 ? width : (gtx.constraints.max.x < ui.INF ? gtx.constraints.max.x : 412)
		size := ui.constrain(gtx.constraints, {w, DH})
		ops.fill(gtx.scene, rounded(gtx, {0, 0, size.x, DH}, corners(tok.DOCKED_TOOLBAR_CONTAINER_SHAPE, {0, 0, size.x, DH})), col.container)
		inner := size.x - tok.DOCKED_TOOLBAR_CONTAINER_LEADING_SPACE - tok.DOCKED_TOOLBAR_CONTAINER_TRAILING_SPACE
		g := tok.DOCKED_TOOLBAR_CONTAINER_MIN_SPACING
		if n > 1 {
			g = clamp((inner - f32(n) * ACTION_SLOT) / f32(n - 1), tok.DOCKED_TOOLBAR_CONTAINER_MIN_SPACING, tok.DOCKED_TOOLBAR_CONTAINER_MAX_SPACING)
		}
		run := f32(n) * ACTION_SLOT + f32(max(n - 1, 0)) * g
		x := tok.DOCKED_TOOLBAR_CONTAINER_LEADING_SPACE + (inner - run) / 2
		for g_, i in actions {
			st := action_state(state, i, forced)
			if toolbar_action(gtx, ui.id_mix(p.id, u64(i)), {x, (DH - ACTION_SLOT) / 2, ACTION_SLOT, ACTION_SLOT}, g_, i == selected, col, st, 1, &p) {
				clicked = i
			}
			x += ACTION_SLOT + g
		}
		ui.widget_close(gtx, &p, {size = size})
		return clicked
	}

	// Floating: lay the pill out along its main axis.
	H :: tok.FLOATING_TOOLBAR_CONTAINER_HEIGHT
	lead := tok.FLOATING_TOOLBAR_CONTAINER_LEADING_SPACE
	trail := tok.FLOATING_TOOLBAR_CONTAINER_TRAILING_SPACE
	between := tok.FLOATING_TOOLBAR_CONTAINER_BETWEEN_SPACE
	// Each action's main-axis extent: a side-group action shrinks away as
	// the toolbar collapses; with a FAB the whole toolbar does.
	ext :: proc(i, n, leading, trailing: int, shown: f32, with_fab: bool) -> f32 {
		if with_fab || i < leading || i >= n - trailing {
			return shown
		}
		return 1
	}
	with_fab := fab != .None
	run: f32
	for i in 0 ..< n {
		run += (ACTION_SLOT + (i > 0 ? between : 0)) * ext(i, n, leading, trailing, shown, with_fab)
	}
	bar_len := (lead + run + trail) * (with_fab ? shown : 1)
	// The FAB's diameter goes from baseline (expanded) to medium
	// (collapsed) on the same progress (FloatingToolbar.kt:1153,1631-1639).
	fab_d: f32
	if with_fab {
		fab_d = tok.FAB_MEDIUM_CONTAINER_WIDTH + (tok.FAB_BASELINE_CONTAINER_WIDTH - tok.FAB_MEDIUM_CONTAINER_WIDTH) * e
	}
	cross := max(H, fab_d)
	main_len := bar_len + (with_fab ? TOOLBAR_FAB_GAP * shown + fab_d : 0)
	size := vertical ? ops.Size{cross, main_len} : ops.Size{main_len, cross}
	size = ui.constrain_min(gtx.constraints, size)

	// at maps a main-axis offset and cross-axis offset to a point.
	at :: proc(vertical: bool, main, cross: f32) -> ops.Point {
		return vertical ? {cross, main} : {main, cross}
	}
	bar0: f32 = with_fab && fab_leading ? fab_d + TOOLBAR_FAB_GAP * shown : 0
	cross0 := (cross - H) / 2
	if bar_len > 0.5 {
		o := at(vertical, bar0, cross0)
		sz := at(vertical, bar_len, H)
		br := ops.Rect{o.x, o.y, sz.x, sz.y}
		pill := rounded(gtx, br, corners(tok.FLOATING_TOOLBAR_CONTAINER_SHAPE, br))
		ops.fill(gtx.scene, pill, col.container)
		// The container clips its content while it resizes (toolbar.json
		// floating-shape-fixed: only its size animates).
		ops.clip_push(gtx.scene, pill)
		m := bar0 + lead * (with_fab ? shown : 1)
		for g_, i in actions {
			k := ext(i, n, leading, trailing, shown, with_fab)
			if i > 0 {
				m += between * k
			}
			if k > 0.01 {
				// A shrinking action stays centred in its shrinking slot.
				ao := at(vertical, m - ACTION_SLOT * (1 - k) / 2, cross0 + (H - ACTION_SLOT) / 2)
				st := action_state(state, i, forced)
				if toolbar_action(gtx, ui.id_mix(p.id, u64(i)), {ao.x, ao.y, ACTION_SLOT, ACTION_SLOT}, g_, i == selected, col, st, k, &p) {
					clicked = i
				}
			}
			m += ACTION_SLOT * k
		}
		ops.clip_pop(gtx.scene)
	}
	if with_fab {
		f0: f32 = fab_leading ? 0 : bar_len + TOOLBAR_FAB_GAP * shown
		fo := at(vertical, f0, (cross - fab_d) / 2)
		// The paired FAB is primary-container on a standard toolbar and
		// tertiary-container on a vibrant one: not toolbar tokens
		// (toolbar.json fab-colour, FloatingToolbar.kt:1113-1140).
		fc, fi := color(tok.FAB_PRIMARY_CONTAINER_CONTAINER_COLOR), color(tok.FAB_PRIMARY_CONTAINER_ICON_COLOR)
		if vibrant {
			fc, fi = color(.Tertiary_Container), color(.On_Tertiary_Container)
		}
		isz := tok.FAB_MEDIUM_ICON_SIZE + (tok.FAB_BASELINE_ICON_SIZE - tok.FAB_MEDIUM_ICON_SIZE) * e
		// The FAB keeps baseline's corner: only its size animates.
		fr := ops.Rect{fo.x, fo.y, fab_d, fab_d}
		if paint_fab_at(gtx, ui.id_mix(p.id, 0xfab), fr, tok.FAB_BASELINE_CONTAINER_SHAPE.radii[0], fab, isz, fc, fi, tok.FAB_PRIMARY_CONTAINER_CONTAINER_ELEVATION, state == .Disabled ? .Disabled : .Live, &p) {
			clicked = TOOLBAR_FAB
		}
	}
	ui.widget_close(gtx, &p, {size = size})
	return clicked
}

// action_state is action i's state when state is forced on the toolbar:
// Hovered, Focused and Pressed land on the forced action only, as a
// pointer would; Disabled on all; Live stays live.
@(private)
action_state :: proc(state: Interaction, i, forced: int) -> Interaction {
	#partial switch state {
	case .Hovered, .Focused, .Pressed, .Dragged:
		return i == forced ? state : .Enabled
	}
	return state
}

// Toolbar_Colors are a toolbar's container and its actions' colours.
@(private)
Toolbar_Colors :: struct {
	container, content, sel_container, sel_content: ops.Color,
}

// toolbar_colors picks standard or vibrant. Vibrant reads the floating
// toolbar's vibrant-* tokens, which the docked toolbar lacks (toolbar.json
// docked-behaviour: the same two-scheme pattern). Standard's content is
// on-surface, the on-colour of its surface-container, and its selected
// action takes secondary-container: toolbar.json names no standard
// selected tokens, so this follows the vibrant triad's pattern of a
// contrasting container.
@(private)
toolbar_colors :: proc(vibrant, docked: bool) -> Toolbar_Colors {
	if vibrant {
		return {
			color(tok.FLOATING_TOOLBAR_VIBRANT_CONTAINER_COLOR),
			color(tok.FLOATING_TOOLBAR_VIBRANT_BUTTON_UNSELECTED_ICON_COLOR),
			color(tok.FLOATING_TOOLBAR_VIBRANT_BUTTON_SELECTED_CONTAINER_COLOR),
			color(tok.FLOATING_TOOLBAR_VIBRANT_BUTTON_SELECTED_ICON_COLOR),
		}
	}
	return {
		color(docked ? tok.DOCKED_TOOLBAR_CONTAINER_COLOR : tok.FLOATING_TOOLBAR_STANDARD_CONTAINER_COLOR),
		color(.On_Surface),
		color(.Secondary_Container),
		color(.On_Secondary_Container),
	}
}

// toolbar_action is one toolbar or bottom-bar action: a small icon button
// centred in slot (its touch target). Selected, it fills a container that
// squares from a circle to the small icon button's selected shape; pressed,
// it tightens to the pressed shape; both spring (fast-spatial), the
// colour fades (fast-effects). alpha fades the whole action, for one
// entering or leaving. Returns true on the frame it is clicked.
@(private)
toolbar_action :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, slot: ops.Rect, g: Icon, selected: bool, col: Toolbar_Colors, state: Interaction, alpha: f32, p: ^ui.Placement) -> bool {
	c := control(gtx, id, slot, state)
	sel_t := animate(gtx, c, 0, selected ? 1 : 0, .Fast_Spatial)
	press_t := animate(gtx, c, 1, c.pressed ? 1 : 0, .Fast_Spatial)
	fill_t := animate(gtx, c, 2, selected ? 1 : 0, .Fast_Effects)
	v := tok.SMALL_ICON_BUTTON_CONTAINER_HEIGHT
	r := ops.Rect{slot.x + (slot.w - v) / 2, slot.y + (slot.h - v) / 2, v, v}
	k := lerp_corners(lerp_corners(corners(tok.SMALL_ICON_BUTTON_CONTAINER_SHAPE_ROUND, r), corners(tok.SMALL_ICON_BUTTON_SELECTED_CONTAINER_SHAPE_ROUND, r), sel_t), corners(tok.SMALL_ICON_BUTTON_PRESSED_CONTAINER_SHAPE, r), press_t)
	shape := rounded(gtx, r, k)
	a := clamp(alpha, 0, 1)
	content := ops.mix(col.content, col.sel_content, fill_t)
	if c.disabled {
		content = ops.with_alpha(color(tok.STANDARD_ICON_BUTTON_DISABLED_COLOR), tok.STANDARD_ICON_BUTTON_DISABLED_OPACITY)
	} else if fill_t > 0 {
		ops.fill(gtx.scene, shape, fade(col.sel_container, fill_t * a))
	}
	paint_state_layer(gtx, c, shape, content)
	isz := tok.SMALL_ICON_BUTTON_ICON_SIZE
	icon(gtx, g, {r.x + (v - isz) / 2, r.y + (v - isz) / 2}, isz, fade(content, a))
	paint_focus_ring_corners(gtx, c, r, k, inward = true)
	listen(gtx, c, id, slot)
	name, _ := reflect.enum_name_from_value(g)
	ops.tag(gtx.scene, id, name)
	ui.part_semantics(gtx, p, id, slot, {role = .Button, label = name, states = states_of(c, selected)})
	return c.clicked
}

// paint_fab_at draws a FAB in r (its corner radius, icon at isz) with its
// own hit area there, for components that place a FAB themselves rather
// than lay one out. elevation_dp is its container-elevation token.
// Returns true on the frame it is clicked.
@(private)
paint_fab_at :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, r: ops.Rect, radius: f32, g: Icon, isz: f32, container, content: ops.Color, elevation_dp: f32, state: Interaction, p: ^ui.Placement) -> bool {
	c := control(gtx, id, r, state)
	rr := ops.Round_Rect{r, min(radius, min(r.w, r.h) / 2)}
	paint_elevation(gtx, rr, elevation_level(elevation_dp))
	ops.fill(gtx.scene, rr, container)
	paint_state_layer(gtx, c, rr, content)
	icon(gtx, g, {r.x + (r.w - isz) / 2, r.y + (r.h - isz) / 2}, isz, content)
	paint_focus_ring(gtx, c, rr)
	listen(gtx, c, id, r)
	name, _ := reflect.enum_name_from_value(g)
	ops.tag(gtx.scene, id, name)
	ui.part_semantics(gtx, p, id, r, {role = .Button, label = name, states = states_of(c)})
	return c.clicked
}

// Fab_Menu_Item is one of a FAB menu's actions.
Fab_Menu_Item :: struct {
	label: string,
	icon:  Icon,
}

// Fab_Menu_Size is the FAB menu trigger's closed size.
Fab_Menu_Size :: enum u8 {
	Baseline, // comp.fab-baseline, 56dp
	Medium, // comp.fab-medium, 80dp
	Large, // comp.fab-large, 96dp
}

// fab_menu is M3 Expressive's FAB menu. One open progress (fast-spatial)
// morphs the trigger from a closed FAB of size (primary-container, its
// size's corner) into a 56dp primary close button, lerping size, corner,
// colour and icon together; the glyph swaps to a close icon halfway.
// The items stack above it in list order, end-aligned (start-aligned with
// align_start), 56dp primary-container pills close-button-between-space
// above the trigger; a count spring (slow-effects) reveals them in list
// order, and each also springs its own width (fast-spatial) and opacity
// (fast-effects) in and out.
//
// Clicking the trigger flips open^; clicking an item closes the menu and
// returns its index. Returns -1 otherwise. The caller places the menu,
// 16dp in from the screen edge (fab-menu.json layout,
// FloatingActionButtonMenu.kt:737). The trigger's shadow is
// fab-primary-container's and stays constant; items have none (both
// fab-menu elevation tokens are dead, fab-menu.json notes). The FAB
// token groups have no disabled-* tokens, so a forced Disabled paints as
// Enabled and only drops the state layer and input.
fab_menu :: proc(
	gtx: ^ui.Ctx,
	glyph: Icon,
	items: []Fab_Menu_Item,
	open: ^bool,
	key: u64 = 0,
	size := Fab_Menu_Size.Baseline,
	align_start := false,
	state := Interaction.Live,
	loc := #caller_location,
) -> int {
	p := ui.widget_open(gtx, key, loc)
	// Closed-state size, corner and icon per trigger size. The corners
	// (16/20/28) and large's 36dp icon are hard-coded upstream, not the
	// FAB's shape tokens (fab-menu.json layout, FloatingActionButtonMenu.kt:715-729).
	closed_d, closed_r, closed_i: f32
	switch size {
	case .Baseline:
		closed_d, closed_r, closed_i = tok.FAB_BASELINE_CONTAINER_WIDTH, 16, tok.FAB_BASELINE_ICON_SIZE
	case .Medium:
		closed_d, closed_r, closed_i = tok.FAB_MEDIUM_CONTAINER_WIDTH, 20, tok.FAB_MEDIUM_ICON_SIZE
	case .Large:
		closed_d, closed_r, closed_i = tok.FAB_LARGE_CONTAINER_WIDTH, 28, 36
	}
	box := ui.constrain_min(gtx.constraints, {closed_d, closed_d})

	// The trigger's hit area is its closed box: the close button sits
	// inside it, anchored to the aligned bottom corner.
	area := ops.Rect{0, 0, closed_d, closed_d}
	c := control(gtx, p.id, area, state)
	if c.clicked {
		open^ = !open^
	}
	t := animate(gtx, c, 0, open^ ? 1 : 0, .Fast_Spatial)
	n := len(items)
	// Stagger: an item count that springs toward n or 0, visibility
	// threshold 1 so the last item does not lag (fab-menu.json states,
	// FloatingActionButtonMenu.kt:203-217).
	count := animate(gtx, c, 1, open^ ? f32(n) : 0, .Slow_Effects, 1)

	lerp :: proc(a, b, t: f32) -> f32 {
		return a + (b - a) * t
	}
	d := lerp(closed_d, tok.FAB_MENU_BASELINE_CLOSE_BUTTON_CONTAINER_WIDTH, t)
	radius := lerp(closed_r, tok.FAB_MENU_BASELINE_CLOSE_BUTTON_CONTAINER_HEIGHT / 2, t)
	isz := lerp(closed_i, tok.FAB_MENU_BASELINE_CLOSE_BUTTON_ICON_SIZE, t)
	// Container primary-container → primary, icon on-primary-container →
	// on-primary (FloatingActionButtonMenu.kt:581,612): the close button's
	// roles have no fab-menu token.
	ct := clamp(t, 0, 1)
	container := ops.mix(color(tok.FAB_PRIMARY_CONTAINER_CONTAINER_COLOR), color(.Primary), ct)
	content := ops.mix(color(tok.FAB_PRIMARY_CONTAINER_ICON_COLOR), color(.On_Primary), ct)
	tx := align_start ? 0 : closed_d - d
	tr := ops.Rect{tx, closed_d - d, d, d}
	rr := ops.Round_Rect{tr, radius}
	paint_elevation(gtx, rr, elevation_level(tok.FAB_PRIMARY_CONTAINER_CONTAINER_ELEVATION))
	ops.fill(gtx.scene, rr, container)
	paint_state_layer(gtx, c, rr, content)
	// The add → close swap at half progress is the icon slot's convention
	// upstream (FloatingActionButtonMenu.kt:440); here the menu owns it.
	icon(gtx, t < 0.5 ? glyph : .Close, {tr.x + (d - isz) / 2, tr.y + (d - isz) / 2}, isz, content)
	paint_focus_ring(gtx, c, rr)
	listen(gtx, c, p.id, area)
	// The trigger names its action, since its icon and colour both change
	// (fab-menu.json accessibility).
	ops.tag(gtx.scene, p.id, open^ ? "Close menu" : "Open actions menu")
	ui.semantics(gtx, &p, {role = .Button, label = open^ ? "Close menu" : "Open actions menu", states = states_of(c) + {.Expandable} + (open^ ? {.Expanded} : {})})

	chosen := -1
	if count > 0.01 || open^ {
		o := ui.overlay_open(gtx)
		defer ui.close(&o)
		H := tok.FAB_MENU_BASELINE_LIST_ITEM_CONTAINER_HEIGHT
		between := tok.FAB_MENU_BASELINE_LIST_ITEM_BETWEEN_SPACE
		// The bottom item sits close-button-between-space above the
		// trigger as it is now, so the stack follows the morph; the two
		// 16dp paddings upstream cancel (fab-menu.json notes).
		y := tr.y - tok.FAB_MENU_BASELINE_CLOSE_BUTTON_BETWEEN_SPACE - f32(n) * H - f32(max(n - 1, 0)) * between
		y0 := y
		// The items shown, declared once painted: a menu widget at the
		// stack's top, so they are parts of it, not of the trigger.
		Shown :: struct {
			id:    ops.Area_Id,
			r:     ops.Rect,
			label: string,
		}
		shown := make([dynamic]Shown, 0, n, gtx.allocator)
		for it, i in items {
			id := ui.id_mix(p.id, u64(100 + i))
			visible := count > f32(i)
			txt := shape_text(gtx, it.label, .Title_Medium)
			full_w := tok.FAB_MENU_BASELINE_LIST_ITEM_LEADING_SPACE + tok.FAB_MENU_BASELINE_LIST_ITEM_ICON_SIZE + tok.FAB_MENU_BASELINE_LIST_ITEM_ICON_LABEL_SPACE + txt.width + tok.FAB_MENU_BASELINE_LIST_ITEM_TRAILING_SPACE
			// Width and opacity spring per item, before its bounds exist.
			wt, at: f32 = visible ? 1 : 0, visible ? 1 : 0
			live := state == .Live
			if live {
				st := ui.widget_state(gtx, id)
				wt = ui.spring_update(&st.springs[0], gtx, wt, spring_params(.Fast_Spatial))
				at = ui.spring_update(&st.springs[1], gtx, at, spring_params(.Fast_Effects))
			}
			w := full_w * max(wt, 0)
			if at > 0.01 && w > 1 {
				r := ops.Rect{align_start ? 0 : closed_d - w, y, w, H}
				ic := control(gtx, id, r, live && open^ ? .Live : .Enabled)
				if ic.clicked {
					chosen = i
					open^ = false
				}
				pill := rounded(gtx, r, corners(tok.FAB_MENU_BASELINE_LIST_ITEM_CONTAINER_SHAPE, r))
				ops.fill(gtx.scene, pill, fade(color(tok.FAB_PRIMARY_CONTAINER_CONTAINER_COLOR), at))
				paint_state_layer(gtx, ic, pill, color(tok.FAB_PRIMARY_CONTAINER_ICON_COLOR))
				ops.clip_push(gtx.scene, pill)
				fg := fade(color(tok.FAB_PRIMARY_CONTAINER_ICON_COLOR), at)
				// Content keeps its place from the aligned edge as the pill grows.
				cx := align_start ? r.x : r.x + r.w - full_w
				lisz := tok.FAB_MENU_BASELINE_LIST_ITEM_ICON_SIZE
				icon(gtx, it.icon, {cx + tok.FAB_MENU_BASELINE_LIST_ITEM_LEADING_SPACE, y + (H - lisz) / 2}, lisz, fg)
				draw_text(gtx, txt, {cx + tok.FAB_MENU_BASELINE_LIST_ITEM_LEADING_SPACE + lisz + tok.FAB_MENU_BASELINE_LIST_ITEM_ICON_LABEL_SPACE, y + (H - txt.height) / 2}, fg)
				ops.clip_pop(gtx.scene)
				paint_focus_ring(gtx, ic, {r, H / 2})
				listen(gtx, ic, id, r)
				ops.tag(gtx.scene, id, ui.frame_string(gtx, it.label))
				append(&shown, Shown{id, r, it.label})
			}
			y += H + between
		}
		ops.transform_push(gtx.scene, ops.translate(0, y0))
		mp := ui.widget_open(gtx, u64(ui.id_mix(p.id, 99)), loc)
		ui.semantics(gtx, &mp, {role = .Menu, label = "actions"})
		for sh in shown {
			ui.part_semantics(gtx, &mp, sh.id, {sh.r.x, sh.r.y - y0, sh.r.w, sh.r.h}, {role = .Menu_Item, label = sh.label})
		}
		ui.widget_close(gtx, &mp, {size = {closed_d, max(y - between - y0, 0)}})
		ops.transform_pop(gtx.scene)
	}
	ui.widget_close(gtx, &p, {size = box})
	return chosen
}
