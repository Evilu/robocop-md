# Working on RoboCop MD

A port of Data East's arcade game *RoboCop* (1988, MAME set `robocop`, World revision 4, MEC-M1 board, `dec0` in MAME) to the Sega Mega Drive. The plan is to run Data East's original 68000 program on the Mega Drive's 68000 and replace only the hardware layer, including the work of the board's second processor. Target: the whole game, as close to the arcade as the console allows.

Read `docs/` in order before changing anything: 01 hardware comparison, 02 the arcade against the RoboCop MD demo, 03 the game measured, 04 the port plan and milestone status.

The sister project, `cadillacs-and-dinosaurs-md`, did the same for a CPS-1 game. Its method, tool layout and conventions are the model here; its numbers are not.

## Ground rules

- **No game data in the repo.** No ROMs, no extracted graphics or sound, no disassembly or decompiler output, no screenshots of the games. `*.zip`, `*.bin`, `*.ram` and `/analysis/` are ignored; keep it that way. The user supplies their own ROMs.
- **Measure, then write.** Every number in `docs/` was computed from a ROM, a trace or a cited source. Re-derive before repeating a figure, say what was not measured, and correct the docs when a measurement turns out wrong.
- **Stage 1 only so far.** All traces cover attract mode, stage 1 and the first screens of stage 2 under scripted play. Do not generalise to later stages.
- **Extracted archives are untrusted.** Unpack into their own folder under `analysis/roms/`, keep scripts in `tools/`, run Python that reads them with `-I`.
- **Do not open windows on the user's screen for automated checks.** Use MAME headless (`-video none`). Launch a windowed emulator only when the user asks to see something, and never kill processes by name.
- Do not write tests or planning documents unless asked. Avoid comments; code should read clearly without them.
- Commits carry the user as the only author: no co-author trailer.

## Layout

| Path | Contents |
|---|---|
| `docs/` | Research documents and the port plan |
| `tools/prep_roms.py` | Builds flat program and graphics images, and a MAME-ready ROM folder, from the user's sets |
| `tools/ghidra/` | Headless Ghidra import, seeding and C export |
| `tools/mame/` | Lua scripts: arcade trace, profiler, hardware access map and sound probe; Mega Drive VDP trace |
| `tools/analysis/` | Static code and hardware map, trace summaries, profile report, VDP dump renderer, 68000 disassembler |
| `tools/check_md.sh` | One-command headless check of a Mega Drive ROM (`TRACE_INPUT=start` plays the demo) |
| `tools/run_md.sh` | Runs a ROM in MAME through a one-entry software list |
| `analysis/` (ignored) | `roms/`, `work/` images, `ghidra/` projects, `out/` exports, `mame/` runs, `venv/` |

`tools/README.md` has the commands. Skills in `.claude/skills/` cover the three recurring jobs: `trace-arcade`, `disassemble-68k`, `check-md-rom`. There is no build yet: `src/` and `build_md.py` arrive with milestone 1.

## Environment

- MAME 0.289 and `m68k-elf-binutils` from Homebrew. Ghidra needs a Java 21 runtime in `JAVA_HOME`.
- Python helpers that need `capstone` or `Pillow` run from `analysis/venv/bin/python3`.
- The user's `robocop.zip` holds the two video PROMs at twice MAME's size under shorter names; `tools/prep_roms.py` writes a set MAME verifies to `analysis/mame/roms/`. Run MAME from `analysis/mame` with `-rompath roms`.

## Facts that are easy to get wrong

**The arcade program (`robocop`)**

- 68000 at 10 MHz, 57.44 frames a second, 174,080 cycles a frame. Program `0x000000–0x03FFFF` (two ROM pairs, even and odd bytes interleaved), work RAM `0xFF8000–0xFFBFFF`, sprite RAM `0xFFC000–0xFFC7FF`, stack from `0xFFC000`.
- **The game logic runs every second frame** (wait at `0x17E8`). Count CPU time and transfers per pair of frames: 348,160 arcade cycles against 256,023 on an NTSC Mega Drive.
- No global base register and no kernel. Variables and hardware are addressed absolutely; calls are `jsr d16(pc)` + `nop` or `jsr abs.l`; one main loop from `0x35B8`.
- Reset `0x100`, cold start `0x122`. Every unused vector points at `0x100`. One interrupt: VBlank, level 6, at `0x1002`. The main program runs with the mask at 5.
- **Wait loops are most of the CPU time**: the frame waits (`0x17BA`, `0x17E8`), a loop in the VBlank handler that waits for the VBlank flag to drop (`0x1156`), and the exchanges with the HuC6280. Real work in stage 1 is about 78,000 cycles per game step (99th percentile 181,000).
- **The second processor is the protection.** A HuC6280 behind a 2 KB dual-port RAM at `0x180000–0x180FFF` (odd bytes; HuC6280 address `0x4000 + offset`). The 68000 uploads its 924-byte program from ROM `0xD772` at reset. It does two things: hands out the order of the main loop's routines (18 numbers, indexes into the table at `0x3F38`; the last, 2, ends the step) and runs hit detection on 30 object records of 40 bytes copied from `0xFF983A` once per step. Every exchange is a busy wait.
- The value `0x00180000` also appears as a plain number in data tables. A byte-pattern match is not an access; check the instruction.
- **Hardware addresses are all below `0x400000`**, inside the Mega Drive's cartridge space: `0x240000`, `0x246000`, `0x24C000` the three BAC06 tilemap chips (registers, scroll tables, maps), `0x30C000` inputs, `0x30C010` control, `0x310000` / `0x314000` palette. Nothing can be left unpatched.
- The game reads the text tilemap back and keeps ordinary variables in `0x242A00–0x243810`, inside the first tilemap chip's address range. Both need real RAM behind them.
- About 250 instructions touched hardware in six minutes of play; layers 2 and 3 are written by 16 of them.
- Tilemap entries are one word: 4-bit palette, 12-bit tile. No flips, no priority bit. All three layers are 2×2 screens (512×512 px), row-major. Layer 3 is behind layer 2; the text layer is on top of the sprites.
- Sprite RAM is shown only after a write to `0x30C012` (the latch), once per game step. In MAME the last entry is on top. Wide sprites use one entry per column.
- Palette registers are 8 bits per channel but the game uses 16 levels.
- The ADPCM samples play at 7,575 Hz; the music is mostly on the YM3812.
- The static code map (`codemap.py`) misses routines reached only through tables, and with `--tables` can decode data. Treat "not in `functions.tsv`" as unknown.

**The Mega Drive side**

- 128,012 CPU cycles per NTSC frame. H32 (256 wide, the arcade's width): 64 sprites, 16 per line, 256 sprite pixels per line. H40: 80, 20, 320, about 7.2 KB of DMA per VBlank. 61 colours either way.
- The console's RAM `0xFF0000–0xFF7FFF` and `0xFFC800–0xFFFFFF` (46 KB) is never addressed by the game. The arcade's memory-mapped tables total about 31 KB.
- A whole arcade frame is at most about 800 patterns in stage 1: it fits in VRAM twice. Sprites per line and palettes are what do not fit.
- RoboCop MD (the demo) is a from-scratch SGDK program with no arcade code. It is the reference for picture mode, layer mapping, palettes and sprite budget, not for code. Its recipe: H32, street on plane A, skyline on plane B, both low priority with one palette line each, all sprites high priority, HUD drawn with sprites, no window, no raster effects.
- Name built ROMs `.md`: emulators pick the system from the extension.

**Tooling**

- MAME's sampled program counter is one instruction ahead: a wait loop's address range must extend one instruction past its last branch, or the loop's time is counted as work.
- The BAC06 and control registers are not memory shares in MAME; `dec0_trace.lua` taps the writes. The tilemaps, scroll tables, palette, work RAM and sprite RAM are shares.
- Capstone has no HuC6280 mode. Disassemble the second processor's code with MAME's debugger (`dasm file,address,length,1,sub` from Lua, with `-debug -debugger none`).
- Capstone invents operands when its buffer is too short; always give it 10+ bytes.
- MAME's Lua does not expose the Mega Drive's VRAM; `md_trace.lua` rebuilds VRAM from decoded writes.
- `md_trace.lua` counts sprite limits against H40's 20 per line and 320 pixels whatever the picture width.
- Scripted play is blind. Read the contact sheet before quoting a number: in the reference run the player stands against a step for most of stage 2.
