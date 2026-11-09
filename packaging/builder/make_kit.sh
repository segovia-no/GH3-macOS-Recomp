#!/bin/bash
# Assembles the builder kit (build/builder/kit) after a developer build
# (./setup.sh) and deps.sh: everything a Mac needs to build the game from
# the player's own copy with only the Xcode Command Line Tools (Apple
# clang), no Homebrew and no LLVM install. Nothing in it comes from the game:
#   bin/          SwARc's lifter, llvm-undname (undname.cpp), upx, 7zz
#   Frameworks/   SwARc's runtime and the libraries it uses (SDL3, libusb,
#                 glslang, the LGPL FFmpeg from deps.sh), relinked to @rpath
#                 (bundle_dylibs.py)
#   include/      SwARc's headers, for the lifted code
#   native/       this project's src/ and SwARc's lifted_table.cpp as objects
#   manifests/    the lifter's manifests and the Ghidra tables
#   tools/        pe_symbols.py, exe_icon.py
#   licenses/     NOTICES.md and every component's license
#   cxxflags, link, config.sh   how the lifted code is compiled and linked
#   build_game.sh the build the builder app runs (kit/build_game.sh)
# SwARc's runtime and src/ are built again for the kit (build/builder/cmake)
# against the LGPL FFmpeg: FFmpeg's libavformat re-exports a set of
# libavcodec/libavutil symbols that depends on its configuration, so
# libraries linked against Homebrew's build do not load with another.
set -euo pipefail
source "$(dirname "$0")/../../scripts/setup/common.sh"
here="$(cd "$(dirname "$0")" && pwd)"
kit="$BUILD/builder/kit"
kb="$BUILD/builder/cmake"
ff="$BUILD/builder/deps/ffmpeg"
srcs="$BUILD/builder/sources"
[ -d "$BUILD/generated" ] || die "no $BUILD/generated (run ./setup.sh first)"
[ -f "$ff/lib/libavcodec.dylib" ] || die "no LGPL FFmpeg in $ff (run packaging/builder/deps.sh)"

step "SwARc runtime and src/ against the LGPL FFmpeg ($kb)"
# deps.sh installs FFmpeg with prefix=/ffmpeg: its pkg-config files, pointed
# at where it really is.
pc="$BUILD/builder/deps/pkgconfig"
rm -rf "$pc" && mkdir -p "$pc"
for f in "$ff"/lib/pkgconfig/*.pc; do
  sed -E "s#^(prefix|libdir|includedir)=/ffmpeg#\\1=$ff#" "$f" > "$pc/$(basename "$f")"
done
PKG_CONFIG_PATH="$pc" cmake -S "$ROOT" -B "$kb" -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DRECOMP_LLVM_ROOT="$LLVM_ROOT" -DSWARC_DIR="$SWARC" -DGH3_GENERATED_DIR="$BUILD/generated" \
  > "$LOGS/kit-configure.log" || die "configure failed (see $LOGS/kit-configure.log)"
grep -q "$ff/lib/libavcodec" "$kb/CMakeCache.txt" ||
  die "the kit build did not pick up $ff (see $LOGS/kit-configure.log)"
cmds="$(ninja -C "$kb" -t commands gh3)"
# Everything gh3 needs except the lifted code, which the player's Mac compiles.
# shellcheck disable=SC2046
ninja -C "$kb" $(echo "$cmds" | python3 -I "$here/kit_flags.py" --targets) > "$LOGS/kit-build.log" 2>&1 ||
  { grep -m5 'error:' "$LOGS/kit-build.log" >&2; die "kit build failed (see $LOGS/kit-build.log)"; }

step "kit: $kit"
rm -rf "$kit"
mkdir -p "$kit"/{bin,Frameworks,include,native,manifests,tools}

# The lifter, and a stand-in for the game linking the game's libraries,
# each with what they load: bundle_dylibs.py copies it into bin/../Frameworks.
# The stand-in is run once the kit is signed, to prove every library loads.
cp "$LIFTER" "$kit/bin/recomp_lift"
python3 -I "$ROOT/packaging/macos/bundle_dylibs.py" "$kit/bin/recomp_lift" > /dev/null
libs=()
while read -r l; do libs+=("$l"); done < <(echo "$cmds" | CMAKE_BUILD="$kb" python3 -I "$here/kit_flags.py" --link-paths)
rpaths=()
for d in $(for l in "${libs[@]}"; do dirname "$l"; done | sort -u); do rpaths+=("-Wl,-rpath,$d"); done
echo 'int main() { return 0; }' | xcrun clang++ -x c++ - -x none -o "$kit/bin/gh3-loadcheck" "${libs[@]}" "${rpaths[@]}"
python3 -I "$ROOT/packaging/macos/bundle_dylibs.py" "$kit/bin/gh3-loadcheck" "$ff/lib" "$BREW/lib" > /dev/null
xcrun clang++ -std=c++20 -O2 -I"$LLVM_ROOT/include" "$here/undname.cpp" \
  "$LLVM_ROOT/lib/libLLVMDemangle.a" -o "$kit/bin/llvm-undname"
cp "$(command -v upx)" "$(command -v 7zz)" "$kit/bin/"
chmod u+w "$kit"/bin/*  # Homebrew installs them read-only

(cd "$SWARC/src" && find . -name '*.h' -print0 | xargs -0 tar -cf -) | tar -xf - -C "$kit/include"
cp "$kb"/CMakeFiles/gh3.dir/src/*.o "$kit/native/"
# recomp_add_lifted builds SwARc's lifted-code registry into the lifted
# code's target; it is SwARc's, not lifted, so it comes prebuilt.
cp "$(find "$kb/CMakeFiles/gh3_lifted.dir" -name lifted_table.cpp.o)" "$kit/native/"
strip -S "$kit"/native/*.o  # debug info names this machine's paths
cp "$ROOT"/manifests/{lifter,fmodex}.manifest "$kit/manifests/"
cp -R "$ROOT/manifests/ghidra" "$kit/manifests/"
cp "$SWARC/tools/pe_symbols.py" "$ROOT/packaging/macos/exe_icon.py" "$kit/tools/"
cp "$here/kit/build_game.sh" "$kit/"

# The lifted code's compile flags and the game's libraries.
echo "$cmds" | CMAKE_BUILD="$kb" python3 -I "$here/kit_flags.py" "$kit"

# FFmpeg: the LGPL build the libraries were linked against. bundle_dylibs.py
# may have found Homebrew's same-named GPL libraries first (it searches
# /opt/homebrew/lib), so they are copied over and checked, and what only
# those needed goes.
for lib in "$ff"/lib/lib*.[0-9]*.dylib; do
  name="$(basename "$lib")"
  [[ "$name" =~ ^lib[a-z]+\.[0-9]+\.dylib$ ]] && cp -f "$lib" "$kit/Frameworks/$name"
done
python3 -I "$here/kit_prune.py" "$kit"
for lib in "$kit"/Frameworks/libav*.dylib "$kit"/Frameworks/libsw*.dylib; do
  cmp -s "$lib" "$ff/lib/$(basename "$lib")" || die "$(basename "$lib") is not the LGPL FFmpeg's"
done
if ls "$kit/Frameworks" | grep -E -i 'x264|x265|SvtAv1|vpx|ssl|crypto'; then
  die "the kit has GPL FFmpeg's dependencies (above)"
fi

# The files the build checks (scripts/setup/common.sh), and the version.
{
  grep -E '^(GH3_EXE|FMODEX_PACKED|FMODEX|MSVCR80|MSVCP80|VCREDIST)_(SHA256|URL)=' "$ROOT/scripts/setup/common.sh"
  echo "VERSION=\"$(git -C "$ROOT" describe --tags --always | sed 's/^v//')\""
  echo "BUILD_NUMBER=\"$(git -C "$ROOT" rev-list --count HEAD)\""
} > "$kit/config.sh"

# Debug maps name the build's object files (this machine's paths); the
# symbols crash reports use stay.
strip -S "$kit"/Frameworks/librecomp_*.dylib "$kit/bin/recomp_lift"

# Licenses: every third-party component in the kit, and NOTICES.md.
lic="$kit/licenses"
mkdir -p "$lic"
ver() { brew list --versions "$1" | awk '{print $2}' | sed 's/_[0-9]*$//'; }
cp "$ROOT/LICENSE" "$lic/GH3-macOS-Recomp.txt"
{ cat "$SWARC/LICENSE"; echo; cat "$SWARC/NOTICE"; } > "$lic/SwARc.txt"
cp "$kb/_deps/softfloat-src/COPYING.txt" "$lic/Berkeley-SoftFloat.txt"
cp "$kb/_deps/coremath-src/LICENSE" "$lic/CORE-MATH.txt"
cp "$kb/_deps/zydis-src/LICENSE" "$lic/Zydis.txt"
cp "$kb/_deps/zydis-src/dependencies/zycore/LICENSE" "$lic/Zycore.txt"
cp "$LLVM_ROOT/LICENSE.TXT" "$lic/LLVM.txt"
{ cat "$ff/LICENSE.md"; echo; cat "$ff/COPYING.LGPLv2.1"; } > "$lic/FFmpeg.txt"
cp "$BREW/opt/sdl3/LICENSE.txt" "$lic/SDL3.txt"
cp "$BREW/opt/libusb/COPYING" "$lic/libusb.txt"
cp "$BREW/opt/glslang/LICENSE.txt" "$lic/glslang.txt"
cp "$BREW/opt/spirv-tools/LICENSE" "$lic/SPIRV-Tools.txt"
{ tar -xOf "$srcs/upx-5.2.0-src.tar.xz" upx-5.2.0-src/LICENSE; echo
  tar -xOf "$srcs/upx-5.2.0-src.tar.xz" upx-5.2.0-src/COPYING; } > "$lic/UPX.txt"
{ for f in License.txt copying.txt unRarLicense.txt; do
    tar -xOzf "$srcs/sevenzip-26.06.tar.gz" "7zip-26.06/DOC/$f"; echo; done; } > "$lic/7-Zip.txt"
source "$kit/config.sh"
cat > "$lic/NOTICES.md" <<NOTICES
# GH3 Builder $VERSION: third-party notices

GH3 Builder holds nothing from Guitar Hero III. It contains the components
below, each under its own license (the files next to this one). The game it
builds links the same libraries, and carries this folder too.

| Component | Version | License | In the builder |
|---|---|---|---|
| GH3-macOS-Recomp | $VERSION | MIT | the build script, native code (src/), manifests |
| SwARc | $(git -C "$SWARC" describe --tags --always) | MIT | the lifter and the runtime libraries (librecomp_*) |
| Berkeley SoftFloat | 3e ($(git -C "$kb/_deps/softfloat-src" rev-parse --short HEAD)) | BSD-3-Clause | in SwARc's runtime |
| CORE-MATH | $(git -C "$kb/_deps/coremath-src" rev-parse --short HEAD) | MIT | in SwARc's runtime |
| Zydis, Zycore | $(git -C "$kb/_deps/zydis-src" describe --tags --always) | MIT | in the lifter and SwARc's runtime |
| LLVM Demangle | $(ver llvm@22) | Apache-2.0 WITH LLVM-exception | in SwARc's runtime and bin/llvm-undname |
| FFmpeg | 9.0.2 | LGPL-2.1-or-later | libavcodec, libavformat, libavutil, libswscale (Bink and MP3 decoding) |
| SDL3 | $(ver sdl3) | Zlib | libSDL3 (window, input, audio, Metal) |
| libusb | $(ver libusb) | LGPL-2.1-or-later | libusb-1.0 (Xbox 360 wireless receiver) |
| glslang | $(ver glslang) | BSD-3-Clause, MIT, Apache-2.0, GPL-3.0-or-later WITH Bison-exception-2.2 | libglslang, libSPIRV (shader compiler) |
| SPIRV-Tools | $(ver spirv-tools) | Apache-2.0 | libSPIRV-Tools |
| UPX | $(ver upx) | GPL-2.0-or-later (with the UPX exception) | bin/upx (unpacks fmodex.dll) |
| 7-Zip | $(ver sevenzip) | LGPL-2.1-or-later, BSD-3-Clause, unRAR restriction | bin/7zz (extracts the Visual C++ runtime) |

## Source code
The LGPL and GPL components' source, exactly the versions above, is published
next to every GH3 Builder release as GH3-Builder-$VERSION-sources.tar:
ffmpeg-9.0.2.tar.xz, libusb-$(ver libusb).tar.bz2, upx-$(ver upx)-src.tar.xz and
sevenzip-$(ver sevenzip).tar.gz, with how FFmpeg was configured. The other
components' source is at their projects; GH3-macOS-Recomp's and SwARc's at
https://github.com/segovia-no/GH3-macOS-Recomp and
https://github.com/segovia-no/SwARc (tag gh3-v$VERSION).

FFmpeg and libusb are linked dynamically (Contents/Frameworks); you may
replace them with your own builds of the same version (re-sign the app
afterwards: codesign --force -s - <app>).

FFmpeg was configured with (packaging/builder/deps.sh in GH3-macOS-Recomp):

    ./configure $(strings "$ff/lib/libavutil.61.dylib" | grep -m1 -- '--prefix=/ffmpeg')
NOTICES

codesign --force -s - "$kit"/Frameworks/*.dylib "$kit"/bin/* 2>/dev/null
"$kit/bin/gh3-loadcheck" || die "the game's libraries do not load together (above)"
rm "$kit/bin/gh3-loadcheck"
# Nothing may point outside the kit: the user's Mac has no Homebrew.
if otool -L "$kit"/bin/* "$kit"/Frameworks/*.dylib 2>/dev/null | grep -E '^\s+/(opt|usr/local)/'; then
  die "the kit links outside itself (above)"
fi
# Nor name this machine's home folder (debug info, build paths).
if grep -rl --binary-files=text "$HOME/" "$kit" > /dev/null; then
  grep -rl --binary-files=text "$HOME/" "$kit" >&2
  die "the kit names $HOME (above)"
fi
echo "kit: $(du -sh "$kit" | cut -f1)"
