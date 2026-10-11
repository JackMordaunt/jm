/*
survivors is a small game in the manner of Vampire Survivors, built on
jm:game as its reference: a hunter walks a field that night fills with
bats, zombies and ghouls, and fights back only through weapons that fire
on their own. Each kill drops a gem; enough gems and the game stops to
offer three upgrades. Survive as long as you can.

	WASD or arrows   walk
	1, 2, 3          choose an upgrade
	R                start again, once dead
	F3               the debug overlay: hitboxes, aims, the aura's reach

Everything the game knows is World, plain data, and step is the only
thing that changes it, so a run recorded in debug builds replays exactly
(see jm:game's tapes), and a test drives step directly with Inputs.

Run it from the repository's root, where its art's path starts:

	just game survivors
*/
package main

import "core:math"
import "core:math/linalg"

import "core:time"

import "jm:game"
import "jm:ui"
import "jm:ui/ops"

// VIEW is the game's size in its own units: the field the camera shows.
VIEW :: [2]f32{480, 270}

TICKS_PER_SECOND :: 60

State :: enum u8 {
	Playing,
	Choosing, // levelled up: the game waits for an upgrade
	Dead,
}

Kind :: enum u8 {
	Bat,
	Zombie,
	Ghoul,
}

Enemy :: struct {
	at:    [2]f32,
	kind:  Kind,
	hp:    f32,
	flash: u8, // ticks left of the white flash a hit gives
}

Weapon :: enum u8 {
	Knife, // thrown toward the nearest enemy, through a few
	Bolt, // a slow orb that seeks the nearest enemy
	Aura, // hurts everything close, every few ticks
}

Shot :: struct {
	at, vel: [2]f32,
	weapon:  Weapon,
	life:    i32, // ticks before it falls
	pierce:  i32, // enemies it may still pass through
	damage:  f32,
}

Gem :: struct {
	at: [2]f32,
	xp: i32,
}

// Upgrade is what a level offers: a weapon's next level, or a trait.
Upgrade :: enum u8 {
	Knife,
	Bolt,
	Aura,
	Vitality, // more health, and some back
	Swiftness, // walk faster
	Magnet, // gems come from further
}

MAX_LEVEL :: 5

Player :: struct {
	at:     [2]f32,
	facing: [2]f32, // the last way walked, a unit vector
	walked: bool, // walked this tick
	hp:     f32,
	max_hp: f32,
	speed:  f32,
	magnet: f32, // how far gems come from
	hurt:   i32, // ticks left of the grace after a hit
	xp:     i32, // toward the next level
	level:  i32,
}

World :: struct {
	state:    State,
	ticks:    i32, // ticks survived
	kills:    i32,
	rng:      game.Rng,
	player:   Player,
	weapons:  [Weapon]i32, // each weapon's level, 0 for not held
	cooldown: [Weapon]i32, // ticks until each fires again
	traits:   [Upgrade]i32, // the levels of Vitality, Swiftness and Magnet taken
	choices:  [3]Upgrade, // what Choosing offers
	offered:  i32, // how many of choices are real: fewer when little is left to take
	spawn:    i32, // ticks until the next spawn
	enemies:  [dynamic; 320]Enemy,
	shots:    [dynamic; 160]Shot,
	gems:     [dynamic; 256]Gem,
}

// Stats is what each kind of enemy is.
Stats :: struct {
	speed, hp, damage, size: f32,
	xp:                      i32,
	frame:                   int, // its first frame in the art; the next is its second
}

STATS := [Kind]Stats {
	.Bat    = {speed = 0.95, hp = 8, damage = 4, size = 10, xp = 1, frame = 2},
	.Zombie = {speed = 0.5, hp = 26, damage = 7, size = 13, xp = 2, frame = 4},
	.Ghoul  = {speed = 0.7, hp = 70, damage = 12, size = 15, xp = 5, frame = 6},
}

PLAYER_SIZE :: 10
GRACE :: 20 // ticks a hit leaves the hunter unhurtable
GEM_REACH :: 8 // how close a gem must come to be taken
SPAWN_DISTANCE :: 300 // beyond the view's corners
FAR :: 420 // an enemy further than this is brought back round

LEFT :: ui.Keys{.Left, .A}
RIGHT :: ui.Keys{.Right, .D}
UP :: ui.Keys{.Up, .W}
DOWN :: ui.Keys{.Down, .S}

// init starts a run from seed: the hunter alone, holding a knife.
init :: proc(world: ^World, seed: u64) {
	world^ = {
		rng = game.rng_seed(seed),
		player = {facing = {1, 0}, hp = 100, max_hp = 100, speed = 1.3, magnet = 28, level = 1},
		spawn = TICKS_PER_SECOND,
	}
	world.weapons[.Knife] = 1
}

step :: proc(world: ^World, input: game.Input) {
	switch world.state {
	case .Dead:
		if input.pressed & {.R} != {} {
			init(world, game.rng_u64(&world.rng))
		}
		return
	case .Choosing:
		choose(world, input)
		return
	case .Playing:
	}
	world.ticks += 1
	walk(&world.player, input)
	spawn(world)
	chase(world)
	fire(world)
	fly(world)
	outline_aura(world)
	bury(world)
	gather(world)
	if world.player.hp <= 0 {
		world.state = .Dead
	}
}

// walk moves the hunter as the keys say, as fast diagonally as straight.
walk :: proc(player: ^Player, input: game.Input) {
	way := [2]f32{game.axis(input, LEFT, RIGHT), game.axis(input, UP, DOWN)}
	player.walked = way != {}
	if player.walked {
		way = linalg.normalize(way)
		player.facing = way
		player.at += way * player.speed
	}
	if player.hurt > 0 {
		player.hurt -= 1
	}
}

// spawn brings enemies in from beyond the view, more and tougher as the
// night goes on.
spawn :: proc(world: ^World) {
	world.spawn -= 1
	if world.spawn > 0 {
		return
	}
	seconds := world.ticks / TICKS_PER_SECOND
	world.spawn = max(6, 50 - seconds / 4)
	for _ in 0 ..< 1 + seconds / 45 {
		if len(world.enemies) == cap(world.enemies) {
			return
		}
		kind := Kind.Bat
		roll := game.rng_float(&world.rng)
		if seconds > 120 && roll < 0.15 {
			kind = .Ghoul
		} else if seconds > 30 && roll < 0.5 {
			kind = .Zombie
		}
		append(&world.enemies, Enemy{at = world.player.at + random_offset(&world.rng, SPAWN_DISTANCE), kind = kind, hp = STATS[kind].hp})
	}
}

// random_offset is a point distance away in a random direction.
random_offset :: proc(rng: ^game.Rng, distance: f32) -> [2]f32 {
	angle := game.rng_float(rng) * math.TAU
	return {math.cos(angle), math.sin(angle)} * distance
}

// chase walks every enemy toward the hunter, keeps them from stacking,
// and lets those touching him hurt him.
chase :: proc(world: ^World) {
	player := &world.player
	for &enemy in world.enemies {
		stats := STATS[enemy.kind]
		toward := player.at - enemy.at
		distance := linalg.length(toward)
		if distance > FAR {
			enemy.at = player.at + random_offset(&world.rng, SPAWN_DISTANCE)
			continue
		}
		if distance > 0.01 {
			enemy.at += toward / distance * stats.speed
		}
		if enemy.flash > 0 {
			enemy.flash -= 1
		}
		if distance < (stats.size + PLAYER_SIZE) / 2 && player.hurt == 0 {
			player.hp -= stats.damage
			player.hurt = GRACE
		}
	}
	// Push overlapping enemies apart, half each way.
	for ii in 0 ..< len(world.enemies) {
		for jj in ii + 1 ..< len(world.enemies) {
			first, second := &world.enemies[ii], &world.enemies[jj]
			apart := second.at - first.at
			reach := (STATS[first.kind].size + STATS[second.kind].size) / 2 * 0.8
			if apart.x > reach || apart.x < -reach || apart.y > reach || apart.y < -reach {
				continue
			}
			distance := linalg.length(apart)
			if distance < reach && distance > 0.01 {
				push := apart / distance * (reach - distance) / 2
				first.at -= push
				second.at += push
			}
		}
	}
	for enemy in world.enemies {
		game.debug_rect(box_around(enemy.at, STATS[enemy.kind].size), {255, 80, 80, 255})
	}
	game.debug_rect(box_around(player.at, PLAYER_SIZE), {80, 255, 120, 255})
}

// box_around is the square of size centred on at: a hitbox, a sprite's place.
box_around :: proc(at: [2]f32, size: f32) -> ops.Rect {
	return {at.x - size / 2, at.y - size / 2, size, size}
}

// nearest is the enemy closest to at, false when there is none within reach.
nearest :: proc(world: ^World, at: [2]f32, reach: f32) -> (index: int, found: bool) {
	best := reach * reach
	for enemy, ii in world.enemies {
		apart := enemy.at - at
		if distance := linalg.dot(apart, apart); distance < best {
			best, index, found = distance, ii, true
		}
	}
	return
}

// fire lets each held weapon act when its cooldown ends.
fire :: proc(world: ^World) {
	player := &world.player
	for level, weapon in world.weapons {
		if level == 0 {
			continue
		}
		world.cooldown[weapon] -= 1
		if world.cooldown[weapon] > 0 {
			continue
		}
		switch weapon {
		case .Knife:
			world.cooldown[weapon] = max(16, 48 - 6 * level)
			aim := player.facing
			if target, ok := nearest(world, player.at, 200); ok {
				aim = linalg.normalize0(world.enemies[target].at - player.at)
			}
			game.debug_arrow(player.at, player.at + aim * 40)
			// More knives fan out around the aim.
			for ii in 0 ..< level {
				turn := (f32(ii) - f32(level - 1) / 2) * 0.18
				way := linalg.Vector2f32{aim.x * math.cos(turn) - aim.y * math.sin(turn), aim.x * math.sin(turn) + aim.y * math.cos(turn)}
				shoot(world, {at = player.at, vel = way * 4.5, weapon = .Knife, life = 55, pierce = 1 + level / 2, damage = 10})
			}
		case .Bolt:
			world.cooldown[weapon] = max(24, 80 - 10 * level)
			if target, ok := nearest(world, player.at, 260); ok {
				way := linalg.normalize0(world.enemies[target].at - player.at)
				shoot(world, {at = player.at, vel = way * 2.5, weapon = .Bolt, life = 120, pierce = 0, damage = 20 + 6 * f32(level)})
			}
		case .Aura:
			world.cooldown[weapon] = 15
			reach := aura_reach(level)
			for &enemy in world.enemies {
				if linalg.distance(enemy.at, player.at) < reach + STATS[enemy.kind].size / 2 {
					hit(&enemy, 3 + 1.5 * f32(level))
				}
			}
		}
	}
}

aura_reach :: proc(level: i32) -> f32 {
	return 22 + 7 * f32(level)
}

shoot :: proc(world: ^World, shot: Shot) {
	if len(world.shots) < cap(world.shots) {
		append(&world.shots, shot)
	}
}

hit :: proc(enemy: ^Enemy, damage: f32) {
	enemy.hp -= damage
	enemy.flash = 6
}

// fly moves the shots and lets them hit what they meet. A bolt turns
// toward the nearest enemy as it goes.
fly :: proc(world: ^World) {
	for ii := len(world.shots) - 1; ii >= 0; ii -= 1 {
		shot := &world.shots[ii]
		if shot.weapon == .Bolt {
			if target, ok := nearest(world, shot.at, 120); ok {
				want := linalg.normalize0(world.enemies[target].at - shot.at) * 2.5
				shot.vel = linalg.lerp(shot.vel, want, 0.08)
			}
		}
		shot.at += shot.vel
		shot.life -= 1
		for &enemy in world.enemies {
			if shot.life <= 0 {
				break
			}
			if enemy.hp <= 0 || linalg.distance(enemy.at, shot.at) > STATS[enemy.kind].size / 2 + 3 {
				continue
			}
			hit(&enemy, shot.damage)
			if shot.pierce == 0 {
				shot.life = 0
			}
			shot.pierce -= 1
		}
		if shot.life <= 0 {
			unordered_remove(&world.shots, ii)
		}
	}
}

// outline_aura shows the aura's reach in the overlay.
outline_aura :: proc(world: ^World) {
	if level := world.weapons[.Aura]; level > 0 {
		reach := aura_reach(level)
		at := world.player.at
		game.debug_rect({at.x - reach, at.y - reach, 2 * reach, 2 * reach}, {255, 200, 80, 255})
	}
}

// bury takes the dead off the field and leaves their gems.
bury :: proc(world: ^World) {
	for ii := len(world.enemies) - 1; ii >= 0; ii -= 1 {
		enemy := world.enemies[ii]
		if enemy.hp > 0 {
			continue
		}
		world.kills += 1
		gem := Gem{at = enemy.at, xp = STATS[enemy.kind].xp}
		if len(world.gems) < cap(world.gems) {
			append(&world.gems, gem)
		} else {
			world.gems[0].xp += gem.xp // a full field banks it in the oldest
		}
		unordered_remove(&world.enemies, ii)
	}
}

// gather pulls in the gems within the magnet's reach and takes those that
// arrive, levelling up when enough are taken.
gather :: proc(world: ^World) {
	player := &world.player
	for ii := len(world.gems) - 1; ii >= 0; ii -= 1 {
		gem := &world.gems[ii]
		distance := linalg.distance(gem.at, player.at)
		if distance < GEM_REACH {
			player.xp += gem.xp
			unordered_remove(&world.gems, ii)
		} else if distance < player.magnet {
			gem.at += (player.at - gem.at) / distance * 3
		}
	}
	if player.xp >= xp_needed(player.level) {
		player.xp -= xp_needed(player.level)
		player.level += 1
		offer(world)
	}
}

xp_needed :: proc(level: i32) -> i32 {
	return 4 + 4 * level + level * level / 2
}

// offer picks up to three upgrades not yet at their last level and waits
// for one; with none left, the run goes on.
offer :: proc(world: ^World) {
	open: [len(Upgrade)]Upgrade
	count := 0
	for upgrade in Upgrade {
		if upgrade_level(world, upgrade) < MAX_LEVEL {
			open[count] = upgrade
			count += 1
		}
	}
	world.offered = i32(min(count, 3))
	for ii in 0 ..< int(world.offered) {
		pick := game.rng_int(&world.rng, ii, count)
		open[ii], open[pick] = open[pick], open[ii]
		world.choices[ii] = open[ii]
	}
	if world.offered > 0 {
		world.state = .Choosing
	}
}

upgrade_level :: proc(world: ^World, upgrade: Upgrade) -> i32 {
	switch upgrade {
	case .Knife:
		return world.weapons[.Knife]
	case .Bolt:
		return world.weapons[.Bolt]
	case .Aura:
		return world.weapons[.Aura]
	case .Vitality, .Swiftness, .Magnet:
		return world.traits[upgrade]
	}
	return 0
}

// choose takes the upgrade 1, 2 or 3 names.
choose :: proc(world: ^World, input: game.Input) {
	keys := [3]ui.Key{.N1, .N2, .N3}
	for key, ii in keys {
		if i32(ii) >= world.offered || key not_in input.pressed {
			continue
		}
		upgrade := world.choices[ii]
		switch upgrade {
		case .Knife:
			world.weapons[.Knife] += 1
		case .Bolt:
			world.weapons[.Bolt] += 1
		case .Aura:
			world.weapons[.Aura] += 1
		case .Vitality:
			world.traits[upgrade] += 1
			world.player.max_hp += 20
			world.player.hp = min(world.player.hp + 40, world.player.max_hp)
		case .Swiftness:
			world.traits[upgrade] += 1
			world.player.speed += 0.15
		case .Magnet:
			world.traits[upgrade] += 1
			world.player.magnet += 18
		}
		world.state = .Playing
		return
	}
}

main :: proc() {
	world: World
	game.run(game.Game(World){title = "Survivors", size = VIEW, seed = u64(time.now()._nsec), clear = {24, 30, 26, 255}, init = init, step = step, draw = draw}, &world)
}
