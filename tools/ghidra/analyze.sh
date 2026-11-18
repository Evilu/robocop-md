#!/bin/sh
# usage: analyze.sh <ghidra dir> <image.bin> <dec0|md> <A5 hex or -> <work dir>
# Imports a flat 68000 image into its own Ghidra project, analyses it and exports
# functions.tsv and decomp.c to <work dir>/out/<image name>.
set -e
G=$1; IMG=$2; MACHINE=$3; A5=$4; W=$5
NAME=$(basename "$IMG" .bin)
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$W/ghidra" "$W/out/$NAME"
"$G/support/analyzeHeadless" "$W/ghidra" "$NAME" -import "$IMG" -overwrite \
  -processor "68000:BE:32:default" -loader BinaryLoader -loader-baseAddr 0 \
  -scriptPath "$HERE" -preScript Seed68k.java "$MACHINE" "$A5" \
  -postScript ExportC.java "$W/out/$NAME" > "$W/out/$NAME/ghidra.log" 2>&1
grep -h "seeded\|exported" "$W/out/$NAME/ghidra.log" | sed 's/.*> //'
