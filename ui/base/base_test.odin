package base

import "core:testing"
import "jm:ui"
import "jm:ui/design"
import "jm:ui/ops"

@(test)
test_palette_satisfies_the_axioms_in_both_modes :: proc(t: ^testing.T) {
	v := design.check(palette(), AXIOMS, context.temp_allocator)
	testing.expect_value(t, len(v), 0)
	for x in v {
		testing.expectf(t, false, "%v: %v %v vs %v: got %.2f, want %v", x.ctx, x.axiom.rel, x.axiom.a, x.axiom.b, x.got, x.axiom.k)
	}
}

@(test)
test_check_catches_a_palette_that_loses_its_text :: proc(t: ^testing.T) {
	p := palette()
	p.bind[.Dark][.Fg] = p.bind[.Dark][.Bg]
	v := design.check(p, AXIOMS, context.temp_allocator)
	if testing.expect_value(t, len(v), 2) { // Fg on Bg and Fg on Surface, in the dark mode only
		for x in v {
			testing.expect_value(t, x.ctx, Mode.Dark)
			testing.expect_value(t, x.axiom.a, Role.Fg)
			testing.expect(t, x.axiom.b == .Bg || x.axiom.b == .Surface)
			testing.expect(t, x.got < 4.5)
		}
	}
}

@(private = "file")
view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	if ui.column(gtx, gap = 4) {
		label(gtx, "plain")
		label(gtx, "styled", {color = {9, 8, 7, 255}, size = 20})
		if panel(gtx) {
			label(gtx, "in a panel")
		}
		divider(gtx)
	}
}

@(test)
test_widgets_take_the_active_theme_and_keep_overrides :: proc(t: ^testing.T) {
	th := light()
	th.colors.bind[.Light][.Fg] = {1, 2, 3, 255}
	th.colors.bind[.Light][.Surface] = {4, 5, 6, 255}
	th.colors.bind[.Light][.Outline] = {7, 8, 9, 255}
	use(&th)
	defer use(nil)
	p: ui.Probe
	ui.probe_init(&p, view, nil, {200, 200}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	glyphs := make([dynamic]ops.Glyphs, context.temp_allocator)
	fills := make([dynamic]ops.Fill, context.temp_allocator)
	for op in p.scene.ops {
		#partial switch v in op {
		case ops.Glyphs:
			append(&glyphs, v)
		case ops.Fill:
			append(&fills, v)
		}
	}
	if testing.expect_value(t, len(glyphs), 3) {
		testing.expect_value(t, glyphs[0].color, ops.Color{1, 2, 3, 255}) // the theme's Fg
		testing.expect_value(t, glyphs[1].color, ops.Color{9, 8, 7, 255}) // the override
		testing.expect_value(t, p.scene.runs[glyphs[1].run].size, 20)
	}
	surface, outline := false, false
	for f in fills {
		if c, ok := f.paint.(ops.Color); ok {
			surface |= c == {4, 5, 6, 255}
			outline |= c == {7, 8, 9, 255} // the divider
		}
	}
	testing.expect(t, surface) // the panel's fill
	testing.expect(t, outline)
	found := false
	for op in p.scene.ops {
		if tag, ok := op.(ops.Tag); ok && tag.name == "in a panel" {
			found = true // the label inside the panel guard was laid out and tagged
		}
	}
	testing.expect(t, found)
}
