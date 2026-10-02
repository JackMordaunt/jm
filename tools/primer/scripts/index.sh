#!/usr/bin/env bash
# Generates kit.json, the entry point an agent reads first: what the kit
# holds, in what order to read it, and an index of every component spec.
# --stdout prints instead of writing, for scripts/check.sh's staleness test.
set -euo pipefail
cd "$(dirname "$0")/.."
mapfile -t specs < <(find components -name '*.json' | sort)
index=$(jq -n \
    --slurpfile tokens tokens/primer.resolved.json \
    --slurpfile specs <(if [ ${#specs[@]} -gt 0 ]; then jq -s . "${specs[@]}"; else echo '[]'; fi) '
  ($specs[0] | sort_by(.id)) as $c |
  {
    name: "primer-kit",
    description: "Primer implementation kit: everything needed to build GitHub Primer React components on any renderer. All facts derive from Primer React at one release of primer/react, the @primer/primitives tokens and @primer/octicons icons at pinned versions, and primer.style.",
    source: $tokens[0].source,
    readOrder: [
      "kit.json: this index.",
      "foundations.json: system rules every spec assumes (token tiers and naming, the 14 themes, colour roles and pairing, the type ramp, radii and borders, spacing, the shadow ramp and z-index, states, focus, motion, control sizes and density, breakpoints, overlays, icons).",
      "tokens/primer.resolved.json: every token value per theme, keyed by the CSS custom property Primer reads (--fgColor-default). Look up any path a spec names here.",
      "components/<id>.json: one spec per component. Build from its tokenGroups plus its layout, states and behaviour rules; its values carry the sizes Primer hard-codes; read its notes before trusting a token."
    ],
    conventions: {
      tokenPaths: "Strings matching ^--[A-Za-z][A-Za-z0-9-]*$ are token paths in tokens/primer.resolved.json; every one in this kit is checked to exist.",
      sources: "source fields cite Primer React files as <Name>.module.css:lines, <Name>.tsx:lines or <Name>.docs.json under source/react, mixins under source/mixins, DESIGN_TOKENS_GUIDE.md, or primer:<slug> for primer.style/product/components.",
      units: "px for dimensions, ms for durations; shadows are layers of {x, y, blur, spread, color, inset}; there are no springs."
    },
    files: [
      { path: "foundations.json", schema: "schema/foundations.schema.json", describes: "System-wide rules." },
      { path: "tokens/primer.resolved.json", schema: "schema/resolved.schema.json", describes: "All tokens, flat, per theme." },
      { path: "components/<id>.json", schema: "schema/component.schema.json", describes: "One spec per component." }
    ],
    components: [ $c[] | { id, name, status, summary, tokenGroups } ]
  }')
if [ "${1:-}" = "--stdout" ]; then echo "$index"; else
    echo "$index" >kit.json
    echo "kit.json: $(jq '.components | length' kit.json) components"
fi
