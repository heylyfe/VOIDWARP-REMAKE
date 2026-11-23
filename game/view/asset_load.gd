extends RefCounted
#
# view/asset_load.gd - the one place a missing asset is reported (U4, cycle 8).
#
# Terra's bug hunt (game/out/BUGHUNT_terra.md) found godot.log carrying "instantiate on
# null" for res://assets/models/player_figure.glb when the import cache was missing. A
# missing asset must never crash the game, and it must never be silent either: a silent
# fallback hides a broken export until the owner reports "the player is invisible".
#
# So every asset load in the game goes through here. Each helper:
#   - gates on ResourceLoader.exists(), NEVER FileAccess.file_exists(): an export packs
#     the imported resource and its remap, not the raw .glb / .mp3 (the lesson
#     view/audio/cue_audio.gd records for the beacon cue);
#   - reports the path ONCE, clearly, through push_warning - a level that draws 40 gifts
#     must not print 40 lines;
#   - returns null so the caller can fall back (a blocky figure, a silent cue, a skipped
#     scene) and carries on.
#
# The report is a warning, not an error: the game is still playable, and the gate's
# Assert-NoScriptError step must not fail on a deliberately-missing test asset.

static var _reported: Dictionary = {}


## True when this path has already been reported (the test seam reads it).
static func reported(path: String) -> bool:
	return _reported.has(path)


## Forget every report, so a test that proves a fallback sees the report again.
static func reset_reports() -> void:
	_reported.clear()


static func _report(path: String, what: String) -> void:
	if _reported.has(path):
		return
	_reported[path] = true
	push_warning("asset_load: %s missing or unloadable: %s (falling back)" % [what, path])


## A PackedScene (a .glb model, a .tscn), or null. The caller instantiates only when
## this is non-null - never `load(path).instantiate()`.
static func scene(path: String) -> PackedScene:
	if not ResourceLoader.exists(path):
		_report(path, "scene")
		return null
	var res: Variant = load(path)
	if res == null or not (res is PackedScene):
		_report(path, "scene")
		return null
	return res as PackedScene


## A Texture2D, or null (the caller draws its placeholder).
static func texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		_report(path, "texture")
		return null
	var res: Variant = load(path)
	if res == null or not (res is Texture2D):
		_report(path, "texture")
		return null
	return res as Texture2D


## An AudioStream, or null (the cue is silent, never an error).
static func stream(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		_report(path, "audio stream")
		return null
	var res: Variant = load(path)
	if res == null or not (res is AudioStream):
		_report(path, "audio stream")
		return null
	return res as AudioStream


## A Script module (an upgrade / curse / enemy behavior), or null.
static func script_module(path: String) -> Script:
	if not ResourceLoader.exists(path):
		_report(path, "script")
		return null
	var res: Variant = load(path)
	if res == null or not (res is Script):
		_report(path, "script")
		return null
	return res as Script
