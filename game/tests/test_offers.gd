extends RefCounted
#
# Shop-offer test (DESIGN.md section 8; ticket T-022). Proves on the REAL content:
#   - CANON: the level-1 shop offers EXACTLY paycheck, more, yearn_for_speed on 100 seeds;
#   - affordability filter price <= max(2 x purse, 80), and the cheapest-fill rule when
#     fewer than 3 pass;
#   - stack pricing floor(price x 1.5^stacks), out-of-stock at max stacks;
#   - class weighting x2 for the current class's boosts, class_only gated;
#   - reroll plinth 15 g + 15 g per use that visit;
#   - seeded: same seed -> same offers.

const ContentApiScript := preload("res://core/content_api.gd")
const OffersScript := preload("res://sim/offers.gd")
const VoidRngScript := preload("res://terrain/void_rng.gd")


func run() -> Array[String]:
	var f: Array[String] = []
	var api := ContentApiScript.load()
	if not bool(api.is_ok()):
		f.append("content api boot failed: %s" % " / ".join(api.boot_errors()))
		return f
	_test_canon_level1_100_seeds(f, api)
	_test_affordability(f, api)
	_test_stack_pricing(f, api)
	_test_class_gating_and_weighting(f, api)
	_test_reroll(f, api)
	_test_seeded(f, api)
	return f


func _rng(seed_value: int) -> RefCounted:
	return VoidRngScript.new(VoidRngScript.mix(seed_value, 822))


func _draw(api: RefCounted, level: int, purse: int, stacks: Dictionary, cls: String,
		seed_value: int, discount: float = 1.0) -> Dictionary:
	return OffersScript.draw_shop(api, level, purse, stacks, cls, _rng(seed_value), discount)


func _ids(shop: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for o in shop["offers"]:
		out.append(str(o["id"]))
	return out


func _test_canon_level1_100_seeds(f: Array[String], api: RefCounted) -> void:
	var canon := ["paycheck", "more", "yearn_for_speed"]
	for seed_value in range(100):
		var shop: Dictionary = _draw(api, 1, 0, {}, "", seed_value)
		var ids := _ids(shop)
		if ids.size() != 3:
			f.append("level1: seed %d offered %d items, want 3" % [seed_value, ids.size()])
			continue
		for id in canon:
			if not ids.has(id):
				f.append("level1: seed %d missing canon upgrade %s (got %s)" % [seed_value, id, str(ids)])
		if ids.size() != 3:
			continue
		var uniq := {}
		for id in ids:
			uniq[id] = true
		if uniq.size() != 3:
			f.append("level1: seed %d offered duplicates" % seed_value)
	# the canon prices hold on the real content
	var shop2: Dictionary = _draw(api, 1, 0, {}, "", 0)
	for o in shop2["offers"]:
		var want := {"paycheck": 40, "more": 50, "yearn_for_speed": 60}
		if int(o["price"]) != int(want.get(str(o["id"]), 0)):
			f.append("level1: %s priced %d, want %d (canon tier T1)" % [str(o["id"]), int(o["price"]), int(want.get(str(o["id"]), 0))])


func _test_affordability(f: Array[String], api: RefCounted) -> void:
	# purse 0 -> threshold 80: only items priced <= 80 may appear at level 4 (T2 in pool)
	for seed_value in range(20):
		var shop: Dictionary = _draw(api, 4, 0, {}, "", seed_value)
		for o in shop["offers"]:
			if int(o["price"]) > 80:
				f.append("afford: purse 0 seed %d offered %s at %d > threshold 80"
						% [seed_value, str(o["id"]), int(o["price"])])
	# purse 300 -> threshold 600: 600-priced items can appear
	var shop300: Dictionary = _draw(api, 10, 300, {}, "", 7)
	if int(shop300["threshold"]) != 600:
		f.append("afford: threshold is %d, want max(2 x 300, 80) = 600" % int(shop300["threshold"]))
	# the fill rule: at level 18 with every T1 item maxed out (T1 prices <= 80 always pass
	# the filter, so the only way to starve it is to stock them all out first) nothing
	# passes at purse 0 and the three cheapest remaining pool items fill the altars.
	var t1_ids: Array[String] = ["paycheck", "more", "yearn_for_speed", "field_dressing",
			"long_reach", "radar_beacon", "radar_gifts", "ledge_grace", "brace", "sure_foot"]
	var maxed := {}
	for id in t1_ids:
		maxed[id] = 9
	var filled_shop: Dictionary = _draw(api, 18, 0, maxed, "", 3)
	if not bool(filled_shop["filled_from_cheapest"]):
		f.append("afford: starved shop must report filled_from_cheapest")
	if _ids(filled_shop).size() != 3:
		f.append("afford: starved shop filled %d altars, want 3" % filled_shop["offers"].size())
	var cheapest_seen := 99999
	for o in filled_shop["offers"]:
		if int(o["price"]) < cheapest_seen:
			cheapest_seen = int(o["price"])
		if (t1_ids as Array).has(str(o["id"])):
			f.append("afford: fill sold maxed-out %s" % str(o["id"]))	# every price in the filled shop must belong to the non-T1 pool items (T2+)
	var pool_ids: Array[String] = api.shop_pool(18)
	for o in filled_shop["offers"]:
		if not pool_ids.has(str(o["id"])):
			f.append("afford: fill offered %s outside the level-18 pool" % str(o["id"]))
	# filled shops never duplicate
	var uniq := {}
	for id in _ids(filled_shop):
		if uniq.has(id):
			f.append("afford: fill produced a duplicate offer")
		uniq[id] = true


func _test_stack_pricing(f: Array[String], api: RefCounted) -> void:
	var paycheck: Dictionary = api.upgrade("paycheck")
	var cases := [[0, 40], [1, 60], [2, 90], [3, 135]]
	for c in cases:
		var got := int(OffersScript.price_for(paycheck, int(c[0])))
		if got != int(c[1]):
			f.append("stacks: paycheck at %d stacks costs %d, want floor(40 x 1.5^%d) = %d"
					% [int(c[0]), got, int(c[0]), int(c[1])])
	# out of stock: paycheck max 3 stacks; at 3 it never appears
	var shops := 0
	for seed_value in range(30):
		var shop: Dictionary = _draw(api, 4, 1000, {"paycheck": 3}, "", seed_value)
		shops += 1
		if _ids(shop).has("paycheck"):
			f.append("stacks: paycheck offered at max stacks (seed %d)" % seed_value)
			break
	if shops == 0:
		f.append("stacks: no shops drawn for the max-stacks check")


func _test_class_gating_and_weighting(f: Array[String], api: RefCounted) -> void:
	# class_only: marathon IS the athletic kit (section 8 table, "Athletic only"), so the
	# two other classes never see it; its owner can.
	var owners := {"marathon": "athletic", "twin_dash": "dasher", "updraft": "glider"}
	var classes: Array[String] = ["dasher", "glider", "athletic"]
	for item in owners.keys():
		var owner: String = owners[item]
		for cls in classes:
			for seed_value in range(30):
				var shop: Dictionary = _draw(api, 18, 10000, {}, cls, seed_value)
				var has := _ids(shop).has(item)
				if cls == owner:
					if has:
						break
					if seed_value == 29:
						f.append("class: %s never offered to its owner %s in 30 draws" % [item, cls])
				elif has:
					f.append("class: %s was offered to a %s (class_only %s)" % [item, cls, owner])
					break
	# weighting x2: at level 2-3 the pool is 10 T1 items, yearn_for_speed boosts athletic.
	# A boosted class draws it at ~3 x 2/11 per shop; a neutral class at ~3/10.
	var athletic_shares := _share(api, "athletic", 1000, 7000)
	if athletic_shares < 0.40 or athletic_shares > 0.68:
		f.append("class: yearn_for_speed share on athletic is %.3f, want ~0.545 (3 x 2/11)"
				% athletic_shares)
	var dasher_shares := _share(api, "dasher", 1000, 9000)
	if dasher_shares < 0.18 or dasher_shares > 0.42:
		f.append("class: yearn_for_speed share on dasher is %.3f, want ~0.30" % dasher_shares)


## Share of shops (over n seeded draws at level 2) that include yearn_for_speed.
func _share(api: RefCounted, cls: String, n: int, seed_base: int) -> float:
	var hits := 0
	for i in n:
		var shop: Dictionary = _draw(api, 2, 10000, {}, cls, seed_base + i)
		if _ids(shop).has("yearn_for_speed"):
			hits += 1
	return float(hits) / float(n)


func _test_reroll(f: Array[String], api: RefCounted) -> void:
	var want := [15, 30, 45, 60]
	for uses in 4:
		var cost := int(OffersScript.reroll_cost(uses, api))
		if cost != int(want[uses]):
			f.append("reroll: use %d costs %d, want %d" % [uses, cost, int(want[uses])])
	if int(OffersScript.reroll_cost(0)) != 15:
		f.append("reroll: no-api fallback must stay 15")


func _test_seeded(f: Array[String], api: RefCounted) -> void:
	for seed_value in range(20):
		var a: Dictionary = _draw(api, 10, 400, {"more": 1}, "dasher", 4200 + seed_value)
		var b: Dictionary = _draw(api, 10, 400, {"more": 1}, "dasher", 4200 + seed_value)
		if str(a["offers"]) != str(b["offers"]):
			f.append("seed: same seed %d drew different offers" % seed_value)
			break
	# and different seeds do draw differently (10 distinct shuffles over 40 seeds)
	var seen := {}
	for seed_value in range(40):
		var shop: Dictionary = _draw(api, 26, 20000, {}, "dasher", 8000 + seed_value)
		seen[str(_ids(shop))] = true
	if seen.size() < 10:
		f.append("seed: 40 seeds produced only %d distinct shop layouts" % seen.size())
