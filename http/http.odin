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

// Sink is what curl's write callback hands bytes to: a writer, or nothing.
Sink :: struct {
	ctx:    runtime.Context,
	w:      io.Writer,
	failed: bool,
}

global_once: sync.Once

// perform is the one transfer routine. Its own temporaries (C strings for
// curl) live on the temp allocator and are released before it returns.
perform :: proc(method, url: string, opts: Opts, body: io.Writer, headers_w: io.Writer) -> (res: Response, err: Error) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	sync.once_do(&global_once, proc() {
		curl.global_init(curl.GLOBAL_DEFAULT)
	})
	h := curl.easy_init()
	if h == nil {
		return {}, .Init_Failed
	}
	defer curl.easy_cleanup(h)

	body_sink := Sink{ctx = context, w = body}
	header_sink := Sink{ctx = context, w = headers_w}

	curl.easy_setopt(h, .URL, cstr(url))
	curl.easy_setopt(h, .NOSIGNAL, c.long(1))
	curl.easy_setopt(h, .WRITEFUNCTION, curl.write_callback(write_cb))
	curl.easy_setopt(h, .WRITEDATA, &body_sink)
	curl.easy_setopt(h, .HEADERFUNCTION, curl.write_callback(write_cb))
	curl.easy_setopt(h, .HEADERDATA, &header_sink)
	curl.easy_setopt(h, .USERAGENT, cstr(opts.user_agent if opts.user_agent != "" else DEFAULT_USER_AGENT))
	if !opts.no_follow {
		curl.easy_setopt(h, .FOLLOWLOCATION, c.long(1))
	}
	if opts.timeout > 0 {
		curl.easy_setopt(h, .TIMEOUT_MS, c.long(opts.timeout / time.Millisecond))
	}
	if opts.insecure {
		curl.easy_setopt(h, .SSL_VERIFYPEER, c.long(0))
		curl.easy_setopt(h, .SSL_VERIFYHOST, c.long(0))
	}
	switch method {
	case "GET":
	case "POST":
		curl.easy_setopt(h, .POST, c.long(1))
	case "HEAD":
		curl.easy_setopt(h, .NOBODY, c.long(1))
	case:
		curl.easy_setopt(h, .CUSTOMREQUEST, cstr(method))
	}
	if opts.body != "" || method == "POST" {
		curl.easy_setopt(h, .POSTFIELDS, raw_data(opts.body))
		curl.easy_setopt(h, .POSTFIELDSIZE_LARGE, curl.off_t(len(opts.body)))
	}

	headers: ^curl.slist
	defer if headers != nil {
		curl.slist_free_all(headers)
	}
	for hdr in opts.headers {
		headers = curl.slist_append(headers, cstr(hdr))
	}
	if headers != nil {
		curl.easy_setopt(h, .HTTPHEADER, headers)
	}

	code := curl.easy_perform(h)
	if code != .E_OK {
		if opts.on_error != nil {
			opts.on_error(string(curl.easy_strerror(code)))
		}
		return {}, .Transfer_Failed
	}
	if body_sink.failed || header_sink.failed {
		return {}, .Write_Failed
	}

	status: c.long
	curl.easy_getinfo(h, .RESPONSE_CODE, &status)
	res.status = int(status)
	res.ok = status >= 200 && status < 300
	return res, .None
}

write_cb :: proc "c" (buffer: [^]byte, size, nitems: c.size_t, userdata: rawptr) -> c.size_t {
	sink := (^Sink)(userdata)
	context = sink.ctx
	n := int(size * nitems)
	if sink.w.procedure == nil {
		return c.size_t(n)
	}
	if _, err := io.write_full(sink.w, buffer[:n]); err != nil {
		sink.failed = true
		return curl.WRITEFUNC_ERROR
	}
	return c.size_t(n)
}

cstr :: proc(s: string) -> cstring {
	return strings.clone_to_cstring(s, context.temp_allocator)
}

with_header :: proc(headers: []string, name, value: string) -> []string {
	out := make([]string, len(headers) + 1, context.temp_allocator)
	copy(out, headers)
	out[len(headers)] = strings.concatenate({name, ": ", value}, context.temp_allocator)
	return out
}
