#!/bin/bash
# Builds Guitar Hero III.app from your own copy of the game, with the
# builder kit this script sits in (packaging/builder/make_kit.sh) and the
# Xcode Command Line Tools. Needs nothing else: no Homebrew, no CMake.
#   build_game.sh <Guitar Hero III folder> <output folder> [--embed-game]
# Work files: $GH3_WORK (default ~/Library/Caches/GH3-macOS-Recomp). A rerun
# reuses what is still valid. Progress lines for the builder app:
#   @@step <n>/<total> <title>
#   @@progress <done>/<total>
set -euo pipefail
kit="$(cd "$(dirname "$0")" && pwd)"

# One lifted file, for the parallel compile below (xargs runs this script).
if [ "${1:-}" = "--cc" ]; then
  o="$GH3_OBJ/$(basename "${2%.cpp}").o"
  # shellcheck disable=SC2086
  if "$GH3_CXX" $GH3_CXXFLAGS -I"$kit/include" -c "$2" -o "$o.tmp" 2> "$o.log"; then
    mv "$o.tmp" "$o" && rm -f "$o.log" && echo ok
  else
    cat "$o.log" >&2
    exit 255  # stops xargs
  fi
  exit 0
fi

[ $# -ge 2 ] || { echo "usage: $0 <Guitar Hero III folder> <output folder> [--embed-game]" >&2; exit 2; }
game="$(cd "$1" && pwd)"
mkdir -p "$2"
out="$(cd "$2" && pwd)"
embed=0
[ "${3:-}" = "--embed-game" ] && embed=1
work="${GH3_WORK:-$HOME/Library/Caches/GH3-macOS-Recomp}"
export PATH="$kit/bin:/usr/bin:/bin:/usr/sbin:/sbin"
source "$kit/config.sh"

total=6
step() { echo "@@step $1/$total $2"; }
die() { echo "error: $*" >&2; exit 1; }
sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }
check_sha() {
  local got
  got="$(sha256 "$1")"
  [ "$got" = "$2" ] || die "$3: unexpected SHA-256 $got (expected $2)"
}

step 1 "Checking the tools"
GH3_CXX="$(xcrun --find clang++ 2>/dev/null)" ||
  die "the Xcode Command Line Tools are not installed (xcode-select --install)"
# The compiler run directly (not through /usr/bin's shims) needs the SDK.
SDKROOT="$(xcrun --show-sdk-path)" || die "no macOS SDK in the Command Line Tools"
export SDKROOT
command -v python3 > /dev/null && python3 -c '' 2>/dev/null ||
  die "python3 is missing (it comes with the Xcode Command Line Tools)"
[ -f "$game/GH3.exe" ] || die "no GH3.exe in $game"
mkdir -p "$work"/{input,runtime,symbols,obj}

step 2 "Preparing GH3.exe, FMOD and the Visual C++ runtime"
in="$work/input"
check_sha "$game/GH3.exe" "$GH3_EXE_SHA256" "GH3.exe (this build needs the GH3.exe it was made for)"
cp "$game/GH3.exe" "$in/GH3.exe"
check_sha "$game/fmodex.dll" "$FMODEX_PACKED_SHA256" "fmodex.dll"
if [ "$(sha256 "$in/fmodex.dll" 2>/dev/null)" != "$FMODEX_SHA256" ]; then
  rm -f "$in/fmodex.dll"
  upx -q -d "$game/fmodex.dll" -o "$in/fmodex.dll" > /dev/null
fi
check_sha "$in/fmodex.dll" "$FMODEX_SHA256" "unpacked fmodex.dll"
if [ "$(sha256 "$in/msvcr80.dll" 2>/dev/null)" != "$MSVCR80_SHA256" ] ||
   [ "$(sha256 "$in/msvcp80.dll" 2>/dev/null)" != "$MSVCP80_SHA256" ]; then
  dl="$work/download"
  rm -rf "$dl" && mkdir -p "$dl"
  echo "downloading Microsoft's Visual C++ 2005 SP1 redistributable"
  curl -sSLf -o "$dl/vcredist_x86.exe" "$VCREDIST_URL"
  check_sha "$dl/vcredist_x86.exe" "$VCREDIST_SHA256" "vcredist_x86.exe"
  7zz x -y -o"$dl/exe" "$dl/vcredist_x86.exe" > /dev/null
  7zz x -y -o"$dl/msi" "$dl/exe/vcredist.msi" > /dev/null
  7zz x -y -o"$dl/msm" "$dl/msi/_14241_Microsoft_VC80_CRT_x86.msm" > /dev/null
  cp "$dl"/msm/msvcr80.dll.8.0.50727.6195.* "$in/msvcr80.dll"
  cp "$dl"/msm/msvcp80.dll.8.0.50727.6195.* "$in/msvcp80.dll"
  rm -rf "$dl"
fi
check_sha "$in/msvcr80.dll" "$MSVCR80_SHA256" "msvcr80.dll"
check_sha "$in/msvcp80.dll" "$MSVCP80_SHA256" "msvcp80.dll"

step 3 "Reading the modules' imports and exports"
for m in GH3.exe msvcr80.dll msvcp80.dll fmodex.dll; do
  name="$(echo "${m%.*}" | tr '[:upper:]' '[:lower:]')"
  mkdir -p "$work/symbols/$name"
  python3 -I "$kit/tools/pe_symbols.py" "$in/$m" --out "$work/symbols/$name" > /dev/null
  cp "$kit/manifests/ghidra/$name/functions.tsv" "$kit/manifests/ghidra/$name/jumptables.tsv" \
    "$work/symbols/$name/"
done

step 4 "Translating the game's code to C++"
new="$work/generated.new"
gen="$work/generated"
rm -rf "$new"
(
  cd "$in"
  recomp_lift \
    --exe GH3.exe --symbols "$work/symbols/gh3" --manifest "$kit/manifests/lifter.manifest" --no-x87-doubles \
    --module msvcr80.dll --symbols "$work/symbols/msvcr80" \
    --module msvcp80.dll --symbols "$work/symbols/msvcp80" \
    --module fmodex.dll --symbols "$work/symbols/fmodex" --manifest "$kit/manifests/fmodex.manifest" \
    --out "$new" > "$work/lift.log" 2>&1
) || die "the translation failed (see $work/lift.log)"
mkdir -p "$gen"
for f in "$gen"/*; do  # files the lifter no longer writes
  if [ -e "$f" ] && [ ! -e "$new/$(basename "$f")" ]; then rm -f "$f"; fi
done
for f in "$new"/*; do  # only changed files replace the old ones
  cmp -s "$f" "$gen/$(basename "$f")" || mv "$f" "$gen/$(basename "$f")"
done
rm -rf "$new"

step 5 "Compiling (the long step)"
export GH3_CXX GH3_OBJ="$work/obj" GH3_CXXFLAGS
GH3_CXXFLAGS="$(cat "$kit/cxxflags")"
todo=()
for src in "$gen"/*.cpp; do
  o="$work/obj/$(basename "${src%.cpp}").o"
  [ "$o" -nt "$src" ] || todo+=("$src")
done
n=${#todo[@]}
if [ "$n" -gt 0 ]; then
  done_=0
  echo "@@progress 0/$n"
  printf '%s\0' "${todo[@]}" | xargs -0 -n 1 -P "$(sysctl -n hw.ncpu)" "$0" --cc |
    while read -r _; do done_=$((done_ + 1)); echo "@@progress $done_/$n"; done ||
    die "compiling failed (errors above)"
fi
for o in "$work"/obj/*.o; do  # objects of files the lifter no longer writes
  [ -e "$gen/$(basename "${o%.o}").cpp" ] || rm -f "$o"
done

step 6 "Linking and packaging the app"
libs=()
while read -r l; do libs+=("$kit/Frameworks/$l"); done < "$kit/link"
"$GH3_CXX" -arch arm64 -Wl,-headerpad_max_install_names "$work"/obj/*.o "$kit"/native/*.o \
  "${libs[@]}" -Wl,-rpath,@executable_path/../Frameworks -o "$work/gh3"

app="$out/Guitar Hero III.app"
contents="$app/Contents"
rm -rf "$app"
mkdir -p "$contents/MacOS" "$contents/Resources"
cp "$work/gh3" "$contents/MacOS/gh3"
cp -R "$kit/Frameworks" "$contents/Frameworks"

# The runtime's own files in the game folder: the original GH3.exe, the
# unpacked FMOD, the lifted CRT DLLs, and an empty PLUGINS (src/plugins.cpp).
rt="$work/runtime"
rm -rf "$rt" && mkdir -p "$rt/PLUGINS"
cp "$in"/{GH3.exe,fmodex.dll,msvcr80.dll,msvcp80.dll} "$rt/"
if [ "$embed" = 1 ]; then
  gdir="$contents/Resources/game"
else
  gdir="$HOME/Library/Application Support/gh3/game"
  rm -rf "$gdir"
fi
mkdir -p "$gdir"
for entry in "$game"/*; do
  [ -e "$entry" ] || continue
  name="$(basename "$entry")"
  if [ -e "$rt/$name" ]; then
    cp -R "$rt/$name" "$gdir/$name"
  elif [ "$embed" = 1 ]; then
    cp -cR "$entry" "$gdir/$name" 2>/dev/null || cp -R "$entry" "$gdir/$name"
  else
    ln -s "$entry" "$gdir/$name"
  fi
done
for entry in "$rt"/*; do
  [ -e "$gdir/$(basename "$entry")" ] || cp -R "$entry" "$gdir/"
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
python3 -I "$kit/tools/exe_icon.py" "$game/GH3.exe" "$tmp/gh3.ico" > /dev/null
sips -s format png "$tmp/gh3.ico" --out "$tmp/gh3.png" > /dev/null
mkdir "$tmp/gh3.iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s "$tmp/gh3.png" --out "$tmp/gh3.iconset/icon_${s}x${s}.png" > /dev/null
  sips -z $((s * 2)) $((s * 2)) "$tmp/gh3.png" --out "$tmp/gh3.iconset/icon_${s}x${s}@2x.png" > /dev/null
done
iconutil -c icns "$tmp/gh3.iconset" -o "$contents/Resources/gh3.icns"

cat > "$contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>gh3</string>
  <key>CFBundleIdentifier</key><string>local.gh3-macos-recomp.app</string>
  <key>CFBundleName</key><string>Guitar Hero III</string>
  <key>CFBundleDisplayName</key><string>Guitar Hero III</string>
  <key>CFBundleIconFile</key><string>gh3</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.music-games</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force -s - "$contents/Frameworks/"*.dylib 2>/dev/null
codesign --force -s - "$app" 2>/dev/null
codesign --verify --strict "$app"
echo "@@done $app"
