extends RefCounted
#
# sim/offers.gd - the upgrade shop draw (DESIGN.md section 8 system; ticket T-022).
#
# The shop never shows the full catalog. draw_shop() walks the CANON pipeline:
#   1. pool: data/upgrade_pools.json bracket for the level (core/content_api.gd
#      shop_pool), tier min level already enforced there;
#   2. exclude upgrades already at max stacks (stacks dict, absent key = 0);
#   3. price whole gold: floor(base x 1.5^stacks x shop_price_mul x discount_mul)
#      - shop_price_mul is the stats dict's value ( Bargain stacks), discount_mul the
#      REST bay's (100 - discount_pct) / 100 (D-T022-4);
#   4. affordability filter: price <= max(2 x purse, 80) (purse in whole gold);
#   5. fewer than 3 pass -> the cheapest remaining pool items fill the altars
#      (affordability waived for the fill, canon);
#   6. draw 3 distinct, weighted x2 for items the current class boosts (class_boost
#      in the upgrade file), seeded through the VoidRng the caller hands in.
#
# Seeded and pure: the same (api, level, purse, stacks, class, rng state, discount) gives
# the same offers; no engine surface here. reroll_cost() prices the plinth: 15 g +
# 15 g per use this visit (economy.json shop.reroll_plinth).

const VoidRngScript := preload("res://terrain/void_rng.gd")

## Canon fallbacks (economy.json shop.*); a passed api overrides from data.
const ALTARS := 3
const REROLL_BASE := 15
const REROLL_INCREMENT := 15
const AFFORD_PURSE_MUL := 2
const AFFORD_FLOOR := 80
const CLASS_BOOST_WEIGHT := 2


## Reroll plinth price: base + increment per use already paid this visit.
static func reroll_cost(uses_this_visit: int, p_api: RefCounted = null) -> int:
	var base := REROLL_BASE
	var inc := REROLL_INCREMENT
	if p_api != null:
		var plinth: Dictionary = p_api.data("economy").get("shop", {}).get("reroll_plinth", {})
		base = int(plinth.get("base", base))
		inc = int(plinth.get("increment_per_use_that_visit", inc))
	return base + inc * uses_this_visit


## Stacked, discounted, price-multiplied whole-gold price; one floor (D-T022-5).
static func price_for(p_upgrade: Dictionary, p_stacks: int, p_price_mul: float = 1.0,
		p_discount_mul: float = 1.0) -> int:
	var raw := float(int(p_upgrade.get("price", 0)))
	raw *= pow(1.5, float(p_stacks))
	raw *= p_price_mul * p_discount_mul
	return int(floor(raw))


## One shop visit. Returns:
##   level                - the level whose pool was drawn (the level just completed)
##   offers               - up to 3 of {"id": String, "price": int gold, "stacks": int owned}
##   reroll_cost          - the plinth's price for the FIRST reroll of this visit
##   threshold            - the affordability cut, max(2 x purse, 80)
##   filled_from_cheapest - true when < 3 passed the filter and the fill rule ran
static func draw_shop(p_api: RefCounted, p_level: int, p_purse_gold: int,
		p_stacks: Dictionary, p_class: String, p_rng: RefCounted,
		p_discount_mul: float = 1.0, p_stats: Dictionary = {}) -> Dictionary:
	var price_mul := float(p_stats.get("shop_price_mul", 1.0))
	var afford_raw: Dictionary = p_api.data("economy").get("shop", {}).get("affordability_filter", {})
	var floor_gold := int(afford_raw.get("floor", AFFORD_FLOOR))
	var purse_mul := int(afford_raw.get("purse_multiplier", AFFORD_PURSE_MUL))
	var threshold := maxi(purse_mul * p_purse_gold, floor_gold)

	var out: Array = []
	var remaining: Array = []       # [[weight, id, price, stacks], ...] not yet drawn
	for id in p_api.shop_pool(p_level):
		var u: Dictionary = p_api.upgrade(id)
		if u.is_empty() or _class_locked(u, p_class):
			continue
		var stacks := int(p_stacks.get(id, 0))
		if stacks >= int(u.get("max_stacks", 1)):
			continue
		var price := price_for(u, stacks, price_mul, p_discount_mul)
		if price <= threshold:
			remaining.append([_weight(u, p_class), id, price, stacks])
	var filled := false
	if remaining.size() < ALTARS:
		# The fill rule (canon): cheapest remaining pool items backfill, affordability
		# waived - a poor player still sees the three cheapest things the level offers.
		filled = true
		var pass_ids := {}
		for item in remaining:
			pass_ids[str(item[1])] = true
		var backfill: Array = []
		for id in p_api.shop_pool(p_level):
			var u: Dictionary = p_api.upgrade(id)
			if u.is_empty() or pass_ids.has(id) or _class_locked(u, p_class):
				continue
			var stacks := int(p_stacks.get(str(id), 0))
			if stacks >= int(u.get("max_stacks", 1)):
				continue
			backfill.append([price_for(u, stacks, price_mul, p_discount_mul), id, stacks, u])
		backfill.sort_custom(func(a, b): return int(a[0]) < int(b[0]) or (int(a[0]) == int(b[0]) and str(a[1]) < str(b[1])))
		for item in backfill:
			if remaining.size() >= ALTARS:
				break
			remaining.append([_weight(item[3], p_class), str(item[1]), int(item[0]), int(item[2])])

	# Weighted draw without replacement: x2 for the current class's boosts.
	while out.size() < ALTARS and not remaining.is_empty():
		var total := 0
		for item in remaining:
			total += int(item[0])
		var roll: int = p_rng.urange(total)
		var picked := 0
		for i in remaining.size():
			roll -= int(remaining[i][0])
			if roll < 0:
				picked = i
				break
		var win: Array = remaining[picked]
		remaining.remove_at(picked)
		out.append({"id": str(win[1]), "price": int(win[2]), "stacks": int(win[3])})

	var rerolls: Dictionary = p_api.data("economy").get("shop", {}).get("reroll_plinth", {})
	var reroll := int(rerolls.get("base", REROLL_BASE))
	return {
		"level": p_level,
		"offers": out,
		"reroll_cost": reroll,
		"threshold": threshold,
		"filled_from_cheapest": filled,
	}


static func _weight(p_upgrade: Dictionary, p_class: String) -> int:
	var boosts: Array = p_upgrade.get("class_boost", [])
	return CLASS_BOOST_WEIGHT if boosts.has(p_class) else 1


## A class_only upgrade is its class's kit (section 8 table rows like "Athletic only"):
## another class never sees the offer (D-T022-3). class_only null / class "" = everyone.
static func _class_locked(p_upgrade: Dictionary, p_class: String) -> bool:
	var only: Variant = p_upgrade.get("class_only")
	return only != null and str(only) != "" and p_class != str(only)


# =============================================================================
# T-023: the intermission draws (DESIGN.md section 6 bays, section 7 system).
# Layer note: these functions never name a content id - pools come from the content
# api and data/offering_schedule.json (the one tunable file). T-074 (NEW / REPEAT /
# FREE altars + per-enemy caps + chaser ceiling) replaces the body of
# enemy_candidates()/draw_enemy_bay() only; its hook is exactly that pair.
#
# Enemy gate table: min_level / max_votes live in content/enemies/<id>/enemy.json
# when the enemy wave (T-030..T-041) has written it; until then the schedule file's
# own "enemies" table (DESIGN.md section 5 CANON numbers) carries them and enemy.json
# wins per id once present. No id is named here - only table-driven lookups.
# =============================================================================

## Hunger fallback (DESIGN.md section 6): an E bay whose pool is exhausted offers
## Hunger instead; +5% enemy speed for all enemies per stack, repeatable.
const HUNGER_SPEED_PCT := 5


## {id: {"min_level": int, "max_votes": int}} for every enemy the content layer knows:
## enemy.json rows first, the schedule's "enemies" fallback table for the rest.
static func enemy_gate(p_api: RefCounted) -> Dictionary:
	var out: Dictionary = {}
	for id in p_api.enemy_ids():
		var e: Dictionary = p_api.enemy(id)
		out[str(id)] = {
			"min_level": int(e.get("min_level", 1)),
			"max_votes": int(e.get("max_votes", 1)),
		}
	var table: Dictionary = p_api.data("offering_schedule").get("enemies", {})
	for id in table.keys():
		var eid := str(id)
		if out.has(eid):
			continue
		var row: Dictionary = table[id]
		out[eid] = {
			"min_level": int(row.get("min_level", 1)),
			"max_votes": int(row.get("max_votes", 1)),
		}
	return out


## Sorted candidate enemy ids for one E draw: min_level <= p_level, votes < max_votes,
## restricted to the schedule's starter pool when p_pool == "starter".
static func enemy_candidates(p_api: RefCounted, p_level: int, p_pool: String,
		p_votes: Dictionary, p_gate: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var starter: Array = p_api.data("offering_schedule").get("starter_pool", [])
	for id in p_gate.keys():
		var eid := str(id)
		var row: Dictionary = p_gate[eid]
		if p_level < int(row["min_level"]):
			continue
		if int(p_votes.get(eid, 0)) >= int(row["max_votes"]):
			continue
		if p_pool == "starter" and not starter.has(eid):
			continue
		out.append(eid)
	out.sort()
	return out


## One E-bay draw (per vote: an E x2 bay re-draws between votes, caller's job).
## Returns {"kind": "enemy", "altars": [{"kind": "enemy", "id", "name", "votes"}]}
## (up to 3 distinct, sorted by id for a stable altar order),
## or {"kind": "hunger", "altars": [{"kind": "hunger", "speed_pct": HUNGER_SPEED_PCT}]}
## when no candidate is left (DESIGN.md section 6, the exhausted-pool fallback).
static func draw_enemy_bay(p_api: RefCounted, p_level: int, p_pool: String,
		p_votes: Dictionary, p_rng: RefCounted) -> Dictionary:
	var gate := enemy_gate(p_api)
	var cands := enemy_candidates(p_api, p_level, p_pool, p_votes, gate)
	var ids: Array = []
	while ids.size() < 3 and not cands.is_empty():
		var roll: int = p_rng.urange(cands.size())
		ids.append(cands[roll])
		cands.remove_at(roll)
	ids.sort()
	var altars: Array = []
	for id in ids:
		var e: Dictionary = p_api.enemy(id)
		altars.append({
			"kind": "enemy",
			"id": str(id),
			"name": str(e.get("name", "")) if not e.is_empty() else str(id),
			"votes": int(p_votes.get(str(id), 0)),
		})
	if altars.is_empty():
		return {"kind": "hunger", "altars": [{"kind": "hunger", "speed_pct": HUNGER_SPEED_PCT}]}
	return {"kind": "enemy", "altars": altars}


## The tithe (DESIGN.md section 7): 100 + 75 per tithe already paid this run.
static func tithe_cost(p_tithes: int, p_api: RefCounted = null) -> int:
	var base := 100
	var per := 75
	if p_api != null:
		var t: Dictionary = p_api.data("economy").get("curse_bay", {}).get("tithe", {})
		base = int(t.get("base", base))
		per = int(t.get("per_tithe_paid_this_run", per))
	return base + per * p_tithes


## One C-bay draw (DESIGN.md section 7 system): 3 distinct curses, gated by
## eligible_curses (min_level + enemy-linked >= 1 vote); non-stacking picked curses
## leave the pool, stackable ones leave at max stacks (p_held: {id: stacks_owned});
## at least on Mild when any Mild is eligible (guaranteed by construction here);
## bounty per altar: api.curse_bounty (severity base x (1 + level/20), economy.json).
## Returns {"altars": [{"kind": "curse", "id", "name", "severity", "stacks", "bounty"}],
##          "tithe": tithe_cost(p_tithes)}.
static func draw_curse_bay(p_api: RefCounted, p_level: int, p_votes: Dictionary,
		p_held: Dictionary, p_rng: RefCounted, p_tithes: int) -> Dictionary:
	var mild: Array = []
	var rest: Array = []
	for id in p_api.eligible_curses(p_level, p_votes):
		var cid := str(id)
		var c: Dictionary = p_api.curse(cid)
		if _held_out(cid, c, p_held):
			continue
		if str(c.get("severity", "")) == "mild":
			mild.append(cid)
		else:
			rest.append(cid)
	var chosen: Array = []
	if mild.is_empty():
		chosen = _draw_up_to(rest, 3, p_rng)
	else:
		# at least one Mild (canon); the rest fill from what remains, seeded.
		chosen = _draw_up_to(mild, 1, p_rng)
		var fill := _draw_up_to(mild + rest, 3 - chosen.size(), p_rng)
		chosen += fill
	chosen.sort()
	var altars: Array = []
	for cid in chosen:
		var c: Dictionary = p_api.curse(cid)
		altars.append({
			"kind": "curse",
			"id": cid,
			"name": str(c.get("name", cid)),
			"severity": str(c.get("severity", "")),
			"stacks": int(p_held.get(cid, 0)),
			"bounty": p_api.curse_bounty(cid, p_level),
		})
	return {"altars": altars, "tithe": tithe_cost(p_tithes, p_api)}


## True when p_id may NOT be offered again: a non-stacking curse is gone once held;
## a stackable one is gone at max stacks (DESIGN.md section 7, pool removal).
static func _held_out(p_id: String, p_curse: Dictionary, p_held: Dictionary) -> bool:
	var held := int(p_held.get(p_id, 0))
	return held >= int(p_curse.get("max_stacks", 1))


## Seeded draw without replacement: shuffles a copy, takes up to p_n.
static func _draw_up_to(p_ids: Array, p_n: int, p_rng: RefCounted) -> Array:
	var pool := (p_ids as Array).duplicate()
	p_rng.shuffle(pool)
	return (pool as Array).slice(0, mini(p_n, pool.size()))
