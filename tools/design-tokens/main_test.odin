package main

import "core:encoding/json"
import "core:strings"
import "core:testing"

@(private = "file")
parse :: proc(s: string) -> json.Object {
	doc, err := json.parse(transmute([]u8)s)
	assert(err == json.Error.None)
	return doc.(json.Object)
}

@(test)
test_material_names_types_and_resolves_colour_roles :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	toks := parse(`{
		"sys.color.on-primary": {"type": "color", "value": "#ffffff", "dark": "#381e72"},
		"sys.color.primary": {"type": "color", "value": "#6750a4", "dark": "#d0bcff"},
		"comp.fab.icon-color": {"type": "color", "value": "#ffffff", "alias": "comp.fab.base-color"},
		"comp.fab.base-color": {"type": "color", "value": "#ffffff", "alias": "sys.color.on-primary"},
		"comp.fab.container-shape": {"type": "shape", "value": [16, 16, 0, 4]},
		"comp.fab.pill": {"type": "shape", "value": "full"},
		"comp.fab.height": {"type": "dimension", "value": 56},
		"sys.elevation.level0": {"type": "dimension", "value": 0},
		"sys.motion.spring.fast.damping": {"type": "number", "value": 0.6, "standard": 0.9},
		"sys.typography.label": {"type": "typography", "value": {"fontFamily": "sans-serif", "fontWeight": 500, "fontSize": 14, "lineHeight": 20, "letterSpacing": 0.1}},
		"ref.palette.primary.40": {"type": "color", "value": "#6750a4"}
	}`)
	out, ok := generate(toks, MATERIAL)
	testing.expect(t, ok)
	for want in ([]string {
			"\tOn_Primary,\n\tPrimary,\n",
			"LIGHT :: [Role]u32 {\n\t.On_Primary = 0xffffff,\n\t.Primary = 0x6750a4,",
			".Primary = 0xd0bcff,",
			"FAB_ICON_COLOR :: Role.On_Primary\n",
			"FAB_CONTAINER_SHAPE :: Shape{radii = {16, 16, 0, 4}}\n",
			"FAB_PILL :: Shape{full = true}\n",
			"FAB_HEIGHT :: f32(56)\n",
			"SYS_ELEVATION_LEVEL0 :: f32(0)\n",
			"SYS_MOTION_SPRING_FAST_DAMPING :: f32(0.6)\nSYS_MOTION_SPRING_FAST_DAMPING_STANDARD :: f32(0.9)\n",
			"SYS_TYPOGRAPHY_LABEL :: Type_Style{weight = 500, size = 14, line_height = 20, tracking = 0.1}\n",
		}) {
		testing.expectf(t, strings.contains(out, want), "missing %q", want)
	}
	testing.expect(t, !strings.contains(out, "PALETTE"))
}

@(test)
test_fluent_splits_humps_keeps_alpha_and_binds_shadows_to_roles :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	toks := parse(`{
		"tokens.colorNeutralForeground1Hover": {"tier": "alias", "type": "color", "value": "#242424", "dark": "#ffffff", "highContrast": "#000000", "teamsDark": "#ffffff"},
		"tokens.colorNeutralShadowAmbient": {"tier": "alias", "type": "color", "value": "#0000001f", "dark": "#0000003d", "highContrast": "#0000003d", "teamsDark": "#0000003d"},
		"tokens.colorNeutralShadowKey": {"tier": "alias", "type": "color", "value": "#00000024", "dark": "#00000047", "highContrast": "#00000047", "teamsDark": "#00000047"},
		"tokens.colorSubtleBackground": {"tier": "alias", "type": "color", "value": "#00000000"},
		"tokens.shadow4": {"tier": "global", "type": "shadow",
			"value": [{"x": 0, "y": 0, "blur": 2, "color": "#0000001f"}, {"x": 0, "y": 2, "blur": 4, "color": "#00000024"}],
			"dark": [{"x": 0, "y": 0, "blur": 2, "color": "#0000003d"}, {"x": 0, "y": 2, "blur": 4, "color": "#00000047"}],
			"highContrast": [{"x": 0, "y": 0, "blur": 2, "color": "#0000003d"}, {"x": 0, "y": 2, "blur": 4, "color": "#00000047"}],
			"teamsDark": [{"x": 0, "y": 0, "blur": 2, "color": "#0000003d"}, {"x": 0, "y": 2, "blur": 4, "color": "#00000047"}]},
		"tokens.borderRadius2XLarge": {"tier": "global", "type": "dimension", "value": 12},
		"tokens.spacingHorizontalXXS": {"tier": "global", "type": "dimension", "value": 2},
		"tokens.fontSizeBase300": {"tier": "global", "type": "dimension", "value": 14},
		"tokens.durationFaster": {"tier": "global", "type": "duration", "value": 100},
		"tokens.curveEasyEase": {"tier": "global", "type": "cubicBezier", "value": [0.33, 0, 0.67, 1]},
		"tokens.fontWeightSemibold": {"tier": "global", "type": "fontWeight", "value": 600},
		"tokens.fontFamilyBase": {"tier": "global", "type": "fontFamily", "value": "'Segoe UI', sans-serif"},
		"typographyStyles.body1Strong": {"type": "typography", "value": {"fontFamily": "fontFamilyBase", "fontSize": 14, "fontWeight": 600, "lineHeight": 20}}
	}`)
	out, ok := generate(toks, FLUENT)
	testing.expect(t, ok)
	for want in ([]string {
			"\tNeutral_Foreground1_Hover,\n\tNeutral_Shadow_Ambient,\n\tNeutral_Shadow_Key,\n\tSubtle_Background,\n",
			"WEB_LIGHT :: [Role]u32 {\n\t.Neutral_Foreground1_Hover = 0x242424ff,\n\t.Neutral_Shadow_Ambient = 0x0000001f,",
			"WEB_DARK :: [Role]u32 {\n\t.Neutral_Foreground1_Hover = 0xffffffff,",
			"HIGH_CONTRAST :: [Role]u32 {\n\t.Neutral_Foreground1_Hover = 0x000000ff,",
			// teamsLight never differs from value here, so it repeats it.
			"TEAMS_LIGHT :: [Role]u32 {\n\t.Neutral_Foreground1_Hover = 0x242424ff,",
			"TEAMS_DARK :: [Role]u32 {\n\t.Neutral_Foreground1_Hover = 0xffffffff,",
			".Subtle_Background = 0x00000000,",
			"SHADOW4 :: Shadow{layers = {{0, 0, 2, .Neutral_Shadow_Ambient}, {0, 2, 4, .Neutral_Shadow_Key}}}\n",
			"BORDER_RADIUS2_XLARGE :: f32(12)\n",
			"SPACING_HORIZONTAL_XXS :: f32(2)\n",
			"FONT_SIZE_BASE300 :: f32(14)\n",
			"DURATION_FASTER :: f32(100)\n",
			"CURVE_EASY_EASE :: Bezier{0.33, 0, 0.67, 1}\n",
			"FONT_WEIGHT_SEMIBOLD :: f32(600)\n",
			"TYPOGRAPHY_STYLES_BODY1_STRONG :: Type_Style{weight = 600, size = 14, line_height = 20, tracking = 0}\n",
		}) {
		testing.expectf(t, strings.contains(out, want), "missing %q", want)
	}
	testing.expect(t, !strings.contains(out, "FONT_FAMILY"))
}

@(test)
test_a_shadow_whose_colour_is_no_role_is_refused :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	toks := parse(`{
		"tokens.colorNeutralShadowAmbient": {"type": "color", "value": "#0000001f", "dark": "#0000003d"},
		"tokens.shadow2": {"type": "shadow",
			"value": [{"x": 0, "y": 0, "blur": 2, "color": "#0000001f"}, {"x": 0, "y": 1, "blur": 2, "color": "#00000024"}],
			"dark": [{"x": 0, "y": 0, "blur": 2, "color": "#0000003d"}, {"x": 0, "y": 1, "blur": 2, "color": "#00000047"}]}
	}`)
	_, ok := generate(toks, FLUENT) // the key layer's colour binds no role
	testing.expect(t, !ok)
}

@(test)
test_generate_refuses_two_paths_with_one_name :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	apart := parse(`{
		"comp.a-b.c": {"type": "dimension", "value": 1},
		"comp.a.b-d": {"type": "dimension", "value": 2}
	}`)
	_, ok := generate(apart, MATERIAL)
	testing.expect(t, ok) // the same shapes of path, two names: fine
	clash := parse(`{
		"comp.a-b.c": {"type": "dimension", "value": 1},
		"comp.a.b-c": {"type": "dimension", "value": 2}
	}`)
	_, ok = generate(clash, MATERIAL)
	testing.expect(t, !ok)
}

@(test)
test_generate_refuses_a_family_the_kit_does_not_name :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	sans := parse(`{
		"sys.typescale.body.font": {"type": "fontFamily", "value": "sans-serif"}
	}`)
	out, ok := generate(sans, MATERIAL)
	testing.expect(t, ok)
	testing.expect(t, !strings.contains(out, "BODY_FONT"))
	serif := parse(`{
		"sys.typescale.body.font": {"type": "fontFamily", "value": "serif"}
	}`)
	_, ok = generate(serif, MATERIAL)
	testing.expect(t, !ok)
}

@(test)
test_the_checked_in_material_tokens_are_current :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	doc, err := json.parse(#load("../material/tokens/m3e.resolved.json"))
	testing.expect(t, err == json.Error.None)
	out, ok := generate(doc.(json.Object)["tokens"].(json.Object), MATERIAL)
	testing.expect(t, ok)
	testing.expect(
		t,
		out == string(#load("../../ui/material/tokens/tokens.odin")),
		"ui/material/tokens/tokens.odin is stale; run just material-tokens",
	)
}

@(test)
test_the_checked_in_fluent_tokens_are_current :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	doc, err := json.parse(#load("../fluent/tokens/fluent.resolved.json"))
	testing.expect(t, err == json.Error.None)
	out, ok := generate(doc.(json.Object)["tokens"].(json.Object), FLUENT)
	testing.expect(t, ok)
	testing.expect(
		t,
		out == string(#load("../../ui/fluent/tokens/tokens.odin")),
		"ui/fluent/tokens/tokens.odin is stale; run just fluent-tokens",
	)
}

@(test)
test_primer_gives_shadow_layers_roles_and_keeps_geometry_per_mode :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	toks := parse(`{
		"--fgColor-default": {"type": "color", "value": "#1f2328", "dark": "#f0f6fc"},
		"--display-blue-fgColor": {"type": "color", "value": "#0969da"},
		"--shadow-floating-small": {"type": "shadow",
			"value": [{"x": 0, "y": 0, "blur": 0, "spread": 1, "color": "#d1d9e040", "inset": false},
				{"x": 0, "y": 6, "blur": 12, "spread": -3, "color": "#25292e0a", "inset": false}],
			"dark": [{"x": 0, "y": 0, "blur": 0, "spread": 1, "color": "#3d444d", "inset": false},
				{"x": 0, "y": 8, "blur": 24, "spread": 0, "color": "#01040966", "inset": false}]},
		"--shadow-inset": {"type": "shadow", "value": [{"x": 0, "y": 1, "blur": 0, "spread": 0, "color": "#1f23280a", "inset": true}]},
		"--control-minTarget-auto": {"type": "dimension", "value": 16, "coarse": 44},
		"--text-codeInline-size": {"type": "dimension", "value": {"value": 0.9285, "unit": "em"}},
		"--motion-transition-hover": {"type": "transition", "value": {"duration": 100, "timingFunction": [0.25, 0.1, 0.25, 1]}},
		"--border-default": {"type": "border", "value": {"width": 1, "style": "solid", "color": "#d1d9e0"}},
		"--breakpoint-medium": {"type": "dimension", "value": 768}
	}`)
	out, ok := generate(toks, PRIMER)
	testing.expect(t, ok)
	for want in ([]string {
			"Role :: enum u8 {\n\tFg_Color_Default,\n\tShadow_Floating_Small_0,\n\tShadow_Floating_Small_1,\n\tShadow_Inset_0,\n}",
			"LIGHT :: [Role]u32 {\n\t.Fg_Color_Default = 0x1f2328ff,\n\t.Shadow_Floating_Small_0 = 0xd1d9e040,\n\t.Shadow_Floating_Small_1 = 0x25292e0a,",
			"DARK :: [Role]u32 {\n\t.Fg_Color_Default = 0xf0f6fcff,\n\t.Shadow_Floating_Small_0 = 0x3d444dff,\n\t.Shadow_Floating_Small_1 = 0x01040966,",
			"Mode :: enum u8 {\n\tLight,\n\tDark,\n\tDark_Dimmed,",
			"\t.Light = {count = 2, layers = {0 = {0, 0, 0, 1, false, .Shadow_Floating_Small_0}, 1 = {0, 6, 12, -3, false, .Shadow_Floating_Small_1}}},\n",
			"\t.Dark = {count = 2, layers = {0 = {0, 0, 0, 1, false, .Shadow_Floating_Small_0}, 1 = {0, 8, 24, 0, false, .Shadow_Floating_Small_1}}},\n",
			"\t.Light = {count = 1, layers = {0 = {0, 1, 0, 0, true, .Shadow_Inset_0}}},\n",
			"CONTROL_MIN_TARGET_AUTO :: f32(16)\nCONTROL_MIN_TARGET_AUTO_COARSE :: f32(44)\n",
			"TEXT_CODE_INLINE_SIZE :: Em(0.9285)\n",
			"MOTION_TRANSITION_HOVER :: Transition{duration = 100, easing = {0.25, 0.1, 0.25, 1}}\n",
			"BREAKPOINT_MEDIUM :: f32(768)\n",
		}) {
		testing.expectf(t, strings.contains(out, want), "missing %q", want)
	}
	testing.expect(t, !strings.contains(out, "Display_Blue"), "a skipped family is no role")
	testing.expect(t, !strings.contains(out, "BORDER_DEFAULT"), "a skipped type is no constant")
}

@(test)
test_primer_refuses_two_colours_with_one_role_name :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	apart := parse(`{
		"--focus-outline-color": {"type": "color", "value": "#0969da"},
		"--focus-outlineColor": {"type": "color", "value": "#0969da"},
		"--overlay-bgColor": {"type": "color", "value": "#ffffff"}
	}`)
	out, ok := generate(apart, PRIMER) // the focus pair is one role, its fallback skipped
	testing.expect(t, ok)
	testing.expect(t, strings.count(out, "\tFocus_Outline_Color,\n") == 1)
	clash := parse(`{
		"--overlay-bgColor": {"type": "color", "value": "#ffffff"},
		"--overlay-bg-color": {"type": "color", "value": "#ffffff"}
	}`)
	_, ok = generate(clash, PRIMER)
	testing.expect(t, !ok)
}

@(test)
test_primer_refuses_a_shadow_whose_layer_count_changes :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	same := parse(`{
		"--shadow-resting-small": {"type": "shadow",
			"value": [{"x": 0, "y": 1, "blur": 1, "spread": 0, "color": "#1f23280a", "inset": false}],
			"dark": [{"x": 0, "y": 1, "blur": 3, "spread": 0, "color": "#01040999", "inset": false}]}
	}`)
	_, ok := generate(same, PRIMER) // geometry may change per mode
	testing.expect(t, ok)
	more := parse(`{
		"--shadow-resting-small": {"type": "shadow",
			"value": [{"x": 0, "y": 1, "blur": 1, "spread": 0, "color": "#1f23280a", "inset": false}],
			"dark": [{"x": 0, "y": 1, "blur": 1, "spread": 0, "color": "#01040999", "inset": false},
				{"x": 0, "y": 1, "blur": 3, "spread": 0, "color": "#01040999", "inset": false}]}
	}`)
	_, ok = generate(more, PRIMER) // the layer count may not
	testing.expect(t, !ok)
}

@(test)
test_primer_refuses_a_type_style_sized_in_em :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	px := parse(`{
		"--text-code-shorthand": {"type": "typography", "value": {"fontWeight": 400, "fontSize": 13, "fontFamily": "ui-monospace"}}
	}`)
	out, ok := generate(px, PRIMER)
	testing.expect(t, ok)
	testing.expect(t, strings.contains(out, "TEXT_CODE_SHORTHAND :: Type_Style{weight = 400, size = 13,"))
	em := parse(`{
		"--text-code-shorthand": {"type": "typography", "value": {"fontWeight": 400, "fontSize": {"value": 0.9, "unit": "em"}, "fontFamily": "ui-monospace"}}
	}`)
	_, ok = generate(em, PRIMER)
	testing.expect(t, !ok)
}

@(test)
test_the_checked_in_primer_tokens_are_current :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	doc, err := json.parse(#load("../primer/tokens/primer.resolved.json"))
	testing.expect(t, err == json.Error.None)
	out, ok := generate(doc.(json.Object)["tokens"].(json.Object), PRIMER)
	testing.expect(t, ok)
	testing.expect(
		t,
		out == string(#load("../../ui/primer/tokens/tokens.odin")),
		"ui/primer/tokens/tokens.odin is stale; run just primer-tokens",
	)
}
