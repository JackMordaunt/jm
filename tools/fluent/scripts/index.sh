#!/usr/bin/env bash
# Generates kit.json, the entry point an agent reads first: what the kit
# holds, in what order to read it, and an index of every component spec.
# --stdout prints instead of writing, for scripts/check.sh's staleness test.
set -euo pipefail
cd "$(dirname "$0")/.."
specs=$(ls components/*.json 2>/dev/null | sort || true)
index=$(jq -n \
    --slurpfile tokens tokens/fluent.resolved.json \
    --slurpfile specs <(if [ -n "$specs" ]; then jq -s . $specs; else echo '[]'; fi) '
  ($specs[0] | sort_by(.id)) as $c |
  {
    name: "fluent-kit",
    description: "Fluent 2 implementation kit: everything needed to build the Fluent UI v9 components on any renderer. All facts derive from Fluent UI React v9 at one commit of microsoft/fluentui and the @fluentui/tokens package it publishes.",
    source: $tokens[0].source,
    readOrder: [
      "kit.json: this index.",
      "foundations.json: system rules every spec assumes (token tiers and themes, the state-per-token rule, colour families and pairing, the type ramp and the Selawik stand-in, shape, spacing, the shadow ramp, focus, disabled, motion, high contrast).",
      "tokens/fluent.resolved.json: every token value per theme, keyed by tokens.<name> as Fluent code spells it. Look up any path a spec names here.",
      "components/<id>.json: one spec per component. Build from its tokenGroups plus its layout, states and behaviour rules; its values carry the sizes Fluent hard-codes; read its notes before trusting a token."
    ],
    conventions: {
      tokenPaths: "Strings matching ^(tokens|typographyStyles)\\.[A-Za-z0-9]+$ are token paths in tokens/fluent.resolved.json; every one in this kit is checked to exist.",
      sources: "source fields cite Fluent UI React files as use<Name>Styles.styles.ts:lines or <Name>.types.ts:lines under source/components, the focus helpers under source/focus, or fluent2:<page> for the design site.",
      units: "px for dimensions, ms for durations; shadows are layers of {x, y, blur, color}; there are no per-corner radii and no springs."
    },
    files: [
      { path: "foundations.json", schema: "schema/foundations.schema.json", describes: "System-wide rules." },
      { path: "tokens/fluent.resolved.json", schema: "schema/resolved.schema.json", describes: "All tokens, flat, per theme." },
      { path: "tokens/fluent.tokens.json", schema: "DTCG 2025.10", describes: "The same tokens with alias references, for theming tools." },
      { path: "components/<id>.json", schema: "schema/component.schema.json", describes: "One spec per component." }
    ],
    components: [ $c[] | { id, name, status, summary, tokenGroups } ]
  }')
if [ "${1:-}" = "--stdout" ]; then echo "$index"; else echo "$index" > kit.json; echo "kit.json: $(jq '.components | length' kit.json) components"; fi
