package ui

import "core:fmt"
import "jm:ui/ops"
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
	bounds:    ops.Rect, // device space: where the draw paints
	visible:   ops.Rect, // device space: what the window and its clips leave
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
frame_overflow :: proc(f: ^Frame, window: ops.Size, allocator := context.allocator) -> []Overflow {
	out := make([dynamic]Overflow, allocator)
	win := ops.Rect{0, 0, window.x, window.y}
	for d, i in f.draws {
		local, kind := draw_bounds(f.scene, d.cmd)
		if local.w <= 0 {
			continue
		}
		b := ops.transform_rect(d.transform, local)
		visible := ops.rect_intersect(win, clip_chain_bounds(f, d.clip))
		cut_by :: proc(b, v: ops.Rect) -> bool {
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
overflow_report :: proc(f: ^Frame, window: ops.Size, allocator := context.allocator) -> string {
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
draw_bounds :: proc(sc: ^ops.Scene, cmd: Draw_Cmd) -> (ops.Rect, string) {
	switch c in cmd {
	case ops.Fill:
		return ops.shape_bounds(sc, c.shape), "fill"
	case ops.Stroke:
		r := ops.shape_bounds(sc, c.shape)
		h := c.style.width / 2
		return {r.x - h, r.y - h, r.w + 2 * h, r.h + 2 * h}, "stroke"
	case ops.Glyphs:
		if int(c.run) < len(sc.runs) {
			run := sc.runs[c.run]
			return {c.origin.x, c.origin.y - run.size, run.advance, run.size * 1.2}, "text"
		}
	case ops.Image:
		return c.dst, "image"
	case ops.Shadow:
		return ops.shadow_bounds(c), "shadow"
	}
	return {}, ""
}

// clip_chain_bounds is the device bounds of clip id and all it sits in;
// NO_CLIP is everywhere.
clip_chain_bounds :: proc(f: ^Frame, id: Clip_Id) -> ops.Rect {
	r := ops.Rect{-1e7, -1e7, 2e7, 2e7}
	for c := id; c != NO_CLIP && int(c) < len(f.clips); c = f.clips[c].parent {
		cl := f.clips[c]
		r = ops.rect_intersect(r, ops.transform_rect(cl.transform, ops.shape_bounds(f.scene, cl.shape)))
	}
	return r
}

// nearest_tag is the name of the smallest tagged hit area over the centre
// of b, or "".
@(private = "file")
nearest_tag :: proc(f: ^Frame, b: ops.Rect) -> string {
	c := ops.Point{b.x + b.w / 2, b.y + b.h / 2}
	best, best_area := "", f32(max(f32))
	for t in f.tags {
		for h in f.hits {
			if h.area != t.id {
				continue
			}
			hb := ops.transform_rect(h.transform, ops.shape_bounds(f.scene, h.shape))
			if ops.rect_contains(hb, c) && hb.w * hb.h < best_area {
				best, best_area = t.name, hb.w * hb.h
			}
		}
	}
	return best
}

