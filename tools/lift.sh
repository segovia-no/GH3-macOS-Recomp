#!/bin/sh
# Lift GH3.exe and the DLLs it imports into work/generated.
cd "$(dirname "$0")/../work" || exit 1
../ref/SwARc/out/build/release/tools/lifter_x86/recomp_lift \
  --exe GH3.exe --symbols symbols --manifest ../recomp/lifter.manifest --no-x87-doubles \
  --module crt/msvcr80.dll --symbols symbols_msvcr80 \
  --module crt/msvcp80.dll --symbols symbols_msvcp80 \
  --module fmod/fmodex.dll --symbols symbols_fmodex --manifest ../recomp/fmodex.manifest \
  --out generated > lift.log 2>&1
status=$?
tail -3 lift.log
exit $status
