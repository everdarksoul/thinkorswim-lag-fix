#!/usr/bin/env bash
# Remove the bilinear agent from a thinkorswim installation: the -javaagent
# line and the jar. Backups made by install.sh are left untouched.
set -euo pipefail
cd "$(dirname "$0")"

TOS_DIR="${1:-$HOME/thinkorswim}"
VMOPTIONS="$TOS_DIR/thinkorswim.vmoptions"

if [ ! -f "$VMOPTIONS" ]; then
  echo "error: $VMOPTIONS not found." >&2
  echo "usage: ./uninstall.sh /path/to/thinkorswim   (default: ~/thinkorswim)" >&2
  exit 1
fi

grep -v -- '-javaagent:.*bilinear-agent' "$VMOPTIONS" > "$VMOPTIONS.tmp" || true
mv "$VMOPTIONS.tmp" "$VMOPTIONS"
rm -f "$TOS_DIR/agent/bilinear-agent.jar"

echo "removed -javaagent line from $VMOPTIONS"
echo "removed $TOS_DIR/agent/bilinear-agent.jar"
echo
echo "Fully quit thinkorswim (⌘Q) and reopen to return to stock rendering."
