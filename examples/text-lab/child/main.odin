// The text lab: jm:ui's text pipeline under a magnifying glass. Each page
// is a set of specimens — Latin features, the world's scripts, mixed
// direction, emoji — drawn with what the shaper produced laid over them:
// baseline and advance box, glyph origins, cluster starts and every caret
// stop. The Editing and Paragraph pages put the same text in live inputs
// to poke carets, hit-testing and wrapping by hand.
//
// Each specimen names the font it asks for; every other script's font
// stands behind it as a fallback, so a rune that font lacks comes from the
// first one that has it.
//
//	text-lab-child                              run as the hot-reload subprocess
//	text-lab-child -page Bidi -png out.png      render one page headlessly
//	text-lab-child -size 950x1040 ...           at another window size
//	text-lab-child -full -page Scripts -png out.png  the whole page, trimmed
//
// The remaining flags are ui/render's headless steps, as in
// examples/fluent-kitchen. The page, sample size and overlay switch
// survive a hot-reload respawn through build/debug/text-lab.state.
package main

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "jm:ui"
import "jm:ui/base"
import "jm:ui/child"
import "jm:ui/fluent"
import "jm:ui/ops"
import "jm:ui/render"

WIDTH :: 1400
HEIGHT :: 900
STATE_FILE :: "build/debug/text-lab.state"
NAV_WIDTH :: 200
SIZES := [?]f32{16, 24, 40, 64}

// Script names the font a sample is shaped in; UI is the chrome's own.
// Scripts sharing a file share a Font_Id (see lab_fonts).
Script :: enum {
	UI,
	Latin,
	Arabic,
	Hebrew,
	Devanagari,
	Bengali,
	Tamil,
	Thai,
	Khmer,
	Myanmar,
	Georgian,
	Armenian,
	Ethiopic,
	CJK,
	Symbols,
	Emoji,
}

// FONT_FILES are the candidates for each script, first found wins; a
// script with none found falls back to ui.default_font (see lab_fonts).
FONT_FILES := [Script][]string {
	.UI         = {"/usr/share/fonts/noto/NotoSans-Regular.ttf"},
	.Latin      = {"/usr/share/fonts/noto/NotoSans-Regular.ttf", "/System/Library/Fonts/Supplemental/Arial.ttf", "C:/Windows/Fonts/arial.ttf"},
	.Arabic     = {"/usr/share/fonts/noto/NotoSansArabic-Regular.ttf", "/System/Library/Fonts/GeezaPro.ttc", "C:/Windows/Fonts/tahoma.ttf"},
	.Hebrew     = {"/usr/share/fonts/noto/NotoSansHebrew-Regular.ttf", "/System/Library/Fonts/ArialHB.ttc", "C:/Windows/Fonts/tahoma.ttf"},
	.Devanagari = {"/usr/share/fonts/noto/NotoSansDevanagari-Regular.ttf", "/System/Library/Fonts/Kohinoor.ttc", "C:/Windows/Fonts/Nirmala.ttc"},
	.Bengali    = {"/usr/share/fonts/noto/NotoSansBengali-Regular.ttf", "C:/Windows/Fonts/Nirmala.ttc"},
	.Tamil      = {"/usr/share/fonts/noto/NotoSansTamil-Regular.ttf", "C:/Windows/Fonts/Nirmala.ttc"},
	.Thai       = {"/usr/share/fonts/noto/NotoSansThai-Regular.ttf", "/System/Library/Fonts/Thonburi.ttc", "C:/Windows/Fonts/LeelawUI.ttf"},
	.Khmer      = {"/usr/share/fonts/noto/NotoSansKhmer-Regular.ttf", "C:/Windows/Fonts/LeelawUI.ttf"},
	.Myanmar    = {"/usr/share/fonts/noto/NotoSansMyanmar-Regular.ttf", "C:/Windows/Fonts/mmrtext.ttf"},
	.Georgian   = {"/usr/share/fonts/noto/NotoSansGeorgian-Regular.ttf", "C:/Windows/Fonts/sylfaen.ttf"},
	.Armenian   = {"/usr/share/fonts/noto/NotoSansArmenian-Regular.ttf", "C:/Windows/Fonts/sylfaen.ttf"},
	.Ethiopic   = {"/usr/share/fonts/noto/NotoSansEthiopic-Regular.ttf", "C:/Windows/Fonts/ebrima.ttf"},
	.CJK        = {"/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc", "/System/Library/Fonts/PingFang.ttc", "C:/Windows/Fonts/msyh.ttc"},
	.Symbols    = {"/usr/share/fonts/noto/NotoSansSymbols2-Regular.ttf", "C:/Windows/Fonts/seguisym.ttf"},
	.Emoji      = {"/usr/share/fonts/noto/NotoColorEmoji.ttf", "/System/Library/Fonts/Apple Color Emoji.ttc", "C:/Windows/Fonts/seguiemj.ttf"},
}

Sample :: struct {
	label:  string,
	text:   string,
	script: Script,
}

LATIN := [?]Sample {
	{"Kerning", "AVATAR Wave To Ty P. Yo", .Latin},
	{"Ligatures (a caret inside one splits it evenly)", "office affine fjord flat ffl", .Latin},
	{"Precomposed vs combining", "é e\u0301 · ñ n\u0303", .Latin},
	{"Stacked marks", "a\u0300\u0301\u0302\u0303 o\u0308\u0304", .Latin},
	{"Numerals and fractions", "0123456789 ½ ⅞ 1st 2nd", .Latin},
	{"Punctuation", "“quotes” ‘single’ — dash … ellipsis", .Latin},
	{"Invisible: zero-width space, soft hyphen, ZWJ", "a\u200Bb soft\u00ADhyphen x\u200Dy", .Latin},
	{"Greek, Cyrillic, Vietnamese in one font", "Ελληνικά Кириллица Tiếng Việt", .Latin},
}

SCRIPTS := [?]Sample {
	{"Arabic: joining forms", "العربية مرحبا بالعالم", .Arabic},
	{"Hebrew", "שלום עולם", .Hebrew},
	{"Devanagari: conjuncts and reordered matras", "नमस्ते दुनिया क्षत्रिय कि", .Devanagari},
	{"Bengali", "বাংলা ভাষা", .Bengali},
	{"Tamil", "தமிழ் மொழி", .Tamil},
	{"Thai: stacked vowels and tones, no spaces", "ภาษาไทยสวัสดีครับ", .Thai},
	{"Khmer: subscript consonants", "ភាសាខ្មែរ", .Khmer},
	{"Myanmar", "မြန်မာဘာသာ", .Myanmar},
	{"Georgian", "ქართული ენა", .Georgian},
	{"Armenian", "Հայերեն լեզու", .Armenian},
	{"Ethiopic", "ግዕዝ አማርኛ", .Ethiopic},
	{"CJK: Chinese, Japanese, Korean", "中文 日本語のテキスト 한국어", .CJK},
	{"Symbols", "★ ☂ ♞ ⚙ ✔ ➜", .Symbols},
}

BIDI := [?]Sample {
	{"Right-to-left alone", "שלום עולם", .Hebrew},
	{"Mixed: needs bidi and fallback", "Hello שלום world", .Hebrew},
	{"Arabic with Latin digits", "مرحبا 123 456", .Arabic},
	{"Arabic-Indic digits", "العدد ٣٤٥ هنا", .Arabic},
	{"Mirrored brackets", "(שלום) [עולם] <א>", .Hebrew},
	{"Directional marks: RLM between a and b", "a\u200Fb \u200E", .Latin},
	{"Isolates: RLI … PDI", "one \u2067שלום two\u2069 three", .Hebrew},
	{"Arabic in Latin", "The word كتاب means book", .Arabic},
}

EMOJI := [?]Sample {
	{"Single and skin tone modifier", "👍 👍🏽", .Emoji},
	{"ZWJ sequences", "👩‍💻 👨‍👩‍👧", .Emoji},
	{"Flags: regional indicator pairs", "🇳🇿 🇯🇵 🇺🇳", .Emoji},
	{"Variation selectors: emoji vs text", "❤\uFE0F ❤\uFE0E", .Emoji},
	{"Keycaps", "1\uFE0F\u20E3 #\uFE0F\u20E3", .Emoji},
}

EDIT := [?]Sample {
	{"Ligatures", "office affine flat", .Latin},
	{"Combining marks", "e\u0301te\u0301 a\u0300\u0301", .Latin},
	{"Arabic", "مرحبا بالعالم", .Arabic},
	{"Hebrew", "שלום עולם", .Hebrew},
	{"Devanagari", "नमस्ते क्षत्रिय", .Devanagari},
	{"Thai", "สวัสดีครับ", .Thai},
	{"CJK", "日本語のテキスト", .CJK},
	{"Emoji", "hi 👩‍💻 🇳🇿", .Emoji},
}

PARAGRAPH :: "Text shaping turns a string into positioned glyphs. A browser also breaks lines at legal opportunities, reorders right-to-left runs, and falls back to another font for a character this one lacks — so a paragraph that mixes scripts wraps, reads and edits as the reader expects. Long unbroken words like Donaudampfschifffahrtsgesellschaftskapitän test emergency breaks."

Page :: struct {
	name: string,
	draw: proc(gtx: ^ui.Ctx, m: ^Model),
}

PAGES := [?]Page {
	{"Latin", page_latin},
	{"Scripts", page_scripts},
	{"Bidi", page_bidi},
	{"Emoji", page_emoji},
	{"Editing", page_editing},
	{"Paragraph", page_paragraph},
}

Model :: struct {
	page:      int,
	size:      int, // index into SIZES
	plain:     bool, // overlays off
	persisted: [3]int,
	scheme:    fluent.Scheme,
	found:     [Script]bool, // whether a candidate in FONT_FILES exists
	font:      [Script]ops.Font_Id,
	seeded:    bool,
	edits:     [len(EDIT)]ui.Text_State,
	paragraph: ui.Text_State,
}

lab_ui :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Model)(user)
	m.scheme = fluent.theme_scheme(.Web_Light)
	fluent.use(&m.scheme, .Light)
	ui_font := m.font[.UI]
	fluent.use_fonts({ui_font, ui_font, ui_font})
	if !m.seeded {
		for e, i in EDIT {
			ui.text_set(&m.edits[i], e.text)
		}
		ui.text_set(&m.paragraph, PARAGRAPH)
		m.seeded = true
	}
	s := &m.scheme
	ops.fill(gtx.scene, ops.Rect{0, 0, gtx.constraints.max.x, gtx.constraints.max.y}, s[.Neutral_Background2])

	r := ui.row_open(gtx, align = .Fill)
	defer ui.close(&r)
	nav(gtx, m)
	ui.flexible(gtx, 1)
	body := ui.column_open(gtx)
	defer ui.close(&body)
	app_bar(gtx, m)
	ui.flexible(gtx, 1)
	{
		for i in 0 ..< len(PAGES) {
			ui.retain(gtx, i)
		}
		ps := ui.scope_open(gtx, m.page)
		defer ui.close(&ps)
		sb := ui.scroll_box_open(gtx)
		defer ui.close(&sb)
		page := ui.inset_open(gtx, {24, 8, 24, 48})
		defer ui.close(&page)
		PAGES[clamp(m.page, 0, len(PAGES) - 1)].draw(gtx, m)
	}
	persist(m)
}

nav :: proc(gtx: ^ui.Ctx, m: ^Model) {
	n := fluent.nav_open(gtx, width = NAV_WIDTH)
	defer fluent.nav_close(&n)
	if fluent.nav_header(gtx) {
		fluent.app_item(gtx, "jm:ui text lab", .Grid, static = true)
	}
	if fluent.nav_body(gtx) {
		selected := PAGES[clamp(m.page, 0, len(PAGES) - 1)].name
		for p, i in PAGES {
			if fluent.nav_item(gtx, p.name, p.name, &selected, key = u64(i)) {
				m.page = i
			}
		}
	}
}

// app_bar is the page title, the sample size and the overlay switch.
app_bar :: proc(gtx: ^ui.Ctx, m: ^Model) {
	s := fluent.scheme()
	bar := ui.inset_open(gtx, {24, 12, 16, 8})
	defer ui.close(&bar)
	r := ui.row_open(gtx, align = .Center, gap = 8)
	defer ui.close(&r)
	base.label(gtx, PAGES[clamp(m.page, 0, len(PAGES) - 1)].name, {size = 20, color = s[.Neutral_Foreground1]})
	ui.fill_space(gtx)
	if fluent.button(gtx, fmt.tprintf("%.0fpx", SIZES[m.size]), .Outline) {
		m.size = (m.size + 1) % len(SIZES)
	}
	if fluent.button(gtx, m.plain ? "Overlays off" : "Overlays on", .Outline) {
		m.plain = !m.plain
	}
}

page_latin :: proc(gtx: ^ui.Ctx, m: ^Model) {
	specimens(gtx, m, LATIN[:], "Features one font and a left-to-right shaper should already get right.")
}

page_scripts :: proc(gtx: ^ui.Ctx, m: ^Model) {
	specimens(gtx, m, SCRIPTS[:], "Complex scripts need GSUB/GPOS per script: joining, reordering, stacking.")
}

page_bidi :: proc(gtx: ^ui.Ctx, m: ^Model) {
	specimens(gtx, m, BIDI[:], "Runs reordered per line (UAX #9 L2 from run directions); fonts fall back per grapheme.")
}

page_emoji :: proc(gtx: ^ui.Ctx, m: ^Model) {
	specimens(gtx, m, EMOJI[:], "Colour glyph formats (CBDT, COLR, sbix) need renderer support as well as shaping.")
}

// page_editing is each sample in a live input, in the sample's font, to
// try the caret and hit-testing against real clusters.
page_editing :: proc(gtx: ^ui.Ctx, m: ^Model) {
	s := fluent.scheme()
	col := ui.column_open(gtx, gap = 12)
	defer ui.close(&col)
	note(gtx, "Click inside a cluster, arrow across marks and ligatures, type. Each input uses its sample's font.")
	for e, i in EDIT {
		c := ui.column_open(gtx, gap = 4, key = u64(i))
		base.label(gtx, e.label, {size = 12, color = s[.Neutral_Foreground2]})
		prev := swap_font(gtx, m.font[e.script])
		fluent.input(gtx, &m.edits[i], width = 480, name = e.label, key = u64(i))
		swap_font(gtx, prev)
		ui.close(&c)
	}
}

page_paragraph :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 20)
	defer ui.close(&col)
	note(gtx, "ui.paragraph_layout at 520px: soft breaks, hanging spaces, emergency breaks, right-to-left alignment.")
	for sm, i in WRAPPED {
		specimen(gtx, m, sm, key = u64(i), width = 520)
	}
	note(gtx, "A textarea: wrapping, vertical caret motion and hit-testing across lines.")
	fluent.textarea(gtx, &m.paragraph, width = 520)
}

WRAPPED := [?]Sample {
	{"Latin", PARAGRAPH, .Latin},
	{"Hebrew: a right-to-left paragraph", "עברית היא שפה שמית ממשפחת השפות האפרו-אסיאתיות. הטקסט נכתב מימין לשמאל, ומספרים כמו 2026 נכתבים משמאל לימין.", .Hebrew},
	{"Arabic: joining across wrapped lines", "اللغة العربية هي أكثر اللغات السامية تحدثاً، وإحدى أكثر اللغات انتشاراً في العالم، يتحدثها أكثر من 400 مليون نسمة.", .Arabic},
	{"Thai: no spaces between words", "ภาษาไทยเป็นภาษาที่มีระดับเสียงของคำแน่นอนหรือวรรณยุกต์เช่นเดียวกับภาษาจีนและออกเสียงแยกคำต่อคำ", .Thai},
	{"CJK: a break between any two ideographs", "日本語の文章は単語の間に空白を置かずに書かれるので、行はほとんどどの文字の間でも折り返すことができます。", .CJK},
}

// swap_font makes id the font fluent's controls and ui's hit-testing
// use, returning what it replaced so the caller can put it back. A
// stand-in for font fallback in the lab only.
swap_font :: proc(gtx: ^ui.Ctx, id: ops.Font_Id) -> ops.Font_Id {
	prev := gtx.font
	gtx.font = id
	fluent.use_fonts({id, id, id})
	return prev
}

note :: proc(gtx: ^ui.Ctx, text: string) {
	base.label(gtx, text, {size = 13, color = fluent.scheme()[.Neutral_Foreground2]})
}

specimens :: proc(gtx: ^ui.Ctx, m: ^Model, samples: []Sample, about: string) {
	col := ui.column_open(gtx, gap = 20)
	defer ui.close(&col)
	note(gtx, about)
	if !m.plain {
		legend(gtx)
	}
	for sm, i in samples {
		specimen(gtx, m, sm, key = u64(i))
	}
}

// Overlay colours.
BOX :: ops.Color{0, 120, 212, 18}
BASELINE :: ops.Color{0, 120, 212, 160}
ORIGIN :: ops.Color{0, 120, 212, 255}
CLUSTER :: ops.Color{16, 124, 16, 200}
CARET :: ops.Color{209, 52, 56, 230}

legend :: proc(gtx: ^ui.Ctx) {
	s := fluent.scheme()
	r := ui.row_open(gtx, gap = 16, align = .Center)
	defer ui.close(&r)
	items := [?]struct {
		c: ops.Color,
		t: string,
	}{{BASELINE, "baseline, advance box"}, {ORIGIN, "glyph origin"}, {CLUSTER, "cluster start"}, {CARET, "caret stop"}}
	for it, i in items {
		c := ui.row_open(gtx, gap = 6, align = .Center, key = u64(i))
		swatch(gtx, it.c)
		base.label(gtx, it.t, {size = 12, color = s[.Neutral_Foreground2]})
		ui.close(&c)
	}
}

swatch :: proc(gtx: ^ui.Ctx, c: ops.Color, loc := #caller_location) -> ui.Dims {
	p := ui.widget_open(gtx, 0, loc)
	ops.fill(gtx.scene, ops.Rect{0, 0, 12, 12}, c)
	return ui.widget_close(gtx, &p, {{12, 12}, 12})
}

// specimen is one sample: its label and counts, then its run at the
// chosen size with the overlays.
specimen :: proc(gtx: ^ui.Ctx, m: ^Model, sm: Sample, key: u64, width: f32 = 0) {
	s := fluent.scheme()
	p := ui.paragraph_layout(gtx.shaper, m.font[sm.script], SIZES[m.size], sm.text, width, gtx.allocator)

	col := ui.column_open(gtx, gap = 4, key = key)
	defer ui.close(&col)
	base.label(gtx, sm.label, {size = 13, color = s[.Neutral_Foreground1]})
	font_note := m.found[sm.script] ? fmt.tprint(sm.script) : fmt.tprintf("%v missing, default font", sm.script)
	glyphs, clusters, runs := 0, 0, 0
	for ln in p.lines {
		runs += len(ln.runs)
		for r in ln.runs {
			glyphs += len(r.glyphs.glyphs)
			clusters += len(r.clusters)
		}
	}
	base.label(gtx, fmt.tprintf("%d bytes · %d graphemes · %d glyphs · %d clusters · %d runs · %d lines · %.1fpx · %s%s", len(sm.text), len(p.graphemes) - 1, glyphs, clusters, runs, len(p.lines), p.width, "rtl · " if p.rtl else "", font_note), {size = 11, color = s[.Neutral_Foreground3]})
	draw_specimen(gtx, p, width, !m.plain, s[.Neutral_Foreground1])
}

// draw_specimen draws paragraph p, width wide (its own width when 0),
// with its top-left at the origin and, when overlays is set, what layout
// produced laid over it: each line's box and baseline, glyph origins, the
// logical start edge of each cluster and a tick at every caret stop.
draw_specimen :: proc(gtx: ^ui.Ctx, p: ui.Paragraph, width: f32, overlays: bool, color: ops.Color, loc := #caller_location) -> ui.Dims {
	w := width if width > 0 else p.width
	pl := ui.widget_open(gtx, 0, loc)
	if overlays {
		if width > 0 {
			ops.stroke(gtx.scene, ops.Rect{0, 0, w, p.height}, BASELINE, {width = 1})
		}
		draw_line_boxes(gtx, p)
	}
	ui.paragraph_draw(gtx.scene, p, {}, color)
	if overlays {
		draw_glyph_marks(gtx, p)
	}
	return ui.widget_close(gtx, &pl, {{w, p.height + tick_height(p)}, p.metrics.ascent})
}

// draw_line_boxes draws, under the text, each line's box and baseline and
// a rule at each cluster's logical start edge.
draw_line_boxes :: proc(gtx: ^ui.Ctx, p: ui.Paragraph) {
	lh := p.pitch
	h := p.metrics.ascent + p.metrics.descent
	for ln, k in p.lines {
		top := f32(k) * lh
		ops.fill(gtx.scene, ops.Rect{ln.x, top, ln.width, h}, BOX)
		ops.fill(gtx.scene, ops.Rect{ln.x, ln.baseline, ln.width, 1}, BASELINE)
		for r in ln.runs {
			for c in r.clusters {
				ops.fill(gtx.scene, ops.Rect{ln.x + (c.x1 - 1 if r.rtl else c.x0), top, 1, h}, CLUSTER)
			}
		}
	}
}

// draw_glyph_marks draws, over the text, a dot at each glyph's origin and
// a tick under each caret stop.
draw_glyph_marks :: proc(gtx: ^ui.Ctx, p: ui.Paragraph) {
	for ln in p.lines {
		for r in ln.runs {
			for g in r.glyphs.glyphs {
				ops.fill(gtx.scene, ops.Ellipse{{ln.x + r.x + g.x - 2, ln.baseline + g.y - 2, 4, 4}}, ORIGIN)
			}
		}
	}
	lh := p.pitch
	h := p.metrics.ascent + p.metrics.descent
	for g in p.graphemes {
		k, x := ui.paragraph_caret(p, g)
		ops.fill(gtx.scene, ops.Rect{x - 0.5, f32(k) * lh + h, 1, tick_height(p)}, CARET)
	}
}

tick_height :: proc(p: ui.Paragraph) -> f32 {
	return max(p.metrics.descent * 0.6, 4)
}

// lab_fonts picks each Script's file, the first candidate in FONT_FILES
// that exists, else jm:ui's default font. It registers them with
// ops.add_font, as the scene will, so scripts sharing a file share the id
// in m.font that the scene gives it.
lab_fonts :: proc(m: ^Model) -> []ops.Font_Ref {
	sc: ops.Scene
	ops.init(&sc)
	for script in Script {
		path := ui.default_font()
		for c in FONT_FILES[script] {
			if os.exists(c) {
				path, m.found[script] = c, true
				break
			}
		}
		m.font[script] = ops.add_font(&sc, path)
	}
	return sc.fonts[:]
}

// lab_fallbacks is every script's font, in Script order, each once: the
// fallback chain behind whichever font a sample asks for.
lab_fallbacks :: proc(m: ^Model) -> []ops.Font_Id {
	out := make([dynamic]ops.Font_Id)
	for script in Script {
		id := m.font[script]
		if !slice.contains(out[:], id) {
			append(&out, id)
		}
	}
	return out[:]
}

// State that survives a respawn.

persist :: proc(m: ^Model) {
	now := [3]int{m.page, m.size, int(m.plain)}
	if now == m.persisted {
		return
	}
	m.persisted = now
	_ = os.write_entire_file(STATE_FILE, transmute([]u8)fmt.tprintf("%d %d %d", now[0], now[1], now[2]))
}

restore :: proc(m: ^Model) {
	data, err := os.read_entire_file(STATE_FILE, context.temp_allocator)
	if err != nil {
		return
	}
	fields := strings.fields(string(data), context.temp_allocator)
	if len(fields) == 3 {
		m.page = clamp(parse_int(fields[0]), 0, len(PAGES) - 1)
		m.size = clamp(parse_int(fields[1]), 0, len(SIZES) - 1)
		m.plain = parse_int(fields[2]) != 0
	}
	m.persisted = {m.page, m.size, int(m.plain)}
}

// parse_int is s as a non-negative integer, 0 for anything else.
parse_int :: proc(s: string) -> int {
	n, ok := strconv.parse_int(s, 10)
	return n if ok && n >= 0 else 0
}

main :: proc() {
	m: Model
	m.size = 2
	fonts := lab_fonts(&m)
	if len(os.args) == 1 {
		restore(&m)
		child.run({ui = lab_ui, user = &m, fonts = fonts, fallbacks = lab_fallbacks(&m)})
		return
	}
	args := os.args[1:]
	size := ops.Size{WIDTH, HEIGHT}
	debug: ui.Debug_Flags
	full := false
	h: render.Headless
	open := false
	defer if open {
		render.headless_destroy(&h)
	}
	setup :: proc(open: bool, flag: string) {
		if open {
			fmt.eprintfln("%s must come before the first step", flag)
			os.exit(2)
		}
	}
	for i := 0; i < len(args); i += 1 {
		switch args[i] {
		case "-reveal":
			setup(open, args[i])
			debug += {.Reveal}
		case "-bounds":
			setup(open, args[i])
			debug += {.Bounds}
		case "-full":
			setup(open, args[i])
			full = true
		case "-size":
			setup(open, args[i])
			i += 1
			w, _, ht := strings.partition(i < len(args) ? args[i] : "", "x")
			size = {f32(parse_int(w)), f32(parse_int(ht))}
			if size.x <= 0 || size.y <= 0 {
				fmt.eprintln("-size needs WxH, e.g. 950x1040")
				os.exit(2)
			}
		case "-plain":
			m.plain = true
		case "-page":
			if i + 1 >= len(args) {
				fmt.eprintln("-page needs a name")
				os.exit(2)
			}
			i += 1
			found := false
			for p, j in PAGES {
				if strings.equal_fold(p.name, args[i]) {
					m.page, found = j, true
				}
			}
			if !found {
				fmt.eprintfln("no page %q", args[i])
				os.exit(2)
			}
		case:
			if !open {
				render.headless_init(&h, lab_ui, &m, size, fonts, debug, full = full, fallbacks = lab_fallbacks(&m))
				open = true
			}
			handled, ok := render.headless_step(&h, args, &i)
			if !handled {
				fmt.eprintfln("unknown flag %s", args[i])
				os.exit(2)
			}
			if !ok {
				os.exit(1)
			}
			continue
		}
		if open {
			ui.probe_frame(&h.p)
		}
	}
}
