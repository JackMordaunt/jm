#!/usr/bin/env bash
# Install what jm's recipes need, then report what is still missing.
#
#   ./setup.sh           install through the platform's package manager, then check
#   ./setup.sh --check   check only; exit 1 when anything required is missing
#
# Homebrew on macOS; apt, dnf or pacman on Linux; winget, else scoop, on
# Windows under Git Bash, which the recipes need there anyway. A package that
# will not install is reported, not fatal, so one distribution lacking one
# package still gets the rest. What no package manager can place is listed
# with the step to take by hand. Odin is fetched from its GitHub release at
# the version CI pins, and only when no odin is on PATH.
set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd)
odin_release=$(sed -n 's/^  ODIN_RELEASE: *//p' "$root/.github/workflows/test.yml")
# The oldest just that parses the justfile (home_directory arrived in
# 1.23.0; measured against 1.21.0 through 1.43.0), and the release fetched
# where the distribution's is older, as Ubuntu 24.04's 1.21.0 is.
just_min=1.23.0
just_fetch=1.58.0
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
missing=0

note() { printf 'setup: %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

as_root() {
  if [ "$(id -u)" = 0 ]; then "$@"; else sudo "$@"; fi
}

platform() {
  case "$(uname -s)" in
  Darwin) echo macos ;;
  Linux) echo linux ;;
  MINGW* | MSYS* | CYGWIN*) echo windows ;;
  *) echo unknown ;;
  esac
}

linux_pm() {
  local pm
  for pm in apt-get dnf pacman; do
    if have "$pm"; then
      echo "$pm"
      return
    fi
  done
  echo none
}

# pm_install installs packages with one manager and fails if any did not.
pm_install() {
  local pm=$1
  shift
  case "$pm" in
  brew) brew install --quiet "$@" ;;
  apt-get) as_root apt-get install -y --no-install-recommends "$@" ;;
  dnf) as_root dnf install -y "$@" ;;
  pacman) as_root pacman -S --needed --noconfirm "$@" ;;
  scoop) powershell.exe -NoProfile -Command "scoop install $*" ;;
  winget)
    winget.exe install --exact --silent --accept-package-agreements \
      --accept-source-agreements --id "$@"
    ;;
  esac
}

# install_all tries the whole list at once, then one package at a time so a
# name one release lacks (Ubuntu 24.04 has no libsdl3-dev) costs only itself.
install_all() {
  local pm=$1 p
  local failed=()
  shift
  if pm_install "$pm" "$@"; then
    return 0
  fi
  note "the batch install failed; retrying one package at a time"
  for p in "$@"; do
    pm_install "$pm" "$p" || failed+=("$p")
  done
  if [ ${#failed[@]} -gt 0 ]; then
    note "could not install: ${failed[*]}"
  fi
}

# install_odin unpacks the pinned release and puts a wrapper on PATH. The
# wrapper execs the real binary by its full path, because odin finds its
# core library beside its own executable and a symlink would hide it.
install_odin() {
  local plat=$1 os arch ext asset dest url top
  if have odin; then
    return 0
  fi
  os=$plat
  case "$(uname -m)" in
  arm64 | aarch64) arch=arm64 ;;
  *) arch=amd64 ;;
  esac
  ext=tar.gz
  if [ "$plat" = windows ]; then ext=zip; fi
  asset="odin-$os-$arch-$odin_release.$ext"
  url="https://github.com/odin-lang/Odin/releases/download/$odin_release/$asset"
  dest="${ODIN_HOME:-$HOME/.local/share/odin/$odin_release}"
  note "fetching $url"
  curl -fsSL --max-time 600 -o "$scratch/$asset" "$url"
  mkdir -p "$scratch/odin"
  if [ "$ext" = zip ]; then
    unzip -q "$scratch/$asset" -d "$scratch/odin"
  else
    tar -xzf "$scratch/$asset" -C "$scratch/odin"
  fi
  top="$scratch/odin"
  if [ "$(find "$top" -mindepth 1 -maxdepth 1 | wc -l)" -eq 1 ]; then
    top=$(find "$top" -mindepth 1 -maxdepth 1)
  fi
  mkdir -p "$(dirname "$dest")"
  rm -rf "$dest"
  mv "$top" "$dest"
  if [ "$plat" = windows ]; then
    note "odin is in $dest; add it to PATH"
    return 0
  fi
  mkdir -p "$HOME/.local/bin"
  printf '#!/bin/sh\nexec "%s/odin" "$@"\n' "$dest" >"$HOME/.local/bin/odin"
  chmod +x "$HOME/.local/bin/odin"
  have odin || note "odin is in ~/.local/bin, which is not on PATH"
}

install_macos() {
  if ! xcode-select -p >/dev/null 2>&1; then
    note "the Xcode command line tools are missing; a dialog will offer them"
    xcode-select --install || true
  fi
  if ! have brew; then
    note "Homebrew is missing; install it from https://brew.sh and run this again"
    return 0
  fi
  # brew install upgrades a formula that is already there, so only the
  # missing ones are named.
  local f
  local want=()
  for f in just cmake sdl3 libpq postgresql@18 comrak; do
    brew list --versions "$f" >/dev/null || want+=("$f")
  done
  if [ ${#want[@]} -gt 0 ]; then install_all brew "${want[@]}"; fi
  if ! have pg_ctl; then
    note "postgresql@18 is keg-only: add $(brew --prefix postgresql@18)/bin to PATH"
  fi
}

install_linux() {
  local pm
  pm=$(linux_pm)
  case "$pm" in
  apt-get)
    as_root apt-get update -qq
    install_all apt-get build-essential clang git ca-certificates curl unzip cmake just \
      pkg-config libcurl4-openssl-dev libmbedtls-dev zlib1g-dev libpq-dev postgresql \
      libsdl3-dev fonts-liberation fonts-noto-core
    ;;
  dnf)
    install_all dnf gcc gcc-c++ make clang git curl unzip cmake just pkgconf \
      libcurl-devel mbedtls-devel zlib-ng-compat-devel libpq-devel \
      postgresql-server SDL3-devel liberation-sans-fonts google-noto-sans-fonts
    ;;
  pacman)
    install_all pacman base-devel clang git curl unzip cmake just pkgconf \
      mbedtls zlib postgresql-libs postgresql sdl3 ttf-liberation noto-fonts
    ;;
  none)
    note "no apt-get, dnf or pacman; install the packages the check lists by hand"
    return 0
    ;;
  esac
  link_font_dir liberation LiberationSans-Regular.ttf
  link_font_dir noto NotoSans-Regular.ttf
  if ! just_recent; then install_just; fi
}

# install_just puts just's own static release in ~/.local/bin.
install_just() {
  local asset
  asset="just-$just_fetch-$(uname -m)-unknown-linux-musl.tar.gz"
  note "fetching just $just_fetch; the distribution's is older than $just_min"
  mkdir -p "$HOME/.local/bin"
  curl -fsSL --max-time 120 \
    "https://github.com/casey/just/releases/download/$just_fetch/$asset" |
    tar -xz -C "$HOME/.local/bin" just
  if ! just_recent; then
    note "an older just is ahead of ~/.local/bin on PATH"
  fi
}

# link_font_dir puts a family where the code looks for it,
# /usr/share/fonts/<name>, which is Arch's layout; Debian and Fedora install
# the same files one directory deeper. CI links Liberation the same way.
link_font_dir() {
  local name=$1 file=$2 found
  if [ -f "/usr/share/fonts/$name/$file" ]; then
    return 0
  fi
  found=$(find /usr/share/fonts -name "$file" -print -quit 2>/dev/null)
  if [ -z "$found" ]; then
    return 0
  fi
  as_root mkdir -p "/usr/share/fonts/$name"
  as_root ln -sf "$(dirname "$found")"/*.ttf "/usr/share/fonts/$name/"
}

# install_windows installs only what is missing: winget exits non-zero for a
# package that is already there, which would read as a failure.
install_windows() {
  local pm="" item cmd id
  if have winget.exe; then
    pm=winget
  elif have scoop || [ -d "$HOME/scoop" ]; then
    pm=scoop
  else
    note "neither winget nor scoop is available; install one and run this again"
    return 0
  fi
  for item in just=Casey.Just:just cmake=Kitware.CMake:cmake ninja=Ninja-build.Ninja:ninja \
    git=Git.Git:git clang-cl=LLVM.LLVM:llvm initdb=PostgreSQL.PostgreSQL.18:postgresql; do
    cmd=${item%%=*}
    id=${item#*=}
    if have "$cmd"; then continue; fi
    if [ "$pm" = winget ]; then id=${id%%:*}; else id=${id#*:}; fi
    pm_install "$pm" "$id" || note "could not install $id"
  done
  if [ -z "$(msvc_dir)" ]; then install_msvc "$pm"; fi
}

install_msvc() {
  if [ "$1" != winget ]; then
    note "scoop has no MSVC; install Visual Studio Build Tools with the C++ workload"
    return 0
  fi
  winget.exe install --exact --silent --accept-package-agreements --accept-source-agreements \
    --id Microsoft.VisualStudio.2022.BuildTools --override \
    "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended" ||
    note "could not install the Visual Studio Build Tools"
}

msvc_dir() {
  local vswhere="/c/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe"
  if [ -x "$vswhere" ]; then
    "$vswhere" -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 \
      -property installationPath 2>/dev/null | head -1
  fi
}

# report prints one requirement. Level "need" fails the check; "want" is for
# something only some tests or demos use, and says which.
report() {
  local level=$1 name=$2 hint=$3
  shift 3
  if "$@" >/dev/null 2>&1; then
    printf '  ok    %s\n' "$name"
    return 0
  fi
  printf '  %s  %s: %s\n' "$level" "$name" "$hint"
  if [ "$level" = need ]; then missing=1; fi
}

# version_at_least reports whether version $2 is $1 or later.
version_at_least() {
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$1" ]
}

just_recent() {
  have just && version_at_least "$just_min" "$(just --version | cut -d' ' -f2)"
}

odin_pinned() {
  odin version | grep -q "version $odin_release"
}

# links asks the C toolchain to link an empty program against each library,
# the same search the Odin linker makes.
links() {
  local lib args=()
  for lib in "$@"; do args+=("-l$lib"); done
  # shellcheck disable=SC2086 # link_dirs is a list of -L flags
  printf 'int main(void) { return 0; }\n' | cc -x c - -o "$scratch/probe" $link_dirs "${args[@]}"
}

font() { [ -f "$1" ]; }

libpq_dir_macos() {
  local d
  d="$(brew --prefix libpq 2>/dev/null)/lib"
  if [ -d "$d" ]; then echo "-L$d"; fi
}

check_common() {
  report need odin "install $odin_release, or let setup.sh fetch it" have odin
  report want "odin $odin_release" "CI pins it; another build may differ" odin_pinned
  report need "just $just_min or later" "https://just.systems" just_recent
  report need git "the fetch recipes clone Blend2D and libgit2" have git
  report need cmake "Blend2D and libgit2 build with it" have cmake
  report need curl "the font and Odin downloads use it" have curl
  report want unzip "just fluent-fonts unpacks Selawik with it" have unzip
  report want comrak "just readme renders the markdown with it; cargo install comrak" have comrak
  report want "initdb, pg_ctl" "pq tests skip without a server" have pg_ctl
  report want Selawik "the fluent kitchen; run just fluent-fonts" \
    font "$HOME/.local/share/fonts/selawik/selawk.ttf"
}

check_macos() {
  link_dirs=""
  if have brew; then link_dirs="-L$(brew --prefix)/lib ${LINKFLAGS-$(libpq_dir_macos)}"; fi
  report need "Xcode command line tools" "xcode-select --install" xcode-select -p
  report need cc "comes with the Xcode command line tools" have cc
  report need make "comes with the Xcode command line tools" have make
  report need libpq "brew install libpq" links pq
  report need SDL3 "brew install sdl3" links SDL3
}

check_linux() {
  link_dirs=${LINKFLAGS-}
  report need cc "a C compiler: build-essential, gcc or base-devel" have cc
  report need clang "odin links through clang" have clang
  report need make "cmake's default generator" have make
  report need libstdc++ "Blend2D is C++" links stdc++
  report need libcurl "vendor:curl for jm:http" links curl z
  report need mbedtls "vendor:curl names it on Linux" links mbedtls mbedx509 mbedcrypto
  report need libpq "libpq-dev, libpq-devel or postgresql-libs" links pq
  report need SDL3 "libsdl3-dev, SDL3-devel or sdl3; build it from source if absent" links SDL3
  report need "Liberation Sans" "the render tests read /usr/share/fonts/liberation" \
    font /usr/share/fonts/liberation/LiberationSans-Regular.ttf
  report want "Noto Sans" "the material kitchen reads /usr/share/fonts/noto" \
    font /usr/share/fonts/noto/NotoSans-Regular.ttf
  if ! have pg_ctl && compgen -G "/usr/lib/postgresql/*/bin/pg_ctl" >/dev/null; then
    note "Debian keeps pg_ctl off PATH: add $(dirname /usr/lib/postgresql/*/bin/pg_ctl | tail -1)"
  fi
}

libpq_lib_windows() {
  compgen -G "/c/Program Files/PostgreSQL/*/lib/libpq.lib" ||
    compgen -G "$HOME/scoop/apps/postgresql/current/lib/libpq.lib"
}

check_windows() {
  local lib
  report need MSVC "Visual Studio Build Tools with the C++ workload" msvc_dir_found
  report need clang-cl "LLVM; wasm3 and Blend2D build with it" have clang-cl
  report need ninja "the Blend2D and libgit2 recipes generate for it" have ninja
  report need libpq.lib "PostgreSQL for Windows ships it" libpq_lib_windows
  lib=$(libpq_lib_windows | head -1 || true)
  if [ -n "$lib" ] && [ -z "${LINKFLAGS:-}" ]; then
    note "set LINKFLAGS=\"/LIBPATH:$(cygpath -d "$(dirname "$lib")")\" so the linker finds libpq"
  fi
  note "run just from an x64 Native Tools shell so cl, lib and link are on PATH"
}

msvc_dir_found() { [ -n "$(msvc_dir)" ]; }

main() {
  local plat mode=install
  plat=$(platform)
  case "${1:-}" in
  --check) mode=check ;;
  "") ;;
  *)
    note "usage: setup.sh [--check]"
    exit 2
    ;;
  esac
  if [ "$plat" = unknown ]; then
    note "$(uname -s) is not a platform jm builds on"
    exit 1
  fi
  if [ "$mode" = install ]; then
    "install_$plat"
    install_odin "$plat"
    if have just && [ ! -f "$HOME/.local/share/fonts/selawik/selawk.ttf" ]; then
      just --justfile "$root/justfile" fluent-fonts || note "could not fetch Selawik"
    fi
  fi
  echo "jm requirements on $plat:"
  check_common
  "check_$plat"
  if [ "$missing" = 1 ]; then
    note "something required is missing; see above"
    exit 1
  fi
}

main "$@"
