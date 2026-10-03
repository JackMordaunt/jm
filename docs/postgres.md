# PostgreSQL

**Parse SQL with PostgreSQL's own grammar, and talk to a PostgreSQL server,
from one Odin program.**

jm has two packages for PostgreSQL:

| | `jm:pg_query` | `jm:pq` |
|---|---|---|
| What it does | Parses SQL into typed Odin nodes | Connects to a server and runs statements |
| C library | libpg_query, PostgreSQL **17.7** grammar | libpq, the system's |
| Links | Statically, from `pg_query/lib/pg_query.a` | Dynamically, `libpq.so.5` |
| Needs a server | No | Yes |
| Builds with | `just pg_query` | Nothing to build |
| Licence | BSD-3-Clause, copy in `pg_query/vendor/LICENSE` | PostgreSQL Licence |

## pg_query, the parser

**Know what a statement does before you run it.**

- **The real grammar.** It is PostgreSQL's own `gram.y`, so it parses what the
  server's parser parses.
- **Typed nodes.** A parse tree arrives as Odin structs you can switch on, not
  JSON you have to dig through.
- **Fails closed.** A node or field the build does not know fails the parse,
  so a safety check never reads a tree with a hole in it.
- **Thread-safe.** Parse on as many threads as you like.
- **Utilities.** `split`, `is_utility`, `fingerprint` and `normalize` answer
  the common questions without re-parsing.

### Quick start

```odin
tree, err := pg_query.parse(`UPDATE rig SET serial_number = 'x' WHERE id = 1`)
if err != nil {
	fault := err.(pg_query.Fault)
	fmt.eprintfln("%s at byte %d", fault.message, fault.cursorpos)
	return
}
defer pg_query.destroy(&tree)
for raw in tree.stmts {
	if update, is_update := raw.stmt.(^pg_query.UpdateStmt); is_update {
		fmt.println(update.relation.relname, len(update.targetList))
	}
}
```

### Typed nodes, generated from the schema

A parse tree comes back as the JSON libpg_query wrote *and* as typed Odin
nodes. The nodes are generated, not written by hand: `pg_query/gen` turns
libpg_query's schema into `pg_query/nodes.odin`, **267 structs, 63 enumerated
types** and a tag-dispatched decoder.

Typing them is the point. Without the schema, a field PostgreSQL renames in its
next major would stop decoding silently. A caller asking "does this statement
write?" would be told no because the field was absent, a failure that fails
*open*. Generated from the schema, the same rename fails to compile.

<details>
<summary>Under the hood: how the nodes are generated and decoded</summary>

`vendor/srcdata/` is libpg_query's own schema — the input it generates its Go,
Ruby and Python bindings from. `pg_query/gen` turns the four sections that
describe parse nodes into `pg_query/nodes.odin`. `just pg_query-gen`
regenerates it; the file is checked in, so nothing normally runs the
generator.

**Why 267 and not 474.** `nodetypes.json` lists 474, and the difference is not
a subset taken for convenience. `struct_defs.json` describes nodes in sixteen
sections. Four of them — `nodes/parsenodes`, `nodes/primnodes`, `nodes/value`
and `nodes/pg_list` — are what a *parse* tree can contain, and they hold 267
structs between them. The rest describe planner and executor nodes, which
exist only in a tree the server has already analysed and which
`pg_query_parse` never emits. The fuzz suite is what says so rather than this
paragraph: an unknown tag fails a parse, and a run that meets one fails.

**Schema conformance.** `schema_conforms` in the tests fails before a rename
would even reach the compiler. It loads the vendored `struct_defs.json` at
compile time and holds every node and field the Odin side names against it.

**Dispatch on the tag.** Every node arrives as a single-key object —
`{"UpdateStmt": {…}}`, `{"BoolExpr": {…}}`. A union matched structurally would
match whichever variant was declared first and hand back the wrong node,
silently. A tag this build has no struct for fails the parse, for the same
reason a missing field would: a gate must not be handed a tree with a hole in
it.

**Zero values.** Fields are plain and left at their zero value when absent,
because libpg_query omits anything false, zero or empty; `"inh":true` is
written and `"inh":false` is not.

**Hand-written shapes.** Two shapes are written by hand in the C rather than
generated from the schema: `A_Const`, whose value arrives under `ival`,
`fval`, `boolval`, `sval` or `bsval`, and the bare `RawStmt` at the top level.
Both are special-cased in `decode.odin` and named in the generator.

</details>

### Threads and memory

Parsing *is* thread-safe, unlike wasm3: the memory contexts are `__thread`.
Eight threads over the same statements agree on every tree through 144,000
parses in C and 9,600 in `pg_query_test.odin`.

> [!WARNING]
> Do not call `pg_query_exit`. The package leaves it unwrapped on purpose:
> calling it on a thread that then ends aborts the process.

> [!WARNING]
> Every `char *` in a C result dies at its `pg_query_free_*`. The package
> clones everything first; do not hold pointers from the raw API.

<details>
<summary>Under the hood: the two traps</summary>

- **The `char *` lifetime.** Every `char *` in a result dies at its
  `pg_query_free_*`, which releases a whole memory context. A pointer held past
  that reads memory the next parse reuses — the `sqlite3_column_text` trap in
  another dialect — so everything the package hands back is cloned first.
- **`pg_query_exit`.** It is the one entry point deliberately left unwrapped.
  `pg_query_init` registers a pthread destructor over the same top memory
  context, so a thread that calls `pg_query_exit` and then ends frees that
  context twice, and the process aborts in glibc. One worker thread, one parse,
  no concurrency needed; reproduced in C against this archive. Let the thread
  end and the destructor does it.

</details>

### Input rules

- **Statements must be valid UTF-8.** The package refuses one that is not,
  with the offset of the first bad byte. That is not tidiness — see
  [what the fuzzer found](fuzzing.md#what-it-found).
- **`normalize`'s output is for showing a human**, not for re-parsing, for a
  reason recorded there too.

<details>
<summary>Under the hood: provenance and build</summary>

`pg_query/vendor/` holds **libpg_query** at commit `6e764b79` of the
`17-latest` branch: PostgreSQL's own `gram.y` and everything it needs, lifted
out of the server source tree, carrying the **17.7** grammar.

- **Vendored:** the `src/` tree, `protobuf/pg_query.pb-c.{c,h}`, the two
  third-party directories under `vendor/`, and `srcdata/`, which is the schema
  the node types are generated from.
- **Left out:** upstream's tests, generator scripts and the optional C++
  protobuf path.

`just pg_query` compiles it once into `pg_query/lib/pg_query.a` — 86
translation units, about twenty seconds, 5 MB — which is gitignored and
rebuilt when any vendored source changes. As with SQLite and wasm3,
`foreign import` resolves that archive relative to the package directory and
`odin check` never opens it. `just check` still type-checks all three targets
on one machine with no archive built.

The flags are upstream's Makefile exactly, less its `-g` and at `-O2` rather
than `-O3`, and they are in the justfile. Two of them are correctness rather
than taste: the PostgreSQL sources are written against `-fno-strict-aliasing`
and `-fwrapv` and miscompile without them.

The protobuf objects are compiled although this binding only wants the JSON
API, which is not for want of trying. `pg_query_parse.c` defines
`pg_query_parse_protobuf` beside `pg_query_parse`, so the object that holds
the one entry point we call also references the protobuf writer, and an
archive without it fails to link. Measured, then written down in the recipe.

</details>

`pg_query/fuzz` is the suite: eight properties over generated SQL, damaged
SQL and bytes that were never SQL, with a SQL generator so a case needs no
fixtures. `just fuzz "pg_query -for=1m"` runs it.

## libpq, the client

**Connect the way psql does, and read rows back as Odin strings.**

- **Same environment as psql.** `pq.connect("")` reads `PGHOST`, `PGDATABASE`
  and the rest, so a script works wherever psql does.
- **Patched by the system.** libpq links dynamically, so TLS and Kerberos
  updates arrive with the operating system, not with a rebuild.
- **Tests bring their own server.** No Docker and no database set up
  beforehand.

### Quick start

```odin
conn, cerr := pq.connect() // PGHOST, PGDATABASE and the rest, as psql reads them
if cerr != nil {
	fmt.eprintln(cerr)
	return
}
defer pq.close(conn)

res, err := pq.exec(conn, `SELECT id, serial_number FROM rig WHERE site = $1`, {"north"})
if err != nil {
	fault := err.(pq.Fault)
	fmt.eprintfln("%s: %s", fault.sqlstate, fault.message)
	return
}
defer pq.destroy(&res)
for row in res.rows {
	fmt.println(row[0].? or_else "NULL", row[1].? or_else "NULL")
}
```

### Why libpq is not vendored

`jm:pq` is the one C library in the collection that is not vendored. It links
the system's `libpq.so.5` dynamically, and a built script needs it at runtime.

| | Vendored libraries | libpq |
|---|---|---|
| Builds with | A plain `cc` | Its own configure step, as a slice of the PostgreSQL tree |
| Brings in | Nothing | OpenSSL and GSSAPI, for TLS and Kerberos |
| Patched | With jm | On the machine's own schedule |

What makes the exception safe is libpq's record: `libpq.so.5` has kept its ABI
since 2006 and is on every machine with a PostgreSQL client, psql included.
Built and tested against libpq 18.6. Windows links `libpq.lib` and is
untested, like every Windows build here.

So there is no `just` recipe for it and nothing under `pq/lib`.
`foreign import "system:pq"` is resolved by the linker. `odin check` never
opens a foreign import, so `just check` type-checks all three targets on a
machine without libpq installed; only building and testing need it.

### Tests bring their own server

`jm:pq/testdb` starts a throwaway PostgreSQL server for the test process, in
about half a second. Where `initdb` and `pg_ctl` are missing, tests that need
a server log why and skip, so the other suites keep running.

<details>
<summary>Under the hood: how the test server is isolated</summary>

`jm:pq/testdb` runs `initdb` into a fresh directory under the temp location
and `pg_ctl start` on it, once per process:

- a Unix socket in that directory;
- `listen_addresses=''`, so nothing listens on TCP;
- `trust` authentication, behind a socket only this user can reach.

It clears every `PG*` variable. A shell exporting `PGHOSTADDR` or `PGSERVICE`
for a real database would otherwise send a test there. It then sets `PGHOST`,
`PGPORT`, `PGUSER` and `PGDATABASE` to the throwaway, which is also what
`pq.connect("")` reads.

It leaves a shell loop behind that waits for the test process to be gone,
however it went, and then stops the server and deletes the directory. An
`@(fini)` would miss an `os.exit`, a failed assertion and a sanitizer abort.

No Docker, and no server needs to exist beforehand: on this machine `initdb`
and `pg_ctl` come with the `postgresql` package. Where they are not on `PATH`,
every test that needs a server logs why and skips, and `jm-fuzz pq` says so
and runs no cases.

</details>

`pq/fuzz` is the suite: six properties against that server, each case on its
own connection as an unprivileged role with a `statement_timeout`.
`just fuzz "pq -for=1m"` runs it.

## See also

- [Fuzzing](fuzzing.md): both PostgreSQL suites and what they found
- [SQLite](sqlite.md): the same column-lifetime trap, in another dialect
- [Setup](setup.md): installing libpq and the PostgreSQL server tools
- [Packages](packages.md): every package in jm
