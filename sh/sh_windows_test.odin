#+build windows
package sh

import "core:testing"

@(test)
quote_cmd :: proc(t: ^testing.T) {
	testing.expect_value(t, quote("plain", context.temp_allocator), "plain")
	testing.expect_value(t, quote("has space", context.temp_allocator), `"has space"`)
	testing.expect_value(t, quote(`say "hi"`, context.temp_allocator), `"say \"hi\""`)
	testing.expect_value(t, quote(`C:\dir\`, context.temp_allocator), `C:\dir\`)
	testing.expect_value(t, quote(`C:\my dir\`, context.temp_allocator), `"C:\my dir\\"`)
}
