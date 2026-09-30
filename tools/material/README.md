# m3e-kit

A Material 3 Expressive implementation kit, written for AI coding agents.
Every file is JSON with a JSON Schema: the tokens, the system rules, one spec
per component, and the shape library. All of it derives from the Jetpack
Compose Material 3 sources at one androidx commit (`source/COMMIT`). Compose
is Google's reference implementation of Expressive; MDC-Android and Material
Web are in maintenance mode.

**Agents start at `kit.json`.** It gives the reading order, the conventions,
and an index of every component.

## Contents

| Path | Schema | What it is |
|---|---|---|
| `kit.json` | — | Generated index: reading order, conventions, file list, and every component's id, status, summary and token groups |
| `foundations.json` | `schema/foundations.schema.json` | System rules every spec assumes: token tiers and modes, units, colour pairing, emphasized type, per-corner shape and morphing, elevation, state layers, disabled, focus ring, touch target, the spring algorithm, window size classes, and the delta from Material Web v0_192 |
| `components/<id>.json` | `schema/component.schema.json` | One spec per component, as described below |
| `tokens/m3e.resolved.json` | `schema/resolved.schema.json` | All 2,512 tokens, flat, references resolved. `value` is light colour and Expressive springs; `dark` and `standard` give the other modes. |
| `tokens/m3e.tokens.json` | DTCG 2025.10 | The same tokens with references intact, for theming tools |
| `shapes/shapes.json`, `shapes/morphs.json` | `schema/shapes.schema.json`, `schema/morphs.schema.json` | The 35-shape library as unit-square cubic Béziers, and the loading indicator's pre-matched morph pairs |
| `kit/index.html` | — | A human view of all of the above |

A component spec (`components/<id>.json`) holds:
- **Identity:** `status` (new, changed or unchanged), and `deprecated.replacedBy` where Expressive retires the component.
- **API and structure:** `inputs` (a framework-neutral API), `anatomy`, and `variants`, each variant mapped to its token group.
- **Rules:** `layout`, `states` and `behaviour`. Each rule is one self-contained sentence plus machine fields:
  - `tokens`: token paths;
  - `values`: hard-coded numbers with units;
  - `motion`: a named spring, a literal spring, a duration, or instant;
  - `source`: `File.kt:line` or `mdc:File.md`.
- **Other:** `accessibility`, and `notes` typed as `upstream-bug`, `missing-token`, `dead-token`, `contradiction`, `inferred` or `gotcha`.

A spec never restates a token value; it names the path. Every such path is
checked to exist.

## Recipes

The kit lives in jm at `tools/material`; its recipes are jm's, in the
justfile's `ui/material` section, run from jm's root.

```
just material-kit-check    # validate every file against its schema; every token path must exist; kit.json must be fresh
just material-kit-index    # regenerate kit.json from components/
just material-kit-tokens   # re-parse source/tokens into tokens/*.json (Odin, m3e-tokens/)
just material-kit-shapes   # regenerate shapes/ from graphics-shapes (Java 21, shapes/gen/)
just material-kit-fetch    # pull token sources at androidx-main, updating source/COMMIT
just material-kit-page     # rebuild kit/index.html
```

`just test` runs the parser's tests, including a full parse of source/.
`just material-tokens` and `just material-shapes` then turn the kit into
jm:ui/material's generated code.

The token parser is strict. An expression shape it has never seen fails the
run instead of dropping a token. So after `just material-kit-fetch`, a failing
`just material-kit-tokens` means the upstream format changed; extend
`parse_value` in `m3e-tokens/parse.odin`.

## Known gaps in the source

- **Missing values.**
  - Compose names no font file; both font slots are the platform sans-serif.
  - There are no shadow geometry tokens, no focus-ring tokens (Material Web's
    are used), and no `shadow` colour role.
- **Code or docs only.**
  - Some behaviour exists only in Compose code, not tokens. The specs cite it
    as `values` with a `source`.
  - A few components have tokens but no Compose implementation: the docked
    toolbar, side sheet, and slider value indicator. Their specs are marked
    `inferred` from the MDC docs.
