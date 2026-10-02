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
