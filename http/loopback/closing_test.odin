package loopback

import "core:testing"

@(test)
closing_keeps_headerless_and_partial_responses :: proc(t: ^testing.T) {
	for c in ([]struct{sent, want: string}{
		{"HTTP/1.1 200 OK\r\n\r\n", "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n"},
		{"HTTP/1.1 204 No Content\r\n\r\n", "HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n"},
		{"HTTP/1.1 200\r\n\r\nbody", "HTTP/1.1 200\r\nConnection: close\r\n\r\nbody"},
		{"HTTP/\r\n\r\n", "HTTP/\r\nConnection: close\r\n\r\n"},
		{"HTTP/1.1 200 OK\r\n", "HTTP/1.1 200 OK\r\nConnection: close\r\n"},
		{"HTTP/1.1 200 OK", "HTTP/1.1 200 OK"},
		{"not an HTTP response\r\n\r\n", "not an HTTP response\r\n\r\n"},
		{
			"HTTP/1.1 200 OK\r\nContent-Length: 1\r\n\r\nx",
			"HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 1\r\n\r\nx",
		},
		{
			"HTTP/1.1 200 OK\r\ncOnNeCtIoN : keep-alive\r\n\r\nbody",
			"HTTP/1.1 200 OK\r\ncOnNeCtIoN : keep-alive\r\n\r\nbody",
		},
	}) {
		testing.expect_value(t, closing(c.sent), c.want)
	}
}
