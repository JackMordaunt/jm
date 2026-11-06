package timefmt

import "core:testing"
import "core:time"
import "core:time/datetime"
import "core:time/timezone"

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

// Values are Python zoneinfo's UTC-to-local answers at the 2026 transitions.
// Named zones are loaded independently; no process-wide TZ mutation is needed.
@(test)
local_transition_boundaries :: proc(t: ^testing.T) {
	when ODIN_OS == .Windows {
		// Windows uses recurrence rules instead of the TZif transition table.
		return
	}
	cases := [?]struct {
		zone:                    string,
		at:                      i64,
		before, boundary, after: string,
	} {
		{
			"Europe/London",
			1774746000,
			"2026-03-29 00:59:59 +0000 GMT",
			"2026-03-29 02:00:00 +0100 BST",
			"2026-03-29 02:00:01 +0100 BST",
		},
		{
			"Europe/London",
			1792890000,
			"2026-10-25 01:59:59 +0100 BST",
			"2026-10-25 01:00:00 +0000 GMT",
			"2026-10-25 01:00:01 +0000 GMT",
		},
		{
			"America/New_York",
			1772953200,
			"2026-03-08 01:59:59 -0500 EST",
			"2026-03-08 03:00:00 -0400 EDT",
			"2026-03-08 03:00:01 -0400 EDT",
		},
		{
			"America/New_York",
			1793512800,
			"2026-11-01 01:59:59 -0400 EDT",
			"2026-11-01 01:00:00 -0500 EST",
			"2026-11-01 01:00:01 -0500 EST",
		},
		{
			"Australia/Lord_Howe",
			1775314800,
			"2026-04-05 01:59:59 +1100 +11",
			"2026-04-05 01:30:00 +1030 +1030",
			"2026-04-05 01:30:01 +1030 +1030",
		},
		{
			"Australia/Lord_Howe",
			1791041400,
			"2026-10-04 01:59:59 +1030 +1030",
			"2026-10-04 02:30:00 +1100 +11",
			"2026-10-04 02:30:01 +1100 +11",
		},
	}
	for c in cases {
		region, ok := timezone.region_load(c.zone, context.temp_allocator)
		testing.expectf(t, ok && region != nil, "cannot load %s", c.zone)
		if !ok || region == nil {
			continue
		}
		wants := [3]string{c.before, c.boundary, c.after}
		for want, i in wants {
			at := c.at + i64(i) - 1
			p := region_parts(time.unix(at, 0), region)
			said := format_parts(p, "%Y-%m-%d %H:%M:%S %z %Z", context.temp_allocator)
			testing.expectf(t, said == want, "%s at %d: %q, want %q", c.zone, at, said, want)
		}
	}
}

// This table does not depend on a system zone database, so Windows exercises
// the transition search too. A repeated hour must keep its distinct instant.
@(test)
local_transition_preserves_the_instant_and_fraction :: proc(t: ^testing.T) {
	records := []datetime.TZ_Record {
		{time = 0, utc_offset = 3600, shortname = "DST", dst = true},
		{time = 7200, utc_offset = 0, shortname = "STD"},
	}
	region := datetime.TZ_Region {
		records = records,
	}
	cases := [?]struct {
		seconds: i64,
		nanos:   i64,
		want:    string,
	} {
		{7199, 999_000_000, "02:59:59.999 +0100 DST 7199"},
		{7200, 0, "02:00:00.000 +0000 STD 7200"},
		{7200, 123_000_000, "02:00:00.123 +0000 STD 7200"},
	}
	for c in cases {
		p := region_parts(time.unix(c.seconds, c.nanos), &region)
		testing.expect_value(
			t,
			format_parts(p, "%H:%M:%S.%f %z %Z %s", context.temp_allocator),
			c.want,
		)
	}
	fixed := datetime.TZ_Region {
		rrule = {std_name = "NPT", std_offset = 5 * 3600 + 45 * 60},
	}
	p := region_parts(time.unix(1800014400, 123_000_000), &fixed)
	testing.expect_value(
		t,
		format_parts(p, "%H:%M:%S.%f %z %Z %s", context.temp_allocator),
		"17:45:00.123 +0545 NPT 1800014400",
	)
}
