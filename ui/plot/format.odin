package plot

import "core:math"
import "core:strconv"

// Short_Scale is which short scale a number's magnitude is written in.
Short_Scale :: enum u8 {
	None, // a million writes as 1000000
	Metric, // as 1M; m, µ and n below one: the SI prefixes, for units like H/s and W
	Finance, // as 1M, with B for a billion and T for a trillion: money
}

// Number_Format is how an axis writes its values: an optional prefix such
// as a dollar sign, the number scaled to a short scale, and a unit after
// it, which the SI symbol joins, as in PH/s. space puts a space between
// the number and the unit. A tooltip writes digits significant figures, 3
// when 0; grouped writes the whole number instead, with thousands
// separators and decimals places, as in $12,345.67.
Number_Format :: struct {
	prefix:   string,
	unit:     string,
	short:    Short_Scale,
	space:    bool,
	digits:   int,
	grouped:  bool,
	decimals: int,
}

// LABEL_MAX is the longest label format writes, in bytes; a longer one is
// cut.
LABEL_MAX :: 48

// Label is one written label, held in place, so writing one allocates
// nothing.
Label :: struct {
	buf: [LABEL_MAX]u8,
	n:   int,
}

// label_text is l's text, valid while l is.
label_text :: proc(l: ^Label) -> string {
	return string(l.buf[:l.n])
}

@(private)
put_text :: proc(l: ^Label, s: string) {
	for i in 0 ..< len(s) {
		if l.n >= LABEL_MAX {
			return
		}
		l.buf[l.n] = s[i]
		l.n += 1
	}
}

// Prefix is a short-scale step: the power of ten it stands for and its
// symbol.
@(private)
Prefix :: struct {
	exp:    int,
	symbol: string,
}

@(private, rodata)
METRIC := [?]Prefix {
	{-9, "n"},
	{-6, "µ"},
	{-3, "m"},
	{0, ""},
	{3, "k"},
	{6, "M"},
	{9, "G"},
	{12, "T"},
	{15, "P"},
	{18, "E"},
}

@(private, rodata)
FINANCE := [?]Prefix{{0, ""}, {3, "k"}, {6, "M"}, {9, "B"}, {12, "T"}}

// prefix_for is the short-scale step a value of magnitude mag is written
// in under short: the largest whose power of ten mag reaches, so the number
// written is at least 1 (or the smallest step, for less).
@(private)
prefix_for :: proc(short: Short_Scale, mag: f64) -> Prefix {
	table: []Prefix
	switch short {
	case .None:
		return {}
	case .Metric:
		table = METRIC[:]
	case .Finance:
		table = FINANCE[:]
	}
	if mag == 0 || !is_finite(mag) {
		return {0, ""}
	}
	best := table[0]
	for p in table {
		if mag >= math.pow(10, f64(p.exp)) * (1 - 1e-9) {
			best = p
		}
	}
	return best
}

// Axis_Format is what axis_format settled on for one axis: the short-scale
// step every label shares, the decimals that tell neighbours apart, and a
// power of ten written after each in scientific notation when plain
// decimals would run past MAX_DECIMALS (exp10, 0 for none).
Axis_Format :: struct {
	prefix:   Prefix,
	decimals: int,
	exp10:    int,
}

// MAX_DECIMALS is the most decimals a tick label writes before it switches
// to scientific notation; MAX_PLAIN the largest magnitude it writes out.
MAX_DECIMALS :: 6
MAX_PLAIN    :: 1e15

// axis_format chooses, for ticks at step whose largest magnitude is mag,
// one short-scale step for every label, so an axis reads 0.5, 1.0, 1.5
// PH/s rather than 500 TH/s, 1 PH/s, 1.5 PH/s, and the fewest decimals
// that still write step's multiples apart.
axis_format :: proc(f: Number_Format, step, mag: f64) -> Axis_Format {
	p := prefix_for(f.short, mag)
	unit := math.pow(10, f64(p.exp))
	scaled, big := step / unit, mag / unit
	d := decimals_for(scaled)
	if d <= MAX_DECIMALS && big < MAX_PLAIN {
		return {p, d, 0}
	}
	e := int(math.floor(math.log10(max(big, scaled))))
	return {p, decimals_for(scaled / math.pow(10, f64(e))), e}
}

// decimals_for is the fewest decimals that write step exactly enough that
// multiples of it never collide, up to 12.
@(private)
decimals_for :: proc(step: f64) -> int {
	if step <= 0 || !is_finite(step) {
		return 0
	}
	for d in 0 ..= 15 {
		x := step * math.pow(10, f64(d))
		if x >= 0.5 && abs(x - math.round(x)) < 1e-9 * x {
			return d
		}
	}
	return 15
}

// format_tick writes v as a tick of an axis formatted by a. Zero is
// written with no decimals, and with the short scale's symbol only where a
// unit follows it: "0 PH/s" and "$0", not "0.0 PH/s" and "$0k".
format_tick :: proc(f: Number_Format, a: Axis_Format, v: f64) -> (l: Label) {
	if v == 0 {
		put_number(&l, f, a.prefix if f.unit != "" else {}, 0, 0, false)
		return
	}
	x := v / math.pow(10, f64(a.prefix.exp + a.exp10))
	put_number(&l, f, a.prefix, x, a.decimals, false, a.exp10)
	return
}

// format_value writes v alone, as a tooltip shows it: grouped, or to
// f.digits significant figures in the short-scale step v's own magnitude
// calls for.
format_value :: proc(f: Number_Format, v: f64) -> (l: Label) {
	if !is_finite(v) {
		put_text(&l, "–")
		return
	}
	if f.grouped {
		put_number(&l, f, {}, v, f.decimals, true)
		return
	}
	p := prefix_for(f.short, abs(v))
	x := v / math.pow(10, f64(p.exp))
	digits := f.digits if f.digits > 0 else 3
	whole := abs(x) < 1 ? 1 : int(math.floor(math.log10(abs(x)))) + 1
	put_number(&l, f, p, x, clamp(digits - whole, 0, 12), false)
	return
}

// put_number writes the prefix, x to decimals places (with thousands
// separators when grouped) and times ten to exp10 if that is not 0, then
// the SI symbol and unit.
@(private)
put_number :: proc(
	l: ^Label,
	f: Number_Format,
	p: Prefix,
	x: f64,
	decimals: int,
	grouped: bool,
	exp10 := 0,
) {
	x := x
	rounded := math.round(x * math.pow(10, f64(decimals))) / math.pow(10, f64(decimals))
	if rounded == 0 {
		x = 0 // never "-0"
	}
	if x < 0 {
		put_text(l, "−")
		x = -x
	}
	put_text(l, f.prefix)
	digits: [64]u8
	s := strconv.write_float(digits[:], x, 'f', decimals, 64)
	if len(s) > 0 && (s[0] == '+' || s[0] == '-') {
		s = s[1:]
	}
	if grouped {
		put_grouped(l, s)
	} else {
		put_text(l, s)
	}
	if exp10 != 0 {
		put_exponent(l, exp10)
	}
	if p.symbol == "" && f.unit == "" {
		return
	}
	if f.space {
		put_text(l, " ")
	}
	put_text(l, p.symbol)
	put_text(l, f.unit)
}

// put_exponent writes e as "e" and the power: e−11, e15.
@(private)
put_exponent :: proc(l: ^Label, e: int) {
	put_text(l, "e")
	if e < 0 {
		put_text(l, "−")
	}
	digits: [24]u8
	put_text(l, strconv.write_int(digits[:], i64(abs(e)), 10))
}

// put_grouped writes the decimal string s with a comma between each three
// whole digits.
@(private)
put_grouped :: proc(l: ^Label, s: string) {
	whole := len(s)
	for i in 0 ..< len(s) {
		if s[i] == '.' {
			whole = i
			break
		}
	}
	for i in 0 ..< whole {
		if i > 0 && (whole - i) % 3 == 0 {
			put_text(l, ",")
		}
		put_text(l, s[i:i + 1])
	}
	put_text(l, s[whole:])
}
