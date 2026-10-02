package primer

import "core:fmt"
import "core:strings"
import "core:testing"
import "core:time"
import "jm:ui"

// RelativeTime's formatting against @github/relative-time-element 5.0.0
// itself: every case below is what the vendored element's update() wrote
// for that date and now, run under node 26.8.1 with TZ=UTC and an en-US
// locale (a stub HTMLElement, Date.now held at now), 2026-10-02.

@(private = "file")
at :: proc(y, mo, d, h, mi, s, ms: int) -> time.Time {
	t, _ := time.datetime_to_time(y, mo, d, h, mi, s, ms * 1_000_000)
	return t
}

@(private = "file")
Relative_Options :: struct {
	format:    Relative_Format,
	tense:     Tense,
	precision: Maybe(Time_Unit),
	threshold: string, // "" is the element's P30D
	prefix:    Maybe(string), // nil is the element's "on"
	options:   Date_Options,
}

@(private = "file")
Relative_Case :: struct {
	date, now:   time.Time,
	o:           Relative_Options,
	text, title: string,
}

@(test)
test_relative_time_writes_what_the_element_writes :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	cases := [?]Relative_Case {
		{at(2026, 10, 2, 12, 0, 0, 0), at(2026, 10, 2, 12, 0, 5, 0), {}, "now", "Oct 2, 2026, 12:00 PM UTC"},
		{at(2026, 10, 2, 12, 0, 0, 0), at(2026, 10, 2, 12, 0, 45, 0), {}, "now", "Oct 2, 2026, 12:00 PM UTC"},
		{at(2026, 10, 2, 12, 0, 30, 0), at(2026, 10, 2, 12, 0, 0, 0), {}, "in 30 seconds", "Oct 2, 2026, 12:00 PM UTC"},
		{at(2026, 10, 2, 12, 0, 5, 0), at(2026, 10, 2, 12, 0, 0, 0), {}, "now", "Oct 2, 2026, 12:00 PM UTC"},
		{at(2026, 10, 2, 12, 0, 54, 0), at(2026, 10, 2, 12, 0, 0, 0), {}, "in 54 seconds", "Oct 2, 2026, 12:00 PM UTC"},
		{at(2026, 10, 2, 12, 0, 57, 0), at(2026, 10, 2, 12, 0, 0, 0), {}, "in 1 minute", "Oct 2, 2026, 12:00 PM UTC"},
		{at(2026, 10, 2, 11, 57, 0, 0), at(2026, 10, 2, 12, 0, 0, 0), {}, "3 minutes ago", "Oct 2, 2026, 11:57 AM UTC"},
		{at(2026, 10, 2, 11, 0, 0, 0), at(2026, 10, 2, 12, 0, 0, 0), {}, "1 hour ago", "Oct 2, 2026, 11:00 AM UTC"},
		{at(2026, 10, 2, 11, 4, 0, 0), at(2026, 10, 2, 12, 0, 0, 0), {}, "1 hour ago", "Oct 2, 2026, 11:04 AM UTC"},
		{at(2026, 10, 2, 7, 0, 0, 0), at(2026, 10, 2, 12, 0, 0, 0), {}, "5 hours ago", "Oct 2, 2026, 7:00 AM UTC"},
		{at(2026, 10, 1, 12, 0, 0, 0), at(2026, 10, 2, 12, 0, 0, 0), {}, "yesterday", "Oct 1, 2026, 12:00 PM UTC"},
		{at(2026, 10, 3, 12, 0, 0, 0), at(2026, 10, 2, 12, 0, 0, 0), {}, "tomorrow", "Oct 3, 2026, 12:00 PM UTC"},
		{at(2026, 9, 29, 12, 0, 0, 0), at(2026, 10, 2, 12, 0, 0, 0), {}, "3 days ago", "Sep 29, 2026, 12:00 PM UTC"},
		{at(2026, 9, 20, 12, 0, 0, 0), at(2026, 10, 2, 12, 0, 0, 0), {}, "2 weeks ago", "Sep 20, 2026, 12:00 PM UTC"},
		{at(2026, 9, 25, 12, 0, 0, 0), at(2026, 10, 2, 12, 0, 0, 0), {}, "last week", "Sep 25, 2026, 12:00 PM UTC"},
		{at(2026, 9, 2, 12, 0, 0, 0), at(2026, 10, 2, 12, 0, 0, 0), {}, "on Sep 2", "Sep 2, 2026, 12:00 PM UTC"},
		{at(2026, 8, 15, 12, 0, 0, 0), at(2026, 10, 2, 12, 0, 0, 0), {}, "on Aug 15", "Aug 15, 2026, 12:00 PM UTC"},
		{at(2025, 10, 2, 12, 0, 0, 0), at(2026, 10, 2, 12, 0, 0, 0), {}, "on Oct 2, 2025", "Oct 2, 2025, 12:00 PM UTC"},
		{at(2026, 8, 15, 12, 0, 0, 0), at(2026, 10, 2, 12, 0, 0, 0), {tense = .Past}, "2 months ago", "Aug 15, 2026, 12:00 PM UTC"},
		{at(2025, 6, 2, 12, 0, 0, 0), at(2026, 10, 2, 12, 0, 0, 0), {tense = .Past}, "last year", "Jun 2, 2025, 12:00 PM UTC"},
		{at(2024, 3, 2, 12, 0, 0, 0), at(2026, 10, 2, 12, 0, 0, 0), {tense = .Past}, "2 years ago", "Mar 2, 2024, 12:00 PM UTC"},
		{at(2026, 3, 31, 12, 0, 0, 0), at(2026, 4, 28, 12, 0, 0, 0), {tense = .Past}, "last month", "Mar 31, 2026, 12:00 PM UTC"},
		{at(2026, 10, 3, 12, 0, 0, 0), at(2026, 10, 2, 12, 0, 0, 0), {tense = .Past}, "now", "Oct 3, 2026, 12:00 PM UTC"},
		{at(2026, 10, 1, 12, 0, 0, 0), at(2026, 10, 2, 12, 0, 0, 0), {tense = .Future}, "now", "Oct 1, 2026, 12:00 PM UTC"},
		{at(2026, 10, 2, 11, 0, 0, 0), at(2026, 10, 2, 12, 0, 0, 0), {precision = .Minute}, "1 hour ago", "Oct 2, 2026, 11:00 AM UTC"},
		{at(2026, 10, 2, 11, 59, 58, 0), at(2026, 10, 2, 12, 0, 0, 0), {precision = .Minute}, "this minute", "Oct 2, 2026, 11:59 AM UTC"},
		{at(2026, 10, 2, 11, 59, 58, 0), at(2026, 10, 2, 12, 0, 0, 0), {precision = .Day}, "today", "Oct 2, 2026, 11:59 AM UTC"},
		{at(2026, 8, 15, 12, 0, 0, 0), at(2026, 10, 2, 12, 0, 0, 0), {threshold = "P1Y"}, "2 months ago", "Aug 15, 2026, 12:00 PM UTC"},
		{at(2026, 10, 1, 12, 0, 0, 0), at(2026, 10, 2, 12, 0, 0, 0), {threshold = "PT1H"}, "on Oct 1", "Oct 1, 2026, 12:00 PM UTC"},
		{at(2026, 10, 1, 12, 0, 0, 0), at(2026, 10, 2, 12, 0, 0, 0), {threshold = "bogus"}, "yesterday", "Oct 1, 2026, 12:00 PM UTC"},
		{at(2026, 8, 15, 12, 0, 0, 0), at(2026, 10, 2, 12, 0, 0, 0), {prefix = ""}, "Aug 15", "Aug 15, 2026, 12:00 PM UTC"},
		{at(2026, 8, 15, 12, 0, 0, 0), at(2026, 10, 2, 12, 0, 0, 0), {options = {weekday = .Short}}, "on Sat, Aug 15", "Aug 15, 2026, 12:00 PM UTC"},
		{at(2026, 8, 15, 12, 0, 0, 0), at(2026, 10, 2, 12, 0, 0, 0), {options = {weekday = .Long, month = .Long, year = .Numeric}}, "on Saturday, August 15, 2026", "Aug 15, 2026, 12:00 PM UTC"},
		{at(2026, 8, 15, 12, 0, 0, 0), at(2026, 10, 2, 12, 0, 0, 0), {options = {month = .Numeric}}, "on 8/15", "Aug 15, 2026, 12:00 PM UTC"},
		{at(2026, 8, 5, 12, 0, 0, 0), at(2026, 10, 2, 12, 0, 0, 0), {options = {month = .Two_Digit, day = .Two_Digit, year = .Two_Digit}}, "on 08/05/26", "Aug 5, 2026, 12:00 PM UTC"},
		{at(2026, 8, 15, 15, 4, 0, 0), at(2026, 10, 2, 12, 0, 0, 0), {options = {hour = .Numeric, minute = .Two_Digit}}, "on Aug 15, 3:04 PM", "Aug 15, 2026, 3:04 PM UTC"},
		{at(2026, 8, 15, 0, 4, 9, 0), at(2026, 10, 2, 12, 0, 0, 0), {options = {hour = .Numeric, minute = .Two_Digit, second = .Two_Digit}}, "on Aug 15, 12:04:09 AM", "Aug 15, 2026, 12:04 AM UTC"},
		{at(2026, 8, 15, 15, 4, 0, 0), at(2026, 10, 2, 12, 0, 0, 0), {options = {hour = .Numeric}}, "on Aug 15, 3 PM", "Aug 15, 2026, 3:04 PM UTC"},
		{at(2026, 8, 15, 15, 4, 0, 0), at(2026, 10, 2, 12, 0, 0, 0), {options = {hour = .Numeric, minute = .Two_Digit, time_zone_name = true}}, "on Aug 15, 3:04 PM UTC", "Aug 15, 2026, 3:04 PM UTC"},
		{at(2026, 8, 15, 15, 4, 0, 0), at(2026, 10, 2, 12, 0, 0, 0), {options = {month = .Hidden}}, "on 15", "Aug 15, 2026, 3:04 PM UTC"},
		{at(2026, 8, 15, 15, 4, 0, 0), at(2026, 10, 2, 12, 0, 0, 0), {options = {day = .Long}}, "on Aug", "Aug 15, 2026, 3:04 PM UTC"},
		{at(2026, 10, 2, 9, 0, 0, 0), at(2026, 10, 2, 12, 0, 0, 0), {format = .Micro}, "3h", "Oct 2, 2026, 9:00 AM UTC"},
		{at(2026, 10, 2, 11, 59, 30, 0), at(2026, 10, 2, 12, 0, 0, 0), {format = .Micro}, "1m", "Oct 2, 2026, 11:59 AM UTC"},
		{at(2026, 9, 20, 12, 0, 0, 0), at(2026, 10, 2, 12, 0, 0, 0), {format = .Micro}, "2w", "Sep 20, 2026, 12:00 PM UTC"},
		{at(2025, 2, 20, 12, 0, 0, 0), at(2026, 10, 2, 12, 0, 0, 0), {format = .Micro}, "1y", "Feb 20, 2025, 12:00 PM UTC"},
		{at(2026, 10, 5, 12, 0, 0, 0), at(2026, 10, 2, 12, 0, 0, 0), {format = .Micro, tense = .Past}, "1m", "Oct 5, 2026, 12:00 PM UTC"},
		{at(2026, 9, 28, 8, 57, 59, 0), at(2026, 10, 2, 12, 0, 0, 0), {format = .Elapsed}, "4d 3h 2m 1s", "Sep 28, 2026, 8:57 AM UTC"},
		{at(2026, 10, 2, 12, 0, 0, 0), at(2026, 10, 2, 12, 0, 0, 0), {format = .Elapsed}, "0s", "Oct 2, 2026, 12:00 PM UTC"},
		{at(2026, 9, 28, 8, 57, 59, 0), at(2026, 10, 2, 12, 0, 0, 0), {format = .Elapsed, precision = .Minute}, "4d 3h 2m", "Sep 28, 2026, 8:57 AM UTC"},
		{at(2026, 10, 5, 12, 0, 0, 0), at(2026, 10, 2, 12, 0, 0, 0), {format = .Elapsed, tense = .Past}, "0s", "Oct 5, 2026, 12:00 PM UTC"},
		{at(2024, 1, 1, 0, 0, 0, 0), at(2026, 10, 2, 12, 0, 0, 0), {format = .Elapsed, precision = .Year}, "2y 9mo 15d 12h", "Jan 1, 2024, 12:00 AM UTC"},
		{at(2026, 10, 2, 11, 59, 59, 950), at(2026, 10, 2, 12, 0, 0, 0), {format = .Elapsed, precision = .Millisecond}, "50ms", "Oct 2, 2026, 11:59 AM UTC"},
	}
	for c, i in cases {
		threshold := c.o.threshold if c.o.threshold != "" else "P30D"
		prefix := c.o.prefix.? or_else "on"
		got, _ := relative_time_text(c.date, c.now, c.o.format, c.o.tense, c.o.precision, threshold, prefix, c.o.options)
		testing.expectf(t, got == c.text, "case %d: got %q, want %q", i, got, c.text)
		title := relative_time_title(c.date)
		testing.expectf(t, title == c.title, "case %d: title %q, want %q", i, title, c.title)
	}
}

@(test)
test_parse_duration_reads_what_duration_re_reads :: proc(t: ^testing.T) {
	s, ok := parse_duration("P1Y2M3W4DT5H6M7S")
	testing.expect(t, ok)
	testing.expect_value(t, s.v, [Time_Unit]i64{.Year = 1, .Month = 2, .Week = 3, .Day = 4, .Hour = 5, .Minute = 6, .Second = 7, .Millisecond = 0})
	testing.expect_value(t, s.sign, 1)
	neg, _ := parse_duration("-PT90M")
	testing.expect_value(t, neg.v[.Minute], -90) // 90 minutes stays 90: nothing is carried
	testing.expect_value(t, neg.sign, -1)
	for bad in ([]string{"", "30D", "P1H", "PT1D", "P1M1Y", "P1.5D", "P1D2"}) {
		_, parsed := parse_duration(bad)
		testing.expectf(t, !parsed, "%q parsed", bad)
	}
	empty, parsed := parse_duration("P") // the regex matches a bare P: a blank duration
	testing.expect(t, parsed && empty.sign == 0)
}

@(test)
test_relative_time_redraws_when_its_text_next_changes :: proc(t: ^testing.T) {
	now := at(2026, 10, 2, 12, 0, 0, 0)
	// 30.25s away: a second's cadence, 0.75s to the next whole second.
	testing.expect_value(t, relative_time_wait(at(2026, 10, 2, 12, 0, 30, 250), now, .Auto, .Second), 0.75)
	// 3m10s away: a minute's, 50s to go.
	testing.expect_value(t, relative_time_wait(at(2026, 10, 2, 11, 56, 50, 0), now, .Auto, .Second), 50)
	// 5h away: an hour's, a whole hour to go.
	testing.expect_value(t, relative_time_wait(at(2026, 10, 2, 7, 0, 0, 0), now, .Micro, .Minute), 3600)
	// Elapsed ticks at its precision however far away.
	testing.expect_value(t, relative_time_wait(at(2026, 9, 28, 8, 57, 59, 500), now, .Elapsed, .Second), 0.5)
}

@(private = "file")
Relative_Model :: struct {
	date, now: time.Time,
}

@(test)
test_relative_time_draws_the_phrase_and_asks_for_its_next_frame :: proc(t: ^testing.T) {
	view :: proc(gtx: ^ui.Ctx, user: rawptr) {
		m := (^Relative_Model)(user)
		col := ui.column_open(gtx)
		defer ui.close(&col)
		relative_time(gtx, m.date, now = m.now, zone = nil)
		relative_time(gtx, at(2025, 10, 2, 12, 0, 0, 0), now = m.now, key = 1) // a date: nothing to redraw
	}
	defer free_all(context.temp_allocator)
	m := Relative_Model{at(2026, 10, 2, 11, 57, 0, 0), at(2026, 10, 2, 12, 0, 0, 0)}
	p: ui.Probe
	ui.probe_init(&p, view, &m, {400, 200}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	testing.expect(t, ui.probe_tagged(&p, "3 minutes ago"))
	testing.expect(t, p.wants_frame)
	testing.expect_value(t, p.frame_after, 60) // three whole minutes: the next minute is a minute off
	sem := ui.probe_semantics(&p, context.temp_allocator)
	title := relative_time_title(m.date, user_zone(), context.temp_allocator)
	testing.expect(t, strings.contains(sem, fmt.tprintf("text \"3 minutes ago\" desc %q", title)), sem) // the title is its description
	// The date alone asks for nothing.
	m.date = at(2025, 10, 2, 12, 0, 0, 0)
	ui.probe_frame(&p)
	testing.expect(t, !p.wants_frame)
	testing.expect_value(t, ui.probe_bounds(&p, "on Oct 2, 2025").h, tok_body_line())
}

@(private = "file")
tok_body_line :: proc() -> f32 {
	return text_style().line_height
}
