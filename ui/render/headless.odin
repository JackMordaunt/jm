package render

import "core:fmt"
import "jm:ui/ops"
import "core:mem"
import "core:os"
import "core:reflect"
import "core:strconv"
import "core:strings"

import bl "jm:ui/blend2d"
import "jm:ui"

// Headless drives a ui proc with no window, for one scripted session: a
// single probe, shaping real text, that every step acts on in turn, so a
// click, a scroll or a key press is still in effect when a later step
// renders or dumps the frame. snapshot is the one-shot form of it.
Headless :: struct {
	p:     ui.Probe,
	r:     Renderer,
	fonts: []ops.Font_Ref,
	full:  bool, // laid out FULL_HEIGHT tall, and the PNG trimmed to its content
	clear: ops.Color,
}

// FULL_HEIGHT is how tall a full session lays the ui out: tall enough that
// a page's scroll box shows all of it, trimmed back when it is written.
FULL_HEIGHT :: f32(16000)

// headless_init opens a session of ui_proc(gtx, user) at size, in fonts
// (fonts must outlive it). debug joins what JM_UI_DEBUG asks for. full
// lays it out FULL_HEIGHT tall so nothing scrolls, and headless_png trims
// the empty rows off the bottom. It runs one frame in real text.
headless_init :: proc(
	h: ^Headless,
	ui_proc: proc(gtx: ^ui.Ctx, user: rawptr),
	user: rawptr,
	size: ops.Size,
	fonts: []ops.Font_Ref,
	debug: ui.Debug_Flags = {},
	full := false,
	clear: ops.Color = {255, 255, 255, 255},
	fallbacks: []ops.Font_Id = nil,
) {
	h.fonts, h.full, h.clear = fonts, full, clear
	at := size
	if full {
		at.y = FULL_HEIGHT
	}
	ui.probe_init(&h.p, ui_proc, user, at, debug = debug | ui.debug_from_env())
	ops.add_fonts(&h.p.scene, fonts)
	init(&h.r)
	h.p.shaper = shaper(&h.r, h.p.scene.fonts[:], fallbacks)
	// probe_init's frame shaped with the stub; lay out again in real text.
	ui.probe_frame(&h.p)
}

// headless_destroy frees everything h owns.
headless_destroy :: proc(h: ^Headless) {
	destroy(&h.r)
	ui.probe_destroy(&h.p)
}

// headless_png writes the current frame to path. A full session's image
// is cut just below its content: every row from the bottom up that is the
// same as the last row is dropped, keeping a 24px margin.
headless_png :: proc(h: ^Headless, path: string) -> bool {
	w, ht := int(h.p.size.x), int(h.p.size.y)
	img: bl.ImageCore
	bl.image_init(&img)
	defer bl.image_destroy(&img)
	if bl.image_create(&img, i32(w), i32(ht), .PRGB32) != 0 {
		return false
	}
	render(&h.r, ui.probe_current(&h.p), &img, h.clear)
	out := &img
	trimmed: bl.ImageCore
	bl.image_init(&trimmed)
	defer bl.image_destroy(&trimmed)
	if h.full {
		data: bl.ImageData
		if bl.image_get_data(&img, &data) != 0 {
			return false
		}
		keep := content_rows(data, w, ht) + 24
		if keep < ht {
			// The same pixels, fewer rows: no copy.
			if bl.image_create_from_data(&trimmed, i32(w), i32(keep), .PRGB32, data.pixel_data, data.stride, .READ, nil, nil) != 0 {
				return false
			}
			out = &trimmed
		}
	}
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	return bl.image_write_to_file(out, cpath, nil) == 0
}

// content_rows is how many rows from the top hold anything: the image's
// height less the run of rows at the bottom identical to its last row.
@(private = "file")
content_rows :: proc(data: bl.ImageData, w, h: int) -> int {
	row :: proc(data: bl.ImageData, y, w: int) -> []u8 {
		base := uintptr(data.pixel_data) + uintptr(y * int(data.stride))
		return mem.slice_ptr((^u8)(rawptr(base)), w * 4)
	}
	last := row(data, h - 1, w)
	y := h - 1
	for y > 0 && mem.compare(row(data, y - 1, w), last) == 0 {
		y -= 1
	}
	return y
}

// inspecting turns Debug_Flag.Inspect on for h and, if the current frame
// was recorded without it, runs one so the frame has its layout boxes.
@(private = "file")
inspecting :: proc(h: ^Headless) {
	if .Inspect not_in h.p.debug {
		h.p.debug += {.Inspect}
		ui.probe_frame(&h.p)
	}
}

// headless_step runs the session step at args[i^], advancing i^ past its
// arguments. It returns handled false for an argument that is not a step,
// for the caller's own flags, and ok false, with a message printed, for a
// step that failed. The steps:
//
//	-click NAME        press and release the area tagged NAME
//	-drag NAME DX DY   press on NAME, move the pointer by DX, DY over four
//	                   frames, release
//	-scroll NAME DY    scroll DY notches over NAME (positive is down)
//	-key KEY           press KEY (a ui.Key name: Enter, Tab, Down, A, ...),
//	                   with modifiers before it joined by +: Shift+Left,
//	                   Shortcut+A (Cmd on macOS, Ctrl elsewhere), Word+Right
//	-move X Y          move the pointer to X, Y
//	-hover NAME        move the pointer to the middle of the area tagged NAME
//	-advance N         run N frames at 1/60 s
//	-replay PATH       run every frame of a recording (ui.RECORD_ENV)
//	-png PATH          write the current frame
//	-dump              print the current frame's sc as text
//	-overflow          print what the window or a clip cuts off at the sides
//	-layout            print every widget's box, constraints and call
//	-semantics         print the frame's semantic tree, as a screen
//	                   reader would read it
//	-stats             print the last frame's timings, counts and memory
//	-events            print the routed events the session logged
//	-inspect X Y       print the widget and input area under X, Y
headless_step :: proc(h: ^Headless, args: []string, i: ^int) -> (handled, ok: bool) {
	need :: proc(args: []string, i: ^int, n: int, flag: string) -> bool {
		if i^ + n >= len(args) {
			fmt.eprintfln("%s needs %d argument(s)", flag, n)
			return false
		}
		return true
	}
	flag := args[i^]
	switch flag {
	case "-click":
		if !need(args, i, 1, flag) {
			return true, false
		}
		i^ += 1
		if !ui.probe_click(&h.p, args[i^]) {
			fmt.eprintfln("no %q to click", args[i^])
			return true, false
		}
		ui.probe_frame(&h.p)
	case "-drag":
		if !need(args, i, 3, flag) {
			return true, false
		}
		dx, dx_ok := strconv.parse_f32(args[i^ + 2])
		dy, dy_ok := strconv.parse_f32(args[i^ + 3])
		if !dx_ok || !dy_ok {
			fmt.eprintfln("-drag: %q %q are not numbers", args[i^ + 2], args[i^ + 3])
			return true, false
		}
		if !ui.probe_drag(&h.p, args[i^ + 1], dx, dy) {
			fmt.eprintfln("no %q to drag", args[i^ + 1])
			return true, false
		}
		i^ += 3
	case "-scroll":
		if !need(args, i, 2, flag) {
			return true, false
		}
		dy, dy_ok := strconv.parse_f32(args[i^ + 2])
		if !dy_ok {
			fmt.eprintfln("-scroll: %q is not a number", args[i^ + 2])
			return true, false
		}
		if !ui.probe_scroll(&h.p, args[i^ + 1], dy) {
			fmt.eprintfln("no %q to scroll", args[i^ + 1])
			return true, false
		}
		i^ += 2
	case "-key":
		if !need(args, i, 1, flag) {
			return true, false
		}
		i^ += 1
		key, mods, key_ok := parse_chord(args[i^])
		if !key_ok {
			fmt.eprintfln("-key: no key %q", args[i^])
			return true, false
		}
		ui.probe_key(&h.p, key, mods)
	case "-move":
		if !need(args, i, 2, flag) {
			return true, false
		}
		x, x_ok := strconv.parse_f32(args[i^ + 1])
		y, y_ok := strconv.parse_f32(args[i^ + 2])
		if !x_ok || !y_ok {
			fmt.eprintfln("-move: %q %q are not numbers", args[i^ + 1], args[i^ + 2])
			return true, false
		}
		ui.probe_move(&h.p, x, y)
		i^ += 2
	case "-hover":
		if !need(args, i, 1, flag) {
			return true, false
		}
		i^ += 1
		c, found := ui.probe_center(&h.p, args[i^])
		if !found {
			fmt.eprintfln("no %q to hover", args[i^])
			return true, false
		}
		ui.probe_move(&h.p, c.x, c.y)
	case "-advance":
		if !need(args, i, 1, flag) {
			return true, false
		}
		i^ += 1
		n, n_ok := strconv.parse_int(args[i^])
		if !n_ok || n < 1 {
			fmt.eprintfln("-advance: %q is not a frame count", args[i^])
			return true, false
		}
		ui.probe_advance(&h.p, n, 1.0 / 60)
	case "-replay":
		if !need(args, i, 1, flag) {
			return true, false
		}
		i^ += 1
		data, rerr := os.read_entire_file(args[i^], context.temp_allocator)
		if rerr != nil {
			fmt.eprintfln("-replay: cannot read %s: %v", args[i^], rerr)
			return true, false
		}
		frames, rok := ui.probe_replay(&h.p, data)
		if !rok {
			fmt.eprintfln("-replay: %s stops being a recording after %d frame(s)", args[i^], frames)
			return true, false
		}
	case "-png":
		if !need(args, i, 1, flag) {
			return true, false
		}
		i^ += 1
		if !headless_png(h, args[i^]) {
			fmt.eprintfln("could not write %s", args[i^])
			return true, false
		}
	case "-dump":
		fmt.print(ui.probe_dump(&h.p))
	case "-overflow":
		fmt.print(ui.overflow_report(ui.probe_current(&h.p), h.p.size, context.temp_allocator))
	case "-events":
		fmt.print(ui.event_log_report(&h.p.tray, context.temp_allocator))
	case "-stats":
		fmt.print(ui.frame_stats_report(h.p.tray.last, context.temp_allocator))
	case "-semantics":
		fmt.print(ui.probe_semantics(&h.p, context.temp_allocator))
	case "-layout":
		inspecting(h)
		fmt.print(ui.layout_report(ui.probe_current(&h.p), context.temp_allocator))
	case "-inspect":
		if !need(args, i, 2, flag) {
			return true, false
		}
		x, x_ok := strconv.parse_f32(args[i^ + 1])
		y, y_ok := strconv.parse_f32(args[i^ + 2])
		if !x_ok || !y_ok {
			fmt.eprintfln("-inspect: %q %q are not numbers", args[i^ + 1], args[i^ + 2])
			return true, false
		}
		inspecting(h)
		fmt.print(ui.inspect_report(ui.probe_current(&h.p), &h.p.layout, {x, y}, context.temp_allocator))
		i^ += 2
	case:
		return false, true
	}
	return true, true
}

// parse_chord reads a -key argument: a ui.Key name, after any modifiers
// joined by +, each a ui.Mod name or Shortcut or Word for ui.SHORTCUT and
// ui.WORD_MOD.
@(private = "file")
parse_chord :: proc(arg: string) -> (key: ui.Key, mods: ui.Mods, ok: bool) {
	rest := arg
	for {
		part, _, after := strings.partition(rest, "+")
		if after == "" && !strings.contains(rest, "+") {
			return reflect.enum_from_name(ui.Key, part) or_return, mods, true
		}
		switch part {
		case "Shortcut":
			mods += {ui.SHORTCUT}
		case "Word":
			mods += {ui.WORD_MOD}
		case:
			mods += {reflect.enum_from_name(ui.Mod, part) or_return}
		}
		rest = after
	}
}
