package primer

import "core:fmt"
import "core:strings"
import "core:testing"
import "jm:ui"
import "jm:ui/design"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// Behaviour of Pagination, SubNav and UnderlinePanels, driven through
// ui.Probe by tags.

// model_string writes a pagination model as pagination.json's
// model-examples behaviour does ("1 … 4 5 6 7 8 … 15"), the current page
// in brackets.
@(private = "file")
model_string :: proc(count, current: int, margin := 1, surrounding := 2) -> string {
	b := strings.builder_make(context.temp_allocator)
	for e in pagination_model(count, current, true, margin, surrounding, context.temp_allocator) {
		switch e.kind {
		case .Previous, .Next:
		case .Break:
			strings.write_string(&b, "… ")
		case .Number:
			fmt.sbprintf(&b, e.selected ? "[%d] " : "%d ", e.num)
		}
	}
	return strings.trim_space(strings.to_string(b))
}

@(test)
test_pagination_model_matches_the_spec_examples :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	testing.expect_value(t, model_string(15, 1), "[1] 2 3 4 5 6 7 … 15")
	testing.expect_value(t, model_string(15, 6), "1 … 4 5 [6] 7 8 … 15")
	testing.expect_value(t, model_string(15, 9), "1 … 7 8 [9] 10 11 … 15")
	testing.expect_value(t, model_string(15, 15), "1 … 9 10 11 12 13 14 [15]")
	testing.expect_value(t, model_string(9, 5), "1 2 3 4 [5] 6 7 8 9") // 9 fit: no ellipsis
	testing.expect_value(t, model_string(10, 5), "1 2 3 4 [5] 6 7 … 10") // an ellipsis never stands for one page
	testing.expect_value(t, model_string(20, 10, 2, 1), "1 2 … 9 [10] 11 … 19 20")
	m := pagination_model(15, 1, true, 1, 2, context.temp_allocator)
	testing.expect(t, m[0].kind == .Previous && m[0].disabled)
	testing.expect(t, m[7].precedes_break) // 7 comes before the ellipsis
	testing.expect(t, !m[len(m) - 1].disabled)
	none := pagination_model(0, 1, true, 1, 2, context.temp_allocator)
	testing.expect_value(t, len(none), 2)
	testing.expect(t, none[1].disabled) // no pages: Next is disabled too
	ends := pagination_model(5, 3, false, 1, 2, context.temp_allocator)
	testing.expect_value(t, len(ends), 2)
}

@(private = "file")
Nav_Model :: struct {
	page:      int,
	count:     int,
	hide:      Viewport_Ranges,
	changes:   int,
	links:     [3]Sub_Nav_Link,
	sub:       int,
	tab:       int,
	mode:      Activation_Mode,
	fired:     int,
	changed:   int,
	shown_tab: int,
}

@(private = "file")
nav_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Nav_Model)(user)
	col := ui.column_open(gtx, align = .Fill)
	defer ui.close(&col)
	if pagination(gtx, &m.page, m.count, hide_pages = m.hide) {
		m.changes += 1
	}
	sn := sub_nav_open(gtx, "Labels and milestones", m.links[:])
	button(gtx, "New label", .Primary)
	if sn.clicked >= 0 {
		m.sub = sn.clicked
	}
	sub_nav_close(&sn)
	tabs := [3]Underline_Tab{{"Code", .Code, ""}, {"Issues", .Issue_Opened, "12"}, {"Pull requests", .Git_Pull_Request, "3"}}
	up := underline_panels_open(gtx, "Repository", tabs[:], &m.tab, m.mode)
	m.shown_tab = m.tab
	if up.changed {
		m.changed += 1
	}
	if up.selected_by >= 0 {
		m.fired += 1
	}
	underline_panels_close(&up)
}

@(private = "file")
nav_probe :: proc(p: ^ui.Probe, m: ^Nav_Model, size := ops.Size{900, 600}) {
	m.page, m.count = 6, 15
	m.links = {{"Labels", true}, {"Milestones", false}, {"Projects", false}}
	ui.probe_init(p, nav_view, m, size, allocator = context.temp_allocator)
}

@(test)
test_pagination_pages_and_geometry :: proc(t: ^testing.T) {
	m: Nav_Model
	p: ui.Probe
	nav_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	box := ui.probe_bounds(&p, "Pagination")
	testing.expect_value(t, box.h, PAGINATION_MARGIN[0] + PAGE_ENTRY + PAGINATION_MARGIN[1]) // 20 + 32 + 15
	six := ui.probe_bounds(&p, "Page 6")
	seven := ui.probe_bounds(&p, "Page 7")
	testing.expect_value(t, six, ops.Rect{six.x, 20, PAGE_ENTRY, PAGE_ENTRY}) // a lone digit: the 32px minimum
	testing.expect_value(t, seven.x, six.x + PAGE_ENTRY + PAGE_GAP) // 4px apart
	prev := ui.probe_bounds(&p, "Previous Page")
	gtx := ui.Ctx{shaper = p.shaper, allocator = context.temp_allocator}
	st := page_style()
	word := design.shape_style(&gtx, "Previous", st, font_for(&gtx, st.weight))
	want := 2 * PAGE_PAD + st.size + PAGE_GAP + word.width // 6px, 1em chevron, 4px, text, 6px
	testing.expectf(t, abs(prev.w - want) < 0.01, "Previous is %v wide, want %v", prev.w, want)
	next := ui.probe_bounds(&p, "Next Page")
	testing.expect(t, abs((prev.x - box.x) - (box.x + box.w - next.x - next.w)) < 0.01, "centred")
	testing.expect(t, ui.probe_tagged(&p, "Page 1...")) // the page before an ellipsis says so
	testing.expect(t, ui.probe_tagged(&p, "Page 8..."))
	testing.expect(t, ui.probe_tagged(&p, "Page 15"))
	testing.expect(t, !ui.probe_tagged(&p, "Page 9"))
	said := ui.probe_semantics(&p, context.temp_allocator)
	testing.expectf(t, strings.contains(said, "navigation \"Pagination\""), "%s", said)
	testing.expectf(t, strings.contains(said, "link \"Page 6\" current page"), "%s", said)
	testing.expectf(t, !strings.contains(said, "\"…\""), "an ellipsis is presentational: %s", said)
}

@(test)
test_pagination_activates_pages_and_skips_disabled_ends :: proc(t: ^testing.T) {
	m: Nav_Model
	p: ui.Probe
	nav_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Next Page"))
	testing.expect_value(t, m.page, 7)
	testing.expect(t, ui.probe_click(&p, "Page 1..."))
	testing.expect_value(t, m.page, 1)
	ui.probe_frame(&p)
	ui.probe_click(&p, "Previous Page") // disabled on page 1: no input area
	testing.expect_value(t, m.page, 1)
	said := ui.probe_semantics(&p, context.temp_allocator)
	testing.expectf(t, !strings.contains(said, "Previous Page"), "a disabled end is hidden: %s", said)
	ui.probe_key(&p, .Tab) // Previous is skipped: Tab lands on page 1
	ui.probe_key(&p, .Tab)
	ui.probe_key(&p, .Enter)
	testing.expect_value(t, m.page, 2)
	testing.expect_value(t, m.changes, 3)
}

@(test)
test_pagination_hides_numbers_per_range :: proc(t: ^testing.T) {
	m: Nav_Model
	p: ui.Probe
	nav_probe(&p, &m, {1500, 600})
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	m.hide = {.Regular}
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "Page 6")) // 1500px is wide, not regular
	m.hide = {.Wide}
	ui.probe_frame(&p)
	testing.expect(t, !ui.probe_tagged(&p, "Page 6"))
	prev, next := ui.probe_bounds(&p, "Previous Page"), ui.probe_bounds(&p, "Next Page")
	testing.expect_value(t, next.x, prev.x + prev.w) // no gap between the ends
}

@(test)
test_sub_nav_links_share_borders_and_report_clicks :: proc(t: ^testing.T) {
	m: Nav_Model
	p: ui.Probe
	nav_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	labels := ui.probe_bounds(&p, "Labels")
	miles := ui.probe_bounds(&p, "Milestones")
	testing.expect_value(t, labels.h, SUB_NAV_LINK)
	gtx := ui.Ctx{shaper = p.shaper, allocator = context.temp_allocator}
	st := tok.Type_Style{weight = tok.BASE_TEXT_WEIGHT_MEDIUM, size = tok.TEXT_BODY_SIZE_MEDIUM, line_height = SUB_NAV_LINE}
	w := design.shape_style(&gtx, "Labels", st, font_for(&gtx, st.weight)).width
	testing.expect_value(t, labels.w, 1 + 16 + w + 16 + 1) // first: both borders
	testing.expect_value(t, miles.x, labels.x + labels.w) // joined edge to edge
	action := ui.probe_bounds(&p, "New label")
	testing.expect_value(t, action.x + action.w, 900) // actions at the far end
	testing.expect(t, ui.probe_click(&p, "Projects"))
	testing.expect_value(t, m.sub, 2)
	said := ui.probe_semantics(&p, context.temp_allocator)
	testing.expectf(t, strings.contains(said, "navigation \"Labels and milestones\""), "%s", said)
	testing.expectf(t, strings.contains(said, "link \"Labels\" current at"), "aria-current=true, not page: %s", said)
}

@(test)
test_underline_panels_select_by_press_arrows_and_keys :: proc(t: ^testing.T) {
	m: Nav_Model
	p: ui.Probe
	nav_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	code := ui.probe_bounds(&p, "Code")
	repo := ui.probe_bounds(&p, "Repository")
	testing.expect_value(t, repo.h, UNDERLINE_STRIP)
	testing.expect_value(t, code.y, repo.y + 8)
	testing.expect_value(t, code.h, UNDERLINE_TAB)
	testing.expect_value(t, code.x, repo.x + 16)
	issues := ui.probe_bounds(&p, "Issues")
	testing.expect_value(t, issues.x, code.x + code.w + 8)
	// The underline sits on the strip's bottom edge, under the selected tab.
	found := false
	for d in ui.probe_current(&p).draws {
		if f, ok := d.cmd.(ops.Fill); ok {
			if c, solid := f.paint.(ops.Color); solid && c == color(.Underline_Nav_Border_Color_Active) {
				r := f.shape.(ops.Rect)
				at := ops.apply(d.transform, {r.x, r.y})
				testing.expect_value(t, at, ops.Point{code.x, repo.y + repo.h - 2})
				testing.expect_value(t, r.w, code.w)
				found = true
			}
		}
	}
	testing.expect(t, found)
	// A press selects (on the way down) and fires the tab's onSelect.
	testing.expect(t, ui.probe_click(&p, "Issues"))
	testing.expect_value(t, m.tab, 1)
	testing.expect_value(t, m.fired, 1)
	// Arrows move and, automatically, select, wrapping; onSelect stays.
	ui.probe_key(&p, .Right)
	ui.probe_frame(&p)
	testing.expect_value(t, m.tab, 2)
	ui.probe_key(&p, .Right)
	ui.probe_frame(&p)
	testing.expect_value(t, m.tab, 0)
	ui.probe_key(&p, .End)
	ui.probe_frame(&p)
	testing.expect_value(t, m.tab, 2)
	testing.expect_value(t, m.fired, 1)
	testing.expect_value(t, m.changed, 4)
	said := ui.probe_semantics(&p, context.temp_allocator)
	testing.expectf(t, strings.contains(said, "tab \"Pull requests\" desc \"3\" selected"), "%s", said)
	testing.expectf(t, strings.contains(said, "tab panel \"Pull requests\""), "%s", said)
}

@(test)
test_underline_panels_manual_mode_moves_focus_only :: proc(t: ^testing.T) {
	m: Nav_Model
	p: ui.Probe
	nav_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	m.mode = .Manual
	ui.probe_click(&p, "Code")
	ui.probe_key(&p, .Right)
	ui.probe_frame(&p)
	testing.expect_value(t, m.tab, 0) // focus moved, the selection did not
	ui.probe_key(&p, .Enter)
	ui.probe_frame(&p)
	testing.expect_value(t, m.tab, 1)
	testing.expect_value(t, m.fired, 2) // the press, then Enter
}
