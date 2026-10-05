package primer

import "core:strings"
import "core:testing"
import "jm:ui"
import "jm:ui/testutil"

// Every guard takes exactly its opener's parameters, so a call reads the
// same in either form and a guard cannot fall behind its opener.
@(test)
test_guards_take_their_openers_parameters :: proc(t: ^testing.T) {
	pairs := []struct {
		name:        string,
		guard, open: typeid,
	} {
		{"action_bar_group", type_of(action_bar_group), type_of(action_bar_group_open)},
		{"action_list_group", type_of(action_list_group), type_of(action_list_group_open)},
		{"data_table_heading", type_of(data_table_heading), type_of(data_table_heading_open)},
		{"dialog", type_of(dialog), type_of(dialog_open)},
		{"form_control", type_of(form_control), type_of(form_control_open)},
		{"checkbox_group", type_of(checkbox_group), type_of(checkbox_group_open)},
		{"radio_group", type_of(radio_group), type_of(radio_group_open)},
		{"topic_tag_group", type_of(topic_tag_group), type_of(topic_tag_group_open)},
		{"stack", type_of(stack), type_of(stack_open)},
		{"card", type_of(card), type_of(card_open)},
		{"card_action", type_of(card_action), type_of(card_action_open)},
		{"card_metadata", type_of(card_metadata), type_of(card_metadata_open)},
		{"header", type_of(header), type_of(header_open)},
		{"header_item", type_of(header_item), type_of(header_item_open)},
		{"action_menu_group", type_of(action_menu_group), type_of(action_menu_group_open)},
		{"timeline_item", type_of(timeline_item), type_of(timeline_item_open)},
		{"sub_nav", type_of(sub_nav), type_of(sub_nav_open)},
		{"underline_panels", type_of(underline_panels), type_of(underline_panels_open)},
		{"overlay", type_of(overlay), type_of(overlay_open)},
		{"anchored_overlay", type_of(anchored_overlay), type_of(anchored_overlay_open)},
		{"popover", type_of(popover), type_of(popover_open)},
		{"page_header_slot", type_of(page_header_slot), type_of(page_header_slot_open)},
		{"split_page_layout_region", type_of(split_page_layout_region), type_of(split_page_layout_region_open)},
		{"page_layout_region", type_of(page_layout_region), type_of(page_layout_region_open)},
	}
	for p in pairs {
		testing.expectf(t, testutil.same_params(p.guard, p.open), "%s and %s_open take different parameters", p.name, p.name)
	}
}

// Guard_Case draws one guard's body, through the guard when guarded and
// through its open/close pair when not.
Guard_Case :: proc(gtx: ^ui.Ctx, guarded: bool)

@(private = "file")
Guard_Run :: struct {
	draw:    Guard_Case,
	guarded: bool,
}

// guard_frame is the second frame a guard case draws, its widget ids
// masked: the two forms sit on different lines, so only their ids differ.
@(private = "file")
guard_frame :: proc(draw: Guard_Case, guarded: bool) -> string {
	run := Guard_Run{draw, guarded}
	p: ui.Probe
	ui.probe_init(&p, proc(gtx: ^ui.Ctx, user: rawptr) {
			// The window's constraints are tight; a column under them lets the
			// case's content take its own size, so its layout shows.
			r := (^Guard_Run)(user)
			ui.column(gtx)
			r.draw(gtx, r.guarded)
		}, &run, {700, 500}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	ui.probe_frame(&p)
	return mask_ids(ui.probe_dump_frame(&p), context.temp_allocator)
}

// mask_ids replaces every run of ten or more digits, an Area_Id, with #.
@(private = "file")
mask_ids :: proc(s: string, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	i := 0
	for i < len(s) {
		j := i
		for j < len(s) && s[j] >= '0' && s[j] <= '9' {
			j += 1
		}
		if j - i >= 10 {
			strings.write_byte(&b, '#')
			i = j
		} else if j > i {
			strings.write_string(&b, s[i:j])
			i = j
		} else {
			strings.write_byte(&b, s[i])
			i += 1
		}
	}
	return strings.to_string(b)
}

// expect_guard_matches_pair checks a guard draws exactly what its pair
// does, and that the frame holds something, so an empty body cannot pass.
@(private)
expect_guard_matches_pair :: proc(t: ^testing.T, name: string, draw: Guard_Case, loc := #caller_location) {
	guarded := guard_frame(draw, true)
	paired := guard_frame(draw, false)
	testing.expectf(t, guarded == paired, "%s: the guard and its pair draw different frames", name, loc = loc)
	testing.expectf(t, strings.count(guarded, "draw ") > 1, "%s: the case drew nothing", name, loc = loc)
}

@(test)
test_container_guards_draw_what_their_pairs_draw :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	expect_guard_matches_pair(t, "stack", proc(gtx: ^ui.Ctx, guarded: bool) {
		if guarded {
			stack(gtx, gap = .Condensed, direction = .Horizontal)
		} else {
			s := stack_open(gtx, gap = .Condensed, direction = .Horizontal)
			defer stack_close(&s)
		}
		button(gtx, "One")
		button(gtx, "Two")
	})
	expect_guard_matches_pair(t, "card", proc(gtx: ^ui.Ctx, guarded: bool) {
		if guarded {
			card(gtx, "Heading", "Description")
		} else {
			c := card_open(gtx, "Heading", "Description")
			defer card_close(&c)
		}
		text(gtx, "Body")
	})
	expect_guard_matches_pair(t, "header", proc(gtx: ^ui.Ctx, guarded: bool) {
		if guarded {
			header(gtx)
		} else {
			h := header_open(gtx)
			defer header_close(&h)
		}
		text(gtx, "Global")
	})
	expect_guard_matches_pair(t, "header_item", proc(gtx: ^ui.Ctx, guarded: bool) {
		h := header_open(gtx)
		defer header_close(&h)
		if guarded {
			header_item(gtx, full = true)
		} else {
			it := header_item_open(gtx, full = true)
			defer header_item_close(&it)
		}
		text(gtx, "Item")
	})
	expect_guard_matches_pair(t, "form_control", proc(gtx: ^ui.Ctx, guarded: bool) {
		if guarded {
			form_control(gtx, "Name", caption = "Caption", required = true)
		} else {
			f := form_control_open(gtx, "Name", caption = "Caption", required = true)
			defer form_control_close(gtx, &f)
		}
		button(gtx, "Field")
	})
	expect_guard_matches_pair(t, "checkbox_group", proc(gtx: ^ui.Ctx, guarded: bool) {
		if guarded {
			checkbox_group(gtx, "Notify", caption = "Pick any")
		} else {
			g := checkbox_group_open(gtx, "Notify", caption = "Pick any")
			defer checkbox_group_close(gtx, &g)
		}
		button(gtx, "Choice")
	})
	expect_guard_matches_pair(t, "radio_group", proc(gtx: ^ui.Ctx, guarded: bool) {
		if guarded {
			radio_group(gtx, "Size", validation = "Choose one")
		} else {
			g := radio_group_open(gtx, "Size", validation = "Choose one")
			defer radio_group_close(gtx, &g)
		}
		button(gtx, "Choice")
	})
	expect_guard_matches_pair(t, "topic_tag_group", proc(gtx: ^ui.Ctx, guarded: bool) {
		if guarded {
			topic_tag_group(gtx)
		} else {
			g := topic_tag_group_open(gtx)
			defer ui.close(&g)
		}
		topic_tag(gtx, "odin")
		topic_tag(gtx, "ui")
	})
	expect_guard_matches_pair(t, "data_table_heading", proc(gtx: ^ui.Ctx, guarded: bool) {
		if guarded {
			data_table_heading(gtx, "Repositories", "All of them", divider = true)
		} else {
			h := data_table_heading_open(gtx, "Repositories", "All of them", divider = true)
			defer data_table_heading_close(&h)
		}
		button(gtx, "New")
	})
}

@(test)
test_slot_guards_draw_what_their_pairs_draw :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	expect_guard_matches_pair(t, "card_action and card_metadata", proc(gtx: ^ui.Ctx, guarded: bool) {
		c := card_open(gtx, "Heading")
		defer card_close(&c)
		if guarded {
			{
				card_action(&c)
				button(gtx, "Act")
			}
			card_metadata(&c)
			card_metadata_item(gtx, "3 stars", .Star)
		} else {
			card_action_open(&c)
			button(gtx, "Act")
			card_action_close(&c)
			card_metadata_open(&c)
			defer card_metadata_close(&c)
			card_metadata_item(gtx, "3 stars", .Star)
		}
	})
	expect_guard_matches_pair(t, "timeline_item", proc(gtx: ^ui.Ctx, guarded: bool) {
		tl := timeline_open(gtx)
		defer timeline_close(&tl)
		if guarded {
			timeline_item(gtx, &tl, .Git_Commit, body = "Committed")
		} else {
			it := timeline_item_open(gtx, &tl, .Git_Commit, body = "Committed")
			defer timeline_item_close(&it)
		}
	})
	expect_guard_matches_pair(t, "page_header_slot", proc(gtx: ^ui.Ctx, guarded: bool) {
		h := page_header_open(gtx, "Title")
		defer page_header_close(&h)
		if guarded {
			page_header_slot(&h, .Actions)
		} else {
			page_header_slot_open(&h, .Actions)
			defer page_header_slot_close(&h)
		}
		button(gtx, "Edit")
	})
	expect_guard_matches_pair(t, "page_layout_region", proc(gtx: ^ui.Ctx, guarded: bool) {
		l := page_layout_open(gtx)
		defer page_layout_close(&l)
		if guarded {
			page_layout_region(&l, .Content)
		} else {
			page_layout_region_open(&l, .Content)
			defer page_layout_region_close(&l)
		}
		button(gtx, "Content")
	})
	expect_guard_matches_pair(t, "split_page_layout_region", proc(gtx: ^ui.Ctx, guarded: bool) {
		l := split_page_layout_open(gtx)
		defer page_layout_close(&l)
		if guarded {
			split_page_layout_region(&l, .Header)
		} else {
			split_page_layout_region_open(&l, .Header)
			defer page_layout_region_close(&l)
		}
		text(gtx, "Header")
	})
	expect_guard_matches_pair(t, "action_list_group", proc(gtx: ^ui.Ctx, guarded: bool) {
		l := action_list_open(gtx)
		defer action_list_close(&l)
		if guarded {
			action_list_group(&l, "Group", auxiliary = "Aux")
		} else {
			action_list_group_open(&l, "Group", auxiliary = "Aux")
			defer action_list_group_close(&l)
		}
		action_list_item(&l, "One")
	})
	expect_guard_matches_pair(t, "action_menu_group", proc(gtx: ^ui.Ctx, guarded: bool) {
		open := true
		button(gtx, "Menu")
		m := action_menu_open(gtx, &open, ui.last_widget(gtx))
		defer action_menu_close(&m)
		if guarded {
			action_menu_group(&m, "Group")
		} else {
			action_menu_group_open(&m, "Group")
			defer action_menu_group_close(&m)
		}
		action_menu_item(&m, "One")
	})
	expect_guard_matches_pair(t, "action_bar_group", proc(gtx: ^ui.Ctx, guarded: bool) {
		b := action_bar_open(gtx, "Bar")
		defer action_bar_close(&b)
		if guarded {
			action_bar_group(&b)
		} else {
			action_bar_group_open(&b)
			defer action_bar_group_close(&b)
		}
		action_bar_button(&b, "One")
		action_bar_button(&b, "Two")
	})
}
