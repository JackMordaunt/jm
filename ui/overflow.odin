package ui

import "core:fmt"
import "core:strings"

// Overflow is one draw whose content runs past the side of what can show
// it: the window, or a clip inside it such as a scroll box's view. Most
// are a layout that does not fit; some are meant (a carousel's peeking
// item, a text field scrolled to its caret), and nothing in a frame tells
// a viewport's clip from a mask, so near names the place for a reader to
// judge.
Overflow :: struct {
	draw:      int, // index in Frame.draws
	kind:      string, // "fill", "stroke", "text" or "image"
	bounds:    Rect, // device space: where the draw paints
	visible:   Rect, // device space: what the window and its clips leave
	near:      string, // the name of the smallest tagged area over it, or ""
}

// OVERFLOW_SLOP is how far, in pixels, a draw may pass an edge before it
// counts: antialiasing and rounding reach a pixel over.
OVERFLOW_SLOP :: f32(1)

// frame_overflow lists f's draws that run past the left or right of the
// window of size window or of their clip. Vertical overflow is left out:
// content below a scroll box's view is how scrolling works, while content
// past the side is a layout that does not fit. A glyph run's extent is
// its origin and advance.
frame_overflow :: proc(f: ^Frame, window: Size, allocator := context.allocator) -> []Overflow {
	out := make([dynamic]Overflow, allocator)
	win := Rect{0, 0, window.x, window.y}
	for d, i in f.draws {
		local, kind := draw_bounds(f.ops, d.cmd)
		if local.w <= 0 {
			continue
		}
		b := transform_rect(d.transform, local)
		visible := rect_intersect(win, clip_chain_bounds(f, d.clip))
		cut_by :: proc(b, v: Rect) -> bool {
			return b.x < v.x - OVERFLOW_SLOP || b.x + b.w > v.x + v.w + OVERFLOW_SLOP
		}
		if !cut_by(b, visible) {
			continue
		}
		// Content wholly outside what shows it is scrolled or tucked away,
		// not cut off: only a draw straddling an edge counts.
		if b.x + b.w <= visible.x || b.x >= visible.x + visible.w || b.y + b.h <= visible.y || b.y >= visible.y + visible.h {
			continue
		}
		append(&out, Overflow{i, kind, b, visible, nearest_tag(f, b)})
	}
	return out[:]
}

// overflow_report is frame_overflow as text, one line a draw; "no
// overflow" when there is none.
overflow_report :: proc(f: ^Frame, window: Size, allocator := context.allocator) -> string {
	list := frame_overflow(f, window, context.temp_allocator)
	if len(list) == 0 {
		return strings.clone("no overflow\n", allocator)
	}
	b := strings.builder_make(allocator)
	for o in list {
		left := max(o.visible.x - o.bounds.x, 0)
		right := max(o.bounds.x + o.bounds.w - (o.visible.x + o.visible.w), 0)
		fmt.sbprintf(&b, "draw %d %s x %.0f..%.0f y %.0f: ", o.draw, o.kind, o.bounds.x, o.bounds.x + o.bounds.w, o.bounds.y)
		if left > 0 {
			fmt.sbprintf(&b, "%.0f past the left ", left)
		}
		if right > 0 {
			fmt.sbprintf(&b, "%.0f past the right ", right)
		}
		if o.near != "" {
			fmt.sbprintf(&b, "near %q", o.near)
		}
		fmt.sbprintln(&b)
	}
	return strings.to_string(b)
}

// draw_bounds is where cmd paints, in its own space, and what it is.
@(private = "file")
draw_bounds :: proc(ops: ^Ops, cmd: Draw_Cmd) -> (Rect, string) {
	switch c in cmd {
	case Fill:
		return shape_bounds(ops, c.shape), "fill"
	case Stroke:
		r := shape_bounds(ops, c.shape)
		h := c.style.width / 2
		return {r.x - h, r.y - h, r.w + 2 * h, r.h + 2 * h}, "stroke"
	case Glyphs:
		if int(c.run) < len(ops.runs) {
			run := ops.runs[c.run]
			return {c.origin.x, c.origin.y - run.size, run.advance, run.size * 1.2}, "text"
		}
	case Image:
		return c.dst, "image"
	}
	return {}, ""
}

// clip_chain_bounds is the device bounds of clip id and all it sits in;
// NO_CLIP is everywhere.
@(private)
clip_chain_bounds :: proc(f: ^Frame, id: Clip_Id) -> Rect {
	r := Rect{-1e7, -1e7, 2e7, 2e7}
	for c := id; c != NO_CLIP && int(c) < len(f.clips); c = f.clips[c].parent {
		cl := f.clips[c]
		r = rect_intersect(r, transform_rect(cl.transform, shape_bounds(f.ops, cl.shape)))
	}
	return r
}

// nearest_tag is the name of the smallest tagged hit area over the centre
// of b, or "".
@(private = "file")
nearest_tag :: proc(f: ^Frame, b: Rect) -> string {
	c := Point{b.x + b.w / 2, b.y + b.h / 2}
	best, best_area := "", f32(max(f32))
	for t in f.tags {
		for h in f.hits {
			if h.area != t.id {
				continue
			}
			hb := transform_rect(h.transform, shape_bounds(f.ops, h.shape))
			if rect_contains(hb, c) && hb.w * hb.h < best_area {
				best, best_area = t.name, hb.w * hb.h
			}
		}
	}
	return best
}

