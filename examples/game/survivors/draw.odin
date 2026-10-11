package main

import "core:fmt"
import "core:math"

import "jm:game"
import "jm:ui"
import "jm:ui/ops"

ART :: game.Sheet {
	path    = "examples/game/survivors/art.png",
	frame   = {16, 16},
	columns = 11,
}

HUNTER_FRAME :: 0
GEM_FRAME :: 8
KNIFE_FRAME :: 9
BOLT_FRAME :: 10

TEXT :: ops.Color{235, 230, 220, 255}
DIM :: ops.Color{150, 150, 160, 255}

draw :: proc(world: ^World, canvas: ^game.Canvas) {
	// The camera keeps the hunter centred; the HUD after it stays put.
	game.camera_open(canvas, world.player.at)
	draw_field(canvas, world.player.at - VIEW / 2)
	draw_aura(world, canvas)
	for gem in world.gems {
		game.sprite(canvas, ART, GEM_FRAME, box_around(gem.at, 12))
	}
	for enemy in world.enemies {
		stats := STATS[enemy.kind]
		frame := stats.frame + int(world.ticks / 12 % 2)
		flip := game.Flips{.X} if enemy.at.x > world.player.at.x else {}
		at := box_around(enemy.at, 16)
		game.sprite(canvas, ART, frame, at, flip)
		if enemy.flash > 0 {
			ops.fill(canvas.scene, ops.Rect{at.x + 3, at.y + 3, 10, 10}, ops.Color{255, 255, 255, 140})
		}
	}
	for shot in world.shots {
		switch shot.weapon {
		case .Knife:
			// The knife's frame in art.png points right: turn it the way it flies.
			at := box_around(shot.at, 16)
			turn := ops.mul(ops.mul(ops.translate(-shot.at.x, -shot.at.y), ops.rotate(angle_of(shot.vel))), ops.translate(shot.at.x, shot.at.y))
			ops.transform_push(canvas.scene, turn)
			game.sprite(canvas, ART, KNIFE_FRAME, at)
			ops.transform_pop(canvas.scene)
		case .Bolt:
			game.sprite(canvas, ART, BOLT_FRAME, box_around(shot.at, 12))
		case .Aura:
		}
	}
	draw_hunter(world, canvas)
	ops.tag(canvas.scene, 0, "hunter", box_around(world.player.at, 16))
	game.camera_close(canvas)

	draw_hud(world, canvas)
	switch world.state {
	case .Choosing:
		draw_choices(world, canvas)
	case .Dead:
		draw_death(world, canvas)
	case .Playing:
	}
}

angle_of :: proc(way: [2]f32) -> f32 {
	return math.atan2(way.y, way.x)
}

// draw_field scatters a grid of tufts over the view whose top left is
// at camera, so a walk across an empty field still reads as one.
draw_field :: proc(canvas: ^game.Canvas, camera: [2]f32) {
	GAP :: 32
	first := [2]f32{f32(int(camera.x / GAP) - 1) * GAP, f32(int(camera.y / GAP) - 1) * GAP}
	for y := first.y; y < camera.y + VIEW.y + GAP; y += GAP {
		for x := first.x; x < camera.x + VIEW.x + GAP; x += GAP {
			// Offset each tuft by its cell, so the grid does not read as one.
			wobble := f32((int(x) * 7 + int(y) * 13) % 11)
			ops.fill(canvas.scene, ops.Rect{x + wobble, y + wobble / 2, 2, 1}, ops.Color{40, 52, 42, 255})
			ops.fill(canvas.scene, ops.Rect{x + wobble + 3, y + wobble / 2 - 1, 1, 2}, ops.Color{40, 52, 42, 255})
		}
	}
}

draw_aura :: proc(world: ^World, canvas: ^game.Canvas) {
	level := world.weapons[.Aura]
	if level == 0 {
		return
	}
	reach := aura_reach(level)
	pulse := u8(30 + 20 * (world.ticks % 30) / 30)
	at := world.player.at
	ops.fill(canvas.scene, ui.circle(at, reach), ops.Color{255, 210, 120, pulse})
}

draw_hunter :: proc(world: ^World, canvas: ^game.Canvas) {
	player := world.player
	// Blink through the grace a hit gives.
	if player.hurt > 0 && player.hurt / 3 % 2 == 0 {
		return
	}
	frame := HUNTER_FRAME + (int(world.ticks / 10 % 2) if player.walked else 0)
	flip := game.Flips{.X} if player.facing.x < 0 else {}
	game.sprite(canvas, ART, frame, box_around(player.at, 16), flip)
	// Health under him.
	bar := ops.Rect{player.at.x - 9, player.at.y + 10, 18, 2}
	ops.fill(canvas.scene, bar, ops.Color{60, 20, 20, 255})
	ops.fill(canvas.scene, ops.Rect{bar.x, bar.y, bar.w * max(player.hp, 0) / player.max_hp, bar.h}, ops.Color{220, 50, 50, 255})
}

draw_hud :: proc(world: ^World, canvas: ^game.Canvas) {
	player := world.player
	// Experience across the top.
	ops.fill(canvas.scene, ops.Rect{0, 0, VIEW.x, 5}, ops.Color{20, 20, 40, 255})
	ops.fill(canvas.scene, ops.Rect{0, 0, VIEW.x * f32(player.xp) / f32(xp_needed(player.level)), 5}, ops.Color{70, 140, 255, 255})
	draw_line(canvas, {4, 8}, 8, TEXT, "LV %d", player.level)
	seconds := world.ticks / TICKS_PER_SECOND
	draw_line(canvas, {VIEW.x / 2 - 12, 8}, 10, TEXT, "%02d:%02d", seconds / 60, seconds % 60)
	draw_line(canvas, {VIEW.x - 64, 8}, 8, TEXT, "kills %d", world.kills)
	// What is held, under the level.
	y: f32 = 20
	for level, weapon in world.weapons {
		if level > 0 {
			draw_line(canvas, {4, y}, 7, DIM, "%v %d", weapon, level)
			y += 9
		}
	}
}

draw_choices :: proc(world: ^World, canvas: ^game.Canvas) {
	panel := ops.Rect{VIEW.x / 2 - 110, 60, 220, 40 + 34 * f32(world.offered)}
	ops.fill(canvas.scene, ops.Rect{0, 0, VIEW.x, VIEW.y}, ops.Color{0, 0, 0, 120})
	ops.fill(canvas.scene, ops.Round_Rect{rect = panel, radius = 6}, ops.Color{30, 26, 44, 245})
	draw_line(canvas, {panel.x + 14, panel.y + 10}, 12, ops.Color{255, 220, 120, 255}, "LEVEL UP")
	for ii in 0 ..< int(world.offered) {
		upgrade := world.choices[ii]
		top := panel.y + 34 + 34 * f32(ii)
		ops.fill(canvas.scene, ops.Round_Rect{rect = {panel.x + 8, top, panel.w - 16, 30}, radius = 4}, ops.Color{48, 42, 70, 255})
		level := upgrade_level(world, upgrade)
		draw_line(canvas, {panel.x + 16, top + 4}, 9, TEXT, "%d   %v %s", ii + 1, upgrade, "new" if level == 0 else fmt.aprintf("%d -> %d", level, level + 1, allocator = canvas.gtx.allocator))
		draw_line(canvas, {panel.x + 30, top + 17}, 7, DIM, "%s", ABOUT[upgrade])
		ops.tag(canvas.scene, 0, fmt.aprintf("choice %d", ii + 1, allocator = canvas.gtx.allocator), {panel.x + 8, top, panel.w - 16, 30})
	}
}

ABOUT := [Upgrade]string {
	.Knife     = "more knives, faster, through more",
	.Bolt      = "a seeking orb that hits hard",
	.Aura      = "hurt all that come close",
	.Vitality  = "more health, and some back",
	.Swiftness = "walk faster",
	.Magnet    = "gems come from further",
}

draw_death :: proc(world: ^World, canvas: ^game.Canvas) {
	ops.fill(canvas.scene, ops.Rect{0, 0, VIEW.x, VIEW.y}, ops.Color{20, 0, 0, 170})
	seconds := world.ticks / TICKS_PER_SECOND
	draw_line(canvas, {VIEW.x / 2 - 60, 100}, 18, ops.Color{230, 60, 60, 255}, "YOU DIED")
	draw_line(canvas, {VIEW.x / 2 - 70, 130}, 9, TEXT, "survived %02d:%02d, %d kills", seconds / 60, seconds % 60, world.kills)
	draw_line(canvas, {VIEW.x / 2 - 40, 150}, 8, DIM, "press R to rise")
}

// draw_line writes a formatted line with its top left at at, size units tall.
draw_line :: proc(canvas: ^game.Canvas, at: [2]f32, size: f32, color: ops.Color, format: string, args: ..any) {
	ui.draw_text(canvas.gtx, fmt.aprintf(format, ..args, allocator = canvas.gtx.allocator), at, size, color)
}
