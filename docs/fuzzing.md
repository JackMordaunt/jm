# Fuzzing

`jm:fuzz` runs properties against generated input and tells you the smallest
case that broke one. A property is handed a subject and a `Source`, draws
whatever input it wants, and says whether the promise held. The package does
the rest: seeding, budgets, an arena per case, shrinking, the corpus, and a
deadline on a case that will not finish.

```
just fuzz                             30 seconds of every suite
just fuzz "tar -for=5m"               one suite, longer
just fuzz "sqlite3 -seed=12345"       replay a reported seed exactly
just fuzz "-corpus=DIR"               keep failures somewhere else
just fuzz-isolate                     five minutes, a child process per case
just fuzz-asan                        the same under AddressSanitizer
```

Each suite keeps its regressions beside its source, in `<suite>/corpus`, and
replays them before generating anything. `just test` runs a few hundred cases
of each suite on fixed seeds and replays those corpora, so a bug found once by
fuzzing stays found without anyone running the fuzzer again.

A case's randomness is **a finite byte string**, and every generator draws
from it. That one decision is what the rest rests on: a case is a pure
function of its bytes, so it replays exactly, it can be written to disk as a
regression, and it can be shrunk by simplifying the bytes and running it
again. Generators are written so a zero byte asks for the simplest value they
can give, which is what shrinking converges on.

Writing a suite means naming a subject, how to make and unmake one, how to
cancel work in flight, and the promises:

```odin
properties := []fuzz.Property(Sandbox){{"no_escape", no_escape}}

suite :: proc() -> fuzz.Suite(Sandbox) {
	return fuzz.Suite(Sandbox) {
		name = "tar", setup = open, teardown = shut, properties = properties,
	}
}
```

Three things in it were each put there by something that went wrong:

- **Shrinking**, because a failure arrived as an 80-byte blob when one byte
  was enough. A found case shrinks to its simplest form before it is
  reported.
- **A corpus**, because a bug found once should be a test from then on. With
  `-corpus`, the case about to run is also written out before it runs, so a
  property that takes the process down — a panic, a failed bounds check,
  anything the harness cannot catch — leaves the input that did it on disk.
  That is how the `jm:tar` crash below was captured.
- **A deadline**, because nothing in SQLite bounds how long a statement runs
  and a damaged recursive CTE returns rows for ever. In this process a suite
  has to supply `cancel` for that to work; `-isolate` lifts the restriction,
  below.

## Isolation

`-isolate` runs each case in a child process. The child is the same binary,
re-run with the case named in its environment, so a program that calls
`fuzz.run` is its own child with no extra wiring.

It costs a spawn per case. Measured with
`just fuzz "tar -for=5s -no-corpus"` against the same run with `-isolate`,
this machine does about 16,200 cases a second in process and 1,070 isolated
— fifteen times slower — which is why it is off by default. What it buys:

- **A crash is a result, not the end of the run.** A panic or a failed bounds
  check comes back as `Crashed`, carrying whatever the child wrote to stderr,
  and the next case starts from a clean process.
- **The deadline works for any subject.** A child is killed whether or not it
  cooperates, so a suite over a parser with no interruption point — `jm:tar`,
  whose loop has nothing to check — gets a deadline for free. No `cancel`
  needed.
- **Shrinking still applies**, so a crash shrinks to its smallest case like
  any other failure.

Use it for unattended runs. In process is the right default for the quick
pass that `just test` and a 30-second `just fuzz` do.

One trap the sqlite3 suite exists to catch: its properties read every row
before comparing any of them. Comparing inside the loop passes even when a
column read hands back SQLite's memory instead of a copy, because the bytes
have not been reused yet. Deleting the clone from `sqlite3.text` leaves the
example-based tests green and fails one case in three here.

## What it found

Wiring `jm:tar` up as the second suite turned up three ways to crash the
parser on a malformed archive, all now fixed, all with regression tests in
`tar/tar_test.odin`:

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

`jm:wasm` was the third suite, and its `bounds` property found the same bug in
a different package on its first run. `wasm.bytes` is what stands between a
guest's chosen pointer and the rest of the process; it checked the range by
adding `ptr + size`, so a size near the top of `int` wrapped the sum back down
into the memory, the check passed, and the slice that followed had a negative
length. `wasm.bytes(mod, 8, max(int))` was enough. It subtracts now — what is
left of the memory after `ptr`, which cannot wrap — and `wasm_test.odin` keeps
the case. Two packages, written days apart, got the same arithmetic wrong in
the same place; a property that draws pointers at the edges finds it in
seconds, and no example-based test here had.

`jm:pg_query` was the fourth suite, and it found two things in its first
runs. `error_sane` bounded `cursorpos` by the length of the statement; a
statement cut short faults at *one past* the end, which is how PostgreSQL
says "at end of input". That one was the property being wrong, and it is
written down in the package now rather than left to be rediscovered.

The second was real. `split_covers` took the process down on raw bytes after
ten thousand cases, inside `core:encoding/json`. libpg_query sets the scanner's
encoding to UTF-8 but does not validate its input against it, so
`SELECT '<0xff><0xfe>' FROM t` parses and those bytes are copied into the parse
tree verbatim — making the tree JSON that is not UTF-8. Decoding that walks
`unquote_string` off the end of its buffer, because an invalid byte decodes as
one byte and re-encodes as the three of U+FFFD. `jm:pg_query` now refuses a
statement that is not UTF-8 before the parser sees it, which is what a
PostgreSQL server with a UTF-8 database does anyway.

A third, under the sanitizer, is upstream's rather than ours and is written
down rather than fixed: `normalize` substitutes a parameter over the literal's
recorded extent without checking that a token boundary survives. A leading
minus belongs to the constant, so `SELECT-1` comes back as `SELECT$1` — one
identifier, not a statement. `normalize_reparses` skips that shape and names
it; `pg_query_test.odin` keeps the case, and the package doc tells a caller
not to re-parse what normalize writes.

`jm:pq` was the fifth suite. Its first run failed `error_sane` on every COPY:
the binding refused `COPY … TO STDOUT` with no SQLSTATE, the mark of a
refusal that never reached the server — but by then the server had started
the COPY. It now carries `0A000`, feature_not_supported, which is both true
and something a caller branching on SQLSTATE can match. Nothing else turned
up in 100,000 cases under the sanitizer.

The sanitizer taught something about itself while the tests were written.
`values_outlive_the_connection` closes the connection and then reads every
string the binding handed back, so that a string still pointing into a freed
`PGresult` traps. With the clone deliberately removed it passed anyway: the
comparison runs in `base:runtime`, which is not instrumented, so ASan never
saw the read. The test now walks every byte in its own code first, and with
the clone removed it fails with a heap-use-after-free, as it should.
