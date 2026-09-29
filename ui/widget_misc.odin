package ui

// divider is a line of the theme's stroke width (at least 1px) across the
// innermost flex's cross axis: horizontal in a column or outside a flex,
// vertical in a row. It spans the cross max when bounded, else the cross
// min. color defaults to the theme outline.
divider :: proc(gtx: ^Ctx, color := Color{}, key: u64 = 0, loc := #caller_location) -> Dims {
	axis, _ := parent_axis(gtx)
	p := widget_open(gtx, key, loc)
	c := or_color(color, gtx.theme.outline)
	t := max(gtx.theme.stroke, 1)
	cs := gtx.constraints
	size: Size
	if axis == .Vertical {
		size = {is_finite(cs.max.x) ? cs.max.x : cs.min.x, t}
	} else {
		size = {t, is_finite(cs.max.y) ? cs.max.y : cs.min.y}
	}
	size = constrain(cs, size)
	if painted(c) {
		fill(gtx.ops, Rect{0, 0, size.x, size.y}, c)
	}
	return widget_close(gtx, &p, {size = size})
}
