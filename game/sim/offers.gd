extends RefCounted
#
# sim/offers.gd - the upgrade shop draw (DESIGN.md section 8 system; ticket T-022).
#
# The shop never shows the full catalog. draw_shop() walks the CANON pipeline:
#   1. pool: data/upgrade_pools.json bracket for the level (core/content_api.gd
#      shop_pool), tier min level already enforced there;
#   2. exclude upgrades already at max stacks (stacks dict, absent key = 0); the
#      optional p_max_stacks_bonus dict ({upgrade id: extra stacks}, T-053's
#      Marathon, D-T053-7) raises an id's cap for this draw;
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
		p_discount_mul: float = 1.0, p_stats: Dictionary = {},
		p_max_stacks_bonus: Dictionary = {}) -> Dictionary:
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
		if stacks >= int(u.get("max_stacks", 1)) + int(p_max_stacks_bonus.get(id, 0)):
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
			if stacks >= int(u.get("max_stacks", 1)) + int(p_max_stacks_bonus.get(id, 0)):
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


# ==============================================================================
# T-023: the intermission draws (DESIGN.md section 6 bays, section 7 system).
# T-074: the E draw implements D-074 - NEW / REPEAT / FREE slots, the per-enemy
# caps (live in enemy_gate) and the chaser ceiling (helpers below). Layer note:
# no content id is named here - every number comes from the schedule file's
# "enemies" and "chaser" blocks (the one tunable file) or from callers' args.
# =============================================================================

## Hunger fallback (DESIGN.md section 6): an E bay whose pool is exhausted offers
## Hunger instead; +5% enemy speed for all enemies per stack, repeatable.
const HUNGER_SPEED_PCT := 5

## D-074 fallbacks for the "chaser" block of the schedule file: the ceiling is a
## number of never-named units (false = "no chaser tracking configured"); a
## chaser type weighs one full body unless the cfg says otherwise. The eps keeps
## exact-boundary fits (e.g. 5.5 + 0.5 = 6.0) inside the limit despite float noise.
const CHASER_CAP_FALLBACK := 6.0
const CHASER_EPS := 0.0001


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


# ------------------------------------------------------------------ D-074 chaser --

## The schedule file's "chaser" block (D-T074-2). Shape:
##   ceiling       - max floating lethal bodies in play (CHASER_CAP_FALLBACK);
##   weights       - {enemy_id: bodies per vote}; ids absent or 0 = not a chaser;
##   kitten_host   - the enemy each kitten trails (with kitten_curse held);
##   kitten_curse  - the curse id that spawns kittens;
##   kitten_weight - one kitten's body weight (D-074: half each).
static func chaser_cfg(p_api: RefCounted) -> Dictionary:
	return p_api.data("offering_schedule").get("chaser", {})


static func _chaser_ceiling(p_cfg: Dictionary) -> float:
	return float(p_cfg.get("ceiling", CHASER_CAP_FALLBACK))


## One voted type's body weight under the curses held (p_curses: {curse_id: stacks}):
## its weight, plus the kitten weight on the host type while the kitten curse is
## held - every cat then trails its kitten (D-T074-3); a NEW cat voted while the
## curse is already held adds weight + kitten in one go, same function.
static func chaser_weight(p_cfg: Dictionary, p_id: String, p_curses: Dictionary) -> float:
	var w := float(p_cfg.get("weights", {}).get(p_id, 0.0))
	if w <= 0.0:
		return 0.0
	var host := str(p_cfg.get("kitten_host", ""))
	var curse := str(p_cfg.get("kitten_curse", ""))
	if p_id == host and curse != "" and int(p_curses.get(curse, 0)) > 0:
		w += float(p_cfg.get("kitten_weight", 0.0))
	return w


## Floating lethal bodies in play right now under the held curses (D-074).
static func chaser_load(p_cfg: Dictionary, p_votes: Dictionary, p_curses: Dictionary) -> float:
	var load := 0.0
	for id in p_votes.keys():
		load += float(int(p_votes[id])) * chaser_weight(p_cfg, str(id), p_curses)
	return load


## True when drawing p_id stays at or under the ceiling (non-chasers always fit).
static func _chaser_fits(p_cfg: Dictionary, p_id: String, p_curses: Dictionary,
		p_load: float, p_ceiling: float) -> bool:
	var w := chaser_weight(p_cfg, p_id, p_curses)
	if w <= 0.0:
		return true
	return p_load + w <= p_ceiling + CHASER_EPS


## One E-bay draw (D-074 slots; per vote: an E x2 bay re-draws between votes, the
## caller passes the just-picked id as p_prev_vote on the re-draw - D-074).
## Slots, in order:
##   new    - the eligible type with 0 votes with the lowest gate min_level,
##            ties by seeded draw; empty -> the slot becomes a FREE pick;
##   repeat - an eligible type already in play, below its cap (the gate filter
##            did that), NEVER the type of the previous vote; empty -> FREE;
##   free   - a seeded pick from everything eligible and not already shown.
## A pick that would push the chaser load (D-074) past the ceiling is not drawn.
## Every enemy altar carries its slot in the "slot" field.
## Returns {"kind": "enemy", "altars": [{"kind": "enemy", "slot", "id", "name",
## "votes"}]} (up to 3 DISTINCT types, in slot order), or {"kind": "hunger",
## "altars": [{"kind": "hunger", "speed_pct": HUNGER_SPEED_PCT}]} when no altar
## can be drawn at all (DESIGN.md section 6, the exhausted-pool fallback).
static func draw_enemy_bay(p_api: RefCounted, p_level: int, p_pool: String,
		p_votes: Dictionary, p_rng: RefCounted, p_prev_vote: String = "",
		p_curses: Dictionary = {}) -> Dictionary:
	var gate := enemy_gate(p_api)
	var cfg := chaser_cfg(p_api)
	var ceiling := _chaser_ceiling(cfg)
	var load := chaser_load(cfg, p_votes, p_curses)
	var eligible := enemy_candidates(p_api, p_level, p_pool, p_votes, gate)

	var picked: Array = ["", "", ""]
	# pass 1 - each slot's own category, in slot order
	if not eligible.is_empty():
		# slot 0 = NEW: vote-less types, lowest min_level first, ties seeded.
		var best := -1
		var cands: Array = []
		for id in eligible:
			var eid := str(id)
			if int(p_votes.get(eid, 0)) != 0:
				continue
			if not _chaser_fits(cfg, eid, p_curses, load, ceiling):
				continue
			var lv := int(gate[eid]["min_level"])
			if best < 0 or lv < best:
				best = lv
				cands = [eid]
			elif lv == best:
				cands.append(eid)
		if not cands.is_empty():
			picked[0] = str(cands[p_rng.urange(cands.size())])
		# slot 1 = REPEAT: in play, below cap, never the previous vote's type.
		if eligible.size() > used_count(picked):
			var rep: Array = []
			for id in eligible:
				var eid := str(id)
				if _taken(picked, eid) or eid == p_prev_vote:
					continue
				if int(p_votes.get(eid, 0)) <= 0:
					continue
				if not _chaser_fits(cfg, eid, p_curses, load, ceiling):
					continue
				rep.append(eid)
			if not rep.is_empty():
				picked[1] = str(rep[p_rng.urange(rep.size())])
	# pass 2 - empty slots fill left to right as FREE picks (D-074: an empty
	# category's altar becomes FREE; "shown" = already on this bay).
	for i in picked.size():
		if str(picked[i]) != "" or eligible.size() <= used_count(picked):
			continue
		var rest: Array = []
		for id in eligible:
			var eid := str(id)
			if _taken(picked, eid):
				continue
			if not _chaser_fits(cfg, eid, p_curses, load, ceiling):
				continue
			rest.append(eid)
		if rest.is_empty():
			break
		picked[i] = str(rest[p_rng.urange(rest.size())])

	var altars: Array = []
	for i in picked.size():
		var eid := str(picked[i])
		if eid == "":
			continue
		var e: Dictionary = p_api.enemy(eid)
		altars.append({
			"kind": "enemy",
			"slot": ["new", "repeat", "free"][i],
			"id": eid,
			"name": str(e.get("name", "")) if not e.is_empty() else eid,
			"votes": int(p_votes.get(eid, 0)),
		})
	if altars.is_empty():
		return {"kind": "hunger", "altars": [{"kind": "hunger", "speed_pct": HUNGER_SPEED_PCT}]}
	return {"kind": "enemy", "altars": altars}


## How many slots of the picked list are filled.
static func used_count(picked: Array) -> int:
	var n := 0
	for p in picked:
		if str(p) != "":
			n += 1
	return n


static func _taken(picked: Array, p_id: String) -> bool:
	return (picked as Array).has(p_id)


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
