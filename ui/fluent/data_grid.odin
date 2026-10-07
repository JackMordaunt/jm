package fluent

import "jm:ui"
import "jm:ui/datagrid"
import tok "jm:ui/fluent/tokens"
import "jm:ui/ops"

// DataGrid on jm:ui/datagrid: Fluent's data-driven table, which Fluent
// builds on its Table primitives, here the datagrid core in the Table's
// look (useTableCellStyles, useTableRowStyles, useTableHeaderCellStyles):
// its row heights, Body1 text in Foreground 1, rows ruled in Stroke 2,
// Subtle's hover and the selection's appearance, and a header that shows
// its sort with an arrow. The core does the rest: virtual rows, sorting,
// selection, the keyboard, copying.
//
//	g: datagrid.Grid
//	datagrid.grid_init(&g, COLUMNS)
//	skin := fluent.data_grid_skin(gtx, &g)
//	skin.cell, skin.cell_user = draw_file_cell, &files // to draw cells of its own
//	ev := datagrid.grid(gtx, &g, COLUMNS, source, &skin, "Files")
//
// The Table primitives (table_open, table_row_open and the cells) stay
// the component for a table the caller composes row by row; this is for
// one the grid lays out from a source.

// data_grid_skin is a Fluent skin for g this frame: the density's row
// height (Normal is Table's Medium, 44px; Condensed its Small, 34px;
// Spacious keeps 44px, Fluent having nothing taller), the theme's
// colours, and selected rows in appearance's tint.
data_grid_skin :: proc(
	gtx: ^ui.Ctx,
	g: ^datagrid.Grid,
	appearance := Table_Selection.Neutral,
) -> (
	s: datagrid.Skin,
) {
	st := &s.style
	st.font = font_for(gtx, tok.FONT_WEIGHT_REGULAR)
	st.header_font = st.font
	st.text_size = style(.Body1).size
	st.row_height = {
		.Normal    = TABLE_CELL_HEIGHT[.Medium],
		.Condensed = TABLE_CELL_HEIGHT[.Small],
		.Spacious  = TABLE_CELL_HEIGHT[.Medium],
	}
	st.header_height = TABLE_CELL_HEIGHT[.Medium]
	st.pad = tok.SPACING_HORIZONTAL_S
	st.header_extra = 16 + tok.SPACING_HORIZONTAL_XS
	st.bg = color(.Neutral_Background1)
	st.fg = color(.Neutral_Foreground1)
	st.muted = color(.Neutral_Foreground3)
	st.header_bg = color(.Neutral_Background1)
	st.header_fg = color(.Neutral_Foreground1)
	st.border = color(.Neutral_Stroke2)
	st.rule = color(.Neutral_Stroke2)
	st.hover = color(.Subtle_Background_Hover)
	st.selected = color(
		.Brand_Background2 if appearance == .Brand else .Subtle_Background_Selected,
	)
	st.cursor = color(.Stroke_Focus2)
	st.focus = color(.Stroke_Focus2)
	st.skeleton = color(.Neutral_Stencil1)
	st.error_fg = color(.Status_Danger_Foreground1)
	st.pin_shadow = ops.with_alpha(color(.Neutral_Stroke1), 0.6)
	st.handle = color(.Brand_Stroke1)
	st.active = color(.Brand_Foreground1)
	s.user = g
	s.header = data_grid_header
	return
}

// data_grid_header is a header's label at fontWeightRegular in
// Foreground 1, and while sorted the Arrow_Up or Arrow_Down icon after it,
// spacingHorizontalXS away (useTableHeaderCellStyles.styles.ts:35-92).
@(private)
data_grid_header :: proc(gtx: ^ui.Ctx, h: ^datagrid.Header, user: rawptr) {
	g := (^datagrid.Grid)(user)
	icon_px: f32 = 16
	right := h.size.x - tok.SPACING_HORIZONTAL_S
	fg := color(.Neutral_Foreground1)
	if h.rank >= 0 {
		right -= icon_px
		ic := Icon.Arrow_Down if h.desc else Icon.Arrow_Up
		icon(gtx, ic, {right, (h.size.y - icon_px) / 2}, icon_px, fg)
		right -= tok.SPACING_HORIZONTAL_XS
	}
	left := tok.SPACING_HORIZONTAL_S
	box := ops.Rect{left, 0, max(right - left, 0), h.size.y}
	datagrid.draw_text_line(
		gtx,
		g,
		font_for(gtx, tok.FONT_WEIGHT_REGULAR),
		style(.Body1).size,
		h.column.title,
		box,
		h.column.align,
		fg,
	)
}
