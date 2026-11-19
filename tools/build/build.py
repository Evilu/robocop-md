"""Build the Mega Drive ROM from the arcade program image.

usage: build.py <robocop_prg.bin> <robocop_sprites.bin> <robocop_tiles1.bin> <robocop_tiles2.bin> <robocop_char.bin>
       <robocop_snd.bin> <robocop_oki.bin> <out.md>

Takes the 256 KB arcade 68000 program, redirects its hardware addresses to
copies in work RAM, replaces the vectors and the header page, replaces the
exchanges with the HuC6280, and appends the hardware layer assembled from src/.
"""
import os
import pickle
import struct
import subprocess
import sys
import tempfile
import zlib

import gfx
import sound
from pathlib import Path

from capstone import CS_ARCH_M68K, CS_MODE_BIG_ENDIAN, CS_MODE_M68K_000, Cs

ROOT = Path(__file__).resolve().parents[2]
PREFIX = os.environ.get('M68K_PREFIX', 'm68k-elf-')
PRG_SIZE = 0x40000
HAL_BASE = 0x40000
ROM_SIZE = 0x400000
SOUND_TABLE = 0x200000
SAMPLE_TABLE = 0x27f000
PCM = 0x280000
GFX_SINGLE = 0x080000
GFX_PAIR = 0x100000
SPRITE_TILES = 3072
GFX_TILES = 0x180000
GFX_BLANK = 0x070000
GFX_CHARS = 0x1e0000
TRAMPOLINE = 0x200

RELOCATIONS = [
    (0x180000, 0x181000, 0xff1000),
    (0x240000, 0x240020, 0xff0800),
    (0x242000, 0x244000, 0xff2000),
    (0x244000, 0x246000, 0xff6000),
    (0x246000, 0x246020, 0xff0820),
    (0x248000, 0x248800, 0xff5800),
    (0x24a000, 0x24a800, 0xff4800),
    (0x24c000, 0x24c020, 0xff0840),
    (0x24c800, 0x24d000, 0xffc800),
    (0x24d000, 0x24d800, 0xff5000),
    (0x24e000, 0x24e800, 0xffc800),
    (0x30c000, 0x30c020, 0xff0860),
    (0x310000, 0x310800, 0xff0000),
    (0x314000, 0x314800, 0xff4000),
]
LIMIT_OPS = ('cmpa', 'cmpi', 'cmp.')
DATA_FROM = 0x240000
LOOSE_DATA = [(0x242000, 0x246000), (0x24a000, 0x24a800), (0x24d000, 0x24d800)]


def relocate(addr, limit=False):
    if limit:
        for lo, hi, to in RELOCATIONS:
            if addr == hi:
                return to + hi - lo
    for lo, hi, to in RELOCATIONS:
        if lo <= addr < hi:
            return to + addr - lo
    return None


def assemble():
    with tempfile.TemporaryDirectory() as tmp:
        obj, elf, out = (Path(tmp) / n for n in ('hal.o', 'hal.elf', 'hal.bin'))
        subprocess.run([PREFIX + 'as', '-m68000', '--register-prefix-optional', '-I', str(ROOT / 'src'),
                        '--defsym', f'GFX_SINGLE={GFX_SINGLE}', '--defsym', f'GFX_PAIR={GFX_PAIR}',
                        '--defsym', f'SPRITE_TILES={SPRITE_TILES}',
                        '--defsym', f'GFX_TILES={GFX_TILES}', '--defsym', f'GFX_BLANK={GFX_BLANK}', '--defsym', f'GFX_CHARS={GFX_CHARS}', '--defsym', f'SOUND_TABLE={SOUND_TABLE}', '--defsym', f'SAMPLE_TABLE={SAMPLE_TABLE}',
                        str(ROOT / 'src' / 'hal.s'), '-o', str(obj)], check=True)
        subprocess.run([PREFIX + 'ld', '-Ttext', hex(HAL_BASE), '-e', hex(HAL_BASE), '-o', str(elf), str(obj)],
                       check=True)
        subprocess.run([PREFIX + 'objcopy', '-O', 'binary', str(elf), str(out)], check=True)
        nm = subprocess.run([PREFIX + 'nm', str(elf)], check=True, capture_output=True, text=True).stdout
        symbols = {line.split()[2]: int(line.split()[0], 16) for line in nm.splitlines() if len(line.split()) == 3}
        return out.read_bytes(), symbols


def header(rom_end):
    h = bytearray(b' ' * 0x100)

    def put(off, text, size):
        h[off:off + size] = text.encode().ljust(size)[:size]

    put(0x00, 'SEGA MEGA DRIVE', 16)
    put(0x10, '(C)     2026.NOV', 16)
    put(0x20, 'ROBOCOP MD - RESEARCH BUILD', 48)
    put(0x50, 'ROBOCOP MD - RESEARCH BUILD', 48)
    put(0x80, 'GM 00000000-00', 14)
    put(0x90, 'J', 16)
    h[0xa0:0xb0] = struct.pack('>4I', 0, rom_end, 0xff0000, 0xffffff)
    put(0xf0, 'JUE', 16)
    return h


def expect(rom, off, data):
    found = bytes(rom[off:off + len(data)])
    if found != data:
        sys.exit(f'{off:06x}: expected {data.hex()}, found {found.hex()}: not the robocop revision 4 program')


def sound_streams(sound_program, samples, cache):
    """Running the 6502 program for every tune takes a few minutes; the result is kept beside the ROM."""
    sources = b''.join((ROOT / 'tools' / 'build' / name).read_bytes() for name in ('sound.py', 'sound6502.py'))
    key = f'{zlib.crc32(sound_program + samples + sources):08x}'
    file = cache / f'sound_{key}.pickle'
    if file.exists():
        return pickle.loads(file.read_bytes())
    print('converting the sound (a few minutes, once) ...', flush=True)
    report = []
    streams = sound.build(sound_program, samples, report)
    cache.mkdir(parents=True, exist_ok=True)
    file.write_bytes(pickle.dumps((streams, report)))
    return streams, report


def build(program, sprites, tiles1, tiles2, chars, sound_program, samples, out_path):
    if len(program) != PRG_SIZE:
        sys.exit('expected the 256 KB robocop program image')
    rom = bytearray(program)
    hal, sym = assemble()
    report, done = [], set()

    def patch(off, old, new, what):
        expect(rom, off, old)
        rom[off:off + len(new)] = new
        done.update(range(off, off + max(len(old), len(new))))
        report.append(f'{off:06x}: {what}')

    jump = lambda name: b'\x4e\xf9' + struct.pack('>I', sym[name])
    call = lambda name: b'\x4e\xb9' + struct.pack('>I', sym[name])
    patch(0x35a8, b'\x00\x80', b'\x00\x81', 'main loop sync: store the HuC6280\'s answer directly')
    patch(0x3eee, bytes.fromhex('13fc000100180003'), jump('hal_sequence') + b'\x4e\x71',
          'routine sequencer replaced')
    patch(0x7630, bytes.fromhex('4279001 80ffe'.replace(' ', '')), call('hal_hit'),
          'HuC6280 interrupt replaced by a call to the hit detection')
    for site in (0x1010, 0x1b86):
        patch(site, bytes.fromhex('33c00030c012'), call('hal_sprites'), 'sprite latch: translate the sprite list')
    patch(0x19c6, bytes.fromhex('33c00030c014'), call('hal_sound'), 'sound command sent to the hardware layer')
    for site, value in ((0x1362, 0x05), (0x1498, 0x01), (0x14b8, 0x04), (0x14d8, 0xc0)):
        patch(site, bytes.fromhex(f'33fc{value:04x}0030c014'), call(f'hal_sound_{value:02x}') + b'\x4e\x71',
              f'fixed sound command {value:02x} sent to the hardware layer')
    patch(0x761c, bytes.fromhex('3e3c04af'), bytes.fromhex('600a4e71'), 'object records no longer copied to the dual-port RAM')
    patch(0x767c, bytes.fromhex('3e3c04af'), bytes.fromhex('4e754e71'), 'object records no longer copied back')
    patch(TRAMPOLINE, bytes(rom[TRAMPOLINE:TRAMPOLINE + 6]), jump('hal_restart'), 'restart trampoline')
    for site in (0x36da, 0x3830):
        expect(rom, site, b'\x4e\xfa' + struct.pack('>h', 0x1bc - (site + 2)))
        patch(site, bytes(rom[site:site + 4]), b'\x4e\xfa' + struct.pack('>h', TRAMPOLINE - (site + 2)),
              'restart jump re-aimed at the trampoline')

    md = Cs(CS_ARCH_M68K, CS_MODE_BIG_ENDIAN | CS_MODE_M68K_000)
    moved, limits, skipped = 0, [], []
    for off in range(0x22c, PRG_SIZE - 4, 2):
        if off in done:
            continue
        value = struct.unpack_from('>I', rom, off)[0]
        if relocate(value) is None and relocate(value, True) is None:
            continue
        for start in (off - 2, off - 4, off - 6):
            ins = next(md.disasm(bytes(rom[start:start + 12]), start), None)
            if not ins or start + ins.size < off + 4:
                continue
            if f'${value:x}.l' not in ins.op_str and f'#${value:x}' not in ins.op_str:
                continue
            limit = ins.mnemonic.startswith(LIMIT_OPS) and f'#${value:x}' in ins.op_str
            target = relocate(value, limit)
            if target is None:
                break
            if limit and target != relocate(value):
                limits.append(f'{start:06x} {ins.mnemonic} {ins.op_str} -> {target:06x}')
            struct.pack_into('>I', rom, off, target)
            done.update(range(off, off + 4))
            moved += 1
            break
        else:
            if relocate(value) is not None:
                skipped.append((off, value))
    report.append(f'{moved} hardware addresses redirected')

    def decodes(start, size):
        ins = next(md.disasm(bytes(rom[start:start + 12]), start), None)
        return ins is not None and ins.size == size

    pointer = lambda value: not value & 1 and value >= DATA_FROM and relocate(value) is not None
    candidates = {off for off, value in skipped if pointer(value)}
    tables, loose = 0, []
    for off, value in sorted(skipped):
        if off not in candidates:
            continue
        after_code = struct.unpack_from('>H', rom, off - 2)[0] in (0x4e75, 0x4e71)
        certain = after_code or off - 4 in candidates or off + 4 in candidates
        if not certain:
            if not any(lo <= value < hi for lo, hi in LOOSE_DATA):
                continue
            if struct.unpack_from('>H', rom, off - 2)[0] < 0xfffe and (decodes(off - 2, 4) or decodes(off - 4, 6)):
                continue
            loose.append(f'{off:06x}:{value:06x}')
        struct.pack_into('>I', rom, off, relocate(value))
        done.update(range(off, off + 4))
        tables += 1
    skipped = [f'{off:06x}:{value:06x}' for off, value in skipped if off not in done]
    report.append(f'{tables} more in data: long pointers after a routine or in a run of pointers')
    report.append(f'{len(loose)} of those are single pointers: ' + ' '.join(loose))
    report.append(f'{len(limits)} compare limits at the end of a range:')
    report += ['  ' + line for line in limits]
    report.append(f'{len(skipped)} values in hardware ranges left alone (not an instruction operand)')

    vectors = [0xffc000, sym['hal_boot']] + [sym['hal_crash']] * 62
    for i in range(25, 32):
        vectors[i] = sym['hal_ignore']
    vectors[30] = sym['hal_vblank']
    struct.pack_into('>64I', rom, 0, *vectors)
    rom[0x100:0x200] = header(ROM_SIZE - 1)

    rom += hal
    if len(rom) > GFX_BLANK:
        sys.exit('hardware layer does not fit')
    layer2, layer3 = gfx.plane_tiles(tiles1, 2048), gfx.plane_tiles(tiles2, 1024)
    text = gfx.characters(chars)
    blank = bytes(not any(layer2[t * 128:(t + 1) * 128]) for t in range(2048))
    blank += bytes(not any(layer3[t * 128:(t + 1) * 128]) for t in range(1024))
    blank += bytes(not any(text[c * 32:(c + 1) * 32]) for c in range(4096))
    rom += b'\xff' * (GFX_BLANK - len(rom)) + blank
    singles, pairs = gfx.sprite_sets(sprites, SPRITE_TILES)
    rom += b'\xff' * (GFX_SINGLE - len(rom)) + singles
    rom += b'\xff' * (GFX_PAIR - len(rom)) + pairs
    report.append(f'sprite patterns: {len(singles)} bytes at {GFX_SINGLE:06x} (16x16), '
                  f'{len(pairs)} bytes at {GFX_PAIR:06x} (16x32)')
    rom += b'\xff' * (GFX_TILES - len(rom)) + layer2 + layer3
    rom += b'\xff' * (GFX_CHARS - len(rom)) + text
    report.append(f'tile patterns: {len(layer2) + len(layer3)} bytes at {GFX_TILES:06x}; '
                  f'characters: {len(text)} bytes at {GFX_CHARS:06x}')
    streams, sound_report = sound_streams(sound_program, samples, Path(out_path).parent / 'cache')
    table = bytearray(1024)
    data = bytearray()
    for value, stream in sorted(streams.items()):
        struct.pack_into('>I', table, value * 4, SOUND_TABLE + 1024 + len(data))
        data += stream
    rom += b'\xff' * (SOUND_TABLE - len(rom)) + table + data
    pcm = sound.samples(samples)
    sample_table, at = bytearray(32 * 8), PCM
    for n, wave in sorted(pcm.items()):
        if n < 32:
            struct.pack_into('>IH', sample_table, n * 8, at, len(wave))
        at += len(wave)
    driver = sound.z80_driver()
    rom += b'\xff' * (SAMPLE_TABLE - len(rom)) + sample_table + struct.pack('>H', len(driver)) + driver
    rom += b'\xff' * (PCM - len(rom)) + b''.join(wave for _, wave in sorted(pcm.items()))
    report.append(f'samples: {len(pcm)}, {at - PCM} bytes of 8-bit PCM at {PCM:06x}; Z80 driver {len(driver)} bytes')
    report += sound_report
    report.append(f'sound: {len(streams)} streams, {len(data)} bytes at {SOUND_TABLE + 1024:06x}')
    if len(rom) > ROM_SIZE:
        sys.exit('sound does not fit')
    rom += b'\xff' * (ROM_SIZE - len(rom))
    checksum = sum(struct.unpack_from(f'>{(len(rom) - 0x200) // 2}H', rom, 0x200)) & 0xffff
    struct.pack_into('>H', rom, 0x18e, checksum)

    out_path = Path(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_bytes(rom)
    report.append(f'hardware layer: {len(hal)} bytes at {HAL_BASE:06x}; ROM {len(rom)} bytes -> {out_path}')
    print('\n'.join(report))
    return skipped


if __name__ == '__main__':
    build(*(Path(a).read_bytes() for a in sys.argv[1:8]), sys.argv[8])
