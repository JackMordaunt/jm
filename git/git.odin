/*
Package git is a repository for programs that ship: open, init, clone,
status, add, commit, log, remotes, fetch, push, pull and diff over libgit2,
so a built binary needs no git on the machine it runs on. The subset is
what an application that keeps its data in a git repository does on the
user's behalf; anything else is a raw call away in ffi.odin.

	repo := must(git.open("~/notes"))
	defer git.close(&repo)
	must(git.add(repo, {"."}))
	id := must(git.commit(repo, "notes: today's bullets"))
	must(git.push(repo, "origin"))

Hooks: libgit2 runs none. A program that wants pre-commit checks runs them
itself before commit, which is also the only way they run for a user who
has no git.

Transport: HTTPS goes through libgit2's own backend on every platform
(WinHTTP, SecureTransport, and on Linux OpenSSL loaded at run time). SSH
remotes go through the platform's ssh binary and agent when the static
library is built with USE_SSH=exec (`just libgit2`), so an ssh:// or
git@ URL works wherever `ssh` does. Credentials for HTTPS are a token in
Credentials; an empty one lets libgit2 try the platform default.

Memory: every string handed back is cloned into the allocator the call was
given, because libgit2 frees its own copy with the object it came from.
Errors carry libgit2's message the same way, in context.allocator.
Threads: libgit2 is thread-safe across repositories; one Repo is not
guarded here, so share it between threads with the caller's own mutex.
*/
package git

import "core:c"
import "core:fmt"
import "core:strings"
import "core:sync"
import "core:time"

// Repo is one open repository. libgit2 owns the handle; close releases it.
Repo :: struct {
	ptr: ^git_repository,
}

// Fault is a failed libgit2 call: its code (GIT_E*), and the message
// libgit2 left, cloned into context.allocator.
Fault :: struct {
	code:    i32,
	message: string,
}

Error :: union {
	Fault,
}

// Signature names an author. Zero means the repository's own config,
// user.name and user.email, which commit needs one way or the other.
Signature :: struct {
	name, email: string,
}

// Credentials answer an HTTPS remote's challenge: a personal access token
// or app password, and the username the host expects beside it (GitHub
// takes any). Empty lets libgit2 try the platform's default credential.
Credentials :: struct {
	username, token: string,
}

// Change is what happened to one path, in the index or the working tree.
Change :: enum u8 {
	None,
	New,
	Modified,
	Deleted,
	Renamed,
	Typechange,
}

// Entry is one path status reports: what is staged and what is not.
Entry :: struct {
	path:       string,
	index:      Change, // staged, HEAD to index
	worktree:   Change, // unstaged, index to working tree
	conflicted: bool,
}

// Commit is one entry of log.
Commit :: struct {
	id:      string, // 40 hex digits
	summary: string, // the first line of the message
	message: string, // as written, leading newlines included: libgit2's own accessor would trim them
	author:  Signature,
	at:      time.Time,
}

Remote :: struct {
	name, url: string,
}

// Sync is what pull did.
Sync :: enum u8 {
	Up_To_Date, // the remote has nothing the branch lacks; the branch may be ahead of it
	Fast_Forwarded, // the branch moved onto the remote's commit
	Diverged, // both sides have commits the other lacks; nothing was changed
}

@(private)
once: sync.Once

// ready initialises libgit2 once per process. Every entry point calls it,
// so a program never has to. It is never shut down: libgit2's shutdown is
// for programs that unload it, and freeing at exit is the OS's job.
@(private)
ready :: proc() {
	sync.once_do(&once, proc() {
		git_libgit2_init()
	})
}

// ready_for_test is ready for a test that calls into libgit2 without
// going through an entry point first.
@(private)
ready_for_test :: proc() {
	ready()
}

// fault reads libgit2's last error for a call that returned code.
@(private)
fault :: proc(code: c.int) -> Error {
	msg := "unknown error"
	if e := git_error_last(); e != nil && e.message != nil {
		msg = string(e.message)
	}
	if strings.has_prefix(msg, "could not load ssl") {
		// `just libgit2` builds Linux with -DUSE_HTTPS=OpenSSL-Dynamic, which
		// dlopens libssl and libcrypto on first use; src/libgit2/streams/
		// openssl_dynamic.c sets this message when that fails.
		msg = fmt.tprintf("%s: libgit2 loads the system OpenSSL 3 at run time; install libssl (libssl.so.3) or use an ssh:// remote", msg)
	}
	return Fault{i32(code), strings.clone(msg)}
}

@(private)
cstr :: proc(s: string) -> cstring {
	return strings.clone_to_cstring(s, context.temp_allocator)
}

// reject_nul refuses a string a C API would silently cut at its first NUL:
// a message, a path or a name with one inside it would otherwise be
// stored as something shorter than the caller asked for.
@(private)
reject_nul :: proc(what: string, values: ..string) -> Error {
	for v in values {
		if strings.contains_rune(v, 0) {
			return Fault{GIT_EINVALIDSPEC, strings.clone(fmt.tprintf("%s holds a NUL byte", what))}
		}
	}
	return nil
}

@(private)
oid_string :: proc(id: ^git_oid, allocator := context.allocator) -> string {
	return strings.clone(string(git_oid_tostr_s(id)), allocator)
}

// open opens the repository at path, a working tree or a bare repository.
open :: proc(path: string) -> (repo: Repo, err: Error) {
	ready()
	reject_nul("path", path) or_return
	if rc := git_repository_open(&repo.ptr, cstr(path)); rc < 0 {
		return {}, fault(rc)
	}
	return
}

// init creates a repository at path, making the directory when it does
// not exist. bare makes one without a working tree, the shape a remote
// to push to has.
init :: proc(path: string, bare := false) -> (repo: Repo, err: Error) {
	ready()
	reject_nul("path", path) or_return
	if rc := git_repository_init(&repo.ptr, cstr(path), c.uint(bare ? 1 : 0)); rc < 0 {
		return {}, fault(rc)
	}
	return
}

// clone fetches url into path, a new directory, and opens it.
clone :: proc(url, path: string) -> (repo: Repo, err: Error) {
	ready()
	reject_nul("url or path", url, path) or_return
	if rc := git_clone(&repo.ptr, cstr(url), cstr(path), nil); rc < 0 {
		return {}, fault(rc)
	}
	return
}

close :: proc(repo: ^Repo) {
	if repo.ptr != nil {
		git_repository_free(repo.ptr)
		repo.ptr = nil
	}
}

// head is the current branch and the commit it is on. ok is false on an
// unborn branch, a repository with no commit yet.
head :: proc(repo: Repo, allocator := context.allocator) -> (branch, id: string, ok: bool) {
	ref: ^git_reference
	if git_repository_head(&ref, repo.ptr) < 0 {
		return
	}
	defer git_reference_free(ref)
	branch = strings.clone(string(git_reference_shorthand(ref)), allocator)
	id = oid_string(git_reference_target(ref), allocator)
	return branch, id, true
}

// status is every path that differs between HEAD, the index and the
// working tree, untracked files included, ignored ones left out, in
// libgit2's path order. A rename is a delete and a new file: no
// similarity guess stands between the caller and the three trees.
status :: proc(repo: Repo, allocator := context.allocator) -> (entries: []Entry, err: Error) {
	opts: git_status_options
	git_status_options_init(&opts, GIT_STATUS_OPTIONS_VERSION)
	opts.show = GIT_STATUS_SHOW_INDEX_AND_WORKDIR
	opts.flags = GIT_STATUS_OPT_INCLUDE_UNTRACKED | GIT_STATUS_OPT_RECURSE_UNTRACKED_DIRS | GIT_STATUS_OPT_SORT_CASE_SENSITIVELY
	list: ^git_status_list
	if rc := git_status_list_new(&list, repo.ptr, &opts); rc < 0 {
		return nil, fault(rc)
	}
	defer git_status_list_free(list)
	n := int(git_status_list_entrycount(list))
	out := make([dynamic]Entry, 0, n, allocator)
	for i in 0 ..< n {
		e := git_status_byindex(list, c.size_t(i))
		s := e.status
		if s & GIT_STATUS_IGNORED != 0 {
			continue
		}
		delta := e.index_to_workdir != nil ? e.index_to_workdir : e.head_to_index
		if delta == nil {
			continue
		}
		path := delta.new_file.path != nil ? delta.new_file.path : delta.old_file.path
		append(
			&out,
			Entry {
				path = strings.clone(string(path), allocator),
				index = index_change(s),
				worktree = worktree_change(s),
				conflicted = s & GIT_STATUS_CONFLICTED != 0,
			},
		)
	}
	return out[:], nil
}

@(private)
index_change :: proc(s: c.uint) -> Change {
	switch {
	case s & GIT_STATUS_INDEX_NEW != 0:
		return .New
	case s & GIT_STATUS_INDEX_MODIFIED != 0:
		return .Modified
	case s & GIT_STATUS_INDEX_DELETED != 0:
		return .Deleted
	case s & GIT_STATUS_INDEX_RENAMED != 0:
		return .Renamed
	case s & GIT_STATUS_INDEX_TYPECHANGE != 0:
		return .Typechange
	}
	return .None
}

@(private)
worktree_change :: proc(s: c.uint) -> Change {
	switch {
	case s & GIT_STATUS_WT_NEW != 0:
		return .New
	case s & GIT_STATUS_WT_MODIFIED != 0:
		return .Modified
	case s & GIT_STATUS_WT_DELETED != 0:
		return .Deleted
	case s & GIT_STATUS_WT_RENAMED != 0:
		return .Renamed
	case s & GIT_STATUS_WT_TYPECHANGE != 0:
		return .Typechange
	}
	return .None
}

@(private)
strarray :: proc(items: []string) -> git_strarray {
	arr := make([]cstring, len(items), context.temp_allocator)
	for s, i in items {
		arr[i] = cstr(s)
	}
	return {raw_data(arr), c.size_t(len(items))}
}

// add stages every change under pathspecs, "." for the whole tree: new
// and modified files are added, deleted ones removed, as `git add -A`
// does. Ignored files stay out.
add :: proc(repo: Repo, pathspecs: []string) -> Error {
	if err := reject_nul("pathspec", ..pathspecs); err != nil {
		return err
	}
	index: ^git_index
	if rc := git_repository_index(&index, repo.ptr); rc < 0 {
		return fault(rc)
	}
	defer git_index_free(index)
	spec := strarray(pathspecs)
	if rc := git_index_add_all(index, &spec, GIT_INDEX_ADD_DEFAULT, nil, nil); rc < 0 {
		return fault(rc)
	}
	if rc := git_index_update_all(index, &spec, nil, nil); rc < 0 {
		return fault(rc)
	}
	if rc := git_index_write(index); rc < 0 {
		return fault(rc)
	}
	return nil
}

// commit records the index as a commit on the current branch and returns
// its id. The author is sig, or the repository's user.name and user.email
// when sig is zero; with neither, the error says so.
commit :: proc(repo: Repo, message: string, sig := Signature{}, allocator := context.allocator) -> (id: string, err: Error) {
	reject_nul("message or signature", message, sig.name, sig.email) or_return
	author: ^git_signature
	if sig == {} {
		if rc := git_signature_default(&author, repo.ptr); rc < 0 {
			return "", fault(rc)
		}
	} else if rc := git_signature_now(&author, cstr(sig.name), cstr(sig.email)); rc < 0 {
		return "", fault(rc)
	}
	defer git_signature_free(author)

	index: ^git_index
	if rc := git_repository_index(&index, repo.ptr); rc < 0 {
		return "", fault(rc)
	}
	defer git_index_free(index)
	tree_id: git_oid
	if rc := git_index_write_tree(&tree_id, index); rc < 0 {
		return "", fault(rc)
	}
	tree: ^git_tree
	if rc := git_tree_lookup(&tree, repo.ptr, &tree_id); rc < 0 {
		return "", fault(rc)
	}
	defer git_tree_free(tree)

	parents: [1]^git_commit
	n_parents: c.size_t
	if git_repository_head_unborn(repo.ptr) == 0 {
		ref: ^git_reference
		if rc := git_repository_head(&ref, repo.ptr); rc < 0 {
			return "", fault(rc)
		}
		defer git_reference_free(ref)
		if rc := git_commit_lookup(&parents[0], repo.ptr, git_reference_target(ref)); rc < 0 {
			return "", fault(rc)
		}
		n_parents = 1
	}
	defer if n_parents > 0 {
		git_commit_free(parents[0])
	}

	oid: git_oid
	if rc := git_commit_create(&oid, repo.ptr, "HEAD", author, author, nil, cstr(message), tree, n_parents, raw_data(parents[:])); rc < 0 {
		return "", fault(rc)
	}
	return oid_string(&oid, allocator), nil
}

// log is the newest limit commits reachable from HEAD, newest first; 0 is
// all of them. since, when set, stops the walk at the first commit made
// before it, as `git log --since` does. An unborn branch logs nothing.
log :: proc(repo: Repo, limit := 0, allocator := context.allocator, since := time.Time{}) -> (commits: []Commit, err: Error) {
	if git_repository_head_unborn(repo.ptr) != 0 {
		return nil, nil
	}
	walk: ^git_revwalk
	if rc := git_revwalk_new(&walk, repo.ptr); rc < 0 {
		return nil, fault(rc)
	}
	defer git_revwalk_free(walk)
	// Time alone is not enough: git/fuzz's first run made three commits
	// in one second and read them back as [c2, c0, c1], the parent
	// before its child. Topological order keeps every commit after the
	// ones that follow from it, whatever the clock says.
	git_revwalk_sorting(walk, GIT_SORT_TOPOLOGICAL | GIT_SORT_TIME)
	if rc := git_revwalk_push_head(walk); rc < 0 {
		return nil, fault(rc)
	}
	out := make([dynamic]Commit, allocator)
	oid: git_oid
	for git_revwalk_next(&oid, walk) == 0 {
		cm: ^git_commit
		if rc := git_commit_lookup(&cm, repo.ptr, &oid); rc < 0 {
			return out[:], fault(rc)
		}
		if since != {} && time.unix(git_commit_time(cm), 0)._nsec < since._nsec {
			git_commit_free(cm)
			break
		}
		a := git_commit_author(cm)
		append(
			&out,
			Commit {
				id = oid_string(&oid, allocator),
				summary = strings.clone(string(git_commit_summary(cm)), allocator),
				message = strings.clone(string(git_commit_message_raw(cm)), allocator),
				author = {strings.clone(string(a.name), allocator), strings.clone(string(a.email), allocator)},
				at = time.unix(git_commit_time(cm), 0),
			},
		)
		git_commit_free(cm)
		if limit > 0 && len(out) >= limit {
			break
		}
	}
	return out[:], nil
}

// remotes lists the configured remotes, in libgit2's order.
remotes :: proc(repo: Repo, allocator := context.allocator) -> (out: []Remote, err: Error) {
	names: git_strarray
	if rc := git_remote_list(&names, repo.ptr); rc < 0 {
		return nil, fault(rc)
	}
	defer git_strarray_dispose(&names)
	list := make([]Remote, int(names.count), allocator)
	for i in 0 ..< int(names.count) {
		r: ^git_remote
		if rc := git_remote_lookup(&r, repo.ptr, names.strings[i]); rc < 0 {
			return list[:i], fault(rc)
		}
		list[i] = {strings.clone(string(names.strings[i]), allocator), strings.clone(string(git_remote_url(r)), allocator)}
		git_remote_free(r)
	}
	return list, nil
}

// remote_add configures name to point at url.
remote_add :: proc(repo: Repo, name, url: string) -> Error {
	if err := reject_nul("remote name or url", name, url); err != nil {
		return err
	}
	r: ^git_remote
	if rc := git_remote_create(&r, repo.ptr, cstr(name), cstr(url)); rc < 0 {
		return fault(rc)
	}
	git_remote_free(r)
	return nil
}

// remote_remove drops name and its tracking branches.
remote_remove :: proc(repo: Repo, name: string) -> Error {
	if err := reject_nul("remote name", name); err != nil {
		return err
	}
	if rc := git_remote_delete(repo.ptr, cstr(name)); rc < 0 {
		return fault(rc)
	}
	return nil
}

// USERNAME_MAX and TOKEN_MAX bound what acquire copies into its stack
// buffers, which is all a callback without a context can allocate. The
// GitHub token tools/git-probe ran with used under a tenth of TOKEN_MAX.
USERNAME_MAX :: 255
TOKEN_MAX :: 1023

// Ask is what a fetch or push hands acquire: the credentials, and how
// many times the remote has asked. libgit2 calls the callback again
// after the server rejects what it was given, so a second ask for a
// password is the first answer refused; tools/git-probe with a wrong
// token showed the calls repeating until libgit2 gave up on its own.
@(private)
Ask :: struct {
	creds: Credentials,
	asked: int,
}

// acquire is the credential callback every fetch and push installs: it
// answers with the token in the payload's Credentials when the remote
// takes a password, with the ssh agent when it takes a key, and with the
// platform default otherwise. Without a token it lets libgit2 carry on.
// A token the remote refused is not offered twice, so the caller reads
// "the remote refused the token" rather than libgit2's own give-up
// message about authentication replays, which the probe saw first.
@(private)
acquire :: proc "c" (out: ^^git_credential, url, username_from_url: cstring, allowed: c.uint, payload: rawptr) -> c.int {
	ask := (^Ask)(payload)
	if allowed & GIT_CREDENTIAL_USERPASS_PLAINTEXT != 0 && ask != nil && ask.creds.token != "" {
		ask.asked += 1
		if ask.asked > 1 {
			git_error_set_str(GIT_ERROR_NET, "the remote refused the token")
			return -1
		}
		user := ask.creds.username != "" ? ask.creds.username : "git"
		if len(user) > USERNAME_MAX || len(ask.creds.token) > TOKEN_MAX {
			git_error_set_str(GIT_ERROR_NET, "credential too long for jm:git (username 255 bytes, token 1023)")
			return -1
		}
		ubuf: [USERNAME_MAX + 1]u8
		tbuf: [TOKEN_MAX + 1]u8
		return git_credential_userpass_plaintext_new(out, tmp_cstring(ubuf[:], user), tmp_cstring(tbuf[:], ask.creds.token))
	}
	if allowed & GIT_CREDENTIAL_SSH_KEY != 0 {
		return git_credential_ssh_key_from_agent(out, username_from_url)
	}
	if allowed & GIT_CREDENTIAL_DEFAULT != 0 {
		return git_credential_default_new(out)
	}
	return GIT_PASSTHROUGH
}

// tmp_cstring copies s, NUL-terminated, into buf, which the caller has
// sized for it: for the callback above, which runs without a context to
// allocate from.
@(private)
tmp_cstring :: proc "contextless" (buf: []u8, s: string) -> cstring {
	n := min(len(s), len(buf) - 1)
	copy(buf[:n], s[:n])
	buf[n] = 0
	return cstring(raw_data(buf))
}

// fetch brings remote's branches up to date under refs/remotes/<remote>.
fetch :: proc(repo: Repo, remote: string, creds := Credentials{}) -> Error {
	if err := reject_nul("remote name", remote); err != nil {
		return err
	}
	r: ^git_remote
	if rc := git_remote_lookup(&r, repo.ptr, cstr(remote)); rc < 0 {
		return fault(rc)
	}
	defer git_remote_free(r)
	ask := Ask{creds = creds}
	opts: git_fetch_options
	git_fetch_options_init(&opts, GIT_FETCH_OPTIONS_VERSION)
	opts.callbacks.credentials = acquire
	opts.callbacks.payload = &ask
	if rc := git_remote_fetch(r, nil, &opts, "fetch"); rc < 0 {
		return fault(rc)
	}
	return nil
}

// push sends branch (the current one by default) to remote, creating it
// there when it is new. A remote that has moved on refuses the push with
// GIT_ENONFASTFORWARD; pull first.
push :: proc(repo: Repo, remote: string, branch := "", creds := Credentials{}) -> Error {
	if err := reject_nul("remote or branch", remote, branch); err != nil {
		return err
	}
	b := branch
	if b == "" {
		ok: bool
		b, _, ok = head(repo, context.temp_allocator)
		if !ok {
			return Fault{GIT_EUNBORNBRANCH, strings.clone("nothing to push: the branch has no commit")}
		}
	}
	r: ^git_remote
	if rc := git_remote_lookup(&r, repo.ptr, cstr(remote)); rc < 0 {
		return fault(rc)
	}
	defer git_remote_free(r)
	ask := Ask{creds = creds}
	opts: git_push_options
	git_push_options_init(&opts, GIT_PUSH_OPTIONS_VERSION)
	opts.callbacks.credentials = acquire
	opts.callbacks.payload = &ask
	refspec := fmt.tprintf("refs/heads/%s:refs/heads/%s", b, b)
	specs := strarray({refspec})
	if rc := git_remote_push(r, &specs, &opts); rc < 0 {
		return fault(rc)
	}
	return nil
}

// default_branch asks remote which branch it checks out by default, the
// short name ("main"), which takes a connection of its own. A remote
// with no commit yet answers GIT_ENOTFOUND.
default_branch :: proc(repo: Repo, remote: string, creds := Credentials{}, allocator := context.temp_allocator) -> (name: string, err: Error) {
	reject_nul("remote name", remote) or_return
	r: ^git_remote
	if rc := git_remote_lookup(&r, repo.ptr, cstr(remote)); rc < 0 {
		return "", fault(rc)
	}
	defer git_remote_free(r)
	ask := Ask{creds = creds}
	cb: git_remote_callbacks
	cb.version = 1
	cb.credentials = acquire
	cb.payload = &ask
	if rc := git_remote_connect(r, GIT_DIRECTION_FETCH, &cb, nil, nil); rc < 0 {
		return "", fault(rc)
	}
	defer git_remote_disconnect(r)
	buf: git_buf
	if rc := git_remote_default_branch(&buf, r); rc < 0 {
		return "", fault(rc)
	}
	defer git_buf_dispose(&buf)
	full := string(buf.ptr[:buf.size])
	return strings.clone(strings.trim_prefix(full, "refs/heads/"), allocator), nil
}

// upstream_id is the commit remote's copy of branch is on, after a fetch.
@(private)
upstream_id :: proc(repo: Repo, remote, branch: string) -> (id: git_oid, err: Error) {
	if rc := git_reference_name_to_id(&id, repo.ptr, cstr(fmt.tprintf("refs/remotes/%s/%s", remote, branch))); rc < 0 {
		return {}, fault(rc)
	}
	return
}

// pull fetches remote and fast-forwards the current branch onto its copy,
// working tree included. It never merges: a branch with its own commits
// reports Diverged and is left as it was, for the caller to decide. Nor
// does it overwrite: with anything uncommitted it fails with
// GIT_EUNCOMMITTED and changes nothing.
pull :: proc(repo: Repo, remote: string, creds := Credentials{}) -> (sync: Sync, err: Error) {
	if ferr := fetch(repo, remote, creds); ferr != nil {
		return .Up_To_Date, ferr
	}
	branch, _, born := head(repo, context.temp_allocator)
	if !born {
		// A repository made by hand and pointed at a remote: take the
		// branch the remote calls its default as ours. A remote with no
		// commit either has nothing to give, and says so with ENOTFOUND.
		derr: Error
		branch, derr = default_branch(repo, remote, creds)
		if f, is_fault := derr.(Fault); is_fault && f.code == GIT_ENOTFOUND {
			return .Up_To_Date, nil
		} else if derr != nil {
			return .Up_To_Date, derr
		}
	}
	their := upstream_id(repo, remote, branch) or_return
	annotated: [1]^git_annotated_commit
	if rc := git_annotated_commit_lookup(&annotated[0], repo.ptr, &their); rc < 0 {
		return .Up_To_Date, fault(rc)
	}
	defer git_annotated_commit_free(annotated[0])
	analysis, preference: c.int
	if rc := git_merge_analysis(&analysis, &preference, repo.ptr, raw_data(annotated[:]), 1); rc < 0 {
		return .Up_To_Date, fault(rc)
	}
	switch {
	case analysis & GIT_MERGE_ANALYSIS_UP_TO_DATE != 0:
		return .Up_To_Date, nil
	case analysis & (GIT_MERGE_ANALYSIS_FASTFORWARD | GIT_MERGE_ANALYSIS_UNBORN) != 0:
		// The fast-forward below is a hard reset, which would take
		// uncommitted work with it: refuse while there is any.
		entries := status(repo, context.temp_allocator) or_return
		if len(entries) > 0 {
			return .Up_To_Date, Fault{GIT_EUNCOMMITTED, strings.clone("uncommitted changes would be overwritten; commit or discard them first")}
		}
		target: ^git_object
		if rc := git_object_lookup(&target, repo.ptr, &their, GIT_OBJECT_COMMIT); rc < 0 {
			return .Up_To_Date, fault(rc)
		}
		defer git_object_free(target)
		// A hard reset to a commit HEAD is an ancestor of is exactly a
		// fast-forward, and needs no checkout options.
		if rc := git_reset(repo.ptr, target, GIT_RESET_HARD, nil); rc < 0 {
			return .Up_To_Date, fault(rc)
		}
		return .Fast_Forwarded, nil
	}
	return .Diverged, nil
}

// ahead_behind counts the commits the current branch has that remote's
// copy lacks, and the reverse, as of the last fetch.
ahead_behind :: proc(repo: Repo, remote: string) -> (ahead, behind: int, err: Error) {
	branch, _, born := head(repo, context.temp_allocator)
	if !born {
		return 0, 0, nil
	}
	local: git_oid
	if rc := git_reference_name_to_id(&local, repo.ptr, "HEAD"); rc < 0 {
		return 0, 0, fault(rc)
	}
	their := upstream_id(repo, remote, branch) or_return
	a, b: c.size_t
	if rc := git_graph_ahead_behind(&a, &b, repo.ptr, &local, &their); rc < 0 {
		return 0, 0, fault(rc)
	}
	return int(a), int(b), nil
}

// diff is the patch text of what is staged (HEAD to index) or, with
// staged false, of what is not (index to working tree), in the format
// `git diff` prints, empty when nothing differs. context_lines is how
// many unchanged lines frame each hunk (`-U`); paths, when given, are
// pathspecs the patch is limited to, matched as git matches them, so
// "*.md" takes markdown in every directory.
diff :: proc(repo: Repo, staged: bool, allocator := context.allocator, context_lines := 3, paths: []string = nil) -> (patch: string, err: Error) {
	reject_nul("pathspec", ..paths) or_return
	index: ^git_index
	if rc := git_repository_index(&index, repo.ptr); rc < 0 {
		return "", fault(rc)
	}
	defer git_index_free(index)
	opts: git_diff_options
	git_diff_options_init(&opts, GIT_DIFF_OPTIONS_VERSION)
	opts.context_lines = u32(max(context_lines, 0))
	opts.pathspec = strarray(paths)
	// a/ and b/ whatever the user's config says: with diff.mnemonicPrefix
	// set, libgit2 printed c/ and i/ (2026-10-09), and a reader of the
	// patch could no longer find the file after "+++ b/".
	opts.old_prefix, opts.new_prefix = "a/", "b/"
	d: ^git_diff
	if staged {
		tree: ^git_tree
		if git_repository_head_unborn(repo.ptr) == 0 {
			ref: ^git_reference
			if rc := git_repository_head(&ref, repo.ptr); rc < 0 {
				return "", fault(rc)
			}
			defer git_reference_free(ref)
			cm: ^git_commit
			if rc := git_commit_lookup(&cm, repo.ptr, git_reference_target(ref)); rc < 0 {
				return "", fault(rc)
			}
			defer git_commit_free(cm)
			if rc := git_commit_tree(&tree, cm); rc < 0 {
				return "", fault(rc)
			}
		}
		defer if tree != nil {
			git_tree_free(tree)
		}
		if rc := git_diff_tree_to_index(&d, repo.ptr, tree, index, &opts); rc < 0 {
			return "", fault(rc)
		}
	} else if rc := git_diff_index_to_workdir(&d, repo.ptr, index, &opts); rc < 0 {
		return "", fault(rc)
	}
	defer git_diff_free(d)
	buf: git_buf
	if rc := git_diff_to_buf(&buf, d, GIT_DIFF_FORMAT_PATCH); rc < 0 {
		return "", fault(rc)
	}
	defer git_buf_dispose(&buf)
	return strings.clone(string(buf.ptr[:buf.size]), allocator), nil
}

// --- beyond the everyday --------------------------------------------------
//
// What a program that keeps its data in git also needs once it does the
// whole job itself, with no git to fall back on: settings, a file as it
// was, counting commits, one commit's change, putting work aside, and
// taking a branch onto another's commits.

// discover opens the repository path is inside: path itself, or the
// nearest directory above it that is one, as git finds a repository from
// a subdirectory.
discover :: proc(path: string) -> (repo: Repo, err: Error) {
	ready()
	reject_nul("path", path) or_return
	if rc := git_repository_open_ext(&repo.ptr, cstr(path), 0, nil); rc < 0 {
		return {}, fault(rc)
	}
	return
}

// config_get is key's value ("user.email"), looked up as git does: the
// repository's own config, then the user's, then the system's. found is
// false when no level sets it.
config_get :: proc(repo: Repo, key: string, allocator := context.allocator) -> (value: string, found: bool) {
	if reject_nul("config key", key) != nil {
		return
	}
	cfg: ^git_config
	if git_repository_config(&cfg, repo.ptr) < 0 {
		return
	}
	defer git_config_free(cfg)
	buf: git_buf
	if git_config_get_string_buf(&buf, cfg, cstr(key)) < 0 {
		return
	}
	defer git_buf_dispose(&buf)
	return strings.clone(string(buf.ptr[:buf.size]), allocator), true
}

// config_set writes key in the repository's own config, .git/config.
config_set :: proc(repo: Repo, key, value: string) -> Error {
	reject_nul("config key or value", key, value) or_return
	cfg: ^git_config
	if rc := git_repository_config(&cfg, repo.ptr); rc < 0 {
		return fault(rc)
	}
	defer git_config_free(cfg)
	if rc := git_config_set_string(cfg, cstr(key), cstr(value)); rc < 0 {
		return fault(rc)
	}
	return nil
}

// resolve is the commit spec names ("HEAD", "origin/main", a full or
// short id, "HEAD~2"), as 40 hex digits. ok is false when it names no
// commit, as `git rev-parse --verify -q spec^{commit}` prints nothing.
resolve :: proc(repo: Repo, spec: string, allocator := context.allocator) -> (id: string, ok: bool) {
	oid, found := resolve_oid(repo, spec)
	if !found {
		return
	}
	return oid_string(&oid, allocator), true
}

@(private)
resolve_oid :: proc(repo: Repo, spec: string) -> (id: git_oid, ok: bool) {
	if spec == "" || reject_nul("revision", spec) != nil {
		return
	}
	obj: ^git_object
	if git_revparse_single(&obj, repo.ptr, cstr(spec)) < 0 {
		return
	}
	defer git_object_free(obj)
	peeled: ^git_object
	if git_object_peel(&peeled, obj, GIT_OBJECT_COMMIT) < 0 {
		return
	}
	defer git_object_free(peeled)
	return git_object_id(peeled)^, true
}

// read_file is path's contents as of the commit rev names ("HEAD"),
// `git show rev:path`. found is false when rev names no commit or the
// commit has no file at path.
read_file :: proc(repo: Repo, rev, path: string, allocator := context.allocator) -> (data: string, found: bool) {
	if reject_nul("revision or path", rev, path) != nil {
		return
	}
	obj: ^git_object
	if git_revparse_single(&obj, repo.ptr, cstr(fmt.tprintf("%s:%s", rev, path))) < 0 {
		return
	}
	defer git_object_free(obj)
	if git_object_type(obj) != GIT_OBJECT_BLOB {
		return
	}
	blob := (^git_blob)(obj)
	n := int(git_blob_rawsize(blob))
	bytes := ([^]u8)(git_blob_rawcontent(blob))[:n]
	return strings.clone(string(bytes), allocator), true
}

// count is how many commits are reachable from to and not from from,
// `git rev-list --count from..to`; from "" counts all of to's history.
// A spec that names no commit is an error, except an empty to on an
// unborn branch, which counts nothing.
count :: proc(repo: Repo, from, to: string) -> (n: int, err: Error) {
	if to == "HEAD" && git_repository_head_unborn(repo.ptr) != 0 {
		return 0, nil
	}
	tip, ok := resolve_oid(repo, to)
	if !ok {
		return 0, Fault{GIT_ENOTFOUND, strings.clone(fmt.tprintf("no commit named %q", to))}
	}
	walk: ^git_revwalk
	if rc := git_revwalk_new(&walk, repo.ptr); rc < 0 {
		return 0, fault(rc)
	}
	defer git_revwalk_free(walk)
	if rc := git_revwalk_push(walk, &tip); rc < 0 {
		return 0, fault(rc)
	}
	if from != "" {
		base, bok := resolve_oid(repo, from)
		if !bok {
			return 0, Fault{GIT_ENOTFOUND, strings.clone(fmt.tprintf("no commit named %q", from))}
		}
		if rc := git_revwalk_hide(walk, &base); rc < 0 {
			return 0, fault(rc)
		}
	}
	oid: git_oid
	for git_revwalk_next(&oid, walk) == 0 {
		n += 1
	}
	return n, nil
}

// changes is what the commit id changed against its first parent (a
// root commit, against nothing): the paths it touched and the patch, as
// `git show --format= id -- paths` prints it, limited to paths when they
// are given. context_lines frames each hunk as diff's does.
changes :: proc(repo: Repo, id: string, paths: []string = nil, context_lines := 3, allocator := context.allocator) -> (files: []string, patch: string, err: Error) {
	reject_nul("pathspec", ..paths) or_return
	oid, ok := resolve_oid(repo, id)
	if !ok {
		return nil, "", Fault{GIT_ENOTFOUND, strings.clone(fmt.tprintf("no commit named %q", id))}
	}
	cm: ^git_commit
	if rc := git_commit_lookup(&cm, repo.ptr, &oid); rc < 0 {
		return nil, "", fault(rc)
	}
	defer git_commit_free(cm)
	tree, parent_tree: ^git_tree
	if rc := git_commit_tree(&tree, cm); rc < 0 {
		return nil, "", fault(rc)
	}
	defer git_tree_free(tree)
	if git_commit_parentcount(cm) > 0 {
		parent: ^git_commit
		if rc := git_commit_parent(&parent, cm, 0); rc < 0 {
			return nil, "", fault(rc)
		}
		defer git_commit_free(parent)
		if rc := git_commit_tree(&parent_tree, parent); rc < 0 {
			return nil, "", fault(rc)
		}
	}
	defer if parent_tree != nil {
		git_tree_free(parent_tree)
	}
	opts: git_diff_options
	git_diff_options_init(&opts, GIT_DIFF_OPTIONS_VERSION)
	opts.context_lines = u32(max(context_lines, 0))
	opts.pathspec = strarray(paths)
	// a/ and b/ whatever the user's config says: with diff.mnemonicPrefix
	// set, libgit2 printed c/ and i/ (2026-10-09), and a reader of the
	// patch could no longer find the file after "+++ b/".
	opts.old_prefix, opts.new_prefix = "a/", "b/"
	d: ^git_diff
	if rc := git_diff_tree_to_tree(&d, repo.ptr, parent_tree, tree, &opts); rc < 0 {
		return nil, "", fault(rc)
	}
	defer git_diff_free(d)
	n := int(git_diff_num_deltas(d))
	list := make([]string, n, allocator)
	for i in 0 ..< n {
		delta := git_diff_get_delta(d, c.size_t(i))
		p := delta.new_file.path != nil ? delta.new_file.path : delta.old_file.path
		list[i] = strings.clone(string(p), allocator)
	}
	buf: git_buf
	if rc := git_diff_to_buf(&buf, d, GIT_DIFF_FORMAT_PATCH); rc < 0 {
		return list, "", fault(rc)
	}
	defer git_buf_dispose(&buf)
	return list, strings.clone(string(buf.ptr[:buf.size]), allocator), nil
}

// unstage puts the index back to HEAD, everything staged unstaged and
// the working tree untouched, as `git reset` does; on an unborn branch it
// empties the index.
unstage :: proc(repo: Repo) -> Error {
	index: ^git_index
	if rc := git_repository_index(&index, repo.ptr); rc < 0 {
		return fault(rc)
	}
	defer git_index_free(index)
	if git_repository_head_unborn(repo.ptr) != 0 {
		if rc := git_index_clear(index); rc < 0 {
			return fault(rc)
		}
	} else {
		oid, _ := resolve_oid(repo, "HEAD")
		cm: ^git_commit
		if rc := git_commit_lookup(&cm, repo.ptr, &oid); rc < 0 {
			return fault(rc)
		}
		defer git_commit_free(cm)
		tree: ^git_tree
		if rc := git_commit_tree(&tree, cm); rc < 0 {
			return fault(rc)
		}
		defer git_tree_free(tree)
		if rc := git_index_read_tree(index, tree); rc < 0 {
			return fault(rc)
		}
	}
	if rc := git_index_write(index); rc < 0 {
		return fault(rc)
	}
	return nil
}

// remote_set_url points the remote name at url.
remote_set_url :: proc(repo: Repo, name, url: string) -> Error {
	reject_nul("remote name or url", name, url) or_return
	if rc := git_remote_set_url(repo.ptr, cstr(name), cstr(url)); rc < 0 {
		return fault(rc)
	}
	return nil
}

// checkout points branch at the commit start names, makes it the current
// branch, and sets the index and working tree to that commit, discarding
// whatever differs: `git checkout -f -B branch start`.
checkout :: proc(repo: Repo, branch, start: string) -> Error {
	reject_nul("branch", branch) or_return
	oid, ok := resolve_oid(repo, start)
	if !ok {
		return Fault{GIT_ENOTFOUND, strings.clone(fmt.tprintf("no commit named %q", start))}
	}
	cm: ^git_commit
	if rc := git_commit_lookup(&cm, repo.ptr, &oid); rc < 0 {
		return fault(rc)
	}
	defer git_commit_free(cm)
	ref: ^git_reference
	if rc := git_branch_create(&ref, repo.ptr, cstr(branch), cm, 1); rc < 0 {
		return fault(rc)
	}
	git_reference_free(ref)
	if rc := git_repository_set_head(repo.ptr, cstr(fmt.tprintf("refs/heads/%s", branch))); rc < 0 {
		return fault(rc)
	}
	return reset_hard(repo, &oid)
}

// reset_hard moves the current branch to id, index and working tree with it.
@(private)
reset_hard :: proc(repo: Repo, id: ^git_oid) -> Error {
	target: ^git_object
	if rc := git_object_lookup(&target, repo.ptr, id, GIT_OBJECT_COMMIT); rc < 0 {
		return fault(rc)
	}
	defer git_object_free(target)
	if rc := git_reset(repo.ptr, target, GIT_RESET_HARD, nil); rc < 0 {
		return fault(rc)
	}
	return nil
}

// signature is sig, or the repository's identity when sig is zero.
@(private)
signature :: proc(repo: Repo, sig: Signature) -> (out: ^git_signature, err: Error) {
	reject_nul("signature", sig.name, sig.email) or_return
	if sig == {} {
		if rc := git_signature_default(&out, repo.ptr); rc < 0 {
			return nil, fault(rc)
		}
	} else if rc := git_signature_now(&out, cstr(sig.name), cstr(sig.email)); rc < 0 {
		return nil, fault(rc)
	}
	return
}

// rebase takes the current branch's commits that onto ("origin/main")
// lacks and replays them, oldest first, on top of onto, then moves the
// branch and the working tree there, as `git rebase onto` does: merge
// commits are dropped, a commit whose change onto already has is
// skipped, and a branch onto adds nothing to is left alone. It replays in memory first, so a commit that conflicts
// changes nothing: conflicts names the paths, and the branch stays where
// it was. Anything uncommitted fails it with GIT_EUNCOMMITTED. committer
// is who replays them; zero is the repository's identity. Each commit
// keeps its author and message.
rebase :: proc(repo: Repo, onto: string, committer := Signature{}, allocator := context.allocator) -> (conflicts: []string, err: Error) {
	base_id, ok := resolve_oid(repo, onto)
	if !ok {
		return nil, Fault{GIT_ENOTFOUND, strings.clone(fmt.tprintf("no commit named %q", onto))}
	}
	if git_repository_head_unborn(repo.ptr) != 0 {
		return nil, reset_hard(repo, &base_id)
	}
	// onto has nothing the branch lacks: the branch is already on it, and
	// replaying would only rewrite commits that need nothing.
	if behind := count(repo, "HEAD", onto) or_return; behind == 0 {
		return nil, nil
	}
	entries := status(repo, context.temp_allocator) or_return
	if len(entries) > 0 {
		return nil, Fault{GIT_EUNCOMMITTED, strings.clone("uncommitted changes would be overwritten; commit or put them aside first")}
	}
	sig := signature(repo, committer) or_return
	defer git_signature_free(sig)
	tip, _ := resolve_oid(repo, "HEAD")

	walk: ^git_revwalk
	if rc := git_revwalk_new(&walk, repo.ptr); rc < 0 {
		return nil, fault(rc)
	}
	defer git_revwalk_free(walk)
	git_revwalk_sorting(walk, GIT_SORT_TOPOLOGICAL | GIT_SORT_TIME | GIT_SORT_REVERSE)
	git_revwalk_push(walk, &tip)
	git_revwalk_hide(walk, &base_id)
	todo := make([dynamic]git_oid, context.temp_allocator)
	oid: git_oid
	for git_revwalk_next(&oid, walk) == 0 {
		append(&todo, oid)
	}
	if len(todo) == 0 {
		// Nothing of ours to replay: onto already has it all.
		return nil, reset_hard(repo, &base_id)
	}

	base: ^git_commit
	if rc := git_commit_lookup(&base, repo.ptr, &base_id); rc < 0 {
		return nil, fault(rc)
	}
	defer git_commit_free(base)
	for &id in todo {
		cm: ^git_commit
		if rc := git_commit_lookup(&cm, repo.ptr, &id); rc < 0 {
			return nil, fault(rc)
		}
		defer git_commit_free(cm)
		if git_commit_parentcount(cm) > 1 {
			continue
		}
		index: ^git_index
		if rc := git_cherrypick_commit(&index, repo.ptr, cm, base, 0, nil); rc < 0 {
			return nil, fault(rc)
		}
		defer git_index_free(index)
		if git_index_has_conflicts(index) != 0 {
			return index_conflicts(index, allocator), nil
		}
		tree_id: git_oid
		if rc := git_index_write_tree_to(&tree_id, index, repo.ptr); rc < 0 {
			return nil, fault(rc)
		}
		base_tree: ^git_tree
		if rc := git_commit_tree(&base_tree, base); rc < 0 {
			return nil, fault(rc)
		}
		same := git_tree_id(base_tree)^ == tree_id
		git_tree_free(base_tree)
		if same {
			continue
		}
		tree: ^git_tree
		if rc := git_tree_lookup(&tree, repo.ptr, &tree_id); rc < 0 {
			return nil, fault(rc)
		}
		defer git_tree_free(tree)
		parents := [1]^git_commit{base}
		next: git_oid
		if rc := git_commit_create(&next, repo.ptr, nil, git_commit_author(cm), sig, nil, git_commit_message_raw(cm), tree, 1, raw_data(parents[:])); rc < 0 {
			return nil, fault(rc)
		}
		replayed: ^git_commit
		if rc := git_commit_lookup(&replayed, repo.ptr, &next); rc < 0 {
			return nil, fault(rc)
		}
		git_commit_free(base)
		base = replayed
	}
	return nil, reset_hard(repo, git_commit_id(base))
}

// index_conflicts is each path with a conflict in index, once.
@(private)
index_conflicts :: proc(index: ^git_index, allocator := context.allocator) -> []string {
	out := make([dynamic]string, allocator)
	for i in 0 ..< int(git_index_entrycount(index)) {
		e := git_index_get_byindex(index, c.size_t(i))
		if e == nil || (e.flags & GIT_INDEX_STAGE_MASK) == 0 {
			continue
		}
		p := string(e.path)
		if len(out) > 0 && out[len(out) - 1] == p {
			continue
		}
		append(&out, strings.clone(p, allocator))
	}
	return out[:]
}

// stash puts away everything uncommitted, untracked files included, and
// leaves the working tree as HEAD has it, `git stash -u`. stashed is
// false when there was nothing to put away.
stash :: proc(repo: Repo, message: string, sig := Signature{}) -> (stashed: bool, err: Error) {
	reject_nul("message", message) or_return
	who := signature(repo, sig) or_return
	defer git_signature_free(who)
	oid: git_oid
	rc := git_stash_save(&oid, repo.ptr, who, cstr(message), GIT_STASH_INCLUDE_UNTRACKED)
	if rc == GIT_ENOTFOUND {
		return false, nil
	}
	if rc < 0 {
		return false, fault(rc)
	}
	return true, nil
}

// unstash brings back what the newest stash put away and drops it, `git
// stash pop`. One that no longer applies cleanly is kept, and the error
// says so.
unstash :: proc(repo: Repo) -> Error {
	if rc := git_stash_pop(repo.ptr, 0, nil); rc < 0 {
		return fault(rc)
	}
	return nil
}

// set_timeouts bounds, for every fetch and push in the process, how long
// connecting may take and how long one read or write may wait. Zero
// leaves libgit2's default, which waits as long as the OS does.
set_timeouts :: proc(connect, io: time.Duration) {
	ready()
	if connect > 0 {
		git_libgit2_opts(GIT_OPT_SET_SERVER_CONNECT_TIMEOUT, c.int(time.duration_milliseconds(connect)))
	}
	if io > 0 {
		git_libgit2_opts(GIT_OPT_SET_SERVER_TIMEOUT, c.int(time.duration_milliseconds(io)))
	}
}
