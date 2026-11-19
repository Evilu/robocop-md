#!/bin/sh
# usage: check_ares.sh <rom.md> <out dir> [captures=8] [seconds between=5]
# Runs a Mega Drive ROM in ares (a window opens), captures that window alone at
# intervals, closes the ares it started, and writes a contact sheet. ares has no
# headless mode and no scripted input: this shows what the ROM does on its own.
# ARES names the ares binary; macOS must allow the terminal to record the screen.
set -e
ROM=$(cd "$(dirname "$1")" && pwd)/$(basename "$1"); OUT=$2; SHOTS=${3:-8}; EVERY=${4:-5}
HERE=$(cd "$(dirname "$0")" && pwd)
ARES=${ARES:-$HOME/Downloads/ares-v148/ares.app/Contents/MacOS/ares}
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
rm -f "$OUT"/ares_*.png
"$ARES" --system "Mega Drive" --no-file-prompt "$ROM" > "$OUT/ares.log" 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null' EXIT
sleep 6
WINDOW=$(swift "$HERE/ares/window_id.swift" $PID | head -1)
[ -n "$WINDOW" ] || { echo "no ares window found"; exit 1; }
i=1
while [ $i -le "$SHOTS" ]; do
  screencapture -x -o -l "$WINDOW" "$OUT/$(printf 'ares_%02d.png' $i)"
  sleep "$EVERY"
  i=$((i + 1))
done
kill $PID 2>/dev/null || true
trap - EXIT
"$HERE/../analysis/venv/bin/python3" -I - "$OUT" <<'PY'
import glob
import sys
from PIL import Image
files = sorted(glob.glob(sys.argv[1] + '/ares_*.png'))
images = [Image.open(f).convert('RGB') for f in files]
width = 480
height = images[0].size[1] * width // images[0].size[0]
cols = 4
sheet = Image.new('RGB', (cols * width, ((len(images) + cols - 1) // cols) * height))
for i, image in enumerate(images):
    sheet.paste(image.resize((width, height)), ((i % cols) * width, (i // cols) * height))
sheet.save(sys.argv[1] + '/ares_sheet.png')
print(len(images), 'captures ->', sys.argv[1] + '/ares_sheet.png')
PY
