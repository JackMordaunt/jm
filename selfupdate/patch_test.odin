package selfupdate

import "core:hash"
import "core:testing"

// A patch reproduces new from old exactly, however the two relate.
@(test)
patch_round_trips :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	old := random_bytes(50_000, 1)
	// new: old with a chunk deleted, a chunk inserted, a chunk moved and
	// a few bytes retouched, the way a rebuilt binary differs.
	new := make([dynamic]byte)
	append(&new, ..old[:10_000])
	append(&new, ..random_bytes(3_000, 2))
	append(&new, ..old[12_000:30_000])
	append(&new, ..old[40_000:])
	append(&new, ..old[30_000:40_000])
	new[20_000] ~= 0xff
	new[20_050] ~= 0xff
	p := diff(old, new[:])
	testing.expect(t, len(p) < len(new) / 4, "a mostly shared file patches small")
	got, ok := apply(old, p)
	testing.expect(t, ok, "applies")
	testing.expect(t, string(got) == string(new[:]), "reproduces new")

	// Degenerate pairs.
	for pair in ([][2][]byte{{old, old}, {{}, old[:100]}, {old[:100], {}}, {old[:5], old[:7]}}) {
		p = diff(pair[0], pair[1])
		got, ok = apply(pair[0], p)
		testing.expect(t, ok && string(got) == string(pair[1]), "degenerate pair round trips")
	}
	same := diff(old, old)
	testing.expect(t, len(same) < 64, "identical files patch to a header and one copy")
}

@(test)
patch_refuses_what_does_not_fit :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	old := random_bytes(4_000, 3)
	new := random_bytes(4_000, 4)
	copy(new[1000:], old[500:2500])
	p := diff(old, new)
	_, ok := apply(old, p)
	testing.expect(t, ok, "the real pair applies")
	_, ok = apply(old[:3_999], p)
	testing.expect(t, !ok, "another old file is refused")
	_, ok = apply(old, p[:len(p) - 1])
	testing.expect(t, !ok, "a truncated patch is refused")
	bent := make([]byte, len(p))
	copy(bent, p)
	bent[len(bent) - 1] ~= 1
	_, ok = apply(old, bent)
	testing.expect(t, !ok, "a corrupted patch fails the result hash")
	_, ok = apply(old, {})
	testing.expect(t, !ok, "an empty patch is refused")
	_, ok = apply(old, transmute([]byte)string("JMP1\x05"))
	testing.expect(t, !ok, "a header alone is refused")
}

// The zlib-wrapped form, built here as one stored block since the test
// has no deflater: zlib header, a final stored block, the Adler-32.
@(test)
patch_applies_the_zlib_wrapped_form :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	old := random_bytes(2_000, 5)
	new := random_bytes(2_000, 6)
	copy(new[200:], old[100:1500])
	raw := diff(old, new)
	wrapped := make([dynamic]byte)
	append(&wrapped, PATCH_MAGIC_Z)
	append(&wrapped, 0x78, 0x01)
	append(&wrapped, 0x01)
	n := u16(len(raw))
	append(&wrapped, byte(n), byte(n >> 8), byte(~n), byte(~n >> 8))
	append(&wrapped, ..raw)
	a := hash.adler32(raw)
	append(&wrapped, byte(a >> 24), byte(a >> 16), byte(a >> 8), byte(a))
	got, ok := apply(old, wrapped[:])
	testing.expect(t, ok, "the wrapped patch applies")
	testing.expect(t, string(got) == string(new), "and reproduces new")
	_, ok = apply(old, wrapped[:len(wrapped) - 3])
	testing.expect(t, !ok, "a truncated stream is refused")
}

@(test)
patch_name_is_asset_hash_prefix_and_suffix :: proc(t: ^testing.T) {
	buf: [128]byte
	name := patch_name(buf[:], "tool-linux-amd64", "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")
	testing.expect_value(t, name, "tool-linux-amd64.0123456789abcdef.patch")
	testing.expect_value(t, patch_name(buf[:], "tool", "short"), "")
	small: [8]byte
	testing.expect_value(t, patch_name(small[:], "tool", "0123456789abcdef0123456789abcdef"), "")
}

// random_bytes is n bytes from a small generator seeded here, so the
// tests see the same data every run.
random_bytes :: proc(n: int, seed: u64) -> []byte {
	state := seed * 0x9E3779B97F4A7C15 + 1
	out := make([]byte, n)
	for i in 0 ..< n {
		state ~= state << 13
		state ~= state >> 7
		state ~= state << 17
		out[i] = byte(state >> 24)
	}
	return out
}
