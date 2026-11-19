"""Build the Mega Drive ROM from your copy of the arcade game.

usage: python3 build_md.py <robocop.zip or folder> [out.md]

Takes MAME's "robocop" set (Robocop, World, revision 4), checks the files the
port uses, and writes the Mega Drive ROM (default out/robocop_md.md). The set
is read straight from the zip; nothing is extracted to disk.
"""
import sys
import zipfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / 'tools' / 'build'))

PROGRAM = [(('ep05-4.11c', 0x29c35379), ('ep01-4.11b', 0x77507c69)),
           (('ep04-3', 0x39181778), ('ep00-3', 0xe128541f))]
SPRITES = [('ep07', 0x495d75cf), ('ep06', 0xa2ae32e2), ('ep11', 0x62fa425a), ('ep10', 0xcce3bd95),
           ('ep09', 0x11bed656), ('ep08', 0xc45c7b4c), ('ep13', 0x8fca9f28), ('ep12', 0x3cd1d0c3)]
TILES1 = [('ep20', 0x1d8d38b8), ('ep21', 0x187929b2), ('ep18', 0xb6580b5e), ('ep19', 0x9bad01c7)]
TILES2 = [('ep14', 0xca56ceda), ('ep15', 0xa945269c), ('ep16', 0xe7fa4d58), ('ep17', 0x84aae89d)]
CHARS = [('ep23', 0xa77e4ab1), ('ep22', 0x9fbd6903)]
SIZE = 0x10000


def reader(source):
    if source.is_dir():
        files = {p.name.lower(): p for p in source.rglob('*') if p.is_file()}
        return lambda name: files[name].read_bytes() if name in files else None
    if not zipfile.is_zipfile(source):
        sys.exit(f'{source} is neither a folder nor a zip file')
    archive = zipfile.ZipFile(source)
    members = {Path(i.filename).name.lower(): i for i in archive.infolist() if not i.is_dir()}

    def read(name):
        info = members.get(name)
        return archive.read(info) if info is not None and info.file_size <= SIZE else None
    return read


def load(read):
    data, problems = {}, []
    for name, crc in [f for pair in PROGRAM for f in pair] + SPRITES + TILES1 + TILES2 + CHARS:
        blob = read(name)
        if blob is None:
            problems.append(f'  {name}: missing')
        elif zlib.crc32(blob) != crc:
            problems.append(f'  {name}: wrong contents (expected CRC32 {crc:08x}; '
                            f'found {len(blob)} bytes, CRC32 {zlib.crc32(blob):08x})')
        data[name] = blob
    if problems:
        sys.exit('This is not the "robocop" set the port needs (Robocop, World, revision 4):\n' +
                 '\n'.join(problems))
    return data


def interleave(even, odd):
    out = bytearray(len(even) * 2)
    out[0::2], out[1::2] = even, odd
    return bytes(out)


def main(argv):
    if len(argv) < 2 or argv[1] in ('-h', '--help'):
        sys.exit(__doc__.strip())
    try:
        import capstone  # noqa: F401
    except ImportError as missing:
        sys.exit(f'Python package missing ({missing.name}): run  python3 -m pip install -r requirements.txt')
    import build

    source = Path(argv[1])
    out = Path(argv[2]) if len(argv) > 2 else ROOT / 'out' / 'robocop_md.md'
    if not source.exists():
        sys.exit(f'{source} not found')
    data = load(reader(source))
    program = b''.join(interleave(data[even[0]], data[odd[0]]) for even, odd in PROGRAM)
    sprites = bytearray(len(SPRITES) * SIZE)
    for i, (name, _) in enumerate(SPRITES):
        sprites[i * SIZE:i * SIZE + len(data[name])] = data[name]
    tiles1 = b''.join(data[name] for name, _ in TILES1)
    tiles2 = b''.join(data[name] for name, _ in TILES2)
    chars = b''.join(data[name] for name, _ in CHARS)
    build.build(program, bytes(sprites), tiles1, tiles2, chars, out)
    print(f'\nDone: {out}')


if __name__ == '__main__':
    main(sys.argv)
