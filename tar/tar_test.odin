package tar

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "jm:sh"

@(test)
git_archive_extracts_whole :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	temp := os.temp_directory(context.temp_allocator) or_else ""
	root, err := os.make_directory_temp(temp, "jm-tar-*", context.temp_allocator)
	testing.expect(t, err == nil)
	defer os.remove_all(root)
	git := proc(root: string, args: ..string) -> sh.Result {
		argv := make([dynamic]string, context.temp_allocator)
		append(
			&argv,
			"git",
			"-c",
			"user.email=t@t",
			"-c",
			"user.name=t",
			"-c",
			"commit.gpgsign=false",
		)
		append(&argv, ..args)
		return sh.exec(argv[:], {dir = root}, context.temp_allocator)
	}
	long := strings.repeat("deep/", 30)
	testing.expect(t, git(root, "init", "-q").ok)
	testing.expect(
		t,
		os.make_directory_all(filepath.join({root, long}, context.temp_allocator) or_else "") ==
		nil,
	)
	testing.expect(
		t,
		os.write_entire_file(
			filepath.join({root, "a.txt"}, context.temp_allocator) or_else "",
			transmute([]byte)string("alpha\n"),
		) ==
		nil,
	)
	testing.expect(
		t,
		os.make_directory_all(filepath.join({root, "sub"}, context.temp_allocator) or_else "") ==
		nil,
	)
	testing.expect(
		t,
		os.write_entire_file(
			filepath.join({root, "sub", "b.bin"}, context.temp_allocator) or_else "",
			transmute([]byte)string("\x00\x01\x02"),
		) ==
		nil,
	)
	testing.expect(
		t,
		os.write_entire_file(
			filepath.join({root, long, "c.txt"}, context.temp_allocator) or_else "",
			transmute([]byte)strings.repeat("x", 1000),
		) ==
		nil,
	)
	testing.expect(t, git(root, "add", "-A").ok)
	testing.expect(t, git(root, "commit", "-q", "-m", "seed").ok)

	archive := git(root, "archive", "--format=tar", "HEAD")
	testing.expect(t, archive.ok)
	entries, read_err := read(transmute([]byte)archive.stdout)
	testing.expect_value(t, read_err, Error.None)
	names := make([dynamic]string, context.temp_allocator)
	for e in entries {
		if !e.dir {
			append(&names, e.name)
		}
	}
	testing.expect_value(t, len(names), 3)

	dest, derr := os.make_directory_temp(temp, "jm-tar-out-*", context.temp_allocator)
	testing.expect(t, derr == nil)
	defer os.remove_all(dest)
	count, xerr := extract(transmute([]byte)archive.stdout, dest)
	testing.expect_value(t, xerr, Error.None)
	testing.expect_value(t, count, 3)
	a, _ := os.read_entire_file_from_path(
		filepath.join({dest, "a.txt"}, context.temp_allocator) or_else "",
		context.temp_allocator,
	)
	testing.expect_value(t, string(a), "alpha\n")
	b, _ := os.read_entire_file_from_path(
		filepath.join({dest, "sub", "b.bin"}, context.temp_allocator) or_else "",
		context.temp_allocator,
	)
	testing.expect_value(t, string(b), "\x00\x01\x02")
	c, cerr := os.read_entire_file_from_path(
		filepath.join({dest, long, "c.txt"}, context.temp_allocator) or_else "",
		context.temp_allocator,
	)
	testing.expect(t, cerr == nil, "the long path was written")
	testing.expect_value(t, string(c), strings.repeat("x", 1000))
}

@(test)
headers_are_read_and_bad_ones_refused :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	n, ok := octal(transmute([]byte)string("00000000144\x00"))
	testing.expect(t, ok)
	testing.expect_value(t, n, 100)
	n, ok = octal(transmute([]byte)string("            "))
	testing.expect(t, ok)
	testing.expect_value(t, n, 0)
	_, ok = octal(transmute([]byte)string("not octal!!!"))
	testing.expect(t, !ok)
	path, found := pax_path(
		transmute([]byte)string("27 mtime=1700000000.123456\n16 path=x/y.txt\n"),
	)
	testing.expect(t, found)
	testing.expect_value(t, path, "x/y.txt")
	_, err := read(transmute([]byte)strings.repeat("z", 512))
	testing.expect_value(t, err, Error.Bad_Header)
	empty, eerr := read(transmute([]byte)strings.repeat("\x00", 1024))
	testing.expect_value(t, eerr, Error.None)
	testing.expect_value(t, len(empty), 0)
}

// A size field in the base-256 form can name a number larger than an int
// holds. The shift used to wrap, the size came back negative, and read
// sliced the archive backwards. Found by jm:tar/fuzz.
@(test)
oversized_size_field_is_rejected :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	archive := make([]byte, 512)
	for i in 124 ..< 136 {
		archive[i] = 0xff
	}
	archive[156] = '0'
	entries, err := read(archive)
	testing.expect_value(t, err, Error.Bad_Header)
	testing.expect_value(t, len(entries), 0)
}

// The same field in octal, written negative.
@(test)
negative_size_field_is_rejected :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	archive := make([]byte, 512)
	copy(archive[124:136], "-0000000001")
	archive[156] = '0'
	_, err := read(archive)
	testing.expect_value(t, err, Error.Bad_Header)
}

// A pax record's length must reach past the space that ends its length
// field, or the record slice runs backwards. A record claiming length 1 is
// one input that used to do it.
@(test)
short_pax_record_is_ignored :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	// A pax extended header claiming a record of length 1, then a real file
	// after it. The bad record must be ignored and the file still read, so a
	// parser that gave up entirely would not pass either.
	archive := make([]byte, 3 * 512)
	copy(archive[0:100], "pax")
	copy(archive[124:136], "00000000002")
	archive[156] = 'x'
	copy(archive[512:], "1 ")
	copy(archive[1024:1124], "real.txt")
	copy(archive[1024 + 124:1024 + 136], "00000000000")
	archive[1024 + 156] = '0'

	entries, err := read(archive)
	testing.expect_value(t, err, Error.None)
	testing.expect_value(t, len(entries), 1)
	if len(entries) == 1 {
		// The unreadable pax record names nothing, so the entry keeps the
		// name in its own header.
		testing.expect_value(t, entries[0].name, "real.txt")
	}
}

// The size guard keeps the field inside an int, but read then adds the
// header's own offset to it, and that is the addition that used to wrap:
// a size of max(int) made end negative and read sliced backwards again.
// Found by reasoning about the first fix rather than by a fuzz run. The
// matching case is committed under tar/fuzz/corpus, so it is checked there
// too.
@(test)
size_that_overflows_when_offset_is_added_is_rejected :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	archive := make([]byte, 512)
	// A base-256 size field encoding exactly max(i64).
	archive[124] = 0x80 // the high bit marks base-256, and is masked off
	archive[128] = 0x7f
	for i in 129 ..< 136 {
		archive[i] = 0xff
	}
	archive[156] = '0'
	entries, err := read(archive)
	testing.expect_value(t, err, Error.Truncated)
	testing.expect_value(t, len(entries), 0)
}
