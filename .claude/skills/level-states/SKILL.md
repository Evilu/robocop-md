---
name: level-states
description: Start the arcade game (robocop) or the Mega Drive build in any scene, make and load MAME save states for each level, skip to the next scene, and compare the two machines level by level in MAME and ares. Use when asked to test, compare or debug a level other than stage 1, to reach the bonus stage or the ending, or to make save states.
---

# Level save states

`docs/05-save-states.md` explains how this works; `docs/06-levels-arcade-vs-md.md` is the list of faults found with it. Run from the repository root. Everything is written under `analysis/`, which git ignores: save states hold the game's program and are never committed.

## The three handles

| Address | Meaning |
|---|---|
| `0xFFB21D` | Scene index, 0 to 9. The game clears it at game start and adds 1 at each stage clear |
| `0xFFB218` | Stage number: `ROM[0x3EE2 + scene]`. `0xFF` is the bonus stage |
| `0xFFB235` | Game mode. Writing 7 during play is "stage cleared": the game goes to the next scene, or to the ending from scene 8 |
| `0xFFB242` | Energy; `0x28` is full. Held every frame it makes the player invulnerable |

Scenes: 0 stage 1, 1 stage 2, 2 bonus, 3 stage 4, 4 stage 3, 5 bonus, 6 stage 5, 7 stage 6, 8 stage 7, 9 after the ending (hangs if forced at game start).

The same addresses work on the Mega Drive build: it runs the same program on the same work RAM.

## Make the states

```sh
tools/level_states.sh test/roms/md/robocop_md.md            # all ten scenes, both machines
tools/level_states.sh test/roms/md/robocop_md.md "3 4"      # some
```

Writes `analysis/mame/states/robocop/scene<N>.sta` and `analysis/mame/states/genesis/scene<N>.sta`, taken at frame 420: coin at 60, start at 120, scene and stage forced from frame 100 to 400. **Remake the Mega Drive states after every build**: a state holds the hardware layer's RAM and VRAM, and the ROM under it has changed.

## Run one scene

```sh
LOAD=scene3 TRACE_FRAMES=3600 HOLD="ffb242=28" tools/level.sh arcade analysis/mame/level_runs/a3
LOAD=scene3 TRACE_FRAMES=3600 HOLD="ffb242=28" tools/level.sh test/roms/md/robocop_md.md analysis/mame/level_runs/m3
```

`tools/mame/level.lua` reads its settings from the environment:

- `LEVEL=n` starts a game in scene n instead of loading a state.
- `LOAD=name`, `SAVE=name@frame[,name@frame]`: states by name. Save deeper states (a boss, a screen with a fault) from a run that reached them.
- `POKE=ffb235=07@300` clears the stage at frame 300: the way to the stage-clear screens, the next scene and, from scene 8, the ending and staff roll.
- `HOLD`, `PLAY=none`, `SNAP_EVERY`, `DUMP_RAM=1`.
- Output: snapshots, `level.csv` (scene, stage, game steps, energy, player position, scroll, objects) and `mame.log`.

## Compare all levels

```sh
tools/compare_levels.sh test/roms/md/robocop_md.md 3600
```

One sheet per scene in `analysis/out/levels/scene<N>.png`, arcade above the Mega Drive, and the two `level.csv` files side by side. Read the sheets. The machines drift apart within seconds (the game's random numbers depend on timing, and the port is slower): compare what is drawn and how fast the step counter runs, not positions.

## In ares

ares takes no scripted input and cannot load MAME's states. Build a ROM that starts by itself in a scene:

```sh
BOOT_SCENE=3 analysis/venv/bin/python3 -I build_md.py robocop.zip test/roms/md/robocop_md_scene3.md
tools/check_ares.sh test/roms/md/robocop_md_scene3.md analysis/mame/ares_scene3 12 3
```

The ROM presses coin and start itself and forces the scene; the stage appears after the story pages, about 18 seconds in. Nobody holds the pad, so the player stands still and dies. Never hand a `BOOT_SCENE` ROM out as the game.

## Finding a new variable

`DUMP_RAM=1` writes work RAM beside each snapshot. Bytes that hold one value through one stretch of play and another through the next are found by comparing the dumps; then search the program for instructions that use the address (`tools/analysis/dis68k.py analysis/work/robocop_prg.bin <addr>:<count>`). That is how the scene index was found.

## Limits

- Scripted play is blind: in most scenes the player walks into a wall or a lift and stays there. A sheet shows the first screens of a stage unless a deeper state was saved.
- Bosses have not been reached in any scene but the first.
- A state made by one MAME version may not load in another.
