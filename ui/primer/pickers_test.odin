package primer

import "core:strings"
import "core:testing"
import "jm:ui"
import tok "jm:ui/primer/tokens"

// Behaviour of text_input_with_tokens, autocomplete and select_panel,
// driven through ui.Probe by tags.

// TextInputWithTokens.

@(private = "file")
Tokens_Model :: struct {
	text:    ui.Text_State,
	tokens:  [dynamic]string,
	visible: int,
	pulled:  bool,
}

@(private = "file")
tokens_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Tokens_Model)(user)
	col := ui.column_open(gtx, gap = 8, align = .Start)
	defer ui.close(&col)
	button(gtx, "Before")
	r := text_input_with_tokens(gtx, &m.text, m.tokens[:], placeholder = "Labels", width = 400, visible_count = m.visible)
	if r.removed >= 0 {
		ordered_remove(&m.tokens, r.removed)
		m.pulled = r.pulled
	}
	button(gtx, "After")
}

@(private = "file")
tokens_probe :: proc(p: ^ui.Probe, m: ^Tokens_Model) {
	m.tokens = make([dynamic]string, context.temp_allocator)
	append(&m.tokens, "bug", "docs", "ui")
	ui.probe_init(p, tokens_view, m, {600, 400}, allocator = context.temp_allocator)
}

@(test)
test_a_token_field_lays_tokens_then_its_input_in_one_well :: proc(t: ^testing.T) {
	m: Tokens_Model
	p: ui.Probe
	tokens_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer ui.text_destroy(&m.text)
	defer free_all(context.temp_allocator)

	bug, docs := ui.probe_bounds(&p, "bug"), ui.probe_bounds(&p, "docs")
	input := ui.probe_bounds(&p, "Labels")
	before := ui.probe_bounds(&p, "Before")
	top := before.y + before.h + 8
	// One line of xlarge tokens: 1 + 6 + 32 + 6 + 1 = 46px tall.
	after := ui.probe_bounds(&p, "After")
	testing.expect_value(t, after.y - 8 - top, 46)
	testing.expect_value(t, bug.h, tok.BASE_SIZE_32)
	testing.expect_value(t, bug.x, tok.BORDER_WIDTH_THIN + tok.BASE_SIZE_12) // 12px in from the border
	testing.expect_value(t, docs.x, bug.x + bug.w + TOKEN_GAP)
	testing.expect(t, input.x > docs.x && input.y == bug.y)
	testing.expect_value(t, input.x + input.w, 400 - tok.BORDER_WIDTH_THIN) // the input takes the rest of its line
	// Narrow, the tokens wrap 4px apart and the field grows.
	for _ in 0 ..< 4 {
		append(&m.tokens, "enhancement")
	}
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_bounds(&p, "After").y > after.y + 32)
}

@(test)
test_a_token_field_is_one_tab_stop_with_arrows_between_tokens :: proc(t: ^testing.T) {
	m: Tokens_Model
	p: ui.Probe
	tokens_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer ui.text_destroy(&m.text)
	defer free_all(context.temp_allocator)

	ui.probe_click(&p, "Before")
	ui.probe_key(&p, .Tab)
	testing.expect_value(t, ui.probe_focus_name(&p), "Labels") // the input, not a token
	ui.probe_key(&p, .Tab)
	testing.expect_value(t, ui.probe_focus_name(&p), "After")
	ui.probe_key(&p, .Tab, {.Shift})
	// ArrowLeft at the caret's start reaches the last token, then the one before.
	ui.probe_key(&p, .Left)
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_focus_name(&p), "ui")
	ui.probe_key(&p, .Left)
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_focus_name(&p), "docs")
	ui.probe_key(&p, .Right)
	ui.probe_key(&p, .Right)
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_focus_name(&p), "Labels") // past the last: the input
	// Backspace on a token removes it; focus takes the token in its place.
	ui.probe_key(&p, .Left)
	ui.probe_key(&p, .Left)
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_focus_name(&p), "docs")
	ui.probe_key(&p, .Backspace)
	testing.expect_value(t, len(m.tokens), 2)
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_focus_name(&p), "ui")
	// Escape returns to the input; Backspace in it pulls the last token back.
	ui.probe_key(&p, .Escape)
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_focus_name(&p), "Labels")
	ui.probe_key(&p, .Backspace)
	testing.expect_value(t, len(m.tokens), 1)
	testing.expect(t, m.pulled)
	testing.expect_value(t, ui.text_string(&m.text), "ui ")
	lo, hi := ui.text_selection(&m.text)
	testing.expect(t, lo == 0 && hi == 3)
}

@(test)
test_a_token_field_collapses_to_its_visible_count_without_focus :: proc(t: ^testing.T) {
	m: Tokens_Model
	p: ui.Probe
	tokens_probe(&p, &m)
	m.visible = 1
	ui.probe_frame(&p)
	defer ui.probe_destroy(&p)
	defer ui.text_destroy(&m.text)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_tagged(&p, "bug"))
	testing.expect(t, !ui.probe_tagged(&p, "docs"))
	testing.expect(t, ui.probe_click(&p, "Labels"))
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "docs")) // focused: every token
	ui.probe_click(&p, "Before")
	ui.probe_frame(&p)
	testing.expect(t, !ui.probe_tagged(&p, "docs"))
}

// Autocomplete.

@(private = "file")
AC_ITEMS := [4]Autocomplete_Item{{text = "Apple"}, {text = "Apricot"}, {text = "Banana"}, {text = "Cherry", disabled = true}}

@(private = "file")
Auto_Model :: struct {
	text:     ui.Text_State,
	selected: [4]bool,
	tokens:   bool,
	result:   Autocomplete_Result,
}

@(private = "file")
auto_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Auto_Model)(user)
	col := ui.column_open(gtx, gap = 8, align = .Start)
	defer ui.close(&col)
	button(gtx, "Before")
	m.result = autocomplete(gtx, &m.text, AC_ITEMS[:], m.selected[:], tokens = m.tokens, placeholder = "Fruit", add_new = m.tokens ? "Add fruit" : "")
	button(gtx, "After")
}

@(private = "file")
auto_probe :: proc(p: ^ui.Probe, m: ^Auto_Model) {
	ui.probe_init(p, auto_view, m, {600, 500}, allocator = context.temp_allocator)
}

@(test)
test_autocomplete_filters_completes_and_chooses_with_focus_in_the_input :: proc(t: ^testing.T) {
	m: Auto_Model
	p: ui.Probe
	auto_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer ui.text_destroy(&m.text)
	defer free_all(context.temp_allocator)

	ui.probe_click(&p, "Fruit")
	ui.probe_type(&p, "Ap")
	ui.probe_frame(&p)
	testing.expect(t, m.result.open)
	testing.expect(t, ui.probe_tagged(&p, "Apple") && ui.probe_tagged(&p, "Apricot") && !ui.probe_tagged(&p, "Banana"))
	testing.expect_value(t, ui.probe_focus_name(&p), "Fruit")
	// The highlighted option completes inline, its rest selected.
	testing.expect_value(t, ui.text_string(&m.text), "Apple")
	lo, hi := ui.text_selection(&m.text)
	testing.expect(t, lo == 2 && hi == 5)
	sem := ui.probe_semantics(&p, context.temp_allocator)
	testing.expectf(t, strings.contains(sem, "combo box \"Fruit\" value \"Apple\" expandable expanded active \"Apple\""), "%s", sem)
	// Down moves the highlight, and the completion follows it.
	ui.probe_key(&p, .Down)
	ui.probe_frame(&p)
	testing.expect_value(t, ui.text_string(&m.text), "Apricot")
	ui.probe_key(&p, .Down) // wraps
	ui.probe_frame(&p)
	testing.expect_value(t, ui.text_string(&m.text), "Apple")
	// Backspace deletes the completion and stops it until more is typed.
	ui.probe_key(&p, .Backspace)
	ui.probe_frame(&p)
	testing.expect_value(t, ui.text_string(&m.text), "Ap")
	ui.probe_type(&p, "r")
	ui.probe_frame(&p)
	testing.expect_value(t, ui.text_string(&m.text), "Apricot")
	// Enter chooses: the text, the selection, closed.
	ui.probe_key(&p, .Enter)
	ui.probe_frame(&p)
	testing.expect(t, m.selected[1] && !m.result.open)
	testing.expect_value(t, ui.text_string(&m.text), "Apricot")
	testing.expect(t, !ui.probe_tagged(&p, "Apple"))
}

@(test)
test_autocomplete_matches_case_blind_but_completes_case_exact :: proc(t: ^testing.T) {
	m: Auto_Model
	p: ui.Probe
	auto_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer ui.text_destroy(&m.text)
	defer free_all(context.temp_allocator)

	ui.probe_click(&p, "Fruit")
	ui.probe_type(&p, "ba")
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "Banana"))
	testing.expect_value(t, ui.text_string(&m.text), "ba") // "ba" is no prefix of "Banana" case-sensitively
	// Escape clears the text and closes.
	ui.probe_key(&p, .Escape)
	ui.probe_frame(&p)
	testing.expect_value(t, ui.text_string(&m.text), "")
	testing.expect(t, !m.result.open)
	// ArrowDown opens a closed menu without moving.
	ui.probe_key(&p, .Down)
	ui.probe_frame(&p)
	testing.expect(t, m.result.open)
	testing.expect(t, ui.probe_tagged(&p, "Cherry"))
	// A click on an option chooses it; a disabled one does nothing.
	ui.probe_click(&p, "Cherry")
	testing.expect(t, !m.selected[3])
	ui.probe_click(&p, "Banana")
	testing.expect(t, m.selected[2])
	testing.expect_value(t, ui.text_string(&m.text), "Banana")
	// Leaving the input closes the menu.
	ui.probe_key(&p, .Down)
	ui.probe_frame(&p)
	testing.expect(t, m.result.open)
	ui.probe_click(&p, "After")
	ui.probe_frame(&p)
	testing.expect(t, !m.result.open)
}

@(test)
test_autocomplete_with_tokens_toggles_choices_and_stays_open :: proc(t: ^testing.T) {
	m := Auto_Model{tokens = true}
	p: ui.Probe
	auto_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer ui.text_destroy(&m.text)
	defer free_all(context.temp_allocator)

	ui.probe_click(&p, "Fruit")
	ui.probe_key(&p, .Down)
	ui.probe_frame(&p)
	ui.probe_key(&p, .Enter)
	ui.probe_frame(&p)
	testing.expect(t, m.selected[0] && m.result.open) // chosen, and still open
	testing.expect(t, ui.probe_tagged(&p, "Apple")) // a token now, and an option
	ui.probe_type(&p, "Ban")
	ui.probe_frame(&p)
	ui.probe_key(&p, .Enter)
	ui.probe_frame(&p)
	testing.expect(t, m.selected[2])
	testing.expect_value(t, ui.text_string(&m.text), "") // the input clears
	// The add-new option follows the matches.
	ui.probe_type(&p, "Kiwi")
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "Add fruit"))
	ui.probe_key(&p, .Enter)
	testing.expect(t, m.result.added)
	// Backspace in the empty input removes the last token: deselects it.
	ui.text_set(&m.text, "")
	ui.probe_frame(&p)
	ui.probe_key(&p, .Backspace)
	testing.expect(t, !m.selected[2] && m.selected[0])
}

// SelectPanel.

@(private = "file")
SP_ITEMS := [4]Select_Panel_Item{{text = "bug", group = -1}, {text = "docs", group = -1}, {text = "ui", group = -1}, {text = "wontfix", group = -1, disabled = true}}

@(private = "file")
Panel_Model :: struct {
	open:     bool,
	filter:   ui.Text_State,
	selected: [4]bool,
	multiple: bool,
	modal:    bool,
	result:   Select_Panel_Result,
	filtered: int,
}

@(private = "file")
panel_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Panel_Model)(user)
	col := ui.column_open(gtx, gap = 8, align = .Start)
	defer ui.close(&col)
	button(gtx, "Before")
	st := ui.stack_open(gtx)
	defer ui.close(&st)
	select_panel_button(gtx, &m.open, SP_ITEMS[:], m.selected[:], "Labels")
	anchor := ui.last_widget(gtx)
	// The caller filters: a case-blind prefix, here.
	items := make([dynamic]Select_Panel_Item, context.temp_allocator)
	flags := make([dynamic]bool, context.temp_allocator)
	owners := make([dynamic]int, context.temp_allocator)
	text := ui.text_string(&m.filter)
	for it, i in SP_ITEMS {
		if strings.has_prefix(it.text, text) {
			append(&items, it)
			append(&flags, m.selected[i])
			append(&owners, i)
		}
	}
	m.result = select_panel(gtx, &m.open, anchor, &m.filter, items[:], flags[:], multiple = m.multiple, variant = m.modal ? .Modal : .Anchored, title = "Apply labels")
	for f, i in flags {
		m.selected[owners[i]] = f
	}
	if m.result.filtered {
		m.filtered += 1
	}
}

@(private = "file")
panel_probe :: proc(p: ^ui.Probe, m: ^Panel_Model) {
	ui.probe_init(p, panel_view, m, {800, 600}, allocator = context.temp_allocator)
}

@(test)
test_a_select_panel_keeps_focus_in_its_filter_and_highlights_with_arrows :: proc(t: ^testing.T) {
	m := Panel_Model{multiple = true}
	p: ui.Probe
	panel_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer ui.text_destroy(&m.filter)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Labels"))
	ui.probe_frame(&p)
	testing.expect(t, m.open)
	testing.expect_value(t, ui.probe_focus_name(&p), "Filter items") // focus went to the filter
	sem := ui.probe_semantics(&p, context.temp_allocator)
	testing.expectf(t, strings.contains(sem, "active \"bug\""), "the first option is the active descendant\n%s", sem)
	ui.probe_key(&p, .Down)
	ui.probe_key(&p, .Enter)
	testing.expect(t, m.selected[1] && m.open) // multiple: toggled, still open
	testing.expect_value(t, ui.probe_focus_name(&p), "Filter items")
	ui.probe_key(&p, .Up)
	ui.probe_key(&p, .Up) // wraps to the last
	ui.probe_frame(&p)
	sem = ui.probe_semantics(&p, context.temp_allocator)
	testing.expectf(t, strings.contains(sem, "active \"wontfix\""), "%s", sem)
	ui.probe_key(&p, .Enter) // a disabled option does nothing
	testing.expect(t, !m.selected[3])
	ui.probe_key(&p, .Page_Up)
	ui.probe_frame(&p)
	sem = ui.probe_semantics(&p, context.temp_allocator)
	testing.expectf(t, strings.contains(sem, "active \"bug\""), "%s", sem)
	// Typing reports the filter; the caller's items come back.
	ui.probe_type(&p, "u")
	ui.probe_frame(&p)
	testing.expect(t, m.filtered > 0)
	testing.expect(t, ui.probe_tagged(&p, "ui") && !ui.probe_tagged(&p, "bug"))
	// Escape closes it and focus goes back to the button.
	ui.probe_key(&p, .Escape)
	testing.expect_value(t, m.result.closed, Panel_Gesture.Escape)
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_focus_name(&p), "docs") // the button now shows the selection
}

@(test)
test_an_anchored_single_panel_chooses_and_closes :: proc(t: ^testing.T) {
	m: Panel_Model
	p: ui.Probe
	panel_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer ui.text_destroy(&m.filter)
	defer free_all(context.temp_allocator)

	ui.probe_click(&p, "Labels")
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_click(&p, "docs"))
	testing.expect(t, m.selected[1] && !m.open)
	testing.expect_value(t, m.result.closed, Panel_Gesture.Selection)
	// Choosing the selection again clears it. (The button reads "docs"
	// now: it is opened by the key, focus being back on it.)
	ui.probe_frame(&p)
	ui.probe_key(&p, .Enter)
	ui.probe_frame(&p)
	testing.expect(t, m.open)
	ui.probe_key(&p, .Down)
	ui.probe_key(&p, .Enter)
	testing.expect(t, !m.selected[1] && !m.open)
}

@(test)
test_a_modal_single_panel_holds_its_choice_until_save :: proc(t: ^testing.T) {
	m := Panel_Model{modal = true}
	p: ui.Probe
	panel_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer ui.text_destroy(&m.filter)
	defer free_all(context.temp_allocator)

	ui.probe_click(&p, "Labels")
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_focus_name(&p), "Filter items")
	ui.probe_click(&p, "ui")
	testing.expect(t, m.open && !m.selected[2]) // only pending
	testing.expect(t, ui.probe_click(&p, "Save"))
	testing.expect(t, m.selected[2] && !m.open)
	// Cancel keeps the selection as it was.
	ui.probe_frame(&p)
	ui.probe_click(&p, "ui") // the button, which shows the selection now
	ui.probe_frame(&p)
	testing.expect(t, m.open)
	ui.probe_click(&p, "bug")
	ui.probe_click(&p, "Cancel")
	testing.expect(t, m.selected[2] && !m.selected[0] && !m.open)
	testing.expectf(t, m.result.closed == .Cancel, "closed by %v, open %v", m.result.closed, m.open)
}

