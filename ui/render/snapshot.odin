package render

import "jm:ui"

// snapshot renders one frame of ui_proc(gtx, user) headlessly and writes it
// to path as a PNG, in the one call that probe_init, per-font add_font, a
// Renderer and swapping in its shaper otherwise take separately. frames runs
// that many probe_frame steps at dt seconds apart before capturing, so an
// animated state reached only after several frames can be sampled without a
// real clock; frames defaults to 1 (the first frame) and dt to 1/60.
snapshot :: proc(
	ui_proc: proc(gtx: ^ui.Ctx, user: rawptr),
	user: rawptr,
	size: ui.Size,
	fonts: []ui.Font_Ref,
	path: string,
	theme: Maybe(ui.Theme) = nil,
	clear: ui.Color = {255, 255, 255, 255},
	frames: int = 1,
	dt: f32 = 1.0 / 60,
) -> bool {
	p: ui.Probe
	ui.probe_init(&p, ui_proc, user, size, theme = theme)
	defer ui.probe_destroy(&p)
	for f in fonts {
		ui.add_font(&p.ops, f.path)
	}
	r: Renderer
	init(&r)
	defer destroy(&r)
	p.shaper = shaper(&r, p.ops.fonts[:])
	ui.probe_advance(&p, frames, dt)
	return render_png(&r, ui.probe_current(&p), int(size.x), int(size.y), path, clear)
}
