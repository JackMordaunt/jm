package main

import "core:fmt"
import "core:strconv"
import "core:strings"

// Kind is what a token's value is once its Kotlin expression is read.
Kind :: enum {
	Number,
	Dimension,   // dp or sp; num holds the amount
	Duration,    // milliseconds
	Color,
	Cubic_Bezier,
	Corner,      // per-corner radii, or full (half the shorter side)
	Font_Family,
	Font_Weight,
	Typography,  // a composite of five references into sys.typescale
	Ref,         // an alias of another token's path
}

Corner :: struct {
	radii: [4]f64, // top-start, top-end, bottom-end, bottom-start, in dp
	full:  bool,
}

TYPOGRAPHY_FIELDS :: [5]string{"fontFamily", "fontWeight", "fontSize", "lineHeight", "letterSpacing"}

Value :: struct {
	kind:   Kind,
	num:    f64,
	unit:   string, // "dp" or "sp" for Dimension
	color:  [3]u8,
	bezier: [4]f64,
	corner: Corner,
	text:   string,    // Font_Family name, or Ref target path
	typo:   [5]string, // Typography: target paths, in TYPOGRAPHY_FIELDS order
}

Mode_Value :: struct {
	mode:  string,
	value: Value,
}

// Token is one design token. The Kotlin source defines some tokens twice:
// light and dark colour, expressive and standard springs. The first mode in
// the list is the default one; the rest are alternates.
Token :: struct {
	path:   string,
	modes:  [dynamic]Mode_Value,
	source: string, // file:line of the default definition
}

Tokens :: struct {
	order:  [dynamic]^Token,
	byPath: map[string]^Token,
	// keys maps each enum-like key (ColorSchemeKeyTokens.Primary) to the
	// path it stands for; check verifies that path is defined.
	keys:   map[string]string,
	errors: [dynamic]string,
}

// Objects whose members are keys, not values: `val Primary = ColorToken(25)`.
KEY_OBJECTS :: []string{"ColorSchemeKeyTokens", "ShapeKeyTokens", "TypographyKeyTokens", "MotionSchemeKeyTokens"}

// mode_of names the alternate mode an object defines, or "" for a default.
mode_of :: proc(object: string) -> string {
	switch object {
	case "ColorDarkTokens":
		return "dark"
	case "StandardMotionTokens":
		return "standard"
	}
	return ""
}

// default_mode is the name the default value carries for objects that
// have an alternate, so the JSON can say what each mode is.
default_mode :: proc(path: string) -> string {
	if strings.has_prefix(path, "sys.color.") {
		return "light"
	}
	if strings.has_prefix(path, "sys.motion.spring.") {
		return "expressive"
	}
	return ""
}

// kebab turns PascalCase into kebab-case: XLargeIconButton -> x-large-icon-button.
// A digit never starts a new word, so Level3 stays level3.
kebab :: proc(s: string, allocator := context.allocator) -> string {
	sb := strings.builder_make(allocator)
	for i in 0 ..< len(s) {
		c := s[i]
		upper := c >= 'A' && c <= 'Z'
		if upper && i > 0 {
			prev := s[i - 1]
			prevLower := (prev >= 'a' && prev <= 'z') || (prev >= '0' && prev <= '9')
			prevUpper := prev >= 'A' && prev <= 'Z'
			nextLower := i + 1 < len(s) && s[i + 1] >= 'a' && s[i + 1] <= 'z'
			if prevLower || (prevUpper && nextLower) {
				strings.write_byte(&sb, '-')
			}
		}
		strings.write_byte(&sb, upper ? c + ('a' - 'A') : c)
	}
	return strings.to_string(sb)
}

// path_of maps a Kotlin object member to its token path.
path_of :: proc(object, member: string) -> string {
	switch object {
	case "PaletteTokens":
		// Primary40 -> ref.palette.primary.40
		i := len(member)
		for i > 0 && member[i - 1] >= '0' && member[i - 1] <= '9' {
			i -= 1
		}
		if i == len(member) {
			return fmt.aprintf("ref.palette.%s", kebab(member))
		}
		return fmt.aprintf("ref.palette.%s.%s", kebab(member[:i]), member[i:])
	case "TypefaceTokens":
		return fmt.aprintf("ref.typeface.%s", kebab(member))
	case "ColorSchemeKeyTokens", "ColorLightTokens", "ColorDarkTokens":
		return fmt.aprintf("sys.color.%s", kebab(member))
	case "ShapeKeyTokens", "ShapeTokens":
		if rest, ok := strings.substring_from(member, len("CornerValue")); ok && strings.has_prefix(member, "CornerValue") {
			return fmt.aprintf("sys.shape.corner-value.%s", kebab(rest))
		}
		return fmt.aprintf("sys.shape.corner.%s", kebab(strings.trim_prefix(member, "Corner")))
	case "TypographyKeyTokens", "TypographyTokens":
		return fmt.aprintf("sys.typography.%s", kebab(member))
	case "TypeScaleTokens":
		// BodyLargeLineHeight -> sys.typescale.body-large.line-height
		for suffix in ([]string{"LineHeight", "Font", "Size", "Tracking", "Weight"}) {
			if strings.has_suffix(member, suffix) {
				style := member[:len(member) - len(suffix)]
				return fmt.aprintf("sys.typescale.%s.%s", kebab(style), kebab(suffix))
			}
		}
		return fmt.aprintf("sys.typescale.%s", kebab(member))
	case "ElevationTokens":
		return fmt.aprintf("sys.elevation.%s", kebab(member))
	case "StateTokens":
		return fmt.aprintf("sys.state.%s", kebab(member))
	case "MotionTokens":
		if strings.has_prefix(member, "Duration") {
			return fmt.aprintf("sys.motion.duration.%s", kebab(strings.trim_prefix(member, "Duration")))
		}
		name := strings.trim_suffix(strings.trim_prefix(member, "Easing"), "CubicBezier")
		return fmt.aprintf("sys.motion.easing.%s", kebab(name))
	case "ExpressiveMotionTokens", "StandardMotionTokens", "MotionSchemeKeyTokens":
		// SpringDefaultSpatialDamping -> sys.motion.spring.default-spatial.damping
		name := strings.trim_prefix(member, "Spring")
		for suffix in ([]string{"Damping", "Stiffness"}) {
			if strings.has_suffix(name, suffix) {
				return fmt.aprintf("sys.motion.spring.%s.%s", kebab(name[:len(name) - len(suffix)]), kebab(suffix))
			}
		}
		return fmt.aprintf("sys.motion.spring.%s", kebab(name))
	}
	return fmt.aprintf("comp.%s.%s", kebab(strings.trim_suffix(object, "Tokens")), kebab(member))
}

// Decl is one Kotlin declaration, joined onto a single line.
Decl :: struct {
	object: string,
	name:   string,
	expr:   string,
	line:   int,
}

// declarations splits a generated token file into its member declarations.
// The generator writes one of three forms, any of which may wrap:
//
//	const val Name = 0.12f
//	val Name = Expr
//	inline val Name: Type
//	    get() = Expr
declarations :: proc(src: string, file: string, t: ^Tokens) -> [dynamic]Decl {
	decls: [dynamic]Decl
	object := ""
	cur: strings.Builder
	curLine := 0
	flush :: proc(decls: ^[dynamic]Decl, object: string, cur: ^strings.Builder, line: int, file: string, t: ^Tokens) {
		text := strings.to_string(cur^)
		if len(text) == 0 {
			return
		}
		defer strings.builder_reset(cur)
		text = strings.trim_prefix(text, "const ")
		text = strings.trim_prefix(text, "inline ")
		text = strings.trim_prefix(text, "val ")
		nameEnd := strings.index_any(text, ": =")
		if nameEnd < 0 {
			append(&t.errors, fmt.aprintf("%s:%d: cannot find a name in %q", file, line, text))
			return
		}
		name := text[:nameEnd]
		expr := ""
		if g := strings.index(text, "get() ="); g >= 0 {
			expr = text[g + len("get() ="):]
		} else if e := strings.index(text, "="); e >= 0 {
			expr = text[e + 1:]
		} else {
			append(&t.errors, fmt.aprintf("%s:%d: %s has no value", file, line, name))
			return
		}
		append(decls, Decl{object, strings.clone(name), strings.clone(strings.trim_space(expr)), line})
	}

	lineNo := 0
	rest := src
	for raw in strings.split_lines_iterator(&rest) {
		lineNo += 1
		// Comments carry upstream TODOs; no token file puts "//" inside a value.
		code := raw
		if c := strings.index(code, "//"); c >= 0 {
			code = code[:c]
		}
		line := strings.trim_space(code)
		if object == "" {
			if strings.has_prefix(line, "internal object ") {
				object = strings.trim_space(strings.trim_suffix(strings.trim_prefix(line, "internal object "), "{"))
			} else if strings.has_prefix(line, "internal class ") {
				decl := strings.trim_prefix(line, "internal class ")
				object = decl[:strings.index_any(decl, "( {")]
			}
			continue
		}
		if raw == "}" {
			// The object's closing brace, at column zero; what follows
			// (TypographyTokens' DefaultTextStyle) is not a token.
			flush(&decls, object, &cur, curLine, file, t)
			break
		}
		if len(line) == 0 {
			continue
		}
		if strings.has_prefix(line, "val ") || strings.has_prefix(line, "inline val ") || strings.has_prefix(line, "const val ") {
			flush(&decls, object, &cur, curLine, file, t)
			curLine = lineNo
			strings.write_string(&cur, line)
			continue
		}
		if strings.builder_len(cur) == 0 {
			append(&t.errors, fmt.aprintf("%s:%d: unexpected line %q", file, lineNo, line))
			continue
		}
		strings.write_byte(&cur, ' ')
		strings.write_string(&cur, line)
	}
	if object == "" {
		append(&t.errors, fmt.aprintf("%s: no token object found", file))
	}
	return decls
}

// Call is `Name(a, key = b, ...)` split into its parts.
Call :: struct {
	name: string,
	args: [dynamic]Arg,
}

Arg :: struct {
	key, value: string,
}

parse_call :: proc(expr: string) -> (c: Call, ok: bool) {
	open := strings.index_byte(expr, '(')
	if open < 0 || !strings.has_suffix(expr, ")") {
		return {}, false
	}
	c.name = strings.trim_space(expr[:open])
	for part in strings.split(expr[open + 1:len(expr) - 1], ",") {
		p := strings.trim_space(part)
		if len(p) == 0 {
			continue // the generator leaves a trailing comma
		}
		if eq := strings.index(p, " = "); eq >= 0 {
			append(&c.args, Arg{strings.trim_space(p[:eq]), strings.trim_space(p[eq + 3:])})
		} else {
			append(&c.args, Arg{"", p})
		}
	}
	return c, true
}

parse_number :: proc(s: string) -> (f64, bool) {
	return strconv.parse_f64(strings.trim_suffix(s, "f"))
}

// parse_unit reads `56.0.dp` or `16.sp`.
parse_unit :: proc(s, unit: string) -> (f64, bool) {
	if !strings.has_suffix(s, unit) {
		return 0, false
	}
	return strconv.parse_f64(s[:len(s) - len(unit)])
}

// parse_value reads one declaration's expression into a Value. It is
// strict on purpose: a shape the generator has not produced before is an
// error, so a changed upstream is noticed rather than half-read.
parse_value :: proc(d: Decl) -> (v: Value, isKey: bool, err: string) {
	e := d.expr
	if n, ok := parse_unit(e, ".dp"); ok {
		return Value{kind = .Dimension, num = n, unit = "dp"}, false, ""
	}
	if n, ok := parse_unit(e, ".sp"); ok {
		return Value{kind = .Dimension, num = n, unit = "sp"}, false, ""
	}
	if n, ok := parse_number(e); ok {
		if d.object == "MotionTokens" && strings.has_prefix(d.name, "Duration") {
			return Value{kind = .Duration, num = n}, false, ""
		}
		return Value{kind = .Number, num = n}, false, ""
	}
	switch e {
	case "CircleShape":
		return Value{kind = .Corner, corner = {full = true}}, false, ""
	case "RectangleShape":
		return Value{kind = .Corner}, false, ""
	case "FontFamily.SansSerif":
		return Value{kind = .Font_Family, text = "sans-serif"}, false, ""
	case "FontWeight.Normal":
		return Value{kind = .Font_Weight, num = 400}, false, ""
	case "FontWeight.Medium":
		return Value{kind = .Font_Weight, num = 500}, false, ""
	case "FontWeight.Bold":
		return Value{kind = .Font_Weight, num = 700}, false, ""
	}
	if c, ok := parse_call(e); ok {
		switch c.name {
		case "ColorToken", "ShapeToken", "TypographyToken", "MotionSchemeToken":
			return {}, true, ""
		case "Color":
			if len(c.args) != 3 {
				break
			}
			for a, i in c.args {
				n, nok := strconv.parse_int(a.value)
				if !nok || n < 0 || n > 255 {
					return {}, false, fmt.aprintf("bad colour channel %q", a.value)
				}
				v.color[i] = u8(n)
			}
			v.kind = .Color
			return v, false, ""
		case "CubicBezierEasing":
			if len(c.args) != 4 {
				break
			}
			for a, i in c.args {
				n, nok := parse_number(a.value)
				if !nok {
					return {}, false, fmt.aprintf("bad easing point %q", a.value)
				}
				v.bezier[i] = n
			}
			v.kind = .Cubic_Bezier
			return v, false, ""
		case "CornerSize":
			if len(c.args) == 1 {
				if n, nok := parse_unit(c.args[0].value, ".dp"); nok {
					return Value{kind = .Dimension, num = n, unit = "dp"}, false, ""
				}
			}
		case "RoundedCornerShape":
			v.kind = .Corner
			if len(c.args) == 1 && c.args[0].key == "" {
				n, nok := parse_unit(c.args[0].value, ".dp")
				if !nok {
					break
				}
				v.corner.radii = {n, n, n, n}
				return v, false, ""
			}
			seen := 0
			for a in c.args {
				n, nok := parse_unit(a.value, ".dp")
				if !nok {
					return {}, false, fmt.aprintf("bad corner %q", a.value)
				}
				switch a.key {
				case "topStart":
					v.corner.radii[0] = n
				case "topEnd":
					v.corner.radii[1] = n
				case "bottomEnd":
					v.corner.radii[2] = n
				case "bottomStart":
					v.corner.radii[3] = n
				case:
					return {}, false, fmt.aprintf("unknown corner %q", a.key)
				}
				seen += 1
			}
			if seen == 4 {
				return v, false, ""
			}
		case "DefaultTextStyle.copy":
			v.kind = .Typography
			fields := TYPOGRAPHY_FIELDS
			for a in c.args {
				ref := a.value
				// fontFamily = fontFamily ?: TypeScaleTokens.BodyLargeFont
				if q := strings.index(ref, "?:"); q >= 0 {
					ref = strings.trim_space(ref[q + 2:])
				}
				found := false
				for f, i in fields {
					if f == a.key {
						p, pok := ref_path(ref, d.object)
						if !pok {
							return {}, false, fmt.aprintf("bad typography reference %q", ref)
						}
						v.typo[i] = p
						found = true
					}
				}
				if !found {
					return {}, false, fmt.aprintf("unknown typography field %q", a.key)
				}
			}
			for p, i in v.typo {
				if p == "" {
					return {}, false, fmt.aprintf("typography is missing %s", fields[i])
				}
			}
			return v, false, ""
		}
		return {}, false, fmt.aprintf("unrecognised call %q", e)
	}
	if p, ok := ref_path(e, d.object); ok {
		return Value{kind = .Ref, text = p}, false, ""
	}
	return {}, false, fmt.aprintf("unrecognised expression %q", e)
}

// ref_path reads `ColorSchemeKeyTokens.Primary`, or a bare `Primary`
// naming a member of the same object.
ref_path :: proc(e, object: string) -> (string, bool) {
	is_ident :: proc(s: string) -> bool {
		if len(s) == 0 || !(s[0] >= 'A' && s[0] <= 'Z') {
			return false
		}
		for c in transmute([]u8)s {
			if !((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')) {
				return false
			}
		}
		return true
	}
	if dot := strings.index_byte(e, '.'); dot >= 0 {
		obj, member := e[:dot], e[dot + 1:]
		if strings.has_suffix(obj, "Tokens") && is_ident(obj) && is_ident(member) {
			return path_of(obj, member), true
		}
		return "", false
	}
	if is_ident(e) {
		return path_of(object, e), true
	}
	return "", false
}

// add_file parses one token file into t.
add_file :: proc(t: ^Tokens, src, file: string) {
	decls := declarations(src, file, t)
	for d in decls {
		loc := fmt.aprintf("%s:%d", file, d.line)
		v, isKey, err := parse_value(d)
		if err != "" {
			append(&t.errors, fmt.aprintf("%s: %s: %s", loc, d.name, err))
			continue
		}
		path := path_of(d.object, d.name)
		if isKey {
			t.keys[fmt.aprintf("%s.%s", d.object, d.name)] = path
			continue
		}
		mode := mode_of(d.object)
		tok, exists := t.byPath[path]
		if !exists {
			tok = new(Token)
			tok.path = path
			t.byPath[path] = tok
			append(&t.order, tok)
		}
		if mode == "" {
			if len(tok.modes) > 0 && tok.modes[0].mode == default_mode(path) && tok.source != "" {
				append(&t.errors, fmt.aprintf("%s: %s is already defined at %s", loc, path, tok.source))
				continue
			}
			inject_at(&tok.modes, 0, Mode_Value{default_mode(path), v})
			tok.source = loc
		} else {
			append(&tok.modes, Mode_Value{mode, v})
		}
	}
}

// check verifies the parsed set is whole: every token has a default value,
// every reference lands on a token, every key names something defined.
check :: proc(t: ^Tokens) {
	for tok in t.order {
		if tok.source == "" {
			append(&t.errors, fmt.aprintf("%s has only a %s value", tok.path, tok.modes[0].mode))
			continue
		}
		for m in tok.modes {
			switch m.value.kind {
			case .Ref:
				if _, ok := t.byPath[m.value.text]; !ok {
					append(&t.errors, fmt.aprintf("%s: %s refers to undefined %s", tok.source, tok.path, m.value.text))
				}
			case .Typography:
				for p in m.value.typo {
					if _, ok := t.byPath[p]; !ok {
						append(&t.errors, fmt.aprintf("%s: %s refers to undefined %s", tok.source, tok.path, p))
					}
				}
			case .Number, .Dimension, .Duration, .Color, .Cubic_Bezier, .Corner, .Font_Family, .Font_Weight:
			}
		}
	}
	for key, path in t.keys {
		if _, ok := t.byPath[path]; ok {
			continue
		}
		// A motion scheme key names a spring, which is a pair of tokens.
		if _, ok := t.byPath[fmt.tprintf("%s.damping", path)]; ok {
			continue
		}
		append(&t.errors, fmt.aprintf("key %s names undefined %s", key, path))
	}
}

// resolve follows references until it reaches a value, in the given mode
// where a token defines one, else in its default.
resolve :: proc(t: ^Tokens, path, mode: string) -> (v: Value, ok: bool) {
	p := path
	for _ in 0 ..< 16 {
		tok, found := t.byPath[p]
		if !found {
			return {}, false
		}
		v = tok.modes[0].value
		for m in tok.modes[1:] {
			if m.mode == mode {
				v = m.value
			}
		}
		if v.kind != .Ref {
			return v, true
		}
		p = v.text
	}
	return {}, false
}

// alt_modes lists every alternate mode anywhere along path's reference
// chain, so a component colour learns it has a dark value.
alt_modes :: proc(t: ^Tokens, path: string, out: ^[dynamic]string) {
	p := path
	for _ in 0 ..< 16 {
		tok, found := t.byPath[p]
		if !found {
			return
		}
		for m in tok.modes[1:] {
			if !contains(out[:], m.mode) {
				append(out, m.mode)
			}
		}
		if tok.modes[0].value.kind == .Typography {
			for sub in tok.modes[0].value.typo {
				alt_modes(t, sub, out)
			}
			return
		}
		if tok.modes[0].value.kind != .Ref {
			return
		}
		p = tok.modes[0].value.text
	}
}

contains :: proc(list: []string, s: string) -> bool {
	for x in list {
		if x == s {
			return true
		}
	}
	return false
}
