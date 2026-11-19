"""Convert the arcade's sound to Mega Drive streams.

Each sound command is run alone in the 6502 emulator (sound6502.py) and the
chip writes it makes are translated for the YM2612 and the PSG.

usage: sound.py <robocop_snd.bin> <robocop_oki.bin> --lengths | --convert
"""
import sys
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sound6502  # noqa: E402

EFFECTS = range(0x05, 0x31)
TUNES = range(0x31, 0x3e)
TUNE_SECONDS = 150
EFFECT_SECONDS = 6


FRAME_RATE = 59.92
OPL_TO_OPN2 = (3_000_000 / 72) / (7_670_454 / 144) * 2
OPN_TO_OPN2 = (1_500_000 / 72) / (7_670_454 / 144)
SSG_TO_PSG = (3_579_545 / 32) / (1_500_000 / 64)
OPL_MODULATOR = (0, 1, 2, 8, 9, 10, 16, 17, 18)
OPL_MULTIPLE = (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 10, 12, 12, 15, 15)

END_FRAME, WAIT, STOP, LOOP, PSG, PART2 = range(6)

# A place a voice can be played: (channel 1-6, half). Half 0 is a whole channel;
# halves 1 and 2 are operators 1-2 and 3-4 of channel 3 in its separate-frequency mode.
WHOLE = [(1, 0), (2, 0), (4, 0)]
HALVES = [(3, 1), (3, 2)]
EFFECT_PLACES = [(5, 0)]
OPERATOR_OFFSET = {1: 0, 2: 8, 3: 4, 4: 12}
HALF_FREQUENCY = {1: (0xa9, 0xaa), 2: (0xa8, 0xa2)}


class Writer:
    """Collects YM2612 and PSG writes by frame and drops the ones that change nothing."""

    def __init__(self):
        self.frames = {}
        self.frame = 0
        self.ym = {}
        self.psg = {}
        self.keys3 = 0

    def at(self, seconds):
        self.frame = int(seconds * FRAME_RATE)

    def write(self, channel, reg, value, force=False):
        part = 1 if channel > 3 else 0
        reg += (channel - 1) % 3
        self.raw(part, reg, value, force)

    def raw(self, part, reg, value, force=False):
        if not force and self.ym.get((part, reg)) == value:
            return
        self.ym[part, reg] = value
        self.frames.setdefault(self.frame, []).append((PART2 if part else None, reg, value))

    def key(self, place, on):
        channel, half = place
        code = channel - 1 if channel <= 3 else channel
        if half == 0:
            mask = 0xf0 if on else 0
        else:
            bits = 0x30 if half == 1 else 0xc0
            self.keys3 = self.keys3 | bits if on else self.keys3 & ~bits
            mask = self.keys3
        self.frames.setdefault(self.frame, []).append((None, 0x28, mask | code))

    def psg_bytes(self, key, *values):
        if self.psg.get(key) == values:
            return
        self.psg[key] = values
        for value in values:
            self.frames.setdefault(self.frame, []).append((PSG, value, None))

    def forget(self):
        self.ym.clear()
        self.psg.clear()

    def encode(self, loop_frame=None, end_frame=None):
        out = bytearray()
        loop_offset = None
        last = max(self.frames) if self.frames else 0
        end = last + 1 if end_frame is None else end_frame
        frame = 0
        while frame < end:
            if frame == loop_frame:
                loop_offset = len(out)
            for kind, a, b in self.frames.get(frame, ()):
                if kind == PSG:
                    out += bytes((PSG, a))
                elif kind == PART2:
                    out += bytes((PART2, a, b))
                else:
                    out += bytes((a, b))
            gap = 1
            while (frame + gap < end and frame + gap not in self.frames and frame + gap != loop_frame
                   and gap < 256):
                gap += 1
            out += bytes((END_FRAME,)) if gap == 1 else bytes((WAIT, gap - 1))
            frame += gap
        if loop_offset is None:
            out.append(STOP)
        else:
            out += bytes((LOOP,)) + loop_offset.to_bytes(3, 'big')
        return bytes(out)


def opn2_frequency(fnum, block, scale):
    value = fnum * scale
    while value >= 2048 and block < 7:
        value /= 2
        block += 1
    while value < 1024 and block > 0:
        value *= 2
        block -= 1
    return min(int(round(value)), 2047), block


def opl_operator(r20, r40, r60, r80):
    """One YM3812 operator's four registers as the YM2612's six."""
    attack, decay = r60 >> 4, r60 & 15
    sustain, release = r80 >> 4, r80 & 15
    return {
        0x30: OPL_MULTIPLE[r20 & 15],
        0x40: min(127, r40 & 63),
        0x50: (0x40 if r20 & 0x10 else 0) | (min(31, attack * 2 + 1) if attack else 0),
        0x60: min(31, decay * 2),
        0x70: 0 if r20 & 0x20 else min(31, release * 2),
        0x80: sustain << 4 | release,
    }


class Voices:
    """Hands the arcade's voices places on the YM2612. A voice keeps its place from one
    note to the next; a new voice takes a free place, else the place of the voice that
    was released longest ago, else the one keyed longest ago."""

    def __init__(self, places):
        self.places = list(places)
        self.owner = {}
        self.place = {}
        self.keyed = {}
        self.since = {}
        self.stolen = self.notes = 0

    def get(self, voice, allowed, now):
        self.notes += 1
        place = self.place.get(voice)
        if place is None:
            candidates = [p for p in allowed if p in self.places]
            free = [p for p in candidates if p not in self.owner]
            if free:
                place = free[0]
            else:
                released = [p for p in candidates if not self.keyed[self.owner[p]]]
                pool = released or candidates
                if not pool:
                    return None
                place = min(pool, key=lambda p: self.since[self.owner[p]])
                del self.place[self.owner[place]]
                self.stolen += 1
            self.owner[place] = voice
            self.place[voice] = place
        self.keyed[voice] = True
        self.since[voice] = now
        return place

    def release(self, voice, now):
        if voice in self.place:
            self.keyed[voice] = False
            self.since[voice] = now


class Converter:
    def __init__(self, places, whole_places):
        self.out = Writer()
        self.voices = Voices(places)
        self.whole = whole_places
        self.opl = [0] * 256
        self.opn = [0] * 256
        self.opn_keys = [0, 0, 0]
        self.ssg = [0] * 16

    def start(self, tune):
        out = self.out
        if tune:
            out.raw(0, 0x27, 0x40, True)
            for channel in (1, 2, 3, 4):
                out.key((channel, 0), False)
                for operator in range(4):
                    out.write(channel, 0x40 + operator * 4, 127, True)
                out.write(channel, 0xb0, 4, True)
                out.write(channel, 0xb4, 0xc0, True)
        else:
            out.key((5, 0), False)
            for channel in range(4):
                out.psg_bytes(('v', channel), 0x9f | channel << 5)

    def silence_spare_operators(self, channel):
        for operator in (3, 4):
            self.out.write(channel, 0x40 + OPERATOR_OFFSET[operator], 127)

    def opl_patch(self, c, place):
        channel, half = place
        opl, out = self.opl, self.out
        m = OPL_MODULATOR[c]
        operators = (3, 4) if half == 2 else (1, 2)
        for operator, o in zip(operators, (m, m + 3)):
            for reg, value in opl_operator(opl[0x20 + o], opl[0x40 + o], opl[0x60 + o], opl[0x80 + o]).items():
                out.write(channel, reg + OPERATOR_OFFSET[operator], value)
        feedback, additive = opl[0xc0 + c] >> 1 & 7, opl[0xc0 + c] & 1
        if half == 0:
            self.silence_spare_operators(channel)
            out.write(channel, 0xb0, feedback << 3 | (7 if additive else 4))
        elif half == 1:
            out.write(channel, 0xb0, feedback << 3 | 4)
        out.write(channel, 0xb4, 0xc0)

    def opl_pitch(self, c, place):
        channel, half = place
        fnum = self.opl[0xa0 + c] | (self.opl[0xb0 + c] & 3) << 8
        fnum, block = opn2_frequency(fnum, self.opl[0xb0 + c] >> 2 & 7, OPL_TO_OPN2)
        high, low = block << 3 | fnum >> 8, fnum & 255
        if half == 0:
            self.out.write(channel, 0xa4, high, True)
            self.out.write(channel, 0xa0, low, True)
        else:
            for reg in HALF_FREQUENCY[half]:
                self.out.raw(0, reg + 4, high, True)
                self.out.raw(0, reg, low, True)

    def opl_write(self, t, reg, value):
        opl = self.opl
        old = opl[reg]
        opl[reg] = value
        if 0xb0 <= reg <= 0xb8:
            c = reg - 0xb0
            voice = ('l', c)
            if value & 0x20 and not old & 0x20:
                feedback = opl[0xc0 + c] >> 1 & 7
                order = HALVES[::-1] + self.whole if not feedback else [HALVES[0]] + self.whole + [HALVES[1]]
                place = self.voices.get(voice, order, t)
                if place:
                    self.out.key(place, False)
                    self.opl_patch(c, place)
                    self.opl_pitch(c, place)
                    self.out.key(place, True)
            elif old & 0x20 and not value & 0x20:
                place = self.voices.place.get(voice)
                if place:
                    self.out.key(place, False)
                self.voices.release(voice, t)
            elif value & 0x20:
                place = self.voices.place.get(voice)
                if place:
                    self.opl_pitch(c, place)
            return
        if 0xa0 <= reg <= 0xa8:
            c = reg - 0xa0
        elif 0xc0 <= reg <= 0xc8:
            c = reg - 0xc0
        elif 0x20 <= reg <= 0x95 and (reg & 0x1f) in OPL_OPERATORS:
            c = OPL_OPERATORS[reg & 0x1f]
        else:
            return
        place = self.voices.place.get(('l', c))
        if place and self.voices.keyed.get(('l', c)):
            if 0xa0 <= reg <= 0xa8:
                self.opl_pitch(c, place)
            else:
                self.opl_patch(c, place)

    def opn_copy(self, c, place):
        channel = place[0]
        for base in (0x30, 0x40, 0x50, 0x60, 0x70, 0x80, 0x90):
            for slot in range(4):
                self.out.write(channel, base + slot * 4, self.opn[base + slot * 4 + c])
        self.out.write(channel, 0xb0, self.opn[0xb0 + c])
        self.out.write(channel, 0xb4, 0xc0)

    def opn_pitch(self, c, place):
        fnum = self.opn[0xa0 + c] | (self.opn[0xa4 + c] & 7) << 8
        fnum, block = opn2_frequency(fnum, self.opn[0xa4 + c] >> 3 & 7, OPN_TO_OPN2)
        self.out.write(place[0], 0xa4, block << 3 | fnum >> 8, True)
        self.out.write(place[0], 0xa0, fnum & 255, True)

    def opn_write(self, t, reg, value):
        opn = self.opn
        opn[reg] = value
        if reg < 0x10:
            self.ssg[reg] = value
            self.ssg_update()
            return
        if reg == 0x28:
            c = value & 3
            if c > 2:
                return
            voice = ('n', c)
            keys = value >> 4
            if keys and not self.opn_keys[c]:
                place = self.voices.get(voice, self.whole, t)
                if place:
                    self.out.key(place, False)
                    self.opn_copy(c, place)
                    self.opn_pitch(c, place)
                    self.out.key(place, True)
            elif not keys and self.opn_keys[c]:
                place = self.voices.place.get(voice)
                if place:
                    self.out.key(place, False)
                self.voices.release(voice, t)
            self.opn_keys[c] = keys
            return
        if 0x30 <= reg < 0xb8 and (reg & 3) < 3:
            c = reg & 3
            place = self.voices.place.get(('n', c))
            if not place or not self.opn_keys[c]:
                return
            if 0xa0 <= reg < 0xa8:
                if reg < 0xa4:
                    self.opn_pitch(c, place)
            elif reg < 0xa0 or 0xb0 <= reg < 0xb4:
                self.out.write(place[0], reg - c, value)

    def ssg_update(self):
        ssg, out = self.ssg, self.out
        noise_volume = 0
        for c in range(3):
            volume = 12 if ssg[8 + c] & 0x10 else ssg[8 + c] & 15
            tone = not ssg[7] >> c & 1
            if not ssg[7] >> (c + 3) & 1 and volume:
                noise_volume = max(noise_volume, volume)
            period = ssg[c * 2] | (ssg[c * 2 + 1] & 15) << 8
            if tone and volume and period:
                n = max(1, min(1023, int(round(period * SSG_TO_PSG))))
                out.psg_bytes(('t', c), 0x80 | c << 5 | n & 15, n >> 4)
                out.psg_bytes(('v', c), 0x90 | c << 5 | min(15, int(round((15 - volume) * 1.5))))
            else:
                out.psg_bytes(('v', c), 0x9f | c << 5)
        if noise_volume:
            rate = 0 if ssg[6] & 31 < 8 else 1 if ssg[6] & 31 < 16 else 2
            out.psg_bytes(('n',), 0xe4 | rate)
            out.psg_bytes(('v', 3), 0xf0 | min(15, int(round((15 - noise_volume) * 1.5))))
        else:
            out.psg_bytes(('v', 3), 0xff)

    def feed(self, events, loop_start=None):
        for t, kind, reg, value in events:
            if loop_start is not None and t >= loop_start:
                self.out.forget()
                loop_start = None
            self.out.at(t)
            if kind == 'l':
                self.opl_write(t, reg, value)
            elif kind == 'n':
                self.opn_write(t, reg, value)


OPL_OPERATORS = {m + k: c for c, m in enumerate(OPL_MODULATOR) for k in (0, 3)}


def convert(events, tune, loop_start=None, loop_end=None):
    """Returns the stream and (notes, notes that took another voice's place)."""
    converter = Converter(WHOLE + HALVES if tune else EFFECT_PLACES, WHOLE if tune else EFFECT_PLACES)
    converter.out.at(0)
    converter.start(tune)
    if loop_end is not None:
        events = [e for e in events if e[0] < loop_end]
    converter.feed(events, loop_start)
    if loop_end is not None:
        stream = converter.out.encode(int(loop_start * FRAME_RATE), int(loop_end * FRAME_RATE))
    else:
        stream = converter.out.encode()
    return stream, (converter.voices.notes, converter.voices.stolen)


ADPCM_STEPS = [16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143,
               157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658, 724, 796, 876, 963,
               1060, 1166, 1282, 1411, 1552]
ADPCM_INDEX = [-1, -1, -1, -1, 2, 4, 6, 8]
SAMPLE_COMMANDS = range(0x3f, 0x50)


def samples(oki):
    """The OKI M6295's samples (4-bit ADPCM, 12-bit output) as unsigned 8-bit PCM, by sample number."""
    out = {}
    for n in range(1, 128):
        start = int.from_bytes(oki[n * 8:n * 8 + 3], 'big')
        end = int.from_bytes(oki[n * 8 + 3:n * 8 + 6], 'big')
        if not start < end < len(oki):
            continue
        signal, index, pcm = 0, 0, bytearray()
        for byte in oki[start:end + 1]:
            for nibble in (byte >> 4, byte & 15):
                step = ADPCM_STEPS[index]
                delta = step >> 3
                if nibble & 1:
                    delta += step >> 2
                if nibble & 2:
                    delta += step >> 1
                if nibble & 4:
                    delta += step
                signal = max(-2048, min(2047, signal - delta if nibble & 8 else signal + delta))
                index = max(0, min(48, index + ADPCM_INDEX[nibble & 7]))
                pcm.append((signal >> 4) + 128)
        out[n] = bytes(pcm)
    return out


def z80_driver():
    """The Z80's whole program: wait for a sample in the mailbox at 0x1F00 (flag, address
    low, middle, high, length low, high), then send its bytes to the YM2612's DAC at about
    7,600 a second, switching ROM bank as the address passes each 32 KB."""
    MAILBOX, BANK = 0x1f00, 0x1f10
    code, labels, fixups = bytearray(), {}, []

    def emit(*values):
        code.extend(values)

    def word(value):
        emit(value & 255, value >> 8)

    def label(name):
        labels[name] = len(code)

    def jump(opcode, name):
        emit(opcode, 0)
        fixups.append((len(code) - 1, name, True))

    def call(name):
        emit(0xcd, 0, 0)
        fixups.append((len(code) - 2, name, False))

    emit(0xf3)
    emit(0x31); word(0x1ff0)
    label('idle')
    emit(0x3a); word(MAILBOX)
    emit(0xb7)
    jump(0x28, 'idle')
    emit(0xaf)
    emit(0x32); word(MAILBOX)
    emit(0x2a); word(MAILBOX + 1)
    emit(0x3a); word(MAILBOX + 3)
    emit(0x47, 0x7c, 0x07, 0x78, 0x17)
    call('bank')
    emit(0xcb, 0xfc)
    emit(0xed, 0x5b); word(MAILBOX + 4)
    label('play')
    emit(0x3a); word(MAILBOX)
    emit(0xb7)
    jump(0x20, 'idle')
    emit(0x3e, 0x2a)
    emit(0x32); word(0x4000)
    emit(0x7e)
    emit(0x32); word(0x4001)
    emit(0x06, 27)
    emit(0x10, 0xfe)
    emit(0x23, 0x7c, 0xb7)
    jump(0x20, 'same_bank')
    emit(0x3a); word(BANK)
    emit(0x3c)
    call('bank')
    emit(0x26, 0x80)
    label('same_bank')
    emit(0x1b, 0x7a, 0xb3)
    jump(0x20, 'play')
    emit(0x3e, 0x2a)
    emit(0x32); word(0x4000)
    emit(0x3e, 0x80)
    emit(0x32); word(0x4001)
    jump(0x18, 'idle')
    label('bank')
    emit(0x32); word(BANK)
    emit(0x06, 8)
    label('bit')
    emit(0x32); word(0x6000)
    emit(0x0f)
    jump(0x10, 'bit')
    emit(0xaf)
    emit(0x32); word(0x6000)
    emit(0xc9)
    for at, name, relative in fixups:
        if relative:
            code[at] = labels[name] - (at + 1) & 255
        else:
            code[at], code[at + 1] = labels[name] & 255, labels[name] >> 8
    return bytes(code)


def _capture(args):
    rom, oki, value = args
    seconds = TUNE_SECONDS if value in TUNES else EFFECT_SECONDS
    return value, sound6502.capture(rom, oki, value, seconds)


def capture_all(rom, oki, values):
    with ProcessPoolExecutor() as pool:
        return dict(pool.map(_capture, [(rom, oki, v) for v in values]))


def build(rom, oki, report=None):
    """Returns {command: stream} for every tune and effect."""
    streams = {}
    for value, (events, start, end) in sorted(capture_all(rom, oki, list(EFFECTS) + list(TUNES)).items()):
        if not events:
            continue
        tune = value in TUNES
        stream, (notes, stolen) = convert(events, tune, start, end)
        streams[value] = stream
        if report is not None and tune:
            length = f'repeats from {start:.1f} s to {end:.1f} s' if start is not None else f'{events[-1][0]:.1f} s, once'
            report.append(f'tune {value:02x}: {len(stream)} bytes, {length}; {notes} notes, {stolen} took a sounding voice\'s place')
    return streams


def main(argv):
    rom, oki = Path(argv[1]).read_bytes(), Path(argv[2]).read_bytes()
    if '--convert' in argv:
        report = []
        streams = build(rom, oki, report)
        print('\n'.join(report))
        print(f'{len(streams)} streams, {sum(map(len, streams.values()))} bytes')
    if '--lengths' in argv:
        for value, (events, start, end) in sorted(capture_all(rom, oki, TUNES).items()):
            last = events[-1][0] if events else 0
            loop = f'repeats {start:.2f}-{end:.2f} ({end - start:.1f} s)' if start is not None else 'no repeat found'
            print(f'{value:02x}: {len(events):6d} writes, last at {last:6.1f} s, {loop}')


if __name__ == '__main__':
    main(sys.argv)
