# Git

**`jm:git` puts git inside your program, so it works on machines that have no
git installed.**

- **No git required.** libgit2 links statically, so a shipped binary carries
  its own git.
- **The everyday subset.** Open, init, clone, status, add, commit, log,
  remotes, fetch, push, pull and diff, for an application that keeps its data
  in a repository.
- **The platform's own security.** HTTPS uses the system's TLS, and `git@`
  remotes go through the system's ssh and agent.
- **Checked against a model.** A fuzz suite runs random sequences of writes,
  pushes and pulls across clones and holds every step against a model.

| At a glance | |
|---|---|
| Version | libgit2 **v1.9.7** |
| Licence | GPLv2 with a linking exception |
| Links | Statically from `git/lib`, else the system libgit2 |
| Builds with | `just libgit2` |

## Quick start

```odin
repo := must(git.open("notes"))
defer git.close(&repo)
must(git.add(repo, {"."}))
id := must(git.commit(repo, "notes: today's bullets"))
must(git.push(repo, "origin"))
```

## How it connects

| Remote | Goes through |
|---|---|
| HTTPS on Windows | WinHTTP |
| HTTPS on macOS | SecureTransport |
| HTTPS on Linux | OpenSSL, loaded at run time |
| `git@` | The platform's ssh and agent (`USE_SSH=exec`) |

> [!WARNING]
> libgit2 runs no hooks. A program that wants pre-commit checks runs them
> itself before `commit`.

<details>
<summary>Under the hood: build and ABI checks</summary>

`just libgit2` fetches libgit2 v1.9.7 into `build/src` and builds it into
`git/lib`. The package links that archive when it exists and the system
libgit2 otherwise, so a machine with the distribution's package tests without
the CMake step.

The archive is built with the platform's own HTTPS (WinHTTP, SecureTransport,
OpenSSL loaded at run time on Linux), `USE_SSH=exec` so `git@` remotes go
through the platform's ssh and agent, and the bundled zlib, regex engine and
HTTP parser.

`git/ffi_test.odin` pins every option struct's size and offsets against what
the C headers lay out. A libgit2 bump that moves a field fails a test instead
of corrupting a stack.

</details>

## The network is tested by hand

`tools/git-probe` makes the runs no test in the repository can make, against a
real remote:

- an anonymous HTTPS clone and fetch;
- a token pulling from and pushing to a private remote, from an unborn branch,
  so the remote is asked for its default branch;
- a push refused as non-fast-forward;
- a wrong token, refused with a plain message;
- the same repository over `git@` through the platform's ssh.

It passed on 2026-09-28 against GitHub with the static Linux build, OpenSSL
loaded at run time. Run it again after a libgit2 bump or a change to the
transport options:

```
just libgit2
odin build tools/git-probe -collection:jm=. -out:build/debug/git-probe
build/debug/git-probe https://github.com/octocat/Hello-World.git \
    https://github.com/<you>/<throwaway>.git "$(gh auth token)" git@github.com:<you>/<throwaway>.git
```

## Tested by fuzzing

`git/fuzz` is the suite: three properties, each case a fresh bare hub with two
clones on local paths.

| Property | What it checks |
|---|---|
| `sequence` | Any order of writes, adds, commits, pushes, fetches and pulls across the clones, each step held against a model of the three trees and the commit history |
| `strings` | A generated message, path and remote name, read back byte for byte, or refused |
| `damaged` | One corrupted file under `.git`, then every question; a Fault is a fine answer, a crash is not |

<details>
<summary>Under the hood: what the model holds the suite to</summary>

Under `sequence`, a push succeeds exactly when the hub is behind. A pull
fast-forwards exactly when the clone is, and refuses when work is uncommitted.
Status is what the trees say.

`strings` is why the wrapper refuses a string with a NUL in it, rather than
letting the C boundary cut it short.

</details>

## See also

- [Fuzzing](fuzzing.md): every property suite and what they found
- [Packages](packages.md): every package in jm
- [Building and testing](building.md): the `just` recipes, `libgit2` among them
