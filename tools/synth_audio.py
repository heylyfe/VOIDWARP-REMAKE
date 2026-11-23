#!/usr/bin/env python3
# tools/synth_audio.py - T-055 placeholder audio synthesis.
#
# ENEMIES.md (owner spec): "All sounds are brand-new - nothing is copied from
# Nullscape audio. Each enemy keeps its 1:1 behavior and cue timing." This tool
# synthesises ONE distinct placeholder .wav per cue name, using only the stdlib
# (wave + math + json). No downloaded, recorded or copied audio ships here.
#
# Sources of truth, in order:
#   1. game/content/enemies/<id>/enemy.json - the "stats.audio_cues" list and the
#      "stats.audio" dict (coil, thicc_ben). Every cue named there gets a .wav.
#      The file name IS the cue name (the stable contract the view hooks use).
#   2. EXTRA_CUES below - (empty since T-087 wired Isagi's and nuke's cue lists into their
#      enemy.json files). Every cue the repo names resolves through enemy.json now.
#
# Output: game/assets/audio/enemies/<id>/<cue>.wav - 44.1 kHz mono 16-bit
# (research/fable-tickets.md section 3's format line). Cue TIMINGS are driven by
# sim telegraph events, never by audio length; lengths below are placeholders.
#
# Usage:
#   python tools/synth_audio.py           synthesise everything, then verify
#   python tools/synth_audio.py --check   verify only: every cue referenced in
#                                         enemy.json resolves to a parseable .wav
#
# Deterministic: every voice derives from a fixed LCG seed, so a rebuild is
# byte-stable. Peak-normalised to 0.89 before quantisation; never clips.

import json
import math
import os
import sys
import wave

SAMPLE_RATE = 44100
PEAK = 0.89
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENEMIES_DIR = os.path.join(ROOT, "game", "content", "enemies")
OUT_DIR = os.path.join(ROOT, "game", "assets", "audio", "enemies")

TAU = 2.0 * math.pi

# --- deterministic pseudo-noise (LCG, Numerical Recipes constants) -----------
class Noise:
    def __init__(self, seed):
        self.state = seed & 0x7FFFFFFF

    def next(self):
        self.state = (1103515245 * self.state + 12345) & 0x7FFFFFFF
        return self.state / 1073741823.5 - 1.0


def sine(freq, t, phase=0.0):
    return math.sin(TAU * freq * t + phase)


# Odd-harmonic stack, a sawtooth-ish brass voice.
def saw(freq, t, harmonics=7):
    s = 0.0
    h = 1
    while h <= harmonics:
        s += sine(freq * h, t) / h
        h += 2
    return s * 0.6


def attack(t, a):
    return min(1.0, t / a) if a > 0.0 else 1.0


# Piecewise-linear glide through (time, freq) knots.
def glide(knots, t):
    if t <= knots[0][0]:
        return knots[0][1]
    for i in range(1, len(knots)):
        if t <= knots[i][0]:
            t0, f0 = knots[i - 1]
            t1, f1 = knots[i]
            return f0 + (f1 - f0) * (t - t0) / (t1 - t0)
    return knots[-1][1]


def bell(freqs_amps_decays, t):
    s = 0.0
    for f, a, d in freqs_amps_decays:
        s += a * sine(f, t) * math.exp(-d * t)
    return s


# Westminster-flavoured four-note figure, compressed (placeholder, NOT a recording).
def westminster(t):
    notes = [(0.0, 392.0), (0.125, 330.0), (0.25, 294.0), (0.375, 262.0)]
    partials = [(1.0, 1.0, 2.0), (2.0, 0.5, 3.0), (2.4, 0.35, 3.6), (3.0, 0.2, 4.4)]
    s = 0.0
    for start, f in notes:
        local = t - start
        if local >= 0.0:
            s += bell([(f * p, a, d) for p, a, d in partials], local) * 0.8
    return s


def deep_bell(freq, t, decay):
    partials = [(1.0, 1.0), (2.0, 0.55), (2.4, 0.33), (3.0, 0.18), (4.2, 0.08)]
    return bell([(freq * p, a, decay * (0.8 + 0.4 * p)) for p, a in partials], t)


# --- cue recipes -------------------------------------------------------------
# Each entry: cue name -> (length_seconds, factory) where factory() returns a
# stateful fn(t) in roughly [-1, 1]. All recipes are [CONTESTABLE] placeholders
# (research/fable-tickets.md section 3 says so of its own recipes); the cue
# NAMES and the enemy.json references are the contract, not the waveforms.
# T-087 additions: locked, ring_release, mine_hum, prowl, leaves, beat,
# string_sweep (section 3 rows the T-055 wave set was missing); the loop rows
# (mine_hum, prowl, flipper_flap) synthesise 2.0 s beds (D-T087-2 [CONTESTABLE]).

def _meow(freq_scale):
    def fn(t):
        f = glide([(0.0, 700.0), (0.15, 1100.0), (0.35, 600.0)], t) * freq_scale
        vib = 0.12 * sine(8.0, t)
        env = attack(t, 0.03) * math.exp(-1.4 * t)
        return sine(f, t) * env * 0.8 + vib * sine(f * 2.0, t) * env * 0.2
    return fn


def _meow_double():
    one = _meow(4.0 / 3.0)  # pitched up a fourth
    def fn(t):
        s = one(t)           # first meow
        if t >= 0.2:         # 12 ticks @ 60 Hz later, the second
            s += one(t - 0.2)
        return s
    return fn


def _coil_boing():
    def fn(t):
        wobble = 1.6 * (1.0 - t / 0.6)          # FM depth decays over the cue
        env = attack(t, 0.005) * math.exp(-2.2 * t)
        return sine(330.0, t, wobble * sine(12.0, t)) * env * 0.9
    return fn


def _coil_landing_twang():
    def fn(t):
        env = attack(t, 0.002) * math.exp(-5.5 * t)
        s = (sine(310.0, t) * 1.0 + sine(827.0, t) * 0.6 + sine(1340.0, t) * 0.35) * env * 0.55
        s += sine(70.0, t) * math.exp(-16.0 * t) * 0.9   # low thump
        return s
    return fn


def _thicc_ben_chime():
    return lambda t: westminster(t)


def _thicc_ben_bell():
    return lambda t: deep_bell(98.0, t, 1.1)


def _explosion():
    noise = Noise(0xE470)
    def fn(t):
        click = noise.next() * math.exp(-90.0 * t) * 1.0
        body = noise.next() * math.exp(-5.0 * t) * 0.7
        thump = sine(60.0, t) * math.exp(-4.0 * t) * 0.9
        return click + body + thump
    return fn


def _pff():
    noise = Noise(0xB1FB)
    state = [0.0]                            # one-pole lowpass, cutoff sweeps down
    def fn(t):
        fc = 3000.0 * (300.0 / 3000.0) ** (t / 0.3)
        a = 1.0 - math.exp(-TAU * fc / SAMPLE_RATE)
        state[0] += a * (noise.next() - state[0])
        return state[0] * math.exp(-7.0 * t) * 2.2
    return fn


def _crack_rumble():
    noise = Noise(0xC4AC)
    clicks = [0.0]
    rate = [4.0]
    def fn(t):
        drone = sine(50.0, t) * 0.5
        rate[0] = 4.0 + (20.0 - 4.0) * (t / 2.0)     # click rate rises 4 -> 20 Hz
        if t >= clicks[0]:
            clicks[0] = t + 1.0 / rate[0]
            return drone + noise.next() * 0.8        # the click itself
        return drone + sine(noise.next() * 30.0 + 60.0, t) * 0.05
    return fn


def _shing():
    noise = Noise(0x5EED)
    def fn(t):
        f = glide([(0.0, 2000.0), (0.18, 6000.0), (0.3, 6000.0)], t)
        sweep = sine(f, t) * attack(t, 0.004) * math.exp(-4.0 * t) * 0.8
        tail = noise.next() * (1.0 if t > 0.12 else 0.0) * math.exp(-30.0 * (t - 0.12)) * 0.25
        return sweep + tail
    return fn


def _whoosh():
    noise = Noise(0x0405)
    state = [0.0]
    def fn(t):
        band = 0.5 + 0.5 * sine(2.5, t)              # wobble the band amplitude
        fc = 2500.0 * (250.0 / 2500.0) ** (t / 0.3)  # sweeps down
        a = 1.0 - math.exp(-TAU * fc / SAMPLE_RATE)
        state[0] += a * (noise.next() - state[0])
        return state[0] * band * attack(t, 0.01) * math.exp(-1.0 * t) * 2.0
    return fn


def _zone_open():
    return lambda t: (sine(glide([(0.0, 400.0), (0.4, 150.0)], t), t)
                      + 0.4 * sine(glide([(0.0, 400.0), (0.4, 150.0)], t) * 2.76, t)) \
        * attack(t, 0.01) * math.exp(-2.5 * t) * 0.8


def _zone_close():
    return lambda t: (sine(glide([(0.0, 150.0), (0.4, 400.0)], t), t)
                      + 0.4 * sine(glide([(0.0, 150.0), (0.4, 400.0)], t) * 2.76, t)) \
        * attack(t, 0.01) * math.exp(-2.5 * t) * 0.8


def _ui_chime():
    return lambda t: (sine(660.0, t) + 0.7 * sine(1320.0, t)) * attack(t, 0.002) * math.exp(-9.0 * t) * 0.8


def _keystroke_tick():
    noise = Noise(0x71C4)
    def fn(t):
        return noise.next() * math.exp(-70.0 * t) * 0.8 + sine(2400.0, t) * math.exp(-40.0 * t) * 0.35
    return fn


def _notification_ping():
    def fn(t):
        if t < 0.07:
            return sine(1568.0, t) * attack(t, 0.002) * math.exp(-10.0 * t) * 0.7
        return sine(2093.0, t - 0.07) * math.exp(-10.0 * (t - 0.07)) * 0.7
    return fn


def _squeak_pop():
    noise = Noise(0x5D04)
    def fn(t):
        s = sine(glide([(0.0, 1200.0), (0.12, 1800.0)], t), t) * attack(t, 0.008) * math.exp(-6.0 * t) * 0.7
        if t >= 0.13:
            s += noise.next() * math.exp(-60.0 * (t - 0.13)) * 0.8   # the pop
        return s
    return fn


def _bark():
    def fn(t):
        s = 0.0
        if 0.02 <= t < 0.08:
            s += saw(500.0, t - 0.02) * attack(t - 0.02, 0.005) * math.exp(-12.0 * (t - 0.02)) * 0.9
        if 0.13 <= t < 0.19:
            s += saw(650.0, t - 0.13) * attack(t - 0.13, 0.005) * math.exp(-12.0 * (t - 0.13)) * 0.9
        return s
    return fn


def _flipper_flap():
    noise = Noise(0xF1A9)
    state = [0.0]
    slaps = [i * (2.0 / 6.6) for i in range(7)]             # ~3.3 Hz over the 2.0 s bed
    def fn(t):
        for s0 in slaps:
            local = t - s0
            if 0.0 <= local < 0.09:
                a = 1.0 - math.exp(-TAU * 700.0 / SAMPLE_RATE)   # soft lowpass
                state[0] += a * (noise.next() - state[0])
                return state[0] * math.exp(-22.0 * local) * 2.0 + sine(180.0, local) * math.exp(-18.0 * local) * 0.5
        return 0.0
    return fn


def _toucher_squelch():
    noise = Noise(0x5CA1)
    def fn(t):
        band = 400.0 + 200.0 * sine(15.0, t)          # wobbling band centre, 15 Hz
        s = noise.next() * sine(band, t) * math.exp(-4.0 * t) * 1.2
        return round(s * 8.0) / 8.0                   # bit-crush to ~4 bits
    return fn


def _you_corrupted_rumble():
    noise = Noise(0xBADD)
    def fn(t):
        gate = 1.0 if sine(30.0, t) >= 0.0 else 0.15  # white noise gated at 30 Hz
        rise = 0.15 + 0.55 * (t / 3.0)                # volume rises over the rumble
        s = noise.next() * gate * rise * 0.8
        if t >= 2.5:                                  # reversed-envelope tone, last 0.5 s
            lt = t - 2.5
            f = 400.0 + (900.0 - 400.0) * (lt / 0.5)
            s += sine(f, lt) * math.exp(6.0 * (lt / 0.5) - 6.0) * 0.6
        return s
    return fn


def _spawn_trumpet():
    def fn(t):
        formant = 1.0 + 0.35 * sine(6.0, t)           # rising formant sweep / tremolo
        env = attack(t, 0.03) * math.exp(-0.9 * t)
        return (saw(233.0, t) + 0.65 * saw(349.23, t)) * formant * env * 0.55
    return fn


def _rumble_build():
    def fn(t):
        hz = 1.0 + (6.0 - 1.0) * (t / 5.0)            # tremolo speeds up 1 -> 6 Hz
        amp = 0.25 + 0.35 * (t / 5.0)                 # amplitude creeps up
        trem = 0.75 + 0.25 * sine(hz, t)
        return sine(40.0, t) * amp * trem
    return fn


def _explode_boom():
    noise = Noise(0xB004)
    def fn(t):
        thump = sine(41.0, t) * attack(t, 0.003) * math.exp(-1.8 * t) * 1.0
        crash = noise.next() * math.exp(-3.0 * t) * 0.45
        return thump + round(crash * 16.0) / 16.0
    return fn


# --- Isagi / nuke TBD-hook cues (enemy.json lists no cues for these yet) ------
def _isagi_voice_direct_shot():
    noise = Noise(0x1151)
    state = [0.0]
    def fn(t):
        fc = 300.0 * (3000.0 / 300.0) ** (t / 1.15)   # rising whoosh 300 -> 3000 Hz
        a = 1.0 - math.exp(-TAU * fc / SAMPLE_RATE)
        state[0] += a * (noise.next() - state[0])
        silence_tail = 1.0 if t < 1.15 else 0.0       # 3 ticks of silence pre-shot
        return (state[0] * 1.6 + sine(300.0 + 600.0 * (t / 1.15), t) * 0.3) * silence_tail * attack(t, 0.05)
    return fn


def _isagi_shoot_sae_math_final_shot():
    def fn(t):                                        # a formant "final shot" yell
        f = 165.0
        formant = 1.0 + 0.6 * math.exp(-((t - 0.18) / 0.09) ** 2) * 2.0
        formant += 0.5 * math.exp(-((t - 0.38) / 0.12) ** 2)
        env = attack(t, 0.012) * math.exp(-3.2 * t)
        return saw(f, t, 9) * formant * env * 0.5
    return fn


def _isagi_gunshot():
    noise = Noise(0x9005)
    def fn(t):
        return noise.next() * math.exp(-25.0 * t) * 0.9 + sine(150.0, t) * math.exp(-12.0 * t) * 0.8
    return fn


def _lock_on_beep():
    return lambda t: (1.0 if sine(1200.0, t) >= 0.0 else -1.0) * attack(t, 0.002) * math.exp(-28.0 * t) * 0.75


def _rocket_booster_roar():
    noise = Noise(0xB0057)
    state = [0.0]
    def fn(t):
        fc = 2000.0 * (200.0 / 2000.0) ** (t / 1.5)   # cutoff falls 2000 -> 200 Hz
        a = 1.0 - math.exp(-TAU * fc / SAMPLE_RATE)
        state[0] += a * (noise.next() - state[0])
        amp = 0.35 + 0.55 * (t / 1.5)                 # rising volume, ends on impact
        return state[0] * amp * 2.2
    return fn


def _impact_boom():
    noise = Noise(0x1CA0)
    def fn(t):
        thump = sine(45.0, t) * attack(t, 0.003) * math.exp(-2.2 * t) * 1.0
        body = noise.next() * math.exp(-4.5 * t) * 0.5
        return thump + body
    return fn


# --- T-087 additions: the section 3 rows T-055's wave set was missing ----------
def _locked():
    # two-tone 1200 -> 1600 Hz, 0.2 s: the ring stops
    def fn(t):
        f = 1200.0 if t < 0.1 else 1600.0
        sq = 1.0 if sine(f, t) >= 0.0 else -1.0             # same square voice as lock_on_beep
        env = attack(t % 0.1 if t < 0.1 else t - 0.1, 0.002) * math.exp(-18.0 * (t % 0.1 if t < 0.1 else t - 0.1))
        return sq * env * 0.7
    return fn


def _ring_release():
    # a short downward chirp 900 -> 200 Hz, 0.3 s
    def fn(t):
        f = glide([(0.0, 900.0), (0.3, 200.0)], t)
        return sine(f, t) * attack(t, 0.004) * math.exp(-3.0 * t) * 0.8
    return fn


def _mine_hum():
    # very quiet 180 Hz hum with a slow 0.5 Hz tremolo (loop bed)
    def fn(t):
        trem = 0.7 + 0.3 * sine(0.5, t)
        return sine(180.0, t) * trem * 0.35
    return fn


def _prowl():
    # granular clicks at an irregular ~6-10 Hz rate (LCG-seeded jitter, deterministic)
    noise = Noise(0x9E11)
    clicks = []
    t = 0.05
    while t < 1.95:
        clicks.append(t)
        t += 0.111 + 0.056 * (noise.next() * 0.5 + 0.5)     # 0.111..0.167 s -> 6..9 Hz
    def fn(t):
        s = 0.0
        for c0 in clicks:
            local = t - c0
            if 0.0 <= local < 0.03:
                s += noise.next() * math.exp(-55.0 * local) * 0.9
        return s * 0.6
    return fn


def _leaves():
    # soft descending two-note, 0.3 s
    def fn(t):
        if t < 0.15:
            return sine(660.0, t) * attack(t, 0.02) * math.exp(-8.0 * t) * 0.6
        return sine(440.0, t - 0.15) * math.exp(-8.0 * (t - 0.15)) * 0.6
    return fn


def _beat():
    # soft tick at 880 Hz, 0.05 s (the metronome)
    def fn(t):
        return sine(880.0, t) * attack(t, 0.002) * math.exp(-60.0 * t) * 0.6
    return fn


def _string_sweep():
    # the telegraph beat, then 4 sweep beats: rapid keystroke ticks at 16 per beat rising in pitch
    noise = Noise(0x57E5)
    def fn(t):
        beat = t / 0.6
        if beat >= 5.0:
            return 0.0
        idx = int(beat * 16.0)
        local = beat * 16.0 - idx
        if local >= 0.09:                                    # tick occupies ~9% of a 1/16 beat
            return 0.0
        f = 800.0 * (4.0 ** (idx / 80.0))                    # pitch rises through the sweep
        click = noise.next() * math.exp(-38.0 * local / 0.09) * 0.7
        return click + sine(f, local * 0.6) * math.exp(-30.0 * local / 0.09) * 0.35
    return fn


# ---- T4 (cycle 7): the two Claude anger warnings -------------------------------------------
# The owner's words (CYCLE7_BRIEF.md T4): "If no clawd is collected for 60 s, Claude releases a warning sound
# (a new synth cue). At 120 s, a second, more urgent sound." Both are NEW voices - nothing here is copied from
# Nullscape or from the old musical kit (ENEMIES.md: "All sounds are brand-new"). The first is a two-note rising
# chime with a soft bell tail; the second is a three-note alarm, higher, faster and with a detuned second voice
# so it reads as urgent rather than merely louder.

def _claude_warning_1():
    # 60 s: a calm two-note rising chime (A5 -> E6) with a bell tail.
    def fn(t):
        s = 0.0
        if t < 0.16:
            s += sine(880.0, t) * attack(t, 0.004) * math.exp(-7.0 * t) * 0.7
        if t >= 0.14:
            lt = t - 0.14
            s += sine(1318.5, lt) * attack(lt, 0.004) * math.exp(-5.0 * lt) * 0.8
            s += 0.25 * sine(2637.0, lt) * math.exp(-9.0 * lt)      # the bell partial
        return s
    return fn


def _claude_warning_2():
    # 120 s: a three-note alarm (E6 -> A6 -> E6), faster, with a detuned second voice beating against the first.
    notes = [(0.0, 1318.5), (0.13, 1760.0), (0.26, 1318.5)]
    def fn(t):
        s = 0.0
        for start, f in notes:
            lt = t - start
            if 0.0 <= lt < 0.13:
                env = attack(lt, 0.003) * math.exp(-9.0 * lt)
                s += (sine(f, lt) + 0.55 * sine(f * 1.012, lt)) * env * 0.75
                s += 0.3 * sine(f * 2.0, lt) * env
        return s
    return fn


# cue name -> (length_seconds, factory). Lengths follow research/fable-tickets.md
# section 3 where a cue maps to its row; enemy.json names are kept verbatim.
RECIPES = {
    # kiwi_cat
    "meow": (0.35, lambda: _meow(1.0)),
    "meow_double": (0.6, _meow_double),
    # coil
    "coil_boing": (0.6, _coil_boing),
    "coil_landing_twang": (0.4, _coil_landing_twang),
    # thicc_ben
    "thicc_ben_chime": (0.5, _thicc_ben_chime),
    "thicc_ben_bell": (1.8, _thicc_ben_bell),
    # gift_larper
    "explosion": (0.8, _explosion),
    "pff": (0.3, _pff),
    # gin
    "crack_rumble": (2.0, _crack_rumble),
    "shing": (0.3, _shing),
    "whoosh": (0.3, _whoosh),
    "zone_open": (0.4, _zone_open),
    "zone_close": (0.4, _zone_close),
    # claude
    "ui_chime": (0.2, _ui_chime),
    "keystroke_tick": (0.08, _keystroke_tick),
    "notification_ping": (0.15, _notification_ping),
    "squeak_pop": (0.2, _squeak_pop),
    "beat": (0.05, _beat),
    "string_sweep": (3.0, _string_sweep),
    # claude, cycle 7 (T4): the two anger warnings
    "claude_warning_1": (0.45, _claude_warning_1),
    "claude_warning_2": (0.42, _claude_warning_2),
    # seal
    "bark": (0.25, _bark),
    "flipper_flap": (2.0, _flipper_flap),
    # toucher
    "toucher_squelch": (0.4, _toucher_squelch),
    "prowl": (2.0, _prowl),
    # gift_larper (mine_hum, loop)
    "mine_hum": (2.0, _mine_hum),
    # you
    "you_corrupted_rumble": (3.0, _you_corrupted_rumble),
    "ring_release": (0.3, _ring_release),
    # address_me
    "spawn_trumpet": (0.9, _spawn_trumpet),
    "rumble_build": (5.0, _rumble_build),
    "explode_boom": (1.2, _explode_boom),
    "leaves": (0.3, _leaves),
    # isagi
    "isagi_voice_direct_shot": (1.2, _isagi_voice_direct_shot),
    "isagi_shoot_sae_math_final_shot": (0.6, _isagi_shoot_sae_math_final_shot),
    "isagi_gunshot": (0.12, _isagi_gunshot),
    # nuke
    "lock_on_beep": (0.05, _lock_on_beep),
    "locked": (0.2, _locked),
    "rocket_booster_roar": (1.5, _rocket_booster_roar),
    "impact_boom": (1.2, _impact_boom),
}

# Enemy id -> extra cue names synthesised beyond what its enemy.json declares.
# Empty since T-087: isagi's and nuke's cue lists are wired into their
# enemy.json files, so the scan finds every cue by itself.
EXTRA_CUES = {}


def enemy_cues(enemy_json_path):
    """The cues one enemy.json references: stats.audio_cues (list) + stats.audio (dict values)."""
    with open(enemy_json_path, "r", encoding="utf-8-sig") as fh:
        data = json.load(fh)
    stats = data.get("stats", {})
    cues = []
    for name in stats.get("audio_cues", []):
        cues.append(str(name))
    audio = stats.get("audio", {})
    if isinstance(audio, dict):
        for value in audio.values():
            cues.append(str(value))
    return cues


def scan_enemies():
    """{enemy_id: [cue, ...]} for every enemy.json under game/content/enemies."""
    found = {}
    for entry in sorted(os.listdir(ENEMIES_DIR)):
        path = os.path.join(ENEMIES_DIR, entry, "enemy.json")
        if os.path.isfile(path):
            found[entry] = enemy_cues(path)
    return found


def synth(cue):
    length, factory = RECIPES[cue]
    n = int(SAMPLE_RATE * length)
    fn = factory()
    samples = [fn(i / SAMPLE_RATE) for i in range(n)]
    peak = max(max(abs(s) for s in samples), 1e-9)
    gain = PEAK / peak if peak > PEAK else 1.0
    return [int(round(s * gain * 32767.0)) for s in samples]


def write_wav(path, samples):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as fh:
        fh.setnchannels(1)
        fh.setsampwidth(2)
        fh.setframerate(SAMPLE_RATE)
        fh.writeframes(b"".join(s.to_bytes(2, "little", signed=True) for s in samples))


def wav_ok(path):
    try:
        with wave.open(path, "rb") as fh:
            return (fh.getframerate() == SAMPLE_RATE and fh.getnchannels() == 1
                    and fh.getsampwidth() == 2 and fh.getnframes() > 0)
    except (wave.Error, EOFError):
        return False


def main():
    check_only = "--check" in sys.argv[1:]
    enemies = scan_enemies()

    missing = sorted({cue for cues in enemies.values() for cue in cues} - set(RECIPES))
    if missing:
        print("synth_audio: cue(s) with no recipe: %s" % ", ".join(missing))
        return 2

    plan = {eid: list(cues) + EXTRA_CUES.get(eid, []) for eid, cues in enemies.items()}

    written = 0
    for enemy_id, cues in sorted(plan.items()):
        for cue in cues:
            if check_only:
                continue
            out = os.path.join(OUT_DIR, enemy_id, cue + ".wav")
            write_wav(out, synth(cue))
            written += 1

    # verify: every cue referenced in enemy.json - plus the extras - resolves
    failures = []
    for enemy_id, cues in sorted(plan.items()):
        for cue in cues:
            if not wav_ok(os.path.join(OUT_DIR, enemy_id, cue + ".wav")):
                failures.append("%s/%s.wav" % (enemy_id, cue))

    if failures:
        print("synth_audio: FAIL - unresolved cue(s): %s" % ", ".join(failures))
        return 1

    declared = sum(len(cues) for cues in enemies.values())
    total = sum(len(cues) for cues in plan.values())
    print("synth_audio: %d cue(s) referenced in enemy.json, %d total file(s) verified OK"
          % (declared, total))
    if not check_only:
        print("synth_audio: wrote %d .wav file(s) under %s" % (written, os.path.relpath(OUT_DIR, ROOT)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
