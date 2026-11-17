extends RefCounted
#
# gin ichimaru placeholder audio (ticket T-041; ENEMIES.md "New sound", verbatim:
# "sword 'shing' (unsheath) + whoosh when the spears launch, deep cracking rumble
# before a platform breaks" + the void zone cues). Hooks named per the section 3
# brief: crack_rumble (the 120-tick mark), shing (the launch, tick 120), whoosh
# (the 18-tick spear flight), zone_open (the tiles vanish), zone_close (the tiles
# fade back).
#
# Pure synthesis on the view layer - NO recorded or downloaded audio, nothing
# copied from any existing recording. Deterministic: same cue, same bytes. The
# cue NAMES are the stable contract; T-055 swaps in file-backed cues.

const SAMPLE_RATE := 22050

const CUES := {
	"crack_rumble": "gin_crack_rumble",
	"shing": "gin_shing",
	"whoosh": "gin_whoosh",
	"zone_open": "gin_zone_open",
	"zone_close": "gin_zone_close",
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
## the created player (already playing), or null when the host is unusable.
static func play_cue(host: Object, cue: String) -> AudioStreamPlayer:
	if not CUES.has(cue):
		push_warning("gin_audio: unknown cue '%s'" % cue)
		return null
	if not (host is Node):
		return null
	var parent := host as Node
	if not parent.is_inside_tree():
		return null
	var p := AudioStreamPlayer.new()
	p.stream = stream_for(cue)
	p.name = "gin_%s" % cue
	parent.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
	return p


## The synthesized placeholder stream for a cue. Deterministic: same cue, same
## bytes (a fixed LCG, no Math.random anywhere).
## Call shapes (dispatched by argc):
##   _render(freq, length_s, amp, decay)                    -> a static-tremolo voice
##   _render(freq, length_s, amp, hz_from, hz_to)           -> a pitch sweep (no decay)
##   _render(freq, length_s, amp, decay, hz_from, hz_to)    -> a sweep with a decay
static func stream_for(cue: String) -> AudioStreamWAV:
	match cue:
		"crack_rumble":
			# the 120-tick mark: a 50 Hz drone with random-ish noise clicks rising
			# 4 -> 20 Hz over 2.0 s
			return _render(50.0, 2.0, 0.55, 0.45)
		"shing":
			# the launch: a bright metallic sweep, sine 2000 -> 6000 Hz, 0.3 s
			return _render(4000.0, 0.3, 0.7, 0.2, 2000.0, 6000.0)
		"whoosh":
			# the 18-tick spear flight: band-passed noise sweeping down, 0.3 s
			return _render(900.0, 0.3, 0.5, 900.0, 300.0)
		"zone_open":
			# the tiles vanish: a hollow drop
			return _render(220.0, 0.4, 0.6, 220.0, 90.0)
		"zone_close":
			# the tiles fade back: the drop's reverse
			return _render(90.0, 0.4, 0.6, 220.0)
	return null


# ---- synthesis ---------------------------------------------------------------------------------


static func _render(freq: float, length_s: float, amp: float, a4: float,
		a5: float = -1.0, a6: float = -1.0) -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * length_s)
	var data := PackedByteArray()
	data.resize(n * 2)
	var hz_from := freq
	var hz_to := freq
	var decay := 3.0
	if a5 < 0.0:
		decay = a4                       # (freq, len, amp, decay)
	else:
		hz_to = a5                        # (freq, len, amp, hz_from, hz_to) - wait:
		# the 5-arg call shape passes (freq, len, amp, hz_from, hz_to): the freq's
		# END is a5 and there is no decay; the 6-arg shape passes a decay too.
		if a6 >= 0.0:
			decay = a4
			hz_to = a5
			a5 = a6
			hz_to = a6
	var rng := 987654321                    # fixed LCG seed: the bytes never drift
	for i in range(n):
		var t := float(i) / float(SAMPLE_RATE)
		var env: float = exp(-decay * t)
		var sweep := lerpf(hz_from, hz_to, clampf(t / length_s, 0.0, 1.0))
		var trem := 0.75 + 0.25 * sin(TAU * 5.0 * t)
		var s := sin(TAU * sweep * t) * amp * env * trem
		if decay > 2.9:
			rng = (1103515245 * rng + 12345) & 0x7FFFFFFF
			var noise: float = float(rng % 1000) / 500.0 - 1.0
			s += noise * 0.12 * env      # the clicks ride on the same envelope
		s = clampf(s, -1.0, 1.0)
		data.encode_s16(i * 2, int(round(s * 30000.0)))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = data
	return wav
