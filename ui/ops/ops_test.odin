package ops

import "core:testing"

@(test)
add_image_keeps_its_own_copy_of_the_path :: proc(t: ^testing.T) {
	o: Scene
	init(&o)
	defer destroy(&o)
	buf := []byte{'a', '.', 'b', 'm', 'p'}
	first := add_image(&o, string(buf))
	buf[0] = 'z' // the caller's memory moves on
	testing.expect_value(t, add_image(&o, "a.bmp"), first)
	testing.expect(t, add_image(&o, "z.bmp") != first)
	testing.expect_value(t, o.images[0].path, "a.bmp")
}
