/*
Package selfupdate lets a distributed binary update itself from a release
served at any base path.

	r := selfupdate.run(selfupdate.Config{
		base_url   = "https://example.com/tool/latest",
		version    = VERSION,     // "" on a development build: nothing happens
		asset      = "tool-linux-amd64",
		public_key = PUBLIC_KEY,  // 32 raw Ed25519 bytes, embedded
		mode       = .Notify,     // or .Apply on `tool update`
		state_dir  = state,
	})
	if r.outcome == .Update_Available { fmt.eprintln(selfupdate.message(&r)) }

The host is anything that serves files under one base path by plain GET: a
GitHub release (`https://github.com/<owner>/<repo>/releases/latest/download`),
an S3 bucket, a static web server, a network share, or a directory (a
base_url without a scheme is read from disk, which is how the tests work).
The layout under the base is:

	<asset>               one file per platform, named as Config.asset
	sha256sums.txt        `sha256sum` output over the assets
	sha256sums.txt.sig    64-byte Ed25519 signature of sha256sums.txt
	version.txt           the release's version, for display only

Nothing is trusted until the signature verifies with the embedded key; the
checksum file alone would only prove a download arrived intact. An update
exists when the published hash for this asset differs from the hash of the
running executable, so no version is parsed: version is for display and
the development-build guard.

Notify checks at most once per interval, recorded by a stamp under
state_dir, and never changes anything. Apply downloads the asset, verifies
it, renames the running executable to `<exe>.old`, moves the new one in,
and runs it again with the same arguments: execve on Unix, spawn-wait-exit
on Windows. The `.old` file is removed on the next run.

A development build (empty version) or an executable that is a symlink,
which is how a checkout is installed, is refused rather than replaced.

Memory: run allocates nothing from context.allocator. Paths, the checksum
file, the signature and the messages live in fixed buffers on the stack
and in the Result, files are hashed in chunks, and downloads stream to
disk. The caps (4 KiB paths, 16 KiB of checksums, 128 bytes of version)
fail loudly when exceeded. core:os and jm:http use the temp allocator for
their own scoped conversions.
*/
package selfupdate

import "core:crypto/ed25519"
import "core:crypto/sha2"
import "core:fmt"
import "core:io"
import "core:mem"
import "core:os"
import "core:strings"
import "core:time"

import "jm:http"

Mode :: enum {
	Notify,
	Apply,
}

Outcome :: enum {
	// The check was rate limited, or nothing applied.
	Skipped,
	Up_To_Date,
	Update_Available,
	// The executable was replaced. Without no_reexec this is never returned:
	// the new binary has taken over.
	Applied,
	// A development build, a symlink, or another reason not to touch it.
	Refused,
	// Network, signature, hash or file-system failure; message says which.
	Failed,
}

// Result is returned by value; message and version read its inline buffers.
Result :: struct {
	outcome:     Outcome,
	message_buf: [256]byte,
	message_len: int,
	version_buf: [VERSION_CAP]byte,
	version_len: int,
}

message :: proc(r: ^Result) -> string {
	return string(r.message_buf[:r.message_len])
}

// version is the released version from version.txt, when it was read.
version :: proc(r: ^Result) -> string {
	return string(r.version_buf[:r.version_len])
}

Config :: struct {
	// Where the release files are served, without a trailing slash. A value
	// without "://" is a directory read directly.
	base_url:   string,
	// This build's version. "" marks a development build and refuses.
	version:    string,
	// This build's file name in the release.
	asset:      string,
	// 32 raw Ed25519 public key bytes.
	public_key: []byte,
	mode:       Mode,
	// Holds the check stamp. "" checks every time.
	state_dir:  string,
	// Minimum time between Notify checks. 0 means 24 hours.
	interval:   time.Duration,
	// The executable to update. "" means this process's own.
	exe:        string,
	// Arguments for the re-exec. nil means this process's own.
	args:       []string,
	// Return Applied instead of running the new binary.
	no_reexec:  bool,
	// Whole-request timeout for each download. 0 means 60 seconds.
	timeout:    time.Duration,
}

SUMS_FILE :: "sha256sums.txt"
SIG_FILE :: "sha256sums.txt.sig"
VERSION_FILE :: "version.txt"
STAMP_FILE :: "selfupdate.stamp"

PATH_CAP :: 4 * mem.Kilobyte
SUMS_CAP :: 16 * mem.Kilobyte
// CHUNK is the read size for hashing and copying files.
CHUNK :: 64 * mem.Kilobyte
VERSION_CAP :: 128
HEX_DIGEST :: 2 * sha2.DIGEST_SIZE_256

// run performs the check or the update cfg.mode asks for.
run :: proc(cfg: Config) -> (r: Result) {
	// The one place core:os needs an allocator, given a stack arena.
	scratch: [PATH_CAP]byte
	arena: mem.Arena
	mem.arena_init(&arena, scratch[:])

	exe := cfg.exe
	if exe == "" {
		p, err := os.get_executable_path(mem.arena_allocator(&arena))
		if err != nil {
			return failf(&r, .Failed, "cannot find this executable: %v", err)
		}
		exe = p
	}
	if len(exe) + 4 >= PATH_CAP {
		return failf(&r, .Failed, "executable path longer than %d bytes", PATH_CAP)
	}
	old_path, new_path: [PATH_CAP]byte
	old := fmt.bprintf(old_path[:], "%s.old", exe)
	fresh := fmt.bprintf(new_path[:], "%s.new", exe)
	// The previous binary, left by an earlier apply. On Windows the run
	// that replaced it may still hold it open, so a failure here is fine.
	os.remove(old)

	if cfg.version == "" {
		return failf(&r, .Refused, "development build")
	}
	if is_link(exe) {
		return failf(&r, .Refused, "installed as a link, not a copy")
	}

	interval := cfg.interval == 0 ? 24 * time.Hour : cfg.interval
	stamp_path: [PATH_CAP]byte
	stamp := ""
	if cfg.state_dir != "" {
		stamp = fmt.bprintf(stamp_path[:], "%s%c%s", cfg.state_dir, SEPARATOR, STAMP_FILE)
	}
	if cfg.mode == .Notify && stamp != "" {
		if t, err := os.modification_time_by_path(stamp); err == nil && time.since(t) < interval {
			return failf(&r, .Skipped, "checked recently")
		}
	}

	base := strings.trim_suffix(cfg.base_url, "/")
	if base == "" {
		return failf(&r, .Failed, "no base_url")
	}
	sums: Fixed(SUMS_CAP)
	if !fetch(base, SUMS_FILE, fixed_writer(&sums), cfg.timeout) {
		return failf(&r, .Failed, "cannot fetch %s/%s", base, SUMS_FILE)
	}
	sig: Fixed(ed25519.SIGNATURE_SIZE)
	if !fetch(base, SIG_FILE, fixed_writer(&sig), cfg.timeout) {
		return failf(&r, .Failed, "cannot fetch %s/%s", base, SIG_FILE)
	}
	if !verify(cfg.public_key, fixed_bytes(&sums), fixed_bytes(&sig)) {
		return failf(&r, .Failed, "signature of %s does not verify", SUMS_FILE)
	}
	ver: Fixed(VERSION_CAP)
	if fetch(base, VERSION_FILE, fixed_writer(&ver), cfg.timeout) {
		v := strings.trim_space(fixed_string(&ver))
		r.version_len = copy(r.version_buf[:], v)
	}

	want, found := published_hash_lookup(fixed_string(&sums), cfg.asset)
	if !found {
		return failf(&r, .Failed, "%s is not in the release", cfg.asset)
	}
	have: [HEX_DIGEST]byte
	if err := file_hash(exe, have[:]); err != nil {
		return failf(&r, .Failed, "cannot read %s: %v", exe, err)
	}
	if stamp != "" {
		os.make_directory_all(cfg.state_dir)
		_ = os.write_entire_file(stamp, r.version_buf[:r.version_len])
	}
	if strings.equal_fold(string(have[:]), want) {
		return failf(&r, .Up_To_Date, "up to date")
	}
	if cfg.mode == .Notify {
		if r.version_len == 0 {
			return failf(&r, .Update_Available, "update available")
		}
		return failf(&r, .Update_Available, "update available: %s", version(&r))
	}

	if !fetch_to_file(base, cfg.asset, fresh, cfg.timeout) {
		os.remove(fresh)
		return failf(&r, .Failed, "cannot download %s", cfg.asset)
	}
	got: [HEX_DIGEST]byte
	if err := file_hash(fresh, got[:]); err != nil || !strings.equal_fold(string(got[:]), want) {
		os.remove(fresh)
		return failf(&r, .Failed, "downloaded file does not match its published hash")
	}
	if !swap(exe, old, fresh, &r) {
		os.remove(fresh)
		return r
	}
	if cfg.no_reexec {
		return failf(&r, .Applied, "updated")
	}
	args := cfg.args
	if args == nil && len(os.args) > 1 {
		args = os.args[1:]
	}
	reexec(exe, args, &r)
	return r
}

// key_from_hex decodes a 64-character hex public key into dst, which must
// hold 32 bytes.
key_from_hex :: proc(s: string, dst: []byte) -> bool {
	if len(s) != 2 * ed25519.PUBLIC_KEY_SIZE || len(dst) < ed25519.PUBLIC_KEY_SIZE {
		return false
	}
	for i in 0 ..< ed25519.PUBLIC_KEY_SIZE {
		hi, ok1 := nibble(s[2 * i])
		lo, ok2 := nibble(s[2 * i + 1])
		if !ok1 || !ok2 {
			return false
		}
		dst[i] = hi << 4 | lo
	}
	return true
}

// ---- internals ----------------------------------------------------------

SEPARATOR :: '\\' when ODIN_OS == .Windows else '/'

// failf sets the outcome and formats the message into the Result.
failf :: proc(r: ^Result, outcome: Outcome, format: string, args: ..any) -> Result {
	r.outcome = outcome
	r.message_len = len(fmt.bprintf(r.message_buf[:], format, ..args))
	return r^
}

nibble :: proc(c: byte) -> (byte, bool) {
	switch {
	case c >= '0' && c <= '9':
		return c - '0', true
	case c >= 'a' && c <= 'f':
		return c - 'a' + 10, true
	case c >= 'A' && c <= 'F':
		return c - 'A' + 10, true
	}
	return 0, false
}

verify :: proc(public_key, msg, sig: []byte) -> bool {
	pk: ed25519.Public_Key
	if !ed25519.public_key_set_bytes(&pk, public_key) {
		return false
	}
	if len(sig) != ed25519.SIGNATURE_SIZE {
		return false
	}
	return ed25519.verify(&pk, msg, sig)
}

// published_hash_lookup finds the hex hash for name in sha256sum's output,
// which writes `hash  name`, or `hash *name` for a binary on Windows. The
// hash is returned as written; callers compare it case-insensitively.
published_hash_lookup :: proc(sums, name: string) -> (string, bool) {
	rest := sums
	for raw in strings.split_lines_iterator(&rest) {
		line := strings.trim_space(strings.trim_suffix(raw, "\r"))
		i := strings.index_byte(line, ' ')
		if i <= 0 {
			continue
		}
		file := strings.trim_left(line[i:], " *")
		if file == name {
			return line[:i], true
		}
	}
	return "", false
}

// file_hash writes the lowercase hex SHA-256 of a file into dst, reading
// it in CHUNK-sized pieces.
file_hash :: proc(p: string, dst: []byte) -> os.Error {
	f, err := os.open(p)
	if err != nil {
		return err
	}
	defer os.close(f)
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	chunk: [CHUNK]byte
	for {
		n, rerr := os.read(f, chunk[:])
		if n > 0 {
			sha2.update(&ctx, chunk[:n])
		}
		if rerr != nil || n == 0 {
			break
		}
	}
	digest: [sha2.DIGEST_SIZE_256]byte
	sha2.final(&ctx, digest[:])
	hex := HEX
	for b, i in digest {
		dst[2 * i] = hex[b >> 4]
		dst[2 * i + 1] = hex[b & 0xF]
	}
	return nil
}

HEX :: "0123456789abcdef"

// fetch writes base/name into dst: over HTTP when base has a scheme,
// otherwise from the file system.
fetch :: proc(base, name: string, dst: io.Writer, timeout: time.Duration) -> bool {
	if !strings.contains(base, "://") {
		src: [PATH_CAP]byte
		return copy_file_to(fmt.bprintf(src[:], "%s%c%s", base, SEPARATOR, name), dst)
	}
	url: [PATH_CAP]byte
	res, err := http.stream(
		"GET",
		fmt.bprintf(url[:], "%s/%s", base, name),
		dst,
		{timeout = timeout == 0 ? 60 * time.Second : timeout},
	)
	return err == .None && res.ok
}

fetch_to_file :: proc(base, name, dest: string, timeout: time.Duration) -> bool {
	f, err := os.create(dest)
	if err != nil {
		return false
	}
	defer os.close(f)
	return fetch(base, name, os.to_writer(f), timeout)
}

// copy_file_to streams a file into a writer through a stack buffer.
copy_file_to :: proc(p: string, dst: io.Writer) -> bool {
	f, err := os.open(p)
	if err != nil {
		return false
	}
	defer os.close(f)
	chunk: [CHUNK]byte
	for {
		n, rerr := os.read(f, chunk[:])
		if n > 0 {
			if _, werr := io.write_full(dst, chunk[:n]); werr != nil {
				return false
			}
		}
		if n == 0 || rerr != nil {
			return n == 0 || rerr == .EOF
		}
	}
}

// swap moves the running executable aside and the new file into its place.
// Renaming a running executable is allowed on every platform; overwriting
// one is not on Windows, and on Unix the old process keeps its inode.
swap :: proc(exe, old, fresh: string, r: ^Result) -> bool {
	os.remove(old)
	if err := os.rename(exe, old); err != nil {
		failf(r, .Failed, "cannot move %s aside: %v", exe, err)
		return false
	}
	if err := os.rename(fresh, exe); err != nil {
		// Put the old binary back rather than leave nothing on PATH.
		os.rename(old, exe)
		failf(r, .Failed, "cannot install %s: %v", exe, err)
		return false
	}
	when ODIN_OS != .Windows {
		os.change_mode(exe, os.Permissions_All - os.Permissions_Write_All + {.Write_User})
	}
	return true
}

is_link :: proc(p: string) -> bool {
	buf: [PATH_CAP]byte
	arena: mem.Arena
	mem.arena_init(&arena, buf[:])
	_, err := os.read_link(p, mem.arena_allocator(&arena))
	return err == nil
}
