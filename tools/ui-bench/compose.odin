package main

import "core:fmt"
import "core:strings"
import "core:time"
import "jm:ui"
import bl "jm:ui/blend2d"
import "jm:ui/render"

// Compose times render.Compositor on frames that change the way real ones
// do, against whole-frame renders of the same frame.
Compose_State :: struct {
	kind:   int,
	step:   int, // changes every frame
	toggle: bool,
}

compose_card :: proc(gtx: ^ui.Ctx, s: ^Compose_State, i: int, x, y: f32, text: string) {
	outer := gtx.constraints
	ui.push_transform(gtx.ops, ui.translate(x, y))
	gtx.constraints = ui.loose({150, 44})
	card := ui.box(gtx, key = u64(i))
	r := ui.row(gtx, gap = 6, align = .Center, key = u64(i))
	ui.label(gtx, text)
	ui.checkbox(gtx, "", &s.toggle, key = u64(i))
	ui.button(gtx, "Go", key = u64(i))
	ui.end(&r)
	ui.end(&card)
	ui.pop_transform(gtx.ops)
	gtx.constraints = outer
}

compose_scene :: proc(gtx: ^ui.Ctx, user: rawptr) {
	s := (^Compose_State)(user)
	size := gtx.constraints.max
	ui.fill(gtx.ops, ui.Rect{0, 0, size.x, size.y}, ui.Color{246, 246, 248, 255})
	switch s.kind {
	case 0, 4:
		// animate: 60 static cards, a ticking label and a rotating clipped badge.
		// full: the same frame, but the whole target is invalidated each time.
		for i in 0 ..< 60 {
			compose_card(gtx, s, i, 16 + f32(i % 5) * 160, 80 + f32(i / 5) * 52, fmt.tprintf("Item %d", i))
		}
		ui.push_transform(gtx.ops, ui.translate(16, 20))
		ui.label(gtx, fmt.tprintf("frame %d", s.step))
		ui.pop_transform(gtx.ops)
		w, h: f32 = 220, 70
		m := ui.mul(ui.mul(ui.translate(-w / 2, -h / 2), ui.rotate(f32(s.step) * 0.02)), ui.translate(size.x - 150, 60))
		ui.push_transform(gtx.ops, m)
		rr := ui.Round_Rect{{0, 0, w, h}, 18}
		ui.push_clip(gtx.ops, rr)
		ui.fill(gtx.ops, rr, ui.Color{60, 90, 220, 255})
		for k in 0 ..< 8 {
			ui.fill(gtx.ops, ui.Rect{f32(k) * 30, -10, 12, h + 20}, ui.Color{255, 255, 255, 60})
		}
		ui.label(gtx, "affine + clip")
		ui.pop_clip(gtx.ops)
		ui.pop_transform(gtx.ops)
	case 1:
		// hover: 1000 cards, one of them changes.
		for i in 0 ..< 1000 {
			text := fmt.tprintf("Item %d", i)
			if i == 437 && s.step % 2 == 1 {
				text = "Item 437*"
			}
			compose_card(gtx, s, i, f32(i % 8) * 160, f32(i / 8) * 6, text)
		}
	case 2:
		// scroll: a clipped list filling the window moves 30 px a frame.
		ui.push_clip(gtx.ops, ui.Rect{8, 8, size.x - 16, size.y - 16})
		ui.push_transform(gtx.ops, ui.translate(0, -f32(s.step % 10) * 30))
		for i in 0 ..< int(size.y / 26) + 12 {
			for c in 0 ..< int(size.x / 160) {
				compose_card(gtx, s, i * 16 + c, f32(c) * 160, f32(i) * 26, fmt.tprintf("Row %d", i))
			}
		}
		ui.pop_transform(gtx.ops)
		ui.pop_clip(gtx.ops)
	case 3:
		// idle: nothing changes.
		for i in 0 ..< 60 {
			compose_card(gtx, s, i, 16 + f32(i % 5) * 160, 80 + f32(i / 5) * 52, fmt.tprintf("Item %d", i))
		}
	}
}

compose_bench :: proc(w, h: int, workers: []int, frames: int) {
	names := []string{"animate", "hover", "scroll", "idle", "full"}
	whats := []string {
		"ticking label + rotating clipped badge",
		"1 of 1000 cards changes",
		"clipped full-window list scrolls 30 px",
		"nothing changes",
		"animate, whole target invalidated",
	}
	BG :: ui.Color{246, 246, 248, 255}

	r: render.Renderer
	render.init(&r)
	defer render.destroy(&r)
	img: bl.ImageCore
	bl.image_init(&img)
	defer bl.image_destroy(&img)
	assert(bl.image_create(&img, i32(w), i32(h), .PRGB32) == 0)

	cell :: proc(v: string, width: int) -> string {
		return strings.right_justify(v, width, " ", context.temp_allocator)
	}
	fmt.printfln("%dx%d, %d frames each, ms per frame; painted/moved = share of the target repainted/scrolled; render = whole frame with Blend2D threads, w = compositor workers", w, h, frames)
	fmt.printf("%-8s %6s %7s %7s %8s %8s", "scene", "draws", "painted", "moved", "render", "t=4")
	for n in workers {
		fmt.printf(" %s", cell(fmt.tprintf("w=%d", n), 8))
	}
	fmt.println("   what")

	for name, kind in names {
		st := Compose_State{kind = kind}
		p: ui.Probe
		ui.probe_init(&p, compose_scene, &st, {f32(w), f32(h)})
		ui.add_font(&p.ops, FONT)
		p.shaper = render.shaper(&r, p.ops.fonts[:])
		ui.probe_frame(&p)
		ui.probe_frame(&p)
		f := ui.probe_current(&p)

		whole: [2]f64
		for t, ti in ([]u32{0, 4}) {
			r.threads = t
			render.render(&r, f, &img, BG)
			t0 := time.tick_now()
			for _ in 0 ..< frames {
				render.render(&r, f, &img, BG)
			}
			whole[ti] = time.duration_milliseconds(time.tick_since(t0)) / f64(frames)
		}
		r.threads = 0
		fmt.printf("%-8s %s", name, cell(fmt.tprint(len(f.draws)), 6))

		for n, ni in workers {
			c: render.Compositor
			render.compositor_init(&c, n)
			st.step = 0
			ui.probe_frame(&p)
			render.compose(&c, ui.probe_current(&p), &img, BG)
			spent: time.Duration
			painted, moved: f64
			for _ in 0 ..< frames {
				st.step += 1
				ui.probe_frame(&p)
				if kind == 4 {
					render.damage_invalidate(&c.damage)
				}
				t0 := time.tick_now()
				render.compose(&c, ui.probe_current(&p), &img, BG)
				spent += time.tick_since(t0)
				for q in c.damage.rects {
					painted += f64(q.w * q.h)
				}
				for q in c.damage.scrolls {
					moved += f64(q.rect.w * q.rect.h)
				}
			}
			render.compositor_destroy(&c)
			if ni == 0 {
				pct :: proc(v: f64, frames, w, h: int) -> string {
					return fmt.tprintf("%.1f%%", 100 * v / f64(frames * w * h))
				}
				fmt.printf(" %s %s", cell(pct(painted, frames, w, h), 7), cell(pct(moved, frames, w, h), 7))
				fmt.printf(" %s %s", cell(fmt.tprintf("%.2f", whole[0]), 8), cell(fmt.tprintf("%.2f", whole[1]), 8))
			}
			fmt.printf(" %s", cell(fmt.tprintf("%.3f", time.duration_milliseconds(spent) / f64(frames)), 8))
		}
		fmt.printfln("   %s", whats[kind])
		ui.probe_destroy(&p)
		free_all(context.temp_allocator)
	}
}
