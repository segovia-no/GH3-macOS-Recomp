#!/bin/bash
# Gathers the binaries that are lifted into build/input, and makes the game
# folder the build runs (build/gamedir):
# - GH3.exe from your install (checked against the SHA-256 the manifests
#   were made for);
# - fmodex.dll from your install, UPX-unpacked;
# - msvcr80.dll and msvcp80.dll (8.0.50727.6195) from Microsoft's VC++ 2005
#   SP1 redistributable, downloaded from Microsoft and extracted here.
# None of these are redistributed: they stay in build/ (gitignored).
set -euo pipefail
source "$(dirname "$0")/common.sh"

[ -f "$GAME/GH3.exe" ] || die "no GH3.exe in $GAME (set GH3_GAME_DIR to your Guitar Hero III folder)"
mkdir -p "$INPUT"

step "GH3.exe"
check_sha "$GAME/GH3.exe" "$GH3_EXE_SHA256" "GH3.exe (this build needs the GH3.exe it was made for, see docs/README.md)"
cp "$GAME/GH3.exe" "$INPUT/GH3.exe"

step "fmodex.dll (UPX-unpacked)"
check_sha "$GAME/fmodex.dll" "$FMODEX_PACKED_SHA256" "fmodex.dll"
rm -f "$INPUT/fmodex.dll"
upx -q -d "$GAME/fmodex.dll" -o "$INPUT/fmodex.dll" > /dev/null
check_sha "$INPUT/fmodex.dll" "$FMODEX_SHA256" "unpacked fmodex.dll"

step "VC++ 2005 SP1 CRT (msvcr80.dll, msvcp80.dll)"
if [ "$(sha256 "$INPUT/msvcr80.dll" 2>/dev/null)" != "$MSVCR80_SHA256" ] ||
   [ "$(sha256 "$INPUT/msvcp80.dll" 2>/dev/null)" != "$MSVCP80_SHA256" ]; then
  dl="$BUILD/download"
  rm -rf "$dl" && mkdir -p "$dl"
  curl -sSLf -o "$dl/vcredist_x86.exe" "$VCREDIST_URL"
  check_sha "$dl/vcredist_x86.exe" "$VCREDIST_SHA256" "vcredist_x86.exe"
  # exe -> vcredist.msi -> the CRT merge module -> the DLLs.
  7zz x -y -o"$dl/exe" "$dl/vcredist_x86.exe" > /dev/null
  7zz x -y -o"$dl/msi" "$dl/exe/vcredist.msi" > /dev/null
  7zz x -y -o"$dl/msm" "$dl/msi/_14241_Microsoft_VC80_CRT_x86.msm" > /dev/null
  cp "$dl"/msm/msvcr80.dll.8.0.50727.6195.* "$INPUT/msvcr80.dll"
  cp "$dl"/msm/msvcp80.dll.8.0.50727.6195.* "$INPUT/msvcp80.dll"
  rm -rf "$dl"
fi
check_sha "$INPUT/msvcr80.dll" "$MSVCR80_SHA256" "msvcr80.dll"
check_sha "$INPUT/msvcp80.dll" "$MSVCP80_SHA256" "msvcp80.dll"

step "build/gamedir"
# Every entry of the install linked in; the runtime's own files (the lifted
# DLLs, a private GH3.exe) copied over them; PLUGINS empty, since the GH3+
# plugin loader is replaced (src/plugins.cpp).
rm -rf "$GAMEDIR" && mkdir -p "$GAMEDIR"
for entry in "$GAME"/*; do ln -s "$entry" "$GAMEDIR/$(basename "$entry")"; done
for f in GH3.exe fmodex.dll msvcr80.dll msvcp80.dll; do
  rm -f "$GAMEDIR/$f"
  cp "$INPUT/$f" "$GAMEDIR/$f"
done
rm -rf "$GAMEDIR/PLUGINS" && mkdir "$GAMEDIR/PLUGINS"
echo "$GAMEDIR"
