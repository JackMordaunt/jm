package game

import "core:os"
import "core:testing"

import jm_path "jm:path"
import "jm:ui"

// Sparks is a World busy enough to drift if anything replayed wrong: a
// body that walks and jumps, sparks drawn from the Rng on each jump, and
// clicks counted where they land.
@(private = "file")
Sparks :: struct {
	at:     [2]f32,
	vel:    [2]f32,
	rng:    Rng,
	sparks: [dynamic; 32][2]f32,
	clicks: [2]f32, // the sum of where clicks landed
	ticks:  int,
}

@(private = "file")
sparks_init :: proc(world: ^Sparks, seed: u64) {
	world^ = {at = {50, 40}, rng = rng_seed(seed)}
}

@(private = "file")
sparks_step :: proc(world: ^Sparks, input: Input) {
	world.ticks += 1
	world.vel.x = 1.5 * axis(input, {.Left}, {.Right})
	if input.pressed & {.Space} != {} {
		world.vel.y = -4
		for _ in 0 ..< 3 {
			if len(world.sparks) < cap(world.sparks) {
				append(&world.sparks, [2]f32{world.at.x + rng_float(&world.rng) * 8, world.at.y})
			}
		}
	}
	world.vel.y = min(world.vel.y + 0.25, 4)
	world.at += world.vel
	world.at.y = min(world.at.y, 40)
	if .Left in input.clicked {
		world.clicks += input.pointer
	}
}

@(private = "file")
sparks_draw :: proc(world: ^Sparks, canvas: ^Canvas) {}

@(private = "file")
SPARKS :: Game(Sparks) {
	size = {100, 50},
	seed = 7,
	init = sparks_init,
	step = sparks_step,
	draw = sparks_draw,
}

// play_sparks plays 600 ticks of scripted input through a probe at the
// tick rate, recording them to path when it is not "", and returns the
// World they leave.
@(private = "file")
play_sparks :: proc(path: string) -> (world: Sparks) {
	SPARKS.init(&world, SPARKS.seed)
	runner: Runner(Sparks)
	runner_init(&runner, SPARKS, &world)
	if path != "" {
		runner_record(&runner, path)
	}
	probe: ui.Probe
	ui.probe_init(&probe, runner_frame(Sparks), &runner, {200, 100})
	defer ui.probe_destroy(&probe)
	for ii in 0 ..< 600 {
		switch ii % 120 {
		case 0:
			ui.probe_key_down(&probe, .Right)
		case 40:
			ui.probe_key(&probe, .Space)
		case 60:
			ui.probe_key_up(&probe, .Right)
			ui.probe_key_down(&probe, .Left)
		case 90:
			ui.probe_click_at(&probe, {f32(ii / 4), 30})
		case 100:
			ui.probe_key_up(&probe, .Left)
		case:
			ui.probe_frame(&probe)
		}
	}
	runner_record_stop(&runner)
	return
}

@(private = "file")
scratch_tape :: proc(t: ^testing.T) -> (dir, path: string) {
	err: os.Error
	dir, err = jm_path.temp_dir("jm-game-tape-", context.temp_allocator)
	testing.expect_value(t, err, nil)
	return dir, jm_path.join(dir, "run.tape", allocator = context.temp_allocator)
}

@(test)
a_tape_replays_the_run_byte_for_byte :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	dir, path := scratch_tape(t)
	defer jm_path.remove_all(dir)

	live := play_sparks(path)
	testing.expect(t, live.ticks >= 600, "the script ran its ticks")
	testing.expect(t, len(live.sparks) > 0 && live.clicks != {}, "the script jumped and clicked")
	data, err := os.read_entire_file(path, context.temp_allocator)
	testing.expect_value(t, err, nil)

	replayed: Sparks
	ticks, ok := tape_replay(SPARKS, &replayed, data)
	testing.expect(t, ok)
	testing.expect_value(t, ticks, u64(live.ticks))
	testing.expect(t, transmute([size_of(Sparks)]u8)replayed == transmute([size_of(Sparks)]u8)live, "the replayed World is the live one")

	// Only the ticks whose input changed were written: a key held for a
	// second is one entry, not sixty. The script changes its input about
	// forty times; one entry a tick would be 600.
	entry := 8 + 1 + 3 * size_of(ui.Keys) + 8 + 3
	testing.expectf(t, len(data) < 60 * entry, "600 ticks took %d bytes, %d entries' worth", len(data), len(data) / entry)
}

@(test)
a_tape_replays_the_same_at_any_frame_rate :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	dir, path := scratch_tape(t)
	defer jm_path.remove_all(dir)
	live := play_sparks(path)
	data, _ := os.read_entire_file(path, context.temp_allocator)

	tape: Tape
	testing.expect(t, tape_open(&tape, data))
	world: Sparks
	runner: Runner(Sparks)
	runner_init(&runner, SPARKS, &world)
	testing.expect(t, runner_replay(&runner, &tape))
	probe: ui.Probe
	ui.probe_init(&probe, runner_frame(Sparks), &runner, {200, 100})
	defer ui.probe_destroy(&probe)
	ui.probe_advance(&probe, 144 * 12, 1.0 / 144) // 12 s of a 144 Hz display, past the tape's 10
	testing.expect(t, transmute([size_of(Sparks)]u8)world == transmute([size_of(Sparks)]u8)live, "the replayed World is the live one")
}

@(test)
a_tape_cut_short_replays_to_its_last_entry :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	dir, path := scratch_tape(t)
	defer jm_path.remove_all(dir)
	play_sparks(path)
	data, _ := os.read_entire_file(path, context.temp_allocator)

	cut := data[:len(data) - 9] // the end entry: a u64 count and its kind
	tape: Tape
	testing.expect(t, tape_open(&tape, cut))
	testing.expect(t, tape.ticks > 0 && tape.ticks < 600)
	world: Sparks
	ticks, ok := tape_replay(SPARKS, &world, cut)
	testing.expect(t, ok)
	testing.expect_value(t, ticks, tape.ticks)
}

@(test)
a_tape_of_another_world_or_none_is_refused :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	dir, path := scratch_tape(t)
	defer jm_path.remove_all(dir)
	play_sparks(path)
	data, _ := os.read_entire_file(path, context.temp_allocator)

	Other :: struct {
		at: [2]f32,
	}
	other: Other
	_, ok := tape_replay(Game(Other){step = proc(world: ^Other, input: Input) {}}, &other, data)
	testing.expect(t, !ok)
	tape: Tape
	testing.expect(t, !tape_open(&tape, transmute([]byte)string("not a tape at all")))
}
