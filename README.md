<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="branding/hero-dark.svg">
    <img src="branding/hero-light.svg" alt="jm" width="360">
  </picture>
</p>

<p align="center"><b>Odin for everything you used to reach for Python to do.</b><br>
Scripts that start like bash and run like C. Batteries linked in. A UI toolkit you can test without a window.</p>

<p align="center">
  <a href="docs/scripts.md">Scripts</a> ·
  <a href="docs/packages.md">Packages</a> ·
  <a href="docs/ui.md">UI</a> ·
  <a href="docs/streams.md">Streams</a> ·
  <a href="docs/fuzzing.md">Fuzzing</a> ·
  <a href="docs/setup.md">Setup</a>
</p>

```odin
#!/usr/bin/env odin-run
package main

import "core:fmt"
import "jm:prelude"
import "jm:sh"
import "jm:path"

must :: prelude.must

main :: proc() {
	context = prelude.init()
	branch := must(sh.out("git rev-parse --abbrev-ref HEAD"))
	for f in must(path.walk(".")) {
		fmt.println(branch, f)
	}
}
```

`chmod +x` and run it. The first run compiles; every run after starts the cached binary.

## Write it like a script

The prelude puts an arena in the allocator, so a script never frees. Anything that can fail
goes through `must`, which dies with the call site and logs the death. The shell, HTTP, paths,
time and tar are one import each. When a script outgrows a script, it is already a native
program. [Writing scripts →](docs/scripts.md)

## Ship one file

SQLite, zstd, wasm3, libgit2 and PostgreSQL's own parser are vendored and linked statically, so
a program that uses them installs nothing. libcurl and libpq are the only system libraries. A
shipped binary updates itself from a signed release, by patch where it can: 197 KB instead of
946 KB between two builds 15 commits apart. [Packages →](docs/packages.md)

## A UI whose frame is data

`jm:ui` is immediate mode, and every frame is plain arrays: a scene, a draw list, a hit list.
A test clicks and types into it with no window. A change is checked as a text dump or a
headless PNG, and the window hot-reloads the app from a child process on every build. Screen
readers hear it through AccessKit on all three platforms. [UI →](docs/ui.md)

<p align="center">
  <img src="docs/images/material.png" alt="Material 3 buttons in every state" width="32%">
  <img src="docs/images/fluent.png" alt="Fluent 2 buttons in every state" width="32%">
  <img src="docs/images/primer.png" alt="Primer buttons in the dark theme" width="32%">
</p>

<p align="center"><sub>Material 3 Expressive, Fluent 2 and GitHub Primer, generated from each system's own
tokens. Every screenshot here was rendered headlessly by jm itself.</sub></p>

## Pipelines that never block

`jm:stream` builds typed operators into a DAG of bounded edges. A node runs only when an edge
changed and yields instead of waiting, so there is no thread per stage and no select. A stage
hop costs about 20 ns, and the same pipeline runs on one thread for a deterministic test or on
a pool in production. [Streams →](docs/streams.md)

## Fuzzed, not hoped

Nine packages carry a property suite for `jm:fuzz`, with shrinking, a corpus and replayable
seeds, and `just test` replays every corpus. The suites have found real bugs on their first runs:
three crashes in the tar reader, a pointer check in the wasm host that wrapped, and invalid
UTF-8 that PostgreSQL's parser passes straight through. [Fuzzing →](docs/fuzzing.md)

## Linux, macOS, Windows

`just check` type-checks every package for all three targets from one machine. CI builds and
tests every package on each of them. [Building and testing →](docs/building.md)

## Get started

```sh
git clone https://mordaunt.dev/code/jm && cd jm
./setup.sh             # install what the recipes need, report what is missing
just odin-run-install  # odin-run into ~/.local/bin, pointed at this checkout
just odin-run-example  # run examples/hello.odin
```

Then open a kitchen to see the UI: `just material-kitchen`, `just fluent-kitchen` or
`just primer-kitchen`. [Setup →](docs/setup.md)

## Learn more

| Guide | What it covers |
|-------|----------------|
| [Setup](docs/setup.md) | Toolchains and system libraries per platform |
| [Writing scripts](docs/scripts.md) | Conventions, logging, the `odin-run` cache |
| [Packages](docs/packages.md) | Every package and what it does |
| [Building and testing](docs/building.md) | `just` recipes and CI |
| [UI](docs/ui.md) | The frame model, needs and commands, hot reload, the example apps |
| [Streams](docs/streams.md) | Dataflow pipelines and their measured costs |
| [Fuzzing](docs/fuzzing.md) | Property suites, isolation, and what they found |
| [SQLite](docs/sqlite.md) · [zstd](docs/zstd.md) · [WebAssembly](docs/wasm.md) | The vendored C libraries and how they are built |
| [PostgreSQL](docs/postgres.md) · [Git](docs/git.md) | The SQL parser, the libpq client and libgit2 |

## Licence

Copyright 2026 Jack Mordaunt. jm is licensed under the [Apache License 2.0](LICENSE). The
vendored libraries keep their own licences, recorded beside their source or in their guide
above. The jm name and mark are not covered by the code licence; see
[branding](branding/README.md).
