# Picking a level: how it was planned and built

The port could only be tested as far as a blind script could walk: stage 1 and the first screens of stage 2. This document is the record of how that was opened up, from the question "where does the game keep its level?" to `build_md.py --scene 6`. It covers the reasoning and the dead ends as well as the result. `docs/05-save-states.md` is the reference for the mechanism itself; `docs/06-levels-arcade-vs-md.md` is what the mechanism found.

Everything here was measured on MAME 0.289 (`robocop`, and the Mega Drive build under `genesis`), ares v148 and Genesis Plus GX.

## The problem

Three things were wanted, in this order:

1. Start the **arcade** game in any level, to have something to compare with.
2. Start the **Mega Drive build** in the same level, at the same point of the game.
3. Do the second in **ares**, which takes no scripted input and cannot load MAME's save states.

A fourth turned up on the way: get from a level to what follows it (the stage-clear screen, the next level, the ending) without playing.

## Plan

The plan rested on one fact about the port: it runs Data East's own program on the arcade's own work RAM, at the same addresses. Whatever selects a level on the arcade selects it on the console, with no change.

So the work was on the arcade first:

1. Find the level variable by comparing work RAM between two stages.
2. Find how the program uses it, from the instructions that reference it.
3. Force it at the right moment and see whether the stage loads.
4. Save a MAME state once it has, on each machine.
5. For ares, move the forcing from a Lua script into the ROM, behind a build option, so the normal ROM is untouched.

Alternatives that were set aside:

- **Playing there and saving a state.** The script cannot play; a person would have to, once per build of the port, since a state of the port dies with every rebuild.
- **A cheat file.** MAME's cheat database may have a stage select for this set, but it would be an address taken on trust, for the arcade only, and would explain nothing.
- **A level-select screen in the game.** Wanted eventually, but it needs text, input handling and a decision about where it lives in the attract sequence. A build option needed 20 instructions.

## Step 1: finding the variable

`tools/mame/level.lua` (then called `ram_dumps.lua`) played the arcade for 12,000 frames with the energy held full and wrote work RAM every 300 frames, with a snapshot beside each dump. The contact sheet showed stage 1 in dumps 1 to 12 and stage 2 from dump 14.

Bytes with one value in every stage 1 dump and another in every stage 2 dump: **52**. Most are positions, scroll limits and object state. Three looked like counters:

| Address | Stage 1 | Stage 2 |
|---|---|---|
| `0xFFB21D` | 0 | 1 |
| `0xFFB218` | 1 | 2 |
| `0xFF9838` | 0 | 1 |

## Step 2: the first attempt, and why it failed

`0xFFB21D` was held at 1 to 8 for the first 400 frames of a game, eight runs side by side.

All eight loaded stage 1.

The program was searched for the three addresses. `0xFFB218` is referenced 42 times, `0xFFB21D` 11 times, `0xFF9838` 5 times. The eleven include this, at `0x3ECA`:

```
lea     $3ee2(pc), a0
moveq   #0, d0
move.b  $ffb21d, d0
move.b  (a0, d0.w), $ffb218
rts
```

and this, at game start (`0x3866`):

```
clr.b   $ffb21d
jsr     $3eca(pc)
```

That explained the failure. `0xFFB21D` is an index, `0xFFB218` is the stage number looked up from it, and the rest of the program reads the stage number. At game start the index is cleared and the stage number derived in consecutive instructions; a value written once a frame from outside never gets between them.

The table at `0x3EE2` is `01 02 FF 04 03 FF 05 06 07 08`.

## Step 3: the second attempt

Both bytes were held: the scene index, and the table's entry for it. Ten runs, one per table entry.

Nine loaded nine different scenes: seven stages and the shooting range twice. The table reads as the game's running order, with `FF` for the bonus stage and stage 4 played before stage 3.

The tenth, scene 9, hung: the step counter stopped at 410 with a black screen. It is not a place a game can start.

## Step 4: leaving a level

The index has 1 added in three places. One of them is in the main loop:

```
cmpi.b  #7, $ffb235
bne     $35b8
cmpi.b  #7, $ffb218
bcs     $3762
```

Game mode 7 is "stage cleared". Below stage 7 the program goes on to the next scene; at stage 7 it runs the ending first. Writing 7 to `0xFFB235` during play gave the `PLAYER 1 READY?` screen and the next stage from scene 0, and the ending, the staff roll and the high-score entry from scene 8. That is also how scene 9 is reached: it is what follows the ending.

## Step 5: the same on the Mega Drive

Nothing had to be found again. `level.lua` looks for the arcade's input names and, not finding them, uses the pad's (`A` for the coin, `Start`, `B`, `C`); the three addresses and the table address are the same. The first run of the port with scene 3 forced loaded the scrap yard.

`tools/level_states.sh` makes a state per scene on each machine at frame 420, and `tools/compare_levels.sh` loads them in pairs.

## Step 6: ares, and the build option

ares was the reason to put the mechanism in the ROM. The requirements:

- The normal build must be byte for byte what it was.
- No new entry point in the arcade program, no new patch site.
- The game must believe a coin went in and start was pressed.

The pad routine already runs once a frame from VBlank and already writes the arcade's input bytes. The forcing was assembled into its end, under a conditional:

```
    .if BOOT_SCENE < 255
    move.l  hal_frames, d0
    cmpi.l  #400, d0
    bhi.s   6f
    cmpi.w  #60, d0
    blo.s   6f
    cmpi.w  #66, d0
    bhs.s   3f
    bclr    #4, IO + 3
3:  cmpi.w  #120, d0
    blo.s   4f
    cmpi.w  #126, d0
    bhs.s   4f
    bclr    #2, IO + 3
4:  cmpi.w  #100, d0
    blo.s   6f
    move.b  #BOOT_SCENE, SCENE
    move.b  SCENE_STAGES + BOOT_SCENE, STAGE
6:
    .endif
```

The frame numbers are the Lua script's: coin for frames 60 to 65, start for 120 to 125, both bytes written from frame 100 to 400. `BOOT_SCENE` reaches the assembler as a symbol from `tools/build/build.py`, 255 when nothing was asked for. The stage number is read from the game's own table, so the build holds no copy of it.

First it was an environment variable (`BOOT_SCENE=3`). It became an argument, `--scene N`, which checks the range, sets the variable, and names the output `robocop_md_scene<N>.md` so a test ROM is not mistaken for the game.

The normal build's hardware layer was the same size before and after (8,676 bytes at the time).

## What went wrong on the way

- **One byte was not enough** (step 2). Found by reading the eleven references rather than by trying more values.
- **The first ares captures of the scene ROMs were black.** Two causes, neither in the ROM. The captures were taken before the stage appeared: with a coin in and no start press at once, the game shows several story pages first, and the stage comes about 18 seconds after power-on. The scripted runs had always pressed start at once and had never shown those pages. And ares draws nothing while the Mac's screen is locked.
- **Scene 9** cannot be forced at game start (step 3).
- **A state of the port is only good for the ROM it was made with.** The first comparison after a rebuild loaded stale states; `level_states.sh` is now run after every build.

## What it is used for

| Need | Command |
|---|---|
| A save state per scene, both machines | `tools/level_states.sh test/roms/md/robocop_md.md` |
| Arcade against port, every scene | `tools/compare_levels.sh test/roms/md/robocop_md.md 3600` |
| One scene, with a stage clear at frame 300 | `LOAD=scene8 POKE="ffb235=07@300" tools/level.sh arcade <dir>` |
| A ROM that starts in a scene (ares, other emulators, a console) | `build_md.py robocop.zip --scene 6` |

The first comparison made with it is `docs/06-levels-arcade-vs-md.md`: every scene loads and plays on the port, and the faults that only later stages show (the player drawn in an enemy's colours, the bonus stage at half speed, an ending without its picture) were found and mostly fixed in the two days after.

## Limits

- A scene starts at its beginning. A boss, or a screen with a fault half-way through a stage, needs a state saved from a run that got there (`SAVE=name@frame`) or a person at the pad.
- The scene ROM takes no part in the game after frame 400. Nobody holds its pad: in ares the player stands still until the game is over.
- The frame numbers assume the attract sequence as it is. If the port's boot ever takes longer than 60 frames to accept a coin, the scene ROM will miss it.
- Not built: a level select inside the game, for a person with a pad. The three bytes are all it would need to write.
