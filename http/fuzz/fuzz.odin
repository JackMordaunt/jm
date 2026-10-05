/*
Package fuzz holds the jm:http suites for jm:fuzz. Both aim at the promise
the Client makes: on_done fires exactly once per accepted request, never after
shutdown returns, and nothing the client allocated outlives it.

	report := fuzz.run_wire({seed = 1, iterations = 1000})
	report  = fuzz.run_model({seed = 1, iterations = 1000})

	http_wire   wire       a loopback server answers with drawn bytes: broken
	                       status lines, bad and duplicate headers, wrong
	                       lengths, broken chunking, oversized parts, a slow
	                       drip, an early close or silence. No crash, no hang
	                       past a request's deadline, no leak, one completion.
	http_model  exactly_once  random submits, cancels and server delays from
	                       two threads, then shutdown at a random moment,
	                       checked against a model of what each request may
	                       report.

Both run requests against real sockets and threads, so a case is not a pure
function of its entropy: the entropy fixes what is asked and when, and the
scheduler decides the rest. A failure replays the same requests, and a race
that needed one exact interleaving may take several replays to show again.
*/
package http_fuzz

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:time"

import harness "jm:fuzz"
import "jm:http"
import "jm:http/loopback"

// Subject is one loopback server, and the scripts it answers with.
Subject :: struct {
	srv:   ^loopback.Server,
	table: ^Table,
}

// Table maps a script's id, the last segment of /s/<id>, to the script.
Table :: struct {
	mutex:   sync.Mutex,
	scripts: map[int]Script,
}

// Script is what the server does once it has read a request: send each step
// after its pause, then close the connection or hold it open in silence.
Script :: struct {
	steps: []Step,
	hang:  bool,
}

Step :: struct {
	pause: time.Duration,
	bytes: string,
}

wire_properties := []harness.Property(Subject){{"wire", wire}}
model_properties := []harness.Property(Subject){{"exactly_once", exactly_once}}

// The corpora, relative to the repository root.
WIRE_CORPUS  :: "http/fuzz/corpus/wire"
MODEL_CORPUS :: "http/fuzz/corpus/model"

wire_suite :: proc() -> harness.Suite(Subject) {
	return harness.Suite(Subject) {
		name       = "http_wire",
		setup      = setup,
		teardown   = teardown,
		// No cancel: every request carries a deadline, and missing one is
		// the failure being looked for. -isolate bounds a case that hangs.
		properties = wire_properties,
	}
}

model_suite :: proc() -> harness.Suite(Subject) {
	return harness.Suite(Subject) {
		name = "http_model",
		setup = setup,
		teardown = teardown,
		properties = model_properties,
	}
}

run_wire :: proc(opts := harness.Opts{}, allocator := context.allocator) -> harness.Report {
	return harness.run(wire_suite(), opts, allocator)
}

run_model :: proc(opts := harness.Opts{}, allocator := context.allocator) -> harness.Report {
	return harness.run(model_suite(), opts, allocator)
}

// The server's threads and the client's run outside the case's arena, which
// is not thread-safe, so everything they touch comes from the heap.
setup :: proc() -> (Subject, bool) {
	heap := runtime.heap_allocator()
	table := new(Table, heap)
	table.scripts = make(map[int]Script, heap)
	srv, ok := loopback.start(answer, table, heap)
	if !ok {
		delete(table.scripts)
		free(table, heap)
		return {}, false
	}
	return Subject{srv, table}, true
}

teardown :: proc(s: ^Subject) {
	loopback.stop(s.srv)
	delete(s.table.scripts)
	free(s.table, runtime.heap_allocator())
}

// register files sc under id for the server to play.
register :: proc(s: Subject, id: int, sc: Script) {
	sync.guard(&s.table.mutex)
	s.table.scripts[id] = sc
}

// answer serves /s/<id> from the table and /m/<status>/<delay>/<length>/<chunked>
// as a well-formed response, for the model.
answer :: proc(conn: ^loopback.Conn, req: loopback.Request) {
	table := (^Table)(conn.server.user)
	switch {
	case strings.has_prefix(req.path, "/s/"):
		id, _ := strconv.parse_int(req.path[3:])
		sync.lock(&table.mutex)
		sc, found := table.scripts[id]
		sync.unlock(&table.mutex)
		if found {
			play(conn, sc)
		}
	case strings.has_prefix(req.path, "/m/"):
		serve_model(conn, req.path[3:])
	}
}

play :: proc(conn: ^loopback.Conn, sc: Script) {
	for step in sc.steps {
		if !loopback.pause(conn, step.pause) || !loopback.send(conn, step.bytes) {
			return
		}
	}
	if sc.hang {
		loopback.hold(conn)
	}
}

serve_model :: proc(conn: ^loopback.Conn, spec: string) {
	parts: [4]int
	rest := spec
	for &p in parts {
		end := strings.index_byte(rest, '/')
		field := rest if end < 0 else rest[:end]
		p, _ = strconv.parse_int(field)
		rest = "" if end < 0 else rest[end + 1:]
	}
	status, delay, length, chunked := parts[0], parts[1], parts[2], parts[3] != 0
	if !loopback.pause(conn, time.Duration(delay) * time.Millisecond) {
		return
	}
	body := strings.repeat("x", length, context.temp_allocator)
	if chunked {
		loopback.send(
			conn,
			fmt.tprintf(
				"HTTP/1.1 %d M\r\nTransfer-Encoding: chunked\r\n\r\n%x\r\n%s\r\n0\r\n\r\n",
				status,
				length,
				body,
			),
		)
	} else {
		loopback.send(
			conn,
			fmt.tprintf("HTTP/1.1 %d M\r\nContent-Length: %d\r\n\r\n%s", status, length, body),
		)
	}
	free_all(context.temp_allocator)
}

// Watch is a client over a tracking allocator, so a case can show that the
// client gave back everything it took.
Watch :: struct {
	track:  mem.Tracking_Allocator,
	client: ^http.Client,
}

watch_start :: proc(w: ^Watch) -> bool {
	mem.tracking_allocator_init(&w.track, runtime.heap_allocator(), runtime.heap_allocator())
	err: http.Error
	w.client, err = http.start(mem.tracking_allocator(&w.track))
	if err != .None {
		mem.tracking_allocator_destroy(&w.track)
	}
	return err == .None
}

// watch_stop shuts the client down and reports what it leaked, or "".
watch_stop :: proc(w: ^Watch) -> string {
	http.shutdown(w.client)
	defer mem.tracking_allocator_destroy(&w.track)
	if n := len(w.track.allocation_map); n > 0 {
		for _, leak in w.track.allocation_map {
			return fmt.tprintf(
				"%d allocations leaked, one of %d bytes from %v",
				n,
				leak.size,
				leak.location,
			)
		}
	}
	if n := len(w.track.bad_free_array); n > 0 {
		return fmt.tprintf("%d bad frees, first at %v", n, w.track.bad_free_array[0].location)
	}
	return ""
}
