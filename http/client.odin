package http

import "base:runtime"
import "core:c"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"

import curl "vendor:curl"

/*
A Client runs requests on one I/O thread of its own, so a caller with a frame
to draw never waits on the network.

	client, _ := http.start()
	defer http.shutdown(client)

	h, _ := http.submit(client, {url = url, timeout = 10 * time.Second}, on_done, &state)
	http.cancel(client, h)   // from any thread; on_done still fires, with .Cancelled

on_done fires exactly once for every request submit accepted: with a
response, a transport error, .Too_Large, .Timed_Out or .Cancelled. It runs
on the client's thread, never after shutdown returns, and is the whole of the
seam to a UI: post what it carries into an inbox and wake the frame loop.
The Result it is handed is borrowed; clone what must outlive the call.

cancel returns true when it decided the outcome: that request's on_done will
carry .Cancelled. It returns false for a request already finished, already
cancelled, or never submitted, so calling it twice is harmless.
*/

// Handle names a submitted request. Handles are never reused, so a stale
// one is safe to cancel. 0 is no request.
Handle :: distinct u64

// Request is one request for submit. Nothing in it need outlive submit.
Request :: struct {
	// "" is GET.
	method:     string,
	url:        string,
	// Extra request headers as "Name: value".
	headers:    []string,
	body:       string,
	// How long the request may take from submit, queueing included. 0 is no
	// limit.
	timeout:    time.Duration,
	// When the request must be done by. The zero Time is none; with both
	// set, the earlier wins.
	deadline:   time.Time,
	// The most body bytes the response may carry. 0 is DEFAULT_MAX_BODY.
	max_body:   int,
	// Do not follow redirects. They are followed by default.
	no_follow:  bool,
	// Skip TLS certificate verification. For local development only.
	insecure:   bool,
	user_agent: string,
}

// Result is how a request ended. response is set only when err is .None;
// its body and headers belong to the client and are freed when on_done
// returns. message is curl's account of a failure it reported, or "".
Result :: struct {
	handle:   Handle,
	err:      Error,
	response: Response,
	message:  string,
}

// Done is called once per request, on the client's thread. It may submit
// and cancel, but must not call shutdown, which would wait for itself.
// context.temp_allocator is the client thread's, freed soon after it returns.
Done :: #type proc(result: Result, user: rawptr)

// The body limit a Request with max_body = 0 gets.
DEFAULT_MAX_BODY :: 64 * 1024 * 1024
// The most response-header bytes a request may receive, redirects included.
MAX_HEAD :: 256 * 1024

// Client is opaque: everything about it goes through start, submit, cancel
// and shutdown, so a backend other than curl could stand behind them.
Client :: struct {}

// start makes a client and its I/O thread. allocator must be thread-safe:
// submit allocates on the caller's thread and the I/O thread frees.
start :: proc(allocator := context.allocator) -> (^Client, Error) {
	global_init()
	s := new(State, allocator)
	s.allocator = allocator
	s.logger = context.logger
	s.multi = curl.multi_init()
	if s.multi == nil {
		free(s, allocator)
		return nil, .Init_Failed
	}
	s.live = make(map[Handle]^Transfer, allocator)
	s.queue = make([dynamic]^Transfer, allocator)
	s.cancels = make([dynamic]Handle, allocator)
	s.active = make([dynamic]^Transfer, allocator)
	context.allocator = allocator
	s.thread = thread.create_and_start_with_poly_data(s, pump)
	return (^Client)(s), .None
}

// submit queues req and returns its handle at once. Every string in req is
// copied. When it returns an error, req was not accepted and on_done will
// not fire: .Init_Failed when curl could not make a handle, .Closed when
// shutdown has begun.
submit :: proc(
	client: ^Client,
	req: Request,
	on_done: Done,
	user: rawptr = nil,
) -> (
	Handle,
	Error,
) {
	assert(on_done != nil, "http.submit needs an on_done to report the result to")
	s := (^State)(client)
	t := new(Transfer, s.allocator)
	t.on_done, t.user = on_done, user
	t.deadline = deadline_of(req)
	// curl copies every string option but the body.
	t.body = strings.clone(req.body, s.allocator)
	t.body_buf = strings.builder_make(s.allocator)
	t.head_buf = strings.builder_make(s.allocator)
	t.wire.body.w = strings.to_writer(&t.body_buf)
	t.wire.head.w = strings.to_writer(&t.head_buf)
	spec := Spec {
		method     = req.method,
		url        = req.url,
		headers    = req.headers,
		body       = t.body,
		user_agent = req.user_agent,
		no_follow  = req.no_follow,
		insecure   = req.insecure,
		max_body   = req.max_body if req.max_body > 0 else DEFAULT_MAX_BODY,
		max_head   = MAX_HEAD,
	}
	t.easy = prepare(spec, &t.wire)
	if t.easy == nil {
		destroy(s, t)
		return 0, .Init_Failed
	}
	curl.easy_setopt(t.easy, .PRIVATE, t)

	sync.guard(&s.mutex)
	if s.closing {
		destroy(s, t)
		return 0, .Closed
	}
	s.next += 1
	t.handle = s.next
	s.live[t.handle] = t
	append(&s.queue, t)
	curl.multi_wakeup(s.multi)
	return t.handle, .None
}

// cancel ends the request h names, from any thread. It returns true when
// the request's on_done will carry .Cancelled because of this call, and
// false when the request had already finished or been cancelled.
cancel :: proc(client: ^Client, h: Handle) -> bool {
	s := (^State)(client)
	sync.guard(&s.mutex)
	t, found := s.live[h]
	if !found || t.cancelled {
		return false
	}
	t.cancelled = true
	append(&s.cancels, h)
	curl.multi_wakeup(s.multi)
	return true
}

// shutdown cancels every request still pending, waits for their on_done
// calls, joins the I/O thread and frees the client. No on_done runs after it
// returns. The client must not be used again, from any thread.
shutdown :: proc(client: ^Client) {
	s := (^State)(client)
	sync.lock(&s.mutex)
	assert(
		s.thread_id != sync.current_thread_id(),
		"http.shutdown called from on_done would wait for its own thread",
	)
	s.closing = true
	curl.multi_wakeup(s.multi)
	sync.unlock(&s.mutex)

	thread.join(s.thread)
	thread.destroy(s.thread)
	assert(len(s.live) == 0 && len(s.active) == 0, "http: a request outlived its client")
	curl.multi_cleanup(s.multi)
	delete(s.live)
	delete(s.queue)
	delete(s.cancels)
	delete(s.active)
	free(s, s.allocator)
}

// ---- the I/O thread ------------------------------------------------------

// State is the client behind the opaque pointer.
@(private)
State :: struct {
	allocator: runtime.Allocator,
	logger:    runtime.Logger,
	multi:     ^curl.CURLM,
	thread:    ^thread.Thread,
	// Guards everything down to active, and Transfer.cancelled.
	mutex:     sync.Mutex,
	thread_id: int,
	// Every request accepted and not yet retired, by handle.
	live:      map[Handle]^Transfer,
	// Accepted but not yet seen by the I/O thread.
	queue:     [dynamic]^Transfer,
	cancels:   [dynamic]Handle,
	closing:   bool,
	next:      Handle,
	// The I/O thread's own: the requests in the multi handle.
	active:    [dynamic]^Transfer,
}

// Transfer is one request from submit to retire.
@(private)
Transfer :: struct {
	handle:    Handle,
	easy:      ^curl.CURL,
	wire:      Wire,
	on_done:   Done,
	user:      rawptr,
	// The zero Time is none.
	deadline:  time.Time,
	body:      string,
	body_buf:  strings.Builder,
	head_buf:  strings.Builder,
	// In the multi handle; the I/O thread's own.
	added:     bool,
	// Guarded by State.mutex. Once set, retire reports .Cancelled whatever
	// else happened, which is what makes cancel's answer true.
	cancelled: bool,
}

// pump is the I/O thread: take what other threads asked for, move the
// transfers on, report what finished, and sleep until there is more.
@(private)
pump :: proc(s: ^State) {
	context.allocator = s.allocator
	context.logger = s.logger
	sync.lock(&s.mutex)
	s.thread_id = sync.current_thread_id()
	sync.unlock(&s.mutex)

	incoming := make([dynamic]^Transfer)
	cancels := make([dynamic]Handle)
	defer delete(incoming)
	defer delete(cancels)
	for {
		closing := take(s, &incoming, &cancels)
		for t in incoming {
			admit(s, t, closing)
		}
		for h in cancels {
			drop(s, h)
		}
		if closing {
			break
		}
		expire(s)
		running: c.int
		curl.multi_perform(s.multi, &running)
		harvest(s)
		// What on_done put on the temp allocator lives until it returns.
		free_all(context.temp_allocator)
		curl.multi_poll(s.multi, nil, 0, poll_timeout(s), nil)
	}
	for len(s.active) > 0 {
		retire(s, s.active[len(s.active) - 1], .Cancelled, "")
	}
}

// take moves what other threads queued into the I/O thread's own lists,
// and says whether shutdown has begun.
@(private)
take :: proc(s: ^State, incoming: ^[dynamic]^Transfer, cancels: ^[dynamic]Handle) -> bool {
	sync.guard(&s.mutex)
	clear(incoming)
	clear(cancels)
	append(incoming, ..s.queue[:])
	append(cancels, ..s.cancels[:])
	clear(&s.queue)
	clear(&s.cancels)
	return s.closing
}

// admit hands a new transfer to curl, or ends it at once when its deadline
// has passed or the client is closing.
@(private)
admit :: proc(s: ^State, t: ^Transfer, closing: bool) {
	if closing {
		retire(s, t, .Cancelled, "")
		return
	}
	if t.deadline != {} {
		left := time.diff(time.now(), t.deadline)
		if left <= 0 {
			retire(s, t, .Timed_Out, "")
			return
		}
		// curl's own limit as well as ours, so it stops resolving and
		// connecting on time too. Rounded up, so it never fires early.
		curl.easy_setopt(t.easy, .TIMEOUT_MS, c.long(ceil_ms(left)))
	}
	// The sinks run on this thread from now on.
	t.wire.body.ctx = context
	t.wire.head.ctx = context
	if curl.multi_add_handle(s.multi, t.easy) != .OK {
		retire(s, t, .Init_Failed, "")
		return
	}
	t.added = true
	append(&s.active, t)
}

// drop ends a cancelled request if it has not ended already.
@(private)
drop :: proc(s: ^State, h: Handle) {
	sync.lock(&s.mutex)
	t, found := s.live[h]
	sync.unlock(&s.mutex)
	if found {
		retire(s, t, .Cancelled, "")
	}
}

// expire ends every active request whose deadline has passed.
@(private)
expire :: proc(s: ^State) {
	now := time.now()
	// Backwards, because retire moves the last transfer into the gap it
	// leaves, and that one has been looked at already.
	for i := len(s.active) - 1; i >= 0; i -= 1 {
		t := s.active[i]
		if t.deadline != {} && time.diff(now, t.deadline) <= 0 {
			retire(s, t, .Timed_Out, "")
		}
	}
}

// harvest reports every transfer curl says has finished.
@(private)
harvest :: proc(s: ^State) {
	for {
		left: c.int
		msg := curl.multi_info_read(s.multi, &left)
		if msg == nil {
			return
		}
		if msg.msg != .DONE {
			continue
		}
		t: ^Transfer
		curl.easy_getinfo(msg.easy_handle, .PRIVATE, &t)
		code := msg.data.result
		err := classify(code, &t.wire)
		retire(s, t, err, "" if err == .None else failure(code, &t.wire))
	}
}

// poll_timeout is how long the loop may sleep: until the nearest deadline, and
// never more than a second. curl shortens it for its own timers, and a
// submit or cancel wakes it early.
@(private)
poll_timeout :: proc(s: ^State) -> c.int {
	wait := time.Second
	now := time.now()
	for t in s.active {
		if t.deadline != {} {
			wait = min(wait, max(time.diff(now, t.deadline), 0))
		}
	}
	// Rounded up, so the loop wakes after the deadline rather than just before.
	return c.int(ceil_ms(wait))
}

// ceil_ms is d in whole milliseconds, rounded up.
@(private)
ceil_ms :: proc(d: time.Duration) -> i64 {
	return i64((d + time.Millisecond - 1) / time.Millisecond)
}

// retire ends a transfer: out of curl, out of the live set, its one on_done
// call, and its memory freed. It is the only place on_done is called.
@(private)
retire :: proc(s: ^State, t: ^Transfer, err: Error, message: string) {
	if t.added {
		curl.multi_remove_handle(s.multi, t.easy)
		for a, i in s.active {
			if a == t {
				unordered_remove(&s.active, i)
				break
			}
		}
	}
	err := err
	message := message
	sync.lock(&s.mutex)
	if t.cancelled {
		err, message = .Cancelled, ""
	}
	delete_key(&s.live, t.handle)
	sync.unlock(&s.mutex)

	result := Result {
		handle  = t.handle,
		err     = err,
		message = message,
	}
	if err == .None {
		status := status_of(t.easy)
		result.response = Response {
			status  = status,
			ok      = status >= 200 && status < 300,
			body    = strings.to_string(t.body_buf),
			headers = strings.to_string(t.head_buf),
		}
	}
	t.on_done(result, t.user)
	destroy(s, t)
}

// destroy frees a transfer and its curl handle.
@(private)
destroy :: proc(s: ^State, t: ^Transfer) {
	if t.easy != nil {
		curl.easy_cleanup(t.easy)
	}
	curl.slist_free_all(t.wire.list)
	strings.builder_destroy(&t.body_buf)
	strings.builder_destroy(&t.head_buf)
	delete(t.body, s.allocator)
	free(t, s.allocator)
}

// deadline_of is the earlier of req's deadline and its timeout from now.
@(private)
deadline_of :: proc(req: Request) -> time.Time {
	d := req.deadline
	if req.timeout > 0 {
		by := time.time_add(time.now(), req.timeout)
		if d == {} || time.diff(by, d) > 0 {
			d = by
		}
	}
	return d
}
