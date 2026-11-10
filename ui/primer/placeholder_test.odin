package primer

import "core:math"
import "core:testing"

import "jm:ui/ops"

@(private = "file")
luminance :: proc(c: ops.Color) -> f64 {
	lin :: proc(v: u8) -> f64 {
		x := f64(v) / 255
		return x <= 0.04045 ? x / 12.92 : math.pow((x + 0.055) / 1.055, 2.4)
	}
	return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
}

@(private = "file")
contrast :: proc(a, b: ops.Color) -> f64 {
	x, y := luminance(a), luminance(b)
	return (max(x, y) + 0.05) / (min(x, y) + 0.05)
}

// A placeholder is clearly fainter than the muted text beside it and than
// typed text, and still legible: 3:1 or more against its well, in the light
// and dark themes, over the default and the inset (contrast) fill.
@(test)
test_placeholders_are_faint_but_legible :: proc(t: ^testing.T) {
	for mode in ([]Theme{.Light, .Dark}) {
		scheme := theme_scheme(mode)
		use(&scheme, mode)
		defer use(nil)

		for contrast_fill in ([]bool{false, true}) {
			w := Well{contrast = contrast_fill}
			fill := color(well_fill(w))
			hint := contrast(placeholder_color(w), fill)
			muted := contrast(color(.Fg_Color_Muted), fill)
			testing.expectf(t, hint >= 3, "%v (inset %v): placeholder %.2f:1 is below 3:1", mode, contrast_fill, hint)
			testing.expectf(t, hint <= muted - 2, "%v (inset %v): placeholder %.2f:1 is too near muted text at %.2f:1", mode, contrast_fill, hint, muted)
		}
	}
}
