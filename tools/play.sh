#!/bin/sh
# Play the recompiled GH3 interactively (real window, keyboard and pads).
# Log: work/play.log. Settings: ~/Library/Application Support/gh3/AspyrConfig.ini
cd "$(dirname "$0")/../work" || exit 1
GH3_FPS_REPORT=${GH3_FPS_REPORT:-0} ./build/gh3 "$PWD/gamedir" 2>&1 | tee play.log
