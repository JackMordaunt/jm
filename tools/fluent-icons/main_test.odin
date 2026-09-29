package main

import "core:strings"
import "core:testing"

@(test)
test_icon_file_names_and_members :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	name, variant, ok := split_icon_file("ic_fluent_chevron_down_20_filled.svg")
	testing.expect(t, ok)
	testing.expect_value(t, name, "chevron_down")
	testing.expect_value(t, variant, "filled")
	testing.expect_value(t, member_name(name, variant), "Chevron_Down_Filled")
	testing.expect_value(t, member_name("add", "regular"), "Add")
	_, _, ok = split_icon_file("ic_fluent_add_24_regular.svg")
	testing.expect(t, !ok)
	_, _, ok = split_icon_file("LICENSE")
	testing.expect(t, !ok)
}

@(test)
test_path_data_takes_one_plain_path :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	d, box, ok := path_data(`<svg width="20" height="20" viewBox="0 0 20 20" fill="none"><path d="M10 2.5V17.5Z" fill="#212121"/></svg>`)
	testing.expect(t, ok)
	testing.expect_value(t, d, "M10 2.5V17.5Z")
	testing.expect_value(t, box, 20)
	_, _, ok = path_data(`<svg viewBox="0 0 20 20"><path d="M0 0"/><path d="M1 1"/></svg>`)
	testing.expect(t, !ok)
	_, _, ok = path_data(`<svg viewBox="0 0 20 20"><path fill-rule="evenodd" d="M0 0"/></svg>`)
	testing.expect(t, !ok)
	_, _, ok = path_data(`<svg viewBox="0 0 24 20"><path d="M0 0"/></svg>`)
	testing.expect(t, !ok)
}

@(test)
test_generate_writes_the_enum_and_tables :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	out := generate([]Svg{{"Add", "M1 1", 20}, {"Add_Filled", "M2 2", 20}})
	for want in ([]string{"\tNone,\n\tAdd,\n\tAdd_Filled,\n", ".Add = \"M1 1\",", ".Add_Filled = 20,", "icon_svg :: proc"}) {
		testing.expectf(t, strings.contains(out, want), "missing %q", want)
	}
}
