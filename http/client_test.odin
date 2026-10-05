package http

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:strings"
import "core:sync"
import "core:testing"
import "core:thread"
import "core:time"

import "jm:http/loopback"

// ---- fixtures -------------------------------------------------------------

// Seen is what a test's on_done calls have reported.
Seen :: struct {
	allocator: runtime.Allocator,
	mutex:     sync.Mutex,
	done:      sync.Sema,
	calls:     map[Handle]int,
	errs:      map[Handle]Error,
	status:    map[Handle]int,
	bodies:    map[Handle]string,
	// Set once shutdown has returned: a call after it is a broken promise.
	closed:    bool,
	late:      int,
	// Blocks the I/O thread inside on_done until posted, when set.
	gate:      ^sync.Sema,
	in_gate:   sync.Sema,
}

seen_make :: proc() -> ^Seen {
	s := new(Seen)
	s.allocator = context.allocator
	s.calls = make(map[Handle]int)
	s.errs = make(map[Handle]Error)
	s.status = make(map[Handle]int)
	s.bodies = make(map[Handle]string)
	return s
}

seen_destroy :: proc(s: ^Seen) {
	for _, b in s.bodies {
		delete(b)
	}
	delete(s.calls)
	delete(s.errs)
	delete(s.status)
	delete(s.bodies)
	free(s)
}

record :: proc(r: Result, user: rawptr) {
	s := (^Seen)(user)
	if gate := sync.atomic_load(&s.gate); gate != nil {
		sync.atomic_store(&s.gate, nil)
		sync.sema_post(&s.in_gate)
		sync.sema_wait(gate)
	}
	sync.guard(&s.mutex)
	if s.closed {
		s.late += 1
	}
	s.calls[r.handle] += 1
	s.errs[r.handle] = r.err
	s.status[r.handle] = r.response.status
	if old, had := s.bodies[r.handle]; had {
		delete(old, s.allocator)
	}
	s.bodies[r.handle] = strings.clone(r.response.body, s.allocator)
	sync.sema_post(&s.done)
}

// await waits for n on_done calls, and says whether they came in time.
await :: proc(s: ^Seen, n: int, within := 5 * time.Second) -> bool {
	for _ in 0 ..< n {
		if !sync.sema_wait_with_timeout(&s.done, within) {
			return false
		}
	}
	return true
}

// Env is a server, a client over a tracking allocator, and what on_done saw.
Env :: struct {
	srv:    ^loopback.Server,
	client: ^Client,
	seen:   ^Seen,
	gates:  ^Gates,
	track:  ^mem.Tracking_Allocator,
}

env_start :: proc(t: ^testing.T) -> (env: Env, ok: bool) {
	env.gates = new(Gates)
	env.srv = loopback.start(routes, env.gates, runtime.heap_allocator()) or_return
	env.seen = seen_make()
	env.track = new(mem.Tracking_Allocator)
	mem.tracking_allocator_init(env.track, runtime.heap_allocator())
	err: Error
	env.client, err = start(mem.tracking_allocator(env.track))
	testing.expect_value(t, err, Error.None)
	return env, err == .None
}

// env_stop shuts the client down, then fails the test if any allocation the
// client made is still live or any on_done call came after shutdown.
env_stop :: proc(t: ^testing.T, env: Env) {
	if env.client != nil {
		shutdown(env.client)
	}
	sync.lock(&env.seen.mutex)
	env.seen.closed = true
	testing.expect_value(t, env.seen.late, 0)
	sync.unlock(&env.seen.mutex)
	seen_destroy(env.seen)
	for _, leak in env.track.allocation_map {
		testing.expectf(t, false, "leaked %d bytes from %v", leak.size, leak.location)
	}
	testing.expect_value(t, len(env.track.bad_free_array), 0)
	loopback.stop(env.srv)
	mem.tracking_allocator_destroy(env.track)
	free(env.track)
	free(env.gates)
}

get_one :: proc(env: Env, path: string, req := Request{}) -> Handle {
	r := req
	r.url = loopback.url(env.srv, path)
	h, err := submit(env.client, r, record, env.seen)
	assert(err == .None)
	return h
}

// ---- the async client -----------------------------------------------------

@(test)
success_delivers_body_and_status :: proc(t: ^testing.T) {
	env := env_start(t) or_else panic("env")
	defer env_stop(t, env)
	h := get_one(env, "/ok")
	testing.expect(t, await(env.seen, 1))
	sync.guard(&env.seen.mutex)
	testing.expect_value(t, env.seen.errs[h], Error.None)
	testing.expect_value(t, env.seen.status[h], 200)
	testing.expect_value(t, env.seen.bodies[h], "hello")
}

@(test)
client_errors_are_responses :: proc(t: ^testing.T) {
	env := env_start(t) or_else panic("env")
	defer env_stop(t, env)
	a := get_one(env, "/404")
	b := get_one(env, "/500")
	testing.expect(t, await(env.seen, 2))
	sync.guard(&env.seen.mutex)
	testing.expect_value(t, env.seen.errs[a], Error.None)
	testing.expect_value(t, env.seen.status[a], 404)
	testing.expect_value(t, env.seen.bodies[a], "nope")
	testing.expect_value(t, env.seen.errs[b], Error.None)
	testing.expect_value(t, env.seen.status[b], 500)
}

@(test)
post_sends_the_body :: proc(t: ^testing.T) {
	env := env_start(t) or_else panic("env")
	defer env_stop(t, env)
	h := get_one(env, "/echo", {method = "POST", body = "ping"})
	testing.expect(t, await(env.seen, 1))
	sync.guard(&env.seen.mutex)
	testing.expect_value(t, env.seen.bodies[h], "ping")
}

@(test)
cancel_before_start :: proc(t: ^testing.T) {
	env := env_start(t) or_else panic("env")
	defer env_stop(t, env)
	// The I/O thread is held inside a's on_done, so b cannot have started.
	gate: sync.Sema
	sync.atomic_store(&env.seen.gate, &gate)
	get_one(env, "/ok")
	testing.expect(t, sync.sema_wait_with_timeout(&env.seen.in_gate, 5 * time.Second))
	b := get_one(env, "/ok")
	testing.expect(t, cancel(env.client, b), "the first cancel decides the outcome")
	sync.sema_post(&gate)
	testing.expect(t, await(env.seen, 2))
	sync.guard(&env.seen.mutex)
	testing.expect_value(t, env.seen.errs[b], Error.Cancelled)
	testing.expect_value(t, loopback.accepted(env.srv), 1)
}

@(test)
cancel_during_connect :: proc(t: ^testing.T) {
	env := env_start(t) or_else panic("env")
	defer env_stop(t, env)
	// The server never answers the TLS ClientHello, so the request is
	// accepted but never gets as far as sending its request line.
	url := fmt.tprintf("https://127.0.0.1:%d/ok", env.srv.port)
	h, _ := submit(env.client, {url = url}, record, env.seen)
	for loopback.accepted(env.srv) == 0 {
		time.sleep(time.Millisecond)
	}
	started := time.now()
	testing.expect(t, cancel(env.client, h))
	testing.expect(t, await(env.seen, 1))
	testing.expect(t, time.since(started) < time.Second, "cancel must not wait on the network")
	sync.guard(&env.seen.mutex)
	testing.expect_value(t, env.seen.errs[h], Error.Cancelled)
}

@(test)
cancel_while_waiting_for_headers :: proc(t: ^testing.T) {
	env := env_start(t) or_else panic("env")
	defer env_stop(t, env)
	h := get_one(env, "/silent")
	testing.expect(t, sync.sema_wait_with_timeout(&env.gates.arrived, 5 * time.Second))
	testing.expect(t, cancel(env.client, h))
	testing.expect(t, await(env.seen, 1))
	sync.guard(&env.seen.mutex)
	testing.expect_value(t, env.seen.errs[h], Error.Cancelled)
}

@(test)
cancel_mid_body :: proc(t: ^testing.T) {
	env := env_start(t) or_else panic("env")
	defer env_stop(t, env)
	h := get_one(env, "/half")
	testing.expect(t, sync.sema_wait_with_timeout(&env.gates.arrived, 5 * time.Second))
	// Long enough for curl to have read the ten bytes that were sent.
	time.sleep(50 * time.Millisecond)
	testing.expect(t, cancel(env.client, h))
	testing.expect(t, await(env.seen, 1))
	sync.guard(&env.seen.mutex)
	testing.expect_value(t, env.seen.errs[h], Error.Cancelled)
	testing.expect_value(t, env.seen.bodies[h], "")
}

@(test)
cancel_after_completion_is_refused :: proc(t: ^testing.T) {
	env := env_start(t) or_else panic("env")
	defer env_stop(t, env)
	h := get_one(env, "/ok")
	testing.expect(t, await(env.seen, 1))
	testing.expect(t, !cancel(env.client, h), "a finished request cannot be cancelled")
	testing.expect(t, !cancel(env.client, 0), "0 names no request")
	testing.expect(t, !cancel(env.client, h + 1000), "nor does a handle never issued")
	sync.guard(&env.seen.mutex)
	testing.expect_value(t, env.seen.errs[h], Error.None)
	testing.expect_value(t, env.seen.calls[h], 1)
}

@(test)
double_cancel_reports_once :: proc(t: ^testing.T) {
	env := env_start(t) or_else panic("env")
	defer env_stop(t, env)
	h := get_one(env, "/silent")
	testing.expect(t, cancel(env.client, h))
	testing.expect(t, !cancel(env.client, h), "the second cancel decides nothing")
	testing.expect(t, await(env.seen, 1))
	time.sleep(50 * time.Millisecond)
	sync.guard(&env.seen.mutex)
	testing.expect_value(t, env.seen.calls[h], 1)
	testing.expect_value(t, env.seen.errs[h], Error.Cancelled)
}

@(test)
timeout_ends_a_slow_request :: proc(t: ^testing.T) {
	env := env_start(t) or_else panic("env")
	defer env_stop(t, env)
	started := time.now()
	h := get_one(env, "/delay/5000", {timeout = 100 * time.Millisecond})
	testing.expect(t, await(env.seen, 1))
	took := time.since(started)
	testing.expectf(t, took >= 100 * time.Millisecond && took < time.Second, "took %v", took)
	sync.guard(&env.seen.mutex)
	testing.expect_value(t, env.seen.errs[h], Error.Timed_Out)
}

@(test)
deadline_ends_a_slow_request :: proc(t: ^testing.T) {
	env := env_start(t) or_else panic("env")
	defer env_stop(t, env)
	by := time.time_add(time.now(), 100 * time.Millisecond)
	h := get_one(env, "/delay/5000", {deadline = by})
	past := get_one(env, "/ok", {deadline = time.time_add(time.now(), -time.Second)})
	testing.expect(t, await(env.seen, 2))
	testing.expect(t, time.diff(by, time.now()) < time.Second)
	sync.guard(&env.seen.mutex)
	testing.expect_value(t, env.seen.errs[h], Error.Timed_Out)
	testing.expect_value(t, env.seen.errs[past], Error.Timed_Out)
}

@(test)
oversized_body_is_refused :: proc(t: ^testing.T) {
	env := env_start(t) or_else panic("env")
	defer env_stop(t, env)
	// Chunked, so max_body must be enforced while the body grows.
	h := get_one(env, "/big", {max_body = 1000})
	fits := get_one(env, "/big", {max_body = 4096})
	testing.expect(t, await(env.seen, 2))
	sync.guard(&env.seen.mutex)
	testing.expect_value(t, env.seen.errs[h], Error.Too_Large)
	testing.expect_value(t, env.seen.errs[fits], Error.None)
	testing.expect_value(t, len(env.seen.bodies[fits]), 4096)
}

@(test)
declared_length_over_the_limit_is_refused :: proc(t: ^testing.T) {
	env := env_start(t) or_else panic("env")
	defer env_stop(t, env)
	h := get_one(env, "/declared", {max_body = 1000})
	testing.expect(t, await(env.seen, 1, time.Second), "refused on the header, not on a deadline")
	sync.guard(&env.seen.mutex)
	testing.expect_value(t, env.seen.errs[h], Error.Too_Large)
}

@(test)
transport_error_is_reported :: proc(t: ^testing.T) {
	env := env_start(t) or_else panic("env")
	defer env_stop(t, env)
	// Port 1 on loopback refuses the connection.
	h, _ := submit(env.client, {url = "http://127.0.0.1:1/"}, record, env.seen)
	testing.expect(t, await(env.seen, 1))
	sync.guard(&env.seen.mutex)
	testing.expect_value(t, env.seen.errs[h], Error.Transfer_Failed)
}

@(test)
shutdown_cancels_requests_in_flight :: proc(t: ^testing.T) {
	env := env_start(t) or_else panic("env")
	handles: [8]Handle
	for &h in handles {
		h = get_one(env, "/silent")
	}
	for _ in handles {
		testing.expect(t, sync.sema_wait_with_timeout(&env.gates.arrived, 5 * time.Second))
	}
	queued := get_one(env, "/silent")
	shutdown(env.client)
	env.client = nil
	{
		sync.guard(&env.seen.mutex)
		for h in handles {
			testing.expect_value(t, env.seen.calls[h], 1)
			testing.expect_value(t, env.seen.errs[h], Error.Cancelled)
		}
		testing.expect_value(t, env.seen.calls[queued], 1)
	}
	env_stop(t, env)
}

@(test)
submit_after_shutdown_began_is_refused :: proc(t: ^testing.T) {
	env := env_start(t) or_else panic("env")
	defer env_stop(t, env)
	s := (^State)(env.client)
	sync.lock(&s.mutex)
	s.closing = true
	sync.unlock(&s.mutex)
	h, err := submit(env.client, {url = loopback.url(env.srv, "/ok")}, record, env.seen)
	testing.expect_value(t, h, Handle(0))
	testing.expect_value(t, err, Error.Closed)
}

Swarm :: struct {
	env:     ^Env,
	handles: []Handle,
}

@(test)
many_concurrent_requests :: proc(t: ^testing.T) {
	env := env_start(t) or_else panic("env")
	defer env_stop(t, env)
	PER_THREAD :: 50
	swarms: [4]Swarm
	threads: [4]^thread.Thread
	for &s, i in swarms {
		s = {&env, make([]Handle, PER_THREAD)}
		threads[i] = thread.create_and_start_with_poly_data(&s, proc(s: ^Swarm) {
			for &h, i in s.handles {
				h = get_one(s.env^, "/ok" if i % 3 != 0 else "/404")
			}
		})
	}
	for th in threads {
		thread.join(th)
		thread.destroy(th)
	}
	testing.expect(t, await(env.seen, len(swarms) * PER_THREAD, 10 * time.Second))
	sync.guard(&env.seen.mutex)
	testing.expect_value(t, len(env.seen.calls), len(swarms) * PER_THREAD)
	for s in swarms {
		for h, i in s.handles {
			testing.expect_value(t, env.seen.calls[h], 1)
			testing.expect_value(t, env.seen.errs[h], Error.None)
			testing.expect_value(t, env.seen.status[h], 200 if i % 3 != 0 else 404)
		}
		delete(s.handles)
	}
}
