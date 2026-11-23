extends RefCounted

## Bankai's view-only cues, generated as PCM and shared by every performance.
const RATE := 22050
const CUES := {
	"hum": [1.0, -28.0],
	"charge": [2.2, -19.0],
	"impact": [0.54, -17.0],
	"volley": [1.45, -21.0],
	"kill": [1.3, -16.0],
}

static var _streams: Dictionary = {}


static func make_player(host: Node, cue: String) -> AudioStreamPlayer:
	if not _streams.has(cue):
		_streams[cue] = _synth(cue, float(CUES[cue][0]))
	var player := AudioStreamPlayer.new()
	player.name = cue
	player.stream = _streams[cue]
	player.volume_db = float(CUES[cue][1])
	host.add_child(player)
	return player


static func _synth(cue: String, duration: float) -> AudioStreamWAV:
	var count := roundi(duration * RATE)
	var pcm := PackedByteArray()
	pcm.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 61
	var low_noise := 0.0
	for i in count:
		var t := float(i) / RATE
		var p := t / duration
		low_noise = lerpf(low_noise, rng.randf_range(-1.0, 1.0), 0.09)
		var sample := 0.0
		match cue:
			"hum":
				# Integer periods join at the loop boundary.
				sample = (0.5 * sin(TAU * 48.0 * t) + 0.18 * sin(TAU * 96.0 * t)) \
						* (0.8 + 0.2 * cos(TAU * t))
			"charge":
				sample = (0.48 * sin(TAU * (95.0 * t + 90.0 * t * t)) + 0.65 * low_noise) * p
			"impact":
				sample = (0.65 * sin(TAU * (56.0 * t + 4.5 * (1.0 - exp(-18.0 * t)))) \
						+ 0.6 * low_noise) * exp(-9.0 * t)
			"volley":
				for ping in 5:
					var age := t - 0.11 * ping
					if age >= 0.0:
						sample += 0.16 * sin(TAU * (740.0 + 175.0 * ping) * age) \
								* minf(age * 160.0, 1.0) * exp(-9.0 * age)
			"kill":
				sample = (0.65 * sin(TAU * (38.0 * t + 3.0 * (1.0 - exp(-10.0 * t)))) \
						+ 0.65 * low_noise) * exp(-3.5 * t)
		if cue != "hum":
			sample *= smoothstep(0.0, 0.008, t) * (1.0 - smoothstep(0.88, 1.0, p))
		pcm.encode_s16(i * 2, roundi(clampf(sample, -0.8, 0.8) * 32767.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = pcm
	if cue == "hum":
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = count
	return stream
