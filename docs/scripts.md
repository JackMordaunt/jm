# Writing scripts

**Write the scripts you would give to Python or bash in Odin, and run them like any script.**

- One `.odin` file with a shebang is a whole script.
- The first run compiles it; every later run starts the cached binary.
- No freeing, no error plumbing: an arena takes the memory and `must` takes the failures.
- Every failure is logged with its call site, so a script that died at 3 am says where.

## Quick start

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

`chmod +x` and run it. On Windows the shebang does nothing; see [Runner](#runner).

## Conventions

### Memory: scripts never free

`prelude.init` puts a growing arena in `context.allocator`, and the exit reclaims it.

> [!TIP]
> `ODIN_SCRIPT_DEBUG=1` swaps in the debug allocator. It reports overflow, double free and
> write after free at exit.

### Errors: `must` and `die`

- Anything that can fail returns `(value, ok)` or `(value, os.Error)`, so `must(...)` wraps it.
- `die` writes the message and the call site to the script log, to stderr, and to one shared
  `deaths.log`.

### Output: stdout is yours

`prelude` never writes to stdout. Stdout is the script's data channel.

### Logs

| Platform | Log dir |
|----------|---------|
| Linux | `~/.local/state` |
| macOS | `~/Library/Logs` |
| Windows | `%LOCALAPPDATA%` |

- Each script logs to `<log dir>/odin/<name>/<name>.log`, rotated to `.1` at 8 MiB.
- Every death also lands in `<log dir>/odin/deaths.log`.
- The default echoes warning and above to stderr; `ODIN_LOG=debug` echoes everything.

### Platforms

Platform splits live in `_unix.odin` / `_windows.odin` files. `just check` type-checks every
package for `linux_amd64`, `darwin_arm64` and `windows_amd64` from one machine.

## Runner

```
odin-run script.odin [args...]   compile if stale, then run
odin-run -clean                  drop the cache
```

| Variable | Effect |
|----------|--------|
| `ODIN_RUN_FLAGS="-debug"` | build unoptimised |
| `ODIN_RUN_VERBOSE=1` | print the build line |

On Windows the shebang does nothing; call `odin-run script.odin` or associate `.odin` with it.

<details>
<summary>Under the hood: the cache</summary>

The cache key covers the script bytes and path, every `.odin` in the collection, the odin
binary, target and flags. A change to any of them rebuilds.

When `vendor/curl/lib/libcurl.dll` exists under the Odin root, it is copied beside the cached
binary.

</details>

## See also

- [Packages](packages.md): everything a script can import
- [Setup](setup.md) and [Building and testing](building.md): installing `odin-run`
- [README](../README.md)
