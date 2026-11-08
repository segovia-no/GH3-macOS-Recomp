#!/bin/bash
# Checks out SwARc at the tested commit in third_party/SwARc, applies
# patches/swarc-gh3.patch and builds its lifter (recomp_lift).
set -euo pipefail
source "$(dirname "$0")/common.sh"

step "SwARc ($SWARC_COMMIT)"
if [ ! -d "$SWARC/.git" ]; then
  git clone -q "$SWARC_URL" "$SWARC"
  git -C "$SWARC" checkout -q "$SWARC_COMMIT"
fi
if git -C "$SWARC" apply --check "$ROOT/patches/swarc-gh3.patch" 2>/dev/null; then
  git -C "$SWARC" apply --index "$ROOT/patches/swarc-gh3.patch"
  echo "applied patches/swarc-gh3.patch"
elif git -C "$SWARC" apply --check -R "$ROOT/patches/swarc-gh3.patch" 2>/dev/null; then
  echo "patches/swarc-gh3.patch already applied"
else
  die "patches/swarc-gh3.patch does not apply to $SWARC (local changes there?)"
fi

step "SwARc lifter"
(
  cd "$SWARC"
  cmake --preset release -DRECOMP_LLVM_ROOT="$LLVM_ROOT" > "$LOGS/swarc-configure.log"
  cmake --build --preset release --target recomp_lift > "$LOGS/swarc-build.log"
)
[ -x "$LIFTER" ] || die "no lifter at $LIFTER (see $LOGS/swarc-build.log)"
echo "$LIFTER"
