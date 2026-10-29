"""Synthesizes Daccord's interface sounds (assets/sfx) from scratch.

Soft, rounded "bloops" in the spirit of other voice chat apps — a mallet-like
tone (a fundamental with a couple of quickly fading overtones), a gentle
attack, a one-pole low-pass for warmth and a short stereo reverb tail so the
notes don't stop dead. Written from nothing but math so the project owns them
outright. Run from the repository root: python tool/make_sfx.py
"""
import math
import struct
import wave

RATE = 44100


def note(freq, dur, amp=0.5, attack=0.012, decay=7.0, bend=0.0, bright=0.30):
    """One mallet-like note of [dur] seconds.

    [bend] is a quick pitch drop (in semitones) over the first 40 ms, which
    gives the "bloop" character; [bright] scales the overtones.
    """
    out = []
    phase = 0.0
    n = int(dur * RATE)
    for i in range(n):
        t = i / RATE
        glide = bend * max(0.0, 1.0 - t / 0.04)
        f = freq * (2 ** (glide / 12))
        phase += 2 * math.pi * f / RATE
        env = (1 - math.exp(-t / attack)) * math.exp(-decay * t)
        s = (
            math.sin(phase)
            + bright * 0.55 * math.exp(-decay * 2.2 * t) * math.sin(2 * phase)
            + bright * 0.25 * math.exp(-decay * 3.5 * t) * math.sin(3 * phase + 0.4)
        )
        out.append(amp * env * s)
    return out


def silence(dur):
    return [0.0] * int(dur * RATE)


def mix(*parts):
    """Overlays (offset_seconds, samples) parts."""
    length = max(int(o * RATE) + len(p) for o, p in parts)
    buf = [0.0] * length
    for offset, samples in parts:
        start = int(offset * RATE)
        for i, s in enumerate(samples):
            buf[start + i] += s
    return buf


def lowpass(samples, cutoff):
    """One-pole low-pass at [cutoff] Hz."""
    a = 1 - math.exp(-2 * math.pi * cutoff / RATE)
    out = []
    y = 0.0
    for s in samples:
        y += a * (s - y)
        out.append(y)
    return out


def reverb(samples, wet=0.16, tail=0.25, delays=(0.0297, 0.0371, 0.0411, 0.0437)):
    """A tiny Schroeder reverb: four comb filters into one all-pass."""
    n = len(samples) + int(tail * RATE)
    dry = samples + silence(tail)
    acc = [0.0] * n
    for d in delays:
        k = int(d * RATE)
        buf = [0.0] * n
        fb = 0.62
        for i in range(n):
            buf[i] = dry[i] + (buf[i - k] * fb if i >= k else 0.0)
            acc[i] += buf[i] / len(delays)
    k = int(0.005 * RATE)
    g = 0.5
    ap = [0.0] * n
    for i in range(n):
        x = acc[i]
        y_del = ap[i - k] if i >= k else 0.0
        x_del = acc[i - k] if i >= k else 0.0
        ap[i] = -g * x + x_del + g * y_del
    return [d + wet * r for d, r in zip(dry, ap)]


def polish(samples, cutoff=3200, wet=0.16):
    return reverb(lowpass(samples, cutoff), wet=wet)


def write(name, left, right=None):
    right = right or left
    peak = max(1e-9, max(max(abs(s) for s in left), max(abs(s) for s in right)))
    gain = min(1.0, 0.8 / peak)
    fade = int(0.006 * RATE)
    n = max(len(left), len(right))
    left = left + silence((n - len(left)) / RATE)
    right = right + silence((n - len(right)) / RATE)
    with wave.open(f"assets/sfx/{name}.wav", "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        frames = bytearray()
        for i in range(n):
            l, r = left[i], right[i]
            if i >= n - fade:
                l *= (n - i) / fade
                r *= (n - i) / fade
            frames += struct.pack(
                "<hh",
                int(max(-1, min(1, l * gain)) * 32767),
                int(max(-1, min(1, r * gain)) * 32767),
            )
        w.writeframes(bytes(frames))


def stereo(samples, width=0.0008):
    """A touch of width: the right channel lags by [width] seconds."""
    k = int(width * RATE)
    return samples, silence(k / RATE) + samples


# Musical pitches (Hz).
D5, E5, G5, A5, B5, D6, E6 = 587.33, 659.25, 783.99, 880.0, 987.77, 1174.66, 1318.51
A3, C4, D4, E4, G4, A4, C5 = 220.0, 261.63, 293.66, 329.63, 392.0, 440.0, 523.25


# Joining: two soft notes a fourth apart, rising. Leaving: the same, falling.
write("voice_join", *stereo(polish(mix(
    (0.00, note(D5, 0.30, amp=0.45, decay=9, bend=-1.5)),
    (0.11, note(G5, 0.42, amp=0.50, decay=7, bend=-1.0)),
))))
write("voice_leave", *stereo(polish(mix(
    (0.00, note(G5, 0.30, amp=0.45, decay=9, bend=-1.0)),
    (0.11, note(D5, 0.45, amp=0.50, decay=6.5, bend=-1.5)),
))))

# A message: one short, round "pop". A mention: a brighter double pop.
write("message_received", *stereo(polish(mix(
    (0.00, note(A5, 0.26, amp=0.42, decay=14, bend=-2.0)),
    (0.00, note(A5 * 2, 0.14, amp=0.08, decay=30)),
), cutoff=4200)))
write("mention_received", *stereo(polish(mix(
    (0.00, note(A5, 0.20, amp=0.40, decay=16, bend=-2.0)),
    (0.10, note(D6, 0.30, amp=0.45, decay=12, bend=-1.5)),
), cutoff=4600)))
write("message_sent", *stereo(polish(
    note(E5, 0.13, amp=0.22, attack=0.004, decay=28, bend=1.5, bright=0.15),
    cutoff=2800, wet=0.08)))

# Mute / deafen go down, unmute / undeafen go up — quick, soft blips.
write("mute", *stereo(polish(
    note(C4, 0.16, amp=0.42, attack=0.006, decay=22, bend=3.0, bright=0.2),
    cutoff=1800, wet=0.10)))
write("unmute", *stereo(polish(
    note(E4, 0.16, amp=0.42, attack=0.006, decay=22, bend=-3.0, bright=0.2),
    cutoff=2200, wet=0.10)))
write("deafen", *stereo(polish(mix(
    (0.00, note(E4, 0.12, amp=0.40, attack=0.006, decay=24, bright=0.2)),
    (0.09, note(A3, 0.22, amp=0.42, attack=0.006, decay=16, bend=2.0, bright=0.2)),
), cutoff=1800, wet=0.10)))
write("undeafen", *stereo(polish(mix(
    (0.00, note(A3, 0.12, amp=0.40, attack=0.006, decay=24, bright=0.2)),
    (0.09, note(E4, 0.22, amp=0.42, attack=0.006, decay=16, bend=-2.0, bright=0.2)),
), cutoff=2200, wet=0.10)))

# A stream going live: three quick rising notes. Ending: two falling ones.
write("stream_start", *stereo(polish(mix(
    (0.00, note(G5, 0.16, amp=0.40, decay=14)),
    (0.09, note(B5, 0.16, amp=0.42, decay=14)),
    (0.18, note(D6, 0.40, amp=0.46, decay=7, bend=-1.0)),
), cutoff=4200)))
write("stream_stop", *stereo(polish(mix(
    (0.00, note(B5, 0.18, amp=0.42, decay=12)),
    (0.11, note(G5, 0.42, amp=0.44, decay=6.5, bend=-1.5)),
), cutoff=3600)))


def melody(steps, amp=0.40, decay=5.0, cutoff=3400):
    """[steps] are (time, freq, dur) triples over one loop."""
    return polish(
        mix(*((t, note(f, d, amp=amp, decay=decay, bend=-0.8)) for t, f, d in steps)),
        cutoff=cutoff,
    )


# Incoming call: a bright four-note motif, twice, then a rest — loops cleanly.
ring = []
motif = [(0.00, E5, 0.45), (0.18, G5, 0.45), (0.36, A5, 0.45), (0.54, E6, 0.80)]
for rep in (0.0, 1.0):
    ring += [(t + rep, f, d) for t, f, d in motif]
ringtone = melody(ring)
ringtone += silence(max(0.0, 3.0 - len(ringtone) / RATE))
write("ringtone", *stereo(ringtone[: int(3.0 * RATE)]))

# Outgoing call: two calm pulses, then a rest, like a phone ringing back.
outgoing = melody(
    [(0.00, A4, 0.9), (0.00, C5, 0.9), (0.5, A4, 0.9), (0.5, C5, 0.9)],
    amp=0.30,
    decay=4.0,
    cutoff=2600,
)
outgoing += silence(max(0.0, 3.0 - len(outgoing) / RATE))
write("ring_outgoing", *stereo(outgoing[: int(3.0 * RATE)]))
print("ok")
