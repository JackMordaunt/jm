#!/usr/bin/env bash
# Checks the kit's JSON: each spec against its schema, then what a schema
# cannot see — every token path exists, every id and cross-reference
# resolves, every component token group is claimed by some spec.
# Exits non-zero on any error; warnings do not fail.
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
schema_check schema/component.schema.json "${specs[@]}"
schema_check schema/foundations.schema.json foundations.json
schema_check schema/resolved.schema.json tokens/m3e.resolved.json
schema_check schema/shapes.schema.json shapes/shapes.json
schema_check schema/morphs.schema.json shapes/morphs.json
# kit.json is generated; a stale one misleads every agent that reads it.
if [ -f kit.json ] && ! diff -q <(scripts/index.sh --stdout) kit.json >/dev/null; then err "kit.json is stale; run just material-kit-index"; fi

# Token paths: exact tokens or group prefixes of the resolved set.
keys=$(jq -r '.tokens | keys[]' tokens/m3e.resolved.json)
groups=$(sed -E 's/\.[^.]+$//' <<< "$keys" | sort -u)
known=$(printf '%s\n%s\n%s\n' "$keys" "$groups" "$(sed -E 's/\.[^.]+$//' <<< "$groups" | sort -u)" | sort -u)
refs() { # every token path a JSON file mentions, as "file<TAB>path"
    jq -r --arg f "$1" '.. | strings | select(test("^(ref|sys|comp)\\.[a-z0-9-]+(\\.[a-z0-9-]+)*$")) | "\($f)\t\(.)"' "$1"
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
done

claimed=$(jq -r '.tokenGroups[], (.variants[].tokenGroup // empty)' "${specs[@]}" | sort -u)
for g in $(jq -r '.comp | keys[] | select(. != "$description")' tokens/m3e.tokens.json); do
    grep -qxF "comp.$g" <<< "$claimed" || echo "warning: comp.$g is claimed by no spec"
done

[ $fail = 0 ] && echo "check: ${#specs[@]} specs ok" || { echo "check: failed"; exit 1; }
