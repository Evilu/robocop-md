"""Survey the arcade's sound commands by running each one alone in the 6502 emulator.

usage: sound_survey.py <robocop_snd.bin> <robocop_oki.bin> [seconds=4]
For every command value prints which voices it uses: YM3812 channels keyed, YM2203
FM channels keyed, SSG channels given volume, OKI samples started, how many chip
writes it makes, and whether it is still making them at the end (music, or a loop).
"""
import sys
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'build'))
import sound6502


def run(args):
    rom, oki, value, seconds = args
    board = sound6502.Board(rom, oki)
    board.run_until(0.3)
    board.command(1)
    board.run_until(0.5)
    start = len(board.log)
    board.command(value)
    board.run_until(0.5 + seconds)
    opl, opn, ssg, samples, writes, last = set(), set(), set(), [], 0, 0.0
    for t, kind, reg, v in board.log[start:]:
        if kind == 'l' and reg in (2, 4):
            continue
        if kind == 'c':
            continue
        writes += 1
        last = t
        if kind == 'l' and 0xb0 <= reg <= 0xb8 and v & 0x20:
            opl.add(reg - 0xb0)
        elif kind == 'n' and reg == 0x28 and v & 0xf0:
            opn.add(v & 3)
        elif kind == 'n' and 8 <= reg <= 10 and v & 0x1f:
            ssg.add(reg - 8)
        elif kind == 'o' and v & 0x80:
            samples.append(v & 0x7f)
    return value, sorted(opl), sorted(opn), sorted(ssg), samples, writes, last - 0.5


def main(argv):
    rom, oki = Path(argv[1]).read_bytes(), Path(argv[2]).read_bytes()
    seconds = float(argv[3]) if len(argv) > 3 else 4.0
    with ProcessPoolExecutor() as pool:
        results = list(pool.map(run, [(rom, oki, v, seconds) for v in range(256)]))
    for value, opl, opn, ssg, samples, writes, last in results:
        if not writes:
            continue
        going = 'still going' if last > seconds - 0.25 else f'ends {last:.2f}s'
        print(f'{value:02x}  writes {writes:5d}  {going:12s} OPL {"".join(map(str, opl)) or "-":9s} '
              f'OPN {"".join(map(str, opn)) or "-":3s} SSG {"".join(map(str, ssg)) or "-":3s} '
              f'samples {" ".join(f"{s:02x}" for s in samples[:6])}')
    print(sum(1 for r in results if r[5]), 'commands make sound chip writes')


if __name__ == '__main__':
    main(sys.argv)
