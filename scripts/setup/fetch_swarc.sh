#!/bin/bash
# Checks out SwARc at the tested commit (SWARC_COMMIT, on the gh3 branch of
# this project's fork) in third_party/SwARc and builds its lifter
# (recomp_lift). A checkout already past that commit (SwARc work in
# progress on the branch) is used as it is.
set -euo pipefail
source "$(dirname "$0")/common.sh"

step "SwARc ($SWARC_COMMIT)"
[ -d "$SWARC/.git" ] || git clone -q --branch "$SWARC_BRANCH" "$SWARC_URL" "$SWARC"
if ! git -C "$SWARC" cat-file -e "$SWARC_COMMIT^{commit}" 2>/dev/null; then
  git -C "$SWARC" fetch -q "$SWARC_URL" "$SWARC_BRANCH"
fi
head="$(git -C "$SWARC" rev-parse HEAD)"
if [ "$head" = "$SWARC_COMMIT" ]; then
  :
elif git -C "$SWARC" merge-base --is-ancestor "$SWARC_COMMIT" HEAD; then
  echo "using $SWARC at $head, ahead of the tested commit"
elif [ -n "$(git -C "$SWARC" status --porcelain --untracked-files=no)" ]; then
  die "$SWARC has local changes and is not at $SWARC_COMMIT: commit them, or delete $SWARC"
else
  git -C "$SWARC" checkout -q "$SWARC_COMMIT"
fi

step "SwARc lifter"
(
  cd "$SWARC"
  cmake --preset release -DRECOMP_LLVM_ROOT="$LLVM_ROOT" > "$LOGS/swarc-configure.log"
  cmake --build --preset release --target recomp_lift > "$LOGS/swarc-build.log"
)
[ -x "$LIFTER" ] || die "no lifter at $LIFTER (see $LOGS/swarc-build.log)"
echo "$LIFTER"
