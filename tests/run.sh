#!/usr/bin/env bash
# run.sh — end-to-end + unit test harness for website-copier-HTTrack.
# Exits non-zero on any failure. Portable (macOS bash 3.2 + Linux).
# No network required: an ephemeral local origin server stands in for the site.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$ROOT/scripts"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/wch-test.XXXXXX")"
PASS=0; FAIL=0; PIDS=""
cleanup(){ for p in $PIDS; do kill "$p" 2>/dev/null || true; done; rm -rf "$TMP"; }
trap cleanup EXIT

ok(){ PASS=$((PASS+1)); echo "  ok: $*"; }
no(){ FAIL=$((FAIL+1)); echo "  FAIL: $*" >&2; }
has(){ printf '%s' "$1" | grep -qF -e "$2"; }

freeport(){ python3 -c 'import socket;s=socket.socket();s.bind(("",0));print(s.getsockname()[1]);s.close()'; }
wait_up(){ # host:port path
  for _ in $(seq 1 50); do curl -fsS "http://127.0.0.1:$1$2" >/dev/null 2>&1 && return 0; sleep 0.1; done; return 1; }

echo "== 1. syntax checks =="
for f in serve.py complete_mirror.py; do
  if python3 -m py_compile "$S/$f"; then ok "py_compile $f"; else no "py_compile $f"; fi
done
for f in grab.sh mirror.sh extract_copy.sh; do
  if bash -n "$S/$f"; then ok "bash -n $f"; else no "bash -n $f"; fi
done
if command -v node >/dev/null 2>&1; then
  if node --check "$S/capture_playwright.js"; then ok "node --check capture_playwright.js"; else no "node --check capture"; fi
fi

echo "== 2. extract_copy.sh =="
mkdir -p "$TMP/b"
cat > "$TMP/b/main.js" <<'EOF'
const a="Stop applying. Start interviewing.";const b=`Your journey runs itself now`;
const c='Join the beta today';function q(){return document.querySelector(".x")}
const gl="attribute vec3 position";const u="uniform mat4 projectionMatrix";
EOF
OUT="$("$S/extract_copy.sh" "$TMP/b/main.js" 2>/dev/null || true)"
has "$OUT" "Stop applying. Start interviewing." && ok "copy: tagline" || no "copy: tagline missing"
has "$OUT" "Join the beta today" && ok "copy: cta" || no "copy: cta missing"
if has "$OUT" "querySelector" || has "$OUT" "uniform mat4"; then no "copy: code/GLSL leaked"; else ok "copy: code/GLSL filtered"; fi

echo "== 3. complete_mirror.py (REAL e2e download from a local origin) =="
# Build an "origin" that HAS the assets, and a "mirror" that is MISSING them.
ORIGIN="$TMP/origin"; MIRROR="$TMP/mirror"
mkdir -p "$ORIGIN/assets/logos" "$ORIGIN/assets/origami" "$ORIGIN/assets/ui" "$ORIGIN/cdnpath"
echo "PNGDATA" > "$ORIGIN/assets/ui/plant.webp"
echo "G" > "$ORIGIN/assets/origami/profile.glb"
echo "G" > "$ORIGIN/assets/origami/match.glb"
echo "L" > "$ORIGIN/assets/logos/google.webp"
echo "C" > "$ORIGIN/cdnpath/extra.webp"
mkdir -p "$MIRROR/assets"
cat > "$MIRROR/assets/main.js" <<EOF
const stat="assets/ui/plant.webp";
const names=["profile","match"];loader.load(\`assets/origami/\${names[i]}.glb\`);
const co=[{logo:\`google\`}];fetch(\`assets/logos/\${c.logo}.webp\`);
const abs="http://127.0.0.1:__PORT__/cdnpath/extra.webp";
EOF
OPORT="$(freeport)"
sed -i.bak "s/__PORT__/$OPORT/" "$MIRROR/assets/main.js" && rm -f "$MIRROR/assets/main.js.bak"
( cd "$ORIGIN" && python3 "$S/serve.py" "$OPORT" --dir "$ORIGIN" >/dev/null 2>&1 ) &
PIDS="$PIDS $!"; disown 2>/dev/null || true
if wait_up "$OPORT" "/assets/ui/plant.webp"; then ok "origin server up"; else no "origin server did not start"; fi
python3 "$S/complete_mirror.py" --mirror "$MIRROR" --base "http://127.0.0.1:$OPORT" \
        --cdn "127.0.0.1:$OPORT" >/dev/null 2>&1 || true
[ -f "$MIRROR/assets/ui/plant.webp" ] && ok "recovered: static path" || no "static path not recovered"
[ -f "$MIRROR/assets/origami/profile.glb" ] && [ -f "$MIRROR/assets/origami/match.glb" ] && ok "recovered: array template" || no "array template not recovered"
[ -f "$MIRROR/assets/logos/google.webp" ] && ok "recovered: object-field template" || no "object-field template not recovered"
[ -f "$MIRROR/127.0.0.1:$OPORT/cdnpath/extra.webp" ] || [ -f "$MIRROR/cdnpath/extra.webp" ] && ok "recovered: absolute/CDN url" || no "absolute url not recovered"

echo "== 4. serve.py (MIME + CORS + SPA) =="
SITE="$TMP/site"; mkdir -p "$SITE/sub"
printf '<!doctype html><title>home</title>' > "$SITE/index.html"
printf 'export const x=1;' > "$SITE/app.mjs"
printf '\0asm' > "$SITE/mod.wasm"
printf 'GLB' > "$SITE/model.glb"
SPORT="$(freeport)"
( python3 "$S/serve.py" "$SPORT" --dir "$SITE" --spa >/dev/null 2>&1 ) &
PIDS="$PIDS $!"; disown 2>/dev/null || true
if wait_up "$SPORT" "/index.html"; then ok "serve.py up" ; else no "serve.py did not start"; fi
CT_MJS="$(curl -fsS -D - -o /dev/null "http://127.0.0.1:$SPORT/app.mjs" 2>/dev/null | tr -d '\r')"
has "$CT_MJS" "text/javascript" && ok "mime: .mjs = text/javascript" || no "mime: .mjs wrong"
has "$CT_MJS" "Access-Control-Allow-Origin: *" && ok "cors header present" || no "cors header missing"
CT_WASM="$(curl -fsS -D - -o /dev/null "http://127.0.0.1:$SPORT/mod.wasm" 2>/dev/null | tr -d '\r')"
has "$CT_WASM" "application/wasm" && ok "mime: .wasm = application/wasm" || no "mime: .wasm wrong"
CT_GLB="$(curl -fsS -D - -o /dev/null "http://127.0.0.1:$SPORT/model.glb" 2>/dev/null | tr -d '\r')"
has "$CT_GLB" "model/gltf-binary" && ok "mime: .glb = model/gltf-binary" || no "mime: .glb wrong"
BODY="$(curl -fsS "http://127.0.0.1:$SPORT/some/spa/route" 2>/dev/null || true)"
has "$BODY" "home" && ok "spa fallback -> index.html" || no "spa fallback failed"

echo "== 5. grab.sh / mirror.sh arg parsing (dry-run, no network) =="
DRUN="$("$S/grab.sh" example.com --out "$TMP/g" --depth 2 --ignore-robots --cdn img.example.com --dry-run 2>&1 || true)"
has "$DRUN" "https://example.com" && ok "grab: scheme auto-added" || no "grab: scheme not added"
has "$DRUN" "-s0" && ok "grab: --ignore-robots -> -s0" || no "grab: robots flag missing"
has "$DRUN" "+img.example.com/*" && ok "grab: --cdn -> httrack filter" || no "grab: cdn filter missing"
MH="$("$S/mirror.sh" -h 2>&1 || true)"; has "$MH" "mirror.sh" && ok "mirror.sh --help" || no "mirror.sh help broken"
GH="$("$S/grab.sh" --help 2>&1 || true)"; has "$GH" "grab.sh" && ok "grab.sh --help" || no "grab.sh help broken"

echo ""
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
