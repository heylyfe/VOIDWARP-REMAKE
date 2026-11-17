extends RefCounted
#
# Boundary scan (FLEET_PACK.md section 3, ticket T-001; FIX-A14 / D-FIX-A14-1). A text scan,
# run headless by res://tests/run_all.gd. The dependency rule:
#   terrain imports nothing; sim may use terrain and core; core may use terrain;
#   view and app may use everything.
#   Nothing under terrain/ sim/ core/ may contain the strings listed in FORBIDDEN_STRINGS
#   (.gd only) or any content id (.gd and .json); app/ may use the engine ("view and app
#   may use everything", FLEET_PACK section 3) but no app file may name a content id
#   either (.gd and .json). .gd files under terrain/ sim/ core/ may not import a res://
#   path outside their layer's allowed prefixes.
# "contains" is matched on whole files, comments included: the point is that no engine API or
# content name leaks into these layers, whatever the line type.
#
# The content ids are NOT listed here: they are discovered at run time by scanning
# res://content/enemies/ (folder names), res://content/curses/, res://content/upgrades/ and
# res://content/biomes/ (*.json file names), so the check grows with the content tree and
# cannot rot. Matching is case-sensitive and whole-word (an id bounded by non-word characters
# or the file edge), which keeps prose like "D-GIN" from tripping the lowercase id "gin" -
# and which is why English prose that collides with an id ("more", "you") is reworded in the
# offending file, never allowlisted.

# Forbidden anywhere under game/terrain/, game/sim/, game/core/ (.gd files only - the app
# layer is UI and may use the engine, FLEET_PACK section 3). An occurrence is ignored when
# it is part of a longer identifier (the character before it is a letter, digit or underscore),
# so `PlayerInput.` does not trip the `Input.` rule while a bare `Input.` engine call still does.
const FORBIDDEN_STRINGS: Array[String] = [
	"Node", "get_tree", "Engine.", "Time.", "randf", "randi", "PhysicsServer", "Input.",
]

# Import (preload/load of a res:// path) allowed-prefixes per layer; app is unrestricted
# ("view and app may use everything", FLEET_PACK section 3).
const ALLOWED_IMPORTS := {
	"res://terrain": ["res://terrain/"],
	"res://sim": ["res://terrain/", "res://sim/", "res://core/"],
	"res://core": ["res://terrain/", "res://core/"],
}

const SCAN_DIRS: Array[String] = ["res://terrain", "res://sim", "res://core", "res://app"]
const SCAN_EXTENSIONS: Array[String] = [".gd", ".json"]
const IMPORT_RE := "((?:preload|load)\\([^)]*\"(res://[^\"]+)\"\\s*\\))"

static var _ids_cache: Array[String] = []
static var _ids_loaded := false


## The content ids, discovered from the content tree (never hand-maintained).
static func content_ids() -> Array[String]:
	if _ids_loaded:
		return _ids_cache
	_ids_loaded = true
	_ids_cache.clear()
	var dir := DirAccess.open("res://content/enemies")
	if dir != null:
		for sub in dir.get_directories():
			if not sub.begins_with("."):
				_ids_cache.append(sub)
	for kind in ["curses", "upgrades", "biomes"]:
		var d := DirAccess.open("res://content/" + kind)
		if d == null:
			continue
		for fn in d.get_files():
			if fn.ends_with(".json") and not fn.begins_with("."):
				_ids_cache.append(fn.trim_suffix(".json"))
	_ids_cache.sort()
	return _ids_cache


func run() -> Array[String]:
	var failures: Array[String] = []
	var ids := content_ids()
	if ids.is_empty():
		failures.append("no content ids discovered under res://content/ - the content scan is broken")
		return failures
	for dir_path in SCAN_DIRS:
		for file_path in _scan_files(dir_path):
			var text := _read(file_path)
			if text.is_empty():
				continue
			var file_name := file_path.substr("res://".length())
			var is_gd := file_path.ends_with(".gd")
			if is_gd and dir_path != "res://app":
				for s in FORBIDDEN_STRINGS:
					if _contains_standalone(text, s):
						failures.append("%s contains forbidden string %s" % [file_name, s])
			for id in ids:
				if _contains_word(text, id):
					failures.append("%s names content id %s" % [file_name, id])
			if is_gd:
				if ALLOWED_IMPORTS.has(dir_path):
					for m in _import_paths(text):
						var ok := false
						for prefix in ALLOWED_IMPORTS[dir_path]:
							if m.begins_with(prefix):
								ok = true
								break
						if not ok:
							failures.append("%s references %s outside its allowed imports" % [file_name, m])
	return failures


# True when `needle` occurs with no word character (letter, digit, underscore) before it.
func _contains_standalone(text: String, needle: String) -> bool:
	var from := 0
	while true:
		var at := text.find(needle, from)
		if at < 0:
			return false
		if at == 0:
			return true
		var prev := text.unicode_at(at - 1)
		if not _is_word_char(prev):
			return true
		from = at + 1
	return false


# True when `needle` occurs bounded by non-word characters (or the file edge) on both sides;
# case-sensitive, so uppercase mentions like "D-GIN" do not trip the lowercase id "gin".
func _contains_word(text: String, needle: String) -> bool:
	var from := 0
	while true:
		var at := text.find(needle, from)
		if at < 0:
			return false
		var lead_ok := at == 0 or not _is_word_char(text.unicode_at(at - 1))
		var end_at := at + needle.length()
		var trail_ok := end_at >= text.length() or not _is_word_char(text.unicode_at(end_at))
		if lead_ok and trail_ok:
			return true
		from = at + 1
	return false


static func _is_word_char(code: int) -> bool:
	return (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code == 95


func _import_paths(text: String) -> Array[String]:
	var out: Array[String] = []
	var re := RegEx.new()
	re.compile(IMPORT_RE)
	for m in re.search_all(text):
		out.append(m.get_string(2))
	return out


# Every scannable file under dir_path, recursively (.gd and .json), sorted.
func _scan_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		var lower := f.to_lower()
		for ext in SCAN_EXTENSIONS:
			if lower.ends_with(ext):
				out.append(dir_path + "/" + f)
				break
	for sub in dir.get_directories():
		if sub.begins_with("."):
			continue
		for p in _scan_files(dir_path + "/" + sub):
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
