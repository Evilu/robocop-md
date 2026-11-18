#!/bin/sh
# usage: reanalyze.sh <ghidra dir> <image name> <work dir>
# Runs SeedCalls on an imported project, then re-exports functions.tsv and decomp.c.
set -e
G=$1; NAME=$2; W=$3
HERE=$(cd "$(dirname "$0")" && pwd)
"$G/support/analyzeHeadless" "$W/ghidra" "$NAME" -process "$NAME.bin" \
  -scriptPath "$HERE" -postScript SeedCalls.java -postScript ExportC.java "$W/out/$NAME" \
  > "$W/out/$NAME/ghidra-pass2.log" 2>&1
grep -h "pass \|exported" "$W/out/$NAME/ghidra-pass2.log" | sed 's/.*> //'
