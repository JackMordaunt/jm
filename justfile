# jm's recipes, in sections by the package or tool each serves, the recipe
# that compiles a package's C library among them; `just` lists them by
# section. The settings every section shares come first.

odin  := env("ODIN", "odin")
root  := replace(justfile_directory(), "\\", "/")
flags := "-vet -strict-style -collection:jm=" + root
exe   := if os() == "windows" { ".exe" } else { "" }
cc    := env("CC", "cc")
just  := quote(just_executable())

# Homebrew keeps libpq keg-only, so on macOS its lib directory is not on the
# linker's search path and jm:pq cannot link without it. LINKFLAGS replaces
# the guess, as CI sets it.
libpq_link := if os() == "macos" { `d="$(brew --prefix libpq 2>/dev/null)/lib"; [ -d "$d" ] && echo "-L$d" || true` } else { "" }
linkflags := env("LINKFLAGS", libpq_link)
link := if linkflags == "" { "" } else { "-extra-linker-flags:\"" + linkflags + "\"" }

# `just` alone lists the recipes.
default:
    @just --list --unsorted

# ============================================================================
# general: what spans every package. check, test and link find the
# packages, so a new one joins them without joining a list.
# ============================================================================

targets := "linux_amd64 darwin_arm64 windows_amd64"
# Directories that check, test and link leave out, with everything under
# them: SKIP="pq tools/jm-fuzz" where there is no libpq to link.
skip := env("SKIP", "")
# Packages whose tests run alone, on one thread, after the rest: the three
# over wasm3, which is not thread-safe; ui/sdl, whose tests spawn
# hot-counter-child copies sharing one exe path; tar, whose git children
# inherit each other's pipes on Windows; and flow and wasm-bench, whose tests
# measure a split of work or its cost and fail under load.
serial_tests := "wasm wasm/fuzz tools/wasm-bench ui/sdl tar flow"

# Packages run in parallel; a program keeps its entry point. A job's output
# is held until it ends, and every failure prints before the recipe fails.
# Name packages to check only those: `just check ui/primer examples/kitchen`.
#
# Type-check packages and programs for linux, darwin and windows, or all
[group('general')]
[positional-arguments]
check *pkgs:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ $# -eq 0 ]; then
      { {{just}} _dirs package | sed 's/$/ -no-entry-point/'; {{just}} _dirs program | sed 's/$/ -entry-point/'; }
    else
      for d in "$@"; do
        d=${d%/}
        [ -d "$d" ] || { echo "check: no package at $d" >&2; exit 1; }
        if grep -qs '^package main' "$d"/*.odin; then echo "$d -entry-point"; else echo "$d -no-entry-point"; fi
      done
    fi \
      | while read -r d entry; do for t in {{targets}}; do printf '%s %s %s\n' "$d" "$t" "$entry"; done; done \
      | xargs -P {{num_cpus()}} -n 3 sh -c '
      entry=$2
      if [ "$entry" = -entry-point ]; then entry=; fi
      if out=$({{odin}} check "$0" {{flags}} -target:"$1" $entry 2>&1); then exit 0; fi
      printf "%s (%s)\n%s\n" "$0" "$1" "$out" >&2
      exit 1'

# Packages run in parallel, then serial_tests one at a time on one thread.
# Every package links with the same flags, a superset of what any one needs.
# A job's output is held until it ends, and every failure prints before the
# recipe fails. Name packages to test only those; arguments starting with
# a dash go to every odin test, so one test runs as
# `just test ui/primer -define:ODIN_TEST_NAMES=primer.test_button_activates`.
#
# Run the named packages' tests, or every package's
[group('general')]
[positional-arguments]
test *args: sqlite zstd wasm pg_query blend2d kb libgit2 accesskit hot-counter-child
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p build/test
    # vendor:sdl3 loads SDL3.dll at start-up on Windows, so ui/sdl's test
    # binary needs it beside it.
    if [ "{{os()}}" = windows ]; then cp "$({{odin}} root)/vendor/sdl3/SDL3.dll" build/test/; cp ui/accesskit/lib/accesskit.dll build/test/ 2>/dev/null || true; fi
    pkgs=() extra=()
    for a in "$@"; do
      case "$a" in
        -*) extra+=("$a");;
        *) a=${a%/}; [ -d "$a" ] || { echo "test: no package at $a" >&2; exit 1; }; pkgs+=("$a");;
      esac
    done
    if [ ${#pkgs[@]} -eq 0 ]; then pkgs=($({{just}} _dirs test)); fi
    export EXTRA="${extra[*]-}"
    run() {
      local p=$1 out
      shift
      # EXTRA is split on purpose: it holds one or more odin flags.
      # shellcheck disable=SC2086
      # A name filter that matches nothing still exits 0, so it fails here.
      if out=$({{odin}} test "$p" {{flags}} {{link}} "$@" $EXTRA -out:build/test/$(echo "$p" | tr / -){{exe}} 2>&1) \
        && ! grep -q '^No tests to run' <<<"$out"; then
        echo "ok   $p ($(grep -o 'Finished [0-9]* tests*' <<<"$out" | tail -1 | cut -d' ' -f2) tests)"
        return 0
      fi
      printf 'FAIL %s\n%s\n' "$p" "$out" >&2
      return 1
    }
    export -f run
    parallel=() serial=()
    for d in "${pkgs[@]}"; do
      case " {{serial_tests}} " in *" $d "*) serial+=("$d");; *) parallel+=("$d");; esac
    done
    failed=0
    if [ ${#parallel[@]} -gt 0 ]; then
      printf '%s\n' "${parallel[@]}" | xargs -P {{num_cpus()}} -n 1 bash -c 'run "$0"' || failed=1
    fi
    for d in "${serial[@]+"${serial[@]}"}"; do run "$d" -define:ODIN_TEST_THREADS=1 || failed=1; done
    exit $failed

# Each is named for its directory, built in parallel: type-checking misses a
# link failure. Output is held as in test.
#
# Build every program into build/debug
[group('general')]
link: sqlite zstd wasm pg_query blend2d kb libgit2 accesskit
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p build/debug
    {{just}} _dirs program | xargs -P {{num_cpus()}} -n 1 sh -c '
      if out=$({{odin}} build "$0" {{flags}} {{link}} -out:build/debug/$(echo "$0" | tr / -){{exe}} 2>&1); then
        echo "ok   $0"
        exit 0
      fi
      printf "FAIL %s\n%s\n" "$0" "$out" >&2
      exit 1'

# Every directory of Odin source, tracked or not but never ignored, less
# skip: so a new package joins check, test and link without joining a list.
# kind picks among them: `package` and `program` split them on `package
# main`, `test` keeps those holding an @(test) proc. CI reads them here too.
[group('general')]
_dirs kind:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{kind}}" in package|program|test) ;; *) echo "_dirs: no kind {{kind}}" >&2; exit 1;; esac
    git ls-files --cached --others --exclude-standard -- '*.odin' | sed -e 's|/[^/]*$||' -e 's|^[^/]*\.odin$|.|' | sort -u \
      | while read -r d; do
      for s in {{skip}}; do case "$d" in "$s"|"$s"/*) continue 2;; esac; done
      case "{{kind}}" in
        package) grep -qs '^package main' "$d"/*.odin && continue ;;
        program) grep -qs '^package main' "$d"/*.odin || continue ;;
        test) grep -qs '@(test)' "$d"/*.odin || continue ;;
      esac
      echo "$d"
    done

# A linked worktree starts with none of the native libraries, which are
# ignored, and building them again costs minutes (Blend2D and libgit2 are
# CMake trees). Each library's recipe first runs this: in a linked
# worktree, a <pkg>/lib missing here is clone-copied from the main checkout
# when its inputs match there, the vendored tree or the pinned revisions,
# and touched so the recipe's staleness check keeps it. A library whose
# inputs differ builds here as usual. Compile flags are not compared:
# delete the copied lib after changing one.
native_libs := "sqlite3:sqlite3/vendor zstd:zstd/vendor wasm:wasm/vendor pg_query:pg_query/vendor ui/kb:ui/kb/vendor ui/blend2d:=blend2d_rev,asmjit_rev git:=libgit2_rev ui/accesskit:=accesskit_ver,accesskit_sha"

[private]
_worktree-libs:
    #!/usr/bin/env bash
    set -euo pipefail
    common=$(git rev-parse --path-format=absolute --git-common-dir)
    [ "$common" != "$(git rev-parse --path-format=absolute --git-dir)" ] || exit 0
    main=$(dirname "$common")
    same() { # input: a path, or =var,var compared as the two justfiles evaluate them
      local in=$1 v
      if [ "${in#=}" = "$in" ]; then diff -rq "$main/$in" "$in" >/dev/null; return; fi
      for v in ${in#=}; do
        [ "$({{just}} --evaluate "$v")" = "$({{just}} -f "$main/justfile" -d "$main" --evaluate "$v")" ] || return 1
      done
    }
    for pair in {{native_libs}}; do
      pkg=${pair%%:*} in=${pair#*:}
      in=${in//,/ }
      # A failed build leaves its lib dir behind empty.
      [ -z "$(ls -A "$pkg/lib" 2>/dev/null)" ] && [ -d "$main/$pkg/lib" ] || continue
      rmdir "$pkg/lib" 2>/dev/null || true
      if ! same "$in"; then echo "worktree: $pkg differs from $main, so its lib builds here"; continue; fi
      case "$(uname -s)" in
        Darwin) cp -Rc "$main/$pkg/lib" "$pkg/lib" ;;
        Linux) cp -R --reflink=auto "$main/$pkg/lib" "$pkg/lib" ;;
        *) cp -R "$main/$pkg/lib" "$pkg/lib" ;;
      esac
      find "$pkg/lib" -exec touch {} +
      echo "worktree: $pkg/lib copied from $main"
    done

# Check out a repository at one commit into dir, unless it is there already.
# GitHub serves any reachable commit by hash, so a shallow fetch of the pin
# needs no tag or branch.
[group('general')]
[private]
fetch dir url rev:
    @if [ "$(git -C {{dir}} rev-parse -q --verify HEAD 2>/dev/null)" != "{{rev}}" ]; then \
        echo "fetch {{url}} @ {{rev}} -> {{dir}}"; \
        mkdir -p {{dir}} && git -C {{dir}} init -q && \
        git -C {{dir}} fetch -q --depth 1 {{url}} {{rev}} && \
        git -C {{dir}} checkout -qf FETCH_HEAD || exit 1; \
    fi

# Every artefact the recipes build, the same list as .gitignore: a new
# package's archive joins both.
#
# Remove build/, every package's compiled C library and the kits' pages
[group('general')]
clean:
    rm -rf build sqlite3/lib wasm/lib pg_query/lib ui/blend2d/lib ui/accesskit/lib git/lib ui/kb/lib tools/*/kit/index.html

# A Windows root starts with its drive letter, which a file URL puts after a slash.
root_url := if root =~ '^/' { "file://" + root } else { "file:///" + root }

# Each page renders to build/readme at its own path. Its <base> is its
# directory in the checkout, so images and LICENSE load from the source, and
# links between pages are rewritten to the rendered copies. Follows the
# browser's light or dark scheme.
#
# Render the README, its docs and THIRD_PARTY.md to HTML and open the README
[group('general')]
readme:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v comrak >/dev/null; then
      echo "readme: comrak is missing; brew install comrak, or cargo install comrak" >&2
      exit 1
    fi
    url="{{root_url}}"
    for f in README.md THIRD_PARTY.md branding/README.md docs/*.md; do
      dir=$(dirname "$f")
      html="build/readme/${f%.md}.html"
      mkdir -p "$(dirname "$html")"
      {
        printf '<!doctype html><meta charset=utf-8><meta name=color-scheme content="light dark">'
        printf '<base href="%s/%s/"><title>jm: %s</title>' "$url" "$dir" "${f%.md}"
        printf '<body style="max-width:56em;margin:2em auto;padding:0 1em;font:16px/1.55 system-ui">'
        printf '<style>pre{overflow:auto;tab-size:4;padding:1em;background:#8881;border-radius:6px}code{font:14px ui-monospace,monospace}table{border-collapse:collapse}td,th{border:1px solid #8884;padding:.3em .6em;text-align:left}img{max-width:100%%}blockquote{margin:0;padding:0 1em;border-left:3px solid #8886;color:#888}'
        printf '.markdown-alert{padding:.2em 1em;margin:1em 0;border-left:4px solid #4493f8;background:#4493f811}.markdown-alert-warning{border-color:#d29922;background:#d2992211}.markdown-alert-tip{border-color:#3fb950;background:#3fb95011}.markdown-alert-title{font-weight:600;margin:.4em 0}</style>'
        comrak -e strikethrough,table,autolink,tasklist,alerts --github-pre-lang --gfm-quirks \
          --header-id-prefix "" --unsafe "$f" |
          sed -E "s|href=\"([^\":#]+)\\.md(#[^\"]*)?\"|href=\"$url/build/readme/$dir/\\1.html\\2\"|g"
      } > "$html"
    done
    case "$(uname -s)" in
    Darwin) open build/readme/README.html ;;
    Linux) setsid -f xdg-open build/readme/README.html >/dev/null 2>&1 ;;
    MINGW* | MSYS* | CYGWIN*) start "" build/readme/README.html ;;
    *) echo "open build/readme/README.html" ;;
    esac

# ============================================================================
# odin-run: tools/odin-run, the `#!/usr/bin/env odin-run` script runner.
# ============================================================================

bindir := env("BINDIR", home_directory() / ".local" / "bin")

# Debug odin-run -> build/debug/odin-run
[group('odin-run')]
odin-run-build:
    mkdir -p build/debug
    {{odin}} build tools/odin-run -debug {{flags}} -define:JM_COLLECTION={{root}} -out:build/debug/odin-run{{exe}}

# Optimised odin-run -> build/release/odin-run
[group('odin-run')]
odin-run-release:
    mkdir -p build/release
    {{odin}} build tools/odin-run -o:speed {{flags}} -define:JM_COLLECTION={{root}} -out:build/release/odin-run{{exe}}

# Install odin-run into ~/.local/bin (override with BINDIR)
[group('odin-run')]
odin-run-install: odin-run-release
    mkdir -p {{bindir}}
    cp build/release/odin-run{{exe}} {{bindir}}/odin-run{{exe}}

# Compile and run the example script
[group('odin-run')]
odin-run-example: odin-run-build sqlite
    ODIN_RUN_VERBOSE=1 build/debug/odin-run{{exe}} examples/hello.odin

# ============================================================================
# sqlite3: jm:sqlite3 and the SQLite amalgamation it links.
# ============================================================================

sqlite_lib := if os() == "windows" { "sqlite3/lib/sqlite3.lib" } else { "sqlite3/lib/sqlite3.a" }
# SQLite compile-time options. sqlite.org's recommended set for 3.53.4, with
# three deliberate changes: THREADSAFE=1 rather than 0, so a connection per
# jm:flow worker is safe; OMIT_AUTOINIT left off, because omitting it makes
# any call before sqlite3_initialize a segfault; and FTS5 compiled in for a
# full-text index. OMIT_LOAD_EXTENSION keeps the build from needing libdl.
sqlite_defines := "-DSQLITE_DQS=0 -DSQLITE_THREADSAFE=1 -DSQLITE_DEFAULT_MEMSTATUS=0 " + \
  "-DSQLITE_DEFAULT_WAL_SYNCHRONOUS=1 -DSQLITE_LIKE_DOESNT_MATCH_BLOBS " + \
  "-DSQLITE_MAX_EXPR_DEPTH=0 -DSQLITE_OMIT_DECLTYPE -DSQLITE_OMIT_DEPRECATED " + \
  "-DSQLITE_OMIT_PROGRESS_CALLBACK -DSQLITE_OMIT_SHARED_CACHE -DSQLITE_STRICT_SUBTYPE=1 " + \
  "-DSQLITE_OMIT_LOAD_EXTENSION -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_MATH_FUNCTIONS"

# The archive lands in sqlite3/lib rather than build/ because foreign import
# resolves relative to the package directory. `just check` never needs it:
# odin check does not open a foreign import, which is how one machine
# type-checks all three targets without building for any of them.

# Compile the vendored SQLite amalgamation into sqlite3/lib if it is stale
[group('sqlite3')]
[unix]
sqlite: _worktree-libs
    @mkdir -p sqlite3/lib
    @if [ ! -f {{sqlite_lib}} ] || [ sqlite3/vendor/sqlite3.c -nt {{sqlite_lib}} ]; then \
        echo "{{cc}} sqlite3 amalgamation -> {{sqlite_lib}}"; \
        {{cc}} -O2 -fPIC -c sqlite3/vendor/sqlite3.c -o sqlite3/lib/sqlite3.o {{sqlite_defines}}; \
        ar rcs {{sqlite_lib}} sqlite3/lib/sqlite3.o; \
    fi

[group('sqlite3')]
[windows]
sqlite: _worktree-libs
    @if (!(Test-Path {{sqlite_lib}}) -or (Get-Item sqlite3/vendor/sqlite3.c).LastWriteTime -gt (Get-Item {{sqlite_lib}}).LastWriteTime) { \
        cl /nologo /O2 /c sqlite3/vendor/sqlite3.c /Fosqlite3/lib/sqlite3.obj {{sqlite_defines}}; \
        lib /nologo /OUT:{{sqlite_lib}} sqlite3/lib/sqlite3.obj \
    }

# ============================================================================
# zstd: jm:zstd and the zstd amalgamation it links.
# ============================================================================

zstd_lib := if os() == "windows" { "zstd/lib/zstd.lib" } else { "zstd/lib/zstd.a" }

# zstd/vendor/zstd.c is zstd 1.5.7's single-file library, generated by its
# build/single_file_libs/create_single_file_library.sh: compression,
# decompression and the dictionary builder, without legacy formats or
# assembly, with multi-threaded compression available. It needs no defines.
#
# Compile the vendored zstd amalgamation into zstd/lib if it is stale
[group('zstd')]
[unix]
zstd: _worktree-libs
    @mkdir -p zstd/lib
    @if [ ! -f {{zstd_lib}} ] || [ zstd/vendor/zstd.c -nt {{zstd_lib}} ]; then \
        echo "{{cc}} zstd amalgamation -> {{zstd_lib}}"; \
        {{cc}} -O2 -fPIC -c zstd/vendor/zstd.c -o zstd/lib/zstd.o; \
        ar rcs {{zstd_lib}} zstd/lib/zstd.o; \
    fi

[group('zstd')]
[windows]
zstd: _worktree-libs
    @if (!(Test-Path {{zstd_lib}}) -or (Get-Item zstd/vendor/zstd.c).LastWriteTime -gt (Get-Item {{zstd_lib}}).LastWriteTime) { \
        New-Item -ItemType Directory -Force zstd/lib | Out-Null; \
        cl /nologo /O2 /c zstd/vendor/zstd.c /Fozstd/lib/zstd.obj; \
        lib /nologo /OUT:{{zstd_lib}} zstd/lib/zstd.obj \
    }

# ============================================================================
# wasm: jm:wasm, the wasm3 it links, and tools/wasm-bench.
# ============================================================================

wasm_cc  := env("WASM_CC", "clang")
wasm_lib   := if os() == "windows" { "wasm/lib/wasm3.lib" } else { "wasm/lib/wasm3.a" }
# wasm3 compile-time options. The defaults are what the interpreter wants:
# bytecode validation and gas metering are both on already. WASI is the one
# thing that is off, and jm:wasm's run needs it to call a command's _start.
wasm_defines := "-Dd_m3HasWASI"

# Unlike SQLite this is a tree rather than one amalgamated file, so the objects
# go to a scratch directory beside the archive and staleness is any source
# newer than it.
#
# Compile the vendored wasm3 into wasm/lib if it is stale
[group('wasm')]
[unix]
wasm: _worktree-libs
    @mkdir -p wasm/lib/obj
    @if [ ! -f {{wasm_lib}} ] || [ -n "$(find wasm/vendor -name '*.[ch]' -newer {{wasm_lib}} -print -quit)" ]; then \
        echo "{{cc}} wasm3 -> {{wasm_lib}}"; \
        for f in wasm/vendor/*.c; do \
            {{cc}} -O2 -fPIC -Iwasm/vendor {{wasm_defines}} -c $f -o wasm/lib/obj/$(basename $f .c).o || exit 1; \
        done; \
        ar rcs {{wasm_lib}} wasm/lib/obj/*.o; \
    fi

[group('wasm')]
[windows]
wasm: _worktree-libs
    @if (!(Test-Path {{wasm_lib}})) { \
        New-Item -ItemType Directory -Force wasm/lib/obj | Out-Null; \
        Get-ChildItem wasm/vendor/*.c | ForEach-Object { cl /nologo /O2 /I wasm/vendor {{wasm_defines}} /c $_.FullName /Fowasm/lib/obj/ }; \
        lib /nologo /OUT:{{wasm_lib}} wasm/lib/obj/*.obj \
    }

# `just bench "-n=64"` fixes the work per call; without one each workload is
# calibrated to take about 25ms.
#
# Time jm:wasm against the workloads in tools/wasm-bench
[group('wasm')]
bench args="": wasm
    mkdir -p build/release
    {{odin}} build tools/wasm-bench -o:speed {{flags}} -out:build/release/wasm-bench{{exe}}
    build/release/wasm-bench{{exe}} tools/wasm-bench/workloads {{args}}

# stream: jm:stream's benchmark and stress tool, tools/stream-bench.
# ============================================================================

# `just stream-bench "-items=200000 -threads=0,3"`; `just stream-stress
# "-nodes=2000 -for=5m"`. Stress is built with the quiescence check on, so a
# pipeline that goes quiet unfinished fails loudly.
#
# Time jm:stream: what a message costs through each shape
[group('stream')]
stream-bench args="":
    {{odin}} build tools/stream-bench -o:speed {{flags}} -out:build/release/stream-bench{{exe}}
    build/release/stream-bench{{exe}} {{args}}

# Stress jm:stream with random DAGs until the time is up
[group('stream')]
stream-stress args="-for=30s":
    {{odin}} build tools/stream-bench -o:speed -define:STREAM_CHECK_YIELDS=true {{flags}} -out:build/release/stream-stress{{exe}}
    build/release/stream-stress{{exe}} stress {{args}}

# The .wasm files are committed, so this is only needed when a source changes.
# It wants a clang with the wasm32 target and wasm-ld; zig cc has both, as
# WASM_CC="zig cc".
#
# Rebuild the benchmark workloads from their C sources
[group('wasm')]
[unix]
bench-build:
    for f in tools/wasm-bench/workloads/*.c; do \
      {{wasm_cc}} --target=wasm32-freestanding -O2 -nostdlib -Wl,--no-entry \
        -Wl,--export=run -Wl,--export-memory -o ${f%.c}.wasm $f || exit 1; \
    done

# ============================================================================
# pg_query: jm:pg_query and the libpg_query it links.
# ============================================================================

pg_query_lib := if os() == "windows" { "pg_query/lib/pg_query.lib" } else { "pg_query/lib/pg_query.a" }
# libpg_query compile flags: upstream's Makefile exactly, less its -g and at
# -O2 rather than -O3. -fno-strict-aliasing and -fwrapv are not taste — the
# PostgreSQL sources are written against them and miscompile without. The
# three -Wno- suppress warnings in generated parser code.
pg_query_flags := "-fno-strict-aliasing -fwrapv -fPIC -O2 " + \
  "-Ipg_query/vendor -Ipg_query/vendor/vendor -Ipg_query/vendor/src/include " + \
  "-Ipg_query/vendor/src/postgres/include " + \
  "-Wno-unused-function -Wno-unused-value -Wno-unused-variable"

# Like wasm3 this is a tree, so the objects go to a scratch directory beside
# the archive and staleness is any source newer than it. It is 86 translation
# units of PostgreSQL, so the first build takes about twenty seconds.
#
# The protobuf objects are compiled even though this binding only wants the
# JSON API: pg_query_parse.c holds pg_query_parse_protobuf beside
# pg_query_parse, so the object that defines the one we call also references
# pg_query_nodes_to_protobuf, and a JSON-only archive fails to link. Measured,
# not assumed. Upstream's file list it is.
#
# Compile the vendored libpg_query into pg_query/lib if it is stale
[group('pg_query')]
[unix]
pg_query: _worktree-libs
    @mkdir -p pg_query/lib/obj
    @if [ ! -f {{pg_query_lib}} ] || [ -n "$(find pg_query/vendor -name '*.[ch]' -newer {{pg_query_lib}} -print -quit)" ]; then \
        echo "{{cc}} libpg_query -> {{pg_query_lib}}"; \
        for f in pg_query/vendor/src/*.c pg_query/vendor/src/postgres/*.c \
                 pg_query/vendor/protobuf/*.c pg_query/vendor/vendor/*/*.c; do \
            {{cc}} {{pg_query_flags}} -c $f -o pg_query/lib/obj/$(basename $f .c).o || exit 1; \
        done; \
        ar rcs {{pg_query_lib}} pg_query/lib/obj/*.o; \
    fi

# Windows wants the win32 port headers, and win32_msvc's shims for the
# unistd.h and dirent.h the sources include (CI compiles this file set
# with these flags on windows-latest).
[group('pg_query')]
[windows]
pg_query: _worktree-libs
    @if (!(Test-Path {{pg_query_lib}})) { \
        New-Item -ItemType Directory -Force pg_query/lib/obj | Out-Null; \
        Get-ChildItem -Recurse pg_query/vendor/src/*.c, pg_query/vendor/protobuf/*.c, pg_query/vendor/vendor/*.c | ForEach-Object { cl /nologo /O2 {{pg_query_flags}} /I pg_query/vendor/src/postgres/include/port/win32 /I pg_query/vendor/src/postgres/include/port/win32_msvc /c $_.FullName /Fopg_query/lib/obj/ }; \
        lib /nologo /OUT:{{pg_query_lib}} pg_query/lib/obj/*.obj \
    }

# nodes.odin is generated and checked in, so nothing here depends on it: this
# is for after the vendored parser is bumped. The schema it reads is
# libpg_query's own, the same input upstream generates its Go and Ruby
# bindings from, and pg_query_test.odin's schema_conforms holds the checked-in
# file against it on every `just test`.
#
# Regenerate pg_query/nodes.odin from the vendored schema
[group('pg_query')]
pg_query-gen:
    mkdir -p build/debug
    {{odin}} build pg_query/gen {{flags}} -out:build/debug/pg_query-gen{{exe}}
    build/debug/pg_query-gen{{exe}} pg_query/vendor/srcdata pg_query/nodes.odin

# ============================================================================
# git: jm:git and the libgit2 it links.
# ============================================================================

libgit2_lib := if os() == "windows" { "git/lib/git2.lib" } else { "git/lib/libgit2.a" }
# libgit2 is C with its own CMake tree, fetched into build/src at the tag the
# binding was written against (v1.9.7). HTTPS uses the platform: WinHTTP,
# SecureTransport, and on Linux OpenSSL loaded at run time, so the archive
# links against no distribution's libssl. SSH runs the platform's ssh
# binary (USE_SSH=exec). zlib, the regex engine and the HTTP parser are the
# bundled ones, so nothing else is needed on the machine.
libgit2_rev := "49e408b3208bc3093757a1c2db938d3590f3f412"
libgit2_https := if os() == "macos" { "SecureTransport" } else { "OpenSSL-Dynamic" }

# Compile libgit2 into git/lib if it is missing
[group('git')]
[unix]
libgit2: _worktree-libs
    @mkdir -p git/lib build
    @if [ ! -f {{libgit2_lib}} ]; then \
        {{just}} fetch build/src/libgit2 https://github.com/libgit2/libgit2 {{libgit2_rev}} || exit 1; \
        echo "cmake libgit2 -> {{libgit2_lib}}"; \
        cmake --fresh -S build/src/libgit2 -B build/libgit2 -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
            -DBUILD_TESTS=OFF -DBUILD_CLI=OFF -DUSE_SSH=exec -DUSE_HTTPS={{libgit2_https}} \
            -DUSE_BUNDLED_ZLIB=ON -DREGEX_BACKEND=builtin -DUSE_HTTP_PARSER=builtin \
            -DUSE_NTLMCLIENT=OFF -DUSE_SHA256=builtin > build/libgit2.log 2>&1 || exit 1; \
        cmake --build build/libgit2 --config Release --parallel >> build/libgit2.log 2>&1 || exit 1; \
        cp build/libgit2/libgit2.a {{libgit2_lib}}; \
    fi

# Compile libgit2 into git/lib if it is missing
[group('git')]
[windows]
libgit2: _worktree-libs
    @mkdir -p git/lib build
    @if [ ! -f {{libgit2_lib}} ]; then \
        {{just}} fetch build/src/libgit2 https://github.com/libgit2/libgit2 {{libgit2_rev}} || exit 1; \
        echo "cmake libgit2 -> {{libgit2_lib}}"; \
        cmake --fresh -S build/src/libgit2 -B build/libgit2 -G Ninja -DCMAKE_MAKE_PROGRAM="$(command -v ninja.exe)" \
            -DCMAKE_C_COMPILER=clang-cl -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded \
            -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTS=OFF -DBUILD_CLI=OFF \
            -DUSE_SSH=exec -DUSE_HTTPS=WinHTTP -DUSE_BUNDLED_ZLIB=ON -DREGEX_BACKEND=builtin \
            -DUSE_HTTP_PARSER=builtin -DUSE_NTLMCLIENT=OFF -DUSE_SHA256=builtin > build/libgit2.log 2>&1 || exit 1; \
        cmake --build build/libgit2 --parallel >> build/libgit2.log 2>&1 || exit 1; \
        cp build/libgit2/git2.lib {{libgit2_lib}}; \
    fi

# ============================================================================
# fuzz: tools/jm-fuzz, every jm:fuzz suite in one program.
# ============================================================================

# Arguments pass straight through: `just fuzz "tar -for=5m"`,
# `just fuzz "sqlite3 -seed=12345"`, `just fuzz "-corpus=build/corpus"`.

# Run every jm:fuzz suite until something gives
[group('fuzz')]
fuzz args="-for=30s": sqlite zstd wasm pg_query blend2d kb libgit2
    mkdir -p build/debug
    {{odin}} build tools/jm-fuzz -debug {{flags}} {{link}} -out:build/debug/jm-fuzz{{exe}}
    build/debug/jm-fuzz{{exe}} {{args}}

# A child process per case: a crash or a hang is reported, not fatal
[group('fuzz')]
fuzz-isolate args="-for=5m": sqlite zstd wasm pg_query blend2d kb libgit2
    mkdir -p build/debug
    {{odin}} build tools/jm-fuzz -debug {{flags}} {{link}} -out:build/debug/jm-fuzz{{exe}}
    build/debug/jm-fuzz{{exe}} -isolate {{args}}

# The same, under AddressSanitizer
[group('fuzz')]
[unix]
fuzz-asan args="-for=30s": sqlite wasm pg_query blend2d kb libgit2
    mkdir -p build/debug
    {{odin}} build tools/jm-fuzz -debug -sanitize:address {{flags}} {{link}} -out:build/debug/jm-fuzz-asan
    build/debug/jm-fuzz-asan {{args}}

# ============================================================================
# ui: jm:ui, the Blend2D and kb_text_shape it links, SDL3 for its windows, and
# the demos that are not one design system's.
# ============================================================================

blend2d_lib := if os() == "windows" { "ui/blend2d/lib/blend2d.lib" } else { "ui/blend2d/lib/libblend2d.a" }
kb_lib := if os() == "windows" { "ui/kb/lib/kb_text_shape.lib" } else { "ui/kb/lib/kb_text_shape.a" }

# AccessKit's C bindings (ui/accesskit) are fetched as the upstream
# release, not built: the zip holds prebuilt libraries for every desktop
# target, so no Rust toolchain is needed here. Linux and macOS keep the
# static archive for this machine, Linux with its debug sections stripped
# (46 MB to 8 MB; the code the linker takes is under 2 MB); Windows keeps
# the DLL and its import library, since the static archive there was built
# against the dynamic C runtime, which Odin does not link. The DLL goes
# beside whatever runs: `test` and `sdl3` copy it.
accesskit_lib := if os() == "windows" { "ui/accesskit/lib/accesskit.lib" } else { "ui/accesskit/lib/libaccesskit.a" }
accesskit_ver := "0.23.1"
accesskit_sha := "35b7ca8a6f1e038b5da35e1e9e5a0adaed9bfcf21e1496d29598fbbadcc7043f"

# Fetch AccessKit's prebuilt library into ui/accesskit/lib if it is missing
[group('ui')]
accesskit: _worktree-libs
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p ui/accesskit/lib build
    [ -f {{accesskit_lib}} ] && exit 0
    zip=build/accesskit-c-{{accesskit_ver}}.zip
    if [ ! -f "$zip" ]; then
      echo "fetch accesskit-c {{accesskit_ver}} -> $zip"
      curl -sSL --max-time 600 -o "$zip" "https://github.com/AccessKit/accesskit-c/releases/download/{{accesskit_ver}}/accesskit-c-{{accesskit_ver}}.zip"
    fi
    if command -v sha256sum >/dev/null; then sum=$(sha256sum "$zip" | cut -d' ' -f1); else sum=$(shasum -a 256 "$zip" | cut -d' ' -f1); fi
    [ "$sum" = "{{accesskit_sha}}" ] || { echo "accesskit: $zip has sha256 $sum, expected {{accesskit_sha}}" >&2; exit 1; }
    case "$(uname -s)-$(uname -m)" in
      Linux-x86_64) sub=linux/x86_64/static; files="libaccesskit.a" ;;
      Linux-i686) sub=linux/x86/static; files="libaccesskit.a" ;;
      Darwin-arm64) sub=macos/arm64/static; files="libaccesskit.a" ;;
      Darwin-x86_64) sub=macos/x86_64/static; files="libaccesskit.a" ;;
      MINGW*-x86_64|MSYS*-x86_64|CYGWIN*-x86_64) sub=windows/x86_64/msvc/shared; files="accesskit.lib accesskit.dll" ;;
      *) echo "accesskit: no prebuilt library for $(uname -s)-$(uname -m)" >&2; exit 1 ;;
    esac
    for f in $files; do
      member="accesskit-c-{{accesskit_ver}}/lib/$sub/$f"
      if command -v unzip >/dev/null; then unzip -qo "$zip" "$member" -d build/accesskit; else 7z x -y -obuild/accesskit "$zip" "$member" >/dev/null; fi
      cp "build/accesskit/$member" ui/accesskit/lib/
    done
    if [ "$(uname -s)" = Linux ]; then strip --strip-debug ui/accesskit/lib/libaccesskit.a; fi
    echo "accesskit -> ui/accesskit/lib ($(du -sh ui/accesskit/lib | cut -f1))"
# Blend2D is C++ with asmjit inside, built by its own CMake tree rather than
# vendored here: 29 MB of source is fetched into build/src instead, at the
# upstream commits the binding in ui/blend2d was generated from (Blend2D
# 0.21.1). The binding's foreign import names the C++ runtime, so nothing that
# links it passes a linker flag.
blend2d_rev := "3525b5fc1506cf1845901f0c2469d7d13758f573"
asmjit_rev  := "5134d396bd00c1b63259387acdbb12dfdf009f9b"

# Compile Blend2D into ui/blend2d/lib if it is missing
[group('ui')]
[unix]
blend2d: _worktree-libs
    @mkdir -p ui/blend2d/lib build
    @if [ ! -f {{blend2d_lib}} ]; then \
        {{just}} fetch build/src/blend2d https://github.com/blend2d/blend2d {{blend2d_rev}} || exit 1; \
        {{just}} fetch build/src/asmjit https://github.com/asmjit/asmjit {{asmjit_rev}} || exit 1; \
        echo "cmake blend2d -> {{blend2d_lib}}"; \
        cmake --fresh -S build/src/blend2d -B build/blend2d -DASMJIT_DIR="{{root}}/build/src/asmjit" \
            -DCMAKE_BUILD_TYPE=Release -DBLEND2D_STATIC=ON -DBLEND2D_TEST=OFF > build/blend2d.log 2>&1 || exit 1; \
        cmake --build build/blend2d --config Release --parallel >> build/blend2d.log 2>&1 || exit 1; \
        cp build/blend2d/libblend2d.a {{blend2d_lib}}; \
    fi

# MSVC hits an internal compiler error on Blend2D's AVX2 deflate decoder, so
# this builds with clang-cl. The static CRT matches what Odin links. ninja.exe
# is named because a ninja wrapper earlier on PATH (depot_tools) is a script
# CMake cannot run.
#
# Compile Blend2D into ui/blend2d/lib if it is missing
[group('ui')]
[windows]
blend2d: _worktree-libs
    @mkdir -p ui/blend2d/lib build
    @if [ ! -f {{blend2d_lib}} ]; then \
        {{just}} fetch build/src/blend2d https://github.com/blend2d/blend2d {{blend2d_rev}} || exit 1; \
        {{just}} fetch build/src/asmjit https://github.com/asmjit/asmjit {{asmjit_rev}} || exit 1; \
        echo "cmake blend2d -> {{blend2d_lib}}"; \
        cmake --fresh -S build/src/blend2d -B build/blend2d -DASMJIT_DIR="{{root}}/build/src/asmjit" \
            -G Ninja -DCMAKE_MAKE_PROGRAM="$(command -v ninja.exe)" \
            -DCMAKE_C_COMPILER=clang-cl -DCMAKE_CXX_COMPILER=clang-cl -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded \
            -DCMAKE_BUILD_TYPE=Release -DBLEND2D_STATIC=ON -DBLEND2D_TEST=OFF > build/blend2d.log 2>&1 || exit 1; \
        cmake --build build/blend2d --parallel >> build/blend2d.log 2>&1 || exit 1; \
        cp build/blend2d/blend2d.lib {{blend2d_lib}}; \
    fi

# Compile the vendored kb_text_shape (ui/kb, jm:ui/shape's shaper) into
# ui/kb/lib if it is stale. C11 for the layout asserts in kb_text_shape.c.
# kb byte-swaps font tables by writing a run of u16 from a struct's first
# field on through the ones after it, which GCC's object-size check reads
# as overflowing that first field: -Wno-stringop-overflow.
#
# Compile the vendored kb_text_shape into ui/kb/lib if it is stale
[group('ui')]
[unix]
kb: _worktree-libs
    @mkdir -p ui/kb/lib
    @if [ ! -f {{kb_lib}} ] || [ ui/kb/vendor/kb_text_shape.c -nt {{kb_lib}} ] || [ ui/kb/vendor/kb_text_shape.h -nt {{kb_lib}} ]; then \
        echo "{{cc}} kb_text_shape -> {{kb_lib}}"; \
        {{cc}} -std=c11 -O2 -fPIC -Wno-stringop-overflow -c ui/kb/vendor/kb_text_shape.c -o ui/kb/lib/kb_text_shape.o; \
        ar rcs {{kb_lib}} ui/kb/lib/kb_text_shape.o; \
    fi

[group('ui')]
[windows]
kb: _worktree-libs
    @New-Item -ItemType Directory -Force ui/kb/lib | Out-Null
    @if (!(Test-Path {{kb_lib}}) -or (Get-Item ui/kb/vendor/kb_text_shape.c).LastWriteTime -gt (Get-Item {{kb_lib}}).LastWriteTime -or (Get-Item ui/kb/vendor/kb_text_shape.h).LastWriteTime -gt (Get-Item {{kb_lib}}).LastWriteTime) { \
        cl /nologo /std:c11 /O2 /c ui/kb/vendor/kb_text_shape.c /Foui/kb/lib/kb_text_shape.obj; \
        lib /nologo /OUT:{{kb_lib}} ui/kb/lib/kb_text_shape.obj \
    }

# vendor:sdl3 links SDL3.dll at load time on Windows, so the demo cannot start
# without it beside the exe.
#
# Copy SDL3.dll, and AccessKit's DLL, next to the demo
[group('ui')]
[windows]
sdl3:
    @mkdir -p build/debug
    @cp "$({{odin}} root)/vendor/sdl3/SDL3.dll" build/debug/
    @cp ui/accesskit/lib/accesskit.dll build/debug/ 2>/dev/null || true

# Nothing to do: SDL3 is a system library off Windows
[group('ui')]
[unix]
sdl3:

# examples/hot-counter/child, the real subprocess ui/sdl's own test
# spawns to prove the host/child protocol against a real process, not a
# stub. blend2d only: the child never links SDL.
#
# Build the child process ui/sdl's tests spawn
[group('ui')]
hot-counter-child: blend2d kb
    mkdir -p build/debug
    {{odin}} build examples/hot-counter/child -debug {{flags}} {{link}} -out:build/debug/hot-counter-child{{exe}}

# `just bench-ui "-w 1800 -h 1200"` measures at another size.
#
# Time jm:ui layout and the Blend2D executor per frame
[group('ui')]
bench-ui args="": blend2d kb
    mkdir -p build/release
    {{odin}} build tools/ui-bench -o:speed {{flags}} {{link}} -out:build/release/ui-bench{{exe}}
    build/release/ui-bench{{exe}} {{args}}

# _hot runs examples/NAME as a hot-reloaded app: hot-watch rebuilds the
# child, and the host too when one of DIRS changes, while the host's window
# is open. Ending the recipe, however it ends, stops both.
[private]
[arg("mode", pattern="debug|release")]
_hot name mode dirs: blend2d kb sdl3
    #!/usr/bin/env bash
    set -eu
    mkdir -p build/debug
    {{odin}} build tools/hot-watch -debug {{flags}} -out:build/debug/hot-watch{{exe}}
    {{odin}} build examples/{{name}}/host {{ if mode == "release" { "-o:speed" } else { "-debug" } }} {{flags}} {{link}} -out:build/debug/{{name}}-host{{exe}}
    build/debug/hot-watch{{exe}} examples/{{name}}/child build/debug/{{name}}.watch {{ if mode == "release" { "-release" } else { "" } }} -host examples/{{name}}/host build/debug/{{name}}-host{{exe}} {{dirs}} &
    watch=$!
    build/debug/{{name}}-host{{exe}} build/debug/{{name}}.watch &
    host=$!
    trap 'kill $watch $host 2>/dev/null' EXIT
    wait $host

# The demo is the proof that the pieces of jm:ui fit: a window, or the same
# frame as text or as a PNG without one.
# Build the hot-reloaded architecture-diagram demo: a live-editable
# diagram of jm:ui's own input/layout/render pipeline, respawned by
# tools/hot-watch every time examples/hot-architecture/child changes.
# Prints the two commands to run it (in separate terminals) rather than
# launching them itself: backgrounding a long-running process portably
# from one just recipe is more trouble than it is worth.
#
# Build the hot-reloaded architecture diagram and print how to run it
[group('ui')]
hot-architecture: blend2d kb sdl3
    mkdir -p build/debug
    {{odin}} build tools/hot-watch -debug {{flags}} -out:build/debug/hot-watch{{exe}}
    {{odin}} build examples/hot-architecture/host -debug {{flags}} {{link}} -out:build/debug/hot-architecture-host{{exe}}
    @echo "terminal 1: build/debug/hot-watch{{exe}} examples/hot-architecture/child build/debug/hot-architecture.watch"
    @echo "terminal 2: build/debug/hot-architecture-host{{exe}} build/debug/hot-architecture.watch"
    @echo "then edit examples/hot-architecture/child/main.odin and watch the window update."

# Every page in every theme, as text: what the window or a clip cuts off
# at a side, and groups with several Tab stops. Prints the lines that are
# new against the kitchen's lint.txt, which its test enforces, and those
# gone from it; `accept` rewrites lint.txt to what the kitchen draws now.
# Read this before rendering a PNG to look at.
#
# Lint a kitchen's pages against its lint.txt
[group('ui')]
[arg("kit", pattern="primer|fluent|material")]
[arg("action", pattern="|accept")]
kitchen-lint kit action="": blend2d kb
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p build/debug
    {{odin}} build examples/{{kit}}-kitchen/child -debug {{flags}} {{link}} -out:build/debug/{{kit}}-kitchen-child{{exe}}
    export LC_ALL=C # comm wants the byte order lint sorts in
    accepted=examples/{{kit}}-kitchen/lint.txt
    now=build/{{kit}}-lint.txt
    build/debug/{{kit}}-kitchen-child{{exe}} -lint > "$now"
    if [ "{{action}}" = accept ]; then cp "$now" "$accepted"; echo "wrote $accepted"; exit 0; fi
    new=$(comm -13 "$accepted" "$now")
    gone=$(comm -23 "$accepted" "$now")
    if [ -n "$gone" ]; then printf 'gone from lint.txt (fixed? run accept):\n%s\n' "$gone"; fi
    if [ -n "$new" ]; then printf 'new:\n%s\n' "$new"; exit 1; fi
    echo "kitchen-lint: nothing new against $accepted"

# examples/text-lab: specimens of every text feature the shaper must
# handle (Latin features, complex scripts, bidi, emoji) with the shaper's
# clusters and caret stops drawn over them, plus live inputs. Hot-reloads
# like material-kitchen, watching ui and ui/fluent too.
#
# Build and open the hot-reloaded text lab
[group('ui')]
[arg("mode", pattern="debug|release")]
text-lab mode="debug": (_hot "text-lab" mode "ui ui/fluent")

# Render one text-lab page, whole, to build/text-<page>.png, no window
[group('ui')]
text-png page="Scripts": blend2d kb
    mkdir -p build/debug
    {{odin}} build examples/text-lab/child -debug {{flags}} {{link}} -out:build/debug/text-lab-child{{exe}}
    build/debug/text-lab-child{{exe}} -full -page "{{page}}" -png "build/text-{{page}}.png"

# ============================================================================
# ui/material: jm:ui/material, its kitchen, and the m3e-kit at tools/material
# that its generated code comes from.
# ============================================================================

# examples/material-kitchen: every jm:ui/material component, one page
# each. Build it and open its window; hot-watch runs in the background
# while the window is open, watching ui, ui/material and examples/kitchen
# too, so editing a component or the kitchen scaffold rebuilds and
# respawns it, and a change there rebuilds the host, which restarts itself
# if the ops encoding changed. Ending the recipe, however it ends, stops
# both.
#
# Build and open the hot-reloaded Material 3 kitchen
[group('ui/material')]
[arg("mode", pattern="debug|release")]
material-kitchen mode="debug": (_hot "material-kitchen" mode "ui ui/material examples/kitchen")

# Render one material-kitchen page to build/material-<page>.png, no window
[group('ui/material')]
material-png page="Buttons": blend2d kb
    mkdir -p build/debug
    {{odin}} build examples/material-kitchen/child -debug {{flags}} {{link}} -out:build/debug/material-kitchen-child{{exe}}
    build/debug/material-kitchen-child{{exe}} -page "{{page}}" -png "build/material-{{page}}.png"

# The m3e-kit's Compose token sources and where androidx keeps them.
m3e_kit := "tools/material"
m3e_tokens_path := "compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/tokens"

# Regenerate ui/material/tokens/tokens.odin from the m3e-kit's resolved
# tokens.
#
# Regenerate ui/material/tokens from the m3e-kit
[group('ui/material')]
material-tokens:
    {{odin}} run tools/design-tokens {{flags}} -- material {{m3e_kit}}/tokens/m3e.resolved.json ui/material/tokens/tokens.odin

# Regenerate ui/material/shape_data.odin, the loading indicator's morph
# pairs, from the m3e-kit's shapes/morphs.json.
#
# Regenerate ui/material/shape_data.odin from the m3e-kit
[group('ui/material')]
material-shapes:
    {{odin}} run {{m3e_kit}}/shape-data {{flags}} -- {{m3e_kit}}/shapes/morphs.json ui/material/shape_data.odin

# Re-parse the kit's Compose sources into its tokens/*.json
[group('ui/material')]
material-kit-tokens:
    {{odin}} run {{m3e_kit}}/m3e-tokens {{flags}} -- {{m3e_kit}}/upstream {{m3e_kit}}/tokens

# Needs java 21 or later; the graphics-shapes jars are fetched and cached.
#
# Regenerate the kit's shapes/ from graphics-shapes
[group('ui/material')]
material-kit-shapes:
    {{m3e_kit}}/shapes/gen/run.sh

# Replaces upstream/ wholesale, so a token file androidx deleted goes too.
# Needs gh.
#
# Pull the kit's Compose token sources at androidx-main
[group('ui/material')]
material-kit-fetch:
    #!/usr/bin/env bash
    set -euo pipefail
    sha=$(gh api repos/androidx/androidx/commits/androidx-main --jq .sha)
    tmp=$(mktemp -d)
    gh api "repos/androidx/androidx/contents/{{m3e_tokens_path}}?ref=$sha" --jq '.[].name' |
        xargs -P 16 -I{} curl -sfL --max-time 60 -o "$tmp/{}" \
            "https://raw.githubusercontent.com/androidx/androidx/$sha/{{m3e_tokens_path}}/{}"
    rm -rf {{m3e_kit}}/upstream/tokens
    mv "$tmp" {{m3e_kit}}/upstream/tokens
    echo "$sha" > {{m3e_kit}}/upstream/COMMIT
    echo "fetched $(ls {{m3e_kit}}/upstream/tokens | wc -l) files at $sha"

# Regenerate the kit's kit.json, the index an agent reads first
[group('ui/material')]
material-kit-index:
    {{m3e_kit}}/scripts/index.sh

# Needs jq and the jsonschema CLI.
#
# Validate the kit: schemas, token paths, a fresh kit.json
[group('ui/material')]
material-kit-check:
    {{m3e_kit}}/scripts/check.sh

# Bundle the kit into kit/index.html, a page for people
[group('ui/material')]
material-kit-page:
    {{m3e_kit}}/kit/build.sh

# ============================================================================
# ui/fluent: jm:ui/fluent, its kitchen, its font, and the fluent-kit and
# Fluent icons at tools/fluent that its generated code comes from.
# ============================================================================

# examples/fluent-kitchen: every jm:ui/fluent component, one page each,
# hot-reloaded like material-kitchen. Selawik, the kit's stand-in for
# Segoe UI, is read from ~/.local/share/fonts/selawik (just fluent-fonts).
#
# Build and open the hot-reloaded Fluent 2 kitchen
[group('ui/fluent')]
[arg("mode", pattern="debug|release")]
fluent-kitchen mode="debug": (_hot "fluent-kitchen" mode "ui ui/fluent examples/kitchen")

# Render one fluent-kitchen page to build/fluent-<page>.png, no window
[group('ui/fluent')]
fluent-png page="Button": blend2d kb
    mkdir -p build/debug
    {{odin}} build examples/fluent-kitchen/child -debug {{flags}} {{link}} -out:build/debug/fluent-kitchen-child{{exe}}
    build/debug/fluent-kitchen-child{{exe}} -page "{{page}}" -png "build/fluent-{{page}}.png"

# ============================================================================
# ui/primer: the primer-kit at tools/primer, GitHub's Primer read from
# Primer React, @primer/primitives and @primer/octicons.
# ============================================================================

# examples/primer-kitchen: every jm:ui/primer component, one page each,
# hot-reloaded like fluent-kitchen, in the system sans.
#
# Build and open the hot-reloaded Primer kitchen
[group('ui/primer')]
[arg("mode", pattern="debug|release")]
primer-kitchen mode="debug": (_hot "primer-kitchen" mode "ui ui/primer examples/kitchen")

# Render one primer-kitchen page to build/primer-<page>.png, no window
[group('ui/primer')]
primer-png page="Button" theme="Light": blend2d kb
    mkdir -p build/debug
    {{odin}} build examples/primer-kitchen/child -debug {{flags}} {{link}} -out:build/debug/primer-kitchen-child{{exe}}
    build/debug/primer-kitchen-child{{exe}} -theme "{{theme}}" -page "{{page}}" -png "build/primer-{{page}}.png"

primer_kit := "tools/primer"

# Regenerate ui/primer/tokens from the primer-kit
[group('ui/primer')]
primer-tokens:
    {{odin}} run tools/design-tokens {{flags}} -- primer {{primer_kit}}/tokens/primer.resolved.json ui/primer/tokens/tokens.odin

# Regenerate ui/primer/icon_data.odin from the kit's vendored octicons
[group('ui/primer')]
primer-icons:
    {{odin}} run {{primer_kit}}/icon-data {{flags}} -- {{primer_kit}}/upstream/npm/octicons/data.json ui/primer/icon_data.odin

# Replaces upstream/ wholesale: primer/react at the commit an @primer/react
# release tag names, then @primer/primitives and @primer/octicons at the
# versions given. Needs gh, npm and jq.
#
# Re-vendor the kit's upstream/ at pinned Primer releases
[group('ui/primer')]
primer-kit-fetch react="38.40.1" primitives="11.10.0" octicons="19.38.0":
    {{primer_kit}}/scripts/fetch.sh {{react}} {{primitives}} {{octicons}}

# Regenerate the kit's tokens/primer.resolved.json from the vendored primitives
[group('ui/primer')]
primer-kit-tokens:
    cd {{primer_kit}} && node scripts/tokens.mjs

# Regenerate the kit's kit.json, the index an agent reads first
[group('ui/primer')]
primer-kit-index:
    {{primer_kit}}/scripts/index.sh

# Needs jq, node, and the jsonschema CLI or uv to run it.
#
# Validate the kit: schemas, token paths, cited sources, fresh kit.json and tokens
[group('ui/primer')]
primer-kit-check:
    {{primer_kit}}/scripts/check.sh

# ============================================================================
# ui/example: whole applications on jm:ui, one directory under examples/
# each, built and run as a user would.
# ============================================================================

# examples/todo: TodoMVC in Fluent, SQLite as the data engine, a stream
# pipeline across four threads; see the README's UI section. `just todo`
# keeps todo.db in the working directory; `just todo -memory` keeps
# nothing, and `just todo path.db` opens that database.
#
# Build and open the todo application
[group('ui/example')]
todo args="": sqlite blend2d kb sdl3
    mkdir -p build/debug
    {{odin}} build examples/todo -debug {{flags}} {{link}} -out:build/debug/todo{{exe}}
    build/debug/todo{{exe}} {{args}}

# Run the todo application's suites, the end-to-end one on real threads and a database
[group('ui/example')]
todo-test: sqlite blend2d kb
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p build/test
    for p in examples/todo/shapes examples/todo/logic examples/todo/store examples/todo/view examples/todo/app; do
      {{odin}} test "$p" {{flags}} {{link}} -out:build/test/$(echo "$p" | tr / -){{exe}}
    done

# examples/gallery: a grid of ten thousand pictures made on demand, each a
# need while its row is in view, abandoned when scrolled away before it
# is done. Pictures go under the temp directory, a folder per run.
#
# Build and open the gallery application
[group('ui/example')]
[arg("mode", pattern="debug|release")]
gallery mode="debug": blend2d kb sdl3
    mkdir -p build/debug
    {{odin}} build examples/gallery {{ if mode == "release" { "-o:speed" } else { "-debug" } }} {{flags}} {{link}} -out:build/debug/gallery{{exe}}
    build/debug/gallery{{exe}}

# Run the gallery's suites, the end-to-end one on real workers and files
[group('ui/example')]
gallery-test: blend2d kb
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p build/test
    for p in examples/gallery/shapes examples/gallery/gen examples/gallery/cache examples/gallery/view examples/gallery/app; do
      {{odin}} test "$p" {{flags}} {{link}} -out:build/test/$(echo "$p" | tr / -){{exe}}
    done

# examples/files: a file browser over the real filesystem, folders read
# and thumbnails made on workers as they come into view, a double click
# entering a folder or opening a file with the system.
#
# Build and open the file browser on a folder, the home folder by default
[group('ui/example')]
files path="": sqlite blend2d kb sdl3
    mkdir -p build/debug
    {{odin}} build examples/files -debug {{flags}} {{link}} -out:build/debug/files{{exe}}
    build/debug/files{{exe}} {{path}}

# Run the file browser's suites, the end-to-end one on a real folder
[group('ui/example')]
files-test: sqlite blend2d kb
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p build/test
    for p in examples/files/shapes examples/files/fs examples/files/store examples/files/view examples/files/app; do
      {{odin}} test "$p" {{flags}} {{link}} -out:build/test/$(echo "$p" | tr / -){{exe}}
    done

# examples/7guis: the seven tasks of the 7GUIs benchmark, a program each
# with its tests beside it. `just sevenguis cells -png build/cells.png`
# renders a task's first frame with no window.
#
# Build and open one 7GUIs task
[group('ui/example')]
[arg("task", pattern="counter|temperature|flight|timer|crud|circles|cells")]
sevenguis task *args: blend2d kb sdl3
    mkdir -p build/debug
    {{odin}} build examples/7guis/{{task}} -debug {{flags}} {{link}} -out:build/debug/7guis-{{task}}{{exe}}
    build/debug/7guis-{{task}}{{exe}} {{args}}

# Run the suites of all seven 7GUIs tasks
[group('ui/example')]
sevenguis-test: blend2d kb
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p build/test
    for task in counter temperature flight timer crud circles cells; do
      {{odin}} test examples/7guis/$task {{flags}} {{link}} -out:build/test/7guis-$task{{exe}}
    done

# Fetch Selawik regular, semibold and bold (OFL-1.1) from microsoft/Selawik
# release 1.01 into ~/.local/share/fonts/selawik for the fluent kitchen.
#
# Fetch Selawik into ~/.local/share/fonts/selawik
[group('ui/fluent')]
fluent-fonts:
    #!/usr/bin/env bash
    set -eu
    dir="$HOME/.local/share/fonts/selawik"
    mkdir -p "$dir"
    tmp=$(mktemp -d)
    curl -sSL --max-time 120 -o "$tmp/selawik.zip" https://github.com/microsoft/Selawik/releases/download/1.01/Selawik_Release.zip
    unzip -o -q "$tmp/selawik.zip" -d "$tmp/selawik"
    cp "$tmp/selawik/selawk.ttf" "$tmp/selawik/selawksb.ttf" "$tmp/selawik/selawkb.ttf" "$dir/"
    curl -sSL --max-time 30 -o "$dir/LICENSE.txt" https://raw.githubusercontent.com/microsoft/Selawik/master/LICENSE.txt
    rm -rf "$tmp"

fluent_kit := "tools/fluent"

# Regenerate ui/fluent/tokens from the fluent-kit
[group('ui/fluent')]
fluent-tokens:
    {{odin}} run tools/design-tokens {{flags}} -- fluent {{fluent_kit}}/tokens/fluent.resolved.json ui/fluent/tokens/tokens.odin

# Regenerate ui/fluent/icon_data.odin from the Fluent UI System Icons in
# tools/fluent/icons, which fluent-icons-fetch fills.
#
# Regenerate ui/fluent/icon_data.odin from the vendored icons
[group('ui/fluent')]
fluent-icons:
    {{odin}} run {{fluent_kit}}/icon-data {{flags}} -- {{fluent_kit}}/icons ui/fluent/icon_data.odin

# Fetch the 20px regular and filled SVG of every icon named in icons.txt
# from microsoft/fluentui-system-icons (MIT), with the licence beside
# them, at ref: the pinned commit in icons/COMMIT unless another ref is
# given (`just fluent-icons-fetch main` bumps it). The set is replaced
# whole, so an icon dropped from icons.txt goes too.
#
# Fetch the icons icons.txt names at a pinned commit
[group('ui/fluent')]
fluent-icons-fetch ref="":
    #!/usr/bin/env bash
    set -euo pipefail
    dir={{fluent_kit}}/icons
    ref="{{ref}}"
    [ -n "$ref" ] || ref=$(cat "$dir/COMMIT")
    repo=https://github.com/microsoft/fluentui-system-icons
    sha=$ref
    if ! [[ $ref =~ ^[0-9a-f]{40}$ ]]; then sha=$(git ls-remote "$repo" "$ref" | cut -f1 | head -1); fi
    [ -n "$sha" ] || { echo "no ref $ref in $repo" >&2; exit 1; }
    base=https://raw.githubusercontent.com/microsoft/fluentui-system-icons/$sha
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    curl -sSfL --max-time 30 -o "$tmp/LICENSE" "$base/LICENSE"
    while read -r name; do
      folder=$(echo "$name" | sed 's/_/ /g; s/\b./\u&/g; s/ /%20/g')
      for v in regular filled; do
        curl -sSfL --max-time 30 -o "$tmp/ic_fluent_${name}_20_$v.svg" "$base/assets/$folder/SVG/ic_fluent_${name}_20_$v.svg"
      done
    done < "$dir/icons.txt"
    rm -f "$dir"/ic_fluent_*.svg "$dir/LICENSE"
    mv "$tmp"/* "$dir"/
    echo "$sha" > "$dir/COMMIT"
    echo "fetched $(ls "$dir"/ic_fluent_*.svg | wc -l) icons at $sha"

# Regenerate the kit's tokens/*.json from the vendored @fluentui/tokens
[group('ui/fluent')]
fluent-kit-tokens:
    cd {{fluent_kit}} && node scripts/tokens.mjs

# Replaces upstream/ wholesale at one commit of microsoft/fluentui: the
# token sources, the focus helpers, and each spec'd component's styles and
# types files; then the @fluentui/tokens package that commit names. Needs
# gh and npm.
#
# Re-vendor the kit's upstream/ at a microsoft/fluentui commit
[group('ui/fluent')]
fluent-kit-fetch commit="master":
    {{fluent_kit}}/scripts/fetch.sh {{commit}}

# Regenerate the kit's kit.json, the index an agent reads first
[group('ui/fluent')]
fluent-kit-index:
    {{fluent_kit}}/scripts/index.sh

# Needs jq, node and the jsonschema CLI.
#
# Validate the kit: schemas, token paths, cited sources, fresh kit.json and tokens
[group('ui/fluent')]
fluent-kit-check:
    {{fluent_kit}}/scripts/check.sh

# Bundle the kit into kit/index.html, a page for people
[group('ui/fluent')]
fluent-kit-page:
    {{fluent_kit}}/kit/build.sh
