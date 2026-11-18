# Analysis tools

Scripts used for the findings in [`docs/`](../docs). They work on ROM sets you supply; nothing here contains game data. Output goes to `analysis/`, which git ignores.

Requirements: Python 3 with `capstone` and Pillow (`python3 -m venv analysis/venv`, then install `requirements.txt` and `pillow` into it), MAME (0.289 tested, `brew install mame`), and for decompilation Ghidra 12 with a Java 21 runtime.

## 1. Prepare images

Extract each set into its own folder under `analysis/roms/` (`robocop/` for the arcade set, `robocop_md/` for the demo's `.bin`), then:

```sh
python3 -I tools/prep_roms.py analysis/roms analysis/work analysis/mame/roms
```

This writes the flat 68000 program (`robocop_prg.bin`, the two even/odd ROM pairs joined), the HuC6280 boot ROM, the 6502 program, the sample ROM, the four graphics regions laid out as MAME does, and a copy of the demo (`robocop_md.bin`). The third argument also writes a `robocop/` folder MAME accepts: some dumps hold the two video PROMs at twice their size under shorter names, and MAME wants the first half. Check with `mame -verifyroms robocop -rompath analysis/mame/roms`.

## 2. Disassemble and decompile

```sh
analysis/venv/bin/python3 -I tools/analysis/dis68k.py analysis/work/robocop_prg.bin 1002:60
analysis/venv/bin/python3 -I tools/analysis/codemap.py analysis/work/robocop_prg.bin analysis/out/robocop_prg --tables
tools/ghidra/analyze.sh <ghidra dir> analysis/work/robocop_prg.bin dec0 - analysis
tools/ghidra/analyze.sh <ghidra dir> analysis/work/robocop_md.bin  md   - analysis
tools/ghidra/reanalyze.sh <ghidra dir> robocop_prg analysis
```

| Script | Does |
|---|---|
| `analysis/dis68k.py` | Disassembles ranges of a flat 68000 image with capstone |
| `analysis/codemap.py` | Follows the code from the vectors (and, with `--tables`, through tables of long pointers) and writes the call targets, the runs of decoded code and every instruction with an absolute hardware address, by region; prints totals per region |
| `ghidra/Seed68k.java` | Pre-analysis: names memory regions for the machine (`dec0` or `md`), creates functions at the vector table's targets |
| `ghidra/SeedCalls.java` | Second pass: disassembles at absolute `JSR`/`JMP` targets and at `LEA`/`PEA` targets that look like code |
| `ghidra/ExportC.java` | Writes `functions.tsv` and `decomp.c` to `analysis/out/<image>/` |

Set `JAVA_HOME` to the Java 21 runtime before the Ghidra scripts. The HuC6280's program is disassembled with MAME's debugger (see the `disassemble-68k` skill): capstone and Ghidra's 6502 modes do not know its extra instructions.

## 3. Trace the arcade in MAME

```sh
cd analysis/mame
mkdir -p rc_run
TRACE_OUT=rc_run TRACE_FRAMES=21600 TRACE_SNAP_EVERY=600 HOLD="ffb242=28" \
  mame robocop -rompath roms -video none -sound none -skip_gameinfo -nothrottle \
  -seconds_to_run 400 -snapshot_directory rc_run -autoboot_script ../../tools/mame/dec0_trace.lua
```

| Script | Does |
|---|---|
| `mame/dec0_trace.lua` | Per frame: the latched sprite list (entries, 16×16 tiles, distinct tiles, pieces of up to 32×32, tiles per line, palettes, flash bits), each tile layer's control, shape, scroll, visible cells, distinct tiles, 8×8 patterns and palettes, the colours on screen (24-bit and cut to 9-bit), the pattern working set and what is new in it, the priority register, sound commands, HuC6280 interrupts, sprite latches and turns of the frame wait loop. Plays the game by script. The board's registers are write-only, so the script keeps copies of what the 68000 writes |
| `mame/dec0_profile.lua` | Samples the program counter about 200 times a frame with a heuristic call stack; per frame, counts samples in the wait loops (`IDLE`) and in the code serving the HuC6280 (`SUBWAIT`) |
| `mame/dec0_access.lua` | Records every instruction that reads or writes arcade hardware, with counts and address range per region, and which work RAM, sprite RAM and dual-port RAM bytes are written |
| `mame/dec0_sound.lua` | Counts the 68000's sound commands and the 6502's writes to each YM2203 and YM3812 register, key-ons per channel and OKI samples per voice |
| `mame/md_trace.lua` | Decodes every 68000 write to the Mega Drive VDP: DMA size, target and source, fills, copies, CRAM and register writes. Keeps its own VRAM and CRAM copies (MAME does not expose the real VRAM to Lua), walks the sprite table each frame, and dumps VRAM, CRAM and registers at snapshot frames |
| `mame/probe.lua` | Lists a machine's devices, memory shares, regions and input fields |

`HOLD="<hex address>=<hex byte>[,...]"` rewrites RAM bytes every frame; `ffb242=28` holds the player's energy at its starting value. All four arcade scripts play the same input script, so their runs line up frame for frame.

## 4. Summarise

```sh
python3 -I tools/analysis/summarise_traces.py --dec0 analysis/mame/rc_run/dec0_frames.csv --from 300 --to 5400
python3 -I tools/analysis/summarise_traces.py --md analysis/mame/demo_run/md_frames.csv
analysis/venv/bin/python3 -I tools/analysis/contact_sheet.py analysis/mame/rc_run/robocop analysis/out/sheet.png 1
analysis/venv/bin/python3 -I tools/analysis/md_vdp_dump.py analysis/mame/demo_run/vdp_004500.bin --render analysis/out/layers
```

`summarise_traces.py` prints per-metric distributions for gameplay frames; `contact_sheet.py` tiles a run's snapshots into one picture (look at it before trusting the numbers); `md_vdp_dump.py` prints the VRAM layout and which patterns, palette lines and priority bits each plane and the sprites use, and can render each layer to PNG.

## 5. Profile the arcade CPU

```sh
cd analysis/mame
mkdir -p rc_prof
TRACE_OUT=rc_prof TRACE_FRAMES=21600 PROFILE_FROM=300 HOLD="ffb242=28" \
  IDLE="17ba-17cc,17e8-17fa,1156-1166" SUBWAIT="3ef6-3f02,3f2a-3f36,763e-7646,35ae-35ba,7620-762a,7680-768a" \
  mame robocop -rompath roms -video none -sound none -skip_gameinfo -nothrottle \
  -seconds_to_run 400 -autoboot_script ../../tools/mame/dec0_profile.lua
python3 -I ../../tools/analysis/profile_report.py rc_prof ../out/robocop_prg/functions.tsv --from 300 --to 5400
```

`profile_report.py` prints real work, HuC6280 service and wait time per pair of frames (the game logic runs every other frame), and the hottest routines. The address ranges end one instruction past each loop: MAME's sampled program counter is ahead by one.

## 6. Check a Mega Drive ROM

```sh
tools/check_md.sh <rom.bin> <out dir> [frames] [snapshot every N frames]
```

Runs the ROM headless in MAME's `genesis` driver (through `tools/run_md.sh`) and reports whether the CPU is running, plus picture width, sprites, colours, the largest per-frame DMA and sprite-limit overflow. Snapshots and VDP dumps land in the output folder, with `md_vram_free.txt` listing the VRAM patterns never written after `WATCH_FROM` (default frame 300). `TRACE_INPUT=start` presses Start and plays (it reaches stage 1 of the demo); `RAM_WATCH=lo-hi` adds the lowest address written in that range. BlastEm or ares are the choice for hands-on testing; they need a window.
