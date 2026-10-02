#!/usr/bin/env bash
# Checks the kit's JSON: each file against its schema, then what a schema
# cannot see — every token path exists, every id and cross-reference
# resolves, every cited source file is vendored, and the generated files
# are fresh. Exits non-zero on any error.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
fail=0
err() {
    echo "error: $*"
    fail=1
}
validate() {
    if command -v jsonschema >/dev/null; then
        jsonschema "$@"
    else
        uvx --quiet --from jsonschema==4.26.0 jsonschema "$@"
    fi
}

schema_check() { # schema instance...
    local schema=$1
    shift
    for f in "$@"; do
        if ! out=$(validate --output plain -i "$f" "$schema" 2>&1); then
            out=$(grep -v -e DeprecationWarning -e "from jsonschema.cli" <<<"$out")
            echo "$out" | sed "s|^|$f: |" | head -20
            fail=1
        fi
    done
}
specs=(components/*.json)
[ -e "${specs[0]}" ] || specs=()
[ ${#specs[@]} -gt 0 ] && schema_check schema/component.schema.json "${specs[@]}"
schema_check schema/foundations.schema.json foundations.json
schema_check schema/resolved.schema.json tokens/primer.resolved.json
# Generated files: a stale one misleads every agent that reads it.
if [ -f kit.json ] && ! diff -q <(scripts/index.sh --stdout) kit.json >/dev/null; then
    err "kit.json is stale; run just primer-kit-index"
fi
if ! diff -q <(node scripts/tokens.mjs --stdout 2>/dev/null) tokens/primer.resolved.json >/dev/null; then
    err "tokens/primer.resolved.json is stale; run just primer-kit-tokens"
fi

# Token paths: every --name string a file mentions must exist.
known=$(jq -r '.tokens | keys[]' tokens/primer.resolved.json)
refs() { # every token path a JSON file mentions, as "file<TAB>path"
    jq -r --arg f "$1" '.. | strings | select(test("^--[A-Za-z][A-Za-z0-9-]*$")) | "\($f)\t\(.)"' "$1"
}
while IFS=$'\t' read -r f p; do
    grep -qxF -- "$p" <<<"$known" || err "$f: unknown token path $p"
done < <(for f in "${specs[@]}" foundations.json; do [ -f "$f" ] && refs "$f"; done)

# Cited files: every file named in a source field or the references must
# be vendored under source/.
cited() { # every file a JSON file cites
    jq -r '(.. | objects | .source? // empty), (.references?.react // [] | .[])' "$1" |
        tr ';' '\n' | sed 's/^ *//; s/:.*//' | grep -E '\.(css|tsx?|json|md)$' | sort -u
}
# A path is looked up under source/react, then source/; a base name must
# name exactly one file, since 43 base names repeat under source/.
for f in "${specs[@]}" foundations.json; do
    while read -r s; do
        if [[ $s == */* ]]; then
            [ -f "source/react/$s" ] || [ -f "source/$s" ] || err "$f: cites $s, not under source/react or source/"
            continue
        fi
        n=$(find source -name "$s" | wc -l | tr -d " ")
        [ "$n" -eq 1 ] || err "$f: cites $s, which names $n files under source/; cite its path"
    done < <(cited "$f")
done

ids=$(for f in "${specs[@]}"; do basename "$f" .json; done)
for f in "${specs[@]}"; do
    id=$(jq -r .id "$f")
    [ "$id" = "$(basename "$f" .json)" ] || err "$f: id $id does not match the file name"
    r=$(jq -r '.deprecated.replacedBy // empty' "$f")
    [ -z "$r" ] || grep -qxF "$r" <<<"$ids" || err "$f: replacedBy $r is not a component"
    while read -r p; do err "$f: part $p is not an anatomy id"; done < <(jq -r '[.anatomy[].id] as $a | [.. | objects | .part? // empty] - $a | .[]' "$f")
    dup=$(jq -r '[.anatomy[].id] | group_by(.) | map(select(length > 1)[0]) | .[]' "$f")
    [ -z "$dup" ] || err "$f: duplicate anatomy ids: $dup"
done

if [ $fail = 0 ]; then echo "check: ${#specs[@]} specs ok"; else
    echo "check: failed"
    exit 1
fi
