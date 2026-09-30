package ui

import "base:sanitizer"
import "core:os"
import jdebug "jm:debug"
import "jm:ui/ops"
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

@(test)
test_frame_memory_kept_past_its_frame_reads_as_poison :: proc(t: ^testing.T) {
	when !ops.POISON_FRAMES {
		return
	}
	// A view that keeps a frame-allocated string in its model: the bug
	// poisoning exists to make loud.
	Model :: struct {
		kept: string,
	}
	view :: proc(gtx: ^Ctx, user: rawptr) {
		m := (^Model)(user)
		if m.kept == "" {
			buf := make([]u8, 4, gtx.allocator)
			copy(buf, "kept")
			m.kept = string(buf)
		}
	}
	m: Model
	p: Probe
	probe_init(&p, view, &m, {10, 10}) // the first frame keeps the string
	defer probe_destroy(&p)
	testing.expect_value(t, m.kept, "kept")
	probe_frame(&p) // resets the arena the string was in
	if jdebug.ASAN {
		// Reading it would trap, which is the point.
		testing.expect(t, sanitizer.address_is_poisoned(raw_data(m.kept)))
		return
	}
	for b in transmute([]u8)m.kept {
		testing.expect_value(t, b, u8(ops.FRAME_POISON))
	}
}

@(test)
test_f11_toggles_debug_and_never_reaches_a_widget :: proc(t: ^testing.T) {
	Seen :: struct {
		debug: Debug_Flags,
		keys:  int,
	}
	view :: proc(gtx: ^Ctx, user: rawptr) {
		s := (^Seen)(user)
		s.debug = gtx.debug
		for e in gtx.router.events {
			if e.kind == .Key {
				s.keys += 1
			}
		}
	}
	seen: Seen
	p: Probe
	probe_init(&p, view, &seen, {10, 10}, debug = {.Slow})
	defer probe_destroy(&p)
	probe_key(&p, .F11)
	testing.expect_value(t, seen.debug, Debug_Flags{.Slow} + DEBUG_TOGGLE)
	probe_key(&p, .F11)
	testing.expect_value(t, seen.debug, Debug_Flags{.Slow})
	testing.expect_value(t, seen.keys, 0)
}
