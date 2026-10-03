# fluent-kit

A Fluent 2 implementation kit, written for AI coding agents. Every file is
JSON with a JSON Schema: the tokens per theme, the system rules, and one spec
per component. All of it derives from Fluent UI React v9 at one commit of
`microsoft/fluentui` (`upstream/COMMIT`) and the `@fluentui/tokens` package that
commit publishes. Fluent UI React is Microsoft's reference implementation of
Fluent 2; the design site fills in what the code leaves unsaid.

**Agents start at `kit.json`.** It gives the reading order, the conventions,
and an index of every component.

## Contents

| Path | Schema | What it is |
|---|---|---|
| `kit.json` | — | Generated index: reading order, conventions, file list, and every component's id, status, summary and tokens |
| `foundations.json` | `schema/foundations.schema.json` | System rules every spec assumes: token tiers and themes, the state-per-token rule, colour families and pairing, the type ramp and the Selawik stand-in, shape, spacing, the shadow ramp, focus, disabled, motion, high contrast, and how this kit was built |
| `components/<id>.json` | `schema/component.schema.json` | One spec per component, as described below |
| `tokens/fluent.resolved.json` | `schema/resolved.schema.json` | All 459 tokens and 17 typography styles, flat, keyed `tokens.<name>` as Fluent code spells them. `value` is the web light theme; `dark`, `highContrast`, `teamsLight` and `teamsDark` appear where that theme differs. |
| `tokens/fluent.tokens.json` | DTCG 2025.10 | The same tokens with alias references intact, for theming tools |

A component spec (`components/<id>.json`) holds:
- **Identity:** `status` (stable or preview) and `summary`.
- **API and structure:** `inputs` (a framework-neutral API), `anatomy`, and `variants`, each variant naming the tokens it alone reads.
- **Rules:** `layout`, `states` and `behaviour`. Each rule is one self-contained sentence plus machine fields:
  - `tokens`: token paths;
  - `values`: the numbers Fluent hard-codes in its styles file, with units;
  - `motion`: a duration token and a curve token, or instant;
  - `source`: `use<Name>Styles.styles.ts:lines`, `<Name>.types.ts:lines`, a focus helper, or `fluent2:<page>`.
- **Other:** `accessibility`, and `notes` typed as `upstream-bug`, `hard-coded`, `dead-token`, `contradiction`, `inferred`, `gotcha` or `high-contrast`.

A spec never restates a token value; it names the path. Every such path is
checked to exist, and every source file a spec cites must be vendored under
`upstream/`.

## What is different from a Material kit

- **No component tokens.** Fluent's styles files hard-code sizes and pick
  alias colours. The `values` field carries the numbers.
- **States are tokens, not layers.** Hover reads `colorNeutralBackground1Hover`;
  nothing is blended over a rest colour.
- **Five themes, one vocabulary.** Web light and dark, Teams light and dark,
  and Windows high contrast bind the same alias names.
- **No springs.** Every animation is a duration token and a curve token.
- **The font is proprietary.** Segoe UI is named; Selawik is the open
  Segoe-metric stand-in the foundations recommend.

## Recipes

The kit lives in jm at `tools/fluent`; its recipes are jm's, in the
justfile's `ui/fluent` section, run from jm's root.

```
just fluent-kit-check    # validate every file against its schema; every token path must exist; kit.json and tokens/ must be fresh
just fluent-kit-index    # regenerate kit.json from components/
just fluent-kit-tokens   # regenerate tokens/*.json from upstream/ (node, reads the vendored @fluentui/tokens package)
just fluent-kit-fetch    # re-vendor upstream/ at a commit of microsoft/fluentui (an argument, default master)
just fluent-kit-page     # rebuild kit/index.html
```

`just fluent-tokens` and `just fluent-icons` then turn the kit and the
icons in `icons/` into jm:ui/fluent's generated code.

`just fluent-kit-tokens` runs node because the published package is the truth about
token values: it evaluates the theme objects the way an app would, so no
parser re-derives them. The alias field, which the package cannot give, is
read off the generated alias sources with a small pattern.

## Known gaps in the source

- Fluent names no focus-ring tokens beyond `colorStrokeFocus1` and `2`; the
  ring's widths are constants in `createFocusOutlineStyle.ts` and the
  button's styles file.
- 202 alias tokens are computed in code rather than named from a global, so
  they carry no `alias`.
- The design site describes anatomy and usage that the code cannot; those
  facts are cited as `fluent2:<page>` and marked `inferred` where the code
  is silent.
