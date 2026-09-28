package ui

import "core:fmt"
import "core:path/filepath"
import "core:strings"

// Inspection is what lies under a point of a frame recorded with
// Debug_Flag.Inspect: the innermost widget box, and the top-most input area,
// which is all a painted row (a list or drawer item drawn inside one
// widget) has.
Inspection :: struct {
	box:      Layout_Box,
	has_box:  bool,
	hit:      Hit,
	hit_rect: Rect, // the hit's shape's device bounds
	has_hit:  bool,
	name:     string, // the tag on the hit's area, or on the box's
}

// inspect_at is what f has under device point p: of the boxes whose rect
// and clips contain p, one on the top layer (an open menu's, over the page
// beneath it), the deepest there, the smallest of equals; and the top-most
// hit area of any kind.
inspect_at :: proc(f: ^Frame, p: Point) -> (got: Inspection) {
	for b in f.boxes {
		if !rect_contains(b.rect, p) || !rect_contains(clip_chain_bounds(f, b.clip), p) {
			continue
		}
		better := !got.has_box || b.layer > got.box.layer
		if got.has_box && b.layer == got.box.layer {
			better = b.depth > got.box.depth || (b.depth == got.box.depth && area(b.rect) <= area(got.box.rect))
		}
		if better {
			got.box, got.has_box = b, true
		}
	}
	#reverse for h in f.hits {
		if hit_contains(f, h, p) {
			got.hit, got.has_hit = h, true
			got.hit_rect = transform_rect(h.transform, shape_bounds(f.ops, h.shape))
			break
		}
	}
	if got.has_box && got.has_hit && got.hit.layer > got.box.layer {
		// The area on top (a menu item painted in an overlay) covers the
		// box found beneath it: that widget is not what is under p.
		got.box, got.has_box = {}, false
	}
	for t in f.tags {
		if got.has_hit && t.id == got.hit.area {
			got.name = t.name
		} else if got.name == "" && got.has_box && t.id == got.box.id {
			got.name = t.name
		}
	}
	return
}

// inspect_lines is got as lines of text, with the widget state layout holds
// for its box and hit when layout is given.
inspect_lines :: proc(got: Inspection, layout: ^Layout, allocator := context.allocator, shared := 0) -> []string {
	lines := make([dynamic]string, allocator)
	if got.name != "" {
		append(&lines, fmt.aprintf("%q", got.name, allocator = allocator))
	}
	if got.has_box {
		b := got.box
		append(&lines, fmt.aprintf("from %s at %s:%d", b.procedure, filepath.base(b.file), b.line, allocator = allocator))
		append(&lines, fmt.aprintf("box  %s at %.0f,%.0f  depth %d", size_text(Size{b.rect.w, b.rect.h}), b.rect.x, b.rect.y, b.depth, allocator = allocator))
		append(&lines, fmt.aprintf("min  %s", size_text(b.min), allocator = allocator))
		append(&lines, fmt.aprintf("max  %s", size_text(b.max), allocator = allocator))
		if shared > 0 {
			append(&lines, fmt.aprintf("id shared with %d other widget(s): wrap each in a ui.scope, or give it a key", shared, allocator = allocator))
		}
		if s := state_text(layout, b.id); s != "" {
			append(&lines, fmt.aprintf("state  %s", s, allocator = allocator))
		}
	}
	if got.has_hit {
		h := got.hit
		append(&lines, fmt.aprintf("hit  %s at %.0f,%.0f  %s", size_text(Size{got.hit_rect.w, got.hit_rect.h}), got.hit_rect.x, got.hit_rect.y, kinds_text(h.kinds), allocator = allocator))
		if s := state_text(layout, h.area); s != "" && (!got.has_box || h.area != got.box.id) {
			append(&lines, fmt.aprintf("hit state  %s", s, allocator = allocator))
		}
	}
	return lines[:]
}

// inspect_report is inspect_at's result at p as text for a reader without
// a window: "nothing at x,y" when p is over neither a widget nor an area.
inspect_report :: proc(f: ^Frame, layout: ^Layout, p: Point, allocator := context.allocator) -> string {
	got := inspect_at(f, p)
	if !got.has_box && !got.has_hit {
		return fmt.aprintf("nothing at %.0f,%.0f\n", p.x, p.y, allocator = allocator)
	}
	b := strings.builder_make(allocator)
	for l in inspect_lines(got, layout, context.temp_allocator, id_sharers(f, got)) {
		strings.write_string(&b, l)
		strings.write_byte(&b, '\n')
	}
	return strings.to_string(b)
}

// layout_report lists every widget box of f, one a line in the order they
// closed, children before their container, indented by depth: the call,
// the box, and the constraints it was given.
layout_report :: proc(f: ^Frame, allocator := context.allocator) -> string {
	if len(f.boxes) == 0 {
		return strings.clone("no layout boxes: record the frame with Debug_Flag.Inspect\n", allocator)
	}
	tags := make(map[Area_Id]string, context.temp_allocator)
	for t in f.tags {
		tags[t.id] = t.name
	}
	uses := make(map[Area_Id]int, context.temp_allocator)
	for x in f.boxes {
		uses[x.id] += 1
	}
	interactive := make(map[Area_Id]bool, context.temp_allocator)
	for hit in f.hits {
		interactive[hit.area] = true
	}
	b := strings.builder_make(allocator)
	for x in f.boxes {
		for _ in 0 ..< x.depth {
			strings.write_string(&b, "  ")
		}
		fmt.sbprintf(&b, "from %s at %s:%d  %s at %.0f,%.0f  min %s max %s", x.procedure, filepath.base(x.file), x.line, size_text(Size{x.rect.w, x.rect.h}), x.rect.x, x.rect.y, size_text(x.min), size_text(x.max))
		if name, ok := tags[x.id]; ok {
			fmt.sbprintf(&b, "  %q", name)
		}
		if n := uses[x.id]; n > 1 && interactive[x.id] {
			fmt.sbprintf(&b, "  (id shared by %d)", n)
		}
		strings.write_byte(&b, '\n')
	}
	return strings.to_string(b)
}

// INSPECT_MAX_COLOR and INSPECT_MIN_COLOR outline the inspected widget's
// max and min constraints from its origin, beside BOUNDS_COLOR's box, so
// the three read apart at a glance.
INSPECT_MAX_COLOR :: Color{255, 170, 0, 220}
INSPECT_MIN_COLOR :: Color{40, 200, 90, 220}

// paint_inspector draws, above everything, what f (the frame this one's
// input was routed against) has under device point p: the widget's box
// filled, its max and min constraints outlined from its origin, the hit
// area outlined, and a panel of inspect_lines beside p. The frame loops
// call it after the app's ui, outside any transform; scale is the display
// density, for the panel's text.
paint_inspector :: proc(gtx: ^Ctx, f: ^Frame, p: Point, scale: f32 = 1) {
	if f == nil {
		return
	}
	got := inspect_at(f, p)
	if !got.has_box && !got.has_hit {
		return
	}
	o := gtx.ops
	m := macro_begin(o)
	if got.has_box {
		r := got.box.rect
		fill(o, r, Color{255, 0, 255, 40})
		stroke(o, r, BOUNDS_COLOR, {width = 2})
		limit :: proc(v, room: f32) -> f32 {
			return is_finite(v) ? v : room // an unbounded max runs to the window's edge
		}
		room := gtx.constraints.max * scale
		mx := Rect{r.x, r.y, limit(got.box.max.x * scale, room.x - r.x), limit(got.box.max.y * scale, room.y - r.y)}
		stroke(o, mx, INSPECT_MAX_COLOR, {width = 1})
		stroke(o, Rect{r.x, r.y, got.box.min.x * scale, got.box.min.y * scale}, INSPECT_MIN_COLOR, {width = 1})
	}
	if got.has_hit {
		stroke(o, got.hit_rect, HIT_BOUNDS_COLOR, {width = 2})
	}
	// The panel: one run a line, on a dark card beside the pointer.
	lines := inspect_lines(got, gtx.layout, gtx.allocator, id_sharers(f, got))
	size := 12 * scale
	lh := size * 1.4
	pad := 8 * scale
	runs := make([]Glyph_Run, len(lines), gtx.allocator)
	w: f32
	for l, i in lines {
		runs[i] = shape(gtx.shaper, gtx.theme.font, size, l, gtx.allocator)
		w = max(w, runs[i].advance)
	}
	card := Rect{p.x + 16 * scale, p.y + 16 * scale, w + 2 * pad, f32(len(lines)) * lh + 2 * pad}
	window := gtx.constraints.max * scale
	if card.x + card.w > window.x {
		card.x = max(p.x - 16 * scale - card.w, 0)
	}
	if card.y + card.h > window.y {
		card.y = max(p.y - 16 * scale - card.h, 0)
	}
	fill(o, Round_Rect{card, 6 * scale}, Color{24, 22, 30, 235})
	for run, i in runs {
		glyphs(o, add_run(o, run), {card.x + pad, card.y + pad + f32(i) * lh + size}, Color{240, 238, 245, 255})
	}
	macro_end(o, m)
	defer_call(o, m, root = true)
}

// kinds_text is ks as their names, space separated.
@(private = "file")
kinds_text :: proc(ks: Event_Kinds) -> string {
	b := strings.builder_make(context.temp_allocator)
	for k in Event_Kind {
		if k in ks {
			if strings.builder_len(b) > 0 {
				strings.write_byte(&b, ' ')
			}
			fmt.sbprint(&b, k)
		}
	}
	return strings.to_string(b)
}

// id_sharers is how many boxes in f other than got's own share its id,
// when the id takes input: a static widget's shared id is harmless, an
// interactive one's shares hover, press and animation.
@(private = "file")
id_sharers :: proc(f: ^Frame, got: Inspection) -> (n: int) {
	if !got.has_box {
		return
	}
	takes_input := false
	for h in f.hits {
		if h.area == got.box.id {
			takes_input = true
		}
	}
	if !takes_input {
		return
	}
	for b in f.boxes {
		if b.id == got.box.id {
			n += 1
		}
	}
	return max(n - 1, 0)
}

@(private = "file")
area :: proc(r: Rect) -> f32 {
	return r.w * r.h
}

// size_text is s as WxH, an unbounded side as inf.
@(private = "file")
size_text :: proc(s: Size) -> string {
	side :: proc(v: f32) -> string {
		return is_finite(v) ? fmt.tprintf("%.0f", v) : "inf"
	}
	return fmt.tprintf("%sx%s", side(s.x), side(s.y))
}

// state_text is the widget state layout keeps for id, the flags that are
// set and any moving springs, or "".
@(private = "file")
state_text :: proc(layout: ^Layout, id: Area_Id) -> string {
	if layout == nil {
		return ""
	}
	st, ok := layout.state[id]
	if !ok || st == nil {
		return ""
	}
	b := strings.builder_make(context.temp_allocator)
	if st.hovered {
		strings.write_string(&b, "hovered ")
	}
	if st.pressed {
		strings.write_string(&b, "pressed ")
	}
	if st.focused {
		strings.write_string(&b, "focused ")
	}
	if st.scroll != 0 {
		fmt.sbprintf(&b, "scroll=%.1f ", st.scroll)
	}
	if st.scroll_x != 0 {
		fmt.sbprintf(&b, "scroll_x=%.1f ", st.scroll_x)
	}
	for s, i in st.springs {
		if s.started && (s.value != 0 || s.target != 0) {
			fmt.sbprintf(&b, "spring%d=%.2f->%.2f ", i, s.value, s.target)
		}
	}
	return strings.trim_right_space(strings.to_string(b))
}
