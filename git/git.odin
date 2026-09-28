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
	message: string,
	author:  Signature,
	at:      time.Time,
}

Remote :: struct {
	name, url: string,
}

// Sync is what pull did.
Sync :: enum u8 {
	Up_To_Date,
	Fast_Forwarded,
	Diverged, // the local branch has commits the remote lacks; nothing was changed
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

// fault reads libgit2's last error for a call that returned code.
@(private)
fault :: proc(code: c.int) -> Error {
	msg := "unknown error"
	if e := git_error_last(); e != nil && e.message != nil {
		msg = string(e.message)
	}
	return Fault{i32(code), strings.clone(msg)}
}

@(private)
cstr :: proc(s: string) -> cstring {
	return strings.clone_to_cstring(s, context.temp_allocator)
}

@(private)
oid_string :: proc(id: ^git_oid, allocator := context.allocator) -> string {
	return strings.clone(string(git_oid_tostr_s(id)), allocator)
}

// open opens the repository at path, a working tree or a bare repository.
open :: proc(path: string) -> (repo: Repo, err: Error) {
	ready()
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
	if rc := git_repository_init(&repo.ptr, cstr(path), c.uint(bare ? 1 : 0)); rc < 0 {
		return {}, fault(rc)
	}
	return
}

// clone fetches url into path, a new directory, and opens it.
clone :: proc(url, path: string) -> (repo: Repo, err: Error) {
	ready()
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
// libgit2's path order.
status :: proc(repo: Repo, allocator := context.allocator) -> (entries: []Entry, err: Error) {
	opts: git_status_options
	git_status_options_init(&opts, GIT_STATUS_OPTIONS_VERSION)
	opts.show = GIT_STATUS_SHOW_INDEX_AND_WORKDIR
	opts.flags = GIT_STATUS_OPT_INCLUDE_UNTRACKED | GIT_STATUS_OPT_RECURSE_UNTRACKED_DIRS | GIT_STATUS_OPT_RENAMES_HEAD_TO_INDEX | GIT_STATUS_OPT_SORT_CASE_SENSITIVELY
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
// all of them. An unborn branch logs nothing.
log :: proc(repo: Repo, limit := 0, allocator := context.allocator) -> (commits: []Commit, err: Error) {
	if git_repository_head_unborn(repo.ptr) != 0 {
		return nil, nil
	}
	walk: ^git_revwalk
	if rc := git_revwalk_new(&walk, repo.ptr); rc < 0 {
		return nil, fault(rc)
	}
	defer git_revwalk_free(walk)
	git_revwalk_sorting(walk, GIT_SORT_TIME)
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
		a := git_commit_author(cm)
		append(
			&out,
			Commit {
				id = oid_string(&oid, allocator),
				summary = strings.clone(string(git_commit_summary(cm)), allocator),
				message = strings.clone(string(git_commit_message(cm)), allocator),
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
	r: ^git_remote
	if rc := git_remote_create(&r, repo.ptr, cstr(name), cstr(url)); rc < 0 {
		return fault(rc)
	}
	git_remote_free(r)
	return nil
}

// remote_remove drops name and its tracking branches.
remote_remove :: proc(repo: Repo, name: string) -> Error {
	if rc := git_remote_delete(repo.ptr, cstr(name)); rc < 0 {
		return fault(rc)
	}
	return nil
}

// acquire is the credential callback every fetch and push installs: it
// answers with the token in the payload's Credentials when the remote
// takes a password, with the ssh agent when it takes a key, and with the
// platform default otherwise. Without a token it lets libgit2 carry on.
@(private)
acquire :: proc "c" (out: ^^git_credential, url, username_from_url: cstring, allowed: c.uint, payload: rawptr) -> c.int {
	creds := (^Credentials)(payload)
	if allowed & GIT_CREDENTIAL_USERPASS_PLAINTEXT != 0 && creds != nil && creds.token != "" {
		context = {}
		buf: [256]u8
		user := creds.username != "" ? creds.username : "git"
		return git_credential_userpass_plaintext_new(out, tmp_cstring(buf[:128], user), tmp_cstring(buf[128:], creds.token))
	}
	if allowed & GIT_CREDENTIAL_SSH_KEY != 0 {
		return git_credential_ssh_key_from_agent(out, username_from_url)
	}
	if allowed & GIT_CREDENTIAL_DEFAULT != 0 {
		return git_credential_default_new(out)
	}
	return GIT_PASSTHROUGH
}

// tmp_cstring copies s, NUL-terminated, into buf: for the callback above,
// which runs without a context to allocate from. A token longer than the
// buffer is cut, and fails authentication rather than overrunning.
@(private)
tmp_cstring :: proc "contextless" (buf: []u8, s: string) -> cstring {
	n := min(len(s), len(buf) - 1)
	copy(buf[:n], s[:n])
	buf[n] = 0
	return cstring(raw_data(buf))
}

// fetch brings remote's branches up to date under refs/remotes/<remote>.
fetch :: proc(repo: Repo, remote: string, creds := Credentials{}) -> Error {
	r: ^git_remote
	if rc := git_remote_lookup(&r, repo.ptr, cstr(remote)); rc < 0 {
		return fault(rc)
	}
	defer git_remote_free(r)
	creds := creds
	opts: git_fetch_options
	git_fetch_options_init(&opts, GIT_FETCH_OPTIONS_VERSION)
	opts.callbacks.credentials = acquire
	opts.callbacks.payload = &creds
	if rc := git_remote_fetch(r, nil, &opts, "fetch"); rc < 0 {
		return fault(rc)
	}
	return nil
}

// push sends branch (the current one by default) to remote, creating it
// there when it is new. A remote that has moved on refuses the push with
// GIT_ENONFASTFORWARD; pull first.
push :: proc(repo: Repo, remote: string, branch := "", creds := Credentials{}) -> Error {
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
	creds := creds
	opts: git_push_options
	git_push_options_init(&opts, GIT_PUSH_OPTIONS_VERSION)
	opts.callbacks.credentials = acquire
	opts.callbacks.payload = &creds
	refspec := fmt.tprintf("refs/heads/%s:refs/heads/%s", b, b)
	specs := strarray({refspec})
	if rc := git_remote_push(r, &specs, &opts); rc < 0 {
		return fault(rc)
	}
	return nil
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
// reports Diverged and is left as it was, for the caller to decide.
pull :: proc(repo: Repo, remote: string, creds := Credentials{}) -> (sync: Sync, err: Error) {
	if ferr := fetch(repo, remote, creds); ferr != nil {
		return .Up_To_Date, ferr
	}
	branch, _, born := head(repo, context.temp_allocator)
	if !born {
		// An empty clone-by-hand: take the remote's branch as ours.
		branch = "main"
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
// `git diff` prints, empty when nothing differs.
diff :: proc(repo: Repo, staged: bool, allocator := context.allocator) -> (patch: string, err: Error) {
	index: ^git_index
	if rc := git_repository_index(&index, repo.ptr); rc < 0 {
		return "", fault(rc)
	}
	defer git_index_free(index)
	opts: git_diff_options
	git_diff_options_init(&opts, GIT_DIFF_OPTIONS_VERSION)
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
