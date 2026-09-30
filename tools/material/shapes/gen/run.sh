#!/usr/bin/env bash
# Regenerates shapes.json, morphs.json and svg/ in the parent directory.
# Needs java >= 21 and curl. Jars are cached in ${M3E_SHAPES_LIB:-$TMPDIR/m3e-shapes-lib}.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
lib="${M3E_SHAPES_LIB:-${TMPDIR:-/tmp}/m3e-shapes-lib}"
mkdir -p "$lib"
g=https://dl.google.com/android/maven2
c=https://repo1.maven.org/maven2
jars=(
  "$g/androidx/graphics/graphics-shapes-desktop/1.0.1/graphics-shapes-desktop-1.0.1.jar"
  "$g/androidx/collection/collection-jvm/1.4.2/collection-jvm-1.4.2.jar"
  "$g/androidx/annotation/annotation-jvm/1.8.1/annotation-jvm-1.8.1.jar"
  "$c/org/jetbrains/kotlin/kotlin-stdlib/1.9.24/kotlin-stdlib-1.9.24.jar"
)
cp=""
for url in "${jars[@]}"; do
  f="$lib/$(basename "$url")"
  [[ -s "$f" ]] || curl -sfL "$url" -o "$f"
  cp="$cp${cp:+:}$f"
done
java -cp "$cp" "$here/ExportShapes.java" "$here/.."
