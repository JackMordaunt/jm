/*
Package loopback is an HTTP/1.1 server on 127.0.0.1 for testing clients. It
parses only as much of a request as a test needs and leaves the response to
a handler, so a test can answer with anything at all: a proper response, a
malformed one, half of one, or nothing.

	srv, _ := loopback.start(proc(conn: ^loopback.Conn, req: loopback.Request) {
		loopback.send(conn, "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nhi")
	})
	defer loopback.stop(srv)
	url := loopback.url(srv, "/items")

Each connection runs its handler on a thread of its own, and the connection
closes when the handler returns. stop unblocks every handler still waiting:
send and pause return false from then on, and hold returns.
*/
package loopback

import "base:runtime"
import "core:fmt"
import "core:net"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"

// Request is what the server read of a request before calling the handler.
// Its strings live until the handler returns.
Request :: struct {
	method: string,
	path:   string,
	// The request line and headers, up to the blank line.
	head:   string,
	body:   string,
}

// Handler answers one connection's request.
Handler :: #type proc(conn: ^Conn, req: Request)

Server :: struct {
	allocator: runtime.Allocator,
	handler:   Handler,
	// The handler's own state; read it with conn.server.user.
	user:      rawptr,
	port:      int,
	listener:  net.TCP_Socket,
	acceptor:  ^thread.Thread,
	// Guards conns and each Conn's closed.
	mutex:     sync.Mutex,
	conns:     [dynamic]^Conn,
	stopping:  bool,
	// How many connections were accepted.
	accepted:  int,
}

Conn :: struct {
	server: ^Server,
	socket: net.TCP_Socket,
	thread: ^thread.Thread,
	closed: bool,
}

// The most request bytes read: a client that sends more is cut off.
MAX_REQUEST :: 1024 * 1024

// start listens on an ephemeral port and serves until stop. allocator must
// be thread-safe: every connection's thread uses it.
start :: proc(
	handler: Handler,
	user: rawptr = nil,
	allocator := context.allocator,
) -> (
	^Server,
	bool,
) {
	listener, err := net.listen_tcp({net.IP4_Loopback, 0})
	if err != nil {
		return nil, false
	}
	bound, berr := net.bound_endpoint(listener)
	if berr != nil {
		net.close(listener)
		return nil, false
	}
	s := new(Server, allocator)
	s.allocator = allocator
	s.handler = handler
	s.user = user
	s.port = bound.port
	s.listener = listener
	s.conns = make([dynamic]^Conn, allocator)
	context.allocator = allocator
	s.acceptor = thread.create_and_start_with_poly_data(s, accept_loop)
	return s, true
}

// url is the address of path on s.
url :: proc(s: ^Server, path: string, allocator := context.temp_allocator) -> string {
	return fmt.aprintf("http://127.0.0.1:%d%s", s.port, path, allocator = allocator)
}

// stop closes every connection, waits for every handler to return, and frees
// the server.
stop :: proc(s: ^Server) {
	sync.lock(&s.mutex)
	s.stopping = true
	for c in s.conns {
		if !c.closed {
			net.shutdown(c.socket, .Both)
		}
	}
	sync.unlock(&s.mutex)
	wake_acceptor(s)
	thread.join(s.acceptor)
	thread.destroy(s.acceptor)
	net.close(s.listener)
	for c in s.conns {
		thread.join(c.thread)
		thread.destroy(c.thread)
		free(c, s.allocator)
	}
	delete(s.conns)
	free(s, s.allocator)
}

// wake_acceptor connects to s until its acceptor, blocked in accept, sees the
// connection and returns. One dial was not enough: with eight copies of
// http/fuzz's tests running at once, stop waited on accept for ever.
@(private)
wake_acceptor :: proc(s: ^Server) {
	for !thread.is_done(s.acceptor) {
		if wake, err := net.dial_tcp(net.Endpoint{net.IP4_Loopback, s.port}); err == nil {
			net.close(wake)
		}
		for i := 0; i < 100 && !thread.is_done(s.acceptor); i += 1 {
			time.sleep(time.Millisecond)
		}
	}
}

// stopping says whether stop has begun.
stopping :: proc(s: ^Server) -> bool {
	return sync.atomic_load(&s.stopping)
}

// accepted is how many connections s has accepted so far.
accepted :: proc(s: ^Server) -> int {
	return sync.atomic_load(&s.accepted)
}

// send writes data whole, and says whether the peer took it.
send :: proc(c: ^Conn, data: string) -> bool {
	if stopping(c.server) {
		return false
	}
	n, err := net.send_tcp(c.socket, transmute([]byte)data)
	return err == nil && n == len(data)
}

// pause waits for d, and says false if stop began meanwhile.
pause :: proc(c: ^Conn, d: time.Duration) -> bool {
	until := time.time_add(time.now(), d)
	for !stopping(c.server) {
		left := time.diff(time.now(), until)
		if left <= 0 {
			return true
		}
		time.sleep(min(left, 5 * time.Millisecond))
	}
	return false
}

// hold keeps the connection open, silent, until stop.
hold :: proc(c: ^Conn) {
	for pause(c, time.Second) {}
}

// ---- internals ----------------------------------------------------------

@(private)
accept_loop :: proc(s: ^Server) {
	context.allocator = s.allocator
	for {
		sock, _, err := net.accept_tcp(s.listener)
		sync.lock(&s.mutex)
		if s.stopping {
			sync.unlock(&s.mutex)
			if err == nil {
				net.close(sock)
			}
			return
		}
		if err != nil {
			sync.unlock(&s.mutex)
			// Out of descriptors, say: let the handlers finish some.
			time.sleep(time.Millisecond)
			continue
		}
		c := new(Conn)
		c.server = s
		c.socket = sock
		append(&s.conns, c)
		sync.atomic_add(&s.accepted, 1)
		c.thread = thread.create_and_start_with_poly_data(c, serve)
		sync.unlock(&s.mutex)
	}
}

@(private)
serve :: proc(c: ^Conn) {
	context.allocator = c.server.allocator
	buf := make([dynamic]byte, 0, 4096)
	defer delete(buf)
	if req, ok := read_request(c, &buf); ok {
		c.server.handler(c, req)
	}
	sync.lock(&c.server.mutex)
	c.closed = true
	net.close(c.socket)
	sync.unlock(&c.server.mutex)
}

// read_request reads the head and as much body as Content-Length declares.
@(private)
read_request :: proc(c: ^Conn, buf: ^[dynamic]byte) -> (req: Request, ok: bool) {
	end := -1
	for end < 0 {
		read_more(c, buf) or_return
		end = strings.index(string(buf[:]), "\r\n\r\n")
	}
	want := end + 4 + content_length(string(buf[:end]))
	for len(buf) < want {
		read_more(c, buf) or_return
	}
	req.head = string(buf[:end])
	req.body = string(buf[end + 4:want])
	line := req.head
	if i := strings.index(line, "\r\n"); i >= 0 {
		line = line[:i]
	}
	if sp := strings.index_byte(line, ' '); sp >= 0 {
		req.method, line = line[:sp], line[sp + 1:]
		sp = strings.index_byte(line, ' ')
		req.path = line[:sp] if sp >= 0 else line
	}
	return req, true
}

@(private)
read_more :: proc(c: ^Conn, buf: ^[dynamic]byte) -> bool {
	chunk: [4096]byte
	if len(buf) >= MAX_REQUEST {
		return false
	}
	n, err := net.recv_tcp(c.socket, chunk[:])
	if err != nil || n == 0 {
		return false
	}
	append(buf, ..chunk[:n])
	return true
}

@(private)
content_length :: proc(head: string) -> int {
	rest := head
	for line in strings.split_lines_iterator(&rest) {
		colon := strings.index_byte(line, ':')
		if colon < 0 || !strings.equal_fold(line[:colon], "content-length") {
			continue
		}
		n, ok := strconv.parse_int(strings.trim_space(line[colon + 1:]))
		if ok && n >= 0 {
			return min(n, MAX_REQUEST)
		}
	}
	return 0
}
