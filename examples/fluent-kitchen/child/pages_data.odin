package main

import "core:fmt"
import "jm:ui"
import "jm:ui/fluent"
import "jm:ui/ops"

// The data display pages: table, list, tag, persona, avatar group,
// skeleton, text and image, on the fluent-kit's table.json, list.json,
// tag.json, persona.json, avatar-group.json, skeleton.json, text.json
// and image.json.

DATA_FILES := [?]string{"Meeting notes", "Thursday plan", "Budget review", "Launch checklist"}
DATA_OWNERS := [?]string{"Katri Ahokas", "Elvia Atkins", "Cameron Evans", "Wanda Howard"}
DATA_WHEN := [?]string{"7h ago", "Yesterday", "Tue", "Last week"}
DATA_PEOPLE := [?]string{"Katri Ahokas", "Elvia Atkins", "Cameron Evans", "Wanda Howard", "Mona Kane", "Allan Munger", "Erik Nason", "Daisy Phillips"}
TAG_APPEARANCES := [?]fluent.Tag_Appearance{.Filled, .Outline, .Brand}
TAG_APPEARANCE_NAMES := [?]string{"Filled", "Outline", "Brand"}

page_table :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	section(gtx, "Sortable, selectable", "44px rows on the surface below; hover and press read Subtle, a selected row Brand Background 2; the Name header sorts")
	COLS := [?]f32{0, 200, 120}
	sizes := [?]fluent.Table_Size{.Medium, .Small, .Extra_Small}
	for size, si in sizes {
		if si > 0 {
			section(gtx, si == 1 ? "Small" : "Extra small", si == 1 ? "34px rows" : "24px rows in caption1, no row border")
		}
		// Each table is its own scope: its rows' ids, and the flex
		// memory they keep, must not collide with the other tables'.
		sc := ui.scope_open(gtx, si)
		t := fluent.table_open(gtx, COLS[:], size, key = u64(si))
		{
			h := fluent.table_header_open(gtx, &t)
			all := m.table_rows[0] && m.table_rows[1] && m.table_rows[2] && m.table_rows[3]
			some := !all && (m.table_rows[0] || m.table_rows[1] || m.table_rows[2] || m.table_rows[3])
			if fluent.table_selection_cell(gtx, &h, &all, mixed = some) {
				for &r in m.table_rows {
					r = all
				}
			}
			fluent.table_header_cell(gtx, &h, "Name", &m.table_sort)
			fluent.table_header_cell(gtx, &h, "Owner")
			fluent.table_header_cell(gtx, &h, "Modified")
			fluent.table_header_close(&h)
		}
		for i in 0 ..< len(DATA_FILES) {
			idx := m.table_sort == .Descending ? len(DATA_FILES) - 1 - i : i
			r := fluent.table_row_open(gtx, &t, &m.table_rows[idx], appearance = si == 1 ? .Neutral : .Brand, name = DATA_FILES[idx], key = u64(i))
			fluent.table_selection_cell(gtx, &r, &m.table_rows[idx])
			fluent.table_cell_layout(gtx, &r, DATA_FILES[idx], size == .Medium ? "Word document" : "", {icon = .Document}, primary = idx == 0)
			fluent.table_cell_layout(gtx, &r, DATA_OWNERS[idx], "", {name = DATA_OWNERS[idx]})
			fluent.table_cell(gtx, &r, DATA_WHEN[idx])
			fluent.table_row_close(&r)
		}
		fluent.table_close(&t)
		ui.close(&sc)
	}
	section(gtx, "Row states", "forced: hovered, pressed, focused and a selected brand row")
	t := fluent.table_open(gtx, COLS[:], key = 10)
	defer fluent.table_close(&t)
	on := true
	for st, i in fluent.STATES {
		r := fluent.table_row_open(gtx, &t, i == 4 ? &on : nil, state = i == 4 ? .Enabled : st, key = u64(20 + i))
		fluent.table_cell(gtx, &r, i == 4 ? "Selected" : STATE_NAMES[i])
		fluent.table_cell(gtx, &r, "Owner")
		fluent.table_cell(gtx, &r, "Today")
		fluent.table_row_close(&r)
	}
}

page_list :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	section(gtx, "Single selection", "each item carries a checkbox with a 4px indicator margin; the row look is the design site's 32px Subtle row")
	{
		c := ui.column_open(gtx, align = .Fill, key = 1)
		defer ui.close(&c)
		ui.spacer(gtx, 0)
		l := fluent.list_open(gtx, .Single, &m.list_single)
		for f, i in DATA_FILES {
			fluent.list_item(gtx, &l, f, key = u64(i))
		}
		fluent.list_close(&l)
	}
	section(gtx, "Multiple selection", "click, Space or Enter toggles")
	l := fluent.list_open(gtx, .Multi, key = 2)
	for p, i in DATA_PEOPLE[:4] {
		fluent.list_item(gtx, &l, p, &m.list_multi[i], .Person, key = u64(10 + i))
	}
	fluent.list_close(&l)
	section(gtx, "Navigable", fmt.tprintf("no selection; items act on click: %d", m.list_actions))
	n := fluent.list_open(gtx, key = 3)
	for f, i in DATA_FILES[:3] {
		if fluent.list_item(gtx, &n, f, ic = .Folder, key = u64(20 + i)) {
			m.list_actions += 1
		}
	}
	fluent.list_close(&n)
}

page_tag :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	section(gtx, "Appearances", "the root never reacts to hover; only a dismissible tag's icon does")
	for n, i in TAG_APPEARANCE_NAMES {
		r, w := variant_row_open(gtx, n, u64(i))
		a := TAG_APPEARANCES[i]
		fluent.tag(gtx, "Primary", a, key = 1)
		fluent.tag(gtx, "With icon", a, .Calendar, key = 2)
		fluent.tag(gtx, "Katri Ahokas", a, media = "Katri Ahokas", key = 3)
		fluent.tag(gtx, "Two lines", a, secondary = "Secondary text", key = 4)
		fluent.tag(gtx, "Dismiss", a, dismissible = true, key = 5)
		fluent.tag(gtx, "Circular", a, shape = .Circular, dismissible = true, key = 6)
		fluent.tag(gtx, "Selected", a, selected = true, key = 7)
		fluent.tag(gtx, "Disabled", a, dismissible = true, state = .Disabled, key = 8)
		variant_row_close(&r, &w)
	}
	section(gtx, "Sizes", "32 / 24 / 20px; extra-small grows its hit area to 24px")
	{
		r, w := variant_row_open(gtx, "Sizes", 20)
		for size, i in ([3]fluent.Tag_Size{.Medium, .Small, .Extra_Small}) {
			fluent.tag(gtx, "Tag", .Filled, .Calendar, size = size, dismissible = true, key = u64(i))
		}
		variant_row_close(&r, &w)
	}
	section(gtx, "Interaction tags", "a primary action and a secondary dismiss, joined by the divider")
	state_header(gtx, 150)
	for n, i in TAG_APPEARANCE_NAMES {
		cell :: proc(gtx: ^ui.Ctx, m: ^Model, st: fluent.Interaction, key: u64) {
			fluent.interaction_tag(gtx, "Primary", TAG_APPEARANCES[key / 16 - 30], .Calendar, state = st, key = key)
		}
		state_row(gtx, m, n, cell, u64(30 + i), 150)
	}
	section(gtx, "Live group", "dismiss removes a tag; the gap follows the size")
	tg := fluent.tag_group_open(gtx)
	defer ui.close(&tg)
	for p, i in DATA_PEOPLE[:5] {
		if m.tags_removed[i] {
			continue
		}
		if _, d := fluent.interaction_tag(gtx, p, .Outline, media = p, key = u64(40 + i)); d {
			m.tags_removed[i] = true
		}
	}
	if fluent.button(gtx, "Reset", size = .Small, key = 50) {
		m.tags_removed = {}
	}
}

page_persona :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	SIZES := [?]fluent.Persona_Size{.Extra_Small, .Small, .Medium, .Large, .Extra_Large, .Huge}
	SIZE_NAMES := [?]string{"Extra small", "Small", "Medium", "Large", "Extra large", "Huge"}
	section(gtx, "Sizes", "avatar 20 / 28 / 32 / 36 / 40 / 56px; the name is subtitle2 at extra-large and huge")
	for n, i in SIZE_NAMES {
		r, w := variant_row_open(gtx, n, u64(i))
		fluent.persona(gtx, "Katri Ahokas", "Available", "Designer", size = SIZES[i], key = 1)
		fluent.persona(gtx, "Elvia Atkins", "Busy", size = SIZES[i], presence_only = true, status = .Busy, key = 2)
		variant_row_close(&r, &w)
	}
	section(gtx, "Text position", "after, before or below the media")
	r, w := variant_row_open(gtx, "Position", 10)
	defer variant_row_close(&r, &w)
	for pos, i in ([3]fluent.Text_Position{.After, .Before, .Below}) {
		fluent.persona(gtx, "Cameron Evans", "Software engineer", "Redmond", "Building 4", size = .Large, position = pos, key = u64(i))
	}
}

page_avatar_group :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	LAYOUTS := [?]fluent.Group_Layout{.Spread, .Stack, .Pie}
	LAYOUT_NAMES := [?]string{"Spread", "Stack", "Pie"}
	section(gtx, "Layouts", "spread sets items apart, stack overlaps them in Background 2 rings, pie cuts up to three into one circle; the rest go behind the overflow button")
	for n, i in LAYOUT_NAMES {
		r, w := variant_row_open(gtx, n, u64(i))
		for size, j in ([3]fluent.Avatar_Size{.S24, .S32, .S48}) {
			fluent.avatar_group(gtx, DATA_PEOPLE[:], size, LAYOUTS[i], max_inline = 3, open = &m.groups_open[i * 3 + j], key = u64(i * 3 + j))
		}
		variant_row_close(&r, &w)
	}
}

page_skeleton :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	section(gtx, "Wave", "Stencil 1 with a Stencil 2 band sliding across over 3s on ease-in-out")
	card :: proc(gtx: ^ui.Ctx, anim: fluent.Skeleton_Animation, translucent: bool, key: u64) {
		r := ui.row_open(gtx, gap = 12, key = key)
		defer ui.close(&r)
		fluent.skeleton_item(gtx, 48, .Circle, animation = anim, translucent = translucent)
		c := ui.column_open(gtx, gap = 8)
		defer ui.close(&c)
		fluent.skeleton_item(gtx, 16, width = 280, animation = anim, translucent = translucent, key = 1)
		fluent.skeleton_item(gtx, 12, width = 200, animation = anim, translucent = translucent, key = 2)
		fluent.skeleton_item(gtx, 12, width = 240, animation = anim, translucent = translucent, key = 3)
	}
	card(gtx, .Wave, false, 1)
	section(gtx, "Pulse", "the opacity runs 1, 0.4, 1 over 1s")
	card(gtx, .Pulse, false, 2)
	section(gtx, "Translucent", "Stencil 1 Alpha, for coloured surfaces")
	card(gtx, .Wave, true, 3)
	section(gtx, "Shapes and sizes", "rectangle, square and circle at 16 / 32 / 48 / 64px")
	r := ui.row_open(gtx, gap = 12, align = .Center, key = 4)
	defer ui.close(&r)
	for size, i in ([4]f32{16, 32, 48, 64}) {
		fluent.skeleton_item(gtx, size, .Square, key = u64(10 + i))
		fluent.skeleton_item(gtx, size, .Circle, key = u64(20 + i))
	}
}

page_text :: proc(gtx: ^ui.Ctx, m: ^Model) {
	s := fluent.scheme()
	fg := s[.Neutral_Foreground1]
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	section(gtx, "Presets", "the ramp's named styles; Text sets no colour, so the page passes Foreground 1")
	ROLES := [?]fluent.Type_Role{.Caption2, .Caption1, .Caption1_Strong, .Body1, .Body1_Strong, .Body2, .Subtitle2, .Subtitle1, .Title3, .Title2, .Title1, .Large_Title}
	ROLE_NAMES := [?]string{"Caption2", "Caption1", "Caption1Strong", "Body1", "Body1Strong", "Body2", "Subtitle2", "Subtitle1", "Title3", "Title2", "Title1", "LargeTitle"}
	for n, i in ROLE_NAMES {
		fluent.text_preset(gtx, n, ROLES[i], fg, key = u64(i))
	}
	section(gtx, "Decoration", "italic shears the run; underline and strikethrough draw their lines")
	{
		r := ui.row_open(gtx, gap = 16, key = 20)
		defer ui.close(&r)
		fluent.text(gtx, "Italic", fg, .S400, italic = true, key = 1)
		fluent.text(gtx, "Underline", fg, .S400, underline = true, key = 2)
		fluent.text(gtx, "Strikethrough", fg, .S400, strikethrough = true, key = 3)
		fluent.text(gtx, "Both", fg, .S400, .Semibold, underline = true, strikethrough = true, key = 4)
	}
	section(gtx, "Block, wrap and truncate", "a 320px block wraps, centres, or truncates with an ellipsis")
	LONG :: "Fluent text wraps at word boundaries inside its block and truncates with an ellipsis when wrapping is off."
	fluent.text(gtx, LONG, fg, block = true, width = 320, key = 30)
	fluent.text(gtx, LONG, fg, block = true, width = 320, align = .Center, key = 31)
	fluent.text(gtx, LONG, fg, block = true, width = 320, wrap_lines = false, truncate = true, key = 32)
}

page_image :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	section(gtx, "Shapes and frame", "square, rounded and circular; bordered draws Stroke 1, shadow draws shadow4; jm:ui draws no bitmaps, so a painter or a placeholder fills the box")
	r := ui.row_open(gtx, gap = 24, align = .Center, key = 1)
	for shape, i in ([3]fluent.Image_Shape{.Square, .Rounded, .Circular}) {
		fluent.image(gtx, {120, 120}, 120, 120, shape, bordered = i != 0, shadow = i == 2, key = u64(i))
	}
	ui.close(&r)
	section(gtx, "Fit", "a 160x100 source in a 120px box: none, center, contain, cover")
	f := ui.row_open(gtx, gap = 24, align = .Center, key = 2)
	defer ui.close(&f)
	paint :: proc(gtx: ^ui.Ctx, rect: ops.Rect, user: rawptr) {
		s := fluent.scheme()
		ops.fill(gtx.scene, rect, s[.Brand_Background2])
		ops.fill(gtx.scene, ops.Ellipse{{rect.x + rect.w * 0.3, rect.y + rect.h * 0.2, rect.w * 0.4, rect.h * 0.6}}, s[.Brand_Background])
		ops.stroke(gtx.scene, rect, s[.Brand_Stroke1], {width = 2})
	}
	for fit, i in ([4]fluent.Image_Fit{.None, .Center, .Contain, .Cover}) {
		fluent.image(gtx, {160, 100}, 120, 120, .Rounded, fit, bordered = true, paint = paint, key = u64(10 + i))
	}
}
