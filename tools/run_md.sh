#!/bin/sh
# usage: run_md.sh <rom.md> <work dir> [extra mame options...]
# Runs a Mega Drive ROM in MAME's genesis driver through a one-entry software list,
# which is the only way MAME enables the Sega (SSF2) mapper. Headless unless the
# options say otherwise.
set -e
ROM=$1; WORK=$2; shift 2
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$WORK"; WORK=$(cd "$WORK" && pwd)
rm -rf "$WORK/softlist"
python3 -I "$HERE/mame/md_softlist.py" "$ROM" "$WORK/softlist"
cd "$WORK"
exec mame genesis rcmd -hashpath "$WORK/softlist/hash" -rompath "$WORK/softlist/roms" \
  -skip_gameinfo -nothrottle "$@"
