package fuzz

import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:sync"
import "core:testing"
import "core:time"

// Nothing is the subject for properties that do not need one.
Nothing :: struct {}

nothing_setup :: proc() -> (Nothing, bool) {return {}, true}

// fails_on_needle fails whenever the blob it drew holds 0xAB, which one byte
// of entropy is enough to do.
fails_on_needle :: proc(n: Nothing, src: ^Source) -> (string, bool) {
	b := bytes(src, 96)
	for c in b {
		if c == 0xAB {
			return "found 0xAB", false
		}
	}
	return "", true
}

always_holds :: proc(n: Nothing, src: ^Source) -> (string, bool) {
	_ = integer(src)
	return "", true
}

// Package level, because a Suite holds a slice, which has to outlive the
// call that hands the Suite back.
needle_properties := []Property(Nothing){{"needle", fails_on_needle}}
always_properties := []Property(Nothing){{"always", always_holds}}
spinner_properties := []Property(Spinner){{"spins", spins}}

needle_suite :: proc() -> Suite(Nothing) {
	return Suite(Nothing){name = "needle", setup = nothing_setup, properties = needle_properties}
}

@(test)
shrinking_reaches_the_small_case :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	r := run(needle_suite(), {seed = 1, iterations = 400, stop_on_first = true, entropy = 256})
	testing.expect(t, len(r.failures) == 1, "the needle must be found")
	if len(r.failures) == 0 {
		return
	}
	f := r.failures[0]
	// One byte of entropy is enough: the length is drawn from it and every
	// later draw wraps back to it.
	testing.expect_value(t, len(f.entropy), 1)
	testing.expect_value(t, f.entropy[0], 0xAB)
	testing.expect(t, f.shrunk_by > 0, "shrinking must have removed something")
}

@(test)
shrinking_can_be_turned_off :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	r := run(
		needle_suite(),
		{seed = 1, iterations = 400, stop_on_first = true, entropy = 256, shrink = -1},
	)
	testing.expect(t, len(r.failures) == 1, "the needle must still be found")
	if len(r.failures) == 0 {
		return
	}
	testing.expect_value(t, len(r.failures[0].entropy), 256)
	testing.expect_value(t, r.failures[0].shrunk_by, 0)
}

@(test)
same_seed_same_run :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	suite := Suite(Nothing) {
		name       = "always",
		setup      = nothing_setup,
		properties = always_properties,
	}
	first := run(suite, {seed = 42, iterations = 120})
	second := run(suite, {seed = 42, iterations = 120})
	// Absolute, so two equally empty reports cannot satisfy the comparison.
	testing.expect_value(t, first.iterations, 120)
	testing.expect(t, first.digest != 0, "a run that generated cases has a digest")
	testing.expect_value(t, first.digest, second.digest)

	other := run(suite, {seed = 43, iterations = 120})
	testing.expect(t, first.digest != other.digest, "two seeds must not agree")
}

@(test)
unset_seed_is_reported_and_replays :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	suite := Suite(Nothing) {
		name       = "always",
		setup      = nothing_setup,
		properties = always_properties,
	}
	r := run(suite, {iterations = 20})
	testing.expect(t, r.seed != 0, "the seed used must come back")
	replay := run(suite, {seed = r.seed, iterations = 20})
	testing.expect_value(t, replay.digest, r.digest)
}

@(test)
a_failure_becomes_a_regression :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	temp := os.temp_directory(context.temp_allocator) or_else ""
	dir, derr := os.make_directory_temp(temp, "jm-fuzz-corpus-*", context.temp_allocator)
	testing.expect(t, derr == nil)
	defer os.remove_all(dir)

	first := run(
		needle_suite(),
		{seed = 1, iterations = 400, stop_on_first = true, corpus_dir = dir},
	)
	testing.expect(t, len(first.failures) == 1, "the needle must be found")
	if len(first.failures) == 0 {
		return
	}
	saved := first.failures[0].saved
	testing.expect(t, saved != "", "the case must have been written")
	testing.expect(t, os.is_file(saved), "the case file must exist")
	testing.expect(
		t,
		strings.has_prefix(filepath.base(saved), "needle-"),
		"the file names the property it belongs to",
	)

	// A later run replays it before generating anything, so the bug found
	// once is checked from then on. A seed that finds nothing new still
	// fails on the regression.
	again := run(needle_suite(), {seed = 2, iterations = 2, corpus_dir = dir})
	testing.expect(t, again.replayed >= 1, "the saved case must be replayed first")
	testing.expect(t, len(again.failures) >= 1, "the regression must still fail")
	testing.expect_value(t, again.failures[0].property, "needle")
}

// Spinner is a subject that only stops when something cancels it, which is
// what a watchdog has to be able to do.
Spinner :: struct {
	stopped: ^bool,
}

spinner_setup :: proc() -> (Spinner, bool) {
	return Spinner{stopped = new(bool, context.allocator)}, true
}

spinner_cancel :: proc(s: Spinner) {
	sync.atomic_store(s.stopped, true)
}

spins :: proc(s: Spinner, src: ^Source) -> (string, bool) {
	// The backstop means a broken watchdog fails this test rather than
	// hanging the suite for ever.
	deadline := time.time_add(time.now(), 30 * time.Second)
	for !sync.atomic_load(s.stopped) {
		if time.since(deadline) > 0 {
			return "the watchdog never fired", false
		}
	}
	return "", true
}

@(test)
a_case_that_will_not_finish_is_cancelled :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	suite := Suite(Spinner) {
		name       = "spinner",
		setup      = spinner_setup,
		cancel     = spinner_cancel,
		properties = spinner_properties,
	}
	r := run(suite, {seed = 1, iterations = 1, case_timeout = 100 * time.Millisecond, shrink = -1})
	testing.expect_value(t, len(r.failures), 1)
	if len(r.failures) == 0 {
		return
	}
	testing.expect(t, r.failures[0].hung, "the case must be reported as a hang")
	testing.expect(
		t,
		strings.contains(r.failures[0].detail, "did not finish"),
		"the detail must say it was cut short",
	)
}

@(test)
a_source_of_zeroes_gives_the_simplest_values :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	zeros := make([]byte, 64)
	s := source(zeros)
	testing.expect_value(t, integer_in(&s, 3, 99), 3)
	testing.expect_value(t, boolean(&s), false)
	testing.expect_value(t, integer(&s), 0)
	testing.expect_value(t, real(&s), 0)
	testing.expect_value(t, len(bytes(&s, 40)), 0)
	testing.expect_value(t, text(&s, AWKWARD, 8), "")
	testing.expect_value(t, choice(&s, []int{7, 8, 9}), 7)

	// The simplest value of most of those is also the zero value of its
	// type, so a generator that ignored the source entirely would pass the
	// assertions above. These say the source is really being read.
	ones := make([]byte, 64)
	for i in 0 ..< len(ones) {
		ones[i] = 0xff
	}
	o := source(ones)
	testing.expect(t, integer_in(&o, 3, 99) != 3, "a full byte must not give lo")
	testing.expect(t, boolean(&o), "a full byte must give true")
	testing.expect(t, integer(&o) != 0, "a full byte must not give zero")
	testing.expect(t, len(bytes(&o, 40)) > 0, "a full byte must give a blob")
	testing.expect(t, text(&o, AWKWARD, 8) != "", "a full byte must give text")
	// Four items, because 255 %% 3 is 0 and would land back on the first.
	testing.expect(t, choice(&o, []int{7, 8, 9, 10}) != 7, "a full byte must not give the first")
	testing.expect_value(t, s.pos > 0, true)
}

@(test)
an_empty_source_still_draws :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	s := source(nil)
	testing.expect_value(t, byte_of(&s), 0)
	testing.expect_value(t, integer(&s), 0)
	testing.expect(t, s.wrapped, "an exhausted source says so")
}

@(test)
draws_stay_inside_their_range :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	// Every byte value, so no draw can land outside whatever it reads.
	all := make([]byte, 256)
	for i in 0 ..< 256 {
		all[i] = byte(i)
	}
	s := source(all)
	seen: map[int]bool
	for _ in 0 ..< 2000 {
		v := integer_in(&s, -5, 7)
		testing.expect(t, v >= -5 && v < 7, "integer_in must stay in [lo, hi)")
		seen[v] = true
	}
	// In range is not enough: a draw that ignored the source would also be
	// in range for ever. Every value in a twelve-wide span must come up.
	testing.expect_value(t, len(seen), 12)

	// A span wider than a byte takes eight of them, so the source has to be
	// long enough for 200 draws or it wraps and repeats itself.
	wide_bytes := make([]byte, 200 * 8)
	lcg := u32(12345)
	for i in 0 ..< len(wide_bytes) {
		lcg = lcg * 1103515245 + 12345
		wide_bytes[i] = byte(lcg >> 16)
	}
	s2 := source(wide_bytes)
	wide: map[int]bool
	for _ in 0 ..< 200 {
		v := integer_in(&s2, 0, 100_000)
		testing.expect(t, v >= 0 && v < 100_000, "a wide range must stay in bounds")
		wide[v] = true
	}
	testing.expect(t, len(wide) > 100, "a wide draw must vary with the source")
}

@(test)
damage_leaves_the_corpus_recognisable :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	corpus := [][]byte{transmute([]byte)string("hello world"), transmute([]byte)string("second")}

	// A zero source picks the first kind, which returns an entry unharmed.
	zeros := make([]byte, 64)
	z := source(zeros)
	out, how := damage(&z, corpus)
	testing.expect_value(t, how, Damage.None)
	testing.expect(t, slice.equal(out, corpus[0]), "None must hand the entry back")

	// With no corpus there is nothing to damage, so it is all noise.
	n := source(zeros)
	_, kind := damage(&n, nil)
	testing.expect_value(t, kind, Damage.Noise)

	// Every kind must be reachable and must not crash on any input.
	all := make([]byte, 4096)
	for i in 0 ..< len(all) {
		all[i] = byte(i * 7)
	}
	seen: [Damage]bool
	s := source(all)
	for _ in 0 ..< 3000 {
		_, k := damage(&s, corpus)
		seen[k] = true
	}
	for k in Damage {
		testing.expectf(t, seen[k], "damage never produced %v", k)
	}
}

@(test)
show_reads_back_as_text_or_hex :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	testing.expect(t, strings.contains(show("plain"), `"plain"`), "printable input shows as text")
	testing.expect(
		t,
		strings.contains(show([]byte{0x00, 0xff}), "00, ff"),
		"unprintable input shows as hex",
	)
	testing.expect(
		t,
		strings.contains(show("has\x00nul"), "6e, 75, 6c"),
		"a NUL makes text show as hex too",
	)
}
