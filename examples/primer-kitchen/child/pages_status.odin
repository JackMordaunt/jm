package main

import "core:fmt"
import "jm:ui"
import "jm:ui/ops"
import "jm:ui/primer"

import "../../kitchen"

// Status is the label and status pages' demo state: which live tokens
// were removed, the last tag or label clicked, the progress bar's value
// and whether the skeletons have loaded.
Status :: struct {
	removed:  bit_set[0 ..< 8],
	selected: int,
	clicked:  string,
	progress: f32,
	loaded:   bool,
}

// The label and status pages, on the primer-kit's components/label.json,
// label-group.json, state-label.json, counter-label.json, token.json,
// issue-label.json, topic-tag.json, branch-name.json, avatar.json,
// avatar-stack.json, circle-badge.json, spinner.json, progress-bar.json and
// skeleton-*.json.

LABEL_VARIANTS := [?]primer.Label_Variant{.Default, .Primary, .Secondary, .Accent, .Success, .Attention, .Severe, .Danger, .Done, .Sponsors}
LABEL_NAMES := [?]string{"Default", "Primary", "Secondary", "Accent", "Success", "Attention", "Severe", "Danger", "Done", "Sponsors"}

page_label :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	kitchen.section(gtx, "Variants", "an outlined pill, no fill: 20px tall, 6px sides, medium 12px text; most borders read a bgColor emphasis token")
	{
		r := ui.wrap_open(gtx, gap = 8, line_gap = 8, align = .Center)
		defer ui.close(&r)
		for v, i in LABEL_VARIANTS {
			primer.label(gtx, LABEL_NAMES[i], v, key = u64(i))
		}
	}
	kitchen.section(gtx, "Large", "24px tall, 8px sides; the text stays 12px")
	r := ui.wrap_open(gtx, gap = 8, line_gap = 8, align = .Center)
	defer ui.close(&r)
	for v, i in LABEL_VARIANTS {
		primer.label(gtx, LABEL_NAMES[i], v, .Large, key = u64(i))
	}
}

STATUSES := [?]primer.State_Status {
	.Issue_Opened,
	.Issue_Closed,
	.Issue_Closed_Not_Planned,
	.Issue_Draft,
	.Pull_Opened,
	.Pull_Closed,
	.Pull_Merged,
	.Pull_Queued,
	.Draft,
	.Unavailable,
	.Alert_Opened,
	.Alert_Fixed,
	.Alert_Dismissed,
	.Alert_Closed,
	.Open,
	.Closed,
	.Archived,
}
STATUS_WORDS := [?]string{"Open", "Closed", "Not planned", "Draft", "Open", "Closed", "Merged", "Queued", "Draft", "Unavailable", "Open", "Fixed", "Dismissed", "Closed", "Open", "Closed", "Archived"}

page_state_label :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	kitchen.section(gtx, "Medium", "32px: 8px by 12px around a 16px line, the status's icon 4px before semibold onEmphasis text")
	{
		r := ui.wrap_open(gtx, gap = 8, line_gap = 8, align = .Center)
		defer ui.close(&r)
		for s, i in STATUSES {
			primer.state_label(gtx, STATUS_WORDS[i], s, key = u64(i))
		}
	}
	kitchen.section(gtx, "Small", "24px: 4px by 8px, 12px text, the icon drawn 12px")
	r := ui.wrap_open(gtx, gap = 8, line_gap = 8, align = .Center)
	defer ui.close(&r)
	for s, i in STATUSES {
		primer.state_label(gtx, STATUS_WORDS[i], s, .Small, key = u64(i))
	}
}

HUES := [?]primer.Label_Hue{.Pink, .Plum, .Purple, .Indigo, .Blue, .Cyan, .Teal, .Pine, .Green, .Lime, .Olive, .Lemon, .Yellow, .Orange, .Red, .Coral, .Gray, .Brown, .Auburn}
HUE_NAMES := [?]string{"pink", "plum", "purple", "indigo", "blue", "cyan", "teal", "pine", "green", "lime", "olive", "lemon", "yellow", "orange", "red", "coral", "gray", "brown", "auburn"}
INTERACTIVE_HUES := [?]primer.Label_Hue{.Blue, .Green, .Orange}
HEX_FILLS := [?]u32{0xd73a4aff, 0x0075caff, 0xa2eeefff, 0x7057ffff, 0xfbca04ff, 0x008672ff, 0xe4e669ff, 0xffffffff, 0x000000ff}

page_issue_label :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	kitchen.section(gtx, "Named hues", "--label-<hue>-* fill and text; 20px, 8px sides, semibold 12px")
	{
		r := ui.wrap_open(gtx, gap = 8, line_gap = 8, align = .Center)
		defer ui.close(&r)
		for h, i in HUES {
			primer.issue_label(gtx, HUE_NAMES[i], h, key = u64(i))
		}
	}
	kitchen.section(gtx, "Hex fills", "the fill exactly; text black above 0.179 WCAG luminance, else white, in every theme")
	{
		r := ui.wrap_open(gtx, gap = 8, line_gap = 8, align = .Center)
		defer ui.close(&r)
		for v, i in HEX_FILLS {
			primer.issue_label(gtx, fmt.tprintf("#%06x", v >> 8), fill = ops.rgba(v), key = u64(i))
		}
	}
	kitchen.section(gtx, "Interactive", "a button: hover and press tokens at once; keyboard focus is an outline 2px outside")
	kitchen.state_header(gtx)
	for h, i in INTERACTIVE_HUES {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: primer.Interaction, key: u64) {
			primer.issue_label(gtx, "enhancement", INTERACTIVE_HUES[key / 16 - 1], interactive = true, state = st, key = key)
		}
		kitchen.state_row(gtx, m, HUE_NAMES[h], cell, u64(i + 1))
	}
	kitchen.section(gtx, "Live", m.status.clicked == "" ? "click one" : fmt.tprintf("clicked %s", m.status.clicked))
	r := ui.wrap_open(gtx, gap = 8, align = .Center)
	defer ui.close(&r)
	for h, i in HUES[:6] {
		if primer.issue_label(gtx, HUE_NAMES[i], h, interactive = true, key = u64(100 + i)) {
			m.status.clicked = HUE_NAMES[i]
		}
	}
}

page_topic_tag :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	kitchen.section(gtx, "States", "an accent-muted pill, 25.5px tall; hovered it fills accent emphasis at once; Primer's outline for keyboard focus")
	kitchen.state_header(gtx)
	{
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: primer.Interaction, key: u64) {
			primer.topic_tag(gtx, "react", state = st, key = key)
		}
		kitchen.state_row(gtx, m, "Link", cell, 1)
	}
	{
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: primer.Interaction, key: u64) {
			primer.topic_tag(gtx, "odin", .Span, state = st, key = key)
		}
		kitchen.state_row(gtx, m, "Span", cell, 2)
	}
	kitchen.section(gtx, "Group", "TopicTag.Group: 2px between tags, 8px between lines")
	sz := ui.sized_open(gtx, {max = {360, 0}})
	defer ui.close(&sz)
	g := primer.topic_tag_group_open(gtx)
	defer ui.close(&g)
	for t, i in ([]string{"immediate-mode", "odin", "ui", "design-systems", "primer", "blend2d", "accessibility", "github"}) {
		primer.topic_tag(gtx, t, key = u64(i))
	}
}

page_branch_name :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	kitchen.section(gtx, "Link and text", "monospace 12px, 2px by 6px on accent muted; a link is fgColor-link, text muted")
	kitchen.state_header(gtx)
	{
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: primer.Interaction, key: u64) {
			primer.branch_name(gtx, "main", state = st, key = key)
		}
		kitchen.state_row(gtx, m, "Link", cell, 1)
	}
	{
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: primer.Interaction, key: u64) {
			primer.branch_name(gtx, "feature/primer-labels", false, state = st, key = key)
		}
		kitchen.state_row(gtx, m, "Text", cell, 2)
	}
}

TOKEN_SIZES := [?]primer.Token_Size{.Small, .Medium, .Large, .XLarge}
TOKEN_SIZE_NAMES := [?]string{"Small", "Medium", "Large", "XLarge"}

page_token :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	kitchen.section(gtx, "Sizes", "16 / 20 / 24 / 32px; a leading visual from medium up; a remove target as tall as the token")
	{
		r := ui.wrap_open(gtx, gap = 8, line_gap = 8, align = .Center)
		defer ui.close(&r)
		for s, i in TOKEN_SIZES {
			primer.token(gtx, TOKEN_SIZE_NAMES[i], s, leading = .Git_Branch, key = u64(i))
			primer.token(gtx, TOKEN_SIZE_NAMES[i], s, removable = true, key = u64(10 + i))
		}
	}
	kitchen.section(gtx, "States", "selected turns text default and the border emphasis; the web has no hover for Token")
	kitchen.state_header(gtx)
	{
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: primer.Interaction, key: u64) {
			primer.token(gtx, "bug", interactive = true, state = st, key = key)
		}
		kitchen.state_row(gtx, m, "Interactive", cell, 1)
	}
	{
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: primer.Interaction, key: u64) {
			primer.token(gtx, "bug", selected = true, removable = true, state = st, key = key)
		}
		kitchen.state_row(gtx, m, "Selected", cell, 2)
	}
	kitchen.section(gtx, "IssueLabelToken", "every colour derived from the fill by perceived lightness, by the theme's light or dark formula")
	{
		r := ui.wrap_open(gtx, gap = 8, line_gap = 8, align = .Center)
		defer ui.close(&r)
		for v, i in HEX_FILLS {
			primer.issue_label_token(gtx, fmt.tprintf("#%06x", v >> 8), ops.rgba(v), removable = i % 2 == 0, selected = i == 3, key = u64(i))
		}
	}
	{
		kitchen.state_header(gtx)
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: primer.Interaction, key: u64) {
			primer.issue_label_token(gtx, "bug", ops.rgba(0xd73a4aff), interactive = true, removable = true, state = st, key = key)
		}
		kitchen.state_row(gtx, m, "Interactive", cell, 3)
	}
	kitchen.section(gtx, "Live", "click a token to select it; its X, or Backspace on a focused one, removes it")
	r := ui.wrap_open(gtx, gap = 8, align = .Center)
	defer ui.close(&r)
	names := [?]string{"bug", "docs", "good first issue", "help wanted", "question"}
	for n, i in names {
		if i in m.status.removed {
			continue
		}
		res := primer.token(gtx, n, .Large, removable = true, selected = m.status.selected == i, interactive = true, key = u64(100 + i))
		if res.clicked {
			m.status.selected = i
		}
		if res.removed {
			m.status.removed += {i}
		}
	}
	if primer.button(gtx, "Reset", .Invisible, .Small, leading = .Sync, key = 200) {
		m.status.removed = {}
	}
}

// LABEL_GROUP_LABELS are the live group's items.
LABEL_GROUP_LABELS := [?]string{"documentation", "bug", "good first issue", "enhancement", "help wanted", "question", "wontfix", "duplicate"}

label_group_items :: proc(gtx: ^ui.Ctx, user: rawptr) {
	for l, i in LABEL_GROUP_LABELS {
		primer.label(gtx, l, LABEL_VARIANTS[i % len(LABEL_VARIANTS)], key = u64(i + 1))
	}
}

page_label_group :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	kitchen.section(gtx, "Untruncated", "every item, 4px apart, wrapping")
	{
		sz := ui.sized_open(gtx, {max = {360, 0}}, key = 1)
		primer.label_group(gtx, label_group_items, nil, key = 1)
		ui.close(&sz)
	}
	kitchen.section(gtx, "Auto, overlay", "the items that fit beside +N; +N opens every item over the row")
	{
		sz := ui.sized_open(gtx, {max = {360, 0}}, key = 2)
		primer.label_group(gtx, label_group_items, nil, .Auto, key = 2)
		ui.close(&sz)
	}
	kitchen.section(gtx, "Count 3, inline", "the first three; +N unhides the rest in place and becomes Show less")
	{
		sz := ui.sized_open(gtx, {max = {360, 0}}, key = 3)
		primer.label_group(gtx, label_group_items, nil, .Count, 3, .Inline, key = 3)
		ui.close(&sz)
	}
	kitchen.section(gtx, "Auto, inline, narrow", "a 200px column")
	sz := ui.sized_open(gtx, {max = {200, 0}}, key = 4)
	primer.label_group(gtx, label_group_items, nil, .Auto, overflow = .Inline, key = 4)
	ui.close(&sz)
}

page_circle_badge :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	kitchen.section(gtx, "Sizes", "56 / 96 / 128px discs on bgColor default under shadow resting medium; the icon 55% of the disc")
	r := ui.wrap_open(gtx, gap = 24, align = .Center)
	defer ui.close(&r)
	primer.circle_badge(gtx, .Rocket, "Launch", .Small, key = 1)
	primer.circle_badge(gtx, .Rocket, "Launch", .Medium, key = 2)
	primer.circle_badge(gtx, .Rocket, "Launch", .Large, key = 3)
	primer.circle_badge(gtx, .Git_Branch, "Branch", diameter = 40, key = 4)
}

page_counter_label :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	kitchen.section(gtx, "Variants", "a pill 2px by 6px around semibold small text; an empty count draws nothing, \"0\" is a count")
	r := ui.wrap_open(gtx, gap = 12, align = .Center)
	defer ui.close(&r)
	primer.counter_label(gtx, "12")
	primer.counter_label(gtx, "12", .Primary)
	primer.counter_label(gtx, "0")
	primer.counter_label(gtx, "1,204", .Primary)
	primer.counter_label(gtx, "")
}

SPINNER_SIZES := [?]primer.Spinner_Size{.Small, .Medium, .Large}

page_spinner :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	kitchen.section(gtx, "Sizes", "16, 32 and 64px; the stroke stays 2px; every spinner shows the same angle")
	r := ui.wrap_open(gtx, gap = 24, align = .Center)
	defer ui.close(&r)
	for s in SPINNER_SIZES {
		primer.spinner(gtx, s, key = u64(s))
	}
	primer.spinner(gtx, .Medium, primer.color(.Fg_Color_Accent), key = 10)
	primer.spinner(gtx, .Medium, delay = .Long, key = 11)
}
