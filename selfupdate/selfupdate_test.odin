package selfupdate

import "core:crypto/ed25519"
import "core:crypto/hash"
import "core:encoding/hex"
import "core:os"
import "core:strings"
import "core:testing"
import "core:time"

import "jm:path"

// Release is a fake release on disk, signed with a throwaway key.
Release :: struct {
	dir:        string,
	public_key: []byte,
	priv:       ed25519.Private_Key,
}

make_release :: proc(t: ^testing.T, root: string, asset, body, version: string) -> (r: Release) {
	r.dir = path.join(root, "release")
	testing.expect_value(t, path.mkdirs(r.dir), nil)
	testing.expect(t, ed25519.private_key_generate(&r.priv), "key generation")
	r.public_key = make([]byte, ed25519.PUBLIC_KEY_SIZE)
	ed25519.private_key_public_bytes(&r.priv, r.public_key)
	write_asset(t, &r, asset, body)
	testing.expect_value(t, path.write(path.join(r.dir, VERSION_FILE), strings.concatenate({version, "\n"})), nil)
	return r
}

// write_asset writes the asset and re-signs the sums, in sha256sum's
// Windows form with the binary marker, which the parser must accept.
write_asset :: proc(t: ^testing.T, r: ^Release, asset, body: string) {
	testing.expect_value(t, path.write(path.join(r.dir, asset), body), nil)
	digest := hash.hash_string(.SHA256, body)
	sums := strings.concatenate({string(hex.encode(digest)), " *", asset, "\n"})
	sign_sums(t, r, sums)
}

sign_sums :: proc(t: ^testing.T, r: ^Release, sums: string) {
	testing.expect_value(t, path.write(path.join(r.dir, SUMS_FILE), sums), nil)
	sig := make([]byte, ed25519.SIGNATURE_SIZE)
	ed25519.sign(&r.priv, transmute([]byte)sums, sig)
	testing.expect_value(t, path.write(path.join(r.dir, SIG_FILE), string(sig)), nil)
}

// exe_file is a stand-in executable with known content.
exe_file :: proc(t: ^testing.T, root, body: string) -> string {
	p := path.join(root, "tool")
	testing.expect_value(t, path.write(p, body), nil)
	return p
}

config :: proc(r: Release, exe, state: string, mode: Mode) -> Config {
	return Config {
		repo = "example/tool",
		base_url = r.dir,
		version = "v1.0.0",
		asset = "tool",
		public_key = r.public_key,
		mode = mode,
		state_dir = state,
		exe = exe,
		no_reexec = true,
	}
}

@(test)
notify_reports_an_update_then_rate_limits :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	root, _ := path.temp_dir("selfupdate-")
	defer os.remove_all(root)
	r := make_release(t, root, "tool", "new binary", "v1.1.0")
	exe := exe_file(t, root, "old binary")
	state := path.join(root, "state")

	res := run(config(r, exe, state, .Notify))
	testing.expect_value(t, res.outcome, Outcome.Update_Available)
	testing.expect_value(t, res.version, "v1.1.0")
	testing.expect_value(t, res.message, "update available: v1.1.0")
	old, _ := path.read(exe)
	testing.expect_value(t, old, "old binary")

	res = run(config(r, exe, state, .Notify))
	testing.expect_value(t, res.outcome, Outcome.Skipped)

	// A stamp older than the interval checks again.
	cfg := config(r, exe, state, .Notify)
	cfg.interval = time.Nanosecond
	res = run(cfg)
	testing.expect_value(t, res.outcome, Outcome.Update_Available)
}

@(test)
matching_hash_is_up_to_date :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	root, _ := path.temp_dir("selfupdate-")
	defer os.remove_all(root)
	r := make_release(t, root, "tool", "same binary", "v1.0.0")
	exe := exe_file(t, root, "same binary")
	res := run(config(r, exe, "", .Apply))
	testing.expect_value(t, res.outcome, Outcome.Up_To_Date)
}

@(test)
apply_swaps_the_executable_and_keeps_a_backup :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	root, _ := path.temp_dir("selfupdate-")
	defer os.remove_all(root)
	r := make_release(t, root, "tool", "new binary", "v1.1.0")
	exe := exe_file(t, root, "old binary")

	res := run(config(r, exe, "", .Apply))
	testing.expect_value(t, res.outcome, Outcome.Applied)
	now, _ := path.read(exe)
	testing.expect_value(t, now, "new binary")
	backup, berr := path.read(strings.concatenate({exe, ".old"}))
	testing.expect_value(t, berr, nil)
	testing.expect_value(t, backup, "old binary")
	testing.expect(t, !os.exists(strings.concatenate({exe, ".new"})), "no temp file left")

	// The next run clears the backup and finds itself current.
	res = run(config(r, exe, "", .Apply))
	testing.expect_value(t, res.outcome, Outcome.Up_To_Date)
	testing.expect(t, !os.exists(strings.concatenate({exe, ".old"})), "backup removed")
}

@(test)
a_bad_signature_is_refused :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	root, _ := path.temp_dir("selfupdate-")
	defer os.remove_all(root)
	r := make_release(t, root, "tool", "new binary", "v1.1.0")
	exe := exe_file(t, root, "old binary")

	// Sums rewritten after signing: the hash is right, the signature is not.
	sums, _ := path.read(path.join(r.dir, SUMS_FILE))
	testing.expect_value(t, path.write(path.join(r.dir, SUMS_FILE), strings.concatenate({sums, "# tampered\n"})), nil)
	res := run(config(r, exe, "", .Apply))
	testing.expect_value(t, res.outcome, Outcome.Failed)
	testing.expect(t, strings.contains(res.message, "signature"), res.message)
	still, _ := path.read(exe)
	testing.expect_value(t, still, "old binary")

	// A different key, with a valid signature under it.
	other := make_release(t, path.join(root, "other"), "tool", "new binary", "v1.1.0")
	cfg := config(other, exe, "", .Apply)
	cfg.public_key = r.public_key
	res = run(cfg)
	testing.expect_value(t, res.outcome, Outcome.Failed)
}

@(test)
a_tampered_asset_is_refused :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	root, _ := path.temp_dir("selfupdate-")
	defer os.remove_all(root)
	r := make_release(t, root, "tool", "new binary", "v1.1.0")
	exe := exe_file(t, root, "old binary")
	testing.expect_value(t, path.write(path.join(r.dir, "tool"), "evil binary"), nil)
	res := run(config(r, exe, "", .Apply))
	testing.expect_value(t, res.outcome, Outcome.Failed)
	testing.expect(t, strings.contains(res.message, "hash"), res.message)
	still, _ := path.read(exe)
	testing.expect_value(t, still, "old binary")
	testing.expect(t, !os.exists(strings.concatenate({exe, ".new"})), "no temp file left")
}

@(test)
development_builds_and_missing_assets_are_refused :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	root, _ := path.temp_dir("selfupdate-")
	defer os.remove_all(root)
	r := make_release(t, root, "tool", "new binary", "v1.1.0")
	exe := exe_file(t, root, "old binary")

	cfg := config(r, exe, "", .Apply)
	cfg.version = ""
	res := run(cfg)
	testing.expect_value(t, res.outcome, Outcome.Refused)

	cfg = config(r, exe, "", .Apply)
	cfg.asset = "tool-other"
	res = run(cfg)
	testing.expect_value(t, res.outcome, Outcome.Failed)
	testing.expect(t, strings.contains(res.message, "not in the release"), res.message)
}

@(test)
published_hash_reads_both_sha256sum_forms :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	sums := "AAAA  tool-linux-amd64\nbbbb *tool-windows-amd64.exe\r\n"
	h, ok := published_hash(sums, "tool-linux-amd64")
	testing.expect(t, ok)
	testing.expect_value(t, h, "aaaa")
	h, ok = published_hash(sums, "tool-windows-amd64.exe")
	testing.expect(t, ok)
	testing.expect_value(t, h, "bbbb")
	_, ok = published_hash(sums, "tool")
	testing.expect(t, !ok, "a prefix is not a match")
}
