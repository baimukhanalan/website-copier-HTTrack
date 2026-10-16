#!/usr/bin/env bash
# mirror.sh — HTTrack wrapper with verified flags, portable (macOS bash 3.2 + Linux).
# macOS has no `timeout`; bound a run with --max-time (HTTrack's own -E).
#
#   mirror.sh <url> <out_dir> [--depth N] [--ext-depth N] [--connections N]
#             [--rate BYTES] [--max-time SEC] [--ignore-robots] [-- <extra httrack args>]
#
# Example:
#   mirror.sh https://why.zero.university ./mirror --max-time 180
set -euo pipefail

URL=""; OUT=""; DEPTH=3; EXTDEPTH=1; CONN=4; RATE=""; MAXTIME=""; ROBOTS="honor"
EXTRA=""; SCOPE=1
ASSET_EXTS="css js mjs png jpg jpeg gif svg webp avif ico woff woff2 ttf otf json map mp4 webm mov mp3 wav ogg wasm glb gltf ktx2 basis bin hdr exr draco"

die(){ echo "mirror: $*" >&2; exit 1; }
while [ $# -gt 0 ]; do
  case "$1" in
    --depth) DEPTH="$2"; shift 2;;
    --ext-depth) EXTDEPTH="$2"; shift 2;;
    --connections) CONN="$2"; shift 2;;
    --rate) RATE="$2"; shift 2;;
    --max-time) MAXTIME="$2"; shift 2;;
    --ignore-robots) ROBOTS="ignore"; shift;;
    --wide) SCOPE=0; shift;;
    --) shift; EXTRA="$*"; break;;
    -h|--help) sed -n '2,12p' "$0"; exit 0;;
    -*) die "unknown option: $1";;
    *) if [ -z "$URL" ]; then URL="$1"; elif [ -z "$OUT" ]; then OUT="$1"; else die "unexpected: $1"; fi; shift;;
  esac
done

[ -n "$URL" ] && [ -n "$OUT" ] || die "usage: mirror.sh <url> <out_dir> [options]"
case "$URL" in http://*|https://*) :;; *) URL="https://$URL";; esac
HOST="$(printf '%s' "$URL" | sed -E 's#^https?://##; s#/.*$##; s#:.*$##')"
command -v httrack >/dev/null 2>&1 || die "httrack not found. Install: brew install httrack / apt install httrack"
mkdir -p "$OUT"

ARGS="$URL -O $OUT -n --depth=$DEPTH --ext-depth=$EXTDEPTH -c$CONN --disable-security-limits -%v"
[ "$ROBOTS" = ignore ] && ARGS="$ARGS -s0"
[ -n "$RATE" ] && ARGS="$ARGS -A $RATE"
[ -n "$MAXTIME" ] && ARGS="$ARGS -E $MAXTIME"
# Scope: pages on start host, assets from anywhere (prevents runaway crawls).
if [ "$SCOPE" = 1 ]; then
  ARGS="$ARGS -* +$HOST/*"
  for e in $ASSET_EXTS; do ARGS="$ARGS +*.$e"; done
fi
[ -n "$EXTRA" ] && ARGS="$ARGS $EXTRA"

echo "httrack $ARGS" >&2
# shellcheck disable=SC2086
httrack $ARGS

echo "" >&2
echo "Files:" >&2
find "$OUT" -type f -not -path '*/hts-cache/*' -not -name '*.gif' -not -name 'hts-log.txt' 2>/dev/null | sort >&2
SITE="$(find "$OUT" -maxdepth 1 -type d ! -path "$OUT" 2>/dev/null | head -1)"
echo "" >&2
echo "Serve:  python3 $(dirname "$0")/serve.py 8899 --dir \"${SITE:-$OUT}\" --spa" >&2
echo "Blank scenes? -> complete_mirror.py then (if needed) capture_playwright.js" >&2
