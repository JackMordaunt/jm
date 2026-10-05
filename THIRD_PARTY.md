# Third-party software

jm is licensed under the [Apache License 2.0](LICENSE). The code and data below are not jm's
and keep their own licences. A program built on jm must carry the notice of every component it
links or ships; the third column says where each notice is.

None of these licences restricts selling a program built on jm. Each one requires its notice
to travel with the program, and libgit2's requires its linking exception to be honoured.

## Linked into a program

| Component | Used by | Licence | Notice |
|-----------|---------|---------|--------|
| [SQLite](https://sqlite.org) 3.53.4 | `sqlite3` | Public domain | none required |
| [zstd](https://github.com/facebook/zstd) 1.5.7 | `zstd`, `selfupdate` | BSD-3-Clause (dual BSD/GPLv2; jm takes BSD) | `zstd/vendor/LICENSE` |
| [wasm3](https://github.com/wasm3/wasm3) 0.9.1 | `wasm` | MIT | `wasm/vendor/LICENSE` |
| [libpg_query](https://github.com/pganalyze/libpg_query) 17-latest | `pg_query` | BSD-3-Clause | `pg_query/vendor/LICENSE` |
| PostgreSQL source inside libpg_query | `pg_query` | PostgreSQL Licence | not yet vendored; see below |
| [libgit2](https://libgit2.org) 1.9.7 | `git` | GPLv2 with linking exception | `build/src/libgit2/COPYING`, fetched by `just libgit2` |
| [Blend2D](https://blend2d.com) | `ui/render` | zlib | `build/src/blend2d/LICENSE.md`, fetched by `just blend2d` |
| [asmjit](https://asmjit.com), inside Blend2D | `ui/render` | zlib | `build/src/asmjit/LICENSE.md`, fetched by `just blend2d` |
| odin-blend2d binding | `ui/blend2d` | Unlicense or MIT | `ui/blend2d/LICENSE` |
| [kb_text_shape](https://github.com/JimmyLefevre/kb) | `ui/shape`, `ui/kb` | zlib | `ui/kb/vendor/LICENSE` |
| [AccessKit](https://accesskit.dev) C 0.23.1 | `ui/accesskit` | MIT or Apache-2.0 | the release archive `just accesskit` fetches |

libgit2's licence is the GNU GPL version 2 with an exception that permits linking it, unchanged,
into a program under any licence. A program that modifies libgit2 itself must release those
changes under the GPL. `COPYING` also carries the licences of what libgit2 bundles (zlib, its
regex engine and its HTTP parser); ship the file whole.

AccessKit's prebuilt library is compiled Rust and contains its crate dependencies. Take their
notices from the release that `just accesskit` fetches.

## System libraries

These link dynamically. On Linux and macOS the system provides them; on Windows a program that
uses them ships the DLLs beside itself and their notices with them.

| Component | Used by | Licence |
|-----------|---------|---------|
| [libcurl](https://curl.se) | `http`, `selfupdate` | curl licence (MIT-style) |
| mbedTLS and zlib, under libcurl on Windows | `http` | Apache-2.0; zlib |
| [libpq](https://www.postgresql.org) | `pq` | PostgreSQL Licence |
| [SDL3](https://libsdl.org) | `ui/shell` | zlib |
| [Odin](https://odin-lang.org) `core:` and `vendor:` | everything | zlib |

## Design-system data

The design-system packages are generated from each system's published sources. The generated
files name their source in the header.

| Data | Used by | Licence | Source |
|------|---------|---------|--------|
| Material 3 tokens and shapes | `ui/material` | Apache-2.0 | androidx Compose Material 3, at `tools/material/upstream/COMMIT` |
| Material Symbols | `ui/material` | Apache-2.0 | google/material-design-icons |
| Fluent 2 tokens | `ui/fluent` | MIT | `tools/fluent/upstream/npm/package/LICENSE` |
| Fluent System Icons | `ui/fluent` | MIT | `tools/fluent/icons/LICENSE` |
| Primer primitives and behaviours | `ui/primer` | MIT | `tools/primer/upstream/npm/*/LICENSE` |
| Octicons | `ui/primer` | MIT | `tools/primer/upstream/npm/octicons/LICENSE` |

The Octicons licence covers the icons, not GitHub's logos and marks. Do not use the GitHub
mark, the Octocat or Mona in a shipped program.

## Fonts

| Font | Used by | Licence |
|------|---------|---------|
| Liberation (Arimo, Tinos, Cousine metrics) | `ui/shape` tests only | SIL OFL 1.1, `ui/shape/testdata/LICENSE` |
| Selawik | fluent kitchen, fetched to the user's font folder | SIL OFL 1.1 |
| Noto Sans | both kitchens, from the system | SIL OFL 1.1 |

No font is embedded in a jm package. A program that bundles one ships its OFL text.

## Example assets

`examples/primer-kitchen/avatars` holds pictures of GitHub's Octocat, Mona and Hubot and the
logos of other projects, used to demonstrate the avatar component. They belong to their owners,
are not covered by jm's licence, and must not ship in a program.

## Known gaps

- `pg_query/vendor` holds PostgreSQL source but not PostgreSQL's `COPYRIGHT` file. Until it is
  vendored, a program using `pg_query` should ship the PostgreSQL Licence from
  <https://www.postgresql.org/about/licence/>.
- `tools/material` records the androidx commit its tokens came from, but carries no copy of the
  Apache-2.0 notice from that source.
