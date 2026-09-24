/*
Package fuzz is the jm:tar suite for jm:fuzz. tar reads archives it did not
write, so the promises worth checking are about what it does with bytes that
are wrong.

	report := fuzz.run({seed = 1, iterations = 10_000})

	survives     read returns entries or an error for any bytes at all
	in_bounds    every entry's data points inside the archive it came from
	round_trip   an archive this suite built reads back as what went in
	truncation   a good archive cut short is an error, not a wrong answer
	no_escape    extract writes nothing outside the directory it was given

no_escape is the one that matters most: an archive naming ../../etc/passwd
is the reason tar.extract has path checks at all, and the only way to know
they hold is to keep making archives that try.

The suite builds its own corpus rather than shelling out to git, so a case is
reproducible anywhere and a run needs nothing installed.
*/
package tar_fuzz

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"

import harness "jm:fuzz"
import "jm:tar"

// Sandbox is a directory a case may write into and nothing outside it.
Sandbox :: struct {
	// Where extract is pointed.
	dest: string,
	// The parent holding dest, watched for anything that escapes.
	root: string,
}

// properties is package level because a Suite holds a slice, which has to
// outlive the call that hands the Suite back.
properties := []harness.Property(Sandbox) {
	{"survives", survives},
	{"in_bounds", in_bounds},
	{"round_trip", round_trip},
	{"truncation", truncation},
	{"no_escape", no_escape},
}

// suite is jm:tar and its promises, ready for harness.run.
suite :: proc() -> harness.Suite(Sandbox) {
	return harness.Suite(Sandbox) {
		name       = "tar",
		setup      = open,
		teardown   = shut,
		// tar.read is a loop over bytes with nothing to interrupt, so a case
		// that will not finish cannot be cut short. A parser that stopped
		// advancing would hang the run rather than be reported, which is
		// why read's offset must always move forward.
		cancel     = nil,
		properties = properties,
	}
}

// run checks the suite. It is the whole package from a caller's side.
run :: proc(opts := harness.Opts{}, allocator := context.allocator) -> harness.Report {
	return harness.run(suite(), opts, allocator)
}

open :: proc() -> (Sandbox, bool) {
	parent := os.temp_directory(context.allocator) or_else ""
	root, err := os.make_directory_temp(parent, "jm-tar-fuzz-*", context.allocator)
	if err != nil {
		return {}, false
	}
	dest, _ := filepath.join({root, "out"}, context.allocator)
	if os.make_directory_all(dest) != nil {
		os.remove_all(root)
		return {}, false
	}
	return Sandbox{dest = dest, root = root}, true
}

shut :: proc(s: ^Sandbox) {
	if s.root != "" {
		os.remove_all(s.root)
	}
	s^ = {}
}

// survives reads whatever bytes it is handed. Any answer is allowed except
// not returning one.
survives :: proc(s: Sandbox, src: ^harness.Source) -> (detail: string, ok: bool) {
	archive := draw_archive(src)
	entries, err := tar.read(archive, context.temp_allocator)
	if err != .None && len(entries) != 0 {
		return fmt.tprintf("%v came back with %d entries", err, len(entries)), false
	}
	return "", true
}

// in_bounds checks the slices read hands back. Each entry's data points into
// the archive, so a length taken from the header that was never checked shows
// up here as a slice pointing somewhere else.
in_bounds :: proc(s: Sandbox, src: ^harness.Source) -> (detail: string, ok: bool) {
	archive := draw_archive(src)
	entries, err := tar.read(archive, context.temp_allocator)
	if err != .None {
		return "", true
	}
	lo := uintptr(raw_data(archive))
	hi := lo + uintptr(len(archive))
	for e, i in entries {
		if len(e.data) == 0 {
			continue
		}
		start := uintptr(raw_data(e.data))
		end := start + uintptr(len(e.data))
		if start < lo || end > hi {
			return fmt.tprintf(
					"entry %d data [%x, %x) is outside the archive [%x, %x)",
					i,
					start,
					end,
					lo,
					hi,
				),
				false
		}
	}
	return "", true
}

// round_trip builds an archive and reads it back. The names and the bytes
// that went in are the names and the bytes that come out.
round_trip :: proc(s: Sandbox, src: ^harness.Source) -> (detail: string, ok: bool) {
	files := make_files(src)
	archive := build(files, context.temp_allocator)
	entries, err := tar.read(archive, context.temp_allocator)
	if err != .None {
		return fmt.tprintf("an archive built here did not read: %v", err), false
	}
	if len(entries) != len(files) {
		return fmt.tprintf("wrote %d files, read %d entries", len(files), len(entries)), false
	}
	for f, i in files {
		if entries[i].name != f.name {
			return fmt.tprintf(
					"entry %d is %s, wanted %s",
					i,
					harness.show(entries[i].name),
					harness.show(f.name),
				),
				false
		}
		if !slice.equal(entries[i].data, f.body) {
			return fmt.tprintf(
					"entry %d holds %s, wanted %s",
					i,
					harness.show(entries[i].data),
					harness.show(f.body),
				),
				false
		}
	}
	return "", true
}

// truncation cuts a good archive short. A short archive may read as fewer
// entries or as an error; what it may not do is report an entry whose data
// was never there.
truncation :: proc(s: Sandbox, src: ^harness.Source) -> (detail: string, ok: bool) {
	files := make_files(src)
	archive := build(files, context.temp_allocator)
	if len(archive) == 0 {
		return "", true
	}
	cut := harness.integer_in(src, 0, len(archive))
	short := archive[:cut]
	entries, err := tar.read(short, context.temp_allocator)
	if err != .None {
		return "", true
	}
	for e, i in entries {
		if len(e.data) == 0 {
			continue
		}
		start := uintptr(raw_data(e.data))
		if start + uintptr(len(e.data)) > uintptr(raw_data(short)) + uintptr(len(short)) {
			return fmt.tprintf("entry %d reads past the %d bytes that are there", i, cut), false
		}
	}
	return "", true
}

// no_escape is the security property: whatever an archive calls its entries,
// extract writes inside the directory it was given and nowhere else.
no_escape :: proc(s: Sandbox, src: ^harness.Source) -> (detail: string, ok: bool) {
	files := make_files(src)
	// Give at least one of them a name that is trying to get out.
	if len(files) > 0 {
		files[0].name = escaping_name(src)
	}
	archive := build(files, context.temp_allocator)
	_, _ = tar.extract(archive, s.dest)

	// Nothing may exist in the sandbox outside the destination directory.
	strays := make([dynamic]string, context.temp_allocator)
	collect_strays(s.root, s.dest, &strays)
	if len(strays) > 0 {
		return fmt.tprintf("extract wrote outside its directory: %v", strays[:]), false
	}
	return "", true
}

// collect_strays gathers every path under root that is not inside dest:
// whatever extract wrote where it should not have.
@(private)
collect_strays :: proc(root, dest: string, strays: ^[dynamic]string) {
	handle, err := os.open(root)
	if err != nil {
		return
	}
	defer os.close(handle)
	entries, rerr := os.read_directory(handle, -1, context.temp_allocator)
	if rerr != nil {
		return
	}
	for e in entries {
		full, _ := filepath.join({root, e.name}, context.temp_allocator)
		if full == dest {
			continue
		}
		if !strings.has_prefix(full, dest) {
			append(strays, full)
			continue
		}
		if e.type == .Directory {
			collect_strays(full, dest, strays)
		}
	}
}

// File is one entry this suite puts into an archive it builds.
File :: struct {
	name: string,
	body: []byte,
	dir:  bool,
}

// make_files draws a handful of entries to build an archive from.
make_files :: proc(src: ^harness.Source) -> []File {
	n := harness.integer_in(src, 0, 5)
	out := make([]File, n, context.temp_allocator)
	for i in 0 ..< n {
		out[i] = File {
			name = safe_name(src, i),
			body = harness.bytes(src, 600, context.temp_allocator),
		}
	}
	return out
}

// NAME_PIECES builds a name a real archive might hold.
NAME_PIECES := []string{"a", "b", "dir", "sub", "-", ".", "_", "0", "file.txt", "x"}

// safe_name draws a name that stays inside the destination, for the
// properties that are not about escaping.
safe_name :: proc(src: ^harness.Source, i: int) -> string {
	body := harness.text(src, NAME_PIECES, 6, context.temp_allocator)
	if body == "" || strings.contains(body, "..") {
		return fmt.tprintf("f%d", i)
	}
	return fmt.tprintf("%s%d", body, i)
}

// ESCAPES are the shapes an archive uses to write where it should not.
ESCAPES := []string {
	"../escaped",
	"../../escaped",
	"/absolute",
	"//absolute",
	"a/../../escaped",
	"./../escaped",
	"a/./../../escaped",
	"....//escaped",
	"a/b/../../../escaped",
}

// escaping_name draws a name that is trying to leave the destination, either
// one of the known shapes or one assembled from the pieces they are made of.
escaping_name :: proc(src: ^harness.Source) -> string {
	if harness.boolean(src) {
		return harness.choice(src, ESCAPES)
	}
	return harness.text(
		src,
		[]string{"..", "/", "a", ".", "\\", "escaped"},
		10,
		context.temp_allocator,
	)
}

// draw_archive draws an archive: one this suite built, the same one damaged,
// or bytes that were never an archive at all.
draw_archive :: proc(src: ^harness.Source) -> []byte {
	switch harness.integer_in(src, 0, 3) {
	case 0:
		return build(make_files(src), context.temp_allocator)
	case 1:
		good := build(make_files(src), context.temp_allocator)
		corpus := [][]byte{good}
		out, _ := harness.damage(src, corpus, context.temp_allocator)
		return out
	}
	return harness.bytes(src, 2048, context.temp_allocator)
}

// build writes a ustar archive holding the given files, so the suite has
// well-formed input without needing a tar program.
build :: proc(files: []File, allocator := context.allocator) -> []byte {
	out := make([dynamic]byte, allocator)
	for f in files {
		header := make([]byte, tar.block, context.temp_allocator)
		name := f.name
		if len(name) > 100 {
			name = name[:100]
		}
		copy(header[0:100], name)
		put_octal(header[100:108], 0o644)
		put_octal(header[108:116], 0)
		put_octal(header[116:124], 0)
		put_octal(header[124:136], f.dir ? 0 : len(f.body))
		put_octal(header[136:148], 0)
		header[156] = f.dir ? '5' : '0'
		copy(header[257:263], "ustar\x00")
		copy(header[263:265], "00")
		// The checksum field counts as spaces while the sum is taken. tar
		// here does not verify it, but a well-formed archive carries one.
		for i in 148 ..< 156 {
			header[i] = ' '
		}
		sum := 0
		for b in header {
			sum += int(b)
		}
		put_octal(header[148:155], sum)
		header[155] = ' '

		append(&out, ..header)
		if !f.dir {
			append(&out, ..f.body)
			if pad := (tar.block - len(f.body) % tar.block) % tar.block; pad > 0 {
				append(&out, ..make([]byte, pad, context.temp_allocator))
			}
		}
	}
	// Two zero blocks end an archive.
	append(&out, ..make([]byte, 2 * tar.block, context.temp_allocator))
	return out[:]
}

// put_octal writes a header number: octal digits, NUL terminated, as the
// format wants them.
@(private)
put_octal :: proc(field: []byte, v: int) {
	s := fmt.tprintf("%0*o", len(field) - 1, v)
	if len(s) > len(field) - 1 {
		s = s[len(s) - (len(field) - 1):]
	}
	copy(field, s)
	field[len(field) - 1] = 0
}
