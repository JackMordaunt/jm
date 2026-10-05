package files_protection

import "core:testing"

@(test)
reason_guards_roots_home_and_places :: proc(t: ^testing.T) {
	home := "/Users/me"
	places := []string{"/Users/me/Documents", "/Users/me/Desktop"}
	cases := []struct {
		path: string,
		want: Reason,
	} {
		{"/", .Root},
		{`C:\`, .Root},
		{"D:", .Root},
		{"/Users/me", .Home},
		{"/Users/me/Documents", .Place},
		{"/Users/me/Documents/report.pdf", .None},
		{"/Users/me/Projects", .None},
		{"/Users", .None},
	}
	for c in cases {
		got := reason(c.path, home, places)
		testing.expectf(t, got == c.want, "%q: %v, want %v", c.path, got, c.want)
	}
}
