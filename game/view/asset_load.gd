extends RefCounted
#
# view/asset_load.gd - the one place a missing asset is reported (U4, cycle 8).
#
# Terra's bug hunt (game/out/BUGHUNT_terra.md) found godot.log carrying "instantiate on
# null" for the player figure model when the import cache was missing. A
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


## A data file's text (a JSON document under res://data/ or res://content/), or "".
## The caller parses and falls back; a missing file is reported once and never fatal.
static func text(path: String) -> String:
	if not ResourceLoader.exists(path):
		_report(path, "data file")
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_report(path, "data file")
		return ""
	var out := f.get_as_text()
	f.close()
	return out


## U4 (Terra finding 3, the teardown null-material error). Clears every surface
## override material under root by sending RID() to the rendering server.
##
## Why this exists: a MeshInstance3D's surface-override Refs are released by
## ~MeshInstance3D, but the rendering-server instance is freed later, by
## ~VisualInstance3D -> free_rid -> instance_free, whose update_dirty_instances() still
## reads the instance's surface-material RIDs. Freeing a node whose overrides are still
## set therefore leaves the RS instance holding a DANGLING material RID, and the dummy
## renderer prints `ERROR: Parameter "material" is null` at
## material_get_instance_shader_parameters from the free (world.gd teardown backtrace).
## Clearing the overrides BEFORE the free replaces those RIDs with a valid null, which
## the update path guards - the error stops because the dangling RID no longer exists,
## not because anything is suppressed. (material_override / material_overlay need no
## help: ~GeometryInstance3D clears them itself, before the RS instance is freed.)
static func release_materials(root: Node) -> void:
	if root == null:
		return
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh != null:
				for s in mi.mesh.get_surface_count():
					mi.set_surface_override_material(s, null)
