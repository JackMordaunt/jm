package plot

import "core:math"
import "core:mem"
import "core:strings"
import "core:time"
import "core:time/datetime"
import "core:time/timezone"
import "jm:timefmt"

// Zone is the calendar a time axis is read in: an IANA region (loaded
// with core:time/timezone's region_load and kept by the caller), else a
// fixed offset east of UTC in seconds. The zero value is UTC.
Zone :: struct {
	region: ^datetime.TZ_Region,
	offset: i64,
}

// zone_offset is how many seconds z's wall clock runs ahead of UTC at the
// instant unix (seconds since 1970 UTC).
zone_offset :: proc(z: Zone, unix: i64) -> i64 {
	if z.region == nil {
		return z.offset
	}
	// time.Time counts nanoseconds in an i64, from 1678 to 2262; outside
	// that the offset at its nearest end stands.
	at := clamp(unix, TIME_MIN, TIME_MAX)
	// core:time/timezone takes the record before one that starts exactly
	// at the instant asked about (it searches for time < t, dev-2026-09),
	// so a second's offset is looked up a second later: a record's own
	// first second then reads its offset, and every other is unchanged.
	utc, ok := time.time_to_datetime(time.unix(at + 1, 0))
	if !ok {
		return 0
	}
	local, tz_ok := timezone.datetime_to_tz(utc, z.region)
	if !tz_ok {
		return 0
	}
	local.tz = nil
	wall, wall_ok := time.datetime_to_time(local)
	if !wall_ok {
		return 0
	}
	return time.time_to_unix(wall) - (at + 1)
}

// TIME_MIN and TIME_MAX are the seconds time.Time reaches, a day short of
// either end.
TIME_MIN :: -9_223_372_036 + 86400
TIME_MAX :: 9_223_372_036 - 86400

// wall_to_unix is the instant z's wall clock reads wall (seconds since
// 1970 on that clock). A wall time skipped by a change of offset, the
// hour clocks jump over in spring, lands at the instant after the jump;
// one that happens twice, as clocks fall back, lands at the first.
wall_to_unix :: proc(z: Zone, wall: i64) -> i64 {
	before := wall - zone_offset(z, wall - 86400) // the offset a day either side
	after := wall - zone_offset(z, wall + 86400)
	lo, hi := min(before, after), max(before, after)
	if wall_of(z, lo) == wall {
		return lo
	}
	if wall_of(z, hi) == wall {
		return hi
	}
	return hi // in a gap: the jump's far side
}

// wall_of is the wall clock reading of z at the instant unix.
wall_of :: proc(z: Zone, unix: i64) -> i64 {
	return unix + zone_offset(z, unix)
}

// Civil is a wall-clock reading broken into calendar fields.
Civil :: struct {
	year:                       i64,
	month, day:                 int, // 1-based
	hour, minute, second, wday: int, // wday 0 is Sunday
}

// days_from_civil is the days since 1970-01-01 of a proleptic Gregorian
// date (Howard Hinnant, "chrono-Compatible Low-Level Date Algorithms").
days_from_civil :: proc(y: i64, m, d: int) -> i64 {
	yy := y - (1 if m <= 2 else 0)
	era := (yy if yy >= 0 else yy - 399) / 400
	yoe := yy - era * 400
	mp := i64((m + 9) % 12)
	doy := (153 * mp + 2) / 5 + i64(d) - 1
	doe := yoe * 365 + yoe / 4 - yoe / 100 + doy
	return era * 146097 + doe - 719468
}

// civil_from_wall breaks a wall-clock reading into its fields.
civil_from_wall :: proc(wall: i64) -> (c: Civil) {
	days := math.floor_div(wall, 86400)
	secs := int(wall - days * 86400)
	z := days + 719468
	era := (z if z >= 0 else z - 146096) / 146097
	doe := z - era * 146097
	yoe := (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
	doy := doe - (365 * yoe + yoe / 4 - yoe / 100)
	mp := (5 * doy + 2) / 153
	c.day = int(doy - (153 * mp + 2) / 5 + 1)
	c.month = int(mp + 3 if mp < 10 else mp - 9)
	c.year = yoe + era * 400 + (1 if c.month <= 2 else 0)
	c.hour, c.minute, c.second = secs / 3600, secs / 60 % 60, secs % 60
	c.wday = int((days % 7 + 11) % 7) // 1970-01-01 was a Thursday
	return
}

// Time_Unit is a calendar unit a time axis steps by.
Time_Unit :: enum u8 {
	Second,
	Minute,
	Hour,
	Day,
	Week, // Monday to Monday
	Month,
	Year,
}

// Time_Step is n of a unit: the distance between a time axis's ticks.
Time_Step :: struct {
	unit: Time_Unit,
	n:    i64,
}

// TIME_STEPS are the steps a time axis may take, finest first.
TIME_STEPS := [?]Time_Step {
	{.Second, 1},
	{.Second, 5},
	{.Second, 15},
	{.Second, 30},
	{.Minute, 1},
	{.Minute, 5},
	{.Minute, 15},
	{.Minute, 30},
	{.Hour, 1},
	{.Hour, 3},
	{.Hour, 6},
	{.Hour, 12},
	{.Day, 1},
	{.Day, 2},
	{.Week, 1},
	{.Week, 2},
	{.Month, 1},
	{.Month, 3},
	{.Month, 6},
	{.Year, 1},
	{.Year, 2},
	{.Year, 5},
	{.Year, 10},
	{.Year, 25},
	{.Year, 50},
	{.Year, 100},
	{.Year, 250},
	{.Year, 500},
	{.Year, 1000},
}

// step_seconds is roughly how long s is, for choosing one.
@(private)
step_seconds :: proc(s: Time_Step) -> f64 {
	unit: f64
	switch s.unit {
	case .Second:
		unit = 1
	case .Minute:
		unit = 60
	case .Hour:
		unit = 3600
	case .Day:
		unit = 86400
	case .Week:
		unit = 7 * 86400
	case .Month:
		unit = 30.44 * 86400
	case .Year:
		unit = 365.25 * 86400
	}
	return unit * f64(s.n)
}

// Time_Ticks is a time axis's ticks: instants (seconds since 1970 UTC),
// and the step they were made at.
Time_Ticks :: struct {
	using list: Tick_List,
	unit:       Time_Step,
}

// time_ticks is at most max_count ticks inside [lo, hi] (seconds since 1970
// UTC) on z's calendar: on the boundaries of the finest step in TIME_STEPS
// that fits, so days start at local midnight, months on the 1st and weeks
// on Monday, whatever offsets the zone changes between. Steps of hours
// count the wall clock's hours, so a day clocks change in has one tick
// fewer or one more than a day of fixed offset would.
time_ticks :: proc(lo, hi: f64, max_count: int, z: Zone) -> (t: Time_Ticks) {
	lo, hi := lo, hi
	if lo > hi {
		lo, hi = hi, lo
	}
	if !tickable(lo) || !tickable(hi) {
		return
	}
	want := clamp(max_count, 1, MAX_TICKS)
	for s in TIME_STEPS {
		if (hi - lo) / step_seconds(s) + 1 > f64(want) * 1.2 {
			continue
		}
		t = {}
		t.unit = s
		if time_ticks_at(&t, i64(lo), i64(hi), want, z) {
			return
		}
	}
	t = {}
	t.unit = TIME_STEPS[len(TIME_STEPS) - 1]
	time_ticks_at(&t, i64(lo), i64(hi), want, z)
	return
}

// tickable reports whether a time axis may end at v. Past ±1e15 seconds,
// some 30 million years, there are no ticks: the wall-clock sums then
// stay far inside i64.
@(private)
tickable :: proc(v: f64) -> bool {
	return is_finite(v) && abs(v) <= 1e15
}

// time_ticks_at fills t with s's boundaries inside [lo, hi], reporting
// false when there are more than want.
@(private)
time_ticks_at :: proc(t: ^Time_Ticks, lo, hi: i64, want: int, z: Zone) -> bool {
	wall := floor_to(wall_of(z, lo), t.unit)
	prev := i64(min(i64))
	for _ in 0 ..< 4 * MAX_TICKS + 8 {
		at := wall_to_unix(z, wall)
		if at > hi {
			return true
		}
		if at >= lo && at > prev {
			if t.n >= want {
				return false
			}
			t.v[t.n] = f64(at)
			t.n += 1
			prev = at
		}
		wall = step_wall(wall, t.unit)
	}
	return true
}

// floor_to is the last boundary of s at or before wall.
@(private)
floor_to :: proc(wall: i64, s: Time_Step) -> i64 {
	c := civil_from_wall(wall)
	day := days_from_civil(c.year, c.month, c.day) * 86400
	switch s.unit {
	case .Second:
		return math.floor_div(wall, s.n) * s.n
	case .Minute:
		return math.floor_div(wall, 60 * s.n) * 60 * s.n
	case .Hour:
		return day + i64(c.hour) / s.n * s.n * 3600
	case .Day:
		return day - i64(c.day - 1) % s.n * 86400
	case .Week:
		// Weeks count from Monday 1970-01-05, day 4, so two-week steps
		// land on the same Mondays whatever the domain.
		monday := day / 86400 - i64((c.wday + 6) % 7)
		w := math.floor_div(math.floor_div(monday - 4, 7), s.n) * s.n
		return (4 + w * 7) * 86400
	case .Month:
		m := (c.month - 1) / int(s.n) * int(s.n) + 1
		return days_from_civil(c.year, m, 1) * 86400
	case .Year:
		y := math.floor_div(c.year, s.n) * s.n
		return days_from_civil(y, 1, 1) * 86400
	}
	return wall
}

// step_wall is the next boundary of s after the boundary wall.
@(private)
step_wall :: proc(wall: i64, s: Time_Step) -> i64 {
	switch s.unit {
	case .Second:
		return wall + s.n
	case .Minute:
		return wall + 60 * s.n
	case .Hour:
		return next_hours(wall, s.n)
	case .Day:
		return next_days(wall, s.n)
	case .Week:
		return wall + 7 * 86400 * s.n
	case .Month:
		c := civil_from_wall(wall)
		m := c.month - 1 + int(s.n)
		return days_from_civil(c.year + i64(m / 12), m % 12 + 1, 1) * 86400
	case .Year:
		c := civil_from_wall(wall)
		return days_from_civil(c.year + s.n, 1, 1) * 86400
	}
	return wall + 1
}

// next_hours is n hours after wall, or the next midnight if that comes
// first: each day's hours restart at midnight.
@(private)
next_hours :: proc(wall, n: i64) -> i64 {
	next := wall + 3600 * n
	if civil_from_wall(next).day != civil_from_wall(wall).day {
		return floor_to(next, {.Day, 1})
	}
	return next
}

// next_days is n days after wall, or the next month's 1st if that comes
// first: each month's days restart on the 1st.
@(private)
next_days :: proc(wall, n: i64) -> i64 {
	next := wall + 86400 * n
	c, d := civil_from_wall(wall), civil_from_wall(next)
	if d.month != c.month && d.day != 1 {
		return days_from_civil(d.year, d.month, 1) * 86400
	}
	return next
}

// Time_Label is a time tick's text: what it reads (main), and the line
// under it (sub) that names its day or year where that changes from the tick before (the
// first tick always has one, for any unit finer than a year).
Time_Label :: struct {
	main, sub: Label,
}

// time_label writes tick i of t on z's calendar. Ticks finer than a day
// read 14:00 over the date; days and weeks Mar 5 over the year; months
// Mar over the year; years 2026 alone. A tick's main text and the context
// in force at it, its own or the last one written, name it uniquely.
time_label :: proc(t: ^Time_Ticks, i: int, z: Zone) -> (l: Time_Label) {
	c := civil_from_wall(wall_of(z, i64(t.v[i])))
	layout := TIME_LAYOUTS[t.unit.unit]
	write_civil(&l.main, c, layout.main)
	if layout.ctx == "" {
		return
	}
	if i == 0 || ctx_changed(civil_from_wall(wall_of(z, i64(t.v[i - 1]))), c, layout.ctx) {
		write_civil(&l.sub, c, layout.ctx)
	}
	return
}

// Time_Layout is how a tick of a unit is written: its main line and the
// context line under it, in timefmt's directives.
@(private)
Time_Layout :: struct {
	main, ctx: string,
}

@(private, rodata)
TIME_LAYOUTS := [Time_Unit]Time_Layout {
	.Second = {"%H:%M:%S", "%b %e"},
	.Minute = {"%H:%M", "%b %e"},
	.Hour   = {"%H:%M", "%b %e"},
	.Day    = {"%b %e", "%Y"},
	.Week   = {"%b %e", "%Y"},
	.Month  = {"%b", "%Y"},
	.Year   = {"%Y", ""},
}

// ctx_changed reports whether a context line of layout ctx reads
// differently at c than at the tick before it, p.
@(private)
ctx_changed :: proc(p, c: Civil, ctx: string) -> bool {
	if p.year != c.year {
		return true
	}
	return ctx != "%Y" && (p.month != c.month || p.day != c.day)
}

// time_value writes the instant v on z's calendar for a tooltip: the date,
// and the time of day when steps between points are shorter than a day.
time_value :: proc(v: f64, spacing: f64, z: Zone) -> (l: Label) {
	if !is_finite(v) {
		put_text(&l, "–")
		return
	}
	c := civil_from_wall(wall_of(z, i64(v)))
	write_civil(&l, c, "%a %b %e, %Y" if spacing >= 86400 else "%b %e, %Y %H:%M")
	return
}

// write_civil formats c with timefmt's directives into l, with each run of
// spaces closed up to one (%e pads a day below 10) and none at the ends.
// timefmt writes into an arena over a buffer on the stack, so this
// allocates nothing.
@(private)
write_civil :: proc(l: ^Label, c: Civil, layout: string) {
	p := timefmt.Parts {
		year    = int(c.year),
		month   = c.month,
		day     = c.day,
		hour    = c.hour,
		minute  = c.minute,
		second  = c.second,
		weekday = c.wday,
	}
	buf: [512]u8
	arena: mem.Arena
	mem.arena_init(&arena, buf[:])
	s := timefmt.format_parts(p, layout, mem.arena_allocator(&arena))
	s = strings.trim_space(s)
	space := false
	for i in 0 ..< len(s) {
		if s[i] == ' ' {
			if !space {
				put_text(l, " ")
			}
			space = true
			continue
		}
		space = false
		put_text(l, s[i:i + 1])
	}
}
