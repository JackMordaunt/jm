#!/usr/bin/env bash
# Bundles the kit into one self-contained page: kit/index.html.
# The template's __KIT_DATA__ is replaced by a JSON object holding the
# resolved tokens, the foundations and component specs, and the shapes.
set -euo pipefail
cd "$(dirname "$0")/.."

shapes=shapes/shapes.json
morphs=shapes/morphs.json
[ -f "$shapes" ] || shapes=<(echo null)
[ -f "$morphs" ] || morphs=<(echo null)

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
jq -s . components/*.json > "$tmp/components.json"

data=$(jq -n \
    --slurpfile tokens tokens/m3e.resolved.json \
    --slurpfile foundations foundations.json \
    --slurpfile components "$tmp/components.json" \
    --slurpfile shapes "$shapes" \
    --slurpfile morphs "$morphs" \
    '{source: $tokens[0].source, tokens: $tokens[0].tokens, foundations: $foundations[0],
      components: $components[0], shapes: $shapes[0], morphs: $morphs[0]}' |
    # "</" inside a script element would end it early; "<\/" is the same JSON.
    sed 's#</#<\\/#g')

{
    awk '/__KIT_DATA__/ {exit} {print}' kit/index.template.html
    printf '%s\n' "$data"
    awk 'found {print} /__KIT_DATA__/ {found = 1}' kit/index.template.html
} > kit/index.html
echo "kit/index.html: $(wc -c < kit/index.html) bytes, $(jq length "$tmp/components.json") component specs"
