# WebAssembly

`wasm/vendor/` holds **wasm3 0.9.1** (commit `c036c43`), the interpreter's
`source/` tree minus the two files this build does not compile: the uvwasi
backend, which needs libuv, and the meta-WASI one, which is for running wasm3
inside wasm3. wasm3 is MIT, and `wasm/vendor/LICENSE` is its copy.

`just wasm` compiles it once into `wasm/lib/wasm3.a`, which is gitignored and
rebuilt when any vendored source changes. As with SQLite, `foreign import`
resolves that archive relative to the package directory, and `odin check`
never opens it, so `just check` still type-checks all three targets on one
machine with no archive built.

The build takes wasm3's defaults, which already have bytecode validation and
gas metering on, and adds one option: `d_m3HasWASI`, without which `run` has
no `_start` to call. That is an interpreter, not a JIT — several times slower
than Wasmtime on arithmetic, and in exchange it is 550 KB of portable C with
nothing to install and no executable pages to allocate at runtime.

One limit is worth knowing before reaching for `jm:flow`: wasm3 is not
thread-safe, and not merely per runtime. Eight threads, each with its own
environment, runtime and copy of a two-instruction module, still produce
spurious traps — a stack overflow, an out of bounds access — roughly five
times in sixteen hundred calls. That was reproduced in C against this archive,
with no Odin involved, so it is wasm3's own state and not the binding's.
`jm:wasm` is therefore a one-thread package; `interrupt` is the only call
meant to cross a thread, because it does nothing but set a flag. `just test`
runs this package's tests with the test runner on a single thread for the
same reason.

`wasm/fuzz` is the suite: six properties over generated modules, damaged ones
and bytes that were never a module, with a small Wasm encoder so a case needs
no toolchain. `just fuzz "wasm -for=1m"` runs it; the section below records
what it found.

## Speed

`just bench` times jm:wasm against the four workloads in
`tools/wasm-bench/workloads`, compiled from the C beside them by
`just bench-build`. Each exports `run(i32) -> i32`: the argument scales the
work linearly and the result is a checksum, so the same module can be run
through another engine and checked. The harness reports the load, the first
call — which is where wasm3 compiles the body — an empty call, and the
workload, and subtracts `run(2n) - run(n)` so that only what scales with the
work is left. On this machine:

```
module        load    first     call     work
fib          14.5µs    2.8µs    138ns   219µs per unit
mandel       10.5µs    7.4µs    118ns   481µs
memsum       10.8µs    5.3µs    106ns   2.3ms
sortbench     9.9µs    7.9µs    102ns   9.5ms
```

A module is instantiated in about ten microseconds and a call into it costs
around a hundred nanoseconds, which is what an embedded interpreter is for.
The work is another matter. The same four modules, at a fixed size — `run(4096)`,
`run(2048)`, `run(512)` and `run(128)` — through every engine that could be
made to run them, each one a command that loads the module, calls `run` once
and exits. Milliseconds of work, fastest of three, lowest first; *first run*
is what the whole process costs at `run(1)`:

| engine | fib | mandel | memsum | sort | first run |
|---|---|---|---|---|---|
| wasmtime 49.0.1, Cranelift JIT | 84 | 178 | 52 | 158 | 2.9ms |
| Node 26.8.1, V8 JIT | 93 | 316 | 80 | 309 | 15.6ms |
| wazero 1.12.0, Go compiler | 125 | 193 | 130 | 380 | 2.0ms |
| WAMR 2.4.5, default (JIT) | 160 | 370 | 71 | 301 | 18.7ms |
| **jm:wasm** (wasm3 0.9.1) | 820 | 897 | 1200 | 1140 | 1.0ms |
| wasm3 0.9.1, its own CLI | 920 | 937 | 1367 | 1236 | 1.1ms |
| WAMR 2.4.5, `--interp` | 2643 | 6528 | 2806 | 6437 | 20.2ms |

Three things are worth taking from it. The bindings cost nothing: the same
modules through wasm3's own CLI come out a few percent *slower*, so what is
measured above is the interpreter, not the crossing. Against a JIT the
interpreter is five to ten times slower on arithmetic and twenty times on
memory traffic, which is the price of the 550 KB of portable C and the one
millisecond to first execution — the fastest start of anything measured here,
where a JIT pays two to twenty milliseconds before it runs a thing. And among
interpreters wasm3 holds up: WAMR's classic interpreter, the other embedded
standard, is three to seven times slower than it on the same modules. WAMR's
default mode is not an interpreter at all, which is what makes it look fast
in the fourth row.

Every engine returned the same checksum for every workload, which is what
makes the columns comparable. The figures are the fastest of three runs on an
otherwise idle machine and repeat to within about fifteen percent, so the
orders of magnitude are the point and the last digit is not. "The bindings
cost nothing" is the same measurement against a C program driving
`wasm/lib/wasm3.a` directly: 800ms against 923 on fib, 1166 against 1153 on
memsum — the two are inside each other's noise.
