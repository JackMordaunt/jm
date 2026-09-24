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
