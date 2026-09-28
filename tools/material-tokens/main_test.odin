package main

import "core:encoding/json"
import "core:strings"
import "core:testing"

@(test)
test_generate_names_types_and_resolves_colour_roles :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	doc, err := json.parse(transmute([]u8)string(`{
		"sys.color.on-primary": {"type": "color", "value": "#ffffff", "dark": "#381e72"},
		"sys.color.primary": {"type": "color", "value": "#6750a4", "dark": "#d0bcff"},
		"comp.fab.icon-color": {"type": "color", "value": "#ffffff", "alias": "comp.fab.base-color"},
		"comp.fab.base-color": {"type": "color", "value": "#ffffff", "alias": "sys.color.on-primary"},
		"comp.fab.container-shape": {"type": "shape", "value": [16, 16, 0, 4]},
		"comp.fab.pill": {"type": "shape", "value": "full"},
		"comp.fab.height": {"type": "dimension", "value": 56},
		"sys.motion.spring.fast.damping": {"type": "number", "value": 0.6, "standard": 0.9},
		"sys.typography.label": {"type": "typography", "value": {"fontFamily": "sans-serif", "fontWeight": 500, "fontSize": 14, "lineHeight": 20, "letterSpacing": 0.1}},
		"ref.palette.primary.40": {"type": "color", "value": "#6750a4"}
	}`))
	testing.expect_value(t, err, json.Error.None)
	out, ok := generate(doc.(json.Object))
	testing.expect(t, ok)
	for want in ([]string {
			"\tOn_Primary,\n\tPrimary,\n",
			".Primary = 0x6750a4,",
			".Primary = 0xd0bcff,",
			"FAB_ICON_COLOR :: Role.On_Primary\n",
			"FAB_CONTAINER_SHAPE :: Shape{radii = {16, 16, 0, 4}}\n",
			"FAB_PILL :: Shape{full = true}\n",
			"FAB_HEIGHT :: f32(56)\n",
			"SYS_MOTION_SPRING_FAST_DAMPING :: f32(0.6)\nSYS_MOTION_SPRING_FAST_DAMPING_STANDARD :: f32(0.9)\n",
			"SYS_TYPOGRAPHY_LABEL :: Type_Style{weight = 500, size = 14, line_height = 20, tracking = 0.1}\n",
		}) {
		testing.expectf(t, strings.contains(out, want), "missing %q", want)
	}
	testing.expect(t, !strings.contains(out, "PALETTE"))
}

@(test)
test_generate_refuses_two_paths_with_one_name :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	apart, _ := json.parse(transmute([]u8)string(`{
		"comp.a-b.c": {"type": "dimension", "value": 1},
		"comp.a.b-d": {"type": "dimension", "value": 2}
	}`))
	_, ok := generate(apart.(json.Object))
	testing.expect(t, ok) // the same shapes of path, two names: fine
	clash, _ := json.parse(transmute([]u8)string(`{
		"comp.a-b.c": {"type": "dimension", "value": 1},
		"comp.a.b-c": {"type": "dimension", "value": 2}
	}`))
	_, ok = generate(clash.(json.Object))
	testing.expect(t, !ok)
}

@(test)
test_generate_refuses_a_family_other_than_sans_serif :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	sans, _ := json.parse(transmute([]u8)string(`{
		"sys.typescale.body.font": {"type": "fontFamily", "value": "sans-serif"}
	}`))
	out, ok := generate(sans.(json.Object))
	testing.expect(t, ok)
	testing.expect(t, !strings.contains(out, "BODY_FONT"))
	serif, _ := json.parse(transmute([]u8)string(`{
		"sys.typescale.body.font": {"type": "fontFamily", "value": "serif"}
	}`))
	_, ok = generate(serif.(json.Object))
	testing.expect(t, !ok)
}
