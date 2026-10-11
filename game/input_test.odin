package game

import "core:testing"

import "jm:ui"
import "jm:ui/ops"

// Input_Log is a World that writes down every Input its ticks got.
@(private = "file")
Input_Log :: struct {
	inputs: [dynamic; 64]Input,
}

@(private = "file")
log_step :: proc(log: ^Input_Log, input: Input) {
	append(&log.inputs, input)
}

@(private = "file")
log_draw :: proc(log: ^Input_Log, canvas: ^Canvas) {}

@(private = "file")
INPUT_LOG :: Game(Input_Log) {
	size = {100, 50},
	step = log_step,
	draw = log_draw,
}

@(private = "file")
last :: proc(log: ^Input_Log) -> Input {
	return log.inputs[len(log.inputs) - 1]
}

@(test)
a_key_held_across_ticks_is_pressed_in_the_first_only :: proc(t: ^testing.T) {
	log: Input_Log
	runner: Runner(Input_Log)
	runner_init(&runner, INPUT_LOG, &log)
	probe: ui.Probe
	ui.probe_init(&probe, runner_frame(Input_Log), &runner, {200, 100})
	defer ui.probe_destroy(&probe)

	ui.probe_key_down(&probe, .Right)
	testing.expect(t, (last(&log).pressed & {.Right} != {}))
	testing.expect(t, (last(&log).held & {.Right, .D} != {}))
	ui.probe_frame(&probe)
	testing.expect(t, !(last(&log).pressed & {.Right} != {}))
	testing.expect_value(t, axis(last(&log), {.Left}, {.Right}), 1)
	ui.probe_key_up(&probe, .Right)
	testing.expect(t, (last(&log).released & {.Right} != {}))
	testing.expect(t, !(last(&log).held & {.Right} != {}))
	for input, ii in log.inputs {
		testing.expect_value(t, input.tick, u64(ii)) // one tick a frame at the probe's 1/60
	}
}

@(test)
a_tap_in_a_frame_that_runs_no_tick_waits_for_the_next :: proc(t: ^testing.T) {
	log: Input_Log
	runner: Runner(Input_Log)
	runner_init(&runner, INPUT_LOG, &log)
	probe: ui.Probe
	ui.probe_init(&probe, runner_frame(Input_Log), &runner, {200, 100})
	defer ui.probe_destroy(&probe)

	ui.probe_set_dt(&probe, 1.0 / 240) // four frames a tick
	for len(log.inputs) == 0 {
		ui.probe_frame(&probe) // line up on a tick
	}
	ticks := len(log.inputs)
	ui.probe_key(&probe, .Space)
	for len(log.inputs) == ticks {
		ui.probe_frame(&probe)
	}
	tap := last(&log)
	testing.expect(t, (tap.pressed & {.Space} != {}) && (tap.released & {.Space} != {}))
	testing.expect(t, !(tap.held & {.Space} != {}))
	for len(log.inputs) == ticks + 1 {
		ui.probe_frame(&probe)
	}
	testing.expect(t, !(last(&log).pressed & {.Space} != {})) // the next tick's edges are its own
}

@(test)
the_pointer_comes_back_in_the_games_units :: proc(t: ^testing.T) {
	log: Input_Log
	runner: Runner(Input_Log)
	runner_init(&runner, INPUT_LOG, &log)
	probe: ui.Probe
	// Twice the game's size: one game unit is two pixels, with no letterbox.
	ui.probe_init(&probe, runner_frame(Input_Log), &runner, {200, 100})
	defer ui.probe_destroy(&probe)

	ui.probe_click_at(&probe, {50, 40})
	clicked := false
	for input in log.inputs {
		if .Left in input.clicked {
			clicked = true
			testing.expect_value(t, input.pointer, [2]f32{25, 20})
		}
	}
	testing.expect(t, clicked)
	testing.expect(t, .Left in last(&log).unclicked || .Left not_in last(&log).buttons)
}

@(test)
the_letterbox_centres_the_game :: proc(t: ^testing.T) {
	_, covers := letterbox({100, 50}, {300, 300})
	testing.expect_value(t, covers, ops.Rect{0, 75, 300, 150})
}
