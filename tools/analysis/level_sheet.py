"""usage: level_sheet.py <arcade run dir> <md run dir> <out.png>
Pairs the snapshots of two tools/level.sh runs: arcade above, Mega Drive below, one
column per snapshot. The arcade picture loses its top and bottom 8 lines, as the port's does."""
import csv
import glob
import sys

from PIL import Image


def shots(folder):
    return sorted(glob.glob(folder + '/*/*.png'))


def rows(folder):
    try:
        return list(csv.DictReader(open(folder + '/level.csv')))
    except FileNotFoundError:
        return []


def main(arcade, md, out):
    a, m = shots(arcade), shots(md)
    n = max(len(a), len(m))
    per_row = 6
    lines = (n + per_row - 1) // per_row
    sheet = Image.new('RGB', (256 * per_row, lines * 456), (40, 0, 40))
    for i in range(n):
        x, y = 256 * (i % per_row), 456 * (i // per_row)
        if i < len(a):
            sheet.paste(Image.open(a[i]).convert('RGB').crop((0, 8, 256, 232)), (x, y))
        if i < len(m):
            sheet.paste(Image.open(m[i]).convert('RGB').crop((0, 0, 256, 224)), (x, y + 228))
    sheet.save(out)
    ra, rm = rows(arcade), rows(md)
    for i in range(max(len(ra), len(rm))):
        left = ra[i] if i < len(ra) else {}
        right = rm[i] if i < len(rm) else {}
        print(f"{left.get('frame', ''):>6}  arcade scene {left.get('scene', '-')} steps {left.get('steps', '-'):>5} scroll {left.get('scroll', '-'):>5} objects {left.get('objects', '-'):>2}"
              f"   md scene {right.get('scene', '-')} steps {right.get('steps', '-'):>5} scroll {right.get('scroll', '-'):>5} objects {right.get('objects', '-'):>2}")
    print(f'{len(a)} arcade and {len(m)} md snapshots -> {out}')


main(*sys.argv[1:4])
