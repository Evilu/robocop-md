# Working on RoboCop MD

A port of Data East's arcade game *RoboCop* (1988, MAME set `robocop`, World revision 4, MEC-M1 board, `dec0` in MAME) to the Sega Mega Drive. The plan is to run Data East's original 68000 program on the Mega Drive's 68000 and replace only the hardware layer, including the work of the board's second processor. Target: the whole game, as close to the arcade as the console allows.

Read `docs/` in order before changing anything: 01 hardware comparison, 02 the arcade against the RoboCop MD demo, 03 the game measured, 04 the port plan and milestone status.

The sister project, `cadillacs-and-dinosaurs-md`, did the same for a CPS-1 game. Its method, tool layout and conventions are the model here; its numbers are not.

## Ground rules

- **No game data in the repo.** No ROMs, no extracted graphics or sound, no disassembly or decompiler output, no screenshots of the games. `*.zip`, `*.bin`, `*.ram` and `/analysis/` are ignored; keep it that way. The user supplies their own ROMs.
- **Measure, then write.** Every number in `docs/` was computed from a ROM, a trace or a cited source. Re-derive before repeating a figure, say what was not measured, and correct the docs when a measurement turns out wrong.
- **Stage 1 only so far.** All traces cover attract mode, stage 1 and the first screens of stage 2 under scripted play. Do not generalise to later stages.
- **Extracted archives are untrusted.** Unpack into their own folder under `analysis/roms/`, keep scripts in `tools/`, run Python that reads them with `-I`.
- **Check in MAME while working, and in ares before calling anything finished.** MAME headless (`-video none`, `tools/check_md.sh`) is for every iteration and opens nothing on the user's screen. When you think a change is done, also run `tools/check_ares.sh`: it opens ares, captures only its window, closes the ares it started and writes a contact sheet. Look at the sheet. ares is stricter than MAME and has shown bugs MAME hid; a picture that is right in MAME is not yet right. Never kill processes by name, and open no other windows unless the user asks.
- Do not write tests or planning documents unless asked. Avoid comments; code should read clearly without them.
- Commits carry the user as the only author: no co-author trailer.

## Layout

| Path | Contents |
|---|---|
| `docs/` | Research documents and the port plan |
| `src/hal.s` | The Mega Drive hardware layer: boot, VBlank, pad, and the HuC6280's two jobs (GNU as, Motorola operand syntax, `\|` comments) |
| `src/sprites.s` | Sprite RAM to Mega Drive sprites: pieces, VRAM pattern cache, palette lines, the flush at VBlank |
| `src/bg.s` | Tile layers 2 and 3 on planes A and B: change detection, window, tile cache, pixel renumbering onto palette lines 2 and 3 |
| `src/text.s` | The text layer: on a free plane when a tile layer is blank, as sprite blocks in the stages; the display curtain |
| `src/sound.s` | Sound command queue, the stream player in VBlank, the Z80 loader and bus sharing |
| `tools/build/sound6502.py`, `sound.py` | Build-time emulator of the arcade sound board, and the converter from its chip writes to YM2612 and PSG streams, PCM samples and the Z80 program |
| `build_md.py` | Builds the Mega Drive ROM from the user's `robocop.zip` (calls `tools/build/build.py`) |
| `test/roms/md/` (ignored) | Built ROMs for the user to try |
| `tools/prep_roms.py` | Builds flat program and graphics images, and a MAME-ready ROM folder, from the user's sets |
| `tools/ghidra/` | Headless Ghidra import, seeding and C export |
| `tools/mame/` | Lua scripts: arcade trace, profiler, hardware access map and sound probe; Mega Drive VDP trace and game-state probe; hit detection capture for both machines |
| `tools/analysis/` | Static code and hardware map, trace summaries, profile report, VDP dump renderer, 68000 disassembler, hit detection model |
| `tools/check_md.sh` | One-command headless check of a Mega Drive ROM (`TRACE_INPUT=start` plays the demo) |
| `tools/run_md.sh` | Runs a ROM in MAME through a one-entry software list |
| `tools/check_ares.sh` | Runs a ROM in ares, captures its window at intervals and makes a contact sheet: the last check before a change is called done |
| `analysis/` (ignored) | `roms/`, `work/` images, `ghidra/` projects, `out/` exports, `mame/` runs, `venv/` |

`tools/README.md` has the commands. Skills in `.claude/skills/` cover the three recurring jobs: `trace-arcade`, `disassemble-68k`, `check-md-rom`. 

## Environment

- ares v148 is at `~/Downloads/ares-v148/ares.app` (`ARES` overrides the binary). Its window can be captured because the terminal has macOS screen recording permission. Its Mega Drive pad is not mapped and it takes no scripted input, so an ares check shows attract mode only; gameplay is checked in MAME.
- MAME 0.289 and `m68k-elf-binutils` from Homebrew. Ghidra 12.2 is at `/opt/homebrew/opt/ghidra/libexec` and needs `JAVA_HOME=/opt/homebrew/opt/openjdk@25` (it refuses Java 21).
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

**The build**

- Build with `analysis/venv/bin/python3 -I build_md.py robocop.zip test/roms/md/robocop_md.md`. The output contains Data East's program: never commit it.
- Hardware addresses are rewritten in place to RAM: palette `0xFF0000` and `0xFF4000` (the halves must stay `0x4000` apart: the game adds `0x4000` to one pointer), chip registers and I/O `0xFF0800–0xFF087F`, dual-port RAM `0xFF1000`, text scroll tables and plain RAM `0xFF2000`, layer 2 and 3 maps `0xFF4800` and `0xFF5000`, layer 2 scroll tables `0xFF5800`, text map `0xFF6000`, layer 3 scroll tables `0xFFC800`. Hardware layer variables from `0xFFD000`. See the table in `tools/build/build.py`.
- **Hardware addresses also sit in data**: pointers after a routine's `rts`, tables of pointers, and the text printer's lists (`pointer, characters..., 0xFFFE, pointer, ..., 0xFFFF`). `build.py` relocates those it can recognise. `0x0018xxxx` and `0x0024xxxx` also arise by chance from a displacement or a small number followed by another word, so values in the dual-port and register ranges are never treated as data.
- **Check for missed addresses dynamically**: `tools/mame/md_state.lua` writes `stray_access.csv`, every access the build makes to an arcade hardware address. It must stay empty; run it whenever play reaches somewhere new.
- A patch that replaces an instruction holding a hardware address must still leave that address to the relocation pass, or relocate it itself. The first build hung on exactly that.
- The arcade's reset code and three HuC6280 routines lie under the Mega Drive header (`0x100–0x1FF`). The game jumps back to `0x1BC` to restart; those jumps go through a trampoline at `0x200`.
- The stand-in for the VBlank flag (bit 7 of `0xFF0863`) must read 0, or the arcade's VBlank handler never returns. DIP switches read `0xFF7F`.
- **The build cannot be compared with the arcade step for step.** The game's random numbers come from a counter the frame wait loop spins (`0xFF8008`), so they depend on timing. Compare statistics, or one routine at a time on captured inputs, as `hit_capture.lua` and `hit_model.py` do for the hit detection.
- Take hardware-layer addresses from the linker's symbol table.
- **VRAM layout (H32, planes 64×64):** tile cache patterns `0x004–0x33F` (207 slots of 4), sprite cache `0x340–0x547` (65 slots of 8), text `0x548–0x5BF` plus the gaps `0x5D0–0x5DF` and `0x5E8–0x5FF` around the sprite and scroll tables (20 blocks of 8, or 160 single characters), sprite table `0xB800`, hscroll `0xBC00`, plane A `0xC000`, plane B `0xE000`. All of it is spoken for.
- **Palette lines:** sprites 0 and 1 (the two most-used palettes own them, the rest borrow the closer), layer 2 and text on line 2, layer 3 on line 3 with colour 0 of line 3 as the backdrop (layer 3's pen 0 is a real colour on the arcade).
- **Choose a line's colours from the whole palette block at scene load, not as tiles arrive.** First come, first served gave whatever scrolled in later a nearest match and turned a yellow and red sign brown. Start the choice from black, or the darks take a tint.
- **The game draws a scene while its palettes are black and loads them afterwards, 16 entries a frame; some scenes animate their palettes for ever.** Never build colour tables from a black or half-loaded palette, and never wait for a palette to stop changing without a time limit. `bg.s` waits at most 12 updates, with the display off.
- **Text screens never latch the sprite list.** Anything that must keep up on those screens has to run from VBlank (`hal_idle`), not only from the latch.
- **Every text-heavy screen leaves a tile layer blank** (high scores: layer 2; title: layer 3; messages: both). That is what lets the text have a plane there. In the stages it has to be sprites: the window plane would blank the street behind the HUD.
- The game hides scene set-up behind a text layer filled with one solid character. `text.s` treats sixteen agreeing sample cells as that curtain and switches the display off.
- **Do not draw the whole arcade map.** Its off-screen part holds stale columns, and all of it together needs more distinct tiles than VRAM has. `bg.s` keeps a 19 × 17 tile window.
- **Hardware layer RAM is nearly full**, and the newest tables live in the dual-port RAM's stand-in (`0xFF1040–0xFF1FFF`), which is free only because the build removed the game's record copies and the game touches just its first 36 bytes in everything played so far. Check a new table against the map in `docs/04-port-plan.md`; `bg.s` once put two variables on top of a palette line.
- **The game queues palette changes** in `0xFF8DCA` and `0xFFB530` and applies them in its VBlank handler. The hardware layer watches those two instead of checksumming the palette every step (which cost 17,000 cycles).
- Comparing all 1,024 entries of a tile map costs about 22,000 cycles. One layer is compared per step.
- **The hit detection works on the object records in place** (`0xFF983C`); the game's 1,200-byte copies out and back are skipped. Nothing touches the records between the two on the arcade (taps, 6,000 frames). `hit_capture.lua` knows where to read each machine's records.
- GNU as rejects a short branch that is out of range rather than widening it; after adding code in the middle of a file expect to change a few `.s` to `.w`. A build that fails leaves the previous ROM in place, so read the build's output before trusting a test run.
- The ROM now holds graphics at `0x180000–0x180FFF`, the arcade's dual-port RAM address: `md_state.lua` ignores accesses made by the hardware layer itself (PC from `0x040000`).
- **Sprite tiles are stored twice in the ROM**: singly at `0x080000` (128 bytes each) and as vertical pairs at `0x100000` (256 bytes per pair), because a 16×32 Mega Drive sprite needs its eight patterns in one run, column by column. Cache keys are the tile code for singles and 3072 + pair number for pairs.
- **The sprite table is built at the latch and sent at the next VBlank**, one frame later, with the patterns it needs. Anything else drawn from the same game step should be sent at that VBlank too.
- Sprite table entry 0 is an off-screen dummy heading the chain; real pieces are linked last to first because the arcade's last entry is on top.
- The arcade program never touches memory outside its own RAM and hardware (checked with read and write taps over 7,200 frames), so `0xFF0000–0xFF7FFF` and `0xFFC800–0xFFFFFF` are the hardware layer's.

**Sound**

- Commands: `0x01`–`0x04` stop and reset, `0x05`–`0x30` effects (YM2203), `0x31`–`0x3D` tunes (YM3812, some with YM2203 voices), `0x3E` stop samples, `0x3F`–`0x4F` samples. The game sends them from five places (`0x19C6` and four fixed ones in the coin code).
- **The 6502 sound program is run at build time, not on the console.** Its tick is the YM3812's timer 1, free-running at 1.152 ms (value 244 at a 3 MHz clock): the handler's write that "starts" the timer each tick does not restart it. Modelling a restart made the music 13% slow.
- The driver's RAM never returns to an earlier state (a 16-bit tick counter), so a tune's repeat is found in its write log, not its memory.
- The YM3812 is used as plain two-operator FM (no waveform select, no rhythm mode) and runs at 3 MHz, the YM2203 at 1.5 MHz: sample rates 41,667 Hz and 20,833 Hz against the YM2612's 53,267 Hz.
- **Loading the Z80:** copy the program with the bus held and reset released, then assert reset, release the bus, release reset. Copying while reset was asserted left the Z80 running garbage in MAME.
- The Z80 and the 68000 both write the YM2612. The 68000 takes the bus for its writes and leaves the address port on `0x2A` before giving it back, so a sample byte the Z80 was about to write still lands in the DAC.
- The sound conversion takes about two and a half minutes and is cached beside the output ROM (`cache/`), keyed by the two ROMs and the two source files.
- Audio can be measured, not heard: `-wavwrite` in MAME and `tools/analysis/compare_audio.py`. Say so when reporting; do not describe how it sounds.

**Tooling**

- MAME's sampled program counter is one instruction ahead: a wait loop's address range must extend one instruction past its last branch, or the loop's time is counted as work.
- The BAC06 and control registers are not memory shares in MAME; `dec0_trace.lua` taps the writes. The tilemaps, scroll tables, palette, work RAM and sprite RAM are shares.
- Capstone has no HuC6280 mode. Disassemble the second processor's code with MAME's debugger (`dasm file,address,length,1,sub` from Lua, with `-debug -debugger none`).
- Capstone invents operands when its buffer is too short; always give it 10+ bytes.
- MAME's Lua does not expose the Mega Drive's VRAM; `md_trace.lua` rebuilds VRAM from decoded writes.
- `md_trace.lua` counts sprite limits against H40's 20 per line and 320 pixels whatever the picture width.
- Scripted play is blind. Read the contact sheet before quoting a number: in the reference run the player stands against a step for most of stage 2.
