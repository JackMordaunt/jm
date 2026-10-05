package design

import "core:testing"

// The calendar arithmetic: month lengths, day counts, months and weeks.

@(test)
test_month_lengths_follow_the_gregorian_leap_rule :: proc(t: ^testing.T) {
	testing.expect_value(t, days_in_month(2026, 2), 28)
	testing.expect_value(t, days_in_month(2024, 2), 29)
	testing.expect_value(t, days_in_month(1900, 2), 28) // a century is not a leap year
	testing.expect_value(t, days_in_month(2000, 2), 29) // unless it divides by 400
	testing.expect_value(t, days_in_month(2026, 4), 30)
	testing.expect_value(t, days_in_month(2026, 12), 31)
	testing.expect(t, date_valid({2024, 2, 29}))
	testing.expect(t, !date_valid({2026, 2, 29}))
	testing.expect(t, !date_valid({2026, 13, 1}))
}

@(test)
test_day_counts_walk_the_calendar_one_day_at_a_time :: proc(t: ^testing.T) {
	testing.expect_value(t, date_days({1970, 1, 1}), 0)
	testing.expect_value(t, date_days({1969, 12, 31}), -1)
	testing.expect_value(t, date_days({2000, 3, 1}) - date_days({2000, 2, 28}), 2)
	// Every day from 1899 to 2101 follows the one before, keeps its
	// weekday's turn, and comes back from its count.
	d := Date{1899, 1, 1}
	n := date_days(d)
	wd := weekday(d)
	for d.year < 2101 {
		next := date_add_days(d, 1)
		testing.expect(t, date_valid(next))
		testing.expect(t, date_less(d, next))
		testing.expect_value(t, date_days(next), n + 1)
		testing.expect_value(t, weekday(next), (wd + 1) % 7)
		testing.expect_value(t, date_from_days(n + 1), next)
		d, n, wd = next, n + 1, weekday(next)
	}
	testing.expect_value(t, date_add_days({2026, 12, 31}, 1), Date{2027, 1, 1})
	testing.expect_value(t, date_add_days({2026, 3, 1}, -1), Date{2026, 2, 28})
}

@(test)
test_moving_by_months_clamps_the_day_and_crosses_years :: proc(t: ^testing.T) {
	testing.expect_value(t, date_add_months({2026, 1, 31}, 1), Date{2026, 2, 28})
	testing.expect_value(t, date_add_months({2024, 1, 31}, 1), Date{2024, 2, 29})
	testing.expect_value(t, date_add_months({2026, 1, 15}, -1), Date{2025, 12, 15})
	testing.expect_value(t, date_add_months({2026, 12, 15}, 1), Date{2027, 1, 15})
	testing.expect_value(t, date_add_months({2026, 3, 31}, -13), Date{2025, 2, 28})
	testing.expect_value(t, date_add_months({2026, 5, 10}, 24), Date{2028, 5, 10})
}

@(test)
test_a_week_starts_on_the_day_asked :: proc(t: ^testing.T) {
	// 2026-10-05 is a Monday.
	testing.expect_value(t, weekday(Date{2026, 10, 5}), 1)
	testing.expect_value(t, week_first(Date{2026, 10, 5}, 0), Date{2026, 10, 4}) // Sunday
	testing.expect_value(t, week_last(Date{2026, 10, 5}, 0), Date{2026, 10, 10})
	testing.expect_value(t, week_first(Date{2026, 10, 5}, 1), Date{2026, 10, 5}) // Monday starts its own week
	testing.expect_value(t, week_last(Date{2026, 10, 5}, 1), Date{2026, 10, 11})
	// A Sunday ends a Monday week.
	testing.expect_value(t, week_first({2026, 10, 4}, 1), Date{2026, 9, 28})
	testing.expect_value(t, week_first({2026, 10, 3}, 6), Date{2026, 10, 3}) // Saturday
}
