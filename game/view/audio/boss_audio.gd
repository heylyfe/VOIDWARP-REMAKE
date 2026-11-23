extends RefCounted
#
# The boss fight's own cues (T8b). One cue today: Peter's laugh, fired by the boss_laugh
# event when any attack connects.
#
# The owner asked for "laugh on death" and supplied no audio, so the placeholder is
# synthesized by game/tools/audio/synth_cues.gd (group "boss", seed 61) like every other
# cue in this game. The owner will drop the real clip in later, so the loader checks
# assets/owner_third_party/peter/laugh.ogg|mp3|wav FIRST and only falls back to the
# placeholder when none of them exists. That folder is the one place third-party art and
# audio live, so it can be removed in a single move.
#
# House shape (view/audio/cue_audio.gd): a static play function that loads the stream,
# returns null SILENTLY when the file is missing, creates the player, parents it to the
# host and starts it. A missing cue is never an error and never stalls the run. The load
# is gated on ResourceLoader.exists, never FileAccess.file_exists, so an export still
# finds the imported stream.

const CueAudio := preload("res://view/audio/cue_audio.gd")

const DIR := "res://assets/audio/boss"
const CUE_LAUGH := "laugh"
const OWNER_DIR := "res://assets/owner_third_party/peter"
const OWNER_BASENAME := "laugh"
## Checked in this order. The owner may drop any of the three.
const OWNER_EXTS := ["ogg", "mp3", "wav"]

const LAUGH_DB := -2.0


## Every cue this module can play, sorted (the test's table).
static func cue_names() -> Array:
	return [CUE_LAUGH]


## The res:// path for a declared cue, or "" when the name is not in the table.
static func path_for(cue: String) -> String:
	if not cue_names().has(cue):
		return ""
	return "%s/%s.wav" % [DIR, cue]


## The owner's real laugh if they have dropped one in, else "". Checked before the
## placeholder so the synthesized cue never plays over the real clip.
static func owner_laugh_path() -> String:
	for ext in OWNER_EXTS:
		var path := "%s/%s.%s" % [OWNER_DIR, OWNER_BASENAME, ext]
		if ResourceLoader.exists(path):
			return path
	return ""


## The laugh that will actually play: the owner's file when present, else the placeholder.
static func laugh_path() -> String:
	var owner := owner_laugh_path()
	return owner if owner != "" else path_for(CUE_LAUGH)


## Peter laughs. Returns the player, or null when neither file resolves.
static func play_laugh(host: Object) -> AudioStreamPlayer:
	return CueAudio.play_2d(host, laugh_path(), LAUGH_DB)
