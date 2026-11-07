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
	when ODIN_OS == .Windows {
		for path in ([]string{`\`, `C:\`, "C:/", "D:", `\\server\share`, `\\server\share\`}) {
			testing.expectf(t, reason(path, home, places) == .Root, "%q is protected", path)
		}
	}
}

@(test)
root_does_not_confuse_a_child_with_its_volume :: proc(t: ^testing.T) {
	for path in ([]string{"", ".", "ordinary", "x:dir"}) {
		testing.expect(t, !root(path), path)
	}
	when ODIN_OS == .Windows {
		for path in ([]string{`C:x`, `C:\x`, `\\server\share\x`}) {
			testing.expect(t, !root(path), path)
		}
	} else {
		for path in ([]string{"/child", `C:\`, `\`}) {
			testing.expect(t, !root(path), path)
		}
	}
}
