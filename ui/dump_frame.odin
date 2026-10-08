package ui

import "core:fmt"
import "core:strings"
import "jm:ui/ops"

// dump_frame is the canonical text form of a Frame, ops.dump's twin: one
// draw or hit per line, in device terms.

// dump_frame renders f in sections, draws, clips, hits and tags, then
// semantics and keys when the frame has any, one entry per line indented
// under its section. Transforms print in brackets;
// a missing clip prints as clip=none.
dump_frame :: proc(f: ^Frame, allocator := context.allocator) -> string {
	sb := strings.builder_make(allocator)
	write_frame_draws(&sb, f)
	write_frame_clips(&sb, f)
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
		if h.scope != 0 {
			fmt.sbprintf(&sb, " scope=%d", h.scope)
		}
		strings.write_byte(&sb, '\n')
	}
	strings.write_string(&sb, "tags\n")
	for t in f.tags {
		strings.write_string(&sb, "  ")
		ops.write_tag(&sb, t)
		strings.write_byte(&sb, '\n')
	}
	if len(f.nodes) > 0 {
		strings.write_string(&sb, "semantics\n")
		for n in f.nodes {
			fmt.sbprintf(&sb, "  node %d in %d layer=%d ", n.id, n.parent, n.layer)
			ops.write_rect(&sb, n.rect)
			strings.write_byte(&sb, ' ')
			ops.write_semantics(&sb, n.semantics)
			strings.write_byte(&sb, '\n')
		}
	}
	if len(f.keys) > 0 {
		strings.write_string(&sb, "keys\n")
		for k in f.keys {
			fmt.sbprintf(&sb, "  key_interest %d %v", k.area, k.key)
			ops.write_mods(&sb, " mods", k.mods)
			ops.write_mods(&sb, " optional", k.optional)
			if k.topmost {
				strings.write_string(&sb, " topmost")
			}
			strings.write_byte(&sb, '\n')
		}
	}
	if len(f.scopes) > 0 {
		strings.write_string(&sb, "scopes\n")
		for s, i in f.scopes {
			fmt.sbprintf(&sb, "  scope %d id=%d in %d%s\n", i + 1, s.id, s.parent, s.trap ? " trap" : "")
		}
	}
	return strings.to_string(sb)
}


// write_frame_draws writes dump_frame's draws section: what frame paints,
// in order. frame_digest hashes it too.
write_frame_draws :: proc(sb: ^strings.Builder, frame: ^Frame) {
	strings.write_string(sb, "draws\n")
	for draw, ii in frame.draws {
		fmt.sbprintf(sb, "  draw %d clip=", ii)
		write_clip_id(sb, draw.clip)
		strings.write_string(sb, " [")
		ops.write_affine(sb, draw.transform)
		strings.write_string(sb, "] ")
		switch cmd in draw.cmd {
		case ops.Fill:
			ops.write_draw(sb, frame.scene, cmd)
		case ops.Stroke:
			ops.write_draw(sb, frame.scene, cmd)
		case ops.Glyphs:
			ops.write_draw(sb, frame.scene, cmd)
		case ops.Image:
			ops.write_draw(sb, frame.scene, cmd)
		case ops.Shadow:
			ops.write_draw(sb, frame.scene, cmd)
		}
		if draw.fade != 0 {
			fmt.sbprintf(sb, " fade=%v", draw.fade)
		}
		strings.write_byte(sb, '\n')
	}
}

// write_frame_clips writes dump_frame's clips section.
write_frame_clips :: proc(sb: ^strings.Builder, frame: ^Frame) {
	strings.write_string(sb, "clips\n")
	for clip, ii in frame.clips {
		fmt.sbprintf(sb, "  clip %d parent=", ii)
		write_clip_id(sb, clip.parent)
		strings.write_string(sb, " [")
		ops.write_affine(sb, clip.transform)
		strings.write_string(sb, "] ")
		ops.write_shape(sb, clip.shape)
		strings.write_byte(sb, '\n')
	}
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
