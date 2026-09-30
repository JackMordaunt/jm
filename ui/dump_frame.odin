package ui

import "core:fmt"
import "core:strings"
import "jm:ui/ops"

// dump_frame is the canonical text form of a Frame, ops.dump's twin: one
// draw or hit per line, in device terms.

// dump_frame renders f in four sections, draws, clips, hits and tags, one
// entry per line indented under its section. Transforms print in brackets;
// a missing clip prints as clip=none.
dump_frame :: proc(f: ^Frame, allocator := context.allocator) -> string {
	sb := strings.builder_make(allocator)
	strings.write_string(&sb, "draws\n")
	for d, i in f.draws {
		fmt.sbprintf(&sb, "  draw %d clip=", i)
		write_clip_id(&sb, d.clip)
		strings.write_string(&sb, " [")
		ops.write_affine(&sb, d.transform)
		strings.write_string(&sb, "] ")
		switch v in d.cmd {
		case ops.Fill:
			ops.write_draw(&sb, f.scene, v)
		case ops.Stroke:
			ops.write_draw(&sb, f.scene, v)
		case ops.Glyphs:
			ops.write_draw(&sb, f.scene, v)
		case ops.Image:
			ops.write_draw(&sb, f.scene, v)
		case ops.Shadow:
			ops.write_draw(&sb, f.scene, v)
		}
		strings.write_byte(&sb, '\n')
	}
	strings.write_string(&sb, "clips\n")
	for c, i in f.clips {
		fmt.sbprintf(&sb, "  clip %d parent=", i)
		write_clip_id(&sb, c.parent)
		strings.write_string(&sb, " [")
		ops.write_affine(&sb, c.transform)
		strings.write_string(&sb, "] ")
		ops.write_shape(&sb, c.shape)
		strings.write_byte(&sb, '\n')
	}
	strings.write_string(&sb, "hits\n")
	for h, i in f.hits {
		fmt.sbprintf(&sb, "  hit %d area=%d order=%d clip=", i, h.area, h.order)
		write_clip_id(&sb, h.clip)
		strings.write_string(&sb, " [")
		ops.write_affine(&sb, h.transform)
		strings.write_string(&sb, "] ")
		ops.write_shape(&sb, h.shape)
		strings.write_string(&sb, " kinds=")
		ops.write_kinds(&sb, h.kinds)
		strings.write_byte(&sb, '\n')
	}
	strings.write_string(&sb, "tags\n")
	for t in f.tags {
		strings.write_string(&sb, "  ")
		ops.write_tag(&sb, t)
		strings.write_byte(&sb, '\n')
	}
	return strings.to_string(sb)
}


// write_draw prints the four drawing sc, shared by dump and dump_frame.
// sc may be nil or lack the run a Glyphs names; the run fields then print ?.

// write_clip_id prints a clip reference, none for NO_CLIP.
write_clip_id :: proc(sb: ^strings.Builder, c: Clip_Id) {
	if c == NO_CLIP {
		strings.write_string(sb, "none")
	} else {
		fmt.sbprintf(sb, "%d", c)
	}
}
