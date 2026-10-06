package datagrid

// Columns: what a column is, the user's arrangement of them, and the
// widths they come to. Everything here is pure: no frame, no shaper, so
// the width solver and the placement are tested and fuzzed on their own.

// MIN_WIDTH is the narrowest a column may be dragged or squeezed, unless
// its own min_width says otherwise.
MIN_WIDTH :: f32(40)

// DEFAULT_WIDTH is what a column without a measured width starts at.
DEFAULT_WIDTH :: f32(120)

// Sizing is how a column takes its width. Auto is its widest cell,
// sampled from the rows; Fixed is Column.width; Grow is its widest cell
// and a share, in proportion to grow, of the width the columns leave
// over. A width the user drags replaces any of them.
Sizing :: enum u8 {
	Auto,
	Fixed,
	Grow,
}

// Align places a column's text and header within it.
Align :: enum u8 {
	Start,
	End,
	Center,
}

// Pin keeps a column in view while the others scroll sideways: at the
// left edge or the right.
Pin :: enum u8 {
	None,
	Left,
	Right,
}

// Value_Kind is what a column's values are: text sorts naturally, digit
// runs by value and letters without case; a number or a date sorts by
// value, and its filter is a range. A date's value is Unix seconds.
Value_Kind :: enum u8 {
	Text,
	Number,
	Date,
}

// Filter_Kind is the filter a column offers. Set keeps the rows whose
// value is one of a chosen few (the admin's included-set filter); Text
// keeps those that contain some text; Range those whose value lies
// between two bounds, either open.
Filter_Kind :: enum u8 {
	None,
	Set,
	Text,
	Range,
}

// Column is one column as the caller declares it, for the life of the
// grid. id names it in views and in the queries a paged source answers,
// so it must stay the same across builds; title is what the header says.
// extra is room a measured width adds for what the text alone does not
// show: a badge's padding, an icon.
Column :: struct {
	id:         string,
	title:      string,
	kind:       Value_Kind,
	sizing:     Sizing,
	width:      f32, // Fixed's width
	grow:       f32, // Grow's share; 0 reads as 1
	min_width:  f32, // 0 reads as MIN_WIDTH
	max_width:  f32, // 0 is no bound
	extra:      f32,
	align:      Align,
	pin:        Pin, // where it starts pinned
	hidden:     bool, // whether it starts hidden
	filter:     Filter_Kind,
	no_sort:    bool,
	no_hide:    bool, // the column menu may not hide it
	no_export:  bool, // left out of CSV and copies: a row number, a checkbox
	row_header: bool, // names its row, for assistive technology and a bold look
	row_number: bool, // shows the row's place in the current order, from 1
}

// Column_State is what the user has done to a column: a width dragged
// (0 for none), hidden or not, pinned where; and what the grid measured
// of it, which is not part of a view.
Column_State :: struct {
	width:  f32,
	hidden: bool,
	pin:    Pin,
	auto:   f32, // the widest sampled cell, header included; 0 unmeasured
}

// Fit is what the widths do when they come to more than the grid's
// width: Scroll keeps them and scrolls sideways; Shrink squeezes the
// Auto and Grow columns no one has sized, in proportion, down to their
// minimums (the admin dashboard's distribute, in data-table-utils.ts),
// and scrolls only past that.
Fit :: enum u8 {
	Scroll,
	Shrink,
}

// Track is one visible column as the width solver sees it: the width it
// starts from, its bounds, its share of what is left over, and whether
// that width may move at all.
Track :: struct {
	base, min, max: f32,
	grow:           f32,
	rigid:          bool, // a user or Fixed width: neither grows nor shrinks
}

// column_min is c's least width.
column_min :: proc(c: Column) -> f32 {
	return c.min_width > 0 ? c.min_width : MIN_WIDTH
}

// clamp_width bounds w by c's minimum and maximum.
clamp_width :: proc(c: Column, w: f32) -> f32 {
	lo := column_min(c)
	out := max(w, lo)
	if c.max_width > 0 {
		out = min(out, max(c.max_width, lo))
	}
	return out
}

// track_of is c's track given what the user and the measurer left in s.
track_of :: proc(c: Column, s: Column_State) -> Track {
	t := Track {
		min = column_min(c),
		max = c.max_width,
	}
	switch {
	case s.width > 0:
		t.base, t.rigid = clamp_width(c, s.width), true
	case c.sizing == .Fixed:
		t.base, t.rigid = clamp_width(c, c.width > 0 ? c.width : DEFAULT_WIDTH), true
	case:
		measured := s.auto > 0 ? s.auto + c.extra : DEFAULT_WIDTH
		t.base = clamp_width(c, measured)
		if c.sizing == .Grow {
			t.grow = c.grow > 0 ? c.grow : 1
		}
	}
	return t
}

// solve_widths writes each track's width into out, for avail pixels of
// columns. Under avail, the growing tracks share what is left in
// proportion to grow, each capped at its max, a capped one keeping no
// more than its cap so the rest share again (CSS Grid's "expand flexible
// tracks"). Over avail with fit Shrink, the tracks that are not rigid
// give up width in proportion to their base, none below its min, until
// they fit or cannot shrink further. An avail that is not finite or not
// positive leaves every track at its base.
solve_widths :: proc(tracks: []Track, avail: f32, fit: Fit, out: []f32) {
	assert(len(out) >= len(tracks))
	total: f32
	for t, i in tracks {
		out[i] = t.base
		total += t.base
	}
	if !(avail > 0) || avail >= INF {
		return
	}
	if total < avail {
		grow_tracks(tracks, avail - total, out)
	} else if total > avail && fit == .Shrink {
		shrink_tracks(tracks, total - avail, out)
	}
}

// INF is an unbounded width.
INF :: f32(1e30)

// grow_tracks shares room among the growing tracks, freezing any that
// reach their max and sharing again what it could not take.
@(private)
grow_tracks :: proc(tracks: []Track, room: f32, out: []f32) {
	room := room
	for _ in 0 ..< len(tracks) + 1 {
		weight: f32
		for t, i in tracks {
			weight += t.grow if can_grow(t, out[i]) else 0
		}
		if weight <= 0 || room <= 0.001 {
			return
		}
		share := room / weight
		room = 0
		for t, i in tracks {
			if can_grow(t, out[i]) {
				room += grow_track(t, &out[i], share * t.grow)
			}
		}
	}
}

// can_grow reports whether t, now w wide, takes a share of the room.
@(private)
can_grow :: proc(t: Track, w: f32) -> bool {
	return t.grow > 0 && !t.rigid && !at_max(t, w)
}

// grow_track widens w by add, no further than t's max, and returns what
// it could not take.
@(private)
grow_track :: proc(t: Track, w: ^f32, add: f32) -> (left: f32) {
	want := w^ + add
	if t.max > 0 && want > t.max {
		capped := max(t.max, w^)
		left, want = want - capped, capped
	}
	w^ = want
	return
}

@(private)
at_max :: proc(t: Track, w: f32) -> bool {
	return t.max > 0 && w >= t.max
}

// shrink_tracks takes excess off the tracks that may shrink, each in
// proportion to its width, none below its min, sharing again what a
// track at its min could not give.
@(private)
shrink_tracks :: proc(tracks: []Track, excess: f32, out: []f32) {
	excess := excess
	for _ in 0 ..< len(tracks) + 1 {
		give: f32
		for t, i in tracks {
			give += out[i] if can_shrink(t, out[i]) else 0
		}
		if give <= 0 || excess <= 0.001 {
			return
		}
		ratio := excess / give
		excess = 0
		for t, i in tracks {
			if !can_shrink(t, out[i]) {
				continue
			}
			want := out[i] - out[i] * ratio
			excess += max(t.min - want, 0)
			out[i] = max(want, t.min)
		}
	}
}

// can_shrink reports whether t, now w wide, gives up width.
@(private)
can_shrink :: proc(t: Track, w: f32) -> bool {
	return !t.rigid && w > t.min
}

// Place is one visible column where it sits: its column index, its pin
// group, and its x and width within that group.
Place :: struct {
	col:  int,
	pin:  Pin,
	x, w: f32,
}

// Placement is the visible columns laid out: every one in navigation
// order (pinned left, then the scrolling middle, then pinned right),
// where each group starts and ends in that slice, and each group's
// width. A middle column's x is from the middle's start; the middle is
// drawn from left_w, moved by the sideways scroll.
Placement :: struct {
	places:        [dynamic]Place,
	mid_first:     int, // places[mid_first:right_first] scroll
	right_first:   int,
	left_w, mid_w: f32,
	right_w:       f32,
	tracks:        [dynamic]Track, // scratch, reused
	widths:        [dynamic]f32,
}

placement_destroy :: proc(p: ^Placement) {
	delete(p.places)
	delete(p.tracks)
	delete(p.widths)
	p^ = {}
}

// place_columns lays out the visible columns of cols in order, their
// state in states, for a grid avail pixels wide, reusing p's arrays. The
// middle shares what the pinned groups leave.
place_columns :: proc(
	p: ^Placement,
	cols: []Column,
	states: []Column_State,
	order: []int,
	avail: f32,
	fit: Fit,
) {
	clear(&p.places)
	clear(&p.tracks)
	gather_pin(p, cols, states, order, .Left)
	p.mid_first = len(p.places)
	gather_pin(p, cols, states, order, .None)
	p.right_first = len(p.places)
	gather_pin(p, cols, states, order, .Right)
	resize(&p.widths, len(p.tracks))
	pinned: f32
	for t, i in p.tracks {
		p.widths[i] = t.base
		if p.places[i].pin != .None {
			pinned += t.base
		}
	}
	mid := p.tracks[p.mid_first:p.right_first]
	solve_widths(mid, avail - pinned, fit, p.widths[p.mid_first:p.right_first])
	p.left_w, p.mid_w, p.right_w = 0, 0, 0
	for &pl, i in p.places {
		pl.w = p.widths[i]
		run := &p.mid_w
		if pl.pin == .Left {
			run = &p.left_w
		} else if pl.pin == .Right {
			run = &p.right_w
		}
		pl.x = run^
		run^ += pl.w
	}
}

// gather_pin appends the visible columns pinned at pin, in order, with
// their tracks.
@(private)
gather_pin :: proc(p: ^Placement, cols: []Column, states: []Column_State, order: []int, pin: Pin) {
	for c in order {
		s := states[c]
		if s.hidden || s.pin != pin {
			continue
		}
		append(&p.places, Place{col = c, pin = pin})
		append(&p.tracks, track_of(cols[c], s))
	}
}

// mid_visible is the range of middle places, [lo, hi) in p.places, that
// show through a middle view view wide scrolled x pixels: the columns
// virtualised sideways.
mid_visible :: proc(p: ^Placement, x, view: f32) -> (lo, hi: int) {
	lo, hi = p.mid_first, p.mid_first
	for i in p.mid_first ..< p.right_first {
		pl := p.places[i]
		if pl.x + pl.w <= x {
			lo = i + 1
			continue
		}
		if pl.x >= x + view {
			break
		}
		hi = i + 1
	}
	if hi < lo {
		hi = lo
	}
	return
}

// place_of is where column col sits in p, -1 when it is not visible.
place_of :: proc(p: ^Placement, col: int) -> int {
	for pl, i in p.places {
		if pl.col == col {
			return i
		}
	}
	return -1
}

// move_column moves column col in order to stand before the column at
// display position to (len(order) moves it last), keeping every other
// column's order. A column that is not in order stays put.
move_column :: proc(order: []int, col, to: int) {
	from := -1
	for c, i in order {
		if c == col {
			from = i
		}
	}
	if from < 0 {
		return
	}
	at := clamp(to, 0, len(order))
	if at > from {
		at -= 1
	}
	if at == from {
		return
	}
	if at < from {
		copy(order[at + 1:from + 1], order[at:from])
	} else {
		copy(order[from:at], order[from + 1:at + 1])
	}
	order[at] = col
}
