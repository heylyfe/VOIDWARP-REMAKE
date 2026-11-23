extends RefCounted
#
# claude placeholder audio hooks - the CYCLE 7 REVAMP (track T4; D-T4-8).
#
# The owner's words (CYCLE7_BRIEF.md T4): "If no clawd is collected for 60 s, Claude releases a warning sound (a
# new synth cue). At 120 s, a second, more urgent sound." The cue names ARE the file names (T-055's contract):
#   claude_warning_1 - the 60 s warning: a two-note rising chime with a bell tail
#   claude_warning_2 - the 120 s warning: a three-note alarm, higher, faster, detuned
# Both are synthesised by tools/synth_audio.py (new voices, nothing copied - ENEMIES.md's "all sounds are
# brand-new"). The old musical-kit cues (ui_chime / keystroke_tick / notification_ping / squeak_pop) are no
# longer played by this enemy: the revamped behavior has no attacks and no plushies.
#
# play() no-ops SILENTLY while a file is absent - the run never stalls on audio. Cue timings are driven by the
# sim's clawd_warning event, never by audio length.

const CUE_WARNING_1 := "claude_warning_1"
const CUE_WARNING_2 := "claude_warning_2"
const DIR := "res://assets/audio/enemies/claude"
const EXTENSION := ".wav"


## The cue name for a warning level (1 or 2); "" for anything else.
static func cue_for_level(level: int) -> String:
	if level == 1:
		return CUE_WARNING_1
	if level == 2:
		return CUE_WARNING_2
	return ""


## Plays one cue. p_volume in [0, 1] scales with distance. Returns true when a file
## existed and an AudioStreamPlayer was started; false (silently) otherwise - a missing
## placeholder is not an error.
static func play(parent: Node, cue: String, p_volume: float = 1.0) -> bool:
	if parent == null or not parent.is_inside_tree() or cue == "":
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
