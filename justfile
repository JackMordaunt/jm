# Standard recipes: build, release, clean, test, install, plus check and example.
#
#   just build     debug odin-run                          -> build/debug/odin-run
#   just release   optimised odin-run                      -> build/release/odin-run
#   just test      run every package's tests
#   just check     type-check every package for linux, darwin and windows
#   just sqlite    compile the vendored SQLite amalgamation into sqlite3/lib
#   just fuzz      run every jm:fuzz suite for thirty seconds
#   just install   release odin-run into ~/.local/bin with this checkout baked in
#   just example   compile and run examples/hello.odin through the collection
#   just clean     remove build/

odin  := env("ODIN", "odin")
root  := justfile_directory()
flags := "-vet -strict-style -collection:jm=" + root
exe   := if os() == "windows" { ".exe" } else { "" }
bindir := env("BINDIR", home_directory() / ".local" / "bin")
packages := "prelude sh http path timefmt debug flow tar sqlite3 fuzz sqlite3/fuzz tar/fuzz"
cc       := env("CC", "cc")
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

# Run every package's tests
test: sqlite
    mkdir -p build/test
    for p in {{packages}}; do \
      {{odin}} test $p {{flags}} -out:build/test/$(echo $p | tr / -){{exe}} || exit 1; \
    done

# Type-check every package and the runner for each target
check:
    for t in {{targets}}; do \
      for p in {{packages}}; do {{odin}} check $p {{flags}} -no-entry-point -target:$t || exit 1; done; \
      {{odin}} check tools/odin-run {{flags}} -target:$t || exit 1; \
      {{odin}} check tools/jm-fuzz {{flags}} -target:$t || exit 1; \
      {{odin}} check examples/hello.odin -file {{flags}} -target:$t || exit 1; \
    done

# Install odin-run into ~/.local/bin (override with BINDIR)
install: release
    mkdir -p {{bindir}}
    cp build/release/odin-run{{exe}} {{bindir}}/odin-run{{exe}}

# Arguments pass straight through: `just fuzz "tar -for=5m"`,
# `just fuzz "sqlite3 -seed=12345"`, `just fuzz "-corpus=build/corpus"`.

# Run every jm:fuzz suite until something gives
fuzz args="-for=30s": sqlite
    mkdir -p build/debug
    {{odin}} build tools/jm-fuzz -debug {{flags}} -out:build/debug/jm-fuzz{{exe}}
    build/debug/jm-fuzz{{exe}} {{args}}

# The same, under AddressSanitizer
[unix]
fuzz-asan args="-for=30s": sqlite
    mkdir -p build/debug
    {{odin}} build tools/jm-fuzz -debug -sanitize:address {{flags}} -out:build/debug/jm-fuzz-asan
    build/debug/jm-fuzz-asan {{args}}

# Compile and run the example script
example: build sqlite
    ODIN_RUN_VERBOSE=1 build/debug/odin-run{{exe}} examples/hello.odin

# Remove build/ and the compiled SQLite archive
clean:
    rm -rf build sqlite3/lib
