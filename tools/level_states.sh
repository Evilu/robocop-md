#!/bin/sh
# usage: level_states.sh <rom.md> [scenes, default "0 1 2 3 4 5 6 7 8 9"]
# Writes one save state per scene for the arcade game and for the Mega Drive ROM,
# taken at frame 420: the game has started in that scene and play is about to begin.
# States: analysis/mame/states/robocop/scene<N>.sta and .../genesis/scene<N>.sta.
set -e
ROM=$1; SCENES=${2:-"0 1 2 3 4 5 6 7 8 9"}
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$HERE/../analysis/mame/level_states
for n in $SCENES; do
  LEVEL=$n SAVE="scene$n@420" TRACE_FRAMES=430 "$HERE/level.sh" arcade "$WORK/arcade$n" &
  LEVEL=$n SAVE="scene$n@420" TRACE_FRAMES=430 "$HERE/level.sh" "$ROM" "$WORK/md$n" &
done
wait
ls -l "$HERE/../analysis/mame/states/robocop" "$HERE/../analysis/mame/states/genesis"
