package windows

import "core:fmt"
import "core:testing"

import "jm:ui"
import bl "jm:ui/blend2d"
import "jm:ui/ops"
import "jm:ui/render"

// TOLERANCE is the most any channel of any pixel may differ from the
// system's own buttons: DirectWrite's anti-aliasing is not Blend2D's.
@(private = "file")
TOLERANCE :: 16

// Native is Windows 11 23H2's caption buttons at 100%, captured on a white
// (light) or black (dark) caption: the 138 × 29 below the window's 1px
// top border, the three 46px slots ending at the client's right edge.
@(private = "file")
Native :: struct {
	png:   []byte,
	dark:  bool,
	bar:   ui.Title_Bar,
	label: string,
}

@(private = "file")
NATIVE := [?]Native {
	{#load("testdata/light-rest.png"), false, {active = true}, "light rest"},
	{#load("testdata/light-inactive.png"), false, {}, "light inactive"},
	{#load("testdata/light-inactive-hover-min.png"), false, {hover = .Minimize}, "light inactive, hover minimize"},
	{#load("testdata/light-hover-min.png"), false, {active = true, hover = .Minimize}, "light hover minimize"},
	{#load("testdata/light-hover-max.png"), false, {active = true, hover = .Maximize}, "light hover maximize"},
	{#load("testdata/light-hover-close.png"), false, {active = true, hover = .Close}, "light hover close"},
	{#load("testdata/light-press-min.png"), false, {active = true, hover = .Minimize, pressed = .Minimize}, "light press minimize"},
	{#load("testdata/light-press-max.png"), false, {active = true, hover = .Maximize, pressed = .Maximize}, "light press maximize"},
	{#load("testdata/light-press-close.png"), false, {active = true, hover = .Close, pressed = .Close}, "light press close"},
	{#load("testdata/dark-rest.png"), true, {active = true}, "dark rest"},
	{#load("testdata/dark-inactive.png"), true, {}, "dark inactive"},
	{#load("testdata/dark-hover-min.png"), true, {active = true, hover = .Minimize}, "dark hover minimize"},
	{#load("testdata/dark-hover-close.png"), true, {active = true, hover = .Close}, "dark hover close"},
	{#load("testdata/dark-press-min.png"), true, {active = true, hover = .Minimize, pressed = .Minimize}, "dark press minimize"},
	{#load("testdata/dark-press-close.png"), true, {active = true, hover = .Close, pressed = .Close}, "dark press close"},
}

@(private = "file")
Rig :: struct {
	dark:   bool,
	height: f32,
}

@(private = "file")
rig_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	r := (^Rig)(user)
	caption_buttons(gtx, r.height, r.dark)
}

// The buttons match the system's in every captured state.
@(test)
caption_buttons_match_the_system :: proc(t: ^testing.T) {
	codecs: bl.ArrayCore
	testing.expect_value(t, bl.image_codec_array_init_built_in_codecs(&codecs), bl.Result(0))
	defer bl.array_destroy(&codecs)
	for n in NATIVE {
		want: bl.ImageCore
		bl.image_init(&want)
		defer bl.image_destroy(&want)
		if !testing.expectf(t, bl.image_read_from_data(&want, raw_data(n.png), len(n.png), &codecs) == 0, "%s: decode", n.label) {
			continue
		}
		r := Rig{n.dark, 30}
		h: render.Headless
		render.headless_init(&h, rig_view, &r, {138, 30}, nil)
		defer render.headless_destroy(&h)
		h.p.title_bar = n.bar
		ui.probe_frame(&h.p)
		got: bl.ImageCore
		bl.image_init(&got)
		defer bl.image_destroy(&got)
		testing.expect_value(t, bl.image_create(&got, 138, 30, .PRGB32), bl.Result(0))
		bg := ops.Color{0, 0, 0, 255} if n.dark else ops.Color{255, 255, 255, 255}
		render.render(&h.r, ui.probe_current(&h.p), &got, bg)
		worst, at := 0, [2]int{}
		for y in 0 ..< 29 {
			for x in 0 ..< 138 {
				a := render.pixel(&got, x, y + 1)
				b := render.pixel(&want, x, y)
				for c in 0 ..< 3 {
					d := abs(int(a[c]) - int(b[c]))
					if d > worst {
						worst, at = d, {x, y + 1}
					}
				}
			}
		}
		testing.expectf(t, worst <= TOLERANCE, "%s: off by %d at %v", n.label, worst, at)
	}
}

// Each button is offered to the shell where it is drawn, and the slots
// round to whole device pixels.
@(test)
caption_buttons_offer_each_button :: proc(t: ^testing.T) {
	r := Rig{false, 48}
	h: render.Headless
	render.headless_init(&h, rig_view, &r, {400, 60}, nil)
	defer render.headless_destroy(&h)
	h.p.density = 1.25
	ui.probe_frame(&h.p)
	f := ui.probe_current(&h.p)
	// The probe's frame is in points: 58 device pixels at 1.25 is 46.4.
	testing.expect_value(t, len(f.buttons), 3)
	want := [3]ops.Caption_Button{.Minimize, .Maximize, .Close}
	for b, i in f.buttons {
		testing.expect_value(t, b.button, want[i])
		testing.expectf(t, abs(b.rect.x - f32(i) * 46.4) < 0.01 && abs(b.rect.w - 46.4) < 0.01 && b.rect.h == 48, "%v at %v", b.button, b.rect)
	}
	testing.expect(t, ui.probe_tagged(&h.p, "Maximize"), "maximize is named")

	h.p.title_bar = {maximized = true}
	ui.probe_frame(&h.p)
	testing.expect(t, ui.probe_tagged(&h.p, "Restore"), fmt.tprint("a maximized window restores"))
}
