package main

import "core:strings"
import "core:testing"
import "jm:ui"
import "jm:ui/render"

// The charts page draws the admin's three charts over the data it makes,
// each summarised for a screen reader as what it shows.
@(test)
test_the_charts_page_draws_the_admin_charts :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	m: Model
	app := kitchen_app(&m)
	for name, i in app.pages {
		if name == "Charts" {
			m.page = i
		}
	}
	h: render.Headless
	render.headless_init(&h, app.ui, app.user, {1400, 3000}, app.fonts)
	defer render.headless_destroy(&h)
	ui.probe_frame(&h.p)
	sem := ui.probe_semantics(&h.p, context.temp_allocator)
	want := [?]string {
		`"Line chart, 5 of 5 series shown, Tue Jul 7, 2026 to Sun Oct 4, 2026`,
		`"Bar chart, 12 categories, 3 of 3 series shown`,
		`"Box plot, 5 categories, 2 of 2 series shown`,
		`group "Fourteen months of hours, plot"`,
		`status "Loading\u2026"`,
		`alert "Couldn\u2019t reach the pool API"`,
	}
	for w in want {
		testing.expectf(t, strings.contains(sem, w), "the page lacks %s:\n%s", w, sem)
	}
	// Wisconsin's feed is down for three days and Paraguay's curtailment
	// cuts its hashrate: the data shows what the page says it does.
	testing.expect(t, m.charts.hashrate[4][58] != m.charts.hashrate[4][58], "a gap is NaN")
	testing.expect(t, m.charts.hashrate[2][33] < m.charts.hashrate[2][20] * 0.6, "curtailed")
}
