#+build !windows
package sh

import "core:testing"
import "core:time"

@(test)
quote_posix :: proc(t: ^testing.T) {
	testing.expect_value(t, quote("plain", context.temp_allocator), "plain")
	testing.expect_value(t, quote("has space", context.temp_allocator), "'has space'")
	testing.expect_value(t, quote("it's", context.temp_allocator), `'it'\''s'`)
	testing.expect_value(t, quote("", context.temp_allocator), "''")
}

@(test)
stdin_reaches_child :: proc(t: ^testing.T) {
	s, ok := out("cat", {stdin = "from stdin"}, context.temp_allocator)
	testing.expect(t, ok)
	testing.expect_value(t, s, "from stdin")
}

@(test)
dir_and_env :: proc(t: ^testing.T) {
	s, ok := out("pwd", {dir = "/"}, context.temp_allocator)
	testing.expect(t, ok)
	testing.expect_value(t, s, "/")
	s, ok = out(
		"echo $JM_TEST",
		{env = {"JM_TEST=set", "PATH=/usr/bin:/bin"}},
		context.temp_allocator,
	)
	testing.expect(t, ok)
	testing.expect_value(t, s, "set")
}

@(test)
timeout_kills_a_slow_child :: proc(t: ^testing.T) {
	r := exec({"sleep", "5"}, {timeout = 200 * time.Millisecond}, context.temp_allocator)
	testing.expect(t, r.timed_out, "the child was not timed out")
	testing.expect(t, !r.ok)
	quick := exec({"echo", "fast"}, {timeout = 5 * time.Second}, context.temp_allocator)
	testing.expect(t, quick.ok)
	testing.expect(t, !quick.timed_out)
	testing.expect_value(t, quick.stdout, "fast\n")
}
