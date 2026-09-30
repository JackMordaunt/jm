// The one translation unit that compiles kb_text_shape. The asserts pin
// every layout ui/kb/kb.odin mirrors, with the same numbers it #asserts,
// so a header update that moves one fails this build instead of reading
// the wrong bytes.
#define KB_TEXT_SHAPE_IMPLEMENTATION
#include "kb_text_shape.h"

#include <stddef.h>

_Static_assert(sizeof(kbts_font) == 72, "kbts_font");
_Static_assert(sizeof(kbts_glyph_iterator) == 32, "kbts_glyph_iterator");
_Static_assert(sizeof(kbts_run) == 56, "kbts_run");
_Static_assert(offsetof(kbts_run, Direction) == 16, "kbts_run.Direction");
_Static_assert(offsetof(kbts_run, Glyphs) == 24, "kbts_run.Glyphs");
_Static_assert(sizeof(kbts_glyph) == 120, "kbts_glyph");
_Static_assert(offsetof(kbts_glyph, Id) == 20, "kbts_glyph.Id");
_Static_assert(offsetof(kbts_glyph, UserIdOrCodepointIndex) == 24, "kbts_glyph.UserIdOrCodepointIndex");
_Static_assert(offsetof(kbts_glyph, OffsetX) == 28, "kbts_glyph.OffsetX");
_Static_assert(offsetof(kbts_glyph, AdvanceY) == 40, "kbts_glyph.AdvanceY");
_Static_assert(sizeof(kbts_shape_codepoint) == 48, "kbts_shape_codepoint");
_Static_assert(offsetof(kbts_shape_codepoint, UserId) == 24, "kbts_shape_codepoint.UserId");
_Static_assert(sizeof(kbts_font_info2_1) == 168, "kbts_font_info2_1");
_Static_assert(offsetof(kbts_font_info2_1, UnitsPerEm) == 152, "kbts_font_info2_1.UnitsPerEm");
_Static_assert(sizeof(kbts_allocator_op) == 24, "kbts_allocator_op");
_Static_assert(offsetof(kbts_allocator_op, Allocate.Size) == 16, "kbts_allocator_op.Allocate.Size");
_Static_assert(KBTS_DIRECTION_LTR == 1 && KBTS_DIRECTION_RTL == 2, "kbts_direction");
_Static_assert(KBTS_USER_ID_GENERATION_MODE_SOURCE_INDEX == 1, "kbts_user_id_generation_mode");
_Static_assert(KBTS_ALLOCATOR_OP_KIND_ALLOCATE == 1 && KBTS_ALLOCATOR_OP_KIND_FREE == 2, "kbts_allocator_op_kind");
