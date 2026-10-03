# Setup

**One script installs everything jm's recipes need and tells you what is still missing.**

- It uses the package manager you already have: Homebrew, apt, dnf, pacman, winget or scoop.
- A package that fails to install is reported, and the rest carry on.
- It fetches Odin only when no `odin` is on `PATH`, at the version CI pins.
- `--check` installs nothing, so it doubles as a health check.

## Quick start

```sh
./setup.sh            # install what is missing, then report
./setup.sh --check    # report only; exits 1 when something required is absent
```

| Platform | Package manager |
|----------|-----------------|
| macOS | Homebrew |
| Linux | apt, dnf or pacman |
| Windows | winget, or else scoop, under Git Bash |

## What jm needs

| Need | macOS | Linux | Windows |
|------|-------|-------|---------|
| Odin `dev-2026-09`, just 1.45+, git, cmake | yes | yes | yes |
| C toolchain | Xcode command line tools | cc, clang, make | MSVC Build Tools, clang-cl, ninja |
| libpq | `libpq` (keg-only; the justfile finds it) | libpq dev package | `libpq.lib` from PostgreSQL, via `LINKFLAGS` |
| SDL3 | `sdl3` | SDL3 dev package | ships with Odin |
| libcurl, mbedtls, zlib | system | dev packages | ships with Odin |
| Liberation Sans in `/usr/share/fonts/liberation` | — | render tests | — |
| `initdb`, `pg_ctl` (optional) | pq tests; they skip without | same | same |
| Selawik, Noto Sans (optional) | fluent kitchen | both kitchens | fluent kitchen |

> [!WARNING]
> Ubuntu 24.04 packages neither SDL3 nor a new enough just. The script fetches just's own
> release there, but SDL3 has to be built from source.

## See also

- [Building and testing](building.md): the recipes this setup enables
- [Writing scripts](scripts.md): your first script once `odin-run` is installed
- [README](../README.md)
