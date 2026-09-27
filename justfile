# Standard recipes: build, release, clean, test, install, plus check and example.
#
#   just build     debug odin-run                          -> build/debug/odin-run
#   just release   optimised odin-run                      -> build/release/odin-run
#   just test      run every package's tests
#   just check     type-check every package for linux, darwin and windows
#   just sqlite    compile the vendored SQLite amalgamation into sqlite3/lib
#   just wasm      compile the vendored wasm3 interpreter into wasm/lib
#   just pg_query  compile the vendored libpg_query parser into pg_query/lib
#   just pg_query-gen  regenerate pg_query/nodes.odin from the vendored schema
#   just blend2d   compile Blend2D into ui/blend2d/lib from BLEND2D_SRC
#   just kitchen   build and open the jm:ui kitchen-sink demo
#   just kitchen-dump  print the demo's first frame as text, no window
#   just kitchen-png   render the demo's first frame to build/kitchen.png
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
packages := "prelude sh http path timefmt debug flow tar sqlite3 selfupdate wasm pg_query fuzz sqlite3/fuzz tar/fuzz wasm/fuzz pg_query/fuzz ui ui/testutil ui/diagram ui/ipc pq pq/testdb pq/fuzz"
cc       := env("CC", "cc")
wasm_cc  := env("WASM_CC", "clang")
sqlite_lib := if os() == "windows" { "sqlite3/lib/sqlite3.lib" } else { "sqlite3/lib/sqlite3.a" }
wasm_lib   := if os() == "windows" { "wasm/lib/wasm3.lib" } else { "wasm/lib/wasm3.a" }
pg_query_lib := if os() == "windows" { "pg_query/lib/pg_query.lib" } else { "pg_query/lib/pg_query.a" }
blend2d_lib := if os() == "windows" { "ui/blend2d/lib/blend2d.lib" } else { "ui/blend2d/lib/libblend2d.a" }
# Blend2D is C++ with asmjit inside, built by its own CMake tree rather than
# vendored here: 29 MB of source is the sibling checkout's job. Anything that
# links it needs libstdc++, except on Windows where the MSVC linker finds the
# C++ runtime itself.
blend2d_src := env("BLEND2D_SRC", home_directory() / "Source" / "Personal" / "odin-blend2d" / "blend2d")
cxx_link := if os() == "windows" { "" } else { "-extra-linker-flags:\"-lstdc++\"" }

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

# Windows wants the win32 port headers as well. Untested, like the other two.
[windows]
pg_query:
    @if (!(Test-Path {{pg_query_lib}})) { \
        New-Item -ItemType Directory -Force pg_query/lib/obj | Out-Null; \
        Get-ChildItem -Recurse pg_query/vendor/src/*.c, pg_query/vendor/protobuf/*.c, pg_query/vendor/vendor/*.c | ForEach-Object { cl /nologo /O2 {{pg_query_flags}} /I pg_query/vendor/src/postgres/include/port/win32 /c $_.FullName /Fopg_query/lib/obj/ }; \
        lib /nologo /OUT:{{pg_query_lib}} pg_query/lib/obj/*.obj \
    }

# Compile Blend2D into ui/blend2d/lib if it is missing
[unix]
blend2d:
    @mkdir -p ui/blend2d/lib
    @if [ ! -f {{blend2d_lib}} ]; then \
        echo "cmake blend2d ({{blend2d_src}}) -> {{blend2d_lib}}"; \
        cmake -S {{blend2d_src}} -B build/blend2d -DCMAKE_BUILD_TYPE=Release -DBLEND2D_STATIC=ON -DBLEND2D_TEST=OFF > build/blend2d.log 2>&1; \
        cmake --build build/blend2d --config Release --parallel >> build/blend2d.log 2>&1; \
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
        echo "cmake blend2d ({{blend2d_src}}) -> {{blend2d_lib}}"; \
        cmake -S {{blend2d_src}} -B build/blend2d -G Ninja -DCMAKE_MAKE_PROGRAM="$(command -v ninja.exe)" \
            -DCMAKE_C_COMPILER=clang-cl -DCMAKE_CXX_COMPILER=clang-cl -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded \
            -DCMAKE_BUILD_TYPE=Release -DBLEND2D_STATIC=ON -DBLEND2D_TEST=OFF > build/blend2d.log 2>&1 || exit 1; \
        cmake --build build/blend2d --parallel >> build/blend2d.log 2>&1 || exit 1; \
        cp build/blend2d/blend2d.lib {{blend2d_lib}}; \
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
hot-counter-child: blend2d
    mkdir -p build/debug
    {{odin}} build examples/hot-counter/child -debug {{flags}} {{cxx_link}} -out:build/debug/hot-counter-child{{exe}}

# Run every package's tests
test: sqlite wasm pg_query blend2d hot-counter-child
    mkdir -p build/test
    for p in {{packages}}; do \
      threads=""; \
      case "$p" in wasm|wasm/fuzz) threads="-define:ODIN_TEST_THREADS=1";; esac; \
      {{odin}} test $p {{flags}} $threads -out:build/test/$(echo $p | tr / -){{exe}} || exit 1; \
    done
    {{odin}} test tools/wasm-bench {{flags}} -define:ODIN_TEST_THREADS=1 -out:build/test/wasm-bench{{exe}}
    {{odin}} test ui/render {{flags}} {{cxx_link}} -out:build/test/ui-render{{exe}}
    {{odin}} test ui/render/fuzz {{flags}} {{cxx_link}} -out:build/test/ui-render-fuzz{{exe}}
    {{odin}} test ui/child {{flags}} {{cxx_link}} -out:build/test/ui-child{{exe}}
    # -1 thread: ui/sdl's tests spawn real hot-counter-child processes
    # sharing one exe path, the same reason wasm's own tests above do.
    {{odin}} test ui/sdl {{flags}} {{cxx_link}} -define:ODIN_TEST_THREADS=1 -out:build/test/ui-sdl{{exe}}

# Type-check every package and the runner for each target
check:
    for t in {{targets}}; do \
      for p in {{packages}}; do {{odin}} check $p {{flags}} -no-entry-point -target:$t || exit 1; done; \
      {{odin}} check tools/odin-run {{flags}} -target:$t || exit 1; \
      {{odin}} check tools/jm-fuzz {{flags}} -target:$t || exit 1; \
      {{odin}} check pg_query/gen {{flags}} -target:$t || exit 1; \
      {{odin}} check tools/wasm-bench {{flags}} -target:$t || exit 1; \
      {{odin}} check examples/hello.odin -file {{flags}} -target:$t || exit 1; \
      {{odin}} check ui/render {{flags}} -no-entry-point -target:$t || exit 1; \
      {{odin}} check ui/render/fuzz {{flags}} -no-entry-point -target:$t || exit 1; \
      {{odin}} check ui/child {{flags}} -no-entry-point -target:$t || exit 1; \
      {{odin}} check ui/sdl {{flags}} -no-entry-point -target:$t || exit 1; \
      {{odin}} check examples/ui-kitchen {{flags}} -target:$t || exit 1; \
      {{odin}} check examples/hotreload-diagram {{flags}} -target:$t || exit 1; \
      {{odin}} check examples/hot-counter/child {{flags}} -target:$t || exit 1; \
      {{odin}} check examples/hot-counter/host {{flags}} -target:$t || exit 1; \
      {{odin}} check examples/hot-architecture/child {{flags}} -target:$t || exit 1; \
      {{odin}} check examples/hot-architecture/host {{flags}} -target:$t || exit 1; \
      {{odin}} check tools/ui-bench {{flags}} -target:$t || exit 1; \
      {{odin}} check tools/hot-watch {{flags}} -target:$t || exit 1; \
    done

# Install odin-run into ~/.local/bin (override with BINDIR)
install: release
    mkdir -p {{bindir}}
    cp build/release/odin-run{{exe}} {{bindir}}/odin-run{{exe}}

# Arguments pass straight through: `just fuzz "tar -for=5m"`,
# `just fuzz "sqlite3 -seed=12345"`, `just fuzz "-corpus=build/corpus"`.

# Run every jm:fuzz suite until something gives
fuzz args="-for=30s": sqlite wasm pg_query blend2d
    mkdir -p build/debug
    {{odin}} build tools/jm-fuzz -debug {{flags}} {{cxx_link}} -out:build/debug/jm-fuzz{{exe}}
    build/debug/jm-fuzz{{exe}} {{args}}

# A child process per case: a crash or a hang is reported, not fatal
fuzz-isolate args="-for=5m": sqlite wasm pg_query blend2d
    mkdir -p build/debug
    {{odin}} build tools/jm-fuzz -debug {{flags}} {{cxx_link}} -out:build/debug/jm-fuzz{{exe}}
    build/debug/jm-fuzz{{exe}} -isolate {{args}}

# The same, under AddressSanitizer
[unix]
fuzz-asan args="-for=30s": sqlite wasm pg_query blend2d
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
bench-ui args="": blend2d
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
#
# Build and open the jm:ui kitchen-sink demo
kitchen: blend2d sdl3
    mkdir -p build/debug
    {{odin}} build examples/ui-kitchen -debug {{flags}} {{cxx_link}} -out:build/debug/ui-kitchen{{exe}}
    build/debug/ui-kitchen{{exe}}

# Build the hot-reloaded architecture-diagram demo: a live-editable
# diagram of jm:ui's own input/layout/render pipeline, respawned by
# tools/hot-watch every time examples/hot-architecture/child changes.
# Prints the two commands to run it (in separate terminals) rather than
# launching them itself: backgrounding a long-running process portably
# from one just recipe is more trouble than it is worth.
hot-architecture: blend2d sdl3
    mkdir -p build/debug
    {{odin}} build tools/hot-watch -debug {{flags}} -out:build/debug/hot-watch{{exe}}
    {{odin}} build examples/hot-architecture/host -debug {{flags}} {{cxx_link}} -out:build/debug/hot-architecture-host{{exe}}
    @echo "terminal 1: build/debug/hot-watch{{exe}} examples/hot-architecture/child build/debug/hot-architecture.watch"
    @echo "terminal 2: build/debug/hot-architecture-host{{exe}} build/debug/hot-architecture.watch"
    @echo "then edit examples/hot-architecture/child/main.odin and watch the window update."

# Print the demo's first frame as text, no window
kitchen-dump: blend2d sdl3
    mkdir -p build/debug
    {{odin}} build examples/ui-kitchen -debug {{flags}} {{cxx_link}} -out:build/debug/ui-kitchen{{exe}}
    build/debug/ui-kitchen{{exe}} -dump

# Render the demo's first frame to build/kitchen.png, no window
kitchen-png: blend2d sdl3
    mkdir -p build/debug
    {{odin}} build examples/ui-kitchen -debug {{flags}} {{cxx_link}} -out:build/debug/ui-kitchen{{exe}}
    build/debug/ui-kitchen{{exe}} -png build/kitchen.png

# Remove build/ and the compiled SQLite, wasm3, libpg_query and Blend2D archives
clean:
    rm -rf build sqlite3/lib wasm/lib pg_query/lib ui/blend2d/lib
