package datagrid

import "jm:ui"
import "jm:ui/ops"

// A grid draws hundreds of cells a frame, and from one frame to the next
// nearly all of them are the cells it drew before: a scroll brings in a
// row or two. Text_Cache keeps the glyphs each cell's text shaped to, so a
// cell shapes once while it stays in view, and a steady frame shapes
// nothing and allocates nothing. It is fixed in size: an open-addressed
// table of runs over one pool of glyphs, both made once, and emptied
// whole when either fills, which costs one frame of shaping.
//
// A run is found by the hash of the shaper, its font, size and text: a
// probe that swaps the stub shaper for a real one, as
// render.headless_init does after probe_init's first frame, misses
// rather than drawing stub glyphs in a real font. Two texts whose
// 64-bit hashes collide would draw one as the other; at a few
// thousand texts in the cache that is a chance near 1e-13.

TEXT_SLOTS  :: 8192 // a power of two
TEXT_GLYPHS :: 1 << 17

@(private)
Text_Slot :: struct {
	hash:    u64,
	first:   i32,
	count:   i32,
	advance: f32,
}

Text_Cache :: struct {
	slots:  []Text_Slot,
	glyphs: []ops.Glyph,
	used:   int, // glyphs taken
	filled: int, // slots taken
	hits:   u64,
	misses: u64,
}

text_cache_init :: proc(c: ^Text_Cache, allocator := context.allocator) {
	c.slots = make([]Text_Slot, TEXT_SLOTS, allocator)
	c.glyphs = make([]ops.Glyph, TEXT_GLYPHS, allocator)
}

text_cache_destroy :: proc(c: ^Text_Cache, allocator := context.allocator) {
	delete(c.slots, allocator)
	delete(c.glyphs, allocator)
	c^ = {}
}

@(private)
text_cache_empty :: proc(c: ^Text_Cache) {
	for &s in c.slots {
		s = {}
	}
	c.used, c.filled = 0, 0
}

// shaped is text in font at size, from the cache or shaped now and kept.
shaped :: proc(
	gtx: ^ui.Ctx,
	c: ^Text_Cache,
	font: ops.Font_Id,
	size: f32,
	text: string,
) -> ops.Glyph_Run {
	if len(text) == 0 {
		return {font = font, size = size}
	}
	h := ui.fnv_u64(
		ui.FNV_OFFSET,
		u64(uintptr(gtx.shaper.data)) ~ u64(uintptr(rawptr(gtx.shaper.shape))),
	)
	h = ui.fnv_u64(ui.fnv_u64(h, u64(font)), u64(transmute(u32)size))
	h = ui.fnv_bytes(h, transmute([]u8)text) | 1 // 0 marks an empty slot
	mask := len(c.slots) - 1
	i := int(h) & mask
	for c.slots[i].hash != 0 {
		if c.slots[i].hash == h {
			c.hits += 1
			s := c.slots[i]
			return {font, size, c.glyphs[s.first:s.first + s.count], s.advance}
		}
		i = (i + 1) & mask
	}
	c.misses += 1
	run := ui.shape(gtx.shaper, font, size, text, gtx.allocator)
	if c.filled * 2 >= len(c.slots) || c.used + len(run.glyphs) > len(c.glyphs) {
		if len(run.glyphs) > len(c.glyphs) / 4 {
			return run // too big to keep: the frame's own copy
		}
		text_cache_empty(c)
		i = int(h) & mask
	}
	first := c.used
	copy(c.glyphs[first:], run.glyphs)
	c.used += len(run.glyphs)
	c.slots[i] = {h, i32(first), i32(len(run.glyphs)), run.advance}
	c.filled += 1
	return {font, size, c.glyphs[first:c.used], run.advance}
}

// Text_Style is how a cell's text is set: font, size, colour, the line's
// ascent, and the ellipsis shaped in that font.
@(private)
Text_Style :: struct {
	font:     ops.Font_Id,
	size:     f32,
	ascent:   f32,
	height:   f32,
	ellipsis: ops.Glyph_Run,
}

// text_style is the style for font at size.
@(private)
text_style :: proc(gtx: ^ui.Ctx, c: ^Text_Cache, font: ops.Font_Id, size: f32) -> Text_Style {
	m := ui.metrics(gtx.shaper, font, size)
	return {font, size, m.ascent, m.ascent + m.descent, shaped(gtx, c, font, size, "…")}
}

// draw_line draws text on one line in box (its own space), placed by
// align and centred down the box, cut with an ellipsis where it would
// pass the box's right edge. It returns whether it was cut.
@(private)
draw_line :: proc(
	gtx: ^ui.Ctx,
	c: ^Text_Cache,
	ts: Text_Style,
	text: string,
	box: ops.Rect,
	align: Align,
	color: ops.Color,
) -> bool {
	if text == "" || box.w <= 0 || !ui.painted(color) {
		return false
	}
	run := shaped(gtx, c, ts.font, ts.size, text)
	y := box.y + (box.h - ts.height) / 2 + ts.ascent
	if run.advance <= box.w + 0.5 {
		x := box.x
		switch align {
		case .End:
			x += box.w - run.advance
		case .Center:
			x += (box.w - run.advance) / 2
		case .Start:
		}
		ops.glyphs(gtx.scene, ops.add_run(gtx.scene, run), {x, y}, color)
		return false
	}
	cut := cut_at(run, box.w - ts.ellipsis.advance)
	if cut <= 0 && len(run.glyphs) > 0 && run.glyphs[len(run.glyphs) - 1].x < run.glyphs[0].x {
		// Right to left: no clean cut from the end; clip instead.
		ops.clip_push(gtx.scene, box)
		ops.glyphs(gtx.scene, ops.add_run(gtx.scene, run), {box.x, y}, color)
		ops.clip_pop(gtx.scene)
		return true
	}
	head := ops.Glyph_Run{run.font, run.size, run.glyphs[:cut], 0}
	pen := box.x
	if cut > 0 {
		head.advance = run.glyphs[cut].x
		ops.glyphs(gtx.scene, ops.add_run(gtx.scene, head), {pen, y}, color)
		pen += head.advance
	}
	if ts.ellipsis.advance <= box.w {
		ops.glyphs(gtx.scene, ops.add_run(gtx.scene, ts.ellipsis), {pen, y}, color)
	}
	return true
}

// cut_at is how many of run's glyphs fit in width, in whole clusters, for
// a run wider than width: glyphs before k end where glyph k starts, so k
// is the last glyph starting within width, moved back to its cluster's
// first glyph.
@(private)
cut_at :: proc(run: ops.Glyph_Run, width: f32) -> int {
	k := 0
	for g, i in run.glyphs {
		if g.x > width {
			break
		}
		k = i
	}
	for k > 0 && run.glyphs[k].cluster == run.glyphs[k - 1].cluster {
		k -= 1
	}
	return k
}

// text_width is text's width in font at size, from the cache.
@(private)
text_width :: proc(
	gtx: ^ui.Ctx,
	c: ^Text_Cache,
	font: ops.Font_Id,
	size: f32,
	text: string,
) -> f32 {
	return shaped(gtx, c, font, size, text).advance
}
