package fluent

import "core:testing"
import "jm:ui/design"

@(test)
test_every_icon_parses_and_has_its_filled_twin :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	for i in Icon {
		if i == .None {
			continue
		}
		data, _ := icon_svg(i)
		_, ok := design.parse_svg_path(data, context.temp_allocator)
		testing.expectf(t, ok, "%v has a command parse_svg_path does not handle", i)
		p, box := icon_path(i)
		testing.expectf(t, len(p.points) > 0, "%v parsed to nothing", i)
		for q in p.points {
			if q.x < -1 || q.y < -1 || q.x > box + 1 || q.y > box + 1 {
				testing.expectf(t, false, "%v has a point %v outside its %v box", i, q, box)
				break
			}
		}
	}
	testing.expect_value(t, filled(.Add), Icon.Add_Filled)
	testing.expect_value(t, filled(.Add_Filled), Icon.Add_Filled)
	testing.expect_value(t, filled(.None), Icon.None)
	testing.expect(t, !is_filled(.Chevron_Down))
	testing.expect(t, is_filled(.Chevron_Down_Filled))
	// The generated order the twin rule relies on: regular, then filled.
	for i in Icon {
		if i == .None {
			continue
		}
		testing.expectf(t, is_filled(i) == (int(i) % 2 == 0), "%v breaks the regular/filled alternation", i)
	}
}
