package main

// The Input method page: fields to compose into, with what composition
// does laid bare beside them. A system input method (Mozc, Pinyin, the
// compose key) drives them as it would any field; with none installed,
// the scripted compositions play the events one would send, a step at a
// time, from buttons that take no focus, so the field keeps it as it
// does while typing.

import "core:fmt"
import "core:strings"
import "jm:ui"
import "jm:ui/base"
import "jm:ui/design"
import "jm:ui/fluent"
import "jm:ui/ops"

// Ime_Step is one event an input method sends: its preedit, with its
// caret or target clause lo to hi in bytes (-1, -1 for a caret at the
// end), or a commit, which sends text as typed and ends the preedit.
Ime_Step :: struct {
	commit: bool,
	text:   string,
	lo, hi: int,
	note:   string,
}

Composition :: struct {
	name:  string,
	steps: []Ime_Step,
}

COMPOSITIONS := [?]Composition {
	{"Japanese: かな → 仮名", {
		{false, "k", -1, -1, "romaji k, waiting for a vowel"},
		{false, "か", -1, -1, "ka becomes か"},
		{false, "かn", -1, -1, "n waits too"},
		{false, "かな", -1, -1, "na becomes な"},
		{false, "仮名", 0, 6, "Space converts; the clause is the target"},
		{true, "仮名", 0, 0, "Enter commits"},
	}},
	{"Japanese: three clauses", {
		{false, "きょうはいいてんき", -1, -1, "typed in kana"},
		{false, "今日はいい天気", 0, 9, "converted; 今日は is the target clause"},
		{false, "今日はいい天気", 9, 15, "Right moves the target to いい"},
		{false, "今日はいい天気", 15, 21, "and to 天気"},
		{true, "今日はいい天気", 0, 0, "Enter commits the sentence"},
	}},
	{"Korean: syllable by syllable", {
		{false, "ㅎ", -1, -1, "a consonant"},
		{false, "하", -1, -1, "a vowel joins it"},
		{false, "한", -1, -1, "a final consonant"},
		{true, "한", 0, 0, "the next jamo commits the syllable"},
		{false, "ㄱ", -1, -1, "and starts the next"},
		{false, "그", -1, -1, ""},
		{false, "글", -1, -1, ""},
		{true, "글", 0, 0, "Space commits"},
	}},
	{"Cancelled", {
		{false, "へんかん", -1, -1, "typed in kana"},
		{false, "変換", 0, 6, "converted"},
		{false, "", -1, -1, "Escape cancels: nothing is committed"},
	}},
}

// IME_FIELDS are the fields to compose into: a label above each, its own
// name in text, which a probe clicks it by.
IME_FIELDS := [?]Sample {
	{"Japanese, Chinese or Korean", "CJK field", .CJK},
	{"Latin: try the compose key (CapsLock a a is å on this machine's Hyprland)", "Latin field", .Latin},
}

// Ime_Lab is the page's state: its fields, the field last focused, and
// how far each composition has played.
Ime_Lab :: struct {
	fields:   [len(IME_FIELDS)]ui.Text_State,
	area:     ui.Text_State, // a textarea, for a caret on a later line
	ids:      [len(IME_FIELDS) + 1]ops.Area_Id,
	focus:    int, // index into the fields, len(fields) for the textarea; -1 for none
	played:   [len(COMPOSITIONS)]int, // steps sent of each
	seen:     ui.Text_Input, // the input method as last drawn
}

// IME_RECT outlines the rect the input method was told to leave clear,
// and ticks the caret offset it was given (ui.Text_Input).
IME_RECT :: ops.Color{209, 52, 56, 200}

page_ime :: proc(gtx: ^ui.Ctx, m: ^Model) {
	lab := &m.ime
	s := fluent.scheme()
	ui.column(gtx, gap = 16)
	note(gtx, "Compose with a system input method, or focus a field and step through a scripted composition.")
	note(gtx, "The preedit is underlined, its target clause thicker; the red box is what the input method must leave clear, ticked at the caret.")
	lab.focus = -1
	for sm, i in IME_FIELDS {
		ui.column(gtx, gap = 4, key = u64(i))
		base.label(gtx, sm.label, {size = 12, color = s[.Neutral_Foreground2]})
		prev := swap_font(gtx, m.font[sm.script])
		r := fluent.input(gtx, &lab.fields[i], width = 480, name = sm.text, key = u64(i))
		swap_font(gtx, prev)
		lab.ids[i] = r.id
		if r.focused {
			lab.focus = i
		}
	}
	{
		ui.column(gtx, gap = 4)
		base.label(gtx, "A textarea: the box follows the caret's line", {size = 12, color = s[.Neutral_Foreground2]})
		prev := swap_font(gtx, m.font[.CJK])
		r := fluent.textarea(gtx, &lab.area, width = 480, name = "Textarea field")
		swap_font(gtx, prev)
		lab.ids[len(IME_FIELDS)] = r.id
		if r.focused {
			lab.focus = len(IME_FIELDS)
		}
	}
	ime_scripts(gtx, m)
	ime_inspector(gtx, m)
	draw_ime_overlay(gtx)
	// The router asks the input method after the frame is laid out, so
	// what this frame drew of it is the last frame's; one more catches up.
	if ime := ui.input_method(gtx); ime != lab.seen {
		lab.seen = ime
		ui.request_frame(gtx)
	}
}

// ime_state is the Text_State of the field that has focus, nil for none.
ime_state :: proc(lab: ^Ime_Lab) -> ^ui.Text_State {
	switch {
	case lab.focus < 0:
		return nil
	case lab.focus < len(lab.fields):
		return &lab.fields[lab.focus]
	}
	return &lab.area
}

// ime_scripts is a row per composition: its name, its next step and a
// button that sends it to the focused field.
ime_scripts :: proc(gtx: ^ui.Ctx, m: ^Model) {
	lab := &m.ime
	s := fluent.scheme()
	ui.column(gtx, gap = 8)
	base.label(gtx, "Scripted compositions", {size = 16, color = s[.Neutral_Foreground1]})
	if lab.focus < 0 {
		note(gtx, "Focus a field first: the steps go where a keyboard's would.")
	}
	for c, i in COMPOSITIONS {
		ui.row(gtx, gap = 12, align = .Center, key = u64(i))
		played := lab.played[i]
		done := played >= len(c.steps)
		label := "Again" if done else fmt.tprintf("Step %d of %d", played + 1, len(c.steps))
		if step_button(gtx, m, label, fmt.tprintf("step %s", c.name), lab.focus >= 0, key = u64(i)) {
			if done {
				played = 0
			}
			ime_send(gtx, c.steps[played])
			lab.played[i] = played + 1
		}
		base.label(gtx, c.name, {size = 13, color = s[.Neutral_Foreground1]})
		next := "" if done else describe_step(c.steps[played])
		base.label(gtx, next, {size = 12, color = s[.Neutral_Foreground3]})
	}
}

// ime_send queues step for the focused area through the router, as
// ui/shell queues SDL's: it arrives with the next frame.
ime_send :: proc(gtx: ^ui.Ctx, step: Ime_Step) {
	if step.commit {
		ui.router_push(gtx.router, {kind = .Text, text = step.text})
		ui.router_push(gtx.router, {kind = .Compose})
		return
	}
	lo, hi := step.lo, step.hi
	if lo < 0 {
		lo, hi = len(step.text), len(step.text)
	}
	ui.router_push(gtx.router, {kind = .Compose, text = step.text, span = {lo, hi}})
}

describe_step :: proc(step: Ime_Step) -> string {
	if step.commit {
		return fmt.tprintf("next: commit “%s” · %s", step.text, step.note)
	}
	if step.lo >= 0 && step.lo < step.hi {
		return fmt.tprintf("next: preedit “%s”, target “%s” · %s", step.text, step.text[step.lo:step.hi], step.note)
	}
	if step.text == "" {
		return fmt.tprintf("next: end the preedit · %s", step.note)
	}
	return fmt.tprintf("next: preedit “%s” · %s", step.text, step.note)
}

// ime_inspector shows, for the focused field, the committed text, the
// text as shown with the preedit marked, and what the input method was
// last asked for.
ime_inspector :: proc(gtx: ^ui.Ctx, m: ^Model) {
	lab := &m.ime
	s := fluent.scheme()
	ui.column(gtx, gap = 4)
	base.label(gtx, "Inspector", {size = 16, color = s[.Neutral_Foreground1]})
	line :: proc(gtx: ^ui.Ctx, text: string) {
		base.label(gtx, text, {size = 13, color = fluent.scheme()[.Neutral_Foreground2]})
	}
	if st := ime_state(lab); st != nil {
		shown := ui.text_display(st, gtx.allocator)
		line(gtx, fmt.tprintf("committed  “%s”, caret at byte %d", ui.text_string(st), st.cursor))
		line(gtx, fmt.tprintf("shown      %s", marked(shown, gtx.allocator)))
		if ui.text_composing(st) {
			line(gtx, fmt.tprintf("preedit    bytes %d to %d, target %d to %d, caret %d", shown.pre_lo, shown.pre_hi, shown.target_lo, shown.target_hi, shown.caret))
		} else {
			line(gtx, "preedit    none")
		}
	} else {
		line(gtx, "no field has focus")
	}
	ime := ui.input_method(gtx)
	if ime.active {
		r := ime.rect
		line(gtx, fmt.tprintf("input method  on for area %x, %v; rect %.0f,%.0f %.0fx%.0f px, caret %.0f px in", u64(ime.area), ime.kind, r.x, r.y, r.w, r.h, ime.caret))
	} else {
		line(gtx, "input method  off")
	}
}

// marked is shown's text with its preedit in [ ] and the target clause
// in ‹ ›.
marked :: proc(shown: ui.Text_Display, allocator := context.temp_allocator) -> string {
	text := shown.text
	if shown.pre_lo == shown.pre_hi {
		return fmt.aprintf("“%s”", text, allocator = allocator)
	}
	b := strings.builder_make(allocator)
	strings.write_string(&b, "“")
	strings.write_string(&b, text[:shown.pre_lo])
	strings.write_string(&b, "[")
	if shown.target_lo < shown.target_hi {
		strings.write_string(&b, text[shown.pre_lo:shown.target_lo])
		strings.write_string(&b, "‹")
		strings.write_string(&b, text[shown.target_lo:shown.target_hi])
		strings.write_string(&b, "›")
		strings.write_string(&b, text[shown.target_hi:shown.pre_hi])
	} else {
		strings.write_string(&b, text[shown.pre_lo:shown.pre_hi])
	}
	strings.write_string(&b, "]")
	strings.write_string(&b, text[shown.pre_hi:])
	strings.write_string(&b, "”")
	return strings.to_string(b)
}

// draw_ime_overlay outlines, over the whole window, the rect the input
// method was told to leave clear and ticks its caret, in a layer from the
// window's top-left; the rect is in device pixels, the layer in dp.
draw_ime_overlay :: proc(gtx: ^ui.Ctx) {
	ime := ui.input_method(gtx)
	if !ime.active {
		return
	}
	layer := ui.overlay_open(gtx, root = true, top = true)
	defer ui.overlay_close(&layer)
	density := gtx.density if gtx.density > 0 else 1
	r := ops.Rect{ime.rect.x / density, ime.rect.y / density, ime.rect.w / density, ime.rect.h / density}
	ops.stroke(gtx.scene, r, IME_RECT, {width = 1})
	x := r.x + ime.caret / density
	ops.fill(gtx.scene, ops.Rect{x - 1, r.y + r.h - 6, 2, 10}, IME_RECT)
}

// step_button is a button that takes no focus: a press on it leaves the
// field focused, so the steps go where typing would.
// It reports a click; disabled, it draws dimmed and takes none. It is
// tagged name, for a probe to click.
step_button :: proc(gtx: ^ui.Ctx, m: ^Model, label, name: string, enabled: bool, key: u64, loc := #caller_location) -> bool {
	s := fluent.scheme()
	p := ui.widget_open(gtx, key, loc)
	text := ui.paragraph_layout(gtx.shaper, m.font[.UI], 13, label, 0, gtx.allocator)
	size := ops.Size{max(text.width + 24, 110), 28}
	bounds := ops.Rect{0, 0, size.x, size.y}
	c := design.control(gtx, p.id, bounds, .Live if enabled else .Disabled)
	fill := s[.Neutral_Background1]
	if c.pressed {
		fill = s[.Neutral_Background1_Pressed]
	} else if c.hovered {
		fill = s[.Neutral_Background1_Hover]
	}
	ops.fill(gtx.scene, ops.Round_Rect{bounds, 4}, fill)
	ops.stroke(gtx.scene, ops.Round_Rect{bounds, 4}, s[.Neutral_Stroke1], {width = 1})
	ui.paragraph_draw(gtx.scene, text, {(size.x - text.width) / 2, (size.y - text.height) / 2}, s[.Neutral_Foreground1] if enabled else s[.Neutral_Foreground_Disabled])
	design.listen(gtx, c.st, p.id, bounds, {.Press, .Release, .Enter, .Leave, .Move})
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, name))
	ui.widget_close(gtx, &p, {size, size.y / 2 + text.metrics.ascent / 2})
	return c.clicked
}
