package game

import "base:runtime"
import "core:fmt"

// check_world names each field of world that is not plain data, as a
// path from the world down ("player.name: string"), empty when there is
// none. A World holds only values: numbers, bools, enums, bit sets, fixed
// arrays, fixed-capacity dynamic arrays ([dynamic; N]T, whose items are
// inline: the place for a game's entities), and structs and unions of
// them. No pointer, slice, dynamic array,
// map, string, procedure, any or typeid, since each of those points
// outside the World: a copy would share it, a file would hold an address,
// and a hot reload would leave it pointing into the old program. Kept to
// values, a snapshot is a copy, a diff walks two copies, and a recording
// can rebuild any tick. A name is a fixed array of bytes and a count.
check_world :: proc(world: typeid, allocator := context.allocator) -> []string {
	problems := make([dynamic]string, allocator)
	check_type(&problems, type_info_of(world), "world", allocator)
	return problems[:]
}

@(private = "file")
check_type :: proc(problems: ^[dynamic]string, info: ^runtime.Type_Info, path: string, allocator: runtime.Allocator) {
	base := runtime.type_info_base(info)
	switch kind in base.variant {
	case runtime.Type_Info_Struct:
		for ii in 0 ..< int(kind.field_count) {
			check_type(problems, kind.types[ii], fmt.tprintf("%s.%s", path, kind.names[ii]), allocator)
		}
	case runtime.Type_Info_Array:
		check_type(problems, kind.elem, fmt.tprintf("%s[]", path), allocator)
	case runtime.Type_Info_Enumerated_Array:
		check_type(problems, kind.elem, fmt.tprintf("%s[]", path), allocator)
	case runtime.Type_Info_Fixed_Capacity_Dynamic_Array:
		check_type(problems, kind.elem, fmt.tprintf("%s[]", path), allocator)
	case runtime.Type_Info_Union:
		for variant in kind.variants {
			check_type(problems, variant, fmt.tprintf("%s.(%v)", path, variant.id), allocator)
		}
	case runtime.Type_Info_Matrix:
		check_type(problems, kind.elem, path, allocator)
	case runtime.Type_Info_Simd_Vector:
		check_type(problems, kind.elem, path, allocator)
	case runtime.Type_Info_Named,
	     runtime.Type_Info_Integer,
	     runtime.Type_Info_Rune,
	     runtime.Type_Info_Float,
	     runtime.Type_Info_Complex,
	     runtime.Type_Info_Quaternion,
	     runtime.Type_Info_Boolean,
	     runtime.Type_Info_Enum,
	     runtime.Type_Info_Bit_Set,
	     runtime.Type_Info_Bit_Field:
	case runtime.Type_Info_String,
	     runtime.Type_Info_Any,
	     runtime.Type_Info_Type_Id,
	     runtime.Type_Info_Pointer,
	     runtime.Type_Info_Multi_Pointer,
	     runtime.Type_Info_Procedure,
	     runtime.Type_Info_Parameters,
	     runtime.Type_Info_Slice,
	     runtime.Type_Info_Dynamic_Array,
	     runtime.Type_Info_Map,
	     runtime.Type_Info_Soa_Pointer:
		append(problems, fmt.aprintf("%s: %v", path, info.id, allocator = allocator))
	}
}
