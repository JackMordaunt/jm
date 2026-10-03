# Fuzzing

**`jm:fuzz` runs properties against generated input and hands you the smallest
case that broke one.**

- **A bug found once stays found.** Each failure is saved to a corpus and
  replayed by `just test` on every run, with no fuzzer needed.
- **Failures arrive small.** A case shrinks to its simplest form before it is
  reported, so an 80-byte blob becomes the one byte that matters.
- **Crashes and hangs are results.** A deadline stops a case that will not
  finish, and `-isolate` turns a panic into a report instead of the end of
  the run.
- **It has paid for itself.** The suites found real bugs in five packages on
  their first runs; see [What it found](#what-it-found).

## Quick start

A property draws its input from a `Source` and says whether its promise held.
This one checks that a midpoint lies between its ends:

```odin
Nothing :: struct {}

midpoint :: proc(lo, hi: i64) -> i64 {return (lo + hi) / 2}

between :: proc(_: Nothing, src: ^fuzz.Source) -> (string, bool) {
	a, b := fuzz.integer(src), fuzz.integer(src)
	lo, hi := min(a, b), max(a, b)
	m := midpoint(lo, hi)
	return fmt.tprintf("midpoint(%d, %d) = %d", lo, hi, m), lo <= m && m <= hi
}

properties := []fuzz.Property(Nothing){{"between", between}}

main :: proc() {
	suite := fuzz.Suite(Nothing) {
		name       = "midpoint",
		setup      = proc() -> (Nothing, bool) {return {}, true},
		properties = properties,
	}
	report := fuzz.run(suite, {seed = 1, iterations = 10_000, stop_on_first = true})
	for f in report.failures {
		fmt.println(f.property, "failed:", f.detail, "| shrunk by", f.shrunk_by, "bytes")
	}
}
```

It finds the overflow at once:

```
between failed: midpoint(9223372036854775807, 9223372036854775807) = -1 | shrunk by 255 bytes
```

To run jm's own suites:

```
just fuzz                             30 seconds of every suite
just fuzz "tar -for=5m"               one suite, longer
just fuzz "sqlite3 -seed=12345"       replay a reported seed exactly
just fuzz "-corpus=DIR"               keep failures somewhere else
just fuzz-isolate                     five minutes, a child process per case
just fuzz-asan                        the same under AddressSanitizer
```

## How it works

A case's randomness is **a finite byte string**, and every generator draws
from it. A case is therefore a pure function of its bytes. It replays exactly,
it can be written to disk as a regression, and it can be shrunk by simplifying
the bytes and running it again.

Generators are written so a zero byte asks for the simplest value they can
give. That is what shrinking converges on.

The package does the rest of the work: seeding, budgets, an arena per case,
shrinking, the corpus, and a deadline on a case that will not finish.

## Writing a suite

A suite names a subject, how to make and unmake one, how to cancel work in
flight, and the promises:

```odin
properties := []fuzz.Property(Sandbox){{"no_escape", no_escape}}

suite :: proc() -> fuzz.Suite(Sandbox) {
	return fuzz.Suite(Sandbox) {
		name = "tar", setup = open, teardown = shut, properties = properties,
	}
}
```

Each suite keeps its regressions beside its source, in `<suite>/corpus`, and
replays them before generating anything. `just test` runs a few hundred cases
of each suite on fixed seeds and replays those corpora.

## Three features, each earned by a failure

| Feature | What went wrong first | What it does now |
|---------|-----------------------|------------------|
| **Shrinking** | A failure arrived as an 80-byte blob when one byte was enough. | A found case shrinks to its simplest form before it is reported. |
| **A corpus** | A bug found once should be a test from then on. | With `-corpus`, the case about to run is written out first. A property that takes the process down leaves its input on disk. That is how the `jm:tar` crash below was captured. |
| **A deadline** | Nothing in SQLite bounds how long a statement runs, and a damaged recursive CTE returns rows for ever. | A case that overruns is cancelled. In process, a suite must supply `cancel`; `-isolate` lifts that restriction. |

"Takes the process down" means anything the harness cannot catch: a panic, a
failed bounds check, and so on.

## Isolation

`-isolate` runs each case in a child process. The child is the same binary,
re-run with the case named in its environment. A program that calls
`fuzz.run` is therefore its own child, with no extra wiring.

| Mode | Cases per second | Use it for |
|------|-----------------:|------------|
| In process (default) | about 16,200 | the quick pass `just test` and a 30-second `just fuzz` do |
| `-isolate` | about 1,070 | unattended runs |

Isolation is fifteen times slower, which is why it is off by default. Measured
with `just fuzz "tar -for=5s -no-corpus"` against the same run with
`-isolate`. In return:

- **A crash is a result, not the end of the run.** A panic or a failed bounds
  check comes back as `Crashed`, with whatever the child wrote to stderr. The
  next case starts from a clean process.
- **The deadline works for any subject.** A child is killed whether or not it
  cooperates. A suite over a parser with no interruption point, such as
  `jm:tar`, whose loop has nothing to check, gets a deadline with no `cancel`.
- **Shrinking still applies.** A crash shrinks to its smallest case like any
  other failure.

## The suites

Nine packages carry a suite. Each one lives in `<package>/fuzz`.

| Package | Properties |
|---------|------------|
| `sqlite3` | `round_trip`, `injection`, `damaged_sql`, `arity`, `atomicity`, `reuse` |
| `tar` | `survives`, `in_bounds`, `round_trip`, `truncation`, `no_escape` |
| `wasm` | `survives`, `reusable`, `round_trip`, `arity`, `bounds`, `bounded` |
| `pg_query` | `survives`, `error_sane`, `tree_valid`, `split_covers`, `utility_agrees`, `fingerprint_ignores_literals`, `normalize_reparses`, `nul_safe` |
| `pq` | `survives`, `literal_round_trip`, `param_round_trip`, `identifier_round_trip`, `error_sane`, `nul_safe` |
| `zstd` | `round_trip`, `patch_round_trip`, `damaged_frame`, `damaged_patch` |
| `git` | `sequence`, `strings`, `damaged` |
| `stream` | fourteen properties over random graphs; see [Streams](streams.md) |
| `ui/render` | `matches_render`, `workers_agree`, `still_is_free` |

> [!TIP]
> The sqlite3 properties read every row before comparing any of them.
> Comparing inside the loop passes even when a column read hands back
> SQLite's memory instead of a copy, because the bytes have not been reused
> yet. Deleting the clone from `sqlite3.text` leaves the example-based tests
> green and fails one case in three here.

## What it found

Every bug below is fixed or written down.

| Package | Input that broke it | What went wrong | Fix |
|---------|---------------------|-----------------|-----|
| `jm:tar` | A base-256 size field larger than an `int` | The shift wrapped; `read` sliced the archive backwards. | Fixed; tested in `tar/tar_test.odin`. |
| `jm:tar` | A pax record of `"1 "` | The claimed length did not reach past its own length field; `read` sliced backwards. | Fixed; tested in `tar/tar_test.odin`. |
| `jm:tar` | A size of `max(int)` | `read` added the header's offset to it, and that wrapped. | The check is a subtraction; `tar/fuzz/corpus` keeps it. |
| `jm:wasm` | `wasm.bytes(mod, 8, max(int))` | `ptr + size` wrapped back into memory, so the bounds check passed. | It subtracts: what is left after `ptr` cannot wrap. `wasm_test.odin` keeps it. |
| `jm:pg_query` | `SELECT '<0xff><0xfe>' FROM t` | Invalid UTF-8 reached the parse tree's JSON and crashed the decoder. | Statements that are not UTF-8 are refused. |
| `jm:pg_query` | `SELECT-1` through `normalize` | Upstream rewrites it as `SELECT$1`, one identifier. | Upstream's bug; documented, not fixed. |
| `jm:pq` | Any `COPY … TO STDOUT` | The refusal carried no SQLSTATE, though the server had started the COPY. | It carries `0A000`. |

Two packages, written days apart, got the same arithmetic wrong in the same
place. A property that draws pointers at the edges finds it in seconds; no
example-based test here had.

<details>
<summary>The full story of each bug</summary>

### jm:tar, the second suite

Wiring `jm:tar` up turned up three ways to crash the parser on a malformed
archive. All are fixed, with regression tests in `tar/tar_test.odin`.

- A size field in the base-256 form can name a number larger than an `int`
  holds. The shift wrapped, the size came back negative, and `read` sliced
  the archive backwards.
- A pax record whose claimed length did not reach past its own length field
  made `read` slice backwards too. `"1 "` was enough.
- Guarding the size field was not enough on its own: `read` then adds the
  header's offset to it, and a size of `max(int)` made *that* wrap. The
  check has to be a subtraction. This one is also `tar/fuzz/corpus`'s first
  entry: the shape needs a dozen specific bytes, so the corpus rather than
  the fuzzer is what keeps it tested.

### jm:wasm, the third suite

Its `bounds` property found the same bug in a different package on its first
run. `wasm.bytes` stands between a guest's chosen pointer and the rest of the
process. It checked the range by adding `ptr + size`, so a size near the top
of `int` wrapped the sum back down into the memory. The check passed, and the
slice that followed had a negative length.

`wasm.bytes(mod, 8, max(int))` was enough. It subtracts now, taking what is
left of the memory after `ptr`, which cannot wrap. `wasm_test.odin` keeps the
case.

### jm:pg_query, the fourth suite

It found two things in its first runs. `error_sane` bounded `cursorpos` by
the length of the statement, but a statement cut short faults at *one past*
the end, which is how PostgreSQL says "at end of input". That was the
property being wrong. It is written down in the package now rather than left
to be rediscovered.

The second was real. `split_covers` took the process down on raw bytes after
ten thousand cases, inside `core:encoding/json`. libpg_query sets the
scanner's encoding to UTF-8 but does not validate its input against it, so
`SELECT '<0xff><0xfe>' FROM t` parses and those bytes are copied into the
parse tree verbatim. The tree becomes JSON that is not UTF-8.

Decoding that walks `unquote_string` off the end of its buffer, because an
invalid byte decodes as one byte and re-encodes as the three of U+FFFD.
`jm:pg_query` now refuses a statement that is not UTF-8 before the parser
sees it. A PostgreSQL server with a UTF-8 database does that anyway.

A third, under the sanitizer, is upstream's rather than ours, and is written
down rather than fixed. `normalize` substitutes a parameter over the
literal's recorded extent without checking that a token boundary survives. A
leading minus belongs to the constant, so `SELECT-1` comes back as
`SELECT$1`: one identifier, not a statement. `normalize_reparses` skips that
shape and names it, `pg_query_test.odin` keeps the case, and the package doc
tells a caller not to re-parse what normalize writes.

### jm:pq, the fifth suite

Its first run failed `error_sane` on every COPY. The binding refused
`COPY … TO STDOUT` with no SQLSTATE, the mark of a refusal that never reached
the server, but by then the server had started the COPY. It now carries
`0A000`, feature_not_supported, which is both true and something a caller
branching on SQLSTATE can match. Nothing else turned up in 100,000 cases
under the sanitizer.

### What the sanitizer taught about itself

`values_outlive_the_connection` closes the connection and then reads every
string the binding handed back, so that a string still pointing into a freed
`PGresult` traps. With the clone deliberately removed, it passed anyway. The
comparison runs in `base:runtime`, which is not instrumented, so ASan never
saw the read.

The test now walks every byte in its own code first. With the clone removed
it fails with a heap-use-after-free, as it should.

</details>

## See also

- [Streams](streams.md): the `stream/fuzz` suite and its stress runner
- [PostgreSQL](postgres.md): why `jm:pg_query` refuses invalid UTF-8
- [Building and testing](building.md): how `just test` replays every corpus
