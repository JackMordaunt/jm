# Writing scripts

A jm script is one `.odin` file with a shebang. `odin-run` compiles it on the
first run and starts the cached binary after that.

```odin
#!/usr/bin/env odin-run
package main

import "core:fmt"
import "jm:prelude"
import "jm:sh"
import "jm:path"

must :: prelude.must
die :: prelude.die

main :: proc() {
	context = prelude.init()
	branch := must(sh.out("git rev-parse --abbrev-ref HEAD"))
	for f in must(path.walk(".")) {
		fmt.println(branch, f)
	}
}
```

`chmod +x` and run it. On Windows the shebang does nothing; see
[Runner](#runner).

## Conventions

- Scripts never free. `prelude.init` puts a growing arena in
  `context.allocator`; the exit reclaims it. `ODIN_SCRIPT_DEBUG=1` swaps in
  the debug allocator, which reports overflow, double free and write after
  free at exit.
- Anything that can fail returns `(value, ok)` or `(value, os.Error)` so
  `must(...)` wraps it. `die` writes the message and the call site to the
  script log, to stderr, and to one shared `deaths.log`.
- `prelude` never writes to stdout. Stdout is the script's data channel.
- Logs: `<log dir>/odin/<name>/<name>.log`, rotated to `.1` at 8 MiB, and
  `<log dir>/odin/deaths.log`. The log dir is `~/.local/state` on Linux,
  `~/Library/Logs` on macOS and `%LOCALAPPDATA%` on Windows. `ODIN_LOG=debug`
  echoes everything to stderr; the default echoes warning and above.
- Platform splits live in `_unix.odin` / `_windows.odin` files. `just check`
  type-checks every package for `linux_amd64`, `darwin_arm64` and
  `windows_amd64` from one machine.

## Runner

```
odin-run script.odin [args...]   compile if stale, then run
odin-run -clean                  drop the cache
```

Cache key: script bytes and path, every `.odin` in the collection, the odin
binary, target and flags. `ODIN_RUN_FLAGS="-debug"` builds unoptimised;
`ODIN_RUN_VERBOSE=1` prints the build line. On Windows the shebang does
nothing; call `odin-run script.odin` or associate `.odin` with it. When
`vendor/curl/lib/libcurl.dll` exists under the Odin root it is copied beside
the cached binary.
