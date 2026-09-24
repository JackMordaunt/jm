/*
Package timefmt formats and parses times with strftime directives, which is
what a script wants for log names, report headers and parsing tool output.

	timefmt.iso(now)                       2026-09-23T10:41:02Z
	timefmt.stamp(now)                     20260923-104102
	timefmt.format(now, "%Y-%m-%d %H:%M")  2026-09-23 10:41
	timefmt.local(now, "%H:%M %Z")         12:41 CEST
	t := must(timefmt.parse("2026-09-23 10:41", "%Y-%m-%d %H:%M"))
	timefmt.duration(3*time.Hour + 2*time.Second)   3h0m2s

Directives: %Y %y %m %d %e %H %M %S %f (milliseconds) %j %a %A %b %B %p
%I %u %w %s (unix seconds) %z %Z %% . Formatting is UTC unless the local
variants are used; parsing produces UTC and supports %Y %y %m %d %e %H %M %S
%f %s %b %B %p %I and literal text.
*/
package timefmt

import "core:strconv"
import "core:strings"
import "core:time"
import "core:time/datetime"
import "core:time/timezone"

Parts :: struct {
	year:     int,
	month:    int, // 1..12
	day:      int, // 1..31
	hour:     int,
	minute:   int,
	second:   int,
	nanos:    int,
	weekday:  int, // 0 = Sunday
	yday:     int, // 1..366
	offset:   int, // seconds east of UTC
	zone:     string,
}

// iso renders t as RFC 3339 in UTC without fractional seconds.
iso :: proc(t: time.Time, allocator := context.allocator) -> string {
	return format(t, "%Y-%m-%dT%H:%M:%SZ", allocator)
}

// stamp renders t compactly for file names: 20260923-104102.
stamp :: proc(t: time.Time, allocator := context.allocator) -> string {
	return format(t, "%Y%m%d-%H%M%S", allocator)
}

// date renders t as YYYY-MM-DD.
date :: proc(t: time.Time, allocator := context.allocator) -> string {
	return format(t, "%Y-%m-%d", allocator)
}

// format renders t in UTC according to layout.
format :: proc(t: time.Time, layout: string, allocator := context.allocator) -> string {
	return format_parts(utc_parts(t), layout, allocator)
}

// local renders t in the machine's time zone. When the zone database cannot
// be read it falls back to UTC, and %Z prints "UTC".
local :: proc(t: time.Time, layout: string, allocator := context.allocator) -> string {
	return format_parts(local_parts(t), layout, allocator)
}

// duration renders d the way humans read it: 250ms, 4.2s, 3m12s, 1h0m2s,
// 2d3h.
duration :: proc(d: time.Duration, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	d := d
	if d < 0 {
		strings.write_byte(&b, '-')
		d = -d
	}
	switch {
	case d < time.Millisecond:
		strings.write_int(&b, int(d / time.Microsecond))
		strings.write_string(&b, "µs")
	case d < time.Second:
		strings.write_int(&b, int(d / time.Millisecond))
		strings.write_string(&b, "ms")
	case d < time.Minute:
		tenths := int(d / (time.Second / 10))
		strings.write_int(&b, tenths / 10)
		if tenths % 10 != 0 {
			strings.write_byte(&b, '.')
			strings.write_int(&b, tenths % 10)
		}
		strings.write_byte(&b, 's')
	case d < time.Hour:
		strings.write_int(&b, int(d / time.Minute))
		strings.write_byte(&b, 'm')
		strings.write_int(&b, int(d % time.Minute / time.Second))
		strings.write_byte(&b, 's')
	case d < 24 * time.Hour:
		strings.write_int(&b, int(d / time.Hour))
		strings.write_byte(&b, 'h')
		strings.write_int(&b, int(d % time.Hour / time.Minute))
		strings.write_byte(&b, 'm')
		strings.write_int(&b, int(d % time.Minute / time.Second))
		strings.write_byte(&b, 's')
	case:
		strings.write_int(&b, int(d / (24 * time.Hour)))
		strings.write_byte(&b, 'd')
		strings.write_int(&b, int(d % (24 * time.Hour) / time.Hour))
		strings.write_byte(&b, 'h')
	}
	return strings.to_string(b)
}

// parse reads s according to layout and returns a UTC time. Fields the
// layout does not mention default to 1970-01-01 00:00:00.
parse :: proc(s, layout: string) -> (t: time.Time, ok: bool) {
	p := Parts{year = 1970, month = 1, day = 1}
	pm := -1 // -1 unset, 0 am, 1 pm
	unix_set := false
	unix: i64
	rest := s
	li := 0
	for li < len(layout) {
		c := layout[li]
		if c != '%' {
			if len(rest) == 0 || rest[0] != c {
				return {}, false
			}
			rest = rest[1:]
			li += 1
			continue
		}
		li += 1
		if li >= len(layout) {
			return {}, false
		}
		d := layout[li]
		li += 1
		switch d {
		case 'Y':
			p.year = take_int(&rest, 4, 4) or_return
		case 'y':
			yy := take_int(&rest, 2, 2) or_return
			p.year = 2000 + yy if yy < 69 else 1900 + yy
		case 'm':
			p.month = take_int(&rest, 1, 2) or_return
		case 'd', 'e':
			rest = strings.trim_left_space(rest)
			p.day = take_int(&rest, 1, 2) or_return
		case 'H':
			p.hour = take_int(&rest, 1, 2) or_return
		case 'I':
			p.hour = take_int(&rest, 1, 2) or_return
		case 'M':
			p.minute = take_int(&rest, 1, 2) or_return
		case 'S':
			p.second = take_int(&rest, 1, 2) or_return
		case 'f':
			ms := take_int(&rest, 1, 3) or_return
			p.nanos = ms * 1_000_000
		case 's':
			v := take_int(&rest, 1, 19) or_return
			unix = i64(v)
			unix_set = true
		case 'b', 'B':
			p.month = take_name(&rest, MONTHS[:]) or_return
		case 'a', 'A':
			_ = take_name(&rest, DAYS[:]) or_return
		case 'p':
			if len(rest) < 2 {
				return {}, false
			}
			switch strings.to_lower(rest[:2], context.temp_allocator) {
			case "am":
				pm = 0
			case "pm":
				pm = 1
			case:
				return {}, false
			}
			rest = rest[2:]
		case '%':
			if len(rest) == 0 || rest[0] != '%' {
				return {}, false
			}
			rest = rest[1:]
		case:
			return {}, false
		}
	}
	if len(rest) != 0 {
		return {}, false
	}
	if unix_set {
		return time.unix(unix, i64(p.nanos)), true
	}
	if pm == 1 && p.hour < 12 {
		p.hour += 12
	} else if pm == 0 && p.hour == 12 {
		p.hour = 0
	}
	dt, err := datetime.components_to_datetime(p.year, p.month, p.day, p.hour, p.minute, p.second, p.nanos)
	if err != nil {
		return {}, false
	}
	return time.datetime_to_time(dt)
}

// utc_parts breaks t into calendar fields in UTC.
utc_parts :: proc(t: time.Time) -> Parts {
	p := parts_from_datetime(t, 0)
	p.zone = "UTC"
	return p
}

// local_parts breaks t into calendar fields in the machine's zone.
local_parts :: proc(t: time.Time) -> Parts {
	region, ok := timezone.region_load("local", context.temp_allocator)
	if !ok || region == nil {
		return utc_parts(t)
	}
	utc_dt, dt_ok := time.time_to_datetime(t)
	if !dt_ok {
		return utc_parts(t)
	}
	local_dt, tz_ok := timezone.datetime_to_tz(utc_dt, region)
	if !tz_ok {
		return utc_parts(t)
	}
	zone, _ := timezone.shortname(local_dt)
	naive := local_dt
	naive.tz = nil
	shifted, time_ok := time.datetime_to_time(naive)
	if !time_ok {
		return utc_parts(t)
	}
	offset := int(time.time_to_unix(shifted) - time.time_to_unix(t))
	p := parts_from_datetime(t, offset)
	p.zone = zone
	return p
}

// ---- internals ----------------------------------------------------------

@(rodata)
MONTHS := [12]string{"January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"}
@(rodata)
DAYS := [7]string{"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"}

parts_from_datetime :: proc(t: time.Time, offset: int) -> Parts {
	shifted := time.time_add(t, time.Duration(offset) * time.Second)
	dt, _ := time.time_to_datetime(shifted)
	p := Parts {
		year   = int(dt.year),
		month  = int(dt.month),
		day    = int(dt.day),
		hour   = int(dt.hour),
		minute = int(dt.minute),
		second = int(dt.second),
		nanos  = int(dt.nano),
		offset = offset,
	}
	p.weekday = int(time.weekday(shifted))
	if ord, err := datetime.date_to_ordinal(dt.date); err == nil {
		if ny, nerr := datetime.new_year(dt.year); nerr == nil {
			if nyo, oerr := datetime.date_to_ordinal(ny); oerr == nil {
				p.yday = int(ord - nyo) + 1
			}
		}
	}
	return p
}

format_parts :: proc(p: Parts, layout: string, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	i := 0
	for i < len(layout) {
		c := layout[i]
		if c != '%' || i + 1 >= len(layout) {
			strings.write_byte(&b, c)
			i += 1
			continue
		}
		d := layout[i + 1]
		i += 2
		switch d {
		case 'Y':
			pad(&b, p.year, 4)
		case 'y':
			pad(&b, p.year % 100, 2)
		case 'm':
			pad(&b, p.month, 2)
		case 'd':
			pad(&b, p.day, 2)
		case 'e':
			if p.day < 10 {
				strings.write_byte(&b, ' ')
			}
			strings.write_int(&b, p.day)
		case 'H':
			pad(&b, p.hour, 2)
		case 'I':
			h := p.hour % 12
			pad(&b, 12 if h == 0 else h, 2)
		case 'M':
			pad(&b, p.minute, 2)
		case 'S':
			pad(&b, p.second, 2)
		case 'f':
			pad(&b, p.nanos / 1_000_000, 3)
		case 'j':
			pad(&b, p.yday, 3)
		case 'a':
			strings.write_string(&b, DAYS[p.weekday][:3])
		case 'A':
			strings.write_string(&b, DAYS[p.weekday])
		case 'b':
			strings.write_string(&b, MONTHS[p.month - 1][:3])
		case 'B':
			strings.write_string(&b, MONTHS[p.month - 1])
		case 'p':
			strings.write_string(&b, "AM" if p.hour < 12 else "PM")
		case 'u':
			strings.write_int(&b, 7 if p.weekday == 0 else p.weekday)
		case 'w':
			strings.write_int(&b, p.weekday)
		case 's':
			unix := datetime_unix(p)
			strings.write_i64(&b, unix)
		case 'z':
			off := p.offset
			strings.write_byte(&b, '-' if off < 0 else '+')
			off = abs(off)
			pad(&b, off / 3600, 2)
			pad(&b, off % 3600 / 60, 2)
		case 'Z':
			strings.write_string(&b, p.zone)
		case '%':
			strings.write_byte(&b, '%')
		case:
			strings.write_byte(&b, '%')
			strings.write_byte(&b, d)
		}
	}
	return strings.to_string(b)
}

datetime_unix :: proc(p: Parts) -> i64 {
	dt, err := datetime.components_to_datetime(p.year, p.month, p.day, p.hour, p.minute, p.second, p.nanos)
	if err != nil {
		return 0
	}
	t, ok := time.datetime_to_time(dt)
	if !ok {
		return 0
	}
	return time.time_to_unix(t) - i64(p.offset)
}

pad :: proc(b: ^strings.Builder, v, width: int) {
	buf: [24]byte
	s := strconv.write_int(buf[:], i64(v), 10)
	for _ in len(s) ..< width {
		strings.write_byte(b, '0')
	}
	strings.write_string(b, s)
}

take_int :: proc(rest: ^string, min_digits, max_digits: int) -> (v: int, ok: bool) {
	n := 0
	for n < len(rest) && n < max_digits && rest[n] >= '0' && rest[n] <= '9' {
		n += 1
	}
	if n < min_digits {
		return 0, false
	}
	v, ok = strconv.parse_int(rest[:n], 10)
	rest^ = rest[n:]
	return
}

// take_name matches a full or three-letter name from names, case-insensitive,
// and returns its 1-based index.
take_name :: proc(rest: ^string, names: []string) -> (index: int, ok: bool) {
	for name, i in names {
		if len(rest) >= len(name) && strings.equal_fold(rest[:len(name)], name) {
			rest^ = rest[len(name):]
			return i + 1, true
		}
	}
	for name, i in names {
		if len(rest) >= 3 && strings.equal_fold(rest[:3], name[:3]) {
			rest^ = rest[3:]
			return i + 1, true
		}
	}
	return 0, false
}
