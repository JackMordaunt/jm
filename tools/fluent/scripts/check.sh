#!/usr/bin/env bash
# Checks the kit's JSON: each file against its schema, then what a schema
# cannot see — every token path exists, every id and cross-reference
# resolves. Exits non-zero on any error; warnings do not fail.
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0
err() { echo "error: $*"; fail=1; }

schema_check() { # schema instance...
    local schema=$1; shift
    for f in "$@"; do
        if ! out=$(jsonschema --output plain -i "$f" "$schema" 2>&1); then
            out=$(grep -v -e DeprecationWarning -e "from jsonschema.cli" <<< "$out")
            echo "$out" | sed "s|^|$f: |" | head -20
            fail=1
        fi
    done
}
specs=(components/*.json)
[ -e "${specs[0]}" ] || specs=()
[ ${#specs[@]} -gt 0 ] && schema_check schema/component.schema.json "${specs[@]}"
schema_check schema/foundations.schema.json foundations.json
schema_check schema/resolved.schema.json tokens/fluent.resolved.json
# kit.json is generated; a stale one misleads every agent that reads it.
if [ -f kit.json ] && ! diff -q <(scripts/index.sh --stdout) kit.json >/dev/null; then err "kit.json is stale; run just fluent-kit-index"; fi
# tokens/*.json are generated from upstream/; a stale one lies about the pinned package.
if ! diff -q <(node scripts/tokens.mjs --stdout 2>/dev/null) tokens/fluent.resolved.json >/dev/null; then err "tokens/fluent.resolved.json is stale; run just fluent-kit-tokens"; fi

# Token paths: every tokens.* / typographyStyles.* string a file mentions must exist.
known=$(jq -r '.tokens | keys[]' tokens/fluent.resolved.json)
refs() { # every token path a JSON file mentions, as "file<TAB>path"
    jq -r --arg f "$1" '.. | strings | select(test("^(tokens|typographyStyles)\\.[A-Za-z0-9]+$")) | "\($f)\t\(.)"' "$1"
}
while IFS=$'\t' read -r f p; do
    grep -qxF "$p" <<< "$known" || err "$f: unknown token path $p"
done < <(for f in "${specs[@]}" foundations.json; do [ -f "$f" ] && refs "$f"; done)

ids=$(for f in "${specs[@]}"; do basename "$f" .json; done)
for f in "${specs[@]}"; do
    id=$(jq -r .id "$f")
    [ "$id" = "$(basename "$f" .json)" ] || err "$f: id $id does not match the file name"
    r=$(jq -r '.deprecated.replacedBy // empty' "$f")
    [ -z "$r" ] || grep -qxF "$r" <<< "$ids" || err "$f: replacedBy $r is not a component"
    jq -r '[.anatomy[].id] as $a | [.. | objects | .part? // empty] - $a | .[]' "$f" |
        while read -r p; do echo "error: $f: part $p is not an anatomy id"; done | grep . && fail=1
    dup=$(jq -r '[.anatomy[].id] | group_by(.) | map(select(length > 1)[0]) | .[]' "$f")
    [ -z "$dup" ] || err "$f: duplicate anatomy ids: $dup"
    # every source file a spec cites must be vendored under upstream/
    jq -r '.. | objects | .source? // empty' "$f" | tr ';' '\n' | sed 's/^ *//; s/:.*//' | grep -E '\.tsx?$' | sort -u |
        while read -r s; do find upstream -name "$s" | grep -q . || echo "error: $f: cites $s, not under upstream/"; done | grep . && fail=1
done

[ $fail = 0 ] && echo "check: ${#specs[@]} specs ok" || { echo "check: failed"; exit 1; }
