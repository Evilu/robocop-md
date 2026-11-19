# Every level: the arcade against the Mega Drive build

A first pass over the whole game with the save states of `docs/05-save-states.md`. Each scene was loaded from its state on the arcade board and on the build of 2026-11-19, played for 3,600 frames by the same blind script with the energy held full, and snapshotted every 300 frames (`tools/compare_levels.sh`). The stage clear and the ending were reached by writing the game mode. Each scene was also built as a self-starting ROM and captured in ares.

What this pass is and is not:

- It is the opening screens of each stage. The script walks into the first obstacle in most of them. Bosses, the later parts of each stage, a second player and continues were not seen.
- Pictures were compared by eye on the sheets; speed was counted from the game's step counter (`0xFF800A`).
- Sound was not compared.
- The first pass is below as it was found. What has been fixed since is in the last section, with what is still wrong.

## Summary

| Scene | Stage | Loads and plays (MAME) | In ares | Worst fault |
|---|---|---|---|---|
| 0 | 1 street | yes | yes | (the reference; see README) |
| 1 | 2 back streets | yes | yes | sprites and scenery change colour |
| 2, 5 | bonus | yes | yes | runs at about half speed |
| 3 | 4 scrap yard | yes | yes | the player is drawn in the wrong colours |
| 4 | 3 warehouse | yes | yes | the player is drawn in the wrong colours; walls grey |
| 6 | 5 plant | yes | yes | sprite colours; slow |
| 7 | 6 tower | yes | yes | sprite colours |
| 8 | 7 upper floors | yes | yes | sprite colours; walls bluer |
| ending | | plays through | not run | the picture is missing and the staff roll does not scroll |

No scene crashed or hung, and `stray_access.csv` was not run on them: that check is still owed for every scene after the first.

## Speed

Game steps over the same 3,300 frames, from each scene's state:

| Scene | Arcade | Mega Drive | Mega Drive / arcade |
|---|---|---|---|
| 0 stage 1 | 1,650 | 1,501 | 91% |
| 1 stage 2 | 1,650 | 1,518 | 92% |
| 3 stage 4 | 1,650 | 1,335 | 81% |
| 4 stage 3 | 1,650 | 1,516 | 92% |
| 6 stage 5 | 1,649 | 1,383 | 84% |
| 7 stage 6 | 1,650 | 1,517 | 92% |
| 8 stage 7 | 1,650 | 1,603 | 97% |

Frames here are each machine's own (57.44 a second on the arcade, 59.92 on the console), so in real time the port is about 4% better than each figure. The scrap yard and the plant are the slow ones.

**The bonus stage runs at about half speed.** Its clock went from 29 to 8 in 1,500 arcade frames and from 30 to 19 in 1,500 Mega Drive frames. The step counter does not show it (it counts every frame in this scene on both machines), so the cause is not yet known: this scene scrolls a sight across the whole screen and may be redrawing far more than a stage does.

## Colours

**Sprite palettes are the main fault of every stage after the first.**

- The player is drawn in another sprite's colours in the scrap yard and the warehouse (red, blue and black where the arcade has silver), from the first frame of play, in MAME and in ares. In stage 2 and the plant he flickers between right and wrong.
- The police car at the start of stages 3 and 4 is orange (arcade: black and white).
- Barrels and crates change colour from one snapshot to the next in stage 2 (red, blue, orange for one red barrel).
- Enemies in the tower stages are grey or black where the arcade has colour.

The hardware layer gives sprite palette lines 0 and 1 to the two palettes that cover most sprites in the frame and makes the rest borrow the nearer one. Stage 1 gets by on that. The later stages show more palettes at once, and the count changes from frame to frame, so who owns a line changes too: the player has no fixed claim on one.

**Scenery.**

- The warehouse walls are grey-green (arcade: dark green) and the upper floors of the tower blue-green (arcade: green). Each layer has one palette line; these stages spread their walls over more palettes than stage 1.
- Stage 2 has a purple cast in the brickwork and floor.
- The plant's sky is right, but in ares its blue fills the border around the picture: colour 0 of line 3 is the backdrop.

**Text.**

- `CONTINUE?`, `INSERT COIN`, `GAME OVER` and the count-down are drawn in the stage's colours and cannot be read over the scrap yard, the plant or the tower. In the scrap yard the score and clock are brown.
- The `POWER` bar is grey in the scrap yard (arcade: blue).

## Things drawn wrong or not at all

- **Ending.** The arcade shows a picture (the car at night) on the left and scrolls the staff roll up the right. The port shows no picture, the text does not scroll smoothly: lines pile up and stay, and stale text remains on the high-score page that follows. The text layer's scroll registers are not followed, and the picture's layer is not shown on this screen.
- **Stage clear.** On the arcade the screen goes black and shows `PLAYER 1 READY?`. On the port the words are drawn over the stage that was just left, and the frame before shows the skyline without the street.
- **Story pages** (shown when a coin is in and start is not pressed at once: pictures with text). MAME shows all of them. In ares the first page shows its text without the picture and the second was black; later pages were drawn, one with `READY?` written over the picture.
- **HUD.** In ares the plant showed no score, clock or weapon box in the capture taken during `CONTINUE?`.
- **Stage 1, with a state loaded:** nothing new.

## Not looked at

- Bosses and everything past the first obstacle of each stage.
- Sprite drop-outs per scene (the 16 per line limit), which the snapshots suggest in the plant and the tower's crowds but which were not counted.
- Hit detection outside stage 1. The model compared equal on stage 1's captures only.
- Sound in any scene but the first.
- Scene 9 and a second loop.

## Order to fix in

1. Sprite palette lines: a fixed line for the player, and a choice that does not change owner every frame.
2. The bonus stage's speed, then the scrap yard's and the plant's.
3. Text colours over a stage (the two reserved colours are not enough for red, white and yellow text).
4. The ending and the stage-clear screen: text layer scroll, and blanking the stage behind a text screen.
5. Scenery colours in the warehouse and the tower.
6. Run `md_state.lua` on every scene for stray accesses, and the hit detection capture on at least one later stage.

## Second pass: what was fixed, and what is left

Build of 2026-11-20, same method. Checked in MAME on every scene from its save state, with the stage clear forced in each, and each self-starting scene ROM was run in Genesis Plus GX (headless, one frame looked at per scene). **The ares check of this build is still owed**: the captures came back black for every ROM, the old build included, because the Mac's screen was locked.

**Fixed**

- **The player's colours.** Sprite palette 0 is the player's in every scene. It now owns palette line 0 as it is. Every other sprite is recoloured, pen by pen, onto line 1, whose 15 colours are chosen from the palettes in use (or onto line 0 when that fits a palette better). On the arcade 4 to 7 sprite palettes are on screen at once with about 40 distinct colours between them, and the sprite palettes are loaded once per stage and never change.
- **Barrels, cars and crates changing colour**: gone with the above; a line no longer changes owner from frame to frame.
- **The bonus stage's speed**: 84 frames to a tick of its clock against the arcade's 72 (it was 131). The cause was not the load but its order: the game hands its sprite list to the VBlank handler through a flag, and skips its own logic for a frame whenever the handler finds the list late. With the list translated inside the handler, one frame in three ran late. The list is now translated while the game waits for the frame, and shown at most every second frame.
- **Stage clear**: the screen goes black and shows `PLAYER 1 READY?`. A palette that stays black for eight updates gives the scene up, so the text can have a plane.
- **Ending**: the picture is shown and the staff roll scrolls. The text follows the text layer's scroll register, on a plane or as sprites.
- **Stray accesses**: none in any scene through a forced stage clear, and the game never writes into the hardware layer's RAM (taps on `0xFF0880–0xFF0FFF`, `0xFF1040–0xFF1FFF` and `0xFFD000` up).

**Speed now** (game steps against the arcade's over 2,700 frames from each state; the runs differ in what the script meets, so a few points either way mean nothing):

| Scene | Before | Now |
|---|---|---|
| 0 stage 1 | 91% | 93% |
| 1 stage 2 | 92% | 92% |
| 3 stage 4 | 81% | 82% |
| 4 stage 3 | 92% | 94% |
| 6 stage 5 | 84% | 65–75% |
| 7 stage 6 | 92% | 92% |
| 8 stage 7 | 97% | 99% |

The plant is the slow one and got slower: the game's own work there is 127,000 cycles a step (profile of the build, `tools/mame/md_profile.lua`), half the console's budget before the hardware layer does anything, and recolouring sprite patterns costs about 8,000 cycles each.

**Still wrong**

- Sprites other than the player share 15 colours. Enemies are duller than on the arcade, and some take a red or grey cast until the palettes they share a line with settle (seen in stages 2, 3, 5 and 6).
- A new sprite palette appearing costs a pause of a frame or two while line 1 is chosen again and the patterns on screen are recoloured.
- HUD colours in the scrap yard (clock brown, power bar grey). Text over a stage still has two colours of its own; `CONTINUE?` and `GAME OVER` are hard to read over the plant and the tower.
- Staff roll: lines are sometimes cut short for a moment as they scroll in (text blocks are redrawn four per update, twenty at most).
- Scenery colours in the warehouse and the tower's upper floors.
- The plant's speed.
- Not looked at: bosses, anything past the first obstacle of each stage, the story pages in ares, sound.

