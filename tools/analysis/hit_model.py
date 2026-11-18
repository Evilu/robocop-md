"""Check the hit detection against captures from hit_capture.lua.

usage: hit_model.py <robocop_prg.bin> <hit_capture.bin> [...]
Runs a model of the HuC6280's interrupt routine (0x2261 in the program the 68000
uploads, read from the program image) on each captured input and compares the
result with the captured output: on an arcade capture this checks the model, on
a Mega Drive capture it checks the port's 68000 routine against the model.
"""
import sys
from pathlib import Path

SIZE = 0x12 + 1200
SUB = 0xd772 - 0x2202


def model(rom, ram):
    ram = bytearray(ram)
    byte = lambda a: rom[a + SUB]
    word = lambda a: byte(a) | byte(a + 1) << 8

    def overlap(a, p, ox, oy, px, py):
        boxes_a = byte(a)
        a += 2
        start = p
        while True:
            boxes_p = byte(p)
            p += 2
            while True:
                xa, xp = word(a) + ox & 0xffff, word(p) + px & 0xffff
                d = (xa - xp) & 0xffff
                if xa < xp:
                    d = -d & 0xffff
                if d < (word(a + 4) + word(p + 4) & 0xffff):
                    ya, yp = word(a + 2) + oy & 0xffff, word(p + 2) + py & 0xffff
                    d = (ya - yp) & 0xffff
                    if ya < yp:
                        d = -d & 0xffff
                    if d < (word(a + 6) + word(p + 6) & 0xffff):
                        return True
                p += 8
                boxes_p = (boxes_p - 1) & 0xff
                if boxes_p & 0x80:
                    break
            a += 8
            p = start
            boxes_a = (boxes_a - 1) & 0xff
            if boxes_a & 0x80:
                return False

    count = ram[0x11]
    rec = 0x12
    for _ in range(30):
        if not count:
            break
        if ram[rec]:
            if not ram[rec + 0x27] & 1 and not ram[rec + 0x1f]:
                kind = ram[rec]
                a = word(word(0x24da + (kind * 2 & 0xff)) + (ram[rec + 0x16] * 2 & 0xff))
                p = word(0x248a + (ram[6] * 2 & 0xff))
                ox, oy = ram[rec + 2] << 8 | ram[rec + 3], ram[rec + 6] << 8 | ram[rec + 7]
                px, py = ram[7] << 8 | ram[8], ram[9] << 8 | ram[10]
                if overlap(a, p, ox, oy, px, py):
                    if kind == 6:
                        ram[rec + 0x27] |= 1
                    else:
                        ram[rec + 0x1f] = 4
                    if not ram[0x0e] | ram[0x0f]:
                        ram[0x0b] = 8
                        if ram[0x0c] & 0x80 and ram[0x0d] & 2:
                            ram[5] = max(ram[5] - byte(0x2335 + kind), 0)
            count -= 1
        rec += 0x28
    ram[4] = 0
    return bytes(ram)


def main(argv):
    rom = Path(argv[1]).read_bytes()
    for path in argv[2:]:
        data = Path(path).read_bytes()
        steps = len(data) // (2 * SIZE)
        bad = hits = damage = busy = 0
        for i in range(steps):
            before = data[i * 2 * SIZE:i * 2 * SIZE + SIZE]
            after = data[i * 2 * SIZE + SIZE:(i + 1) * 2 * SIZE]
            want = model(rom, before)
            busy += before[0x11] > 0
            hits += any(before[k] != after[k] for k in range(0x12, SIZE))
            damage += before[5] != after[5]
            if want[5:] != after[5:]:
                bad += 1
                if bad <= 3:
                    diff = [f'{k:x}: in {before[k]:02x} captured {after[k]:02x} model {want[k]:02x}'
                            for k in range(SIZE) if want[k] != after[k]]
                    print(f'  step {i}: ' + '; '.join(diff[:8]))
        print(f'{path}: {steps} steps, {busy} with objects, {hits} with a record marked, {damage} with energy taken; '
              f'{bad} differ from the model')


if __name__ == '__main__':
    main(sys.argv)
