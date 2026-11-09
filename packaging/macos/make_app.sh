#!/bin/bash
# Builds a double-clickable build/Guitar Hero III.app from the current build:
#   Contents/MacOS/gh3          the recompiled game
#   Contents/Frameworks/        SwARc's libraries and their Homebrew deps
#                               (SDL3, ffmpeg, libusb, ...), relinked to the
#                               bundle (bundle_dylibs.py)
#   Contents/Resources/gh3.icns from GH3.exe's icon
# and the game folder the app runs, ~/Library/Application Support/gh3/game:
# each entry of "Guitar Hero III/" linked in, plus the runtime's own files
# from build/gamedir (the lifted CRT DLLs, the unpacked fmodex.dll). Links
# out of a bundle would break its signature, so they live there.
# Options:
#   --embed-game   copy the game folder into the bundle instead
#                  (Contents/Resources/game; APFS clones, so no extra disk
#                  space on the same volume). The app then works without
#                  this repository, but songs added to "Guitar Hero III/"
#                  later do not show up in it.
# Environment: GH3_GAME_DIR (default: <repo>/Guitar Hero III).
# Log of a run: ~/Library/Logs/Guitar Hero III.log. Settings and saves stay
# in ~/Library/Application Support/gh3.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
build="${GH3_BUILD_DIR:-$root/build}"
src="${GH3_GAME_DIR:-$root/Guitar Hero III}"
app="$build/Guitar Hero III.app"
embed=0
for a in "$@"; do
  case "$a" in
    --embed-game) embed=1 ;;
    *) echo "usage: $0 [--embed-game]" >&2; exit 2 ;;
  esac
done
[ -f "$src/GH3.exe" ] || { echo "make_app: no GH3.exe in $src" >&2; exit 1; }

cmake --build "$build/cmake" --target gh3

rm -rf "$app"
contents="$app/Contents"
mkdir -p "$contents/MacOS" "$contents/Frameworks" "$contents/Resources"
cp "$build/cmake/gh3" "$contents/MacOS/gh3"
python3 -I "$here/bundle_dylibs.py" "$contents/MacOS/gh3" "$(brew --prefix)/lib"

# The game folder; entries that build/gamedir holds as real files (not links
# into the game folder) are the runtime's and win.
if [ "$embed" = 1 ]; then
  game="$contents/Resources/game"
else
  game="$HOME/Library/Application Support/gh3/game"
  rm -rf "$game"
fi
mkdir -p "$game"
for entry in "$src"/*; do
  [ -e "$entry" ] || continue
  name="$(basename "$entry")"
  if [ -e "$build/gamedir/$name" ] && [ ! -L "$build/gamedir/$name" ]; then
    cp -R "$build/gamedir/$name" "$game/$name"
  elif [ "$embed" = 1 ]; then
    cp -cR "$entry" "$game/$name" 2>/dev/null || cp -R "$entry" "$game/$name"
  else
    ln -s "$entry" "$game/$name"
  fi
done
for entry in "$build/gamedir"/*; do  # runtime files the game folder lacks
  name="$(basename "$entry")"
  [ -L "$entry" ] || [ -e "$game/$name" ] || cp -R "$entry" "$game/$name"
done

# Icon: the exe's largest (48x48), scaled into an iconset.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
python3 -I "$here/exe_icon.py" "$src/GH3.exe" "$tmp/gh3.ico"
sips -s format png "$tmp/gh3.ico" --out "$tmp/gh3.png" >/dev/null
mkdir "$tmp/gh3.iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s "$tmp/gh3.png" --out "$tmp/gh3.iconset/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d "$tmp/gh3.png" --out "$tmp/gh3.iconset/icon_${s}x${s}@2x.png" >/dev/null
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
  <key>CFBundleShortVersionString</key><string>$(git -C "$root" describe --tags --always | sed 's/^v//')</string>
  <key>CFBundleVersion</key><string>$(git -C "$root" rev-list --count HEAD)</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.music-games</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad hoc signatures: relinking invalidated the libraries' own.
codesign --force -s - "$contents/Frameworks/"*.dylib 2>/dev/null
codesign --force -s - "$app" 2>/dev/null
codesign --verify --strict "$app"
echo "make_app: $app ($(du -sh "$app" | cut -f1), game $([ $embed = 1 ] && echo embedded || echo linked))"
