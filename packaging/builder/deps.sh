#!/bin/bash
# The builder's third-party pieces that need more than Homebrew's builds:
# - the source of every (L)GPL component the builder ships, pinned to the
#   version in it, in build/builder/sources (published with each builder,
#   as their licenses require);
# - FFmpeg built as LGPL with only what SwARc uses (the Bink demuxer; the
#   Bink video/audio, MP3 and MJPEG decoders; swscale), in
#   build/builder/deps/ffmpeg. Homebrew's FFmpeg is GPL (x264, x265, ...).
# Same FFmpeg version as Homebrew's, so its libraries are drop-in
# replacements for the ones the developer build linked (make_kit.sh).
set -euo pipefail
source "$(dirname "$0")/../../scripts/setup/common.sh"
src="$BUILD/builder/sources"
deps="$BUILD/builder/deps"
mkdir -p "$src" "$deps"

# name version url sha256 (versions: what Homebrew installed; checked below)
SOURCES=(
  "ffmpeg 9.0.2 https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz 8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e"
  "libusb 1.0.30 https://github.com/libusb/libusb/releases/download/v1.0.30/libusb-1.0.30.tar.bz2 fea36f34f9156400209595e300840767ab1a385ede1dc7ee893015aea9c6dbaf"
  "upx 5.2.0 https://github.com/upx/upx/releases/download/v5.2.0/upx-5.2.0-src.tar.xz af99e526d5759de94412aea1104d5e4ca406cb725295f8633ecc9e843dc1ce1c"
  "sevenzip 26.06 https://github.com/ip7z/7zip/archive/refs/tags/26.06.tar.gz 63bbf0ede83e4286ec8a2905ed732a12acc36dd4771984d870b054240ce761fa"
)

step "sources (build/builder/sources)"
for s in "${SOURCES[@]}"; do
  read -r name version url sha <<< "$s"
  have="$(brew list --versions "$name" | awk '{print $2}' | sed 's/_[0-9]*$//')"
  [ "$have" = "$version" ] ||
    die "$name: Homebrew has $have, the builder is pinned to $version (update SOURCES in $0)"
  file="$(basename "$url")"
  case "$file" in "$name"*) ;; *) file="$name-$file" ;; esac
  file="$src/$file"
  [ "$(sha256 "$file" 2>/dev/null)" = "$sha" ] || curl -sSLf -o "$file" "$url"
  check_sha "$file" "$sha" "$name source"
  echo "$(basename "$file")"
done

step "FFmpeg (LGPL, minimal)"
ff="$deps/ffmpeg"
if [ ! -f "$ff/lib/libavcodec.dylib" ]; then
  work="$deps/ffmpeg-build"
  rm -rf "$work" "$ff" && mkdir -p "$work"
  tar -xf "$src/ffmpeg-9.0.2.tar.xz" -C "$work" --strip-components 1
  (
    cd "$work"
    # A neutral prefix: FFmpeg embeds its configure line in libavutil.
    ./configure --prefix=/ffmpeg --install-name-dir='@rpath' \
      --enable-shared --disable-static --disable-programs --disable-doc \
      --disable-network --disable-autodetect --disable-everything \
      --disable-avdevice --disable-avfilter --disable-swresample \
      --enable-decoder=bink,binkaudio_rdft,binkaudio_dct,mp3,mp3float,mjpeg \
      --enable-demuxer=bink --enable-protocol=file --enable-swscale \
      --cc=clang --arch=arm64 --extra-cflags=-mmacosx-version-min=26.0 \
      --extra-ldflags=-mmacosx-version-min=26.0 > "$LOGS/ffmpeg-configure.log"
    make -j"$(sysctl -n hw.ncpu)" > "$LOGS/ffmpeg-build.log" 2>&1
    make install DESTDIR="$deps" > /dev/null
  ) || die "FFmpeg build failed (see $LOGS/ffmpeg-*.log)"
  cp "$work/COPYING.LGPLv2.1" "$work/LICENSE.md" "$ff/"
  rm -rf "$work"
fi
strings "$ff/lib/libavutil.dylib" | grep -q 'LGPL version 2.1 or later' ||
  die "$ff is not an LGPL build"
ls "$ff/lib"/*.dylib | xargs -n1 basename | tr '\n' ' '; echo
