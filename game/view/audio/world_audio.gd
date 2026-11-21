extends RefCounted
#
# The world's own cues (the owner's "the game is too quiet" pass): the gift pickup, the
# level-complete sting, the death sting and the two halves of a platform collapse. Every
# file is synthesized by game/tools/audio/synth_cues.gd - no sampled audio ships here.
#
#   gift_pickup_01..03  one per black gift collected, three variants so a chain does not
#                       grate (A5 / B5 / D6, a whole tone apart)
#   level_complete      the rising arpeggio on the beacon entry
#   death               the falling sting when the run ends
#   collapse_crack      the crackle when a zone starts to crack
#   collapse_fall       the rumble when that zone's tiles leave collision
#
# House shape (view/audio/cue_audio.gd): a static play function that loads the stream,
# returns null SILENTLY when the file is missing, creates the player, parents it to the
# host and starts it. A missing cue is never an error and never stalls the run.
#
# Call sites pass a VARIANT INDEX, never a cue-name string, so a typo cannot ship silent.

const CueAudio := preload("res://view/audio/cue_audio.gd")

const DIR := "res://assets/audio/world"
const CUE_LEVEL_COMPLETE := "level_complete"
const CUE_DEATH := "death"
const CUE_COLLAPSE_CRACK := "collapse_crack"
const CUE_COLLAPSE_FALL := "collapse_fall"
const GIFT_PICKUPS := ["gift_pickup_01", "gift_pickup_02", "gift_pickup_03"]

const GIFT_DB := -4.0
const COMPLETE_DB := -3.0
const DEATH_DB := -2.0
const CRACK_DB := -7.0
const FALL_DB := -5.0


## Every cue this module can play, sorted (the test's table).
static func cue_names() -> Array:
	var out: Array = [CUE_LEVEL_COMPLETE, CUE_DEATH, CUE_COLLAPSE_CRACK, CUE_COLLAPSE_FALL]
	out.append_array(GIFT_PICKUPS)
	out.sort()
	return out


## The res:// path for a declared cue, or "" when the name is not in the table.
static func path_for(cue: String) -> String:
	if not cue_names().has(cue):
		return ""
	return "%s/%s.wav" % [DIR, cue]


## One gift pickup. `variant` is wrapped into the three-variant table, so any integer is
## safe (the caller passes the slot id, which is stable per gift).
static func play_gift_pickup(host: Object, variant: int) -> AudioStreamPlayer:
	var i := posmod(variant, GIFT_PICKUPS.size())
	return CueAudio.play_2d(host, path_for(str(GIFT_PICKUPS[i])), GIFT_DB)


static func play_level_complete(host: Object) -> AudioStreamPlayer:
	return CueAudio.play_2d(host, path_for(CUE_LEVEL_COMPLETE), COMPLETE_DB)


static func play_death(host: Object) -> AudioStreamPlayer:
	return CueAudio.play_2d(host, path_for(CUE_DEATH), DEATH_DB)


static func play_collapse_crack(host: Object) -> AudioStreamPlayer:
	return CueAudio.play_2d(host, path_for(CUE_COLLAPSE_CRACK), CRACK_DB)


static func play_collapse_fall(host: Object) -> AudioStreamPlayer:
	return CueAudio.play_2d(host, path_for(CUE_COLLAPSE_FALL), FALL_DB)

