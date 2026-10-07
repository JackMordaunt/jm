package datagrid

import "jm:ui"
import "jm:ui/ops"

// Density is how much room a row takes.
Density :: enum u8 {
	Normal,
	Condensed,
	Spacious,
}

// Style is a grid's look, which a design system's skin fills from its
// tokens: the fonts, the row heights per density, the cell padding and
// every colour the grid paints. A zero colour paints nothing; a zero
// font is the toolkit's.
Style :: struct {
	font:          ops.Font_Id,
	header_font:   ops.Font_Id,
	text_size:     f32,
	header_size:   f32, // 0 is text_size
	row_height:    [Density]f32,
	header_height: f32,
	group_height:  f32, // a group header's row; 0 is the row height
	pad:           f32, // a cell's inline padding
	header_extra:  f32, // what a header's controls take beside its title: sort mark, filter button
	radius:        f32, // the outer corners
	bg:            ops.Color,
	fg:            ops.Color,
	muted:         ops.Color, // a group's count, an empty grid's message
	header_bg:     ops.Color,
	header_fg:     ops.Color,
	border:        ops.Color, // the outline
	rule:          ops.Color, // between rows
	column_rule:   ops.Color, // between columns
	zebra:         ops.Color, // every other row
	hover:         ops.Color,
	selected:      ops.Color,
	selected_fg:   ops.Color, // 0 keeps fg
	cursor:        ops.Color, // the focused cell's outline
	focus:         ops.Color, // the grid's outline while it has focus
	skeleton:      ops.Color,
	error_fg:      ops.Color,
	group_bg:      ops.Color,
	group_fg:      ops.Color,
	pin_shadow:    ops.Color, // the edge of a pinned group over scrolled columns
	handle:        ops.Color, // a resize handle under the pointer, a drop marker
	active:        ops.Color, // a header's sort and filter marks when on
	stale_alpha:   f32, // how opaque a stale row's text is; 0 reads as 0.5
}

// DEFAULT_STYLE is a plain look in greys and blue, for a grid with no
// design system: tests, and a skin that changes only a few fields.
DEFAULT_STYLE :: Style {
	text_size = 12,
	row_height = {.Normal = 33, .Condensed = 25, .Spacious = 41},
	header_height = 36,
	pad = 8,
	header_extra = 28,
	bg = {255, 255, 255, 255},
	fg = {31, 35, 40, 255},
	muted = {101, 109, 118, 255},
	header_bg = {246, 248, 250, 255},
	header_fg = {31, 35, 40, 255},
	border = {209, 217, 224, 255},
	rule = {209, 217, 224, 255},
	hover = {129, 139, 152, 26},
	selected = {9, 105, 218, 36},
	cursor = {9, 105, 218, 255},
	focus = {9, 105, 218, 255},
	skeleton = {129, 139, 152, 46},
	error_fg = {209, 36, 47, 255},
	group_bg = {246, 248, 250, 255},
	group_fg = {31, 35, 40, 255},
	pin_shadow = {31, 35, 40, 40},
	handle = {9, 105, 218, 255},
	active = {9, 105, 218, 255},
}

// Cell is one cell as a skin's cell slot sees it: the grid, the column
// and its index, the row (a client row's index, -1 for a paged one) and
// its place in the current order (item), its key, its text, its box in
// its own space, what its row shows, and how it is lit. fg is the text
// colour the grid would use.
Cell :: struct {
	grid:     ^Grid,
	col:      int,
	column:   ^Column,
	row:      int,
	item:     int,
	key:      Row_Key,
	text:     string,
	size:     ops.Size,
	state:    Row_State,
	selected: bool,
	hovered:  bool,
	cursor:   bool,
	fg:       ops.Color,
}

// Header is a header cell as a skin's header slot sees it: the column,
// its box, its sort (rank in the sort, -1 unsorted, and direction),
// whether it is filtered, hovered or the keyboard's, and key, a base to
// key the skin's own widgets in it (a filter button) so each header's
// are its own.
Header :: struct {
	grid:     ^Grid,
	col:      int,
	column:   ^Column,
	size:     ops.Size,
	rank:     int,
	desc:     bool,
	filtered: bool,
	hovered:  bool,
	cursor:   bool,
	key:      u64,
}

// Group_Row is a group header as a skin's group slot sees it.
Group_Row :: struct {
	grid:      ^Grid,
	text:      string,
	count:     int,
	collapsed: bool,
	size:      ops.Size,
	cursor:    bool,
}

// Skin is how a design system dresses a grid: its style, and slots for
// what it draws itself, each called inside the part's box with the
// toolkit's widgets at hand. A nil slot, or a cell slot that returns
// false, leaves the part to the grid's own drawing from the style. The
// header slot draws a header's content over the grid's sort and drag
// handling, so a widget it draws there (a filter button that opens a
// popover) takes its own presses. empty draws in the body of a grid with
// no rows; failed on a row whose page could not be had.
//
// The cell slot is called with cell_user rather than user: it is the
// application's, drawing its own cells (a badge, a button that takes its
// own presses and leaves the row's selection alone), so a design system
// that sets the other slots and user every frame leaves it as the caller
// set it.
Skin :: struct {
	style:     Style,
	user:      rawptr,
	cell:      proc(gtx: ^ui.Ctx, c: ^Cell, user: rawptr) -> bool,
	cell_user: rawptr,
	header:    proc(gtx: ^ui.Ctx, h: ^Header, user: rawptr),
	group:     proc(gtx: ^ui.Ctx, g: ^Group_Row, user: rawptr) -> bool,
	empty:     proc(gtx: ^ui.Ctx, size: ops.Size, user: rawptr),
	failed:    proc(gtx: ^ui.Ctx, size: ops.Size, error: string, user: rawptr) -> bool,
}

// row_height is a row's height at density d, 33px where the style
// leaves it 0.
row_height :: proc(s: ^Style, d: Density) -> f32 {
	h := s.row_height[d]
	return h > 0 ? h : 33
}

// group_height is a group header's height.
group_height :: proc(s: ^Style, d: Density) -> f32 {
	return s.group_height > 0 ? s.group_height : row_height(s, d)
}

// scale_alpha scales c's alpha by a, where ops.with_alpha sets it: a
// stale row dims whatever colour its text had.
@(private)
scale_alpha :: proc(c: ops.Color, a: f32) -> ops.Color {
	out := c
	out.a = u8(f32(c.a) * clamp(a, 0, 1))
	return out
}
