/*
Package http is a small client over vendor:curl. The foreign import block in
vendor/curl/curl.odin links system libcurl on Linux and macOS and the bundled
lib/libcurl.lib on Windows, so TLS, proxies and redirects come from whatever
curl build is linked rather than from here.

	res := must(http.get("https://api.example.com/items"))
	if !res.ok { die("HTTP %d: %s", res.status, res.body) }

	items: []Item
	must(http.get_json("https://api.example.com/items", &items))

	res  = must(http.post_json(url, Payload{name = "x"}))
	must(http.download("https://example.com/big.tar.gz", "build/big.tar.gz"))
	_, err := http.stream("GET", url, os.to_writer(f))   // any io.Writer, nothing allocated

Every call returns (Response, Error). Error is set only when the transfer
could not complete; an HTTP 4xx or 5xx is a Response with ok == false, so
the caller decides whether a status is fatal.

The calls above block. A program that must not wait, such as one with a frame
to draw, starts a Client instead: submit returns a Handle at once, cancel
stops a request from any thread, and an on_done callback reports each one
exactly once. client.odin describes it. Both share one transfer setup, so a
request behaves the same whichever way it is made.
*/
package http

import "base:runtime"
import "core:c"
import "core:encoding/json"
import "core:io"
import "core:os"
import "core:strings"
import "core:sync"
import "core:time"

import curl "vendor:curl"

Response :: struct {
	status:  int,
	// 2xx.
	ok:      bool,
	body:    string,
	// Raw response headers, one per line, as the server sent them.
	headers: string,
}

Error :: enum {
	None,
	Init_Failed,
	Transfer_Failed,
	Write_Failed,
	Encode_Failed,
	Decode_Failed,
	// The body or the headers outgrew their limit.
	Too_Large,
	// A timeout or deadline passed before the response was complete.
	Timed_Out,
	// cancel or shutdown ended the request first.
	Cancelled,
	// submit was refused because the client is shutting down.
	Closed,
}

Opts :: struct {
	// Extra request headers as "Name: value".
	headers:    []string,
	// Whole-request timeout. 0 leaves CURLOPT_TIMEOUT_MS unset, whose libcurl
	// default is 0, no limit.
	timeout:    time.Duration,
	// Do not follow redirects. They are followed by default.
	no_follow:  bool,
	// Skip TLS certificate verification. For local development only.
	insecure:   bool,
	user_agent: string,
	// Request body; content_type names it. Used by request.
	body:       string,
	// Called with libcurl's error text when the transfer fails.
	on_error:   proc(msg: string),
}

DEFAULT_USER_AGENT :: "jm-odin-http/1"

// get performs a GET.
get :: proc(url: string, opts := Opts{}, allocator := context.allocator) -> (Response, Error) {
	return request("GET", url, opts, allocator)
}

// post sends body with the given content type.
post :: proc(url, body: string, content_type := "application/octet-stream", opts := Opts{}, allocator := context.allocator) -> (Response, Error) {
	o := opts
	o.body = body
	o.headers = with_header(opts.headers, "Content-Type", content_type)
	return request("POST", url, o, allocator)
}

// post_json marshals v and posts it as application/json.
post_json :: proc(url: string, v: any, opts := Opts{}, allocator := context.allocator) -> (Response, Error) {
	data, err := json.marshal(v, {}, context.temp_allocator)
	if err != nil {
		return {}, .Encode_Failed
	}
	return post(url, string(data), "application/json", opts, allocator)
}

// get_json fetches url and unmarshals the body into out. A non-2xx status is
// returned as the Response with Error.None, and out is left untouched.
get_json :: proc(url: string, out: ^$T, opts := Opts{}, allocator := context.allocator) -> (Response, Error) {
	o := opts
	o.headers = with_header(opts.headers, "Accept", "application/json")
	res, err := request("GET", url, o, allocator)
	if err != .None || !res.ok {
		return res, err
	}
	if jerr := json.unmarshal_string(res.body, out, json.DEFAULT_SPECIFICATION, allocator); jerr != nil {
		return res, .Decode_Failed
	}
	return res, .None
}

// download streams url into the file at dest, replacing it. A non-2xx
// status still writes whatever the server sent, so check res.ok.
download :: proc(url, dest: string, opts := Opts{}, allocator := context.allocator) -> (Response, Error) {
	f, ferr := os.create(dest)
	if ferr != nil {
		return {}, .Write_Failed
	}
	defer os.close(f)
	hb := strings.builder_make(allocator)
	res, err := stream("GET", url, os.to_writer(f), opts, strings.to_writer(&hb))
	res.headers = strings.to_string(hb)
	return res, err
}

// request performs an arbitrary method with the body from opts.
request :: proc(method, url: string, opts := Opts{}, allocator := context.allocator) -> (Response, Error) {
	bb := strings.builder_make(allocator)
	hb := strings.builder_make(allocator)
	res, err := stream(method, url, strings.to_writer(&bb), opts, strings.to_writer(&hb))
	res.body = strings.to_string(bb)
	res.headers = strings.to_string(hb)
	return res, err
}

// stream performs a request and writes the body to dst as it arrives, and
// the raw headers to headers when one is given. It allocates nothing of
// its own: the writers decide where bytes go, so a caller can stream into
// a file, a builder, or a fixed buffer. The returned Response carries the
// status only; body and headers are empty.
stream :: proc(method, url: string, dst: io.Writer, opts := Opts{}, headers: io.Writer = {}) -> (Response, Error) {
	return perform(method, url, opts, dst, headers)
}

// ---- internals ----------------------------------------------------------

// Spec is one transfer as both APIs describe it to curl, so a blocking call
// and a submitted request are configured by the same code.
@(private)
Spec :: struct {
	method:     string,
	url:        string,
	headers:    []string,
	body:       string,
	user_agent: string,
	// curl's own whole-transfer limit; 0 is none.
	timeout:    time.Duration,
	no_follow:  bool,
	insecure:   bool,
	// Bytes the body and the headers may reach; 0 is no limit.
	max_body:   int,
	max_head:   int,
}

// Sink is what curl's write callback hands bytes to: a writer, or nothing,
// with a limit on how many it will take.
@(private)
Sink :: struct {
	ctx:       runtime.Context,
	w:         io.Writer,
	limit:     int,
	written:   int,
	failed:    bool,
	too_large: bool,
}

// Wire is a transfer's state that curl holds pointers into, so it must not
// move while the transfer runs.
@(private)
Wire :: struct {
	body:   Sink,
	head:   Sink,
	list:   ^curl.slist,
	errbuf: [curl.ERROR_SIZE]byte,
}

@(private)
global_once: sync.Once

// global_init runs curl_global_init once per process, before the first
// handle is made; sync.Once makes the first caller pay for it while the rest
// wait.
@(private)
global_init :: proc() {
	sync.once_do(&global_once, proc() {
		curl.global_init(curl.GLOBAL_DEFAULT)
	})
}

// prepare makes an easy handle configured for spec, its bytes going to the
// sinks in wire. The caller frees the handle and then wire.list.
@(private)
prepare :: proc(spec: Spec, wire: ^Wire) -> ^curl.CURL {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	global_init()
	h := curl.easy_init()
	if h == nil {
		return nil
	}
	wire.body.limit = spec.max_body
	wire.head.limit = spec.max_head
	curl.easy_setopt(h, .URL, cstr(spec.url))
	curl.easy_setopt(h, .NOSIGNAL, c.long(1))
	curl.easy_setopt(h, .ERRORBUFFER, &wire.errbuf[0])
	curl.easy_setopt(h, .WRITEFUNCTION, curl.write_callback(write_cb))
	curl.easy_setopt(h, .WRITEDATA, &wire.body)
	curl.easy_setopt(h, .HEADERFUNCTION, curl.write_callback(write_cb))
	curl.easy_setopt(h, .HEADERDATA, &wire.head)
	ua := spec.user_agent if spec.user_agent != "" else DEFAULT_USER_AGENT
	curl.easy_setopt(h, .USERAGENT, cstr(ua))
	if !spec.no_follow {
		curl.easy_setopt(h, .FOLLOWLOCATION, c.long(1))
	}
	if spec.timeout > 0 {
		curl.easy_setopt(h, .TIMEOUT_MS, c.long(max(spec.timeout / time.Millisecond, 1)))
	}
	if spec.max_body > 0 {
		// CURLOPT_MAXFILESIZE_LARGE refuses a response whose Content-Length
		// is over the limit; a body with no length is held to it by the sink.
		curl.easy_setopt(h, .MAXFILESIZE_LARGE, curl.off_t(spec.max_body))
	}
	if spec.insecure {
		curl.easy_setopt(h, .SSL_VERIFYPEER, c.long(0))
		curl.easy_setopt(h, .SSL_VERIFYHOST, c.long(0))
	}
	set_request(h, spec)
	for hdr in spec.headers {
		wire.list = curl.slist_append(wire.list, cstr(hdr))
	}
	if wire.list != nil {
		curl.easy_setopt(h, .HTTPHEADER, wire.list)
	}
	return h
}

// set_request sets the verb and the body. CURLOPT_POSTFIELDS is not copied
// (COPYPOSTFIELDS is the option that copies), so spec.body must outlive the
// transfer.
@(private)
set_request :: proc(h: ^curl.CURL, spec: Spec) {
	switch spec.method {
	case "", "GET":
	case "POST":
		curl.easy_setopt(h, .POST, c.long(1))
	case "HEAD":
		curl.easy_setopt(h, .NOBODY, c.long(1))
	case:
		curl.easy_setopt(h, .CUSTOMREQUEST, cstr(spec.method))
	}
	if spec.body != "" || spec.method == "POST" {
		curl.easy_setopt(h, .POSTFIELDSIZE_LARGE, curl.off_t(len(spec.body)))
		curl.easy_setopt(h, .POSTFIELDS, raw_data(spec.body))
	}
}

// classify turns how a transfer ended into an Error. A sink that refused
// bytes made curl stop with CURLE_WRITE_ERROR, which says only that a write
// callback failed, so the sink's own reason outranks curl's code.
@(private)
classify :: proc(code: curl.code, wire: ^Wire) -> Error {
	switch {
	case wire.body.too_large || wire.head.too_large || code == .E_FILESIZE_EXCEEDED:
		return .Too_Large
	case wire.body.failed || wire.head.failed:
		return .Write_Failed
	case code == .E_OPERATION_TIMEDOUT:
		return .Timed_Out
	case code == .E_OK:
		return .None
	}
	return .Transfer_Failed
}

// failure is curl's account of why a transfer failed: the detail it wrote
// to the error buffer, or the generic text for its code.
@(private)
failure :: proc(code: curl.code, wire: ^Wire) -> string {
	if wire.errbuf[0] != 0 {
		return string(cstring(&wire.errbuf[0]))
	}
	return string(curl.easy_strerror(code))
}

// status reads the final response's status code.
@(private)
status_of :: proc(h: ^curl.CURL) -> int {
	status: c.long
	curl.easy_getinfo(h, .RESPONSE_CODE, &status)
	return int(status)
}

// perform is the blocking transfer. Its own temporaries live on the temp
// allocator and are released before it returns.
@(private)
perform :: proc(
	method, url: string,
	opts: Opts,
	body: io.Writer,
	headers_w: io.Writer,
) -> (
	res: Response,
	err: Error,
) {
	spec := Spec {
		method     = method,
		url        = url,
		headers    = opts.headers,
		body       = opts.body,
		user_agent = opts.user_agent,
		timeout    = opts.timeout,
		no_follow  = opts.no_follow,
		insecure   = opts.insecure,
	}
	wire := Wire {
		body = {ctx = context, w = body},
		head = {ctx = context, w = headers_w},
	}
	h := prepare(spec, &wire)
	if h == nil {
		return {}, .Init_Failed
	}
	defer curl.slist_free_all(wire.list)
	defer curl.easy_cleanup(h)

	code := curl.easy_perform(h)
	if err = classify(code, &wire); err != .None {
		if opts.on_error != nil {
			opts.on_error(failure(code, &wire))
		}
		return {}, err
	}
	res.status = status_of(h)
	res.ok = res.status >= 200 && res.status < 300
	return res, .None
}

@(private)
write_cb :: proc "c" (buffer: [^]byte, size, nitems: c.size_t, userdata: rawptr) -> c.size_t {
	sink := (^Sink)(userdata)
	context = sink.ctx
	n := int(size * nitems)
	if sink.limit > 0 && n > sink.limit - sink.written {
		sink.too_large = true
		return curl.WRITEFUNC_ERROR
	}
	sink.written += n
	if sink.w.procedure == nil {
		return c.size_t(n)
	}
	if _, err := io.write_full(sink.w, buffer[:n]); err != nil {
		sink.failed = true
		return curl.WRITEFUNC_ERROR
	}
	return c.size_t(n)
}

@(private)
cstr :: proc(s: string) -> cstring {
	return strings.clone_to_cstring(s, context.temp_allocator)
}

@(private)
with_header :: proc(headers: []string, name, value: string) -> []string {
	out := make([]string, len(headers) + 1, context.temp_allocator)
	copy(out, headers)
	out[len(headers)] = strings.concatenate({name, ": ", value}, context.temp_allocator)
	return out
}
