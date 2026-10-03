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
	accent_strokes :: proc(p: ^ui.Probe) -> (n: int) {
		for op in p.scene.ops {
			if st, ok := op.(ops.Stroke); ok {
				if c, solid := st.paint.(ops.Color); solid && c == color(.Bg_Color_Accent_Emphasis) {
					n += 1
				}
			}
		}
		return
	}
	before := accent_strokes(&p) // the selected sub nav link's border
	ui.probe_key(&p, .Tab) // Previous is skipped: Tab lands on page 1
	ui.probe_key(&p, .Tab)
	ui.probe_frame(&p)
	testing.expect_value(t, accent_strokes(&p), before + 1) // keyboard focus outlines page 2 in --bgColor-accent-emphasis
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
	// One Tab stop, held by the tab the arrows reached until Enter selects.
	ui.probe_key(&p, .Tab)
	testing.expect(t, focus_name(&p) != "Pull requests")
	ui.probe_key(&p, .Tab, {.Shift})
	testing.expect_value(t, focus_name(&p), "Issues")
	ui.probe_key(&p, .Enter)
	ui.probe_frame(&p)
	testing.expect_value(t, m.tab, 1)
	testing.expect_value(t, m.fired, 2) // the press, then Enter
}

@(test)
test_breadcrumbs_fold_by_width_and_by_count :: proc(t: ^testing.T) {
	w4 := []f32{200, 200, 200, 200}
	w6 := []f32{100, 100, 100, 100, 100, 100}
	folded, hide := breadcrumbs_fold(w6, 1000, 28, false)
	testing.expect_value(t, folded, 2) // everything fits, but menu shows at most 4
	testing.expect(t, hide)
	folded, _ = breadcrumbs_fold(w4, 600, 28, false)
	testing.expect_value(t, folded, 2) // 4 x 216 > 600; 3 x 216 + 28 > 600; 2 x 216 + 28 fits
	folded, _ = breadcrumbs_fold([]f32{60, 60, 60}, 500, 28, false)
	testing.expect_value(t, folded, 2) // under 544px with more than two: one crumb stays
	folded, hide = breadcrumbs_fold([]f32{50, 100, 100, 100, 100}, 2000, 28, true)
	testing.expect_value(t, folded, 1) // four after the root, three may stay: the first after the root folds, never the root
	testing.expect(t, !hide)
	folded, hide = breadcrumbs_fold([]f32{50, 100, 100}, 2000, 28, true)
	testing.expect_value(t, folded, 0)
	folded, hide = breadcrumbs_fold([]f32{50, 400}, 300, 28, true)
	testing.expect_value(t, folded, 0)
	testing.expect(t, hide) // the last crumb alone is too wide: the root goes into the menu
	folded, _ = breadcrumbs_fold(nil, 300, 28, false)
	testing.expect_value(t, folded, 0)
}

@(private = "file")
Crumbs_Model :: struct {
	overflow: Breadcrumbs_Overflow,
	variant:  Breadcrumbs_Variant,
	clicked:  int,
	width:    f32,
}

@(private = "file")
crumbs_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Crumbs_Model)(user)
	col := ui.column_open(gtx, align = .Start)
	defer ui.close(&col)
	box := ui.sized_open(gtx, {min = {m.width, 0}, max = {m.width, ui.INF}})
	defer ui.close(&box)
	items := [6]Breadcrumb{{"github", false}, {"primer", false}, {"react", false}, {"src", false}, {"Breadcrumbs", false}, {"Breadcrumbs.tsx", true}}
	if at := breadcrumbs(gtx, items[:], m.overflow, m.variant); at >= 0 {
		m.clicked = at
	}
}

@(test)
test_breadcrumbs_wrap_mode_shows_every_crumb_and_marks_the_page :: proc(t: ^testing.T) {
	m := Crumbs_Model{width = 900, clicked = -1}
	p: ui.Probe
	ui.probe_init(&p, crumbs_view, &m, {900, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	gh, pr := ui.probe_bounds(&p, "github"), ui.probe_bounds(&p, "primer")
	testing.expect_value(t, gh.h, style(.Body_Medium).line_height)
	testing.expect(t, abs(pr.x - (gh.x + gh.w + 2 * CRUMB_RULE.margin + CRUMB_RULE.stroke)) < 0.01, "a rule and 0.5em either side between crumbs")
	testing.expect(t, ui.probe_click(&p, "primer"))
	testing.expect_value(t, m.clicked, 1)
	said := ui.probe_semantics(&p, context.temp_allocator)
	testing.expectf(t, strings.contains(said, "navigation \"Breadcrumbs\""), "%s", said)
	testing.expectf(t, strings.contains(said, "link \"Breadcrumbs.tsx\" current page"), "%s", said)
	m.width = 200 // wraps onto more lines
	ui.probe_frame(&p)
	last := ui.probe_bounds(&p, "Breadcrumbs.tsx")
	testing.expect(t, last.y > gh.y)
	m.variant = .Spacious
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_bounds(&p, "github").h, style(.Body_Medium).line_height + 2 * tok.BASE_SIZE_4)
}

@(test)
test_breadcrumbs_menu_folds_leading_crumbs :: proc(t: ^testing.T) {
	m := Crumbs_Model{width = 900, clicked = -1, overflow = .Menu}
	p: ui.Probe
	ui.probe_init(&p, crumbs_view, &m, {900, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_tagged(&p, "2 more breadcrumb items")) // six crumbs, four stay
	testing.expect(t, !ui.probe_tagged(&p, "github"))
	testing.expect(t, ui.probe_tagged(&p, "react"))
	testing.expect(t, ui.probe_click(&p, "2 more breadcrumb items"))
	ui.probe_frame(&p)
	said := ui.probe_semantics(&p, context.temp_allocator)
	testing.expectf(t, strings.contains(said, "button \"2 more breadcrumb items\" expandable expanded"), "%s", said)
	testing.expectf(t, strings.contains(said, "list \"Breadcrumbs\""), "the menu is an ActionList of links: %s", said)
	testing.expectf(t, strings.contains(said, "link \"github\""), "%s", said)
	testing.expect(t, ui.probe_click(&p, "primer"))
	testing.expect_value(t, m.clicked, 1)
	m.overflow = .Menu_With_Root
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "github")) // the root stays
	testing.expect(t, ui.probe_tagged(&p, "2 more breadcrumb items")) // primer and react
	testing.expect(t, !ui.probe_tagged(&p, "react"))
	gh, more := ui.probe_bounds(&p, "github"), ui.probe_bounds(&p, "2 more breadcrumb items")
	testing.expect(t, abs(more.x - (gh.x + gh.w + CRUMB_GLYPH)) < 0.01, "the button follows the root's 16px slash")
}

@(private = "file")
Unav_Model :: struct {
	current, clicked: int,
	width:            f32,
}

@(private = "file")
unav_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Unav_Model)(user)
	col := ui.column_open(gtx, align = .Start)
	defer ui.close(&col)
	box := ui.sized_open(gtx, {min = {m.width, 0}, max = {m.width, ui.INF}})
	defer ui.close(&box)
	items := [5]Underline_Tab{{"Code", .Code, ""}, {"Issues", .Issue_Opened, "30"}, {"Pull requests", .Git_Pull_Request, "3"}, {"Discussions", .Comment_Discussion, ""}, {"Security", .Shield, ""}}
	if at := underline_nav(gtx, "Repository", items[:], m.current); at >= 0 {
		m.clicked = at
		m.current = at
	}
}

@(test)
test_underline_nav_moves_items_that_break_into_more :: proc(t: ^testing.T) {
	m := Unav_Model{width = 1000, clicked = -1, current = 4}
	p: ui.Probe
	ui.probe_init(&p, unav_view, &m, {1000, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	code := ui.probe_bounds(&p, "Code")
	testing.expect_value(t, code, ops.Rect{16, 8, code.w, UNDERLINE_TAB})
	testing.expect(t, ui.probe_tagged(&p, "Security"))
	testing.expect(t, !ui.probe_tagged(&p, "More"))
	gtx := ui.Ctx{shaper = p.shaper, allocator = context.temp_allocator}
	icon_w := measure_underline_tab(&gtx, {"Code", .Code, ""}, false).w
	testing.expect(t, abs(code.w - icon_w) < 0.01, "1000px: icons show")
	m.width = 500
	ui.probe_frame(&p)
	code = ui.probe_bounds(&p, "Code")
	testing.expect(t, abs(code.w - measure_underline_tab(&gtx, {"Code", .None, ""}, false).w) < 0.01, "under 768px: no icons")
	testing.expect(t, ui.probe_tagged(&p, "More"))
	testing.expect(t, !ui.probe_tagged(&p, "Security")) // a leading run stays
	more := ui.probe_bounds(&p, "More")
	testing.expect(t, more.x + more.w <= 500 - 16 + 0.01)
	said := ui.probe_semantics(&p, context.temp_allocator)
	testing.expectf(t, strings.contains(said, "\"More items, including current item\""), "%s", said)
	testing.expectf(t, strings.contains(said, "heading \"Repository navigation\" level 2"), "%s", said)
	testing.expect(t, ui.probe_click(&p, "More"))
	ui.probe_frame(&p)
	said = ui.probe_semantics(&p, context.temp_allocator)
	testing.expectf(t, strings.contains(said, "menu \"More items\""), "the More menu is an ActionMenu: %s", said)
	testing.expectf(t, strings.contains(said, "menu item \"Security\""), "%s", said)
	testing.expect(t, ui.probe_click(&p, "Security"))
	testing.expect_value(t, m.clicked, 4)
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_click(&p, "Issues"))
	testing.expect_value(t, m.clicked, 1)
	ui.probe_frame(&p)
	said = ui.probe_semantics(&p, context.temp_allocator)
	testing.expectf(t, strings.contains(said, "link \"Issues\" desc \"30\" current page"), "%s", said)
	testing.expectf(t, strings.contains(said, "\"More items\""), "%s", said)
	m.width = 60 // nothing fits beside More: every item moves
	ui.probe_frame(&p)
	testing.expect(t, !ui.probe_tagged(&p, "Code"))
}

@(private = "file")
Nav_List_Model :: struct {
	groups:   [2]Nav_Group,
	top:      [3]Nav_Item,
	kids:     [2]Nav_Item,
	repo:     [2]Nav_Item,
	more:     [5]Nav_Item,
	chosen:   string,
	current:  int, // which kid is current, -1 for none
}

@(private = "file")
nav_list_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Nav_List_Model)(user)
	col := ui.column_open(gtx, align = .Start)
	defer ui.close(&col)
	box := ui.sized_open(gtx, {min = {300, 0}, max = {300, ui.INF}})
	defer ui.close(&box)
	m.kids = {{label = "Branches", current = m.current == 0}, {label = "Rules", current = m.current == 1}}
	m.top = {
		{label = "General", leading = .Gear},
		{label = "Code and automation", leading = .Code, children = m.kids[:]},
		{label = "Billing", inactive_text = "Ask an owner", trailing_text = "3"},
	}
	m.repo = {{label = "Issues", description = "Open work", trailing_text = "12"}, {label = "Wiki", description = "Pages", block_description = true}}
	m.more = {{label = "M1"}, {label = "M2"}, {label = "M3"}, {label = "M4"}, {label = "M5"}}
	m.groups = {{items = m.top[:]}, {title = "Features", items = m.repo[:], more = m.more[:], more_pages = 2}}
	if it := nav_list(gtx, m.groups[:], "Settings"); it != nil {
		m.chosen = it.label
	}
}

@(private = "file")
nav_list_probe :: proc(p: ^ui.Probe, m: ^Nav_List_Model) {
	ui.probe_init(p, nav_list_view, m, {600, 900}, allocator = context.temp_allocator)
}

@(test)
test_nav_list_rows_and_the_current_item :: proc(t: ^testing.T) {
	m := Nav_List_Model{current = 1}
	p: ui.Probe
	nav_list_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	general := ui.probe_bounds(&p, "General")
	testing.expect_value(t, general.h, 2 * tok.CONTROL_MEDIUM_PADDING_BLOCK + LIST_LINE) // 32
	testing.expect_value(t, general.x, tok.BASE_SIZE_8)
	testing.expect_value(t, general.w, 300 - 2 * tok.BASE_SIZE_8)
	rules := ui.probe_bounds(&p, "Rules") // opened: its parent holds the current item
	testing.expect(t, rules.h > 0)
	said := ui.probe_semantics(&p, context.temp_allocator)
	testing.expectf(t, strings.contains(said, "navigation \"Settings\""), "%s", said)
	testing.expectf(t, strings.contains(said, "heading \"Settings\" level 2"), "%s", said)
	testing.expectf(t, strings.contains(said, "heading \"Features\" level 3"), "%s", said)
	testing.expectf(t, strings.contains(said, "link \"Rules\" current page"), "%s", said)
	testing.expectf(t, strings.contains(said, "button \"Code and automation\" expandable expanded"), "%s", said)
	// The current item's line: 4px wide, 8px left of the row, inset 4px.
	found := false
	for d in ui.probe_current(&p).draws {
		if f, ok := d.cmd.(ops.Fill); ok {
			if c, solid := f.paint.(ops.Color); solid && c == color(.Border_Color_Accent_Emphasis) {
				r := f.shape.(ops.Round_Rect).rect
				at := ops.apply(d.transform, {r.x, r.y})
				testing.expect_value(t, at, ops.Point{rules.x - 8, rules.y + 4})
				testing.expect_value(t, r.h, rules.h - 8)
				found = true
			}
		}
	}
	testing.expect(t, found)
	// Closing the parent hides its items and hands it the current look.
	testing.expect(t, ui.probe_click(&p, "Code and automation"))
	ui.probe_frame(&p)
	testing.expect(t, !ui.probe_tagged(&p, "Rules"))
	ui.probe_move(&p, 590, 890) // hovered, it would show the hover fill
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	parent := ui.probe_bounds(&p, "Code and automation")
	selected := 0
	for d in ui.probe_current(&p).draws {
		if f, ok := d.cmd.(ops.Fill); ok {
			if c, solid := f.paint.(ops.Color); solid && c == color(.Control_Transparent_Bg_Color_Selected) {
				r := f.shape.(ops.Round_Rect).rect
				testing.expect_value(t, ops.apply(d.transform, {r.x, r.y}), ops.Point{parent.x, parent.y})
				selected += 1
			}
		}
	}
	testing.expect_value(t, selected, 1)
}

@(test)
test_nav_list_activation_skips_inactive_and_parents :: proc(t: ^testing.T) {
	m := Nav_List_Model{current = -1}
	p: ui.Probe
	nav_list_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, !ui.probe_tagged(&p, "Branches")) // no current inside: closed
	testing.expect(t, ui.probe_click(&p, "Code and automation"))
	ui.probe_frame(&p)
	branches := ui.probe_bounds(&p, "Branches")
	parent := ui.probe_bounds(&p, "Code and automation")
	testing.expect_value(t, branches.x, parent.x) // the same 8px in
	// A leaf under a parent shows its depth spacer: 8px of padding, then
	// 8px a level with no gap after it (ActionList.module.css:525-529).
	text_x := f32(-1)
	for d in ui.probe_current(&p).draws {
		if g, ok := d.cmd.(ops.Glyphs); ok {
			at := ops.apply(d.transform, g.origin)
			if at.y > branches.y && at.y < branches.y + branches.h {
				text_x = at.x
				break
			}
		}
	}
	testing.expect_value(t, text_x, branches.x + tok.CONTROL_MEDIUM_PADDING_INLINE_CONDENSED + LIST_DEPTH_STEP)
	testing.expect_value(t, m.chosen, "") // a parent toggles, it does not navigate
	testing.expect(t, ui.probe_click(&p, "Branches"))
	testing.expect_value(t, m.chosen, "Branches")
	testing.expect(t, ui.probe_click(&p, "Billing")) // found by its tag, though it has no input area
	testing.expect_value(t, m.chosen, "Branches") // inactive: ignored
}

@(test)
test_nav_list_show_more_reveals_pages_and_moves_focus :: proc(t: ^testing.T) {
	testing.expect_value(t, nav_more_shown(5, 2, 1), 3) // ceil(2.5)
	testing.expect_value(t, nav_more_shown(5, 2, 2), 5)
	testing.expect_value(t, nav_more_shown(5, 0, 1), 5)
	testing.expect_value(t, nav_more_shown(5, 2, 0), 0)
	m := Nav_List_Model{current = -1}
	p: ui.Probe
	nav_list_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, !ui.probe_tagged(&p, "M1"))
	testing.expect(t, ui.probe_click(&p, "Show more"))
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "M3"))
	testing.expect(t, !ui.probe_tagged(&p, "M4"))
	said := ui.probe_semantics(&p, context.temp_allocator)
	testing.expectf(t, strings.contains(said, "link \"M1\" focused"), "the first revealed item takes focus: %s", said)
	testing.expect(t, ui.probe_click(&p, "Show more"))
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "M5"))
	testing.expect(t, !ui.probe_tagged(&p, "Show more")) // the last page: the row goes
	said = ui.probe_semantics(&p, context.temp_allocator)
	testing.expectf(t, strings.contains(said, "link \"M4\" focused"), "5 - floor(5 / 2): %s", said)
}

@(private = "file")
narrow_tabs_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	sel := (^int)(user)
	col := ui.column_open(gtx, align = .Start)
	defer ui.close(&col)
	box := ui.sized_open(gtx, {min = {200, 0}, max = {200, ui.INF}})
	defer ui.close(&box)
	tabs := [4]Underline_Tab{{"Code", .Code, ""}, {"Issues", .Issue_Opened, "12"}, {"Pull requests", .Git_Pull_Request, "3"}, {"Discussions", .Comment_Discussion, ""}}
	up := underline_panels_open(gtx, "Narrow", tabs[:], sel)
	underline_panels_close(&up)
}

@(test)
test_underline_panels_scroll_the_focused_tab_into_view :: proc(t: ^testing.T) {
	sel := 0
	p: ui.Probe
	ui.probe_init(&p, narrow_tabs_view, &sel, {600, 300}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	last := ui.probe_bounds(&p, "Discussions")
	testing.expect(t, last.x + last.w > 200) // past the 200px strip
	ui.probe_click(&p, "Code")
	ui.probe_key(&p, .End)
	ui.probe_frame(&p)
	testing.expect_value(t, sel, 3)
	last = ui.probe_bounds(&p, "Discussions")
	testing.expect(t, abs(last.x + last.w - 200) < 0.01, "its end at the strip's")
}
