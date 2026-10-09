package git

import "core:os"
import "core:strings"
import "core:testing"
import "core:time"
import "jm:path"

SIG :: Signature{"Test Author", "test@example.com"}

// temp_root is a fresh temporary directory, removed when the test ends.
@(private = "file")
temp_root :: proc(t: ^testing.T) -> string {
	dir, err := path.temp_dir("jm-git-")
	testing.expect(t, err == nil, "temp dir")
	return dir
}

@(private = "file")
write :: proc(t: ^testing.T, p, body: string) {
	testing.expect(t, path.write(p, body) == nil, p)
}

// A repository from nothing: init, add, commit, and the log and status
// that follow, then an edit seen unstaged, staged, and committed.
@(test)
init_add_commit_log :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	dir := temp_root(t)
	defer os.remove_all(dir)
	repo, err := init(dir)
	testing.expect(t, err == nil, "init")
	defer close(&repo)

	_, _, born := head(repo)
	testing.expect(t, !born, "a new repository has no head")
	empty, lerr := log(repo)
	testing.expect(t, lerr == nil && len(empty) == 0, "an unborn branch logs nothing")

	write(t, path.join(dir, "notes.md"), "- **a** — one — 2026-09-28\n")
	st, serr := status(repo)
	testing.expect(t, serr == nil, "status")
	testing.expect_value(t, len(st), 1)
	testing.expect_value(t, st[0].path, "notes.md")
	testing.expect_value(t, st[0].worktree, Change.New)
	testing.expect_value(t, st[0].index, Change.None)

	testing.expect(t, add(repo, {"."}) == nil, "add")
	st, _ = status(repo)
	testing.expect_value(t, st[0].index, Change.New)
	patch, derr := diff(repo, staged = true)
	testing.expect(t, derr == nil && strings.contains(patch, "+- **a**"), "the staged diff shows the new line")

	id, cerr := commit(repo, "notes: first bullet", SIG)
	testing.expect(t, cerr == nil, "commit")
	testing.expect_value(t, len(id), 40)
	branch, head_id, ok := head(repo)
	testing.expect(t, ok && head_id == id, "head is the commit")
	testing.expect(t, branch == "main" || branch == "master", branch)
	st, _ = status(repo)
	testing.expect_value(t, len(st), 0)

	write(t, path.join(dir, "notes.md"), "- **a** — one — 2026-09-28\n- **b** — two — 2026-09-28\n")
	st, _ = status(repo)
	testing.expect_value(t, st[0].worktree, Change.Modified)
	patch, _ = diff(repo, staged = false)
	testing.expect(t, strings.contains(patch, "+- **b**"), "the unstaged diff shows the edit")
	testing.expect(t, add(repo, {"notes.md"}) == nil, "add the edit")
	_, cerr = commit(repo, "notes: second bullet", SIG)
	testing.expect(t, cerr == nil, "second commit")

	commits, lerr2 := log(repo)
	testing.expect(t, lerr2 == nil, "log")
	testing.expect_value(t, len(commits), 2)
	testing.expect_value(t, commits[0].summary, "notes: second bullet")
	testing.expect_value(t, commits[1].summary, "notes: first bullet")
	testing.expect_value(t, commits[0].author.email, "test@example.com")
	one, _ := log(repo, limit = 1)
	testing.expect_value(t, len(one), 1)
}

// Two clones of one bare remote: push from one, clone the other, then a
// second push and a pull that fast-forwards; a local commit makes the
// next pull report Diverged and leaves the branch alone.
@(test)
push_clone_pull :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	root := temp_root(t)
	defer os.remove_all(root)
	bare := path.join(root, "remote.git")
	hub, err := init(bare, bare = true)
	testing.expect(t, err == nil, "init bare")
	close(&hub)

	a_dir := path.join(root, "a")
	a, aerr := init(a_dir)
	testing.expect(t, aerr == nil, "init a")
	defer close(&a)
	write(t, path.join(a_dir, "f.md"), "one\n")
	testing.expect(t, add(a, {"."}) == nil, "add")
	_, cerr := commit(a, "f: one", SIG)
	testing.expect(t, cerr == nil, "commit a")
	testing.expect(t, remote_add(a, "origin", bare) == nil, "remote add")
	rs, rerr := remotes(a)
	testing.expect(t, rerr == nil && len(rs) == 1 && rs[0].name == "origin" && rs[0].url == bare, "remotes lists it")
	testing.expect(t, push(a, "origin") == nil, "push")

	b_dir := path.join(root, "b")
	b, berr := clone(bare, b_dir)
	testing.expect(t, berr == nil, "clone")
	defer close(&b)
	bl, _ := log(b)
	testing.expect_value(t, len(bl), 1)
	testing.expect_value(t, bl[0].summary, "f: one")

	write(t, path.join(a_dir, "f.md"), "one\ntwo\n")
	testing.expect(t, add(a, {"."}) == nil, "add two")
	_, cerr = commit(a, "f: two", SIG)
	testing.expect(t, cerr == nil, "commit two")
	testing.expect(t, push(a, "origin") == nil, "push two")

	testing.expect(t, fetch(b, "origin") == nil, "fetch")
	ahead, behind, aberr := ahead_behind(b, "origin")
	testing.expect(t, aberr == nil && ahead == 0 && behind == 1, "b is one behind")
	sync, perr := pull(b, "origin")
	testing.expect(t, perr == nil, "pull")
	testing.expect_value(t, sync, Sync.Fast_Forwarded)
	body, _ := path.read(path.join(b_dir, "f.md"))
	testing.expect_value(t, body, "one\ntwo\n")
	sync, _ = pull(b, "origin")
	testing.expect_value(t, sync, Sync.Up_To_Date)

	write(t, path.join(b_dir, "g.md"), "mine\n")
	testing.expect(t, add(b, {"."}) == nil, "add g")
	_, cerr = commit(b, "g: mine", SIG)
	testing.expect(t, cerr == nil, "commit g")
	write(t, path.join(a_dir, "f.md"), "one\ntwo\nthree\n")
	testing.expect(t, add(a, {"."}) == nil, "add three")
	_, cerr = commit(a, "f: three", SIG)
	testing.expect(t, cerr == nil, "commit three")
	testing.expect(t, push(a, "origin") == nil, "push three")
	sync, perr = pull(b, "origin")
	testing.expect(t, perr == nil, "pull diverged")
	testing.expect_value(t, sync, Sync.Diverged)
	bl, _ = log(b)
	testing.expect_value(t, bl[0].summary, "g: mine")
	ahead, behind, _ = ahead_behind(b, "origin")
	testing.expect(t, ahead == 1 && behind == 1, "one each way")
	perr = push(b, "origin")
	pf, refused := perr.(Fault)
	testing.expect(t, refused && pf.code == GIT_ENONFASTFORWARD, "a diverged push is refused as non-fast-forward")

	testing.expect(t, remote_remove(a, "origin") == nil, "remote remove")
	rs, _ = remotes(a)
	testing.expect_value(t, len(rs), 0)
}

// A failed call carries libgit2's own message.
@(test)
errors_carry_the_message :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	_, err := open("/nonexistent/jm-git-test")
	f, is_fault := err.(Fault)
	testing.expect(t, is_fault, "open of nothing fails")
	testing.expect(t, f.code < 0 && len(f.message) > 0, f.message)
}

// The credential callback hands over the token once, refuses to repeat
// a token the remote rejected, and refuses one it cannot hold.
@(test)
acquire_answers_once :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	ready_for_test()
	ask := Ask{creds = {token = "tok"}}
	cred: ^git_credential
	testing.expect_value(t, acquire(&cred, "https://x", nil, GIT_CREDENTIAL_USERPASS_PLAINTEXT, &ask), 0)
	testing.expect(t, cred != nil, "a credential was made")
	git_credential_free(cred)
	cred = nil
	testing.expect_value(t, acquire(&cred, "https://x", nil, GIT_CREDENTIAL_USERPASS_PLAINTEXT, &ask), -1)
	testing.expect(t, cred == nil, "no second credential")
	testing.expect_value(t, string(git_error_last().message), "the remote refused the token")

	long := Ask{creds = {token = strings.repeat("x", TOKEN_MAX + 1)}}
	testing.expect_value(t, acquire(&cred, "https://x", nil, GIT_CREDENTIAL_USERPASS_PLAINTEXT, &long), -1)
	testing.expect(t, strings.has_prefix(string(git_error_last().message), "credential too long"), "the long token is named")

	none: Ask
	testing.expect_value(t, acquire(&cred, "https://x", nil, GIT_CREDENTIAL_USERPASS_PLAINTEXT, &none), GIT_PASSTHROUGH)
}

// A pull into a repository with no commit takes the remote's default
// branch, and a remote with nothing on it is simply up to date.
@(test)
pull_from_unborn :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	root := temp_root(t)
	defer os.remove_all(root)
	bare := path.join(root, "hub.git")
	hub, err := init(bare, bare = true)
	testing.expect(t, err == nil, "init bare")
	close(&hub)

	empty_dir := path.join(root, "empty")
	empty, eerr := init(empty_dir)
	testing.expect(t, eerr == nil, "init")
	defer close(&empty)
	testing.expect(t, remote_add(empty, "origin", bare) == nil, "remote add")
	sync, perr := pull(empty, "origin")
	testing.expect(t, perr == nil, "pull from an empty remote")
	testing.expect_value(t, sync, Sync.Up_To_Date)

	src_dir := path.join(root, "src")
	src, serr := init(src_dir)
	testing.expect(t, serr == nil, "init src")
	defer close(&src)
	write(t, path.join(src_dir, "a.md"), "a\n")
	testing.expect(t, add(src, {"."}) == nil, "add")
	_, cerr := commit(src, "a", SIG)
	testing.expect(t, cerr == nil, "commit")
	testing.expect(t, remote_add(src, "origin", bare) == nil, "remote add src")
	testing.expect(t, push(src, "origin") == nil, "push")

	sync, perr = pull(empty, "origin")
	testing.expect(t, perr == nil, "pull from unborn onto the pushed branch")
	testing.expect_value(t, sync, Sync.Fast_Forwarded)
	branch, _, born := head(empty)
	want, _, _ := head(src)
	testing.expect(t, born && branch == want, "the unborn repository took the remote's branch name")
	body, _ := path.read(path.join(empty_dir, "a.md"))
	testing.expect_value(t, body, "a\n")
}

// commit_file writes body to name in the repository at dir and commits it.
@(private = "file")
commit_file :: proc(t: ^testing.T, repo: Repo, dir, name, body, msg: string) -> string {
	write(t, path.join(dir, name), body)
	testing.expect(t, add(repo, {"."}) == nil, "add")
	id, err := commit(repo, msg, SIG)
	testing.expect(t, err == nil, msg)
	return id
}

// What a repository says about itself: its settings, a file as a commit
// had it, how many commits lie between two, one commit's change, and
// opening it from a directory inside.
@(test)
settings_files_counts_and_changes :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	dir := temp_root(t)
	defer os.remove_all(dir)
	repo, err := init(dir)
	testing.expect(t, err == nil, "init")
	defer close(&repo)

	_, found := config_get(repo, "brain.unset")
	testing.expect(t, !found, "an unset key is not found")
	testing.expect(t, config_set(repo, "core.hooksPath", "/x/hooks") == nil, "config set")
	v, vfound := config_get(repo, "core.hooksPath")
	testing.expect(t, vfound && v == "/x/hooks", v)

	n, cerr := count(repo, "", "HEAD")
	testing.expect(t, cerr == nil && n == 0, "an unborn branch counts nothing")
	first := commit_file(t, repo, dir, "a.md", "one\n", "a: one")
	path.mkdirs(path.join(dir, "sub"))
	commit_file(t, repo, dir, "sub/b.txt", "b\n", "b: add")
	commit_file(t, repo, dir, "a.md", "one\ntwo\n", "a: two")

	id, ok := resolve(repo, "HEAD~2")
	testing.expect(t, ok && id == first, "HEAD~2 is the first commit")
	short, sok := resolve(repo, first[:7])
	testing.expect(t, sok && short == first, "a short id resolves")
	_, nok := resolve(repo, "nope")
	testing.expect(t, !nok, "a name of nothing does not resolve")

	body, bfound := read_file(repo, "HEAD~1", "a.md")
	testing.expect(t, bfound && body == "one\n", body)
	_, gone := read_file(repo, "HEAD", "missing.md")
	testing.expect(t, !gone, "a missing file is not found")

	n, cerr = count(repo, "", "HEAD")
	testing.expect(t, cerr == nil && n == 3, "three commits")
	n, _ = count(repo, first, "HEAD")
	testing.expect_value(t, n, 2)
	recent, _ := log(repo, since = time.time_add(time.now(), -time.Hour))
	testing.expect_value(t, len(recent), 3)
	none, _ := log(repo, since = time.time_add(time.now(), time.Hour))
	testing.expect_value(t, len(none), 0)

	files, patch, xerr := changes(repo, "HEAD", context_lines = 0)
	testing.expect(t, xerr == nil && len(files) == 1 && files[0] == "a.md", "the last commit touched a.md")
	testing.expect(t, strings.contains(patch, "+two") && !strings.contains(patch, "\n one\n"), patch)
	files, _, _ = changes(repo, first)
	testing.expect(t, len(files) == 1 && files[0] == "a.md", "a root commit is diffed against nothing")
	files, _, _ = changes(repo, "HEAD~1", paths = {"*.md"})
	testing.expect_value(t, len(files), 0)

	sub, derr := discover(path.join(dir, "sub"))
	testing.expect(t, derr == nil, "discover from a subdirectory")
	_, sub_head, _ := head(sub)
	_, top_head, _ := head(repo)
	testing.expect(t, sub_head == top_head, "the subdirectory's repository is this one")
	close(&sub)
}

// What is staged can be read as a patch limited to some paths and framed
// by no context, and put back without touching the working tree.
@(test)
diff_paths_and_unstage :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	dir := temp_root(t)
	defer os.remove_all(dir)
	repo, err := init(dir)
	testing.expect(t, err == nil, "init")
	defer close(&repo)
	path.mkdirs(path.join(dir, "AI"))
	commit_file(t, repo, dir, "AI/m.md", "a\nb\nc\n", "start")
	write(t, path.join(dir, "AI", "m.md"), "a\nb\nc\nd\n")
	write(t, path.join(dir, "x.txt"), "x\n")
	testing.expect(t, add(repo, {"."}) == nil, "add")

	patch, derr := diff(repo, staged = true, context_lines = 0, paths = {"*.md"})
	testing.expect(t, derr == nil, "diff")
	testing.expect(t, strings.contains(patch, "+++ b/AI/m.md") && strings.contains(patch, "+d"), patch)
	testing.expect(t, !strings.contains(patch, "\n c\n") && !strings.contains(patch, "x.txt"), patch)

	testing.expect(t, unstage(repo) == nil, "unstage")
	patch, _ = diff(repo, staged = true)
	testing.expect_value(t, patch, "")
	body, _ := path.read(path.join(dir, "x.txt"))
	testing.expect_value(t, body, "x\n")
}

// Two machines that both wrote: the one behind replays its commit on
// top of the other's, and a commit that cannot be replayed cleanly
// changes nothing and names the file.
@(test)
rebase_replays_or_names_the_conflict :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	root := temp_root(t)
	defer os.remove_all(root)
	bare := path.join(root, "hub.git")
	hub, _ := init(bare, bare = true)
	close(&hub)
	a_dir := path.join(root, "a")
	a, _ := init(a_dir)
	defer close(&a)
	commit_file(t, a, a_dir, "f.md", "1\n2\n3\n", "start")
	remote_add(a, "origin", bare)
	testing.expect(t, push(a, "origin") == nil, "push start")
	b_dir := path.join(root, "b")
	b, berr := clone(bare, b_dir)
	testing.expect(t, berr == nil, "clone")
	defer close(&b)

	commit_file(t, a, a_dir, "f.md", "1\n2\n3\nfrom a\n", "a: end")
	testing.expect(t, push(a, "origin") == nil, "push a")
	commit_file(t, b, b_dir, "g.md", "from b\n", "b: g")
	testing.expect(t, fetch(b, "origin") == nil, "fetch")
	branch, _, _ := head(b)
	onto := strings.concatenate({"origin/", branch})
	conflicts, rerr := rebase(b, onto, SIG)
	testing.expect(t, rerr == nil && len(conflicts) == 0, "a clean replay")
	bl, _ := log(b)
	testing.expect(t, len(bl) == 3 && bl[0].summary == "b: g" && bl[1].summary == "a: end", "b's commit sits on a's")
	testing.expect_value(t, bl[0].author.name, SIG.name)
	f, _ := path.read(path.join(b_dir, "f.md"))
	testing.expect_value(t, f, "1\n2\n3\nfrom a\n")
	n, _ := count(b, onto, "HEAD")
	testing.expect_value(t, n, 1)
	testing.expect(t, push(b, "origin") == nil, "the replayed branch pushes")
	_, pushed, _ := head(b)
	conflicts, rerr = rebase(b, onto, SIG)
	_, still, _ := head(b)
	testing.expect(t, rerr == nil && still == pushed, "a branch onto adds nothing to is left alone")

	// Both change the same line: the replay stops before it starts.
	sync, perr := pull(a, "origin")
	testing.expect(t, perr == nil && sync == .Fast_Forwarded, "a takes b's commit")
	commit_file(t, a, a_dir, "f.md", "1\nA\n3\nfrom a\n", "a: two")
	testing.expect(t, push(a, "origin") == nil, "push a's two")
	_, before, _ := head(b)
	commit_file(t, b, b_dir, "f.md", "1\nB\n3\nfrom a\n", "b: two")
	_, mine, _ := head(b)
	testing.expect(t, mine != before, "b committed")
	testing.expect(t, fetch(b, "origin") == nil, "fetch two")
	conflicts, rerr = rebase(b, onto, SIG)
	testing.expect(t, rerr == nil && len(conflicts) == 1 && conflicts[0] == "f.md", "the conflict is named")
	_, after, _ := head(b)
	testing.expect_value(t, after, mine)
	f, _ = path.read(path.join(b_dir, "f.md"))
	testing.expect_value(t, f, "1\nB\n3\nfrom a\n")
	st, _ := status(b)
	testing.expect_value(t, len(st), 0)
}

// Uncommitted work put aside and brought back, untracked files included;
// a branch taken from a commit, the working tree with it.
@(test)
stash_and_checkout :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	dir := temp_root(t)
	defer os.remove_all(dir)
	repo, _ := init(dir)
	defer close(&repo)
	first := commit_file(t, repo, dir, "a.md", "one\n", "one")
	commit_file(t, repo, dir, "a.md", "one\ntwo\n", "two")

	stashed, serr := stash(repo, "aside", SIG)
	testing.expect(t, serr == nil && !stashed, "a clean tree has nothing to put aside")
	write(t, path.join(dir, "a.md"), "edited\n")
	write(t, path.join(dir, "new.md"), "new\n")
	stashed, serr = stash(repo, "aside", SIG)
	testing.expect(t, serr == nil && stashed, "stash")
	st, _ := status(repo)
	testing.expect_value(t, len(st), 0)
	testing.expect(t, unstash(repo) == nil, "unstash")
	body, _ := path.read(path.join(dir, "a.md"))
	testing.expect_value(t, body, "edited\n")
	body, _ = path.read(path.join(dir, "new.md"))
	testing.expect_value(t, body, "new\n")

	testing.expect(t, checkout(repo, "old", first) == nil, "checkout -f -B old first")
	branch, id, _ := head(repo)
	testing.expect(t, branch == "old" && id == first, branch)
	body, _ = path.read(path.join(dir, "a.md"))
	testing.expect_value(t, body, "one\n")
}
