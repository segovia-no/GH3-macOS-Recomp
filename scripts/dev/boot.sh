#!/bin/sh
# Boot the recompiled GH3 against build/gamedir for at most $1 seconds
# (default 60) without taking input or focus, and print the end of the
# log. Log: build/logs/boot.log.
cd "$(dirname "$0")/../../build" || exit 1
mkdir -p logs
secs=${1:-60}
GH3_BACKGROUND=1 GH3_WATCHDOG_SECS=30 ./cmake/gh3 "$PWD/gamedir" > logs/boot.log 2>&1 &
pid=$!
# Never leave the game running if this script is stopped early.
trap 'kill $pid 2>/dev/null' EXIT INT TERM
i=0
while [ $i -lt "$secs" ] && kill -0 $pid 2>/dev/null; do sleep 1; i=$((i + 1)); done
kill $pid 2>/dev/null
wait $pid
echo "exit $? after ${i}s"
grep -m1 -A3 'FATAL' logs/boot.log || tail -20 logs/boot.log
