"""Synthesizes Daccord's interface sounds (assets/sfx) from scratch.

Short, soft sine "bloops" in the spirit of other voice chat apps, written from
nothing but math so the project owns them outright. Run from the repository
root: python tool/make_sfx.py
"""
import math
import struct
import wave

RATE = 44100


def tone(freq_from, freq_to, dur, amp=0.5, attack=0.006, decay=8.0, harmonic=0.18):
    """A sine glide with a quick attack, an exponential tail and a soft
    second harmonic for warmth."""
    out = []
    phase = 0.0
    n = int(dur * RATE)
    for i in range(n):
        t = i / RATE
        f = freq_from + (freq_to - freq_from) * min(1.0, t / dur)
        phase += 2 * math.pi * f / RATE
        env = min(1.0, t / attack) * math.exp(-decay * t)
        s = math.sin(phase) + harmonic * math.sin(2 * phase)
        out.append(amp * env * s / (1 + harmonic))
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


def write(name, samples):
    peak = max(1e-9, max(abs(s) for s in samples))
    gain = min(1.0, 0.85 / peak)
    fade = int(0.004 * RATE)
    with wave.open(f"assets/sfx/{name}.wav", "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        frames = bytearray()
        for i, s in enumerate(samples + silence(0.02)):
            if i >= len(samples) - fade and i < len(samples):
                s *= (len(samples) - i) / fade
            v = int(max(-1, min(1, s * gain)) * 32767)
            frames += struct.pack("<hh", v, v)
        w.writeframes(bytes(frames))


# Joining: two rising notes. Leaving: the same, falling.
write("voice_join", mix((0, tone(520, 560, 0.16, decay=14)), (0.09, tone(780, 830, 0.24, decay=11))))
write("voice_leave", mix((0, tone(780, 740, 0.16, decay=14)), (0.09, tone(520, 470, 0.26, decay=11))))
# A message: one short, round pop. A mention: a brighter double pop.
write("message_received", tone(990, 930, 0.17, amp=0.45, decay=22))
write("mention_received", mix((0, tone(1050, 1000, 0.13, decay=24)), (0.085, tone(1400, 1340, 0.18, decay=20))))
write("message_sent", tone(700, 760, 0.09, amp=0.25, decay=30))
# Mute / deafen go down, unmute / undeafen go up — quick, unobtrusive blips.
write("mute", tone(620, 430, 0.11, amp=0.4, decay=26))
write("unmute", tone(430, 620, 0.11, amp=0.4, decay=26))
write("deafen", mix((0, tone(620, 520, 0.08, decay=30)), (0.07, tone(470, 360, 0.12, decay=24))))
write("undeafen", mix((0, tone(360, 470, 0.08, decay=30)), (0.07, tone(520, 640, 0.12, decay=24))))
# A stream going live: three quick rising notes. Ending: two falling ones.
write("stream_start", mix((0, tone(660, 680, 0.10, decay=20)), (0.08, tone(880, 900, 0.10, decay=20)), (0.16, tone(1100, 1180, 0.24, decay=12))))
write("stream_stop", mix((0, tone(880, 840, 0.12, decay=18)), (0.10, tone(620, 560, 0.26, decay=11))))
print("ok")
