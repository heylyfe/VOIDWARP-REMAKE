extends RefCounted
#
# roster.gd - the ONE content-derived roster read (ticket FIX-A14; D-FIX-A14-2).
#
# Everything outside this file that needs roster data (run-over display names, diegetic
# spawn lines, the biome act order) reads it here. Nothing here names a content id: the
# values live in the content tree and are discovered by scanning it once per process:
#   res://content/enemies/<id>/enemy.json   id, name, optional death_name, optional
#                                           spawn_line, stats.death_code (T-021/D-T030-1)
#   res://content/biomes/<id>.json          id, levels[] (act window; DESIGN.md section 10)
# Engine surface: Array/Dictionary/DirAccess/FileAccess/JSON only (core layer).
# Cache is process-wide; content cannot change under a running game.

static var _loaded := false
static var _codes: Dictionary = {}        # death code -> display name
static var _id_names: Dictionary = {}     # enemy id   -> display name
static var _spawn_lines: Dictionary = {}  # enemy id   -> the diegetic danger line
static var _biome_order: Array[String] = []  # biome ids, act order (by levels[0])


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	_codes.clear()
	_id_names.clear()
	_spawn_lines.clear()
	_biome_order.clear()
	var dir := DirAccess.open("res://content/enemies")
	if dir != null:
		for sub in dir.get_directories():
			if sub.begins_with("."):
				continue
			var parsed: Variant = _read_json("res://content/enemies/%s/enemy.json" % sub)
			if parsed == null:
				continue
			_note_enemy(sub, parsed)
	var bdir := DirAccess.open("res://content/biomes")
	if bdir != null:
		var keyed: Array = []  # [[levels0, id], ...]
		for fn in bdir.get_files():
			if not fn.ends_with(".json") or fn.begins_with("."):
				continue
			var parsed2: Variant = _read_json("res://content/biomes/%s" % fn)
			if parsed2 == null:
				continue
			var levels: Variant = parsed2.get("levels", [])
			var first := int(levels[0]) if levels is Array and not (levels as Array).is_empty() else 999999
			keyed.append([first, str(parsed2.get("id", fn.trim_suffix(".json")))])
		keyed.sort_custom(func(a, b): return int(a[0]) < int(b[0]))
		for row in keyed:
			_biome_order.append(str(row[1]))


static func _note_enemy(fallback_id: String, data: Dictionary) -> void:
	var id := str(data.get("id", fallback_id))
	var name := str(data.get("name", id))
	var dname := str(data.get("death_name", ""))
	if dname == "":
		dname = name
	_id_names[id] = dname
	var stats: Variant = data.get("stats", {})
	if stats is Dictionary and (stats as Dictionary).has("death_code"):
		var code := str((stats as Dictionary)["death_code"])
		if code != "":
			_codes[code] = dname
	var line := str(data.get("spawn_line", ""))
	if line != "":
		_spawn_lines[id] = line


static func _read_json(path: String) -> Variant:
	var text := FileAccess.get_file_as_string(path)
	if text.strip_edges().is_empty():
		return null
	return JSON.parse_string(text)


## death code -> display name ("D-MINE" -> the tripmine carrier's death_name); {} on empty scan.
static func death_names() -> Dictionary:
	_ensure()
	return _codes.duplicate()


## enemy id -> display name (death_name, defaulting to name).
static func id_names() -> Dictionary:
	_ensure()
	return _id_names.duplicate()


## enemy id -> the diegetic danger line; an id without a spawn_line is absent.
static func spawn_lines() -> Dictionary:
	_ensure()
	return _spawn_lines.duplicate()


## biome ids in act order (DESIGN.md section 10; sorted by each biome's first level).
static func biome_order() -> Array[String]:
	_ensure()
	var out: Array[String] = []
	for b in _biome_order:
		out.append(b)
	return out


## Display name for one death code; "" when the code is not in content.
static func name_for_code(code: String) -> String:
	_ensure()
	return str(_codes.get(code, ""))


## Display name for one enemy id; "" when the id is not in content.
static func name_for_id(id: String) -> String:
	_ensure()
	return str(_id_names.get(id, ""))
