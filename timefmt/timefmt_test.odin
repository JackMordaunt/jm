package timefmt

import "core:testing"
import "core:time"

@(test)
format_directives :: proc(t: ^testing.T) {
	// 2026-09-23T10:41:02.250Z is a Wednesday, day 266 of the year.
	tm := time.unix(1790160062, 250_000_000)
	testing.expect_value(t, iso(tm, context.temp_allocator), "2026-09-23T10:41:02Z")
	testing.expect_value(t, stamp(tm, context.temp_allocator), "20260923-104102")
	testing.expect_value(t, date(tm, context.temp_allocator), "2026-09-23")
	testing.expect_value(t, format(tm, "%a %A %b %B %e %j %y %f %I%p %u %w %s %z %Z %%", context.temp_allocator),
		"Wed Wednesday Sep September 23 266 26 250 10AM 3 3 1790160062 +0000 UTC %")
}

@(test)
parse_roundtrip :: proc(t: ^testing.T) {
	tm, ok := parse("2026-09-23 10:41:02", "%Y-%m-%d %H:%M:%S")
	testing.expect(t, ok)
	testing.expect_value(t, time.time_to_unix(tm), i64(1790160062))

	tm, ok = parse("23 Sep 2026 3:05 pm", "%d %b %Y %I:%M %p")
	testing.expect(t, ok)
	testing.expect_value(t, format(tm, "%H:%M", context.temp_allocator), "15:05")

	tm, ok = parse("1790160062", "%s")
	testing.expect(t, ok)
	testing.expect_value(t, time.time_to_unix(tm), i64(1790160062))

	_, ok = parse("2026-13-01", "%Y-%m-%d")
	testing.expect(t, !ok, "month 13 must fail")
	_, ok = parse("2026-09-23 extra", "%Y-%m-%d")
	testing.expect(t, !ok, "trailing text must fail")
}

@(test)
durations :: proc(t: ^testing.T) {
	testing.expect_value(t, duration(250 * time.Millisecond, context.temp_allocator), "250ms")
	testing.expect_value(t, duration(4200 * time.Millisecond, context.temp_allocator), "4.2s")
	testing.expect_value(t, duration(3 * time.Minute + 12 * time.Second, context.temp_allocator), "3m12s")
	testing.expect_value(t, duration(time.Hour + 2 * time.Second, context.temp_allocator), "1h0m2s")
	testing.expect_value(t, duration(51 * time.Hour, context.temp_allocator), "2d3h")
	testing.expect_value(t, duration(-500 * time.Microsecond, context.temp_allocator), "-500µs")
}

@(test)
local_has_zone :: proc(t: ^testing.T) {
	s := local(time.now(), "%Z", context.temp_allocator)
	testing.expect(t, len(s) > 0, "zone name must not be empty")
}
