"""Summarise Mega Drive VDP dumps written by tools/mame/md_trace.lua.

usage: md_vdp_dump.py <dump.bin> [...] [--render <out_dir>]

Each dump is 64 KB VRAM + 64 CRAM words + 32 register bytes. For every dump this
prints the VRAM layout, which patterns, palette lines and priority bits the
planes, window and sprites use, and optionally renders each layer to PNG
(rendering needs Pillow).
"""
import struct
import sys
from pathlib import Path


def load(path):
    b = Path(path).read_bytes()
    vram = b[:0x10000]
    cram = struct.unpack('>64H', b[0x10000:0x10080])
    reg = b[0x10080:0x100a0]
    return vram, cram, reg


def layout(reg):
    h40 = reg[12] & 0x81 != 0
    size = {0: 32, 1: 64, 3: 128}
    return {
        'width': 320 if h40 else 256,
        'plane_a': (reg[2] & 0x38) << 10,
        'plane_b': (reg[4] & 0x07) << 13,
        'window': ((reg[3] & 0x3c) if h40 else (reg[3] & 0x3e)) << 10,
        'sat': ((reg[5] & 0x7e) if h40 else (reg[5] & 0x7f)) << 9,
        'hscroll': (reg[13] & 0x3f) << 10,
        'plane_w': size.get(reg[16] & 3, 32),
        'plane_h': size.get((reg[16] >> 4) & 3, 32),
        'window_h': reg[17],
        'window_v': reg[18],
        'shadow_highlight': bool(reg[12] & 0x08),
        'hscroll_mode': reg[11] & 3,
        'vscroll_mode': (reg[11] >> 2) & 1,
    }


def window_rows(L):
    v = L['window_v']
    return v & 0x1f if v & 0x80 == 0 else 28 - (v & 0x1f)


def word(vram, a):
    return (vram[a & 0xffff] << 8) | vram[(a + 1) & 0xffff]


def plane_cells(vram, base, w, h):
    for row in range(h):
        for col in range(w):
            yield col, row, word(vram, base + (row * w + col) * 2)


def sprites(vram, sat):
    out, i, seen = [], 0, set()
    while i not in seen and len(out) < 80:
        seen.add(i)
        e = sat + i * 8
        y = word(vram, e) & 0x3ff
        sz = word(vram, e + 2)
        attr = word(vram, e + 4)
        x = word(vram, e + 6) & 0x1ff
        out.append({'x': x - 128, 'y': y - 128, 'w': ((sz >> 10) & 3) + 1, 'h': ((sz >> 8) & 3) + 1, 'attr': attr})
        i = sz & 0x7f
        if i == 0:
            break
    return out


def blank_pattern(vram, idx):
    return not any(vram[idx * 32:idx * 32 + 32])


def summarise(path):
    vram, cram, reg = load(path)
    L = layout(reg)
    print(f'== {Path(path).name}')
    print('   layout: ' + ', '.join(f'{k}={v:#x}' if isinstance(v, int) and v > 64 else f'{k}={v}' for k, v in L.items()))
    stats = {}
    tables = {'plane A': (L['plane_a'], L['plane_w'], L['plane_h']),
              'plane B': (L['plane_b'], L['plane_w'], L['plane_h']),
              'window': (L['window'], 64 if L['width'] == 320 else 32, window_rows(L))}
    owner = {}
    for name, (base, w, h) in tables.items():
        tiles, pals, prio, used = set(), {}, 0, 0
        for _, _, e in plane_cells(vram, base, w, h):
            t = e & 0x7ff
            if t == 0 or blank_pattern(vram, t):
                continue
            used += 1
            tiles.add(t)
            pals[(e >> 13) & 3] = pals.get((e >> 13) & 3, 0) + 1
            if e & 0x8000:
                prio += 1
            owner.setdefault(t, set()).add(name)
        stats[name] = (used, len(tiles), pals, prio)
    spr = [s for s in sprites(vram, L['sat']) if -32 < s['x'] < L['width'] and -32 < s['y'] < 224]
    st, sp, sprio = set(), {}, 0
    for s in spr:
        a = s['attr']
        n = s['w'] * s['h']
        for k in range(n):
            st.add((a & 0x7ff) + k)
            owner.setdefault((a & 0x7ff) + k, set()).add('sprites')
        sp[(a >> 13) & 3] = sp.get((a >> 13) & 3, 0) + 1
        if a & 0x8000:
            sprio += 1
    for name, (used, n, pals, prio) in stats.items():
        print(f'   {name:8}: {used:5} cells, {n:4} distinct patterns, palette lines {dict(sorted(pals.items()))}, high-priority cells {prio}')
    print(f'   sprites : {len(spr):5} visible, {len(st):4} patterns, palette lines {dict(sorted(sp.items()))}, high-priority {sprio}')
    nonblank = sum(1 for i in range(0x800) if not blank_pattern(vram, i))
    tables = min(L['plane_a'], L['plane_b'], L['window'], L['sat'], L['hscroll']) // 32
    referenced = set(owner)
    free = sum(1 for i in range(1, tables) if i not in referenced)
    print(f'   VRAM: {nonblank} non-blank 32-byte slots of 2048; tables start at slot {tables:#x} '
          f'({2048 - tables} slots); pattern slots below that not referenced this frame: {free}')
    lines = []
    for p in range(4):
        cols = cram[p * 16:p * 16 + 16]
        lines.append(f'line {p}: {len(set(c & 0xeee for c in cols[1:]))} distinct')
    print('   CRAM: ' + '; '.join(lines))
    regions = {}
    for t, o in owner.items():
        regions.setdefault('+'.join(sorted(o)), []).append(t)
    for k, v in sorted(regions.items()):
        print(f'   pattern range used by {k:22}: {min(v):#05x}-{max(v):#05x} ({len(v)} patterns)')
    return vram, cram, reg, L


def render(vram, cram, reg, L, out, stem):
    from PIL import Image

    def colour(c):
        return ((c & 0xe) * 18, ((c >> 4) & 0xe) * 18, ((c >> 8) & 0xe) * 18)

    pal = [colour(c) for c in cram]

    def draw_cell(img, px, py, e):
        t = e & 0x7ff
        p = (e >> 13) & 3
        hf, vf = e & 0x800, e & 0x1000
        for y in range(8):
            for x in range(8):
                sx, sy = (7 - x if hf else x), (7 - y if vf else y)
                b = vram[t * 32 + sy * 4 + sx // 2]
                v = (b >> 4) if sx % 2 == 0 else (b & 15)
                if v:
                    img.putpixel((px + x, py + y), pal[p * 16 + v])

    for name, base, w, h in (('planeA', L['plane_a'], L['plane_w'], L['plane_h']),
                             ('planeB', L['plane_b'], L['plane_w'], L['plane_h']),
                             ('window', L['window'], 64, 32)):
        img = Image.new('RGB', (w * 8, h * 8), (40, 0, 40))
        for col, row, e in plane_cells(vram, base, w, h):
            draw_cell(img, col * 8, row * 8, e)
        img.save(out / f'{stem}_{name}.png')
    img = Image.new('RGB', (L['width'] + 64, 224 + 64), (40, 0, 40))
    for s in reversed(sprites(vram, L['sat'])):
        a = s['attr']
        for cx in range(s['w']):
            for cy in range(s['h']):
                k = cx * s['h'] + cy
                e = (a & 0xf800) | ((a + k) & 0x7ff)
                hx = s['w'] - 1 - cx if a & 0x800 else cx
                vy = s['h'] - 1 - cy if a & 0x1000 else cy
                x, y = s['x'] + 32 + hx * 8, s['y'] + 32 + vy * 8
                if 0 <= x < img.width - 8 and 0 <= y < img.height - 8:
                    draw_cell(img, x, y, e & ~0x1800 | (a & 0x1800))
    img.save(out / f'{stem}_sprites.png')


def main(argv):
    out = None
    if '--render' in argv:
        i = argv.index('--render')
        out = Path(argv[i + 1])
        out.mkdir(parents=True, exist_ok=True)
        argv = argv[:i] + argv[i + 2:]
    for p in argv:
        vram, cram, reg, L = summarise(p)
        if out:
            render(vram, cram, reg, L, out, Path(p).stem)


if __name__ == '__main__':
    main(sys.argv[1:])
