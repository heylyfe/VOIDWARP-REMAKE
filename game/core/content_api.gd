extends RefCounted
#
# content_api.gd - the read surface over the content registry (DESIGN.md section 12;
# ticket T-013). Everything outside core/ reads content through this script: entries by id,
# the eligibility pools, the shop pool, and the modifier arithmetic.
#
# Read-only by construction: no method mutates the loaded content. sim/ and view/ must treat
# the returned Dictionaries as immutable (copy before writing; nothing here hands out a
# writable copy). Load once per boot with load(), keep the instance.
#
# Boot refusal: load() calls registry.load_all() (which pushes one error per offending file,
# name included). is_ok() false => the boot path must quit(1); boot_errors() carries the
# lines. Every query below returns empty/sorted-safe values on a failed boot.
#
# Layer rules (game/tests/test_boundaries.gd): refers to other scripts only via preload
# ("res://..."), engine surface Array/Dictionary only.

const RegistryScript := preload("res://core/registry.gd")
const StatsScript := preload("res://core/stats.gd")

# Upgrade tiers enter the shop pool at these levels (DESIGN.md section 8 tier table [CANON]).
# Filled at load() from data/upgrade_pools.json "tiers" (tier -> pool_from), the one source
# of the table (D-C4-15-1); it was a code constant that duplicated the data file's _doc.
# Empty on a failed boot, so shop_pool() then admits nothing.
var TIER_FROM: Dictionary = {}

var _reg: Dictionary = {}


## Scans + validates everything once; see registry.gd for the contract.
static func load() -> RefCounted:
	var api := new()
	api._reg = RegistryScript.load_all()
	for t in api.tiers().keys():
		if str(t).begins_with("_"):
			continue
		api.TIER_FROM[str(t)] = int((api.tiers()[t] as Dictionary).get("pool_from", 99999))
	return api


## The price-tier table, {"T1": {"pool_from", "price_min", "price_max"}, ...} plus its "_doc"
## (data/upgrade_pools.json tiers; DESIGN.md section 8). {} on a failed boot.
func tiers() -> Dictionary:
	var t: Variant = data("upgrade_pools").get("tiers", {})
	return t if t is Dictionary else {}


func is_ok() -> bool:
	return bool(_reg.get("ok", false))


## The refusal lines from the boot (each names the offending file). Empty when is_ok().
func boot_errors() -> Array[String]:
	var out: Array[String] = []
	for e in _reg.get("errors", []):
		out.append(str(e))
	return out


## Sorted "kind:id" strings for every content file - the content set for RunState
## (DESIGN.md section 13 rule 2). Empty array on a failed boot.
func content_ids() -> Array[String]:
	return _str_array(_reg.get("content_ids", []))


# ------------------------------------------------------------------------------ entry access --

## Sorted id lists per kind.
func enemy_ids() -> Array[String]:
	return _str_array(_reg.get("enemies", {}).keys())
func curse_ids() -> Array[String]:
	return _str_array(_reg.get("curses", {}).keys())
func upgrade_ids() -> Array[String]:
	return _str_array(_reg.get("upgrades", {}).keys())
func biome_ids() -> Array[String]:
	return _str_array(_reg.get("biomes", {}).keys())


## One entry's file data by id; {} when the id is absent (or the boot failed).
func enemy(id: String) -> Dictionary:
	return _reg.get("enemies", {}).get(id, {})
func curse(id: String) -> Dictionary:
	return _reg.get("curses", {}).get(id, {})
func upgrade(id: String) -> Dictionary:
	return _reg.get("upgrades", {}).get(id, {})
func biome(id: String) -> Dictionary:
	return _reg.get("biomes", {}).get(id, {})


## The six parsed data files by name (economy, offering_schedule, palette, player, tips,
## upgrade_pools); {} when absent. Nullable keys stay null: read data.get("mode", "").
func data(name: String) -> Dictionary:
	return _reg.get("data", {}).get(name, {})


# ------------------------------------------------------------------------------ eligibility --

## Curses eligible at p_level (DESIGN.md section 7 gating): min_level <= level, and an
## enemy-linked curse appears only if that enemy has >= 1 vote. votes: {enemy_id: int}
## (absent key = 0 votes). Curses whose file carries "retired": true are never eligible,
## at any level and regardless of votes - they stay on disk (honest no-ops, not deleted)
## but leave every offer pool. Returns sorted ids.
func eligible_curses(p_level: int, votes: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for id in curse_ids():
		var c: Dictionary = curse(id)
		if bool(c.get("retired", false)):
			continue
		if int(c.get("min_level", 1)) > p_level:
			continue
		var req: Variant = c.get("requires_enemy")
		if req != null and int(votes.get(str(req), 0)) < 1:
			continue
		out.append(id)
	return out


## The brackeed upgrade pool for p_level (DESIGN.md section 8 [CANON]): the ids of the
## one bracket containing the level (first bracket wins on overlap), kept only when the
## upgrade exists in content/upgrades/ and its tier has entered the pool at or below the
## level (data/upgrade_pools.json tiers: T1@1, T2@4, T3@10, T4@18, T5@26). Sorted as listed in the bracket file.
func shop_pool(p_level: int) -> Array[String]:
	var out: Array[String] = []
	var brackets: Variant = data("upgrade_pools").get("brackets", [])
	if not (brackets is Array):
		return out
	for bracket in brackets:
		var b: Dictionary = bracket
		var lo := int(b.get("min_level", 0))
		var hi_v: Variant = b.get("max_level")
		if p_level < lo or (hi_v != null and p_level > int(hi_v)):
			continue
		for raw_id in b.get("ids", []):
			var id := str(raw_id)
			var u: Dictionary = upgrade(id)
			if u.is_empty():
				continue
			if int(TIER_FROM.get(str(u.get("tier", "")), 99999)) > p_level:
				continue
			out.append(id)
		break  # the first bracket containing the level is the one that applies
	return out


## Every curse bounty a bay shows before the pick (DESIGN.md section 7 system):
## severity base x (1 + level/20), floored to whole gold (data/economy.json gold_arithmetic).
func curse_bounty(id: String, p_level: int) -> int:
	var bases := {"mild": 20, "harsh": 45, "brutal": 90}
	var base: int = int(bases.get(str(curse(id).get("severity", "")), 0))
	return int(floor(float(base) * float(20 + p_level) / 20.0))


# --------------------------------------------------------------------------- modifier semantics --

## DESIGN.md section 12 modifier math. base: {stat: value}; mods: modifier dicts as read
## from content files; ctx: {"phase": "" | "black_phase" | "gold_phase",
## "class": "" | "dasher" | "glider" | "athletic"}.
## Per stat: (base + sum of adds) x product of muls, then "set" wins (the last set in mods
## order, when several apply). Stats touched by a mod but absent from base start at
## StatsScript.DEFAULTS (0 when a stat has no default yet). A modifier whose "when" does
## not match the context is skipped. Returns a new dict; inputs untouched.
static func apply_modifiers(base: Dictionary, mods: Array, ctx: Dictionary) -> Dictionary:
	var adds: Dictionary = {}
	var muls: Dictionary = {}
	var sets: Dictionary = {}
	for m in mods:
		var mod: Dictionary = m
		if not _when_matches(str(mod.get("when", "always")), ctx):
			continue
		var stat := str(mod.get("stat", ""))
		if not StatsScript.is_known(stat):
			continue  # the registry already refused any file carrying an unknown stat
		match str(mod.get("op", "")):
			"add":
				adds[stat] = float(adds.get(stat, 0.0)) + float(mod["value"])
			"mul":
				muls[stat] = float(muls.get(stat, 1.0)) * float(mod["value"])
			"set":
				sets[stat] = mod["value"]
	var stats: Array = []
	for s in base.keys():
		stats.append(str(s))
	for s in adds.keys(): stats.append(s)
	for s in muls.keys(): stats.append(s)
	for s in sets.keys(): stats.append(s)
	stats.sort(); stats = _unique(stats)
	var out: Dictionary = {}
	for s in stats:
		var start: float = float(base.get(s, StatsScript.DEFAULTS.get(s, 0.0)))
		var val: float = (start + float(adds.get(s, 0.0))) * float(muls.get(s, 1.0))
		if sets.has(s):
			val = float(sets[s])
		out[s] = val
	return out


## One content entry's modifiers repeated per stack (stackable curses/upgrades apply their
## modifiers once per owned stack, DESIGN.md sections 7 and 8). stacks <= 0 -> [].
static func mods_for_stacks(mods: Array, stacks: int) -> Array:
	var out: Array = []
	for _i in maxi(stacks, 0):
		for m in mods:
			out.append(m)
	return out


static func _when_matches(when: String, ctx: Dictionary) -> bool:
	if when == "always" or when == "":
		return true
	if when == "black_phase" or when == "gold_phase":
		return str(ctx.get("phase", "")) == when
	if when.begins_with("class:"):
		return str(ctx.get("class", "")) == when.substr(6)
	return false


# ------------------------------------------------------------------------------------ helpers --

static func _str_array(raw) -> Array[String]:
	var out: Array[String] = []
	for item in raw:
		out.append(str(item))
	return out


static func _unique(sorted_arr: Array) -> Array:
	var out: Array = []
	for item in sorted_arr:
		if not out.is_empty() and str(out[out.size() - 1]) == str(item):
			continue
		out.append(item)
	return out
