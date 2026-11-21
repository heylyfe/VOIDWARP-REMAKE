extends RefCounted
#
# Menu cues: the hover tick and the click. Both are synthesized by
# game/tools/audio/synth_cues.gd (no sampled audio ships here).
#
#   menu_hover   one soft high tick when the selection moves onto an entry
#   menu_click   two tones a fifth apart when an entry is activated
#
# House shape (view/audio/cue_audio.gd): a static play function that loads the stream,
# returns null SILENTLY when the file is missing, creates the player, parents it to the
# host and starts it. A missing cue is never an error and never stalls the menu.
#
# The menu is a Control, not a Node3D, so both cues are non-positional. Call sites pass no
# cue-name string at all (play_hover / play_click), so a typo cannot ship silent.

const CueAudio := preload("res://view/audio/cue_audio.gd")

const DIR := "res://assets/audio/ui"
const CUE_HOVER := "menu_hover"
const CUE_CLICK := "menu_click"

const HOVER_DB := -16.0   # a tick under the music bed, never a click in the ear
const CLICK_DB := -8.0


## Every cue this module can play, sorted (the test's table).
static func cue_names() -> Array:
	var out: Array = [CUE_HOVER, CUE_CLICK]
	out.sort()
	return out


## The res:// path for a declared cue, or "" when the name is not in the table.
static func path_for(cue: String) -> String:
	if not cue_names().has(cue):
		return ""
	return "%s/%s.wav" % [DIR, cue]


static func play_hover(host: Object) -> AudioStreamPlayer:
	return CueAudio.play_2d(host, path_for(CUE_HOVER), HOVER_DB)


static func play_click(host: Object) -> AudioStreamPlayer:
	return CueAudio.play_2d(host, path_for(CUE_CLICK), CLICK_DB)

