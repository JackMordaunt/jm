/*
Package stream builds a pipeline of stages as a DAG and runs it without blocking.

A stage is a node. It runs only when something changed at one of its edges, and a
run never blocks: it drains what it can and yields. That is why there is no select
and no thread per stage. Blocking belongs at the edges of the pipeline, in a thread
that feeds a port, or in a sink such as a frame.

	Pipeline   owns the nodes, the edges, the timers and the ready queue
	Edge       a bounded ring from one node to one node, one producer, one consumer
	Inlet      the same, fed from any thread; how completions and ports arrive
	Node       a run proc, its state, its edges, its timer, and a schedule flag
	Stream(T)  a typed handle to a node's output, what the operators build on
	Workers    threads that run blocking work and report through an inlet

A node observes five things: a message on an input, an input ending, an output
cancelled, its timer firing, and a message on an inlet. It does six: emit, keep
state, close its outputs by yielding Done, cancel an input by finishing, arm a
timer, and submit work. Every operator is some machine over those symbols.

`run(p, threads)` drives the pipeline until it is quiescent, on the calling thread
plus that many more. A node's schedule flag keeps it on one thread at a time, so
node state needs no locks and an edge needs only its two indices to be atomic.
`drain` runs what is ready now on this thread; `step` runs one node, so a test
walks a pipeline deterministically.

The scheduler is built for throughput, and `just stream-bench` prints what a
stage hop costs on the machine at hand. A node's consumers are woken when its
run ends, not per message, so a run of pushes costs one wake. The consumer woken last goes into the
worker's own slot and runs next on the same thread, warm in cache and without
the shared queue; a node that spent its budget goes to the back of the shared
queue instead, so another worker may take it. A worker with nothing to do spins
briefly before it sleeps, and a wake reaches the lock only when someone is
asleep. The price is ordering: with more than one thread, which ready node runs
next is not the order they became ready, and `step` is the only driver that
promises queue order.

Back pressure is a full edge: the producer parks on it and the consumer wakes it
when it pops. Bounded edges have one consequence: a stage that waits on a
particular input, which is zip, deadlocks when the same source reaches it along
two paths of different rate, directly and through a filter say. The source parks
on the full path while zip waits on the other. The structure is known when the
graph is built, so `connect` refuses it: a node that `waits` may not take two
inputs that share an ancestor unless every stage on both paths is `one_to_one`.
Merge never waits on one input, so it is safe to fan into.

A node can be pinned to a thread of the caller's choosing: a texture upload
that must happen on the render thread, a sink that writes what a frame
reads. `run` never runs a pinned node; it waits, and the owning thread runs
what is ready of them with `drain_pinned`, once a frame say. `p.wake` is
called when a pinned node becomes ready, so that thread can be told. `step`
and `drain` run pinned nodes too, since the one thread driving is the owner.

With CHECK_YIELDS on, which it is in debug and test builds, a
single-threaded `step` verifies each yield against the edges, and `run` fails a
pipeline that went quiet with a node unfinished, instead of hanging silently.
*/
package stream

import "base:intrinsics"
import "core:container/priority_queue"
import "core:container/queue"
import "core:fmt"
import "core:mem"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"

import "jm:stream/ring"

// Messages one run of a node handles before it yields, so a hot node cannot
// starve the rest.
BUDGET :: 64

// Messages an edge holds before its producer parks.
DEFAULT_CAP :: 16

// `run` with this many threads picks the count itself: three at most, and no
// more than the graph can use. The cap comes from `stream-bench crossover` on
// the 24-core desktop this was developed on, where three threads were never
// worse than one by more than a fifth with no work in the stages and two to
// three times better once a stage cost fifty nanoseconds, while more threads
// paid only from two hundred nanoseconds a stage and never beyond the number of
// nodes. Another machine moves those points; pass a count for a pipeline
// whose stages do real work.
AUTO :: -1

// How many times a worker with nothing to do polls the shared queue before it
// sleeps. The assumption behind it: a consumer that drained and went idle is
// often woken again by its producer's next push sooner than a sleeping worker
// could be roused, so a few hundred polls are cheaper than a sleep and a wake.
// The fanout8 shape in tools/stream-bench is where that showed.
SPIN :: 400

// How many workers may spin at once. More than this and they fight over the
// lock they take on the way to sleep.
SPINNERS :: 2

// Verify yields and quiescence. -define:STREAM_CHECK_YIELDS=false turns it off.
CHECK_YIELDS :: #config(STREAM_CHECK_YIELDS, ODIN_DEBUG || ODIN_TEST)

Node_Id :: distinct int

// The typed handle to a node's output.
Stream :: struct($T: typeid) {
	p:    ^Pipeline,
	node: Node_Id,
}

// A zipped pair.
Pair :: struct($A, $B: typeid) {
	first:  A,
	second: B,
}

// Where a node is in the scheduler. The two Running states let a wake that
// lands mid-run queue the node again instead of being lost.
Sched :: enum u8 {
	Idle,
	Scheduled,
	Running,
	Running_Again,
}

// Why a run ended.
Yield :: enum u8 {
	Drained, // nothing to do until an input, inlet or timer changes
	Budget, // more to do, let others run first
	Blocked, // an out edge is full, the node is parked on it
	Done, // the node will never emit again
}

// ---------------------------------------------------------------------------
// Clock
// ---------------------------------------------------------------------------

// Where the pipeline reads time. A manual clock never sleeps: `run` returns when
// nothing is ready and the test advances it. The pipeline keeps a copy, and
// `data` points at whatever the copy's `now` needs, the caller's Manual_Clock
// say, which the caller keeps alive for the run.
Clock :: struct {
	now:    proc(c: ^Clock) -> time.Duration,
	manual: bool,
	data:   rawptr,
}

real_clock := Clock {
	now = real_now,
}

@(private)
real_now :: proc(c: ^Clock) -> time.Duration {
	return time.tick_diff(time.Tick{}, time.tick_now())
}

Manual_Clock :: struct {
	using clock: Clock,
	t:           time.Duration,
}

manual_clock :: proc() -> Manual_Clock {
	return {clock = {now = manual_now, manual = true}}
}

@(private)
manual_now :: proc(c: ^Clock) -> time.Duration {
	return time.Duration(sync.atomic_load(&(^Manual_Clock)(c.data).t))
}

// Move a manual clock. Call it between runs, not while one is in progress.
advance :: proc(c: ^Manual_Clock, d: time.Duration) {
	sync.atomic_store(&c.t, c.t + d)
}

@(private)
Timer :: struct {
	at:  time.Duration,
	seq: u64,
	n:   ^Node,
}

@(private)
timer_less :: proc(a, b: Timer) -> bool {
	return a.at < b.at
}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

// One producer, one consumer, over a ring from jm:stream/ring that keeps the
// two ends on their own cache lines. The flags are placed the same way: what
// the consumer touches per pop sits apart from what the producer touches per
// push, and the write-once flags sit with the side that reads them.
Edge :: struct {
	using buffer: ring.Raw,
	// The consumer's: cleared on every pop; set by the producer only when it
	// blocks. `closed` is set once by the producer and read here when empty.
	parked:       bool,
	closed:       bool,
	_pad3:        [ring.LINE]u8,
	// The producer's: set on every push, cleared when its run ends.
	// `cancelled` is set once by the consumer and read here on every emit.
	dirty:        bool,
	cancelled:    bool,
	_pad4:        [ring.LINE]u8,
	from, to:     ^Node,
}

// An edge any thread may push into: the same ring, under a mutex that covers
// it and `closed`, with a condition for a sender waiting on room.
Inlet :: struct {
	p:            ^Pipeline,
	n:            ^Node,
	mutex:        sync.Mutex,
	space:        sync.Cond,
	using buffer: ring.Raw,
	closed:       bool,
}

Node :: struct {
	p:          ^Pipeline,
	id:         Node_Id,
	name:       string,
	run:        proc(n: ^Node) -> Yield,
	cleanup:    proc(n: ^Node), // runs at destroy, before the state is freed
	// Emits exactly one message per message in, so two paths through such
	// nodes from one source stay in step. False for anything that drops,
	// expands or ends early.
	one_to_one: bool,
	// Waits for a message on one particular input while others may be full,
	// as zip does. `connect` checks such a node's inputs for a shared source.
	waits:      bool,
	// Runs only in drain_pinned, step or drain, never on a pool thread.
	pinned:     bool,
	state:      rawptr,
	state_size: int,
	ins:        [dynamic]^Edge,
	outs:       [dynamic]^Edge,
	inlets:     [dynamic]^Inlet,
	parked:     bool, // set by block, read and cleared by the thread running the node
	runs:       int,
	// Other threads CAS `sched` on every wake, so it shares no line with what
	// the running node reads.
	_pad0:      [64]u8,
	sched:      Sched, // atomic
	done:       bool, // atomic
	_pad1:      [64]u8,
	// Timer, under Pipeline.timer_mutex: one deadline per node, and `seq` tells
	// a stale heap entry apart.
	armed:      bool,
	deadline:   time.Duration,
	timer_seq:  u64,
	fired:      bool,
}

Pipeline :: struct {
	allocator:   mem.Allocator,
	cap:         int,
	clock:       Clock,
	nodes:       [dynamic]^Node,
	edges:       [dynamic]^Edge,
	inlets:      [dynamic]^Inlet,
	started:     bool, // atomic: start has queued the sources
	// The shared ready queue and what a worker needs to decide it can stop,
	// all under `mutex`. A worker touches it only when its own slot is empty.
	// `more` wakes an idle worker, and is signalled only when one exists.
	mutex:       sync.Mutex,
	more:        sync.Cond,
	ready:       queue.Queue(^Node),
	ready_count: int, // atomic mirror of queue.len(ready), for a spinner's glance
	pinned:      queue.Queue(^Node), // ready pinned nodes, for drain_pinned; under `mutex`
	// Called, from whichever thread made it so, when the pinned queue goes
	// from empty to not: how a frame loop learns it has a node to run.
	wake:        proc(data: rawptr),
	wake_data:   rawptr,
	active:      int, // workers running or holding a node
	sleeping:    int, // workers waiting on `more`
	spinning:    int, // workers polling before they sleep; at most SPINNERS
	open_inlets: int,
	quit:        bool, // atomic, written under `mutex`
	quiescent:   bool, // quit because nothing could happen, not because of stop
	workers:     int, // threads in the current run besides the caller
	// Timers under their own mutex, taken after `mutex` and never before it.
	// `armed` is also read atomically outside it, to skip the lock when zero.
	timer_mutex: sync.Mutex,
	timers:      priority_queue.Priority_Queue(Timer),
	armed:       int,
	// Pick which ready node runs next. nil runs them in order; a fuzz driver
	// draws one at random to stand in for a pool's interleaving. Only for a
	// single-threaded run.
	choose:      proc(data: rawptr, count: int) -> int,
	choose_data: rawptr,
}

// Build a pipeline whose nodes, edges and queues live in `allocator`.
make_pipeline :: proc(
	allocator: mem.Allocator,
	cap := DEFAULT_CAP,
	clock: ^Clock = nil,
) -> (
	p: ^Pipeline,
) {
	p = new(Pipeline, allocator)
	p.allocator = allocator
	p.cap = cap
	p.clock = clock^ if clock != nil else real_clock
	if p.clock.manual && p.clock.data == nil {
		p.clock.data = clock // the caller's Manual_Clock, whose first field this is
	}
	p.nodes = make([dynamic]^Node, allocator)
	p.edges = make([dynamic]^Edge, allocator)
	p.inlets = make([dynamic]^Inlet, allocator)
	queue.init(&p.ready, 16, allocator)
	queue.init(&p.pinned, 4, allocator)
	priority_queue.init(
		&p.timers,
		timer_less,
		priority_queue.default_swap_proc(Timer),
		16,
		allocator,
	)
	return
}

// Free everything. Stop any thread that feeds an inlet first.
destroy :: proc(p: ^Pipeline) {
	for n in p.nodes {
		if n.cleanup != nil {
			n->cleanup()
		}
	}
	for e in p.edges {
		ring.destroy(&e.buffer, p.allocator)
		free(e, p.allocator)
	}
	for inlet in p.inlets {
		ring.destroy(&inlet.buffer, p.allocator)
		free(inlet, p.allocator)
	}
	for n in p.nodes {
		delete(n.ins)
		delete(n.outs)
		delete(n.inlets)
		if n.state != nil {
			mem.free_with_size(n.state, n.state_size, p.allocator)
		}
		free(n, p.allocator)
	}
	delete(p.nodes)
	delete(p.edges)
	delete(p.inlets)
	queue.destroy(&p.ready)
	queue.destroy(&p.pinned)
	priority_queue.destroy(&p.timers)
	free(p, p.allocator)
}

// Add a node that runs `run` over `state`; the pipeline owns the state copy.
add_node :: proc(p: ^Pipeline, name: string, run: proc(n: ^Node) -> Yield, state: $S) -> ^Node {
	n := new(Node, p.allocator)
	n.p = p
	n.id = Node_Id(len(p.nodes))
	n.name = name
	n.run = run
	n.ins = make([dynamic]^Edge, p.allocator)
	n.outs = make([dynamic]^Edge, p.allocator)
	n.inlets = make([dynamic]^Inlet, p.allocator)
	when size_of(S) > 0 {
		s := new(S, p.allocator)
		s^ = state
		n.state = s
		n.state_size = size_of(S)
	}
	append(&p.nodes, n)
	return n
}

// Wire an edge carrying messages of `shape` from node `from` to `to`. A node
// emits one value to every out, so the shape must match the node's other outs:
// see `out_shape`. Panics too when `to` waits on its inputs and this one shares
// a source with an earlier input across a stage that changes the message
// count, since that graph deadlocks on bounded edges: see `shared_source`.
connect :: proc(p: ^Pipeline, from: Node_Id, to: ^Node, shape: ring.Shape) -> ^Edge {
	if want, ok := out_shape(node_at(p, from), shape); !ok {
		fmt.panicf(
			"stream: %s#%d emits %v, so an edge to %s#%d cannot carry %v",
			node_at(p, from).name,
			int(from),
			want.id,
			to.name,
			int(to.id),
			shape.id,
		)
	}
	if to.waits && len(to.ins) > 0 {
		if shared, blame, ii, ok := shared_source(p, to, node_at(p, from)); !ok {
			fmt.panicf(
				"stream: %s#%d takes %s#%d beside its input %d, and both descend from %s#%d through %s#%d, which changes the count; the source would park on one side while %s waits on the other. Zip streams from different sources, or keep every stage between one-in-one-out",
				to.name,
				int(to.id),
				node_at(p, from).name,
				int(from),
				ii,
				shared.name,
				int(shared.id),
				blame.name,
				int(blame.id),
				to.name,
			)
		}
	}
	e := new(Edge, p.allocator)
	ring.init(&e.buffer, p.cap, shape, p.allocator)
	e.from = node_at(p, from)
	e.to = to
	append(&e.from.outs, e)
	append(&to.ins, e)
	append(&p.edges, e)
	return e
}

// What `from` emits, from its existing outs, and whether `shape` agrees with
// it. A node with no outs yet agrees with anything.
out_shape :: proc(from: ^Node, shape: ring.Shape) -> (want: ring.Shape, ok: bool) {
	if len(from.outs) == 0 {
		return shape, true
	}
	want = from.outs[0].shape
	return want, want == shape
}

// Give `to` an inlet other threads push into. Zero `cap` takes the pipeline's.
add_inlet :: proc(p: ^Pipeline, to: ^Node, shape: ring.Shape, cap := 0) -> ^Inlet {
	inlet := new(Inlet, p.allocator)
	inlet.p = p
	inlet.n = to
	ring.init(&inlet.buffer, cap if cap > 0 else p.cap, shape, p.allocator)
	append(&to.inlets, inlet)
	append(&p.inlets, inlet)
	sync.mutex_lock(&p.mutex)
	p.open_inlets += 1
	sync.mutex_unlock(&p.mutex)
	return inlet
}

node_at :: proc(p: ^Pipeline, id: Node_Id) -> ^Node {
	return p.nodes[int(id)]
}

// Keep node `id` off the pool: it runs only when its owner calls
// drain_pinned, or under step and drain. Call it before the run starts.
pin :: proc(p: ^Pipeline, id: Node_Id) {
	node_at(p, id).pinned = true
}

// Would feeding `from` into `to`, beside the inputs it has, let one source
// reach `to` along two paths of different rate? Returns the shared source, the
// stage that changes the count, and which existing input shares it. Paths
// made only of one_to_one stages keep in step, so a source fanned out to two
// such paths is fine; so is the same stream wired to both inputs.
shared_source :: proc(
	p: ^Pipeline,
	to: ^Node,
	from: ^Node,
) -> (
	shared: ^Node,
	blame: ^Node,
	input: int,
	ok: bool,
) {
	// Per node: unseen, or seen with the first count-changing stage on the
	// way down to the input, nil when every path was one_to_one. Two paths
	// from one ancestor to the same input: the impure one wins, because the
	// counts then differ already.
	Mark :: struct {
		seen:  bool,
		blame: ^Node,
	}
	walk :: proc(marks: []Mark, n: ^Node, blame: ^Node) {
		m := &marks[int(n.id)]
		if m.seen && (m.blame != nil || blame == nil) {
			return
		}
		m.seen = true
		m.blame = blame
		below := blame
		if below == nil && !n.one_to_one {
			below = n
		}
		for e in n.ins {
			walk(marks, e.from, below)
		}
	}
	mine := make([]Mark, len(p.nodes), p.allocator)
	defer delete(mine, p.allocator)
	walk(mine, from, nil)
	theirs := make([]Mark, len(p.nodes), p.allocator)
	defer delete(theirs, p.allocator)
	for e, ii in to.ins {
		for &m in theirs {
			m = {}
		}
		walk(theirs, e.from, nil)
		for n in p.nodes {
			a, b := mine[int(n.id)], theirs[int(n.id)]
			if a.seen && b.seen && (a.blame != nil || b.blame != nil) {
				return n, a.blame if a.blame != nil else b.blame, ii, false
			}
		}
	}
	return nil, nil, 0, true
}

// The node behind a stream handle.
node_of :: proc(s: Stream($T)) -> ^Node {
	return node_at(s.p, s.node)
}

// ---------------------------------------------------------------------------
// Edges
// ---------------------------------------------------------------------------

// Exact, from either side.
edge_len :: proc(e: ^Edge) -> int {
	return ring.len(&e.buffer)
}

// Producer side.
edge_full :: proc(e: ^Edge) -> bool {
	return ring.full(&e.buffer)
}

// Consumer side: at least one message waits.
edge_has :: proc(e: ^Edge) -> bool {
	return ring.has(&e.buffer)
}

// Messages the producer has pushed and the consumer has popped, for a check
// or a log; each is the owning side's count.
edge_pushed :: proc(e: ^Edge) -> int {
	return e.pushed
}

edge_popped :: proc(e: ^Edge) -> int {
	return e.popped
}

edge_closed :: proc(e: ^Edge) -> bool {
	return sync.atomic_load(&e.closed)
}

edge_cancelled :: proc(e: ^Edge) -> bool {
	return sync.atomic_load(&e.cancelled)
}

// Closed and drained: the consumer will never see another message.
edge_ended :: proc(e: ^Edge) -> bool {
	return edge_closed(e) && edge_len(e) == 0
}

// Producer side.
edge_push :: proc(e: ^Edge, msg: rawptr) -> bool {
	if !ring.push(&e.buffer, msg) {
		return false
	}
	// The consumer is scheduled once the producer's run ends, not per
	// message: one wake for a run of pushes, and a consumer that keeps pace
	// is not woken for every message it would find anyway.
	e.dirty = true
	return true
}

// Consumer side.
edge_pop :: proc(e: ^Edge, out: rawptr) -> bool {
	if !ring.pop(&e.buffer, out) {
		return false
	}
	if sync.atomic_exchange(&e.parked, false) {
		schedule(e.from)
	}
	return true
}

// Producer side.
edge_close :: proc(e: ^Edge) {
	if sync.atomic_exchange(&e.closed, true) {
		return
	}
	schedule(e.to)
}

// Consumer side.
edge_cancel :: proc(e: ^Edge) {
	if sync.atomic_exchange(&e.cancelled, true) {
		return
	}
	sync.atomic_store(&e.parked, false)
	schedule(e.from)
}

// ---------------------------------------------------------------------------
// Inlets: the thread-safe edge
// ---------------------------------------------------------------------------

// Push without waiting. False when the inlet is full or closed.
inlet_push :: proc(inlet: ^Inlet, msg: rawptr) -> bool {
	sync.mutex_lock(&inlet.mutex)
	ok := !inlet.closed && ring.push(&inlet.buffer, msg)
	sync.mutex_unlock(&inlet.mutex)
	if ok {
		schedule(inlet.n)
	}
	return ok
}

// Push, waiting for space. False only when the inlet closed meanwhile.
inlet_send :: proc(inlet: ^Inlet, msg: rawptr) -> bool {
	sync.mutex_lock(&inlet.mutex)
	for !inlet.closed && ring.full(&inlet.buffer) {
		sync.cond_wait(&inlet.space, &inlet.mutex)
	}
	ok := !inlet.closed && ring.push(&inlet.buffer, msg)
	sync.mutex_unlock(&inlet.mutex)
	if ok {
		schedule(inlet.n)
	}
	return ok
}

// No more messages. Safe from any thread, and idempotent.
inlet_close :: proc(inlet: ^Inlet) {
	sync.mutex_lock(&inlet.mutex)
	was := inlet.closed
	inlet.closed = true
	sync.mutex_unlock(&inlet.mutex)
	if was {
		return
	}
	sync.cond_broadcast(&inlet.space)
	sync.mutex_guard(&inlet.p.mutex)
	inlet.p.open_inlets -= 1
	schedule(inlet.n, locked = true)
	sync.cond_broadcast(&inlet.p.more)
}

@(private)
inlet_pop :: proc(inlet: ^Inlet, out: rawptr) -> bool {
	sync.mutex_lock(&inlet.mutex)
	ok := ring.pop(&inlet.buffer, out)
	sync.mutex_unlock(&inlet.mutex)
	if ok {
		sync.cond_signal(&inlet.space)
	}
	return ok
}

inlet_len :: proc(inlet: ^Inlet) -> int {
	sync.mutex_guard(&inlet.mutex)
	return ring.len(&inlet.buffer)
}

// Closed and drained.
inlet_ended :: proc(inlet: ^Inlet) -> bool {
	sync.mutex_guard(&inlet.mutex)
	return inlet.closed && ring.len(&inlet.buffer) == 0
}

// ---------------------------------------------------------------------------
// What an operator's run proc uses
// ---------------------------------------------------------------------------

// Pop one message from input `inlet`.
take_in :: proc(n: ^Node, ii: int, out: ^$T) -> bool {
	return edge_pop(n.ins[ii], out)
}

in_len :: proc(n: ^Node, ii: int) -> int {
	return edge_len(n.ins[ii])
}

// At least one message waits on input `ii`. Cheaper than in_len.
in_has :: proc(n: ^Node, ii: int) -> bool {
	return edge_has(n.ins[ii])
}

in_ended :: proc(n: ^Node, ii: int) -> bool {
	return edge_ended(n.ins[ii])
}

// Every input is closed and drained.
ins_ended :: proc(n: ^Node) -> bool {
	for e in n.ins {
		if !edge_ended(e) {
			return false
		}
	}
	return true
}

// Pop one message from inlet `ii`.
take_from_inlet :: proc(n: ^Node, ii: int, out: ^$T) -> bool {
	return inlet_pop(n.inlets[ii], out)
}

// Every inlet is closed and drained.
inlets_ended :: proc(n: ^Node) -> bool {
	for inlet in n.inlets {
		if !inlet_ended(inlet) {
			return false
		}
	}
	return true
}

// Nobody downstream wants more. A node with no outs is never cancelled.
outs_cancelled :: proc(n: ^Node) -> bool {
	if len(n.outs) == 0 {
		return false
	}
	for e in n.outs {
		if !edge_cancelled(e) {
			return false
		}
	}
	return true
}

// Every live out has room for one message, so `emit` cannot half-deliver.
out_ready :: proc(n: ^Node) -> bool {
	for e in n.outs {
		if !edge_cancelled(e) && edge_full(e) {
			return false
		}
	}
	return true
}

// Push one message to every live out. Call only after `out_ready`.
emit :: proc(n: ^Node, v: ^$T) {
	for e in n.outs {
		if edge_cancelled(e) {
			continue
		}
		ok := edge_push(e, v)
		assert(ok, "emit on a full edge: check out_ready first")
	}
}

// Park on every full out and yield Blocked.
block :: proc(n: ^Node) -> Yield {
	n.parked = true
	for e in n.outs {
		if !edge_cancelled(e) && edge_full(e) {
			sync.atomic_store(&e.parked, true)
		}
	}
	return .Blocked
}

// The pipeline's time, as the node should see it.
now :: proc(n: ^Node) -> time.Duration {
	return n.p.clock.now(&n.p.clock)
}

// Run again once the clock reaches `at`. Replaces any earlier deadline and
// forgets a fire not yet observed.
arm :: proc(n: ^Node, at: time.Duration) {
	p := n.p
	sync.mutex_lock(&p.timer_mutex)
	n.timer_seq += 1
	n.deadline = at
	n.fired = false
	if !n.armed {
		n.armed = true
		sync.atomic_add(&p.armed, 1)
	}
	priority_queue.push(&p.timers, Timer{at, n.timer_seq, n})
	sync.mutex_unlock(&p.timer_mutex)
	// A worker asleep with no deadline must learn there is one.
	sync.mutex_guard(&p.mutex)
	if p.sleeping > 0 {
		sync.cond_broadcast(&p.more)
	}
}

arm_in :: proc(n: ^Node, d: time.Duration) {
	arm(n, now(n) + d)
}

disarm :: proc(n: ^Node) {
	p := n.p
	sync.mutex_guard(&p.timer_mutex)
	n.timer_seq += 1
	n.fired = false
	if n.armed {
		n.armed = false
		sync.atomic_sub(&p.armed, 1)
	}
}

// True once after the deadline passed.
fired :: proc(n: ^Node) -> bool {
	sync.mutex_guard(&n.p.timer_mutex)
	f := n.fired
	n.fired = false
	return f
}

// ---------------------------------------------------------------------------
// Scheduler
// ---------------------------------------------------------------------------

// Ask for `n` to run. Safe from any thread. A node that is running is marked
// to run again, so a wake that lands mid-run is not lost. `locked` says the
// caller holds `p.mutex`: anything that can let the pool conclude it is
// finished, such as unarming a timer or closing an inlet, must schedule the
// node under the same lock, or the pool may decide between the two.
schedule :: proc(n: ^Node, locked := false) {
	if sync.atomic_load(&n.done) {
		return
	}
	for {
		s := sync.atomic_load(&n.sched)
		switch s {
		case .Idle:
			if _, ok := sync.atomic_compare_exchange_strong(&n.sched, Sched.Idle, Sched.Scheduled);
			   ok {
				enqueue(n, locked)
				return
			}
		case .Running:
			if _, ok := sync.atomic_compare_exchange_strong(
				&n.sched,
				Sched.Running,
				Sched.Running_Again,
			); ok {
				return
			}
		case .Scheduled, .Running_Again:
			return
		}
	}
}

// Worker is one thread running nodes. Its slot holds the node woken most
// recently by the node it is running, which it runs next: the consumer of
// what was just produced, still warm in cache, with no queue and no wake in
// between. An earlier occupant goes to the shared queue for another worker.
@(private)
Worker :: struct {
	p:        ^Pipeline,
	slot:     ^Node,
	use_slot: bool,
}

@(thread_local)
current_worker: ^Worker

@(private)
enqueue :: proc(n: ^Node, locked := false) {
	if !locked && !n.pinned {
		if w := current_worker; w != nil && w.p == n.p && w.use_slot {
			if w.slot != nil {
				enqueue_global(w.slot)
			}
			w.slot = n
			return
		}
	}
	enqueue_global(n, locked)
}

@(private)
enqueue_global :: proc(n: ^Node, locked := false) {
	p := n.p
	if !locked {
		sync.mutex_lock(&p.mutex)
	}
	first_pinned := false
	if n.pinned {
		first_pinned = queue.len(p.pinned) == 0
		queue.push_back(&p.pinned, n)
	} else {
		queue.push_back(&p.ready, n)
		sync.atomic_add(&p.ready_count, 1)
		if p.sleeping > 0 {
			sync.cond_signal(&p.more)
		}
	}
	if !locked {
		sync.mutex_unlock(&p.mutex)
	}
	if first_pinned && p.wake != nil {
		p.wake(p.wake_data)
	}
}

// Queue every source, so `step` has something to run. Any thread may call
// it, and run, step and drain_pinned each do, so a pool and a pinned
// thread can arrive together: the exchange lets exactly one of them queue
// the sources. A caller that loses returns before they are queued, which
// is safe: a node runs only once it is scheduled.
start :: proc(p: ^Pipeline) {
	if sync.atomic_exchange(&p.started, true) {
		return
	}
	for n in p.nodes {
		if len(n.ins) == 0 {
			schedule(n)
		}
	}
}

// Wake every node whose deadline has passed. Takes `p.mutex` for the whole
// of it, so a node is never unarmed and not yet queued when the pool looks
// for work. Costs one atomic load when nothing is armed.
@(private)
fire_timers :: proc(p: ^Pipeline) {
	if sync.atomic_load(&p.armed) == 0 {
		return
	}
	sync.mutex_guard(&p.mutex)
	fire_timers_locked(p)
}

// fire_timers with `p.mutex` already held.
@(private)
fire_timers_locked :: proc(p: ^Pipeline) {
	if sync.atomic_load(&p.armed) == 0 {
		return
	}
	due: [16]^Node
	count := 0
	for {
		sync.mutex_lock(&p.timer_mutex)
		t := p.clock.now(&p.clock)
		for count < len(due) {
			top, ok := priority_queue.peek_safe(p.timers)
			if !ok || top.at > t {
				break
			}
			priority_queue.pop(&p.timers)
			n := top.n
			if !n.armed || n.timer_seq != top.seq {
				continue
			}
			n.armed = false
			sync.atomic_sub(&p.armed, 1)
			n.fired = true
			due[count] = n
			count += 1
		}
		sync.mutex_unlock(&p.timer_mutex)
		for n in due[:count] {
			schedule(n, locked = true)
		}
		if count < len(due) {
			return
		}
		count = 0
	}
}

// How long a worker may sleep before a deadline, or forever (negative), and
// whether a deadline holds the run open: a manual clock's never does, since
// only the caller can move it.
@(private)
next_deadline :: proc(p: ^Pipeline) -> (wait: time.Duration, holds: bool) {
	if sync.atomic_load(&p.armed) == 0 || p.clock.manual {
		return -1, false
	}
	sync.mutex_guard(&p.timer_mutex)
	top, ok := priority_queue.peek_safe(p.timers)
	if !ok {
		return -1, false
	}
	return max(top.at - p.clock.now(&p.clock), 0), true
}

// Nodes with a live deadline.
armed_count :: proc(p: ^Pipeline) -> int {
	return sync.atomic_load(&p.armed)
}

// Take one ready node off the shared queue, or with `pinned` off the pinned
// queue first. Call with `p.mutex` held.
@(private)
dequeue :: proc(p: ^Pipeline, pinned := false) -> (n: ^Node, ok: bool) {
	if pinned {
		if n, ok = dequeue_pinned(p); ok {
			return n, true
		}
	}
	for queue.len(p.ready) > 0 {
		if p.choose != nil && p.workers == 0 {
			// Swap the chosen one to the front; a drawn order is no order.
			pick := p.choose(p.choose_data, queue.len(p.ready))
			front := queue.front(&p.ready)
			queue.set(&p.ready, 0, queue.get(&p.ready, pick))
			queue.set(&p.ready, pick, front)
		}
		n = queue.pop_front(&p.ready)
		sync.atomic_sub(&p.ready_count, 1)
		if sync.atomic_load(&n.done) {
			sync.atomic_store(&n.sched, Sched.Idle)
			continue
		}
		sync.atomic_store(&n.sched, Sched.Running)
		return n, true
	}
	return nil, false
}

// Take one ready pinned node. Call with `p.mutex` held.
@(private)
dequeue_pinned :: proc(p: ^Pipeline) -> (n: ^Node, ok: bool) {
	for queue.len(p.pinned) > 0 {
		n = queue.pop_front(&p.pinned)
		if sync.atomic_load(&n.done) {
			sync.atomic_store(&n.sched, Sched.Idle)
			continue
		}
		sync.atomic_store(&n.sched, Sched.Running)
		return n, true
	}
	return nil, false
}

// Run a node once, wake the consumers of what it pushed, and settle its flag.
// `exact` turns on the yield checks, which hold only when no other thread can
// touch the edges meanwhile. A node that spent its budget goes to the back of
// the shared queue, not the slot, so the consumer of what it produced runs
// first and another worker may take the producer.
@(private)
run_node :: proc(p: ^Pipeline, n: ^Node, exact: bool) {
	n.runs += 1
	y := n->run()
	for e in n.outs {
		if e.dirty {
			e.dirty = false
			schedule(e.to)
		}
	}
	when CHECK_YIELDS {
		if exact {
			if msg, ok := check_yield(n, y); !ok {
				fmt.panicf("stream: %s#%d yielded %v %s", n.name, int(n.id), y, msg)
			}
		}
	}
	again := false
	switch y {
	case .Done:
		sync.atomic_store(&n.done, true)
		finish(n)
	case .Budget:
		again = true
	case .Blocked:
		// A consumer may have popped between the node seeing an edge full and
		// parking on it, so no edge carries the park. If there is room now,
		// run again rather than wait for a wake that will never come.
		again = out_ready(n)
	case .Drained:
	}
	n.parked = false
	if again {
		sync.atomic_store(&n.sched, Sched.Scheduled)
		enqueue_global(n)
		return
	}
	if _, ok := sync.atomic_compare_exchange_strong(&n.sched, Sched.Running, Sched.Idle); !ok {
		// A wake landed while the node ran: more arrived on an edge it just
		// read. Run it next on this thread rather than cross the lock.
		sync.atomic_store(&n.sched, Sched.Scheduled)
		enqueue(n)
	}
}

// Run one ready node on this thread, in queue order. False when nothing is
// ready now. Only for a pipeline no other thread is running.
step :: proc(p: ^Pipeline) -> bool {
	fire_timers(p)
	sync.mutex_lock(&p.mutex)
	n, ok := dequeue(p, pinned = true)
	sync.mutex_unlock(&p.mutex)
	if !ok {
		return false
	}
	run_node(p, n, exact = true)
	return true
}

// Judge a yield by what the edges show. A wrong yield is a node that would
// never run again, or one that stopped with work in front of it.
check_yield :: proc(n: ^Node, y: Yield) -> (msg: string, ok: bool) {
	switch y {
	case .Drained:
		sync.mutex_lock(&n.p.timer_mutex)
		armed := n.armed
		sync.mutex_unlock(&n.p.timer_mutex)
		waiting := armed || !inlets_ended(n)
		if !waiting && ins_ended(n) {
			return "after every input ended; it will never run again", false
		}
		if !waiting && len(n.ins) > 0 && out_ready(n) {
			all := true
			for e in n.ins {
				if edge_len(e) == 0 {
					all = false
					break
				}
			}
			if all {
				return "with a message on every input and room to emit", false
			}
		}
	case .Blocked:
		if !n.parked {
			return "without calling block", false
		}
		for e in n.outs {
			if !edge_cancelled(e) && edge_full(e) {
				return "", true
			}
		}
		return "with room on every out", false
	case .Budget, .Done:
	}
	return "", true
}

@(private)
finish :: proc(n: ^Node) {
	disarm(n)
	for e in n.outs {
		edge_close(e)
	}
	for e in n.ins {
		edge_cancel(e)
	}
	for inlet in n.inlets {
		inlet_close(inlet)
	}
}

// Run what is ready at this instant and return.
drain :: proc(p: ^Pipeline) {
	start(p)
	for step(p) {}
}

// Run the pinned nodes that are ready, on this thread, and return how many
// ran. For the thread that owns them while `run` drives the rest on a pool:
// a frame loop calls it once a frame, or when `p.wake` says to. The pool
// counts the node as running meanwhile, so it cannot conclude the pipeline
// is quiet under it.
drain_pinned :: proc(p: ^Pipeline) -> (ran: int) {
	start(p)
	for {
		fire_timers(p)
		sync.mutex_lock(&p.mutex)
		n, ok := dequeue_pinned(p)
		if ok {
			p.active += 1
		}
		sync.mutex_unlock(&p.mutex)
		if !ok {
			return
		}
		run_node(p, n, exact = false)
		sync.mutex_lock(&p.mutex)
		p.active -= 1
		// A worker asleep over this node must look again: it may have been
		// the last thing keeping the pipeline from quiescence.
		if p.sleeping > 0 {
			sync.cond_broadcast(&p.more)
		}
		sync.mutex_unlock(&p.mutex)
		ran += 1
	}
}

// Drive the pipeline until it is quiescent: nothing ready, nothing running, no
// inlet open, no timer armed, and no pinned node ready: those wait for their
// owner's drain_pinned, and so does `run`. With a manual clock an armed timer does not
// hold it, since only the caller can move the clock. The caller runs nodes,
// and so do `threads` more started for the call and joined before it returns;
// AUTO sizes the pool from the graph, and a pipeline with a `choose` hook
// always runs on the caller alone, since a drawn order needs one thread.
run :: proc(p: ^Pipeline, threads := AUTO) {
	threads := threads
	threads = pool_size(p, threads)
	start(p)
	sync.mutex_lock(&p.mutex)
	sync.atomic_store(&p.quit, false)
	p.quiescent = false
	p.workers = threads
	sync.mutex_unlock(&p.mutex)
	pool := make([]^thread.Thread, threads, p.allocator)
	for &t in pool {
		t = thread.create_and_start_with_data(p, pool_main, context)
	}
	work(p)
	for t in pool {
		thread.join(t)
		thread.destroy(t)
	}
	delete(pool, p.allocator)
	sync.mutex_lock(&p.mutex)
	p.workers = 0
	sync.mutex_unlock(&p.mutex)
	when CHECK_YIELDS {
		if sync.atomic_load(&p.quiescent) && !finished(p) {
			if armed_count(p) == 0 {
				b := strings.builder_make(context.temp_allocator)
				dump(p, &b)
				fmt.panicf("stream: quiescent with a node unfinished\n%s", strings.to_string(b))
			}
		}
	}
}

// Threads `run` would start besides the caller for `threads`: the count given,
// or for AUTO one per node past the first, up to three. A pipeline with a
// `choose` hook gets none, since a drawn order needs one thread.
pool_size :: proc(p: ^Pipeline, threads: int) -> int {
	if p.choose != nil {
		return 0
	}
	if threads < 0 {
		return clamp(len(p.nodes) - 1, 0, 3)
	}
	return threads
}

// Make `run` return as soon as every node now running has yielded. Nodes keep
// their state; a later `run` carries on.
stop :: proc(p: ^Pipeline) {
	sync.mutex_guard(&p.mutex)
	sync.atomic_store(&p.quit, true)
	sync.cond_broadcast(&p.more)
}

@(private)
pool_main :: proc(data: rawptr) {
	work((^Pipeline)(data))
}

// Run nodes until the pipeline is quiescent or stopped. A worker runs from
// its slot without touching the lock; only with the slot empty does it go to
// the shared queue. With that empty too it spins a little, then sleeps.
@(private)
work :: proc(p: ^Pipeline) {
	w := Worker {
		p        = p,
		use_slot = !(p.workers == 0 && p.choose != nil),
	}
	prev := current_worker
	current_worker = &w
	defer current_worker = prev
	exact := p.workers == 0
	sync.mutex_lock(&p.mutex)
	p.active += 1
	sync.mutex_unlock(&p.mutex)
	for {
		fire_timers(p)
		if sync.atomic_load(&p.quit) {
			if w.slot != nil {
				enqueue_global(w.slot)
			}
			sync.mutex_lock(&p.mutex)
			p.active -= 1
			sync.mutex_unlock(&p.mutex)
			return
		}
		n := w.slot
		w.slot = nil
		if n != nil {
			// What dequeue does for the shared queue: claim it, or drop it
			// if it finished while it waited.
			if sync.atomic_load(&n.done) {
				sync.atomic_store(&n.sched, Sched.Idle)
				continue
			}
			sync.atomic_store(&n.sched, Sched.Running)
		} else {
			ok: bool
			n, ok = take_shared(p)
			if !ok {
				return
			}
		}
		run_node(p, n, exact)
	}
}

// Take a node from the shared queue, spinning then sleeping until one comes.
// False means the pipeline is quiescent or stopped and the worker should go.
@(private)
take_shared :: proc(p: ^Pipeline) -> (n: ^Node, ok: bool) {
	sync.mutex_guard(&p.mutex)
	for {
		fire_timers_locked(p)
		if n, ok = dequeue(p); ok {
			// More behind it and someone asleep: pass the word along.
			if queue.len(p.ready) > 0 && p.sleeping > 0 {
				sync.cond_signal(&p.more)
			}
			return n, true
		}
		if sync.atomic_load(&p.quit) {
			p.active -= 1
			return nil, false
		}
		p.active -= 1
		wait, holds := next_deadline(p)
		if p.active == 0 && p.open_inlets == 0 && !holds && queue.len(p.pinned) == 0 {
			sync.atomic_store(&p.quit, true)
			p.quiescent = true
			sync.cond_broadcast(&p.more)
			return nil, false
		}
		// Others are still at work. Spin a little before sleeping, since
		// what they produce next is likely to land in the queue soon.
		if p.spinning < SPINNERS {
			p.spinning += 1
			sync.mutex_unlock(&p.mutex)
			spun := false
			for _ in 0 ..< SPIN {
				if sync.atomic_load(&p.ready_count) > 0 || sync.atomic_load(&p.quit) {
					spun = true
					break
				}
				intrinsics.cpu_relax()
			}
			sync.mutex_lock(&p.mutex)
			p.spinning -= 1
			p.active += 1
			if spun || queue.len(p.ready) > 0 || sync.atomic_load(&p.quit) {
				continue
			}
			p.active -= 1
		}
		wait, holds = next_deadline(p)
		if p.active == 0 && p.open_inlets == 0 && !holds && queue.len(p.pinned) == 0 {
			sync.atomic_store(&p.quit, true)
			p.quiescent = true
			sync.cond_broadcast(&p.more)
			return nil, false
		}
		p.sleeping += 1
		if wait >= 0 {
			sync.cond_wait_with_timeout(&p.more, &p.mutex, wait)
		} else {
			sync.cond_wait(&p.more, &p.mutex)
		}
		p.sleeping -= 1
		p.active += 1
	}
}

// Every node finished.
finished :: proc(p: ^Pipeline) -> bool {
	for n in p.nodes {
		if !sync.atomic_load(&n.done) {
			return false
		}
	}
	return true
}

// Write one line per node, edge and inlet, for a test or a log.
dump :: proc(p: ^Pipeline, b: ^strings.Builder) {
	for n in p.nodes {
		fmt.sbprintf(b, "%s#%d %v runs=%d", n.name, int(n.id), sync.atomic_load(&n.sched), n.runs)
		sync.mutex_lock(&p.timer_mutex)
		if n.armed {
			fmt.sbprintf(b, " armed=%v", n.deadline)
		}
		sync.mutex_unlock(&p.timer_mutex)
		if sync.atomic_load(&n.done) {
			strings.write_string(b, " done")
		}
		if n.pinned {
			strings.write_string(b, " pinned")
		}
		strings.write_byte(b, '\n')
	}
	for e in p.edges {
		fmt.sbprintf(
			b,
			"  %s#%d -> %s#%d %d/%d pushed=%d popped=%d",
			e.from.name,
			int(e.from.id),
			e.to.name,
			int(e.to.id),
			edge_len(e),
			e.cap,
			edge_pushed(e),
			edge_popped(e),
		)
		if edge_closed(e) {
			strings.write_string(b, " closed")
		}
		if edge_cancelled(e) {
			strings.write_string(b, " cancelled")
		}
		if sync.atomic_load(&e.parked) {
			strings.write_string(b, " parked")
		}
		strings.write_byte(b, '\n')
	}
	for inlet in p.inlets {
		sync.mutex_lock(&inlet.mutex)
		fmt.sbprintf(
			b,
			"  inlet -> %s#%d %d/%d pushed=%d popped=%d",
			inlet.n.name,
			int(inlet.n.id),
			ring.len(&inlet.buffer),
			inlet.cap,
			inlet.pushed,
			inlet.popped,
		)
		if inlet.closed {
			strings.write_string(b, " closed")
		}
		sync.mutex_unlock(&inlet.mutex)
		strings.write_byte(b, '\n')
	}
}
