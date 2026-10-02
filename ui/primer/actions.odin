package primer

import "base:runtime"
import "core:strings"
import "jm:ui"
import "jm:ui/design"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// Link is inline navigational text (primer-kit link.json,
// Link.module.css): --fgColor-accent, underlined on hover; muted is
// --fgColor-muted turning accent on hover with no underline. It has no box
// and takes the size of the text around it (size). Primer draws no focus
// style and leaves the browser's ring; this draws Button's link outline,
// 2px outside (link.json notes, inferred). Returns true when activated.
link :: proc(gtx: ^ui.Ctx, label: string, muted := false, size := tok.TEXT_BODY_SIZE_MEDIUM, state := Interaction.Live, key: u64 = 0, loc := #caller_location) -> bool {
	p := ui.widget_open(gtx, key, loc)
	st := tok.Type_Style{weight = tok.BASE_TEXT_WEIGHT_NORMAL, size = size, line_height = size * tok.TEXT_BODY_LINE_HEIGHT_MEDIUM}
	t := design.shape_style(gtx, label, st, font_for(gtx, st.weight))
	sz := ui.constrain_min(gtx.constraints, {t.width, st.line_height})
	area := ops.Rect{0, 0, sz.x, sz.y}
	c := control(gtx, p.id, area, state)
	y := (sz.y - t.height) / 2
	fg, underline := link_look(c, muted, false)
	draw_text(gtx, t, {0, y}, fg)
	if underline {
		paint_underline(gtx, {0, y + baseline_of(t)}, t.width, fg)
	}
	paint_focus_outline(gtx, c, {area, 0}, LINK_FOCUS_OFFSET)
	listen(gtx, c.st, p.id, area, cursor = .Pointer)
	said := ui.frame_string(gtx, label)
	ops.tag(gtx.scene, p.id, said)
	ui.semantics(gtx, &p, {role = .Link, label = said})
	ui.widget_close(gtx, &p, {sz, y + baseline_of(t)})
	return c.clicked
}

// link_look is a link's colour and whether it is underlined in c's
// state: accent, underlined on hover; muted, accent on hover with no
// underline; inline under the user's link-underline preference, underlined
// at rest and not on hover (link.json states).
@(private)
link_look :: proc(c: Control, muted, underlines: bool) -> (fg: ops.Color, underline: bool) {
	hot := c.hovered && !c.disabled
	if muted {
		return color(hot ? .Fg_Color_Accent : .Fg_Color_Muted), false
	}
	return color(.Fg_Color_Accent), hot != underlines
}

// paint_underline draws a 1px rule width long under a baseline at pos,
// offset 0.05rem below the default position (Link.module.css:4). jm:ui
// reads no underline metric from the font, so the default is taken as
// 1px under the baseline.
@(private)
paint_underline :: proc(gtx: ^ui.Ctx, pos: ops.Point, width: f32, c: ops.Color) {
	OFFSET :: 1 + 0.05 * 16
	ops.fill(gtx.scene, ops.Rect{pos.x, pos.y + OFFSET, width, tok.BORDER_WIDTH_THIN}, c)
}

// Link_Span is a link inside prose: the bytes [lo, hi) of the text.
Link_Span :: struct {
	lo, hi: int,
}

// prose is a paragraph of body text wrapped at the width offered, in which
// each of links is an inline link: accent, underlined on hover (or at rest
// and not on hover with underlines, the user's link-underline preference),
// hit-tested on the line fragments it wraps across (link.json notes). It
// returns the index of the link activated this frame, or -1.
prose :: proc(gtx: ^ui.Ctx, text: string, links: []Link_Span, underlines := false, role := Type_Role.Body_Medium, key: u64 = 0, loc := #caller_location) -> int {
	p := ui.widget_open(gtx, key, loc)
	st := style(role)
	para := design.layout_style(gtx, text, st, font_for(gtx, st.weight), gtx.constraints.max.x)
	sz := ui.constrain_min(gtx.constraints, {para.width, para.height})
	ui.paragraph_draw(gtx.scene, para, {}, color(.Fg_Color_Default))
	picked := -1
	for l, i in links {
		id := ui.id_mix(p.id, u64(i))
		rects := ui.paragraph_selection_rects(para, l.lo, l.hi, gtx.allocator)
		c := control(gtx, id, rects_bounds(rects), .Live)
		fg, underline := link_look(c, false, underlines)
		for r in rects {
			ops.clip_push(gtx.scene, r)
			ui.paragraph_draw(gtx.scene, para, {}, fg)
			ops.clip_pop(gtx.scene)
			if underline {
				paint_underline(gtx, {r.x, baseline_in(para, r)}, r.w, fg)
			}
			ops.input_area(gtx.scene, id, r, CLICK_KINDS, .Pointer)
		}
		if c.clicked {
			picked = i
		}
		ui.semantics(gtx, &p, {role = .Link, label = ui.frame_string(gtx, text[l.lo:l.hi])})
	}
	ui.widget_close(gtx, &p, {sz, para.lines[0].baseline if len(para.lines) > 0 else 0})
	return picked
}

// baseline_in is the baseline of the line r covers in para: lines'
// baselines are measured from the paragraph's top, as r is.
@(private)
baseline_in :: proc(para: ui.Paragraph, r: ops.Rect) -> f32 {
	for ln in para.lines {
		if ln.baseline >= r.y && ln.baseline <= r.y + r.h {
			return ln.baseline
		}
	}
	return r.y + r.h
}

// rects_bounds is the box around rects.
@(private)
rects_bounds :: proc(rects: []ops.Rect) -> ops.Rect {
	if len(rects) == 0 {
		return {}
	}
	b := rects[0]
	for r in rects[1:] {
		x0, y0 := min(b.x, r.x), min(b.y, r.y)
		b = {x0, y0, max(b.x + b.w, r.x + r.w) - x0, max(b.y + b.h, r.y + r.h) - y0}
	}
	return b
}

// Platform is how a keyboard hint names platform keys (KeybindingHint
// platform.ts): apple for macOS and iOS, windows, or other.
Platform :: enum u8 {
	Apple,
	Windows,
	Other,
}

// PLATFORM is the platform this program was built for.
PLATFORM :: Platform.Apple when ODIN_OS == .Darwin else Platform.Windows when ODIN_OS == .Windows else Platform.Other

// Hint_Format is how keys are written: condensed symbols or full words.
Hint_Format :: enum u8 {
	Condensed,
	Full,
}

// Hint_Variant is a key cap's colouring: on a plain surface, inside an
// emphasis surface (a tooltip), or on a primary button.
Hint_Variant :: enum u8 {
	Normal,
	On_Emphasis,
	On_Primary,
}

// Hint_Size is a key cap's size: 20px or 14px tall.
Hint_Size :: enum u8 {
	Normal,
	Small,
}

// MAX_HINT_KEYS bounds the keys a chord holds and the chords a sequence
// holds; a shortcut longer than that is not one a person types.
MAX_HINT_KEYS :: 8

// hint_chords splits a sequence into its chords at spaces and each chord
// into its keys at +, lower-cased and sorted modifiers first: control,
// meta, alt, option, shift, function, then the rest as given
// (KeybindingHint components/utils.ts:9-28). Strings live in allocator.
hint_chords :: proc(keys: string, allocator := context.temp_allocator) -> (chords: [MAX_HINT_KEYS][MAX_HINT_KEYS]string, lens: [MAX_HINT_KEYS]int, n: int) {
	priority :: proc(k: string) -> int {
		switch k {
		case "control":
			return 1
		case "meta":
			return 2
		case "alt":
			return 3
		case "option":
			return 4
		case "shift":
			return 5
		case "function":
			return 6
		}
		return 7
	}
	rest := keys
	for chord in strings.split_iterator(&rest, " ") {
		if n == MAX_HINT_KEYS {
			break
		}
		c := chord
		for k in strings.split_iterator(&c, "+") {
			if lens[n] == MAX_HINT_KEYS {
				break
			}
			chords[n][lens[n]] = strings.to_lower(k, allocator)
			lens[n] += 1
		}
		// A stable insertion sort: equal priorities keep their order.
		ks := chords[n][:lens[n]]
		for i in 1 ..< len(ks) {
			for j := i; j > 0 && priority(ks[j]) < priority(ks[j - 1]); j -= 1 {
				ks[j], ks[j - 1] = ks[j - 1], ks[j]
			}
		}
		n += 1
	}
	return
}

// capitalised is s with its first letter upper case and the rest lower.
@(private)
capitalised :: proc(s: string, allocator: runtime.Allocator) -> string {
	if s == "" {
		return s
	}
	return strings.concatenate({strings.to_upper(s[:1], allocator), strings.to_lower(s[1:], allocator)}, allocator)
}

// key_label is how key is written in format on platform (KeybindingHint
// key-names.ts:14-58).
key_label :: proc(key: string, format: Hint_Format, platform := PLATFORM, allocator := context.temp_allocator) -> string {
	apple, windows := platform == .Apple, platform == .Windows
	if format == .Full {
		switch key {
		case "alt":
			return apple ? "Option" : "Alt"
		case "meta":
			return apple ? "Command" : windows ? "Windows" : "Meta"
		case "mod":
			return apple ? "Command" : "Control"
		case "+":
			return "Plus"
		case "pageup":
			return "Page Up"
		case "pagedown":
			return "Page Down"
		case "arrowup":
			return "Up Arrow"
		case "arrowdown":
			return "Down Arrow"
		case "arrowleft":
			return "Left Arrow"
		case "arrowright":
			return "Right Arrow"
		case "capslock":
			return "Caps Lock"
		case "printscreen":
			return "Print Screen"
		}
		return capitalised(key, allocator)
	}
	switch key {
	case "alt":
		return apple ? "⌥" : "Alt"
	case "control":
		return "⌃"
	case "shift":
		return "⇧"
	case "meta":
		return apple ? "⌘" : windows ? "Win" : "Meta"
	case "mod":
		return apple ? "⌘" : "⌃"
	case "pageup":
		return "PgUp"
	case "pagedown":
		return "PgDn"
	case "arrowup":
		return "↑"
	case "arrowdown":
		return "↓"
	case "arrowleft":
		return "←"
	case "arrowright":
		return "→"
	case "plus":
		return "+"
	case "backspace":
		return "⌫"
	case "delete":
		return "Del"
	case "space":
		return "␣"
	case "tab":
		return "⇥"
	case "enter":
		return "⏎"
	case "escape":
		return "Esc"
	case "function":
		return "Fn"
	case "capslock":
		return "CapsLock"
	case "insert":
		return "Ins"
	case "printscreen":
		return "PrtScn"
	}
	return capitalised(key, allocator)
}

// spoken_key is key's name as a screen reader should say it: words, not
// symbols (KeybindingHint key-names.ts:65-116).
spoken_key :: proc(key: string, platform := PLATFORM, allocator := context.temp_allocator) -> string {
	apple, windows := platform == .Apple, platform == .Windows
	switch key {
	case "alt":
		return apple ? "option" : "alt"
	case "meta":
		return apple ? "command" : windows ? "Windows" : "meta"
	case "mod":
		return apple ? "command" : "control"
	case "pageup":
		return "page up"
	case "pagedown":
		return "page down"
	case "arrowup":
		return "up arrow"
	case "arrowdown":
		return "down arrow"
	case "arrowleft":
		return "left arrow"
	case "arrowright":
		return "right arrow"
	case "capslock":
		return "caps lock"
	case "printscreen":
		return "print screen"
	case "`":
		return "backtick"
	case "~":
		return "tilde"
	case "!":
		return "exclamation point"
	case "@":
		return "at"
	case "#":
		return "hash"
	case "$":
		return "dollar sign"
	case "%":
		return "percent"
	case "^":
		return "caret"
	case "&":
		return "ampersand"
	case "*":
		return "asterisk"
	case "(":
		return "left parenthesis"
	case ")":
		return "right parenthesis"
	case "_":
		return "underscore"
	case "-":
		return "dash"
	case "+":
		return "plus"
	case "=":
		return "equals"
	case "[":
		return "left bracket"
	case "{":
		return "left curly brace"
	case "]":
		return "right bracket"
	case "}":
		return "right curly brace"
	case "\\":
		return "backslash"
	case "|":
		return "pipe"
	case ";":
		return "semicolon"
	case ":":
		return "colon"
	case "'":
		return "single quote"
	case "\"":
		return "double quote"
	case ",":
		return "comma"
	case "<":
		return "left angle bracket"
	case ".":
		return "period"
	case ">":
		return "right angle bracket"
	case "/":
		return "forward slash"
	case "?":
		return "question mark"
	case " ":
		return "space"
	}
	return strings.to_lower(key, allocator)
}

// spoken_hint is keys as one accessible string: a chord's keys spoken and
// separated by spaces, chords by "then" (components/utils.ts:30-41).
spoken_hint :: proc(keys: string, platform := PLATFORM, allocator := context.temp_allocator) -> string {
	chords, lens, n := hint_chords(keys, allocator)
	b := strings.builder_make(allocator)
	for ci in 0 ..< n {
		if ci > 0 {
			strings.write_string(&b, " then ")
		}
		for ki in 0 ..< lens[ci] {
			if ki > 0 {
				strings.write_byte(&b, ' ')
			}
			strings.write_string(&b, spoken_key(chords[ci][ki], platform, allocator))
		}
	}
	return strings.to_string(b)
}

// Hint_Cap is one size's key cap: padding, line box, text size, minimum
// width and corner radius (Chord.module.css:1-48).
@(private)
Hint_Cap :: struct {
	pad, line, text, min_w, radius: f32,
}

@(private)
hint_cap :: proc(variant: Hint_Variant, size: Hint_Size) -> Hint_Cap {
	if size == .Small {
		return {tok.BASE_SIZE_2, tok.BASE_SIZE_8, 11, tok.BASE_SIZE_16, tok.BORDER_RADIUS_SMALL}
	}
	if variant == .Normal {
		return {tok.BASE_SIZE_4, 10, tok.TEXT_BODY_SIZE_SMALL, tok.BASE_SIZE_20, tok.BORDER_RADIUS_MEDIUM}
	}
	return {tok.BASE_SIZE_4, 10, tok.TEXT_BODY_SIZE_SMALL, 0, tok.BORDER_RADIUS_DEFAULT}
}

// Hint_Colors are a cap's fill, text and border.
Hint_Colors :: struct {
	fill, text, border: ops.Color,
}

// hint_colors is variant's cap colours (Chord.module.css:16-32).
hint_colors :: proc(variant: Hint_Variant) -> Hint_Colors {
	switch variant {
	case .On_Emphasis:
		return {color(.Counter_Bg_Color_Emphasis), color(.Fg_Color_On_Emphasis), {}}
	case .On_Primary:
		return {color(.Button_Primary_Bg_Color_Active), color(.Fg_Color_On_Emphasis), {}}
	case .Normal:
	}
	return {color(.Bg_Color_Transparent), color(.Fg_Color_Muted), color(.Border_Color_Default)}
}

// Hint_Layout is a hint shaped: each chord's key texts, and its size.
@(private)
Hint_Layout :: struct {
	keys:    [MAX_HINT_KEYS][MAX_HINT_KEYS]Text,
	lens:    [MAX_HINT_KEYS]int,
	n:       int,
	widths:  [MAX_HINT_KEYS]f32,
	cap:     Hint_Cap,
	gap:     f32, // 0.5ch between keys
	space:   f32, // a space between chords
	plus:    Text, // the + between keys in full format
	full:    bool,
	size:    ops.Size,
}

// layout_hint shapes keys into caps: each chord one cap, its keys 0.5ch
// apart (with a + between them in full format), chords a space apart.
@(private)
layout_hint :: proc(gtx: ^ui.Ctx, keys: string, format: Hint_Format, variant: Hint_Variant, size: Hint_Size) -> (h: Hint_Layout) {
	h.cap = hint_cap(variant, size)
	h.full = format == .Full
	st := tok.Type_Style{weight = tok.BASE_TEXT_WEIGHT_NORMAL, size = h.cap.text, line_height = h.cap.line}
	shape :: proc(gtx: ^ui.Ctx, s: string, st: tok.Type_Style) -> Text {
		return design.shape_style(gtx, s, st, font_for(gtx, st.weight))
	}
	h.gap = shape(gtx, "0", st).width / 2
	h.space = shape(gtx, " ", st).width
	h.plus = shape(gtx, "+", st)
	chords, lens, n := hint_chords(keys, gtx.allocator)
	h.n, h.lens = n, lens
	b := tok.BORDER_WIDTH_THIN
	for ci in 0 ..< n {
		w: f32
		for ki in 0 ..< lens[ci] {
			t := shape(gtx, key_label(chords[ci][ki], format, PLATFORM, gtx.allocator), st)
			h.keys[ci][ki] = t
			if ki > 0 {
				w += h.gap + (h.full ? h.plus.width + h.gap : 0)
			}
			w += t.width
		}
		h.widths[ci] = max(w + 2 * (h.cap.pad + b), h.cap.min_w)
		h.size.x += h.widths[ci] + (ci > 0 ? h.space : 0)
	}
	h.size.y = h.cap.line + 2 * (h.cap.pad + b)
	return
}

// paint_hint draws h with its top-left at pos in colors. A cap clips its
// keys to its padding edge, as the CSS's overflow does, since the line
// box is smaller than the text (keybinding-hint.json notes).
@(private)
paint_hint :: proc(gtx: ^ui.Ctx, h: Hint_Layout, pos: ops.Point, colors: Hint_Colors) {
	x := pos.x
	b := tok.BORDER_WIDTH_THIN
	for ci in 0 ..< h.n {
		if ci > 0 {
			x += h.space
		}
		box := ops.Rect{x, pos.y, h.widths[ci], h.size.y}
		rr := ops.Round_Rect{box, h.cap.radius}
		if ui.painted(colors.fill) {
			ops.fill(gtx.scene, rr, colors.fill)
		}
		if ui.painted(colors.border) {
			stroke_inside(gtx, rr, colors.border, b)
		}
		content: f32
		for ki in 0 ..< h.lens[ci] {
			if ki > 0 {
				content += h.gap + (h.full ? h.plus.width + h.gap : 0)
			}
			content += h.keys[ci][ki].width
		}
		ops.clip_push(gtx.scene, ops.Rect{box.x + b, box.y + b, box.w - 2 * b, box.h - 2 * b})
		kx := x + (box.w - content) / 2
		for ki in 0 ..< h.lens[ci] {
			t := h.keys[ci][ki]
			if ki > 0 {
				kx += h.gap
				if h.full {
					draw_text(gtx, h.plus, {kx, pos.y + (h.size.y - h.plus.height) / 2}, colors.text)
					kx += h.plus.width + h.gap
				}
			}
			draw_text(gtx, t, {kx, pos.y + (h.size.y - t.height) / 2}, colors.text)
			kx += t.width
		}
		ops.clip_pop(gtx.scene)
		x += box.w
	}
}

// keybinding_hint shows a keyboard shortcut as key caps: keys is a
// sequence of chords separated by spaces, each chord keys joined by +
// ("Mod+Shift+K", "g i"). It binds nothing; assistive technology hears
// the keys' spoken names (keybinding-hint.json).
keybinding_hint :: proc(gtx: ^ui.Ctx, keys: string, format := Hint_Format.Condensed, variant := Hint_Variant.Normal, size := Hint_Size.Normal, key: u64 = 0, loc := #caller_location) {
	p := ui.widget_open(gtx, key, loc)
	h := layout_hint(gtx, keys, format, variant, size)
	sz := ui.constrain_min(gtx.constraints, h.size)
	paint_hint(gtx, h, {0, (sz.y - h.size.y) / 2}, hint_colors(variant))
	ui.semantics(gtx, &p, {role = .Text, label = spoken_hint(keys, PLATFORM, gtx.allocator)})
	ui.widget_close(gtx, &p, {sz, 0})
}
