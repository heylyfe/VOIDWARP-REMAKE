extends RefCounted
#
# Content schema test (FLEET_PACK section 4 gate step 5; ticket T-013).
#
# Validates the REAL content on disk through the registry (core/registry.gd + the JSON
# schemas in core/schemas/), then asserts the counts the launch content promises (46 curses,
# 36 upgrades, 5 biomes; eleven enemy entries so far - the tripmine (T-021), the kiwi cat
# (T-030), coil (T-031), thicc ben (T-032), YOU?! (T-035), seal (T-038), isagi (T-033),
# nuke (T-034), address_me (T-039), toucher (T-037) and gin (T-041)), the id-sorted
# determinism, the data-file presence, the CANON pool relationships of DESIGN.md section 8,
# and the sync between the schema enums and the closed code lists in core/stats.gd + core/hooks.gd.

const RegistryScript := preload("res://core/registry.gd")
const ContentApiScript := preload("res://core/content_api.gd")
const StatsScript := preload("res://core/stats.gd")
const HooksScript := preload("res://core/hooks.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	var res := RegistryScript.load_all()
	if not _check(failures, bool(res.get("ok", false)), "registry refuses boot on the real content: %s" % _first_errors(res)):
		return failures

	# Counts (T-014 tickets) and determinism (DESIGN.md section 12: sorted by id).
	# (T-021: +1 enemy - the tripmine; T-030: +1 - kiwi cat; T-031: +1 - coil;
	# T-032: +1 - thicc ben; T-035: +1 - YOU?!; T-038: +1 - seal; T-033: +1 - isagi;
	# T-034: +1 - nuke; T-039: +1 - address_me; T-037: +1 - toucher; T-041: +1 - gin.)
	var counts := {"curses": 46, "upgrades": 36, "biomes": 5, "enemies": 11}
	var dictionaries := {"curses": res["curses"], "upgrades": res["upgrades"], "biomes": res["biomes"], "enemies": res["enemies"]}
	for key in counts:
		var dict: Dictionary = dictionaries[key]
		_check(failures, dict.size() == counts[key], "%s count is %d, expected %d" % [key, dict.size(), counts[key]])
		_ascending(failures, str(key), dict.keys())
	_check(failures, (res["data"] as Dictionary).size() == 6, "data files loaded: %d, expected 6" % (res["data"] as Dictionary).size())
	var cids: Array[String] = []
	for item in res["content_ids"]: cids.append(str(item))
	_check(failures, cids.size() == 98, "content_ids has %d entries, expected 98" % cids.size())
	_ascending(failures, "content_ids", cids)
	_pools_and_api(failures)
	_api_semantics(failures)
	_schema_list_sync(failures)
	return failures


# CANON pool relationships (DESIGN.md section 8): level 1 = exactly paycheck/more/
# yearn_for_speed; every later bracket = all upgrades whose tier has entered the pool
# (T1@1, T2@4, T3@10, T4@18, T5@26); 26+ open-ended and == all 36.
# Also the api-level reads: eligible curses with and without votes, the bounty formula,
# and the modifier arithmetic of DESIGN.md section 12.
func _pools_and_api(failures: Array[String]) -> void:
	var api: RefCounted = ContentApiScript.load()
	if not _check(failures, api.call("is_ok"), "content api boot failed: %s" % " / ".join(api.call("boot_errors"))):
		return
	var tiers: Dictionary = api.TIER_FROM
	var upgrades: Dictionary = api._reg["upgrades"]
	var expected_by_min: Dictionary = {}
	var all_count := 0
	for id in upgrades.keys():
		all_count += 1
		var u: Dictionary = upgrades[id]
		var from := int(tiers[str(u.get("tier", ""))])
		for min_level in [2, 4, 10, 18, 26]:
			if from <= min_level:
				if not expected_by_min.has(min_level):
					expected_by_min[min_level] = []
				(expected_by_min[min_level] as Array).append(str(id))
	var pool_data: Dictionary = api.call("data", "upgrade_pools")
	var brackets: Array = pool_data.get("brackets", [])
	_check(failures, brackets.size() == 6, "pool bracket count %d, expected 6" % brackets.size())
	var mins: Array = [2, 4, 10, 18, 26]
	var index := 0
	for b in brackets:
		var bracket: Dictionary = b
		var lo := int(bracket.get("min_level", 0))
		var ids: Array[String] = []
		for raw in bracket.get("ids", []): ids.append(str(raw))
		if lo == 1:
			_check(failures, ids == ["paycheck", "more", "yearn_for_speed"] or str(ids) == str(["paycheck", "more", "yearn_for_speed"]),
				"level-1 bracket is %s, expected exactly the CANON three" % str(ids))
		else:
			var expected: Array = expected_by_min.get(mins[index - 1], [])
			expected.sort()
			var mine := ids.duplicate()
			mine.sort()
			_check(failures, str(mine) == str(expected), "bracket %s ids (%d) != tier-entered set (%d)" % [bracket.get("bracket", "?"), mine.size(), expected.size()])
		index += 1
	var shop: Array[String] = api.call("shop_pool", 26)
	_check(failures, shop.size() == all_count, "shop pool at 26 has %d ids, catalog has %d" % [shop.size(), all_count])
	_check(failures, (api.call("shop_pool", 1) as Array).size() == 3, "shop pool at level 1 is not 3 ids")
	_check(failures, (api.call("shop_pool", 0) as Array).is_empty(), "shop pool at level 0 should be empty")


# API reads (DESIGN.md section 7/12 gated shapes) + schema/code list sync.
func _api_semantics(failures: Array[String]) -> void:
	var api: RefCounted = ContentApiScript.load()
	if not api.call("is_ok"):
		return  # already reported by _pools_and_api
	# Eligibility: min_level gating + the >= 1 vote gate on enemy-linked curses.
	var l1: Array = api.call("eligible_curses", 1, {})
	_check(failures, str(l1) == str(["hungry_void", "thick_fog", "unmarked"]), "eligible curses at level 1 = %s, expected the three min_level-1 general curses" % str(l1))
	var votes: Dictionary = {"kiwi_cat": 1}
	var l3: Array = api.call("eligible_curses", 3, votes)
	_check(failures, (l3 as Array).has("zoomies"), "zoomies (kiwi_cat, min 3) not offered with 1 kiwi_cat vote at level 3")
	var l3_no_votes: Array = api.call("eligible_curses", 3, {})
	_check(failures, not (l3_no_votes as Array).has("zoomies"), "zoomies offered with zero kiwi_cat votes")
	# Bounty: floor(base x (20 + level) / 20), data/economy.json bounties 20/45/90.
	_check(failures, int(api.call("curse_bounty", "hungry_void", 1)) == 47, "harsh bounty at level 1 is %s, expected floor(45 x 21 / 20) = 47" % str(api.call("curse_bounty", "hungry_void", 1)))
	_check(failures, int(api.call("curse_bounty", "unmarked", 0)) == 20, "mild bounty at level 0 is %s, expected 20" % str(api.call("curse_bounty", "unmarked", 0)))
	# Modifier math: (base + add) x mul, set wins, `when` filters.
	var mods: Array = [
		{"stat": "fog_density", "op": "add", "value": 0.006},
		{"stat": "fog_density", "op": "mul", "value": 2.0},
		{"stat": "chain_window", "op": "set", "value": 3.0},
		{"stat": "run_speed", "op": "add", "value": -1.0, "when": "gold_phase"},
	]
	var gold_ctx: Dictionary = {"phase": "gold_phase"}
	var out: Dictionary = api.call("apply_modifiers", {}, mods, gold_ctx)
	_check(failures, is_equal_approx(float(out["fog_density"]), 0.036), "fog_density add-then-mul gave %s" % str(out["fog_density"]))
	_check(failures, is_equal_approx(float(out["chain_window"]), 3.0), "set must win: chain_window %s, expected 3.0" % str(out["chain_window"]))
	_check(failures, is_equal_approx(float(out["run_speed"]), 0.0), "gold_phase run_speed add gave %s, expected -1.0" % str(out["run_speed"]))
	var black_ctx: Dictionary = {"phase": "black_phase"}
	var out_black: Dictionary = api.call("apply_modifiers", {}, mods, black_ctx)
	_check(failures, not out_black.has("run_speed"), "gold-only modifier applied in the black phase")
	# Every stat the shipped data names is in the closed list (schema enum is the second net).
	var used: Array = []
	for kind in ["curses", "upgrades"]:
		var src: Dictionary = api._reg[kind]
		for id in src.keys():
			for m in src[id].get("modifiers", []):
				if not (used as Array).has(str(m["stat"])):
					(used as Array).append(str(m["stat"]))
	for stat in used:
		_check(failures, StatsScript.is_known(stat), "data uses stat '%s' which is not in the closed list" % stat)


# The schema enums must be the SAME closed lists as core/stats.gd and core/hooks.gd
# (stat/hook enums in curse.schema.json AND upgrade.schema.json).
func _schema_list_sync(failures: Array[String]) -> void:
	for schema_name in ["curse", "upgrade"]:
		var doc: Dictionary = _read_json("res://core/schemas/%s.schema.json" % schema_name)
		if doc.is_empty():
			_check(failures, false, "cannot read core/schemas/%s.schema.json" % schema_name)
			continue
		var defs: Dictionary = doc.get("definitions", {})
		var stat_enum: Array = defs.get("modifier", {}).get("properties", {}).get("stat", {}).get("enum", [])
		_check(failures, _same_words(stat_enum, StatsScript.STATS), "%s.schema.json stat enum != core/stats.gd STATS" % schema_name)
		var hook_enum: Array = defs.get("hook", {}).get("enum", [])
		_check(failures, _same_words(hook_enum, HooksScript.HOOKS), "%s.schema.json hook enum != core/hooks.gd HOOKS" % schema_name)


func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return data if data is Dictionary else {}


static func _same_words(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	var pool := {}
	for item in b:
		pool[str(item)] = true
	for item in a:
		if not pool.has(str(item)):
			return false
	return true


func _check(failures: Array[String], ok: bool, msg: String) -> bool:
	if not ok:
		failures.append(msg)
	return ok


func _first_errors(res: Dictionary) -> String:
	var errs: Array = res.get("errors", [])
	var out: Array[String] = []
	for i in mini(3, errs.size()):
		out.append(str(errs[i]))
	return " / ".join(out)


func _ascending(failures: Array[String], label: String, keys: Array) -> void:
	var prev := ""
	for item in keys:
		var id := str(item)
		if prev != "" and id.to_lower() < prev.to_lower():
			failures.append("%s: id '%s' is out of id order (after '%s')" % [label, id, prev])
		prev = id
