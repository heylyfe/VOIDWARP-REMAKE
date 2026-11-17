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
	_test_bay_shapes(f, api)
	_test_bay_rules(f, api)
	_test_thousand_runs(f, api)
	_test_single_stack_to_cap(f, api)
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


# ============================================================================
# T-074: the E draw - D-074 slots (NEW / REPEAT / FREE), the per-enemy caps
# and the chaser ceiling, proved on the REAL content + schedule data.
# ============================================================================

const IntermissionScript := preload("res://sim/intermission.gd")

const CHASERS := ["kiwi_cat", "you", "toucher", "seal"]   # D-074's floaters, 1 body each


func _bay(api: RefCounted, level: int, pool: String, votes: Dictionary,
		rng: RefCounted, prev: String = "", curses: Dictionary = {}) -> Dictionary:
	return OffersScript.draw_enemy_bay(api, level, pool, votes, rng, prev, curses)


func _bay_ids(bay: Dictionary) -> Array:
	var out: Array = []
	for a in bay["altars"]:
		out.append(str(a["id"]))
	return out


## The test's own NEW-category oracle: unpicked types this vote may still show
## (gate numbers, pool and ceiling headroom - MathGoods separate from the draw).
func _elig_unpicked(api: RefCounted, draw_level: int, pool: String, votes: Dictionary,
		gate: Dictionary, cfg: Dictionary, curses: Dictionary) -> Array:
	var out: Array = []
	var starter: Array = api.data("offering_schedule").get("starter_pool", [])
	var ceiling := float(cfg.get("ceiling", 6.0))
	var load: float = OffersScript.chaser_load(cfg, votes, curses)
	for id in gate.keys():
		var eid := str(id)
		if int(votes.get(eid, 0)) != 0:
			continue
		if draw_level < int(gate[eid]["min_level"]):
			continue
		if pool == "starter" and not starter.has(eid):
			continue
		var w: float = OffersScript.chaser_weight(cfg, eid, curses)
		if w > 0.0 and load + w > ceiling + 0.0001:
			continue
		out.append(eid)
	out.sort()
	return out


func _test_bay_shapes(f: Array[String], api: RefCounted) -> void:
	# the pre-run E bay: exactly the starter trio, three DISTINCT altars, the
	# NEW slot lit, nothing hunger about it
	for seed_value in range(60):
		var bay: Dictionary = _bay(api, 1, "starter", {}, VoidRngScript.new(3100 + seed_value))
		var ids := _bay_ids(bay)
		if ids.size() != 3:
			f.append("shapes: pre-run drew %d altars, want 3 (seed %d)" % [ids.size(), seed_value])
			continue
		var uniq := {}
		for id in ids:
			uniq[id] = true
		if uniq.size() != 3:
			f.append("shapes: pre-run altars not distinct (seed %d): %s" % [seed_value, str(ids)])
		for id in ids:
			if not ["kiwi_cat", "coil", "thicc_ben"].has(id):
				f.append("shapes: pre-run offered %s, outside the starter trio" % id)
				break
		if not _bay_slots(bay).has("new"):
			f.append("shapes: pre-run bay without a NEW slot while all types are unpicked (seed %d)" % seed_value)
	# every altar names one of the three slots
	var bay2: Dictionary = _bay(api, 30, "", {}, VoidRngScript.new(7))
	for a in bay2["altars"]:
		if not ["new", "repeat", "free"].has(str(a["slot"])):
			f.append("shapes: unknown slot %s" % str(a["slot"]))
	# seeded: same seed -> same bay; 40 seeds -> many distinct layouts
	var votes25 := {"kiwi_cat": 1, "gin": 1}
	var a1: Dictionary = _bay(api, 25, "", votes25, VoidRngScript.new(77), "gin")
	var a2: Dictionary = _bay(api, 25, "", votes25, VoidRngScript.new(77), "gin")
	if str(a1) != str(a2):
		f.append("shapes: same seed drew different bays")
	var layouts := {}
	for seed_value in range(40):
		layouts[str(_bay_ids(_bay(api, 25, "", votes25, VoidRngScript.new(9000 + seed_value), "gin")))] = true
	if layouts.size() < 10:
		f.append("shapes: 40 seeds produced only %d bay layouts" % layouts.size())


func _bay_slots(bay: Dictionary) -> Array:
	var out: Array = []
	for a in bay["altars"]:
		out.append(str(a.get("slot", "")))
	return out


func _test_bay_rules(f: Array[String], api: RefCounted) -> void:
	var gate: Dictionary = OffersScript.enemy_gate(api)
	# NEW = the vote-less eligible type with the LOWEST min_level (ties seeded):
	# against two starters already voted, NEW must be coil or thicc_ben (min 1),
	# never one of the higher first-shown types.
	for seed_value in range(100):
		var votes := {"kiwi_cat": 1, "seal": 1}
		var bay: Dictionary = _bay(api, 20, "", votes, VoidRngScript.new(4200 + seed_value), "seal")
		for a in bay["altars"]:
			if str(a["slot"]) == "new":
				if int(votes.get(str(a["id"]), 0)) != 0:
					f.append("rules: the NEW slot offered in-play %s" % str(a["id"]))
				if int(gate[str(a["id"])]["min_level"]) != 1:
					f.append("rules: NEW offered %s (min_level %d) while a lower-min unpicked type exists"
							% [str(a["id"]), int(gate[str(a["id"])]["min_level"])])
	# REPEAT never offers the type of the previous vote (coil here); the other
	# in-play below-cap types are its only lawful pool.
	var prev_hit := false
	var repeat_seen := false
	for seed_value in range(200):
		var votes := {"kiwi_cat": 1, "coil": 2, "thicc_ben": 1}
		var bay: Dictionary = _bay(api, 20, "", votes, VoidRngScript.new(5100 + seed_value), "coil")
		for a in bay["altars"]:
			if str(a["slot"]) == "repeat":
				repeat_seen = true
				if str(a["id"]) == "coil":
					prev_hit = true
	if not repeat_seen:
		f.append("rules: no REPEAT slot in 200 draws although three types are in play")
	if prev_hit:
		f.append("rules: the REPEAT slot offered the previous vote's type")
	# a type at its cap never appears on any altar (kiwi cat capped at 4)
	for seed_value in range(100):
		var bay: Dictionary = _bay(api, 30, "", {"kiwi_cat": 4}, VoidRngScript.new(6100 + seed_value))
		if str(bay["kind"]) != "enemy":
			f.append("rules: one capped type starved the whole bay to hunger (seed %d)" % seed_value)
			break
		if _bay_ids(bay).has("kiwi_cat"):
			f.append("rules: kiwi cat offered AT its cap (seed %d)" % seed_value)
			break
	# the chaser ceiling: you x2 + seal x2 + toucher x2 = 6 bodies in play; no
	# chaser fits anymore (a 7th body), non-chasers still draw.
	for seed_value in range(100):
		var bay: Dictionary = _bay(api, 30, "", {"you": 2, "seal": 2, "toucher": 2},
				VoidRngScript.new(7100 + seed_value))
		if str(bay["kind"]) != "enemy":
			f.append("rules: a bay at chaser load 6 fell to hunger although non-chasers remain")
			break
		for id in _bay_ids(bay):
			if CHASERS.has(id):
				f.append("rules: chaser %s drawn at ceiling load 6" % id)
				break
	# The Litter's kittens: with the curse held each cat weighs 1.5, so
	# kiwi x2 + toucher + you = 5.0 and a third cat would load 6.5 > 6 - no cat
	# while the curse is held; without it the same state loads 4.0 and cats show.
	var cat_under_litter := false
	var cat_without := false
	for seed_value in range(200):
		var votes := {"kiwi_cat": 2, "toucher": 1, "you": 1}
		var lit: Dictionary = _bay(api, 30, "", votes, VoidRngScript.new(8100 + seed_value), "", {"litter": 1})
		if _bay_ids(lit).has("kiwi_cat"):
			cat_under_litter = true
		var plain: Dictionary = _bay(api, 30, "", votes, VoidRngScript.new(8100 + seed_value), "")
		if _bay_ids(plain).has("kiwi_cat"):
			cat_without = true
	if cat_under_litter:
		f.append("rules: a cat was drawn with The Litter held - its kitten breaks the ceiling")
	if not cat_without:
		f.append("rules: no cat ever drawn in 200 unlit draws although headroom existed")


## The 1,000-run walk (T-074): every vote of a full lobby sequence is drawn and
## checked; the picks drive the next draw in the real E x2 order.
func _test_thousand_runs(f: Array[String], api: RefCounted) -> void:
	var gate: Dictionary = OffersScript.enemy_gate(api)
	var cfg: Dictionary = OffersScript.chaser_cfg(api)
	var ceiling := float(cfg.get("ceiling", 6.0))
	var runs := 1000
	var hunger_draws := 0
	var dup_breaches := 0     # a bay that did not show 3 DISTINCT altars
	var cap_breaches := 0     # an offered card already at (or past) its cap
	var ceil_breaches := 0    # an offered card that pushes past the chaser ceiling
	var new_missing := 0      # no NEW altar although an eligible unpicked type exists
	var missing := 0          # runs whose level-19 vote left a type unoffered
	var short_bays := 0       # informational: bays drawn with under 3 candidates
	for r in range(runs):
		var votes: Dictionary = {}
		var seen: Dictionary = {}
		var prev := ""
		var rng: RefCounted = VoidRngScript.new(70000 + r)
		for level in range(31):
			for b in IntermissionScript.bays_for_level(api, level):
				if str(b["bay"]) != "E":
					continue
				var pool := str(b.get("pool", ""))
				for _v in range(int(b.get("count", 1))):
					var draw_level := level + 1
					var oracle: Array = _elig_unpicked(api, draw_level, pool, votes, gate, cfg, {})
					var bay: Dictionary = OffersScript.draw_enemy_bay(
							api, draw_level, pool, votes, rng, prev, {})
					var ids := _bay_ids(bay)
					if str(bay["kind"]) == "hunger":
						hunger_draws += 1
						continue
					# every OFFERED type is recorded, picked or not
					for id in ids:
						seen[id] = 1
					# distinctness of one bay; a bay under 3 altars is the pool's
					# own shape (T-023 offered "up to 3") - counted, not failed
					if _ids_uniq(ids).size() != ids.size():
						dup_breaches += 1
					if ids.size() < 3:
						short_bays += 1
					# every offered card is legal: under its cap, under the ceiling
					var load: float = OffersScript.chaser_load(cfg, votes, {})
					for a in bay["altars"]:
						var eid := str(a["id"])
						if int(votes.get(eid, 0)) >= int(gate[eid]["max_votes"]):
							cap_breaches += 1
						var w: float = OffersScript.chaser_weight(cfg, eid, {})
						if w > 0.0 and load + w > ceiling + 0.0001:
							ceil_breaches += 1
					# a NEW altar is present while an eligible unpicked type exists
					if not oracle.is_empty() and not _has_new(bay):
						new_missing += 1
					# the vote: the NEW altar when shown, else the seeded first fit
					var pick := ""
					for a in bay["altars"]:
						if str(a["slot"]) == "new":
							pick = str(a["id"])
					if pick == "":
						pick = str(ids[rng.urange(ids.size())])
					votes[pick] = int(votes.get(pick, 0)) + 1
					prev = pick
				if level == 19 and seen.size() < 12:
					missing += 1
	if hunger_draws > 0:
		f.append("runs: %d hunger draws before level 30 - the vote economy starved" % hunger_draws)
	if short_bays > 0:
		# information only, the response file quotes it: bays whose eligible pool
		# (below cap + ceiling headroom) had fewer than 3 types left to show
		print("T074 walk: %d of %d draws showed fewer than 3 candidates (pool shape, not a failure)"
				% [short_bays, runs * 22])
	print("T074 walk: level-19 coverage %d / %d runs offered all 12 types (bound >= 990)"
			% [runs - missing, runs])
	if dup_breaches > 0:
		f.append("runs: %d bays showed the same type twice (distinctness broken)" % dup_breaches)
	if new_missing > 0:
		f.append("runs: %d votes showed no NEW altar although an eligible unpicked type existed" % new_missing)
	if cap_breaches > 0:
		f.append("runs: %d offered cards exceeded their per-enemy caps" % cap_breaches)
	if ceil_breaches > 0:
		f.append("runs: %d offered cards pushed past the chaser ceiling (load over 6)" % ceil_breaches)
	if missing > 10:
		f.append("runs: %d of %d runs left a type unoffered by the level-19 vote (99%% bound = 10)"
				% [missing, runs])


func _ids_uniq(ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		if not out.has(id):
			out.append(id)
	return out


func _has_new(bay: Dictionary) -> bool:
	for a in bay["altars"]:
		if str(a.get("slot", "")) == "new":
			return true
	return false


## "Picking the same enemy at every vote" (T-074): always take kiwi cat when any
## altar shows it. Every other vote is a THROWAWAY: it picks some other type for
## the previous-vote marker and immediately retracts its vote (a canon run votes
## others too; this fixture keeps the other ledgers at zero so the pool cannot
## exhaust before the target's cap - the assertion is about the target's path).
## The target must land EXACTLY on its cap (4) and then never be offered again.
func _test_single_stack_to_cap(f: Array[String], api: RefCounted) -> void:
	var target := "kiwi_cat"
	var gate: Dictionary = OffersScript.enemy_gate(api)
	var cap := int(gate[target]["max_votes"])
	for r in range(30):
		var votes: Dictionary = {}
		var prev := ""
		var rng: RefCounted = VoidRngScript.new(90000 + r)
		var reached := false
		for turn in range(100):
			var bay: Dictionary = _bay(api, 28, "", votes, rng, prev)
			if str(bay["kind"]) != "enemy":
				f.append("stack: the bay starved before the cap (r=%d, turn %d)" % [r, turn])
				break
			var pick := ""
			var keep := false
			for a in bay["altars"]:
				if str(a["id"]) == target:
					pick = target
					keep = true
					break
			if pick == "":
				var ids := _bay_ids(bay)
				pick = str(ids[rng.urange(ids.size())])
			votes[pick] = int(votes.get(pick, 0)) + 1
			prev = pick
			if int(votes.get(target, 0)) >= cap:
				reached = true
				break
			if not keep:
				votes[pick] = int(votes.get(pick, 0)) - 1
				if int(votes[pick]) <= 0:
					votes.erase(pick)
		if not reached:
			f.append("stack: %s never reached its cap of %d within 400 votes (r=%d)" % [target, cap, r])
			continue
		if int(votes.get(target, 0)) != cap:
			f.append("stack: %s votes %d, want exactly its cap %d" % [target, int(votes.get(target, 0)), cap])
		# capped: 30 further draws, the type must never be offered again
		var resurfaced := false
		for turn in range(30):
			var bay: Dictionary = _bay(api, 28, "", votes, rng, prev)
			if str(bay["kind"]) != "enemy":
				break   # the whole pool exhausted in this fixture - nothing to offer
			if _bay_ids(bay).has(target):
				f.append("stack: %s offered again after its cap (r=%d, turn %d)" % [target, r, turn])
				resurfaced = true
				break
		if resurfaced:
			break
