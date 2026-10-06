package flow

import "core:sync"
import "core:testing"
import "core:time"

// Counting alone cannot tell "every item once" from "one item twice and another
// never", so each worker also sums the items it saw. The two together pin the run
// down: the count proves how many were handled and the sum proves which.
@(private = "file")
Tally :: struct {
	handled: int,
	sum:     int,
}

@(private = "file")
ITEMS :: 100_000

@(private = "file")
count_up :: proc(item: int, tally: ^Tally) -> bool {
	tally.handled += 1
	tally.sum += item
	return true
}

@(private = "file")
sequence :: proc() -> []int {
	items := make([]int, ITEMS, context.temp_allocator)
	for i in 0 ..< ITEMS {
		items[i] = i
	}
	return items
}

@(private = "file")
busy :: proc(tallies: []Tally) -> (n: int) {
	for tally in tallies {
		if tally.handled > 0 {
			n += 1
		}
	}
	return
}

@(private = "file")
totals :: proc(tallies: []Tally) -> (handled, sum: int) {
	for t in tallies {
		handled += t.handled
		sum += t.sum
	}
	return
}

@(test)
test_each_handles_every_item_exactly_once :: proc(t: ^testing.T) {
	tallies := make([]Tally, 8, context.temp_allocator)
	each(sequence(), tallies, count_up)

	handled, sum := totals(tallies)
	testing.expect_value(t, handled, ITEMS)
	testing.expect_value(t, sum, ITEMS * (ITEMS - 1) / 2)
}

/*
A meeting point that shows work was split without timing it: a worker that meets
waits there until a second worker has met too. Work kept on one worker never gets
past it, so the meeting is called off at a deadline and the test fails rather than
hanging; work that is split does, however loaded the machine and however late the
other workers start.
*/
@(private)
Meeting :: struct {
	arrived:    int, // atomic: workers that have met
	called_off: bool, // atomic: the deadline passed, and no one waits any more
}

// How long a worker waits at a meeting before the test gives up on the split.
@(private)
MEETING_LIMIT :: 30 * time.Second

// meet counts this worker in, the first time it calls, then waits for a second.
@(private)
meet :: proc(m: ^Meeting, met: ^bool) {
	if !met^ {
		met^ = true
		sync.atomic_add(&m.arrived, 1)
	}
	start := time.tick_now()
	for sync.atomic_load(&m.arrived) < 2 && !sync.atomic_load(&m.called_off) {
		if time.tick_since(start) > MEETING_LIMIT {
			sync.atomic_store(&m.called_off, true)
		}
		time.sleep(time.Millisecond)
	}
}

@(private = "file")
Share :: struct {
	meeting: ^Meeting,
	met:     bool,
	handled: int,
}

@(test)
test_each_shares_the_work_out :: proc(t: ^testing.T) {
	m: Meeting
	shares := make([]Share, 4, context.temp_allocator)
	for &s in shares {
		s.meeting = &m
	}
	each(make([]int, 32, context.temp_allocator), shares, proc(_: int, s: ^Share) -> bool {
		meet(s.meeting, &s.met)
		s.handled += 1
		return true
	})

	busy := 0
	for s in shares {
		busy += 1 if s.handled > 0 else 0
	}
	testing.expect(t, busy > 1, "work stayed on a single worker")
}

@(test)
test_each_with_one_slot_runs_inline :: proc(t: ^testing.T) {
	tallies := make([]Tally, 1, context.temp_allocator)
	each(sequence(), tallies, count_up)

	handled, sum := totals(tallies)
	testing.expect_value(t, handled, ITEMS)
	testing.expect_value(t, sum, ITEMS * (ITEMS - 1) / 2)
}

@(test)
test_each_stops_when_work_returns_false :: proc(t: ^testing.T) {
	// One slot keeps this deterministic: with several workers a few more items
	// finish after the decision to stop, which is the documented behaviour.
	tallies := make([]Tally, 1, context.temp_allocator)
	each(sequence(), tallies, proc(item: int, tally: ^Tally) -> bool {
		if item == 10 {
			return false
		}
		tally.handled += 1
		return true
	})
	testing.expect_value(t, tallies[0].handled, 10)
}

@(test)
test_each_stops_early_across_workers :: proc(t: ^testing.T) {
	tallies := make([]Tally, 8, context.temp_allocator)
	each(sequence(), tallies, proc(item: int, tally: ^Tally) -> bool {
		if item > 100 {
			return false
		}
		tally.handled += 1
		return true
	})

	handled, _ := totals(tallies)
	testing.expect(t, handled > 0, "no item was handled before the stop")
	testing.expect(t, handled < ITEMS, "stopping did not cut the run short")
}

@(test)
test_each_tolerates_empty_input :: proc(t: ^testing.T) {
	tallies := make([]Tally, 4, context.temp_allocator)
	each([]int{}, tallies, count_up)
	handled, _ := totals(tallies)
	testing.expect_value(t, handled, 0)

	// No slots means no worker can own state, so there is nothing to run on.
	each(sequence(), []Tally{}, count_up)
}

@(test)
test_width_never_exceeds_the_work :: proc(t: ^testing.T) {
	// However wide the machine, three items can only keep three workers busy.
	testing.expect_value(t, width(3, .Io), 3)
	testing.expect_value(t, width(1, .Io), 1)
	// No work still has to give a runnable answer rather than zero.
	testing.expect_value(t, width(0), 1)
}

@(test)
test_width_respects_the_limit :: proc(t: ^testing.T) {
	testing.expect_value(t, width(1000, .Io, limit = 4), 4)
	// The limit is a ceiling, not a target: fewer items still win.
	testing.expect_value(t, width(2, .Io, limit = 4), 2)
}

@(test)
test_width_grows_with_waiting :: proc(t: ^testing.T) {
	// Plenty of work, so the load is the only thing deciding the answer.
	cpu := width(10_000, .Cpu)
	mixed := width(10_000, .Mixed)
	io := width(10_000, .Io)
	testing.expect(t, cpu >= 1)
	testing.expect(t, mixed > cpu, "mixed work should outnumber cpu bound work")
	testing.expect(t, io > mixed, "waiting work should outnumber mixed work")
	// Derived from the core count, so a huge input cannot produce a huge width.
	testing.expect(t, io < 10_000, "width ran away with the input")
}

@(test)
test_each_ignores_a_pathological_width :: proc(t: ^testing.T) {
	// Asking for thousands of workers is a mistake, not an instruction. The run has
	// to stay correct and the pool has to stay within what the machine can use.
	tallies := make([]Tally, 4000, context.temp_allocator)
	each(sequence(), tallies, count_up)

	handled, sum := totals(tallies)
	testing.expect_value(t, handled, ITEMS)
	testing.expect_value(t, sum, ITEMS * (ITEMS - 1) / 2)
	testing.expect(
		t,
		busy(tallies) <= width(ITEMS, .Mixed),
		"the pool grew past the default ceiling",
	)
}

@(test)
test_each_caps_by_the_load_it_is_given :: proc(t: ^testing.T) {
	// Cpu is the narrowest tier, so it has to hold the pool below the default.
	tallies := make([]Tally, 4000, context.temp_allocator)
	each(sequence(), tallies, count_up, .Cpu)

	handled, _ := totals(tallies)
	testing.expect_value(t, handled, ITEMS)
	testing.expect(t, busy(tallies) <= width(ITEMS, .Cpu), "the load did not reach the ceiling")
}
