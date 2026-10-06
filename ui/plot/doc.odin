/*
Package plot draws charts with jm:ui: line and area charts, bar charts and
box plots, each an immediate-mode proc over data the caller owns.

	style := plot_primer.style(gtx) // or any system's, or plot.default_style()
	plot.line_chart(gtx, &chart, &style)

It belongs to no design system. Everything a chart takes from one, its
colours, fonts and the sizes of its marks, is a Plot_Style, which
ui/plot/primer and ui/plot/fluent build from their systems' themes and
default_style builds from nothing. A palette's colours are checked by
computation (check_palette): contrast against the plot and separation
under simulated colour-vision deficiency.

Every chart has the same parts:

  - A legend of its series, each entry a toggle; a single series has none.
  - Axes: linear, log or time values, with ticks at nice steps
    (linear_ticks, log_ticks, time_ticks on a Zone's calendar), labels in
    a Number_Format ("1.2 PH/s", "$1.2k"), and categories in bands whose
    labels turn or thin when crowded.
  - A readout: a crosshair over the nearest x for a line chart, or the
    category under the pointer for bars and boxes, with a tooltip listing
    every series there.
  - Keyboard and screen readers: the plot takes focus, the arrow keys walk
    its points and series, and the point the keyboard is on is the plot's
    active descendant, named in words.
  - Plain states: an error, loading with nothing yet, and no data say so
    in place of a plot; loading with data keeps the old chart, faded.

The data stays the caller's: a chart reads slices and copies nothing. Per
frame a chart allocates only from the frame allocator, and of that only
in proportion to its width, not its data: a line is min/max-decimated to
the pixel columns it crosses (Reducer), so a series of 10,000 points
draws about as many as one of 1,000.

The pure parts (scales, ticks, labels, time, decimation, box statistics,
stacking) are tested on their own and fuzzed by ui/plot/fuzz.
*/
package plot
