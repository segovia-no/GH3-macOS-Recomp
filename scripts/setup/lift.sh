#!/bin/bash
# Lifts GH3.exe and the DLLs it imports (the CRT, FMOD Ex) to C++ in
# build/generated, with the manifests in manifests/.
# GH3.exe is lifted with --no-x87-doubles: its float code runs at PC=24,
# where the host-double path is never taken, and without it clang builds
# even the Havok solver's 12k-instruction functions at -O2.
set -euo pipefail
source "$(dirname "$0")/common.sh"

[ -x "$LIFTER" ] || die "no lifter at $LIFTER (run scripts/setup/fetch_swarc.sh)"
step "lift"
cd "$INPUT"
new="$BUILD/generated.new"
out="$BUILD/generated"
rm -rf "$new"
"$LIFTER" \
  --exe GH3.exe --symbols "$SYMBOLS/gh3" --manifest "$ROOT/manifests/lifter.manifest" --no-x87-doubles \
  --module msvcr80.dll --symbols "$SYMBOLS/msvcr80" \
  --module msvcp80.dll --symbols "$SYMBOLS/msvcp80" \
  --module fmodex.dll --symbols "$SYMBOLS/fmodex" --manifest "$ROOT/manifests/fmodex.manifest" \
  --out "$new" > "$LOGS/lift.log" 2>&1 || die "lift failed (see $LOGS/lift.log)"
tail -3 "$LOGS/lift.log"

# Only files whose content changed replace the old ones, so a rerun does
# not recompile all of the lifted code.
mkdir -p "$out"
for f in "$out"/*; do  # files the lifter no longer writes
  if [ -e "$f" ] && [ ! -e "$new/$(basename "$f")" ]; then rm -f "$f"; fi
done
changed=0
for f in "$new"/*; do
  name="$(basename "$f")"
  cmp -s "$f" "$out/$name" || { mv "$f" "$out/$name"; changed=$((changed + 1)); }
done
rm -rf "$new"
echo "$changed generated files changed"
