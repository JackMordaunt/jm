package http_fuzz

import "base:runtime"
import "core:fmt"
import "core:sync"
import "core:thread"
import "core:time"

import harness "jm:fuzz"
import "jm:http"

// Model_Request is one request of a model case: what was drawn for it, then
// what the drivers and on_done saw. Everything after the drawn fields is
// guarded by Model.mutex.
Model_Request :: struct {
	model:          ^Model,
	status:         int,
	delay:          time.Duration,
	length:         int,
	chunked:        bool,
	timeout:        time.Duration,
	max_body:       int,
	// A request this one's on_done cancels, and one it submits; -1 is none.
	then_cancel:    int,
	follow:         int,
	state:          enum {
		Unsent,
		Accepted,
		Refused,
	},
	refusal:        http.Error,
	// shutdown had begun when submit refused it.
	refused_late:   bool,
	handle:         http.Handle,
	submitted:      time.Time,
	cancel_yes:     int,
	// cancel said yes to a request whose on_done had already fired.
	yes_after_done: bool,
	calls:          int,
	err:            http.Error,
	got_status:     int,
	got_length:     int,
	done_at:        time.Time,
}

Model :: struct {
	mutex:       sync.Mutex,
	client:      ^http.Client,
	port:        int,
	recs:        []Model_Request,
	shutting:    bool,
	shutdown_at: time.Time,
	closed:      bool,
	// on_done calls after shutdown returned.
	late:        int,
	// cancel said yes to a handle that was never issued.
	stale_yes:   int,
}

Op_Kind :: enum {
	Submit,
	Cancel,
	Cancel_Stale,
	Sleep,
}

Op :: struct {
	kind:   Op_Kind,
	target: int,
	ms:     int,
}

// Hangs is a delay no deadline in a case reaches: the request ends only by
// its timeout, a cancel, or shutdown.
HANG :: 10 * time.Second

// exactly_once runs submits and cancels from two threads against requests
// the server delays, then shuts down at a drawn moment, and holds every
// request to the model.
exactly_once :: proc(s: Subject, src: ^harness.Source) -> (detail: string, ok: bool) {
	w: Watch
	if !watch_start(&w) {
		return "http.start failed", false
	}
	m := new(Model)
	m.client = w.client
	m.port = s.srv.port
	direct := harness.integer_in(src, 1, 13)
	follows := harness.integer_in(src, 0, 4)
	m.recs = make([]Model_Request, direct + follows)
	for &r, i in m.recs {
		draw_request(src, m, &r, i, direct)
	}
	ops: [2][]Op
	for &list, k in ops {
		list = draw_ops(src, direct, k)
	}

	other: ^thread.Thread
	{
		// The thread's record outlives no case, but is made beside threads
		// that are running, and the case's arena is not thread-safe.
		context.allocator = runtime.heap_allocator()
		other = thread.create_and_start_with_poly_data2(m, ops[1], drive)
	}
	drive(m, ops[0])
	thread.join(other)
	thread.destroy(other)

	time.sleep(
		time.Duration(harness.integer_in(src, 0, 4) * harness.integer_in(src, 0, 60)) *
		time.Millisecond,
	)
	sync.lock(&m.mutex)
	m.shutting = true
	m.shutdown_at = time.now()
	sync.unlock(&m.mutex)
	leaked := watch_stop(&w)
	sync.lock(&m.mutex)
	m.closed = true
	sync.unlock(&m.mutex)

	if bad := judge_model(m); bad != "" {
		return bad, false
	}
	return leaked, leaked == ""
}

draw_request :: proc(src: ^harness.Source, m: ^Model, r: ^Model_Request, i, direct: int) {
	r.model = m
	r.status = harness.choice(src, []int{200, 201, 204, 404, 500})
	if r.status == 204 {
		r.length = 0
	} else {
		r.length = harness.choice(src, []int{0, 5, 100, 2000, 70_000})
	}
	r.chunked = harness.boolean(src)
	r.delay = time.Duration(harness.integer_in(src, 0, 200)) * time.Millisecond
	if harness.integer_in(src, 0, 6) == 0 {
		r.delay = HANG
	}
	switch harness.integer_in(src, 0, 4) {
	case 0, 1:
		r.timeout = time.Duration(harness.integer_in(src, 10, 400)) * time.Millisecond
	case 2:
		// Loose: timing this request out is a fault unless the answer came
		// more than SLACK late, which the judge allows for.
		r.timeout = r.delay + 2 * SLACK
	}
	r.max_body = harness.choice(src, []int{0, 50, 1000})
	r.then_cancel, r.follow = -1, -1
	if harness.integer_in(src, 0, 3) == 0 {
		r.then_cancel = harness.integer_in(src, 0, len(m.recs))
	}
	// Each follow-up has one parent, drawn among the direct requests.
	if i >= direct {
		parent := &m.recs[harness.integer_in(src, 0, direct)]
		if parent.follow < 0 {
			parent.follow = i
		}
	}
}

// draw_ops gives thread k its list: it submits the direct requests whose
// index has its parity, in order, with cancels and sleeps between.
draw_ops :: proc(src: ^harness.Source, direct, k: int) -> []Op {
	out := make([dynamic]Op)
	next := k
	// Bounded by draws, not by ops: entropy that has run out draws zeroes,
	// and a zero asks for nothing to be added.
	for draws := 0;
	    draws < 64 && (next < direct || harness.integer_in(src, 0, 3) == 0);
	    draws += 1 {
		switch harness.integer_in(src, 0, 6) {
		case 0, 1, 2:
			if next < direct {
				append(&out, Op{kind = .Submit, target = next})
				next += 2
			}
		case 3:
			append(&out, Op{kind = .Cancel, target = harness.integer_in(src, 0, direct)})
		case 4:
			append(&out, Op{kind = .Sleep, ms = harness.integer_in(src, 0, 30)})
		case 5:
			append(&out, Op{kind = .Cancel_Stale})
		}
	}
	return out[:]
}

drive :: proc(m: ^Model, ops: []Op) {
	for op in ops {
		switch op.kind {
		case .Submit:
			send(m, op.target)
		case .Cancel:
			cancel_request(m, op.target)
		case .Cancel_Stale:
			if http.cancel(m.client, http.Handle(1 << 40)) {
				sync.guard(&m.mutex)
				m.stale_yes += 1
			}
		case .Sleep:
			time.sleep(time.Duration(op.ms) * time.Millisecond)
		}
	}
}

send :: proc(m: ^Model, i: int) {
	r := &m.recs[i]
	url: [128]byte
	req := http.Request {
		url      = fmt.bprintf(
			url[:],
			"http://127.0.0.1:%d/m/%d/%d/%d/%d",
			m.port,
			r.status,
			int(r.delay / time.Millisecond),
			r.length,
			int(r.chunked),
		),
		timeout  = r.timeout,
		max_body = r.max_body,
	}
	sync.lock(&m.mutex)
	r.submitted = time.now()
	sync.unlock(&m.mutex)
	h, err := http.submit(m.client, req, on_model_done, r)
	sync.guard(&m.mutex)
	if err == .None {
		r.state, r.handle = .Accepted, h
	} else {
		r.state, r.refusal, r.refused_late = .Refused, err, m.shutting
	}
}

cancel_request :: proc(m: ^Model, i: int) {
	r := &m.recs[i]
	sync.lock(&m.mutex)
	h, done := r.handle, r.calls > 0
	sync.unlock(&m.mutex)
	if h == 0 {
		return
	}
	yes := http.cancel(m.client, h)
	sync.guard(&m.mutex)
	if yes {
		r.cancel_yes += 1
		r.yes_after_done |= done
	}
}

on_model_done :: proc(res: http.Result, user: rawptr) {
	r := (^Model_Request)(user)
	m := r.model
	sync.lock(&m.mutex)
	r.calls += 1
	r.err = res.err
	r.got_status = res.response.status
	r.got_length = len(res.response.body)
	r.done_at = time.now()
	if m.closed {
		m.late += 1
	}
	then_cancel, follow := r.then_cancel, r.follow
	sync.unlock(&m.mutex)
	if then_cancel >= 0 {
		cancel_request(m, then_cancel)
	}
	if follow >= 0 {
		send(m, follow)
	}
}

// judge_model holds each request to what the model allows, after shutdown.
judge_model :: proc(m: ^Model) -> string {
	if m.late > 0 {
		return fmt.tprintf("%d on_done calls after shutdown returned", m.late)
	}
	if m.stale_yes > 0 {
		return "cancel said yes to a handle never issued"
	}
	for &r, i in m.recs {
		if bad := judge_request(m, &r); bad != "" {
			return fmt.tprintf("request %d (%v): %s", i, summary(&r), bad)
		}
	}
	return ""
}

judge_request :: proc(m: ^Model, r: ^Model_Request) -> string {
	switch r.state {
	case .Unsent:
		return "" if r.calls == 0 else "on_done fired for a request never submitted"
	case .Refused:
		if r.calls != 0 {
			return "on_done fired for a refused request"
		}
		if r.refusal != .Closed || !r.refused_late {
			return fmt.tprintf("submit refused with %v before shutdown", r.refusal)
		}
		return ""
	case .Accepted:
	}
	took := time.diff(r.submitted, r.done_at)
	limit := r.max_body if r.max_body > 0 else http.DEFAULT_MAX_BODY
	switch {
	case r.calls != 1:
		return fmt.tprintf("on_done fired %d times", r.calls)
	case r.cancel_yes > 1:
		return fmt.tprintf("cancel said yes %d times", r.cancel_yes)
	case r.yes_after_done:
		return "cancel said yes after on_done had fired"
	case r.cancel_yes == 1 && r.err != .Cancelled:
		return fmt.tprintf("cancel said yes, on_done said %v", r.err)
	case r.err == .Cancelled && r.cancel_yes == 0 && time.diff(m.shutdown_at, r.done_at) < 0:
		return "Cancelled before shutdown, with no cancel"
	}
	switch r.err {
	case .None:
		switch {
		case r.got_status != r.status || r.got_length != r.length:
			return fmt.tprintf("got %d with %d bytes", r.got_status, r.got_length)
		case r.length > limit:
			return "a body past its limit was delivered"
		case took < r.delay:
			return fmt.tprintf("answered in %v, before the server's %v delay", took, r.delay)
		}
	case .Too_Large:
		if r.length <= limit {
			return "Too_Large for a body within its limit"
		}
	case .Timed_Out:
		switch {
		case r.timeout == 0:
			return "Timed_Out with no timeout"
		case took < r.timeout - time.Millisecond:
			return fmt.tprintf("Timed_Out after %v, before its %v timeout", took, r.timeout)
		case r.delay + SLACK < r.timeout:
			return fmt.tprintf("Timed_Out though the server answered after %v", r.delay)
		}
	case .Cancelled:
	case .Transfer_Failed, .Init_Failed, .Write_Failed, .Encode_Failed, .Decode_Failed, .Closed:
		return fmt.tprintf("%v from a well-formed server", r.err)
	}
	if r.timeout > 0 && r.err != .Cancelled && took > r.timeout + SLACK {
		return fmt.tprintf("%v after %v, past its %v timeout", r.err, took, r.timeout)
	}
	return ""
}

summary :: proc(r: ^Model_Request) -> string {
	return fmt.tprintf(
		"%d, %d bytes%s after %v, timeout %v, max %d, cancels %d",
		r.status,
		r.length,
		" chunked" if r.chunked else "",
		r.delay,
		r.timeout,
		r.max_body,
		r.cancel_yes,
	)
}
