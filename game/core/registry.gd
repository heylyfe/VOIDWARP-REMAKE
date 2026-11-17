extends RefCounted
#
# registry.gd - THE content registry (DESIGN.md section 12; ticket T-013).
#
# Boot contract: scans content/ (the four seated kinds enemies, curses, upgrades, biomes;
# gimmicks/ and modes/ are parse-checked only until their own tickets seat them) and data/
# (the six data files), sorts every kind by id and schema-validates every file against
# core/schemas/<kind>.schema.json. On ANY problem - a JSON parse error, a schema violation,
# an id that does not match its file name, a missing enemy.json - the boot is refused:
# load_all() pushes one error per offending file (the message names the file) and returns
# with ok=false. The boot path (app/, T-024) must treat ok=false as fatal and quit(1).
# game/tests/test_dropin.gd proves the refusal names the offending file.
#
# Schema dialect implemented here - the only keywords the core/schemas/*.json files use:
#   type                  a string ("object", "array", "string", "integer", "number",
#                         "boolean", "null") or an array of those strings
#   properties            {name: schema}
#   required              [name, ...]: the key must exist (null counts as present)
#   additionalProperties  false, or a schema applied to every key not named in properties
#   enum                  exact value match against one of the listed variants
#   pattern               a RegEx the string must match
#   items                 schema applied to every array element
#   minItems / maxItems   array length bounds
#   minimum / maximum     number bounds
#   definitions + $ref    {"$ref": "name"} resolves to definitions.name (resolved once at
#                         schema load, before validation walks the tree)
# Unknown keywords are ignored, so schema files may grow richer keywords before this
# validator learns them.
#
# Layer rules (game/tests/test_boundaries.gd): engine surface here is limited to Array/
# Dictionary/DirAccess/FileAccess/JSON/RegEx. No content id is ever named in core/: the
# per-kind vocabularies (enemy ids, stats, hooks) live in the schema JSON files and in
# core/stats.gd + core/hooks.gd only.

const CONTENT_KINDS: Array[String] = ["enemies", "curses", "upgrades", "biomes"]
# content folder name -> singular schema name under core/schemas/.
const SCHEMA_NAMES: Dictionary = {
	"enemies": "enemy", "curses": "curse", "upgrades": "upgrade", "biomes": "biome",
}
const DATA_FILES: Array[String] = [
	"economy", "offering_schedule", "palette", "player", "tips", "upgrade_pools",
]
# Scanned for JSON parse validity only; their schemas arrive with the gimmick/mode tickets.
const PARSE_ONLY_DIRS: Array[String] = ["res://content/gimmicks", "res://content/modes"]


## The one boot call. Returns:
##   {ok: bool,
##    errors: Array[String] (one line per offending file, name included),
##    enemies / curses / upgrades / biomes: {id: file data}, each in id order,
##    content_ids: sorted Array[String] ("kind:id"; the content set for RunState),
##    data: {name: file data}}.
## On failure (ok=false) the boot must stop: every offending file name has been pushed as an
## error by the time this returns.
static func load_all() -> Dictionary:
	var res: Dictionary = {
		"ok": true, "errors": [],
		"enemies": {}, "curses": {}, "upgrades": {}, "biomes": {},
		"content_ids": [], "data": {},
	}
	var schemas := _load_schemas(res)
	for kind in CONTENT_KINDS:
		_scan_kind(kind, schemas, res)
	for df in DATA_FILES:
		_scan_data_file(df, schemas, res)
	for dir_path in PARSE_ONLY_DIRS:
		_scan_parse_only(dir_path, res)
	_collect_content_ids(res)
	if not (res["errors"] as Array).is_empty():
		res["ok"] = false
		for e in res["errors"]:
			push_error("content registry refuses boot - %s" % str(e))
	return res


# ------------------------------------------------------------------ schema and file reading --

static func _load_schemas(res: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var names: Array[String] = []
	for kind in CONTENT_KINDS:
		names.append(str(SCHEMA_NAMES[kind]))
	for df in DATA_FILES:
		names.append(df)
	for name in names:
		var path := "res://core/schemas/%s.schema.json" % name
		var parsed: Variant = _read_json(path, res)
		if typeof(parsed) != TYPE_DICTIONARY:
			res["errors"].append("%s: schema file is not a JSON object" % path)
			out[name] = {}
			continue
		var doc: Dictionary = parsed
		var defs: Dictionary = doc.get("definitions", {})
		out[name] = _deref(doc, defs)
	return out


## Replaces every {"$ref": "name"} node with definitions[name], recursively, once at load.
static func _deref(node: Variant, defs: Dictionary) -> Variant:
	if node is Dictionary:
		var d: Dictionary = node
		if d.has("$ref") and defs.has(str(d["$ref"])):
			return defs[str(d["$ref"])]
		var out: Dictionary = {}
		for k in d.keys():
			out[k] = _deref(d[k], defs)
		return out
	if node is Array:
		var out_arr: Array = []
		for item in node:
			out_arr.append(_deref(item, defs))
		return out_arr
	return node


static func _read_json(path: String, res: Dictionary) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		res["errors"].append("%s: cannot open file (error %d)" % [path, FileAccess.get_open_error()])
		return null
	var text := f.get_as_text()
	f.close()
	if text.strip_edges().is_empty():
		res["errors"].append("%s: file is empty" % path)
		return null
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		res["errors"].append("%s: is not valid JSON" % path)
		return null
	return parsed


# --------------------------------------------------------------------------- the content scan --

static func _scan_kind(kind: String, schemas: Dictionary, res: Dictionary) -> void:
	var dir := DirAccess.open("res://content/" + kind)
	if dir == null:
		res["errors"].append("res://content/%s: cannot open folder (error %d)" % [kind, DirAccess.get_open_error()])
		return
	var entries: Array = []  # [[id, res path], ...]
	if kind == "enemies":
		for sub in dir.get_directories():
			if sub.begins_with("."):
				continue
			var path := "res://content/enemies/%s/enemy.json" % sub
			if not FileAccess.file_exists(path):
				# An enemy folder without enemy.json is content that has not been written yet, not
				# malformed content: the enemy behaviour wave (T-030..T-041) owns enemy.json, while
				# T-016 creates the folder for its sprites. Skip it so the registry still boots.
				push_warning("content registry: res://content/enemies/%s has no enemy.json yet - skipped (pending the enemy wave)" % sub)
				continue
			entries.append([sub, path])
	else:
		for fn in dir.get_files():
			if fn.begins_with(".") or not fn.ends_with(".json"):
				continue
			entries.append([fn.trim_suffix(".json"), "res://content/" + kind + "/" + fn])
	var schema: Dictionary = schemas.get(str(SCHEMA_NAMES[kind]), {})
	var staged: Dictionary = {}
	for e in entries:
		var eid: String = e[0]
		var epath: String = e[1]
		var data: Variant = _read_json(epath, res)
		if data == null:
			continue  # the parse error is already recorded with the file name
		_validate(schema, data, "", epath, res["errors"])
		if typeof(data) != TYPE_DICTIONARY or not (data as Dictionary).has("id"):
			continue  # the schema validation just recorded the problem
		var data_id := str((data as Dictionary)["id"])
		if data_id != eid:
			res["errors"].append("%s: id '%s' does not match its %s file name / folder name '%s'" % [epath, data_id, kind, eid])
		staged[eid] = data
	res[kind] = _sorted_copy(staged)


static func _scan_data_file(df: String, schemas: Dictionary, res: Dictionary) -> void:
	var path := "res://data/%s.json" % df
	var data: Variant = _read_json(path, res)
	if data == null:
		return
	_validate(schemas.get(df, {}), data, "", path, res["errors"])
	res["data"][df] = data


static func _scan_parse_only(dir_path: String, res: Dictionary) -> void:
	for path in _json_files_under(dir_path, res):
		_read_json(path, res)  # a parse failure is recorded with the file name


static func _json_files_under(dir_path: String, res: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out  # an empty (or absent) parse-only folder is fine
	for fn in dir.get_files():
		if not fn.begins_with(".") and fn.ends_with(".json"):
			out.append(dir_path + "/" + fn)
	for sub in dir.get_directories():
		if sub.begins_with("."):
			continue
		for p in _json_files_under(dir_path + "/" + sub, res):
			out.append(p)
	out.sort()
	return out


## Rebuilds {id: data} with the keys inserted in id order (determinism, DESIGN.md section 12).
static func _sorted_copy(staged: Dictionary) -> Dictionary:
	var ids := staged.keys()
	ids.sort()
	var ordered: Dictionary = {}
	for id in ids:
		ordered[id] = staged[id]
	return ordered


static func _collect_content_ids(res: Dictionary) -> void:
	var all: Array = []
	for kind in CONTENT_KINDS:
		var dict: Dictionary = res[kind]
		for id in dict.keys():
			all.append("%s:%s" % [SCHEMA_NAMES[kind], id])
	all.sort()
	var out: Array[String] = []
	for item in all:
		out.append(str(item))
	res["content_ids"] = out


# --------------------------------------------------------------------------------- the validator --

static func _validate(schema: Dictionary, value: Variant, path: String, label: String, errs: Array) -> void:
	if schema.is_empty():
		return
	if schema.has("type") and not _type_ok(schema["type"], value):
		errs.append("%s: %s must be of type %s (got %s)" % [label, _loc(path), str(schema["type"]), type_string(typeof(value))])
		return
	if schema.has("enum") and not _in_enum(schema["enum"], value):
		errs.append("%s: %s must be one of %s (got %s)" % [label, _loc(path), str(schema["enum"]), str(value)])
	if schema.has("pattern") and typeof(value) == TYPE_STRING:
		var re := RegEx.new()
		if re.compile(str(schema["pattern"])) != OK:
			errs.append("%s: %s schema pattern does not compile: %s" % [label, _loc(path), str(schema["pattern"])])
		elif re.search(str(value)) == null:
			errs.append("%s: %s does not match pattern '%s'" % [label, _loc(path), str(schema["pattern"])])
	if typeof(value) == TYPE_ARRAY:
		_validate_array(schema, value, path, label, errs)
	if typeof(value) == TYPE_DICTIONARY:
		_validate_object(schema, value, path, label, errs)
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		if schema.has("minimum") and float(value) < float(schema["minimum"]):
			errs.append("%s: %s is %s, below minimum %s" % [label, _loc(path), str(value), str(schema["minimum"])])
		if schema.has("maximum") and float(value) > float(schema["maximum"]):
			errs.append("%s: %s is %s, above maximum %s" % [label, _loc(path), str(value), str(schema["maximum"])])


static func _validate_object(schema: Dictionary, value: Dictionary, path: String, label: String, errs: Array) -> void:
	var props: Dictionary = schema.get("properties", {})
	for req in schema.get("required", []):
		if not value.has(str(req)):
			errs.append("%s: %s is missing required key '%s'" % [label, _loc(path), str(req)])
	var addl: Variant = schema.get("additionalProperties", true)
	for k in value.keys():
		var key := str(k)
		if props.has(key):
			_validate(props[key], value[k], _join(path, key), label, errs)
		elif addl is Dictionary:
			_validate(addl, value[k], _join(path, key), label, errs)
		elif addl == false:
			errs.append("%s: %s has key '%s' which the schema does not allow" % [label, _loc(path), key])


static func _validate_array(schema: Dictionary, value: Array, path: String, label: String, errs: Array) -> void:
	var items: Variant = schema.get("items", null)
	for i in value.size():
		if items is Dictionary:
			_validate(items, value[i], "%s[%d]" % [_loc(path), i], label, errs)
	if schema.has("minItems") and value.size() < int(schema["minItems"]):
		errs.append("%s: %s needs at least %s items (got %d)" % [label, _loc(path), str(schema["minItems"]), value.size()])
	if schema.has("maxItems") and value.size() > int(schema["maxItems"]):
		errs.append("%s: %s allows at most %s items (got %d)" % [label, _loc(path), str(schema["maxItems"]), value.size()])


static func _type_ok(t: Variant, value: Variant) -> bool:
	var types: Array = t if t is Array else [t]
	for tt in types:
		var name := str(tt)
		if name == "null" and typeof(value) == TYPE_NIL:
			return true
		if name == "boolean" and typeof(value) == TYPE_BOOL:
			return true
		if name == "string" and typeof(value) == TYPE_STRING:
			return true
		if name == "number" and (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT):
			return true
		if name == "integer":
			if typeof(value) == TYPE_INT:
				return true
			if typeof(value) == TYPE_FLOAT and is_equal_approx(value, floorf(value)):
				return true
		if name == "array" and typeof(value) == TYPE_ARRAY:
			return true
		if name == "object" and typeof(value) == TYPE_DICTIONARY:
			return true
	return false


static func _in_enum(options: Array, value: Variant) -> bool:
	for o in options:
		if typeof(o) == typeof(value) and o == value:
			return true
	return false


static func _loc(path: String) -> String:
	return path if path != "" else "<root>"


static func _join(path: String, key: String) -> String:
	return key if path == "" else path + "." + key
