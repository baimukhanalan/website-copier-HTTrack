#!/usr/bin/env bash
# install.sh — make the scripts runnable and (optionally) install as a Claude skill.
#
#   ./install.sh            # chmod scripts, print how to use
#   ./install.sh --skill    # also symlink into ~/.claude/skills/httrack-site-mirror
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

chmod +x "$HERE"/scripts/*.sh "$HERE"/scripts/*.py "$HERE"/scripts/*.js 2>/dev/null || true
echo "Scripts are executable."

if [ "${1:-}" = "--skill" ]; then
  DST="$HOME/.claude/skills/httrack-site-mirror"
  mkdir -p "$HOME/.claude/skills"
  rm -rf "$DST"
  ln -s "$HERE" "$DST"
  echo "Linked as Claude skill: $DST -> $HERE"
  echo "Restart Claude Code; the 'httrack-site-mirror' skill will be available."
fi

cat <<EOF

Quick start:
  $HERE/scripts/grab.sh https://example.com --serve

Requires: httrack + python3 (always), node+playwright only for --capture.
  macOS:  brew install httrack
  Linux:  sudo apt install httrack   (or dnf/pacman)
EOF
