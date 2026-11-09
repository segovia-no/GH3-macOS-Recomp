#!/bin/bash
# Builds build/builder/GH3 Builder.app: the SwiftUI front end
# (app/GH3Builder.swift, compiled with the Command Line Tools' swiftc) with
# the kit (make_kit.sh) in Contents/Resources/kit. It holds nothing from the
# game, so it can be shared; the game it builds cannot. Also makes the two
# files a release publishes:
#   build/builder/GH3-Builder-<version>-macOS26-arm64.zip   the app
#   build/builder/GH3-Builder-<version>-sources.tar         the (L)GPL sources
#                                                           its NOTICES.md names
#   make_builder.sh [--no-kit]   (--no-kit: reuse build/builder/kit)
set -euo pipefail
source "$(dirname "$0")/../../scripts/setup/common.sh"
here="$(cd "$(dirname "$0")" && pwd)"
if [ "${1:-}" != "--no-kit" ]; then
  "$here/deps.sh"
  "$here/make_kit.sh"
fi
kit="$BUILD/builder/kit"
[ -f "$kit/build_game.sh" ] || die "no kit at $kit (run make_kit.sh)"

app="$BUILD/builder/GH3 Builder.app"
step "$app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
xcrun swiftc -O -parse-as-library -swift-version 5 -target arm64-apple-macos26 \
  "$here/app/GH3Builder.swift" -o "$app/Contents/MacOS/GH3Builder"
cp -R "$kit" "$app/Contents/Resources/kit"
source "$kit/config.sh"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>GH3Builder</string>
  <key>CFBundleIdentifier</key><string>local.gh3-macos-recomp.builder</string>
  <key>CFBundleName</key><string>GH3 Builder</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force -s - "$app"
codesign --verify --strict "$app"
echo "$app ($(du -sh "$app" | cut -f1))"

zip="$BUILD/builder/GH3-Builder-$VERSION-macOS26-arm64.zip"
srctar="$BUILD/builder/GH3-Builder-$VERSION-sources.tar"
rm -f "$BUILD"/builder/GH3-Builder-*.zip "$BUILD"/builder/GH3-Builder-*-sources.tar
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
tar -cf "$srctar" -C "$BUILD/builder" sources -C "$kit/licenses" NOTICES.md
echo "$zip ($(du -h "$zip" | cut -f1))"
echo "$srctar ($(du -h "$srctar" | cut -f1))"
