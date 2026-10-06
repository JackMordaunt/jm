/*
The raw C API: the subset of libgit2 the wrapper needs, under the C names,
exported so a caller that needs an interface the wrapper does not cover can
reach for it. The wrapper in git.odin is what programs should use. The
declarations were taken from the libgit2 1.9.7 headers; every struct here
is laid out exactly as those headers lay it out on a 64-bit target, and
ffi_test.odin pins the sizes and offsets so a header change is caught
before it corrupts a stack.

Linking: `just libgit2` fetches libgit2 and builds a static archive into
git/lib, the way `just blend2d` builds Blend2D, and this file links it
when it is there. Without it the system libgit2 is linked instead, so a
machine with the distribution's package builds and tests without the CMake
step, and `odin check` (which opens no library) type-checks every target
either way. A shipped binary is built with the static library: the app
then needs no git and no libgit2 on the machine it runs on.
*/
package git

import "core:c"

when ODIN_OS == .Windows {
	when #exists("lib/git2.lib") {
		@(extra_linker_flags = "winhttp.lib rpcrt4.lib crypt32.lib ole32.lib ws2_32.lib secur32.lib advapi32.lib")
		foreign import lib "lib/git2.lib"
	} else {
		foreign import lib "system:git2.lib"
	}
} else when ODIN_OS == .Darwin {
	when #exists("lib/libgit2.a") {
		// zlib is a library here, not a -lz flag, so it is linked once in a
		// program that also links vendor:curl, whose foreign import lists
		// "system:z" too. ignore_duplicates makes Odin's linker step skip a
		// library already on the line (src/linker.cpp, dev-2026-09);
		// tools/jm-fuzz, which links both, shows one -lz and no ld warning.
		@(extra_linker_flags = "-framework Security -framework CoreFoundation -liconv")
		@(ignore_duplicates)
		foreign import lib {"lib/libgit2.a", "system:z"}
	} else {
		foreign import lib "system:git2"
	}
} else {
	when #exists("lib/libgit2.a") {
		// -ldl for the OpenSSL-Dynamic HTTPS backend, which loads the
		// distribution's libssl at run time rather than linking it.
		@(extra_linker_flags = "-lpthread -ldl -lm")
		foreign import lib "lib/libgit2.a"
	} else {
		foreign import lib "system:git2"
	}
}

// Opaque handles. libgit2 owns each; the matching *_free releases it.
git_repository :: struct {}
git_reference :: struct {}
git_index :: struct {}
git_tree :: struct {}
git_commit :: struct {}
git_object :: struct {}
git_revwalk :: struct {}
git_status_list :: struct {}
git_remote :: struct {}
git_annotated_commit :: struct {}
git_diff :: struct {}
git_credential :: struct {}

GIT_OID_SHA1_SIZE :: 20

git_oid :: struct {
	id: [GIT_OID_SHA1_SIZE]u8,
}

git_strarray :: struct {
	strings: [^]cstring,
	count:   c.size_t,
}

git_error :: struct {
	message: cstring,
	klass:   c.int,
}

git_time :: struct {
	time:   i64,
	offset: c.int,
	sign:   c.char,
}

git_signature :: struct {
	name:  cstring,
	email: cstring,
	at:    git_time, // the header's `when`, an Odin keyword
}

git_buf :: struct {
	ptr:      [^]u8,
	reserved: c.size_t,
	size:     c.size_t,
}

git_status_options :: struct {
	version:          c.uint,
	show:             c.int,
	flags:            c.uint,
	pathspec:         git_strarray,
	baseline:         ^git_tree,
	rename_threshold: u16,
}

git_status_entry :: struct {
	status:           c.uint,
	head_to_index:    ^git_diff_delta,
	index_to_workdir: ^git_diff_delta,
}

git_diff_file :: struct {
	id:        git_oid,
	path:      cstring,
	size:      u64,
	flags:     u32,
	mode:      u16,
	id_abbrev: u16,
}

git_diff_delta :: struct {
	status:     c.int,
	flags:      u32,
	similarity: u16,
	nfiles:     u16,
	old_file:   git_diff_file,
	new_file:   git_diff_file,
}

git_diff_options :: struct {
	version:           c.uint,
	flags:             u32,
	ignore_submodules: c.int,
	pathspec:          git_strarray,
	notify_cb:         rawptr,
	progress_cb:       rawptr,
	payload:           rawptr,
	context_lines:     u32,
	interhunk_lines:   u32,
	oid_type:          c.int,
	id_abbrev:         u16,
	max_size:          i64,
	old_prefix:        cstring,
	new_prefix:        cstring,
}

git_credential_acquire_cb :: #type proc "c" (out: ^^git_credential, url, username_from_url: cstring, allowed_types: c.uint, payload: rawptr) -> c.int

git_proxy_options :: struct {
	version:           c.uint,
	type:              c.int,
	url:               cstring,
	credentials:       git_credential_acquire_cb,
	certificate_check: rawptr,
	payload:           rawptr,
}

git_remote_callbacks :: struct {
	version:                c.uint,
	sideband_progress:      rawptr,
	completion:             rawptr,
	credentials:            git_credential_acquire_cb,
	certificate_check:      rawptr,
	transfer_progress:      rawptr,
	update_tips:            rawptr,
	pack_progress:          rawptr,
	push_transfer_progress: rawptr,
	push_update_reference:  rawptr,
	push_negotiation:       rawptr,
	transport:              rawptr,
	remote_ready:           rawptr,
	payload:                rawptr,
	resolve_url:            rawptr,
	update_refs:            rawptr,
}

git_fetch_options :: struct {
	version:          c.int,
	callbacks:        git_remote_callbacks,
	prune:            c.int,
	update_fetchhead: c.uint,
	download_tags:    c.int,
	proxy_opts:       git_proxy_options,
	depth:            c.int,
	follow_redirects: c.int,
	custom_headers:   git_strarray,
}

git_push_options :: struct {
	version:             c.uint,
	pb_parallelism:      c.uint,
	callbacks:           git_remote_callbacks,
	proxy_opts:          git_proxy_options,
	follow_redirects:    c.int,
	custom_headers:      git_strarray,
	remote_push_options: git_strarray,
}

// Struct versions the *_init procs are given (GIT_*_OPTIONS_VERSION).
GIT_STATUS_OPTIONS_VERSION :: 1
GIT_FETCH_OPTIONS_VERSION :: 1
GIT_PUSH_OPTIONS_VERSION :: 1
GIT_DIFF_OPTIONS_VERSION :: 1

// The git_error_code values (errors.h) the wrapper returns or a caller
// tells apart; each is named where it is used.
GIT_ENOTFOUND :: -3
GIT_ENONFASTFORWARD :: -11
GIT_EUNBORNBRANCH :: -9
GIT_EINVALIDSPEC :: -12
GIT_EUNCOMMITTED :: -15
GIT_PASSTHROUGH :: -30

// One path's status bits, from status.h.
GIT_STATUS_INDEX_NEW :: 1 << 0
GIT_STATUS_INDEX_MODIFIED :: 1 << 1
GIT_STATUS_INDEX_DELETED :: 1 << 2
GIT_STATUS_INDEX_RENAMED :: 1 << 3
GIT_STATUS_INDEX_TYPECHANGE :: 1 << 4
GIT_STATUS_WT_NEW :: 1 << 7
GIT_STATUS_WT_MODIFIED :: 1 << 8
GIT_STATUS_WT_DELETED :: 1 << 9
GIT_STATUS_WT_TYPECHANGE :: 1 << 10
GIT_STATUS_WT_RENAMED :: 1 << 11
GIT_STATUS_IGNORED :: 1 << 14
GIT_STATUS_CONFLICTED :: 1 << 15

// What status lists, from status.h.
GIT_STATUS_OPT_INCLUDE_UNTRACKED :: 1 << 0
GIT_STATUS_OPT_RECURSE_UNTRACKED_DIRS :: 1 << 4
GIT_STATUS_OPT_SORT_CASE_SENSITIVELY :: 1 << 9
GIT_STATUS_SHOW_INDEX_AND_WORKDIR :: 0

GIT_INDEX_ADD_DEFAULT :: 0
GIT_OBJECT_COMMIT :: 1
GIT_RESET_HARD :: 3
GIT_DIFF_FORMAT_PATCH :: 1
GIT_DIRECTION_FETCH :: 0
GIT_ERROR_NET :: 12 // git_error_t: the class a credential problem is reported under
GIT_SORT_TOPOLOGICAL :: 1 << 0
GIT_SORT_TIME :: 1 << 1

// What git_merge_analysis reports, from merge.h.
GIT_MERGE_ANALYSIS_NORMAL :: 1 << 0
GIT_MERGE_ANALYSIS_UP_TO_DATE :: 1 << 1
GIT_MERGE_ANALYSIS_FASTFORWARD :: 1 << 2
GIT_MERGE_ANALYSIS_UNBORN :: 1 << 3

// The credential kinds a remote may ask acquire for, from credential.h.
GIT_CREDENTIAL_USERPASS_PLAINTEXT :: 1 << 0
GIT_CREDENTIAL_SSH_KEY :: 1 << 1
GIT_CREDENTIAL_DEFAULT :: 1 << 3

@(default_calling_convention = "c")
foreign lib {
	git_libgit2_init :: proc() -> c.int ---
	git_libgit2_shutdown :: proc() -> c.int ---
	git_error_last :: proc() -> ^git_error ---
	git_error_set_str :: proc(error_class: c.int, str: cstring) -> c.int ---

	git_repository_open :: proc(out: ^^git_repository, path: cstring) -> c.int ---
	git_repository_init :: proc(out: ^^git_repository, path: cstring, is_bare: c.uint) -> c.int ---
	git_repository_free :: proc(repo: ^git_repository) ---
	git_repository_workdir :: proc(repo: ^git_repository) -> cstring ---
	git_repository_head :: proc(out: ^^git_reference, repo: ^git_repository) -> c.int ---
	git_repository_head_unborn :: proc(repo: ^git_repository) -> c.int ---
	git_repository_index :: proc(out: ^^git_index, repo: ^git_repository) -> c.int ---
	git_clone :: proc(out: ^^git_repository, url, local_path: cstring, options: rawptr) -> c.int ---

	git_reference_free :: proc(ref: ^git_reference) ---
	git_reference_target :: proc(ref: ^git_reference) -> ^git_oid ---
	git_reference_shorthand :: proc(ref: ^git_reference) -> cstring ---
	git_reference_name :: proc(ref: ^git_reference) -> cstring ---
	git_reference_name_to_id :: proc(out: ^git_oid, repo: ^git_repository, name: cstring) -> c.int ---
	git_branch_upstream :: proc(out: ^^git_reference, branch: ^git_reference) -> c.int ---

	git_oid_tostr_s :: proc(oid: ^git_oid) -> cstring ---

	git_index_add_all :: proc(index: ^git_index, pathspec: ^git_strarray, flags: c.uint, callback: rawptr, payload: rawptr) -> c.int ---
	git_index_update_all :: proc(index: ^git_index, pathspec: ^git_strarray, callback: rawptr, payload: rawptr) -> c.int ---
	git_index_write :: proc(index: ^git_index) -> c.int ---
	git_index_write_tree :: proc(out: ^git_oid, index: ^git_index) -> c.int ---
	git_index_free :: proc(index: ^git_index) ---

	git_tree_lookup :: proc(out: ^^git_tree, repo: ^git_repository, id: ^git_oid) -> c.int ---
	git_tree_free :: proc(tree: ^git_tree) ---

	git_commit_lookup :: proc(out: ^^git_commit, repo: ^git_repository, id: ^git_oid) -> c.int ---
	git_commit_free :: proc(commit: ^git_commit) ---
	git_commit_summary :: proc(commit: ^git_commit) -> cstring ---
	git_commit_message_raw :: proc(commit: ^git_commit) -> cstring ---
	git_commit_author :: proc(commit: ^git_commit) -> ^git_signature ---
	git_commit_time :: proc(commit: ^git_commit) -> i64 ---
	git_commit_id :: proc(commit: ^git_commit) -> ^git_oid ---
	git_commit_tree :: proc(out: ^^git_tree, commit: ^git_commit) -> c.int ---
	git_commit_create :: proc(id: ^git_oid, repo: ^git_repository, update_ref: cstring, author, committer: ^git_signature, message_encoding, message: cstring, tree: ^git_tree, parent_count: c.size_t, parents: [^]^git_commit) -> c.int ---

	git_signature_default :: proc(out: ^^git_signature, repo: ^git_repository) -> c.int ---
	git_signature_now :: proc(out: ^^git_signature, name, email: cstring) -> c.int ---
	git_signature_free :: proc(sig: ^git_signature) ---

	git_revwalk_new :: proc(out: ^^git_revwalk, repo: ^git_repository) -> c.int ---
	git_revwalk_push_head :: proc(walk: ^git_revwalk) -> c.int ---
	git_revwalk_sorting :: proc(walk: ^git_revwalk, sort_mode: c.uint) -> c.int ---
	git_revwalk_next :: proc(out: ^git_oid, walk: ^git_revwalk) -> c.int ---
	git_revwalk_free :: proc(walk: ^git_revwalk) ---

	git_status_options_init :: proc(opts: ^git_status_options, version: c.uint) -> c.int ---
	git_status_list_new :: proc(out: ^^git_status_list, repo: ^git_repository, opts: ^git_status_options) -> c.int ---
	git_status_list_entrycount :: proc(list: ^git_status_list) -> c.size_t ---
	git_status_byindex :: proc(list: ^git_status_list, idx: c.size_t) -> ^git_status_entry ---
	git_status_list_free :: proc(list: ^git_status_list) ---

	git_remote_list :: proc(out: ^git_strarray, repo: ^git_repository) -> c.int ---
	git_remote_lookup :: proc(out: ^^git_remote, repo: ^git_repository, name: cstring) -> c.int ---
	git_remote_create :: proc(out: ^^git_remote, repo: ^git_repository, name, url: cstring) -> c.int ---
	git_remote_delete :: proc(repo: ^git_repository, name: cstring) -> c.int ---
	git_remote_url :: proc(remote: ^git_remote) -> cstring ---
	git_remote_free :: proc(remote: ^git_remote) ---
	git_fetch_options_init :: proc(opts: ^git_fetch_options, version: c.uint) -> c.int ---
	git_push_options_init :: proc(opts: ^git_push_options, version: c.uint) -> c.int ---
	git_remote_fetch :: proc(remote: ^git_remote, refspecs: ^git_strarray, opts: ^git_fetch_options, reflog_message: cstring) -> c.int ---
	git_remote_push :: proc(remote: ^git_remote, refspecs: ^git_strarray, opts: ^git_push_options) -> c.int ---
	git_remote_connect :: proc(remote: ^git_remote, direction: c.int, callbacks: ^git_remote_callbacks, proxy_opts: ^git_proxy_options, custom_headers: ^git_strarray) -> c.int ---
	git_remote_default_branch :: proc(out: ^git_buf, remote: ^git_remote) -> c.int ---
	git_remote_disconnect :: proc(remote: ^git_remote) -> c.int ---
	git_strarray_dispose :: proc(array: ^git_strarray) ---

	git_graph_ahead_behind :: proc(ahead, behind: ^c.size_t, repo: ^git_repository, local, upstream: ^git_oid) -> c.int ---
	git_annotated_commit_lookup :: proc(out: ^^git_annotated_commit, repo: ^git_repository, id: ^git_oid) -> c.int ---
	git_annotated_commit_free :: proc(commit: ^git_annotated_commit) ---
	git_merge_analysis :: proc(analysis_out, preference_out: ^c.int, repo: ^git_repository, their_heads: [^]^git_annotated_commit, their_heads_len: c.size_t) -> c.int ---
	git_object_lookup :: proc(out: ^^git_object, repo: ^git_repository, id: ^git_oid, type: c.int) -> c.int ---
	git_object_free :: proc(object: ^git_object) ---
	git_reset :: proc(repo: ^git_repository, target: ^git_object, reset_type: c.int, checkout_opts: rawptr) -> c.int ---

	git_diff_options_init :: proc(opts: ^git_diff_options, version: c.uint) -> c.int ---
	git_diff_tree_to_index :: proc(out: ^^git_diff, repo: ^git_repository, old_tree: ^git_tree, index: ^git_index, opts: ^git_diff_options) -> c.int ---
	git_diff_index_to_workdir :: proc(out: ^^git_diff, repo: ^git_repository, index: ^git_index, opts: ^git_diff_options) -> c.int ---
	git_diff_to_buf :: proc(out: ^git_buf, diff: ^git_diff, format: c.int) -> c.int ---
	git_diff_free :: proc(diff: ^git_diff) ---
	git_buf_dispose :: proc(buffer: ^git_buf) ---

	git_credential_userpass_plaintext_new :: proc(out: ^^git_credential, username, password: cstring) -> c.int ---
	git_credential_ssh_key_from_agent :: proc(out: ^^git_credential, username: cstring) -> c.int ---
	git_credential_default_new :: proc(out: ^^git_credential) -> c.int ---
	git_credential_free :: proc(cred: ^git_credential) ---
}
