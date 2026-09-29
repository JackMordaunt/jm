package render

import "jm:ui"
import "jm:ui/ops"

// snapshot renders one frame of ui_proc(gtx, user) headlessly and writes it
// to path as a PNG, in the one call that probe_init, per-font add_font, a
// Renderer and swapping in its shaper otherwise take separately. frames runs
// that many probe_frame steps at dt seconds apart before capturing, so an
// animated state reached only after several frames can be sampled without a
// real clock; frames defaults to 1 (the first frame) and dt to 1/60.
// debug sets gtx.debug, joined by whatever JM_UI_DEBUG asks for
// (ui.debug_from_env).
snapshot :: proc(
	ui_proc: proc(gtx: ^ui.Ctx, user: rawptr),
	user: rawptr,
	size: ops.Size,
	fonts: []ops.Font_Ref,
	path: string,
	clear: ops.Color = {255, 255, 255, 255},
	frames: int = 1,
	dt: f32 = 1.0 / 60,
	debug: ui.Debug_Flags = {},
) -> bool {
	p: ui.Probe
	ui.probe_init(&p, ui_proc, user, size, debug = debug | ui.debug_from_env())
	defer ui.probe_destroy(&p)
	for f in fonts {
		ops.add_font(&p.scene, f.path)
	}
	r: Renderer
	init(&r)
	defer destroy(&r)
	p.shaper = shaper(&r, p.scene.fonts[:])
	ui.probe_advance(&p, frames, dt)
	return render_png(&r, ui.probe_current(&p), int(size.x), int(size.y), path, clear)
}
