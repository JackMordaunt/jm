package plot

import "core:fmt"
import "core:testing"
import "core:time/datetime"

// new_york is America/New_York's offsets around 2026, written out so the
// tests need no tz database: EST, EDT from 2026-03-08 07:00 UTC, EST from
// 2026-11-01 06:00 UTC, EDT from 2027-03-14 07:00 UTC.
@(private = "file")
new_york :: proc() -> Zone {
	@(static) records := [?]datetime.TZ_Record {
		{time = -2717650800, utc_offset = -18000, shortname = "EST"},
		{time = 1772953200, utc_offset = -14400, shortname = "EDT", dst = true},
		{time = 1793512800, utc_offset = -18000, shortname = "EST"},
		{time = 1805007600, utc_offset = -14400, shortname = "EDT", dst = true},
		{time = 4102444800, utc_offset = -18000, shortname = "EST"},
	}
	@(static) region: datetime.TZ_Region
	region = {name = "America/New_York", records = records[:]}
	return {region = &region}
}

@(private = "file")
HOUR :: 3600

@(private = "file")
DAY :: 86400

@(test)
test_civil_dates_round_trip :: proc(t: ^testing.T) {
	testing.expect_value(t, days_from_civil(1970, 1, 1), 0)
	testing.expect_value(t, days_from_civil(2026, 1, 1) * DAY, 1767225600)
	testing.expect_value(t, days_from_civil(1969, 12, 31), -1)
	for d := i64(-800_000); d <= 800_000; d += 997 {
		c := civil_from_wall(d * DAY + 3723)
		testing.expect_value(t, days_from_civil(c.year, c.month, c.day), d)
		testing.expect_value(t, [3]int{c.hour, c.minute, c.second}, [3]int{1, 2, 3})
	}
	testing.expect_value(t, civil_from_wall(0).wday, 4) // a Thursday
	testing.expect_value(t, civil_from_wall(-DAY).wday, 3)
}

@(test)
test_zone_offsets_follow_the_records :: proc(t: ^testing.T) {
	z := new_york()
	testing.expect_value(t, zone_offset(z, 1767225600), -5 * HOUR)
	testing.expect_value(t, zone_offset(z, 1772953200 + 1), -4 * HOUR)
	// A record's own first second reads its offset, not the one before.
	testing.expect_value(t, zone_offset(z, 1772953200), -4 * HOUR)
	testing.expect_value(t, zone_offset(z, 1772953199), -5 * HOUR)
	// 02:30 on 2026-03-08 never happens in New York: it lands after the jump.
	gap := days_from_civil(2026, 3, 8) * DAY + 2 * HOUR + 1800
	testing.expect_value(t, wall_of(z, wall_to_unix(z, gap)), gap + HOUR)
	// 01:30 on 2026-11-01 happens twice: the first, in EDT.
	twice := days_from_civil(2026, 11, 1) * DAY + HOUR + 1800
	testing.expect_value(t, wall_to_unix(z, twice), twice + 4 * HOUR)
}

@(test)
test_days_start_at_local_midnight_across_spring_forward :: proc(t: ^testing.T) {
	z := new_york()
	lo := f64(wall_to_unix(z, days_from_civil(2026, 3, 5) * DAY))
	hi := f64(wall_to_unix(z, days_from_civil(2026, 3, 12) * DAY))
	tk := time_ticks(lo, hi, 10, z)
	testing.expect_value(t, tk.unit, Time_Step{.Day, 1})
	testing.expect_value(t, tk.n, 8)
	for v, i in ticks_of(&tk) {
		c := civil_from_wall(wall_of(z, i64(v)))
		testing.expectf(t, c.hour == 0 && c.minute == 0, "tick %d is at %02d:%02d, not midnight", i, c.hour, c.minute)
		if i > 0 {
			gap := i64(v - tk.v[i - 1])
			// The day clocks go forward is an hour short.
			want := i64(DAY - HOUR) if c.day == 9 else DAY
			testing.expectf(t, gap == want, "day %d is %d s long, want %d", c.day, gap, want)
		}
	}
}

@(test)
test_hours_skip_the_hour_clocks_jump :: proc(t: ^testing.T) {
	z := new_york()
	lo := f64(wall_to_unix(z, days_from_civil(2026, 3, 8) * DAY))
	hi := f64(wall_to_unix(z, days_from_civil(2026, 3, 8) * DAY + 6 * HOUR))
	tk := time_ticks(lo, hi, 8, z)
	testing.expect_value(t, tk.unit, Time_Step{.Hour, 1})
	want := [?]string{"00:00", "01:00", "03:00", "04:00", "05:00", "06:00"}
	testing.expect_value(t, tk.n, len(want))
	for i in 0 ..< min(tk.n, len(want)) {
		l := time_label(&tk, i, z)
		testing.expect_value(t, label_text(&l.main), want[i])
		if i > 0 {
			testing.expect_value(t, tk.v[i] - tk.v[i - 1], HOUR) // 02:00 does not exist
		}
	}
}

@(test)
test_hours_fall_back_once :: proc(t: ^testing.T) {
	z := new_york()
	day := days_from_civil(2026, 11, 1) * DAY
	tk := time_ticks(f64(wall_to_unix(z, day)), f64(wall_to_unix(z, day + 4 * HOUR)), 8, z)
	want := [?]string{"00:00", "01:00", "02:00", "03:00", "04:00"}
	testing.expect_value(t, tk.n, len(want))
	for i in 0 ..< min(tk.n, len(want)) {
		l := time_label(&tk, i, z)
		testing.expect_value(t, label_text(&l.main), want[i])
	}
	// 01:00 EDT to 02:00 EST is two hours: the 01:00 clocks repeat is not
	// ticked twice.
	testing.expect_value(t, tk.v[2] - tk.v[1], 2 * HOUR)
	first := time_label(&tk, 0, z)
	testing.expect_value(t, label_text(&first.sub), "Nov 1")
}

@(test)
test_months_name_the_year_where_it_turns :: proc(t: ^testing.T) {
	lo := f64(days_from_civil(2025, 11, 15) * DAY)
	hi := f64(days_from_civil(2026, 4, 20) * DAY)
	tk := time_ticks(lo, hi, 6, {})
	testing.expect_value(t, tk.unit, Time_Step{.Month, 1})
	mains := [?]string{"Dec", "Jan", "Feb", "Mar", "Apr"}
	subs := [?]string{"2025", "2026", "", "", ""}
	testing.expect_value(t, tk.n, len(mains))
	for i in 0 ..< min(tk.n, len(mains)) {
		l := time_label(&tk, i, {})
		testing.expect_value(t, label_text(&l.main), mains[i])
		testing.expect_value(t, label_text(&l.sub), subs[i])
	}
}

@(test)
test_weeks_start_on_monday :: proc(t: ^testing.T) {
	lo := f64(days_from_civil(2026, 1, 1) * DAY)
	hi := f64(days_from_civil(2026, 4, 1) * DAY)
	tk := time_ticks(lo, hi, 16, {})
	testing.expect(t, tk.unit.unit == .Week, "13 weeks at 16 ticks steps by the week")
	for v in ticks_of(&tk) {
		c := civil_from_wall(i64(v))
		testing.expect_value(t, c.wday, 1)
	}
	l := time_label(&tk, 0, {})
	testing.expect_value(t, label_text(&l.main), "Jan 5") // %e's padding closed up
}

@(test)
test_a_zone_off_the_hour_ticks_its_own_half_hours :: proc(t: ^testing.T) {
	nepal := Zone{offset = 5 * HOUR + 45 * 60}
	lo := f64(days_from_civil(2026, 6, 1) * DAY)
	tk := time_ticks(lo, lo + 4 * HOUR, 9, nepal)
	testing.expect_value(t, tk.unit, Time_Step{.Minute, 30})
	for v in ticks_of(&tk) {
		c := civil_from_wall(wall_of(nepal, i64(v)))
		testing.expectf(t, c.minute % 30 == 0 && c.second == 0, "tick at local %02d:%02d", c.hour, c.minute)
	}
}

@(test)
test_time_labels_name_every_tick_once :: proc(t: ^testing.T) {
	z := new_york()
	spans := [?]f64{90, 3600, 86400, 3 * 86400, 40 * 86400, 400 * 86400, 30 * 365 * 86400}
	for span in spans {
		lo := f64(1767225600 + 12345)
		tk := time_ticks(lo, lo + span, 12, z)
		testing.expectf(t, tk.n >= 2, "a span of %v s has %d ticks", span, tk.n)
		seen: map[string]bool
		defer delete(seen)
		sub := ""
		for i in 0 ..< tk.n {
			l := time_label(&tk, i, z)
			if l.sub.n > 0 {
				sub = fmt.tprint(label_text(&l.sub))
			}
			key := fmt.tprint(sub, label_text(&l.main))
			testing.expectf(t, !seen[key], "span %v: %q twice", span, key)
			seen[key] = true
		}
	}
}
