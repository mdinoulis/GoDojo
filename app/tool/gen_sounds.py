"""Synthesises the app's sound effects (no third-party audio needed).

  stone.wav   - a stone placed on a wooden board: sharp click + body thump
  capture.wav - captured stones being picked up: a short stone-on-stone rattle

Run: python tool/gen_sounds.py   (writes assets/sounds/*.wav)
"""
import os
import wave

import numpy as np

RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sounds")
rng = np.random.default_rng(7)


def t(seconds):
    return np.arange(int(RATE * seconds)) / RATE


def bandpassed_noise(n, lo, hi):
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1 / RATE)
    spec[(f < lo) | (f > hi)] = 0
    return np.fft.irfft(spec, n)


def click(duration, partials, noise_band, noise_decay, noise_gain):
    """Damped sinusoids (freq, decay seconds, gain) plus a filtered noise burst."""
    x = t(duration)
    out = np.zeros_like(x)
    for freq, decay, gain in partials:
        out += gain * np.sin(2 * np.pi * freq * x + rng.uniform(0, np.pi)) * np.exp(-x / decay)
    out += noise_gain * bandpassed_noise(len(x), *noise_band) * np.exp(-x / noise_decay)
    attack = np.minimum(1, x / 0.0008)  # avoid a hard edge
    return out * attack


def stone():
    s = click(
        0.16,
        partials=[(185, 0.035, 0.55), (420, 0.020, 0.35), (2350, 0.010, 0.45),
                  (3600, 0.006, 0.30), (5200, 0.004, 0.15)],
        noise_band=(1500, 9000), noise_decay=0.004, noise_gain=0.9)
    return s


def capture():
    total = np.zeros(int(RATE * 0.42))
    starts = [0.0, 0.085, 0.15, 0.24]
    for i, st in enumerate(starts):
        pitch = 1 + 0.06 * rng.standard_normal()
        c = click(
            0.09,
            partials=[(3900 * pitch, 0.012, 0.5), (6100 * pitch, 0.007, 0.35),
                      (2600 * pitch, 0.015, 0.25)],
            noise_band=(3000, 12000), noise_decay=0.003, noise_gain=0.6)
        c *= 0.9 - 0.15 * i
        a = int(RATE * st)
        total[a:a + len(c)] += c
    return total


def write(name, samples, peak=0.8):
    samples = samples / np.max(np.abs(samples)) * peak
    fade = np.linspace(1, 0, int(RATE * 0.01))
    samples[-len(fade):] *= fade
    data = (samples * 32767).astype("<i2").tobytes()
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)
    print(name, f"{len(samples) / RATE:.2f}s")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    write("stone.wav", stone())
    write("capture.wav", capture(), peak=0.6)
