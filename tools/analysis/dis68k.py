"""Disassemble ranges of a flat 68000 image.

usage: dis68k.py <image.bin> <hex address>:<instruction count> [...]
Needs capstone. Addresses must be instruction-aligned; if the listing looks like
nonsense, the start address is inside an instruction or in data.
"""
import sys

from capstone import CS_ARCH_M68K, CS_MODE_BIG_ENDIAN, CS_MODE_M68K_000, Cs


def main(argv):
    data = open(argv[1], 'rb').read()
    md = Cs(CS_ARCH_M68K, CS_MODE_BIG_ENDIAN | CS_MODE_M68K_000)
    for spec in argv[2:]:
        addr, count = spec.split(':')
        addr, count = int(addr, 16), int(count)
        print(f'--- {addr:06x}')
        for i, ins in enumerate(md.disasm(data[addr:addr + count * 10], addr)):
            if i >= count:
                break
            print(f'{ins.address:06x}  {ins.mnemonic} {ins.op_str}')


if __name__ == '__main__':
    main(sys.argv)
