# Standard recipes: build, release, clean, test, install, plus check and example.
#
#   just build     debug odin-run                          -> build/debug/odin-run
#   just release   optimised odin-run                      -> build/release/odin-run
#   just test      run every package's tests
#   just check     type-check every package for linux, darwin and windows
#   just link      build every program into build/debug
#   just sqlite    compile the vendored SQLite amalgamation into sqlite3/lib
#   just wasm      compile the vendored wasm3 interpreter into wasm/lib
#   just pg_query  compile the vendored libpg_query parser into pg_query/lib
#   just pg_query-gen  regenerate pg_query/nodes.odin from the vendored schema
#   just blend2d   fetch and compile Blend2D into ui/blend2d/lib
#   just libgit2   fetch and compile libgit2 into git/lib
#   just material-kitchen  build and open the hot-reloaded Material 3 kitchen
#   just material-png  render one material-kitchen page headlessly
#   just fluent-kitchen  build and open the hot-reloaded Fluent 2 kitchen
#   just fluent-png  render one fluent-kitchen page headlessly
#   just material-tokens  regenerate ui/material/tokens from the m3e-kit
#   just fluent-tokens  regenerate ui/fluent/tokens from the fluent-kit
#   just fluent-icons  regenerate ui/fluent/icon_data.odin from the vendored Fluent icons
#   just material-shapes  regenerate ui/material/shape_data.odin from the m3e-kit
#   just fuzz      run every jm:fuzz suite for thirty seconds
#   just bench     time jm:wasm against the workloads in tools/wasm-bench
#   just bench-ui  time jm:ui layout and the Blend2D executor per frame
#   just fuzz-isolate  the same, a child process per case
#   just install   release odin-run into ~/.local/bin with this checkout baked in
#   just example   compile and run examples/hello.odin through the collection
#   just clean     remove build/

odin  := env("ODIN", "odin")
root  := replace(justfile_directory(), "\\", "/")
flags := "-vet -strict-style -collection:jm=" + root
exe   := if os() == "windows" { ".exe" } else { "" }
bindir := env("BINDIR", home_directory() / ".local" / "bin")
# Directories that check, test and link leave out, with everything under
# them: SKIP="pq tools/jm-fuzz" where there is no libpq to link.
skip := env("SKIP", "")
# Packages whose tests run alone, on one thread, after the rest: the three
# over wasm3, which is not thread-safe; ui/sdl, whose tests spawn
# hot-counter-child copies sharing one exe path; tar, whose git children
# inherit each other's pipes on Windows; and flow and wasm-bench, whose tests
# measure a split of work or its cost and fail under load.
serial_tests := "wasm wasm/fuzz tools/wasm-bench ui/sdl tar flow"
cc       := env("CC", "cc")
wasm_cc  := env("WASM_CC", "clang")
sqlite_lib := if os() == "windows" { "sqlite3/lib/sqlite3.lib" } else { "sqlite3/lib/sqlite3.a" }
wasm_lib   := if os() == "windows" { "wasm/lib/wasm3.lib" } else { "wasm/lib/wasm3.a" }
pg_query_lib := if os() == "windows" { "pg_query/lib/pg_query.lib" } else { "pg_query/lib/pg_query.a" }
blend2d_lib := if os() == "windows" { "ui/blend2d/lib/blend2d.lib" } else { "ui/blend2d/lib/libblend2d.a" }
libgit2_lib := if os() == "windows" { "git/lib/git2.lib" } else { "git/lib/libgit2.a" }
kb_lib := if os() == "windows" { "ui/kb/lib/kb_text_shape.lib" } else { "ui/kb/lib/kb_text_shape.a" }
# Blend2D is C++ with asmjit inside, built by its own CMake tree rather than
# vendored here: 29 MB of source is fetched into build/src instead, at the
# upstream commits the binding in ui/blend2d was generated from (Blend2D
# 0.21.1). Anything that links it needs libstdc++, except on Windows where
# the MSVC linker finds the C++ runtime itself.
blend2d_rev := "3525b5fc1506cf1845901f0c2469d7d13758f573"
asmjit_rev  := "5134d396bd00c1b63259387acdbb12dfdf009f9b"
# libgit2 is C with its own CMake tree, fetched into build/src at the tag the
# binding was written against (v1.9.7). HTTPS uses the platform: WinHTTP,
# SecureTransport, and on Linux OpenSSL loaded at run time, so the archive
# links against no distribution's libssl. SSH runs the platform's ssh
# binary (USE_SSH=exec). zlib, the regex engine and the HTTP parser are the
# bundled ones, so nothing else is needed on the machine.
libgit2_rev := "49e408b3208bc3093757a1c2db938d3590f3f412"
libgit2_https := if os() == "macos" { "SecureTransport" } else { "OpenSSL-Dynamic" }
# Homebrew keeps libpq keg-only, so on macOS its lib directory is not on the
# linker's search path and jm:pq cannot link without it. LINKFLAGS replaces
# the guess, as CI sets it. Odin takes -extra-linker-flags once, so these and
# the C++ runtime travel together in cxx_link.
libpq_link := if os() == "macos" { `d="$(brew --prefix libpq 2>/dev/null)/lib"; [ -d "$d" ] && echo "-L$d" || true` } else { "" }
linkflags := env("LINKFLAGS", libpq_link)
link := if linkflags == "" { "" } else { "-extra-linker-flags:\"" + linkflags + "\"" }
cxx_link := if os() == "windows" { link } else { "-extra-linker-flags:\"" + trim(linkflags + " -lstdc++") + "\"" }
just := quote(just_executable())

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
# wasm3 compile-time options. The defaults are what the interpreter wants:
# bytecode validation and gas metering are both on already. WASI is the one
# thing that is off, and jm:wasm's run needs it to call a command's _start.
wasm_defines := "-Dd_m3HasWASI"
# libpg_query compile flags: upstream's Makefile exactly, less its -g and at
# -O2 rather than -O3. -fno-strict-aliasing and -fwrapv are not taste — the
# PostgreSQL sources are written against them and miscompile without. The
# three -Wno- suppress warnings in generated parser code.
pg_query_flags := "-fno-strict-aliasing -fwrapv -fPIC -O2 " + \
  "-Ipg_query/vendor -Ipg_query/vendor/vendor -Ipg_query/vendor/src/include " + \
  "-Ipg_query/vendor/src/postgres/include " + \
  "-Wno-unused-function -Wno-unused-value -Wno-unused-variable"
targets  := "linux_amd64 darwin_arm64 windows_amd64"

# `just` alone lists the recipes.
default:
    @just --list --unsorted

# Debug odin-run -> build/debug/odin-run
build:
    mkdir -p build/debug
    {{odin}} build tools/odin-run -debug {{flags}} -define:JM_COLLECTION={{root}} -out:build/debug/odin-run{{exe}}

# Optimised odin-run -> build/release/odin-run
release:
    mkdir -p build/release
    {{odin}} build tools/odin-run -o:speed {{flags}} -define:JM_COLLECTION={{root}} -out:build/release/odin-run{{exe}}

# The archive lands in sqlite3/lib rather than build/ because foreign import
# resolves relative to the package directory. `just check` never needs it:
# odin check does not open a foreign import, which is how one machine
# type-checks all three targets without building for any of them.

# Compile the vendored SQLite amalgamation into sqlite3/lib if it is stale
[unix]
sqlite:
    @mkdir -p sqlite3/lib
    @if [ ! -f {{sqlite_lib}} ] || [ sqlite3/vendor/sqlite3.c -nt {{sqlite_lib}} ]; then \
        echo "{{cc}} sqlite3 amalgamation -> {{sqlite_lib}}"; \
        {{cc}} -O2 -fPIC -c sqlite3/vendor/sqlite3.c -o sqlite3/lib/sqlite3.o {{sqlite_defines}}; \
        ar rcs {{sqlite_lib}} sqlite3/lib/sqlite3.o; \
    fi

[windows]
sqlite:
    @if (!(Test-Path {{sqlite_lib}}) -or (Get-Item sqlite3/vendor/sqlite3.c).LastWriteTime -gt (Get-Item {{sqlite_lib}}).LastWriteTime) { \
        cl /nologo /O2 /c sqlite3/vendor/sqlite3.c /Fosqlite3/lib/sqlite3.obj {{sqlite_defines}}; \
        lib /nologo /OUT:{{sqlite_lib}} sqlite3/lib/sqlite3.obj \
    }

# Compile the vendored kb_text_shape (ui/kb, jm:ui/shape's shaper) into
# ui/kb/lib if it is stale. C11 for the layout asserts in kb_text_shape.c.
# kb byte-swaps font tables by writing a run of u16 from a struct's first
# field on through the ones after it, which GCC's object-size check reads
# as overflowing that first field: -Wno-stringop-overflow.
[unix]
kb:
    @mkdir -p ui/kb/lib
    @if [ ! -f {{kb_lib}} ] || [ ui/kb/vendor/kb_text_shape.c -nt {{kb_lib}} ] || [ ui/kb/vendor/kb_text_shape.h -nt {{kb_lib}} ]; then \
        echo "{{cc}} kb_text_shape -> {{kb_lib}}"; \
        {{cc}} -std=c11 -O2 -fPIC -Wno-stringop-overflow -c ui/kb/vendor/kb_text_shape.c -o ui/kb/lib/kb_text_shape.o; \
        ar rcs {{kb_lib}} ui/kb/lib/kb_text_shape.o; \
    fi

[windows]
kb:
    @New-Item -ItemType Directory -Force ui/kb/lib | Out-Null
    @if (!(Test-Path {{kb_lib}}) -or (Get-Item ui/kb/vendor/kb_text_shape.c).LastWriteTime -gt (Get-Item {{kb_lib}}).LastWriteTime -or (Get-Item ui/kb/vendor/kb_text_shape.h).LastWriteTime -gt (Get-Item {{kb_lib}}).LastWriteTime) { \
        cl /nologo /std:c11 /O2 /c ui/kb/vendor/kb_text_shape.c /Foui/kb/lib/kb_text_shape.obj; \
        lib /nologo /OUT:{{kb_lib}} ui/kb/lib/kb_text_shape.obj \
    }

# Unlike SQLite this is a tree rather than one amalgamated file, so the objects
# go to a scratch directory beside the archive and staleness is any source
# newer than it.
#
# Compile the vendored wasm3 into wasm/lib if it is stale
[unix]
wasm:
    @mkdir -p wasm/lib/obj
    @if [ ! -f {{wasm_lib}} ] || [ -n "$(find wasm/vendor -name '*.[ch]' -newer {{wasm_lib}} -print -quit)" ]; then \
        echo "{{cc}} wasm3 -> {{wasm_lib}}"; \
        for f in wasm/vendor/*.c; do \
            {{cc}} -O2 -fPIC -Iwasm/vendor {{wasm_defines}} -c $f -o wasm/lib/obj/$(basename $f .c).o || exit 1; \
        done; \
        ar rcs {{wasm_lib}} wasm/lib/obj/*.o; \
    fi

[windows]
wasm:
    @if (!(Test-Path {{wasm_lib}})) { \
        New-Item -ItemType Directory -Force wasm/lib/obj | Out-Null; \
        Get-ChildItem wasm/vendor/*.c | ForEach-Object { cl /nologo /O2 /I wasm/vendor {{wasm_defines}} /c $_.FullName /Fowasm/lib/obj/ }; \
        lib /nologo /OUT:{{wasm_lib}} wasm/lib/obj/*.obj \
    }

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
[unix]
pg_query:
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
[windows]
pg_query:
    @if (!(Test-Path {{pg_query_lib}})) { \
        New-Item -ItemType Directory -Force pg_query/lib/obj | Out-Null; \
        Get-ChildItem -Recurse pg_query/vendor/src/*.c, pg_query/vendor/protobuf/*.c, pg_query/vendor/vendor/*.c | ForEach-Object { cl /nologo /O2 {{pg_query_flags}} /I pg_query/vendor/src/postgres/include/port/win32 /I pg_query/vendor/src/postgres/include/port/win32_msvc /c $_.FullName /Fopg_query/lib/obj/ }; \
        lib /nologo /OUT:{{pg_query_lib}} pg_query/lib/obj/*.obj \
    }

# Check out a repository at one commit into dir, unless it is there already.
# GitHub serves any reachable commit by hash, so a shallow fetch of the pin
# needs no tag or branch.
[private]
fetch dir url rev:
    @if [ "$(git -C {{dir}} rev-parse -q --verify HEAD 2>/dev/null)" != "{{rev}}" ]; then \
        echo "fetch {{url}} @ {{rev}} -> {{dir}}"; \
        mkdir -p {{dir}} && git -C {{dir}} init -q && \
        git -C {{dir}} fetch -q --depth 1 {{url}} {{rev}} && \
        git -C {{dir}} checkout -qf FETCH_HEAD || exit 1; \
    fi

# Compile Blend2D into ui/blend2d/lib if it is missing
[unix]
blend2d:
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
[windows]
blend2d:
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

# Compile libgit2 into git/lib if it is missing
[unix]
libgit2:
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
[windows]
libgit2:
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

# nodes.odin is generated and checked in, so nothing here depends on it: this
# is for after the vendored parser is bumped. The schema it reads is
# libpg_query's own, the same input upstream generates its Go and Ruby
# bindings from, and pg_query_test.odin's schema_conforms holds the checked-in
# file against it on every `just test`.
#
# Regenerate pg_query/nodes.odin from the vendored schema
pg_query-gen:
    mkdir -p build/debug
    {{odin}} build pg_query/gen {{flags}} -out:build/debug/pg_query-gen{{exe}}
    build/debug/pg_query-gen{{exe}} pg_query/vendor/srcdata pg_query/nodes.odin

# jm:wasm's tests run on one thread because wasm3 is not thread-safe, whatever
# the runtimes are; the package doc records what two threads do to it.
#
# examples/hot-counter/child, the real subprocess ui/sdl's own test
# spawns to prove the host/child protocol against a real process, not a
# stub. blend2d only: the child never links SDL.
hot-counter-child: blend2d kb
    mkdir -p build/debug
    {{odin}} build examples/hot-counter/child -debug {{flags}} {{cxx_link}} -out:build/debug/hot-counter-child{{exe}}

# Every directory of Odin source, tracked or not but never ignored, less
# skip: so a new package joins check, test and link without joining a list.
# kind picks among them: `package` and `program` split them on `package
# main`, `test` keeps those holding an @(test) proc. CI reads them here too.
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

# Run every package's tests: packages in parallel, then serial_tests one at a
# time on one thread.
# Every package links with cxx_link, a superset of what any one needs. A
# job's output is held until it ends, and every failure prints before the
# recipe fails.
test: sqlite wasm pg_query blend2d kb libgit2 hot-counter-child
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p build/test
    # vendor:sdl3 loads SDL3.dll at start-up on Windows, so ui/sdl's test
    # binary needs it beside it.
    if [ "{{os()}}" = windows ]; then cp "$({{odin}} root)/vendor/sdl3/SDL3.dll" build/test/; fi
    run() {
      local p=$1 out
      shift
      if out=$({{odin}} test "$p" {{flags}} {{cxx_link}} "$@" -out:build/test/$(echo "$p" | tr / -){{exe}} 2>&1); then
        echo "ok   $p"
        return 0
      fi
      printf 'FAIL %s\n%s\n' "$p" "$out" >&2
      return 1
    }
    export -f run
    parallel=() serial=()
    for d in $({{just}} _dirs test); do
      case " {{serial_tests}} " in *" $d "*) serial+=("$d");; *) parallel+=("$d");; esac
    done
    failed=0
    printf '%s\n' "${parallel[@]}" | xargs -P {{num_cpus()}} -n 1 bash -c 'run "$0"' || failed=1
    for d in "${serial[@]}"; do run "$d" -define:ODIN_TEST_THREADS=1 || failed=1; done
    exit $failed

# Type-check every package and program for each target, in parallel; a
# program keeps its entry point. A job's output is held until it ends, and
# every failure prints before the recipe fails.
check:
    #!/usr/bin/env bash
    set -euo pipefail
    { {{just}} _dirs package | sed 's/$/ -no-entry-point/'; {{just}} _dirs program | sed 's/$/ -entry-point/'; } \
      | while read -r d entry; do for t in {{targets}}; do printf '%s %s %s\n' "$d" "$t" "$entry"; done; done \
      | xargs -P {{num_cpus()}} -n 3 sh -c '
      entry=$2
      if [ "$entry" = -entry-point ]; then entry=; fi
      if out=$({{odin}} check "$0" {{flags}} -target:"$1" $entry 2>&1); then exit 0; fi
      printf "%s (%s)\n%s\n" "$0" "$1" "$out" >&2
      exit 1'

# Build every program into build/debug, named for its directory, in
# parallel: type-checking misses a link failure. Output is held as in test.
link: sqlite wasm pg_query blend2d kb libgit2
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p build/debug
    {{just}} _dirs program | xargs -P {{num_cpus()}} -n 1 sh -c '
      if out=$({{odin}} build "$0" {{flags}} {{cxx_link}} -out:build/debug/$(echo "$0" | tr / -){{exe}} 2>&1); then
        echo "ok   $0"
        exit 0
      fi
      printf "FAIL %s\n%s\n" "$0" "$out" >&2
      exit 1'

# Install odin-run into ~/.local/bin (override with BINDIR)
install: release
    mkdir -p {{bindir}}
    cp build/release/odin-run{{exe}} {{bindir}}/odin-run{{exe}}

# Arguments pass straight through: `just fuzz "tar -for=5m"`,
# `just fuzz "sqlite3 -seed=12345"`, `just fuzz "-corpus=build/corpus"`.

# Run every jm:fuzz suite until something gives
fuzz args="-for=30s": sqlite wasm pg_query blend2d kb libgit2
    mkdir -p build/debug
    {{odin}} build tools/jm-fuzz -debug {{flags}} {{cxx_link}} -out:build/debug/jm-fuzz{{exe}}
    build/debug/jm-fuzz{{exe}} {{args}}

# A child process per case: a crash or a hang is reported, not fatal
fuzz-isolate args="-for=5m": sqlite wasm pg_query blend2d kb libgit2
    mkdir -p build/debug
    {{odin}} build tools/jm-fuzz -debug {{flags}} {{cxx_link}} -out:build/debug/jm-fuzz{{exe}}
    build/debug/jm-fuzz{{exe}} -isolate {{args}}

# The same, under AddressSanitizer
[unix]
fuzz-asan args="-for=30s": sqlite wasm pg_query blend2d kb libgit2
    mkdir -p build/debug
    {{odin}} build tools/jm-fuzz -debug -sanitize:address {{flags}} {{cxx_link}} -out:build/debug/jm-fuzz-asan
    build/debug/jm-fuzz-asan {{args}}

# `just bench "-n=64"` fixes the work per call; without one each workload is
# calibrated to take about 25ms.
#
# Time jm:wasm against the workloads in tools/wasm-bench
bench args="": wasm
    mkdir -p build/release
    {{odin}} build tools/wasm-bench -o:speed {{flags}} -out:build/release/wasm-bench{{exe}}
    build/release/wasm-bench{{exe}} tools/wasm-bench/workloads {{args}}

# `just bench-ui "-w 1800 -h 1200"` measures at another size.
#
# Time jm:ui layout and the Blend2D executor per frame
bench-ui args="": blend2d kb
    mkdir -p build/release
    {{odin}} build tools/ui-bench -o:speed {{flags}} {{cxx_link}} -out:build/release/ui-bench{{exe}}
    build/release/ui-bench{{exe}} {{args}}

# The .wasm files are committed, so this is only needed when a source changes.
# It wants a clang with the wasm32 target and wasm-ld; zig cc has both, as
# WASM_CC="zig cc".
#
# Rebuild the benchmark workloads from their C sources
[unix]
bench-build:
    for f in tools/wasm-bench/workloads/*.c; do \
      {{wasm_cc}} --target=wasm32-freestanding -O2 -nostdlib -Wl,--no-entry \
        -Wl,--export=run -Wl,--export-memory -o ${f%.c}.wasm $f || exit 1; \
    done

# Compile and run the example script
example: build sqlite
    ODIN_RUN_VERBOSE=1 build/debug/odin-run{{exe}} examples/hello.odin

# vendor:sdl3 links SDL3.dll at load time on Windows, so the demo cannot start
# without it beside the exe.
#
# Copy SDL3.dll next to the demo
[windows]
sdl3:
    @mkdir -p build/debug
    @cp "$({{odin}} root)/vendor/sdl3/SDL3.dll" build/debug/

# Nothing to do: SDL3 is a system library off Windows
[unix]
sdl3:

# The demo is the proof that the pieces of jm:ui fit: a window, or the same
# frame as text or as a PNG without one.
# Build the hot-reloaded architecture-diagram demo: a live-editable
# diagram of jm:ui's own input/layout/render pipeline, respawned by
# tools/hot-watch every time examples/hot-architecture/child changes.
# Prints the two commands to run it (in separate terminals) rather than
# launching them itself: backgrounding a long-running process portably
# from one just recipe is more trouble than it is worth.
hot-architecture: blend2d kb sdl3
    mkdir -p build/debug
    {{odin}} build tools/hot-watch -debug {{flags}} -out:build/debug/hot-watch{{exe}}
    {{odin}} build examples/hot-architecture/host -debug {{flags}} {{cxx_link}} -out:build/debug/hot-architecture-host{{exe}}
    @echo "terminal 1: build/debug/hot-watch{{exe}} examples/hot-architecture/child build/debug/hot-architecture.watch"
    @echo "terminal 2: build/debug/hot-architecture-host{{exe}} build/debug/hot-architecture.watch"
    @echo "then edit examples/hot-architecture/child/main.odin and watch the window update."

# examples/material-kitchen: every jm:ui/material component, one page
# each. Build it and open its window; hot-watch runs in the background
# while the window is open, watching ui and ui/material too, so editing a
# component rebuilds and respawns it, and a change there rebuilds the host,
# which restarts itself if the ops encoding changed. Ending the recipe,
# however it ends, stops both.
material-kitchen: blend2d kb sdl3
    #!/usr/bin/env bash
    set -eu
    mkdir -p build/debug
    {{odin}} build tools/hot-watch -debug {{flags}} -out:build/debug/hot-watch{{exe}}
    {{odin}} build examples/material-kitchen/host -debug {{flags}} {{cxx_link}} -out:build/debug/material-kitchen-host{{exe}}
    build/debug/hot-watch{{exe}} examples/material-kitchen/child build/debug/material-kitchen.watch -host examples/material-kitchen/host build/debug/material-kitchen-host{{exe}} ui ui/material &
    watch=$!
    build/debug/material-kitchen-host{{exe}} build/debug/material-kitchen.watch &
    host=$!
    trap 'kill $watch $host 2>/dev/null' EXIT
    wait $host

# Regenerate ui/material/tokens/tokens.odin from the M3 Expressive kit's
# resolved tokens. M3E_KIT is the kit checkout.
material-tokens:
    {{odin}} run tools/design-tokens {{flags}} -- material "${M3E_KIT:-$HOME/Source/Personal/m3e-kit}/tokens/m3e.resolved.json" ui/material/tokens/tokens.odin

# Regenerate ui/fluent/tokens from the Fluent 2 kit's fluent.resolved.json.
fluent-tokens:
    {{odin}} run tools/design-tokens {{flags}} -- fluent "${FLUENT_KIT:-$HOME/Source/Personal/fluent-kit}/tokens/fluent.resolved.json" ui/fluent/tokens/tokens.odin

# Regenerate ui/fluent/icon_data.odin from the Fluent UI System Icons in
# FLUENT_ICONS, the directory fluent-icons-fetch fills.
fluent-icons:
    {{odin}} run tools/fluent-icons {{flags}} -- "${FLUENT_ICONS:-$HOME/Source/Vendor/fluent-icons}" ui/fluent/icon_data.odin

# Fetch the 20px regular and filled SVG of every icon named in
# tools/fluent-icons/icons.txt from microsoft/fluentui-system-icons (MIT)
# into FLUENT_ICONS, with the licence beside them.
fluent-icons-fetch:
    #!/usr/bin/env bash
    set -eu
    dir="${FLUENT_ICONS:-$HOME/Source/Vendor/fluent-icons}"
    base=https://raw.githubusercontent.com/microsoft/fluentui-system-icons/main
    mkdir -p "$dir"
    curl -sSL --max-time 30 -o "$dir/LICENSE" "$base/LICENSE"
    while read -r name; do
      folder=$(echo "$name" | sed 's/_/ /g; s/\b./\u&/g; s/ /%20/g')
      for v in regular filled; do
        curl -sSL --max-time 30 -o "$dir/ic_fluent_${name}_20_$v.svg" "$base/assets/$folder/SVG/ic_fluent_${name}_20_$v.svg"
      done
    done < tools/fluent-icons/icons.txt

# Regenerate ui/material/shape_data.odin, the loading indicator's morph
# pairs, from the M3 Expressive kit's shapes/morphs.json.
material-shapes:
    {{odin}} run tools/material-shapes {{flags}} -- "${M3E_KIT:-$HOME/Source/Personal/m3e-kit}/shapes/morphs.json" ui/material/shape_data.odin

# Render one material-kitchen page to build/material-<page>.png, no window
material-png page="Buttons": blend2d kb
    mkdir -p build/debug
    {{odin}} build examples/material-kitchen/child -debug {{flags}} {{cxx_link}} -out:build/debug/material-kitchen-child{{exe}}
    build/debug/material-kitchen-child{{exe}} -page "{{page}}" -png "build/material-{{page}}.png"

# examples/fluent-kitchen: every jm:ui/fluent component, one page each,
# hot-reloaded like material-kitchen. Selawik, the kit's stand-in for
# Segoe UI, is read from ~/.local/share/fonts/selawik (just fluent-fonts).
fluent-kitchen: blend2d kb sdl3
    #!/usr/bin/env bash
    set -eu
    mkdir -p build/debug
    {{odin}} build tools/hot-watch -debug {{flags}} -out:build/debug/hot-watch{{exe}}
    {{odin}} build examples/fluent-kitchen/host -debug {{flags}} {{cxx_link}} -out:build/debug/fluent-kitchen-host{{exe}}
    build/debug/hot-watch{{exe}} examples/fluent-kitchen/child build/debug/fluent-kitchen.watch -host examples/fluent-kitchen/host build/debug/fluent-kitchen-host{{exe}} ui ui/fluent &
    watch=$!
    build/debug/fluent-kitchen-host{{exe}} build/debug/fluent-kitchen.watch &
    host=$!
    trap 'kill $watch $host 2>/dev/null' EXIT
    wait $host

# examples/text-lab: specimens of every text feature the shaper must
# handle (Latin features, complex scripts, bidi, emoji) with the shaper's
# clusters and caret stops drawn over them, plus live inputs. Hot-reloads
# like material-kitchen, watching ui and ui/fluent too.
text-lab: blend2d kb sdl3
    #!/usr/bin/env bash
    set -eu
    mkdir -p build/debug
    {{odin}} build tools/hot-watch -debug {{flags}} -out:build/debug/hot-watch{{exe}}
    {{odin}} build examples/text-lab/host -debug {{flags}} {{cxx_link}} -out:build/debug/text-lab-host{{exe}}
    build/debug/hot-watch{{exe}} examples/text-lab/child build/debug/text-lab.watch -host examples/text-lab/host build/debug/text-lab-host{{exe}} ui ui/fluent &
    watch=$!
    build/debug/text-lab-host{{exe}} build/debug/text-lab.watch &
    host=$!
    trap 'kill $watch $host 2>/dev/null' EXIT
    wait $host

# Render one text-lab page, whole, to build/text-<page>.png, no window
text-png page="Scripts": blend2d kb
    mkdir -p build/debug
    {{odin}} build examples/text-lab/child -debug {{flags}} {{cxx_link}} -out:build/debug/text-lab-child{{exe}}
    build/debug/text-lab-child{{exe}} -full -page "{{page}}" -png "build/text-{{page}}.png"

# Render one fluent-kitchen page to build/fluent-<page>.png, no window
fluent-png page="Button": blend2d kb
    mkdir -p build/debug
    {{odin}} build examples/fluent-kitchen/child -debug {{flags}} {{cxx_link}} -out:build/debug/fluent-kitchen-child{{exe}}
    build/debug/fluent-kitchen-child{{exe}} -page "{{page}}" -png "build/fluent-{{page}}.png"

# Fetch Selawik regular, semibold and bold (OFL-1.1) from microsoft/Selawik
# release 1.01 into ~/.local/share/fonts/selawik for the fluent kitchen.
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

# Remove build/ and the compiled SQLite, wasm3, libpg_query and Blend2D archives
clean:
    rm -rf build sqlite3/lib wasm/lib pg_query/lib ui/blend2d/lib
