#!/bin/sh
# usage: compare_levels.sh <rom.md> [frames, default 3600] [scenes]
# Loads each scene's save state on the arcade game and on the Mega Drive ROM, plays both
# with the same scripted pad and full energy, and writes a sheet per scene with the
# arcade's snapshots above the port's: analysis/out/levels/scene<N>.png.
# Run level_states.sh first. The two machines drift apart (the game's random numbers
# depend on timing): compare what is drawn, not positions.
set -e
ROM=$1; FRAMES=${2:-3600}; SCENES=${3:-"0 1 2 3 4 5 6 7 8 9"}
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$HERE/../analysis/mame/level_runs
OUT=$HERE/../analysis/out/levels
mkdir -p "$OUT"
for n in $SCENES; do
  rm -rf "$WORK/arcade$n" "$WORK/md$n"
  LOAD=scene$n TRACE_FRAMES=$FRAMES SNAP_EVERY=${SNAP_EVERY:-300} HOLD="ffb242=28" "$HERE/level.sh" arcade "$WORK/arcade$n" &
  LOAD=scene$n TRACE_FRAMES=$FRAMES SNAP_EVERY=${SNAP_EVERY:-300} HOLD="ffb242=28" "$HERE/level.sh" "$ROM" "$WORK/md$n" &
done
wait
for n in $SCENES; do
  "$HERE/../analysis/venv/bin/python3" -I "$HERE/analysis/level_sheet.py" "$WORK/arcade$n" "$WORK/md$n" "$OUT/scene$n.png"
done
