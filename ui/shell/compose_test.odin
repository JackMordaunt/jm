package shell

import "core:testing"

@(test)
test_compose_span_counts_characters_as_bytes :: proc(t: ^testing.T) {
	// か and な are three bytes each; 🙂 is four.
	testing.expect_value(t, compose_span("かな", 1, 0), [2]int{3, 3})
	testing.expect_value(t, compose_span("かな", 0, 2), [2]int{0, 6})
	testing.expect_value(t, compose_span("a🙂b", 1, 1), [2]int{1, 5})
	testing.expect_value(t, compose_span("a🙂b", 2, 0), [2]int{5, 5})
	// Unset is the end of the text; past the end clamps to it.
	testing.expect_value(t, compose_span("かな", -1, -1), [2]int{6, 6})
	testing.expect_value(t, compose_span("かな", 5, 3), [2]int{6, 6})
	testing.expect_value(t, compose_span("", 0, 0), [2]int{0, 0})
}
