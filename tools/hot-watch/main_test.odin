package main

import "core:os"
import "core:slice"
import "core:testing"

import "jm:path"

@(test)
test_prune_keeps_the_named_builds_and_names_that_are_not_builds :: proc(t: ^testing.T) {
	dir, err := path.temp_dir("jm-hot-watch-", context.temp_allocator)
	testing.expect_value(t, err, nil)
	defer os.remove_all(dir)
	for name in ([]string{
		"app-child-100", "app-child-200", "app-child-300", "app-child-x", "app-child-host",
		"app-host", "other-100",
	}) {
		testing.expect_value(t, path.write(path.join(dir, name, allocator = context.temp_allocator), "x"), nil)
	}
	for name in ([]string{"app-child-100.dSYM", "app-child-200.dSYM", "app-child-300.dSYM"}) {
		sym := path.join(dir, name, "Contents", allocator = context.temp_allocator)
		testing.expect_value(t, path.mkdirs(sym), nil)
		testing.expect_value(t, path.write(path.join(sym, "dwarf", allocator = context.temp_allocator), "x"), nil)
	}

	prune(dir, "app-child", {"app-child-200", "app-child-300.exe"})

	entries, rerr := os.read_all_directory_by_path(dir, context.temp_allocator)
	testing.expect_value(t, rerr, nil)
	names := make([]string, len(entries), context.temp_allocator)
	for e, i in entries {
		names[i] = e.name
	}
	slice.sort(names)
	testing.expect(t, slice.equal(names, []string{
		"app-child-200", "app-child-200.dSYM", "app-child-300", "app-child-300.dSYM",
		"app-child-host", "app-child-x", "app-host", "other-100",
	}), "prune left the wrong names")
}

@(test)
test_build_stem_needs_digits_after_the_base :: proc(t: ^testing.T) {
	stem, ok := build_stem("app-child-123.exe", "app-child")
	testing.expect(t, ok && stem == "app-child-123")
	_, ok = build_stem("app-child-", "app-child")
	testing.expect(t, !ok)
	_, ok = build_stem("app-childish-1", "app-child")
	testing.expect(t, !ok)
	_, ok = build_stem("app-chil", "app-child")
	testing.expect(t, !ok)
}
