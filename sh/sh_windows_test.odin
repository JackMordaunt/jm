#+build windows
package sh

import "core:strings"
import "core:testing"

// findstr ships in System32 and echoes every line matching "^".
@(test)
stdin_reaches_child :: proc(t: ^testing.T) {
	r := exec({"findstr", "^"}, {stdin = "from stdin\n"}, context.temp_allocator)
	testing.expectf(t, r.ok, "exit %d: %s", r.code, r.stderr)
	testing.expect_value(t, strings.trim_space(r.stdout), "from stdin")
}

@(test)
quote_cmd :: proc(t: ^testing.T) {
	testing.expect_value(t, quote("plain", context.temp_allocator), "plain")
	testing.expect_value(t, quote("has space", context.temp_allocator), `"has space"`)
	testing.expect_value(t, quote(`say "hi"`, context.temp_allocator), `"say \"hi\""`)
	testing.expect_value(t, quote(`C:\dir\`, context.temp_allocator), `C:\dir\`)
	testing.expect_value(t, quote(`C:\my dir\`, context.temp_allocator), `"C:\my dir\\"`)
}
