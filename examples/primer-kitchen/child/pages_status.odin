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
	ui.column(gtx, gap = 10)
	kitchen.section(gtx, "Variants", "an outlined pill, no fill: 20px tall, 6px sides, medium 12px text; most borders read a bgColor emphasis token")
	{
		ui.wrap(gtx, gap = 8, line_gap = 8, align = .Center)
		for v, i in LABEL_VARIANTS {
			primer.label(gtx, LABEL_NAMES[i], v, key = u64(i))
		}
	}
	kitchen.section(gtx, "Large", "24px tall, 8px sides; the text stays 12px")
	ui.wrap(gtx, gap = 8, line_gap = 8, align = .Center)
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
	ui.column(gtx, gap = 10)
	kitchen.section(gtx, "Medium", "32px: 8px by 12px around a 16px line, the status's icon 4px before semibold onEmphasis text")
	{
		ui.wrap(gtx, gap = 8, line_gap = 8, align = .Center)
		for s, i in STATUSES {
			primer.state_label(gtx, STATUS_WORDS[i], s, key = u64(i))
		}
	}
	kitchen.section(gtx, "Small", "24px: 4px by 8px, 12px text, the icon drawn 12px")
	ui.wrap(gtx, gap = 8, line_gap = 8, align = .Center)
	for s, i in STATUSES {
		primer.state_label(gtx, STATUS_WORDS[i], s, .Small, key = u64(i))
	}
}

HUES := [?]primer.Label_Hue{.Pink, .Plum, .Purple, .Indigo, .Blue, .Cyan, .Teal, .Pine, .Green, .Lime, .Olive, .Lemon, .Yellow, .Orange, .Red, .Coral, .Gray, .Brown, .Auburn}
HUE_NAMES := [?]string{"pink", "plum", "purple", "indigo", "blue", "cyan", "teal", "pine", "green", "lime", "olive", "lemon", "yellow", "orange", "red", "coral", "gray", "brown", "auburn"}
INTERACTIVE_HUES := [?]primer.Label_Hue{.Blue, .Green, .Orange}
HEX_FILLS := [?]u32{0xd73a4aff, 0x0075caff, 0xa2eeefff, 0x7057ffff, 0xfbca04ff, 0x008672ff, 0xe4e669ff, 0xffffffff, 0x000000ff}

page_issue_label :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.column(gtx, gap = 10)
	kitchen.section(gtx, "Named hues", "--label-<hue>-* fill and text; 20px, 8px sides, semibold 12px")
	{
		ui.wrap(gtx, gap = 8, line_gap = 8, align = .Center)
		for h, i in HUES {
			primer.issue_label(gtx, HUE_NAMES[i], h, key = u64(i))
		}
	}
	kitchen.section(gtx, "Hex fills", "the fill exactly; text black above 0.179 WCAG luminance, else white, in every theme")
	{
		ui.wrap(gtx, gap = 8, line_gap = 8, align = .Center)
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
	ui.wrap(gtx, gap = 8, align = .Center)
	for h, i in HUES[:6] {
		if primer.issue_label(gtx, HUE_NAMES[i], h, interactive = true, key = u64(100 + i)) {
			m.status.clicked = HUE_NAMES[i]
		}
	}
}

page_topic_tag :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.column(gtx, gap = 10)
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
	ui.sized(gtx, {max = {360, 0}})
	primer.topic_tag_group(gtx)
	for t, i in ([]string{"immediate-mode", "odin", "ui", "design-systems", "primer", "blend2d", "accessibility", "github"}) {
		primer.topic_tag(gtx, t, key = u64(i))
	}
}

page_branch_name :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.column(gtx, gap = 10)
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
	ui.column(gtx, gap = 10)
	kitchen.section(gtx, "Sizes", "16 / 20 / 24 / 32px; a leading visual from medium up; a remove target as tall as the token")
	{
		ui.wrap(gtx, gap = 8, line_gap = 8, align = .Center)
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
		ui.wrap(gtx, gap = 8, line_gap = 8, align = .Center)
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
	ui.wrap(gtx, gap = 8, align = .Center)
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
	ui.column(gtx, gap = 10)
	kitchen.section(gtx, "Untruncated", "every item, 4px apart, wrapping")
	{
		ui.sized(gtx, {max = {360, 0}}, key = 1)
		primer.label_group(gtx, label_group_items, nil, key = 1)
	}
	kitchen.section(gtx, "Auto, overlay", "the items that fit beside +N; +N opens every item over the row")
	{
		ui.sized(gtx, {max = {360, 0}}, key = 2)
		primer.label_group(gtx, label_group_items, nil, .Auto, key = 2)
	}
	kitchen.section(gtx, "Count 3, inline", "the first three; +N unhides the rest in place and becomes Show less")
	{
		ui.sized(gtx, {max = {360, 0}}, key = 3)
		primer.label_group(gtx, label_group_items, nil, .Count, 3, .Inline, key = 3)
	}
	kitchen.section(gtx, "Auto, inline, narrow", "a 200px column")
	ui.sized(gtx, {max = {200, 0}}, key = 4)
	primer.label_group(gtx, label_group_items, nil, .Auto, overflow = .Inline, key = 4)
}

page_circle_badge :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.column(gtx, gap = 10)
	kitchen.section(gtx, "Sizes", "56 / 96 / 128px discs on bgColor default under shadow resting medium; the icon 55% of the disc")
	ui.wrap(gtx, gap = 24, align = .Center)
	primer.circle_badge(gtx, .Rocket, "Launch", .Small, key = 1)
	primer.circle_badge(gtx, .Rocket, "Launch", .Medium, key = 2)
	primer.circle_badge(gtx, .Rocket, "Launch", .Large, key = 3)
	primer.circle_badge(gtx, .Git_Branch, "Branch", diameter = 40, key = 4)
}

page_counter_label :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.column(gtx, gap = 10)
	kitchen.section(gtx, "Variants", "a pill 2px by 6px around semibold small text; an empty count draws nothing, \"0\" is a count")
	ui.wrap(gtx, gap = 12, align = .Center)
	primer.counter_label(gtx, "12")
	primer.counter_label(gtx, "12", .Primary)
	primer.counter_label(gtx, "0")
	primer.counter_label(gtx, "1,204", .Primary)
	primer.counter_label(gtx, "")
}

// AVATARS are identicons drawn for the kitchen, found from the repository
// root, where the kitchen runs.
AVATARS := [?]primer.Avatar_Source {
	{"examples/primer-kitchen/avatars/mona.png", "@mona"},
	{"examples/primer-kitchen/avatars/hubot.png", "@hubot"},
	{"examples/primer-kitchen/avatars/octocat.png", "@octocat"},
	{"examples/primer-kitchen/avatars/primer.png", "@primer"},
	{"examples/primer-kitchen/avatars/odin.png", "@odin"},
	{"examples/primer-kitchen/avatars/blend2d.png", "@blend2d"},
	{"examples/primer-kitchen/avatars/jm.png", "@jm"},
}

page_avatar :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.column(gtx, gap = 10)
	kitchen.section(gtx, "Sizes", "a size-px square clipped round, with a 1px avatar-borderColor ring outside its box")
	{
		ui.wrap(gtx, gap = 16, align = .Center)
		for s, i in ([]f32{16, 20, 24, 32, 40, 64}) {
			primer.avatar(gtx, AVATARS[i % len(AVATARS)].src, s, alt = AVATARS[i % len(AVATARS)].alt, key = u64(i))
		}
	}
	kitchen.section(gtx, "Square", "radius clamp(4px, size - 24px, 6px): 4px to 28px, 6px from 30px")
	{
		ui.wrap(gtx, gap = 16, align = .Center)
		for s, i in ([]f32{20, 28, 29, 32, 64}) {
			primer.avatar(gtx, AVATARS[3].src, s, square = true, key = u64(i))
		}
	}
	kitchen.section(gtx, "No image", "the avatar-bgColor placeholder in its ring; SkeletonAvatar takes the same box")
	ui.wrap(gtx, gap = 16, align = .Center)
	primer.avatar(gtx, size = 32, key = 1)
	primer.avatar(gtx, size = 32, square = true, key = 2)
	primer.skeleton_avatar(gtx, 32, key = 3)
	primer.skeleton_avatar(gtx, 32, true, key = 4)
}

page_avatar_stack :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.column(gtx, gap = 10)
	kitchen.section(gtx, "Cascade", "55% then 85% overlap, the 3rd to 5th at 70 / 55 / 40%; a 1px gap cut round each overlap")
	kitchen.state_header(gtx)
	{
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: primer.Interaction, key: u64) {
			primer.avatar_stack(gtx, AVATARS[:], size = 24, state = st, key = key)
		}
		kitchen.state_row(gtx, m, "Cascade", cell, 1)
	}
	{
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: primer.Interaction, key: u64) {
			primer.avatar_stack(gtx, AVATARS[:4], .Stack, 24, state = st, key = key)
		}
		kitchen.state_row(gtx, m, "Stack", cell, 2)
	}
	{
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: primer.Interaction, key: u64) {
			primer.avatar_stack(gtx, AVATARS[:3], .Stack, 24, square = true, state = st, key = key)
		}
		kitchen.state_row(gtx, m, "Square", cell, 3)
	}
	kitchen.section(gtx, "Live", "hover or focus a stack: it fans out over 200ms, over what follows; the right one is aligned right")
	ui.row(gtx, gap = 16, align = .Center)
	primer.avatar_stack(gtx, AVATARS[:], size = 32, key = 10)
	primer.label(gtx, "after the stack")
	primer.avatar_stack(gtx, AVATARS[:5], .Stack, 32, align_right = true, key = 11)
	primer.avatar_stack(gtx, AVATARS[:2], size = 32, disable_expand = true, key = 12)
}

page_progress_bar :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.column(gtx, gap = 12)
	ui.sized(gtx, {max = {480, 0}})
	ui.column(gtx, gap = 12, align = .Fill)
	kitchen.section(gtx, "Sizes", "5 / 8 / 10px tracks with small corners; the fill bgColor-success-emphasis by default")
	primer.progress_bar(gtx, 30, size = .Small, label = "Small", key = 1)
	primer.progress_bar(gtx, 50, label = "Default", key = 2)
	primer.progress_bar(gtx, 70, size = .Large, label = "Large", key = 3)
	kitchen.section(gtx, "Roles and segments", "any bgColor emphasis role; segments 2px apart, not normalised")
	primer.progress_bar(gtx, 64, .Bg_Color_Accent_Emphasis, label = "Accent", key = 4)
	segs := [?]primer.Progress_Item{{40, .Bg_Color_Success_Emphasis, "Done"}, {25, .Bg_Color_Attention_Emphasis, "Review"}, {15, .Bg_Color_Danger_Emphasis, "Blocked"}}
	primer.progress_bar_items(gtx, segs[:], .Large, key = 5)
	kitchen.section(gtx, "Animated", "a mask twice the fill's width sweeps it once a second; still under reduced motion")
	primer.progress_bar(gtx, 80, animated = true, label = "Uploading", key = 6)
	primer.progress_bar(gtx, 45, .Bg_Color_Done_Emphasis, .Large, animated = true, label = "Indexing", key = 7)
}

page_skeleton_box :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.column(gtx, gap = 12)
	kitchen.section(gtx, "Boxes", "skeletonLoader-bgColor, small corners, 16px tall by default, full width unless given one; shimmering")
	{
		ui.sized(gtx, {max = {480, 0}}, key = 1)
		primer.skeleton_box(gtx, key = 1)
	}
	ui.wrap(gtx, gap = 12, align = .Center)
	primer.skeleton_box(gtx, 120, 80, key = 2)
	primer.skeleton_box(gtx, 64, 64, key = 3)
	primer.skeleton_box(gtx, 200, 24, delay = .Long, key = 4)
}

SKELETON_ROLES := [?]primer.Type_Role{.Display, .Title_Large, .Title_Medium, .Title_Small, .Subtitle, .Body_Large, .Body_Medium, .Body_Small}
SKELETON_ROLE_NAMES := [?]string{"Display", "Title large", "Title medium", "Title small", "Subtitle", "Body large", "Body medium", "Body small"}

page_skeleton_text :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.column(gtx, gap = 8)
	kitchen.section(gtx, "Sizes", "a bar the font size tall in one line box; display and title large take medium corners")
	for role, i in SKELETON_ROLES {
		ui.row(gtx, gap = 16, align = .Center, key = u64(i))
		lbl := ui.sized_open(gtx, {min = {120, 0}, max = {120, 0}}, key = u64(i))
		primer.label(gtx, SKELETON_ROLE_NAMES[i], .Secondary)
		ui.close(&lbl)
		ui.sized(gtx, {max = {320, 0}}, key = u64(100 + i))
		primer.skeleton_text(gtx, role, key = u64(i))
	}
	kitchen.section(gtx, "Lines", "bars 2 x leading apart; the last at most 65% wide, at least 50px")
	ui.sized(gtx, {max = {360, 0}})
	primer.skeleton_text(gtx, lines = 4, key = 50)
}

page_skeleton_avatar :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.column(gtx, gap = 10)
	kitchen.section(gtx, "Sizes and shapes", "an avatar's box in shimmering skeletonLoader-bgColor, no ring; the avatar beside it for the swap")
	for square, row in ([]bool{false, true}) {
		ui.wrap(gtx, gap = 16, align = .Center, key = u64(row))
		for s, i in ([]f32{20, 32, 48, 64}) {
			primer.skeleton_avatar(gtx, s, square, key = u64(i))
			primer.avatar(gtx, AVATARS[i].src, s, square, key = u64(10 + i))
		}
	}
}

SPINNER_SIZES := [?]primer.Spinner_Size{.Small, .Medium, .Large}

page_spinner :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.column(gtx, gap = 10)
	kitchen.section(gtx, "Sizes", "16, 32 and 64px; the stroke stays 2px; every spinner shows the same angle")
	ui.wrap(gtx, gap = 24, align = .Center)
	for s in SPINNER_SIZES {
		primer.spinner(gtx, s, key = u64(s))
	}
	primer.spinner(gtx, .Medium, primer.color(.Fg_Color_Accent), key = 10)
	primer.spinner(gtx, .Medium, delay = .Long, key = 11)
}
