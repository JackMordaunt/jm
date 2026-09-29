package design

import "core:math"
import "jm:ui"

// Colour metrics: the measurements axioms are stated in. Every one takes
// jm:ui's sRGB Color, so a system's scheme is measured as it is painted.

// linear is sRGB channel v (0-255) as linear light, 0-1.
linear :: proc(v: u8) -> f32 {
	c := f32(v) / 255
	if c <= 0.04045 {
		return c / 12.92
	}
	return math.pow((c + 0.055) / 1.055, 2.4)
}

// luminance is c's relative luminance Y (0-1), alpha ignored.
luminance :: proc(c: ui.Color) -> f32 {
	return 0.2126 * linear(c[0]) + 0.7152 * linear(c[1]) + 0.0722 * linear(c[2])
}

// OKLCH is a colour in OKLab's polar form: perceptual lightness l in
// [0, 1], chroma c, and hue h in degrees [0, 360).
OKLCH :: struct {
	l, c, h: f32,
}

// oklch is c in OKLCH, alpha ignored. The matrices are OKLab's
// (bottosson.github.io/posts/oklab, "A perceptual color space for image
// processing").
oklch :: proc(c: ui.Color) -> OKLCH {
	r, g, b := linear(c[0]), linear(c[1]), linear(c[2])
	l_ := math.pow(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b, 1.0 / 3)
	m_ := math.pow(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b, 1.0 / 3)
	s_ := math.pow(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b, 1.0 / 3)
	L := 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
	A := 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
	B := 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
	h := math.to_degrees(math.atan2(B, A))
	if h < 0 {
		h += 360
	}
	return {L, math.sqrt(A * A + B * B), h}
}

// hue_dist is the shortest angular distance between hues a and b, in
// degrees [0, 180].
hue_dist :: proc(a, b: f32) -> f32 {
	d := abs(math.mod(a - b, 360))
	return min(d, 360 - d)
}

// wcag_ratio is the WCAG 2 contrast ratio between a and b, 1-21. It is
// symmetric, so neither has to be the text.
wcag_ratio :: proc(a, b: ui.Color) -> f32 {
	la, lb := luminance(a), luminance(b)
	if la < lb {
		la, lb = lb, la
	}
	return (la + 0.05) / (lb + 0.05)
}

// apca is the APCA lightness contrast Lc of text fg on background bg, as
// an absolute value 0-108: the 0.0.98G algorithm from the APCA-W3 readme
// (github.com/Myndex/apca-w3), whose example pairs design_test checks
// to within 0.05. It is polarity-aware: light text on dark scores
// differently from the reverse, which is why axioms keep foreground and
// background ordered. Typical thresholds to ask for: Lc 75 for body
// text, 60 for larger text, 45 for headlines, 30 for non-text.
apca :: proc(fg, bg: ui.Color) -> f32 {
	// APCA's own sRGB coefficients, close to but not WCAG's, on a plain
	// 2.4 power curve rather than the piecewise sRGB transfer.
	y :: proc(c: ui.Color) -> f32 {
		ch :: proc(v: u8) -> f32 {return math.pow(f32(v) / 255, 2.4)}
		return 0.2126729 * ch(c[0]) + 0.7151522 * ch(c[1]) + 0.0721750 * ch(c[2])
	}
	soft :: proc(v: f32) -> f32 {
		if v < 0.022 {
			return v + math.pow(0.022 - v, 1.414)
		}
		return v
	}
	yt, yb := soft(y(fg)), soft(y(bg))
	if abs(yb - yt) < 0.0005 {
		return 0
	}
	s: f32
	if yb > yt { // dark text on light
		s = (math.pow(yb, 0.56) - math.pow(yt, 0.57)) * 1.14
		if s < 0.1 {
			return 0
		}
		return (s - 0.027) * 100
	}
	s = (math.pow(yb, 0.65) - math.pow(yt, 0.62)) * 1.14
	if s > -0.1 {
		return 0
	}
	return -(s + 0.027) * 100
}
