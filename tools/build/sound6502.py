"""Run the arcade's 6502 sound program and log what it writes to its chips.

The sound board: 65C02 at 1.5 MHz, 2 KB RAM, YM2203 at 0x0800, YM3812 at 0x1000,
sound latch at 0x3000 (a write from the 68000 raises NMI), OKI M6295 at 0x3800,
ROM at 0x8000. The YM3812's timer 1 is the only interrupt source in this game.

usage: sound6502.py <robocop_snd.bin> <robocop_oki.bin> <commands.csv> <out.csv>
commands.csv holds lines "seconds,c,00,value" (other lines are ignored), as
written by tools/mame/dec0_sound_log.lua; out.csv is written in the same format,
so the two can be compared.
"""
import sys
from pathlib import Path

CLOCK = 1_500_000
OPL_TIMER_CYCLES = 144
IDLE = bytes.fromhex('4c9180')
DELAY = bytes.fromhex('38e901d0fb')
OKI_RATE = 1_000_000 / 132

N, V, B, D, I, Z, C = 0x80, 0x40, 0x10, 0x08, 0x04, 0x02, 0x01


class Board:
    def __init__(self, rom, oki_rom):
        self.rom = rom
        self.ram = bytearray(0x800)
        self.cycles = 0
        self.log = []
        self.opn_reg = self.opl_reg = 0
        self.latch = 0
        self.nmi = False
        self.timer_value = 0
        self.timer_end = None
        self.timer_flag = False
        self.oki_pending = None
        self.on_tick = None
        self.nmi_edge = False
        self.oki_busy_until = [0.0] * 4
        self.oki_length = {}
        for n in range(1, 128):
            start = int.from_bytes(oki_rom[n * 8:n * 8 + 3], 'big')
            end = int.from_bytes(oki_rom[n * 8 + 3:n * 8 + 6], 'big')
            if start < end < len(oki_rom):
                self.oki_length[n] = (end - start + 1) * 2 / OKI_RATE
        self.a = self.x = self.y = 0
        self.s = 0xff
        self.p = I | 0x20
        self.pc = rom[0x7ffc] | rom[0x7ffd] << 8

    def time(self):
        return self.cycles / CLOCK

    def irq(self):
        if self.timer_end is not None and self.cycles >= self.timer_end:
            self.timer_flag = True
            self.timer_end += (256 - self.timer_value) * OPL_TIMER_CYCLES
        return self.timer_flag

    def read(self, a):
        if a >= 0x8000:
            return self.rom[a - 0x8000]
        if a < 0x800:
            return self.ram[a]
        if a == 0x1000:
            return 0xc0 if self.irq() else 0
        if a == 0x3000:
            self.nmi = False
            return self.latch
        if a == 0x3800:
            now = self.time()
            return 0xf0 | sum(1 << v for v in range(4) if self.oki_busy_until[v] > now)
        return 0

    def write(self, a, v):
        if a < 0x800:
            self.ram[a] = v
        elif a == 0x0800:
            self.opn_reg = v
        elif a == 0x0801:
            self.log.append((self.time(), 'n', self.opn_reg, v))
        elif a == 0x1000:
            self.opl_reg = v
        elif a == 0x1001:
            self.log.append((self.time(), 'l', self.opl_reg, v))
            if self.opl_reg == 2:
                self.timer_value = v
            elif self.opl_reg == 4:
                if v & 0x80:
                    self.timer_flag = False
                elif v & 1:
                    if self.timer_end is None:
                        self.timer_end = self.cycles + (256 - self.timer_value) * OPL_TIMER_CYCLES
                else:
                    self.timer_end = None
        elif a == 0x3800:
            self.log.append((self.time(), 'o', 0, v))
            if self.oki_pending is not None:
                for voice in range(4):
                    if v >> 4 & 1 << voice:
                        self.oki_busy_until[voice] = self.time() + self.oki_length.get(self.oki_pending, 0)
                self.oki_pending = None
            elif v & 0x80:
                self.oki_pending = v & 0x7f
            else:
                for voice in range(4):
                    if v >> 3 & 1 << voice:
                        self.oki_busy_until[voice] = 0.0

    def command(self, value):
        self.log.append((self.time(), 'c', 0, value))
        self.latch = value
        self.nmi = True
        self.nmi_edge = True

    def push(self, v):
        self.ram[0x100 + self.s] = v
        self.s = self.s - 1 & 0xff

    def pop(self):
        self.s = self.s + 1 & 0xff
        return self.ram[0x100 + self.s]

    def interrupt(self, vector, brk=False):
        self.push(self.pc >> 8)
        self.push(self.pc & 0xff)
        self.push(self.p | 0x20 | (B if brk else 0))
        self.p = (self.p | I) & ~D
        self.pc = self.read(vector) | self.read(vector + 1) << 8
        self.cycles += 7

    def run_until(self, seconds):
        limit = int(seconds * CLOCK)
        step = self.step
        idle = 0x8091 if self.rom[0x91:0x94] == IDLE else -1
        delay = 0x8f5f if self.rom[0xf5f:0xf64] == DELAY else -1
        while self.cycles < limit:
            if self.nmi_edge:
                self.nmi_edge = False
                self.interrupt(0xfffa)
            elif not self.p & I and self.irq():
                if self.on_tick and self.on_tick():
                    return
                self.interrupt(0xfffe)
            pc = self.pc
            if pc == idle and not self.p & I and self.timer_end is not None:
                self.cycles = max(self.cycles + 3, min(limit, self.timer_end))
            elif pc == delay:
                self.cycles += 7 * (self.a or 256) - 1
                self.a = 0
                self.p = self.p & ~N | Z | C
                self.pc = pc + 5
            else:
                step()

    def nz(self, v):
        self.p = self.p & ~(N | Z) | (v & N) | (0 if v else Z)
        return v

    def adc(self, v):
        if self.p & D:
            raise NotImplementedError(f'decimal mode at {self.pc:04x}')
        r = self.a + v + (self.p & C)
        self.p = self.p & ~(C | V) | (C if r > 0xff else 0) | (V if ~(self.a ^ v) & (self.a ^ r) & 0x80 else 0)
        self.a = self.nz(r & 0xff)

    def compare(self, r, v):
        self.p = self.p & ~C | (C if r >= v else 0)
        self.nz(r - v & 0xff)

    def step(self):
        read, write = self.read, self.write
        pc = self.pc
        op = read(pc)
        lo = read(pc + 1 & 0xffff)
        mode, size, cycles = MODES[op]
        ea = None
        if mode == 'imm':
            ea = pc + 1 & 0xffff
        elif mode == 'zp':
            ea = lo
        elif mode == 'zpx':
            ea = lo + self.x & 0xff
        elif mode == 'zpy':
            ea = lo + self.y & 0xff
        elif mode in ('abs', 'abx', 'aby', 'ind', 'iax'):
            ea = lo | read(pc + 2 & 0xffff) << 8
            if mode == 'abx':
                ea = ea + self.x & 0xffff
            elif mode == 'aby':
                ea = ea + self.y & 0xffff
        elif mode == 'izx':
            z = lo + self.x & 0xff
            ea = self.ram[z] | self.ram[z + 1 & 0xff] << 8
        elif mode == 'izy':
            ea = (self.ram[lo] | self.ram[lo + 1 & 0xff] << 8) + self.y & 0xffff
        elif mode == 'izp':
            ea = self.ram[lo] | self.ram[lo + 1 & 0xff] << 8
        self.pc = pc + size & 0xffff
        self.cycles += cycles
        name = NAMES[op]
        if name == 'lda':
            self.a = self.nz(read(ea))
        elif name == 'sta':
            write(ea, self.a)
        elif name == 'ldx':
            self.x = self.nz(read(ea))
        elif name == 'ldy':
            self.y = self.nz(read(ea))
        elif name == 'stx':
            write(ea, self.x)
        elif name == 'sty':
            write(ea, self.y)
        elif name == 'stz':
            write(ea, 0)
        elif name in BRANCHES:
            flag, wanted = BRANCHES[name]
            if flag is None or bool(self.p & flag) == wanted:
                self.pc = self.pc + (lo - 256 if lo & 0x80 else lo) & 0xffff
                self.cycles += 1
        elif name == 'jsr':
            ret = self.pc - 1 & 0xffff
            self.push(ret >> 8)
            self.push(ret & 0xff)
            self.pc = ea
        elif name == 'rts':
            self.pc = (self.pop() | self.pop() << 8) + 1 & 0xffff
        elif name == 'rti':
            self.p = self.pop() & ~B | 0x20
            self.pc = self.pop() | self.pop() << 8
        elif name == 'jmp':
            if mode == 'ind':
                ea = read(ea) | read(ea + 1 & 0xffff) << 8
            elif mode == 'iax':
                ea = ea + self.x & 0xffff
                ea = read(ea) | read(ea + 1 & 0xffff) << 8
            self.pc = ea
        elif name == 'adc':
            self.adc(read(ea))
        elif name == 'sbc':
            self.adc(read(ea) ^ 0xff)
        elif name == 'cmp':
            self.compare(self.a, read(ea))
        elif name == 'cpx':
            self.compare(self.x, read(ea))
        elif name == 'cpy':
            self.compare(self.y, read(ea))
        elif name == 'and':
            self.a = self.nz(self.a & read(ea))
        elif name == 'ora':
            self.a = self.nz(self.a | read(ea))
        elif name == 'eor':
            self.a = self.nz(self.a ^ read(ea))
        elif name == 'bit':
            v = read(ea)
            self.p = self.p & ~Z | (0 if self.a & v else Z)
            if mode != 'imm':
                self.p = self.p & ~(N | V) | (v & (N | V))
        elif name in ('inc', 'dec', 'asl', 'lsr', 'rol', 'ror'):
            v = self.a if mode == 'acc' else read(ea)
            if name == 'inc':
                v = v + 1 & 0xff
            elif name == 'dec':
                v = v - 1 & 0xff
            else:
                carry = self.p & C
                if name in ('asl', 'rol'):
                    out = v >> 7
                    v = v << 1 & 0xff | (carry if name == 'rol' else 0)
                else:
                    out = v & 1
                    v = v >> 1 | (carry << 7 if name == 'ror' else 0)
                self.p = self.p & ~C | out
            self.nz(v)
            if mode == 'acc':
                self.a = v
            else:
                write(ea, v)
        elif name == 'inx':
            self.x = self.nz(self.x + 1 & 0xff)
        elif name == 'iny':
            self.y = self.nz(self.y + 1 & 0xff)
        elif name == 'dex':
            self.x = self.nz(self.x - 1 & 0xff)
        elif name == 'dey':
            self.y = self.nz(self.y - 1 & 0xff)
        elif name == 'tax':
            self.x = self.nz(self.a)
        elif name == 'tay':
            self.y = self.nz(self.a)
        elif name == 'txa':
            self.a = self.nz(self.x)
        elif name == 'tya':
            self.a = self.nz(self.y)
        elif name == 'tsx':
            self.x = self.nz(self.s)
        elif name == 'txs':
            self.s = self.x
        elif name == 'pha':
            self.push(self.a)
        elif name == 'pla':
            self.a = self.nz(self.pop())
        elif name == 'phx':
            self.push(self.x)
        elif name == 'plx':
            self.x = self.nz(self.pop())
        elif name == 'phy':
            self.push(self.y)
        elif name == 'ply':
            self.y = self.nz(self.pop())
        elif name == 'php':
            self.push(self.p | B | 0x20)
        elif name == 'plp':
            self.p = self.pop() & ~B | 0x20
        elif name == 'clc':
            self.p &= ~C
        elif name == 'sec':
            self.p |= C
        elif name == 'cli':
            self.p &= ~I
        elif name == 'sei':
            self.p |= I
        elif name == 'cld':
            self.p &= ~D
        elif name == 'sed':
            self.p |= D
        elif name == 'clv':
            self.p &= ~V
        elif name == 'trb':
            v = read(ea)
            self.p = self.p & ~Z | (0 if self.a & v else Z)
            write(ea, v & ~self.a)
        elif name == 'tsb':
            v = read(ea)
            self.p = self.p & ~Z | (0 if self.a & v else Z)
            write(ea, v | self.a)
        elif name == 'brk':
            self.pc = pc + 2 & 0xffff
            self.interrupt(0xfffe, True)
        elif name == 'nop':
            pass
        else:
            raise NotImplementedError(f'opcode {op:02x} at {pc:04x}')


def capture(rom, oki_rom, value, max_seconds):
    """Runs one command from a quiet board. Returns its chip writes as (seconds since the
    command, chip, register, value) and, when the driver's memory comes back to a state it
    writes start repeating, the times the repeating part starts and ends (else None, None)."""
    board = Board(rom, oki_rom)
    board.run_until(0.3)
    board.command(1)
    board.run_until(0.5)
    start, first = board.time(), len(board.log) + 1
    board.command(value)
    board.run_until(start + max_seconds)
    events = [(t - start, kind, reg, v) for t, kind, reg, v in board.log[first:]
              if not (kind == 'l' and reg in (2, 4))]
    return (events,) + repeat(events)


def repeat(events, block=400):
    """Finds where a list of chip writes starts repeating: the last `block` writes are
    looked for earlier in the list, and the match is then extended backwards."""
    writes = [e[1:] for e in events]
    n = len(writes)
    if n < 3 * block:
        return None, None
    tail = writes[n - block:]
    first = tail[0]
    for m in range(n - 2 * block, -1, -1):
        if writes[m] == first and writes[m:m + block] == tail:
            period = n - block - m
            i = m
            while i > 0 and writes[i - 1] == writes[i - 1 + period]:
                i -= 1
            return events[i][0], events[i + period][0]
    return None, None


BRANCHES = {'bpl': (N, False), 'bmi': (N, True), 'bvc': (V, False), 'bvs': (V, True), 'bcc': (C, False),
            'bcs': (C, True), 'bne': (Z, False), 'beq': (Z, True), 'bra': (None, True)}
SIZES = {'imp': 1, 'acc': 1, 'imm': 2, 'zp': 2, 'zpx': 2, 'zpy': 2, 'izx': 2, 'izy': 2, 'izp': 2, 'rel': 2,
         'abs': 3, 'abx': 3, 'aby': 3, 'ind': 3, 'iax': 3}
TABLE = """
00 brk imp 7|01 ora izx 6|04 tsb zp 5|05 ora zp 3|06 asl zp 5|08 php imp 3|09 ora imm 2|0a asl acc 2|0c tsb abs 6
0d ora abs 4|0e asl abs 6|10 bpl rel 2|11 ora izy 5|12 ora izp 5|14 trb zp 5|15 ora zpx 4|16 asl zpx 6|18 clc imp 2
19 ora aby 4|1a inc acc 2|1c trb abs 6|1d ora abx 4|1e asl abx 7|20 jsr abs 6|21 and izx 6|24 bit zp 3|25 and zp 3
26 rol zp 5|28 plp imp 4|29 and imm 2|2a rol acc 2|2c bit abs 4|2d and abs 4|2e rol abs 6|30 bmi rel 2|31 and izy 5
32 and izp 5|34 bit zpx 4|35 and zpx 4|36 rol zpx 6|38 sec imp 2|39 and aby 4|3a dec acc 2|3c bit abx 4|3d and abx 4
3e rol abx 7|40 rti imp 6|41 eor izx 6|45 eor zp 3|46 lsr zp 5|48 pha imp 3|49 eor imm 2|4a lsr acc 2|4c jmp abs 3
4d eor abs 4|4e lsr abs 6|50 bvc rel 2|51 eor izy 5|52 eor izp 5|55 eor zpx 4|56 lsr zpx 6|58 cli imp 2|59 eor aby 4
5a phy imp 3|5d eor abx 4|5e lsr abx 7|60 rts imp 6|61 adc izx 6|64 stz zp 3|65 adc zp 3|66 ror zp 5|68 pla imp 4
69 adc imm 2|6a ror acc 2|6c jmp ind 5|6d adc abs 4|6e ror abs 6|70 bvs rel 2|71 adc izy 5|72 adc izp 5|74 stz zpx 4
75 adc zpx 4|76 ror zpx 6|78 sei imp 2|79 adc aby 4|7a ply imp 4|7c jmp iax 6|7d adc abx 4|7e ror abx 7|80 bra rel 2
81 sta izx 6|84 sty zp 3|85 sta zp 3|86 stx zp 3|88 dey imp 2|89 bit imm 2|8a txa imp 2|8c sty abs 4|8d sta abs 4
8e stx abs 4|90 bcc rel 2|91 sta izy 6|92 sta izp 5|94 sty zpx 4|95 sta zpx 4|96 stx zpy 4|98 tya imp 2|99 sta aby 5
9a txs imp 2|9c stz abs 4|9d sta abx 5|9e stz abx 5|a0 ldy imm 2|a1 lda izx 6|a2 ldx imm 2|a4 ldy zp 3|a5 lda zp 3
a6 ldx zp 3|a8 tay imp 2|a9 lda imm 2|aa tax imp 2|ac ldy abs 4|ad lda abs 4|ae ldx abs 4|b0 bcs rel 2|b1 lda izy 5
b2 lda izp 5|b4 ldy zpx 4|b5 lda zpx 4|b6 ldx zpy 4|b8 clv imp 2|b9 lda aby 4|ba tsx imp 2|bc ldy abx 4|bd lda abx 4
be ldx aby 4|c0 cpy imm 2|c1 cmp izx 6|c4 cpy zp 3|c5 cmp zp 3|c6 dec zp 5|c8 iny imp 2|c9 cmp imm 2|ca dex imp 2
cc cpy abs 4|cd cmp abs 4|ce dec abs 6|d0 bne rel 2|d1 cmp izy 5|d2 cmp izp 5|d5 cmp zpx 4|d6 dec zpx 6|d8 cld imp 2
d9 cmp aby 4|da phx imp 3|dd cmp abx 4|de dec abx 7|e0 cpx imm 2|e1 sbc izx 6|e4 cpx zp 3|e5 sbc zp 3|e6 inc zp 5
e8 inx imp 2|e9 sbc imm 2|ea nop imp 2|ec cpx abs 4|ed sbc abs 4|ee inc abs 6|f0 beq rel 2|f1 sbc izy 5|f2 sbc izp 5
f5 sbc zpx 4|f6 inc zpx 6|f8 sed imp 2|f9 sbc aby 4|fa plx imp 4|fd sbc abx 4|fe inc abx 7
"""
NAMES = ['?'] * 256
MODES = [('imp', 1, 2)] * 256
for entry in TABLE.replace('\n', '|').split('|'):
    if entry.strip():
        code, name, mode, cycles = entry.split()
        NAMES[int(code, 16)] = name
        MODES[int(code, 16)] = (mode, SIZES[mode], int(cycles))


def main(argv):
    board = Board(Path(argv[1]).read_bytes(), Path(argv[2]).read_bytes())
    for line in open(argv[3]):
        t, kind, _, value = line.strip().split(',')
        if kind == 'c':
            board.run_until(float(t))
            board.command(int(value, 16))
    board.run_until(board.time() + 5)
    with open(argv[4], 'w') as out:
        for t, kind, reg, value in board.log:
            out.write(f'{t:.6f},{kind},{reg:02x},{value:02x}\n')


if __name__ == '__main__':
    main(sys.argv)
