"""Compare the pitch content of two recordings (MAME -wavwrite) of the same music.

usage: compare_audio.py <reference.wav> <other.wav> [from seconds] [to seconds]
Each tenth of a second becomes a 12-bin chroma vector (energy per pitch class,
110 Hz to 3.5 kHz). Prints the lag at which the two agree best and the mean
correlation of their chroma there, and the same after shifting one by each
number of semitones: music that is right gives a clear peak at 0.
"""
import sys
import wave

import numpy as np

STEP = 0.1


def chroma(path, start, end):
    w = wave.open(path)
    rate, channels = w.getframerate(), w.getnchannels()
    data = np.frombuffer(w.readframes(w.getnframes()), dtype='<i2').astype(np.float64)
    data = data.reshape(-1, channels).mean(axis=1)[int(start * rate):int(end * rate)]
    size = int(rate * STEP)
    window = np.hanning(size * 2)
    freqs = np.fft.rfftfreq(size * 2, 1 / rate)
    keep = (freqs >= 110) & (freqs <= 3500)
    classes = np.round(12 * np.log2(freqs[keep] / 440)).astype(int) % 12
    out = []
    for i in range(0, len(data) - size * 2, size):
        power = np.abs(np.fft.rfft(data[i:i + size * 2] * window))[keep] ** 2
        vector = np.bincount(classes, weights=power, minlength=12)
        out.append(vector / (np.linalg.norm(vector) + 1e-9))
    return np.array(out)


def agreement(a, b, lag):
    if lag >= 0:
        a, b = a[lag:], b
    else:
        a, b = a, b[-lag:]
    n = min(len(a), len(b))
    return float((a[:n] * b[:n]).sum(axis=1).mean()) if n > 20 else 0.0


def main(argv):
    start = float(argv[3]) if len(argv) > 3 else 0
    end = float(argv[4]) if len(argv) > 4 else 1e9
    a, b = chroma(argv[1], start, end), chroma(argv[2], start, end)
    best = max(range(-30, 31), key=lambda lag: agreement(a, b, lag))
    print(f'best lag {best * STEP:+.1f} s, chroma agreement {agreement(a, b, best):.2f} (1 = same pitch classes, about 0.3 = unrelated)')
    shifts = [max(agreement(a, np.roll(b, s, axis=1), lag) for lag in range(best - 3, best + 4)) for s in range(12)]
    print('by semitone shift of the second:', ' '.join(f'{s}:{v:.2f}' for s, v in enumerate(shifts)))


if __name__ == '__main__':
    main(sys.argv)
