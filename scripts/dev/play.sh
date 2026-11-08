#!/bin/sh
# Play the recompiled GH3 interactively. It runs as a minimal app bundle
# (build/dev/GH3.app, the binary symlinked in) launched through LaunchServices:
# a bare binary started from a terminal never becomes the active app on
# macOS, so its window opens behind and the keyboard stays with the terminal.
# Log: build/logs/play.log. Settings: ~/Library/Application Support/gh3/AspyrConfig.ini
# Options (environment): GH3_RESOLUTION=WxH, GH3_FULLSCREEN=window|desktop|exclusive
# GH3_X360RX_TRACE=1: log every packet from an Xbox 360 wireless receiver.
# GH3_PROFILE=1: fps once a second in the log, and a 5 s CPU sample of the
# game every 15 s into build/prof/ (macOS `sample`), to find slow spots.
cd "$(dirname "$0")/../../build" || exit 1
mkdir -p logs dev
app="$PWD/dev/GH3.app"
mkdir -p "$app/Contents/MacOS"
ln -sf "$PWD/cmake/gh3" "$app/Contents/MacOS/gh3"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>gh3</string>
  <key>CFBundleIdentifier</key><string>local.gh3-macos-recomp.dev</string>
  <key>CFBundleName</key><string>Guitar Hero III</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict>
</plist>
PLIST
: > logs/play.log
if [ -n "$GH3_PROFILE" ]; then
  GH3_FPS_REPORT=1
  rm -rf prof && mkdir -p prof
fi
env_args=""
for v in GH3_RESOLUTION GH3_FULLSCREEN GH3_FPS_REPORT GH3_TRACE GH3_TRACE_FILTER GH3_AUDIO_DUMP GH3_VERIFY_SKIN GH3_X360RX_TRACE; do
  eval val=\${$v}
  [ -n "$val" ] && env_args="$env_args --env $v=$val"
done
# shellcheck disable=SC2086
open -W -n $env_args --stdout "$PWD/logs/play.log" --stderr "$PWD/logs/play.log" "$app" \
  --args "$PWD/gamedir" &
pid=$!
tail -f logs/play.log &
tail_pid=$!
if [ -n "$GH3_PROFILE" ]; then
  (
    start=$(date +%s)
    sleep 10
    while kill -0 $pid 2>/dev/null; do
      gpid=$(pgrep -x gh3 | head -1)
      [ -n "$gpid" ] && sample "$gpid" 5 -file "prof/t$(( $(date +%s) - start )).txt" >/dev/null 2>&1
      sleep 10
    done
  ) &
fi
wait $pid
sleep 1
kill $tail_pid 2>/dev/null
