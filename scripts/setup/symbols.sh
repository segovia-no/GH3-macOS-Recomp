#!/bin/bash
# The lifter's inputs for each module (build/symbols/<module>):
# - pe_info.txt, imports.tsv, exports.tsv: SwARc's tools/pe_symbols.py;
# - functions.tsv, jumptables.tsv: Ghidra's analysis of the module,
#   committed in manifests/ghidra/<module> (addresses only), so a build
#   needs no Ghidra and lifts the same code everywhere.
#   scripts/dev/ghidra_analyze.sh redoes it.
set -euo pipefail
source "$(dirname "$0")/common.sh"

for m in GH3.exe msvcr80.dll msvcp80.dll fmodex.dll; do
  name="$(echo "${m%.*}" | tr '[:upper:]' '[:lower:]')"
  out="$SYMBOLS/$name"
  step "symbols $m"
  mkdir -p "$out"
  PATH="$LLVM_ROOT/bin:$PATH" python3 -I "$SWARC/tools/pe_symbols.py" "$INPUT/$m" --out "$out" \
    > "$LOGS/pe_symbols-$name.log" 2>&1 || die "pe_symbols.py failed on $m (see $LOGS/pe_symbols-$name.log)"
  cp "$ROOT/manifests/ghidra/$name/functions.tsv" "$ROOT/manifests/ghidra/$name/jumptables.tsv" "$out/"
  echo "$(($(wc -l < "$out/functions.tsv") - 1)) functions"
done
