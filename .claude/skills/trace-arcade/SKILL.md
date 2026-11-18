---
name: trace-arcade
description: Measure what the Data East arcade game (robocop) does per frame in MAME - sprites, tilemaps, palettes, graphics on screen, CPU work, a per-routine profile, hardware accesses and sound chip use. Use when asked to trace, measure or profile the arcade game, or to get numbers for a new stage or scene.
---

# Trace and profile the arcade game

Run everything from `analysis/mame`. Output stays under `analysis/`, which git ignores. `roms/` there is the MAME-ready set written by `tools/prep_roms.py`.

## Trace (video load)

```sh
mkdir -p rc_run
TRACE_OUT=rc_run TRACE_FRAMES=21600 TRACE_SNAP_EVERY=600 HOLD="ffb242=28" \
  mame robocop -rompath roms -video none -sound none -skip_gameinfo -nothrottle \
  -seconds_to_run 400 -snapshot_directory rc_run -autoboot_script ../../tools/mame/dec0_trace.lua \
  > rc_run/mame.log 2>&1
python3 -I ../../tools/analysis/summarise_traces.py --dec0 rc_run/dec0_frames.csv
```

- 21,600 frames take about 4 minutes; run in the background.
- Check `grep -c "trace error" <dir>/mame.log` is 0 and the CSV has `TRACE_FRAMES + 1` lines.

## Profile (CPU)

```sh
mkdir -p rc_prof
TRACE_OUT=rc_prof TRACE_FRAMES=21600 PROFILE_FROM=300 HOLD="ffb242=28" \
  IDLE="17ba-17cc,17e8-17fa,1156-1166" SUBWAIT="3ef6-3f02,3f2a-3f36,763e-7646,35ae-35ba,7620-762a,7680-768a" \
  mame robocop -rompath roms -video none -sound none -skip_gameinfo -nothrottle \
  -seconds_to_run 400 -autoboot_script ../../tools/mame/dec0_profile.lua > rc_prof/mame.log 2>&1
python3 -I ../../tools/analysis/profile_report.py rc_prof ../out/robocop_prg/functions.tsv
```

- `profile_frames.csv` has, per frame, the samples taken, those in the frame wait loops (`IDLE`), those serving the HuC6280 (`SUBWAIT`: waiting for it and copying objects to and from it) and those inside the VBlank handler. Cycles = samples ÷ samples in the frame × 174,080.
- The game logic runs every other frame: add frames in pairs before comparing with a budget.

## Hardware accesses, RAM use, sound

```sh
TRACE_OUT=rc_access TRACE_FRAMES=21600 RAM_FROM_FRAME=300 BOOT_CLEAR=14e-15e HOLD="ffb242=28" mame robocop ... -autoboot_script ../../tools/mame/dec0_access.lua
TRACE_OUT=rc_sound TRACE_FRAMES=7200 HOLD="ffb242=28" mame robocop ... -autoboot_script ../../tools/mame/dec0_sound.lua
```

`access_pcs.csv` lists every instruction that read or wrote arcade hardware; `ram_written.bin` and `shared_written.bin` mark the work RAM and dual-port RAM bytes written. `sound_summary.txt` counts the 68000's sound commands and the 6502's writes per chip register, key-ons per channel and samples per OKI voice.

## Always look at what was played

Build a contact sheet and read it before trusting any statistic:

```sh
../venv/bin/python3 -I ../../tools/analysis/contact_sheet.py rc_run/robocop ../out/sheet.png 1
```

The input script is blind. A run that sat on a menu or stood still produces clean-looking but meaningless numbers.

## Traps

- **Waiting is not work.** The frame wait loops, the loop in the VBlank handler that waits for VBlank to end (`0x1156`) and the loops waiting for the HuC6280 are most of the arcade's CPU time. Quote work with them taken out, and say so.
- **Two frames per game step.** Sprite RAM is latched and the HuC6280 is interrupted once per pair of frames in gameplay. Per-frame CPU figures alternate between a busy and an idle frame.
- **The registers cannot be read back.** `dec0_trace.lua` keeps copies of what the 68000 writes to the BAC06 control and scroll registers and the priority register; a trace started from a save state has zeros until the game rewrites them.
- **`HOLD="ffb242=28"` keeps the player's energy at its starting value** so the script gets further. It changes what is on screen (no deaths, no continue screen). Say when a figure used it.
- **Pattern counts** are 8×8 cells with at least one non-zero pixel, for the full 256×240 picture.
- **Determinism.** The same script gives the same run frame for frame, so a second run can be joined to the first by frame number.
- To reach another stage, extend the input script or load a save state; do not assume stage 1 numbers carry over.
