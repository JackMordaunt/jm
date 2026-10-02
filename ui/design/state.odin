package design

import "jm:ui"
import "jm:ui/ops"

// State_Roles is one property's colour role in each state a system that
// binds a token per state paints it in (Fluent, Primer): the rest token
// and its hover, pressed and disabled twins. A property with no token for
// a state repeats its rest role there.
State_Roles :: struct($R: typeid) {
	rest, hover, pressed, disabled: R,
}

// role_for is the role s binds for c's state: disabled, then pressed (or
// dragged), then hovered; focused and enabled read the rest role, since
// focus is drawn as a ring, not a recolouring.
role_for :: proc(s: State_Roles($R), c: Control) -> R {
	#partial switch c.state {
	case .Disabled:
		return s.disabled
	case .Pressed, .Dragged:
		return s.pressed
	case .Hovered:
		return s.hover
	}
	return s.rest
}

// Fades are a component's colour transitions: one per property it eases,
// numbered by the component like animate's spring slots. A component
// keeps them in its widget data (ui.widget_data) while it is Live.
Fades :: struct {
	slots: [4]Fade,
}

Fade :: struct {
	from, to: ops.Color,
	tween:    ui.Tween,
	live:     bool, // a value has been seen; until then there is nothing to ease from
}

// blend is target eased from the colour slot last showed: a change of
// target starts a transition of duration ms along curve. A forced state
// (f nil) has no retained colour, so it is target at once, as is the
// first frame of a live one. A duration of 0 snaps.
blend :: proc(gtx: ^ui.Ctx, f: ^Fades, slot: int, target: ops.Color, duration: f32, curve: Bezier) -> ops.Color {
	if f == nil {
		return target
	}
	s := &f.slots[slot]
	if !s.live {
		s^ = {from = target, to = target, live = true}
		return target
	}
	if target != s.to {
		s.from = fade_value(s, curve)
		s.to = target
		s.tween = {to = 1, duration = duration / 1000}
	}
	ui.tween_update(&s.tween, gtx)
	return fade_value(s, curve)
}

@(private = "file")
fade_value :: proc(f: ^Fade, curve: Bezier) -> ops.Color {
	if f.tween.duration <= 0 {
		return f.to
	}
	return ops.mix(f.from, f.to, bezier_ease(curve, f.tween.t / f.tween.duration))
}
