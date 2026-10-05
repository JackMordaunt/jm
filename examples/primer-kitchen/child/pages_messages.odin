package main

import "core:fmt"
import "core:time"
import "jm:ui"
import "jm:ui/primer"

import "../../kitchen"

// Messages is the messages and text pages' demo state.
Messages :: struct {
	dismissed: bool,
	banner:    string, // what the live banner last did
	blank:     string, // what the live blankslate last did
	opened:    time.Time, // when the relative-time page was first drawn
	timeline:  int, // clicks on the timeline's actions
}

// The messages and text pages, on the primer-kit's components/banner,
// inline-message, blankslate, heading, text, truncate, relative-time and
// timeline specs. These components have no states of their own: their
// actions are Buttons, whose states the Button page shows.

// narrow_box is a column capped at w, to show a component's layout when
// it is offered less than the page.
narrow_box :: proc(gtx: ^ui.Ctx, w: f32, key: u64 = 0, loc := #caller_location) -> ui.Inset {
	return ui.sized_open(gtx, {max = {w, 0}}, key, loc)
}

BANNER_VARIANTS := [?]primer.Banner_Variant{.Info, .Critical, .Success, .Upsell, .Warning}
BANNER_NAMES := [?]string{"Info", "Critical", "Success", "Upsell", "Warning"}

page_banner :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.column(gtx, gap = 10)
	kitchen.section(gtx, "Variants", "the variant's muted tint and border, its icon in its foreground; title and description keep the page's text colour")
	for v, i in BANNER_VARIANTS {
		primer.banner(gtx, fmt.tprintf("%s banner", BANNER_NAMES[i]), "A description of what happened and what to do about it.", v, key = u64(i))
	}
	kitchen.section(gtx, "Actions", "beside the content from a 500px content box, under it below that, primary first; stacked always under")
	primer.banner(gtx, "Update available", "A new version is ready to install.", primary = "Update", secondary = "Later", key = 10)
	{
		box := narrow_box(gtx, 420)
		defer ui.close(&box)
		primer.banner(gtx, "Update available", "Under 500px the actions move below.", primary = "Update", secondary = "Later", key = 11)
	}
	primer.banner(gtx, "Stacked", "Always under the content.", .Success, primary = "Review", secondary = "Dismiss", actions = .Stacked, key = 12)
	primer.banner(gtx, "Inline", "Beside the content on one row unless the window is under 768px.", .Upsell, primary = "Upgrade", actions = .Inline, key = 13)
	primer.banner(gtx, "Dismissible", "With a visible title, a dismissible banner stacks its actions whatever its width.", .Warning, primary = "Fix it", dismissible = true, key = 14)
	kitchen.section(gtx, "Compact, flush and hidden title", "4px padding; no side borders or radius; a title only assistive technology hears")
	primer.banner(gtx, "Compact", "Half the padding.", layout = .Compact, key = 20)
	primer.banner(gtx, "Flush", "Edge to edge inside a dialog or card.", .Critical, flush = true, key = 21)
	primer.banner(gtx, "Hidden title", "Only the description shows; the icon shrinks to 16px.", hide_title = true, key = 22)
	kitchen.section(gtx, "Live", "act on it or dismiss it; the caller removes it")
	if !m.messages.dismissed {
		switch primer.banner(gtx, "Build failed", "The last run of CI failed on main.", .Critical, primary = "Re-run", secondary = "View logs", dismissible = true, key = 30) {
		case .Primary:
			m.messages.banner = "Re-run"
		case .Secondary:
			m.messages.banner = "View logs"
		case .Dismiss:
			m.messages.dismissed = true
			m.messages.banner = "Dismissed"
		case .None:
		}
	} else if primer.button(gtx, "Show the banner again", key = 31) {
		m.messages.dismissed = false
	}
	primer.text(gtx, fmt.tprintf("Last: %s", m.messages.banner if m.messages.banner != "" else "nothing yet"), .Small, color = primer.color(.Fg_Color_Muted))
}

INLINE_VARIANTS := [?]primer.Inline_Variant{.None, .Critical, .Warning, .Success, .Unavailable}
INLINE_NAMES := [?]string{"No variant: a neutral note", "Critical: the name is taken", "Warning: this will rewrite history", "Success: saved", "Unavailable: this branch is locked"}

page_inline_message :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.column(gtx, gap = 10)
	kitchen.section(gtx, "Medium", "14px text, 16px outline icons, 8px apart, all in the variant's foreground")
	for v, i in INLINE_VARIANTS {
		primer.inline_message(gtx, INLINE_NAMES[i], v, key = u64(i))
	}
	kitchen.section(gtx, "Small", "12px text; the variants take 12px filled icons, no variant keeps a 16px InfoIcon")
	for v, i in INLINE_VARIANTS {
		primer.inline_message(gtx, INLINE_NAMES[i], v, .Small, key = u64(10 + i))
	}
	kitchen.section(gtx, "Wrapping", "the icon stays centred on the first line")
	box := narrow_box(gtx, 260)
	defer ui.close(&box)
	primer.inline_message(gtx, "This repository has branch protection rules that block force pushes to main.", .Warning, key = 20)
}

page_blankslate :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.column(gtx, gap = 10)
	kitchen.section(gtx, "Medium", "a muted visual, title-medium heading, body-large muted description, a primary Button and a link, each centred; 32px padding")
	switch primer.blankslate(gtx, "You don't have any projects yet", "Projects help you plan and track work across repositories.", .Project, primary = "New project", secondary = "Learn more", border = true, key = 1) {
	case .Primary:
		m.messages.blank = "New project"
	case .Secondary:
		m.messages.blank = "Learn more"
	case .None:
	}
	primer.text(gtx, fmt.tprintf("Last: %s", m.messages.blank if m.messages.blank != "" else "nothing yet"), .Small, color = primer.color(.Fg_Color_Muted))
	kitchen.section(gtx, "Small and large", "small: title-small, body-medium, 16px padding, the visual capped at 24px, a small Button; large: title-large with 8px above")
	primer.blankslate(gtx, "No results", "Try a different search.", .Search, primary = "Clear filters", size = .Small, border = true, key = 2)
	primer.blankslate(gtx, "Welcome to issues", "Issues are where you track bugs, ideas and tasks.", .Issue_Opened, primary = "New issue", size = .Large, border = true, key = 3)
	kitchen.section(gtx, "Narrow, spacious and a compact container", "narrow caps it at 485px; spacious pads 80px by 40px; offered 544px or less, every size compacts")
	primer.blankslate(gtx, "Narrow and spacious", "Capped at 485px and centred in the width it is offered, the description balanced across its lines.", .Inbox, narrow = true, spacious = true, border = true, key = 4)
	box := narrow_box(gtx, 400)
	defer ui.close(&box)
	primer.blankslate(gtx, "Offered 400px", "The heading drops to title-small, the description to body-medium.", .Project, primary = "New project", secondary = "Learn more", border = true, key = 5)
}

HEADING_VARIANTS := [?]primer.Heading_Variant{.Default, .Large, .Medium, .Small}
HEADING_NAMES := [?]string{"Default heading (32px, the page's 1.5)", "Large heading (title-large)", "Medium heading (title-medium)", "Small heading (title-small)"}

page_heading :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.column(gtx, gap = 10)
	kitchen.section(gtx, "Variants", "the title presets, semibold, no margin; the level is told to assistive technology apart from the look")
	for v, i in HEADING_VARIANTS {
		primer.heading(gtx, HEADING_NAMES[i], level = i + 1, variant = v, key = u64(i))
	}
	kitchen.section(gtx, "Wrapping", "a heading wraps at the width it is offered")
	box := narrow_box(gtx, 320)
	defer ui.close(&box)
	primer.heading(gtx, "A long heading that wraps onto a second line", variant = .Medium, key = 10)
}

TEXT_SIZES := [?]primer.Text_Size{.Small, .Medium, .Large}
TEXT_WEIGHTS := [?]primer.Text_Weight{.Light, .Normal, .Medium, .Semibold}
TEXT_WEIGHT_NAMES := [?]string{"light", "normal", "medium", "semibold"}
TEXT_SIZE_NAMES := [?]string{"Small 12/19.5", "Medium 14/21", "Large 16/24"}
WHITE_SPACES := [?]primer.White_Space{.Normal, .Nowrap, .Pre, .Pre_Wrap, .Pre_Line}
WHITE_SPACE_NAMES := [?]string{"normal", "nowrap", "pre", "pre-wrap", "pre-line"}

page_text :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.column(gtx, gap = 10)
	kitchen.section(gtx, "Sizes and weights", "body sizes with their line heights; light draws in the nearest face jm:ui has, normal")
	for s, i in TEXT_SIZES {
		ui.row(gtx, gap = 16, align = .Baseline, key = u64(i))
		for w, j in TEXT_WEIGHTS {
			primer.text(gtx, fmt.tprintf("%s %s", TEXT_SIZE_NAMES[i], TEXT_WEIGHT_NAMES[j]), s, w, key = u64(j))
		}
	}
	kitchen.section(gtx, "White space", "the same text in a 220px box under each mode")
	sample := "Spaces   and\ttabs,\n  then a line break and enough words to wrap."
	ui.wrap(gtx, gap = 24, line_gap = 16)
	for ws, i in WHITE_SPACES {
		ui.column(gtx, gap = 4, key = u64(10 + i))
		primer.text(gtx, WHITE_SPACE_NAMES[i], .Small, .Semibold, color = primer.color(.Fg_Color_Muted))
		box := narrow_box(gtx, 220)
		primer.text(gtx, sample, white_space = ws)
		ui.close(&box)
	}
}

page_truncate :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.column(gtx, gap = 10)
	kitchen.section(gtx, "Block and inline", "one line cut at 125px with an ellipsis; a block fills its parent up to the cap, inline hugs its text")
	primer.truncate(gtx, "feature/a-branch-name-far-too-long-to-show", title = "feature/a-branch-name-far-too-long-to-show")
	r := ui.row_open(gtx, gap = 8, align = .Baseline)
	primer.text(gtx, "Merging")
	primer.truncate(gtx, "jackmordaunt/a-very-long-fork-name", inline = true, key = 1)
	primer.text(gtx, "into")
	primer.truncate(gtx, "main", inline = true, key = 2)
	ui.close(&r)
	kitchen.section(gtx, "Wider caps", "maxWidth in px")
	primer.truncate(gtx, "A sentence of release notes that runs past three hundred pixels wide.", max_width = 300, key = 3)
	kitchen.section(gtx, "Expandable", "hover to show the whole line; neighbours move; the keyboard never expands it")
	ui.row(gtx, gap = 8, align = .Baseline)
	primer.truncate(gtx, "refs/heads/expand-me-to-read-the-whole-name", expandable = true, inline = true, key = 4)
	primer.counter_label(gtx, "12")
	primer.button(gtx, "Next to it", size = .Small, key = 5)
}

RELATIVE_OFFSETS := [?]time.Duration {
	-5 * time.Second,
	-3 * time.Minute,
	-5 * time.Hour,
	-26 * time.Hour,
	-10 * 24 * time.Hour,
	-45 * 24 * time.Hour,
	-400 * 24 * time.Hour,
	2 * time.Hour,
	3 * 24 * time.Hour,
}

page_relative_time :: proc(gtx: ^ui.Ctx, m: ^Model) {
	if m.messages.opened == {} {
		m.messages.opened = time.now()
	}
	now := time.now()
	ui.column(gtx, gap = 10)
	kitchen.section(gtx, "Auto", "relative within 30 days, then \"on\" a date; English, in your time zone; the precise date is the description")
	for d, i in RELATIVE_OFFSETS {
		ui.row(gtx, gap = 16, align = .Baseline, key = u64(i))
		lab := ui.sized_open(gtx, {min = {140, 0}, max = {140, 0}})
		primer.text(gtx, fmt.tprintf("%v", d), .Small, color = primer.color(.Fg_Color_Muted))
		ui.close(&lab)
		primer.relative_time(gtx, time.time_add(now, d), now = now)
		primer.relative_time(gtx, time.time_add(now, d), .Micro, now = now, key = 1)
		primer.relative_time(gtx, time.time_add(now, d), .Elapsed, now = now, key = 2)
	}
	kitchen.section(gtx, "Live", "since this page was first drawn: redrawn at each unit boundary, not every frame")
	ui.row(gtx, gap = 16, align = .Baseline)
	primer.relative_time(gtx, m.messages.opened, key = 10)
	primer.relative_time(gtx, m.messages.opened, .Elapsed, key = 11)
	primer.relative_time(gtx, time.time_add(m.messages.opened, -400 * 24 * time.Hour), options = {weekday = .Long, month = .Long, hour = .Numeric, minute = .Two_Digit, time_zone_name = true}, key = 12)
}

TIMELINE_EVENTS := [?]struct {
	badge:     primer.Icon,
	variant:   primer.Badge_Variant,
	condensed: bool,
	body:      string,
} {
	{.Git_Commit, .None, true, "jack added 2 commits"},
	{.Eye, .None, false, "monalisa reviewed these changes"},
	{.Tag, .Accent, false, "jack added the enhancement label"},
	{.Check, .Success, false, "All checks have passed"},
	{.Git_Merge, .Done, false, "jack merged this pull request into main"},
}

page_timeline :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.column(gtx, gap = 10)
	kitchen.section(gtx, "Items, badges and a break", "a 2px muted line; 32px badges ringed in the page colour; a condensed item's bare icon; avatars hang 72px left of the line")
	timeline_demo(gtx, m, .None, 1)
	kitchen.section(gtx, "Narrow and clipped", "below 480px the actions move under the body; clipped at both ends the line stops at the first badge and the last content")
	box := narrow_box(gtx, 420)
	defer ui.close(&box)
	timeline_demo(gtx, m, .Both, 2)
}

// timeline_demo is a pull request's history: a condensed commit, a
// review with an avatar and actions, labels, checks, a break, a merge.
timeline_demo :: proc(gtx: ^ui.Ctx, m: ^Model, clip: primer.Timeline_Clip, key: u64) {
	ui.inset(gtx, {left = 72}, key = key)
	tl := primer.timeline_open(gtx, clip, key = key)
	defer primer.timeline_close(&tl)
	for e, i in TIMELINE_EVENTS {
		if i == 4 {
			primer.timeline_break(&tl)
		}
		it := primer.timeline_item_open(gtx, &tl, e.badge, e.variant, e.condensed, e.body, key = u64(i))
		if i == 1 {
			av := primer.timeline_avatar_open(gtx, &it)
			primer.avatar(gtx, size = 40, alt = "monalisa")
			ui.close(&av)
			primer.text(gtx, "Looks good, one nit on the error message.", color = primer.color(.Fg_Color_Default))
			primer.timeline_actions(gtx, &it)
			if primer.button(gtx, fmt.tprintf("Reply (%d)", m.messages.timeline), size = .Small) {
				m.messages.timeline += 1
			}
			primer.icon_button(gtx, .Kebab_Horizontal, "More", .Invisible, .Small)
		}
		primer.timeline_item_close(&it)
	}
}
