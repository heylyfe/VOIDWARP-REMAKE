extends RefCounted
#
# address me placeholder audio (ticket T-039; ENEMIES.md "New sound" (verbatim):
# "elephant trumpet on spawn, low rumbling build-up during the 5 seconds,
# massive boom on the explode frame.").
#
# Hooks named per the ENEMIES.md line, synthesized at runtime as AudioStreamWAV
# placeholders - NO recorded or downloaded audio, nothing copied from any existing
# recording. The cue NAMES are the stable contract; T-055 swaps in file-backed
# cues:
#
#   "spawn_trumpet" -> file name address_me_trumpet   (the elephant trumpet on
#                       appearance - raised by address_me_view.gd on entering the
#                       'spawn' state)
#   "rumble_build"  -> file name address_me_rumble    (the low rumbling build-up
#                       over the 5.0 s countdown - raised on entering the
#                       'telegraph' state)
#   "explode_boom"  -> file name address_me_boom      (the massive boom on the
#                       explode frame - raised on entering the 'attack' state, the
#                       kill tick)
#
# Pure synthesis on the view layer: no sim access, no engine calls beyond
# AudioStreamWAV/AudioStreamPlayer construction. Deterministic (fixed sample
# rate, fixed formulas) - the byte output for a cue is identical on every boot.

const SAMPLE_RATE := 22050
const SAMPLE_FMT := AudioStreamWAV.FORMAT_16_BITS

# cue id (the view plays these) -> intended file name (T-055 drops .wav files in)
const CUES := {
	"spawn_trumpet": "address_me_trumpet",
	"rumble_build": "address_me_rumble",
	"explode_boom": "address_me_boom",
}


static func cue_names() -> Array:
	var out: Array = []
	for k in CUES.keys():
		out.append(str(k))
	out.sort()
	return out


static func file_name_for(cue: String) -> String:
	return str(CUES.get(cue, ""))


# ---- the held curses gate the consumer through -------------------------------

# The contract modules the cues are gated by. `unannounced` owns the rule
# sentence "no trumpet - only the sprite and the rumble" (content/curses/
# unannounced.gd); this view asks IT which cues are allowed and never restates
# the rule here. As curses are given consumers, they join this list.
const CURSE_SCRIPTS := [
	preload("res://content/curses/unannounced.gd"),
]


## The cues the SHIPPED game may play on this run: every cue in cue_names()
## that each held curse's own module still allows. `state` is the run's carried
## curse state ({"curses_held": {curse_id: stacks}}); an empty dict is a
## curse-free run and keeps every cue.
static func allowed_cues(state: Dictionary) -> Array:
	var out: Array = []
	for cue in cue_names():
		var ok := true
		for curse in CURSE_SCRIPTS:
			if not curse.cue_allowed(state, str(cue)):
				ok = false
				break
		if ok:
			out.append(str(cue))
	return out


## May this cue play on this run? Asks each curse module (same state contract
## as allowed_cues); with no curses held, any cue in CUES is allowed.
static func cue_allowed(state: Dictionary, cue: String) -> bool:
	if not CUES.has(cue):
		return false
	for curse in CURSE_SCRIPTS:
		if not curse.cue_allowed(state, cue):
			return false
	return true


## Plays the cue on `host` (a Node in the tree - the view passes itself). Returns
## the created player (already playing), or null when the host is unusable
## (e.g. a headless test with no tree). Never crashes. An empty `state` (the
## view's default) is a curse-free run: every cue in cue_names() plays.
## `state` is the run's carried curse state ({"curses_held": {curse_id: stacks}});
## the played set comes from allowed_cues(), which asks the curse module - the
## consumer never re-states a curse's rule here.
static func play_cue(host: Object, cue: String, state: Dictionary = {}) -> AudioStreamPlayer:
	if not cue_allowed(state, cue):
		return null
	if not CUES.has(cue):
		push_warning("address_me_audio: unknown cue '%s'" % cue)
		return null
	if not (host is Node):
		return null
	var parent := host as Node
	if not parent.is_inside_tree():
		return null
	var p := AudioStreamPlayer.new()
	p.stream = stream_for(cue)
	p.name = "address_me_%s" % cue
	parent.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
	return p


## The synthesized placeholder stream for a cue. Deterministic: same cue, same bytes.
static func stream_for(cue: String) -> AudioStreamWAV:
	match cue:
		"spawn_trumpet":
			# one elephant trumpet blast: a brassy ~233 Hz (A#3) fundamental with
			# strong odd harmonics, an 8 Hz tremolo, and a noise breath on the attack
			return _render(233.0, 1.4, 0.8, 8.0, 12.0, 0.25)
		"rumble_build":
			# the 5 s low rumble: 55 Hz (A1) sub, tremolo ramping 1 -> 6 Hz (the
			# anim block's tremolo ramp), amplitude creeping up as the ring drains
			return _render(55.0, 5.0, 0.55, 1.0, 3.5, 0.0, 6.0)
		"explode_boom":
			# the massive boom: 41 Hz (E1) sub with a near-instant attack and a long
			# tail; the noise crash is baked into the formula (noise_mix > 0)
			return _render(41.0, 2.5, 1.0, 2.0, 1.8, 0.45)
		_:
			return null


# ---- synthesis ---------------------------------------------------------------

# One voice: a fundamental with a saw-ish harmonic stack, exponential decay,
# tremolo hz (static) and an amplitude ramp from `amp` to `amp_end`.
# If `tremolo_end > 0`, the tremolo rate ramps linearly from `tremolo` to
# `tremolo_end` over the full length (the build-up). `noise_mix` > 0 mixes
# white-ish noise (deterministic via the cue's own LCG) for the attack transient.
static func _render(freq: float, length_s: float, amp: float, tremolo: float,
		decay: float, noise_mix: float, tremolo_end: float = 0.0,
		amp_end: float = -1.0) -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * length_s)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := 987654321                    # fixed LCG seed: the bytes never drift
	var amp_hi := amp_end if amp_end >= 0.0 else amp
	for i in range(n):
		var t := float(i) / float(SAMPLE_RATE)
		var env: float = exp(-decay * t)
		var a := lerpf(amp, amp_hi, clampf(t / length_s, 0.0, 1.0))
		var hz := lerpf(tremolo, tremolo_end if tremolo_end > 0.0 else tremolo,
				clampf(t / length_s, 0.0, 1.0))
		var trem := 0.75 + 0.25 * sin(TAU * hz * t)
		var s := 0.0
		for h in [1.0, 3.0, 5.0, 7.0]:
			s += (1.0 / h) * sin(TAU * freq * h * t)
		s *= a * env * trem * 0.5
		if noise_mix > 0.0:
			rng = (1103515245 * rng + 12345) & 0x7FFFFFFF
			var noise: float = float(rng % 1000) / 500.0 - 1.0
			s += noise * noise_mix * exp(-6.0 * t)
		s = clampf(s, -1.0, 1.0)
		var v := int(round(s * 30000.0))
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = SAMPLE_FMT
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = data
	return wav
