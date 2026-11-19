extends RefCounted
#
# Curse content integrity test. One pass over game/content/curses/, asserting:
#   1. "script": true JSON <-> .gd module pairing, both directions (orphans reported);
#   2. every JSON "id" equals its filename stem;
#   3. every JSON declares the fields the game reads: id, name, severity, min_level,
#      max_stacks, rule, counter_play, modifiers;
#   4. every modifiers[] entry is well-formed for the modifier pass (core/content_api.gd
#      apply_modifiers / mods_for_stacks): a stat in the closed list, op add|mul|set, a
#      numeric value, a "when" some shipped context matches - verified by actually applying
#      each modifier and requiring its stat in the output, so a modifier the pass would
#      silently drop fails here;
#   5. every script module declares const CURSE_ID, equal to its JSON id;
#   6. every script module held_stacks(state) returns 0 for an empty state and the held
#      (clamped) stack count for a held one - called for real on synthetic states, never
#      read from the source;
#   7. max_stacks in the JSON matches the module own clamp where the module has one
#      (const MAX_STACKS, and functionally via held_stacks(huge)).
#
# FAILS LOUDLY: a future curse added with a broken shape reports a failure naming its
# file. This test fixes nothing; it only reports.

const ContentApiScript := preload("res://core/content_api.gd")
const StatsScript := preload("res://core/stats.gd")

const CURSES_DIR := "res://content/curses"
const REQUIRED_FIELDS: Array[String] = ["id", "name", "severity", "min_level", "max_stacks", "rule", "counter_play", "modifiers"]
const ALLOWED_OPS: Array[String] = ["add", "mul", "set"]
# "when" values the shipped contexts can match (core/content_api.gd _when_matches; the
# class list mirrors data/player.json and core/schemas/curse.schema.json).
const ALLOWED_WHENS: Array[String] = ["always", "", "black_phase", "gold_phase", "class:dasher", "class:glider", "class:athletic"]
const HUGE := 1000000


func run() -> Array[String]:
	var failures: Array[String] = []
	var scan := _scan(failures)
	var docs: Array = scan["docs"]
	_check_pairing(failures, scan)
	for d in docs:
		_check_id(failures, d)
		_check_required(failures, d)
		_check_modifiers(failures, d)
	_check_modules(failures, docs)
	return failures


## Scan the folder once: parse every .json, collect every .gd stem. A json that does not
## parse is reported and skipped (the registry refuses the boot on it too).
func _scan(failures: Array[String]) -> Dictionary:
	var docs: Array = []
	var gd_stems: Array[String] = []
	var dir := DirAccess.open(CURSES_DIR)
	if dir == null:
		failures.append("cannot open %s (error %d)" % [CURSES_DIR, DirAccess.get_open_error()])
		return {"docs": docs, "gd": gd_stems}
	for fn in dir.get_files():
		if fn.begins_with("."):
			continue
		if fn.ends_with(".json"):
			var path := "%s/%s" % [CURSES_DIR, fn]
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed == null or not (parsed is Dictionary):
				failures.append("%s: not valid JSON / not an object" % path)
				continue
			docs.append({"stem": fn.trim_suffix(".json"), "path": path, "data": parsed})
		elif fn.ends_with(".gd"):
			gd_stems.append(fn.trim_suffix(".gd"))
	docs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["stem"]) < str(b["stem"]))
	gd_stems.sort()
	return {"docs": docs, "gd": gd_stems}


## Assertion 1: a "script": true JSON and a same-stem .gd appear exactly together.
## The one exemption is a curse the content itself marks "retired": true - it is out of
## the offer pool, so its module was never merged and the flag is the content's own
## machine-readable statement of that. Any other orphan still fails loudly.
func _check_pairing(failures: Array[String], scan: Dictionary) -> void:
	var script_stems: Array[String] = []
	for d in scan["docs"]:
		var data: Dictionary = d["data"]
		if bool(data.get("script", false)) and not bool(data.get("retired", false)):
			script_stems.append(str(d["stem"]))
	var gd_stems: Array = scan["gd"]
	for s in script_stems:
		if not gd_stems.has(s):
			failures.append("%s.json has \"script\": true but %s.gd is missing - a scripted curse with no module" % [s, s])
	for s in gd_stems:
		if not script_stems.has(s):
			failures.append("%s.gd has no JSON with \"script\": true - an orphan module (its JSON is missing, declarative, retired, or lost its \"script\" flag)" % s)

## Assertion 2: the JSON id is the filename stem.
func _check_id(failures: Array[String], d: Dictionary) -> void:
	var data: Dictionary = d["data"]
	var stem := str(d["stem"])
	if not data.has("id"):
		return  # already reported by the required-fields check
	if str(data["id"]) != stem:
		failures.append("%s: id \"%s\" does not match its filename stem \"%s\"" % [d["path"], str(data["id"]), stem])


## Assertion 3: the fields the game reads are all declared.
func _check_required(failures: Array[String], d: Dictionary) -> void:
	var data: Dictionary = d["data"]
	for field in REQUIRED_FIELDS:
		if not data.has(field):
			failures.append("%s: missing required field \"%s\"" % [d["path"], field])
	if data.has("max_stacks") and int(data["max_stacks"]) < 1:
		failures.append("%s: max_stacks is %d, expected >= 1" % [d["path"], int(data["max_stacks"])])


## Assertion 4: modifiers are well-formed for the modifier pass, proven by applying each
## modifier and requiring its stat in the output. A modifier the pass would silently drop
## (unknown stat, unknown op, non-numeric value, unmatchable when) fails here.
func _check_modifiers(failures: Array[String], d: Dictionary) -> void:
	var data: Dictionary = d["data"]
	var id := str(d["stem"])
	if not data.has("modifiers"):
		return  # already reported by the required-fields check
	var mods: Variant = data["modifiers"]
	if not (mods is Array):
		failures.append("%s: modifiers is not an array" % d["path"])
		return
	for i in mods.size():
		_check_modifier(failures, d["path"], id, mods[i], i)
	# mods_for_stacks shape: the array must survive the per-stack repeat intact.
	var applied: Array = ContentApiScript.mods_for_stacks(mods, 2)
	if applied.size() != mods.size() * 2:
		failures.append("%s: mods_for_stacks(modifiers, 2) gave %d modifiers, expected %d" % [d["path"], applied.size(), mods.size() * 2])


func _check_modifier(failures: Array[String], path: String, id: String, m: Variant, i: int) -> void:
	var label := "%s: modifiers[%d]" % [id, i]
	var ok := true
	if not (m is Dictionary):
		failures.append("%s is not an object: %s" % [label, str(m)])
		return
	var mod: Dictionary = m
	# stat: must be in the closed list, else apply_modifiers skips it silently.
	var stat_v: Variant = mod.get("stat", null)
	var stat := ""
	if stat_v == null:
		failures.append("%s has no stat" % label)
		ok = false
	elif typeof(stat_v) != TYPE_STRING:
		failures.append("%s stat is not a string: %s" % [label, str(stat_v)])
		ok = false
	else:
		stat = str(stat_v)
		if not StatsScript.is_known(stat):
			failures.append("%s names stat \"%s\", which is not in the closed list (core/stats.gd) - apply_modifiers would silently drop it" % [label, stat])
			ok = false
	# op: anything else falls through the match with no branch - silently dropped.
	var op_v: Variant = mod.get("op", null)
	if op_v == null or not (op_v is String) or not ALLOWED_OPS.has(str(op_v)):
		failures.append("%s op is %s, expected one of %s" % [label, str(op_v), str(ALLOWED_OPS)])
		ok = false
	# value: the pass does float(value); missing or non-numeric is a silent no-op.
	if not mod.has("value"):
		failures.append("%s has no value" % label)
		ok = false
	elif typeof(mod["value"]) != TYPE_INT and typeof(mod["value"]) != TYPE_FLOAT:
		failures.append("%s value is %s, expected a number" % [label, type_string(typeof(mod["value"]))])
		ok = false
	# when: absent is "always"; present must match a shipped context or the pass skips it
	# everywhere (a modifier that never applies).
	var when := "always"
	if mod.has("when"):
		if typeof(mod["when"]) != TYPE_STRING:
			failures.append("%s when is not a string: %s" % [label, str(mod["when"])])
			ok = false
		else:
			when = str(mod["when"])
			if not ALLOWED_WHENS.has(when):
				failures.append("%s when is \"%s\" - no shipped context matches it; allowed: %s" % [label, when, str(ALLOWED_WHENS)])
				ok = false
	# Decisive check: apply this modifier alone in a context that satisfies its "when" and
	# require its stat in the output.
	if ok:
		var out: Dictionary = ContentApiScript.apply_modifiers({}, [mod], _ctx_for(when))
		if not out.has(stat):
			failures.append("%s: apply_modifiers produces no \"%s\" for this modifier (when \"%s\") - the modifier pass silently drops it" % [label, stat, when])


func _ctx_for(when: String) -> Dictionary:
	if when == "black_phase" or when == "gold_phase":
		return {"phase": when}
	if when.begins_with("class:"):
		return {"class": when.substr(6)}
	return {}

## Assertions 5-7: the script modules. CURSE_ID == JSON id; held_stacks(state) called for
## real on synthetic states (empty -> 0, held -> the held/clamped stack count); the module
## clamp, where one exists, matches the JSON max_stacks.
func _check_modules(failures: Array[String], docs: Array) -> void:
	for d in docs:
		var data: Dictionary = d["data"]
		if not bool(data.get("script", false)):
			continue
		var stem := str(d["stem"])
		var path := "%s/%s.gd" % [CURSES_DIR, stem]
		if not FileAccess.file_exists(path):
			continue  # already reported by the pairing check
		var k: Variant = load(path)
		if k == null:
			failures.append("%s: module failed to load" % path)
			continue
		var consts: Dictionary = {}
		if k.has_method("get_script_constant_map"):
			consts = k.get_script_constant_map()
		_check_curse_id(failures, stem, data, consts)
		var max_stacks := int(data.get("max_stacks", 1))
		if consts.has("MAX_STACKS") and int(consts["MAX_STACKS"]) != max_stacks:
			failures.append("%s: module MAX_STACKS is %d, the JSON max_stacks is %d" % [stem, int(consts["MAX_STACKS"]), max_stacks])
		_check_held_stacks(failures, k, stem, data, max_stacks)


func _check_curse_id(failures: Array[String], stem: String, data: Dictionary, consts: Dictionary) -> void:
	var cid: Variant = consts.get("CURSE_ID", null)
	if cid == null:
		failures.append("%s.gd: script module does not declare const CURSE_ID" % stem)
		return
	if str(cid) != str(data.get("id", "")):
		failures.append("%s.gd: CURSE_ID \"%s\" does not equal the JSON id \"%s\"" % [stem, str(cid), str(data.get("id", ""))])


func _check_held_stacks(failures: Array[String], k: Variant, stem: String, data: Dictionary, max_stacks: int) -> void:
	var id := str(data.get("id", stem))
	var has_it := false
	for m in k.get_script_method_list():
		if str((m as Dictionary).get("name", "")) == "held_stacks":
			has_it = true
			break
	if not has_it:
		failures.append("%s.gd: script module does not declare held_stacks(state) - the stack contract cannot be verified" % stem)
		return
	# Empty states: no curse held anywhere -> 0.
	_expect_stacks(failures, k, stem, "held_stacks({})", k.call("held_stacks", {}), 0)
	_expect_stacks(failures, k, stem, "held_stacks({\"curses_held\": {}})", k.call("held_stacks", {"curses_held": {}}), 0)
	# A held one: below the cap -> the held count; at the cap -> the cap.
	_expect_stacks(failures, k, stem, "held_stacks({\"curses_held\": {\"%s\": 1}})" % id,
			k.call("held_stacks", {"curses_held": {id: 1}}), 1)
	_expect_stacks(failures, k, stem, "held_stacks({\"curses_held\": {\"%s\": max_stacks}})" % id,
			k.call("held_stacks", {"curses_held": {id: max_stacks}}), max_stacks)
	# Huge hold: a module with a clamp must clamp to the JSON max_stacks; a module that
	# does not clamp is allowed (the sim caps stacks at pick time).
	var held: Variant = k.call("held_stacks", {"curses_held": {id: HUGE}})
	if typeof(held) != TYPE_INT and typeof(held) != TYPE_FLOAT:
		failures.append("%s.gd: held_stacks(huge hold) returned %s, expected an int" % [stem, str(held)])
	elif int(held) != HUGE and int(held) != max_stacks:
		failures.append("%s.gd: held_stacks clamps a huge hold to %d, the JSON max_stacks is %d" % [stem, int(held), max_stacks])


func _expect_stacks(failures: Array[String], k: Variant, stem: String, label: String, got: Variant, want: int) -> void:
	if typeof(got) != TYPE_INT and typeof(got) != TYPE_FLOAT:
		failures.append("%s.gd: %s returned %s, expected int %d" % [stem, label, str(got), want])
		return
	if int(got) != want:
		failures.append("%s.gd: %s returned %d, expected %d" % [stem, label, int(got), want])
