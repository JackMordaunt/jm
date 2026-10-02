// design-tokens writes a jm:ui design system's tokens package from its
// kit's resolved token file: every token as a typed Odin constant, and the
// colour roles' values per mode.
//
//	design-tokens material tools/material/tokens/m3e.resolved.json ui/material/tokens/tokens.odin
//	design-tokens fluent tools/fluent/tokens/fluent.resolved.json ui/fluent/tokens/tokens.odin
//	design-tokens primer tools/primer/tokens/primer.resolved.json ui/primer/tokens/tokens.odin
//
// Every kit writes the same flat shape: {type, value, <mode>: value, alias}
// keyed by path. What differs between them is a Profile: which paths are
// colour roles, which modes exist, what a name drops, and which types the
// kit has (Material's shapes, Fluent's and Primer's shadows).
//
// A colour is never a literal outside the role tables: a colour token is
// the Role its alias chain ends at, and a shadow layer's colour is the
// Role whose binding equals it in every mode, so components follow
// whatever scheme is active. A kit whose shadows carry colours no role
// holds (Primer) gives each layer a role of its own instead. A token
// with a twin mode (the m3e-kit's standard key, its Standard motion
// values; the primer-kit's coarse key, its coarse-pointer sizes) also
// gets a <NAME>_<TWIN> constant. A family token carries nothing: jm:ui
// draws in whatever faces the app gives it, so the tool only checks the
// family is one the kit is expected to name.
package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

// Profile is what one kit's file means.
Profile :: struct {
	role_prefix:  string, // a colour token whose path has it is a role
	skip:         []string, // path prefixes with no constant and no role
	skip_types:   []string, // token types with no constant
	drop:        []string, // path prefixes a constant's name leaves out
	modes:       []Mode, // the role tables, first the default
	twin:        string, // a mode key that gives a <NAME>_<TWIN> constant, or ""
	alpha:       bool, // role values are 0xRRGGBBAA, not 0xRRGGBB
	families:     []string, // a font family token must name one of these
	shadow_roles: bool, // each shadow layer is its own role, with spread and inset
	header:       string, // the file's head: generated-by, package doc, types
}

// MAX_SHADOW_LAYERS is the length of a shadow_roles kit's Shadow.layers.
MAX_SHADOW_LAYERS :: 5

// Mode is one column of the role tables: the key in the file and the
// constant it becomes.
Mode :: struct {
	key, name, doc: string,
}

MATERIAL :: Profile {
	role_prefix = "sys.color.",
	skip        = {"ref."},
	drop        = {"comp."},
	modes       = {{"value", "LIGHT", "the baseline light scheme"}, {"dark", "DARK", "the baseline dark scheme"}},
	twin        = "standard",
	families    = {"sans-serif"},
	header      = MATERIAL_HEADER,
}

FLUENT :: Profile {
	role_prefix = "tokens.color",
	drop        = {"tokens."},
	modes       = {
		{"value", "WEB_LIGHT", "the web light theme"},
		{"dark", "WEB_DARK", "the web dark theme"},
		{"highContrast", "HIGH_CONTRAST", "the Teams high contrast theme"},
		{"teamsLight", "TEAMS_LIGHT", "the Teams light theme"},
		{"teamsDark", "TEAMS_DARK", "the Teams dark theme"},
	},
	alpha       = true,
	families    = {"Segoe UI", "Consolas", "Bahnschrift"},
	header      = FLUENT_HEADER,
}

PRIMER :: Profile {
	role_prefix  = "--",
	skip         = {
		"--color-",
		"--display-",
		"--data-",
		"--prettylights-",
		"--codeMirror-",
		"--diffBlob-",
		"--contribution-",
		"--text-codeInline-shorthand",
		"--focus-outlineColor", // the fallback focusOutline.css reads after --focus-outline-color
	},
	skip_types   = {"border", "custom-string", "custom-viewportRange"},
	drop         = {"--"},
	modes        = {
		{"value", "LIGHT", "the light theme"},
		{"dark", "DARK", "the dark theme"},
		{"darkDimmed", "DARK_DIMMED", "the dark dimmed theme"},
		{
			"lightHighContrast",
			"LIGHT_HIGH_CONTRAST",
			"the light high contrast theme",
		},
		{
			"darkHighContrast",
			"DARK_HIGH_CONTRAST",
			"the dark high contrast theme",
		},
		{
			"darkDimmedHighContrast",
			"DARK_DIMMED_HIGH_CONTRAST",
			"the dark dimmed high contrast theme",
		},
		{"lightColorblind", "LIGHT_COLORBLIND", "the light colorblind theme"},
		{"darkColorblind", "DARK_COLORBLIND", "the dark colorblind theme"},
		{
			"lightColorblindHighContrast",
			"LIGHT_COLORBLIND_HIGH_CONTRAST",
			"the light colorblind high contrast theme",
		},
		{
			"darkColorblindHighContrast",
			"DARK_COLORBLIND_HIGH_CONTRAST",
			"the dark colorblind high contrast theme",
		},
		{"lightTritanopia", "LIGHT_TRITANOPIA", "the light tritanopia theme"},
		{"darkTritanopia", "DARK_TRITANOPIA", "the dark tritanopia theme"},
		{
			"lightTritanopiaHighContrast",
			"LIGHT_TRITANOPIA_HIGH_CONTRAST",
			"the light tritanopia high contrast theme",
		},
		{
			"darkTritanopiaHighContrast",
			"DARK_TRITANOPIA_HIGH_CONTRAST",
			"the dark tritanopia high contrast theme",
		},
	},
	twin         = "coarse",
	alpha        = true,
	families     = {"-apple-system", "ui-monospace"},
	shadow_roles = true,
	header       = PRIMER_HEADER,
}

main :: proc() {
	if len(os.args) != 4 {
		fmt.eprintln("usage: design-tokens <material|fluent|primer> <resolved.json> <out.odin>")
		os.exit(2)
	}
	profile: Profile
	switch os.args[1] {
	case "material":
		profile = MATERIAL
	case "fluent":
		profile = FLUENT
	case "primer":
		profile = PRIMER
	case:
		fmt.eprintfln("no kit %q", os.args[1])
		os.exit(2)
	}
	data, err := os.read_entire_file(os.args[2], context.allocator)
	if err != nil {
		fmt.eprintfln("read %s: %v", os.args[2], err)
		os.exit(1)
	}
	doc, jerr := json.parse(data)
	if jerr != nil {
		fmt.eprintfln("parse %s: %v", os.args[2], jerr)
		os.exit(1)
	}
	toks := doc.(json.Object)["tokens"].(json.Object)
	out, ok := generate(toks, profile)
	if !ok {
		os.exit(1)
	}
	if werr := os.write_entire_file(os.args[3], transmute([]u8)out); werr != nil {
		fmt.eprintfln("write %s: %v", os.args[3], werr)
		os.exit(1)
	}
}

generate :: proc(toks: json.Object, p: Profile) -> (string, bool) {
	keys := make([dynamic]string)
	for k in toks {
		append(&keys, k)
	}
	slice.sort(keys[:])

	b := strings.builder_make()
	fmt.sbprint(&b, p.header)

	// Roles: every colour role token, in path order, then any shadow
	// layers' own roles.
	roles := make([dynamic]Role_Entry)
	for k in keys {
		if is_role(p, k, toks[k].(json.Object)) {
			append(&roles, Role_Entry{role_name(p, k), toks[k].(json.Object)})
		}
	}
	if p.shadow_roles {
		append(&roles, ..shadow_layer_roles(toks, p, keys[:]))
	}
	named := make(map[string]bool)
	for r in roles {
		if named[r.name] {
			fmt.eprintfln("two colour tokens are both role %s", r.name)
			return "", false
		}
		named[r.name] = true
	}
	fmt.sbprintln(&b, "// Role is one colour role. A colour token names the role it aliases.")
	fmt.sbprintfln(&b, "Role :: enum %s {{", len(roles) <= 256 ? "u8" : "u16")
	for r in roles {
		fmt.sbprintfln(&b, "\t%s,", r.name)
	}
	fmt.sbprintln(&b, "}\n")
	for mode in p.modes {
		layout := p.alpha ? "RRGGBBAA" : "RRGGBB"
		fmt.sbprintfln(&b, "// %s is %s, 0x%s per role.", mode.name, mode.doc, layout)
		fmt.sbprintfln(&b, "%s :: [Role]u32 {{", mode.name)
		for r in roles {
			c := mode_value(r.colors, mode.key).(json.String)
			fmt.sbprintfln(&b, "\t.%s = %s,", r.name, hex(c, p.alpha))
		}
		fmt.sbprintln(&b, "}\n")
	}

	if p.shadow_roles {
		fmt.sbprintln(&b, "// Mode is one theme, in the order of the role tables above.")
		fmt.sbprintln(&b, "Mode :: enum u8 {")
		for mode in p.modes {
			fmt.sbprintfln(&b, "\t%s,", mode_enum_name(mode))
		}
		fmt.sbprintln(&b, "}\n")
	}

	seen := make(map[string]string)
	ok := true
	for k in keys {
		t := toks[k].(json.Object)
		skipped := has_any_prefix(k, p.skip) || has_any(t["type"].(json.String), p.skip_types)
		if skipped || is_role(p, k, t) {
			continue
		}
		name := const_name(p, k)
		if prev, dup := seen[name]; dup {
			fmt.eprintfln("%s and %s both name %s", prev, k, name)
			ok = false
			continue
		}
		seen[name] = k
		line, lok := literal(toks, p, k, t, "value")
		ok &&= lok
		if line == "" {
			continue
		}
		fmt.sbprintfln(&b, "%s :: %s", name, line)
		if p.twin != "" {
			if _, has := t[p.twin]; has {
				twin, tok := literal(toks, p, k, t, p.twin)
				ok &&= tok
				fmt.sbprintfln(&b, "%s_%s :: %s", name, strings.to_upper(p.twin), twin)
			}
		}
	}
	return strings.to_string(b), ok
}

// Role_Entry is one colour role: its enum name, and an object holding its
// colour as value plus one key per mode where that mode differs.
Role_Entry :: struct {
	name:   string,
	colors: json.Object,
}

// is_role says whether token t at path is a colour role.
is_role :: proc(p: Profile, path: string, t: json.Object) -> bool {
	colour := t["type"].(json.String) == "color"
	return colour && strings.has_prefix(path, p.role_prefix) && !has_any_prefix(path, p.skip)
}

// shadow_layer_roles is a role for each layer of each shadow token,
// <PATH>_<i>, coloured as that layer is in every mode.
shadow_layer_roles :: proc(toks: json.Object, p: Profile, keys: []string) -> []Role_Entry {
	out := make([dynamic]Role_Entry)
	for k in keys {
		t := toks[k].(json.Object)
		if t["type"].(json.String) != "shadow" || has_any_prefix(k, p.skip) {
			continue
		}
		for i in 0 ..< len(t["value"].(json.Array)) {
			colors := make(json.Object)
			for mode in p.modes {
				colors[mode.key] = mode_value(t, mode.key).(json.Array)[i].(json.Object)["color"]
			}
			append(&out, Role_Entry{shadow_role_name(p, k, i), colors})
		}
	}
	return out[:]
}

shadow_role_name :: proc(p: Profile, path: string, i: int) -> string {
	return role_name(p, fmt.aprintf("%s-%d", path, i))
}

MATERIAL_HEADER :: `// Code generated by tools/design-tokens from the m3e-kit's
// tokens/m3e.resolved.json. DO NOT EDIT; run just material-tokens.

// Package tokens is Material 3 Expressive's design tokens as constants,
// named after their kit path: comp.button-small.container-height is
// BUTTON_SMALL_CONTAINER_HEIGHT and sys.shape.corner.full is
// SYS_SHAPE_CORNER_FULL. Units are the kit file's: dimensions dp (text
// sp), durations ms, opacities 0-1. The package is named apart from
// ui/fluent/tokens so one program can link both systems.
package material_tokens

import "jm:ui/design"

// Shape is a corner shape: four radii in dp, [top-start, top-end,
// bottom-end, bottom-start], or full, half the shorter side.
Shape :: struct {
	radii: [4]f32,
	full:  bool,
}

// Type_Style and Bezier are jm:ui/design's: a composite typography token
// (sizes in sp) and a CSS cubic-bezier easing, so a token passes straight
// to design's shaping and easing procs.
Type_Style :: design.Type_Style
Bezier :: design.Bezier

`

FLUENT_HEADER :: `// Code generated by tools/design-tokens from the fluent-kit's
// tokens/fluent.resolved.json. DO NOT EDIT; run just fluent-tokens.

// Package tokens is Fluent 2's design tokens as constants, named after
// their kit path with the humps split: tokens.borderRadiusMedium is
// BORDER_RADIUS_MEDIUM, tokens.colorNeutralForeground1Hover is
// Role.Neutral_Foreground1_Hover and typographyStyles.body1Strong is
// TYPOGRAPHY_STYLES_BODY1_STRONG. Units are the kit file's: dimensions
// px, durations ms. The package is named apart from ui/material/tokens
// so one program can link both systems.
package fluent_tokens

import "jm:ui/design"

// Shadow is an elevation token: two layers, ambient then key, each an
// offset and blur in px and the colour role it is painted in.
Shadow :: struct {
	layers: [2]Shadow_Layer,
}

Shadow_Layer :: struct {
	x, y, blur: f32,
	color:      Role,
}

// Type_Style and Bezier are jm:ui/design's: a composite typography token
// (sizes in px, no tracking) and a CSS cubic-bezier easing, so a token
// passes straight to design's shaping and easing procs.
Type_Style :: design.Type_Style
Bezier :: design.Bezier

`

PRIMER_HEADER :: `// Code generated by tools/design-tokens from the primer-kit's
// tokens/primer.resolved.json. DO NOT EDIT; run just primer-tokens.

// Package tokens is Primer's design tokens as constants, named after the
// CSS custom property Primer reads with the humps split:
// --control-medium-size is CONTROL_MEDIUM_SIZE, --fgColor-default is
// Role.Fg_Color_Default, and a size that grows for a coarse pointer has
// a <NAME>_COARSE twin. Units are the kit file's: dimensions px (Em where
// Primer sizes relative to the font), durations ms. Each shadow layer's
// colour is a role of its own, <SHADOW>_<i>: in the kit's
// tokens/primer.resolved.json (@primer/primitives 11.10.0) none of the
// 23 layers matches any colour token in all 14 themes. The package is named apart from
// the other kits' tokens so one program can link them all.
package primer_tokens

import "jm:ui/design"

// Shadow is a CSS box-shadow list in one theme: its first count layers,
// painted in order, each an offset, blur and spread in px, inset or not,
// and the colour role it is painted in. A shadow token is a [Mode]Shadow,
// since seven of the kit's 13 change geometry in the dark themes
// (tokens/primer.resolved.json): --shadow-resting-small's second layer
// blurs 2px in light, 3px in dark.
Shadow :: struct {
	count:  int,
	layers: [5]Shadow_Layer,
}

Shadow_Layer :: struct {
	x, y, blur, spread: f32,
	inset:              bool,
	color:              Role,
}

// Em is a size relative to the font it is set in.
Em :: distinct f32

// Transition is a time-based change: a duration in ms and its easing.
Transition :: struct {
	duration: f32,
	easing:   Bezier,
}

// Type_Style and Bezier are jm:ui/design's: a composite typography token
// (sizes in px, no tracking) and a CSS cubic-bezier easing, so a token
// passes straight to design's shaping and easing procs.
Type_Style :: design.Type_Style
Bezier :: design.Bezier

`

// literal is t's mode value as an Odin constant expression, or "" for a
// token with nothing to carry. ok is false for a value it cannot write.
literal :: proc(toks: json.Object, p: Profile, path: string, t: json.Object, mode: string) -> (string, bool) {
	v := t[mode]
	switch t["type"].(json.String) {
	case "color":
		root, ok := color_root(toks, p, path)
		if !ok {
			fmt.eprintfln("%s: alias chain does not reach a %s role", path, p.role_prefix)
			return "", false
		}
		return fmt.aprintf("Role.%s", role_name(p, root)), true
	case "dimension", "number", "duration", "fontWeight":
		if o, relative := v.(json.Object); relative {
			if o["unit"].(json.String) != "em" {
				fmt.eprintfln("%s: unknown unit %v", path, o["unit"])
				return "", false
			}
			return fmt.aprintf("Em(%v)", number(o["value"])), true
		}
		return fmt.aprintf("f32(%v)", number(v)), true
	case "transition":
		o := v.(json.Object)
		e := o["timingFunction"].(json.Array)
		return fmt.aprintf(
			"Transition{{duration = %v, easing = {{%v, %v, %v, %v}}}}",
			number(o["duration"]),
			number(e[0]),
			number(e[1]),
			number(e[2]),
			number(e[3]),
		), true
	case "fontFamily":
		// jm:ui draws in whatever faces the app gives it, so a family
		// carries nothing, as long as it is one the kit is known to name;
		// anything else is a change worth hearing about.
		f := v.(json.String)
		for want in p.families {
			if strings.contains(f, want) {
				return "", true
			}
		}
		fmt.eprintfln("%s: font family %q names none of %v", path, f, p.families)
		return "", false
	case "cubicBezier":
		a := v.(json.Array)
		return fmt.aprintf("Bezier{{%v, %v, %v, %v}}", number(a[0]), number(a[1]), number(a[2]), number(a[3])), true
	case "shape":
		if s, is_str := v.(json.String); is_str {
			if s != "full" {
				fmt.eprintfln("%s: unknown shape keyword %q", path, s)
				return "", false
			}
			return "Shape{full = true}", true
		}
		a := v.(json.Array)
		return fmt.aprintf("Shape{{radii = {{%v, %v, %v, %v}}}}", number(a[0]), number(a[1]), number(a[2]), number(a[3])), true
	case "shadow":
		return shadow_literal(toks, p, path, t)
	case "typography":
		o := v.(json.Object)
		if _, relative := o["fontSize"].(json.Object); relative {
			fmt.eprintfln("%s: a font size relative to the font has no Type_Style", path)
			return "", false
		}
		return fmt.aprintf(
			"Type_Style{{weight = %v, size = %v, line_height = %v, tracking = %v}}",
			number(o["fontWeight"]),
			number(o["fontSize"]),
			number(o["lineHeight"]),
			number(o["letterSpacing"]),
		), true
	}
	fmt.eprintfln("%s: unknown type %v", path, t["type"])
	return "", false
}

// shadow_literal is t as a Shadow: its two layers' geometry, which must
// be the same in every mode, and for each layer's colour the one role
// bound to that colour in every mode.
shadow_literal :: proc(toks: json.Object, p: Profile, path: string, t: json.Object) -> (string, bool) {
	if p.shadow_roles {
		return layered_shadow_literal(p, path, t)
	}
	layers := t["value"].(json.Array)
	if len(layers) != 2 {
		fmt.eprintfln("%s: %d layers, not 2", path, len(layers))
		return "", false
	}
	parts: [2]string
	for i in 0 ..< 2 {
		l := layers[i].(json.Object)
		for mode in p.modes {
			m := mode_value(t, mode.key).(json.Array)[i].(json.Object)
			if number(m["x"]) != number(l["x"]) || number(m["y"]) != number(l["y"]) || number(m["blur"]) != number(l["blur"]) {
				fmt.eprintfln("%s: layer %d's geometry differs in %s", path, i, mode.key)
				return "", false
			}
		}
		role, ok := color_role_of(toks, p, t, i)
		if !ok {
			fmt.eprintfln("%s: layer %d's colour is no role's binding in every mode", path, i)
			return "", false
		}
		parts[i] = fmt.aprintf("{{%v, %v, %v, .%s}}", number(l["x"]), number(l["y"]), number(l["blur"]), role_name(p, role))
	}
	return fmt.aprintf("Shadow{{layers = {{%s, %s}}}}", parts[0], parts[1]), true
}

// layered_shadow_literal is t as a [Mode]Shadow: per mode, up to
// MAX_SHADOW_LAYERS layers, each painted in its own role. Primer's dark
// themes change some layers' offsets and blurs, so the geometry is per
// mode too; the number of layers must not change, since each layer is
// one role.
layered_shadow_literal :: proc(p: Profile, path: string, t: json.Object) -> (string, bool) {
	n := len(t["value"].(json.Array))
	if n > MAX_SHADOW_LAYERS {
		fmt.eprintfln("%s: %d layers, more than %d", path, n, MAX_SHADOW_LAYERS)
		return "", false
	}
	b := strings.builder_make()
	fmt.sbprintln(&b, "[Mode]Shadow {")
	for mode in p.modes {
		m := mode_value(t, mode.key).(json.Array)
		if len(m) != n {
			fmt.eprintfln("%s: %d layers in %s, %d in value", path, len(m), mode.key, n)
			return "", false
		}
		parts := make([]string, n)
		for i in 0 ..< n {
			l := m[i].(json.Object)
			parts[i] = fmt.aprintf(
				"%d = {{%v, %v, %v, %v, %v, .%s}}",
				i,
				number(l["x"]),
				number(l["y"]),
				number(l["blur"]),
				number(l["spread"]),
				l["inset"].(json.Boolean),
				shadow_role_name(p, path, i),
			)
		}
		layers := strings.join(parts, ", ")
		fmt.sbprintfln(&b, "\t.%s = {{count = %d, layers = {{%s}}}},", mode_enum_name(mode), n, layers)
	}
	fmt.sbprint(&b, "}")
	return strings.to_string(b), true
}

// mode_enum_name is a mode as a Mode member: DARK_DIMMED is Dark_Dimmed.
mode_enum_name :: proc(m: Mode) -> string {
	ws := strings.split(strings.to_lower(m.name), "_")
	for &w in ws {
		w = capitalise(w)
	}
	return strings.join(ws, "_")
}

// color_role_of is the one role whose colour equals shadow t's layer i
// colour in every mode. Two roles with that binding would be ambiguous,
// so that is a failure too.
color_role_of :: proc(toks: json.Object, p: Profile, t: json.Object, i: int) -> (string, bool) {
	found := ""
	for path, v in toks {
		if !strings.has_prefix(path, p.role_prefix) {
			continue
		}
		r := v.(json.Object)
		same := true
		for mode in p.modes {
			want := mode_value(t, mode.key).(json.Array)[i].(json.Object)["color"].(json.String)
			if mode_value(r, mode.key).(json.String) != want {
				same = false
				break
			}
		}
		if same {
			if found != "" {
				return "", false
			}
			found = path
		}
	}
	return found, found != ""
}

// mode_value is t's value in mode, or its default value where the mode
// does not differ.
mode_value :: proc(t: json.Object, mode: string) -> json.Value {
	if v, has := t[mode]; has {
		return v
	}
	return t["value"]
}

number :: proc(v: json.Value) -> f64 {
	#partial switch n in v {
	case json.Float:
		return f64(n)
	case json.Integer:
		return f64(n)
	}
	return 0
}

// hex is a #rrggbb or #rrggbbaa colour as an Odin literal: 0xRRGGBB, or
// with alpha 0xRRGGBBAA, an opaque colour widened to ff.
hex :: proc(s: string, alpha: bool) -> string {
	h := strings.trim_prefix(s, "#")
	if alpha && len(h) == 6 {
		return fmt.aprintf("0x%sff", h)
	}
	if !alpha && len(h) == 8 {
		return fmt.aprintf("0x%s", h[:6])
	}
	return fmt.aprintf("0x%s", h)
}

// color_root follows path's alias chain to the role it ends at.
color_root :: proc(toks: json.Object, p: Profile, path: string) -> (string, bool) {
	q := path
	for !strings.has_prefix(q, p.role_prefix) {
		t, has := toks[q]
		if !has {
			return "", false
		}
		a, aliased := t.(json.Object)["alias"]
		if !aliased {
			return "", false
		}
		q = a.(json.String)
	}
	return q, true
}

has_any :: proc(s: string, set: []string) -> bool {
	return slice.contains(set, s)
}

has_any_prefix :: proc(s: string, prefixes: []string) -> bool {
	for p in prefixes {
		if strings.has_prefix(s, p) {
			return true
		}
	}
	return false
}

// const_name is path as an upper snake identifier, its dropped prefix
// gone: comp.button-small.container-height is
// BUTTON_SMALL_CONTAINER_HEIGHT, tokens.fontSizeBase300 is
// FONT_SIZE_BASE300.
const_name :: proc(p: Profile, path: string) -> string {
	q := path
	for d in p.drop {
		q = strings.trim_prefix(q, d)
	}
	return strings.to_upper(strings.join(words(q), "_"))
}

// role_name is a role path as an enum member: sys.color.on-primary is
// On_Primary, tokens.colorNeutralForeground1Hover is
// Neutral_Foreground1_Hover.
role_name :: proc(p: Profile, path: string) -> string {
	ws := words(strings.trim_prefix(path, p.role_prefix))
	for &w in ws {
		w = capitalise(w)
	}
	return strings.join(ws, "_")
}

// words splits a path at its separators (. - _) and at its humps: a
// capital after a lower-case letter or a digit starts a word, so
// level0 stays one word and Foreground1Hover is two.
words :: proc(s: string) -> []string {
	out := make([dynamic]string)
	start := 0
	prev: rune = 0
	for c, i in s {
		switch {
		case c == '.' || c == '-' || c == '_':
			if i > start {
				append(&out, s[start:i])
			}
			start = i + 1
		case is_upper(c) && (is_lower(prev) || is_digit(prev)):
			append(&out, s[start:i])
			start = i
		}
		prev = c
	}
	if start < len(s) {
		append(&out, s[start:])
	}
	return out[:]
}

capitalise :: proc(w: string) -> string {
	if w == "" {
		return w
	}
	return strings.concatenate({strings.to_upper(w[:1]), w[1:]})
}

is_upper :: proc(c: rune) -> bool {
	return c >= 'A' && c <= 'Z'
}

is_lower :: proc(c: rune) -> bool {
	return c >= 'a' && c <= 'z'
}

is_digit :: proc(c: rune) -> bool {
	return c >= '0' && c <= '9'
}
