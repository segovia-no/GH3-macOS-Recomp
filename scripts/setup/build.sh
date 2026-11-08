#!/bin/bash
# Configures and builds the game (CMakeLists.txt) into build/cmake: the
# lifted code in build/generated, the native code in src/ and SwARc's
# runtime. The first build compiles about 150 large generated files.
set -euo pipefail
source "$(dirname "$0")/common.sh"

[ -d "$BUILD/generated" ] || die "no build/generated (run scripts/setup/lift.sh)"
step "configure"
cmake -S "$ROOT" -B "$CMAKE_BUILD" -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DRECOMP_LLVM_ROOT="$LLVM_ROOT" -DSWARC_DIR="$SWARC" -DGH3_GENERATED_DIR="$BUILD/generated" \
  > "$LOGS/configure.log" || die "configure failed (see $LOGS/configure.log)"
step "build (logs/build.log)"
cmake --build "$CMAKE_BUILD" --target gh3 > "$LOGS/build.log" 2>&1 ||
  { grep -m5 'error:' "$LOGS/build.log" >&2; die "build failed (see $LOGS/build.log)"; }
echo "$CMAKE_BUILD/gh3"
