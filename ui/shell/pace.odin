package shell

import "core:fmt"
import "core:math"
import "core:os"
import "core:strconv"

// ANIMATION_HZ is the rate animation-only frames are held to on a display
// that refreshes faster, unless App.animation_hz or ANIMATION_HZ_ENV says
// otherwise: a trial default, to be kept or dropped once compared.
ANIMATION_HZ :: 60

// ANIMATION_HZ_ENV is the environment variable that overrides
// App.animation_hz for a run: JM_UI_ANIMATION_HZ=0 lifts the cap,
// JM_UI_ANIMATION_HZ=60 sets it, so one binary can be tried both ways.
ANIMATION_HZ_ENV :: "JM_UI_ANIMATION_HZ"

// NS_PER_MS is a millisecond in SDL's ns ticks.
@(private)
NS_PER_MS :: 1_000_000

// Pacer holds the frames that only an animation asks for to a rate below
// a fast display's. A spring that moves every frame otherwise presents at
// the display's rate, 120 a second on a ProMotion panel; capped at 60 it
// presents half as often, and whether the motion looks the same is what
// the trial default is to settle. The ui steps its animations by real
// dt, so the motion covers the same ground in the same time either way.
//
// Frames that input causes are never held: a wait holds only the frame
// after a frame that took no event, and an event arriving during the
// wait ends it. The due times form a timeline a period apart, rather than
// each being a period after the frame that ran, so a wake that lands a
// millisecond late does not push every frame after it back.
@(private)
Pacer :: struct {
	hz:  f32, // animation-only frames a second at most; 0 for the display's own rate
	due: u64, // ticks, in ns, when the frame that last ran was due; 0 off the timeline
}

// pace is how long, in whole ms, the wait after a frame holds the next
// one: 0 when the cap is off, when the frame took input (quiet is false),
// or when the display refreshes no faster than the cap, which makes the
// cap a no-op on a 60 Hz display. start is when the frame that ran began
// and now is the present time, both in SDL's ns ticks; refresh_hz is the
// display's rate. A frame that ran off the timeline, before its due time
// or past its successor's, restarts the timeline from itself.
@(private)
pace :: proc(p: ^Pacer, start, now: u64, quiet: bool, refresh_hz: f32) -> i32 {
	if p.hz <= 0 || !quiet || math.round(refresh_hz) <= p.hz {
		p.due = 0
		return 0
	}
	period := u64(1e9 / f64(p.hz))
	next := p.due + period
	if p.due == 0 || start < p.due || next <= start {
		next = start + period
	}
	if next <= now {
		p.due = now
		return 0
	}
	p.due = next
	return i32((next - now + NS_PER_MS - 1) / NS_PER_MS)
}

// animation_hz is the cap a run uses: ANIMATION_HZ_ENV's number when the
// variable is set, else cfg, else ANIMATION_HZ. A value that is not a
// number is reported and ignored, so a typo leaves the app as configured.
@(private)
animation_hz :: proc(cfg: Maybe(f32)) -> f32 {
	buf: [64]u8
	if v := os.get_env(buf[:], ANIMATION_HZ_ENV); v != "" {
		if hz, ok := strconv.parse_f32(v); ok {
			return hz
		}
		fmt.eprintfln("shell: %s=%q is not a number; ignored", ANIMATION_HZ_ENV, v)
	}
	return cfg.? or_else ANIMATION_HZ
}
