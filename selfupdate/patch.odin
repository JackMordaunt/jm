package selfupdate

import "core:bytes"
import "core:compress/zlib"
import "core:crypto/sha2"
import "core:mem"

// A patch turns the binary a machine has into the one a release
// published, so an update downloads what changed rather than the whole
// file. The format is brain's own, so the same code writes it in CI and
// reads it here, with no decoder to link:
//
//	"JMP1"                 magic
//	uvarint old_len        the file the patch applies to
//	uvarint new_len        the file it produces
//	32 bytes               SHA-256 of the result
//	ops until new_len:
//	  uvarint n<<1 | 0     ADD: the next n bytes verbatim
//	  uvarint n<<1 | 1     COPY: n bytes of old, from
//	  uvarint offset         this offset
//
// diff finds the copies with a rolling hash over WINDOW bytes of old,
// indexed every STEP bytes, each hit extended both ways and kept from
// MIN_MATCH bytes. The ops themselves are not entropy coded; a release
// wraps the whole patch in a zlib stream behind a second magic,
//
//	"JMPZ" zlib(JMP1 patch)
//
// which apply inflates with core:compress/zlib before reading the ops.
// Measured 2026-10-01 on brainfold's dev-2026-09 and dev-2026-09-2
// linux-amd64 builds (2.38 MB each) with tools/patch: the raw patch was
// 24% of the new file and the zlib-wrapped one 10%, against 6% from
// `zstd --patch-from` on the same pair. The compression stage is written
// by the release workflow, which has a deflater; Odin's core has only the
// inflater, which is all a client needs.

PATCH_MAGIC :: "JMP1"
PATCH_MAGIC_Z :: "JMPZ"
PATCH_WINDOW :: 24
PATCH_STEP :: 4
PATCH_MIN_MATCH :: 20
PATCH_MUL :: 0x100000001b3 // the rolling hash multiplier, any odd one works

// patch_name is how a release names the patch from one build to the
// asset: the asset's name, the first PATCH_HASH_LEN hex digits of the
// old file's SHA-256, and .patch.
PATCH_HASH_LEN :: 16

// diff writes a patch from old to new into a new buffer from allocator.
diff :: proc(old, new: []byte, allocator := context.allocator) -> []byte {
	out := make([dynamic]byte, 0, len(new) / 4 + 64, allocator)
	append(&out, PATCH_MAGIC)
	put_uvarint(&out, u64(len(old)))
	put_uvarint(&out, u64(len(new)))
	digest: [sha2.DIGEST_SIZE_256]byte
	sha_bytes(new, digest[:])
	append(&out, ..digest[:])

	// Index old: the rolling hash of each STEP-aligned window, to its
	// first offset. A 64-bit hash makes a false hit rare; memcmp settles it.
	index := make(map[u64]i32, max(16, len(old) / PATCH_STEP), context.temp_allocator)
	defer delete(index)
	if len(old) >= PATCH_WINDOW {
		for i := 0; i + PATCH_WINDOW <= len(old); i += PATCH_STEP {
			h := window_hash(old[i:i + PATCH_WINDOW])
			if _, taken := index[h]; !taken {
				index[h] = i32(i)
			}
		}
	}
	// The power that rolls the oldest byte out.
	pow: u64 = 1
	for _ in 1 ..< PATCH_WINDOW {
		pow *= PATCH_MUL
	}

	lit := 0 // start of the pending literal run
	p := 0
	h: u64
	fresh := true
	for p + PATCH_WINDOW <= len(new) {
		if fresh {
			h = window_hash(new[p:p + PATCH_WINDOW])
			fresh = false
		}
		if o32, hit := index[h]; hit {
			o := int(o32)
			if mem.compare(old[o:o + PATCH_WINDOW], new[p:p + PATCH_WINDOW]) == 0 {
				// Extend forward, then back into the literal run.
				n := PATCH_WINDOW
				for o + n < len(old) && p + n < len(new) && old[o + n] == new[p + n] {
					n += 1
				}
				for o > 0 && p > lit && old[o - 1] == new[p - 1] {
					o -= 1
					p -= 1
					n += 1
				}
				if n >= PATCH_MIN_MATCH {
					put_add(&out, new[lit:p])
					put_uvarint(&out, u64(n) << 1 | 1)
					put_uvarint(&out, u64(o))
					p += n
					lit = p
					fresh = true
					continue
				}
				// Too short to pay for itself: undo the backward step.
				p = max(p, lit)
			}
		}
		// Roll one byte: drop new[p], take new[p+WINDOW].
		if p + PATCH_WINDOW < len(new) {
			h = (h - u64(new[p]) * pow) * PATCH_MUL + u64(new[p + PATCH_WINDOW])
		}
		p += 1
	}
	put_add(&out, new[lit:])
	return out[:]
}

// apply produces new from old and a patch, raw or zlib-wrapped, or
// reports that the patch is malformed, for another file, or yields a
// result that fails its own hash.
apply :: proc(old, patch: []byte, allocator := context.allocator) -> (new: []byte, ok: bool) {
	r := patch
	if len(r) >= len(PATCH_MAGIC_Z) && string(r[:len(PATCH_MAGIC_Z)]) == PATCH_MAGIC_Z {
		buf: bytes.Buffer
		buf.buf = make([dynamic]byte, 0, len(old) + len(patch), allocator)
		defer bytes.buffer_destroy(&buf)
		if zlib.inflate(r[len(PATCH_MAGIC_Z):], &buf) != nil {
			return
		}
		return apply(old, bytes.buffer_to_bytes(&buf), allocator)
	}
	if len(r) < len(PATCH_MAGIC) || string(r[:len(PATCH_MAGIC)]) != PATCH_MAGIC {
		return
	}
	r = r[len(PATCH_MAGIC):]
	old_len, ok1 := get_uvarint(&r)
	new_len, ok2 := get_uvarint(&r)
	if !ok1 || !ok2 || old_len != u64(len(old)) || new_len > 1 << 32 || len(r) < sha2.DIGEST_SIZE_256 {
		return
	}
	want := r[:sha2.DIGEST_SIZE_256]
	r = r[sha2.DIGEST_SIZE_256:]
	out := make([]byte, int(new_len), allocator)
	n := 0
	for n < int(new_len) {
		tag, tok := get_uvarint(&r)
		if !tok {
			delete(out, allocator)
			return nil, false
		}
		count := int(tag >> 1)
		if count < 0 || n + count > int(new_len) {
			delete(out, allocator)
			return nil, false
		}
		if tag & 1 == 0 {
			if len(r) < count {
				delete(out, allocator)
				return nil, false
			}
			copy(out[n:], r[:count])
			r = r[count:]
		} else {
			off, ook := get_uvarint(&r)
			if !ook || off > u64(len(old)) || int(off) + count > len(old) {
				delete(out, allocator)
				return nil, false
			}
			copy(out[n:], old[int(off):int(off) + count])
		}
		n += count
	}
	if len(r) != 0 {
		delete(out, allocator)
		return nil, false
	}
	digest: [sha2.DIGEST_SIZE_256]byte
	sha_bytes(out, digest[:])
	if mem.compare(digest[:], want) != 0 {
		delete(out, allocator)
		return nil, false
	}
	return out, true
}

// patch_name writes `<asset>.<hash16>.patch` into dst and returns it;
// have_hex is the old file's full hex SHA-256.
patch_name :: proc(dst: []byte, asset, have_hex: string) -> string {
	if len(have_hex) < PATCH_HASH_LEN {
		return ""
	}
	n := copy(dst, asset)
	n += copy(dst[n:], ".")
	n += copy(dst[n:], have_hex[:PATCH_HASH_LEN])
	n += copy(dst[n:], ".patch")
	if n >= len(dst) {
		return ""
	}
	return string(dst[:n])
}

// ---- internals ----------------------------------------------------------

window_hash :: proc(w: []byte) -> u64 {
	h: u64
	for b in w {
		h = h * PATCH_MUL + u64(b)
	}
	return h
}

put_add :: proc(out: ^[dynamic]byte, lit: []byte) {
	if len(lit) == 0 {
		return
	}
	put_uvarint(out, u64(len(lit)) << 1)
	append(out, ..lit)
}

put_uvarint :: proc(out: ^[dynamic]byte, v: u64) {
	v := v
	for v >= 0x80 {
		append(out, byte(v) | 0x80)
		v >>= 7
	}
	append(out, byte(v))
}

get_uvarint :: proc(r: ^[]byte) -> (v: u64, ok: bool) {
	shift: uint
	for i in 0 ..< len(r) {
		b := r[i]
		if shift > 63 {
			return 0, false
		}
		v |= u64(b & 0x7f) << shift
		if b < 0x80 {
			r^ = r[i + 1:]
			return v, true
		}
		shift += 7
	}
	return 0, false
}

sha_bytes :: proc(data: []byte, dst: []byte) {
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	sha2.update(&ctx, data)
	sha2.final(&ctx, dst)
}
