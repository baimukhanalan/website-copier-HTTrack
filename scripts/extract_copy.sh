#!/usr/bin/env bash
# extract_copy.sh — pull human-readable copy from a (minified) JS bundle.
# Canvas/WebGL sites bake their on-screen text into the bundle as string
# literals; this surfaces them while filtering shader/GLSL/minified noise.
#
#   scripts/extract_copy.sh <bundle.js> [min_len] [max_len]
#
# Strategy:
#   1. If a source map is referenced, say so (that's the real goldmine).
#   2. Beautify when js-beautify is available (splits packed lines).
#   3. Grep quoted/backtick string literals that look like prose
#      (contain a space + letters, sane length), minus code/GLSL tokens.
set -euo pipefail

JS="${1:?usage: extract_copy.sh <bundle.js> [min_len] [max_len]}"
MIN="${2:-6}"
MAX="${3:-120}"
[ -f "$JS" ] || { echo "no such file: $JS" >&2; exit 1; }

if grep -aoE 'sourceMappingURL=[^ "]+' "$JS" | head -1 | grep -q .; then
  echo "### source map referenced -> fetch it and read original strings there:" >&2
  grep -aoE 'sourceMappingURL=[^ "]+' "$JS" | head -1 >&2
  echo "" >&2
fi

SRC="$JS"
TMP="$(mktemp -t bundle).js"
if command -v js-beautify >/dev/null 2>&1; then
  js-beautify -q "$JS" > "$TMP" 2>/dev/null || true
elif command -v npx >/dev/null 2>&1; then
  npx --yes js-beautify "$JS" > "$TMP" 2>/dev/null || true
fi
# Only use the beautified copy if it is actually non-empty (npx can no-op to empty).
if [ -s "$TMP" ]; then SRC="$TMP"; fi

# Quoted + backtick literals that read like copy.
grep -aoE "[\"\`'][^\"\`']{${MIN},${MAX}}[\"\`']" "$SRC" \
  | sed -E "s/^[\"\`']//; s/[\"\`']$//" \
  | grep -E '[A-Za-z].*[ ].*[A-Za-z]' \
  | grep -viE 'function|return|undefined|prototype|webkit|https?:|[0-9]+px|rgba?\(|matrix|attribute|uniform|gl_|vec[0-9]|mat[0-9]|float |const |#define|#ifdef|texture|varying|className|querySelector|appendChild|addEventListener|charCodeAt' \
  | grep -vE '^[a-z]+([A-Z][a-z]+)+$' \
  | sort -u
