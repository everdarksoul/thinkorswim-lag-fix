#!/usr/bin/env bash
# Wire the bilinear agent into a thinkorswim installation. Safe to re-run:
# the vmoptions file is backed up, any previous bilinear-agent line is
# replaced, and the current jar is installed fresh.
set -euo pipefail
cd "$(dirname "$0")"

TOS_DIR="${1:-$HOME/thinkorswim}"
VMOPTIONS="$TOS_DIR/thinkorswim.vmoptions"
DEST="$TOS_DIR/agent/bilinear-agent.jar"

if [ ! -f "$VMOPTIONS" ]; then
  echo "error: $VMOPTIONS not found." >&2
  echo "usage: ./install.sh /path/to/thinkorswim   (default: ~/thinkorswim)" >&2
  exit 1
fi

[ -f bilinear-agent.jar ] || ./build.sh

STAMP="$(date +%Y%m%d-%H%M%S)"
cp "$VMOPTIONS" "$VMOPTIONS.bak.$STAMP"
mkdir -p "$TOS_DIR/agent"
cp bilinear-agent.jar "$DEST"

# Drop any older bilinear-agent line (whatever path it pointed at), then
# append the current one exactly once, at the end where TOS keeps extras.
grep -v -- '-javaagent:.*bilinear-agent' "$VMOPTIONS" > "$VMOPTIONS.tmp" || true
mv "$VMOPTIONS.tmp" "$VMOPTIONS"
printf '%s\n' "-javaagent:$DEST" >> "$VMOPTIONS"

echo "installed : $DEST"
echo "configured: $VMOPTIONS"
echo "backup    : $VMOPTIONS.bak.$STAMP"
echo
echo "Fully quit thinkorswim (⌘Q — closing the window is not enough) and reopen."
