# Save states for every level

Until now every measurement covered attract mode, stage 1 and the first screens of stage 2: as far as a blind script could walk. This document is how the other levels were reached, on the arcade board and on the Mega Drive build, and how to keep them as save states.

Everything here was measured on MAME 0.289 with the `robocop` set and the build of 2026-11-19. Tools: `tools/level.sh`, `tools/level_states.sh`, `tools/compare_levels.sh`, `tools/mame/level.lua`. The skill `level-states` has the commands.

## What a MAME save state is

`manager.machine:save("name")` from Lua (or `-statesave`, or Shift+F7 in a window) writes `<state_directory>/<system>/<name>.sta`.

- The file starts with a 32-byte header: the text `MAMESAVE`, a version byte (2), a flags byte, the system's name padded to 18 bytes, and a 4-byte signature computed from the list of saved items. MAME refuses a state whose signature does not match the running driver.
- The rest is one zlib stream. The arcade's state is 182 KB on disk and 8.2 MB inflated; the Mega Drive's 183 KB and 8.9 MB.
- Inside is every item the emulated devices registered: CPU registers, all RAM, the video chips' registers and tables, the sound chips. The arcade's work RAM is a block of 16 KB in host byte order (each 68000 word swapped); in the scene 3 state it starts at offset `0x58D8` of the inflated data.
- A state does not hold the ROM. The Mega Drive build's state is only good for the ROM it was made with: rebuild, and the hardware layer's variables and the VRAM it filled no longer match the code.

A save state made by walking there is the obvious way to keep a level. The script cannot walk that far, so the levels are reached another way and the state saved afterwards.

## Where the game keeps the level

Work RAM was dumped every 300 frames over a run that went from stage 1 into stage 2 (12,000 frames, `DUMP_RAM=1`). 52 bytes hold one value through stage 1 and another through stage 2. Two of them are the level:

| Address | Stage 1 | Stage 2 | References in the program |
|---|---|---|---|
| `0xFFB21D` | 0 | 1 | 11 |
| `0xFFB218` | 1 | 2 | 42 |

The routine at `0x3ECA` ties them together:

```
lea     $3ee2(pc), a0
moveq   #0, d0
move.b  $ffb21d, d0
move.b  (a0, d0.w), $ffb218
rts
```

`0xFFB21D` is an index into the game's list of scenes; `0xFFB218` is the stage number the rest of the program tests. The table at `0x3EE2`:

| Scene | Table | What loads |
|---|---|---|
| 0 | 1 | Stage 1: the street |
| 1 | 2 | Stage 2: the back streets and the pipe works |
| 2 | `FF` | Bonus stage: the shooting range |
| 3 | 4 | Stage 4: the scrap yard |
| 4 | 3 | Stage 3: the warehouse |
| 5 | `FF` | Bonus stage again |
| 6 | 5 | Stage 5: the plant |
| 7 | 6 | Stage 6: the office tower |
| 8 | 7 | Stage 7: the tower's upper floors |
| 9 | 8 | What follows the ending |

The stage numbers are the program's own; stages 3 and 4 are played in the order 4, 3. The names are descriptions of the pictures, not the game's.

The index is cleared at game start (`0x3866`) and has 1 added in three places (`0x3606`, `0x3726`, `0x378A`), each followed by a call to `0x3ECA`.

## Starting in any scene

Holding `0xFFB21D` alone while a game starts does nothing: the game clears it and calls `0x3ECA` in the same breath, and the stage loader reads `0xFFB218`. Holding both does it. `level.lua` presses the coin at frame 60 and start at frame 120, and from frame 100 to 400 writes the scene to `0xFFB21D` and `ROM[0x3EE2 + scene]` to `0xFFB218` every frame. By frame 420 the stage is loaded and play is about to begin; the state is saved there.

Scenes 0 to 8 load this way on the arcade. Scene 9 does not: the step counter stops at 410 and the screen stays black. It is entered only from the ending.

Without the early start press the game first shows several story pages (pictures with text), which the earlier scripted runs never saw because they pressed start at once.

## Leaving a scene

The main loop tests the game mode at `0x36E8`:

```
cmpi.b  #7, $ffb235
bne     $35b8
cmpi.b  #7, $ffb218
bcs     $3762          ; stages 1-6 and the bonus: next scene
...                    ; stage 7: the ending at $1c4c0, then the next scene
```

Writing 7 to `0xFFB235` during play is therefore "stage cleared". From scene 0 the game shows `PLAYER 1 READY?` and loads scene 1. From scene 8 it plays the ending: a picture of the car at night beside the scrolling staff roll, `THE END`, and the high-score entry. `POKE=ffb235=07@300` does this in `level.lua`.

`0xFFB242` is the energy (`0x28` full). Rewritten every frame it keeps the player alive for as long as a run lasts.

## The same on the Mega Drive

The port runs the arcade's program, and the arcade's work RAM sits at the same addresses in the console's RAM. Every address above works unchanged, and so does the script: the only difference is the names of the pad's buttons. MAME's `genesis` driver saves and loads states for a cartridge from a software list as it does for the arcade.

ares is the stricter emulator and takes no scripted input, so for ares the forcing is built into a test ROM: `BOOT_SCENE=n` at build time assembles a few instructions into the pad routine that press coin and start and hold the two bytes for the first 400 frames. The normal build is byte for byte what it was without them.

## What a state is good for, and what it is not

- It starts a level in a second instead of walking there, on both machines from the same point of the game.
- The two machines do not stay together after loading. The game's random numbers come from a counter the frame wait spins, and the port runs fewer game steps a second (see `docs/06-levels-arcade-vs-md.md`). Compare pictures and rates.
- The script still plays blind. In most scenes it walks into the first obstacle; the sheets show the opening screens of each stage. Deeper points need a state saved by hand (`SAVE=name@frame`) from a run that reached them, or a person at the pad.
- Bosses were not reached in any scene after the first.
