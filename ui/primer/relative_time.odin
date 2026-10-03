package primer

import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:time"
import "core:time/datetime"
import "core:time/timezone"
import "jm:timefmt"
import "jm:ui"
import "jm:ui/ops"

// RelativeTime's text is @github/relative-time-element 5.0.0's, vendored
// at tools/primer/upstream/npm/relative-time-element: the relative phrase
// within a threshold ("3 days ago", "in 2 hours", "yesterday"), a date
// past it ("on Oct 2"), and the micro and elapsed durations ("3h",
// "4d 3h 2m 1s"). This file ports duration.js and the element's
// formatting (relative-time-element.js) rule for rule, including the
// quirks noted where they occur. The element formats through the
// browser's Intl APIs in the page's language; jm:ui has no locale, so
// the text is English as Intl's en-US gives it.

// Time_Unit is a unit of a span of time, largest first, in
// duration.js's unitNames order.
Time_Unit :: enum u8 {
	Year,
	Month,
	Week,
	Day,
	Hour,
	Minute,
	Second,
	Millisecond,
}

// Span is duration.js's Duration: a count per unit, each the same sign,
// and that sign (-1 past, 1 future, 0 blank).
Span :: struct {
	v:    [Time_Unit]i64,
	sign: i64,
}

// span_of is the Duration constructor: the sign is the first non-zero
// unit's, largest first (duration.js:8-33).
span_of :: proc(v: [Time_Unit]i64) -> (s: Span) {
	s.v = v
	for n in v {
		if n != 0 {
			s.sign = n < 0 ? -1 : 1
			break
		}
	}
	return
}

// span_abs is the span with every count made positive.
span_abs :: proc(s: Span) -> Span {
	v := s.v
	for &n in v {
		n = abs(n)
	}
	return span_of(v)
}

// parse_duration reads an ISO 8601 duration as duration.js's durationRe
// does: [-+]P, then any of nY nM nW nD, then T and any of nH nM nS, with
// no fractions (duration.js:2,39-48). A leading minus negates every part.
parse_duration :: proc(str: string) -> (s: Span, ok: bool) {
	t := strings.trim_space(str)
	factor := i64(1)
	if strings.has_prefix(t, "-") || strings.has_prefix(t, "+") {
		factor = t[0] == '-' ? -1 : 1
		t = t[1:]
	}
	if !strings.has_prefix(t, "P") {
		return
	}
	t = t[1:]
	v: [Time_Unit]i64
	date_units := [4]Time_Unit{.Year, .Month, .Week, .Day}
	time_units := [3]Time_Unit{.Hour, .Minute, .Second}
	designators, units := "YMWD", date_units[:]
	next := 0 // the first designator still allowed, so each comes once and in order
	in_time := false
	for len(t) > 0 {
		if t[0] == 'T' && !in_time {
			designators, units, next, in_time = "HMS", time_units[:], 0, true
			t = t[1:]
			continue
		}
		digits := 0
		n: i64
		for digits < len(t) && t[digits] >= '0' && t[digits] <= '9' {
			n = n * 10 + i64(t[digits] - '0')
			digits += 1
		}
		if digits == 0 || digits == len(t) {
			return
		}
		at := strings.index_byte(designators[next:], t[digits])
		if at < 0 {
			return
		}
		v[units[next + at]] = n * factor
		next += at + 1
		t = t[digits + 1:]
	}
	return span_of(v), true
}

// MS_PER is each fixed unit in milliseconds.
@(private = "file")
MS_SECOND :: i64(1000)
@(private = "file")
MS_MINUTE :: 60 * MS_SECOND
@(private = "file")
MS_HOUR :: 60 * MS_MINUTE
@(private = "file")
MS_DAY :: 24 * MS_HOUR

// unix_ms is t in whole milliseconds since 1970, as a JS Date holds it.
@(private = "file")
unix_ms :: proc(t: time.Time) -> i64 {
	ns := time.to_unix_nanoseconds(t)
	ms := ns / 1_000_000
	if ns % 1_000_000 < 0 {
		ms -= 1
	}
	return ms
}

// elapsed_time is the span from now to date in whole units down to
// precision, months 30 days and years 12 months (duration.js:93-108).
// The port keeps a slip: indexOf('year') is 0, which the || takes for
// missing, so a precision of year counts every unit.
elapsed_time :: proc(date, now: time.Time, precision := Time_Unit.Second) -> Span {
	delta := unix_ms(date) - unix_ms(now)
	if delta == 0 {
		return {}
	}
	sign := delta < 0 ? i64(-1) : 1
	ms := abs(delta)
	sec := ms / 1000
	mins := sec / 60
	hr := mins / 60
	day := hr / 24
	month := day / 30
	year := month / 12
	i := int(precision)
	if i == 0 {
		i = len(Time_Unit)
	}
	v: [Time_Unit]i64
	v[.Year] = year * sign
	v[.Month] = i >= 1 ? (month - year * 12) * sign : 0
	v[.Day] = i >= 3 ? (day - month * 30) * sign : 0
	v[.Hour] = i >= 4 ? (hr - day * 24) * sign : 0
	v[.Minute] = i >= 5 ? (mins - hr * 60) * sign : 0
	v[.Second] = i >= 6 ? (sec - mins * 60) * sign : 0
	v[.Millisecond] = i >= 7 ? (ms - sec * 1000) * sign : 0
	return span_of(v)
}

// Civil is a wall-clock date: month 0-11 as JS counts it, day of the
// month, and milliseconds into the day.
@(private)
Civil :: struct {
	year, month, day, ms: i64,
}

// days_from_civil is the days from 1970-01-01 to y-m-d, m 1-12, in the
// proleptic Gregorian calendar (Howard Hinnant's chrono-compatible
// low-level date algorithms, days_from_civil).
@(private = "file")
days_from_civil :: proc(year, m, d: i64) -> i64 {
	y := year - (m <= 2 ? 1 : 0)
	era := (y >= 0 ? y : y - 399) / 400
	yoe := y - era * 400
	mp := (m + 9) % 12
	doy := (153 * mp + 2) / 5 + d - 1
	doe := yoe * 365 + yoe / 4 - yoe / 100 + doy
	return era * 146097 + doe - 719468
}

// civil_from_days is days_from_civil's inverse, month 0-11.
@(private = "file")
civil_from_days :: proc(days: i64) -> (y, m, d: i64) {
	z := days + 719468
	era := (z >= 0 ? z : z - 146096) / 146097
	doe := z - era * 146097
	yoe := (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
	doy := doe - (365 * yoe + yoe / 4 - yoe / 100)
	mp := (5 * doy + 2) / 153
	d = doy - (153 * mp + 2) / 5 + 1
	m = mp < 10 ? mp + 3 : mp - 9
	y = yoe + era * 400 + (m <= 2 ? 1 : 0)
	return y, m - 1, d
}

@(private = "file")
floor_div :: proc(a, b: i64) -> i64 {
	q := a / b
	if (a % b != 0) && ((a < 0) != (b < 0)) {
		q -= 1
	}
	return q
}

// civil_make is y, month m (0-based, any value) and day d (any value,
// 0 the last of the month before) carried into range, as a JS Date's
// setters carry them; ms is kept.
@(private = "file")
civil_make :: proc(y, m, d, ms: i64) -> Civil {
	yy := y + floor_div(m, 12)
	mm := m - floor_div(m, 12) * 12
	z := days_from_civil(yy, mm + 1, 1) + d - 1
	cy, cm, cd := civil_from_days(z)
	return {cy, cm, cd, ms}
}

@(private = "file")
civil_from_ms :: proc(ms: i64) -> Civil {
	days := floor_div(ms, MS_DAY)
	y, m, d := civil_from_days(days)
	return {y, m, d, ms - days * MS_DAY}
}

@(private = "file")
civil_ms :: proc(c: Civil) -> i64 {
	return days_from_civil(c.year, c.month + 1, c.day) * MS_DAY + c.ms
}

// zone_offset_ms is how far zone's wall clock is ahead of UTC at t, and
// its abbreviation then ("UTC" for no zone).
@(private)
zone_offset_ms :: proc(t: time.Time, zone: ^datetime.TZ_Region) -> (offset: i64, name: string) {
	if zone == nil {
		return 0, "UTC"
	}
	utc, ok := time.time_to_datetime(t)
	if !ok {
		return 0, "UTC"
	}
	local, converted := timezone.datetime_to_tz(utc, zone)
	if !converted {
		return 0, "UTC"
	}
	wall, _ := time.datetime_to_time(local.date.year, local.date.month, local.date.day, local.time.hour, local.time.minute, local.time.second)
	// Both in whole seconds, so t's fraction does not shave the offset.
	offset = (time.to_unix_seconds(wall) - time.to_unix_seconds(t)) * 1000
	// shortname reads the instant from the fields, ignoring their zone
	// (core:time/timezone tzdate.odin:243-249, dev-2026-09), so it is given
	// the UTC fields with the zone attached.
	utc.tz = zone
	return offset, timezone.shortname(utc)
}

// local_civil is t on zone's wall clock.
@(private)
local_civil :: proc(t: time.Time, zone: ^datetime.TZ_Region) -> Civil {
	off, _ := zone_offset_ms(t, zone)
	return civil_from_ms(unix_ms(t) + off)
}

// round_to_single_unit rounds s, a span from now, to the one unit a
// relative phrase names, by duration.js's roundToSingleUnit
// (duration.js:109-182): a unit at 55 of the next rounds up, days from
// 12 hours (21 with no days), and calendar months and years counted on
// zone's calendar from now, so a month back from 31 March is 28 or 29
// February.
round_to_single_unit :: proc(s: Span, now: time.Time, zone: ^datetime.TZ_Region = nil) -> Span {
	if s.sign == 0 {
		return s
	}
	sign := s.sign
	years, months, weeks, days := abs(s.v[.Year]), abs(s.v[.Month]), abs(s.v[.Week]), abs(s.v[.Day])
	hours, minutes, seconds, ms := abs(s.v[.Hour]), abs(s.v[.Minute]), abs(s.v[.Second]), abs(s.v[.Millisecond])
	if ms >= 900 {
		seconds += round_half_up(f64(ms) / 1000)
	}
	if seconds != 0 || minutes != 0 || hours != 0 || days != 0 || weeks != 0 || months != 0 || years != 0 {
		ms = 0
	}
	if seconds >= 55 {
		minutes += round_half_up(f64(seconds) / 60)
	}
	if minutes != 0 || hours != 0 || days != 0 || weeks != 0 || months != 0 || years != 0 {
		seconds = 0
	}
	if minutes >= 55 {
		hours += round_half_up(f64(minutes) / 60)
	}
	if hours != 0 || days != 0 || weeks != 0 || months != 0 || years != 0 {
		minutes = 0
	}
	if days != 0 && hours >= 12 {
		days += round_half_up(f64(hours) / 24)
	}
	if days == 0 && hours >= 21 {
		days += round_half_up(f64(hours) / 24)
	}
	if days != 0 || weeks != 0 || months != 0 || years != 0 {
		hours = 0
	}
	if days >= 27 || years + months + days != 0 {
		years, months, weeks, days = calendar_round(years, months, weeks, days, sign, local_civil(now, zone))
	}
	if years != 0 {
		months = 0
	}
	if weeks >= 4 {
		months += round_half_up(f64(weeks) / 4)
	}
	if months != 0 || years != 0 {
		weeks = 0
	}
	if days != 0 && weeks != 0 && months == 0 && years == 0 {
		weeks += round_half_up(f64(days) / 7)
		days = 0
	}
	return span_of(
		{
			.Year = years * sign,
			.Month = months * sign,
			.Week = weeks * sign,
			.Day = days * sign,
			.Hour = hours * sign,
			.Minute = minutes * sign,
			.Second = seconds * sign,
			.Millisecond = ms * sign,
		},
	)
}

// calendar_round is roundToSingleUnit's calendar step (duration.js
// :147-176): it moves now's date by the span with a JS Date's setters
// and counts whole days or months between.
@(private = "file")
calendar_round :: proc(years_in, months_in, weeks_in, days_in, sign: i64, now: Civil) -> (years, months, weeks, days: i64) {
	years, months, weeks, days = years_in, months_in, weeks_in, days_in
	cy, cm, cd := now.year, now.month, now.day
	month_end := civil_make(cy, cm + months * sign + 1, 0, now.ms)
	correction := max(0, cd - month_end.day)
	d := civil_make(cy + years * sign, cm, cd, now.ms) // setFullYear
	d = civil_make(d.year, d.month, cd - correction, now.ms) // setDate
	d = civil_make(d.year, cm + months * sign, d.day, now.ms) // setMonth
	d = civil_make(d.year, d.month, cd - correction + days * sign, now.ms) // setDate
	year_diff := d.year - cy
	month_diff := d.month - cm
	days_diff := abs(round_half_up(f64(civil_ms(d) - civil_ms(now)) / f64(MS_DAY))) + correction
	months_diff := abs(year_diff * 12 + month_diff)
	switch {
	case days_diff < 27:
		if days >= 6 {
			weeks += round_half_up(f64(days) / 7)
			days = 0
		} else {
			days = days_diff
		}
		months, years = 0, 0
	case months_diff <= 11:
		months = months_diff
		years = 0
	case:
		months = 0
		years = year_diff * sign
	}
	if months != 0 || years != 0 {
		days = 0
	}
	return
}

// round_half_up is Math.round: halves round up, toward positive infinity.
@(private = "file")
round_half_up :: proc(x: f64) -> i64 {
	f := i64(x)
	if f64(f) > x {
		f -= 1 // truncation went up for a negative x
	}
	if x - f64(f) >= 0.5 {
		f += 1
	}
	return f
}

// relative_unit is the one unit and count a relative phrase says for s:
// getRelativeTimeUnit (duration.js:183-193).
relative_unit :: proc(s: Span, now: time.Time, zone: ^datetime.TZ_Region = nil) -> (n: i64, unit: Time_Unit) {
	r := round_to_single_unit(s, now, zone)
	if r.sign == 0 {
		return 0, .Second
	}
	for u in Time_Unit {
		if u != .Millisecond && r.v[u] != 0 {
			return r.v[u], u
		}
	}
	return 0, .Second
}

// apply_span is now moved by s with a JS Date's UTC setters, the large
// units last when s is negative (duration.js:72-92).
@(private = "file")
apply_span :: proc(now_ms: i64, s: Span) -> i64 {
	c := civil_from_ms(now_ms)
	small := s.v[.Second] * MS_SECOND + s.v[.Minute] * MS_MINUTE + s.v[.Hour] * MS_HOUR
	days := s.v[.Week] * 7 + s.v[.Day]
	if s.sign < 0 {
		c = civil_from_ms(civil_ms(c) + small)
		c = civil_make(c.year, c.month, c.day + days, c.ms)
		c = civil_make(c.year, c.month + s.v[.Month], c.day, c.ms)
		c = civil_make(c.year + s.v[.Year], c.month, c.day, c.ms)
	} else {
		c = civil_make(c.year + s.v[.Year], c.month, c.day, c.ms)
		c = civil_make(c.year, c.month + s.v[.Month], c.day, c.ms)
		c = civil_make(c.year, c.month, c.day + days, c.ms)
		c = civil_from_ms(civil_ms(c) + small)
	}
	return civil_ms(c)
}

// within is Duration.compare(s, limit) === 1: s reaches less far from
// now than limit does (duration.js:50-55).
@(private = "file")
within :: proc(s, limit: Span, now: time.Time) -> bool {
	at := unix_ms(now)
	return abs(apply_span(at, s) - at) < abs(apply_span(at, limit) - at)
}

// Relative_Format is what RelativeTime shows: Auto a relative phrase
// within the threshold and a date past it, Micro the one-unit duration
// ("3h"), Elapsed the duration in every unit down to the precision.
Relative_Format :: enum u8 {
	Auto,
	Micro,
	Elapsed,
}

// Tense forces a relative phrase into the past or future; a time on the
// wrong side of now reads as now.
Tense :: enum u8 {
	Auto,
	Past,
	Future,
}

// Date_Style is how one field of the date form is written, as an
// Intl.DateTimeFormat option: Default is the element's own choice
// (month short, day numeric, the year only when it is not this year,
// the rest left out), Hidden leaves the field out. A style a field does
// not take (Long for a day) leaves it out, as the element's getters do.
Date_Style :: enum u8 {
	Default,
	Hidden,
	Numeric,
	Two_Digit,
	Short,
	Long,
	Narrow,
}

// Date_Options is the date form's fields (relative-time.json inputs
// second to timeZoneName); time_zone_name adds the zone's abbreviation.
Date_Options :: struct {
	weekday, year, month, day, hour, minute, second: Date_Style,
	time_zone_name:                                   bool,
}

// style_name is an English name (timefmt's MONTHS and DAYS) in style:
// short is the first three letters (May stays May), narrow the first.
@(private = "file")
style_name :: proc(long: string, style: Date_Style) -> string {
	#partial switch style {
	case .Short:
		return long[:3]
	case .Narrow:
		return long[:1]
	}
	return long
}

@(private = "file")
write_numeral :: proc(sb: ^strings.Builder, n: i64, style: Date_Style) {
	if style == .Two_Digit {
		fmt.sbprintf(sb, "%02d", n %% 100)
	} else {
		fmt.sbprintf(sb, "%d", n)
	}
}

// Date_Fields is a Date_Options with its defaults applied and the styles a
// field does not take dropped: what the element's getters return.
@(private = "file")
Date_Fields :: struct {
	weekday, year, month, day, hour, minute, second: Date_Style,
	zone:                                             bool,
}

// resolve applies the element's defaults for format auto
// (relative-time-element.js:143-213): month short, day numeric, the
// year numeric when date's UTC year is not now's, the rest left out.
@(private = "file")
resolve :: proc(o: Date_Options, date, now: time.Time) -> (r: Date_Fields) {
	pick :: proc(p: Date_Style, def: Date_Style, allowed: bit_set[Date_Style]) -> Date_Style {
		if p == .Default {
			return def
		}
		return p in allowed ? p : .Hidden
	}
	numeric := bit_set[Date_Style]{.Numeric, .Two_Digit}
	named_styles := bit_set[Date_Style]{.Short, .Long, .Narrow}
	r.weekday = pick(o.weekday, .Hidden, named_styles)
	r.day = pick(o.day, .Numeric, numeric)
	r.month = pick(o.month, .Short, numeric + named_styles)
	this_year := civil_from_ms(unix_ms(now)).year == civil_from_ms(unix_ms(date)).year
	r.year = pick(o.year, .Hidden if this_year else .Numeric, numeric)
	r.hour = pick(o.hour, .Hidden, numeric)
	r.minute = pick(o.minute, .Hidden, numeric)
	r.second = pick(o.second, .Hidden, numeric)
	r.zone = o.time_zone_name
	return
}

// format_date writes date on zone's wall clock as Intl.DateTimeFormat
// en-US writes r's fields (as node 26's ICU wrote them for
// relative_time_test's cases): "Thu, Oct 2, 2025", "10/2/2025", then ", "
// and the time, "3:04 PM", then the zone's abbreviation.
@(private = "file")
format_date :: proc(sb: ^strings.Builder, date: time.Time, r: Date_Fields, zone: ^datetime.TZ_Region) {
	off, zone_name := zone_offset_ms(date, zone)
	c := civil_from_ms(unix_ms(date) + off)
	weekday := (floor_div(civil_ms(c), MS_DAY) % 7 + 11) % 7 // 1970-01-01 was a Thursday
	start := strings.builder_len(sb^)
	if r.weekday != .Hidden {
		strings.write_string(sb, style_name(timefmt.DAYS[weekday], r.weekday))
		if r.month != .Hidden || r.day != .Hidden || r.year != .Hidden {
			strings.write_string(sb, ", ")
		}
	}
	switch r.month {
	case .Short, .Long, .Narrow:
		strings.write_string(sb, style_name(timefmt.MONTHS[c.month], r.month))
		if r.day != .Hidden {
			strings.write_byte(sb, ' ')
			write_numeral(sb, c.day, r.day)
		}
		if r.year != .Hidden {
			strings.write_string(sb, r.day != .Hidden ? ", " : " ")
			write_numeral(sb, c.year, r.year)
		}
	case .Default, .Hidden, .Numeric, .Two_Digit:
		parts := 0
		if r.month != .Hidden {
			write_numeral(sb, c.month + 1, r.month)
			parts += 1
		}
		if r.day != .Hidden {
			if parts > 0 {
				strings.write_byte(sb, '/')
			}
			write_numeral(sb, c.day, r.day)
			parts += 1
		}
		if r.year != .Hidden {
			if parts > 0 {
				strings.write_byte(sb, '/')
			}
			write_numeral(sb, c.year, r.year)
		}
	}
	if r.hour != .Hidden {
		if strings.builder_len(sb^) > start {
			strings.write_string(sb, ", ")
		}
		h := c.ms / MS_HOUR
		twelve := h % 12 == 0 ? 12 : h % 12
		write_numeral(sb, twelve, r.hour)
		if r.minute != .Hidden {
			fmt.sbprintf(sb, ":%02d", c.ms / MS_MINUTE % 60)
			if r.second != .Hidden {
				fmt.sbprintf(sb, ":%02d", c.ms / MS_SECOND % 60)
			}
		}
		strings.write_string(sb, h < 12 ? " AM" : " PM")
	}
	if r.zone {
		strings.write_string(sb, r.hour != .Hidden ? " " : ", ")
		strings.write_string(sb, zone_name)
	}
}

// relative_phrase is Intl.RelativeTimeFormat en with numeric auto, long
// style: "yesterday", "next week", "now", "3 days ago", "in 1 hour".
@(private = "file")
relative_phrase :: proc(sb: ^strings.Builder, n: i64, unit: Time_Unit) {
	names := [Time_Unit]string {
		.Year        = "year",
		.Month       = "month",
		.Week        = "week",
		.Day         = "day",
		.Hour        = "hour",
		.Minute      = "minute",
		.Second      = "second",
		.Millisecond = "millisecond",
	}
	name := names[unit]
	switch {
	case n == 0 && unit == .Second:
		strings.write_string(sb, "now")
		return
	case n == 0 && unit == .Day:
		strings.write_string(sb, "today")
		return
	case n == 0:
		fmt.sbprintf(sb, "this %s", name)
		return
	case unit == .Day && abs(n) == 1:
		strings.write_string(sb, n < 0 ? "yesterday" : "tomorrow")
		return
	case (unit == .Week || unit == .Month || unit == .Year) && abs(n) == 1:
		fmt.sbprintf(sb, "%s %s", n < 0 ? "last" : "next", name)
		return
	}
	count := abs(n)
	plural := count == 1 ? "" : "s"
	if n < 0 {
		write_grouped(sb, count)
		fmt.sbprintf(sb, " %s%s ago", name, plural)
	} else {
		strings.write_string(sb, "in ")
		write_grouped(sb, count)
		fmt.sbprintf(sb, " %s%s", name, plural)
	}
}

// write_grouped writes n with commas between thousands, as en-US does.
@(private = "file")
write_grouped :: proc(sb: ^strings.Builder, n: i64) {
	if n >= 1000 {
		write_grouped(sb, n / 1000)
		fmt.sbprintf(sb, ",%03d", n % 1000)
		return
	}
	fmt.sbprintf(sb, "%d", n)
}

// format_span writes s as the element's DurationFormat ponyfill does in
// narrow style for en (duration-format-ponyfill.js:72-100): every unit
// that is not zero, or is in always, as "3y", "2mo", "1w", "4d", "5h",
// "6m", "7s", "8ms", joined by spaces as Intl.ListFormat's narrow unit
// list joins them.
@(private = "file")
format_span :: proc(sb: ^strings.Builder, s: Span, always: bit_set[Time_Unit] = {}) {
	suffix := [Time_Unit]string {
		.Year        = "y",
		.Month       = "mo",
		.Week        = "w",
		.Day         = "d",
		.Hour        = "h",
		.Minute      = "m",
		.Second      = "s",
		.Millisecond = "ms",
	}
	first := true
	for u in Time_Unit {
		if s.v[u] == 0 && u not_in always {
			continue
		}
		if !first {
			strings.write_byte(sb, ' ')
		}
		first = false
		write_grouped(sb, s.v[u])
		strings.write_string(sb, suffix[u])
	}
}

// default_precision is the element's precision when none is given:
// minute for micro, else second (relative-time-element.js:228-235).
default_precision :: proc(format: Relative_Format) -> Time_Unit {
	return format == .Micro ? .Minute : .Second
}

// relative_time_text is what RelativeTime shows for date at now, on
// zone's calendar and clock (UTC when nil): the element's update
// (relative-time-element.js:333-372) with its format resolved by
// resolveFormat, threshold the ISO 8601 duration within which Auto is
// relative (P30D when it does not parse), prefix the word before a date.
// live is whether the text changes as time passes, as a relative phrase
// or a duration does and a date does not: the element stops updating a
// date. The string is from allocator.
relative_time_text :: proc(
	date, now: time.Time,
	format := Relative_Format.Auto,
	tense := Tense.Auto,
	precision: Maybe(Time_Unit) = nil,
	threshold := "P30D",
	prefix := "on",
	options := Date_Options{},
	zone: ^datetime.TZ_Region = nil,
	allocator := context.temp_allocator,
) -> (text: string, live: bool) {
	unit := precision.? or_else default_precision(format)
	span := elapsed_time(date, now, unit)
	sb := strings.builder_make(allocator)
	switch format {
	case .Micro, .Elapsed:
		write_duration(&sb, span, format, tense, unit, now, zone)
		live = true
	case .Auto:
		limit, ok := parse_duration(threshold)
		if !ok {
			limit, _ = parse_duration("P30D")
		}
		if tense != .Auto || within(span, limit, now) {
			if (tense == .Future && span.sign != 1) || (tense == .Past && span.sign != -1) {
				span = {}
			}
			n, u := relative_unit(span, now, zone)
			if u == .Second && n < 10 {
				// Under ten seconds, and every past second, reads as the
				// precision's "now" (relative-time-element.js:442-444).
				relative_phrase(&sb, 0, unit == .Millisecond ? .Second : unit)
			} else {
				relative_phrase(&sb, n, u)
			}
			live = true
		} else {
			if prefix != "" {
				strings.write_string(&sb, prefix)
				strings.write_byte(&sb, ' ')
			}
			format_date(&sb, date, resolve(options, date, now), zone)
		}
	}
	return strings.to_string(sb), live
}

// write_duration is the element's getDurationFormat
// (relative-time-element.js:412-433): micro rounds to one unit and
// shows 1m for anything on the wrong side of a forced tense; elapsed
// shows a zero span there.
@(private = "file")
write_duration :: proc(sb: ^strings.Builder, span: Span, format: Relative_Format, tense: Tense, unit: Time_Unit, now: time.Time, zone: ^datetime.TZ_Region) {
	d := span
	empty: Span
	wrong_side := (tense == .Past && d.sign != -1) || (tense == .Future && d.sign != 1)
	if format == .Micro {
		d = round_to_single_unit(d, now, zone)
		empty = span_of(#partial [Time_Unit]i64{.Minute = 1})
		if d.v[.Month] == 0 && ((tense == .Past && d.sign != -1) || (tense == .Future && d.sign != 1)) {
			d = empty
		}
	} else if wrong_side {
		d = empty
	}
	if d.sign == 0 {
		format_span(sb, empty, {unit})
		return
	}
	format_span(sb, span_abs(d))
}

// relative_time_title is the precise date the element sets as its title:
// day numeric, month short, year numeric, hour numeric, minute 2-digit
// and the zone's abbreviation, "Oct 2, 2025, 3:04 PM UTC"
// (relative-time-element.js:385-395).
relative_time_title :: proc(date: time.Time, zone: ^datetime.TZ_Region = nil, allocator := context.temp_allocator) -> string {
	sb := strings.builder_make(allocator)
	format_date(&sb, date, {weekday = .Hidden, day = .Numeric, month = .Short, year = .Numeric, hour = .Numeric, minute = .Two_Digit, second = .Hidden, zone = true}, zone)
	return strings.to_string(sb)
}

// relative_time_wait is how long, in seconds, until the text for date
// may next change: the element's update cadence (getUnitFactor,
// relative-time-element.js:22-38), a second within a minute of now, a
// minute within the hour, then an hour, or the elapsed format's
// precision, counted to the next whole unit of the distance rather than
// from whenever it was drawn.
relative_time_wait :: proc(date, now: time.Time, format: Relative_Format, precision: Time_Unit) -> f32 {
	distance := abs(unix_ms(now) - unix_ms(date))
	factor := MS_HOUR
	switch {
	case format == .Elapsed && precision == .Second:
		factor = MS_SECOND
	case format == .Elapsed && precision == .Minute:
		factor = MS_MINUTE
	case distance < MS_MINUTE:
		factor = MS_SECOND
	case distance < MS_HOUR:
		factor = MS_MINUTE
	}
	return f32(factor - distance % factor) / 1000
}

// local_zone is the user's time zone, loaded once per thread; nil (UTC)
// when the system names none.
@(private = "file", thread_local)
local_zone: ^datetime.TZ_Region

@(private = "file", thread_local)
local_loaded: bool

@(private)
user_zone :: proc() -> ^datetime.TZ_Region {
	if !local_loaded {
		// Kept for the thread's life, so it comes from the heap rather than
		// the caller's allocator.
		local_zone, _ = timezone.region_load("local", runtime.heap_allocator())
		local_loaded = true
	}
	return local_zone
}

// relative_time is a timestamp as text relative to now (primer-kit
// components/relative-time.json, @github/relative-time-element): "3
// hours ago", "in 2 days" or, past threshold, "on Oct 2". format, tense,
// precision, threshold, prefix and options are the element's (see
// relative_time_text). The text is body text in size and color (the
// page's by default) and, while it is relative or a duration, is redrawn
// when it may next change (relative_time_wait). Unless no_title, the precise date is told to
// assistive technology as its description. now is the clock (the
// system's when zero); zone the time zone (the user's when nil).
//
// Departures: English only, as jm:ui has no locale; zone abbreviations
// are the tz database's, which Intl's need not match; the
// title is not shown on hover (no tooltip yet; see truncate); the
// element's datetime, relative and duration formats, its format-style
// and the page-wide data-prefers-absolute-time switch are not offered,
// as Primer's RelativeTime does not expose them.
relative_time :: proc(
	gtx: ^ui.Ctx,
	date: time.Time,
	format := Relative_Format.Auto,
	tense := Tense.Auto,
	precision: Maybe(Time_Unit) = nil,
	threshold := "P30D",
	prefix := "on",
	options := Date_Options{},
	no_title := false,
	size := Text_Size.Medium,
	color := ops.Color{},
	now := time.Time{},
	zone: ^datetime.TZ_Region = nil,
	key: u64 = 0,
	loc := #caller_location,
) -> ui.Dims {
	clock := now if now != {} else time.now()
	z := zone if zone != nil else user_zone()
	unit := precision.? or_else default_precision(format)
	s, live := relative_time_text(date, clock, format, tense, unit, threshold, prefix, options, z, gtx.allocator)
	if live {
		ui.request_frame(gtx, relative_time_wait(date, clock, format, unit))
	}
	b := Text_Block {
		style = text_style(size),
		color = ui.or_color(color, primer_fg()),
		semantics = {role = .Text},
	}
	if !no_title {
		b.semantics.description = relative_time_title(date, z, gtx.allocator)
	}
	return text_block(gtx, s, b, key, loc)
}
