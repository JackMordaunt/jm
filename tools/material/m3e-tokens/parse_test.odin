package main

import "core:testing"

SOURCE_DIR :: #directory + "/../source/tokens"

@(test)
test_kebab :: proc(t: ^testing.T) {
	cases := [][2]string {
		{"XLargeIconButton", "x-large-icon-button"},
		{"ContainerHeight", "container-height"},
		{"Level3", "level3"},
		{"FabPrimaryContainer", "fab-primary-container"},
		{"OnSurface", "on-surface"},
	}
	for c in cases {
		testing.expect_value(t, kebab(c[0], context.temp_allocator), c[1])
	}
}

@(test)
test_path_of :: proc(t: ^testing.T) {
	// The parser allocates freely, as a one-shot CLI may; the runner frees temp.
	context.allocator = context.temp_allocator
	cases := [][3]string {
		{"PaletteTokens", "NeutralVariant40", "ref.palette.neutral-variant.40"},
		{"ColorSchemeKeyTokens", "PrimaryContainer", "sys.color.primary-container"},
		{"ColorDarkTokens", "PrimaryContainer", "sys.color.primary-container"},
		{"ShapeKeyTokens", "CornerExtraLargeTop", "sys.shape.corner.extra-large-top"},
		{"ShapeTokens", "CornerValueLarge", "sys.shape.corner-value.large"},
		{"TypeScaleTokens", "BodyLargeLineHeight", "sys.typescale.body-large.line-height"},
		{"TypographyKeyTokens", "LabelLargeEmphasized", "sys.typography.label-large-emphasized"},
		{"MotionTokens", "EasingEmphasizedAccelerateCubicBezier", "sys.motion.easing.emphasized-accelerate"},
		{"MotionTokens", "DurationShort1", "sys.motion.duration.short1"},
		{"ExpressiveMotionTokens", "SpringFastSpatialDamping", "sys.motion.spring.fast-spatial.damping"},
		{"SplitButtonXSmallTokens", "InnerCornerSize", "comp.split-button-x-small.inner-corner-size"},
	}
	for c in cases {
		testing.expect_value(t, path_of(c[0], c[1]), c[2])
	}
}

@(test)
test_parse_file :: proc(t: ^testing.T) {
	// The parser allocates freely, as a one-shot CLI may; the runner frees temp.
	context.allocator = context.temp_allocator
	src := `// GENERATED CODE - DO NOT MODIFY BY HAND
package androidx.compose.material3.tokens

internal object DemoTokens {
    const val Opacity = 0.38f
    inline val Height: androidx.compose.ui.unit.Dp
        get() = 56.0.dp // TODO: a trailing note
    inline val Color: ColorToken
        get() = ColorSchemeKeyTokens.Primary
    val Shape =
        RoundedCornerShape(
            topStart = 28.0.dp,
            topEnd = 28.0.dp,
            bottomEnd = 0.0.dp,
            bottomStart = 0.0.dp,
        )
    val Pill = CircleShape
    inline val Ease: CubicBezierEasing
        get() = CubicBezierEasing(0.2f, 0.0f, 0.0f, 1.0f)
}

internal val NotAToken = 1
`
	toks: Tokens
	add_file(&toks, src, "DemoTokens.kt")
	testing.expect_value(t, len(toks.errors), 0)
	testing.expect_value(t, len(toks.order), 6)

	op := toks.byPath["comp.demo.opacity"].modes[0].value
	testing.expect_value(t, op.kind, Kind.Number)
	testing.expect_value(t, op.num, 0.38)
	h := toks.byPath["comp.demo.height"].modes[0].value
	testing.expect_value(t, h.num, 56)
	testing.expect_value(t, toks.byPath["comp.demo.color"].modes[0].value.text, "sys.color.primary")
	s := toks.byPath["comp.demo.shape"].modes[0].value
	testing.expect_value(t, s.corner.radii, [4]f64{28, 28, 0, 0})
	testing.expect(t, toks.byPath["comp.demo.pill"].modes[0].value.corner.full)
	testing.expect_value(t, toks.byPath["comp.demo.ease"].modes[0].value.bezier, [4]f64{0.2, 0, 0, 1})
}

@(test)
test_unknown_expression_is_an_error :: proc(t: ^testing.T) {
	// The parser allocates freely, as a one-shot CLI may; the runner frees temp.
	context.allocator = context.temp_allocator
	src := "internal object DemoTokens {\n    val Weird = SomethingNew(3)\n}\n"
	toks: Tokens
	add_file(&toks, src, "DemoTokens.kt")
	testing.expect_value(t, len(toks.errors), 1)
}

// The real sources: whole, and the values the M3 baseline is known for.
@(test)
test_source :: proc(t: ^testing.T) {
	// The parser allocates freely, as a one-shot CLI may; the runner frees temp.
	context.allocator = context.temp_allocator
	toks := load(SOURCE_DIR)
	for e in toks.errors {
		testing.expectf(t, false, "%s", e)
	}
	color :: proc(t: ^testing.T, toks: ^Tokens, path, mode: string, want: [3]u8) {
		v, ok := resolve(toks, path, mode)
		testing.expect(t, ok, path)
		testing.expect_value(t, v.color, want)
	}
	color(t, toks, "sys.color.primary", "", {0x67, 0x50, 0xa4})
	color(t, toks, "sys.color.primary", "dark", {0xd0, 0xbc, 0xff})
	color(t, toks, "comp.fab-primary-container.container-color", "dark", {0x4f, 0x37, 0x8b})
	color(t, toks, "sys.color.surface-tint", "dark", {0xd0, 0xbc, 0xff})

	d, _ := resolve(toks, "sys.motion.spring.default-spatial.damping", "")
	testing.expect_value(t, d.num, 0.8)
	d, _ = resolve(toks, "sys.motion.spring.default-spatial.damping", "standard")
	testing.expect_value(t, d.num, 0.9)

	e, _ := resolve(toks, "comp.fab-primary-container.hovered-container-elevation", "")
	testing.expect_value(t, e.num, 8)
}
