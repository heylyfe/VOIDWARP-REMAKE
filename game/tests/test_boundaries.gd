extends RefCounted
#
# Boundary scan (FLEET_PACK.md section 3, ticket T-001). A text scan, run headless by
# res://tests/run_all.gd. The dependency rule:
#   terrain imports nothing; sim may use terrain and core; core may use terrain;
#   view and app may use everything.
#   Nothing under terrain/ sim/ core/ may contain the strings listed in FORBIDDEN_STRINGS,
#   or any content id.
# "contains" is matched on whole .gd files, comments included: the point is that no engine
# API or content name leaks into the pure layers, whatever the line type.


# Forbidden anywhere under game/terrain/, game/sim/, game/core/.
# An occurrence is ignored when it is part of a longer identifier (the character before it is
# a letter, digit or underscore), so `PlayerInput.` does not trip the `Input.` rule while
# a bare `Input.` engine call still does.
const FORBIDDEN_STRINGS: Array[String] = [
	"Node", "get_tree", "Engine.", "Time.", "randf", "randi", "PhysicsServer", "Input.",
]

# Import (preload/load of a res:// path) allowed-prefixes per layer.
const ALLOWED_IMPORTS := {
	"res://terrain": ["res://terrain/"],
	"res://sim": ["res://terrain/", "res://sim/", "res://core/"],
	"res://core": ["res://terrain/", "res://core/"],
}

# Content ids that scenery code may never name. Empty today; every ticket that adds content
# appends its ids here (registry ids only, e.g. "kiwi_cat"), and the scan grows with them.
const KNOWN_CONTENT_IDS: Array[String] = []

const SCAN_DIRS: Array[String] = ["res://terrain", "res://sim", "res://core"]
const IMPORT_RE := "((?:preload|load)\\([^)]*\"(res://[^\"]+)\"\\s*\\))"


func run() -> Array[String]:
	var failures: Array[String] = []
	for dir_path in SCAN_DIRS:
		var files := _gd_files(dir_path)
		for file_path in files:
			var text := _read(file_path)
			if text.is_empty():
				continue
			var file_name := file_path.substr("res://".length())
			for s in FORBIDDEN_STRINGS:
				if _contains_standalone(text, s):
					failures.append("%s contains forbidden string %s" % [file_name, s])
			for id in KNOWN_CONTENT_IDS:
				if id != "" and text.contains(id):
					failures.append("%s names content id %s" % [file_name, id])
			for m in _import_paths(text):
				var ok := false
				for prefix in ALLOWED_IMPORTS[dir_path]:
					if m.begins_with(prefix):
						ok = true
						break
				if not ok:
					failures.append("%s references %s outside its allowed imports" % [file_name, m])
	return failures


# True when `needle` occurs and is not preceded by a letter, digit or underscore.
func _contains_standalone(text: String, needle: String) -> bool:
	var from := 0
	while true:
		var at := text.find(needle, from)
		if at < 0:
			return false
		if at == 0:
			return true
		var prev := text.unicode_at(at - 1)
		var alnum := (prev >= 48 and prev <= 57) or (prev >= 65 and prev <= 90) or (prev >= 95 and prev <= 122) or prev == 95
		if not alnum:
			return true
		from = at + 1
	return false


func _import_paths(text: String) -> Array[String]:
	var out: Array[String] = []
	var re := RegEx.new()
	re.compile(IMPORT_RE)
	for m in re.search_all(text):
		out.append(m.get_string(2))
	return out


func _gd_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path + "/" + f)
	out.sort()
	return out


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text