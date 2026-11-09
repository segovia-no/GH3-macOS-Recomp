# Shared paths and helpers for the setup scripts (sourced, not run).
# Everything generated goes under build/ (GH3_BUILD_DIR); SwARc is checked
# out in third_party/SwARc (SWARC_DIR); the game install is read from
# "Guitar Hero III/" next to this repository (GH3_GAME_DIR).

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD="${GH3_BUILD_DIR:-$ROOT/build}"
GAME="${GH3_GAME_DIR:-$ROOT/Guitar Hero III}"
SWARC="${SWARC_DIR:-$ROOT/third_party/SwARc}"
# SwARc: this project's fork of JTM-rootstorm/SwARc. Its gh3 branch is
# upstream plus the generic changes this port needs (docs/dev/architecture.md).
SWARC_URL="https://github.com/segovia-no/SwARc.git"
SWARC_BRANCH="gh3"
SWARC_COMMIT="4a7ec399886952f90a643a75c8ecde42deeba6ca"

INPUT="$BUILD/input"      # GH3.exe and the DLLs that are lifted with it
SYMBOLS="$BUILD/symbols"  # per module: pe_symbols.py output, manifests/ghidra tables
LOGS="$BUILD/logs"
GAMEDIR="$BUILD/gamedir"  # the game folder the build runs (links + runtime files)
CMAKE_BUILD="$BUILD/cmake"

# The files the manifests and native code were made for (addresses in
# manifests/ and src/ are specific to them).
GH3_EXE_SHA256="4322a71ddda6c3c971ae2162bdc62299e4cf0c0bc6f6ee9032bcfdccb8e5e804"
FMODEX_PACKED_SHA256="6340182911e7213ddcc26372b38dc4aaf1d91c722dd42e64336987dd24beafbb"
FMODEX_SHA256="843acf46b53a9b6735a66f31ca9b0d7ccb02ffd0b9c6a0b60ffb2a8908370d59"
# Microsoft Visual C++ 2005 SP1 redistributable (x86), MFC security update.
VCREDIST_URL="https://download.microsoft.com/download/8/B/4/8B42259F-5D70-43F4-AC2E-4B208FD8D66A/vcredist_x86.EXE"
VCREDIST_SHA256="8648c5fc29c44b9112fe52f9a33f80e7fc42d10f3b5b42b2121542a13e44adfd"
MSVCR80_SHA256="c3ac989c8489a23bb96400b1856f5325ffc67e844f04651ea5d61bc20a991c6d"
MSVCP80_SHA256="372af797353f9335915cd06d4076bab8410775dcaf2dac0593197d7c41bbffb2"

BREW="$(brew --prefix 2>/dev/null || echo /opt/homebrew)"
LLVM_ROOT="$BREW/opt/llvm@22"
# Ghidra: only for scripts/dev (the build uses manifests/ghidra).
GHIDRA_JAVA="$BREW/opt/openjdk@25"
GHIDRA_HEADLESS="$BREW/opt/ghidra/libexec/support/analyzeHeadless"
LIFTER="$SWARC/out/build/release/tools/lifter_x86/recomp_lift"

step() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }

# check_sha <file> <expected> <what>
check_sha() {
  local got
  got="$(sha256 "$1")"
  [ "$got" = "$2" ] || die "$3: unexpected SHA-256 $got (expected $2)"
}

mkdir -p "$BUILD" "$LOGS"
