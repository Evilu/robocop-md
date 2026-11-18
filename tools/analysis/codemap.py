"""Follow the code of a flat 68000 image from its vectors and map hardware accesses.

usage: codemap.py <image.bin> <out dir> [--seed <hex>[,<hex>...]] [--tables]
Recursive descent with capstone: follows branches, calls and jumps with known
targets. --tables also follows tables of long pointers loaded with
`lea table(pc),aN` or `lea table.l,aN` when every entry looks like code.
Writes functions.tsv (address, callers), code.tsv (start, end of each run of
decoded code) and access.tsv (instruction, address touched, read/write guess).
Prints totals per hardware region.
"""
import struct
import sys
from collections import defaultdict
from pathlib import Path

from capstone import CS_ARCH_M68K, CS_MODE_BIG_ENDIAN, CS_MODE_M68K_000, Cs
from capstone.m68k import (M68K_AM_ABSOLUTE_DATA_LONG, M68K_AM_ABSOLUTE_DATA_SHORT, M68K_AM_BRANCH_DISPLACEMENT,
                           M68K_AM_IMMEDIATE, M68K_AM_PCI_DISP, M68K_OP_BR_DISP, M68K_OP_MEM)

REGIONS = [
    (0x180000, 0x180fff, 'shared RAM (HuC6280)'),
    (0x240000, 0x240017, 'BAC06 #1 control (text)'),
    (0x242000, 0x2427ff, 'BAC06 #1 col/row scroll'),
    (0x242800, 0x243fff, 'RAM 242800'),
    (0x244000, 0x245fff, 'BAC06 #1 tilemap (text)'),
    (0x246000, 0x246017, 'BAC06 #2 control'),
    (0x248000, 0x2487ff, 'BAC06 #2 col/row scroll'),
    (0x24a000, 0x24a7ff, 'BAC06 #2 tilemap'),
    (0x24c000, 0x24c017, 'BAC06 #3 control'),
    (0x24c800, 0x24cfff, 'BAC06 #3 col/row scroll'),
    (0x24d000, 0x24d7ff, 'BAC06 #3 tilemap'),
    (0x300000, 0x30001f, 'rotary inputs'),
    (0x30c000, 0x30c00b, 'inputs, DIP'),
    (0x30c010, 0x30c01f, 'control (priority, DMA, sound, IRQ ack)'),
    (0x310000, 0x3107ff, 'palette RG'),
    (0x314000, 0x3147ff, 'palette B'),
    (0xff8000, 0xffbfff, 'work RAM'),
    (0xffc000, 0xffc7ff, 'sprite RAM'),
]
ENDS = {'rts', 'rte', 'rtr', 'jmp', 'bra', 'stop', 'illegal'}


def region(addr):
    for lo, hi, name in REGIONS:
        if lo <= addr <= hi:
            return name
    return None


def main(argv):
    data = Path(argv[1]).read_bytes()
    out = Path(argv[2])
    out.mkdir(parents=True, exist_ok=True)
    seeds = set(struct.unpack('>64I', data[:256])[1:])
    follow_tables = '--tables' in argv
    if '--seed' in argv:
        seeds |= {int(s, 16) for s in argv[argv.index('--seed') + 1].split(',')}
    md = Cs(CS_ARCH_M68K, CS_MODE_BIG_ENDIAN | CS_MODE_M68K_000)
    md.detail = True
    size = len(data)
    insn = {}
    callers = defaultdict(set)
    access = []
    tables = set()
    work = [s for s in seeds if s < size and not s & 1]

    def plausible(target):
        if target & 1 or not 0x100 <= target < size:
            return False
        ins = next(md.disasm(data[target:target + 12], target), None)
        return ins is not None and ins.mnemonic not in ('ori', 'dc.w')

    while work:
        pc = work.pop()
        while 0 <= pc < size and pc not in insn:
            ins = next(md.disasm(data[pc:pc + 12], pc), None)
            if ins is None or ins.mnemonic == 'dc.w':
                break
            insn[pc] = ins.size
            m = ins.mnemonic
            stop = m.split('.')[0] in ENDS
            for n, op in enumerate(ins.operands):
                target = None
                if op.type == M68K_OP_BR_DISP or op.address_mode == M68K_AM_BRANCH_DISPLACEMENT:
                    target = pc + 2 + op.br_disp.disp
                elif op.type == M68K_OP_MEM and op.address_mode == M68K_AM_PCI_DISP:
                    target = pc + 2 + op.mem.disp
                    if m.startswith(('jsr', 'jmp')):
                        pass
                    elif m.startswith('lea') and follow_tables:
                        tables.add(target)
                        target = None
                    else:
                        target = None
                elif op.address_mode in (M68K_AM_ABSOLUTE_DATA_LONG, M68K_AM_ABSOLUTE_DATA_SHORT):
                    addr = op.imm & 0xffffff
                    if m.startswith(('jsr', 'jmp')):
                        target = addr
                    else:
                        if m.startswith('lea') and follow_tables and addr < size:
                            tables.add(addr)
                        name = region(addr)
                        if name:
                            kind = 'lea' if m.startswith(('lea', 'pea')) else \
                                'w' if n == len(ins.operands) - 1 and not m.startswith(('tst', 'cmp', 'btst')) else 'r'
                            access.append((pc, addr, kind, name, f'{m} {ins.op_str}'))
                elif op.address_mode == M68K_AM_IMMEDIATE and m.startswith(('movea', 'move.l', 'cmpa', 'adda', 'suba')):
                    addr = op.imm & 0xffffff
                    name = region(addr)
                    if name and name != 'work RAM':
                        access.append((pc, addr, 'imm', name, f'{m} {ins.op_str}'))
                if target is not None and 0 <= target < size and not target & 1:
                    if m.startswith(('jsr', 'bsr')):
                        callers[target].add(pc)
                    work.append(target)
            if stop:
                break
            pc += ins.size
        if not work and follow_tables:
            for t in sorted(tables):
                a = t
                while a + 4 <= size and a not in insn:
                    v = struct.unpack_from('>I', data, a)[0]
                    if not plausible(v):
                        break
                    if v not in insn:
                        callers[v].add(-t)
                        work.append(v)
                    a += 4
            tables.clear()

    runs, start, prev = [], None, None
    for a in sorted(insn):
        if start is None:
            start = a
        elif a != prev:
            runs.append((start, prev))
            start = a
        prev = a + insn[a]
    if start is not None:
        runs.append((start, prev))
    (out / 'code.tsv').write_text(''.join(f'{a:06x}\t{b:06x}\n' for a, b in runs))
    (out / 'functions.tsv').write_text(''.join(
        f'{a:06x}\t{len(c)}\n' for a, c in sorted(callers.items())))
    (out / 'access.tsv').write_text(''.join(
        f'{pc:06x}\t{addr:06x}\t{kind}\t{name}\t{text}\n' for pc, addr, kind, name, text in sorted(access)))
    code_bytes = sum(insn.values())
    print(f'instructions {len(insn)}  code bytes {code_bytes} ({100 * code_bytes / size:.1f}% of image)  '
          f'call targets {len(callers)}  code runs {len(runs)}')
    totals = defaultdict(lambda: defaultdict(int))
    for pc, addr, kind, name, text in access:
        totals[name][kind] += 1
    for lo, hi, name in REGIONS:
        if name in totals:
            t = totals[name]
            print(f'{name:42s} {sum(t.values()):5d}  ' + '  '.join(f'{k} {v}' for k, v in sorted(t.items())))


if __name__ == '__main__':
    main(sys.argv)
