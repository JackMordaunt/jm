/*
Package kb binds kb_text_shape, Jimmy Lefevre's OpenType shaper and Unicode
segmenter (https://github.com/JimmyLefevre/kb, zlib licence), vendored at
v2.28d, commit 55036ab, in vendor/. `just kb` compiles it to lib/.

Only what jm:ui/shape calls is bound: the context API, fonts from memory
and font info. Names are kb's own without the kbts_ prefix. Structs are
mirrored only as far as Odin reads them; every size and offset used is
pinned by #assert here and _Static_assert in vendor/kb_text_shape.c, so a
header update that moves one fails to build.
*/
package kb

import "base:runtime"
import "core:c"

when ODIN_OS == .Windows {
	foreign import lib "lib/kb_text_shape.lib"
} else {
	foreign import lib "lib/kb_text_shape.a"
}

Shape_Context :: struct {}

// Font is a parsed font, kbts_font, opaque. A context keeps the pointer
// ShapePushFont is given (kbts_ShapePopFont returns Font->Info.Font, the
// pointer pushed), so a pushed font must not move.
Font :: struct #align (8) {
	_: [72]u8,
}

Direction :: enum c.int {
	Dont_Know = 0,
	LTR       = 1,
	RTL       = 2,
}

// Language is kbts_language; only Dont_Know is named here.
Language :: enum u32 {
	Dont_Know = 0,
}

User_Id_Generation_Mode :: enum c.int {
	Codepoint_Index = 0,
	Source_Index    = 1, // the byte offset of each codepoint in the UTF-8 input
}

Shape_Error :: enum c.int {
	None = 0,
}

Glyph_Iterator :: struct #align (8) {
	_: [32]u8,
}

Run :: struct {
	font:                ^Font,
	script:              u32,
	paragraph_direction: Direction,
	direction:           Direction,
	flags:               u32,
	glyphs:              Glyph_Iterator,
}

// Glyph is the head of kbts_glyph (120 bytes, pinned in
// kb_text_shape.c); kb hands out pointers to them, so only the fields read
// are mirrored.
Glyph :: struct {
	_:                          [16]u8, // Prev, Next
	codepoint:                  rune,
	id:                         u16,
	uid:                        u16,
	user_id_or_codepoint_index: c.int, // a codepoint index, from the context API
	offset_x, offset_y:         i32, // font units, y up
	advance_x, advance_y:       i32,
}

// Break is one of kbts_break_flags: flags on a codepoint describe the
// boundary before it (jm:ui/shape's test_shape_text_directions_and_breaks
// pins this: soft breaks land on the rune after each space).
Break :: enum u32 {
	Direction           = 0, // direction changes; direction holds the new one
	Script              = 1,
	Grapheme            = 2, // a caret may stop here
	Word                = 3,
	Line_Soft           = 4, // a line may wrap here
	Line_Hard           = 5, // a line must end here
	Manual              = 6,
	Paragraph_Direction = 7, // paragraph_direction is set
}
Breaks :: distinct bit_set[Break;u32]

// Shape_Codepoint is kbts_shape_codepoint; user_id is the input's user id,
// a byte offset under Source_Index. direction and paragraph_direction hold
// only where breaks says they changed, as kb_text_shape.h's own comments
// on kbts_shape_codepoint put it ("Only set when (BreakFlags & ...)").
Shape_Codepoint :: struct #align (8) {
	_:                   [24]u8,
	user_id:             c.int,
	breaks:              Breaks,
	script:              u32,
	direction:           Direction,
	paragraph_direction: Direction,
	_:                   [4]u8,
}

// Font_Info2_1 is kbts_font_info2_1; set size to size_of(Font_Info2_1)
// before asking.
Font_Info2_1 :: struct #align (8) {
	size:          u32,
	_:             [148]u8,
	units_per_em:  u16,
	_:             [14]u8,
}

Allocator_Op_Kind :: enum c.int {
	None     = 0,
	Allocate = 1,
	Free     = 2,
}

Allocator_Op :: struct {
	kind:    Allocator_Op_Kind,
	pointer: rawptr, // allocated, or to free
	size:    u32, // asked, then given
}

Allocator_Function :: #type proc "c" (data: rawptr, op: ^Allocator_Op)

#assert(size_of(Font) == 72)
#assert(size_of(Glyph_Iterator) == 32)
#assert(size_of(Run) == 56)
#assert(offset_of(Run, direction) == 16)
#assert(offset_of(Run, glyphs) == 24)
#assert(offset_of(Glyph, id) == 20)
#assert(offset_of(Glyph, user_id_or_codepoint_index) == 24)
#assert(offset_of(Glyph, offset_x) == 28)
#assert(offset_of(Glyph, advance_y) == 40)
#assert(size_of(Shape_Codepoint) == 48)
#assert(offset_of(Shape_Codepoint, user_id) == 24)
#assert(offset_of(Shape_Codepoint, breaks) == 28)
#assert(offset_of(Shape_Codepoint, direction) == 36)
#assert(offset_of(Shape_Codepoint, paragraph_direction) == 40)
#assert(size_of(Font_Info2_1) == 168)
#assert(offset_of(Font_Info2_1, units_per_em) == 152)
#assert(size_of(Allocator_Op) == 24)
#assert(offset_of(Allocator_Op, size) == 16)

@(default_calling_convention = "c", link_prefix = "kbts_")
foreign lib {
	CreateShapeContext :: proc(allocator: Allocator_Function, data: rawptr) -> ^Shape_Context ---
	DestroyShapeContext :: proc(ctx: ^Shape_Context) ---
	ShapePushFont :: proc(ctx: ^Shape_Context, font: ^Font) -> ^Font ---
	ShapePopFont :: proc(ctx: ^Shape_Context) -> ^Font ---
	ShapeBegin :: proc(ctx: ^Shape_Context, paragraph: Direction, language: Language) ---
	ShapeEnd :: proc(ctx: ^Shape_Context) ---
	ShapeError :: proc(ctx: ^Shape_Context) -> Shape_Error ---
	ShapeRun :: proc(ctx: ^Shape_Context, run: ^Run) -> b32 ---
	ShapeGetShapeCodepoint :: proc(ctx: ^Shape_Context, index: c.int, out: ^Shape_Codepoint) -> b32 ---
	GlyphIteratorNext :: proc(it: ^Glyph_Iterator, glyph: ^^Glyph) -> b32 ---
	FreeFont :: proc(font: ^Font) ---
	FontIsValid :: proc(font: ^Font) -> b32 ---
	GetFontInfo2 :: proc(font: ^Font, info: ^Font_Info2_1) ---

	@(link_name = "kbts_ShapeUtf8")
	_shape_utf8 :: proc(ctx: ^Shape_Context, text: [^]u8, length: c.int, mode: User_Id_Generation_Mode) ---
	@(link_name = "kbts_FontFromMemory")
	_font_from_memory :: proc(data: rawptr, size: c.int, index: c.int, allocator: Allocator_Function, allocator_data: rawptr) -> Font ---
}

ShapeUtf8 :: proc(ctx: ^Shape_Context, text: string, mode: User_Id_Generation_Mode) {
	_shape_utf8(ctx, raw_data(text), c.int(len(text)), mode)
}

// FontFromMemory parses font index of data; data must outlive the font.
FontFromMemory :: proc(data: []byte, index: int, allocator: Allocator_Function, allocator_data: rawptr) -> Font {
	return _font_from_memory(raw_data(data), c.int(len(data)), c.int(index), allocator, allocator_data)
}

// allocator hands kb an Odin allocator, through runtime.mem_alloc at
// DEFAULT_ALIGNMENT. a must outlive every use.
allocator :: proc(a: ^runtime.Allocator) -> (Allocator_Function, rawptr) {
	return serve_allocator_op, a
}

@(private)
serve_allocator_op :: proc "c" (data: rawptr, op: ^Allocator_Op) {
	context = runtime.default_context()
	a := (^runtime.Allocator)(data)^
	#partial switch op.kind {
	case .Allocate:
		mem, _ := runtime.mem_alloc(int(op.size), runtime.DEFAULT_ALIGNMENT, a)
		op.pointer = raw_data(mem)
		op.size = u32(len(mem))
	case .Free:
		_ = runtime.mem_free(op.pointer, a)
	}
}
