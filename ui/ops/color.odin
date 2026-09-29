package ops

// Colour arithmetic on Color.

// mix blends a toward b by t in [0, 1], channel by channel (alpha included).
mix :: proc(a, b: Color, t: f32) -> Color {
	out: Color
	for i in 0 ..< 4 {
		out[i] = u8(f32(a[i]) + (f32(b[i]) - f32(a[i])) * clamp(t, 0, 1) + 0.5)
	}
	return out
}

// with_alpha is c with its alpha channel set to t in [0, 1], RGB unchanged
// — a real translucent colour, not a pre-mixed solid one. State layers and
// disabled dimming both use this: painted on top of whatever is already
// there, the way Material's own state layers and disabled scrims work,
// rather than baking a flattened colour ahead of time per widget state.
with_alpha :: proc(c: Color, t: f32) -> Color {
	out := c
	out[3] = u8(255 * clamp(t, 0, 1))
	return out
}
