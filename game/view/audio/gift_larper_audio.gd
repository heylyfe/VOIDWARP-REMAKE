extends RefCounted
#
# gift Larper placeholder audio hooks (ticket T-036). ENEMIES.md "New sound" line, verbatim:
# "Roblox tripmine explosion sound effect." The cue names ARE the file names (T-055's contract,
# the kiwi cat pattern):
#   explosion - fired on the contact tick when the ladder reaches death (D-MINE); the
#               synthesized blast (TBD.md section 2); 0.5 s class
#   pff       - fired when the ladder defuses the mine (defuse roll passed / Subspacial
#               Barrier consumed): the anim block's defused puff - a small hiss, the kill
#               does NOT happen
#
# The files are placeholders T-055 will synthesise (tools/synth_audio.py, stdlib wave); they do
# not exist yet, so play() no-ops SILENTLY while the file is absent - the run never stalls on
# audio, and T-055's "every cue in enemy.json resolves to a file" check, not this file, decides
# when they land. Cue timings are driven by the sim/mine ladder outcome (the view's
# on_detonation / on_defused), never by audio length.

const CUE_EXPLOSION := "explosion"
const CUE_PFF := "pff"
const DIR := "res://assets/audio/enemies/gift_larper"
const EXTENSION := ".wav"


## Plays one cue. p_volume in [0, 1] scales with distance (the tell is 12 u - the blast
## carries farther, but the caller decides). Returns true when a file existed and an
## AudioStreamPlayer was started via the given parent node; false (silently) otherwise - a
## missing placeholder is not an error.
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
