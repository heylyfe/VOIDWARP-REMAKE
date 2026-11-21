extends RefCounted
#
# The enemy cues that ride a ROW STATE EDGE instead of a sim event (the "too quiet" pass's
# audit of view/audio/ and the enemy views).
#
# The audit's finding: every enemy cue file exists (T-055's tools/synth_audio.py made them)
# and most are played - the telegraph tells through view/vfx/telegraph_view.gd's TELL_CUES,
# the data-driven offsets through view/audio/threat_cues.gd, the bespoke views through their
# own modules. Two lethal attacks had a file and no player at all, because their
# enemy.json row names a sim event the sim never raises:
#
#   nuke  impact_boom   event "blast"    - the explosion frame (anim_state attack_explosion)
#   you   ring_release  event "release"  - the shockwave band (anim_state attack)
#
# Both are visible as an anim_state edge on the live row, so that is where they are played:
# app/world.gd's per-row pass calls play_state() on every state change, for bespoke and
# billboard rows alike. The table below is the whole contract - an id/state pair that is not
# in it plays nothing.
#
# Still unplayed after this pass, and why (recorded in TBD.md):
#   gift_larper mine_hum  event "proximity_6u"  - a proximity LOOP, not a telegraph/attack
#   toucher     prowl     event "proximity_14u" - same
#   kiwi_cat    meow_double  event "zoomies"    - the zoomies event does not exist in the sim
#
# House shape (view/audio/cue_audio.gd): a static play function that loads the stream,
# returns null SILENTLY when the file is missing, creates the player, parents it to the host
# and starts it. A missing cue is never an error and never stalls the run.

const CueAudio := preload("res://view/audio/cue_audio.gd")

const DIR := "res://assets/audio/enemies"

# enemy id -> anim_state -> cue name. Only the edges with no sim event of their own.
const STATE_CUES := {
	"nuke": {"attack_explosion": "impact_boom"},
	"you": {"attack": "ring_release"},
}

const STATE_DB := -3.0
const STATE_UNIT_SIZE := 14.0


## The cue an id/state edge carries, or "" when the edge has none (the negative-control
## entry point: an undeclared pair must never resolve).
static func cue_for_state(enemy_id: String, state: String) -> String:
	var rows: Variant = STATE_CUES.get(enemy_id, null)
	if not (rows is Dictionary):
		return ""
	return str((rows as Dictionary).get(state, ""))


## The res:// path for a declared id/state edge, or "" when the pair is not in the table.
static func path_for_state(enemy_id: String, state: String) -> String:
	var cue := cue_for_state(enemy_id, state)
	if cue == "":
		return ""
	return "%s/%s/%s.wav" % [DIR, enemy_id, cue]


## Plays the edge's cue at `pos` under `host`, or returns null (silently) when the edge has
## no cue or the file is missing.
static func play_state(host: Object, enemy_id: String, state: String,
		pos: Vector3) -> AudioStreamPlayer3D:
	var path := path_for_state(enemy_id, state)
	if path == "":
		return null
	return CueAudio.play_3d(host, path, pos, STATE_DB, STATE_UNIT_SIZE)

