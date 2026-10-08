package primer

import "core:fmt"
import "core:strings"
import "core:testing"
import "jm:ui"
import "jm:ui/design"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// Behaviour of button and icon_button, driven through ui.Probe by tags.

@(private = "file")
Buttons_Model :: struct {
	saves, deletes, stars, offs, loads, nopes: int,
	loading:                                   bool,
}

@(private = "file")
buttons :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Buttons_Model)(user)
	col := ui.column_open(gtx, gap = 16, align = .Start)
	defer ui.close(&col)
	if button(gtx, "Save", .Primary) {
		m.saves += 1
	}
	if button(gtx, "Delete", .Danger, .Small, leading = .Trash) {
		m.deletes += 1
	}
	if icon_button(gtx, .Star, "Star", size = .Large) {
		m.stars += 1
	}
	if button(gtx, "Off", state = .Disabled) {
		m.offs += 1
	}
	if button(gtx, "Load", loading = m.loading) {
		m.loads += 1
	}
	if button(gtx, "Nope", inactive = true) {
		m.nopes += 1
	}
	button(gtx, "Issues", count = "12")
	button(gtx, "Read more", .Link)
	button(gtx, "Wide", block = true)
}

@(private = "file")
buttons_probe :: proc(p: ^ui.Probe, m: ^Buttons_Model) {
	ui.probe_init(p, buttons, m, {600, 700}, allocator = context.temp_allocator)
}

@(test)
test_button_activates_by_click_and_keyboard_and_not_when_disabled :: proc(t: ^testing.T) {
	m: Buttons_Model
	p: ui.Probe
	buttons_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Save"))
	testing.expect_value(t, m.saves, 1)
	ui.probe_key(&p, .Enter)
	testing.expect_value(t, m.saves, 2)
	ui.probe_key(&p, .Space)
	testing.expect_value(t, m.saves, 3)
	testing.expect(t, ui.probe_click(&p, "Delete"))
	testing.expect_value(t, m.deletes, 1)
	testing.expect(t, ui.probe_click(&p, "Star")) // an icon button is tagged by its name
	testing.expect_value(t, m.stars, 1)
	testing.expect(t, !ui.probe_click(&p, "Off")) // disabled: no input area
	testing.expect_value(t, m.offs, 0)
	// Inactive looks disabled but stays live (button.json states).
	testing.expect(t, ui.probe_click(&p, "Nope"))
	testing.expect_value(t, m.nopes, 1)
}

@(test)
test_a_loading_button_keeps_focus_but_ignores_activation :: proc(t: ^testing.T) {
	m: Buttons_Model
	p: ui.Probe
	buttons_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Load"))
	testing.expect_value(t, m.loads, 1)
	m.loading = true
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_click(&p, "Load")) // still a live area: it keeps focus
	ui.probe_key(&p, .Enter)
	testing.expect_value(t, m.loads, 1)
	testing.expect(t, p.wants_frame) // its spinner turns
}

@(test)
test_button_geometry_follows_the_css :: proc(t: ^testing.T) {
	m: Buttons_Model
	p: ui.Probe
	buttons_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	save := ui.probe_bounds(&p, "Save")
	testing.expect_value(t, save.h, tok.CONTROL_MEDIUM_SIZE) // 32
	gtx := ui.Ctx{shaper = p.shaper, allocator = context.temp_allocator}
	st := button_metrics(.Medium).style
	label := design.shape_style(&gtx, "Save", st, font_for(&gtx, st.weight))
	testing.expect_value(t, save.w, label.width + 2 * tok.CONTROL_MEDIUM_PADDING_INLINE_NORMAL) // hugs: 12px each side
	del := ui.probe_bounds(&p, "Delete")
	testing.expect_value(t, del.h, tok.CONTROL_SMALL_SIZE) // 28
	star := ui.probe_bounds(&p, "Star")
	testing.expect_value(t, star, ops.Rect{star.x, star.y, tok.CONTROL_LARGE_SIZE, tok.CONTROL_LARGE_SIZE}) // a 40px square
	// A count adds one gap and the pill after the label.
	issues := design.shape_style(&gtx, "Issues", st, font_for(&gtx, st.weight))
	cst := counter_style()
	pill := counter_size(design.shape_style(&gtx, "12", cst, font_for(&gtx, cst.weight)))
	counted := ui.probe_bounds(&p, "Issues")
	want := 2 * tok.CONTROL_MEDIUM_PADDING_INLINE_NORMAL + issues.width + tok.BASE_SIZE_8 + pill.x
	testing.expectf(t, abs(counted.w - want) < 0.01, "counted button %v wide, want %v", counted.w, want)
	// A link has no box: as tall as its line, exactly as wide as its label.
	link := ui.probe_bounds(&p, "Read more")
	testing.expect_value(t, link.h, st.line_height)
	testing.expect_value(t, link.w, design.shape_style(&gtx, "Read more", st, font_for(&gtx, st.weight)).width)
	testing.expect_value(t, ui.probe_bounds(&p, "Wide").w, 600) // block fills the width
}

@(private = "file")
is_color :: proc(p: ops.Paint, c: ops.Color) -> bool {
	got, solid := p.(ops.Color)
	return solid && got == c
}

@(private = "file")
count_focus_strokes :: proc(p: ^ui.Probe) -> (n: int) {
	focus := color(.Focus_Outline_Color)
	for op in p.scene.ops {
		if s, ok := op.(ops.Stroke); ok && is_color(s.paint, focus) {
			n += 1
		}
	}
	return
}

@(test)
test_focus_shows_for_the_keyboard_not_a_click :: proc(t: ^testing.T) {
	m: Buttons_Model
	p: ui.Probe
	buttons_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	ui.probe_click(&p, "Delete")
	ui.probe_frame(&p)
	testing.expect_value(t, count_focus_strokes(&p), 0) // focused by a click: no outline
	ui.probe_key(&p, .Tab)
	ui.probe_frame(&p)
	testing.expect_value(t, count_focus_strokes(&p), 1) // moved by Tab: the outline shows
}

@(test)
test_a_counter_label_without_a_count_takes_no_space :: proc(t: ^testing.T) {
	view :: proc(gtx: ^ui.Ctx, user: rawptr) {
		r := ui.row_open(gtx)
		defer ui.close(&r)
		counter_label(gtx, "")
		counter_label(gtx, "0", .Primary)
	}
	p: ui.Probe
	ui.probe_init(&p, view, nil, {200, 100}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	fills := 0
	for op in p.scene.ops {
		if f, ok := op.(ops.Fill); ok && is_color(f.paint, color(.Bg_Color_Neutral_Emphasis)) {
			fills += 1
			r := f.shape.(ops.Round_Rect).rect
			testing.expect_value(t, r.x, 0) // the empty one before it took no width
			testing.expect_value(t, r.h, tok.TEXT_BODY_SIZE_SMALL + 2 * (2 + tok.BORDER_WIDTH_THIN)) // 18px
		}
	}
	testing.expect_value(t, fills, 1) // "0" is a count, "" is not
}

@(private = "file")
Expanded_Model :: struct {
	open: bool,
	hits: int,
}

@(private = "file")
expanded_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Expanded_Model)(user)
	col := ui.column_open(gtx, gap = 16, align = .Start)
	defer ui.close(&col)
	button(gtx, "Plain")
	if button(gtx, "Menu", action = .Triangle_Down, expanded = m.open) {
		m.open = !m.open
	}
	icon_button(gtx, .Kebab_Horizontal, "More", expanded = m.open)
	if button(gtx, "Skipped", tab_stop = false) {
		m.hits += 1
	}
	button(gtx, "Last")
}

@(test)
test_an_expanded_button_reports_it_and_keeps_its_pressed_fill :: proc(t: ^testing.T) {
	m: Expanded_Model
	p: ui.Probe
	ui.probe_init(&p, expanded_view, &m, {400, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	sem := ui.probe_semantics(&p, context.temp_allocator)
	testing.expectf(t, strings.contains(sem, "button \"Menu\" expandable at"), "closed: expandable, not expanded\n%s", sem)
	testing.expectf(t, strings.contains(sem, "button \"Plain\" at"), "a plain button says neither\n%s", sem)
	pressed := color(.Button_Default_Bg_Color_Active)
	testing.expect_value(t, fills_of(&p, pressed), 0)
	m.open = true
	ui.probe_move(&p, 390, 390) // the pointer off every button
	sem = ui.probe_semantics(&p, context.temp_allocator)
	testing.expectf(t, strings.contains(sem, "button \"Menu\" expandable expanded at"), "open: expanded\n%s", sem)
	testing.expect_value(t, fills_of(&p, pressed), 2) // the menu button and the icon button, both default
	// Hovered, it shows its hover fill: the CSS's :hover follows [aria-expanded].
	c, _ := ui.probe_center(&p, "Menu")
	ui.probe_move(&p, c.x, c.y)
	ui.probe_advance(&p, 10, 1.0 / 60) // past the 80ms fade
	testing.expect_value(t, fills_of(&p, pressed), 1) // the icon button's, still expanded and not hovered
	testing.expect_value(t, fills_of(&p, color(.Button_Default_Bg_Color_Hover)), 1)
}

@(private = "file")
tooltips_shown :: proc(p: ^ui.Probe) -> (n: int) {
	return fills_of(p, color(.Tooltip_Bg_Color))
}

@(test)
test_an_expanded_icon_button_shows_no_tooltip :: proc(t: ^testing.T) {
	m: Expanded_Model
	p: ui.Probe
	ui.probe_init(&p, expanded_view, &m, {400, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	c, _ := ui.probe_center(&p, "More")
	ui.probe_move(&p, c.x, c.y)
	ui.probe_advance(&p, 6, 1.0 / 60) // past the 50ms delay
	testing.expect_value(t, tooltips_shown(&p), 1) // closed: the tooltip names it
	m.open = true
	ui.probe_advance(&p, 2, 1.0 / 60)
	testing.expect_value(t, tooltips_shown(&p), 0) // open: its menu shows instead
}

@(private = "file")
own_tooltip_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	col := ui.column_open(gtx, gap = 16, align = .Start)
	defer ui.close(&col)
	st := ui.stack_open(gtx)
	defer ui.close(&st)
	icon_button(gtx, .Bold, "Bold", description = "Make it bold", no_tooltip = true)
	tooltip(gtx, "Bold, the caller's words", ui.last_widget(gtx))
}

@(test)
test_an_icon_button_without_its_tooltip_leaves_the_callers_to_fade_in :: proc(t: ^testing.T) {
	p: ui.Probe
	ui.probe_init(&p, own_tooltip_view, nil, {400, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	c, _ := ui.probe_center(&p, "Bold")
	ui.probe_move(&p, c.x, c.y)
	ui.probe_advance(&p, 30, 1.0 / 60) // past the delay and the 100ms fade
	testing.expect_value(t, tooltips_shown(&p), 1)
	for op in p.scene.ops {
		_, fading := op.(ops.Push_Opacity)
		testing.expect(t, !fading, "the caller's tooltip is still fading in, half a second on")
	}
}

@(test)
test_a_button_out_of_the_tab_order_is_skipped_by_tab_and_still_clicks :: proc(t: ^testing.T) {
	m: Expanded_Model
	p: ui.Probe
	ui.probe_init(&p, expanded_view, &m, {400, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	last, _ := ui.probe_find(&p, "Last")
	ui.probe_click(&p, "More")
	ui.probe_frame(&p)
	ui.probe_key(&p, .Tab)
	testing.expect_value(t, p.router.focus, last.area) // past Skipped
	testing.expect(t, ui.probe_click(&p, "Skipped"))
	testing.expect_value(t, m.hits, 1)
}

@(private = "file")
hint_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	col := ui.column_open(gtx, gap = 16, align = .Start)
	defer ui.close(&col)
	button(gtx, "Search", keybinding = "Mod+K")
	button(gtx, "Search bare")
	icon_button(gtx, .Bold, "Bold", keybinding = {"Mod+B"})
	icon_button(gtx, .Italic, "Italic")
}

@(test)
test_a_keybinding_hint_takes_the_trailing_slot_and_shortens_the_end :: proc(t: ^testing.T) {
	p: ui.Probe
	ui.probe_init(&p, hint_view, nil, {600, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	gtx := ui.Ctx{shaper = p.shaper, allocator = context.temp_allocator}
	st := button_metrics(.Medium).style
	label := design.shape_style(&gtx, "Search", st, font_for(&gtx, st.weight))
	hint := layout_hint(&gtx, "Mod+K", .Condensed, .Normal, .Normal)
	// 12px at the start, the label, the 8px gap, the caps, then only 6px.
	want := tok.CONTROL_MEDIUM_PADDING_INLINE_NORMAL + label.width + tok.BASE_SIZE_8 + hint.size.x + tok.BASE_SIZE_6
	got := ui.probe_bounds(&p, "Search").w
	testing.expectf(t, abs(got - want) < 0.01, "button with a hint %v wide, want %v", got, want)
}

@(test)
test_an_icon_buttons_shortcut_is_said_with_its_name_and_shown_in_its_tooltip :: proc(t: ^testing.T) {
	p: ui.Probe
	ui.probe_init(&p, hint_view, nil, {600, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	said := ui.probe_semantics(&p, context.temp_allocator)
	want := strings.concatenate({"\"Bold (", spoken_hint("Mod+B", PLATFORM, context.temp_allocator), ")\""}, context.temp_allocator)
	testing.expectf(t, strings.contains(said, want), "want %s in %s", want, said)
	testing.expect(t, strings.contains(said, "\"Italic\""))
	// Hovered past the delay, the tooltip holds the caps beside the name:
	// its padding, the name, a 6px margin, the small on-emphasis caps.
	at, _ := ui.probe_center(&p, "Bold")
	ui.probe_move(&p, at.x, at.y)
	ui.probe_advance(&p, 10, 0.02)
	bubble: f32
	for op in p.scene.ops {
		if f, ok := op.(ops.Fill); ok && is_color(f.paint, color(.Tooltip_Bg_Color)) {
			if rr, is_rr := f.shape.(ops.Round_Rect); is_rr {
				bubble = rr.rect.w
			}
		}
	}
	gtx := ui.Ctx{shaper = p.shaper, allocator = context.temp_allocator}
	st := style(.Body_Small)
	name := design.shape_style(&gtx, "Bold", st, font_for(&gtx, st.weight))
	caps := layout_hint(&gtx, "Mod+B", .Condensed, .On_Emphasis, .Small)
	wide := 2 * tok.OVERLAY_PADDING_CONDENSED + name.width + tok.BASE_SIZE_6 + caps.size.x
	testing.expectf(t, abs(bubble - wide) < 0.5, "tooltip %v wide, want %v", bubble, wide)
}

// A block button's trailing action sits at its end, not after its label:
// the probe's 400px window holds the button.
@(test)
test_a_block_buttons_action_sits_at_its_end :: proc(t: ^testing.T) {
	view :: proc(gtx: ^ui.Ctx, user: rawptr) {
		button(gtx, "Menu", block = true, align = .Start, action = .Triangle_Down)
	}
	p: ui.Probe
	ui.probe_init(&p, view, nil, {400, 100}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	context.allocator = context.temp_allocator
	x := 400 - button_metrics(.Medium).pad - BUTTON_ICON + tok.BASE_SIZE_4
	dump := ui.probe_dump(&p)
	want := fmt.tprintf("transform 1 0 0 1 %v ", x)
	testing.expectf(t, strings.contains(dump, want), "want x %v in\n%s", x, dump)
}
