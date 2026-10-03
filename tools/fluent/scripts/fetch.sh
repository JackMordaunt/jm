#!/usr/bin/env bash
# Vendors the sources the kit is read from, at one commit: the token
# package sources, the focus helpers, the styles and types files of every
# component package listed below, and the published @fluentui/tokens at
# the version that commit's package.json names. Writes upstream/COMMIT.
set -euo pipefail
cd "$(dirname "$0")/.."
ref=${1:-master}
sha=$(gh api "repos/microsoft/fluentui/commits/$ref" --jq .sha)
tree=$(mktemp)
gh api "repos/microsoft/fluentui/git/trees/$sha?recursive=1" --jq '.tree[] | select(.type=="blob") | .path' > "$tree"
raw="https://raw.githubusercontent.com/microsoft/fluentui/$sha"
rm -rf upstream && mkdir -p upstream/tokens upstream/focus upstream/components upstream/npm
echo "$sha" > upstream/COMMIT
grep '^packages/tokens/src/' "$tree" | grep -v -E '\.test\.|spec-e2e' | while read -r p; do
    out="upstream/tokens/${p#packages/tokens/src/}"; mkdir -p "$(dirname "$out")"
    curl -sfL --max-time 60 -o "$out" "$raw/$p"
done
for f in constants createCustomFocusIndicatorStyle createFocusOutlineStyle; do
    curl -sfL --max-time 60 -o "upstream/focus/$f.ts" "$raw/packages/react-components/react-tabster/src/focus/$f.ts"
done
pkgs='button|checkbox|radio|switch|input|textarea|slider|card|divider|tabs|menu|dialog|tooltip|badge|progress|spinner|link|label|toolbar|avatar|accordion|field|breadcrumb|carousel|combobox|drawer|infolabel|list|message-bar|nav|persona|popover|rating|search|select|skeleton|spinbutton|swatch-picker|table|tag-picker|tags|teaching-popover|text|toast|tree|color-picker|calendar-compat|datepicker-compat|timepicker-compat'
grep -E "^packages/react-components/react-($pkgs)/library/src/components/[A-Za-z]+/(use[A-Za-z]+\.styles\.ts|[A-Za-z]+\.types\.ts)$" "$tree" | while read -r p; do
    rel="${p#packages/react-components/}"; pkg="${rel%%/*}"; comp=$(basename "$(dirname "$rel")")
    mkdir -p "upstream/components/$pkg/$comp"
    curl -sfL --max-time 60 -o "upstream/components/$pkg/$comp/${p##*/}" "$raw/$p"
done
# the files the specs cite beyond the styles and types files, listed in
# scripts/extra-sources.txt as they land under upstream/components/
grep -v '^#' scripts/extra-sources.txt | grep . | while read -r rel repo; do
    pkg="${rel%%/*}"; rest="${repo:-${rel#*/}}"
    mkdir -p "upstream/components/$(dirname "$rel")"
    curl -sfL --max-time 60 -o "upstream/components/$rel" "$raw/packages/react-components/$pkg/library/src/$rest"
done
mkdir -p upstream/motion
for m in Collapse Fade Scale Slide; do curl -sfL --max-time 60 -o "upstream/motion/$m.ts" "$raw/packages/react-components/react-motion-components-preview/library/src/components/$m/$m.ts"; done
version=$(curl -sfL "$raw/packages/tokens/package.json" | jq -r .version)
(cd upstream/npm && npm pack "@fluentui/tokens@$version" --pack-destination . >/dev/null && tar xzf "fluentui-tokens-$version.tgz" && rm "fluentui-tokens-$version.tgz")
echo "fetched microsoft/fluentui@$sha, @fluentui/tokens@$version"
