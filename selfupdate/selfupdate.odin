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
	if r.outcome == .Update_Available { fmt.eprintln(r.message) }

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

Network is jm:http, so libcurl.
*/
package selfupdate

import "core:crypto/ed25519"
import "core:crypto/hash"
import "core:encoding/hex"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

import "jm:http"
import "jm:path"

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

Result :: struct {
	outcome: Outcome,
	message: string,
	// The released version, from version.txt, when it was read.
	version: string,
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

SUMS_FILE    :: "sha256sums.txt"
SIG_FILE     :: "sha256sums.txt.sig"
VERSION_FILE :: "version.txt"
STAMP_FILE   :: "selfupdate.stamp"

// run performs the check or the update cfg.mode asks for.
run :: proc(cfg: Config) -> Result {
	exe := cfg.exe
	if exe == "" {
		p, err := os.get_executable_path(context.allocator)
		if err != nil {
			return {.Failed, fmt.aprintf("cannot find this executable: %v", err), ""}
		}
		exe = p
	}
	// The previous binary, left by an earlier apply. On Windows the run
	// that replaced it may still hold it open, so a failure here is fine.
	os.remove(strings.concatenate({exe, ".old"}))

	if cfg.version == "" {
		return {.Refused, "development build", ""}
	}
	if is_link(exe) {
		return {.Refused, "installed as a link, not a copy", ""}
	}

	interval := cfg.interval == 0 ? 24 * time.Hour : cfg.interval
	stamp := cfg.state_dir == "" ? "" : path.join(cfg.state_dir, STAMP_FILE)
	if cfg.mode == .Notify && stamp != "" {
		if t, err := os.modification_time_by_path(stamp); err == nil && time.since(t) < interval {
			return {.Skipped, "checked recently", ""}
		}
	}

	base := strings.trim_suffix(cfg.base_url, "/")
	if base == "" {
		return {.Failed, "no base_url", ""}
	}
	sums, ok := fetch(base, SUMS_FILE, cfg.timeout)
	if !ok {
		return {.Failed, fmt.aprintf("cannot fetch %s/%s", base, SUMS_FILE), ""}
	}
	sig, sok := fetch(base, SIG_FILE, cfg.timeout)
	if !sok {
		return {.Failed, fmt.aprintf("cannot fetch %s/%s", base, SIG_FILE), ""}
	}
	if !verify(cfg.public_key, sums, sig) {
		return {.Failed, "signature of sha256sums.txt does not verify", ""}
	}
	version := ""
	if v, vok := fetch(base, VERSION_FILE, cfg.timeout); vok {
		version = strings.trim_space(string(v))
	}

	want, found := published_hash_lookup(string(sums), cfg.asset)
	if !found {
		return {.Failed, fmt.aprintf("%s is not in the release", cfg.asset), version}
	}
	have, herr := file_hash(exe)
	if herr != nil {
		return {.Failed, fmt.aprintf("cannot read %s: %v", exe, herr), version}
	}
	if stamp != "" {
		path.mkdirs(cfg.state_dir)
		path.write(stamp, version)
	}
	if have == want {
		return {.Up_To_Date, "up to date", version}
	}
	if cfg.mode == .Notify {
		msg := version == "" ? "update available" : fmt.aprintf("update available: %s", version)
		return {.Update_Available, msg, version}
	}

	fresh := strings.concatenate({exe, ".new"})
	if !fetch_to_file(base, cfg.asset, fresh, cfg.timeout) {
		os.remove(fresh)
		return {.Failed, fmt.aprintf("cannot download %s", cfg.asset), version}
	}
	got, gerr := file_hash(fresh)
	if gerr != nil || got != want {
		os.remove(fresh)
		return {.Failed, "downloaded file does not match its published hash", version}
	}
	if msg := swap(exe, fresh); msg != "" {
		os.remove(fresh)
		return {.Failed, msg, version}
	}
	if cfg.no_reexec {
		return {.Applied, "updated", version}
	}
	args := cfg.args
	if args == nil && len(os.args) > 1 {
		args = os.args[1:]
	}
	if msg := reexec(exe, args); msg != "" {
		return {.Failed, msg, version}
	}
	return {.Applied, "updated", version}
}

// key_from_hex decodes a 64-character hex public key.
key_from_hex :: proc(s: string) -> ([]byte, bool) {
	b, ok := hex.decode(transmute([]byte)s)
	if !ok || len(b) != ed25519.PUBLIC_KEY_SIZE {
		return nil, false
	}
	return b, true
}

// ---- internals ----------------------------------------------------------

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

// published_hash_lookup finds the hex hash for name in sha256sum's output, which
// writes `hash  name`, or `hash *name` for a binary on Windows.
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
			return strings.to_lower(line[:i]), true
		}
	}
	return "", false
}

file_hash :: proc(p: string) -> (string, os.Error) {
	data, err := os.read_entire_file_from_path(p, context.allocator)
	if err != nil {
		return "", err
	}
	digest := hash.hash_bytes(.SHA256, data)
	return string(hex.encode(digest)), nil
}

fetch :: proc(base, name: string, timeout: time.Duration) -> ([]byte, bool) {
	if !strings.contains(base, "://") {
		data, err := os.read_entire_file_from_path(path.join(base, name), context.allocator)
		return data, err == nil
	}
	url := strings.concatenate({base, "/", name})
	res, err := http.get(url, {timeout = timeout == 0 ? 60 * time.Second : timeout})
	if err != .None || !res.ok {
		return nil, false
	}
	return transmute([]byte)res.body, true
}

fetch_to_file :: proc(base, name, dest: string, timeout: time.Duration) -> bool {
	if !strings.contains(base, "://") {
		return os.copy_file(dest, path.join(base, name)) == nil
	}
	url := strings.concatenate({base, "/", name})
	res, err := http.download(url, dest, {timeout = timeout == 0 ? 60 * time.Second : timeout})
	return err == .None && res.ok
}

// swap moves the running executable aside and the new file into its place.
// Renaming a running executable is allowed on every platform; overwriting
// one is not on Windows, and on Unix the old process keeps its inode.
swap :: proc(exe, fresh: string) -> string {
	old := strings.concatenate({exe, ".old"})
	os.remove(old)
	if err := os.rename(exe, old); err != nil {
		return fmt.aprintf("cannot move %s aside: %v", exe, err)
	}
	if err := os.rename(fresh, exe); err != nil {
		// Put the old binary back rather than leave nothing on PATH.
		os.rename(old, exe)
		return fmt.aprintf("cannot install %s: %v", exe, err)
	}
	when ODIN_OS != .Windows {
		os.change_mode(exe, os.Permissions_All - os.Permissions_Write_All + {.Write_User})
	}
	return ""
}

is_link :: proc(p: string) -> bool {
	_, err := os.read_link(p, context.temp_allocator)
	return err == nil
}
