// git-probe is the manual run of jm:git against real remotes, the part no
// test in the repository can reach: HTTPS through the platform's TLS,
// a token answering a private remote, and ssh:// through the platform's
// ssh. Each step prints PASS or FAIL with libgit2's message, and the
// process exits 1 if anything failed. Run it against the static build
// (`just libgit2` first) since that is the one a shipped program carries.
//
//	git-probe https://github.com/octocat/Hello-World.git
//	git-probe <public https url> <private https url> <token> [<ssh url of the same private repo>]
//
// With a private URL and token it commits into the private repository,
// so give it a throwaway one. GITHUB_TOKEN or `gh auth token` is a fine
// source for the token.
package main

import "core:fmt"
import "core:os"
import "jm:git"
import "jm:path"

failed := 0

report :: proc(step: string, err: git.Error, extra := "") {
	if err == nil {
		fmt.printfln("PASS  %s%s", step, extra)
	} else {
		failed += 1
		fmt.printfln("FAIL  %s: %v", step, err)
	}
}

main :: proc() {
	if len(os.args) < 2 {
		fmt.eprintln("usage: git-probe <public https url> [<private https url> <token> [<ssh url>]]")
		os.exit(2)
	}
	os.exit(run())
}

// run is the whole probe; it returns the exit code so main's os.exit
// comes after every deferred close and the work directory's removal.
run :: proc() -> int {
	public := os.args[1]
	root, terr := path.temp_dir("git-probe-")
	if terr != nil {
		fmt.eprintln("temp dir:", terr)
		return 1
	}
	defer os.remove_all(root)
	fmt.printfln("work dir %s", root)

	// 1. HTTPS, anonymous: clone a public repository, then fetch it again.
	{
		pub, err := git.clone(public, path.join(root, "public"))
		report("https clone (anonymous)", err)
		if err == nil {
			defer git.close(&pub)
			commits, lerr := git.log(pub, limit = 3)
			report("log of the clone", lerr, fmt.tprintf("  %d commits read, newest %q", len(commits), len(commits) > 0 ? commits[0].summary : ""))
			report("https fetch (anonymous)", git.fetch(pub, "origin"))
			a, b, aerr := git.ahead_behind(pub, "origin")
			report("ahead/behind after fetch", aerr, fmt.tprintf("  %d ahead, %d behind", a, b))
		}
	}

	if len(os.args) < 4 {
		return summary()
	}
	private, token := os.args[2], os.args[3]
	creds := git.Credentials{token = token}
	sig := git.Signature{"git-probe", "git-probe@example.com"}

	// 2. HTTPS with a token: a repository made by hand, pointed at the
	//    private remote, pulled from unborn (which asks the remote for its
	//    default branch), committed to and pushed; then a second copy
	//    pulls what the first pushed.
	one_dir := path.join(root, "one")
	one, ierr := git.init(one_dir)
	report("init", ierr)
	if ierr != nil {
		return summary()
	}
	defer git.close(&one)
	report("remote add (https)", git.remote_add(one, "origin", private))
	sync, perr := git.pull(one, "origin", creds)
	report("https pull with token from an unborn branch", perr, fmt.tprintf("  %v", sync))
	body := fmt.tprintf("- **git-probe** — pushed over https by jm:git — %s\n", private)
	if werr := path.write(path.join(one_dir, "PROBE.md"), body); werr != nil {
		fmt.println("FAIL  write:", werr)
		failed += 1
	}
	report("add", git.add(one, {"."}))
	id, cerr := git.commit(one, "git-probe: https push", sig)
	report("commit", cerr, fmt.tprintf("  %s", id))
	report("https push with token", git.push(one, "origin", creds = creds))

	two_dir := path.join(root, "two")
	two, ierr2 := git.init(two_dir)
	report("init the second copy", ierr2)
	if ierr2 == nil {
		defer git.close(&two)
		report("remote add (https), second copy", git.remote_add(two, "origin", private))
		sync2, perr2 := git.pull(two, "origin", creds)
		report("https pull of what was pushed", perr2, fmt.tprintf("  %v", sync2))
		got, rerr := path.read(path.join(two_dir, "PROBE.md"))
		if rerr != nil || got != body {
			failed += 1
			fmt.printfln("FAIL  the pulled file differs: %v %q", rerr, got)
		} else {
			fmt.println("PASS  the pulled file is the one pushed")
		}
		report("https push refused as non-fast-forward when behind", expect_nonff(one, one_dir, two, two_dir, sig, creds))
	}

	// 3. A wrong token is refused, not hung, and says so.
	{
		bad_dir := path.join(root, "bad")
		bad, berr := git.init(bad_dir)
		if berr == nil {
			defer git.close(&bad)
			git.remote_add(bad, "origin", private)
			ferr := git.fetch(bad, "origin", {token = "not-a-token"})
			if f, is_fault := ferr.(git.Fault); is_fault {
				fmt.printfln("PASS  a wrong token is refused: %s", f.message)
			} else {
				failed += 1
				fmt.println("FAIL  a wrong token was accepted")
			}
		}
	}

	// 4. SSH through the platform's ssh binary: fetch and push the same
	//    repository over git@ or ssh://.
	if len(os.args) >= 5 {
		ssh_url := os.args[4]
		three_dir := path.join(root, "three")
		three, ierr3 := git.init(three_dir)
		if ierr3 == nil {
			defer git.close(&three)
			report("remote add (ssh)", git.remote_add(three, "origin", ssh_url))
			sync3, perr3 := git.pull(three, "origin")
			report("ssh pull from an unborn branch", perr3, fmt.tprintf("  %v", sync3))
			path.write(path.join(three_dir, "SSH.md"), "pushed over ssh by jm:git\n")
			report("add over ssh copy", git.add(three, {"."}))
			_, cerr3 := git.commit(three, "git-probe: ssh push", sig)
			report("commit", cerr3)
			report("ssh push", git.push(three, "origin"))
			report("ssh fetch", git.fetch(three, "origin"))
		}
	}
	return summary()
}

// expect_nonff makes `two` a commit behind by committing in `one` and
// pushing, then commits in `two` and pushes: that push must be refused
// with GIT_ENONFASTFORWARD.
expect_nonff :: proc(one: git.Repo, one_dir: string, two: git.Repo, two_dir: string, sig: git.Signature, creds: git.Credentials) -> git.Error {
	if err := path.write(path.join(one_dir, "SECOND.md"), "second\n"); err != nil {
		return git.Fault{-1, "could not write in one"}
	}
	if err := git.add(one, {"."}); err != nil {
		return err
	}
	if _, err := git.commit(one, "git-probe: second", sig); err != nil {
		return err
	}
	if err := git.push(one, "origin", creds = creds); err != nil {
		return err
	}
	path.write(path.join(two_dir, "MINE.md"), "mine\n")
	if err := git.add(two, {"."}); err != nil {
		return err
	}
	if _, err := git.commit(two, "git-probe: mine", sig); err != nil {
		return err
	}
	err := git.push(two, "origin", creds = creds)
	if f, is_fault := err.(git.Fault); is_fault && f.code == git.GIT_ENONFASTFORWARD {
		return nil
	}
	if err == nil {
		return git.Fault{-1, "a non-fast-forward push was accepted"}
	}
	return err
}

summary :: proc() -> int {
	if failed > 0 {
		fmt.printfln("%d step(s) failed", failed)
		return 1
	}
	fmt.println("all steps passed")
	return 0
}
