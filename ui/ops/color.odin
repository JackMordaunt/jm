package ops

// Colour arithmetic on Color.

// rgba is 0xRRGGBBAA as a Color: how the design systems' generated token
// tables write a colour.
rgba :: proc(v: u32) -> Color {
	return {u8(v >> 24), u8(v >> 16), u8(v >> 8), u8(v)}
}

// mix blends a toward b by t in [0, 1] with premultiplied alpha, and is
// exactly a at t <= 0 and b at t >= 1. Premultiplying is what makes a
// fade from a transparent colour read right: transparent black (a
// subtle button's rest background) toward light grey eases through
// translucent light grey, not through dark grey, which straight
// channel-by-channel mixing gives. Opaque colours mix as before.
mix :: proc(a, b: Color, t: f32) -> Color {
	if t <= 0 {
		return a
	}
	if t >= 1 {
		return b
	}
	aa, ba := f32(a[3]) / 255, f32(b[3]) / 255
	alpha := aa + (ba - aa) * t
	out: Color
	out[3] = u8(alpha * 255 + 0.5)
	if alpha <= 0 {
		return out
	}
	for i in 0 ..< 3 {
		pa, pb := f32(a[i]) * aa, f32(b[i]) * ba
		out[i] = u8(clamp((pa + (pb - pa) * t) / alpha, 0, 255) + 0.5)
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
