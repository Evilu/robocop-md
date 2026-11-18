# RoboCop MD

A port of Data East's 1988 arcade game *RoboCop* to the Sega Mega Drive / Genesis.

The plan is the one used for [Cadillacs and Dinosaurs MD](https://github.com/Evilu/cadillacs-and-dinosaurs-md): the Mega Drive runs Data East's own 68000 program, and only the hardware layer underneath it is replaced (video, palettes, input, sound, the protection processor, memory map). The goal is the whole game, as close to the arcade as the console allows.

**Status: research.** Nothing builds yet. The arcade machine and the game program have been measured for attract mode, stage 1 and the start of stage 2; the findings and the plan are in `docs/`.

What the research found, in short:

- The arcade's 68000 runs at 10 MHz but waits for more than half of every game step; the game's real work is about a third of what a Mega Drive has.
- The game's RAM sits inside the console's RAM at the same addresses, and the whole game is about 1.3 MB: no mapper is needed.
- The board's protection is a second processor (a HuC6280) that runs hit detection and decides the order of the main loop. Its 924-byte program is stored in the 68000 ROM, so it can be read and rewritten.
- The picture is 256 pixels wide, which the console has a mode for. What does not fit is sprites per line in crowded moments, the 16 extra lines of height, and about 25 arcade palettes into 4.

## ROMs

This repository contains no ROM data. To build, you will supply your own dump of the arcade ROM set: you bring a copy of the game you own, and the build turns it into a Mega Drive ROM on your own machine.

The set is MAME's `robocop` (*Robocop*, World, revision 4).

## Development

Changes go through branches and pull requests: one branch per change, a pull request into `main`. The research behind the port and the measurements are in `docs/`; how to prepare the ROMs, trace the arcade and check a Mega Drive ROM is in `tools/README.md`.

- [Data East MEC-M1 vs Mega Drive architecture](docs/01-architecture-dec0-vs-mega-drive.md)
- [RoboCop: arcade vs the RoboCop MD demo](docs/02-robocop-arcade-vs-md-demo.md)
- [RoboCop, measured](docs/03-robocop-measured.md)
- [Port plan](docs/04-port-plan.md)
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
