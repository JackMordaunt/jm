package stream

import "core:sync"
import "core:time"

import "jm:stream/ring"

/*
The operators. Each builds a node whose run proc is instantiated for the types
it carries, so the public surface is typed and the pipeline underneath is not.

A stage body cannot block, and it has no closure to keep state in: it is a
struct of state plus a proc, so every operator takes a `state: ^$S` form beside
the plain one. The user owns that state and keeps it alive for the run.
*/

// ---------------------------------------------------------------------------
// Sources
// ---------------------------------------------------------------------------

@(private)
From_Slice :: struct($T: typeid) {
	items: []T,
	index: int,
}

// Emit every item of `items`, then end. The slice must outlive the run.
from_slice :: proc(p: ^Pipeline, items: []$T, name := "from_slice") -> Stream(T) {
	run :: proc(n: ^Node) -> Yield {
		st := (^From_Slice(T))(n.state)
		for _ in 0 ..< BUDGET {
			if outs_cancelled(n) || st.index == len(st.items) {
				return .Done
			}
			if !out_ready(n) {
				return block(n)
			}
			emit(n, &st.items[st.index])
			st.index += 1
		}
		return .Budget
	}
	n := add_node(p, name, run, From_Slice(T){items = items})
	return Stream(T){p, n.id}
}

@(private)
Generate :: struct($T, $S: typeid) {
	state: ^S,
	next:  proc(state: ^S) -> (T, bool),
}

// Emit what `next` returns until it returns false. For an endless source, a
// downstream `take` ends it.
generate :: proc(
	p: ^Pipeline,
	state: ^$S,
	next: proc(state: ^S) -> ($T, bool),
	name := "generate",
) -> Stream(T) {
	run :: proc(n: ^Node) -> Yield {
		st := (^Generate(T, S))(n.state)
		for _ in 0 ..< BUDGET {
			if outs_cancelled(n) {
				return .Done
			}
			if !out_ready(n) {
				return block(n)
			}
			v, ok := st.next(st.state)
			if !ok {
				return .Done
			}
			emit(n, &v)
		}
		return .Budget
	}
	n := add_node(p, name, run, Generate(T, S){state, next})
	return Stream(T){p, n.id}
}

// ---------------------------------------------------------------------------
// One in, one out
// ---------------------------------------------------------------------------

transform :: proc {
	transform_fn,
	transform_with,
}

@(private)
Transform :: struct($A, $B, $S: typeid) {
	state: ^S,
	f:     proc(state: ^S, a: A) -> B,
}

// Emit `f(a)` for every `a`.
transform_with :: proc(
	s: Stream($A),
	state: ^$S,
	f: proc(state: ^S, a: A) -> $B,
	name := "transform",
) -> Stream(B) {
	run :: proc(n: ^Node) -> Yield {
		st := (^Transform(A, B, S))(n.state)
		for _ in 0 ..< BUDGET {
			if outs_cancelled(n) {
				return .Done
			}
			if !out_ready(n) {
				return block(n)
			}
			a: A
			if !take_in(n, 0, &a) {
				return ins_ended(n) ? .Done : .Drained
			}
			b := st.f(st.state, a)
			emit(n, &b)
		}
		return .Budget
	}
	n := add_node(s.p, name, run, Transform(A, B, S){state, f})
	n.one_to_one = true
	connect(s.p, s.node, n, ring.shape_of(A))
	return Stream(B){s.p, n.id}
}

@(private)
Fn :: struct($F: typeid) {
	f: F,
}

transform_fn :: proc(s: Stream($A), f: proc(a: A) -> $B, name := "transform") -> Stream(B) {
	run :: proc(n: ^Node) -> Yield {
		st := (^Fn(proc(a: A) -> B))(n.state)
		for _ in 0 ..< BUDGET {
			if outs_cancelled(n) {
				return .Done
			}
			if !out_ready(n) {
				return block(n)
			}
			a: A
			if !take_in(n, 0, &a) {
				return ins_ended(n) ? .Done : .Drained
			}
			b := st.f(a)
			emit(n, &b)
		}
		return .Budget
	}
	n := add_node(s.p, name, run, Fn(proc(a: A) -> B){f})
	n.one_to_one = true
	connect(s.p, s.node, n, ring.shape_of(A))
	return Stream(B){s.p, n.id}
}

filter :: proc {
	filter_fn,
	filter_with,
}

@(private)
Filter :: struct($A, $S: typeid) {
	state: ^S,
	keep:  proc(state: ^S, a: A) -> bool,
}

// Emit the `a` that `keep` accepts.
filter_with :: proc(
	s: Stream($A),
	state: ^$S,
	keep: proc(state: ^S, a: A) -> bool,
	name := "filter",
) -> Stream(A) {
	run :: proc(n: ^Node) -> Yield {
		st := (^Filter(A, S))(n.state)
		for _ in 0 ..< BUDGET {
			if outs_cancelled(n) {
				return .Done
			}
			if !out_ready(n) {
				return block(n)
			}
			a: A
			if !take_in(n, 0, &a) {
				return ins_ended(n) ? .Done : .Drained
			}
			if st.keep(st.state, a) {
				emit(n, &a)
			}
		}
		return .Budget
	}
	n := add_node(s.p, name, run, Filter(A, S){state, keep})
	connect(s.p, s.node, n, ring.shape_of(A))
	return Stream(A){s.p, n.id}
}

filter_fn :: proc(s: Stream($A), keep: proc(a: A) -> bool, name := "filter") -> Stream(A) {
	run :: proc(n: ^Node) -> Yield {
		st := (^Fn(proc(a: A) -> bool))(n.state)
		for _ in 0 ..< BUDGET {
			if outs_cancelled(n) {
				return .Done
			}
			if !out_ready(n) {
				return block(n)
			}
			a: A
			if !take_in(n, 0, &a) {
				return ins_ended(n) ? .Done : .Drained
			}
			if st.f(a) {
				emit(n, &a)
			}
		}
		return .Budget
	}
	n := add_node(s.p, name, run, Fn(proc(a: A) -> bool){keep})
	connect(s.p, s.node, n, ring.shape_of(A))
	return Stream(A){s.p, n.id}
}

flat_map :: proc {
	flat_map_fn,
	flat_map_with,
}

@(private)
Flat_Map :: struct($A, $B, $S: typeid) {
	state:   ^S,
	f:       proc(state: ^S, a: A) -> []B,
	pending: []B,
	cur:     int,
}

// Emit every element of `f(a)` for every `a`. The slice `f` returns must stay
// valid until `f` is called again.
flat_map_with :: proc(
	s: Stream($A),
	state: ^$S,
	f: proc(state: ^S, a: A) -> []$B,
	name := "flat_map",
) -> Stream(B) {
	run :: proc(n: ^Node) -> Yield {
		st := (^Flat_Map(A, B, S))(n.state)
		for _ in 0 ..< BUDGET {
			if outs_cancelled(n) {
				return .Done
			}
			if !out_ready(n) {
				return block(n)
			}
			if st.cur < len(st.pending) {
				emit(n, &st.pending[st.cur])
				st.cur += 1
				continue
			}
			a: A
			if !take_in(n, 0, &a) {
				return ins_ended(n) ? .Done : .Drained
			}
			st.pending = st.f(st.state, a)
			st.cur = 0
		}
		return .Budget
	}
	n := add_node(s.p, name, run, Flat_Map(A, B, S){state = state, f = f})
	connect(s.p, s.node, n, ring.shape_of(A))
	return Stream(B){s.p, n.id}
}

@(private)
Flat_Map_Fn :: struct($A, $B: typeid) {
	f:       proc(a: A) -> []B,
	pending: []B,
	cur:     int,
}

flat_map_fn :: proc(s: Stream($A), f: proc(a: A) -> []$B, name := "flat_map") -> Stream(B) {
	run :: proc(n: ^Node) -> Yield {
		st := (^Flat_Map_Fn(A, B))(n.state)
		for _ in 0 ..< BUDGET {
			if outs_cancelled(n) {
				return .Done
			}
			if !out_ready(n) {
				return block(n)
			}
			if st.cur < len(st.pending) {
				emit(n, &st.pending[st.cur])
				st.cur += 1
				continue
			}
			a: A
			if !take_in(n, 0, &a) {
				return ins_ended(n) ? .Done : .Drained
			}
			st.pending = st.f(a)
			st.cur = 0
		}
		return .Budget
	}
	n := add_node(s.p, name, run, Flat_Map_Fn(A, B){f = f})
	connect(s.p, s.node, n, ring.shape_of(A))
	return Stream(B){s.p, n.id}
}

@(private)
Take :: struct {
	left: int,
}

// Pass the first `count` messages, then end and cancel upstream.
take :: proc(s: Stream($T), count: int, name := "take") -> Stream(T) {
	run :: proc(n: ^Node) -> Yield {
		st := (^Take)(n.state)
		for _ in 0 ..< BUDGET {
			if outs_cancelled(n) || st.left == 0 {
				return .Done
			}
			if !out_ready(n) {
				return block(n)
			}
			v: T
			if !take_in(n, 0, &v) {
				return ins_ended(n) ? .Done : .Drained
			}
			emit(n, &v)
			st.left -= 1
		}
		return .Budget
	}
	n := add_node(s.p, name, run, Take{count})
	connect(s.p, s.node, n, ring.shape_of(T))
	return Stream(T){s.p, n.id}
}

// ---------------------------------------------------------------------------
// Many in
// ---------------------------------------------------------------------------

// Pair the ii-th message of `a` with the ii-th of `b`. Ends when either ends.
zip :: proc(a: Stream($A), b: Stream($B), name := "zip") -> Stream(Pair(A, B)) {
	run :: proc(n: ^Node) -> Yield {
		for _ in 0 ..< BUDGET {
			if outs_cancelled(n) {
				return .Done
			}
			if !out_ready(n) {
				return block(n)
			}
			if !in_has(n, 0) || !in_has(n, 1) {
				return in_ended(n, 0) || in_ended(n, 1) ? .Done : .Drained
			}
			pair: Pair(A, B)
			take_in(n, 0, &pair.first)
			take_in(n, 1, &pair.second)
			emit(n, &pair)
		}
		return .Budget
	}
	assert(a.p == b.p, "zip across pipelines")
	n := add_node(a.p, name, run, struct{}{})
	n.waits = true
	connect(a.p, a.node, n, ring.shape_of(A))
	connect(a.p, b.node, n, ring.shape_of(B))
	return Stream(Pair(A, B)){a.p, n.id}
}

@(private)
Merge :: struct {
	next: int,
}

// Interleave every input. Each run drains the input it is on before moving to
// the next, up to the budget, so round robin is per batch: a poll of an empty
// edge reads the producer's cache line, and tools/stream-bench merge8 on three
// threads went from 1.6 µs a message polling every input per message to 53 ns
// per batch on 2026-10-02. Ends when all end.
merge :: proc(streams: []Stream($T), name := "merge") -> Stream(T) {
	run :: proc(n: ^Node) -> Yield {
		st := (^Merge)(n.state)
		budget := BUDGET
		idle := 0 // inputs tried in a row with nothing to give
		for budget > 0 {
			if outs_cancelled(n) {
				return .Done
			}
			if !out_ready(n) {
				return block(n)
			}
			v: T
			if take_in(n, st.next, &v) {
				emit(n, &v)
				budget -= 1
				idle = 0
				continue
			}
			idle += 1
			st.next = (st.next + 1) % len(n.ins)
			if idle == len(n.ins) {
				return ins_ended(n) ? .Done : .Drained
			}
		}
		st.next = (st.next + 1) % len(n.ins)
		return .Budget
	}
	assert(len(streams) > 0, "merge of nothing")
	p := streams[0].p
	n := add_node(p, name, run, Merge{})
	for s in streams {
		assert(s.p == p, "merge across pipelines")
		connect(p, s.node, n, ring.shape_of(T))
	}
	return Stream(T){p, n.id}
}

// ---------------------------------------------------------------------------
// Sinks
// ---------------------------------------------------------------------------

for_each :: proc {
	for_each_fn,
	for_each_with,
}

@(private)
For_Each :: struct($T, $S: typeid) {
	state: ^S,
	f:     proc(state: ^S, v: T),
}

// Call `f` on every message.
for_each_with :: proc(
	s: Stream($T),
	state: ^$S,
	f: proc(state: ^S, v: T),
	name := "for_each",
) -> Node_Id {
	run :: proc(n: ^Node) -> Yield {
		st := (^For_Each(T, S))(n.state)
		for _ in 0 ..< BUDGET {
			v: T
			if !take_in(n, 0, &v) {
				return ins_ended(n) ? .Done : .Drained
			}
			st.f(st.state, v)
		}
		return .Budget
	}
	n := add_node(s.p, name, run, For_Each(T, S){state, f})
	connect(s.p, s.node, n, ring.shape_of(T))
	return n.id
}

for_each_fn :: proc(s: Stream($T), f: proc(v: T), name := "for_each") -> Node_Id {
	run :: proc(n: ^Node) -> Yield {
		st := (^Fn(proc(v: T)))(n.state)
		for _ in 0 ..< BUDGET {
			v: T
			if !take_in(n, 0, &v) {
				return ins_ended(n) ? .Done : .Drained
			}
			st.f(v)
		}
		return .Budget
	}
	n := add_node(s.p, name, run, Fn(proc(v: T)){f})
	connect(s.p, s.node, n, ring.shape_of(T))
	return n.id
}

// Append every message to `out`, which the caller owns.
collect :: proc(s: Stream($T), out: ^[dynamic]T, name := "collect") -> Node_Id {
	run :: proc(n: ^Node) -> Yield {
		out := (^Fn(^[dynamic]T))(n.state).f
		for _ in 0 ..< BUDGET {
			v: T
			if !take_in(n, 0, &v) {
				return ins_ended(n) ? .Done : .Drained
			}
			append(out, v)
		}
		return .Budget
	}
	n := add_node(s.p, name, run, Fn(^[dynamic]T){out})
	connect(s.p, s.node, n, ring.shape_of(T))
	return n.id
}

// ---------------------------------------------------------------------------
// The other symbols: a port fed by any thread, the clock, and completions
// ---------------------------------------------------------------------------

// The sending end of `port`. Any thread may use it.
Port :: struct($T: typeid) {
	inlet: ^Inlet,
}

// Wait for room, then push. False once the port is closed.
port_send :: proc(port: Port($T), v: T) -> bool {
	v := v
	return inlet_send(port.inlet, &v)
}

// Push without waiting. False when full or closed.
port_push :: proc(port: Port($T), v: T) -> bool {
	v := v
	return inlet_push(port.inlet, &v)
}

port_close :: proc(port: Port($T)) {
	inlet_close(port.inlet)
}

// A source other threads feed. The stream ends when the port is closed.
port :: proc(p: ^Pipeline, $T: typeid, cap := 0, name := "port") -> (Stream(T), Port(T)) {
	run :: proc(n: ^Node) -> Yield {
		for _ in 0 ..< BUDGET {
			if outs_cancelled(n) {
				return .Done
			}
			if !out_ready(n) {
				return block(n)
			}
			v: T
			if !take_from_inlet(n, 0, &v) {
				return inlets_ended(n) ? .Done : .Drained
			}
			emit(n, &v)
		}
		return .Budget
	}
	n := add_node(p, name, run, struct{}{})
	ii := add_inlet(p, n, ring.shape_of(T), cap)
	return Stream(T){p, n.id}, Port(T){ii}
}

@(private)
Interval :: struct {
	every:   time.Duration,
	started: bool,
	pending: bool,
}

// Emit the time every `every`. A tick that finds the out full waits for room;
// ticks do not pile up.
interval :: proc(p: ^Pipeline, every: time.Duration, name := "interval") -> Stream(time.Duration) {
	run :: proc(n: ^Node) -> Yield {
		st := (^Interval)(n.state)
		if outs_cancelled(n) {
			return .Done
		}
		if !st.started {
			st.started = true
			arm_in(n, st.every)
			return .Drained
		}
		if fired(n) {
			st.pending = true
			arm_in(n, st.every)
		}
		if st.pending {
			if !out_ready(n) {
				return block(n)
			}
			t := now(n)
			emit(n, &t)
			st.pending = false
		}
		return .Drained
	}
	n := add_node(p, name, run, Interval{every = every})
	return Stream(time.Duration){p, n.id}
}

@(private)
Debounce :: struct($T: typeid) {
	quiet:  time.Duration,
	latest: T,
	has:    bool,
	due:    bool,
}

// Emit the latest message once none arrived for `quiet`, and whatever is
// pending when the input ends.
debounce :: proc(s: Stream($T), quiet: time.Duration, name := "debounce") -> Stream(T) {
	run :: proc(n: ^Node) -> Yield {
		st := (^Debounce(T))(n.state)
		if outs_cancelled(n) {
			return .Done
		}
		got := false
		for _ in 0 ..< BUDGET {
			if !take_in(n, 0, &st.latest) {
				break
			}
			st.has = true
			got = true
		}
		if got {
			st.due = false
			arm_in(n, st.quiet)
		}
		if fired(n) {
			st.due = true
		}
		if in_ended(n, 0) {
			st.due = true
		}
		if st.due && st.has {
			if !out_ready(n) {
				return block(n)
			}
			emit(n, &st.latest)
			st.has = false
			st.due = false
		}
		if in_ended(n, 0) {
			return .Done
		}
		return in_len(n, 0) > 0 ? .Budget : .Drained
	}
	n := add_node(s.p, name, run, Debounce(T){quiet = quiet})
	connect(s.p, s.node, n, ring.shape_of(T))
	return Stream(T){s.p, n.id}
}

// Latest is a sink another thread reads: the last message to arrive, taken
// at most once per arrival. A frame loop reads it once a frame, so a burst
// of answers costs the frame one take and a loop that stops reading, with
// its window hidden say, never parks the pipeline: the node drains every
// message into it and keeps only the newest.
Latest :: struct($T: typeid) {
	using box: Mailbox,
	value:     T,
}

// Mailbox is the untyped half of a Latest: its lock and flags.
@(private)
Mailbox :: struct {
	mutex: sync.Mutex,
	fresh: bool, // a message arrived since the last take
	ended: bool, // the input ended; nothing more will arrive
}

@(private)
mailbox_lock :: proc(m: ^Mailbox) {
	sync.mutex_lock(&m.mutex)
}

@(private)
mailbox_unlock :: proc(m: ^Mailbox) {
	sync.mutex_unlock(&m.mutex)
}

// Keep the newest message of `s` for latest_take. Never blocks the producer.
latest :: proc(s: Stream($T), name := "latest") -> ^Latest(T) {
	run :: proc(n: ^Node) -> Yield {
		l := (^Latest(T))(n.state)
		v: T
		got := false
		for _ in 0 ..< BUDGET {
			if !take_in(n, 0, &v) {
				break
			}
			got = true
		}
		if got {
			mailbox_lock(&l.box)
			l.value = v
			l.fresh = true
			mailbox_unlock(&l.box)
		}
		if in_has(n, 0) {
			return .Budget
		}
		if in_ended(n, 0) {
			mailbox_lock(&l.box)
			l.ended = true
			mailbox_unlock(&l.box)
			return .Done
		}
		return .Drained
	}
	n := add_node(s.p, name, run, Latest(T){})
	connect(s.p, s.node, n, ring.shape_of(T))
	return (^Latest(T))(n.state)
}

// Take the newest message, if one arrived since the last take. Any thread.
latest_take :: proc(l: ^Latest($T), out: ^T) -> bool {
	mailbox_lock(&l.box)
	defer mailbox_unlock(&l.box)
	if !l.fresh {
		return false
	}
	out^ = l.value
	l.fresh = false
	return true
}

// The input ended: no later take will succeed. Any thread.
latest_ended :: proc(l: ^Latest($T)) -> bool {
	mailbox_lock(&l.box)
	defer mailbox_unlock(&l.box)
	return l.ended
}

@(private)
Debounce_By :: struct($T, $K: typeid) {
	quiet:   time.Duration,
	key:     proc(v: T) -> K,
	pending: map[K]Pending(T),
	armed:   time.Duration, // the deadline armed, or 0 for none
}

@(private)
Pending :: struct($T: typeid) {
	value: T,
	due:   time.Duration,
}

// Emit the latest message of each key once none with that key arrived for
// `quiet`, and whatever is pending when the input ends. A keyed debounce:
// a burst of changes to one record settles to one message without holding
// up another record's. Keys are emitted in due order, and in arrival order
// when due together.
debounce_by :: proc(
	s: Stream($T),
	quiet: time.Duration,
	key: proc(v: T) -> $K,
	name := "debounce_by",
) -> Stream(T) {
	run     :: proc(n: ^Node) -> Yield {
		st := (^Debounce_By(T, K))(n.state)
		if outs_cancelled(n) {
			return .Done
		}
		v: T
		for _ in 0 ..< BUDGET {
			if !take_in(n, 0, &v) {
				break
			}
			k := st.key(v)
			// A key re-set keeps its slot, so arrival order is first arrival.
			st.pending[k] = Pending(T){v, now(n) + st.quiet}
		}
		_ = fired(n)
		ended := in_ended(n, 0)
		t := now(n)
		// Emit what is due, earliest first, and find the next deadline.
		for {
			next: time.Duration = -1
			due_k: K
			due_v: T
			have := false
			for k, pd in st.pending {
				if ended || pd.due <= t {
					if !have || pd.due < next {
						have, next, due_k, due_v = true, pd.due, k, pd.value
					}
				}
			}
			if !have {
				break
			}
			if !out_ready(n) {
				return block(n)
			}
			emit(n, &due_v)
			delete_key(&st.pending, due_k)
		}
		if ended {
			return .Done
		}
		soonest: time.Duration = -1
		for _, pd in st.pending {
			if soonest < 0 || pd.due < soonest {
				soonest = pd.due
			}
		}
		if soonest >= 0 && soonest != st.armed {
			st.armed = soonest
			arm(n, soonest)
		}
		if soonest < 0 {
			st.armed = 0
		}
		return in_len(n, 0) > 0 ? .Budget : .Drained
	}
	cleanup :: proc(n: ^Node) {
		st := (^Debounce_By(T, K))(n.state)
		delete(st.pending)
	}
	n := add_node(s.p, name, run, Debounce_By(T, K){quiet = quiet, key = key})
	st := (^Debounce_By(T, K))(n.state)
	st.pending = make(map[K]Pending(T), s.p.allocator)
	n.cleanup = cleanup
	connect(s.p, s.node, n, ring.shape_of(T))
	return Stream(T){s.p, n.id}
}

@(private)
Async_Slot :: struct($A, $B, $S: typeid) {
	owner: ^Async_Map(A, B, S),
	idx:   int,
	seq:   u64,
	a:     A,
	b:     B,
	busy:  bool,
	ready: bool,
}

@(private)
Async_Map :: struct($A, $B, $S: typeid) {
	workers:   ^Workers,
	state:     ^S,
	f:         proc(state: ^S, a: A) -> B,
	ordered:   bool,
	slots:     []Async_Slot(A, B, S),
	busy:      int,
	next_seq:  u64,
	next_emit: u64,
	inlet:     ^Inlet,
}

// Run `f` on the workers, at most `concurrency` at a time. Ordered keeps the
// input order; unordered emits each result as it lands. `f` runs on a worker
// thread, so what it touches through `state` must be safe to share.
async_map :: proc(
	s: Stream($A),
	workers: ^Workers,
	state: ^$S,
	f: proc(state: ^S, a: A) -> $B,
	concurrency := 4,
	ordered := true,
	name := "async_map",
) -> Stream(B) {
	job     :: proc(data: rawptr) {
		slot := (^Async_Slot(A, B, S))(data)
		slot.b = slot.owner.f(slot.owner.state, slot.a)
		idx := slot.idx
		inlet_send(slot.owner.inlet, &idx)
	}
	run     :: proc(n: ^Node) -> Yield {
		st := (^Async_Map(A, B, S))(n.state)
		for _ in 0 ..< BUDGET {
			if outs_cancelled(n) {
				return .Done
			}
			idx_completed: int
			for take_from_inlet(n, 0, &idx_completed) {
				st.slots[idx_completed].ready = true
			}
			if !out_ready(n) {
				return block(n)
			}
			emitted := false
			for &slot in st.slots {
				if slot.busy && slot.ready && (!st.ordered || slot.seq == st.next_emit) {
					emit(n, &slot.b)
					slot.busy = false
					slot.ready = false
					st.busy -= 1
					st.next_emit += 1
					emitted = true
					break
				}
			}
			if emitted {
				continue
			}
			if st.busy == len(st.slots) {
				return .Drained
			}
			a: A
			if !take_in(n, 0, &a) {
				return ins_ended(n) && st.busy == 0 ? .Done : .Drained
			}
			for &slot in st.slots {
				if slot.busy {
					continue
				}
				slot.a = a
				slot.seq = st.next_seq
				slot.busy = true
				st.next_seq += 1
				st.busy += 1
				submit(st.workers, job, &slot)
				break
			}
		}
		return .Budget
	}
	cleanup :: proc(n: ^Node) {
		st := (^Async_Map(A, B, S))(n.state)
		delete(st.slots, n.p.allocator)
	}
	n := add_node(
		s.p,
		name,
		run,
		Async_Map(A, B, S){workers = workers, state = state, f = f, ordered = ordered},
	)
	n.cleanup = cleanup
	n.one_to_one = true
	st := (^Async_Map(A, B, S))(n.state)
	st.slots = make([]Async_Slot(A, B, S), max(concurrency, 1), s.p.allocator)
	for &slot, ii in st.slots {
		slot.owner = st
		slot.idx = ii
	}
	st.inlet = add_inlet(s.p, n, ring.shape_of(int), len(st.slots))
	connect(s.p, s.node, n, ring.shape_of(A))
	return Stream(B){s.p, n.id}
}
