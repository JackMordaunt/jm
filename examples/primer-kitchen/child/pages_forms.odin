package main

import "core:fmt"
import "jm:ui"
import "jm:ui/base"
import "jm:ui/primer"

import "../../kitchen"

// Forms is the form pages' demo state: the live fields' text, the
// choices, and the sample text the state grids show.
Forms :: struct {
	sample, empty:                 ui.Text_State,
	repo, search, bio, notes:      ui.Text_State,
	email:                         ui.Text_State,
	branch, size, theme:           int,
	terms, news, digest, mentions: bool,
	parent_kids:                   [3]bool,
	visibility, merge:             int,
	notify, autosave, saving:      bool,
	view, panes, filter:           int,
	seeded:                        bool,
	clears, submits:               int,
}

// forms_seed fills the forms' text the first time a page draws.
forms_seed :: proc(f: ^Forms) {
	if f.seeded {
		return
	}
	f.seeded = true
	ui.text_set(&f.sample, "octocat")
	ui.text_set(&f.repo, "jm")
	ui.text_set(&f.email, "mona@")
	f.branch, f.size, f.theme = 0, -1, 2
	f.news, f.autosave = true, true
	f.parent_kids = {true, false, true}
	f.view = 1
}

// The form-control pages, on the primer-kit's components/text-input.json,
// textarea.json, select.json, checkbox.json, checkbox-group.json,
// radio.json, radio-group.json, toggle-switch.json, form-control.json and
// segmented-control.json.

FIELD_CELL_W :: f32(180)

INPUT_ROWS := [?]string{"Placeholder", "Text", "Leading icon", "Trailing action", "Loading", "Error", "Success", "Contrast"}

page_text_input :: proc(gtx: ^ui.Ctx, m: ^Model) {
	forms_seed(&m.forms)
	ui.column(gtx, gap = 10)
	kitchen.section(gtx, "States", "the well: a 1px border, inset top shadow, 2px ring at -1px on any focus; no hover state")
	kitchen.state_header(gtx, FIELD_CELL_W)
	for n, i in INPUT_ROWS {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: primer.Interaction, key: u64) {
			f := &(^Model)(user).forms
			w := FIELD_CELL_W - 12
			switch key / 16 - 1 {
			case 0:
				primer.text_input(gtx, &f.empty, "Placeholder", width = w, state = st, key = key)
			case 1:
				primer.text_input(gtx, &f.sample, width = w, state = st, key = key)
			case 2:
				primer.text_input(gtx, &f.sample, leading = .Search, trailing_text = "kb", width = w, state = st, key = key)
			case 3:
				primer.text_input(gtx, &f.sample, action = .X_Circle_Fill, action_name = "Clear", width = w, state = st, key = key)
			case 4:
				primer.text_input(gtx, &f.sample, loading = true, width = w, state = st, key = key)
			case 5:
				primer.text_input(gtx, &f.sample, validation = .Error, width = w, state = st, key = key)
			case 6:
				primer.text_input(gtx, &f.sample, validation = .Success, width = w, state = st, key = key)
			case 7:
				primer.text_input(gtx, &f.sample, contrast = true, width = w, state = st, key = key)
			}
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 1), FIELD_CELL_W)
	}
	kitchen.section(gtx, "Sizes", "28px with 3px block padding, 32px, and 40px fixed with 12px visual insets")
	{
		ui.wrap(gtx, gap = 12, align = .Center)
		sizes := [?]primer.Field_Size{.Small, .Medium, .Large}
		for s, i in sizes {
			primer.text_input(gtx, &m.forms.sample, leading = .Mail, size = s, width = 200, key = u64(40 + i))
		}
	}
	kitchen.section(gtx, "Live", "type, select, Enter submits; the counter turns to error past 20 characters but never blocks")
	{
		primer.form_control(gtx, "Repository name", caption = "Great repository names are short and memorable.", required = true)
		e := primer.text_input(gtx, &m.forms.repo, leading = .Repo, character_limit = 20)
		if e.submitted {
			m.forms.submits += 1
		}
	}
	{
		primer.form_control(gtx, "Search")
		e := primer.text_input(gtx, &m.forms.search, "Find a file…", leading = .Search, action = .X_Circle_Fill, action_name = "Clear", loading = len(m.forms.search.buf) > 3, block = true)
		if e.action {
			ui.text_set(&m.forms.search, "")
			m.forms.clears += 1
		}
	}
	base_note(gtx, fmt.tprintf("submitted %d times, cleared %d times", m.forms.submits, m.forms.clears))
}

// base_note is a muted line of demo bookkeeping.
base_note :: proc(gtx: ^ui.Ctx, s: string) {
	base.label(gtx, s, {size = 12, color = base.color(.Muted)})
}

page_textarea :: proc(gtx: ^ui.Ctx, m: ^Model) {
	forms_seed(&m.forms)
	ui.column(gtx, gap = 10)
	kitchen.section(gtx, "States", "TextInput's well, the text padded 12px on 20px lines; the grip drags both axes")
	kitchen.state_header(gtx, FIELD_CELL_W)
	rows := [?]string{"Placeholder", "Error", "Contrast"}
	for n, i in rows {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: primer.Interaction, key: u64) {
			f := &(^Model)(user).forms
			w := FIELD_CELL_W - 12
			switch key / 16 - 1 {
			case 0:
				primer.textarea(gtx, &f.empty, "Leave a comment", rows = 2, width = w, state = st, key = key)
			case 1:
				primer.textarea(gtx, &f.sample, rows = 2, validation = .Error, width = w, state = st, key = key)
			case 2:
				primer.textarea(gtx, &f.sample, rows = 2, contrast = true, width = w, state = st, key = key)
			}
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 1), FIELD_CELL_W)
	}
	kitchen.section(gtx, "Live", "Enter adds a line; auto size grows from 3 lines to at most 164px; the counter allows 140")
	{
		primer.form_control(gtx, "Bio", caption = "Grows with its text.")
		primer.textarea(gtx, &m.forms.bio, "Tell us about yourself", auto_size = true, min_height = 84, max_height = 164, character_limit = 140, cols = 40)
	}
	{
		primer.form_control(gtx, "Notes")
		primer.textarea(gtx, &m.forms.notes, "Seven rows, resizable", resize = .Vertical)
	}
}

BRANCHES := [?]primer.Select_Option{{label = "main"}, {label = "develop"}, {label = "release/1.0", group = "Releases"}, {label = "release/0.9", group = "Releases", disabled = true}, {label = "hotfix", group = "Other"}}
SIZES := [?]primer.Select_Option{{label = "Small"}, {label = "Medium"}, {label = "Large"}}

page_select :: proc(gtx: ^ui.Ctx, m: ^Model) {
	forms_seed(&m.forms)
	ui.column(gtx, gap = 10)
	kitchen.section(gtx, "States", "TextInput's well, as wide as the widest option, the up-down arrow 4px from the end")
	kitchen.state_header(gtx, FIELD_CELL_W)
	rows := [?]string{"Chosen", "Placeholder", "Error", "Small"}
	for n, i in rows {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: primer.Interaction, key: u64) {
			chosen, none := 0, -1
			switch key / 16 - 1 {
			case 0:
				primer.select(gtx, BRANCHES[:], &chosen, state = st, key = key)
			case 1:
				primer.select(gtx, SIZES[:], &none, "Choose a size", state = st, key = key)
			case 2:
				primer.select(gtx, BRANCHES[:], &chosen, validation = .Error, state = st, key = key)
			case 3:
				primer.select(gtx, SIZES[:], &chosen, size = .Small, state = st, key = key)
			}
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 1), FIELD_CELL_W)
	}
	kitchen.section(gtx, "Live", "press, Space or Alt+Down opens; Up and Down change it closed; a letter jumps")
	ui.wrap(gtx, gap = 24, align = .Start)
	{
		primer.form_control(gtx, "Base branch", caption = "Grouped, one disabled")
		primer.select(gtx, BRANCHES[:], &m.forms.branch)
	}
	{
		primer.form_control(gtx, "Size", validation = m.forms.size < 0 ? "Choose a size" : "", required = true)
		primer.select(gtx, SIZES[:], &m.forms.size, "Choose a size", required = true)
	}
}

CHECK_ROWS := [?]string{"Unchecked", "Checked", "Indeterminate", "Labelled"}

page_checkbox :: proc(gtx: ^ui.Ctx, m: ^Model) {
	forms_seed(&m.forms)
	ui.column(gtx, gap = 10)
	kitchen.section(gtx, "States", "16px, no hover or pressed colour; keyboard focus is a 2px outline 2px outside")
	kitchen.state_header(gtx)
	for n, i in CHECK_ROWS {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: primer.Interaction, key: u64) {
			off, on := false, true
			switch key / 16 - 1 {
			case 0:
				primer.checkbox(gtx, &off, state = st, key = key)
			case 1:
				primer.checkbox(gtx, &on, state = st, key = key)
			case 2:
				primer.checkbox(gtx, &off, indeterminate = true, state = st, key = key)
			case 3:
				primer.checkbox(gtx, &on, "Label", state = st, key = key)
			}
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 1))
	}
	kitchen.section(gtx, "Live", "the label toggles too; the check is revealed bottom up after the fill")
	f := &m.forms
	primer.checkbox(gtx, &f.terms, "Accept the terms", required = true)
	primer.checkbox(gtx, &f.news, "Newsletter", caption = "A short email, once a month")
	primer.checkbox(gtx, &f.digest, "Weekly digest", caption = "With a leading visual", leading = .Mail)
	all := f.parent_kids[0] && f.parent_kids[1] && f.parent_kids[2]
	some := f.parent_kids[0] || f.parent_kids[1] || f.parent_kids[2]
	parent := all
	if primer.checkbox(gtx, &parent, "All repositories", indeterminate = some && !all) {
		f.parent_kids = parent ? {true, true, true} : {}
	}
	names := [3]string{"jm", "brain", "review"}
	for n, i in names {
		ui.inset(gtx, {24, 0, 0, 0}, key = u64(70 + i))
		primer.checkbox(gtx, &f.parent_kids[i], n, key = u64(80 + i))
	}
}

page_checkbox_group :: proc(gtx: ^ui.Ctx, m: ^Model) {
	forms_seed(&m.forms)
	ui.column(gtx, gap = 10)
	f := &m.forms
	kitchen.section(gtx, "Live", "a semibold legend, a 14px caption, options 8px apart, one validation message")
	{
		primer.checkbox_group(gtx, "Notifications", caption = "Choose what to hear about", validation = f.news || f.mentions || f.digest ? "" : "Choose at least one", required = true)
		primer.checkbox(gtx, &f.news, "Releases")
		primer.checkbox(gtx, &f.mentions, "Mentions", caption = "When someone @-mentions you")
		primer.checkbox(gtx, &f.digest, "Weekly digest")
	}
	kitchen.section(gtx, "Disabled and success", "a disabled group mutes its legend and disables every checkbox")
	ui.wrap(gtx, gap = 48, align = .Start)
	{
		primer.checkbox_group(gtx, "Archived", disabled = true)
		primer.checkbox(gtx, &f.news, "Releases", key = 1)
		primer.checkbox(gtx, &f.mentions, "Mentions", key = 2)
	}
	{
		primer.checkbox_group(gtx, "Labels", validation = "Saved", status = .Success)
		primer.checkbox(gtx, &f.parent_kids[0], "bug", key = 3)
		primer.checkbox(gtx, &f.parent_kids[1], "enhancement", key = 4)
	}
}

RADIO_ROWS := [?]string{"Unchecked", "Checked", "Labelled"}

page_radio :: proc(gtx: ^ui.Ctx, m: ^Model) {
	forms_seed(&m.forms)
	ui.column(gtx, gap = 10)
	kitchen.section(gtx, "States", "16px; checked thickens the ring to 4px around an 8px dot")
	kitchen.state_header(gtx)
	for n, i in RADIO_ROWS {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: primer.Interaction, key: u64) {
			switch key / 16 - 1 {
			case 0:
				primer.radio(gtx, false, state = st, key = key)
			case 1:
				primer.radio(gtx, true, state = st, key = key)
			case 2:
				primer.radio(gtx, true, "Label", state = st, key = key)
			}
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 1))
	}
	kitchen.section(gtx, "Live", "the caller keeps the choice; a checked radio pressed again stays checked")
	names := [?]string{"Merge commit", "Squash and merge", "Rebase and merge"}
	for n, i in names {
		if primer.radio(gtx, m.forms.merge == i, n, key = u64(50 + i)) {
			m.forms.merge = i
		}
	}
}

page_radio_group :: proc(gtx: ^ui.Ctx, m: ^Model) {
	forms_seed(&m.forms)
	ui.column(gtx, gap = 10)
	f := &m.forms
	kitchen.section(gtx, "Live", "click one, then Up/Down/Left/Right move and check, wrapping past the disabled one")
	{
		primer.radio_group(gtx, "Visibility", caption = "Who can see this repository", validation = f.visibility == 2 ? "Internal needs an enterprise" : "", required = true)
		names := [?]string{"Public", "Private", "Internal", "Secret"}
		captions := [?]string{"Anyone on the internet", "You choose who can see it", "", ""}
		for n, i in names {
			if primer.radio(gtx, f.visibility == i, n, caption = captions[i], state = i == 3 ? .Disabled : .Live, key = u64(i)) {
				f.visibility = i
			}
		}
	}
	kitchen.section(gtx, "Disabled", "the legend mutes to --fgColor-muted; the options' labels are --control-fgColor-disabled")
	{
		primer.radio_group(gtx, "Merge method", disabled = true)
		names := [?]string{"Merge", "Squash"}
		for n, i in names {
			primer.radio(gtx, i == 0, n, key = u64(10 + i))
		}
	}
}

SWITCH_ROWS := [?]string{"Off", "On", "Small", "Loading", "Label at end"}

page_toggle_switch :: proc(gtx: ^ui.Ctx, m: ^Model) {
	forms_seed(&m.forms)
	ui.column(gtx, gap = 10)
	kitchen.section(gtx, "States", "64 by 32px at the 6px radius; hover, keyboard focus and press change only the track; outline 3px outside")
	kitchen.state_header(gtx, FIELD_CELL_W)
	for n, i in SWITCH_ROWS {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: primer.Interaction, key: u64) {
			off, on := false, true
			switch key / 16 - 1 {
			case 0:
				primer.toggle_switch(gtx, &off, "Demo", state = st, key = key)
			case 1:
				primer.toggle_switch(gtx, &on, "Demo", state = st, key = key)
			case 2:
				primer.toggle_switch(gtx, &on, "Demo", size = .Small, state = st, key = key)
			case 3:
				primer.toggle_switch(gtx, &on, "Demo", loading = true, state = st, key = key)
			case 4:
				primer.toggle_switch(gtx, &off, "Demo", status_position = .End, state = st, key = key)
			}
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 1), FIELD_CELL_W)
	}
	kitchen.section(gtx, "Live", "the status label toggles too and never changes width")
	f := &m.forms
	ui.row(gtx, gap = 16, align = .Center)
	primer.toggle_switch(gtx, &f.notify, "Notifications")
	primer.toggle_switch(gtx, &f.autosave, "Autosave", label_on = "Enabled", label_off = "Disabled")
	if primer.toggle_switch(gtx, &f.saving, "Saving", loading = f.saving) {
		f.saving = true
	}
	if primer.button(gtx, "Reset", .Invisible, size = .Small) {
		f.saving = false
	}
}

page_form_control :: proc(gtx: ^ui.Ctx, m: ^Model) {
	forms_seed(&m.forms)
	ui.column(gtx, gap = 16)
	f := &m.forms
	kitchen.section(gtx, "Vertical", "label, input, validation, caption, 4px apart; a press on the label focuses the input")
	{
		primer.form_control(gtx, "Email", caption = "We never share it", validation = len(f.email.buf) > 0 && !valid_email(ui.text_string(&f.email)) ? "Enter a whole address" : "", required = true)
		primer.text_input(gtx, &f.email, "you@example.com")
	}
	{
		primer.form_control(gtx, "Theme", validation = "Saved", status = .Success)
		primer.select(gtx, SIZES[:], &f.theme)
	}
	{
		primer.form_control(gtx, "Disabled", caption = "Greys the label and caption", disabled = true)
		primer.text_input(gtx, &f.sample)
	}
	{
		primer.form_control(gtx, "Hidden label", caption = "The label names the field but draws nothing", hide_label = true)
		primer.text_input(gtx, &f.empty, "Search…", leading = .Search)
	}
	kitchen.section(gtx, "Horizontal", "a checkbox or radio: box, then label (normal weight) and caption 8px after it")
	primer.checkbox(gtx, &f.terms, "Accept the terms", caption = "You can change this later", required = true)
	primer.radio(gtx, true, "Selected option", caption = "With a caption", leading = .Repo)
}

// valid_email is the demo's check: something either side of one "@".
valid_email :: proc(s: string) -> bool {
	at := -1
	for c, i in s {
		if c == '@' {
			if at >= 0 {
				return false
			}
			at = i
		}
	}
	return at > 0 && at < len(s) - 1
}

SEGMENT_ROWS := [?]string{"Text", "Icons and count", "Icon only", "Subtle", "Small"}
VIEWS := [?]primer.Segment{{label = "Preview"}, {label = "Raw"}, {label = "Blame"}}
PANES := [?]primer.Segment{{label = "Files", icon = .File, count = "12"}, {label = "Commits", icon = .Git_Commit}, {label = "Checks", icon = .Checklist, disabled = true}}
ICONS := [?]primer.Segment{{label = "List", icon = .List_Unordered, icon_only = true}, {label = "Grid", icon = .Apps, icon_only = true}}
FILTERS := [?]primer.Segment{{label = "Open"}, {label = "Closed"}, {label = "All", divider = true}}

page_segmented_control :: proc(gtx: ^ui.Ctx, m: ^Model) {
	forms_seed(&m.forms)
	ui.column(gtx, gap = 10)
	kitchen.section(gtx, "States", "the state shows on the first unselected segment; each segment reserves its semibold width")
	kitchen.state_header(gtx, 260)
	for n, i in SEGMENT_ROWS {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: primer.Interaction, key: u64) {
			sel := 1
			switch key / 16 - 1 {
			case 0:
				primer.segmented_control(gtx, VIEWS[:], &sel, "View", state = st, key = key)
			case 1:
				sel = 0
				primer.segmented_control(gtx, PANES[:], &sel, "Pane", state = st, key = key)
			case 2:
				primer.segmented_control(gtx, ICONS[:], &sel, "Layout", state = st, key = key)
			case 3:
				primer.segmented_control(gtx, FILTERS[:], &sel, "Filter", variant = .Subtle, state = st, key = key)
			case 4:
				primer.segmented_control(gtx, VIEWS[:], &sel, "View", size = .Small, state = st, key = key)
			}
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 1), 260)
	}
	kitchen.section(gtx, "Live", "the knob slides over 200ms; Tab between segments, Enter or Space selects")
	f := &m.forms
	primer.segmented_control(gtx, VIEWS[:], &f.view, "File view", key = 100)
	primer.segmented_control(gtx, PANES[:], &f.panes, "Pane", key = 101)
	primer.segmented_control(gtx, FILTERS[:], &f.filter, "Filter", variant = .Subtle, key = 102)
	primer.segmented_control(gtx, VIEWS[:], &f.view, "File view, full width", full_width = true, key = 103)
}
