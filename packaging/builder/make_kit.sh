#!/bin/bash
# Assembles the builder kit (build/builder/kit) from a finished developer
# build (./setup.sh): everything a Mac needs to build the game from the
# player's own copy with only the Xcode Command Line Tools (Apple clang),
# no Homebrew and no LLVM install. Nothing in it comes from the game:
#   bin/          SwARc's lifter, llvm-undname (undname.cpp), upx, 7zz
#   Frameworks/   SwARc's runtime and the libraries it uses (SDL3, ffmpeg,
#                 libusb, ...), relinked to @rpath (bundle_dylibs.py)
#   include/      SwARc's headers, for the lifted code
#   native/       this project's src/ and SwARc's lifted_table.cpp as objects
#   manifests/    the lifter's manifests and the Ghidra tables
#   tools/        pe_symbols.py, exe_icon.py
#   cxxflags, link, config.sh   what the developer build used
#   build_game.sh the build the builder app runs (kit/build_game.sh)
set -euo pipefail
source "$(dirname "$0")/../../scripts/setup/common.sh"
here="$(cd "$(dirname "$0")" && pwd)"
kit="$BUILD/builder/kit"
cm="$CMAKE_BUILD"
[ -x "$cm/gh3" ] || die "no $cm/gh3 (run ./setup.sh first)"

step "kit: $kit"
rm -rf "$kit"
mkdir -p "$kit"/{bin,Frameworks,include,native,manifests,tools}

# The lifter and the game binary, each with its libraries: bundle_dylibs.py
# copies them into bin/../Frameworks. gh3 itself is only a template here.
cp "$LIFTER" "$kit/bin/recomp_lift"
python3 -I "$ROOT/packaging/macos/bundle_dylibs.py" "$kit/bin/recomp_lift" > /dev/null
cp "$cm/gh3" "$kit/bin/gh3.template"
python3 -I "$ROOT/packaging/macos/bundle_dylibs.py" "$kit/bin/gh3.template" "$BREW/lib" > /dev/null
rm "$kit/bin/gh3.template"
xcrun clang++ -std=c++20 -O2 -I"$LLVM_ROOT/include" "$here/undname.cpp" \
  "$LLVM_ROOT/lib/libLLVMDemangle.a" -o "$kit/bin/llvm-undname"
cp "$(command -v upx)" "$(command -v 7zz)" "$kit/bin/"

(cd "$SWARC/src" && find . -name '*.h' -print0 | xargs -0 tar -cf -) | tar -xf - -C "$kit/include"
cp "$cm"/CMakeFiles/gh3.dir/src/*.o "$kit/native/"
# recomp_add_lifted builds SwARc's lifted-code registry into the lifted
# code's target; it is SwARc's, not lifted, so it comes prebuilt.
cp "$(find "$cm/CMakeFiles/gh3_lifted.dir" -name lifted_table.cpp.o)" "$kit/native/"
cp "$ROOT"/manifests/{lifter,fmodex}.manifest "$kit/manifests/"
cp -R "$ROOT/manifests/ghidra" "$kit/manifests/"
cp "$SWARC/tools/pe_symbols.py" "$ROOT/packaging/macos/exe_icon.py" "$kit/tools/"
cp "$here/kit/build_game.sh" "$kit/"

# The lifted code's compile flags and the game's libraries, as the
# developer build (CMake, SwARc's recomp_add_lifted) used them.
ninja -C "$cm" -t commands gh3 | CMAKE_BUILD="$cm" python3 -I "$here/kit_flags.py" "$kit"

# The files the build checks (scripts/setup/common.sh), and the version.
{
  grep -E '^(GH3_EXE|FMODEX_PACKED|FMODEX|MSVCR80|MSVCP80|VCREDIST)_(SHA256|URL)=' "$ROOT/scripts/setup/common.sh"
  echo "VERSION=\"$(git -C "$ROOT" rev-parse --short HEAD)\""
  echo "BUILD_NUMBER=\"$(git -C "$ROOT" rev-list --count HEAD)\""
} > "$kit/config.sh"

codesign --force -s - "$kit"/Frameworks/*.dylib "$kit"/bin/* 2>/dev/null
# Nothing may point outside the kit: the user's Mac has no Homebrew.
if otool -L "$kit"/bin/* "$kit"/Frameworks/*.dylib 2>/dev/null | grep -E '^\s+/(opt|usr/local)/'; then
  die "the kit links outside itself (above)"
fi
echo "kit: $(du -sh "$kit" | cut -f1)"
