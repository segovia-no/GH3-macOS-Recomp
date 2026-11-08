#!/bin/bash
# GH3-macOS-Recomp: builds Guitar Hero III (PC) for macOS from your own copy
# of the game, from scratch to build/Guitar Hero III.app:
#   1. checks the tools (Homebrew packages)
#   2. SwARc: checkout, patch, lifter        scripts/setup/fetch_swarc.sh
#   3. inputs: GH3.exe, fmodex.dll, the CRT  scripts/setup/prepare_inputs.sh
#   4. analysis (Ghidra)                     scripts/setup/analyze.sh
#   5. lift to C++                           scripts/setup/lift.sh
#   6. build                                 scripts/setup/build.sh
#   7. app bundle                            packaging/macos/make_app.sh
# Every step can be rerun on its own. Usage:
#   ./setup.sh [--game <Guitar Hero III folder>] [--embed-game]
# The game folder defaults to "Guitar Hero III" next to this file. See
# docs/guides/install.md.
set -euo pipefail
cd "$(dirname "$0")"
app_args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --game) export GH3_GAME_DIR="$(cd "$2" && pwd)"; shift 2 ;;
    --embed-game) app_args+=(--embed-game); shift ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "unknown option $1 (see --help)" >&2; exit 2 ;;
  esac
done
source scripts/setup/common.sh

step "tools"
[ "$(uname -s)-$(uname -m)" = "Darwin-arm64" ] || die "macOS on Apple Silicon only"
command -v brew > /dev/null || die "Homebrew is needed: https://brew.sh"
missing=()
for f in cmake ninja sdl3 ffmpeg llvm@22 glslang spirv-cross ghidra sevenzip upx libusb; do
  brew list --versions "$f" > /dev/null 2>&1 || missing+=("$f")
done
if [ ${#missing[@]} -gt 0 ]; then
  echo "installing: ${missing[*]}"
  brew install "${missing[@]}"
fi
command -v xcrun > /dev/null || die "Xcode Command Line Tools are needed: xcode-select --install"

scripts/setup/fetch_swarc.sh
scripts/setup/prepare_inputs.sh
scripts/setup/analyze.sh
scripts/setup/lift.sh
scripts/setup/build.sh
packaging/macos/make_app.sh ${app_args[@]+"${app_args[@]}"}
step "done: open \"$BUILD/Guitar Hero III.app\""
