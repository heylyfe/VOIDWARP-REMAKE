extends RefCounted
#
# kiwi cat placeholder audio hooks (ticket T-030). ENEMIES.md "New sound" line, verbatim:
# "cat meow when near player." The section 3 sound brief splits it into two cues, and the
# cue names ARE the file names (T-055's contract):
#   meow         - every 180 ticks while within 14 u; 0.35 s; sine glide 700 -> 1100 -> 600 Hz,
#                  vibrato 8 Hz, soft attack; volume rises as the cat closes in
#   meow_double  - Zoomies (script curse): two meows 12 ticks apart, pitched up a fourth
#
# The files are placeholders synthesised by T-055 (tools/synth_audio.py, stdlib wave);
# they do not exist yet, so play() no-ops SILENTLY while the file is absent - the run never
# stalls on audio, and T-055's "every cue in enemy.json resolves to a file" check, not this
# file, decides when they land. Cue timings are driven by sim telegraph events, never by
# audio length (a missing/late wav cannot drift the sim).

const CUE_MEOW := "meow"
const CUE_MEOW_DOUBLE := "meow_double"
const DIR := "res://assets/audio/enemies/kiwi_cat"
const EXTENSION := ".wav"


## Plays one cue. p_volume in [0, 1] scales with distance (the brief: volume rises as the cat
## closes). Returns true when a file existed and an AudioStreamPlayer was started via the
## given parent node; false (silently) otherwise - a missing placeholder is not an error.
static func play(parent: Node, cue: String, p_volume: float = 1.0) -> bool:
	if parent == null or not parent.is_inside_tree():
		return false
	var path := "%s/%s%s" % [DIR, cue, EXTENSION]
	if not ResourceLoader.exists(path):
		return false
	var stream: Variant = load(path)
	if stream == null:
		return false
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = linear_to_db(clampf(p_volume, 0.001, 1.0))
	player.autoplay = true
	parent.add_child(player)
	return true

