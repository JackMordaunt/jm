package tar_fuzz

import "core:os"
import "core:slice"
import "core:strings"
import "core:testing"

import harness "jm:fuzz"
import "jm:tar"

// A short run on fixed seeds, so `just test` catches a regression without
// waiting for a long fuzz run.
@(test)
properties_hold :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	for seed in ([]u64{1, 3, 7, 99}) {
		report := run({seed = seed, iterations = 300})
		testing.expect_value(t, report.iterations, 300)
		for f in report.failures {
			testing.expectf(
				t,
				false,
				"%s failed at case %d (replay: jm-fuzz tar -seed=%d): %s",
				f.property,
				f.iteration,
				f.seed,
				f.detail,
			)
		}
	}
}

@(test)
suite_is_complete :: proc(t: ^testing.T) {
	s := suite()
	testing.expect_value(t, s.name, "tar")
	testing.expect(t, s.setup != nil, "a case needs a sandbox")
	testing.expect(t, s.teardown != nil, "a case must give it back")
	testing.expect(t, len(s.properties) == 5, "every property must be registered")
	for p in s.properties {
		testing.expect(t, p.name != "", "a property needs a name to be saved under")
		testing.expect(t, p.check != nil, "a property needs a body")
	}
}

// The archive this suite builds has to be one jm:tar accepts, or every
// property built on it is testing the builder's bugs instead of tar's.
@(test)
built_archives_are_well_formed :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	files := []File {
		{name = "a.txt", body = transmute([]byte)string("alpha")},
		{name = "dir/b.bin", body = []byte{0, 1, 2, 0xff}},
		{name = "empty", body = nil},
	}
	archive := build(files)
	testing.expect(t, len(archive) % tar.block == 0, "an archive is whole blocks")

	entries, err := tar.read(archive)
	testing.expect_value(t, err, tar.Error.None)
	testing.expect_value(t, len(entries), 3)
	for f, i in files {
		testing.expect_value(t, entries[i].name, f.name)
		testing.expect(t, slice.equal(entries[i].data, f.body), "the bytes must match")
	}
}

// no_escape is only worth anything if the names it draws really do try to
// escape, so check the generator rather than trusting it.
@(test)
escaping_names_actually_escape :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	bytes := make([]byte, 4096)
	for i in 0 ..< len(bytes) {
		bytes[i] = byte(i * 13 + 7)
	}
	src := harness.source(bytes)
	dangerous := 0
	for _ in 0 ..< 500 {
		name := escaping_name(&src)
		if len(name) > 0 && (name[0] == '/' || contains_dotdot(name)) {
			dangerous += 1
		}
	}
	testing.expect(t, dangerous > 100, "most drawn names must be trying to get out")
}

@(private = "file")
contains_dotdot :: proc(s: string) -> bool {
	for i in 0 ..< len(s) - 1 {
		if s[i] == '.' && s[i + 1] == '.' {
			return true
		}
	}
	return false
}

// A run is a pure function of its seed.
@(test)
same_seed_same_run :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	first := run({seed = 5, iterations = 100})
	second := run({seed = 5, iterations = 100})
	testing.expect(t, first.digest != 0, "a run that generated cases has a digest")
	testing.expect_value(t, first.digest, second.digest)
}

// The committed corpus is replayed by `just test`, so a bug found once by
// fuzzing stays found without anyone having to run the fuzzer again.
@(test)
regressions_still_pass :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	report := run({seed = 1, iterations = 1, corpus_dir = CORPUS})
	committed := count_cases(CORPUS)
	testing.expect(t, committed >= 1, "this suite has regressions committed")
	testing.expect_value(t, report.replayed, committed)
	for f in report.failures {
		testing.expectf(t, false, "%s regressed: %s", f.property, f.detail)
	}
}

// count_cases is how many regressions are committed, so the test below can
// say the corpus was read rather than only that nothing failed.
@(private = "file")
count_cases :: proc(dir: string) -> int {
	handle, err := os.open(dir)
	if err != nil {
		return 0
	}
	defer os.close(handle)
	entries, rerr := os.read_directory(handle, -1, context.temp_allocator)
	if rerr != nil {
		return 0
	}
	n := 0
	for e in entries {
		if strings.has_suffix(e.name, ".case") {
			n += 1
		}
	}
	return n
}
