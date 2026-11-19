extends RefCounted
#
# Model-materials guard (ticket J12). Text + container scan, run headless by
# res://tests/run_all.gd. Guards against the "model renders default white" defect
# class that shipped four times (J3 gold gift, J8 black gift, J10 tripmine,
# J11 player figure):
#
# Every .glb under res://assets/models/ is exported with NO materials
# (assets_src t015_common.py uses export_materials="NONE") and carries its palette
# in vertex colours (COLOR_0). A view that does not assign a BASE material with
# vertex_color_use_as_albedo therefore renders Godot's default WHITE and the
# palette is never seen. This test stops a fifth occurrence:
#
# Rule A (models): enumerate EVERY *.glb under res://assets/models/ at run time
#   (DirAccess, not a hardcoded list - a new model is covered automatically).
#   Read the glb's JSON chunk (12-byte header, then length/type chunks, chunk
#   type "JSON") and classify:
#     - materials == 0 (the key may be absent): every primitive of every mesh
#       MUST declare COLOR_0 in its attributes, else the model carries no
#       palette at all and no loader can save it - FAIL naming the model and
#       the offending primitive index.
#     - materials > 0: the model SHIPS its own materials. That is allowed, and
#       it is never silently accepted: an explicit NOTE line is printed naming
#       the model and its material count, and the vertex-colour requirement is
#       dropped for it. (If that happens, loaders of THAT model are not
#       required to set vertex_color_use_as_albedo - see Rule B's file scope.)
#
# Rule B (loaders): every .gd file under res://view/ and res://app/ whose text
#   contains "res://assets/models/" loads a model, so it must either
#     - contain the string "vertex_color_use_as_albedo" (it assigns a base
#       material that reads the mesh's vertex colours, directly or via a helper),
#       or
#     - be listed in ALLOW_LIST below with a reason (an explicit, reviewed
#       exception - e.g. a white invulnerability shell that deliberately does
#       not render the model's palette).
#   Anything else FAILs: adding a new .glb-loading view without a vertex-colour
#   base material (or without a conscious allow-list entry) is a test failure.
#   Rule B is FILE-scoped, not call-site-scoped: it cannot prove that the exact
#   load() call site assigns the material, only that the file builds one. That
#   is the strongest check a headless text scan can make; the allow-list keeps
#   the exceptions explicit and named.
#   Anti-rot: an allow-list entry whose file vanished, no longer loads a model,
#   or now contains "vertex_color_use_as_albedo" is a STALE entry and FAILs -
#   the list can never silently grow or silently outlive its reason.
#
# game/tests/ and game/tools/ also load models but are out of scope for Rule B
# (they are harnesses and checkers, not renderers); test_player_anim.gd loads
# the player figure in a fixture context.

const MODELS_DIR := "res://assets/models"
const SCAN_DIRS: Array[String] = ["res://view", "res://app"]
const GLB_MAGIC := 0x46546C67   # "glTF" little-endian
const CHUNK_JSON := 0x4E4F534A  # "JSON" little-endian

## Explicit exceptions to Rule B, each with its reason (J12). Keep this list
## SHORT and every entry names why the file does NOT assign a vertex-colour
## base material. Adding an entry without a reason is a review failure.
const ALLOW_LIST := {
	"res://view/respawn_view.gd": "loads player_figure.glb solely to draw the invulnerability rim: a CULL_FRONT white unshaded back-face shell (alpha blink, 8 Hz) around the player model the caller owns. It never renders the model's body or palette, so vertex_color_use_as_albedo is meaningless here by design (T-085 section 2.5).",
}


func run() -> Array[String]:
	var failures: Array[String] = []
	var glbs := _enumerate_glbs()
	if glbs.is_empty():
		failures.append("no .glb found under %s - the model scan is broken" % MODELS_DIR)
		return failures
	var vertex_colour_models := 0
	var self_materialed := 0
	for path in glbs:
		var doc = _read_glb_json(path, failures)
		if typeof(doc) != TYPE_DICTIONARY:
			continue   # _read_glb_json already appended the failure
		var mats: Array = doc.get("materials", [])
		if mats.size() > 0:
			# A model that ships materials is fine - but say so explicitly.
			self_materialed += 1
			print("NOTE %s ships its own materials (%d); vertex-colour base material not required by this guard" % [path.get_file(), mats.size()])
			continue
		vertex_colour_models += 1
		_check_vertex_colours(path, doc, failures)
	# Rule B: the loader scan.
	var loaders := 0
	var allow_listed := 0
	for dir_path in SCAN_DIRS:
		for file_path in _scan_gd_files(dir_path):
			var text := _read(file_path)
			if not text.contains("res://assets/models/"):
				continue
			loaders += 1
			var rel := file_path
			if ALLOW_LIST.has(rel):
				allow_listed += 1
				if text.contains("vertex_color_use_as_albedo"):
					failures.append("%s allow-list entry is stale: the file now assigns vertex-colour base materials - remove the entry" % rel)
				continue
			if not text.contains("vertex_color_use_as_albedo"):
				failures.append("%s loads a model under res://assets/models/ but never assigns a base material with vertex_color_use_as_albedo (and is not on the J12 allow-list) - the model renders Godot's default white" % rel)
	# Anti-rot: every allow-list entry must still exist, still load a model,
	# and still not carry a vertex-colour pass (checked above).
	for rel in ALLOW_LIST:
		var text := _read(rel)
		if text.is_empty():
			failures.append("allow-list entry %s: file missing or unreadable - remove the stale entry" % rel)
		elif not text.contains("res://assets/models/"):
			failures.append("allow-list entry %s: file no longer loads a model - remove the stale entry" % rel)
	print("NOTE %d glbs enumerated (%d vertex-colour palette, %d self-materialed), %d loaders checked, %d allow-listed" % [glbs.size(), vertex_colour_models, self_materialed, loaders, allow_listed])
	return failures


# Every *.glb under MODELS_DIR (recursively), sorted.
func _enumerate_glbs() -> Array[String]:
	var out: Array[String] = []
	_collect_glbs(MODELS_DIR, out)
	out.sort()
	return out


func _collect_glbs(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for f in dir.get_files():
		if f.to_lower().ends_with(".glb"):
			out.append(dir_path + "/" + f)
	for sub in dir.get_directories():
		if sub.begins_with("."):
			continue
		_collect_glbs(dir_path + "/" + sub, out)


# Parses the glb JSON chunk. Appends a failure and returns null on any structural
# problem (bad magic, truncated header, missing/unparsable JSON chunk).
func _read_glb_json(path: String, failures: Array[String]):
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		failures.append("%s: cannot open (error %d)" % [path, FileAccess.get_open_error()])
		return null
	var bytes := f.get_buffer(f.get_length())
	f.close()
	var name := path.get_file()
	if bytes.size() < 20:
		failures.append("%s: too small to be a glb (%d bytes)" % [name, bytes.size()])
		return null
	var magic := _u32(bytes, 0)
	if magic != GLB_MAGIC:
		failures.append("%s: bad magic 0x%08x (not a glb)" % [name, magic])
		return null
	var offset := 12
	while offset + 8 <= bytes.size():
		var chunk_len := _u32(bytes, offset)
		var chunk_type := _u32(bytes, offset + 4)
		var data_start := offset + 8
		if data_start + chunk_len > bytes.size():
			failures.append("%s: truncated chunk at offset %d" % [name, offset])
			return null
		if chunk_type == CHUNK_JSON:
			var text := bytes.slice(data_start, data_start + chunk_len).get_string_from_utf8()
			var parsed = JSON.parse_string(text)
			if typeof(parsed) != TYPE_DICTIONARY:
				failures.append("%s: JSON chunk did not parse to a dictionary" % name)
				return null
			return parsed
		offset = data_start + chunk_len
	failures.append("%s: no JSON chunk found" % name)
	return null


static func _u32(bytes: PackedByteArray, at: int) -> int:
	return bytes[at] | (bytes[at + 1] << 8) | (bytes[at + 2] << 16) | (bytes[at + 3] << 24)


# Rule A, vertex-colour branch: every primitive of every mesh must carry COLOR_0.
func _check_vertex_colours(path: String, doc: Dictionary, failures: Array[String]) -> void:
	var name := path.get_file()
	var meshes: Array = doc.get("meshes", [])
	if meshes.is_empty():
		failures.append("%s: declares no meshes and no materials - nothing to render" % name)
		return
	var total_prims := 0
	for mi in meshes.size():
		var mesh: Dictionary = meshes[mi]
		var prims: Array = mesh.get("primitives", [])
		for pi in prims.size():
			total_prims += 1
			var attrs: Dictionary = prims[pi].get("attributes", {})
			if not attrs.has("COLOR_0"):
				failures.append("%s: mesh %d primitive %d has no COLOR_0 and the model ships no materials - no loader can give it a palette" % [name, mi, pi])
	if total_prims == 0:
		failures.append("%s: declares meshes with zero primitives" % name)


# Every .gd under dir_path, recursively, sorted.
func _scan_gd_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.to_lower().ends_with(".gd"):
			out.append(dir_path + "/" + f)
	for sub in dir.get_directories():
		if sub.begins_with("."):
			continue
		for p in _scan_gd_files(dir_path + "/" + sub):
			out.append(p)
	out.sort()
	return out


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text
