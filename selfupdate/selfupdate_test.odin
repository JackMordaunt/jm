package selfupdate

import "core:crypto/ed25519"
import "core:crypto/hash"
import "core:encoding/hex"
import "core:os"
import "core:strings"
import "core:testing"
import "core:time"

import "jm:path"

// The tests run `run` under the runner's tracking allocator on purpose: a
// leak in the package fails the test. The helpers' own scratch goes on the
// temp allocator.

// Release is a fake release on disk, signed with a throwaway key.
Release :: struct {
	dir:        string,
	public_key: []byte,
	priv:       ed25519.Private_Key,
}

make_release :: proc(t: ^testing.T, root: string, asset, body, version: string) -> (r: Release) {
	ta := context.temp_allocator
	r.dir = path.join(root, "release", allocator = ta)
	testing.expect_value(t, path.mkdirs(r.dir), nil)
	testing.expect(t, ed25519.private_key_generate(&r.priv), "key generation")
	r.public_key = make([]byte, ed25519.PUBLIC_KEY_SIZE, ta)
	ed25519.private_key_public_bytes(&r.priv, r.public_key)
	write_asset(t, &r, asset, body)
	testing.expect_value(t, path.write(path.join(r.dir, VERSION_FILE, allocator = ta), strings.concatenate({version, "\n"}, ta)), nil)
	return r
}

// write_asset writes the asset and re-signs the sums, in sha256sum's
// Windows form with the binary marker, which the parser must accept.
write_asset :: proc(t: ^testing.T, r: ^Release, asset, body: string) {
	ta := context.temp_allocator
	testing.expect_value(t, path.write(path.join(r.dir, asset, allocator = ta), body), nil)
	digest := hash.hash_string(.SHA256, body, ta)
	sums := strings.concatenate({string(hex.encode(digest, ta)), " *", asset, "\n"}, ta)
	sign_sums(t, r, sums)
}

sign_sums :: proc(t: ^testing.T, r: ^Release, sums: string) {
	ta := context.temp_allocator
	testing.expect_value(t, path.write(path.join(r.dir, SUMS_FILE, allocator = ta), sums), nil)
	sig: [ed25519.SIGNATURE_SIZE]byte
	ed25519.sign(&r.priv, transmute([]byte)sums, sig[:])
	testing.expect_value(t, path.write(path.join(r.dir, SIG_FILE, allocator = ta), string(sig[:])), nil)
}

// exe_file is a stand-in executable with known content.
exe_file :: proc(t: ^testing.T, root, body: string) -> string {
	p := path.join(root, "tool", allocator = context.temp_allocator)
	testing.expect_value(t, path.write(p, body), nil)
	return p
}

config :: proc(r: Release, exe, state: string, mode: Mode) -> Config {
	return Config {
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

temp_root :: proc(t: ^testing.T) -> string {
	root, err := path.temp_dir("selfupdate-", context.temp_allocator)
	testing.expect_value(t, err, nil)
	return root
}

read :: proc(p: string) -> string {
	s, _ := path.read(p, context.temp_allocator)
	return s
}

@(test)
notify_reports_an_update_then_rate_limits :: proc(t: ^testing.T) {
	root := temp_root(t)
	defer os.remove_all(root)
	r := make_release(t, root, "tool", "new binary", "v1.1.0")
	exe := exe_file(t, root, "old binary")
	state := path.join(root, "state", allocator = context.temp_allocator)

	res := run(config(r, exe, state, .Notify))
	testing.expect_value(t, res.outcome, Outcome.Update_Available)
	testing.expect_value(t, version(&res), "v1.1.0")
	testing.expect_value(t, message(&res), "update available: v1.1.0")
	testing.expect_value(t, read(exe), "old binary")

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
	root := temp_root(t)
	defer os.remove_all(root)
	r := make_release(t, root, "tool", "same binary", "v1.0.0")
	exe := exe_file(t, root, "same binary")
	res := run(config(r, exe, "", .Apply))
	testing.expect_value(t, res.outcome, Outcome.Up_To_Date)
}

@(test)
apply_swaps_the_executable_and_keeps_a_backup :: proc(t: ^testing.T) {
	root := temp_root(t)
	defer os.remove_all(root)
	r := make_release(t, root, "tool", "new binary", "v1.1.0")
	exe := exe_file(t, root, "old binary")
	old := strings.concatenate({exe, ".old"}, context.temp_allocator)
	fresh := strings.concatenate({exe, ".new"}, context.temp_allocator)

	res := run(config(r, exe, "", .Apply))
	testing.expect_value(t, res.outcome, Outcome.Applied)
	testing.expect_value(t, read(exe), "new binary")
	testing.expect_value(t, read(old), "old binary")
	testing.expect(t, !os.exists(fresh), "no temp file left")

	// The next run clears the backup and finds itself current.
	res = run(config(r, exe, "", .Apply))
	testing.expect_value(t, res.outcome, Outcome.Up_To_Date)
	testing.expect(t, !os.exists(old), "backup removed")
}

@(test)
a_bad_signature_is_refused :: proc(t: ^testing.T) {
	root := temp_root(t)
	defer os.remove_all(root)
	r := make_release(t, root, "tool", "new binary", "v1.1.0")
	exe := exe_file(t, root, "old binary")

	// Sums rewritten after signing: the hash is right, the signature is not.
	sums_path := path.join(r.dir, SUMS_FILE, allocator = context.temp_allocator)
	sums := read(sums_path)
	testing.expect_value(t, path.write(sums_path, strings.concatenate({sums, "# tampered\n"}, context.temp_allocator)), nil)
	res := run(config(r, exe, "", .Apply))
	testing.expect_value(t, res.outcome, Outcome.Failed)
	testing.expect(t, strings.contains(message(&res), "signature"), message(&res))
	testing.expect_value(t, read(exe), "old binary")

	// A different key, with a valid signature under it.
	other := make_release(t, path.join(root, "other", allocator = context.temp_allocator), "tool", "new binary", "v1.1.0")
	cfg := config(other, exe, "", .Apply)
	cfg.public_key = r.public_key
	res = run(cfg)
	testing.expect_value(t, res.outcome, Outcome.Failed)
}

@(test)
a_tampered_asset_is_refused :: proc(t: ^testing.T) {
	root := temp_root(t)
	defer os.remove_all(root)
	r := make_release(t, root, "tool", "new binary", "v1.1.0")
	exe := exe_file(t, root, "old binary")
	testing.expect_value(t, path.write(path.join(r.dir, "tool", allocator = context.temp_allocator), "evil binary"), nil)
	res := run(config(r, exe, "", .Apply))
	testing.expect_value(t, res.outcome, Outcome.Failed)
	testing.expect(t, strings.contains(message(&res), "hash"), message(&res))
	testing.expect_value(t, read(exe), "old binary")
	testing.expect(t, !os.exists(strings.concatenate({exe, ".new"}, context.temp_allocator)), "no temp file left")
}

@(test)
development_builds_and_missing_assets_are_refused :: proc(t: ^testing.T) {
	root := temp_root(t)
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
	testing.expect(t, strings.contains(message(&res), "not in the release"), message(&res))
}

@(test)
an_oversized_checksum_file_is_refused_not_grown :: proc(t: ^testing.T) {
	root := temp_root(t)
	defer os.remove_all(root)
	r := make_release(t, root, "tool", "new binary", "v1.1.0")
	exe := exe_file(t, root, "old binary")
	big := strings.repeat("x", SUMS_CAP + 1, context.temp_allocator)
	sign_sums(t, &r, big)
	res := run(config(r, exe, "", .Apply))
	testing.expect_value(t, res.outcome, Outcome.Failed)
	testing.expect(t, strings.contains(message(&res), "cannot fetch"), message(&res))
}

@(test)
published_hash_reads_both_sha256sum_forms :: proc(t: ^testing.T) {
	sums := "aaaa  tool-linux-amd64\nbbbb *tool-windows-amd64.exe\r\n"
	h, ok := published_hash_lookup(sums, "tool-linux-amd64")
	testing.expect(t, ok)
	testing.expect_value(t, h, "aaaa")
	h, ok = published_hash_lookup(sums, "tool-windows-amd64.exe")
	testing.expect(t, ok)
	testing.expect_value(t, h, "bbbb")
	_, ok = published_hash_lookup(sums, "tool")
	testing.expect(t, !ok, "a prefix is not a match")
}

@(test)
key_from_hex_fills_a_caller_buffer :: proc(t: ^testing.T) {
	key: [32]byte
	testing.expect(t, key_from_hex(strings.concatenate({"00ff", strings.repeat("ab", 30, context.temp_allocator)}, context.temp_allocator), key[:]))
	testing.expect_value(t, key[0], 0x00)
	testing.expect_value(t, key[1], 0xff)
	testing.expect_value(t, key[31], 0xab)
	testing.expect(t, !key_from_hex("zz", key[:]), "wrong length")
}
