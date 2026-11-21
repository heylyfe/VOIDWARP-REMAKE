extends RefCounted
#
# The two beds (the owner's "the game is too quiet" pass): the lobby ambience and the
# music bed. Both are synthesized by game/tools/audio/synth_cues.gd and both LOOP - the
# generator crossfades each one's tail into its head, so the loop point is seamless.
#
#   lobby_ambience  the Antechamber's low drone and air (4 s loop)
#   music_bed       the menu's four-chord pad (8 s loop, Am - F - C - G)
#
# House shape (view/audio/cue_audio.gd): a static start function that loads the stream,
# returns null SILENTLY when the file is missing, creates the player, parents it to the
# host and starts it. A missing bed is never an error and never stalls the screen.
#
# A bed is a long-lived player: the caller owns it and passes it back to stop() when the
# screen it belongs to goes away. Call sites pass no cue-name string at all.

const CueAudio := preload("res://view/audio/cue_audio.gd")

const DIR := "res://assets/audio/ambience"
const CUE_LOBBY := "lobby_ambience"
const CUE_MUSIC := "music_bed"

const LOBBY_DB := -20.0   # a bed sits well under every cue
const MUSIC_DB := -22.0


## Every cue this module can play, sorted (the test's table).
static func cue_names() -> Array:
	var out: Array = [CUE_LOBBY, CUE_MUSIC]
	out.sort()
	return out


## The res:// path for a declared cue, or "" when the name is not in the table.
static func path_for(cue: String) -> String:
	if not cue_names().has(cue):
		return ""
	return "%s/%s.wav" % [DIR, cue]


## Starts the lobby ambience loop. The caller owns the player and stops it with stop().
static func start_lobby(host: Object) -> AudioStreamPlayer:
	return CueAudio.loop_2d(host, path_for(CUE_LOBBY), LOBBY_DB)


## Starts the music bed loop. The caller owns the player and stops it with stop().
static func start_music(host: Object) -> AudioStreamPlayer:
	return CueAudio.loop_2d(host, path_for(CUE_MUSIC), MUSIC_DB)


static func stop(player: AudioStreamPlayer) -> void:
	CueAudio.stop_loop(player)

