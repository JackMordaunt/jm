package render_fuzz

import "core:math"

import harness "jm:fuzz"
import "jm:ui"

// Model is a scene the generator edits from frame to frame: clips, each able
// to scroll its content, and items drawn in order. build turns it into a
// ui.Frame. Every choice is drawn from a Source, zero bytes giving the
// simplest scene: one small target, nothing on it.
Model :: struct {
	size:  [2]i32,
	clips: [dynamic]Clip_Model,
	items: [dynamic]Item,
	ids:   int, // items made so far, so each has its own id
}

Clip_Kind :: enum u8 {
	Rect,
	Round_Rect,
	Ellipse,
}

// Clip_Model is a clip shape at rect, turned by angle, whose parent's
// content scroll moves it along. Its own scroll moves the content under it.
Clip_Model :: struct {
	parent: int, // -1 for none; always below this clip's index
	kind:   Clip_Kind,
	rect:   ui.Rect,
	radius: f32,
	angle:  f32,
	scroll: [2]f32,
}

Item_Kind :: enum u8 {
	Rect,
	Round_Rect,
	Ellipse,
	Path,
	Text,
}

Paint_Kind :: enum u8 {
	Solid,
	Translucent,
	Linear,
	Radial,
}

// Item is one draw: a shape of size at pos, turned by angle, filled or,
// with a stroke width, outlined.
Item :: struct {
	kind:   Item_Kind,
	size:   [2]f32,
	radius: f32,
	pos:    [2]f32,
	angle:  f32,
	paint:  Paint_Kind,
	colors: [2]ui.Color,
	stroke: f32, // 0 fills
	clip:   int, // -1 for none
	seed:   u8, // picks the text, and bends the path
	id:     int, // which item this is, whatever its place in the order
}

Edit :: enum u8 {
	Nothing,
	Move,
	Recolor,
	Add,
	Remove,
	Swap,
	Scroll,
	Turn_Clip,
	Resize,
}

SIZES := [][2]i32{{64, 48}, {200, 150}, {320, 240}, {257, 131}}
BIG :: [2]i32{640, 480}
TEXTS := []string{"Ag", "Wafgjy", "hello, world", "ÅÉÎ fff", "Thq"}
TEXT_SIZES := []f32{9, 13, 24}
ANGLES := []f32{0, 0, 0, 0.3, math.PI / 4}
FRACTIONS := []f32{0, 0, 0.5, 0.25, 0.3}

// generate draws a starting scene. One case in eight is big: a 640×480
// target and a grid of a thousand cells under the first clip, which is what
// it takes to reach the compositor's shared paths.
generate :: proc(src: ^harness.Source) -> Model {
	m: Model
	big := harness.integer_in(src, 0, 8) == 7
	m.size = BIG if big else harness.choice(src, SIZES)
	for _ in 0 ..< harness.integer_in(src, 0, 5) {
		append(&m.clips, clip_model(src, &m))
	}
	for _ in 0 ..< harness.integer_in(src, 0, 30) {
		append(&m.items, item(src, &m))
	}
	if big {
		if len(m.clips) == 0 {
			append(&m.clips, Clip_Model{parent = -1, kind = .Rect, rect = {10, 10, 620, 460}})
		}
		for i in 0 ..< 1100 {
			c := u8(i * 7)
			append(&m.items, Item {
				kind = .Rect,
				size = {20, 10},
				pos = {f32(i % 25) * 24, f32(i / 25) * 14},
				colors = {{c, 255 - c, 90, 255}, {}},
				clip = 0,
			})
		}
	}
	return m
}

// edit changes m the way a frame of a real ui might.
edit :: proc(src: ^harness.Source, m: ^Model) {
	e := Edit(harness.integer_in(src, 0, len(Edit)))
	n := len(m.items)
	switch e {
	case .Nothing:
	case .Move:
		if n > 0 {
			it := &m.items[harness.integer_in(src, 0, n)]
			it.pos += {f32(harness.integer_in(src, -20, 21)), f32(harness.integer_in(src, -20, 21))} + harness.choice(src, FRACTIONS)
		}
	case .Recolor:
		if n > 0 {
			m.items[harness.integer_in(src, 0, n)].colors[0] = color(src)
		}
	case .Add:
		inject_at(&m.items, harness.integer_in(src, 0, n + 1), item(src, m))
	case .Remove:
		if n > 0 {
			ordered_remove(&m.items, harness.integer_in(src, 0, n))
		}
	case .Swap:
		if n > 1 {
			i := harness.integer_in(src, 0, n - 1)
			m.items[i], m.items[i + 1] = m.items[i + 1], m.items[i]
		}
	case .Scroll:
		// Mostly whole pixels, the moves the compositor can scroll.
		if len(m.clips) > 0 {
			c := &m.clips[harness.integer_in(src, 0, len(m.clips))]
			d := f32(harness.integer_in(src, -40, 41))
			if harness.boolean(src) {
				c.scroll.y += d + harness.choice(src, FRACTIONS)
			} else {
				c.scroll.x += d
			}
		}
	case .Turn_Clip:
		if len(m.clips) > 0 {
			m.clips[harness.integer_in(src, 0, len(m.clips))].angle += 0.1
		}
	case .Resize:
		m.size = harness.choice(src, SIZES)
	}
}

clip_model :: proc(src: ^harness.Source, m: ^Model) -> Clip_Model {
	w, h := f32(m.size.x), f32(m.size.y)
	c := Clip_Model {
		parent = harness.integer_in(src, -1, len(m.clips)),
		kind   = Clip_Kind(harness.integer_in(src, 0, len(Clip_Kind))),
		angle  = harness.choice(src, ANGLES),
		radius = f32(harness.integer_in(src, 0, 30)),
	}
	c.rect.x = f32(harness.integer_in(src, -10, int(w))) + harness.choice(src, FRACTIONS)
	c.rect.y = f32(harness.integer_in(src, -10, int(h))) + harness.choice(src, FRACTIONS)
	c.rect.w = f32(harness.integer_in(src, 1, int(w) + 20))
	c.rect.h = f32(harness.integer_in(src, 1, int(h) + 20))
	return c
}

item :: proc(src: ^harness.Source, m: ^Model) -> Item {
	w, h := f32(m.size.x), f32(m.size.y)
	m.ids += 1
	it := Item {
		id     = m.ids,
		kind   = Item_Kind(harness.integer_in(src, 0, len(Item_Kind))),
		angle  = harness.choice(src, ANGLES),
		paint  = Paint_Kind(harness.integer_in(src, 0, len(Paint_Kind))),
		colors = {color(src), color(src)},
		stroke = harness.choice(src, []f32{0, 0, 1, 2.5, 6}),
		clip   = harness.integer_in(src, -1, len(m.clips)),
		seed   = u8(harness.integer_in(src, 0, 256)),
		radius = f32(harness.integer_in(src, 0, 20)),
	}
	it.size = {f32(harness.integer_in(src, 1, 90)), f32(harness.integer_in(src, 1, 60))}
	// One in six is large enough to cover whole tiles, like a background
	// or a panel.
	if harness.integer_in(src, 0, 6) == 5 {
		it.size = {f32(harness.integer_in(src, 64, int(w) + 40)), f32(harness.integer_in(src, 64, int(h) + 40))}
	}
	it.pos = {
		f32(harness.integer_in(src, -30, int(w) + 10)) + harness.choice(src, FRACTIONS),
		f32(harness.integer_in(src, -30, int(h) + 10)) + harness.choice(src, FRACTIONS),
	}
	return it
}

color :: proc(src: ^harness.Source) -> ui.Color {
	return {u8(harness.integer_in(src, 0, 256)), u8(harness.integer_in(src, 0, 256)), u8(harness.integer_in(src, 0, 256)), 255}
}

// shift is how far the content under clip c has scrolled, its ancestors'
// scrolls included; -1 has none.
shift :: proc(m: ^Model, c: int) -> [2]f32 {
	s: [2]f32
	for i := c; i >= 0; i = m.clips[i].parent {
		s += m.clips[i].scroll
	}
	return s
}

// build writes m into frame, with its resources in ops, as flatten would:
// every clip after its parent, every draw after its clip.
build :: proc(m: ^Model, ops: ^ui.Ops, frame: ^ui.Frame, shaper: ui.Shaper, font: ui.Font_Id) {
	ui.ops_reset(ops)
	ui.frame_reset(frame)
	frame.ops = ops
	for c in m.clips {
		s := shift(m, c.parent)
		t := ui.mul(ui.rotate(c.angle), ui.translate(c.rect.x - s.x, c.rect.y - s.y))
		local := ui.Rect{0, 0, c.rect.w, c.rect.h}
		shape: ui.Shape
		switch c.kind {
		case .Rect:
			shape = local
		case .Round_Rect:
			shape = ui.Round_Rect{local, c.radius}
		case .Ellipse:
			shape = ui.Ellipse{local}
		}
		append(&frame.clips, ui.Clip{ui.Clip_Id(c.parent), shape, t})
	}
	for &it in m.items {
		s := shift(m, it.clip)
		t := ui.mul(ui.rotate(it.angle), ui.translate(it.pos.x - s.x, it.pos.y - s.y))
		local := ui.Rect{0, 0, it.size.x, it.size.y}
		paint := make_paint(&it)
		cmd: ui.Draw_Cmd
		shape: ui.Shape
		switch it.kind {
		case .Rect:
			shape = local
		case .Round_Rect:
			shape = ui.Round_Rect{local, it.radius}
		case .Ellipse:
			shape = ui.Ellipse{local}
		case .Path:
			shape = ui.Path_Ref{ui.add_path(ops, bent_path(it.size, it.seed))}
		case .Text:
			text := TEXTS[int(it.seed) % len(TEXTS)]
			size := TEXT_SIZES[int(it.seed) % len(TEXT_SIZES)]
			append(&ops.runs, ui.shape(shaper, font, size, text, context.allocator))
			cmd = ui.Glyphs{ui.Run_Id(len(ops.runs) - 1), {0, size}, it.colors[0]}
		}
		if cmd == nil {
			if it.stroke > 0 {
				cmd = ui.Stroke{shape, paint, {width = it.stroke}}
			} else {
				cmd = ui.Fill{shape, paint}
			}
		}
		append(&frame.draws, ui.Draw{t, ui.Clip_Id(it.clip), cmd})
	}
}

make_paint :: proc(it: ^Item) -> ui.Paint {
	a, b := it.colors[0], it.colors[1]
	switch it.paint {
	case .Solid:
		return a
	case .Translucent:
		return ui.Color{a.r, a.g, a.b, 120}
	case .Linear:
		stops := make([]ui.Gradient_Stop, 2)
		stops[0], stops[1] = {0, a}, {1, b}
		return ui.Linear_Gradient{{0, 0}, it.size, stops}
	case .Radial:
		stops := make([]ui.Gradient_Stop, 2)
		stops[0], stops[1] = {0, a}, {1, b}
		return ui.Radial_Gradient{it.size / 2, max(it.size.x, it.size.y) / 2, stops}
	}
	return a
}

// bent_path is a closed path inside size: a triangle, with a curve on one
// side when seed says so.
bent_path :: proc(size: [2]f32, seed: u8) -> ui.Path {
	verbs := make([dynamic]ui.Path_Verb)
	points := make([dynamic]ui.Point)
	append(&verbs, ui.Path_Verb.Move)
	append(&points, ui.Point{0, size.y})
	append(&verbs, ui.Path_Verb.Line)
	append(&points, ui.Point{size.x / 2, 0})
	if seed % 2 == 1 {
		append(&verbs, ui.Path_Verb.Cubic)
		append(&points, ui.Point{size.x, 0}, ui.Point{size.x, size.y / 2}, ui.Point{size.x, size.y})
	} else {
		append(&verbs, ui.Path_Verb.Line)
		append(&points, ui.Point{size.x, size.y})
	}
	append(&verbs, ui.Path_Verb.Close)
	return {verbs[:], points[:]}
}
