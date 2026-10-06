# SQLite

**A real SQL database inside your program, with nothing to install and no
quoting to get wrong.**

- **One binary.** SQLite is compiled in, so a built program needs no system
  library and no shared object.
- **Values are always bound.** An apostrophe, a newline or a NUL byte
  round-trips unchanged, and there is no string-building path for an injection.
- **Safe memory by default.** Text and blob columns are copied out before
  SQLite can reuse them.
- **Change feeds.** Hooks report the rows a committed transaction touched, so
  a UI can refresh when the data changes.
- **Full-text search** is built in through FTS5.

| At a glance | |
|---|---|
| Version | SQLite **3.53.4** |
| Licence | Public domain |
| Links | Statically, from `sqlite3/lib/sqlite3.a` |
| Builds with | `just sqlite` |

## Quick start

```odin
db := must(sqlite3.open("notes.db"))
defer sqlite3.close(&db)

must(sqlite3.exec(db, `CREATE TABLE IF NOT EXISTS note(id INTEGER PRIMARY KEY, body TEXT)`))
must(sqlite3.exec_args(db, `INSERT INTO note(body) VALUES (?)`, "it isn't quoted by hand"))

rows := must(sqlite3.query(db, `SELECT id, body FROM note WHERE body LIKE ?`, "%isn't%"))
defer sqlite3.finish(&rows)
for sqlite3.next(&rows) {
	fmt.println(sqlite3.integer(rows, 0), sqlite3.text(rows, 1))
}
```

## Typed queries

`tools/jm-sqlgen` turns a package's SQL into Odin that the compiler checks. A
package keeps a `schema.sql` and a `queries.sql`, each opening with
`-- engine: sqlite`:

```sql
-- name: todo_state :one
-- Whether todo id exists, and whether it is done.
-- params: id: i64
SELECT done AS "done: bool" FROM todo WHERE id = @id;
```

`just sqlgen <dir>` writes `queries_gen.odin` beside them, which holds a
`Todo_State_Row` struct and this proc:

```odin
todo_state :: proc(db: sqlite3.Db, id: i64, allocator := context.allocator) -> (
	row: Todo_State_Row, found: bool, err: sqlite3.Error)
```

A `:many` query `todos` comes three ways: the cursor (`todos_open`,
`todos_next`, `todos_close`); `todos`, the cursor as a guard that closes at
the end of its block and leaves what stopped it in `rows.err`; and
`todos_all`, every row in a slice in the caller's allocator.

A swapped or missing argument is a compile error. A misspelt column fails the
generator. Editing either SQL file without regenerating fails the build,
through a compile-time hash of each. `check(db)` re-prepares every query
against a live database, so a schema that drifted from `schema.sql` fails when
the database is opened.

SQLite supplies the types. A column that reads a table column directly takes
its declared type. It is `Maybe` unless the column is NOT NULL and the
statement's bytecode shows nothing that can produce a NULL, such as an outer
join, an aggregate or a subquery. Tables must be STRICT, because only a STRICT
table holds to its declared types. An expression, or a column of a
compound SELECT, is annotated in its alias, as `done` is above.

An annotation is a claim, so `queries_gen_test.odin` tests it. Every query
runs against several data sets: empty tables, every nullable column NULL, the
extremes of each type, and each table alone. Each value read is checked
against its generated type. A parameter type that a STRICT column cannot
convert fails too. One that it can convert, such as an `i64` written to a
TEXT column, does not, so parameter annotations are only partly verified.

The tool's doc comment (`tools/jm-sqlgen/main.odin`) has the full format.
`examples/todo/store/db` is the todo app's SQL, generated this way, and
`tools/jm-sqlgen/testdata/notes` covers the result kinds and an outer join.
The same tool generates for PostgreSQL over `jm:pq`: see
[PostgreSQL](postgres.md#typed-queries).

## Watch what changed

`sqlite3.hooks` installs the connection's update, commit and rollback hooks.
A watcher buffers the rows the update hook reports and hands the buffer on at
commit. A change in a transaction that rolls back never happened, so the
rollback hook drops the buffer.

`examples/todo/store` is the pattern: its commit hook pushes each batch into a
stream pipeline, which re-runs the live queries on every batch.

## Use it from several threads

The build runs SQLite with `SQLITE_THREADSAFE=1`, because `jm:flow` exists and
a connection per worker has to be safe. Give each worker its own connection.

## Memory you can trust

> [!WARNING]
> SQLite frees the bytes behind a text or blob column on the next `step`. The
> package already copies them for you; do not reach around it with the raw API.

<details>
<summary>Under the hood: why a stale column pointer is silent</summary>

SQLite reuses its own pool rather than returning freed memory to libc. Reading
a stale pointer therefore yields the *next* row's data instead of crashing,
and AddressSanitizer cannot see it. That is why `text` and `blob` clone into
the allocator the query was given.

</details>

<details>
<summary>Under the hood: provenance, build and compile options</summary>

`sqlite3/vendor/` holds the SQLite **3.53.4** amalgamation (`sqlite3.c` and
`sqlite3.h`, source id
`bf7c7f30031888f4e796e429ab3978879485813aaca6f641c7b33e4e09459bcc`). It was
taken from sqlite.org and verified against the SHA3-256 that page publishes.
SQLite is public domain, so vendoring it carries no licence obligation.

`just sqlite` compiles it once into `sqlite3/lib/sqlite3.a`, which is
gitignored and rebuilt when the amalgamation or the compile options change.
`foreign import` resolves that archive relative to the package directory. `odin check` never
opens a foreign import, so `just check` still type-checks all three targets on
one machine with no archive built.

The compile options are sqlite.org's recommended set, with four deliberate
departures, all of them in the justfile:

| Option | Recommended | Here | Why |
|---|---|---|---|
| `SQLITE_THREADSAFE` | `0` | `1` | A connection per `jm:flow` worker has to be safe. |
| `SQLITE_OMIT_AUTOINIT` | set | **not** set | With it, any call made before `sqlite3_initialize` is a segfault rather than an error. |
| `SQLITE_ENABLE_FTS5` | — | added | A full-text index. |
| `SQLITE_ENABLE_COLUMN_METADATA` | — | added, in place of `SQLITE_OMIT_DECLTYPE` | `jm-sqlgen` asks which table column a result column reads. The two options exclude each other; the archive grows by 1.7 KB. |

`SQLITE_OMIT_LOAD_EXTENSION` keeps the link from needing libdl.

</details>

## See also

- [Packages](packages.md): every package in jm
- [Streams](streams.md): the pipeline the todo app feeds its change batches into
- [UI](ui.md): the todo and files apps, which keep their data in SQLite
- [Fuzzing](fuzzing.md): the `jm:sqlite3` property suite
