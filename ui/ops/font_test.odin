package ops

import "core:testing"

@(test)
test_add_font_after_add_fonts_takes_an_unused_id :: proc(t: ^testing.T) {
	sc: Scene
	init(&sc)
	defer destroy(&sc)
	add_fonts(&sc, {{0, "a.ttf"}, {5, "a.ttf"}})
	testing.expect_value(t, add_font(&sc, "b.ttf"), Font_Id(6))
	testing.expect_value(t, add_font(&sc, "a.ttf"), Font_Id(0))
	testing.expect_value(t, len(sc.fonts), 3)
}
