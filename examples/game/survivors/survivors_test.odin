package main

import "core:os"
import "core:testing"

import "jm:game"
import jm_path "jm:path"
import "jm:ui"

// run steps world n ticks holding keys, pressing press on the first.
@(private = "file")
run :: proc(world: ^World, ticks: int, keys: ui.Keys = {}, press: ui.Keys = {}) {
	for ii in 0 ..< ticks {
		input := game.Input{held = keys}
		if ii == 0 {
			input.pressed = press
		}
		step(world, input)
	}
}

@(private = "file")
quiet :: proc(seed: u64 = 1) -> (world: World) {
	init(&world, seed)
	world.spawn = 1 << 30 // no enemies unless a test places them
	return
}

@(test)
the_hunter_walks_as_fast_diagonally_as_straight :: proc(t: ^testing.T) {
	straight := quiet()
	run(&straight, 60, {.Right})
	testing.expect(t, abs(straight.player.at.x - 60 * 1.3) < 0.01)

	diagonal := quiet()
	run(&diagonal, 60, {.Right, .Down})
	moved := diagonal.player.at
	testing.expect(t, abs(moved.x * moved.x + moved.y * moved.y - (60 * 1.3) * (60 * 1.3)) < 0.1)
	testing.expect(t, moved.x > 0 && moved.y > 0)
}

@(test)
a_bat_that_touches_the_hunter_hurts_once_a_grace :: proc(t: ^testing.T) {
	world := quiet()
	world.weapons[.Knife] = 0 // unarmed, so the bat lives
	append(&world.enemies, Enemy{at = {2, 0}, kind = .Bat, hp = 8})
	run(&world, GRACE)
	testing.expect_value(t, world.player.hp, 100 - STATS[.Bat].damage)
	run(&world, 1)
	testing.expect_value(t, world.player.hp, 100 - 2 * STATS[.Bat].damage)
}

@(test)
a_knife_kills_a_bat_whose_gem_levels_the_hunter_up :: proc(t: ^testing.T) {
	world := quiet()
	world.player.xp = xp_needed(1) - 1
	append(&world.enemies, Enemy{at = {60, 0}, kind = .Bat, hp = 8})
	run(&world, 30)
	testing.expect_value(t, world.kills, 1)
	testing.expect_value(t, len(world.gems), 1)
	// The gem lies where the bat fell; walking over it takes it.
	for world.state == .Playing && world.ticks < 200 {
		run(&world, 1, {.Right})
	}
	testing.expect_value(t, world.state, State.Choosing)
	testing.expect_value(t, world.player.level, 2)
	testing.expect_value(t, world.offered, 3)

	// While choosing, nothing moves; 1 takes the first offer.
	at := world.player.at
	run(&world, 10, {.Right})
	testing.expect_value(t, world.player.at, at)
	first := world.choices[0]
	before := upgrade_level(&world, first)
	run(&world, 1, press = {.N1})
	testing.expect_value(t, world.state, State.Playing)
	testing.expect_value(t, upgrade_level(&world, first), before + 1)
}

@(test)
an_offer_never_repeats_or_passes_the_last_level :: proc(t: ^testing.T) {
	world := quiet()
	world.weapons = {.Knife = MAX_LEVEL, .Bolt = MAX_LEVEL, .Aura = MAX_LEVEL}
	world.traits[.Vitality] = MAX_LEVEL
	offer(&world)
	testing.expect_value(t, world.offered, 2) // only Swiftness and Magnet are left
	testing.expect(t, world.choices[0] != world.choices[1])
	for ii in 0 ..< 2 {
		testing.expect(t, world.choices[ii] == .Swiftness || world.choices[ii] == .Magnet)
	}
}

@(test)
the_dead_rise_with_r :: proc(t: ^testing.T) {
	world := quiet()
	world.player.hp = 1
	world.weapons[.Knife] = 0
	append(&world.enemies, Enemy{at = {0, 0}, kind = .Zombie, hp = 26})
	run(&world, 1)
	testing.expect_value(t, world.state, State.Dead)
	ticks := world.ticks
	run(&world, 30, {.Right})
	testing.expect_value(t, world.ticks, ticks) // the dead stay dead
	run(&world, 1, press = {.R})
	testing.expect_value(t, world.state, State.Playing)
	testing.expect_value(t, world.player.hp, 100)
	testing.expect_value(t, len(world.enemies), 0)
}

@(test)
the_night_grows_and_a_run_replays_exactly :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	dir, err := jm_path.temp_dir("survivors-", context.temp_allocator)
	testing.expect_value(t, err, nil)
	defer jm_path.remove_all(dir)
	path := jm_path.join(dir, "run.tape", allocator = context.temp_allocator)

	// Three minutes of circling, choosing the first offer at each level.
	survivors := game.Game(World){size = VIEW, seed = 3, init = init, step = step, draw = draw}
	world: World
	init(&world, survivors.seed)
	runner: game.Runner(World)
	game.runner_init(&runner, survivors, &world)
	defer game.runner_destroy(&runner)
	game.runner_record(&runner, path)
	probe: ui.Probe
	ui.probe_init(&probe, game.runner_frame(World), &runner, VIEW)
	defer ui.probe_destroy(&probe)
	ways := [4]ui.Key{.Right, .Down, .Left, .Up}
	for second in 0 ..< 180 {
		way := ways[second / 3 % 4]
		ui.probe_key_down(&probe, way)
		ui.probe_advance(&probe, 59, 1.0 / 60)
		ui.probe_key_up(&probe, way)
		if world.state == .Choosing {
			ui.probe_key(&probe, .N1)
		}
		if world.state == .Dead {
			break
		}
	}
	game.runner_record_stop(&runner)
	testing.expectf(t, world.kills > 50, "kills: %d", world.kills)
	testing.expectf(t, world.player.level > 3, "level: %d", world.player.level)

	data, read_err := os.read_entire_file(path, context.temp_allocator)
	testing.expect_value(t, read_err, nil)
	replayed: World
	_, ok := game.tape_replay(survivors, &replayed, data)
	testing.expect(t, ok)
	testing.expect(t, transmute([size_of(World)]u8)replayed == transmute([size_of(World)]u8)world, "the replay ends in the live World")
}
