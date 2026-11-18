#!/bin/sh
# usage: check_md.sh <rom.bin> <out dir> [frames] [snapshot every N frames]
# Runs a Mega Drive ROM headless in MAME with no input, saves snapshots, VDP dumps and
# the per-frame VDP trace, and reports whether the CPU ended up in an exception vector.
set -e
ROM=$(cd "$(dirname "$1")" && pwd)/$(basename "$1"); OUT=$2; FRAMES=${3:-600}; EVERY=${4:-120}
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
cd "$OUT"
TRACE_OUT="$OUT" TRACE_FRAMES=$FRAMES TRACE_SNAP_EVERY=$EVERY TRACE_INPUT=${TRACE_INPUT:-none} \
  "$HERE/run_md.sh" "$ROM" "$OUT" -video none -sound none \
  -seconds_to_run $((FRAMES / 50 + 10)) -snapshot_directory "$OUT" \
  -autoboot_script "$HERE/mame/md_trace.lua" > "$OUT/mame.log" 2>&1 || true
grep -h "trace error\|Fatal" "$OUT/mame.log" || true
python3 -I - "$OUT/md_frames.csv" "$ROM" <<'PY'
import csv, struct, sys
rows = list(csv.DictReader(open(sys.argv[1])))
rom = open(sys.argv[2], 'rb').read()
vec = set(struct.unpack('>24I', rom[8:104]))
last = rows[-1]
pcs = [int(r['pc'], 16) for r in rows[-60:]]
stuck = len(set(pcs)) == 1
in_exc = any(abs(pcs[-1] - v) < 0x20 for v in vec if v)
print(f"frames {len(rows)}  last PC {pcs[-1]:06x}  width {last['width']}  sprites {last['spr_visible']}  colours {last['cram_colours']}")
print('VRAM DMA bytes/frame max', max(int(r['dma_vram']) for r in rows), ' lines over sprite limit max', max(int(r['spr_over_lines']) for r in rows))
print('RESULT:', 'CPU appears stuck in an exception handler' if (stuck and in_exc) else 'CPU stuck at one address' if stuck else 'running')
PY
ls "$OUT"/rcmd/*.png "$OUT"/genesis/*.png 2>/dev/null | wc -l | xargs echo snapshots:
