package fluent

import "core:testing"
import "jm:ui"
import tok "jm:ui/fluent/tokens"
import "jm:ui/ops"

// Behaviour of the feedback group: what a badge, avatar, progress bar
// and spinner measure and show, through ui.Probe and direct calls.

@(private = "file")
Feedback_Model :: struct {
	badge, dot, hidden, avatar, bar, spin: ui.Dims,
	value:                                 f32,
	indeterminate:                         bool,
}

@(private = "file")
feedback :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Feedback_Model)(user)
	col := ui.column_open(gtx, gap = 16)
	defer ui.close(&col)
	m.badge = badge(gtx, "New")
	m.dot = counter_badge(gtx, 3, dot = true)
	m.hidden = counter_badge(gtx, 0)
	m.avatar = avatar(gtx, "Katri Ahokas", .S48, presence = true)
	m.bar = progress_bar(gtx, m.indeterminate ? -1 : m.value, width = 200, name = "bar")
	m.spin = spinner(gtx, "Loading", .Medium)
}

// bar_widths is the width of every round rect the frame filled at the
// progress bar's height: the track first, then the bar.
@(private = "file")
bar_widths :: proc(p: ^ui.Probe) -> [dynamic]f32 {
	out := make([dynamic]f32, context.temp_allocator)
	for op in p.scene.ops {
		if f, ok := op.(ops.Fill); ok {
			if rr, is_rr := f.shape.(ops.Round_Rect); is_rr && rr.rect.h == 2 {
				append(&out, rr.rect.w)
			}
		}
	}
	return out
}

@(test)
test_counter_text_caps_at_the_overflow :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	testing.expect_value(t, counter_text(5, 99), "5")
	testing.expect_value(t, counter_text(99, 99), "99")
	testing.expect_value(t, counter_text(105, 99), "99+")
	testing.expect_value(t, counter_text(1000, 999), "999+")
}

@(test)
test_initials_and_the_colorful_hash :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	testing.expect_value(t, initials("Katri Ahokas"), "KA")
	testing.expect_value(t, initials("Katri Ahokas", first_only = true), "K")
	testing.expect_value(t, initials("cher"), "C")
	testing.expect_value(t, initials("Ada  King Lovelace"), "AL")
	testing.expect_value(t, initials(""), "")
	// Colorful lands on a named colour and is stable per name.
	c := avatar_color(.Colorful, "Katri Ahokas")
	testing.expect(t, c >= .Dark_Red && c <= .Anchor)
	testing.expect_value(t, avatar_color(.Colorful, "Katri Ahokas"), c)
	testing.expect_value(t, avatar_color(.Teal, "Katri Ahokas"), Avatar_Color.Teal)
	// "a" is one unit, 97, at index 0: shift 0 leaves it 97, and 97 mod
	// the 30 colours is 7, Brass (useAvatar.tsx:233-241 at the kit's
	// commit, the hash avatar_color reimplements).
	testing.expect_value(t, avatar_color(.Colorful, "a"), Avatar_Color.Brass)
	testing.expect_value(t, avatar_roles(.Brass).bg, tok.Role.Palette_Brass_Background2)
}

// tagged reports whether the frame tagged an area name.
@(private = "file")
tagged :: proc(p: ^ui.Probe, name: string) -> bool {
	for op in p.scene.ops {
		if g, ok := op.(ops.Tag); ok && g.name == name {
			return true
		}
	}
	return false
}

@(test)
test_badge_avatar_and_spinner_measure_their_sizes :: proc(t: ^testing.T) {
	m := Feedback_Model{value = 0.5}
	p: ui.Probe
	ui.probe_init(&p, feedback, &m, {600, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect_value(t, m.badge.size.y, 20) // medium
	testing.expect(t, m.badge.size.x >= 20)
	testing.expect_value(t, m.dot.size, ops.Size{6, 6})
	testing.expect_value(t, m.hidden.size, ops.Size{}) // a zero count hides
	testing.expect_value(t, m.avatar.size, ops.Size{48, 48})
	testing.expect_value(t, m.bar.size, ops.Size{200, 2})
	testing.expect_value(t, m.spin.size.y, 32)
	testing.expect(t, m.spin.size.x > 32 + SPINNER_GAP) // the label after the ring
	// Tags: the badge by its text, the avatar by its name, the spinner by its label.
	testing.expect(t, tagged(&p, "New"))
	testing.expect(t, tagged(&p, "Katri Ahokas"))
	testing.expect(t, tagged(&p, "Loading"))
}

@(test)
test_progress_bar_follows_its_value_and_a_spinner_keeps_animating :: proc(t: ^testing.T) {
	m := Feedback_Model{value = 0.5}
	p: ui.Probe
	ui.probe_init(&p, feedback, &m, {600, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	ws := bar_widths(&p)
	testing.expect_value(t, len(ws), 2)
	testing.expect_value(t, ws[0], 200) // the track
	testing.expect_value(t, ws[1], 100) // the bar at 0.5, no transition on the first frame
	testing.expect(t, p.wants_frame) // the spinner spins every frame

	// A change eases over 300ms: half way through it is between.
	m.value = 1
	ui.probe_advance(&p, 1, 0.15)
	ws = bar_widths(&p)
	testing.expect(t, ws[1] > 100 && ws[1] < 200)
	ui.probe_advance(&p, 4, 0.1)
	testing.expect_value(t, bar_widths(&p)[1], 200)
	// A reset to 0 jumps.
	m.value = 0
	ui.probe_advance(&p, 1, 0.016)
	testing.expect_value(t, bar_widths(&p)[1], 0)

	// Indeterminate: a 33% segment that asks for frames.
	m.indeterminate = true
	ui.probe_advance(&p, 2, 0.016)
	testing.expect(t, p.wants_frame)
	ws = bar_widths(&p)
	testing.expect(t, len(ws) >= 2)
	testing.expect_value(t, ws[1], 66)
}
