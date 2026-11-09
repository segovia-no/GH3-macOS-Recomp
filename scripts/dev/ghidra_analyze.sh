#!/bin/bash
# Redoes the Ghidra analysis committed in manifests/ghidra: for each module
# (default: all four), Ghidra headless with SwARc's export scripts, into
# manifests/ghidra/<module>/{functions,jumptables}.tsv. The Ghidra projects
# stay in build/ghidra, for scripts/dev/ghidra/*.java and for looking around.
# Needs build/input (scripts/setup/prepare_inputs.sh) and
# `brew install ghidra`.
# The committed tables come from Ghidra 12.2 (GHIDRA_VERSION). Another version can
# find other functions: check `git diff manifests/ghidra`, re-lift, redo
# manifests/noentry.manifest (docs/dev/building.md) and play before
# committing new ones.
#   scripts/dev/ghidra_analyze.sh [GH3.exe|msvcr80.dll|msvcp80.dll|fmodex.dll ...]
set -euo pipefail
source "$(dirname "$0")/../setup/common.sh"
GHIDRA_VERSION="12.2"

[ -x "$GHIDRA_HEADLESS" ] || die "no Ghidra at $GHIDRA_HEADLESS (brew install ghidra)"
have="$(brew list --versions ghidra | cut -d' ' -f2)"
[ "$have" = "$GHIDRA_VERSION" ] ||
  echo "warning: Ghidra $have; manifests/ghidra was made with $GHIDRA_VERSION" >&2
mkdir -p "$BUILD/ghidra"
[ $# -gt 0 ] || set -- GH3.exe msvcr80.dll msvcp80.dll fmodex.dll
for m in "$@"; do
  [ -f "$INPUT/$m" ] || die "no $INPUT/$m (run scripts/setup/prepare_inputs.sh)"
  name="$(echo "${m%.*}" | tr '[:upper:]' '[:lower:]')"
  out="$ROOT/manifests/ghidra/$name"
  step "Ghidra: $m"
  mkdir -p "$out"
  JAVA_HOME="$GHIDRA_JAVA" "$GHIDRA_HEADLESS" "$BUILD/ghidra" "$name" -import "$INPUT/$m" -overwrite \
    -scriptPath "$SWARC/tools/ghidra" \
    -postScript ExportFunctions.java "$out/functions.tsv" \
    -postScript ExportJumpTables.java "$out/jumptables.tsv" \
    -analysisTimeoutPerFile 7200 > "$LOGS/ghidra-$name.log" 2>&1 ||
    die "Ghidra failed on $m (see $LOGS/ghidra-$name.log)"
  [ -s "$out/functions.tsv" ] || die "no functions exported for $m (see $LOGS/ghidra-$name.log)"
  echo "$(($(wc -l < "$out/functions.tsv") - 1)) functions"
done
