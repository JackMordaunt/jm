package flow

import "core:sync"
import "core:thread"

/*
Run work over a set that grows as the work discovers more of it.

`seed` starts the queue; every later item arrives through `manager`, which runs one
at a time. `work` runs on many threads at once, taking the next item the moment one
exists rather than in rounds.

Each worker owns one slot of `states`, so `work` needs no locks, exactly as in `each`.
`manager` sees that slot beside the item that filled it, and queues whatever comes
next, that item included.

`work` returning false marks the item failed, not the run. `manager` returning false
ends the run; workers finish the item in hand and report through their state.

Every item reaches `work` or `discard`, never both and never neither. A stopped run
leaves items queued that nothing else can reach, so an item owning memory needs
`discard` to release it.

`len(states)` sets the width, capped by what the machine can use.
*/
manage :: proc(
	seed: []$I,
	states: []$S,
	work: proc(item: I, state: ^S) -> bool,
	manager: proc(item: I, ok: bool, state: ^S, queue: ^[dynamic]I) -> bool,
	discard: proc(item: I) = nil,
	load := Load.Io,
) {
	if len(seed) == 0 || len(states) == 0 {
		return
	}
	q: Queue(I, S)
	q.states = states
	q.work = work
	q.manager = manager
	q.items = make([dynamic]I, context.allocator)
	defer delete(q.items)
	// Runs before the delete above, while the queue still holds what was never taken.
	defer sweep(&q, discard)
	append(&q.items, ..seed)

	pool := min(len(states), width(1 << 30, load))
	if pool == 1 {
		drain(&q, 0)
		return
	}

	threads := make([]^thread.Thread, pool - 1, context.temp_allocator)
	defer delete(threads, context.temp_allocator)
	started := 0
	for i in 0 ..< len(threads) {
		t := thread.create_and_start_with_poly_data(Hand(I, S){&q, i + 1}, hand_entry)
		if t == nil {
			break
		}
		threads[i] = t
		started += 1
	}
	drain(&q, 0)
	thread.join_multiple(..threads[:started])
	for t in threads[:started] {
		thread.destroy(t)
	}
}

// Release what the run never took, once every worker has stopped.
@(private)
sweep :: proc(q: ^Queue($I, $S), discard: proc(item: I)) {
	if discard == nil {
		return
	}
	for item in q.items[q.head:] {
		discard(item)
	}
	q.head = len(q.items)
}

@(private)
Queue :: struct($I: typeid, $S: typeid) {
	items:   [dynamic]I,
	head:    int,
	active:  int, // workers holding an item, which may yet produce more
	idle:    int, // workers asleep in `wake`, the most a signal can rouse
	over:    bool,
	mutex:   sync.Mutex,
	wake:    sync.Cond,
	states:  []S,
	work:    proc(item: I, state: ^S) -> bool,
	manager: proc(item: I, ok: bool, state: ^S, queue: ^[dynamic]I) -> bool,
}

@(private)
Hand :: struct($I: typeid, $S: typeid) {
	queue: ^Queue(I, S),
	index: int,
}

@(private)
hand_entry :: proc(h: Hand($I, $S)) {
	drain(h.queue, h.index)
}

/*
Take items until the run is over, handing each to `work` and then to `manager`.

A worker wakes only as many sleepers as it queued items for, less the one it takes
itself, and never more than are asleep. Broadcasting after every item instead woke
every idle worker for an item only one of them could take, and sent the rest back
to sleep.

Holding the lock from `manager` straight into taking the next item saves a second
round trip through it per item, and means the worker that found more work is the
first to start on it, with no wakeup at all.

Nothing can be stranded by waking too few. A worker sleeps only on an empty queue,
and whoever fills it again is awake and comes back for more until it is empty, so
a signal decides only how soon an item starts, never whether. A signal whose item
was taken first is harmless: the sleeper finds the queue empty and sleeps again,
and since the wait rechecks the queue in a loop, a spurious wakeup does the same.

The broadcasts stay where every sleeper must act: when the run is over, whether
`manager` ended it or the last item finished with nothing queued, each must wake to
leave.
*/
@(private)
drain :: proc(q: ^Queue($I, $S), index: int) {
	state := &q.states[index]
	sync.mutex_lock(&q.mutex)
	for {
		// Wait while the queue is empty but someone still holds an item, since that
		// worker may yet discover more. Empty with nobody working means finished.
		for q.head >= len(q.items) && q.active > 0 && !q.over {
			q.idle += 1
			sync.cond_wait(&q.wake, &q.mutex)
			q.idle -= 1
		}
		if q.over || q.head >= len(q.items) {
			q.over = true
			if q.idle > 0 {
				sync.cond_broadcast(&q.wake)
			}
			sync.mutex_unlock(&q.mutex)
			return
		}
		item := q.items[q.head]
		q.head += 1
		q.active += 1
		// Reclaim the consumed prefix once it dominates, or a deep traversal keeps
		// every item it has ever seen.
		if q.head > 1024 && q.head * 2 > len(q.items) {
			n := copy(q.items[:], q.items[q.head:])
			resize(&q.items, n)
			q.head = 0
		}
		sync.mutex_unlock(&q.mutex)

		ok := q.work(item, state)

		sync.mutex_lock(&q.mutex)
		q.active -= 1
		queued := len(q.items)
		// The manager runs for a failed item too: deciding what a failure means is
		// the whole of its job.
		if !q.manager(item, ok, state, &q.items) {
			q.over = true
			continue // the top of the loop wakes everyone to leave
		}
		// This worker takes one of what it queued at the top of the loop; the rest
		// are for sleepers.
		rouse := min(len(q.items) - queued - 1, q.idle)
		for _ in 0 ..< rouse {
			sync.cond_signal(&q.wake)
		}
	}
}
