package material

import "jm:ui/ops"
import "jm:ui/design"
import tok "jm:ui/material/tokens"

// Per-corner geometry is design's; a Material shape token resolves into
// it here.
Corners :: design.Corners
corners_all :: design.corners_all
lerp_corners :: design.lerp_corners
grow_corners :: design.grow_corners
rounded :: design.rounded
arc :: design.arc
KAPPA :: design.KAPPA

// corners resolves shape token sh for a box r: full becomes half the
// shorter side, and the token's [top-start, top-end, bottom-end,
// bottom-start] maps onto left-to-right corners.
corners :: proc(sh: tok.Shape, r: ops.Rect) -> Corners {
	if sh.full {
		return corners_all(min(r.w, r.h) / 2)
	}
	return {sh.radii[0], sh.radii[1], sh.radii[2], sh.radii[3]}
}
