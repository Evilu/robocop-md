---
name: check-md-rom
description: Run a Mega Drive ROM headless in MAME and check that it boots, what it draws and how it uses the VDP (DMA per frame, sprites, palettes, VRAM layout), then confirm the picture in ares with a screen capture before calling a change finished. Use after building the port's ROM, when asked whether a build works, or to inspect any Mega Drive ROM such as the RoboCop MD demo.
---

# Check a Mega Drive ROM

## One command

```sh
tools/check_md.sh <rom.bin> <out dir> [frames=600] [snapshot every=120]
```

Runs the ROM in MAME's `genesis` driver with no window and no input, then prints:

- `RESULT: running`, `CPU stuck at one address`, or `CPU appears stuck in an exception handler`
- picture width, visible sprites, colours in CRAM
- the largest per-frame VRAM DMA and the worst sprite-limit overflow

Snapshots (`genesis/*.png`), VDP dumps (`vdp_*.bin`) and the per-frame trace (`md_frames.csv`) are in the output folder. **Look at the snapshots**: "running" only means the CPU is executing, not that the picture is right.

## Before calling a change finished: ares

```sh
tools/check_ares.sh <rom.md> <out dir> [captures=8] [seconds between=5]
```

Opens ares with the ROM, captures only the ares window every few seconds, closes the ares it started, and writes `<out dir>/ares_sheet.png`. **Read the sheet.** MAME is lenient about VDP timing and has hidden real bugs (a scene drawn in the wrong colours showed in ares and not in MAME). The MAME check is for every iteration; the ares check is the last step before saying something works.

ares takes no scripted input and its pad is not mapped here, so it shows what the ROM does on its own: the attract sequence, including its gameplay demo. Allow about 40 seconds to see the whole sequence. Compare with the same sequence in MAME (`tools/check_md.sh` with no input) and with the arcade.

## Inspect the picture

```sh
analysis/venv/bin/python3 -I tools/analysis/md_vdp_dump.py <out dir>/vdp_000600.bin --render <out dir>/layers
```

Prints the VRAM layout and, per plane and for sprites, the cells used, distinct patterns, palette lines and priority bits; renders plane A, plane B, the window and the sprites to separate PNGs.

## With input

`TRACE_INPUT=start tools/check_md.sh ...` presses Start every 240 frames, then walks right, shoots (B) and jumps (C): it reaches stage 1 of the RoboCop MD demo. `TRACE_INPUT=arcade` is for a port that keeps the arcade's coin (A at frame 700, Start at 800). The default, `none`, leaves the pads alone. `HOLD=<hex address>=<hex byte>` rewrites RAM bytes every frame (to keep the player alive).

Summarise a run with `python3 -I tools/analysis/summarise_traces.py --md <out dir>/md_frames.csv`.

## Budgets to compare against

| | Limit (NTSC, H32, as the demo uses) | Limit (NTSC, H40) | RoboCop MD demo in stage 1 |
|---|---|---|---|
| VRAM DMA per frame | lower than H40; not measured here | about 7,200 bytes in VBlank | 274 mean, 1,200 p95 |
| Sprites per frame | 64 | 80 | 40 mean, 54 max |
| Sprites per line | 16 | 20 | 7.5 mean, 11 max |
| Sprite pixels per line | 256 | 320 | 121 mean, 320 max (counted against the H40 limit) |
| Colours | 61 | 61 | 46 |
| CPU cycles per frame | 128,000 | 128,000 | — |

## Limits of this check

- MAME performs DMA instantly and is lenient about VDP timing. A build that works here can still glitch on hardware. BlastEm is the accuracy reference, but it needs a window: ask the user before launching it, or ask them to run it.
- MAME's Lua cannot read the real VRAM; the trace rebuilds it from decoded writes. If the ROM writes VRAM in a way the decoder does not handle, the dumps will be wrong while the snapshots are right. Trust the snapshots.
- The trace counts sprite pixels per line against 320 and sprites per line against 20 whatever the width; for a 256-wide picture compare with 256 and 16 yourself.
- ROMs over 4 MB need the `SEGA SSF` header string for the mapper to be enabled. The arcade content of this game is about 1.2 MB, so no mapper is expected.
