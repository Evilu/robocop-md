---
name: disassemble-68k
description: Read, disassemble and decompile the programs in this project (the robocop arcade 68000 program, its HuC6280 protection program, the RoboCop MD demo) with the repo's capstone, Ghidra and MAME debugger tools. Use when asked what a routine does, where the game touches hardware, to find a routine, or to extend code coverage.
---

# Disassemble the programs

## Inputs

`python3 -I tools/prep_roms.py analysis/roms analysis/work analysis/mame/roms` builds the flat images: `robocop_prg.bin` (256 KB, the two interleaved ROM pairs joined), `robocop_sub.bin` (the HuC6280's 512-byte boot ROM), `robocop_snd.bin` (6502), the graphics regions as MAME lays them out, and `robocop_md.bin` (the demo). Program ROMs are split into even and odd bytes on disk; always work from the prepared images.

## Quick look at an address

```sh
analysis/venv/bin/python3 -I tools/analysis/dis68k.py analysis/work/robocop_prg.bin 1002:60
```

If the listing is nonsense, the address is mid-instruction or in data: try the neighbouring even addresses, or start from a known entry point.

## Static code and hardware map

```sh
analysis/venv/bin/python3 -I tools/analysis/codemap.py analysis/work/robocop_prg.bin analysis/out/robocop_map --tables
```

Follows the code from the vectors and writes `functions.tsv` (call targets), `code.tsv` (runs of decoded code) and `access.tsv` (every instruction with an absolute hardware address, by region). `--tables` also follows tables of long pointers and can take data for code: check a surprising entry with `dis68k.py`.

## Ghidra output

`analysis/out/<image>/functions.tsv` (address, size, callers, callees) and `decomp.c`. Regenerate with `tools/ghidra/analyze.sh <ghidra dir> analysis/work/robocop_prg.bin dec0 - analysis` then `reanalyze.sh` (see `tools/README.md`); set `JAVA_HOME` to a Java 25 runtime (Ghidra 12.2 refuses 21); with Homebrew the Ghidra directory is `/opt/homebrew/opt/ghidra/libexec`.

## How the arcade code is laid out

- Globals are addressed absolutely (`$ff8dd5.l`), not through a base register. Work RAM is `0xFF8000–0xFFBFFF`, sprite RAM `0xFFC000–0xFFC7FF`, initial stack `0xFFC000`.
- Calls are `jsr d16(pc)` followed by a `nop` (the linker's padding for a long call), or `jsr abs.l`. Jump tables are tables of long pointers reached with `lea table(pc),a0 / movea.l (a0,d0.w),a0 / jsr (a0)`.
- Reset `0x100` (every unused vector points there too), cold start `0x122`, VBlank handler `0x1002` (level 6), main loop `0x35b8`.
- Frame waits: `0x17ba` waits for one VBlank, `0x17e8` for two. Gameplay uses the second: the game logic runs every other frame.
- Hardware by absolute address: `0x180000–0x180FFF` dual-port RAM shared with the HuC6280 (odd bytes), `0x240000`, `0x246000`, `0x24C000` the three BAC06 tilemap chips, `0x30C000` inputs, `0x30C010` control (priority, sprite latch, sound command, interrupt acknowledge), `0x310000` / `0x314000` palette, `0xFFC000` sprite RAM.

## The HuC6280

The protection processor's real program is not in its own ROM: the 68000 uploads 924 bytes from ROM `0xD772` through the dual-port RAM at boot, and the HuC6280 runs them at `0x2202`. Capstone has no HuC6280 mode; disassemble with MAME's debugger:

```sh
cd analysis/mame
mame robocop -rompath roms -video none -sound none -debug -debugger none -seconds_to_run 5 \
  -autoboot_script <script that runs  manager.machine.debugger:command("dasm sub_ram.asm,2000,400,1,sub")  after 120 frames>
```

In its address space the dual-port RAM is at `0x4000` (68000 address `0x180000 + 2 × offset + 1`) and its own RAM at `0x2000`.

## Coverage is incomplete

Static tools find code by following direct calls. Routines reached only through tables may be missed, and `--tables` may add data. To find more:

1. Use the profiler's addresses (`analysis/mame/*_prof/profile_leaf.csv`, `profile_incl.csv`): they are code that really ran. `profile_incl.csv` keys are call targets; negative keys are indirect call sites.
2. Use the access map (`analysis/mame/*_access/access_pcs.csv`): every instruction that really touched hardware.

Never conclude that a region is data, or that the game never touches some hardware, from a function list alone.

## Finding things

- Scan for an absolute address as a 4-byte big-endian value at even offsets to find hardware accesses (data can match by chance; `0x00180000` also appears as a plain number in tables; check the instruction).
- For "what runs every frame", start at the main loop `0x35b8` and the VBlank handler `0x1002`.
- For "what is slow", use the profile, not intuition.
- The RoboCop MD demo is GCC output on SGDK: arguments on the stack, RAM at `0xE0FF0000`. Its code shares nothing with the arcade.

Disassembly and decompiler output are game code: keep them in `analysis/`, quote only short excerpts in docs.
