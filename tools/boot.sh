#!/bin/sh
# Boot the recompiled GH3 against work/gamedir for at most $1 seconds
# (default 60) and print the head of the log. Log: work/boot.log.
cd "$(dirname "$0")/../work" || exit 1
secs=${1:-60}
GH3_BACKGROUND=1 GH3_WATCHDOG_SECS=30 ./build/gh3 "$PWD/gamedir" > boot.log 2>&1 &
pid=$!
i=0
while [ $i -lt "$secs" ] && kill -0 $pid 2>/dev/null; do sleep 1; i=$((i + 1)); done
kill $pid 2>/dev/null
wait $pid
echo "exit $? after ${i}s"
grep -m1 -A3 'FATAL' boot.log || tail -20 boot.log
