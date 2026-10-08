package ui

import "jm:ui/ops"

// EMBED_CLIP_DEPTH bounds how deep a frame's clips may nest for
// embed_frame: deeper clips past it are left out, and the draw shows
// less clipped than it was.
EMBED_CLIP_DEPTH :: 64

// embed_frame draws what frame shows into gtx's scene, under the
// transform and clip current there: its draws, each with its transform,
// clips and fade, and nothing else. Its input areas, semantics, key
// interests and focus scopes stay out, so the picture takes no input
// and claims no keys: a recorded frame shown inside a tool's window, as
// the replay scrubber does. frame is laid out already, so its deferred
// layers sit where flatten placed them and its stickies where they stuck.
//
// The draws' paths, glyph runs and gradient stops are not copied: the
// scene frame was flattened from must outlive gtx's frame, until it is
// rendered. Fonts and images are matched to gtx's scene by path, and
// added there when it lacks one.
embed_frame :: proc(gtx: ^Ctx, frame: ^Frame) {
	if frame.scene == nil {
		return
	}
	scene := gtx.scene
	current := NO_CLIP
	pushed := 0 // clips pushed for current
	for draw in frame.draws {
		if draw.clip != current {
			for _ in 0 ..< pushed {
				ops.clip_pop(scene)
			}
			current = draw.clip
			pushed = embed_clips(scene, frame, current)
		}
		if draw.fade != 0 {
			ops.opacity_push(scene, 1 - draw.fade)
		}
		ops.transform_push(scene, draw.transform)
		switch cmd in draw.cmd {
		case ops.Fill:
			ops.fill(scene, embed_shape(scene, frame.scene, cmd.shape), embed_paint(scene, frame.scene, cmd.paint))
		case ops.Stroke:
			ops.stroke(scene, embed_shape(scene, frame.scene, cmd.shape), embed_paint(scene, frame.scene, cmd.paint), cmd.style)
		case ops.Glyphs:
			if int(cmd.run) < len(frame.scene.runs) {
				run := frame.scene.runs[cmd.run]
				run.font = embed_font(scene, frame.scene, run.font)
				ops.glyphs(scene, ops.add_run(scene, run), cmd.origin, cmd.color)
			}
		case ops.Image:
			ops.image(scene, embed_image(scene, frame.scene, cmd.id), cmd.dst, cmd.src, cmd.alpha)
		case ops.Shadow:
			ops.shadow(scene, cmd.rect, cmd.radius, cmd.blur, cmd.color)
		}
		ops.transform_pop(scene)
		if draw.fade != 0 {
			ops.opacity_pop(scene)
		}
	}
	for _ in 0 ..< pushed {
		ops.clip_pop(scene)
	}
}

// embed_clips pushes clip and the clips it sits in, outermost first, each
// under its own transform, and returns how many it pushed.
@(private = "file")
embed_clips :: proc(scene: ^ops.Scene, frame: ^Frame, clip: Clip_Id) -> int {
	chain: [EMBED_CLIP_DEPTH]Clip_Id
	depth := 0
	for at := clip; at != NO_CLIP && int(at) < len(frame.clips) && depth < len(chain); at = frame.clips[at].parent {
		chain[depth] = at
		depth += 1
	}
	for ii := depth - 1; ii >= 0; ii -= 1 {
		outer := frame.clips[chain[ii]]
		ops.transform_push(scene, outer.transform)
		ops.clip_push(scene, embed_shape(scene, frame.scene, outer.shape))
		ops.transform_pop(scene)
	}
	return depth
}

// embed_shape is shape as scene can draw it: a path is added to scene.
@(private = "file")
embed_shape :: proc(scene, from: ^ops.Scene, shape: ops.Shape) -> ops.Shape {
	ref, is_path := shape.(ops.Path_Ref)
	if !is_path {
		return shape
	}
	if int(ref.id) >= len(from.paths) {
		return ops.Rect{}
	}
	return ops.Path_Ref{ops.add_path(scene, from.paths[ref.id])}
}

// embed_paint is paint as scene can draw it: an image paint's image is
// found in or added to scene.
@(private = "file")
embed_paint :: proc(scene, from: ^ops.Scene, paint: ops.Paint) -> ops.Paint {
	image, is_image := paint.(ops.Image_Paint)
	if !is_image {
		return paint
	}
	return ops.Image_Paint{embed_image(scene, from, image.image)}
}

// embed_image is the id scene knows from's image id by: the one with the
// same path, added if scene has none.
@(private = "file")
embed_image :: proc(scene, from: ^ops.Scene, id: ops.Image_Id) -> ops.Image_Id {
	for ref in from.images {
		if ref.id == id {
			return ops.add_image(scene, ref.path)
		}
	}
	return id
}

// embed_font is the id scene knows from's font id by: the same id when
// scene has it at the same file and weight, as a tool showing its own
// application's frames does, else the one add_font gives.
@(private = "file")
embed_font :: proc(scene, from: ^ops.Scene, id: ops.Font_Id) -> ops.Font_Id {
	for ref in from.fonts {
		if ref.id != id {
			continue
		}
		for own in scene.fonts {
			if own.id == id && own.path == ref.path && own.weight == ref.weight {
				return id
			}
		}
		return ops.add_font(scene, ref.path, ref.weight)
	}
	return id
}
