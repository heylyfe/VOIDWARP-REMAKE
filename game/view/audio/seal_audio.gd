extends RefCounted
#
# seal placeholder audio hooks (ticket T-038). ENEMIES.md "New sound" line, verbatim:
# "actual seal barks (arf arf) on the dash, wet flipper flaps while it moves." The section 5.9
# cue split and the cue names ARE the file names (T-055's contract):
#   bark         - on tick 0 of the dash (DESIGN.md section 5.9; ENEMIES.md: the real seal
#                  bark replaces the copyrighted-era cry); 0.4 s; dry double arf
#   flipper_flap - wet flipper flaps while it moves - one per flap cycle (the T-083 anim
#                  block's 9 ticks per frame / telegraph's 6.6 Hz flap audio cadence) while
#                  flapping and during the telegraph; 0.3 s; low wet slap
#
# The files are placeholders synthesised by T-055 (tools/synth_audio.py, stdlib wave);
# they do not exist yet, so play() no-ops SILENTLY while a file is absent - the run never
# stalls on audio, and T-055's "every cue in enemy.json resolves to a file" check, not this
# file, decides when they land. Cue timings are driven by sim telegraph events and the sim
# tick counter, never by audio length (a missing/late wav cannot drift the sim).

const CUE_BARK := "bark"
const CUE_FLIPPER_FLAP := "flipper_flap"
const DIR := "res://assets/audio/enemies/seal"
const EXTENSION := ".wav"


## Plays one cue. p_volume in [0, 1] scales with distance. Returns true when a file existed
## and an AudioStreamPlayer was started via the given parent node; false (silently) otherwise
## - a missing placeholder is not an error.
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

