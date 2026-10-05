package design

// Calendar arithmetic every system's date picker needs: a Gregorian date,
// the facts a month grid is drawn from, and moving a date by days and
// months. A system aliases these and keeps what is its own (the picker,
// its modes, its formats).

// Date is a Gregorian calendar date; the zero Date is none.
Date :: struct {
	year:  int,
	month: int, // 1-12
	day:   int, // 1-31
}

// days_in_month is the length of month (1-12) in year, Gregorian.
days_in_month :: proc(year, month: int) -> int {
	switch month {
	case 2:
		leap := (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
		return leap ? 29 : 28
	case 4, 6, 9, 11:
		return 30
	}
	return 31
}

// weekday is 0 (Sunday) to 6 for a Gregorian date, by Sakamoto's method.
weekday :: proc(d: Date) -> int {
	T := [12]int{0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4}
	y := d.year
	if d.month < 3 {
		y -= 1
	}
	return (y + y / 4 - y / 100 + y / 400 + T[d.month - 1] + d.day) % 7
}

// date_less reports whether a is before b.
date_less :: proc(a, b: Date) -> bool {
	if a.year != b.year {
		return a.year < b.year
	}
	if a.month != b.month {
		return a.month < b.month
	}
	return a.day < b.day
}

// date_days is d counted in days from 1970-01-01, negative before it
// (Howard Hinnant's days_from_civil), so date arithmetic is integer
// arithmetic.
date_days :: proc(d: Date) -> int {
	y := d.month <= 2 ? d.year - 1 : d.year
	era := (y >= 0 ? y : y - 399) / 400
	yoe := y - era * 400
	mp := d.month > 2 ? d.month - 3 : d.month + 9
	doy := (153 * mp + 2) / 5 + d.day - 1
	doe := yoe * 365 + yoe / 4 - yoe / 100 + doy
	return era * 146097 + doe - 719468
}

// date_from_days is the date n days from 1970-01-01: date_days undone.
date_from_days :: proc(n: int) -> Date {
	z := n + 719468
	era := (z >= 0 ? z : z - 146096) / 146097
	doe := z - era * 146097
	yoe := (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
	doy := doe - (365 * yoe + yoe / 4 - yoe / 100)
	mp := (5 * doy + 2) / 153
	day := doy - (153 * mp + 2) / 5 + 1
	month := mp < 10 ? mp + 3 : mp - 9
	return {yoe + era * 400 + (month <= 2 ? 1 : 0), month, day}
}

// date_add_days is d moved n days, either way.
date_add_days :: proc(d: Date, n: int) -> Date {
	return date_from_days(date_days(d) + n)
}

// date_add_months is d moved n months, either way, its day clamped to
// the length of the month it lands in (Jan 31 + 1 month is Feb 28 or 29).
date_add_months :: proc(d: Date, n: int) -> Date {
	m := d.year * 12 + d.month - 1 + n
	month := m %% 12 + 1
	year := (m - (month - 1)) / 12
	return {year, month, min(d.day, days_in_month(year, month))}
}

// date_valid reports whether d names a real day of years 1 to 9999.
date_valid :: proc(d: Date) -> bool {
	return(
		d.year >= 1 &&
		d.year <= 9999 &&
		d.month >= 1 &&
		d.month <= 12 &&
		d.day >= 1 &&
		d.day <= days_in_month(d.year, d.month) \
	)
}

// month_of is the first day of d's month.
month_of :: proc(d: Date) -> Date {
	return {d.year, d.month, 1}
}

// week_first is the first day of d's week when weeks start on
// week_start (0 Sunday to 6 Saturday); week_last its last.
week_first :: proc(d: Date, week_start: int) -> Date {
	return date_add_days(d, -((weekday(d) - week_start) %% 7))
}

week_last :: proc(d: Date, week_start: int) -> Date {
	return date_add_days(week_first(d, week_start), 6)
}
