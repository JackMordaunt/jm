package main

import "core:fmt"
import "core:math"
import "core:strconv"
import "core:strings"

Source :: struct {
	repo, commit, path: string,
}

// num writes a number in its shortest form: 56, 0.12, -4.5.
num :: proc(sb: ^strings.Builder, f: f64) {
	if f == math.floor(f) && abs(f) < 1e15 {
		fmt.sbprintf(sb, "%d", i64(f))
		return
	}
	buf: [64]u8
	strings.write_string(sb, strings.trim_prefix(strconv.write_float(buf[:], f, 'g', -1, 64), "+"))
}

hex :: proc(c: [3]u8) -> string {
	return fmt.tprintf("#%02x%02x%02x", c[0], c[1], c[2])
}

// dtcg_type is the $type a kind is written under. DTCG has no spring or
// shape type; shape is this kit's own, documented in the README.
dtcg_type :: proc(k: Kind) -> string {
	switch k {
	case .Number:
		return "number"
	case .Dimension:
		return "dimension"
	case .Duration:
		return "duration"
	case .Color:
		return "color"
	case .Cubic_Bezier:
		return "cubicBezier"
	case .Corner:
		return "shape"
	case .Font_Family:
		return "fontFamily"
	case .Font_Weight:
		return "fontWeight"
	case .Typography:
		return "typography"
	case .Ref:
	}
	return ""
}

dimension :: proc(sb: ^strings.Builder, n: f64, unit: string) {
	strings.write_string(sb, `{"value": `)
	num(sb, n)
	fmt.sbprintf(sb, `, "unit": "%s"}`, unit)
}

// dtcg_value writes a value in DTCG 2025.10 form: dp and sp become px,
// the unit they equal at density 1.
dtcg_value :: proc(sb: ^strings.Builder, v: Value) {
	switch v.kind {
	case .Number, .Font_Weight:
		num(sb, v.num)
	case .Dimension:
		dimension(sb, v.num, "px")
	case .Duration:
		dimension(sb, v.num, "ms")
	case .Color:
		strings.write_string(sb, `{"colorSpace": "srgb", "components": [`)
		for c, i in v.color {
			if i > 0 {
				strings.write_string(sb, ", ")
			}
			num(sb, math.round(f64(c) / 255 * 10000) / 10000)
		}
		fmt.sbprintf(sb, `], "hex": "%s"}`, hex(v.color))
	case .Cubic_Bezier:
		strings.write_byte(sb, '[')
		for p, i in v.bezier {
			if i > 0 {
				strings.write_string(sb, ", ")
			}
			num(sb, p)
		}
		strings.write_byte(sb, ']')
	case .Corner:
		names := [4]string{"topStart", "topEnd", "bottomEnd", "bottomStart"}
		strings.write_byte(sb, '{')
		for n, i in names {
			if i > 0 {
				strings.write_string(sb, ", ")
			}
			fmt.sbprintf(sb, `"%s": `, n)
			if v.corner.full {
				dimension(sb, 50, "%")
			} else {
				dimension(sb, v.corner.radii[i], "px")
			}
		}
		strings.write_byte(sb, '}')
	case .Font_Family:
		fmt.sbprintf(sb, `"%s"`, v.text)
	case .Typography:
		fields := TYPOGRAPHY_FIELDS
		strings.write_byte(sb, '{')
		for f, i in fields {
			if i > 0 {
				strings.write_string(sb, ", ")
			}
			fmt.sbprintf(sb, `"%s": "{{%s}}"`, f, v.typo[i])
		}
		strings.write_byte(sb, '}')
	case .Ref:
		fmt.sbprintf(sb, `"{{%s}}"`, v.text)
	}
}

Node :: struct {
	key:      string,
	children: [dynamic]^Node,
	token:    ^Token,
}

child :: proc(n: ^Node, key: string) -> ^Node {
	for c in n.children {
		if c.key == key {
			return c
		}
	}
	c := new(Node)
	c.key = key
	append(&n.children, c)
	return c
}

group_description :: proc(path: string) -> (string, bool) {
	switch path {
	case "ref":
		return "Reference tokens: the raw palette and typefaces. Components never use these directly.", true
	case "sys":
		return "System tokens: the roles components are built from. Colour and springs carry a second mode in $extensions.", true
	case "comp":
		return "Component tokens, one group per component variant, aliasing sys tokens.", true
	case "sys.color":
		return "Colour roles. $value is the light scheme; $extensions.m3e.modes.dark the dark one.", true
	case "sys.motion.spring":
		return "Spring physics: damping ratio and stiffness (N/m, unit mass). $value is the Expressive motion scheme; $extensions.m3e.modes.standard the Standard one.", true
	case "sys.shape.corner":
		return "Corner shapes. A 50% radius means half the component's shorter side (a pill or circle).", true
	case "sys.typescale":
		return "Type scale properties. Sizes, line heights and tracking are in sp, written as px.", true
	case "sys.typography":
		return "Composite text styles built from sys.typescale.", true
	}
	return "", false
}

// write_dtcg renders the token set as one DTCG document, references intact.
write_dtcg :: proc(t: ^Tokens, src: Source) -> string {
	root := new(Node)
	for top in ([]string{"ref", "sys", "comp"}) {
		child(root, top)
	}
	for tok in t.order {
		n := root
		for part in strings.split(tok.path, ".", context.temp_allocator) {
			if n.token != nil {
				append(&t.errors, fmt.aprintf("%s is both a token and a group", n.token.path))
			}
			n = child(n, part)
		}
		n.token = tok
	}

	sb := strings.builder_make()
	strings.write_string(&sb, "{\n")
	strings.write_string(&sb, `  "$description": "Material 3 Expressive design tokens, parsed from the Jetpack Compose Material 3 token sources. 1 dp = 1 px at density 1; sp likewise before font scaling.",`)
	fmt.sbprintf(&sb, "\n  \"$extensions\": {{\"m3e.source\": {{\"repo\": \"%s\", \"commit\": \"%s\", \"path\": \"%s\"}}}},\n", src.repo, src.commit, src.path)
	write_children(&sb, t, root, "", 1)
	strings.write_string(&sb, "\n}\n")
	return strings.to_string(sb)
}

write_children :: proc(sb: ^strings.Builder, t: ^Tokens, n: ^Node, prefix: string, depth: int) {
	indent := strings.repeat("  ", depth, context.temp_allocator)
	for c, i in n.children {
		if i > 0 {
			strings.write_string(sb, ",\n")
		}
		path := prefix == "" ? c.key : fmt.tprintf("%s.%s", prefix, c.key)
		fmt.sbprintf(sb, `%s"%s": {{`, indent, c.key)
		if c.token != nil {
			write_token(sb, t, c.token)
			strings.write_byte(sb, '}')
			continue
		}
		strings.write_byte(sb, '\n')
		if d, ok := group_description(path); ok {
			fmt.sbprintf(sb, "%s  \"$description\": \"%s\",\n", indent, d)
		}
		write_children(sb, t, c, path, depth + 1)
		fmt.sbprintf(sb, "\n%s}}", indent)
	}
}

write_token :: proc(sb: ^strings.Builder, t: ^Tokens, tok: ^Token) {
	v := tok.modes[0].value
	typ := dtcg_type(v.kind)
	if v.kind == .Ref {
		r, _ := resolve(t, tok.path, "")
		typ = dtcg_type(r.kind)
	}
	fmt.sbprintf(sb, `"$type": "%s", "$value": `, typ)
	dtcg_value(sb, v)
	if len(tok.modes) > 1 {
		strings.write_string(sb, `, "$extensions": {"m3e.modes": {`)
		for m, i in tok.modes[1:] {
			if i > 0 {
				strings.write_string(sb, ", ")
			}
			fmt.sbprintf(sb, `"%s": `, m.mode)
			dtcg_value(sb, m.value)
		}
		strings.write_string(sb, "}}")
	}
}

// resolved_value writes a fully resolved value in plain units: colours as
// hex, dimensions as dp, durations as ms, corners as four radii or "full".
resolved_value :: proc(sb: ^strings.Builder, t: ^Tokens, v: Value, mode: string) {
	switch v.kind {
	case .Number, .Font_Weight, .Dimension, .Duration:
		num(sb, v.num)
	case .Color:
		fmt.sbprintf(sb, `"%s"`, hex(v.color))
	case .Cubic_Bezier:
		dtcg_value(sb, v)
	case .Corner:
		if v.corner.full {
			strings.write_string(sb, `"full"`)
			return
		}
		strings.write_byte(sb, '[')
		for r, i in v.corner.radii {
			if i > 0 {
				strings.write_string(sb, ", ")
			}
			num(sb, r)
		}
		strings.write_byte(sb, ']')
	case .Font_Family:
		fmt.sbprintf(sb, `"%s"`, v.text)
	case .Typography:
		fields := TYPOGRAPHY_FIELDS
		strings.write_byte(sb, '{')
		for f, i in fields {
			if i > 0 {
				strings.write_string(sb, ", ")
			}
			fmt.sbprintf(sb, `"%s": `, f)
			sub, _ := resolve(t, v.typo[i], mode)
			resolved_value(sb, t, sub, mode)
		}
		strings.write_byte(sb, '}')
	case .Ref:
		r, _ := resolve(t, v.text, mode)
		resolved_value(sb, t, r, mode)
	}
}

// write_resolved renders every token flat, keyed by path, with each
// reference followed to its final value in every mode it touches.
write_resolved :: proc(t: ^Tokens, src: Source) -> string {
	sb := strings.builder_make()
	strings.write_string(&sb, "{\n")
	strings.write_string(&sb, `  "description": "Material 3 Expressive tokens, every reference resolved. value is the default mode (light colour, Expressive springs); dark and standard give the other mode where the token depends on it. alias is the token this one points at. Units: dimensions dp (text sp), durations ms, corners [top-start, top-end, bottom-end, bottom-start] dp or \"full\".",`)
	fmt.sbprintf(&sb, "\n  \"source\": {{\"repo\": \"%s\", \"commit\": \"%s\", \"path\": \"%s\"}},\n", src.repo, src.commit, src.path)
	strings.write_string(&sb, "  \"tokens\": {\n")
	for tok, i in t.order {
		if i > 0 {
			strings.write_string(&sb, ",\n")
		}
		v, _ := resolve(t, tok.path, "")
		fmt.sbprintf(&sb, `    "%s": {{"type": "%s", "value": `, tok.path, dtcg_type(v.kind))
		resolved_value(&sb, t, v, "")
		modes: [dynamic]string
		alt_modes(t, tok.path, &modes)
		for m in modes {
			mv, _ := resolve(t, tok.path, m)
			fmt.sbprintf(&sb, `, "%s": `, m)
			resolved_value(&sb, t, mv, m)
		}
		if tok.modes[0].value.kind == .Ref {
			fmt.sbprintf(&sb, `, "alias": "%s"`, tok.modes[0].value.text)
		}
		strings.write_byte(&sb, '}')
	}
	strings.write_string(&sb, "\n  }\n}\n")
	return strings.to_string(sb)
}
