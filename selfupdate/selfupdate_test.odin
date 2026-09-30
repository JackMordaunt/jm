package selfupdate

import "core:bytes"
import "core:crypto/ed25519"
import "core:crypto/hash"
import "core:encoding/hex"
import "core:os"
import "core:strings"
import "core:testing"
import "core:time"

import "jm:path"
import "jm:zstd"

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

// ---- routes: patch, compressed asset, full download ---------------------

File :: struct {
	name: string,
	body: []byte,
}

// publish writes files beside the asset and signs sums over all of them.
publish :: proc(t: ^testing.T, r: ^Release, asset, body: string, files: ..File) {
	ta := context.temp_allocator
	b := strings.builder_make(ta)
	all := make([dynamic]File, ta)
	append(&all, File{asset, transmute([]byte)body})
	append(&all, ..files)
	for f in all {
		testing.expect_value(t, path.write(path.join(r.dir, f.name, allocator = ta), string(f.body)), nil)
		digest := hash.hash_bytes(.SHA256, f.body, ta)
		strings.write_string(&b, string(hex.encode(digest, ta)))
		strings.write_string(&b, "  ")
		strings.write_string(&b, f.name)
		strings.write_byte(&b, '\n')
	}
	sign_sums(t, r, strings.to_string(b))
}

// binary is a stand-in executable large enough that a patch is small beside
// it: seeded noise, which does not compress on its own.
binary :: proc(n: int, seed: u64) -> string {
	b := make([]byte, n, context.temp_allocator)
	x := seed
	for &c in b {
		x = x * 6364136223846793005 + 1442695040888963407
		c = byte(x >> 56)
	}
	return string(b)
}

// rebuilt is old with a stretch changed in the middle, as the next build is.
rebuilt :: proc(old: string) -> string {
	mid := len(old) / 2
	return strings.concatenate({old[:mid], binary(2000, 77), old[mid + 1000:]}, context.temp_allocator)
}

zst_of :: proc(t: ^testing.T, body: string) -> File {
	buf := make([]byte, zstd.compress_bound(len(body)), context.temp_allocator)
	packed, err := zstd.compress(buf, transmute([]byte)body, {level = 19})
	testing.expect_value(t, err, nil)
	return {"tool" + ZST_EXT, packed}
}

patch_of :: proc(t: ^testing.T, old, new: string, from := "") -> File {
	out: bytes.Buffer
	bytes.buffer_init_allocator(&out, 0, 0, context.temp_allocator)
	testing.expect_value(t, zstd.diff(bytes.buffer_to_stream(&out), transmute([]byte)old, transmute([]byte)new), nil)
	from_hex := from
	if from_hex == "" {
		from_hex = string(hex.encode(hash.hash_string(.SHA256, old, context.temp_allocator), context.temp_allocator))
	}
	name := make([]byte, PATH_CAP, context.temp_allocator)
	return {patch_name(name, "tool", from_hex), bytes.buffer_to_bytes(&out)}
}

// expect_update runs Apply and checks the swap happened by the route expected and
// left no download behind.
expect_update :: proc(t: ^testing.T, r: Release, exe, new: string, via: Via, loc := #caller_location) -> Result {
	res := run(config(r, exe, "", .Apply))
	testing.expect_value(t, res.outcome, Outcome.Applied, loc = loc)
	testing.expect_value(t, res.via, via, loc = loc)
	testing.expect(t, read(exe) == new, "the new binary is installed", loc = loc)
	testing.expect(t, !os.exists(strings.concatenate({exe, ".dl"}, context.temp_allocator)), "no download left", loc = loc)
	testing.expect(t, !os.exists(strings.concatenate({exe, ".new"}, context.temp_allocator)), "no temp file left", loc = loc)
	return res
}

@(test)
apply_prefers_the_patch_from_this_build :: proc(t: ^testing.T) {
	root := temp_root(t)
	defer os.remove_all(root)
	old := binary(200_000, 1)
	new := rebuilt(old)
	r := make_release(t, root, "tool", "placeholder", "v1.1.0")
	p := patch_of(t, old, new)
	testing.expectf(t, len(p.body) < 8000, "patch is %d bytes", len(p.body))
	publish(t, &r, "tool", new, zst_of(t, new), p)
	exe := exe_file(t, root, old)
	res := expect_update(t, r, exe, new, .Patch)
	testing.expect_value(t, message(&res), "updated via patch")
}

@(test)
a_patch_for_another_build_is_not_fetched :: proc(t: ^testing.T) {
	root := temp_root(t)
	defer os.remove_all(root)
	old := binary(100_000, 2)
	new := rebuilt(old)
	r := make_release(t, root, "tool", "placeholder", "v1.1.0")
	other := binary(100_000, 3)
	publish(t, &r, "tool", new, zst_of(t, new), patch_of(t, other, new))
	exe := exe_file(t, root, old)
	res := expect_update(t, r, exe, new, .Compressed)
	testing.expect_value(t, message(&res), "updated via compressed asset")
}

@(test)
a_tampered_patch_is_never_decoded :: proc(t: ^testing.T) {
	root := temp_root(t)
	defer os.remove_all(root)
	old := binary(100_000, 4)
	new := rebuilt(old)
	r := make_release(t, root, "tool", "placeholder", "v1.1.0")
	p := patch_of(t, old, new)
	publish(t, &r, "tool", new, zst_of(t, new), p)
	// Rewritten after signing: zstd must not be handed it.
	testing.expect_value(t, path.write(path.join(r.dir, p.name, allocator = context.temp_allocator), "not a patch"), nil)
	exe := exe_file(t, root, old)
	res := expect_update(t, r, exe, new, .Compressed)
	testing.expect_value(t, message(&res), "updated via compressed asset (patch: does not match its published hash)")
}

@(test)
a_signed_patch_that_does_not_decode_falls_back :: proc(t: ^testing.T) {
	root := temp_root(t)
	defer os.remove_all(root)
	old := binary(100_000, 5)
	new := rebuilt(old)
	r := make_release(t, root, "tool", "placeholder", "v1.1.0")
	p := patch_of(t, old, new)
	p.body = transmute([]byte)binary(len(p.body), 6)
	publish(t, &r, "tool", new, zst_of(t, new), p)
	exe := exe_file(t, root, old)
	res := expect_update(t, r, exe, new, .Compressed)
	testing.expect_value(t, message(&res), "updated via compressed asset (patch: does not decode)")
}

@(test)
a_patch_to_the_wrong_binary_falls_back :: proc(t: ^testing.T) {
	root := temp_root(t)
	defer os.remove_all(root)
	old := binary(100_000, 7)
	new := rebuilt(old)
	r := make_release(t, root, "tool", "placeholder", "v1.1.0")
	// Signed and decodable, but to something other than the asset.
	p := patch_of(t, old, rebuilt(new))
	publish(t, &r, "tool", new, p)
	exe := exe_file(t, root, old)
	res := expect_update(t, r, exe, new, .Full)
	testing.expect_value(t, message(&res), "updated via full download (patch: decodes to the wrong binary)")
}

@(test)
a_damaged_compressed_asset_falls_back_to_the_full_one :: proc(t: ^testing.T) {
	root := temp_root(t)
	defer os.remove_all(root)
	new := binary(50_000, 8)
	r := make_release(t, root, "tool", "placeholder", "v1.1.0")
	zst := zst_of(t, new)
	zst.body = zst.body[:len(zst.body) / 2]
	publish(t, &r, "tool", new, zst)
	exe := exe_file(t, root, "old binary")
	res := expect_update(t, r, exe, new, .Full)
	testing.expect_value(t, message(&res), "updated via full download (compressed asset: does not decode)")
}

@(test)
every_route_failing_leaves_the_executable :: proc(t: ^testing.T) {
	root := temp_root(t)
	defer os.remove_all(root)
	old := binary(50_000, 9)
	new := rebuilt(old)
	r := make_release(t, root, "tool", "placeholder", "v1.1.0")
	publish(t, &r, "tool", new, zst_of(t, new), patch_of(t, old, new))
	for name in ([]string{"tool", "tool" + ZST_EXT, patch_of(t, old, new).name}) {
		testing.expect_value(t, os.remove(path.join(r.dir, name, allocator = context.temp_allocator)), nil)
	}
	exe := exe_file(t, root, old)
	res := run(config(r, exe, "", .Apply))
	testing.expect_value(t, res.outcome, Outcome.Failed)
	testing.expect_value(t, message(&res), "cannot update tool: download failed")
	testing.expect(t, read(exe) == old, "the old binary stays")
}
