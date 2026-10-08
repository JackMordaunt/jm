package scrub

import "core:fmt"
import "core:os"
import "core:strings"

import "jm:ui"
import "jm:ui/base"
import "jm:ui/design"
import "jm:ui/ops"
import "jm:ui/shell"

// Scrubber is a Tape on show: the frame shown, and the picture decoded
// for it.
Scrubber :: struct {
	tape:     ^Tape, // borrowed: the caller's, alive while the scrubber is
	path:     string, // borrowed: the recording's, for the header
	at:       int, // the moment shown
	playing:  bool,
	clock:    f64, // while playing: the recording's time reached
	dragging: bool, // the timeline is held
	shown:    int, // the picture decoded into scene and frame; -1 for none
	scene:    ops.Scene,
	frame:    ui.Frame,
	hovering: bool,
	pointer:  ops.Point, // over the picture, in the recorded frame's units
}

// SIDE_WIDTH is how wide the inspector beside the picture is.
SIDE_WIDTH :: 360
// TIMELINE_HEIGHT is how tall the timeline is.
TIMELINE_HEIGHT :: 36
// DIFFERS_COLOR marks a frame whose digest is not the blessed one.
DIFFERS_COLOR :: ops.Color{220, 40, 40, 255}
// INSPECT_COLOR outlines the widget under the pointer in the picture.
INSPECT_COLOR :: ops.Color{255, 0, 255, 200}
// PAPER is what a recorded frame is drawn over, as the headless renderer
// clears to.
PAPER :: ops.Color{255, 255, 255, 255}

// run replays the recording at path through app and opens the scrubber on
// it, returning when its window closes. Blessed digests beside the
// recording (path + ui.DIGESTS_EXT), if any, mark the frames that differ.
// It reports what went wrong on stderr and returns false.
run :: proc(app: App, path: string) -> bool {
	data, rerr := os.read_entire_file(path, context.allocator)
	if rerr != nil {
		fmt.eprintfln("scrub: cannot read %s: %v", path, rerr)
		return false
	}
	defer delete(data)
	blessed: []u64
	sums := strings.concatenate({path, ui.DIGESTS_EXT}, context.temp_allocator)
	if text, terr := os.read_entire_file(sums, context.temp_allocator); terr == nil {
		parsed, ok := ui.digests_parse(string(text))
		if !ok {
			fmt.eprintfln("scrub: %s is not a digests file; marking nothing", sums)
		}
		blessed = parsed
	}
	defer delete(blessed)

	tape: Tape
	defer tape_destroy(&tape)
	if !tape_record(&tape, app, data, blessed) {
		fmt.eprintfln("scrub: %s stops being a recording after %d frame(s)", path, len(tape.moments))
	}
	if len(tape.moments) == 0 {
		fmt.eprintfln("scrub: %s has no frames", path)
		return false
	}
	fmt.eprintfln("scrub: %d frame(s), %d picture(s)", len(tape.moments), len(tape.pictures))

	scrubber: Scrubber
	scrubber_init(&scrubber, &tape, path)
	defer scrubber_destroy(&scrubber)
	title := app.title
	if title == "" {
		title = fmt.tprintf("scrub %s", path)
	}
	shell.run({title = title, width = 1280, height = 860, ui = view, user = &scrubber, fonts = app.fonts, fallbacks = app.fallbacks})
	return true
}

// scrubber_init readies scrubber to show tape from its first frame.
scrubber_init :: proc(scrubber: ^Scrubber, tape: ^Tape, path: string) {
	scrubber^ = {tape = tape, path = path, shown = -1}
	ops.init(&scrubber.scene)
	ui.frame_init(&scrubber.frame)
}

// scrubber_destroy frees what scrubber holds; its tape is the caller's.
scrubber_destroy :: proc(scrubber: ^Scrubber) {
	ui.frame_destroy(&scrubber.frame)
	ops.destroy(&scrubber.scene)
	scrubber^ = {}
}

// scrubber_seek shows moment index, kept within the tape, and stops play.
scrubber_seek :: proc(scrubber: ^Scrubber, index: int) {
	scrubber.at = clamp(index, 0, len(scrubber.tape.moments) - 1)
	scrubber.clock = scrubber.tape.moments[scrubber.at].time
	scrubber.playing = false
}

// scrubber_moment is the moment shown.
scrubber_moment :: proc(scrubber: ^Scrubber) -> Moment {
	return scrubber.tape.moments[scrubber.at]
}

// scrubber_picture is the picture the moment shown showed.
scrubber_picture :: proc(scrubber: ^Scrubber) -> Picture {
	return scrubber.tape.pictures[scrubber_moment(scrubber).picture]
}

// scrubber_show decodes the moment shown's picture and lays it out, if it
// is not the one already.
@(private)
scrubber_show :: proc(scrubber: ^Scrubber) {
	index := scrubber_moment(scrubber).picture
	if index == scrubber.shown {
		return
	}
	kept := scrubber_picture(scrubber)
	if !ops.decode(kept.scene, &scrubber.scene) {
		ops.reset(&scrubber.scene) // the encoder's own bytes: never expected
	}
	ui.flatten(&scrubber.scene, &scrubber.frame, {0, 0, kept.size.x, kept.size.y})
	scrubber.shown = index
}

// view is the scrubber's window: the frame's numbers and input above, the
// picture with the inspector beside it, and the timeline below.
view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	scrubber := (^Scrubber)(user)
	follow_keys(gtx, scrubber)
	play(gtx, scrubber)
	scrubber_show(scrubber)

	ops.fill(gtx.scene, ops.Rect{0, 0, gtx.constraints.max.x, gtx.constraints.max.y}, base.color(.Bg))
	if ui.column(gtx, align = .Fill) {
		header(gtx, scrubber)
		ui.flexible(gtx, 1)
		if ui.row(gtx, align = .Fill) {
			ui.flexible(gtx, 1)
			picture(gtx, scrubber)
			side(gtx, scrubber)
		}
		timeline(gtx, scrubber)
	}
}

// follow_keys moves the scrubber by the keys it takes app-wide.
@(private)
follow_keys :: proc(gtx: ^ui.Ctx, scrubber: ^Scrubber) {
	area := ui.claim_id(gtx)
	for key in ([]ui.Key{.Left, .Right, .Home, .End, .Space}) {
		ui.key_interest(gtx, area, key, optional = {.Shift})
	}
	for event in ui.events(gtx, area) {
		if event.kind != .Key {
			continue
		}
		shift := .Shift in event.mods
		#partial switch event.key {
		case .Left:
			scrubber_seek(scrubber, tape_change_before(scrubber.tape, scrubber.at) if shift else scrubber.at - 1)
		case .Right:
			scrubber_seek(scrubber, tape_change_after(scrubber.tape, scrubber.at) if shift else scrubber.at + 1)
		case .Home:
			scrubber_seek(scrubber, 0)
		case .End:
			scrubber_seek(scrubber, len(scrubber.tape.moments) - 1)
		case .Space:
			if scrubber.playing {
				scrubber.playing = false
			} else {
				if scrubber.at == len(scrubber.tape.moments) - 1 {
					scrubber_seek(scrubber, 0) // from the start again
				}
				scrubber.playing = true
				scrubber.clock = scrubber_moment(scrubber).time
			}
		}
	}
}

// play moves on, while playing, to the moment the recording reached in
// the time since: at the recorded pace, a slow frame as slow as it was.
@(private)
play :: proc(gtx: ^ui.Ctx, scrubber: ^Scrubber) {
	if !scrubber.playing {
		return
	}
	scrubber.clock += f64(gtx.dt)
	last := len(scrubber.tape.moments) - 1
	for scrubber.at < last && scrubber.tape.moments[scrubber.at + 1].time <= scrubber.clock {
		scrubber.at += 1
	}
	if scrubber.at == last {
		scrubber.playing = false
		return
	}
	ui.request_frame(gtx)
}

// header is the moment's numbers on one line and its input on the next.
@(private)
header :: proc(gtx: ^ui.Ctx, scrubber: ^Scrubber) {
	moment := scrubber_moment(scrubber)
	tape := scrubber.tape
	if ui.inset(gtx, ui.pad_all(12)) {
		if ui.column(gtx, gap = 4) {
			line := fmt.tprintf(
				"frame %d of %d    %.3f s    dt %.1f ms    picture %d of %d%s",
				scrubber.at + 1,
				len(tape.moments),
				moment.time,
				moment.dt * 1000,
				moment.picture + 1,
				len(tape.pictures),
				"    playing" if scrubber.playing else "",
			)
			base.label(gtx, line)
			if tape.blessed {
				blessed := fmt.tprintf("%d frame(s) differ from %s%s", tape.differ, scrubber.path, ui.DIGESTS_EXT)
				if moment.differs {
					blessed = fmt.tprintf("this frame differs; %s", blessed)
				}
				base.label(gtx, blessed, {color = DIFFERS_COLOR if tape.differ > 0 else base.color(.Muted)})
			}
			base.label(gtx, moment.input if moment.input != "" else "no input", {color = base.color(.Muted)})
		}
	}
}

// fit is how the picture of size sits in a box of room: scaled down to
// fit, never up, and centred.
@(private)
fit :: proc(size, room: ops.Size) -> (offset: ops.Point, scale: f32) {
	scale = 1
	if size.x > 0 && size.y > 0 {
		scale = min(room.x / size.x, room.y / size.y, 1)
	}
	offset = {(room.x - size.x * scale) / 2, (room.y - size.y * scale) / 2}
	return
}

// picture draws the recorded frame shown, fitted to the room it is given,
// and tracks the pointer over it for the inspector.
@(private)
picture :: proc(gtx: ^ui.Ctx, scrubber: ^Scrubber) {
	placement := ui.widget_open(gtx)
	room := gtx.constraints.max
	kept := scrubber_picture(scrubber)
	offset, scale := fit(kept.size, room)
	for event in ui.events(gtx, placement.id) {
		#partial switch event.kind {
		case .Move, .Enter:
			scrubber.pointer = {(event.pos.x - offset.x) / scale, (event.pos.y - offset.y) / scale}
			scrubber.hovering = ops.rect_contains(ops.Rect{0, 0, kept.size.x, kept.size.y}, scrubber.pointer)
		case .Leave:
			scrubber.hovering = false
		}
	}
	scene := gtx.scene
	ops.input_area(scene, placement.id, ops.Rect{0, 0, room.x, room.y}, {.Move, .Enter, .Leave})
	ops.transform_push(scene, ops.translate(offset.x, offset.y))
	ops.transform_push(scene, ops.scale(scale, scale))
	whole := ops.Rect{0, 0, kept.size.x, kept.size.y}
	ops.clip_push(scene, whole)
	ops.fill(scene, whole, PAPER)
	ui.embed_frame(gtx, &scrubber.frame)
	if scrubber.hovering {
		got := ui.inspect_at(&scrubber.frame, scrubber.pointer)
		if got.has_box {
			ops.stroke(scene, got.box.rect, INSPECT_COLOR, {width = 2 / scale})
		} else if got.has_hit {
			ops.stroke(scene, got.hit_rect, INSPECT_COLOR, {width = 2 / scale})
		}
	}
	ops.clip_pop(scene)
	// Where the recorded window ends, when its own background is the
	// scrubber's.
	ops.stroke(scene, whole, base.color(.Outline), {width = 1 / scale})
	ops.transform_pop(scene)
	ops.transform_pop(scene)
	ui.widget_close(gtx, &placement, {size = room})
}

// side is the inspector: what is under the pointer in the picture, and
// the keys.
@(private)
side :: proc(gtx: ^ui.Ctx, scrubber: ^Scrubber) {
	if ui.sized(gtx, {min = {SIDE_WIDTH, 0}, max = {SIDE_WIDTH, ui.INF}}) {
		if ui.inset(gtx, ui.pad_all(12)) {
			if ui.column(gtx, gap = 4) {
				report := "point at the picture to inspect it"
				if scrubber.hovering {
					report = ui.inspect_report(&scrubber.frame, nil, scrubber.pointer, gtx.allocator)
				}
				for line in strings.split_lines_iterator(&report) {
					note(gtx, line, base.color(.Fg))
				}
				ui.spacer(gtx, 16)
				for help in HELP {
					note(gtx, help, base.color(.Muted))
				}
			}
		}
	}
}

// note is text wrapped to the width it is offered, so a long inspector
// line runs onto the next rather than past the window's edge.
@(private)
note :: proc(gtx: ^ui.Ctx, text: string, color: ops.Color, loc := #caller_location) {
	placement := ui.widget_open(gtx, 0, loc)
	paragraph := ui.paragraph_layout(gtx.shaper, base.font(gtx), base.theme().text_size, text, gtx.constraints.max.x, gtx.allocator)
	design.draw_paragraph(gtx, paragraph, {}, color)
	size := ui.constrain(gtx.constraints, {paragraph.width, paragraph.height})
	ops.tag(gtx.scene, placement.id, ui.frame_string(gtx, text), {0, 0, size.x, size.y})
	ui.widget_close(gtx, &placement, {size, paragraph.metrics.ascent})
}

// HELP is the keys, as the inspector lists them.
@(private)
HELP := [?]string {
	"Left, Right    a frame",
	"Shift+Left, Shift+Right    a change",
	"Home, End    the ends",
	"Space    play at the recorded pace",
	"the timeline    press or drag to seek",
}

// timeline is every moment across the window: a mark where the picture
// changed, a red one where the digest differs from the blessed one, and
// the moment shown. A press or a drag along it seeks.
@(private)
timeline :: proc(gtx: ^ui.Ctx, scrubber: ^Scrubber) {
	placement := ui.widget_open(gtx)
	width := gtx.constraints.max.x
	count := len(scrubber.tape.moments)
	x_of :: proc(index, count: int, width: f32) -> f32 {
		return (f32(index) + 0.5) / f32(count) * width
	}
	index_at :: proc(x: f32, count: int, width: f32) -> int {
		return clamp(int(x / width * f32(count)), 0, count - 1)
	}
	for event in ui.events(gtx, placement.id) {
		#partial switch event.kind {
		case .Press:
			scrubber.dragging = true
			scrubber_seek(scrubber, index_at(event.pos.x, count, width))
		case .Move:
			if scrubber.dragging {
				scrubber_seek(scrubber, index_at(event.pos.x, count, width))
			}
		case .Release, .Cancel:
			scrubber.dragging = false
		}
	}
	scene := gtx.scene
	whole := ops.Rect{0, 0, width, TIMELINE_HEIGHT}
	ops.fill(scene, whole, base.color(.Surface))
	ops.input_area(scene, placement.id, whole, {.Press, .Release, .Move}, cursor = .Pointer)
	// One mark per pixel column at most: a long recording has more frames
	// than the window has columns.
	last_change, last_differ := f32(-1), f32(-1)
	for ii in 0 ..< count {
		x := f32(int(x_of(ii, count, width)))
		if scrubber.tape.moments[ii].differs && x != last_differ {
			ops.fill(scene, ops.Rect{x, 0, 1, TIMELINE_HEIGHT}, DIFFERS_COLOR)
			last_differ = x
		} else if tape_changes(scrubber.tape, ii) && x != last_change {
			ops.fill(scene, ops.Rect{x, TIMELINE_HEIGHT / 3, 1, TIMELINE_HEIGHT / 3}, base.color(.Muted))
			last_change = x
		}
	}
	at := x_of(scrubber.at, count, width)
	ops.fill(scene, ops.Rect{at - 1, 0, 3, TIMELINE_HEIGHT}, base.color(.Fg))
	ui.widget_close(gtx, &placement, {size = {width, TIMELINE_HEIGHT}})
}
