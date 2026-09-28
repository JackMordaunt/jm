package ui

import "core:os"
import "core:testing"

@(test)
test_debug_from_env_reads_jm_ui_debug :: proc(t: ^testing.T) {
	defer os.unset_env(DEBUG_ENV)
	os.unset_env(DEBUG_ENV)
	testing.expect_value(t, debug_from_env(), Debug_Flags{})
	os.set_env(DEBUG_ENV, "reveal")
	testing.expect_value(t, debug_from_env(), Debug_Flags{.Reveal})
	os.set_env(DEBUG_ENV, "Reveal, bounds,nonsense")
	testing.expect_value(t, debug_from_env(), Debug_Flags{.Reveal, .Bounds})
}

@(test)
test_probe_time_sums_dt_and_slow_quarters_it :: proc(t: ^testing.T) {
	Seen :: struct {
		dt:   f32,
		time: f64,
	}
	view :: proc(gtx: ^Ctx, user: rawptr) {
		(^Seen)(user)^ = {gtx.dt, gtx.time}
	}
	seen: Seen
	p: Probe
	probe_init(&p, view, &seen, {100, 100}) // runs the first frame
	defer probe_destroy(&p)
	probe_advance(&p, 3, 0.5)
	testing.expect_value(t, seen.dt, f32(0.5))
	testing.expect(t, abs(seen.time - (1.0 / 60 + 1.5)) < 1e-6) // f32 dt, summed in f64

	slow: Probe
	probe_init(&slow, view, &seen, {100, 100}, debug = {.Slow})
	defer probe_destroy(&slow)
	probe_advance(&slow, 2, 1)
	testing.expect_value(t, seen.dt, SLOW_FACTOR)
	testing.expect(t, abs(seen.time - f64(SLOW_FACTOR) * (1.0 / 60 + 2)) < 1e-6)
}
