package http

import "base:runtime"
import "core:fmt"
import "core:io"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:testing"
import "core:time"

import "jm:http/loopback"

// ---- fixtures -------------------------------------------------------------

// Gates lets a test see a request reach the server.
Gates :: struct {
	arrived: sync.Sema,
}

// routes answers by path, so one server serves every scenario.
routes :: proc(conn: ^loopback.Conn, req: loopback.Request) {
	gates := (^Gates)(conn.server.user)
	switch {
	case req.path == "/ok":
		loopback.send(conn, "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhello")
	case req.path == "/404":
		loopback.send(conn, "HTTP/1.1 404 Not Found\r\nContent-Length: 4\r\n\r\nnope")
	case req.path == "/500":
		loopback.send(conn, "HTTP/1.1 500 Oops\r\nContent-Length: 4\r\n\r\nboom")
	case req.path == "/echo":
		loopback.send(
			conn,
			fmt.tprintf(
				"HTTP/1.1 200 OK\r\nContent-Length: %d\r\n\r\n%s",
				len(req.body),
				req.body,
			),
		)
	case req.path == "/silent":
		sync.sema_post(&gates.arrived)
		loopback.hold(conn)
	case req.path == "/half":
		loopback.send(conn, "HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\n0123456789")
		sync.sema_post(&gates.arrived)
		loopback.hold(conn)
	case req.path == "/big":
		loopback.send(conn, "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n")
		for _ in 0 ..< 4 {
			loopback.send(
				conn,
				fmt.tprintf("400\r\n%s\r\n", strings.repeat("x", 1024, context.temp_allocator)),
			)
		}
		loopback.send(conn, "0\r\n\r\n")
	case req.path == "/declared":
		// Declares more than it sends, so only the declaration can refuse it.
		loopback.send(conn, "HTTP/1.1 200 OK\r\nContent-Length: 5000\r\n\r\n")
		loopback.hold(conn)
	case strings.has_prefix(req.path, "/delay/"):
		ms, _ := strconv.parse_int(req.path[len("/delay/"):])
		if loopback.pause(conn, time.Duration(ms) * time.Millisecond) {
			loopback.send(conn, "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok")
		}
	case:
		loopback.send(conn, "HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\n\r\n")
	}
}

// ---- the blocking API --------------------------------------------------------

@(test)
blocking_calls_still_work :: proc(t: ^testing.T) {
	gates: Gates
	srv, ok := loopback.start(routes, &gates, runtime.heap_allocator())
	testing.expect(t, ok)
	defer loopback.stop(srv)
	context.allocator = context.temp_allocator

	res, err := get(loopback.url(srv, "/ok"))
	testing.expect_value(t, err, Error.None)
	testing.expect_value(t, res.body, "hello")
	testing.expect(t, strings.contains(res.headers, "Content-Length: 5"))

	res, err = get(loopback.url(srv, "/404"))
	testing.expect_value(t, err, Error.None)
	testing.expect(t, !res.ok && res.status == 404)

	res, err = post_json(loopback.url(srv, "/echo"), struct {
		n: int,
	}{7})
	testing.expect_value(t, err, Error.None)
	testing.expect_value(t, res.body, `{"n":7}`)

	// An empty POST sends no body rather than waiting for one.
	res, err = post(loopback.url(srv, "/echo"), "")
	testing.expect_value(t, err, Error.None)
	testing.expect_value(t, res.body, "")

	_, err = get(loopback.url(srv, "/delay/5000"), {timeout = 100 * time.Millisecond})
	testing.expect_value(t, err, Error.Timed_Out)

	_, err = get("http://127.0.0.1:1/")
	testing.expect_value(t, err, Error.Transfer_Failed)
}

// A writer that refuses bytes ends the transfer as Write_Failed, not as the
// generic write error curl reports for it.
@(test)
refusing_writer_is_write_failed :: proc(t: ^testing.T) {
	gates: Gates
	srv, ok := loopback.start(routes, &gates, runtime.heap_allocator())
	testing.expect(t, ok)
	defer loopback.stop(srv)
	refuse := io.Writer {
		procedure = proc(
			_: rawptr,
			_: io.Stream_Mode,
			_: []byte,
			_: i64,
			_: io.Seek_From,
		) -> (
			i64,
			io.Error,
		) {
			return 0, .Unknown
		},
	}
	_, err := stream("GET", loopback.url(srv, "/ok"), refuse)
	testing.expect_value(t, err, Error.Write_Failed)
}
