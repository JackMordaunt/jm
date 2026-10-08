package ops

import "core:strings"
import "core:testing"

@(test)
test_a_path_by_content_keeps_its_name_when_its_index_moves :: proc(t: ^testing.T) {
	scene: Scene
	init(&scene)
	defer destroy(&scene)
	verbs := []Path_Verb{.Move, .Line, .Line, .Close}
	points := []Point{{2, 4}, {12, 4}, {2, 9}}
	first := add_path(&scene, {verbs = verbs, points = points})
	sb := strings.builder_make()
	defer strings.builder_destroy(&sb)
	write_shape(&sb, Path_Ref{first}, &scene, by_content = true)
	alone := strings.clone(strings.to_string(sb), context.temp_allocator)
	defer free_all(context.temp_allocator)
	testing.expect(t, strings.has_prefix(alone, "path "))
	testing.expect(t, strings.has_suffix(alone, " bounds 2 4 10 5"))

	// The same path added after another: a new index, the same name.
	reset(&scene)
	add_path(&scene, {verbs = verbs[:2], points = points[:2]})
	second := add_path(&scene, {verbs = verbs, points = points})
	testing.expect_value(t, second, Path_Id(1))
	strings.builder_reset(&sb)
	write_shape(&sb, Path_Ref{second}, &scene, by_content = true)
	testing.expect_value(t, strings.to_string(sb), alone)

	// By index, as dump has always written it.
	strings.builder_reset(&sb)
	write_shape(&sb, Path_Ref{second})
	testing.expect_value(t, strings.to_string(sb), "path#1")
}
