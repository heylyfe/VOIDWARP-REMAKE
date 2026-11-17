extends RefCounted
#
# thicc ben placeholder audio (ticket T-032; ENEMIES.md "New sound":
# "the real Big Ben bell chime (Westminster bongs) before each teleport").
#
# Hooks named per the ENEMIES.md line, synthesized at runtime as
# AudioStreamWAV placeholders - NO recorded or downloaded audio, nothing copied
# from any existing recording. The cues are NOT the actual Westminster chime
# (that recording cannot ship); they are a same-rhythm stand-in, marked
# `tbd_audio: true` in enemy.json stats and TBD.md section 2. T-055 replaces
# these with file-backed cues; the cue NAMES are the stable contract:
#
#   "teleport_chime" -> file name thicc_ben_chime   (the cue that lands the
#                       Westminster bongs ~0.5 s before ben appears - raised by
#                       thicc_ben_view.gd at tick 45 of the 75-tick telegraph)
#   "touch_bell"     -> file name thicc_ben_bell    (the bell that rings on
#                       touch - raised by thicc_ben_view.gd on the sim's
#                       screen_blur / chain_reset "thicc_ben_eject" event)
#
# Pure synthesis on the view layer: no sim access, no engine calls beyond
# AudioStreamWAV/AudioStreamPlayer construction. Deterministic (fixed sample
# rate, fixed formulas) - the byte output for a cue is identical on every boot.

const SAMPLE_RATE := 22050
const SAMPLE_FMT := AudioStreamWAV.FORMAT_16_BITS

# cue id (the view plays these) -> intended file name (T-055 drops .wav files in)
const CUES := {
	"teleport_chime": "thicc_ben_chime",
	"touch_bell": "thicc_ben_bell",
}


static func cue_names() -> Array:
	var out: Array = []
	for k in CUES.keys():
		out.append(str(k))
	out.sort()
	return out


static func file_name_for(cue: String) -> String:
	return str(CUES.get(cue, ""))


## Plays the cue on `host` (a Node in the tree - the view passes itself). Returns
## the created player (already playing), or null when the host is unusable
## (e.g. a headless test with no tree). Never crashes.
static func play_cue(host: Object, cue: String) -> AudioStreamPlayer:
	if not CUES.has(cue):
		push_warning("thicc_ben_audio: unknown cue '%s'" % cue)
		return null
	if not (host is Node):
		return null
	var parent := host as Node
	if not parent.is_inside_tree():
		return null
	var p := AudioStreamPlayer.new()
	p.stream = stream_for(cue)
	p.name = "thicc_ben_%s" % cue
	parent.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
	return p


## The synthesized placeholder stream for a cue. Deterministic: same cue, same bytes.
static func stream_for(cue: String) -> AudioStreamWAV:
	match cue:
		"teleport_chime":
			# Westminster-ish descending four-note bong figure (placeholder rhythm,
			# not the actual melody): 392, 330, 294, 262 Hz, bell timbre.
			return _render([
				{"freq": 392.0, "start": 0.00, "amp": 0.9},
				{"freq": 330.0, "start": 0.45, "amp": 0.9},
				{"freq": 294.0, "start": 0.90, "amp": 0.9},
				{"freq": 262.0, "start": 1.35, "amp": 1.0},
			], 2.6)
		"touch_bell":
			# one deep bong (G3), long decay - the bell that rings on touch
			return _render([
				{"freq": 196.0, "start": 0.0, "amp": 1.0},
			], 2.4)
		_:
			return null


# ---- synthesis ---------------------------------------------------------------

# A bell voice: inharmonic partials with exponential decay (strike at t = start).
const PARTIALS := [1.0, 2.0, 2.76, 5.40, 8.93]
const PARTIAL_AMPS := [1.0, 0.55, 0.30, 0.16, 0.08]
const PARTIAL_DECAY := [2.4, 3.1, 3.8, 4.9, 6.0]

static func _bell(t: float, freq: float, amp: float) -> float:
	var out := 0.0
	for i in range(PARTIALS.size()):
		out += PARTIAL_AMPS[i] * sin(TAU * PARTIALS[i] * freq * t) * exp(-PARTIAL_DECAY[i] * t)
	return out * amp


static func _render(notes: Array, length_s: float) -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * length_s)
	var data := PackedByteArray()
	data.resize(n * 2)
	var peak := 1.0
	for i in range(n):
		var t := float(i) / float(SAMPLE_RATE)
		var s := 0.0
		for note in notes:
			var local: float = t - float(note["start"])
			if local >= 0.0:
				s += _bell(local, float(note["freq"]), float(note["amp"]))
		s = clampf(s, -1.0, 1.0)
		peak = maxf(peak, absf(s))
		var v := int(round(s * 30000.0))
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = SAMPLE_FMT
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = data
	return wav
