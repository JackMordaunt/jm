package primer

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:strings"
import "jm:ui"
import "jm:ui/base"
import "jm:ui/design"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// The label family: Label, StateLabel, IssueLabel, Token and
// IssueLabelToken, TopicTag, BranchName and CircleBadge. Each is a pill or
// chip of one line that hugs its text; the interactive ones read
// state := Interaction.Live like Button and tag themselves by their text.

// line_baseline is t's baseline when centred in a box h tall.
@(private)
line_baseline :: proc(t: Text, h: f32) -> f32 {
	return (h - t.height) / 2 + baseline_of(t)
}

// Label_Variant is a Label's text and border colour.
Label_Variant :: enum u8 {
	Default,
	Primary,
	Secondary,
	Accent,
	Success,
	Attention,
	Severe,
	Danger,
	Done,
	Sponsors,
}

// Label_Size is a Label's height: 20 or 24px.
Label_Size :: enum u8 {
	Small,
	Large,
}

// label_roles is v's text and border roles (Label.module.css:25-78). Most
// borders read a --bgColor-<role>-emphasis token, danger reads
// --borderColor-danger-emphasis and primary --fgColor-default
// (label.json notes).
@(private)
label_roles :: proc(v: Label_Variant) -> (fg, border: tok.Role) {
	switch v {
	case .Default:
		return .Fg_Color_Default, .Border_Color_Default
	case .Primary:
		return .Fg_Color_Default, .Fg_Color_Default
	case .Secondary:
		return .Fg_Color_Muted, .Border_Color_Muted
	case .Accent:
		return .Fg_Color_Accent, .Bg_Color_Accent_Emphasis
	case .Success:
		return .Fg_Color_Success, .Bg_Color_Success_Emphasis
	case .Attention:
		return .Fg_Color_Attention, .Bg_Color_Attention_Emphasis
	case .Severe:
		return .Fg_Color_Severe, .Bg_Color_Severe_Emphasis
	case .Danger:
		return .Fg_Color_Danger, .Border_Color_Danger_Emphasis
	case .Done:
		return .Fg_Color_Done, .Bg_Color_Done_Emphasis
	case .Sponsors:
		return .Fg_Color_Sponsors, .Bg_Color_Sponsors_Emphasis
	}
	return .Fg_Color_Default, .Border_Color_Default
}

// label is Primer's Label: a small outlined pill of metadata or status
// (Beta, Private) with no fill, its 1px border and text in variant's
// colours (primer-kit label.json, Label.module.css:1-79). It is exactly
// 20px (small) or 24px (large) tall with 6px or 8px sides, medium-weight
// small body text on a line of 1, and is not interactive.
//
// Departures: none; like the CSS it never wraps or truncates, so a long
// label overflows a narrow parent.
label :: proc(gtx: ^ui.Ctx, text: string, variant := Label_Variant.Default, size := Label_Size.Small, key: u64 = 0, loc := #caller_location) {
	p := ui.widget_open(gtx, key, loc)
	st := tok.Type_Style{weight = tok.BASE_TEXT_WEIGHT_MEDIUM, size = tok.TEXT_BODY_SIZE_SMALL, line_height = tok.TEXT_BODY_SIZE_SMALL}
	t := design.shape_style(gtx, text, st, font_for(gtx, st.weight))
	h, pad := tok.BASE_SIZE_20, tok.BASE_SIZE_6
	if size == .Large {
		h, pad = tok.BASE_SIZE_24, tok.BASE_SIZE_8
	}
	w := t.width + 2 * pad
	sz := ui.constrain_min(gtx.constraints, {w, h})
	y := (sz.y - h) / 2
	box := ops.Rect{0, y, w, h}
	fg, border := label_roles(variant)
	stroke_inside(gtx, {box, radius(tok.BORDER_RADIUS_FULL, box)}, color(border), tok.BORDER_WIDTH_THIN)
	draw_text(gtx, t, {pad, y + (h - t.height) / 2}, color(fg))
	said := ui.frame_string(gtx, text)
	ops.tag(gtx.scene, p.id, said, box)
	ui.semantics(gtx, &p, {role = .Text, label = said})
	ui.widget_close(gtx, &p, {sz, y + line_baseline(t, h)})
}

// State_Status is the object state a StateLabel shows; it fixes the
// colour, the icon and what the icon says (StateLabel.tsx:24-61).
State_Status :: enum u8 {
	Issue_Opened,
	Issue_Closed,
	Issue_Closed_Not_Planned,
	Issue_Draft,
	Pull_Opened,
	Pull_Closed,
	Pull_Merged,
	Pull_Queued,
	Draft,
	Unavailable,
	Alert_Opened,
	Alert_Fixed,
	Alert_Dismissed,
	Alert_Closed,
	Open,
	Closed,
	Archived,
}

// State_Look is a status's fill and ring roles, its icon and the icon's
// spoken name.
@(private)
State_Look :: struct {
	fill, ring: tok.Role,
	icon:       Icon,
	name:       string,
}

// state_look is s's look (StateLabel.module.css:24-127, StateLabel.tsx:
// 24-61): closed and issueClosed are done (purple), only pullClosed and
// alertClosed are closed (red) (state-label.json notes).
@(private)
state_look :: proc(s: State_Status) -> State_Look {
	OPEN :: [2]tok.Role{.Bg_Color_Open_Emphasis, .Border_Color_Open_Emphasis}
	DONE :: [2]tok.Role{.Bg_Color_Done_Emphasis, .Border_Color_Done_Emphasis}
	CLOSED :: [2]tok.Role{.Bg_Color_Closed_Emphasis, .Border_Color_Closed_Emphasis}
	DRAFT :: [2]tok.Role{.Bg_Color_Draft_Emphasis, .Border_Color_Draft_Emphasis}
	NEUTRAL :: [2]tok.Role{.Bg_Color_Neutral_Emphasis, .Border_Color_Neutral_Emphasis}
	ATTENTION :: [2]tok.Role{.Bg_Color_Attention_Emphasis, .Border_Color_Attention_Emphasis}
	look :: proc(r: [2]tok.Role, i: Icon, name: string) -> State_Look {
		return {r[0], r[1], i, name}
	}
	switch s {
	case .Issue_Opened:
		return look(OPEN, .Issue_Opened, "Issue")
	case .Pull_Opened:
		return look(OPEN, .Git_Pull_Request, "Pull request")
	case .Alert_Opened:
		return look(OPEN, .Shield, "Alert")
	case .Open:
		return look(OPEN, .None, "")
	case .Issue_Closed:
		return look(DONE, .Issue_Closed, "Issue")
	case .Pull_Merged:
		return look(DONE, .Git_Merge, "Pull request")
	case .Alert_Fixed:
		return look(DONE, .Shield_Check, "Alert")
	case .Closed:
		return look(DONE, .None, "")
	case .Pull_Closed:
		return look(CLOSED, .Git_Pull_Request_Closed, "Pull request")
	case .Alert_Closed:
		return look(CLOSED, .Shield_X, "Alert")
	case .Pull_Queued:
		return look(ATTENTION, .Git_Merge_Queue, "Pull request")
	case .Draft:
		return look(DRAFT, .Git_Pull_Request_Draft, "Pull request")
	case .Issue_Draft:
		return look(DRAFT, .Issue_Draft, "Issue")
	case .Alert_Dismissed:
		return look(DRAFT, .Shield_Slash, "Alert")
	case .Issue_Closed_Not_Planned:
		return look(NEUTRAL, .Skip, "Issue, not planned")
	case .Unavailable:
		return look(NEUTRAL, .Alert, "")
	case .Archived:
		return look(NEUTRAL, .Archive, "Archived")
	}
	return look(NEUTRAL, .None, "")
}

// State_Label_Size is a StateLabel's height: 24 or 32px.
State_Label_Size :: enum u8 {
	Small,
	Medium,
}

// STATE_LINE is a StateLabel's line height, a hard-coded 16px
// (StateLabel.module.css:6).
STATE_LINE :: f32(16)

// state_label is Primer's StateLabel: a filled pill naming an issue's,
// pull request's or alert's state, with the status's 16px octicon 4px
// before semibold onEmphasis text (primer-kit state-label.json,
// StateLabel.module.css:1-135). Height is padding around a 16px line:
// 4px by 8px at small (24px), 8px by 12px at medium (32px); at small the
// icon is drawn 1em (12px) wide, so 12px. A 1px inset ring of the
// status's border colour sits inside the edge. text is the visible word;
// the icon's spoken name (Issue, Pull request...) is read before it.
//
// Departures: none.
state_label :: proc(gtx: ^ui.Ctx, text: string, status: State_Status, size := State_Label_Size.Medium, key: u64 = 0, loc := #caller_location) {
	p := ui.widget_open(gtx, key, loc)
	lk := state_look(status)
	px, py, fs := tok.BASE_SIZE_12, tok.BASE_SIZE_8, tok.TEXT_BODY_SIZE_MEDIUM
	ic := f32(16)
	if size == .Small {
		px, py, fs, ic = tok.BASE_SIZE_8, tok.BASE_SIZE_4, tok.TEXT_BODY_SIZE_SMALL, tok.TEXT_BODY_SIZE_SMALL
	}
	st := tok.Type_Style{weight = tok.BASE_TEXT_WEIGHT_SEMIBOLD, size = fs, line_height = STATE_LINE}
	t := design.shape_style(gtx, text, st, font_for(gtx, st.weight))
	visual := lk.icon != .None ? ic + tok.BASE_SIZE_4 : 0
	w, h := 2 * px + visual + t.width, 2 * py + STATE_LINE
	sz := ui.constrain_min(gtx.constraints, {w, h})
	y := (sz.y - h) / 2
	box := ops.Rect{0, y, w, h}
	rr := ops.Round_Rect{box, radius(tok.BORDER_RADIUS_FULL, box)}
	ops.fill(gtx.scene, rr, color(lk.fill))
	stroke_inside(gtx, rr, color(lk.ring), tok.BORDER_WIDTH_THIN)
	on := color(.Fg_Color_On_Emphasis)
	if lk.icon != .None {
		icon(gtx, lk.icon, {px, y + (h - ic) / 2}, ic, on)
	}
	draw_text(gtx, t, {px + visual, y + py}, on)
	said := ui.frame_string(gtx, text)
	ops.tag(gtx.scene, p.id, said, box)
	spoken := said
	if lk.name != "" {
		spoken = strings.concatenate({lk.name, " ", text}, gtx.allocator)
	}
	ui.semantics(gtx, &p, {role = .Text, label = spoken})
	ui.widget_close(gtx, &p, {sz, y + py + baseline_of(t)})
}

// Label_Hue is an IssueLabel's named colour (issue-label.json variants):
// each reads its --label-<hue>-* tokens.
Label_Hue :: enum u8 {
	Pink,
	Plum,
	Purple,
	Indigo,
	Blue,
	Cyan,
	Teal,
	Pine,
	Green,
	Lime,
	Olive,
	Lemon,
	Yellow,
	Orange,
	Red,
	Coral,
	Gray,
	Brown,
	Auburn,
}

// HUE_ROLES is each hue's fill and text per state; there is no disabled
// state, so that slot repeats rest (IssueLabel.module.css:46-215).
@(private, rodata)
HUE_ROLES := [Label_Hue][2]State_Roles {
	.Pink = {{.Label_Pink_Bg_Color_Rest, .Label_Pink_Bg_Color_Hover, .Label_Pink_Bg_Color_Active, .Label_Pink_Bg_Color_Rest}, {.Label_Pink_Fg_Color_Rest, .Label_Pink_Fg_Color_Hover, .Label_Pink_Fg_Color_Active, .Label_Pink_Fg_Color_Rest}},
	.Plum = {{.Label_Plum_Bg_Color_Rest, .Label_Plum_Bg_Color_Hover, .Label_Plum_Bg_Color_Active, .Label_Plum_Bg_Color_Rest}, {.Label_Plum_Fg_Color_Rest, .Label_Plum_Fg_Color_Hover, .Label_Plum_Fg_Color_Active, .Label_Plum_Fg_Color_Rest}},
	.Purple = {{.Label_Purple_Bg_Color_Rest, .Label_Purple_Bg_Color_Hover, .Label_Purple_Bg_Color_Active, .Label_Purple_Bg_Color_Rest}, {.Label_Purple_Fg_Color_Rest, .Label_Purple_Fg_Color_Hover, .Label_Purple_Fg_Color_Active, .Label_Purple_Fg_Color_Rest}},
	.Indigo = {{.Label_Indigo_Bg_Color_Rest, .Label_Indigo_Bg_Color_Hover, .Label_Indigo_Bg_Color_Active, .Label_Indigo_Bg_Color_Rest}, {.Label_Indigo_Fg_Color_Rest, .Label_Indigo_Fg_Color_Hover, .Label_Indigo_Fg_Color_Active, .Label_Indigo_Fg_Color_Rest}},
	.Blue = {{.Label_Blue_Bg_Color_Rest, .Label_Blue_Bg_Color_Hover, .Label_Blue_Bg_Color_Active, .Label_Blue_Bg_Color_Rest}, {.Label_Blue_Fg_Color_Rest, .Label_Blue_Fg_Color_Hover, .Label_Blue_Fg_Color_Active, .Label_Blue_Fg_Color_Rest}},
	.Cyan = {{.Label_Cyan_Bg_Color_Rest, .Label_Cyan_Bg_Color_Hover, .Label_Cyan_Bg_Color_Active, .Label_Cyan_Bg_Color_Rest}, {.Label_Cyan_Fg_Color_Rest, .Label_Cyan_Fg_Color_Hover, .Label_Cyan_Fg_Color_Active, .Label_Cyan_Fg_Color_Rest}},
	.Teal = {{.Label_Teal_Bg_Color_Rest, .Label_Teal_Bg_Color_Hover, .Label_Teal_Bg_Color_Active, .Label_Teal_Bg_Color_Rest}, {.Label_Teal_Fg_Color_Rest, .Label_Teal_Fg_Color_Hover, .Label_Teal_Fg_Color_Active, .Label_Teal_Fg_Color_Rest}},
	.Pine = {{.Label_Pine_Bg_Color_Rest, .Label_Pine_Bg_Color_Hover, .Label_Pine_Bg_Color_Active, .Label_Pine_Bg_Color_Rest}, {.Label_Pine_Fg_Color_Rest, .Label_Pine_Fg_Color_Hover, .Label_Pine_Fg_Color_Active, .Label_Pine_Fg_Color_Rest}},
	.Green = {{.Label_Green_Bg_Color_Rest, .Label_Green_Bg_Color_Hover, .Label_Green_Bg_Color_Active, .Label_Green_Bg_Color_Rest}, {.Label_Green_Fg_Color_Rest, .Label_Green_Fg_Color_Hover, .Label_Green_Fg_Color_Active, .Label_Green_Fg_Color_Rest}},
	.Lime = {{.Label_Lime_Bg_Color_Rest, .Label_Lime_Bg_Color_Hover, .Label_Lime_Bg_Color_Active, .Label_Lime_Bg_Color_Rest}, {.Label_Lime_Fg_Color_Rest, .Label_Lime_Fg_Color_Hover, .Label_Lime_Fg_Color_Active, .Label_Lime_Fg_Color_Rest}},
	.Olive = {{.Label_Olive_Bg_Color_Rest, .Label_Olive_Bg_Color_Hover, .Label_Olive_Bg_Color_Active, .Label_Olive_Bg_Color_Rest}, {.Label_Olive_Fg_Color_Rest, .Label_Olive_Fg_Color_Hover, .Label_Olive_Fg_Color_Active, .Label_Olive_Fg_Color_Rest}},
	.Lemon = {{.Label_Lemon_Bg_Color_Rest, .Label_Lemon_Bg_Color_Hover, .Label_Lemon_Bg_Color_Active, .Label_Lemon_Bg_Color_Rest}, {.Label_Lemon_Fg_Color_Rest, .Label_Lemon_Fg_Color_Hover, .Label_Lemon_Fg_Color_Active, .Label_Lemon_Fg_Color_Rest}},
	.Yellow = {{.Label_Yellow_Bg_Color_Rest, .Label_Yellow_Bg_Color_Hover, .Label_Yellow_Bg_Color_Active, .Label_Yellow_Bg_Color_Rest}, {.Label_Yellow_Fg_Color_Rest, .Label_Yellow_Fg_Color_Hover, .Label_Yellow_Fg_Color_Active, .Label_Yellow_Fg_Color_Rest}},
	.Orange = {{.Label_Orange_Bg_Color_Rest, .Label_Orange_Bg_Color_Hover, .Label_Orange_Bg_Color_Active, .Label_Orange_Bg_Color_Rest}, {.Label_Orange_Fg_Color_Rest, .Label_Orange_Fg_Color_Hover, .Label_Orange_Fg_Color_Active, .Label_Orange_Fg_Color_Rest}},
	.Red = {{.Label_Red_Bg_Color_Rest, .Label_Red_Bg_Color_Hover, .Label_Red_Bg_Color_Active, .Label_Red_Bg_Color_Rest}, {.Label_Red_Fg_Color_Rest, .Label_Red_Fg_Color_Hover, .Label_Red_Fg_Color_Active, .Label_Red_Fg_Color_Rest}},
	.Coral = {{.Label_Coral_Bg_Color_Rest, .Label_Coral_Bg_Color_Hover, .Label_Coral_Bg_Color_Active, .Label_Coral_Bg_Color_Rest}, {.Label_Coral_Fg_Color_Rest, .Label_Coral_Fg_Color_Hover, .Label_Coral_Fg_Color_Active, .Label_Coral_Fg_Color_Rest}},
	.Gray = {{.Label_Gray_Bg_Color_Rest, .Label_Gray_Bg_Color_Hover, .Label_Gray_Bg_Color_Active, .Label_Gray_Bg_Color_Rest}, {.Label_Gray_Fg_Color_Rest, .Label_Gray_Fg_Color_Hover, .Label_Gray_Fg_Color_Active, .Label_Gray_Fg_Color_Rest}},
	.Brown = {{.Label_Brown_Bg_Color_Rest, .Label_Brown_Bg_Color_Hover, .Label_Brown_Bg_Color_Active, .Label_Brown_Bg_Color_Rest}, {.Label_Brown_Fg_Color_Rest, .Label_Brown_Fg_Color_Hover, .Label_Brown_Fg_Color_Active, .Label_Brown_Fg_Color_Rest}},
	.Auburn = {{.Label_Auburn_Bg_Color_Rest, .Label_Auburn_Bg_Color_Hover, .Label_Auburn_Bg_Color_Active, .Label_Auburn_Bg_Color_Rest}, {.Label_Auburn_Fg_Color_Rest, .Label_Auburn_Fg_Color_Hover, .Label_Auburn_Fg_Color_Active, .Label_Auburn_Fg_Color_Rest}},
}

// READABLE_LUMINANCE is the relative luminance above which a hex label's
// text is black, below or at which it is white (color2k 2.0.3's
// readableColor; issue-label.json behaviour hex-text-colour).
READABLE_LUMINANCE :: f32(0.179)

// readable_text is the text colour on an arbitrary fill: black when the
// fill's WCAG relative luminance (each channel linearised, then 0.2126 R
// + 0.7152 G + 0.0722 B) is above 0.179, else white; the same in every
// theme. Like the CSS it is a literal black or white, not a token.
readable_text :: proc(fill: ops.Color) -> ops.Color {
	if design.luminance(fill) > READABLE_LUMINANCE {
		return {0, 0, 0, 255}
	}
	return {255, 255, 255, 255}
}

// issue_label is Primer's IssueLabel: a filled pill naming a user-defined
// issue label, at least 20px tall with 8px sides and semibold small text
// (primer-kit issue-label.json, IssueLabel.module.css:2-43). hue picks a
// named colour's --label-<hue>-* tokens; a fill (any opaque colour, alpha
// 0 for none) overrides it, painted exactly, with black or white text by
// readable_text. interactive makes it a button: the hue's hover and
// pressed tokens apply at once (no fade), and keyboard focus draws the
// 2px outline 2px outside the pill. Returns true on activation.
//
// Departures: a hex label has no hover or pressed colour, as on the web,
// where its inline colours outrank the module's (issue-label.json
// notes); the transparent high-contrast ring is not drawn.
issue_label :: proc(
	gtx: ^ui.Ctx,
	text: string,
	hue := Label_Hue.Gray,
	fill := ops.Color{},
	interactive := false,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_open(gtx, key, loc)
	st := tok.Type_Style {
		weight      = tok.BASE_TEXT_WEIGHT_SEMIBOLD,
		size        = tok.TEXT_BODY_SIZE_SMALL,
		line_height = tok.TEXT_BODY_SIZE_SMALL * tok.TEXT_BODY_LINE_HEIGHT_SMALL,
	}
	t := design.shape_style(gtx, text, st, font_for(gtx, st.weight))
	pad := tok.BASE_SIZE_8
	w, h := t.width + 2 * pad, max(tok.BASE_SIZE_20, t.height)
	sz := ui.constrain_min(gtx.constraints, {w, h})
	y := (sz.y - h) / 2
	box := ops.Rect{0, y, w, h}
	rr := ops.Round_Rect{box, radius(tok.BORDER_RADIUS_FULL, box)}
	c: Control
	if interactive {
		c = control(gtx, p.id, box, state)
	}
	bg, fg: ops.Color
	if fill[3] != 0 {
		bg, fg = fill, readable_text(fill)
	} else {
		roles := HUE_ROLES[hue]
		bg, fg = color_for(roles[0], c), color_for(roles[1], c)
	}
	ops.fill(gtx.scene, rr, bg)
	draw_text(gtx, t, {pad, y + (h - t.height) / 2}, fg)
	said := ui.frame_string(gtx, text)
	ops.tag(gtx.scene, p.id, said, box)
	if interactive {
		paint_focus_outline(gtx, c, rr, ISSUE_LABEL_FOCUS_OFFSET)
		listen(gtx, c.st, p.id, box, cursor = .Pointer)
		ui.semantics(gtx, &p, {role = .Button, label = said})
	} else {
		ui.semantics(gtx, &p, {role = .Text, label = said})
	}
	ui.widget_close(gtx, &p, {sz, y + line_baseline(t, h)})
	return interactive && c.clicked
}

// ISSUE_LABEL_FOCUS_OFFSET puts an IssueLabel's outline 2px outside the
// pill, not inside (IssueLabel.module.css:41-43).
ISSUE_LABEL_FOCUS_OFFSET :: f32(2)

// Topic_Element is what a TopicTag is: a link (the default), a button or
// a plain span.
Topic_Element :: enum u8 {
	Link,
	Button,
	Span,
}

// topic_tag is Primer's TopicTag: a full-radius accent-muted pill of
// small semibold accent text, 2px by 12px around a 19.5px line plus a
// 1px --topicTag-borderColor border (transparent but in high contrast):
// 25.5px tall (primer-kit topic-tag.json, TopicTag.module.css:13-35).
// Hovered it fills --bgColor-accent-emphasis with onEmphasis text at
// once, whatever element it is, as the CSS's :hover rule applies to a
// span too. A link or button tag is focusable and returns true on
// activation; a span never does.
//
// Departure: TopicTag.module.css:13-35 has no focus rule, leaving the
// browser's ring (topic-tag.json notes); this draws Primer's 2px outline
// for keyboard focus.
topic_tag :: proc(gtx: ^ui.Ctx, text: string, element := Topic_Element.Link, state := Interaction.Live, key: u64 = 0, loc := #caller_location) -> bool {
	p := ui.widget_open(gtx, key, loc)
	st := tok.Type_Style {
		weight      = tok.BASE_TEXT_WEIGHT_SEMIBOLD,
		size        = tok.TEXT_BODY_SIZE_SMALL,
		line_height = tok.TEXT_BODY_SIZE_SMALL * tok.TEXT_BODY_LINE_HEIGHT_SMALL,
	}
	t := design.shape_style(gtx, text, st, font_for(gtx, st.weight))
	b := tok.BORDER_WIDTH_THIN
	px, py := tok.BASE_SIZE_12, tok.BASE_SIZE_2
	w, h := t.width + 2 * (px + b), t.height + 2 * (py + b)
	sz := ui.constrain_min(gtx.constraints, {w, h})
	y := (sz.y - h) / 2
	box := ops.Rect{0, y, w, h}
	rr := ops.Round_Rect{box, radius(tok.BORDER_RADIUS_FULL, box)}
	c := control(gtx, p.id, box, element == .Span && state == .Focused ? .Enabled : state)
	hot := c.hovered && !c.disabled
	ops.fill(gtx.scene, rr, color(hot ? .Bg_Color_Accent_Emphasis : .Bg_Color_Accent_Muted))
	if border := color(.Topic_Tag_Border_Color); ui.painted(border) {
		stroke_inside(gtx, rr, border, b)
	}
	draw_text(gtx, t, {px + b, y + py + b}, color(hot ? .Fg_Color_On_Emphasis : .Fg_Color_Accent))
	said := ui.frame_string(gtx, text)
	ops.tag(gtx.scene, p.id, said, box)
	switch element {
	case .Link, .Button:
		paint_focus_outline(gtx, c, rr)
		listen(gtx, c.st, p.id, box, cursor = .Pointer)
		ui.semantics(gtx, &p, {role = element == .Link ? .Link : .Button, label = said})
	case .Span:
		listen(gtx, c.st, p.id, box, {.Move, .Enter, .Leave})
		ui.semantics(gtx, &p, {role = .Text, label = said})
	}
	ui.widget_close(gtx, &p, {sz, y + py + b + baseline_of(t)})
	return element != .Span && c.clicked
}

// topic_tag_group_open is TopicTag.Group: a wrapping row of tags 2px
// apart, lines 8px apart (TopicTagGroup.module.css:1-6). Close it with
// ui.close.
topic_tag_group_open :: proc(gtx: ^ui.Ctx, key: u64 = 0, loc := #caller_location) -> ui.Flex {
	return ui.wrap_open(gtx, gap = tok.BASE_SIZE_2, line_gap = tok.BASE_SIZE_8, align = .Center, key = key, loc = loc)
}

// BRANCH_LINE is a BranchName's line: it inherits the text around it,
// BaseStyles' unitless 1.5 at the chip's own 12px, 18px (branch-name.json
// notes).
BRANCH_LINE :: tok.TEXT_BODY_SIZE_SMALL * 1.5

// branch_name is Primer's BranchName: a branch's name in the monospace
// face (mono_font) at small body size, 2px by 6px inside an accent-muted
// chip with medium corners, no border (primer-kit branch-name.json,
// BranchName.module.css:1-14): 22px tall on an 18px line. As a link
// (link, the default) its text is --fgColor-link, it is focusable and it
// returns true on activation; otherwise its text is --fgColor-muted and
// it is plain text.
//
// Departures: BranchName.module.css:1-14 has no focus rule, leaving the
// browser's ring (branch-name.json states); a linked chip here draws
// Primer's 2px outline for keyboard focus. A long
// name neither wraps nor truncates: the chip widens.
branch_name :: proc(gtx: ^ui.Ctx, name: string, link := true, state := Interaction.Live, key: u64 = 0, loc := #caller_location) -> bool {
	p := ui.widget_open(gtx, key, loc)
	st := tok.Type_Style{weight = tok.BASE_TEXT_WEIGHT_NORMAL, size = tok.TEXT_BODY_SIZE_SMALL, line_height = BRANCH_LINE}
	t := design.shape_style(gtx, name, st, mono_font(gtx))
	px, py := tok.BASE_SIZE_6, tok.BASE_SIZE_2
	w, h := t.width + 2 * px, t.height + 2 * py
	sz := ui.constrain_min(gtx.constraints, {w, h})
	y := (sz.y - h) / 2
	box := ops.Rect{0, y, w, h}
	rr := ops.Round_Rect{box, radius(tok.BORDER_RADIUS_MEDIUM, box)}
	ops.fill(gtx.scene, rr, color(.Bg_Color_Accent_Muted))
	draw_text(gtx, t, {px, y + py}, color(link ? .Fg_Color_Link : .Fg_Color_Muted))
	said := ui.frame_string(gtx, name)
	ops.tag(gtx.scene, p.id, said, box)
	c: Control
	if link {
		c = control(gtx, p.id, box, state)
		paint_focus_outline(gtx, c, rr)
		listen(gtx, c.st, p.id, box, cursor = .Pointer)
		ui.semantics(gtx, &p, {role = .Link, label = said})
	} else {
		ui.semantics(gtx, &p, {role = .Text, label = said})
	}
	ui.widget_close(gtx, &p, {sz, y + py + baseline_of(t)})
	return link && c.clicked
}

// Circle_Badge_Size is a CircleBadge's diameter: 56, 96 or 128px
// (CircleBadge.tsx:9-13).
Circle_Badge_Size :: enum u8 {
	Small,
	Medium,
	Large,
}

@(rodata)
CIRCLE_BADGE_DIAMETER := [Circle_Badge_Size]f32{.Small = 56, .Medium = 96, .Large = 128}

// CIRCLE_BADGE_ICON is the share of the disc's height an icon may take:
// at most 60% of its width and 55% of its height, so a square octicon is
// 55% (CircleBadge.module.css:14-18).
CIRCLE_BADGE_ICON :: f32(0.55)

// circle_badge is Primer's CircleBadge, deprecated upstream with no
// replacement: a disc of --bgColor-default under --shadow-resting-medium
// holding ic centred, 55% of the disc tall, in --fgColor-default
// (primer-kit circle-badge.json, CircleBadge.module.css:1-18). diameter
// overrides size when above 0. name is what a reader hears, as the icon's
// aria-label; empty leaves the badge decorative.
//
// Departure: content is an octicon only, not an image.
circle_badge :: proc(gtx: ^ui.Ctx, ic: Icon, name := "", size := Circle_Badge_Size.Medium, diameter: f32 = 0, key: u64 = 0, loc := #caller_location) {
	p := ui.widget_open(gtx, key, loc)
	d := diameter > 0 ? diameter : CIRCLE_BADGE_DIAMETER[size]
	sz := ui.constrain_min(gtx.constraints, {d, d})
	box := ops.Rect{0, (sz.y - d) / 2, d, d}
	rr := ops.Round_Rect{box, d / 2}
	paint_shadow(gtx, rr, tok.SHADOW_RESTING_MEDIUM)
	ops.fill(gtx.scene, rr, color(.Bg_Color_Default))
	s := d * CIRCLE_BADGE_ICON
	iw := icon_width(ic, s)
	if iw > d * 0.6 {
		s *= d * 0.6 / iw
		iw = d * 0.6
	}
	icon(gtx, ic, {(d - iw) / 2, box.y + (d - s) / 2}, s, color(.Fg_Color_Default))
	said := ui.frame_string(gtx, name)
	if said != "" {
		ops.tag(gtx.scene, p.id, said, box)
		ui.semantics(gtx, &p, {role = .Image, label = said})
	}
	ui.widget_close(gtx, &p, {sz, 0})
}

// Token_Size is a Token's height: 16, 20, 24 or 32px.
Token_Size :: enum u8 {
	Small,
	Medium,
	Large,
	XLarge,
}

// Token_Metrics are one size's dimensions (TokenBase.module.css:22-54,
// _RemoveTokenButton.module.css:1-39, Token.module.css:25-34): height,
// side padding, text size, the gap before the remove button and after a
// leading visual, and the remove X's size.
@(private)
Token_Metrics :: struct {
	height, pad, text, gap, x: f32,
}

@(private)
token_metrics :: proc(s: Token_Size) -> Token_Metrics {
	switch s {
	case .Small:
		return {tok.BASE_SIZE_16, tok.BASE_SIZE_4, tok.TEXT_BODY_SIZE_SMALL, tok.BASE_SIZE_4, 12}
	case .Large:
		return {tok.BASE_SIZE_24, tok.BASE_SIZE_8, tok.TEXT_BODY_SIZE_MEDIUM, tok.BASE_SIZE_6, 16}
	case .XLarge:
		return {tok.BASE_SIZE_32, tok.BASE_SIZE_12, tok.TEXT_BODY_SIZE_MEDIUM, tok.BASE_SIZE_6, 16}
	case .Medium:
	}
	return {tok.BASE_SIZE_20, tok.BASE_SIZE_6, tok.TEXT_BODY_SIZE_SMALL, tok.BASE_SIZE_4, 12}
}

// TOKEN_VISUAL is a leading visual's size: an octicon's default 16px.
TOKEN_VISUAL :: f32(16)

// TOKEN_REMOVE_HINT is what a removable Token adds to its name, visually
// hidden (Token.tsx:84).
TOKEN_REMOVE_HINT :: " (press backspace or delete to remove)"

// Token_Result is what a token reports on a frame: clicked when it was
// activated, removed when its remove button was pressed or Backspace or
// Delete reached it.
Token_Result :: struct {
	clicked, removed: bool,
}

// Token_Look is a token's colours for the frame: fill, border, text, an
// optional 2px ring 2px outside (IssueLabelToken selected) and whether it
// lifts with --shadow-resting-medium.
@(private)
Token_Look :: struct {
	fill, border, text, ring: ops.Color,
	lift:                     bool,
}

// Token_Opts is what a token was asked to be: removable (a remove button
// unless hide_remove; Backspace and Delete remove either way), selected,
// interactive (a button; Token's on_click), with a leading visual.
@(private)
Token_Opts :: struct {
	text:                                                 string,
	size:                                                 Token_Size,
	leading:                                              Icon,
	removable, hide_remove, selected, interactive, issue: bool,
	fill:                                                 ops.Color,
	no_tab:                                               bool, // out of Tab's order: a token field's tokens, which arrows reach
	focus_selects:                                        bool, // looks selected while it holds focus: a token field's
}

// token is Primer's Token: a full-radius pill with a 1px border and one
// line of semibold text, --fgColor-muted on --bgColor-neutral-muted with
// a --borderColor-muted border; selected (the token a caret is on) turns
// text --fgColor-default and the border --borderColor-emphasis (primer-kit
// token.json, Token.module.css:1-34, TokenBase.module.css:1-54). Its
// height is the size's base size exactly, 16, 20, 24 or 32px. leading
// draws a 16px octicon 4px (6px at large and up) before the text, never
// at small. removable adds a round remove target as tall as the token at
// its end, with a 12px X (16px at large and up), filled
// --control-transparent-bgColor-hover on hover and -active pressed;
// hide_remove keeps only keyboard removal. interactive makes the token a
// button. When it is interactive and shows a remove button, the remove
// target sits over the token's own and takes its own clicks but not
// focus; removal is then Backspace or Delete on the focused token. The
// text ends in an ellipsis when the token is narrower than its content.
//
// Departures: a Token shows no hover lift, as on the web, where the hover
// rule's [data-interactive] is never set (token.json notes); a leading
// visual is an octicon, not an avatar; TokenBase.module.css and
// _RemoveTokenButton.module.css have no focus rule (token.json notes),
// and this draws Primer's 2px outline on the token and the remove button.
token :: proc(
	gtx: ^ui.Ctx,
	text: string,
	size := Token_Size.Medium,
	leading := Icon.None,
	removable := false,
	hide_remove := false,
	selected := false,
	interactive := false,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> Token_Result {
	return token_widget(gtx, {text, size, leading, removable, hide_remove, selected, interactive, false, {}, false, false}, state, key, loc)
}

// issue_label_token is Primer's IssueLabelToken: a Token whose every
// colour derives from fill, a label's arbitrary colour, by
// issue_label_token_look's light or dark formula for the theme's family
// (token.json behaviour issue-label-token-colour). Selected draws a 2px
// ring 2px outside the pill; an interactive token lifts with
// --shadow-resting-medium on hover and darkens (light) or brightens
// (dark) its fill. It has no leading visual and no spoken removal hint.
issue_label_token :: proc(
	gtx: ^ui.Ctx,
	text: string,
	fill: ops.Color,
	size := Token_Size.Medium,
	removable := false,
	hide_remove := false,
	selected := false,
	interactive := false,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> Token_Result {
	return token_widget(gtx, {text, size, .None, removable, hide_remove, selected, interactive, true, fill, false, false}, state, key, loc)
}

// HSL is a colour's hue in degrees and saturation and lightness in
// percent, each rounded to an integer as IssueLabelToken.tsx:48-60 sets
// its custom properties.
HSL :: struct {
	h, s, l: f32,
}

// to_hsl is c in HSL, rounded as the token's CSS variables are.
to_hsl :: proc(c: ops.Color) -> HSL {
	r, g, b := f32(c[0]) / 255, f32(c[1]) / 255, f32(c[2]) / 255
	hi, lo := max(r, g, b), min(r, g, b)
	l := (hi + lo) / 2
	h, s: f32
	if hi != lo {
		d := hi - lo
		s = l > 0.5 ? d / (2 - hi - lo) : d / (hi + lo)
		switch hi {
		case r:
			h = (g - b) / d + (g < b ? 6 : 0)
		case g:
			h = (b - r) / d + 2
		case:
			h = (r - g) / d + 4
		}
		h *= 60
	}
	return {math.round(h), math.round(s * 100), math.round(l * 100)}
}

// from_hsl is CSS's hsl(h, s%, l%) at alpha a (0-1), lightness clamped
// to 0-100% as CSS clamps it.
from_hsl :: proc(c: HSL, a: f32 = 1) -> ops.Color {
	s, l := clamp(c.s, 0, 100) / 100, clamp(c.l, 0, 100) / 100
	k :: proc(n, h, s, l: f32) -> u8 {
		kk := math.mod(n + h / 30, 12)
		v := l - s * min(l, 1 - l) * max(-1, min(kk - 3, 9 - kk, 1))
		return u8(math.round(clamp(v, 0, 1) * 255))
	}
	h := math.mod(math.mod(c.h, 360) + 360, 360)
	return {k(0, h, s, l), k(8, h, s, l), k(4, h, s, l), u8(math.round(clamp(a, 0, 1) * 255))}
}

// perceived_lightness is IssueLabelToken's P: (0.2126 r + 0.7152 g +
// 0.0722 b) / 255 with no gamma linearisation (IssueLabelToken.module.css
// :66-78).
perceived_lightness :: proc(c: ops.Color) -> f32 {
	return (0.2126 * f32(c[0]) + 0.7152 * f32(c[1]) + 0.0722 * f32(c[2])) / 255
}

// lightness_switch is clamp(1 / (t - p), 0, 1): 1 below the threshold,
// 0 above, and 1 at it, where CSS's 1/0 is infinity (token.json notes).
lightness_switch :: proc(p, t: f32) -> f32 {
	if p == t {
		return 1
	}
	return clamp(1 / (t - p), 0, 1)
}

// LIGHT_THRESHOLD and DARK_THRESHOLD are the perceived lightness a fill
// must stay below for light text: 0.453 in light themes, 0.6 in dark
// (IssueLabelToken.module.css:3,36).
LIGHT_THRESHOLD :: f32(0.453)
DARK_THRESHOLD :: f32(0.6)

// issue_label_token_look is an IssueLabelToken's colours for fill in
// mode, selected or hovered-while-interactive (IssueLabelToken.module.css
// :2-64). Light: the fill itself, white or black text by the switch, a
// border hsla(h, s, l - 25) only near white, and selected a fill 5%
// darker ringed in the fill; hover lays 15% black over the fill. Dark:
// the fill at 18%, text hsl(h, s, l + lighten) with lighten = (0.6 - P)
// x 100 x switch, the border that text at 30%, selected ringed in the
// text; hover fills hsla(h, s, l + 10, 0.3).
issue_label_token_look :: proc(fill: ops.Color, mode: base.Mode, selected, hovered: bool) -> (lk: Token_Look) {
	c := to_hsl(fill)
	p := perceived_lightness(fill)
	opaque := ops.Color{fill[0], fill[1], fill[2], 255}
	switch mode {
	case .Light:
		sw := lightness_switch(p, LIGHT_THRESHOLD)
		lk.fill = opaque
		v := u8(math.round(sw * 255))
		lk.text = {v, v, v, 255}
		lk.border = from_hsl({c.h, c.s, c.l - 25}, clamp((p - 0.96) * 100, 0, 1))
		if selected {
			lk.fill = from_hsl({c.h, c.s, c.l - 5})
			lk.ring = opaque
		}
		if hovered {
			lk.fill = ops.mix(lk.fill, {0, 0, 0, 255}, 0.15)
			lk.lift = true
		}
	case .Dark:
		sw := lightness_switch(p, DARK_THRESHOLD)
		lighten := (DARK_THRESHOLD - p) * 100 * sw
		lk.fill = {fill[0], fill[1], fill[2], u8(math.round(0.18 * 255))}
		lk.text = from_hsl({c.h, c.s, c.l + lighten})
		lk.border = from_hsl({c.h, c.s, c.l + lighten}, 0.3)
		if selected {
			lk.ring = lk.text
		}
		if hovered {
			lk.fill = from_hsl({c.h, c.s, c.l + 10}, 0.3)
			lk.lift = true
		}
	}
	return
}

// token_widget is token and issue_label_token.
@(private)
token_widget :: proc(gtx: ^ui.Ctx, o: Token_Opts, state: Interaction, key: u64, loc: runtime.Source_Code_Location) -> (res: Token_Result) {
	p := ui.widget_open(gtx, key, loc)
	mt := token_metrics(o.size)
	st := tok.Type_Style{weight = tok.BASE_TEXT_WEIGHT_SEMIBOLD, size = mt.text, line_height = mt.text}
	font := font_for(gtx, st.weight)
	t := design.shape_style(gtx, o.text, st, font)
	b := tok.BORDER_WIDTH_THIN
	shows_remove := o.removable && !o.hide_remove
	visual := o.leading != .None && o.size != .Small
	lead := visual ? TOKEN_VISUAL + (o.size >= .Large ? tok.BASE_SIZE_6 : tok.BASE_SIZE_4) : 0
	tail := shows_remove ? mt.gap + mt.height - b : mt.pad
	natural := b + mt.pad + lead + t.width + tail + b
	w := min(natural, gtx.constraints.max.x)
	sz := ui.constrain_min(gtx.constraints, {w, mt.height})
	y := (sz.y - mt.height) / 2
	box := ops.Rect{0, y, w, mt.height}
	rr := ops.Round_Rect{box, radius(tok.BORDER_RADIUS_FULL, box)}
	two := o.interactive && shows_remove
	c: Control
	if o.interactive {
		c = control(gtx, p.id, box, state)
	}
	look: Token_Look
	selected := o.selected || (o.focus_selects && c.focused && !c.disabled)
	if o.issue {
		look = issue_label_token_look(o.fill, mode_of(theme()), selected, o.interactive && c.hovered && !c.disabled)
	} else {
		look = {color(.Bg_Color_Neutral_Muted), color(selected ? .Border_Color_Emphasis : .Border_Color_Muted), color(selected ? .Fg_Color_Default : .Fg_Color_Muted), {}, false}
	}
	if look.lift {
		paint_shadow(gtx, rr, tok.SHADOW_RESTING_MEDIUM)
	}
	ops.fill(gtx.scene, rr, look.fill)
	if ui.painted(look.border) {
		stroke_inside(gtx, rr, look.border, b)
	}
	x := b + mt.pad
	if visual {
		icon(gtx, o.leading, {x, y + (mt.height - TOKEN_VISUAL) / 2}, TOKEN_VISUAL, look.text)
		x += lead
	}
	room := w - x - tail - b
	if t.width <= room {
		draw_text(gtx, t, {x, y + (mt.height - t.height) / 2}, look.text)
	} else {
		line := design.layout_style(gtx, o.text, st, font, max(room, 0), max_lines = 1)
		draw_paragraph(gtx, line, {x, y + (mt.height - t.height) / 2}, look.text)
	}
	if ui.painted(look.ring) {
		ring := tok.BASE_SIZE_2
		out := ops.Rect{box.x - 2 * ring, box.y - 2 * ring, box.w + 4 * ring, box.h + 4 * ring}
		stroke_inside(gtx, {out, radius(tok.BORDER_RADIUS_FULL, out)}, look.ring, ring)
	}
	said := ui.frame_string(gtx, o.text)
	ops.tag(gtx.scene, p.id, said, box)
	name := said
	if o.removable && !o.issue {
		name = strings.concatenate({o.text, TOKEN_REMOVE_HINT}, gtx.allocator)
	}
	if o.interactive {
		paint_focus_outline(gtx, c, rr)
		listen(gtx, c.st, p.id, box, CLICK_KINDS, .Pointer, no_tab = o.no_tab)
		res.clicked = c.clicked
		res.removed = o.removable && removal_key(gtx, p.id, c)
	}
	if shows_remove {
		rt := Remove_Target {
			tag       = strings.concatenate({"Remove ", o.text}, gtx.allocator),
			id        = ui.id_mix(p.id, 1),
			rect      = {w - mt.height, y, mt.height, mt.height},
			x         = mt.x,
			ink       = look.text,
			focusable = !two,
			keys      = !o.interactive,
		}
		res.removed |= remove_button(gtx, &p, rt, state)
	}
	ui.semantics(gtx, &p, {role = o.interactive ? .Button : .Text, label = name})
	ui.widget_close(gtx, &p, {sz, y + line_baseline(t, mt.height)})
	return
}

// removal_key is whether Backspace or Delete reached the focused token
// this frame (TokenBase.tsx:60-66).
@(private)
removal_key :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, c: Control) -> bool {
	if c.st == nil {
		return false
	}
	for e in ui.events(gtx, id) {
		if e.kind == .Key && (e.key == .Backspace || e.key == .Delete) {
			return true
		}
	}
	return false
}

// Remove_Target is a token's remove button: its area and box, the X's
// size and colour, whether it takes focus and whether Backspace and
// Delete on it remove, and its tag ("Remove <text>", for probes; a reader
// hears "Remove token").
@(private)
Remove_Target :: struct {
	tag:             string,
	id:              ops.Area_Id,
	rect:            ops.Rect,
	x:               f32,
	ink:             ops.Color,
	focusable, keys: bool,
}

// remove_button draws a token's remove target t: a round hit area
// as tall as the token holding an x px X in ink, filled
// --control-transparent-bgColor-hover while hovered or focused and -active
// while pressed, at once (_RemoveTokenButton.module.css:41-48). focusable
// makes it a real button named "Remove token" in the tab order; otherwise
// it takes clicks only. keys lets Backspace and Delete on it remove the
// token too, as TokenBase.tsx:60-66's keydown handler on the token sees
// them from the button inside it. Returns true when it
// removed.
@(private)
remove_button :: proc(gtx: ^ui.Ctx, p: ^ui.Placement, t: Remove_Target, state: Interaction) -> bool {
	id, r := t.id, t.rect
	c := control(gtx, id, r, state)
	rr := ops.Round_Rect{r, r.h / 2}
	fill: tok.Role = .Control_Transparent_Bg_Color_Rest
	switch {
	case c.pressed:
		fill = .Control_Transparent_Bg_Color_Active
	case c.hovered || c.focused:
		fill = .Control_Transparent_Bg_Color_Hover
	}
	if bg := color(fill); ui.painted(bg) && !c.disabled {
		ops.fill(gtx.scene, rr, bg)
	}
	icon(gtx, .X, {r.x + (r.w - t.x) / 2, r.y + (r.h - t.x) / 2}, t.x, t.ink)
	kinds := design.CLICK_KINDS if t.focusable else ops.Event_Kinds{.Press, .Release, .Enter, .Leave, .Move}
	listen(gtx, c.st, id, rr, kinds, .Pointer)
	ops.tag(gtx.scene, id, t.tag)
	if t.focusable {
		paint_focus_outline(gtx, c, rr)
		ui.part_semantics(gtx, p, id, r, {role = .Button, label = "Remove token"})
	}
	return c.clicked || (t.keys && removal_key(gtx, id, c))
}

// Label_Group_Truncation is how a LabelGroup decides what shows: None
// shows every item and wraps; Auto shows the items that fit on one line
// beside the "+N" toggle; Count shows the first count.
Label_Group_Truncation :: enum u8 {
	None,
	Auto,
	Count,
}

// Label_Group_Overflow is how the hidden items are revealed: Overlay
// opens a dialog over the row with every item; Inline unhides them in
// place, wraps the row, and turns the toggle into Show less.
Label_Group_Overflow :: enum u8 {
	Overlay,
	Inline,
}

// LABEL_GROUP_GAP is the gap between items, and between wrapped lines
// (LabelGroup.module.css:1-17).
LABEL_GROUP_GAP :: tok.BASE_SIZE_4

// LABEL_GROUP_ROW is a truncating group's minimum height, the small
// Button's, so the row does not shift when the toggle appears
// (LabelGroup.module.css:27-36).
LABEL_GROUP_ROW :: tok.CONTROL_SMALL_SIZE

// LABEL_GROUP_PAD is the overflow overlay's padding, a JavaScript
// constant in LabelGroup.tsx:135.
LABEL_GROUP_PAD :: tok.BASE_SIZE_8

@(private)
Label_Group_State :: struct {
	expanded: bool, // inline: every item shown
	open:     bool, // overlay: the dialog is up
}

// Label_Group_Items draws a group's items, each one widget (a label,
// token or issue label), in order; it is called once for the row and
// again inside the overlay while that is open.
Label_Group_Items :: proc(gtx: ^ui.Ctx, user: rawptr)

// label_group is Primer's LabelGroup: a row of labels, tokens or issue
// labels 4px apart (primer-kit label-group.json, LabelGroup.tsx,
// LabelGroup.module.css). Untruncated it wraps. Truncated (Auto or
// Count) it is one row at least 28px tall: the items that show, then an
// invisible small "+N" button for the N hidden (spoken "Show +N more").
// Inline, +N unhides them all and wraps the row, the button turning to
// Show less; Overlay, +N opens a dialog over the row, 8px padded, as wide
// as the row up to the button's right edge plus 8px, every item wrapping
// beside an invisible Close button; Close, Escape or a press outside
// closes it.
//
// Auto measures every item and the "+N" for the total count (the widest
// it can read) first, through ui.overflow_row_open, and keeps the longest
// run from the first item that fits with the toggle 4px after it: a
// strict prefix. The web keeps the toggle's box but no gap, and its
// IntersectionObserver lets a later, narrower item fill a gap left by a
// wide one (label-group.json notes); a prefix keeps reading order.
//
// Departures: items are drawn by a callback, so they are not list items
// and focus after +N does not move into the first hidden item: the toggle
// keeps it, becoming Show less. A wrapped line is as tall as its tallest
// item, not 28px. The overlay does not take focus.
label_group :: proc(
	gtx: ^ui.Ctx,
	items: Label_Group_Items,
	user: rawptr,
	truncation := Label_Group_Truncation.None,
	count := 0,
	overflow := Label_Group_Overflow.Overlay,
	key: u64 = 0,
	loc := #caller_location,
) {
	id := ui.claim_id(gtx, key, loc)
	gs := ui.widget_data(gtx, id, Label_Group_State)
	truncating := truncation != .None && !(overflow == .Inline && gs.expanded)
	// One call site and key each for the box, the row and the toggle, in
	// both modes, so the toggle keeps its id, and focus, from +N to Show
	// less and back.
	box := ui.sized_open(gtx, {min = {0, truncation != .None ? LABEL_GROUP_ROW : 0}}, key = u64(ui.id_mix(id, 1)), loc = loc)
	defer ui.close(&box)
	row: ui.Flex
	if truncating {
		row = ui.overflow_row_open(gtx, LABEL_GROUP_GAP, .Center, key = u64(ui.id_mix(id, 2)), loc = loc)
	} else {
		row = ui.wrap_open(gtx, LABEL_GROUP_GAP, LABEL_GROUP_GAP, .Center, key = u64(ui.id_mix(id, 2)), loc = loc)
	}
	defer ui.close(&row)
	ui.container_semantics(gtx, {role = .List}, row.index)
	items(gtx, user)
	total := ui.flex_count(&row)
	hidden := 0
	toggle_w := label_group_toggle_width(gtx, total)
	if truncating {
		switch truncation {
		case .Count:
			hidden = max(total - max(count, 0), 0)
			ui.flex_truncate(&row, count)
		case .Auto:
			hidden = ui.flex_fit(&row, toggle_w)
		case .None:
		}
	}
	if hidden == 0 && truncating {
		gs.open = false
		return
	}
	if !truncating {
		if truncation != .None && label_group_toggle(gtx, "Show less", "", id) {
			gs.expanded = false
		}
		return
	}
	plus := fmt_plus(gtx, hidden)
	if overflow == .Overlay && gs.open {
		kept := ui.flex_count(&row)
		right := ui.flex_extent(&row) + (kept > 0 ? LABEL_GROUP_GAP : 0) + label_group_toggle_width(gtx, hidden)
		label_group_overlay(gtx, id, gs, right, total, items, user)
	}
	heard := strings.concatenate({"Show ", plus, " more"}, gtx.allocator)
	if label_group_toggle(gtx, plus, heard, id) {
		switch overflow {
		case .Inline:
			gs.expanded = true
		case .Overlay:
			gs.open = true
		}
	}
}

// fmt_plus is "+n", in the frame's allocator.
@(private)
fmt_plus :: proc(gtx: ^ui.Ctx, n: int) -> string {
	return fmt.aprintf("+%d", n, allocator = gtx.allocator)
}

// label_group_toggle is the group's +N or Show less: an invisible small
// button, one call site so it keeps one id.
@(private)
label_group_toggle :: proc(gtx: ^ui.Ctx, text, name: string, id: ops.Area_Id) -> bool {
	return button(gtx, text, .Invisible, .Small, name = name, key = u64(ui.id_mix(id, 3)))
}

// label_group_toggle_width is the "+n" button's width: the small
// button's sides around its label.
@(private)
label_group_toggle_width :: proc(gtx: ^ui.Ctx, n: int) -> f32 {
	mt := button_metrics(.Small)
	t := design.shape_style(gtx, fmt_plus(gtx, n), mt.style, font_for(gtx, mt.style.weight))
	return t.width + 2 * mt.pad
}

// Label_Group_Surface is what the overlay's surface paint reports: the
// size it came to, for popup_close.
@(private)
Label_Group_Surface :: struct {
	id:   ops.Area_Id,
	size: ops.Size,
}

// paint_label_group_surface paints the overflow dialog's surface:
// --overlay-bgColor at --borderRadius-large under --shadow-floating-small
// (overlay.json anatomy), and takes the presses on it so the scrim
// beneath does not close it.
@(private)
paint_label_group_surface :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, size: ops.Size, user: rawptr) {
	s := (^Label_Group_Surface)(user)
	s.size = size
	rr := ops.Round_Rect{{0, 0, size.x, size.y}, tok.BORDER_RADIUS_LARGE}
	paint_shadow(gtx, rr, tok.SHADOW_FLOATING_SMALL)
	ops.fill(gtx.scene, rr, color(.Overlay_Bg_Color))
	ops.input_area(gtx.scene, ui.id_mix(s.id, 5), rr, {.Press, .Release, .Move, .Enter, .Leave, .Scroll})
}

// label_group_overlay is the overflow dialog, anchored inside the row's
// right at the toggle (side inside-right, offset -8px on both axes): its
// top-left 8px above the row's start and right edge 8px past the toggle's
// (LabelGroup.tsx:76-107), every item wrapping beside an invisible Close
// button. Close, Escape or a press outside closes it.
@(private)
label_group_overlay :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, gs: ^Label_Group_State, right: f32, total: int, items: Label_Group_Items, user: rawptr) {
	scrim := ui.id_mix(id, 4)
	for e in ui.events(gtx, scrim) {
		if e.kind == .Press || (e.kind == .Key && e.key == .Escape) {
			gs.open = false
		}
	}
	w := right + LABEL_GROUP_PAD
	ov := ui.popup_open(gtx, {0, -LABEL_GROUP_PAD, w, 0}, id, .Below, .Start, 0, {min = {w, 0}, max = {w, ui.INF}})
	label := fmt.aprintf("All %d labels", total, allocator = gtx.allocator)
	ui.overlay_semantics(gtx, &ov, {role = .Dialog, label = label, states = {.Modal}}, key = u64(ui.id_mix(id, 6)))
	ui.key_interest(gtx, scrim, .Escape)
	ops.input_area(gtx.scene, scrim, ops.Rect{-1e5, -1e5, 2e5, 2e5}, {.Press, .Release, .Move, .Enter, .Leave, .Scroll})
	sf := surface_of(gtx, id)
	sf.id = id
	b := ui.box_open(gtx, {padding = ui.pad_all(LABEL_GROUP_PAD), paint = paint_label_group_surface, user = sf}, key = u64(ui.id_mix(id, 7)))
	r := ui.row_open(gtx, gap = LABEL_GROUP_GAP, align = .Start)
	close_w := button_metrics(.Medium).height
	room := ui.sized_open(gtx, {min = {w - 2 * LABEL_GROUP_PAD - LABEL_GROUP_GAP - close_w, 0}, max = {w - 2 * LABEL_GROUP_PAD - LABEL_GROUP_GAP - close_w, 0}})
	inner := ui.wrap_open(gtx, LABEL_GROUP_GAP, LABEL_GROUP_GAP, .Center)
	items(gtx, user)
	ui.close(&inner)
	ui.close(&room)
	if icon_button(gtx, .X, "Close", .Invisible) {
		gs.open = false
	}
	ui.close(&r)
	ui.close(&b)
	if !gs.open {
		ov.discard = true
	}
	ui.popup_close(&ov, sf.size)
}

// surface_of is the overlay surface's retained report for group id.
@(private)
surface_of :: proc(gtx: ^ui.Ctx, id: ops.Area_Id) -> ^Label_Group_Surface {
	return ui.widget_data(gtx, ui.id_mix(id, 8), Label_Group_Surface)
}

