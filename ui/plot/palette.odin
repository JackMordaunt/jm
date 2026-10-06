package plot

import "core:math"
import "jm:ui/design"
import "jm:ui/ops"

// The measures a series palette is checked by, so a style's colours are
// computed safe rather than eyeballed. Distances are Euclidean in OKLab,
// times 100 (ΔE); colour-vision deficiency is simulated with Machado,
// Oliveira and Fernandes (2009) at severity 1.0, in linear sRGB, to which
// the thresholds below are calibrated.

// CVD is a colour-vision deficiency to simulate.
CVD :: enum u8 {
	None,
	Protan,
	Deutan,
	Tritan,
}

@(private, rodata)
MACHADO := [CVD][3][3]f64 {
	.None   = {{1, 0, 0}, {0, 1, 0}, {0, 0, 1}},
	.Protan = {
		{0.152286, 1.052583, -0.204868},
		{0.114503, 0.786281, 0.099216},
		{-0.003882, -0.048116, 1.051998},
	},
	.Deutan = {
		{0.367322, 0.860646, -0.227968},
		{0.280085, 0.672501, 0.047413},
		{-0.011820, 0.042940, 0.968881},
	},
	.Tritan = {
		{1.255528, -0.076749, -0.178779},
		{-0.078411, 0.930809, 0.147602},
		{0.004733, 0.691367, 0.303900},
	},
}

// CVD_TARGET is the ΔE a pair of neighbouring series should keep apart
// under protanopia and deuteranopia; CVD_FLOOR the least that is legal,
// and only where identity is also carried another way (a dash, a marker,
// a label). NORMAL_FLOOR is the least two neighbours may sit apart for a
// reader with full colour vision. CONTRAST_MIN is a mark's WCAG contrast
// against the plot's background. CHROMA_FLOOR is the OKLCH chroma below
// which a hue reads as grey.
CVD_TARGET   :: 8.0
CVD_FLOOR    :: 6.0
NORMAL_FLOOR :: 15.0
CONTRAST_MIN :: 3.0
CHROMA_FLOOR :: 0.10

// oklab is c (alpha ignored) seen with deficiency d, in OKLab.
oklab :: proc(c: ops.Color, d := CVD.None) -> [3]f64 {
	lin := [3]f64{f64(design.linear(c[0])), f64(design.linear(c[1])), f64(design.linear(c[2]))}
	m := MACHADO[d]
	s: [3]f64
	for i in 0 ..< 3 {
		s[i] = clamp(m[i][0] * lin[0] + m[i][1] * lin[1] + m[i][2] * lin[2], 0, 1)
	}
	l := math.cbrt(0.4122214708 * s[0] + 0.5363325363 * s[1] + 0.0514459929 * s[2])
	mm := math.cbrt(0.2119034982 * s[0] + 0.6806995451 * s[1] + 0.1073969566 * s[2])
	ss := math.cbrt(0.0883024619 * s[0] + 0.2817188376 * s[1] + 0.6299787005 * s[2])
	return {
		0.2104542553 * l + 0.7936177850 * mm - 0.0040720468 * ss,
		1.9779984951 * l - 2.4285922050 * mm + 0.4505937099 * ss,
		0.0259040371 * l + 0.7827717662 * mm - 0.8086757660 * ss,
	}
}

// delta_e is how far apart a and b look with deficiency d: OKLab distance
// times 100.
delta_e :: proc(a, b: ops.Color, d := CVD.None) -> f64 {
	x, y := oklab(a, d), oklab(b, d)
	v := x - y
	return 100 * math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
}

// cvd_distance is the lesser of a and b's distance under protanopia and
// under deuteranopia: the red-green deficiencies, the commonest.
cvd_distance :: proc(a, b: ops.Color) -> f64 {
	return min(delta_e(a, b, .Protan), delta_e(a, b, .Deutan))
}

// Palette_Report is what check_palette measured: the worst of each
// measure, and the pair or slot it came from.
Palette_Report :: struct {
	min_chroma:      f64, // OKLCH chroma of the greyest slot
	min_contrast:    f64, // WCAG contrast of the faintest slot on the background
	adjacent_cvd:    f64, // the closest neighbours under protanopia or deuteranopia
	adjacent_normal: f64, // the closest neighbours with full colour vision
	prefix_cvd:      f64, // the closest pair among the first prefix slots, any two
	adjacent_at:     int, // adjacent_cvd's pair is slots at and at + 1
	lightness:       [2]f64, // the OKLCH lightness of the darkest and lightest slot
}

// check_palette measures colors, a series palette in slot order, on
// background bg. Series are given slots in order and only neighbours in
// that order sit side by side in a legend or a stack, so separation is
// measured between neighbours; the first prefix slots, the ones a chart of
// a few series uses, are also measured pair by pair, since any two lines
// may cross.
check_palette :: proc(colors: []ops.Color, bg: ops.Color, prefix := 3) -> (r: Palette_Report) {
	r.min_chroma, r.min_contrast = max(f64), max(f64)
	r.adjacent_cvd, r.adjacent_normal, r.prefix_cvd = max(f64), max(f64), max(f64)
	r.lightness = {1, 0}
	for c, i in colors {
		lab := oklab(c)
		r.min_chroma = min(r.min_chroma, math.sqrt(lab[1] * lab[1] + lab[2] * lab[2]))
		r.min_contrast = min(r.min_contrast, f64(design.wcag_ratio(c, bg)))
		r.lightness = {min(r.lightness[0], lab[0]), max(r.lightness[1], lab[0])}
		if i + 1 < len(colors) {
			d := cvd_distance(c, colors[i + 1])
			if d < r.adjacent_cvd {
				r.adjacent_cvd, r.adjacent_at = d, i
			}
			r.adjacent_normal = min(r.adjacent_normal, delta_e(c, colors[i + 1]))
		}
		for j in i + 1 ..< min(prefix, len(colors)) {
			r.prefix_cvd = min(r.prefix_cvd, cvd_distance(c, colors[j]))
		}
	}
	return
}
