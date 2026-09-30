package main

import "core:crypto/ed25519"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import "jm:path"
import "jm:selfupdate"

// The seam: files mkpatch writes, published as CI publishes them, must be
// what selfupdate.run takes its cheapest route with.

noise :: proc(n: int, seed: u64) -> []byte {
	b := make([]byte, n, context.temp_allocator)
	x := seed
	for &c in b {
		x = x * 6364136223846793005 + 1442695040888963407
		c = byte(x >> 56)
	}
	return b
}

// release lays out a signed release in dir from the files in it, as the
// publish job does: sha256sum over everything, then the signature.
release :: proc(t: ^testing.T, dir: string, priv: ^ed25519.Private_Key) {
	ta := context.temp_allocator
	entries, err := os.read_all_directory_by_path(dir, ta)
	testing.expect_value(t, err, nil)
	b := strings.builder_make(ta)
	for e in entries {
		data, rerr := os.read_entire_file(e.fullpath, ta)
		testing.expect_value(t, rerr, nil)
		strings.write_string(&b, sha256_hex(data))
		strings.write_string(&b, "  ")
		strings.write_string(&b, e.name)
		strings.write_byte(&b, '\n')
	}
	sums := strings.to_string(b)
	sig: [ed25519.SIGNATURE_SIZE]byte
	ed25519.sign(priv, transmute([]byte)sums, sig[:])
	testing.expect_value(t, os.write_entire_file(path.join(dir, selfupdate.SUMS_FILE, allocator = ta), sums), nil)
	testing.expect_value(t, os.write_entire_file(path.join(dir, selfupdate.SIG_FILE, allocator = ta), sig[:]), nil)
}

@(test)
selfupdate_applies_what_mkpatch_makes :: proc(t: ^testing.T) {
	ta := context.temp_allocator
	root, err := path.temp_dir("mkpatch-", ta)
	testing.expect_value(t, err, nil)
	defer os.remove_all(root)

	old := noise(300_000, 1)
	new := make([]byte, len(old), ta)
	copy(new, old)
	copy(new[len(new) / 2:], noise(3000, 2))
	older := noise(300_000, 3)

	dist := path.join(root, "dist", allocator = ta)
	new_path := path.join(dist, "tool", allocator = ta)
	old_path := path.join(root, "old", allocator = ta)
	older_path := path.join(root, "older", allocator = ta)
	testing.expect_value(t, os.make_directory_all(dist), nil)
	testing.expect_value(t, os.write_entire_file(new_path, new), nil)
	testing.expect_value(t, os.write_entire_file(old_path, old), nil)
	testing.expect_value(t, os.write_entire_file(older_path, older), nil)

	testing.expect(t, make_files(new_path, {old_path, older_path}, dist), "mkpatch succeeds")
	entries, _ := os.read_all_directory_by_path(dist, ta)
	names := make([dynamic]string, ta)
	for e in entries {
		append(&names, e.name)
	}
	// An unrelated older build's patch would be as large as the asset.
	testing.expectf(t, len(names) == 3, "tool, tool.zst and one patch: %v", names)

	priv: ed25519.Private_Key
	testing.expect(t, ed25519.private_key_generate(&priv), "key generation")
	public_key: [ed25519.PUBLIC_KEY_SIZE]byte
	ed25519.private_key_public_bytes(&priv, public_key[:])
	release(t, dist, &priv)

	exe := path.join(root, "bin", "tool", allocator = ta)
	testing.expect_value(t, os.make_directory_all(filepath.dir(exe)), nil)
	testing.expect_value(t, os.write_entire_file(exe, old), nil)
	res := selfupdate.run(
		{
			base_url = dist,
			version = "v1.0.0",
			asset = "tool",
			public_key = public_key[:],
			mode = .Apply,
			exe = exe,
			no_reexec = true,
		},
	)
	testing.expect_value(t, res.outcome, selfupdate.Outcome.Applied)
	testing.expect_value(t, res.via, selfupdate.Via.Patch)
	got, _ := os.read_entire_file(exe, ta)
	testing.expect(t, string(got) == string(new), "the new build is installed")
}
