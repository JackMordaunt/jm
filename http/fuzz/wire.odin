package http_fuzz

import "core:fmt"
import "core:strings"
import "core:sync"
import "core:time"

import harness "jm:fuzz"
import "jm:http"
import "jm:http/loopback"

// The slack in every timing rule, here and in the model: how late past its
// deadline a completion may arrive, and how long before a timeout an answer
// must come to make timing out a fault. It catches a deadline that never
// fires, not one that fires late: a loaded machine can hold a thread off the
// CPU for seconds.
SLACK :: 5 * time.Second

// Wire_Request is one request of a wire case and what on_done said about it.
Wire_Request :: struct {
	completions: ^Completions,
	max_body:    int,
	timeout:     time.Duration,
	submitted:   time.Time,
	handle:      http.Handle,
	cancelled:   bool,
	// Written by on_done, under completions.mutex.
	calls:       int,
	result:      http.Result,
	body_len:    int,
	took:        time.Duration,
}

// Completions is where a wire case's on_done calls report to it.
Completions :: struct {
	mutex: sync.Mutex,
	done:  sync.Sema,
}

STATUS_LINES := []string {
	"HTTP/1.1 200 OK",
	"HTTP/1.1 204 No Content",
	"HTTP/1.1 304 Not Modified",
	"HTTP/1.1 404 Not Found",
	"HTTP/1.1 500 Internal Server Error",
	"HTTP/1.0 200 OK",
	"HTTP/1.1 100 Continue",
	"HTTP/1.1 101 Switching Protocols",
	"HTTP/1.1 302 Found",
	"HTTP/1.1 200",
	"HTTP/1.1 99 Low",
	"HTTP/1.1 1000 High",
	"HTTP/1.1 -200 Negative",
	"HTTP/1.1 99999999999999999999 Huge",
	"HTTP/1.1 2OO OK",
	"HTTP/2 200",
	"HTTP/0.9 200 OK",
	"HTTP/1.1  200  OK",
	"http/1.1 200 ok",
	"ICY 200 OK",
	"HTTP/1.1",
	"",
	"\x00\xff\xfe",
}

EOLS := []string{"\r\n", "\n", "\r", "", "\r\r\n"}

// wire answers each request with drawn bytes and checks the client's one
// promise about any answer at all: a single on_done, in time, sane, and
// nothing left allocated.
wire :: proc(s: Subject, src: ^harness.Source) -> (detail: string, ok: bool) {
	w: Watch
	if !watch_start(&w) {
		return "http.start failed", false
	}
	completions := new(Completions)
	reqs := make([]Wire_Request, harness.integer_in(src, 1, 4))
	longest: time.Duration
	for &p, i in reqs {
		path := fmt.tprintf("/s/%d", i)
		register(s, i, draw_script(src, path))
		p.completions = completions
		p.max_body = harness.choice(src, []int{0, 16, 1024})
		p.timeout = time.Duration(harness.integer_in(src, 20, 300)) * time.Millisecond
		longest = max(longest, p.timeout)
		req := http.Request {
			method   = harness.choice(src, []string{"GET", "POST", "HEAD", "DELETE"}),
			url      = loopback.url(s.srv, path),
			body     = harness.boolean(src) ? "{}" : "",
			timeout  = p.timeout,
			max_body = p.max_body,
		}
		p.submitted = time.now()
		h, err := http.submit(w.client, req, on_wire_done, &p)
		if err != .None {
			watch_stop(&w)
			return fmt.tprintf("submit refused: %v", err), false
		}
		sync.guard(&completions.mutex)
		p.handle = h
	}
	if harness.boolean(src) {
		time.sleep(time.Duration(harness.integer_in(src, 0, 40)) * time.Millisecond)
		p := &reqs[harness.integer_in(src, 0, len(reqs))]
		p.cancelled = http.cancel(w.client, p.handle)
	}
	for _ in reqs {
		if !sync.sema_wait_with_timeout(&completions.done, longest + 2 * SLACK) {
			break
		}
	}
	leaked := watch_stop(&w)
	if bad := judge(reqs); bad != "" {
		return bad, false
	}
	return leaked, leaked == ""
}

on_wire_done :: proc(r: http.Result, user: rawptr) {
	p := (^Wire_Request)(user)
	sync.guard(&p.completions.mutex)
	p.calls += 1
	p.result = r
	p.body_len = len(r.response.body)
	// The strings die when on_done returns.
	p.result.response.body = ""
	p.result.response.headers = ""
	p.result.message = ""
	p.took = time.since(p.submitted)
	sync.sema_post(&p.completions.done)
}

// judge holds each request to the promise, after shutdown has returned.
judge :: proc(reqs: []Wire_Request) -> string {
	for p, i in reqs {
		err := p.result.err
		switch {
		case p.calls != 1:
			return fmt.tprintf("request %d: on_done fired %d times", i, p.calls)
		case p.took > p.timeout + SLACK:
			return fmt.tprintf(
				"request %d: %v ended after %v, deadline %v",
				i,
				err,
				p.took,
				p.timeout,
			)
		case p.cancelled && err != .Cancelled:
			return fmt.tprintf("request %d: cancel said yes, on_done said %v", i, err)
		case !p.cancelled && err == .Cancelled:
			return fmt.tprintf("request %d: Cancelled, but nothing cancelled it", i)
		case err != .None &&
		     err != .Transfer_Failed &&
		     err != .Too_Large &&
		     err != .Timed_Out &&
		     err != .Cancelled:
			return fmt.tprintf("request %d: %v is not an outcome of a transfer", i, err)
		case err == .None && (p.result.response.status < 100 || p.result.response.status > 999):
			return fmt.tprintf("request %d: status %d", i, p.result.response.status)
		case err == .None &&
		     p.body_len > (p.max_body if p.max_body > 0 else http.DEFAULT_MAX_BODY):
			return fmt.tprintf(
				"request %d: %d body bytes past a limit of %d",
				i,
				p.body_len,
				p.max_body,
			)
		}
	}
	return ""
}

// draw_script draws a response, and how it is delivered.
draw_script :: proc(src: ^harness.Source, self: string) -> Script {
	whole := draw_response(src, self)
	steps := make([dynamic]Step)
	at := 0
	for at < len(whole) {
		n := len(whole) - at
		if harness.boolean(src) {
			n = harness.integer_in(src, 1, n + 1)
		}
		pause := time.Duration(harness.integer_in(src, 0, 4) * harness.integer_in(src, 0, 15))
		append(&steps, Step{pause * time.Millisecond, whole[at:at + n]})
		at += n
	}
	return Script{steps[:], harness.integer_in(src, 0, 4) == 0}
}

draw_response :: proc(src: ^harness.Source, self: string) -> string {
	if harness.integer_in(src, 0, 16) == 0 {
		return string(harness.bytes(src, 512))
	}
	b := strings.builder_make()
	eol := harness.integer_in(src, 0, 4) == 0 ? harness.choice(src, EOLS) : "\r\n"
	body := draw_body(src)
	strings.write_string(&b, harness.choice(src, STATUS_LINES))
	strings.write_string(&b, eol)
	chunked := false
	for _ in 0 ..< harness.integer_in(src, 0, 5) {
		chunked |= draw_header(src, &b, len(body), self)
		strings.write_string(&b, eol)
	}
	strings.write_string(&b, eol)
	if chunked && harness.integer_in(src, 0, 4) != 0 {
		draw_chunks(src, &b, body)
	} else {
		strings.write_string(&b, body)
	}
	return strings.to_string(b)
}

draw_body :: proc(src: ^harness.Source) -> string {
	switch harness.integer_in(src, 0, 6) {
	case 0:
		return ""
	case 1:
		// From 1 to 300 KiB: past every small max_body, and too long to
		// arrive in one read.
		return strings.repeat("b", harness.integer_in(src, 1, 300) * 1024)
	case:
		return string(harness.bytes(src, 64))
	}
}

// draw_header writes one header and says whether it asked for chunking.
draw_header :: proc(
	src: ^harness.Source,
	b: ^strings.Builder,
	body_len: int,
	self: string,
) -> bool {
	switch harness.integer_in(src, 0, 16) {
	case 0:
		fmt.sbprintf(b, "Content-Length: %d", body_len)
	case 1:
		fmt.sbprintf(b, "Content-Length: %d", body_len + harness.integer_in(src, -8, 9))
	case 2:
		fmt.sbprintf(b, "Content-Length: %d", harness.integer(src))
	case 3:
		strings.write_string(
			b,
			harness.choice(
				src,
				[]string {
					"Content-Length: abc",
					"Content-Length:",
					"Content-Length: 99999999999999999999999",
				},
			),
		)
	case 4:
		fmt.sbprintf(b, "Content-Length: %d, %d", body_len, body_len + 1)
	case 5:
		strings.write_string(b, "Transfer-Encoding: chunked")
		return true
	case 6:
		strings.write_string(
			b,
			harness.choice(
				src,
				[]string {
					"Transfer-Encoding: gzip, chunked",
					"Transfer-Encoding: identity",
					"Transfer-Encoding: chunked, chunked",
				},
			),
		)
	case 7:
		strings.write_string(
			b,
			harness.choice(
				src,
				[]string{"Connection: close", "Connection: keep-alive", "Connection: upgrade"},
			),
		)
	case 8:
		// Past MAX_HEAD at the top of the range.
		strings.write_string(b, "X-Long: ")
		strings.write_string(b, strings.repeat("h", harness.integer_in(src, 0, 400) * 1024))
	case 9:
		strings.write_string(b, "No-Colon-Here")
	case 10:
		strings.write_string(b, " folded: continuation")
	case 11:
		fmt.sbprintf(b, "Location: %s", self)
	case 12:
		strings.write_string(
			b,
			harness.choice(
				src,
				[]string {
					"Content-Encoding: gzip",
					"Content-Encoding: br",
					"Content-Type: application/json",
				},
			),
		)
	case 13:
		for _ in 0 ..< harness.integer_in(src, 0, 2000) {
			strings.write_string(b, "X-Many: m\r\n")
		}
		strings.write_string(b, "X-Last: l")
	case:
		strings.write_string(b, string(harness.bytes(src, 64)))
	}
	return false
}

CHUNK_SIZES := []string{"%x", "%X", "%x;ext=1", "zz", "-1", "ffffffffffffffffffff", "", " %x"}

// draw_chunks writes body chunked, with sizes that are sometimes lies.
draw_chunks :: proc(src: ^harness.Source, b: ^strings.Builder, body: string) {
	rest := body
	for len(rest) > 0 {
		n := harness.integer_in(src, 1, len(rest) + 1)
		size := harness.integer_in(src, 0, 4) == 0 ? harness.choice(src, CHUNK_SIZES) : "%x"
		claim := n + (harness.integer_in(src, 0, 4) == 0 ? harness.integer_in(src, -2, 3) : 0)
		if strings.contains(size, "%") {
			fmt.sbprintf(b, size, claim)
		} else {
			strings.write_string(b, size)
		}
		fmt.sbprintf(b, "\r\n%s\r\n", rest[:n])
		rest = rest[n:]
	}
	switch harness.integer_in(src, 0, 4) {
	case 0:
	// No last chunk: the body never ends.
	case 1:
		strings.write_string(b, "0\r\nX-Trailer: t\r\n\r\n")
	case:
		strings.write_string(b, "0\r\n\r\n")
	}
}
