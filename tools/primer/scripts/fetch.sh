#!/usr/bin/env bash
# Vendors the sources the kit is read from: primer/react at the commit an
# @primer/react release tag names (each component's CSS module, docs JSON
# and implementation, and the postcss mixins they use), the published
# @primer/primitives and @primer/octicons packages at pinned versions, and
# the two behaviour packages Primer React depends on (@primer/behaviors:
# anchored positioning, focus traps and zones; @github/relative-time-element)
# at the versions its lockfile resolves.
# Writes source/COMMIT and source/VERSIONS. Everything is assembled in a
# temp directory, which also receives the previous source/.
set -euo pipefail
cd "$(dirname "$0")/.."
react=${1:-38.40.1}
primitives=${2:-11.10.0}
octicons=${3:-19.38.0}
sha=$(gh api "repos/primer/react/commits/%40primer%2Freact%40$react" --jq .sha)
tmp=$(mktemp -d)
out="$tmp/source"
mkdir -p "$out/react" "$out/mixins" "$out/npm/primitives/dist" "$out/npm/octicons/build"

gh api "repos/primer/react/tarball/$sha" >"$tmp/react.tgz"
tar xzf "$tmp/react.tgz" -C "$tmp"
root=$(echo "$tmp"/primer-react-*)
(cd "$root/packages/react/src" && find . -type f \( -name '*.module.css' -o -name '*.docs.json' -o -name '*.tsx' -o -name '*.ts' \) |
    grep -v -E '\.(test|stories|figma|dev|features|examples)\.|__snapshots__|__tests__|/stories/' |
    while read -r p; do mkdir -p "$out/react/$(dirname "$p")" && cp "$p" "$out/react/$p"; done)
cp "$root"/packages/postcss-preset-primer/src/mixins/*.css "$out/mixins/"

for p in "primitives@$primitives" "octicons@$octicons"; do
    name=${p%@*}
    (cd "$tmp" && npm pack --silent "@primer/$p" >/dev/null)
    mkdir -p "$tmp/$name"
    tar xzf "$tmp/primer-$name-${p#*@}.tgz" -C "$tmp/$name" --strip-components 1
    cp "$tmp/$name/package.json" "$tmp/$name/LICENSE" "$out/npm/$name/"
    [ "$name" != primitives ] || cp "$tmp/$name/DESIGN_TOKENS_GUIDE.md" "$out/npm/$name/"
done
# Only what the kit reads: the token docs and sources, octicons' data.
# The docs carry each token's Figma and LLM metadata (22 MB over the 14
# themes); a token keeps its name, type, resolved value and the alias it
# was written as. An icon keeps its keywords and each size's path data.
cp -R "$tmp/primitives/src" "$out/npm/primitives/"
(cd "$tmp/primitives/dist" && find docs -name '*.json') | while read -r f; do
    mkdir -p "$out/npm/primitives/dist/$(dirname "$f")"
    jq -S 'map_values({type, value} + (if (.original["$value"] | type) == "string" and (.original["$value"] | startswith("{"))
        then {alias: .original["$value"]} else {} end))' "$tmp/primitives/dist/$f" >"$out/npm/primitives/dist/$f"
done
jq -S 'map_values({keywords, heights: (.heights | map_values({width,
    d: [.ast | .. | objects | select(.name == "path") | .attributes.d]}))})' \
    "$tmp/octicons/build/data.json" >"$out/npm/octicons/build/data.json"

locked() { # the version root's package-lock.json resolves package $1 to
    jq -r --arg p "node_modules/$1" '.packages[$p].version' "$root/package-lock.json"
}
behaviors=$(locked @primer/behaviors)
relative=$(locked @github/relative-time-element)
(cd "$tmp" && npm pack --silent "@primer/behaviors@$behaviors" "@github/relative-time-element@$relative" >/dev/null)
mkdir -p "$tmp/behaviors" "$tmp/relative" "$out/npm/behaviors" "$out/npm/relative-time-element"
tar xzf "$tmp/primer-behaviors-$behaviors.tgz" -C "$tmp/behaviors" --strip-components 1
tar xzf "$tmp/github-relative-time-element-$relative.tgz" -C "$tmp/relative" --strip-components 1
cp -R "$tmp/behaviors/dist/esm" "$out/npm/behaviors/"
find "$out/npm/behaviors" \( -name '*.d.ts' -o -name '*.map' -o -path '*/stories/*' \) -delete
cp "$tmp/behaviors/package.json" "$tmp/behaviors/LICENSE" "$out/npm/behaviors/"
cp "$tmp/relative/dist/relative-time-element.js" "$tmp/relative/dist/duration.js" "$tmp/relative/dist/duration-format-ponyfill.js" \
    "$tmp/relative/package.json" "$tmp/relative/LICENSE" "$out/npm/relative-time-element/"

echo "$sha" >"$out/COMMIT"
printf '@primer/react %s\n@primer/primitives %s\n@primer/octicons %s\n@primer/behaviors %s\n@github/relative-time-element %s\n' \
    "$react" "$primitives" "$octicons" "$behaviors" "$relative" >"$out/VERSIONS"
[ ! -e source ] || mv source "$tmp/previous-source"
mv "$out" source
echo "fetched primer/react@$sha ($react), primitives $primitives, octicons $octicons"
