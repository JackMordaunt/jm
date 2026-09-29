package design

// Calendar arithmetic every system's date picker needs: a Gregorian date
// and the three facts a month grid is drawn from. A system aliases these
// and keeps what is its own (the picker, its modes, its formats).

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
