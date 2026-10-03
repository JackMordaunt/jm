# primer-kit

A Primer implementation kit, written for AI coding agents. Every file is
JSON with a JSON Schema: the tokens per theme, the system rules, and one spec
per component. All of it derives from Primer React at the commit an
`@primer/react` release names (`upstream/COMMIT`, `upstream/VERSIONS`), the
`@primer/primitives` tokens and `@primer/octicons` icons at pinned versions,
the `@primer/behaviors` (anchored positioning, focus traps and zones) and
`@github/relative-time-element` builds Primer React's lockfile resolves, and
primer.style where the code leaves something unsaid.

**Agents start at `kit.json`.** It gives the reading order, the conventions,
and an index of every component.

## Contents

| Path | Schema | What it is |
|---|---|---|
| `kit.json` | — | Generated index: reading order, conventions, file list, and every component's id, status, summary and tokens |
| `foundations.json` | `schema/foundations.schema.json` | System rules every spec assumes: token tiers and naming, the 14 themes, colour roles and pairing, the type ramp, radii and borders, spacing, the shadow ramp and z-index, states, focus, motion, control sizes and density, breakpoints, overlays, icons |
| `components/<id>.json` | `schema/component.schema.json` | One spec per component, as described below |
| `tokens/primer.resolved.json` | `schema/resolved.schema.json` | All tokens, flat, keyed by the CSS custom property Primer reads (`--fgColor-default`). `value` is the light theme; the other 13 themes appear where they differ, and `coarse` where a coarse pointer changes a size. |

The token sources with their aliases intact are Primer's own, DTCG-shaped,
under `upstream/npm/primitives/src/tokens`.

A component spec (`components/<id>.json`) holds:
- **Identity:** `status` (alpha, beta, draft, deprecated or experimental, verbatim from Primer's `.docs.json`) and `summary`.
- **API and structure:** `inputs` (a framework-neutral API), `anatomy`, and `variants`, each variant naming the tokens it alone reads.
- **Rules:** `layout`, `states` and `behaviour`. Each rule is one self-contained sentence plus machine fields:
  - `tokens`: token paths;
  - `values`: the numbers Primer hard-codes in a CSS module, with units;
  - `motion`: a duration token and an easing token, a hard-coded duration and curve, or instant;
  - `source`: `<Name>.module.css:lines`, `<Name>.tsx:lines`, `<Name>.docs.json`, a mixin, `DESIGN_TOKENS_GUIDE.md`, or `primer:<page>`.
- **Other:** `accessibility`, and `notes` typed as `upstream-bug`, `hard-coded`, `dead-token`, `contradiction`, `inferred`, `gotcha`, `high-contrast`, `density` or `web-only`.

A spec never restates a token value; it names the path. Every such path is
checked to exist, and every source file a spec cites must be vendored under
`upstream/`.

## What is different from the Fluent and Material kits

- **Three token tiers, partly.** Base scales, functional tokens, and a
  component tier for some components only (`--button-*`, `--control-*`,
  `--label-*`...); the rest compose functional tokens in their CSS.
- **States are tokens, not layers.** Hover reads `--button-default-bgColor-hover`;
  nothing is blended over a rest colour.
- **Fourteen themes, one vocabulary.** Light, dark and dark dimmed, each
  with high-contrast, colorblind and tritanopia variants.
- **Density by pointer.** `size-fine` and `size-coarse` differ only in the
  `-auto` tokens; the coarse value is the `coarse` key.
- **Shadows are CSS box-shadow lists**: several layers with spread, rings
  standing in for borders, and inset layers.
- **The focus outline sits inside the control**, offset −2px.
- **No springs.** Transitions are short colour fades, often hard-coded per module.

## Recipes

The kit lives in jm at `tools/primer`; its recipes are jm's, in the
justfile's `ui/primer` section, run from jm's root.

```
just primer-kit-check    # validate every file against its schema; every token path must exist; kit.json and tokens/ must be fresh
just primer-kit-index    # regenerate kit.json from components/
just primer-kit-tokens   # regenerate tokens/primer.resolved.json from upstream/ (node)
just primer-kit-fetch    # re-vendor upstream/ at pinned releases (gh, npm, jq)
```
