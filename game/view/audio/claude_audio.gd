extends RefCounted
#
# claude placeholder audio hooks (ticket T-040). ENEMIES.md "New sound" line, verbatim:
# "Claude-themed instrument set - soft UI chimes, keystroke ticks and notification pings
# for the drums/strings/wind attacks; cute squeak-pop when you pick up a plushie to calm
# it down." The cue names ARE the file names (T-055's contract; seal_audio/CUE_* idiom):
#   ui_chime          - soft UI chime, on the tick a drum ring fires (beats 1 and 3)
#   keystroke_tick    - keystroke tick, on the tick the strings telegraph line appears
#                       and while the beam sweeps (one per beat)
#   notification_ping - notification ping, on the tick each wind shot launches
#   squeak_pop        - cute squeak-pop, on the tick a clawd Crab plushie is picked up
#
# The wav files are placeholders synthesised by T-055's pipeline and do not exist yet,
# so play() no-ops SILENTLY while a file is absent - the run never stalls on audio.
# Cue timings are driven by the sim row's tick stamps (last_drum_tick / last_sweep_tick
# / last_shot_tick / last_pickup_tick), never by audio length.

const CUE_UI_CHIME := "ui_chime"
const CUE_KEYSTROKE_TICK := "keystroke_tick"
const CUE_NOTIFICATION_PING := "notification_ping"
const CUE_SQUEAK_POP := "squeak_pop"
const DIR := "res://assets/audio/enemies/claude"
const EXTENSION := ".wav"


## Plays one cue. p_volume in [0, 1] scales with distance. Returns true when a file
## existed and an AudioStreamPlayer was started; false (silently) otherwise - a missing
## placeholder is not an error.
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
