# SQLite

`sqlite3/vendor/` holds the SQLite **3.53.4** amalgamation (`sqlite3.c` and
`sqlite3.h`, source id `bf7c7f30031888f4e796e429ab3978879485813aaca6f641c7b33e4e09459bcc`),
taken from sqlite.org and verified against the SHA3-256 that page publishes.
SQLite is public domain, so vendoring it carries no licence obligation.

`just sqlite` compiles it once into `sqlite3/lib/sqlite3.a`, which is
gitignored and rebuilt when the amalgamation changes. `foreign import`
resolves that archive relative to the package directory. `odin check` never
opens a foreign import, so `just check` still type-checks all three targets on
one machine with no archive built.

The compile options are sqlite.org's recommended set, with three deliberate
departures, all of them in the justfile:

- `SQLITE_THREADSAFE=1`, not the recommended `0`. `jm:flow` exists, and a
  connection per worker has to be safe.
- `SQLITE_OMIT_AUTOINIT` is **not** set, though it is recommended. With it, any
  call made before `sqlite3_initialize` is a segfault rather than an error.
- `SQLITE_ENABLE_FTS5` is added, for a full-text index, and
  `SQLITE_OMIT_LOAD_EXTENSION` keeps the link from needing libdl.

One trap is worth knowing even though the package handles it: the bytes behind
a text or blob column are freed on the next `step`, and SQLite reuses its own
pool rather than returning them to libc, so reading a stale pointer yields the
*next* row's data instead of crashing. AddressSanitizer cannot see it. That is
why `text` and `blob` clone into the allocator the query was given.

`sqlite3.hooks` installs the connection's update, commit and rollback
hooks: a watcher buffers the rows the update hook reports and hands the
buffer on at commit, since a change in a transaction that rolls back never
happened. `examples/todo/store` is the pattern.
