extends RefCounted
#
# The player's own cues (the owner's "the game is too quiet" pass): footsteps, landing,
# dash and the glide wind. Every file is synthesized by game/tools/audio/synth_cues.gd -
# no sampled, recorded or downloaded audio ships here.
#
#   footstep_01..04  one per step, four variants so a run does not machine-gun one sample
#   land             the body thud on touching down
#   dash             the air being cut, on the dash's start tick
#   glide            wind under the wing, LOOPED while the glider is out
#   jump_pad         the springy rising boing of a jump pad firing (D-JUMPPAD-5)
#
# House shape (view/audio/cue_audio.gd): a static play function that loads the stream,
# returns null SILENTLY when the file is missing, creates the player, parents it to the
# host and starts it. A missing cue is never an error and never stalls the run.
#
# Call sites pass a VARIANT INDEX, never a cue-name string, so a typo cannot ship silent:
# the only place a name appears is the table below, and tests/test_audio_cues_synth.gd
# proves every name in it resolves through ResourceLoader.exists and loads as an
# AudioStream.

const CueAudio := preload("res://view/audio/cue_audio.gd")

const DIR := "res://assets/audio/player"
const CUE_LAND := "land"
const CUE_DASH := "dash"
const CUE_GLIDE := "glide"
const CUE_JUMP_PAD := "jump_pad"
const FOOTSTEPS := ["footstep_01", "footstep_02", "footstep_03", "footstep_04"]

const STEP_DB := -9.0     # a step is a texture under the level, not an event
const LAND_DB := -5.0
const DASH_DB := -4.0
const JUMP_PAD_DB := -3.0
const GLIDE_DB := -14.0   # a bed: it must sit under everything else while it runs


## Every cue this module can play, sorted (the test's table).
static func cue_names() -> Array:
	var out: Array = [CUE_LAND, CUE_DASH, CUE_GLIDE, CUE_JUMP_PAD]
	out.append_array(FOOTSTEPS)
	out.sort()
	return out


## The res:// path for a declared cue, or "" when the name is not in the table (the
## negative-control entry point: an undeclared name must never resolve).
static func path_for(cue: String) -> String:
	if not cue_names().has(cue):
		return ""
	return "%s/%s.wav" % [DIR, cue]


## One footstep. `variant` is wrapped into the four-variant table, so any integer is safe.
static func play_footstep(host: Object, variant: int) -> AudioStreamPlayer:
	var i := posmod(variant, FOOTSTEPS.size())
	return CueAudio.play_2d(host, path_for(str(FOOTSTEPS[i])), STEP_DB)


static func play_land(host: Object) -> AudioStreamPlayer:
	return CueAudio.play_2d(host, path_for(CUE_LAND), LAND_DB)


static func play_dash(host: Object) -> AudioStreamPlayer:
	return CueAudio.play_2d(host, path_for(CUE_DASH), DASH_DB)


static func play_jump_pad(host: Object) -> AudioStreamPlayer:
	return CueAudio.play_2d(host, path_for(CUE_JUMP_PAD), JUMP_PAD_DB)


## Starts the glide wind loop. The caller owns the player and passes it back to
## stop_glide() when the glide ends; null (silently) when the cue is missing.
static func start_glide(host: Object) -> AudioStreamPlayer:
	return CueAudio.loop_2d(host, path_for(CUE_GLIDE), GLIDE_DB)


static func stop_glide(player: AudioStreamPlayer) -> void:
	CueAudio.stop_loop(player)

