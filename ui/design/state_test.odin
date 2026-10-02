package design

import "core:testing"
import "jm:ui"
import "jm:ui/ops"

@(private = "file")
Look :: enum u8 {
	Rest,
	Hover,
	Pressed,
	Disabled,
}

@(test)
test_role_for_picks_disabled_then_pressed_then_hovered :: proc(t: ^testing.T) {
	s := State_Roles(Look){.Rest, .Hover, .Pressed, .Disabled}
	want := [Interaction]Look {
		.Live     = .Rest,
		.Enabled  = .Rest,
		.Hovered  = .Hover,
		.Focused  = .Rest,
		.Pressed  = .Pressed,
		.Dragged  = .Pressed,
		.Disabled = .Disabled,
	}
	gtx: ui.Ctx
	for st in Interaction {
		if st == .Live {
			continue
		}
		testing.expectf(t, role_for(s, control(&gtx, 1, {}, st)) == want[st], "%v", st)
	}
	both := Control{hovered = true, pressed = true}
	both.state = effective_state(both)
	testing.expect_value(t, role_for(s, both), Look.Pressed)
}

@(test)
test_state_if_adds_states_only_when_on :: proc(t: ^testing.T) {
	testing.expect_value(t, state_if(true, {.Checked}), ops.States{.Checked})
	testing.expect_value(t, state_if(false, {.Checked}), ops.States{})
}

@(test)
test_blend_eases_over_its_duration_and_snaps_with_none :: proc(t: ^testing.T) {
	red, blue := ops.Color{255, 0, 0, 255}, ops.Color{0, 0, 255, 255}
	linear := Bezier{0, 0, 1, 1}
	gtx: ui.Ctx
	gtx.dt = 0.05
	f: Fades
	testing.expect_value(t, blend(&gtx, &f, 2, red, 100, linear), red)
	mid := blend(&gtx, &f, 2, blue, 100, linear) // 50 of 100ms: halfway, to a step of 8-bit colour
	for ch in 0 ..< 4 {
		testing.expectf(t, abs(int(mid[ch]) - int(ops.mix(red, blue, 0.5)[ch])) <= 1, "mid %v", mid)
	}
	testing.expect_value(t, blend(&gtx, &f, 2, red, 0, linear), red) // no duration: there at once
	testing.expect_value(t, blend(&gtx, nil, 2, blue, 100, linear), blue) // forced: nothing retained
}

@(private = "file")
Field_Seen :: struct {
	text:    string,
	scrolls: int,
	clicks:  int,
}

@(private = "file")
field_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	seen := (^Field_Seen)(user)
	p := ui.widget_open(gtx)
	area := ops.Rect{0, 0, 100, 30}
	c := control(gtx, p.id, area, .Live)
	if c.clicked {
		seen.clicks += 1
	}
	for e in ui.events(gtx, p.id) {
		#partial switch e.kind {
		case .Text:
			seen.text = e.text
		case .Scroll:
			seen.scrolls += 1
		}
	}
	listen(gtx, c.st, p.id, area, EDIT_KINDS)
	ops.tag(gtx.scene, p.id, "field")
	ui.widget_close(gtx, &p, {size = {100, 30}})
}

@(test)
test_a_field_listening_for_edit_kinds_takes_clicks_text_and_the_wheel :: proc(t: ^testing.T) {
	seen: Field_Seen
	p: ui.Probe
	ui.probe_init(&p, field_view, &seen, {200, 100}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect(t, ui.probe_click(&p, "field"))
	testing.expect_value(t, seen.clicks, 1)
	ui.probe_type(&p, "a") // focused by the click, it takes typed text
	testing.expect_value(t, seen.text, "a")
	testing.expect(t, ui.probe_scroll(&p, "field", 1))
	testing.expect_value(t, seen.scrolls, 1)
}
