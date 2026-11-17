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
