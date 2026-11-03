"""Synthesise an original, royalty-free background track for the depotOS videos.

120 BPM (one bar = 2 s), chords Am - F - C - G.
  intro   pads + arpeggio, riser into the drop
  drop    kick, clap, hats, bass (bar 3 of the track)
  +8 bars a light lead melody joins
  end     drums stop on a final chord that rings out

usage: python make_music.py <duration_s> <out.wav> [--drop S] [--end S]
  --drop  time of the beat drop in the video (default 6.0)
  --end   time of the final chord in the video (default 44.0)
The musical grid is shifted so the drop lands exactly on --drop; --end is snapped to the nearest bar.
"""
import argparse
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt, fftconvolve

ap = argparse.ArgumentParser()
ap.add_argument("duration", type=float)
ap.add_argument("out")
ap.add_argument("--drop", type=float, default=6.0)
ap.add_argument("--end", type=float, default=44.0)
args = ap.parse_args()

SR = 44100
BPM = 120
BEAT = 60 / BPM
BAR = 4 * BEAT
rng = np.random.default_rng(7)

# Render on a grid where the drop is bar 3, then cut the head so the drop lands on args.drop.
SHIFT = 3 * BAR - args.drop                       # seconds to trim from the start
DUR = args.duration + SHIFT                       # rendered length before trimming
N = int(DUR * SR) + SR
DROP = 3 * BAR
END_HIT = round((args.end + SHIFT) / BAR) * BAR
LEAD_IN = DROP + 8 * BAR

def hz(m): return 440.0 * 2 ** ((m - 69) / 12)
def t_of(n): return np.arange(n) / SR
def lp(x, f): return sosfilt(butter(2, f, "low", fs=SR, output="sos"), x)
def hp(x, f): return sosfilt(butter(2, f, "high", fs=SR, output="sos"), x)
def bp(x, lo, hi): return sosfilt(butter(2, [lo, hi], "band", fs=SR, output="sos"), x)

def place(buf, sig, start, gain=1.0, pan=0.0):
    i = int(start * SR)
    if i >= N or i < 0: return
    sig = sig[: N - i]
    l, r = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
    buf[0, i:i + len(sig)] += sig * gain * l * 1.414
    buf[1, i:i + len(sig)] += sig * gain * r * 1.414

def saw(f, n, detune=0.0):
    ph = (np.arange(n) * f * (1 + detune) / SR) % 1.0
    return 2 * ph - 1

def env(n, a, d, s=0.0, r=None):
    """attack, then exponential decay toward sustain level s; optional release at the end."""
    e = np.ones(n)
    na = max(1, int(a * SR))
    e[:na] = np.linspace(0, 1, na)
    k = np.arange(n - na) / SR
    e[na:] = s + (1 - s) * np.exp(-k / max(d, 1e-4))
    if r:
        nr = min(n, int(r * SR))
        e[-nr:] *= np.linspace(1, 0, nr)
    return e

CHORDS = [  # (bass root, chord tones) as MIDI notes
    (45, [57, 60, 64]),   # Am
    (41, [57, 60, 65]),   # F  (A C F voicing keeps the pad smooth)
    (48, [55, 60, 64]),   # C
    (43, [55, 59, 62]),   # G
]
def chord_at(bar): return CHORDS[bar % 4]

mus = np.zeros((2, N)); drm = np.zeros((2, N)); send = np.zeros((2, N))
n_bars = int(np.ceil(DUR / BAR)) + 1

# Pads: detuned saws, low-passed, slow attack.
for b in range(n_bars):
    start = b * BAR
    if start > END_HIT: break
    root, tones = chord_at(b)
    n = int(BAR * SR) + int(0.3 * SR)
    sig = np.zeros(n)
    for m in tones:
        for dt in (-0.004, 0.0, 0.005):
            sig += saw(hz(m), n, dt)
    sig = lp(sig, 1400 if start < DROP else 2200) / 9
    sig *= env(n, 0.35, 10, 1.0, r=0.3)
    g = 0.22 if start < DROP else 0.28
    place(mus, sig, start, g, -0.25); place(mus, sig, start + 0.012, g, 0.25)
    place(send, sig, start, 0.18)

# Arpeggio: 16th-note plucks, ping-pong panned, filter opens toward the drop.
PATTERN = [0, 1, 2, 1, 3, 2, 1, 2, 0, 1, 2, 1, 3, 2, 3, 2]
step = BEAT / 4
for b in range(n_bars):
    root, tones = chord_at(b)
    pool = [t + 12 for t in tones] + [tones[0] + 24]
    for k, idx in enumerate(PATTERN):
        st = b * BAR + k * step
        if st >= END_HIT: break
        if st < BAR and k % 2: continue
        n = int(0.32 * SR)
        f = hz(pool[idx])
        sig = (np.sin(2 * np.pi * f * t_of(n)) + 0.35 * saw(f, n)) * env(n, 0.003, 0.11)
        sig = lp(sig, 1200 + 3800 * min(1.0, st / DROP))
        place(mus, sig, st, 0.10 if st < DROP else 0.12, 0.45 if k % 2 else -0.45)
        place(send, sig, st, 0.10)

# Bass: off-beat 8ths after the drop.
for b in range(n_bars):
    start = b * BAR
    if start < DROP or start >= END_HIT: continue
    root, _ = chord_at(b)
    for k in range(1, 8, 2):
        st = start + k * BEAT / 2
        n = int(BEAT / 2 * 0.9 * SR)
        m = root + (12 if k == 7 else 0)
        sig = np.sin(2 * np.pi * hz(m) * t_of(n)) + 0.25 * lp(saw(hz(m), n), 600)
        place(mus, sig * env(n, 0.005, 0.18, 0.5, r=0.03), st, 0.30)

# Lead: a light bell motif for the second half.
MOTIF = [(0.0, 2), (1.0, 1), (1.5, 2), (2.5, 3), (3.0, 2)]
for b in range(n_bars):
    start = b * BAR
    if start < LEAD_IN or start >= END_HIT: continue
    _, tones = chord_at(b)
    pool = [t + 12 for t in tones] + [tones[0] + 24]
    for beat, idx in MOTIF:
        n = int(0.7 * SR); f = hz(pool[idx] + 12); tt = t_of(n)
        sig = (np.sin(2*np.pi*f*tt) + 0.3*np.sin(2*np.pi*2*f*tt) + 0.12*np.sin(2*np.pi*3.01*f*tt)) * env(n, 0.004, 0.25)
        place(mus, sig, start + beat * BEAT, 0.07, 0.15)
        place(send, sig, start + beat * BEAT, 0.12)

# --- drums ---
def kick():
    n = int(0.35 * SR); tt = t_of(n)
    ph = 2 * np.pi * np.cumsum(45 + 95 * np.exp(-tt / 0.035)) / SR
    click = hp(rng.standard_normal(n), 3000) * np.exp(-tt / 0.004) * 0.3
    return np.sin(ph) * np.exp(-tt / 0.16) + click

def clap():
    n = int(0.25 * SR); tt = t_of(n)
    e = np.exp(-tt / 0.06)
    for off in (0.0, 0.011, 0.022):
        i = int(off * SR); e[i:i + 80] += 0.7
    return bp(rng.standard_normal(n), 900, 5000) * e * 0.6

def hat(open_=False):
    n = int((0.22 if open_ else 0.05) * SR); tt = t_of(n)
    return hp(rng.standard_normal(n), 7000) * np.exp(-tt / (0.07 if open_ else 0.012))

def crash(length=2.2):
    n = int(length * SR); tt = t_of(n)
    return hp(rng.standard_normal(n), 4000) * np.exp(-tt / (length / 3.5))

kick_times = []
for b in range(n_bars):
    for beat in range(4):
        st = b * BAR + beat * BEAT
        if DROP <= st < END_HIT:
            place(drm, kick(), st, 0.85); kick_times.append(st)
            if beat in (1, 3): place(drm, clap(), st, 0.32, 0.05); place(send, clap(), st, 0.10)
            place(drm, hat(True), st + BEAT / 2, 0.09, 0.3)
            place(drm, hat(), st + BEAT / 4, 0.05, -0.3); place(drm, hat(), st + 3 * BEAT / 4, 0.05, -0.3)
        elif DROP - BAR <= st < DROP:
            place(drm, hat(), st + BEAT / 2, 0.05, 0.3)

# Riser into the drop, with a building clap roll.
n = int(BAR * SR); tt = t_of(n); noise = rng.standard_normal(n); rise = np.zeros(n)
for i, seg in enumerate(np.array_split(np.arange(n), 16)):
    lo = 400 * 2 ** (i / 4); rise[seg] = bp(noise, lo, min(lo * 4, 18000))[seg]
rise *= (tt / tt[-1]) ** 2
place(drm, rise, DROP - BAR, 0.22); place(send, rise, DROP - BAR, 0.10)
for k in range(16):
    place(drm, clap(), DROP - BAR / 2 + k * BAR / 32, 0.04 + 0.16 * k / 15)

# Impacts on the drop and the final chord.
for hit in (DROP, END_HIT):
    place(drm, crash(), hit, 0.20); place(send, crash(), hit, 0.15)
    n = int(1.2 * SR); tt = t_of(n)
    place(drm, np.sin(2 * np.pi * (38 + 30 * np.exp(-tt / 0.08)) * tt) * np.exp(-tt / 0.5), hit, 0.7)

# Final chord: bright C major ringing out to the end.
n = int(max(1.0, DUR - END_HIT + 0.5) * SR)
sig = np.zeros(n)
for m in [60, 64, 67, 72, 48, 36]:
    for dt in (-0.004, 0.0, 0.004):
        sig += saw(hz(m), n, dt)
sig = lp(sig, 2600) / 14 * env(n, 0.01, 1.4, 0.15)
place(mus, sig, END_HIT, 0.5, -0.2); place(mus, sig, END_HIT + 0.01, 0.5, 0.2); place(send, sig, END_HIT, 0.3)

# --- mix ---
duck = np.ones(N)   # sidechain pump on every kick
for kt in kick_times:
    i = int(kt * SR); n = int(BEAT * SR)
    seg = 1 - 0.55 * np.exp(-np.arange(n) / SR / 0.09)
    duck[i:i + n] = np.minimum(duck[i:i + n], seg[: len(duck[i:i + n])])
mus *= duck

n_ir = int(1.6 * SR); tt = t_of(n_ir)
ir = np.stack([rng.standard_normal(n_ir), rng.standard_normal(n_ir)]) * np.exp(-tt / 0.45)
ir = np.stack([lp(ir[0], 6000), lp(ir[1], 6000)]) * 0.02
wet = np.stack([hp(fftconvolve(send[0], ir[0])[:N], 250), hp(fftconvolve(send[1], ir[1])[:N], 250)])

mix = (mus + drm + wet * 0.9)[:, int(SHIFT * SR): int(DUR * SR)]
fi, fo = int(0.25 * SR), int(1.6 * SR)
mix[:, :fi] *= np.linspace(0, 1, fi)
mix[:, -fo:] *= np.linspace(1, 0, fo) ** 1.5
mix /= np.max(np.abs(mix)) + 1e-9
mix = np.tanh(mix * 1.6) / np.tanh(1.6) * 0.89
wavfile.write(args.out, SR, (mix.T * 32767).astype(np.int16))
print(f"wrote {args.out}: {mix.shape[1] / SR:.2f}s  drop at {args.drop:.2f}s  final chord at {END_HIT - SHIFT:.2f}s")
