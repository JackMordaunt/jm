package git

import "core:os"
import "core:strings"
import "core:testing"
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
