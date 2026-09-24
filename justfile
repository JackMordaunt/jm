# Standard recipes: build, release, clean, test, install, plus check and example.
#
#   just build     debug odin-run                          -> build/debug/odin-run
#   just release   optimised odin-run                      -> build/release/odin-run
#   just test      run every package's tests
#   just check     type-check every package for linux, darwin and windows
#   just install   release odin-run into ~/.local/bin with this checkout baked in
#   just example   compile and run examples/hello.odin through the collection
#   just clean     remove build/

odin  := env("ODIN", "odin")
root  := justfile_directory()
flags := "-vet -strict-style -collection:jfm=" + root
exe   := if os() == "windows" { ".exe" } else { "" }
bindir := env("BINDIR", home_directory() / ".local" / "bin")
packages := "prelude sh http path timefmt debug flow tar"
targets  := "linux_amd64 darwin_arm64 windows_amd64"

# `just` alone lists the recipes.
default:
    @just --list --unsorted

# Debug odin-run -> build/debug/odin-run
build:
    mkdir -p build/debug
    {{odin}} build tools/odin-run -debug {{flags}} -define:JFM_ROOT={{root}} -out:build/debug/odin-run{{exe}}

# Optimised odin-run -> build/release/odin-run
release:
    mkdir -p build/release
    {{odin}} build tools/odin-run -o:speed {{flags}} -define:JFM_ROOT={{root}} -out:build/release/odin-run{{exe}}

# Run every package's tests
test:
    mkdir -p build/test
    for p in {{packages}}; do {{odin}} test $p {{flags}} -out:build/test/$p{{exe}} || exit 1; done

# Type-check every package and the runner for each target
check:
    for t in {{targets}}; do \
      for p in {{packages}}; do {{odin}} check $p {{flags}} -no-entry-point -target:$t || exit 1; done; \
      {{odin}} check tools/odin-run {{flags}} -target:$t || exit 1; \
      {{odin}} check examples/hello.odin -file {{flags}} -target:$t || exit 1; \
    done

# Install odin-run into ~/.local/bin (override with BINDIR)
install: release
    mkdir -p {{bindir}}
    cp build/release/odin-run{{exe}} {{bindir}}/odin-run{{exe}}

# Compile and run the example script
example: build
    ODIN_RUN_VERBOSE=1 build/debug/odin-run{{exe}} examples/hello.odin

# Remove build/
clean:
    rm -rf build
