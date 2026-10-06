package main

import "core:fmt"
import "core:math"
import "jm:ui"
import "jm:ui/plot"
import plot_primer "jm:ui/plot/primer"

import "../../kitchen"

// Charts is the charts page's data, the shapes the admin's charts draw,
// made once from a fixed seed so every render is the same.
Charts :: struct {
	made:      bool,
	days:      []f64, // 90 days, as Unix seconds at midnight UTC
	hashrate:  [5][]f64, // H/s per facility per day
	lines:     [5]plot.Line_Series,
	months:    [12]string,
	sales:     [3]plot.Bar_Series,
	rigs:      [1]plot.Bar_Series,
	boxes:     [2]plot.Box_Series,
	sales_day: [2]plot.Line_Series, // the admin's sales chart: dollars and rigs, by day
	hours:     []f64,
	dense:     [2]plot.Line_Series,
	hidden:    plot.Series_Set,
}

FACILITIES := [5]string{"Ethiopia", "Norway", "Paraguay", "South Dakota", "Wisconsin"}

// DAY0 is 2026-07-07, 90 days before 2026-10-05.
DAY0 :: 1783382400

page_charts :: proc(gtx: ^ui.Ctx, m: ^Model) {
	c := &m.charts
	if !c.made {
		charts_make(c)
	}
	style := plot_primer.style(gtx)
	ui.column(gtx, gap = 10, align = .Fill)
	kitchen.section(gtx, "Hashrate per facility", HASH_NOTE)
	hash := plot.Line_Chart {
		label = "Hashrate per facility",
		height = 320,
		xs = c.days,
		series = c.lines[:],
		x = {kind = .Time},
		y = {format = HASH},
		hidden = &c.hidden,
	}
	plot.line_chart(gtx, &hash, &style)
	{
		ui.row(gtx, gap = 24, align = .Fill)
		ui.flexible(gtx, 1)
		{
			ui.column(gtx, gap = 10, align = .Fill)
			kitchen.section(
				gtx,
				"Monthly sales",
				"invoices and sales receipts stacked up, refunds down from zero",
			)
			sales := plot.Bar_Chart {
				label = "Monthly sales",
				height = 300,
				categories = c.months[:],
				series = c.sales[:],
				stacked = true,
				value = {format = MONEY},
			}
			plot.bar_chart(gtx, &sales, &style)
		}
		ui.flexible(gtx, 1)
		{
			ui.column(gtx, gap = 10, align = .Fill)
			kitchen.section(
				gtx,
				"Client efficiency",
				"per facility, clients and rigs; hover a dot for the rig it is",
			)
			eff := plot.Box_Chart {
				label = "Client efficiency",
				height = 300,
				categories = FACILITIES[:],
				series = c.boxes[:],
				mean = true,
				value = {format = {unit = "%"}, min = 80, max = 105},
			}
			plot.box_chart(gtx, &eff, &style)
		}
	}
	page_charts_rest(gtx, c, &style)
}

// page_charts_rest is the rest of the page: the admin's two-axis sales chart,
// a stacked area, horizontal bars, a dense series and the plain states.
page_charts_rest :: proc(gtx: ^ui.Ctx, c: ^Charts, style: ^plot.Plot_Style) {
	{
		ui.row(gtx, gap = 24, align = .Fill)
		ui.flexible(gtx, 1)
		{
			ui.column(gtx, gap = 10, align = .Fill)
			kitchen.section(
				gtx,
				"Sales and rigs",
				"the admin's sales chart: two measures on two axes, each axis keyed to its line",
			)
			two := plot.Line_Chart {
				label = "Sales and rigs",
				height = 260,
				xs = c.days[30:],
				series = c.sales_day[:],
				x = {kind = .Time},
				y = {title = "Sales", format = MONEY},
				y2 = {title = "Rigs", zero = true},
			}
			plot.line_chart(gtx, &two, style)
		}
		ui.flexible(gtx, 1)
		{
			ui.column(gtx, gap = 10, align = .Fill)
			kitchen.section(gtx, "Fleet hashrate", "the same five facilities stacked")
			stack := plot.Line_Chart {
				label = "Fleet hashrate",
				height = 260,
				xs = c.days,
				series = c.lines[:],
				x = {kind = .Time},
				y = {format = HASH},
				fill = .Stacked,
			}
			plot.line_chart(gtx, &stack, style)
		}
	}
	kitchen.section(gtx, "Rigs per facility", "horizontal bars, categories down the left")
	rigs := plot.Bar_Chart {
		label      = "Rigs per facility",
		height     = 200,
		categories = FACILITIES[:],
		series     = c.rigs[:],
		horizontal = true,
	}
	plot.bar_chart(gtx, &rigs, style)
	kitchen.section(gtx, "Fourteen months of hours", DENSE_NOTE)
	dense := plot.Line_Chart {
		label = "Fourteen months of hours",
		height = 240,
		xs = c.hours,
		series = c.dense[:],
		x = {kind = .Time},
		y = {format = HASH},
	}
	plot.line_chart(gtx, &dense, style)
	kitchen.section(gtx, "States", "loading with nothing yet, a failed load, and no data")
	ui.row(gtx, gap = 24, align = .Fill)
	states := [3]plot.Status{.Loading, .Error, .Ready}
	messages := [3]string{"", "Couldn’t reach the pool API", ""}
	for st, i in states {
		ui.flexible(gtx, 1)
		empty := plot.Line_Chart {
			label = fmt.tprintf("State %d", i),
			height = 140,
			status = st,
			message = messages[i],
			x = {kind = .Time},
		}
		plot.line_chart(gtx, &empty, style, key = u64(i))
	}
}

DENSE_NOTE ::
	"10,080 hourly points a series, drawn as at most four a pixel column; " +
	"Norway's one bad hour, at a fifth of its rate on Apr 18, survives the thinning"

HASH_NOTE ::
	"90 days, a point a day: Paraguay curtailed for five days, " +
	"Wisconsin's Foreman feed down for three, Ethiopia's new rigs on from day 50; " +
	"click a name to hide its line"

HASH  :: plot.Number_Format {
	unit  = "H/s",
	short = .Metric,
	space = true,
}
MONEY :: plot.Number_Format {
	prefix  = "$",
	short   = .Finance,
	grouped = false,
}

// Rand is a small fixed-seed generator, so the page draws the same data
// on every machine and every run.
Rand :: struct {
	s: u64,
}

next :: proc(r: ^Rand) -> f64 {
	r.s = r.s * 6364136223846793005 + 1442695040888963407
	return f64(r.s >> 11) / f64(u64(1) << 53)
}

// noise is a normal draw, by Box-Muller.
noise :: proc(r: ^Rand) -> f64 {
	u := max(next(r), 1e-12)
	return math.sqrt(-2 * math.ln(u)) * math.cos(2 * math.PI * next(r))
}

// charts_make makes the page's data.
charts_make :: proc(c: ^Charts) {
	c.made = true
	r := Rand{42}
	c.days = make([]f64, 90)
	for i in 0 ..< 90 {
		c.days[i] = f64(DAY0 + i * 86400)
	}
	charts_hashrate(c, &r)
	charts_sales(c, &r)
	charts_boxes(c, &r)
	charts_dense(c, &r)
}

charts_hashrate :: proc(c: ^Charts, r: ^Rand) {
	base := [5]f64{38e15, 182e15, 96e15, 24e15, 61e15}
	for f in 0 ..< 5 {
		ys := make([]f64, 90)
		for i in 0 ..< 90 {
			v := base[f] * (1 + 0.012 * noise(r) + 0.02 * math.sin(f64(i) / 6 + f64(f)))
			ys[i] = v * event_scale(f, i)
		}
		c.hashrate[f] = ys
		c.lines[f] = {
			name = FACILITIES[f],
			ys   = ys,
		}
	}
}

// Event is something that happened to a facility's hashrate on days from
// up to to: a scale on it, or no readings at all.
Event :: struct {
	facility, from, to: int,
	scale:              f64,
	gap:                bool,
}

EVENTS := [?]Event {
	{facility = 2, from = 31, to = 36, scale = 0.42}, // curtailed
	{facility = 4, from = 58, to = 61, gap = true}, // Foreman's feed down
	{facility = 0, from = 50, to = 90, scale = 1.45}, // new rigs online
}

// event_scale is what the day's events do to facility f's hashrate on day
// i: Norway also takes a maintenance window each week.
event_scale :: proc(f, i: int) -> f64 {
	for e in EVENTS {
		if e.facility == f && i >= e.from && i < e.to {
			return math.nan_f64() if e.gap else e.scale
		}
	}
	return 0.94 if f == 1 && i % 7 == 3 else 1
}

charts_sales :: proc(c: ^Charts, r: ^Rand) {
	names := [12]string {
		"Oct",
		"Nov",
		"Dec",
		"Jan",
		"Feb",
		"Mar",
		"Apr",
		"May",
		"Jun",
		"Jul",
		"Aug",
		"Sep",
	}
	c.months = names
	kinds := [3]string{"Invoices", "Sales receipts", "Refunds"}
	for k in 0 ..< 3 {
		vs := make([]f64, 12)
		for i in 0 ..< 12 {
			season := 1 + 0.35 * math.sin(f64(i) / 2)
			switch k {
			case 0:
				vs[i] = (210_000 + 60_000 * noise(r)) * season
			case 1:
				vs[i] = (48_000 + 15_000 * noise(r)) * season
			case 2:
				vs[i] = -(9_000 + 6_000 * abs(noise(r)))
			}
		}
		c.sales[k] = {
			name   = kinds[k],
			values = vs,
		}
	}
	rigs := make([]f64, 5)
	counts := [5]f64{212, 1046, 588, 133, 371}
	copy(rigs, counts[:])
	c.rigs[0] = {
		name   = "Rigs",
		values = rigs,
	}
	sales := make([]f64, 60)
	count := make([]f64, 60)
	for i in 0 ..< 60 {
		count[i] = math.round(max(0, 3 + 2.5 * noise(r)))
		sales[i] = count[i] * (3_400 + 400 * noise(r))
	}
	c.sales_day = {
		{name = "Total sales", ys = sales},
		{name = "Rig count", ys = count, right = true},
	}
}

// charts_boxes makes each facility's client and rig efficiency, in
// percent of sticker hashrate: a client's is its rigs' together, so it
// spreads less, and one rig a facility hashes far under sticker.
charts_boxes :: proc(c: ^Charts, r: ^Rand) {
	sizes := [2][5]int{{18, 64, 41, 12, 29}, {212, 1046, 588, 133, 371}}
	kinds := [2]string{"client", "rig"}
	for s in 0 ..< 2 {
		boxes := make([]plot.Box_Stats, 5)
		names := make([][]string, 5)
		for f in 0 ..< 5 {
			boxes[f] = plot.box_stats(efficiency(r, f, sizes[s][f], rigs = s == 1))
			names[f] = make([]string, len(boxes[f].outliers))
			for &n, j in names[f] {
				n = fmt.aprintf("%s %d", kinds[s], 1000 + f * 100 + j)
			}
		}
		c.boxes[s] = {
			name          = "Clients" if s == 0 else "Rigs",
			boxes         = boxes,
			outlier_names = names,
		}
	}
}

// efficiency is n samples of facility f's efficiency, on the temp
// allocator: its rigs', or its clients'.
efficiency :: proc(r: ^Rand, f, n: int, rigs: bool) -> []f64 {
	spread := [5]f64{2.4, 1.1, 1.8, 2.9, 1.5}
	centre := [5]f64{96.1, 99.2, 97.4, 95.3, 98.6}
	samples := make([]f64, n, context.temp_allocator)
	for &v in samples {
		v = centre[f] + spread[f] * noise(r) * (1 if rigs else 0.7)
	}
	if rigs {
		samples[0] = centre[f] - 14 - 4 * next(r) // a rig hashing far under sticker
	}
	return samples
}

charts_dense :: proc(c: ^Charts, r: ^Rand) {
	n := 10_080
	c.hours = make([]f64, n)
	for i in 0 ..< n {
		c.hours[i] = f64(DAY0 - 330 * 86400 + i * 3600)
	}
	for s in 0 ..< 2 {
		ys := make([]f64, n)
		mean: f64 = 120e15 if s == 0 else 70e15
		level := mean
		for i in 0 ..< n {
			level += 0.6e15 * noise(r) - (level - mean) * 0.01
			ys[i] = level * (1 + 0.04 * math.sin(f64(i) * 2 * math.PI / 24))
			if s == 0 && i == 6000 {
				ys[i] *= 0.2 // one bad hour: decimation keeps it
			}
		}
		c.dense[s] = {
			name = FACILITIES[1 + s],
			ys   = ys,
		}
	}
}
