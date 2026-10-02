package ops

import "core:testing"

@(test)
test_add_font_after_add_fonts_takes_an_unused_id :: proc(t: ^testing.T) {
	sc: Scene
	init(&sc)
	defer destroy(&sc)
	add_fonts(&sc, {{id = 0, path = "a.ttf"}, {id = 5, path = "a.ttf"}})
	testing.expect_value(t, add_font(&sc, "b.ttf"), Font_Id(6))
	testing.expect_value(t, add_font(&sc, "a.ttf"), Font_Id(0))
	testing.expect_value(t, len(sc.fonts), 3)
}

@(test)
test_add_font_keeps_one_id_per_path_and_weight :: proc(t: ^testing.T) {
	sc: Scene
	init(&sc)
	defer destroy(&sc)
	regular := add_font(&sc, "sans.ttf", 400)
	semibold := add_font(&sc, "sans.ttf", 600)
	testing.expect(t, regular != semibold, "two weights of one file share an id")
	testing.expect_value(t, add_font(&sc, "sans.ttf", 600), semibold)
	testing.expect_value(t, add_font(&sc, "sans.ttf", 400), regular)
	testing.expect_value(t, len(sc.fonts), 2)
	testing.expect_value(t, sc.fonts[1].weight, 600)
}
