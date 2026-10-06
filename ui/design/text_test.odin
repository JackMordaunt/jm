package design

import "core:testing"
import "jm:ui"

@(test)
test_layout_style_balances_when_asked :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	gtx := ui.Ctx{shaper = ui.stub_shaper(), allocator = context.temp_allocator}
	st := Type_Style{weight = 400, size = 10, line_height = 15}
	// Through the stub each rune is 6px: greedy at 120px is four words
	// then two, balanced three and three, each line 15px tall.
	six := "aaaa bbbb cccc dddd eeee ffff"
	greedy := layout_style(&gtx, six, st, 0, 120)
	testing.expect_value(t, greedy.lines[0].end, 20)
	even := layout_style(&gtx, six, st, 0, 120, balance = true)
	testing.expect_value(t, len(even.lines), 2)
	testing.expect_value(t, even.lines[0].end, 15)
	testing.expect_value(t, even.width, 84)
	testing.expect_value(t, even.height, 30)
}

@(test)
test_thousands_groups_digits_by_three :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	testing.expect_value(t, thousands(1234567), "1,234,567")
	testing.expect_value(t, thousands(999), "999")
	testing.expect_value(t, thousands(-1000), "-1,000")
	testing.expect_value(t, thousands(0), "0")
}
