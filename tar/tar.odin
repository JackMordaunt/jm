/*
Package tar reads a tar archive in memory and writes its files out, which
is what a repository's `git archive` output needs and nothing more: ustar
and GNU headers, the pax extended headers git writes for long paths and
the commit id, regular files and directories. Links, devices and anything
else are skipped, and a path that climbs out of the destination is not
written anywhere.

	archive := must(sh.exec({"git", "archive", "--format=tar", "HEAD"}))
	count := must(tar.extract(transmute([]byte)archive.stdout, "build/tree"))
*/
package tar

import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"

// Error is why an archive could not be read or written.
Error :: enum {
	None,
	// A header is not a tar header: the archive is truncated or not tar.
	Bad_Header,
	// An entry's size does not fit in what follows its header.
	Truncated,
	// A file or directory could not be written.
	Write_Failed,
}

// Entry is one file the archive holds, as extract hands it to a visitor.
Entry :: struct {
	name: string,
	data: []byte,
	dir:  bool,
}

// block is the header and record size the format is built on.
block :: 512

// extract writes the archive's regular files and directories under dir,
// creating directories as needed, and returns how many files it wrote.
extract :: proc(archive: []byte, dir: string) -> (count: int, err: Error) {
	entries := read(archive, context.temp_allocator) or_return
	for e in entries {
		clean, _ := filepath.clean(e.name, context.temp_allocator)
		if clean == "." ||
		   clean == "" ||
		   strings.has_prefix(clean, "..") ||
		   strings.has_prefix(clean, "/") ||
		   strings.contains(clean, "/../") {
			continue
		}
		full := filepath.join({dir, clean}, context.temp_allocator) or_else clean
		if e.dir {
			if !os.is_dir(full) && os.make_directory_all(full) != nil {
				return count, .Write_Failed
			}
			continue
		}
		parent := filepath.dir(full)
		if !os.is_dir(parent) && os.make_directory_all(parent) != nil {
			return count, .Write_Failed
		}
		if os.write_entire_file(full, e.data) != nil {
			return count, .Write_Failed
		}
		count += 1
	}
	return count, .None
}

// read lists the archive's regular files and directories, with their data
// pointing into the archive. A pax extended header's path, or a GNU long
// name, names the entry that follows it.
read :: proc(archive: []byte, allocator := context.allocator) -> (entries: []Entry, err: Error) {
	out := make([dynamic]Entry, allocator)
	offset := 0
	pending_name := ""
	for offset + block <= len(archive) {
		header := archive[offset:offset + block]
		if is_zero(header) {
			break // Two zero blocks end the archive; one is enough to stop.
		}
		size, ok := octal(header[124:136])
		if !ok || size < 0 {
			return nil, .Bad_Header
		}
		start := offset + block
		// Compared by subtraction, because start + size is the addition that
		// overflows: the size guard above keeps size inside an int, and
		// adding start to it is what pushes it back out. The loop condition
		// puts start no further than len(archive), so this cannot wrap.
		if size > len(archive) - start {
			return nil, .Truncated
		}
		end := start + size
		flag := header[156]
		name := field(header[0:100])
		if prefix := field(header[345:500]); prefix != "" && string(header[257:262]) == "ustar" {
			name = strings.concatenate({prefix, "/", name}, allocator)
		}
		if pending_name != "" {
			name = pending_name
			pending_name = ""
		}
		data := archive[start:end]
		switch flag {
		case 'x':
			if path, found := pax_path(data); found {
				pending_name = strings.clone(path, allocator)
			}
		case 'L':
			pending_name = strings.clone(strings.trim_right(string(data), "\x00"), allocator)
		case '0', 0, '7':
			append(&out, Entry{name = strings.clone(name, allocator), data = data})
		case '5':
			append(&out, Entry{name = strings.clone(name, allocator), dir = true})
		case 'g':
		// A global header carries the commit id, which names no file.
		}
		offset = end + ((block - end % block) % block)
	}
	return out[:], .None
}

// field is a fixed-width header field, up to its first NUL.
field :: proc(raw: []byte) -> string {
	s := string(raw)
	if i := strings.index_byte(s, 0); i >= 0 {
		s = s[:i]
	}
	return s
}

// octal reads a size field: octal digits, or the base-256 form a large
// entry takes.
octal :: proc(raw: []byte) -> (int, bool) {
	if len(raw) > 0 && raw[0] & 0x80 != 0 {
		n := 0
		for b, i in raw {
			v := int(b)
			if i == 0 {
				v &= 0x7f
			}
			// A size larger than an int holds is not a size this can read.
			// Without the check the shift wraps, the size comes back
			// negative, and the caller slices the archive backwards.
			if n > (max(int) - v) / 256 {
				return 0, false
			}
			n = n << 8 | v
		}
		return n, true
	}
	s := strings.trim(field(raw), " ")
	if s == "" {
		return 0, true
	}
	v, ok := strconv.parse_int(s, 8)
	if !ok || v < 0 {
		return 0, false
	}
	return v, true
}

// pax_path reads the path record out of a pax extended header, whose
// records are "length key=value\n".
pax_path :: proc(data: []byte) -> (string, bool) {
	rest := string(data)
	for len(rest) > 0 {
		space := strings.index_byte(rest, ' ')
		if space < 0 {
			break
		}
		length, ok := strconv.parse_int(rest[:space])
		// The record is rest[space + 1:length], so a length that does not
		// reach past the space would slice backwards.
		if !ok || length <= space + 1 || length > len(rest) {
			break
		}
		record := rest[space + 1:length]
		if strings.has_prefix(record, "path=") {
			return strings.trim_suffix(record[5:], "\n"), true
		}
		rest = rest[length:]
	}
	return "", false
}

is_zero :: proc(b: []byte) -> bool {
	for c in b {
		if c != 0 {
			return false
		}
	}
	return true
}
