"""Summarise MAME trace CSVs from dec0_trace.lua and md_trace.lua.

usage: summarise_traces.py --dec0 <dec0_frames.csv> --md <md_frames.csv> [--from <frame>] [--to <frame>]
Arcade gameplay frames are those with sprites and the first 16x16 layer showing tiles.
"""
import argparse
import collections
import csv
import statistics

HEX = ('pc', 'priority', 'pf1_ctrl', 'pf2_ctrl', 'pf3_ctrl')


def rows(path):
    return list(csv.DictReader(open(path)))


def n(r, k):
    return int(r[k], 16) if k in HEX else int(r[k])


def pct(v, p):
    v = sorted(v)
    return v[min(len(v) - 1, int(len(v) * p))]


def table(title, frames, keys):
    print(f'\n{title} ({len(frames)} frames)')
    print(f'{"metric":28} {"mean":>8} {"p50":>7} {"p95":>7} {"p99":>7} {"max":>7}')
    for k in keys:
        v = [n(r, k) for r in frames]
        print(f'{k:28} {statistics.mean(v):8.1f} {pct(v, .5):7} {pct(v, .95):7} {pct(v, .99):7} {max(v):7}')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dec0')
    ap.add_argument('--md')
    ap.add_argument('--from', dest='lo', type=int, default=0)
    ap.add_argument('--to', dest='hi', type=int, default=10 ** 9)
    ap.add_argument('--clock', type=float, default=10e6, help='arcade 68000 clock in Hz')
    ap.add_argument('--refresh', type=float, default=57.444853, help='arcade frames per second')
    ap.add_argument('--poll-cycles', type=float, default=50, help='68000 cycles per turn of the frame wait loop')
    a = ap.parse_args()
    if a.dec0:
        every = [r for r in rows(a.dec0) if a.lo <= n(r, 'frame') <= a.hi]
        g = [r for r in every if n(r, 'obj_tiles') > 0 and n(r, 'pf2_unique') > 10]
        table('Arcade gameplay', g, ['obj_entries', 'obj_tiles', 'obj_unique', 'md_sprites_est', 'obj_line_tiles_max',
                                     'obj_lines_over_320px', 'obj_pals', 'obj_flash', 'obj_colour8',
                                     'pf1_cells', 'pf1_unique', 'pf1_pals', 'pf2_unique', 'pf2_patterns', 'pf2_pals',
                                     'pf3_unique', 'pf3_patterns', 'pf3_pals', 'palettes', 'colours', 'colours_9bit',
                                     'working_set_patterns', 'new_patterns_vs_prev'] +
              [k for k in ('obj_colours9', 'pf1_colours9', 'pf2_colours9', 'pf3_colours9', 'pf23_colours9') if k in g[0]])
        for th in (16, 20):
            print(f'frames with more than {th} sprite tiles on a line: '
                  f'{sum(1 for r in g if n(r, "obj_line_tiles_max") > th) / len(g) * 100:.2f}%')
        print(f'frames with more than 80 sprite tiles: {sum(1 for r in g if n(r, "obj_tiles") > 80) / len(g) * 100:.2f}%, '
              f'more than 80 after merging into 32x32 pieces: {sum(1 for r in g if n(r, "md_sprites_est") > 80) / len(g) * 100:.2f}%')
        for name in ('priority', 'pf1_ctrl', 'pf2_ctrl', 'pf3_ctrl', 'pf1_shape', 'pf2_shape', 'pf3_shape'):
            print(f'{name}:', dict(collections.Counter(r[name] for r in g).most_common(6)))
        dma = sum(n(r, 'sprite_dma') for r in g)
        print(f'sprite list latched in {dma / len(g) * 100:.1f}% of frames; sub CPU interrupts {sum(n(r, "sub_irqs") for r in g) / len(g):.2f} per frame; '
              f'sound commands {sum(n(r, "sound_cmds") for r in g) / len(g):.3f} per frame')
        ch = sum(1 for x, y in zip(g, g[1:]) if x['obj_hash'] != y['obj_hash'])
        print(f'frames whose sprite list differs from the previous frame: {ch / len(g) * 100:.1f}%')
        cyc = a.clock / a.refresh
        pairs = [(n(x, 'idle_reads') + n(y, 'idle_reads')) * a.poll_cycles for x, y in zip(g[0::2], g[1::2])
                 if n(y, 'frame') == n(x, 'frame') + 1]
        busy = [2 * cyc - p for p in pairs]
        print(f'cycles outside the frame wait loop per pair of frames ({2 * cyc:.0f} available): '
              f'mean {statistics.mean(busy):.0f} p50 {pct(busy, .5):.0f} p95 {pct(busy, .95):.0f} '
              f'p99 {pct(busy, .99):.0f} max {max(busy):.0f}')
        for name, budget in (('two NTSC Mega Drive frames', 2 * 7670454 / 59.92), ('two PAL Mega Drive frames', 2 * 7600489 / 49.70)):
            print(f'pairs needing more than {name} ({budget:.0f} cycles): '
                  f'{sum(1 for b in busy if b > budget) / len(busy) * 100:.2f}%')
        scenes = collections.Counter((r['pf2_shape'], r['pf3_shape'], r['priority']) for r in every)
        print('all frames by (pf2 shape, pf3 shape, priority):', dict(scenes.most_common(8)))
    if a.md:
        m = [r for r in rows(a.md) if a.lo <= n(r, 'frame') <= a.hi]
        g = [r for r in m if r['in_game'] == '1' and n(r, 'spr_visible') >= 3]
        table('Mega Drive gameplay', g, ['dma_vram', 'dma_cram', 'dma_vsram', 'dma_active', 'dma_ops', 'cpu_vram',
                                        'cpu_cram', 'fill', 'copy', 'cram_active', 'reg_active', 'spr_visible',
                                        'spr_cells', 'spr_line_max', 'spr_line_px_max', 'spr_over_lines',
                                        'spr_pals', 'cram_colours', 'cram_changed'])
        sat = sum(1 for r in g if n(r, 'sat_dma') > 0)
        print(f'frames with a sprite-table DMA: {sat / len(g) * 100:.1f}%')
        for label, test in (('a line over a sprite limit', lambda r: n(r, 'spr_over_lines') > 0),
                            ('more than 16 sprites on a line', lambda r: n(r, 'spr_line_max') > 16),
                            ('a CRAM change', lambda r: n(r, 'cram_changed') > 0),
                            ('any VRAM DMA', lambda r: n(r, 'dma_vram') > 0)):
            print(f'frames with {label}: {sum(1 for r in g if test(r)) / len(g) * 100:.2f}%')
        if 'dma_src_rom' in g[0]:
            rom, ram = sum(n(r, 'dma_src_rom') for r in g), sum(n(r, 'dma_src_ram') for r in g)
            if rom + ram:
                print(f'VRAM DMA bytes from ROM: {rom / (rom + ram) * 100:.1f}%')
        hist = collections.Counter(n(r, 'pc') & ~0xf for r in g)
        print('most common frame-end PC (16-byte buckets):', ', '.join(f'{k:06x}:{v}' for k, v in hist.most_common(8)))
        modes = collections.Counter((r['hscroll_mode'], r['vscroll_mode'], r['width'], r['hint']) for r in g)
        print('scroll modes (h, v, width, hint):', dict(modes))
        print('mapper register writes:', sum(n(r, 'mapper') for r in m))


if __name__ == '__main__':
    main()
