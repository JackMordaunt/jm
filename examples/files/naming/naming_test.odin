package files_naming

import "core:strings"
import "core:testing"

import "../files"

@(test)
validity_follows_each_platforms_rules :: proc(t: ^testing.T) {
	long := strings.repeat("x", files.MAX_NAME + 1)
	defer delete(long)
	limit := long[:files.MAX_NAME]
	cases := []struct {
		name:  string,
		on:    Platform,
		want:  Validity,
	} {
		{"notes.txt", .Linux, .Valid},
		{"", .Darwin, .Empty},
		{".", .Linux, .Dots},
		{"..", .Windows, .Dots},
		{"a/b", .Darwin, .Separator},
		{`a\b`, .Linux, .Valid},
		{`a\b`, .Windows, .Separator},
		{"a:b", .Darwin, .Valid},
		{"a:b", .Windows, .Bad_Character},
		{"what?", .Windows, .Bad_Character},
		{"tab\there", .Windows, .Bad_Character},
		{"tab\there", .Linux, .Valid},
		{"nul\x00here", .Linux, .Bad_Character},
		{"CON", .Windows, .Reserved},
		{"aux.txt", .Windows, .Reserved},
		{"Com3.log", .Windows, .Reserved},
		{"lpt0", .Windows, .Valid}, // only 1 to 9 are devices
		{"CON", .Linux, .Valid},
		{"console", .Windows, .Valid},
		{"name.", .Windows, .Trailing_Dot_Or_Space},
		{"name ", .Windows, .Trailing_Dot_Or_Space},
		{"name.", .Darwin, .Valid},
		{limit, .Linux, .Valid},
		{long, .Linux, .Too_Long},
	}
	for c in cases {
		got := validity(c.name, c.on)
		testing.expectf(t, got == c.want, "%q on %v: %v, want %v", c.name, c.on, got, c.want)
	}
}

@(test)
taken_folds_case_where_the_filesystem_does :: proc(t: ^testing.T) {
	siblings := []string{"Photo.JPG", "notes"}
	testing.expect(t, taken("photo.jpg", siblings, .Darwin))
	testing.expect(t, taken("photo.jpg", siblings, .Windows))
	testing.expect(t, !taken("photo.jpg", siblings, .Linux))
	testing.expect(t, taken("Photo.JPG", siblings, .Linux))
	testing.expect(t, !taken("other", siblings, .Darwin))
}

@(test)
free_name_numbers_past_the_names_taken :: proc(t: ^testing.T) {
	buf: [files.MAX_NAME]u8
	siblings := []string{"photo.jpg", "photo 2.jpg", "New folder", "archive.tar.gz", ".profile"}
	cases := []struct {
		wanted: string,
		dir:    bool,
		on:     Platform,
		want:   string,
	} {
		{"report.pdf", false, .Linux, "report.pdf"},
		{"photo.jpg", false, .Linux, "photo 3.jpg"},
		{"PHOTO.jpg", false, .Darwin, "PHOTO 3.jpg"},
		{"PHOTO.jpg", false, .Linux, "PHOTO.jpg"},
		{"New folder", true, .Linux, "New folder 2"},
		{"archive.tar.gz", false, .Linux, "archive.tar 2.gz"},
		{".profile", false, .Linux, ".profile 2"}, // a leading dot is no extension
	}
	for c in cases {
		got := free_name(c.wanted, siblings, c.on, c.dir, buf[:])
		testing.expectf(t, got == c.want, "%q: %q, want %q", c.wanted, got, c.want)
	}
}
