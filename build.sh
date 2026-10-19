#!/usr/bin/env bash
# Build bilinear-agent.jar and smoke-test that its premain hook actually runs.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build/classes
javac --release 11 -d build/classes src/BilinearAgent.java
jar cfm bilinear-agent.jar MANIFEST.MF -C build/classes .

echo "built: $(pwd)/bilinear-agent.jar"

if java -javaagent:./bilinear-agent.jar -version 2>&1 | grep -q "\[BilinearAgent\] loaded"; then
  echo "smoke test: OK — premain executed"
else
  echo "smoke test: FAILED — agent did not load" >&2
  exit 1
fi
