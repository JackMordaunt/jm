package path

import "core:math/rand"
import "core:os"
import "core:strings"
import "core:testing"

@(test)
expand_home :: proc(t: ^testing.T) {
	h := home(context.temp_allocator)
	testing.expect(t, len(h) > 0, "home must resolve")
	testing.expect_value(t, expand("~", context.temp_allocator), h)
	testing.expect(t, strings.has_prefix(expand("~/x", context.temp_allocator), h))
	testing.expect(t, strings.has_suffix(expand("~/x", context.temp_allocator), "x"))
	testing.expect_value(t, expand("a/../b", context.temp_allocator), "b")
}

@(test)
files_roundtrip :: proc(t: ^testing.T) {
	root, err := temp_dir("jm-path-test-", context.temp_allocator)
	testing.expect_value(t, err, nil)
	defer remove_all(root)

	nested := join(root, "a", "b", allocator = context.temp_allocator)
	testing.expect_value(t, mkdirs(nested), nil)
	testing.expect_value(t, mkdirs(nested), nil) // existing is fine
	testing.expect(t, is_dir(nested))

	file := join(nested, "f.txt", allocator = context.temp_allocator)
	testing.expect_value(t, write(file, "one\r\ntwo\n"), nil)
	testing.expect_value(t, append_file(file, "three\n"), nil)

	text, rerr := read(file, context.temp_allocator)
	testing.expect_value(t, rerr, nil)
	testing.expect_value(t, text, "one\r\ntwo\nthree\n")

	ls, lerr := read_lines(file, context.temp_allocator)
	testing.expect_value(t, lerr, nil)
	testing.expect_value(t, len(ls), 3)
	if len(ls) == 3 {
		testing.expect_value(t, ls[0], "one")
		testing.expect_value(t, ls[2], "three")
	}

	other := join(root, "z.txt", allocator = context.temp_allocator)
	testing.expect_value(t, write(other, "z"), nil)
	names, nerr := list(root, context.temp_allocator)
	testing.expect_value(t, nerr, nil)
	testing.expect_value(t, len(names), 2)
	if len(names) == 2 {
		testing.expect_value(t, names[0], "a")
		testing.expect_value(t, names[1], "z.txt")
	}

	files, werr := walk(root, context.temp_allocator)
	testing.expect_value(t, werr, nil)
	testing.expect_value(t, len(files), 2)
	if len(files) == 2 {
		testing.expect(t, strings.has_suffix(files[0], "f.txt"))
		testing.expect(t, strings.has_suffix(files[1], "z.txt"))
	}

	_, missing := read(join(root, "missing", allocator = context.temp_allocator), context.temp_allocator)
	testing.expect(t, missing != nil)
	testing.expect(t, missing == os.General_Error.Not_Exist)
}

@(test)
same_paths :: proc(t: ^testing.T) {
	testing.expect(t, same("a/b/../c", "a/c"))
	testing.expect(t, !same("a/c", "a/d"))
	when ODIN_OS == .Windows || ODIN_OS == .Darwin {
		testing.expect(t, same("A/C", "a/c"))
	}
}

@(test)
app_dirs_exist :: proc(t: ^testing.T) {
	d, err := cache_dir("jm-path-test", context.temp_allocator)
	testing.expect_value(t, err, nil)
	testing.expect(t, is_dir(d))
	testing.expect(t, strings.has_suffix(d, "jm-path-test"), "cache_dir must use the app name")
	remove_all(d)
}

// Resetting the random seed must not make temp_dir reuse a removed directory's name.
@(test)
temp_dirs_differ_under_one_seed :: proc(t: ^testing.T) {
	rand.reset(t.seed)
	a, ea := temp_dir("jm-path-same-", context.temp_allocator)
	if !testing.expect_value(t, ea, nil) {
		return
	}
	testing.expect_value(t, remove_all(a), nil)
	rand.reset(t.seed)
	b, eb := temp_dir("jm-path-same-", context.temp_allocator)
	defer remove_all(b)

	testing.expect_value(t, eb, nil)
	testing.expect(t, a != b, "two fresh folders share a name")
	testing.expect(t, is_dir(b), "the second folder exists")
}

@(test)
temp_directory_preserves_pattern_and_parent :: proc(t: ^testing.T) {
	root, err := temp_dir("jm-path-pattern-", context.temp_allocator)
	if !testing.expect_value(t, err, nil) {
		return
	}
	defer remove_all(root)

	name, nerr := make_directory_temp(root, "before-*-after", context.temp_allocator)
	testing.expect_value(t, nerr, nil)
	testing.expect_value(t, dir(name), root)
	testing.expect(t, strings.has_prefix(base(name), "before-"))
	testing.expect(t, strings.has_suffix(base(name), "-after"))
	testing.expect(t, is_dir(name))
	_, invalid := make_directory_temp(root, "nested/name", context.temp_allocator)
	testing.expect_value(t, invalid, os.Error(.Pattern_Has_Separator))
}
