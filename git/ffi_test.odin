package git

import "core:testing"

// The structs in ffi.odin are passed to libgit2 by pointer, so their
// layout has to be the C one exactly. These sizes and offsets are what a
// C program printed against libgit2 1.9.7's headers on x86-64 Linux, the
// one ABI checked. Nothing in them is platform-sized but pointers and
// size_t, so the other 64-bit targets are expected to agree; when one is
// first built, print the same numbers there and widen this test.
@(test)
struct_layout_matches_libgit2 :: proc(t: ^testing.T) {
	testing.expect_value(t, size_of(git_oid), 20)
	testing.expect_value(t, size_of(git_strarray), 16)
	testing.expect_value(t, size_of(git_error), 16)
	testing.expect_value(t, size_of(git_signature), 32)
	testing.expect_value(t, size_of(git_time), 16)
	testing.expect_value(t, size_of(git_buf), 24)
	testing.expect_value(t, size_of(git_status_options), 48)
	testing.expect_value(t, offset_of(git_status_options, pathspec), 16)
	testing.expect_value(t, offset_of(git_status_options, baseline), 32)
	testing.expect_value(t, offset_of(git_status_options, rename_threshold), 40)
	testing.expect_value(t, size_of(git_status_entry), 24)
	testing.expect_value(t, size_of(git_diff_file), 48)
	testing.expect_value(t, offset_of(git_diff_file, path), 24)
	testing.expect_value(t, offset_of(git_diff_file, flags), 40)
	testing.expect_value(t, offset_of(git_diff_file, mode), 44)
	testing.expect_value(t, size_of(git_diff_delta), 112)
	testing.expect_value(t, size_of(git_diff_options), 96)
	testing.expect_value(t, offset_of(git_diff_options, payload), 48)
	testing.expect_value(t, offset_of(git_diff_options, context_lines), 56)
	testing.expect_value(t, offset_of(git_diff_options, oid_type), 64)
	testing.expect_value(t, offset_of(git_diff_options, id_abbrev), 68)
	testing.expect_value(t, offset_of(git_diff_options, max_size), 72)
	testing.expect_value(t, offset_of(git_diff_options, old_prefix), 80)
	testing.expect_value(t, size_of(git_proxy_options), 40)
	testing.expect_value(t, size_of(git_remote_callbacks), 128)
	testing.expect_value(t, offset_of(git_remote_callbacks, credentials), 24)
	testing.expect_value(t, offset_of(git_remote_callbacks, payload), 104)
	testing.expect_value(t, offset_of(git_remote_callbacks, resolve_url), 112)
	testing.expect_value(t, size_of(git_fetch_options), 216)
	testing.expect_value(t, offset_of(git_fetch_options, prune), 136)
	testing.expect_value(t, offset_of(git_fetch_options, update_fetchhead), 140)
	testing.expect_value(t, offset_of(git_fetch_options, download_tags), 144)
	testing.expect_value(t, offset_of(git_fetch_options, proxy_opts), 152)
	testing.expect_value(t, offset_of(git_fetch_options, depth), 192)
	testing.expect_value(t, offset_of(git_fetch_options, follow_redirects), 196)
	testing.expect_value(t, offset_of(git_fetch_options, custom_headers), 200)
	testing.expect_value(t, size_of(git_push_options), 216)
	testing.expect_value(t, offset_of(git_push_options, callbacks), 8)
	testing.expect_value(t, offset_of(git_push_options, proxy_opts), 136)
	testing.expect_value(t, offset_of(git_push_options, follow_redirects), 176)
	testing.expect_value(t, offset_of(git_push_options, custom_headers), 184)
	testing.expect_value(t, offset_of(git_push_options, remote_push_options), 200)
}
