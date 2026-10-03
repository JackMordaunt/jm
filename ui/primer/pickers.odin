package primer

import "core:fmt"
import "core:strings"
import "jm:ui"
import "jm:ui/design"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// The pickers: TextInputWithTokens, Autocomplete and SelectPanel
// (primer-kit components/text-input-with-tokens.json, autocomplete.json,
// select-panel.json). Autocomplete and SelectPanel keep keyboard focus in
// a text field and point at an option of an ActionList as its active
// descendant, which Up and Down move and Enter activates.

// TextInputWithTokens.

// TOKEN_INPUT_MIN is the narrowest the text input beside a token field's
// tokens gets before it wraps to a line of its own. The web's input keeps
// its intrinsic width; a native build picks a sensible minimum
// (text-input-with-tokens.json notes): this package's 64px.
TOKEN_INPUT_MIN :: tok.BASE_SIZE_64

// TOKEN_GAP is the gap between tokens, the input and the overflow count,
// and between lines (TextInputWithTokens.module.css:26-42).
TOKEN_GAP :: tok.BASE_SIZE_4

// Token_Field is what one frame of a token field did: the input's edit,
// and the token removed (by its X, Backspace or Delete on it, or
// Backspace in the empty input), -1 for none.
Token_Field :: struct {
	using edit: Field_Edit,
	removed:    int,
	pulled:     bool, // the removal was Backspace in the empty input, which put its text in the input
}

// Token_Field_Data is what a token field keeps between frames: a removal
// whose focus still has to land, and the input's caret scroll.
@(private)
Token_Field_Data :: struct {
	refocus: int, // one more than the index a removed token's focus goes to next frame; 0 for none
	scroll:  f32,
	pending: Token_Move,
	focused: bool, // the input or a token had focus last frame
	ids:     [TOKEN_FIELD_MAX]ops.Area_Id, // the tokens' ids last frame
}

// TOKEN_FIELD_MAX is the most tokens whose ids a token field remembers
// from one frame to the next, to give the focused one keys.
TOKEN_FIELD_MAX :: 64

// Token_Move is an arrow, Home or End a token or the input asked for,
// resolved once every token's id is known.
@(private)
Token_Move :: struct {
	from: int, // the token index, -1 for the input
	key:  ui.Key,
}

// token_field_size is the field's size for its tokens (TokenBase.module.css
// :46-54, TextInputWithTokens.tsx:269-274): small and medium tokens put it
// in its small size, large and xlarge in its medium size.
@(private)
token_field_size :: proc(s: Token_Size) -> Field_Size {
	return s <= .Medium ? .Small : .Medium
}

// token_width is a token's width as token_widget lays it out.
@(private)
token_width :: proc(gtx: ^ui.Ctx, text: string, size: Token_Size, removable: bool) -> f32 {
	mt := token_metrics(size)
	st := tok.Type_Style{weight = tok.BASE_TEXT_WEIGHT_SEMIBOLD, size = mt.text, line_height = mt.text}
	t := design.shape_style(gtx, text, st, font_for(gtx, st.weight))
	b := tok.BORDER_WIDTH_THIN
	tail := removable ? mt.gap + mt.height - b : mt.pad
	return b + mt.pad + t.width + tail + b
}

// Token_Well is a token field's well, read by its box's paint.
@(private)
Token_Well :: struct {
	well: Well,
}

@(private)
paint_token_well :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, size: ops.Size, user: rawptr) {
	w := (^Token_Well)(user)
	box := ops.Rect{0, 0, size.x, size.y}
	paint_well(gtx, box, w.well)
	paint_well_focus(gtx, box, w.well)
}

// text_input_with_tokens is Primer's TextInputWithTokens
// (text-input-with-tokens.json): TextInput's well holding tokens, each a
// removable Token, then the text input, in a row that wraps, 4px apart,
// the field padded 6px top and bottom and 12px on its left and growing
// with its lines. s is the input's text; tokens the chosen values' texts.
// size sizes the tokens (16, 20, 24 or 32px) and puts the field in its
// small (28px) or medium (32px) size. leading and trailing are octicons
// either side of the tokens; loading shows a spinner where loader says.
// visible_count > 0 shows only that many tokens and a +N count while
// neither the input nor a token has focus. hide_remove drops the X
// buttons; keyboard removal stays. The field is one tab stop, the input;
// from it ArrowLeft at the caret's start reaches the last token and
// ArrowRight at its end the first; on a token, ArrowLeft and ArrowRight
// move between tokens and past either end to the input, Home and End go
// to the input and the last token, Backspace or Delete removes it and
// Escape returns to the input. Backspace in the empty input removes the
// last token and puts its text, and a space, in the input, all selected.
// A press anywhere on the field but a token focuses the input. combobox
// makes the input a combo box, described by its tokens ("Selected: a,
// b"), as Autocomplete uses it.
//
// Departures: a token has no leading visual; preventTokenWrapping and
// maxHeight (scrolling the field) are not offered; the input's minimum
// width is TOKEN_INPUT_MIN; Home and End on a token reach the ring's ends,
// where the upstream getNextFocusable returns the token itself for them
// (TextInputWithTokens.tsx:132-162);
// focus after Backspace in the empty input stays in the input, which the
// spec's notes ask to confirm (upstream lands on the first token).
text_input_with_tokens :: proc(
	gtx: ^ui.Ctx,
	s: ^ui.Text_State,
	tokens: []string,
	size := Token_Size.XLarge,
	placeholder := "",
	leading := Icon.None,
	trailing := Icon.None,
	loading := false,
	loader := Loader_Position.Auto,
	visible_count := 0,
	hide_remove := false,
	validation := Validation_Status.None,
	block := false,
	contrast := false,
	width: f32 = 0,
	name := "",
	combobox: Maybe(Combobox) = nil,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> (r: Token_Field) {
	r.removed = -1
	id := ui.claim_id(gtx, key, loc)
	d := ui.widget_data(gtx, id, Token_Field_Data)
	fc := field_context(gtx, id, name, validation, false, state)
	disabled := fc.state == .Disabled
	fsize := token_field_size(size)
	st := field_style(fsize)
	mt := token_metrics(size)
	lead_spin := loading && (loader == .Leading || (loader == .Auto && leading != .None))
	trail_spin := loading && !lead_spin
	lead := leading != .None || lead_spin
	trail := trailing != .None || trail_spin
	// The well: 1px border, 6px above and below, 12px on the left, 8px
	// beside a trailing visual (TextInputWithTokens.module.css:1-14,
	// TextInputWrapper.module.css:152-187).
	b := FIELD_BORDER
	pad_l := tok.BASE_SIZE_12
	pad_r: f32 = trail ? tok.BASE_SIZE_8 : 0
	cs := ui.offer(gtx)
	w := width
	if w <= 0 {
		w = pad_l + TEXT_INPUT_COLUMNS * field_ch(gtx, st) + pad_r + 2 * b
	}
	if block && ui.is_finite(cs.max.x) {
		w = cs.max.x
	}
	w = ui.constrain(cs, {w, 0}).x
	x0 := b + pad_l + (lead ? BUTTON_ICON + tok.BASE_SIZE_8 : 0)
	inner := max(w - x0 - b - pad_r - (trail ? BUTTON_ICON + tok.BASE_SIZE_8 : 0), 0)
	input_id := ui.id_mix(id, 0x1e7)
	shown := len(tokens)
	if visible_count > 0 && !d.focused && ui.focused(gtx) != input_id && visible_count < len(tokens) {
		shown = visible_count
	}
	ln := token_field_lines(gtx, tokens, shown, size, !disabled && !hide_remove, inner)
	h := max(field_height(fsize), ln.content + 2 * tok.BASE_SIZE_6 + 2 * b)
	top := (h - ln.content) / 2
	target := token_field_steer(gtx, d, s, input_id, shown)
	well := new(Token_Well, gtx.allocator)
	well.well = Well{false, disabled, contrast, fc.status}
	frame := ui.sized_open(gtx, {min = {w, h}, max = {w, h}}, key = u64(ui.id_mix(id, 1)), loc = loc)
	box := ui.box_open(gtx, {paint = paint_token_well, user = well}, key = u64(ui.id_mix(id, 2)), loc = loc)
	stack := ui.stack_open(gtx, key = u64(ui.id_mix(id, 3)), loc = loc)
	// A press on the field but not a token focuses the input
	// (TextInputWithTokens.tsx:260-266).
	if !disabled && fc.state == .Live {
		for e in ui.events(gtx, ui.id_mix(id, 4)) {
			if e.kind == .Press && e.button == .Left {
				ui.focus_request(gtx, input_id)
			}
		}
		ops.input_area(gtx.scene, ui.id_mix(id, 4), ops.Rect{0, 0, w, h}, {.Press}, .Text)
	}
	visual := color(disabled ? .Fg_Color_Disabled : .Fg_Color_Muted)
	if lead {
		paint_field_icon(gtx, leading, {b + pad_l, (h - BUTTON_ICON) / 2}, lead_spin, visual)
	}
	if trail {
		paint_field_icon(gtx, trailing, {w - b - pad_r - BUTTON_ICON, (h - BUTTON_ICON) / 2}, trail_spin, visual)
	}
	focused_any := ui.focused(gtx) == input_id
	token_ids := make([]ops.Area_Id, shown, gtx.allocator)
	for i in 0 ..< shown {
		pad := ui.inset_open(gtx, {left = x0 + ln.at[i].x, top = top + ln.at[i].y}, key = u64(ui.id_mix(id, 0x7000 + u64(i))))
		// Only the focused token is a tab stop and hears keys: the field's
		// one stop is the input.
		roving := i >= TOKEN_FIELD_MAX || (ui.focused(gtx) != d.ids[i] && target != i)
		res := token_widget(gtx, {tokens[i], size, .None, !disabled, hide_remove || disabled, false, true, false, {}, roving, true}, disabled ? .Disabled : fc.state, 0, loc)
		token_ids[i] = ui.last_widget(gtx).id
		if i < TOKEN_FIELD_MAX {
			d.ids[i] = token_ids[i]
		}
		ui.close(&pad)
		focused_any |= ui.focused(gtx) == token_ids[i]
		if res.removed {
			r.removed = i
		}
	}
	well.well.focused = focused_any
	if ln.count.width > 0 {
		draw_text(gtx, ln.count, {x0 + ln.count_at.x, top + ln.count_at.y}, color(.Fg_Color_Muted))
	}
	input: {
		pad := ui.inset_open(gtx, {left = x0 + ln.input_at.x, top = top + ln.input_at.y}, key = u64(ui.id_mix(id, 5)))
		sem := ops.Semantics{role = .Text_Field, label = fc.name != "" ? fc.name : placeholder, description = fc.description}
		if _, ok := combobox.?; ok && len(tokens) > 0 {
			sem.description = join_words(gtx, sem.description, strings.concatenate({"Selected: ", strings.join(tokens, ", ", gtx.allocator)}, gtx.allocator))
		}
		sem.states = design.state_if(disabled, {.Disabled}) + design.state_if(fc.status == .Error, {.Invalid}) + design.state_if(loading, {.Busy})
		combobox_semantics(&sem, combobox)
		edge: ui.Key
		r.edit, edge = bare_input(gtx, s, input_id, {ln.input_w, mt.height}, st, placeholder, &d.scroll, sem, disabled ? .Disabled : fc.state)
		ui.close(&pad)
		if edge == .Backspace {
			if n := len(tokens); n > 0 && !disabled {
				// TextInputWithTokens.tsx:229-258: the last token's text and a
				// space go back in the input, all selected.
				r.removed, r.pulled = n - 1, true
				ui.text_set(s, strings.concatenate({tokens[n - 1], " "}, gtx.allocator))
				ui.text_select(s, 0, len(s.buf))
				r.changed = true
			}
		}
	}
	if r.removed >= 0 && !r.pulled {
		d.refocus = r.removed + 1
	}
	d.focused = focused_any
	ui.close(&stack)
	ui.close(&box)
	ui.close(&frame)
	r.focused = focused_any
	r.id = input_id
	return
}

// Token_Lines is a token field's content laid out in lines: each shown
// token's place, the +N count and its place, the input's place and
// width, and the lines' height.
@(private)
Token_Lines :: struct {
	at:                 []ops.Point,
	count:              Text,
	count_at, input_at: ops.Point,
	input_w, content:   f32,
}

// token_field_lines lays the first shown tokens out in inner: each at its
// width, 4px apart, wrapping; then the +N count of the hidden; then the
// input, taking what is left of its line, or a line of its own when that
// is under TOKEN_INPUT_MIN (TextInputWithTokens.module.css:20-42).
@(private)
token_field_lines :: proc(gtx: ^ui.Ctx, tokens: []string, shown: int, size: Token_Size, removable: bool, inner: f32) -> (ln: Token_Lines) {
	lh := token_metrics(size).height
	x, y: f32
	place :: proc(x, y: ^f32, w, inner, lh: f32) -> ops.Point {
		if x^ > 0 && x^ + w > inner {
			x^ = 0
			y^ += lh + TOKEN_GAP
		}
		p := ops.Point{x^, y^}
		x^ += w + TOKEN_GAP
		return p
	}
	ln.at = make([]ops.Point, shown, gtx.allocator)
	for i in 0 ..< shown {
		ln.at[i] = place(&x, &y, token_width(gtx, tokens[i], size, removable), inner, lh)
	}
	if hidden := len(tokens) - shown; hidden > 0 {
		cst := tok.Type_Style{weight = tok.BASE_TEXT_WEIGHT_NORMAL, size = OVERFLOW_COUNT_SIZE[size], line_height = lh}
		ln.count = design.shape_style(gtx, fmt.aprintf("+%d", hidden, allocator = gtx.allocator), cst, font_for(gtx, cst.weight))
		ln.count_at = place(&x, &y, ln.count.width, inner, lh)
	}
	if x > 0 && x + TOKEN_INPUT_MIN > inner {
		x = 0
		y += lh + TOKEN_GAP
	}
	ln.input_at = {x, y}
	ln.input_w = max(inner - x, 0)
	ln.content = y + lh
	return
}

// token_field_steer reads the keys the tokens and the input heard and
// moves focus where they lead, before anything is drawn, so the token
// they reach is already the tab stop that hears the next key. It returns
// the token focus goes to, -1 for the input, -2 for no move.
@(private)
token_field_steer :: proc(gtx: ^ui.Ctx, d: ^Token_Field_Data, s: ^ui.Text_State, input: ops.Area_Id, shown: int) -> int {
	n := min(shown, TOKEN_FIELD_MAX)
	for i in 0 ..< n {
		if d.ids[i] != 0 {
			token_field_token_keys(gtx, d, d.ids[i], i)
		}
	}
	token_field_input_keys(gtx, d, s, input)
	target := token_field_target(d, n)
	switch {
	case target == -1:
		ui.focus_request(gtx, input)
	case target >= 0:
		ui.focus_request(gtx, d.ids[target])
	}
	return target
}

// paint_field_icon draws a field's 16px visual at pos, or a spinner there.
@(private)
paint_field_icon :: proc(gtx: ^ui.Ctx, ic: Icon, pos: ops.Point, spinning: bool, c: ops.Color) {
	if spinning {
		paint_spinner(gtx, pos, BUTTON_ICON, c)
	} else {
		icon(gtx, ic, pos, BUTTON_ICON, c)
	}
}

// OVERFLOW_COUNT_SIZE is the +N count's text size per token size
// (TextInputWithTokens.module.css:44-62).
@(private)
OVERFLOW_COUNT_SIZE := [Token_Size]f32 {
	.Small  = tok.TEXT_BODY_SIZE_SMALL,
	.Medium = tok.TEXT_BODY_SIZE_MEDIUM,
	.Large  = tok.TEXT_BODY_SIZE_MEDIUM,
	.XLarge = tok.TEXT_BODY_SIZE_LARGE,
}

// token_field_token_keys reads the arrows, Home, End and Escape the
// token at index heard (TextInputWithTokens.tsx:132-185,204-208).
@(private)
token_field_token_keys :: proc(gtx: ^ui.Ctx, d: ^Token_Field_Data, id: ops.Area_Id, index: int) {
	for e in ui.events(gtx, id) {
		if e.kind != .Key {
			continue
		}
		#partial switch e.key {
		case .Left, .Right, .Home, .End, .Escape:
			d.pending = {index, e.key}
		}
	}
}

// token_field_input_keys reads ArrowLeft with the input's caret at its
// start and ArrowRight at its end, which leave the input for the tokens;
// elsewhere they move the caret (focus-zone.mjs:82-110).
@(private)
token_field_input_keys :: proc(gtx: ^ui.Ctx, d: ^Token_Field_Data, s: ^ui.Text_State, input: ops.Area_Id) {
	for e in ui.events(gtx, input) {
		if e.kind != .Key || e.mods != {} {
			continue
		}
		lo, hi := ui.text_selection(s)
		switch {
		case e.key == .Left && lo == 0 && hi == 0:
			d.pending = {-1, .Left}
		case e.key == .Right && lo == len(s.buf) && hi == len(s.buf):
			d.pending = {-1, .Right}
		}
	}
}

// token_field_target is where focus goes this frame among n tokens, -1
// for the input, -2 for nowhere new: after a removal, the token that took
// the removed one's place, else the first, else the input
// (TextInputWithTokens.tsx:164-185); after an arrow, the next along the
// ring of the input then each token, wrapping (TextInputWithTokens.tsx
// :132-162).
@(private)
token_field_target :: proc(d: ^Token_Field_Data, n: int) -> (target: int) {
	target = -2
	if d.refocus > 0 {
		at := d.refocus - 1
		switch {
		case at < n:
			target = at
		case n > 0:
			target = 0
		case:
			target = -1
		}
		d.refocus = 0
	}
	mv := d.pending
	d.pending = {}
	from := mv.from
	#partial switch mv.key {
	case .Left:
		target = from < 0 ? n - 1 : from - 1
	case .Right:
		target = from + 1
		if target >= n {
			target = -1
		}
	case .Home, .Escape:
		target = -1
	case .End:
		target = n - 1
	}
	return
}

// bare_input is a token field's text input: unbordered, its text and caret
// on a line centred in size, in the field's type, editing s; it scrolls
// sideways to keep the caret in view. It reports Backspace in an empty
// input, which pulls the last token back.
@(private)
bare_input :: proc(gtx: ^ui.Ctx, s: ^ui.Text_State, id: ops.Area_Id, size: ops.Size, st: tok.Type_Style, placeholder: string, scroll: ^f32, sem: ops.Semantics, state: Interaction) -> (r: Field_Edit, edge: ui.Key) {
	p := ui.widget_open(gtx, u64(id))
	ui.text_clamp(s)
	box := ops.Rect{0, 0, size.x, size.y}
	c := control(gtx, id, box, state)
	font := font_for(gtx, st.weight)
	stops := ui.text_stops(gtx, s, font, st.size)
	text_y := (size.y - FIELD_LINE) / 2
	if c.st != nil {
		for e in ui.events(gtx, id) {
			#partial switch e.kind {
			case .Press, .Move, .Release:
				str := string(s.buf[:])
				ui.text_follow_pointer(s, design.layout_style(gtx, str, st, font), e, {e.pos.x + scroll^, 0}, stops)
			case .Text, .Paste:
				r.changed |= ui.text_edit(gtx, s, id, e, stops)
			case .Key:
				lo, hi := ui.text_selection(s)
				switch {
				case e.key == .Enter:
					r.submitted = true
				case e.key == .Backspace && len(s.buf) == 0 && lo == hi:
					edge = .Backspace
				case:
					r.changed |= ui.text_edit(gtx, s, id, e, stops)
				}
			}
		}
	}
	str := string(s.buf[:])
	t := design.layout_style(gtx, str, st, font)
	_, caret := ui.paragraph_caret(t, s.cursor)
	scroll^ = ui.text_scroll(scroll^, t.width + FIELD_CARET_W, caret, FIELD_CARET_W, size.x)
	r.focused = field_focused(c)
	r.id = id
	fg := color(c.disabled ? .Fg_Color_Disabled : .Fg_Color_Default)
	ops.clip_push(gtx.scene, box)
	if len(str) > 0 {
		design.draw_paragraph(gtx, t, {-scroll^, text_y}, fg, selection_paint(s, r.focused))
	} else if placeholder != "" {
		draw_text(gtx, design.shape_style(gtx, placeholder, st, font), {0, text_y}, color(.Fg_Color_Muted))
	}
	if r.focused && c.st != nil {
		ops.fill(gtx.scene, ops.Rect{caret - scroll^, text_y + 2, FIELD_CARET_W, FIELD_LINE - 4}, fg)
	}
	ops.clip_pop(gtx.scene)
	listen(gtx, c.st, id, box, design.EDIT_KINDS, .Text)
	out := sem
	out.label = ui.frame_string(gtx, sem.label)
	out.value = ui.frame_string(gtx, str)
	ops.tag(gtx.scene, id, out.label)
	ui.part_semantics(gtx, &p, id, box, out)
	ui.widget_close(gtx, &p, {size, text_y + (len(t.lines) > 0 ? t.lines[0].baseline : 0)})
	return
}

// Autocomplete.

// AUTOCOMPLETE_MAX is the most options an Autocomplete orders.
AUTOCOMPLETE_MAX :: 512

// AUTOCOMPLETE_PAD is the padding around the empty state and the loading
// spinner (AutocompleteMenu.module.css:1-9).
AUTOCOMPLETE_PAD :: tok.BASE_SIZE_16

// Autocomplete_Item is one option: its text, which the filter and the
// inline completion match and a single choice writes into the input,
// and ActionList's description and visuals.
Autocomplete_Item :: struct {
	text, description: string,
	leading, trailing: Icon,
	disabled:          bool,
}

// Autocomplete_Filter decides whether item shows for the typed text.
Autocomplete_Filter :: #type proc(item: Autocomplete_Item, text: string) -> bool

// autocomplete_prefix is the default filter: a case-insensitive prefix
// match on the item's text (AutocompleteMenu.tsx:33-37).
autocomplete_prefix :: proc(item: Autocomplete_Item, text: string) -> bool {
	return len(item.text) >= len(text) && strings.equal_fold(item.text[:len(text)], text)
}

// Autocomplete_Result is what one frame of an Autocomplete did.
Autocomplete_Result :: struct {
	changed: bool, // the selection changed
	edited:  bool, // the user changed the text
	added:   bool, // the add-new option was chosen: create a value from the text
	open:    bool, // the menu shows
	field:   Token_Field, // the input's frame
}

// Autocomplete_Data is what an Autocomplete keeps between frames.
@(private)
Autocomplete_Data :: struct {
	open:     bool,
	active:   int, // the highlighted option, among those shown
	typed:    int, // how much of the input the user typed; the rest is the inline completion
	suppress: bool, // Backspace: no completion until text is typed again
	input:    ops.Area_Id, // the input's area last frame
	focused:  bool,
	order:    [AUTOCOMPLETE_MAX]u16,
	ordered:  int, // how many items the order covers
}

// autocomplete is Primer's Autocomplete (autocomplete.json): a text input
// that opens a listbox of matching options under itself as the user
// types, or on ArrowDown or ArrowUp, and completes the highlighted one
// inline. items are every option; selected, as long as items, which are
// chosen. filter decides what shows for the typed text, by default
// autocomplete_prefix. Focus stays in the input: Up and Down move the
// highlight, wrapping, the pointer moving onto an option highlights it,
// and Enter chooses it; Home and End stay with the text (focus-zone.mjs
// :82-88). A single choice writes the option's text into the input and
// closes the menu; multiple toggles it, clears the input and stays open,
// and with tokens the choices show as tokens in a TextInputWithTokens.
// When the highlighted option starts with the typed text
// (case-sensitively) and is not chosen, the input shows its whole text
// with the untyped rest selected: typing goes on over it, Enter takes it
// and Backspace deletes it, after which nothing completes until more is
// typed; leaving the input drops it. Escape clears the text and closes
// the menu; leaving the input and a press outside close it. The options
// keep their order while the menu is open and are sorted chosen first as
// it closes. add_new appends an option with a plus icon that reports
// added; empty_text shows, padded 16px, when nothing matches; loading
// shows a spinner instead of the options. The menu is as wide as its
// widest option, at least 192px, unless width is a step.
//
// Departures: the empty state is a status node while it shows rather
// than an announcement after 250ms of quiet (AutocompleteMenu.tsx
// :129-131); onOpenChange's repeated calls (AutocompleteMenu.tsx:328-344)
// are not reproduced; items added after the first frame are ordered
// after the rest, where the upstream sort index misses them
// (AutocompleteMenu.tsx:171,219-235).
autocomplete :: proc(
	gtx: ^ui.Ctx,
	s: ^ui.Text_State,
	items: []Autocomplete_Item,
	selected: []bool,
	multiple := false,
	tokens := false,
	token_size := Token_Size.Large,
	filter: Autocomplete_Filter = nil,
	placeholder := "",
	add_new := "",
	empty_text := "No selectable options",
	loading := false,
	open_on_focus := false,
	width := Overlay_Width.Auto,
	block := false,
	name := "",
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> (r: Autocomplete_Result) {
	id := ui.claim_id(gtx, key, loc)
	d := ui.widget_data(gtx, id, Autocomplete_Data)
	// The field and its menu share an origin, so the menu hangs from it.
	stack := ui.stack_open(gtx, key = u64(ui.id_mix(id, 3)), loc = loc)
	defer ui.close(&stack)
	multi := multiple || tokens
	keep := filter if filter != nil else Autocomplete_Filter(autocomplete_prefix)
	autocomplete_cover(d, items, selected)
	typed := string(s.buf[:min(d.typed, len(s.buf))])
	shown := autocomplete_shown(gtx, d, items, typed, keep, add_new)
	enter, moved: bool
	if state == .Live {
		enter, moved = autocomplete_keys(gtx, d, s, len(shown))
	}
	d.active = len(shown) > 0 ? clamp(d.active, 0, len(shown) - 1) : 0
	base := ui.id_mix(id, 0x11)
	active_id: ops.Area_Id
	if d.open && len(shown) > 0 {
		active_id = action_list_item_id(base, d.active)
	}
	combo := Combobox{d.open, active_id}
	if tokens {
		texts := make([dynamic]string, gtx.allocator)
		owners := make([dynamic]int, gtx.allocator)
		for it, i in items {
			if i < len(selected) && selected[i] {
				append(&texts, it.text)
				append(&owners, i)
			}
		}
		r.field = text_input_with_tokens(gtx, s, texts[:], token_size, placeholder, block = block, name = name, combobox = combo, state = state, key = u64(ui.id_mix(id, 1)), loc = loc)
		if r.field.removed >= 0 {
			selected[owners[r.field.removed]] = false
			r.changed = true
		}
	} else {
		r.field.edit = text_input(gtx, s, placeholder, block = block, name = name, combobox = combo, state = state, key = u64(ui.id_mix(id, 1)), loc = loc)
		r.field.removed = -1
	}
	anchor := ui.last_widget(gtx)
	d.input = r.field.id
	if r.field.changed && !r.field.pulled {
		r.edited = true
		d.typed = len(s.buf)
		d.active = 0
		d.open = true
		typed = string(s.buf[:])
		shown = autocomplete_shown(gtx, d, items, typed, keep, add_new)
	}
	if r.field.focused && !d.focused && open_on_focus {
		d.open = true
	}
	if !r.field.focused && d.focused {
		// Leaving drops the completion and closes the menu
		// (AutocompleteInput.tsx:58-86).
		autocomplete_revert(d, s)
		d.open = false
	}
	d.focused = r.field.focused
	chosen := -1
	if enter && d.open && d.active < len(shown) {
		chosen = d.active
	}
	was_open := d.open
	a := anchored_overlay_open(gtx, &d.open, {0, anchor.size}, width = width, focus = {prevent = true}, trap = false, scroll = &popup_scroll(gtx, base).offset, key = u64(ui.id_mix(id, 2)))
	if a.visible {
		clicked := autocomplete_menu(gtx, d, items, selected, shown, multi, add_new, empty_text, loading, base, moved, &a)
		if clicked >= 0 {
			chosen = clicked
		}
	}
	anchored_overlay_close(&a)
	if chosen >= 0 && chosen < len(shown) {
		autocomplete_choose(d, s, items, selected, shown[chosen], multi, &r)
	} else if d.open && !d.suppress && r.field.focused {
		autocomplete_complete(d, s, items, selected, shown, typed)
	}
	if was_open && !d.open {
		autocomplete_revert(d, s)
		autocomplete_sort(d, selected)
	}
	r.open = d.open
	return
}

// AUTOCOMPLETE_ADD stands for the add-new option among the shown.
@(private)
AUTOCOMPLETE_ADD :: -1

// autocomplete_cover keeps d's order covering items: items that arrived
// since are appended in their own order, and an order over more items
// than there are is rebuilt, chosen first.
@(private)
autocomplete_cover :: proc(d: ^Autocomplete_Data, items: []Autocomplete_Item, selected: []bool) {
	n := min(len(items), AUTOCOMPLETE_MAX)
	if d.ordered > n || d.ordered == 0 {
		for i in 0 ..< n {
			d.order[i] = u16(i)
		}
		d.ordered = n
		autocomplete_sort(d, selected)
		return
	}
	for i in d.ordered ..< n {
		d.order[i] = u16(i)
	}
	d.ordered = n
}

// autocomplete_sort orders the chosen options first, keeping the rest in
// their order (sortOnCloseFn's default, AutocompleteMenu.tsx:29-30,
// 219-235).
@(private)
autocomplete_sort :: proc(d: ^Autocomplete_Data, selected: []bool) {
	out: [AUTOCOMPLETE_MAX]u16
	k := 0
	for pass in 0 ..< 2 {
		for i in 0 ..< d.ordered {
			o := int(d.order[i])
			on := o < len(selected) && selected[o]
			if on == (pass == 0) {
				out[k] = u16(o)
				k += 1
			}
		}
	}
	d.order = out
}

// autocomplete_shown is the options that show for typed, in d's order,
// then the add-new option.
@(private)
autocomplete_shown :: proc(gtx: ^ui.Ctx, d: ^Autocomplete_Data, items: []Autocomplete_Item, typed: string, keep: Autocomplete_Filter, add_new: string) -> []int {
	out := make([dynamic]int, gtx.allocator)
	for i in 0 ..< d.ordered {
		o := int(d.order[i])
		if keep(items[o], typed) {
			append(&out, o)
		}
	}
	if add_new != "" {
		append(&out, AUTOCOMPLETE_ADD)
	}
	return out[:]
}

// autocomplete_keys reads the keys the input heard this frame: ArrowDown
// or ArrowUp open a closed menu, else move the highlight, wrapping; Enter
// chooses; Escape clears the text and closes; Backspace stops the
// completion until more is typed (AutocompleteInput.tsx:88-174). It
// reports Enter and whether the highlight moved.
@(private)
autocomplete_keys :: proc(gtx: ^ui.Ctx, d: ^Autocomplete_Data, s: ^ui.Text_State, n: int) -> (enter, moved: bool) {
	if d.input == 0 {
		return
	}
	for e in ui.events(gtx, d.input) {
		#partial switch e.kind {
		case .Text:
			d.suppress = false
		case .Key:
			if .Alt in e.mods {
				continue
			}
			#partial switch e.key {
			case .Down, .Up:
				if !d.open {
					d.open = true
				} else if n > 0 {
					step := e.key == .Down ? 1 : -1
					d.active = (d.active + step + n) %% n
					moved = true
				}
			case .Enter:
				enter = true
			case .Escape:
				if len(s.buf) > 0 {
					ui.text_set(s, "")
					d.typed = 0
				}
				d.open = false
			case .Backspace:
				d.suppress = true
			}
		}
	}
	return
}

// autocomplete_revert drops the inline completion, leaving what was typed.
@(private)
autocomplete_revert :: proc(d: ^Autocomplete_Data, s: ^ui.Text_State) {
	if d.typed < len(s.buf) {
		resize(&s.buf, d.typed)
		ui.text_move(s, d.typed)
	}
}

// autocomplete_complete shows the highlighted option's untyped rest,
// selected, after what was typed, when the option starts with it
// (case-sensitively, AutocompleteMenu.tsx:317-326) and is not chosen.
@(private)
autocomplete_complete :: proc(d: ^Autocomplete_Data, s: ^ui.Text_State, items: []Autocomplete_Item, selected: []bool, shown: []int, typed: string) {
	if d.active >= len(shown) || len(typed) == 0 {
		autocomplete_revert(d, s)
		return
	}
	o := shown[d.active]
	if o == AUTOCOMPLETE_ADD || (o < len(selected) && selected[o]) || !strings.has_prefix(items[o].text, typed) {
		autocomplete_revert(d, s)
		return
	}
	full := items[o].text
	if string(s.buf[:]) != full {
		ui.text_set(s, full)
	}
	ui.text_select(s, len(typed), len(full))
}

// autocomplete_choose chooses option o (AutocompleteMenu.tsx:183-203):
// toggles it; a single choice clears the others, writes its text into
// the input with the caret at the end, and closes; multiple clears the
// input and stays open. The add-new option reports added.
@(private)
autocomplete_choose :: proc(d: ^Autocomplete_Data, s: ^ui.Text_State, items: []Autocomplete_Item, selected: []bool, o: int, multi: bool, r: ^Autocomplete_Result) {
	if o == AUTOCOMPLETE_ADD {
		r.added = true
		return
	}
	if o >= len(selected) || items[o].disabled {
		return
	}
	r.changed = true
	if multi {
		selected[o] = !selected[o]
		ui.text_set(s, "")
		d.typed = 0
		return
	}
	on := !selected[o]
	for &v in selected {
		v = false
	}
	selected[o] = on
	ui.text_set(s, items[o].text)
	ui.text_move(s, len(s.buf))
	d.typed = len(s.buf)
	d.open = false
}

// autocomplete_menu lays the open menu out: a spinner while loading, the
// empty text when nothing shows, else an inset listbox of the shown
// options whose highlighted one is both the active descendant and active
// (AutocompleteMenu.tsx:170-181,296-315). It returns the option clicked,
// as an index into shown, or -1.
@(private)
autocomplete_menu :: proc(
	gtx: ^ui.Ctx,
	d: ^Autocomplete_Data,
	items: []Autocomplete_Item,
	selected: []bool,
	shown: []int,
	multi: bool,
	add_new, empty_text: string,
	loading: bool,
	base: ops.Area_Id,
	moved: bool,
	a: ^Anchored_Overlay,
) -> int {
	if loading {
		pad := ui.inset_open(gtx, ui.pad_all(AUTOCOMPLETE_PAD))
		c := ui.centered_open(gtx)
		spinner(gtx, .Medium)
		ui.close(&c)
		ui.close(&pad)
		return -1
	}
	if len(shown) == 0 {
		if empty_text != "" {
			pad := ui.inset_open(gtx, ui.pad_all(AUTOCOMPLETE_PAD))
			ui.container_semantics(gtx, {role = .Status, label = ui.frame_string(gtx, empty_text)})
			text(gtx, empty_text, color = color(.Fg_Color_Muted))
			ui.close(&pad)
		}
		return -1
	}
	view := a.surface.look.data.size.y
	l := action_list_open(gtx, .Inset, multi ? .Multiple : .None, .Listbox, .Descendant, wrap = true, active = d.active, follow = moved, scroll = {&popup_scroll(gtx, base).offset, view, 0, tok.BASE_SIZE_8}, id_base = base)
	for o, i in shown {
		if o == AUTOCOMPLETE_ADD {
			action_list_item(&l, add_new, leading = .Plus, active = i == d.active)
			continue
		}
		it := items[o]
		on := o < len(selected) && selected[o]
		action_list_item(&l, it.text, it.description, leading = it.leading, trailing = it.trailing, selected = on, disabled = it.disabled, active = i == d.active)
	}
	action_list_close(&l)
	if l.hovered >= 0 {
		d.active = l.hovered
	}
	return l.activated
}

// Menu_Scroll is a popup list's scroll offset, kept by its owner so the
// highlighted option can be scrolled into view.
@(private)
Menu_Scroll :: struct {
	offset: ui.Scroll_Offset,
}

@(private)
popup_scroll :: proc(gtx: ^ui.Ctx, base: ops.Area_Id) -> ^Menu_Scroll {
	return ui.widget_data(gtx, ui.id_mix(base, 0x5c), Menu_Scroll)
}
