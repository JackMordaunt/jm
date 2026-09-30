#!/usr/bin/env bash
# Generates kit.json, the entry point an agent reads first: what the kit
# holds, in what order to read it, and an index of every component spec.
# --stdout prints instead of writing, for scripts/check.sh's staleness test.
set -euo pipefail
cd "$(dirname "$0")/.."

index=$(jq -n \
    --slurpfile tokens tokens/m3e.resolved.json \
    --slurpfile shapes shapes/shapes.json \
    --slurpfile specs <(jq -s . components/*.json) '
  ($specs[0] | sort_by(.id)) as $c |
  {
    name: "m3e-kit",
    description: "Material 3 Expressive implementation kit: everything needed to build the M3 Expressive components on any renderer. All facts derive from the Jetpack Compose Material 3 sources at one androidx commit.",
    source: { repo: $tokens[0].source.repo, commit: $tokens[0].source.commit },
    readOrder: [
      "kit.json: this index.",
      "foundations.json: system rules every spec assumes (token tiers and modes, units, colour pairing, emphasized type, per-corner shape and morphing, state layers, disabled, focus ring, touch target, spring algorithm, window size classes).",
      "tokens/m3e.resolved.json: every token value, keyed by path. Look up any path a spec names here.",
      "components/<id>.json: one spec per component. Build from its tokenGroups plus its layout, states and behaviour rules; read its notes before trusting a token.",
      "shapes/shapes.json and shapes/morphs.json: only for the shape library and the loading indicator."
    ],
    conventions: {
      tokenPaths: "Strings matching ^(ref|sys|comp)(\\.[a-z0-9-]+)+$ are token paths or group prefixes in tokens/m3e.resolved.json; every one in this kit is checked to exist.",
      sources: "source fields cite Compose as File.kt:line at the pinned commit, or mdc:File.md for MDC-Android docs.",
      units: "dp for dimensions, sp for text, ms for durations; shapes are [top-start, top-end, bottom-end, bottom-start] dp or \"full\"."
    },
    files: [
      { path: "foundations.json", schema: "schema/foundations.schema.json", describes: "System-wide rules." },
      { path: "tokens/m3e.resolved.json", schema: "schema/resolved.schema.json", describes: "All tokens, references resolved, both modes." },
      { path: "tokens/m3e.tokens.json", schema: null, describes: "The same tokens as a DTCG 2025.10 document with references intact, for theming tools." },
      { path: "components/<id>.json", schema: "schema/component.schema.json", describes: "One spec per component." },
      { path: "shapes/shapes.json", schema: "schema/shapes.schema.json", describes: "35 shapes as unit-square cubic Béziers." },
      { path: "shapes/morphs.json", schema: "schema/morphs.schema.json", describes: "Loading indicator morph pairs, pre-matched for linear interpolation." },
      { path: "shapes/svg/<name>.svg", schema: null, describes: "Each shape as SVG, viewBox 0 0 100 100." }
    ],
    counts: { tokens: ($tokens[0].tokens | length), components: ($c | length), shapes: ($shapes[0].shapes | length) },
    components: [ $c[] | {
      id, name, status,
      replacedBy: (.deprecated.replacedBy // null),
      summary, tokenGroups,
      file: "components/\(.id).json"
    } ]
  }')

if [ "${1:-}" = --stdout ]; then echo "$index"; else echo "$index" > kit.json; echo "kit.json: $(jq '.counts' -c kit.json)"; fi
