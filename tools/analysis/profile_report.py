"""Report on a dec0_profile.lua run.

usage: profile_report.py <profile dir> <codemap functions.tsv> [--from <frame>] [--to <frame>] [--top 30]
       [--idle 17ba-17cc,17e8-17fa,1156-1166] [--subwait 3ef6-3f00,...]
Prints how the frames divide between the wait loops, serving the HuC6280 and real
work, in cycles per pair of frames (the game logic runs every other frame), and
the hottest routines by exclusive (PC inside) and inclusive (on the call stack) samples.
Per-address totals cover the frames the profiler was told to count (PROFILE_FROM).
"""
import argparse
import bisect
import csv
import statistics
from pathlib import Path


def ranges(text):
    return [tuple(int(x, 16) for x in part.split('-')) for part in text.split(',') if part]


def pct(v, p):
    v = sorted(v)
    return v[min(len(v) - 1, int(len(v) * p))]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('dir')
    ap.add_argument('functions')
    ap.add_argument('--idle', default='17ba-17cc,17e8-17fa,1156-1166')
    ap.add_argument('--subwait', default='3ef6-3f02,3f2a-3f36,763e-7646,35ae-35ba,7620-762a,7680-768a')
    ap.add_argument('--from', dest='lo', type=int, default=0)
    ap.add_argument('--to', dest='hi', type=int, default=10 ** 9)
    ap.add_argument('--frame-cycles', type=float, default=10e6 / 57.444853)
    ap.add_argument('--top', type=int, default=30)
    a = ap.parse_args()
    d = Path(a.dir)
    frames = [r for r in csv.DictReader(open(d / 'profile_frames.csv')) if a.lo <= int(r['frame']) <= a.hi]
    pairs = []
    for x, y in zip(frames[0::2], frames[1::2]):
        s = int(x['samples']) + int(y['samples'])
        if not s:
            continue
        scale = 2 * a.frame_cycles / s
        idle = (int(x['idle']) + int(y['idle'])) * scale
        sub = (int(x['subwait']) + int(y['subwait'])) * scale
        pairs.append((2 * a.frame_cycles - idle - sub, sub, idle))
    print(f'{len(pairs)} pairs of frames, {2 * a.frame_cycles:.0f} cycles each')
    for name, i in (('real work', 0), ('serving the HuC6280 (waits and copies)', 1), ('frame wait loops', 2)):
        v = [p[i] for p in pairs]
        print(f'{name:40} mean {statistics.mean(v):7.0f}  p50 {pct(v, .5):7.0f}  p95 {pct(v, .95):7.0f}  '
              f'p99 {pct(v, .99):7.0f}  max {max(v):7.0f}')
    work = [p[0] for p in pairs]
    for name, budget in (('one NTSC Mega Drive frame', 7670454 / 59.92), ('two NTSC Mega Drive frames', 2 * 7670454 / 59.92)):
        print(f'pairs whose real work exceeds {name} ({budget:.0f} cycles): '
              f'{sum(1 for w in work if w > budget) / len(work) * 100:.2f}%')

    leaf = {int(k): int(v) for k, v in csv.reader(open(d / 'profile_leaf.csv'))}
    incl = {int(k): int(v) for k, v in csv.reader(open(d / 'profile_incl.csv'))}
    idle_r, sub_r = ranges(a.idle), ranges(a.subwait)
    inside = lambda rs, pc: any(lo <= pc < hi for lo, hi in rs)
    total = sum(leaf.values())
    idle = sum(v for k, v in leaf.items() if inside(idle_r, k))
    sub = sum(v for k, v in leaf.items() if inside(sub_r, k))
    real = total - idle - sub
    print(f'\nper-address totals: {total} samples; wait loops {idle / total * 100:.1f}%, '
          f'HuC6280 {sub / total * 100:.1f}%, real work {real / total * 100:.1f}%')

    starts = sorted(int(line.split('\t')[0], 16) for line in open(a.functions) if line[:1] in '0123456789abcdef')
    targets = sorted(k for k in incl if k > 0)

    def owner(pc):
        best = None
        for table in (starts, targets):
            i = bisect.bisect_right(table, pc) - 1
            if i >= 0 and pc - table[i] < 0x400 and (best is None or table[i] > best):
                best = table[i]
        return f'{best:06x}' if best is not None else f'{pc & ~0xff:06x}+'

    excl = {}
    for pc, v in leaf.items():
        if inside(idle_r, pc) or inside(sub_r, pc):
            continue
        o = owner(pc)
        excl[o] = excl.get(o, 0) + v
    print(f'\ntop {a.top} routines by exclusive samples (share of real work; "+" = 256-byte block of unmapped code):')
    for o, v in sorted(excl.items(), key=lambda x: -x[1])[:a.top]:
        on = incl.get(int(o.rstrip('+'), 16), 0) if not o.endswith('+') else 0
        print(f'  {o:8} {v / real * 100:5.1f}%   on stack {on / real * 100:5.1f}%')
    print(f'\ntop {a.top} call targets by inclusive samples (share of real work; "via" = indirect call site):')
    for o, v in sorted(incl.items(), key=lambda x: -x[1])[:a.top]:
        name = f'{o:06x}' if o > 0 else f'via {-o:06x}'
        print(f'  {name:12} {v / real * 100:5.1f}%')


if __name__ == '__main__':
    main()
