# Setup

`./setup.sh` installs what the recipes need and then reports what is still
missing; `./setup.sh --check` only reports, and exits 1 when something
required is absent. It uses Homebrew on macOS, apt, dnf or pacman on Linux,
and winget or else scoop on Windows under Git Bash. A package that fails to
install is reported and the rest carry on. Odin is fetched from its GitHub
release at the version CI pins, and only when no `odin` is on `PATH`.

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

Ubuntu 24.04 packages neither SDL3 nor a new enough just: the script fetches
just's own release, and SDL3 has to be built from source there.
