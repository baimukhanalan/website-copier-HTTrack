#!/usr/bin/env bash
# grab.sh — one command to mirror a site and make it actually work offline.
#
# Pipeline:  httrack  ->  complete_mirror.py  ->  (optional) playwright capture
#            ->  (optional) serve
#
# Usage:
#   grab.sh <url> [out_dir] [options]
#
# Options:
#   --out DIR            output directory (default: ./mirror-<host>)
#   --depth N            page recursion depth           (default: 3)
#   --ext-depth N        off-domain link depth          (default: 2)
#   --connections N      simultaneous connections       (default: 4)
#   --rate BYTES         max transfer bytes/sec (politeness throttle)
#   --max-time SEC       hard wall-clock cap (HTTrack -E; macOS-safe timeout)
#   --robots             honor robots.txt (default: honored; see --ignore-robots)
#   --ignore-robots      ignore robots.txt (only for sites you own/are allowed)
#   --cdn HOST           also pull assets from this host (repeatable)
#   --no-complete        skip the JS-bundle asset recovery pass
#   --capture            run the Playwright ground-truth capture (needs node+playwright)
#   --serve [PORT]       serve the result when done (default port 8899, SPA fallback)
#   --dry-run            show what would run, do nothing
#   -h --help            this help
#
# Portable: macOS (bash 3.2) and Linux. Only `httrack` + `python3` are required;
# node/playwright are needed only for --capture.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
URL=""; OUT=""; DEPTH=3; EXTDEPTH=1; CONN=4; RATE=""; MAXTIME=""
ROBOTS="honor"; COMPLETE=1; CAPTURE=0; SERVE=0; SERVE_PORT=8899; DRY=0
CDN=""; SCOPE=1
# asset extensions fetched from ANY host (pages stay on the start host)
ASSET_EXTS="css js mjs png jpg jpeg gif svg webp avif ico woff woff2 ttf otf json map mp4 webm mov mp3 wav ogg wasm glb gltf ktx2 basis bin hdr exr draco"

die(){ echo "grab: $*" >&2; exit 1; }
say(){ echo ">> $*" >&2; }
run(){ if [ "$DRY" = 1 ]; then echo "+ $*" >&2; else "$@"; fi; }

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) sed -n '2,30p' "$0"; exit 0;;
    --out) OUT="$2"; shift 2;;
    --depth) DEPTH="$2"; shift 2;;
    --ext-depth) EXTDEPTH="$2"; shift 2;;
    --connections) CONN="$2"; shift 2;;
    --rate) RATE="$2"; shift 2;;
    --max-time) MAXTIME="$2"; shift 2;;
    --robots) ROBOTS="honor"; shift;;
    --ignore-robots) ROBOTS="ignore"; shift;;
    --cdn) CDN="$CDN $2"; shift 2;;
    --wide) SCOPE=0; shift;;
    --no-complete) COMPLETE=0; shift;;
    --capture) CAPTURE=1; shift;;
    --serve) SERVE=1; shift
             if [ $# -gt 0 ] && printf '%s' "${1:-}" | grep -qE '^[0-9]+$'; then SERVE_PORT="$1"; shift; fi;;
    --dry-run) DRY=1; shift;;
    -*) die "unknown option: $1";;
    *) if [ -z "$URL" ]; then URL="$1"; elif [ -z "$OUT" ]; then OUT="$1"; else die "unexpected arg: $1"; fi; shift;;
  esac
done

[ -n "$URL" ] || die "usage: grab.sh <url> [out] [options]   (see --help)"
case "$URL" in http://*|https://*) :;; *) URL="https://$URL";; esac

# derive host and default out dir
HOST="$(printf '%s' "$URL" | sed -E 's#^https?://##; s#/.*$##; s#:.*$##')"
[ -n "$OUT" ] || OUT="./mirror-$HOST"

command -v httrack >/dev/null 2>&1 || die "httrack not found -> brew install httrack (macOS) / apt install httrack (Linux)"
command -v python3 >/dev/null 2>&1 || die "python3 not found"

say "URL=$URL  OUT=$OUT  depth=$DEPTH ext=$EXTDEPTH conn=$CONN robots=$ROBOTS"

# ---- 1. HTTrack mirror -------------------------------------------------------
MARGS="$URL -O $OUT -n --depth=$DEPTH --ext-depth=$EXTDEPTH -c$CONN --disable-security-limits -%v"
[ "$ROBOTS" = ignore ] && MARGS="$MARGS -s0"
[ -n "$RATE" ] && MARGS="$MARGS -A $RATE"
[ -n "$MAXTIME" ] && MARGS="$MARGS -E $MAXTIME"
# Scope: keep PAGES on the start host, but allow ASSETS from any host (incl. CDNs).
# This stops runaway crawls (e.g. a footer link to another site) while still
# grabbing cross-origin css/js/fonts/models the page references.
if [ "$SCOPE" = 1 ]; then
  MARGS="$MARGS -* +$HOST/*"
  for h in $CDN; do MARGS="$MARGS +$h/*"; done
  for e in $ASSET_EXTS; do MARGS="$MARGS +*.$e"; done
else
  for h in $CDN; do MARGS="$MARGS +$h/*"; done
fi
say "httrack $MARGS"
# shellcheck disable=SC2086
run httrack $MARGS || say "httrack returned non-zero (partial mirror is still usable)"

# locate the mirrored host dir
SITEDIR="$OUT/$HOST"
if [ ! -d "$SITEDIR" ]; then
  SITEDIR="$(find "$OUT" -maxdepth 1 -type d ! -path "$OUT" 2>/dev/null | head -1)"
fi
[ -n "$SITEDIR" ] && [ -d "$SITEDIR" ] || { say "no site dir produced under $OUT"; SITEDIR="$OUT"; }
say "site dir: $SITEDIR"

# ---- 2. recover runtime-loaded assets ---------------------------------------
if [ "$COMPLETE" = 1 ]; then
  BASE="$(printf '%s' "$URL" | sed -E 's#(https?://[^/]+).*#\1#')"
  CDNARG=""
  for h in $CDN; do CDNARG="$CDNARG --cdn $h"; done
  say "complete_mirror.py (recovering JS-built assets)"
  # shellcheck disable=SC2086
  run python3 "$HERE/complete_mirror.py" --mirror "$SITEDIR" --base "$BASE" $CDNARG || say "completer had issues (continuing)"
fi

# ---- 3. optional ground-truth capture ---------------------------------------
if [ "$CAPTURE" = 1 ]; then
  if command -v node >/dev/null 2>&1; then
    say "playwright capture (gated/interactive assets)"
    run node "$HERE/capture_playwright.js" "$URL" "$SITEDIR" || say "capture needs: npm i -D playwright && npx playwright install chromium"
  else
    say "node not found -> skipping --capture"
  fi
fi

# ---- 4. report + optional serve ---------------------------------------------
if [ "$DRY" != 1 ]; then
  N="$(find "$SITEDIR" -type f -not -path '*/hts-cache/*' 2>/dev/null | wc -l | tr -d ' ')"
  say "done: $N files in $SITEDIR"
fi
if [ "$SERVE" = 1 ]; then
  say "serving $SITEDIR at http://localhost:$SERVE_PORT/ (Ctrl-C to stop)"
  run python3 "$HERE/serve.py" "$SERVE_PORT" --dir "$SITEDIR" --spa
else
  echo "" >&2
  echo "Next: python3 $HERE/serve.py $SERVE_PORT --dir \"$SITEDIR\" --spa" >&2
fi
