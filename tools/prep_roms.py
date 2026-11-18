"""Build flat images from user-supplied ROM sets.

usage: prep_roms.py <roms_dir> <out_dir> [<mame_rom_dir>]
<roms_dir> holds one extracted folder per set: robocop/, robocop_md/.
With <mame_rom_dir>, also writes a robocop/ folder MAME accepts: some dumps carry
the two video PROMs at twice their size, and MAME wants the first half.
"""
import glob
import shutil
import sys
import zlib
from pathlib import Path

PROMS = {'mb7116e.12c': ('mb7116e_a-1.12c', 0x200, 0x86e775f8),
         'mb7122e.17e': ('mb7122e_a-2.17e', 0x400, 0xa5cda23e)}


def interleave(*parts):
    out = bytearray(len(parts[0]) * len(parts))
    for i, p in enumerate(parts):
        out[i::len(parts)] = p
    return bytes(out)


def main(roms, out, mame=None):
    rd = lambda n: (roms / 'robocop' / n).read_bytes()
    out.mkdir(parents=True, exist_ok=True)
    if (roms / 'robocop').is_dir():
        prg = interleave(rd('ep05-4.11c'), rd('ep01-4.11b')) + interleave(rd('ep04-3'), rd('ep00-3'))
        (out / 'robocop_prg.bin').write_bytes(prg)
        (out / 'robocop_sub.bin').write_bytes(rd('en_24_mb7124e.a2'))
        (out / 'robocop_snd.bin').write_bytes(rd('ep03-3'))
        (out / 'robocop_oki.bin').write_bytes(rd('ep02'))
        (out / 'robocop_char.bin').write_bytes(rd('ep23') + rd('ep22'))
        (out / 'robocop_tiles1.bin').write_bytes(b''.join(rd(n) for n in ('ep20', 'ep21', 'ep18', 'ep19')))
        (out / 'robocop_tiles2.bin').write_bytes(b''.join(rd(n) for n in ('ep14', 'ep15', 'ep16', 'ep17')))
        spr = bytearray(b'\xff' * 0x80000)
        for i, n in enumerate(('ep07', 'ep06', 'ep11', 'ep10', 'ep09', 'ep08', 'ep13', 'ep12')):
            blob = rd(n)
            spr[i * 0x10000:i * 0x10000 + len(blob)] = blob
        (out / 'robocop_sprites.bin').write_bytes(spr)
        if mame:
            dest = mame / 'robocop'
            dest.mkdir(parents=True, exist_ok=True)
            for p in (roms / 'robocop').iterdir():
                if p.name in PROMS:
                    name, size, crc = PROMS[p.name]
                    blob = p.read_bytes()[:size]
                    if zlib.crc32(blob) != crc:
                        sys.exit(f'{p.name}: first {size} bytes do not match MAME ({crc:08x})')
                    (dest / name).write_bytes(blob)
                elif p.is_file():
                    shutil.copyfile(p, dest / p.name)
    md = glob.glob(str(roms / 'robocop_md' / '*.bin'))
    if md:
        (out / 'robocop_md.bin').write_bytes(Path(md[0]).read_bytes())


if __name__ == '__main__':
    main(Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]) if len(sys.argv) > 3 else None)
