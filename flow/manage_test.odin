package flow

import "core:sync"
import "core:thread"
import "core:testing"
import "core:time"

// A binary tree flattened into indices: node i holds 2i+1 and 2i+2. Walking it is
// the shape manage is for, since a worker only learns of a node by visiting its
// parent, and it is deterministic enough to check exactly.
@(private = "file")
NODES :: 20_000

@(private = "file")
Visit :: struct {
	seen:    [dynamic]int,
	found:   [dynamic]int,
	stop:    int, // visit this node and the run ends; -1 for never
	meeting: ^Meeting, // set, every node but the root waits there for a second worker
	met:     bool,
}

@(private = "file")
descend :: proc(item: int, v: ^Visit) -> bool {
	append(&v.seen, item)
	if item == v.stop {
		return false
	}
	for c in ([]int{2 * item + 1, 2 * item + 2}) {
		if c < NODES {
			append(&v.found, c)
		}
	}
	return true
}

@(private = "file")
hand_over :: proc(item: int, ok: bool, v: ^Visit, queue: ^[dynamic]int) -> bool {
	for c in v.found {
		append(queue, c)
	}
	clear(&v.found)
	return ok
}

/*
Worker states, each holding what its worker saw.

The dynamic arrays are deliberately not on the temp allocator. A dynamic array
remembers the allocator it was made with, and these are appended to from every
worker at once, so a per-thread arena belonging to whichever thread built them would
be grown from all of them without a lock. That miscounted a node roughly once in
twelve runs. `delete` them with `release`.
*/
@(private = "file")
visitors :: proc(n: int, stop := -1) -> []Visit {
	v := make([]Visit, n, context.temp_allocator)
	for i in 0 ..< n {
		v[i] = Visit {
			seen  = make([dynamic]int, context.allocator),
			found = make([dynamic]int, context.allocator),
			stop  = stop,
		}
	}
	return v
}

@(private = "file")
release :: proc(v: []Visit) {
	for s in v {
		delete(s.seen)
		delete(s.found)
	}
}

@(private = "file")
totals :: proc(v: []Visit) -> (count, sum: int) {
	for s in v {
		for i in s.seen {
			count += 1
			sum += i
		}
	}
	return
}

@(test)
test_manage_reaches_every_node_once :: proc(t: ^testing.T) {
	v := visitors(8)
	defer release(v)
	manage([]int{0}, v, descend, hand_over)

	// The count proves how many were visited and the sum proves which, so together
	// they rule out one node twice and another never.
	count, sum := totals(v)
	testing.expect_value(t, count, NODES)
	testing.expect_value(t, sum, NODES * (NODES - 1) / 2)
}

@(test)
test_manage_agrees_with_one_worker :: proc(t: ^testing.T) {
	// A single worker runs inline with no threads at all, which is the yardstick the
	// concurrent run has to match.
	one := visitors(1)
	defer release(one)
	manage([]int{0}, one, descend, hand_over)
	count, sum := totals(one)
	testing.expect_value(t, count, NODES)
	testing.expect_value(t, sum, NODES * (NODES - 1) / 2)
}

@(private = "file")
SPLIT :: 400

// The root waits for nothing: its children reach the queue only once it returns.
@(private = "file")
descend_meeting :: proc(item: int, v: ^Visit) -> bool {
	if item != 0 {
		meet(v.meeting, &v.met)
	}
	append(&v.seen, item)
	for c in ([]int{2 * item + 1, 2 * item + 2}) {
		if c < SPLIT {
			append(&v.found, c)
		}
	}
	return true
}

@(test)
test_manage_spreads_across_workers :: proc(t: ^testing.T) {
	m: Meeting
	v := visitors(4)
	defer release(v)
	for &s in v {
		s.meeting = &m
	}
	manage([]int{0}, v, descend_meeting, hand_over)

	count, sum := totals(v)
	testing.expect_value(t, count, SPLIT)
	testing.expect_value(t, sum, SPLIT * (SPLIT - 1) / 2)

	busy := 0
	for s in v {
		if len(s.seen) > 0 {
			busy += 1
		}
	}
	testing.expect(t, busy > 1, "the traversal stayed on a single worker")
}

@(test)
test_manage_stops_when_the_manager_returns_false :: proc(t: ^testing.T) {
	// One worker keeps this exact: with several, those already holding an item
	// finish it, which is the documented behaviour.
	one := visitors(1, stop = 0)
	defer release(one)
	manage([]int{0}, one, descend, hand_over)
	count, _ := totals(one)
	testing.expect_value(t, count, 1)
}

@(test)
test_manage_tolerates_an_empty_seed :: proc(t: ^testing.T) {
	v := visitors(4)
	defer release(v)
	manage([]int{}, v, descend, hand_over)
	count, _ := totals(v)
	testing.expect_value(t, count, 0)
}

// A failed item is the manager's to judge, and the judgement it cannot make without
// being told which item failed is to try that one again.
@(private = "file")
Attempt :: struct {
	id:    int,
	tries: int,
}

@(private = "file")
Attempt_Log :: struct {
	seen: [dynamic]Attempt,
}

@(private = "file")
refuse_twice :: proc(item: Attempt, f: ^Attempt_Log) -> bool {
	append(&f.seen, item)
	return !(item.id == 1 && item.tries < 2)
}

@(private = "file")
retry :: proc(item: Attempt, ok: bool, f: ^Attempt_Log, queue: ^[dynamic]Attempt) -> bool {
	if !ok {
		append(queue, Attempt{id = item.id, tries = item.tries + 1})
	}
	return true
}

@(test)
test_manage_requeues_a_failed_item :: proc(t: ^testing.T) {
	// One worker keeps the count exact; the point is the shape, not the width.
	f := make([]Attempt_Log, 1, context.temp_allocator)
	f[0].seen = make([dynamic]Attempt, context.temp_allocator)
	seed := []Attempt{{id = 0}, {id = 1}, {id = 2}}
	manage(seed, f, refuse_twice, retry)

	// Three items, one of them attempted three times, and the run carried on past
	// the failures rather than ending at the first.
	testing.expect_value(t, len(f[0].seen), 5)
	tries := 0
	for a in f[0].seen {
		if a.id == 1 {
			tries += 1
		}
	}
	testing.expect_value(t, tries, 3)
}

// A tree as wide as a directory full of directories: node i queues FAN children,
// FAN*i+1 through FAN*i+FAN, below FAN_NODES. Each worker counts and sums what it
// saw, and what it queued, so a run can be balanced against itself.
@(private = "file")
FAN :: 16

@(private = "file")
FAN_NODES :: 50_000

// More workers than any one item queues children, so most of them sleep at once and
// contend for each item queued.
@(private = "file")
FAN_WORKERS :: 64

@(private = "file")
Fan :: struct {
	count:  int,
	sum:    int,
	queued: int, // children this worker's manager calls queued, seed not counted
	queued_sum: int, // the sum of those children
	found:  [dynamic]int,
	stop:   int, // working this node ends the run; -1 for never
}

// Set once the node that stops the run has been worked. The other workers wait
// for it, so the stop lands with the root's children still queued however the
// scheduler orders the workers: left to run, a worker that gets node 1 late
// finds the rest of the tree already worked.
@(private = "file")
fan_stopped: bool // atomic

@(private = "file")
fan_out :: proc(item: int, f: ^Fan) -> bool {
	if f.stop >= 0 && item != 0 && item != f.stop {
		// Bounded, so a broken manager fails the test instead of hanging it.
		deadline := time.tick_add(time.tick_now(), 5 * time.Second)
		for !sync.atomic_load(&fan_stopped) && time.tick_diff(time.tick_now(), deadline) > 0 {
			thread.yield()
		}
	}
	f.count += 1
	f.sum += item
	if item == f.stop {
		sync.atomic_store(&fan_stopped, true)
		return false
	}
	for c in FAN * item + 1 ..= FAN * item + FAN {
		if c < FAN_NODES {
			append(&f.found, c)
		}
	}
	return true
}

@(private = "file")
fan_hand_over :: proc(item: int, ok: bool, f: ^Fan, queue: ^[dynamic]int) -> bool {
	for c in f.found {
		append(queue, c)
		f.queued_sum += c
	}
	f.queued += len(f.found)
	clear(&f.found)
	return ok
}

@(private = "file")
fans :: proc(n: int, stop := -1) -> []Fan {
	f := make([]Fan, n, context.temp_allocator)
	for &s in f {
		s.found = make([dynamic]int, context.allocator)
		s.stop = stop
	}
	return f
}

@(private = "file")
fan_release :: proc(f: []Fan) {
	for s in f {
		delete(s.found)
	}
}

@(private = "file")
fan_totals :: proc(f: []Fan) -> (count, sum, queued, queued_sum: int) {
	for s in f {
		count += s.count
		sum += s.sum
		queued += s.queued
		queued_sum += s.queued_sum
	}
	return
}

// What `discard` saw, per test, since it is handed nothing but the item.
@(private = "file")
Discards :: struct {
	count: int, // atomic
	sum:   int, // atomic
}

@(private = "file")
fan_discards: Discards

@(private = "file")
stop_discards: Discards

@(private = "file")
discard_fan :: proc(item: int) {
	sync.atomic_add(&fan_discards.count, 1)
}

@(private = "file")
discard_stopped :: proc(item: int) {
	sync.atomic_add(&stop_discards.count, 1)
	sync.atomic_add(&stop_discards.sum, item)
}

@(test)
test_manage_fans_out_to_every_node_once :: proc(t: ^testing.T) {
	// Repeated, since a lost wakeup shows as a hang only on some interleavings, and a
	// woken worker finding its item already taken only under contention.
	for _ in 0 ..< 10 {
		f := fans(FAN_WORKERS)
		manage([]int{0}, f, fan_out, fan_hand_over, discard_fan)
		count, sum, queued, _ := fan_totals(f)
		fan_release(f)
		testing.expect_value(t, count, FAN_NODES)
		testing.expect_value(t, sum, FAN_NODES * (FAN_NODES - 1) / 2)
		testing.expect_value(t, queued, FAN_NODES - 1)
	}
	testing.expect_value(t, sync.atomic_load(&fan_discards.count), 0)
}

@(test)
test_manage_discards_what_a_stopped_run_left_queued :: proc(t: ^testing.T) {
	// Node 1 is among the root's first children, so the run ends with nearly the
	// whole tree still to come and most of the root's children still queued.
	sync.atomic_store(&fan_stopped, false)
	f := fans(FAN_WORKERS, stop = 1)
	defer fan_release(f)
	manage([]int{0}, f, fan_out, fan_hand_over, discard_stopped)
	count, sum, queued, queued_sum := fan_totals(f)

	// Every item queued, the seed with them, reached `work` or `discard`, and the
	// sums show none reached both: an item worked and discarded would count twice
	// while another went missing, and the sums would not agree. Which nodes were
	// worked, and so which were queued, depends on how the workers interleave:
	// the sum to match is of the items queued, the seed with them.
	discarded := sync.atomic_load(&stop_discards.count)
	testing.expect_value(t, count + discarded, queued + 1)
	testing.expect_value(t, sum + sync.atomic_load(&stop_discards.sum), queued_sum)
	testing.expect(t, count >= 2, "a run ended before working the seed and the node that stops it")
	testing.expect(t, discarded > 0, "a run stopped early discarded nothing")
	testing.expect(t, count < FAN_NODES, "a stopped run kept going")
}

@(private = "file")
Calls :: struct {
	count: int,
}

@(private = "file")
do_nothing :: proc(item: int, s: ^Calls) -> bool {
	s.count += 1
	return true
}

@(private = "file")
queue_nothing :: proc(item: int, ok: bool, s: ^Calls, queue: ^[dynamic]int) -> bool {
	return true
}

@(test)
test_manage_ends_when_a_wide_seed_spawns_nothing :: proc(t: ^testing.T) {
	// Every worker but those given a seed item finds the queue empty and sleeps; the
	// last item finished has to wake them all to leave, or this test never returns.
	for round in 0 ..< 100 {
		s := make([]Calls, FAN_WORKERS, context.temp_allocator)
		seed := []int{0, 1, 2}
		manage(seed[:1 + round % 3], s, do_nothing, queue_nothing)
		n := 0
		for w in s {
			n += w.count
		}
		testing.expect_value(t, n, 1 + round % 3)
	}
}
