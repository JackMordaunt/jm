package main

import "core:fmt"
import "jm:ui"
import m3 "jm:ui/material"

// init_progress_values gives the progress group's live controls their
// starting values once: Model's zero values would start them all empty.
init_progress_values :: proc(m: ^Model) {
	if m.progress_ready {
		return
	}
	m.progress_ready = true
	m.centered, m.upright, m.brightness, m.progress = 40, 0.3, 0.6, 0.45
}

// slider_row is state_row with room above it for the Pressed cell's value
// label: the 44dp pill sits value-indicator-active-bottom-space (12dp)
// over the handle, which starts 2dp into its 48dp row, so it rises 54dp
// over the row; this gap and the column's 10dp cover that.
slider_row :: proc(gtx: ^ui.Ctx, m: ^Model, label: string, cell: State_Cell, key: u64) {
	gap(gtx, 44)
	state_row(gtx, m, label, cell, key)
}

page_sliders :: proc(gtx: ^ui.Ctx, m: ^Model) {
	init_progress_values(m)
	col := ui.column(gtx, gap = 10)
	defer ui.end(&col)
	section(gtx, "Continuous", "16dp track, 4dp handle that halves while pressed or focused; the gaps widen with it; value label while pressed")
	state_header(gtx)
	cell :: proc(gtx: ^ui.Ctx, m: ^Model, st: m3.Interaction, key: u64) {
		v: f32 = 0.6
		m3.slider(gtx, &v, width = 160, state = st, key = key)
	}
	slider_row(gtx, m, "Standard", cell, 1)
	cell_c :: proc(gtx: ^ui.Ctx, m: ^Model, st: m3.Interaction, key: u64) {
		v: f32 = 40
		m3.slider(gtx, &v, -100, 100, width = 160, track = .Centered, state = st, key = key)
	}
	slider_row(gtx, m, "Centered", cell_c, 2)
	cell_i :: proc(gtx: ^ui.Ctx, m: ^Model, st: m3.Interaction, key: u64) {
		v: f32 = 0.5
		m3.slider(gtx, &v, width = 160, start_icon = .Remove, end_icon = .Add, state = st, key = key)
	}
	slider_row(gtx, m, "Inset icons", cell_i, 3)

	section(gtx, "Stops", "step 10: a stop dot at each step, in the other segment's colour, none in a gap")
	state_header(gtx)
	cell2 :: proc(gtx: ^ui.Ctx, m: ^Model, st: m3.Interaction, key: u64) {
		v: f32 = 40
		m3.slider(gtx, &v, 0, 100, 10, width = 160, state = st, key = key)
	}
	slider_row(gtx, m, "Standard", cell2, 4)
	cell2c :: proc(gtx: ^ui.Ctx, m: ^Model, st: m3.Interaction, key: u64) {
		v: f32 = -40
		m3.slider(gtx, &v, -100, 100, 20, width = 160, track = .Centered, state = st, key = key)
	}
	slider_row(gtx, m, "Centered", cell2c, 5)

	section(gtx, "Range", "two handles, each with its own gaps; Tab moves the keys to the other handle")
	state_header(gtx)
	cell3 :: proc(gtx: ^ui.Ctx, m: ^Model, st: m3.Interaction, key: u64) {
		a, b: f32 = 20, 70
		m3.range_slider(gtx, &a, &b, 0, 100, width = 160, state = st, key = key)
	}
	slider_row(gtx, m, "Continuous", cell3, 6)
	cell3s :: proc(gtx: ^ui.Ctx, m: ^Model, st: m3.Interaction, key: u64) {
		a, b: f32 = 20, 70
		m3.range_slider(gtx, &a, &b, 0, 100, 10, width = 160, state = st, key = key)
	}
	slider_row(gtx, m, "Stops", cell3s, 7)

	section(gtx, "Vertical", "lo at the top, or at the bottom with top_to_bottom = false; the label sits to the start side")
	state_header(gtx)
	cell_v :: proc(gtx: ^ui.Ctx, m: ^Model, st: m3.Interaction, key: u64) {
		v: f32 = 0.35
		m3.slider(gtx, &v, width = 120, vertical = true, top_to_bottom = false, state = st, key = key)
	}
	slider_row(gtx, m, "Bottom to top", cell_v, 8)

	section(gtx, "Live", "drag, or click to focus and use the arrow keys, Page Up/Down, Home and End")
	s := m3.scheme()
	ui.label(gtx, fmt.tprintf("Volume %.0f%%", m.volume * 100), {color = s[.On_Surface_Variant]})
	m3.slider(gtx, &m.volume, width = 320, key = 10)
	ui.label(gtx, fmt.tprintf("Steps %.0f", m.steps), {color = s[.On_Surface_Variant]})
	m3.slider(gtx, &m.steps, 0, 100, 10, width = 320, key = 11)
	ui.label(gtx, fmt.tprintf("Range %.0f to %.0f", m.range_lo, m.range_hi), {color = s[.On_Surface_Variant]})
	m3.range_slider(gtx, &m.range_lo, &m.range_hi, 0, 100, width = 320, key = 12)
	ui.label(gtx, fmt.tprintf("Balance %.0f", m.centered), {color = s[.On_Surface_Variant]})
	m3.slider(gtx, &m.centered, -100, 100, width = 320, track = .Centered, key = 13)
	ui.label(gtx, fmt.tprintf("Brightness %.0f%%, label always shown", m.brightness * 100), {color = s[.On_Surface_Variant]})
	gap(gtx, 56)
	m3.slider(gtx, &m.brightness, width = 320, start_icon = .Remove, end_icon = .Add, indicator = .Always, key = 14)
	ui.label(gtx, fmt.tprintf("Vertical %.2f", m.upright), {color = s[.On_Surface_Variant]})
	m3.slider(gtx, &m.upright, width = 160, vertical = true, key = 15)
}

// FROZEN are the times, in seconds, the indeterminate indicators are
// frozen at to show their loop, then -1 for one running live.
FROZEN :: [?]f32{0.3, 0.7, 1.1, 1.5, -1}

page_progress :: proc(gtx: ^ui.Ctx, m: ^Model) {
	init_progress_values(m)
	col := ui.column(gtx, gap = 12)
	defer ui.end(&col)
	for style in m3.Progress_Style {
		wavy := style == .Wavy
		section(gtx, wavy ? "Linear, wavy" : "Linear", wavy ? "10dp tall; the wave flattens below 10% and above 95%, and travels a wavelength a second" : "4dp: the indicator and track split by a 4dp gap plus the round caps, a stop dot at the end")
		for v, i in ([?]f32{0, 0.05, 0.25, 0.6, 1}) {
			m3.linear_progress(gtx, v, 320, style = style, at = 0.25, key = u64(100 * int(style) + i))
		}
		section(gtx, wavy ? "Linear, wavy, indeterminate" : "Linear, indeterminate", "two lines on a 1750ms loop, at 0.3s, 0.7s, 1.1s and 1.5s, then live")
		for at, i in FROZEN {
			m3.linear_progress(gtx, -1, 320, style = style, at = at, key = u64(100 * int(style) + 10 + i))
		}
	}
	section(gtx, "Square caps", "butt caps render the raw gap, and the stop is a square")
	m3.linear_progress(gtx, 0.6, 320, square = true, key = 200)
	m3.linear_progress(gtx, -1, 320, square = true, at = 0.7, key = 201)

	for style in m3.Progress_Style {
		wavy := style == .Wavy
		section(gtx, wavy ? "Circular, wavy" : "Circular", wavy ? "48dp: 0, 5, 25, 60 and 100%, then the 6000ms indeterminate loop at 0.3s, 1.8s, 3.3s and live" : "40dp, 4dp stroke: 0, 5, 25, 60 and 100%, then indeterminate (no track) at 0.3s, 1.8s, 3.3s and live")
		r := ui.wrap(gtx, gap = 24, align = .Center)
		for v, i in ([?]f32{0, 0.05, 0.25, 0.6, 1}) {
			m3.circular_progress(gtx, v, style = style, at = 0.25, key = u64(300 + 100 * int(style) + i))
		}
		for at, i in ([?]f32{0.3, 1.8, 3.3, -1}) {
			m3.circular_progress(gtx, -1, style = style, at = at, key = u64(300 + 100 * int(style) + 10 + i))
		}
		ui.end(&r)
	}

	section(gtx, "Live", "the slider drives the determinate indicators below it")
	s := m3.scheme()
	ui.label(gtx, fmt.tprintf("Progress %.0f%%", m.progress * 100), {color = s[.On_Surface_Variant]})
	m3.slider(gtx, &m.progress, width = 320, key = 500)
	m3.linear_progress(gtx, m.progress, 320, key = 501)
	m3.linear_progress(gtx, m.progress, 320, style = .Wavy, key = 502)
	r := ui.wrap(gtx, gap = 24, align = .Center)
	defer ui.end(&r)
	m3.circular_progress(gtx, m.progress, key = 503)
	m3.circular_progress(gtx, m.progress, style = .Wavy, key = 504)
}

page_loading :: proc(gtx: ^ui.Ctx, m: ^Model) {
	init_progress_values(m)
	col := ui.column(gtx, gap = 16)
	defer ui.end(&col)
	for contained in ([?]bool{false, true}) {
		section(gtx, contained ? "Indeterminate, contained" : "Indeterminate", "each of the 7 morphs, frozen 0.5s into it (soft-burst to cookie-9 first), then live")
		r := ui.wrap(gtx, gap = 24, align = .Center)
		for k in 0 ..< 7 {
			m3.loading_indicator(gtx, contained, at = f32(k) * 0.65 + 0.5, key = u64(10 * int(contained) + k))
		}
		m3.loading_indicator(gtx, contained, key = u64(10 * int(contained) + 9))
		ui.end(&r)
	}
	for contained in ([?]bool{false, true}) {
		section(gtx, contained ? "Determinate, contained" : "Determinate", "circle to soft-burst as progress runs 0, 25, 50, 75 and 100%, turning back 180°")
		r := ui.wrap(gtx, gap = 24, align = .Center)
		for v, i in ([?]f32{0, 0.25, 0.5, 0.75, 1}) {
			m3.loading_indicator(gtx, contained, progress = v, key = u64(20 + 10 * int(contained) + i))
		}
		ui.end(&r)
	}
	section(gtx, "Live", "the slider drives the determinate pair")
	s := m3.scheme()
	ui.label(gtx, fmt.tprintf("Progress %.0f%%", m.progress * 100), {color = s[.On_Surface_Variant]})
	m3.slider(gtx, &m.progress, width = 320, key = 40)
	r := ui.wrap(gtx, gap = 24, align = .Center)
	defer ui.end(&r)
	m3.loading_indicator(gtx, progress = m.progress, key = 41)
	m3.loading_indicator(gtx, true, progress = m.progress, key = 42)
}
