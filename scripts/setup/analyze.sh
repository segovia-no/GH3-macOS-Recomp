#!/bin/bash
# The lifter's inputs for each module (build/symbols/<module>):
# - pe_info.txt, imports.tsv, exports.tsv: SwARc's tools/pe_symbols.py;
# - functions.tsv, jumptables.tsv: Ghidra's headless analysis with SwARc's
#   export scripts (a few minutes for GH3.exe, seconds for the DLLs).
# A module whose functions.tsv exists is skipped (delete it to redo).
set -euo pipefail
source "$(dirname "$0")/common.sh"

[ -x "$GHIDRA_HEADLESS" ] || die "no Ghidra at $GHIDRA_HEADLESS (brew install ghidra)"
mkdir -p "$BUILD/ghidra"

for m in GH3.exe msvcr80.dll msvcp80.dll fmodex.dll; do
  name="$(echo "${m%.*}" | tr '[:upper:]' '[:lower:]')"
  out="$SYMBOLS/$name"
  [ -s "$out/functions.tsv" ] && { echo "$m: done"; continue; }
  step "analyze $m"
  mkdir -p "$out"
  PATH="$LLVM_ROOT/bin:$PATH" python3 -I "$SWARC/tools/pe_symbols.py" "$INPUT/$m" --out "$out" \
    > "$LOGS/pe_symbols-$name.log" 2>&1
  JAVA_HOME="$GHIDRA_JAVA" "$GHIDRA_HEADLESS" "$BUILD/ghidra" "$name" -import "$INPUT/$m" -overwrite \
    -scriptPath "$SWARC/tools/ghidra" \
    -postScript ExportFunctions.java "$out/functions.tsv" \
    -postScript ExportJumpTables.java "$out/jumptables.tsv" \
    -analysisTimeoutPerFile 7200 > "$LOGS/ghidra-$name.log" 2>&1 ||
    die "Ghidra failed on $m (see $LOGS/ghidra-$name.log)"
  [ -s "$out/functions.tsv" ] || die "no functions exported for $m (see $LOGS/ghidra-$name.log)"
  echo "$(wc -l < "$out/functions.tsv") functions"
done
