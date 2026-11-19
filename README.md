# RoboCop MD

A port of Data East's 1988 arcade game *RoboCop* to the Sega Mega Drive / Genesis.

The plan is the one used for [Cadillacs and Dinosaurs MD](https://github.com/Evilu/cadillacs-and-dinosaurs-md): the Mega Drive runs Data East's own 68000 program, and only the hardware layer underneath it is replaced (video, palettes, input, sound, the protection processor, memory map). The goal is the whole game, as close to the arcade as the console allows.

**Status: stage 1 plays in emulators with sprites, backgrounds, the HUD, music, effects and samples.** The game boots, shows its attract sequence, takes a coin and plays stage 1 and into stage 2, and enemies hit the player through our replacement for the board's protection processor. The picture is checked in MAME and ares. The sound is a first version, checked by measurement in MAME only. Later stages have not been played.

What the research found, in short:

- The arcade's 68000 runs at 10 MHz but waits for more than half of every game step; the game's real work is about a third of what a Mega Drive has.
- The game's RAM sits inside the console's RAM at the same addresses, and the whole game is about 1.3 MB: no mapper is needed.
- The board's protection is a second processor (a HuC6280) that runs hit detection and decides the order of the main loop. Its 924-byte program is stored in the 68000 ROM, so it can be read and rewritten; our 68000 version gives the same results as the original on every game step we captured.
- The picture is 256 pixels wide, which the console has a mode for. What does not fit is sprites per line in crowded moments, the 16 extra lines of height, and about 25 arcade palettes into 4.

## ROMs

This repository contains no ROM data. To build, you supply your own dump of the arcade ROM set: you bring a copy of the game you own, and the build turns it into a Mega Drive ROM on your own machine.

## What you need

- **Your own dump of the arcade game:** MAME's `robocop` set (*Robocop*, World, revision 4), as `robocop.zip` or as a folder of its files. The build checks the four program ROMs, the eighteen graphics ROMs, the sound program and the sample ROM by CRC32 and tells you which one is missing or wrong. Other revisions and regions (`robocopw`, `robocopj`, `robocopu`, the bootlegs) are not supported.
- **Python 3.9 or newer**, with `capstone` (`requirements.txt`).
- **GNU binutils for the 68000** (`as`, `ld`, `objcopy`, `nm`):
  - macOS: `brew install m68k-elf-binutils`
  - Debian / Ubuntu: `sudo apt install binutils-m68k-linux-gnu`
  - other: any 68000 binutils; set `M68K_PREFIX` to the tool prefix (for example `M68K_PREFIX=m68k-linux-gnu-`).

## Build

```sh
git clone https://github.com/Evilu/robocop-md.git
cd robocop-md
python3 -m venv .venv
.venv/bin/python3 -m pip install -r requirements.txt
.venv/bin/python3 build_md.py /path/to/robocop.zip
```

The ROM is written to `out/robocop_md.md` (4 MB, no mapper); a second argument chooses another path. The first build takes about three minutes, most of it converting the sound; the result is kept in `out/cache` and later builds take seconds. The built ROM contains Data East's program, graphics and sound: do not share it.

Pad: **A** inserts a coin, **Start** starts, **B** attacks, **C** jumps. Run in MAME and ares (in ares, map the Mega Drive pad first: it has no default mapping). Do not try it on a real console yet.

## Known issues

Everything here was seen in MAME or ares in the attract sequence, stage 1 and the first screens of stage 2. Every stage, the bonus stage and the ending have been loaded and compared with the arcade; what was found, what has been fixed and what is left is in [docs/06](docs/06-levels-arcade-vs-md.md).

**Sound**
- First version, converted mechanically from the arcade's three sound chips: the notes are right, but instruments and balance have not been tuned by ear.
- The music has five voices where the arcade has up to nine; some notes are dropped.
- One sample at a time.

**Missing**
- Only one player has been tried.

**Speed**
- Stages run at 82% to 99% of the arcade's speed; stage 5 at about 70%.
- A scene change blanks the screen for a fraction of a second while the new scene is drawn.

**Colours**
- The street is drawn with 13 colours where the arcade has 40: close shades merge.
- The player has a palette line to himself; every other sprite shares 15 colours chosen from those in use, so enemies and effects are duller than on the arcade and sometimes off-colour.
- In-game text shares the street's colours and two of its own.

**Graphics**
- The top 8 and bottom 8 lines of the arcade picture are cut off; the score is on the very top line.
- When more than 16 sprites share a line, or the HUD and the game's sprites together exceed 64, some disappear for a frame.
- In the stages only 20 blocks of text fit, enough for the HUD; longer messages over a stage would be cut.
- Title: the white flash lasts longer than on the arcade and some of the text is missing during it; at the end of the title the static shows in a band behind the whole logo, where the arcade shows it only inside the letters.
- A scene change in the attract sequence can show a few stray blocks for a frame (seen in ares).

**Hardware**
- Never run on a real console or flash cart. Do not try yet.

## Development

Changes go through branches and pull requests: one branch per change, a pull request into `main`. The research behind the port and the measurements are in `docs/`; how to prepare the ROMs, trace the arcade and check a Mega Drive ROM is in `tools/README.md`.

- [Data East MEC-M1 vs Mega Drive architecture](docs/01-architecture-dec0-vs-mega-drive.md)
- [RoboCop: arcade vs the RoboCop MD demo](docs/02-robocop-arcade-vs-md-demo.md)
- [RoboCop, measured](docs/03-robocop-measured.md)
- [Port plan](docs/04-port-plan.md)
- [Save states for every level](docs/05-save-states.md)
- [Every level: arcade vs the Mega Drive build](docs/06-levels-arcade-vs-md.md)
- [Picking a level: how it was planned and built](docs/07-level-select.md)
- [Analysis tools](tools/README.md)

## Rights

All rights reserved by their respective owners. I do not own anything related to *RoboCop* or the Data East hardware: the game, its code, graphics, sound, characters and trademarks belong to their rights holders (the arcade game is by Data East, under licence from Orion Pictures; the *RoboCop* property is owned by Metro-Goldwyn-Mayer). Sega and Mega Drive are trademarks of Sega. *RoboCop MD* by Boca's Retro Stuff is the work of its authors and is used here only as a technical reference. This is a non-commercial fan research project with no affiliation with or endorsement by any of them.

## Credits

This project stands on other people's work. Thank you to:

**The game**
- Data East, for *RoboCop* (1988) and the MEC-M1 arcade hardware.
- Orion Pictures, Paul Verhoeven, Edward Neumeier and Michael Miner, for the 1987 film the game is based on.

**Emulators and tools we run**
- The [MAME](https://www.mamedev.org/) team, and Bryan McPhail in particular for the Data East 16-bit driver (`dec0`), with hardware notes by Guru: it is our reference for how the board behaves, and MAME runs every trace and test in this project.
- Michael Pavone, for [BlastEm](https://www.retrodev.com/blastem/), and the [ares](https://ares-emu.net/) team, for the emulators test builds are played in.
- The NSA's [Ghidra](https://ghidra-sre.org/) team, the [Capstone](https://www.capstone-engine.org/) disassembler authors, and the [GNU Binutils](https://www.gnu.org/software/binutils/) maintainers.

**Hardware documentation and research**
- Charles MacDonald, for the Mega Drive hardware documents.
- [Plutiedev](https://plutiedev.com/), [md.railgun.works](https://md.railgun.works/), [Raster Scroll](https://rasterscroll.com/), [Sega Retro](https://segaretro.org/) and the [SpritesMind](https://gendev.spritesmind.net/) community, for Mega Drive programming knowledge.
- Stéphane Dallongeville, for [SGDK](https://github.com/Stephane-D/SGDK), whose source and documentation we learned from.

**Fan projects we learned from**
- [Boca's Retro Stuff](https://bocasretrostuff.itch.io/robocop-md), for the *RoboCop MD* demo, and LukeMcQueen for its music: our reference for what this game can look and sound like on the Mega Drive.
- JOTD, for [Bad Dudes for Amiga](https://github.com/jotd666/baddudes): the same Data East board, ported by keeping the original 68000 code.
- Mauro Xavier and the *Final Fight MD* team, whose port set the bar for arcade games on the Mega Drive.
- Our own [Cadillacs and Dinosaurs MD](https://github.com/Evilu/cadillacs-and-dinosaurs-md), whose method and tools this project started from, and everyone credited there.

If we have used your work and missed you here, please open an issue and we will add you.
