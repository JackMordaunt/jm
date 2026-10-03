# Git

`jm:git` is the git a shipped program carries with it: `just libgit2`
fetches libgit2 v1.9.7 into `build/src` and builds it into
`git/lib`, and the package links that archive when it exists and the
system libgit2 otherwise, so a machine with the distribution's package
tests without the CMake step. The archive is built with the platform's
own HTTPS (WinHTTP, SecureTransport, OpenSSL loaded at run time on Linux),
`USE_SSH=exec` so `git@` remotes go through the platform's ssh and agent,
and the bundled zlib, regex engine and HTTP parser. libgit2 runs no
hooks; a program that wants pre-commit checks runs them before `commit`.
`git/ffi_test.odin` pins every option struct's size and offsets against
what the C headers lay out, so a libgit2 bump that moves a field fails a
test instead of corrupting a stack.

**The network is tested by hand.** `tools/git-probe` is the run no test in
the repository can make: an anonymous HTTPS clone and fetch, a token
pulling from and pushing to a private remote (from an unborn branch, so
the remote is asked for its default branch), a push refused as
non-fast-forward, a wrong token refused with a plain message, and the
same repository over `git@` through the platform's ssh. It passed on
2026-09-28 against GitHub with the static Linux build, OpenSSL loaded at
run time. Run it again after a libgit2 bump or a change to the transport
options:

```
just libgit2
odin build tools/git-probe -collection:jm=. -out:build/debug/git-probe
build/debug/git-probe https://github.com/octocat/Hello-World.git \
    https://github.com/<you>/<throwaway>.git "$(gh auth token)" git@github.com:<you>/<throwaway>.git
```

`git/fuzz` is the suite: three properties, each case a fresh bare hub with
two clones on local paths. `sequence` draws any order of writes, adds,
commits, pushes, fetches and pulls across the clones and holds every step
against a model of the three trees and the commit history, so a push
succeeds exactly when the hub is behind, a pull fast-forwards exactly when
the clone is and refuses when work is uncommitted, and status is what the
trees say. `strings` sends a generated message, path and remote name
through and reads each back byte for byte, or sees the call refuse it: it
is why the wrapper refuses a string with a NUL in it rather than letting
the C boundary cut it short. `damaged` corrupts one file under `.git` and
asks every question; a Fault is a fine answer, a crash is not.
