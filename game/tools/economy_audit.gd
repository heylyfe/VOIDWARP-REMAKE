extends SceneTree
#
# Economy audit A11 (FLEET_PACK.md section 4; ticket T-022) - headless:
#
#   <godot> --headless --path game --script res://tools/economy_audit.gd
#
# Simulates 1,000 runs to level 30 with the average-player income model of DESIGN.md
# section 3.2 (one total-per-level number per level, read from data/economy.json - the
# rows already fold in the 50%-collection-at-mean-chain assumption; levels between rows
# interpolate linearly, D-T022-6) and the shop cadence of data/offering_schedule.json
# (U bays at full price, REST bays at their discount_pct, D-T022-4). The player earns,
# then at every shop the offers come from sim/offers.gd draw_shop(); the average player
# buys every offered item they can afford, in offer order.
#
# Asserted (canon bands, not to be weakened):
#   1. shops where >= 1 offered item is affordable          >= 80%
#   2. shops where all 3 offered items are affordable       <= 30%
#   3. purchases per run to level 30 (average player)        18-24
#   4. purchases per run (cautious player, stipend-only income, buys the cheapest
#      affordable offer per shop, D-T022-6)                  6-10
# Prints "AUDIT OK (...)" and exits 0, or "AUDIT FAIL (...)" and exits 1.

const ContentApiScript := preload("res://core/content_api.gd")
const EconomyScript := preload("res://sim/economy.gd")
const OffersScript := preload("res://sim/offers.gd")
const VoidRngScript := preload("res://terrain/void_rng.gd")

const RUNS := 1000
const MAX_LEVEL := 30
const AVG_INCOME_SEED := 331
const CLASS_SEED_OFFSET := 9001
const CLASSES: Array[String] = ["dasher", "glider", "athletic"]

const BAND_ONE := 0.80
const BAND_ALL := 0.30
const BAND_PURCHASES_MIN := 18
const BAND_PURCHASES_MAX := 24
const BAND_CAUTIOUS_MIN := 6
const BAND_CAUTIOUS_MAX := 10


func _init() -> void:
	var api := ContentApiScript.load()
	if not api.is_ok():
		print("AUDIT FAIL (content boot refused: %s)" % " / ".join(api.boot_errors()))
		quit(1)
		return
	var failures: Array[String] = []
	_canon_preamble(failures, api)
	var avg := _simulate(failures, api, false)
	var cautious := _simulate(failures, api, true)
	var afford1 := float(avg["shops_with_1"]) / maxf(1.0, float(avg["shops"]))
	var afford3 := float(avg["shops_with_3"]) / maxf(1.0, float(avg["shops"]))
	var summ := "runs=%d shops/run=%d afford1=%.1f%% afford3=%.1f%% purchases=%.2f cautious=%.2f" % [
		RUNS, int(round(float(avg["shops"]) / RUNS)), afford1 * 100.0, afford3 * 100.0,
		float(avg["purchases"]) / RUNS, float(cautious["purchases"]) / RUNS,
	]
	if failures.is_empty():
		print("AUDIT OK (%s)" % summ)
		quit(0)
	else:
		for msg in failures:
			print("AUDIT FAIL: %s" % msg)
		print("AUDIT FAIL (%s)" % summ)
		quit(1)


## The canon constants the audit leans on must be the shipped ones (design section 3.2).
func _canon_preamble(failures: Array[String], api: RefCounted) -> void:
	var e: RefCounted = EconomyScript.create({}, api)
	if float(e.window_s) != 4.0 or int(e.cap_centi) != 200 or int(e.base_gift_centi) != 200:
		failures.append("canon drift: chain window/cap/base are %s/%d/%d, want 4.0/200/200"
				% [str(e.window_s), int(e.cap_centi), int(e.base_gift_centi)])
	if int(e.overtime_max_tier) != 8 or float(e.overtime_period_s) != 20.0:
		failures.append("canon drift: overtime max/period %d/%s, want 8/20.0"
				% [int(e.overtime_max_tier), str(e.overtime_period_s)])
	if int(EconomyScript.stipend_for(1)) != 12 or int(EconomyScript.stipend_for(30)) != 70:
		failures.append("canon drift: stipend formula")
	e.begin_gold_phase()
	int(e.tick_gold(160.0))
	if int(e.overtime_tier) != 8:
		failures.append("canon drift: 160 s of gold phase is tier %d, want 8" % int(e.overtime_tier))


## One full model pass. Cautious: stipend-only income (no gold), buys the cheapest
## affordable offer per shop. Average: full income, buys every affordable offer.
func _simulate(failures: Array[String], api: RefCounted, cautious: bool) -> Dictionary:
	var schedule: Dictionary = api.data("offering_schedule").get("levels", {})
	var shops := 0
	var shops_with_1 := 0
	var shops_with_3 := 0
	var purchases := 0
	for run in RUNS:
		var cls: String = CLASSES[int(VoidRngScript.new(VoidRngScript.mix(run, CLASS_SEED_OFFSET)).urange(3))]
		var purse := 0
		var stacks := {}
		for level in range(1, MAX_LEVEL + 1):
			purse += _income(api, level, cautious)
			var raw_bays: Variant = schedule.get(str(level), [])
			if not (raw_bays is Array):
				continue
			for bay_v in raw_bays:
				var bay: Dictionary = bay_v
				var kind := str(bay.get("bay", ""))
				if kind != "U" and kind != "REST":
					continue
				var discount := 1.0
				if kind == "REST":
					discount = (100.0 - float(bay.get("discount_pct", 0))) / 100.0
				var draw_rng: RefCounted = VoidRngScript.new(VoidRngScript.mix(VoidRngScript.mix(run, AVG_INCOME_SEED), level))
				var shop: Dictionary = OffersScript.draw_shop(api, level, purse, stacks, cls, draw_rng, discount)
				shops += 1
				var affordable := 0
				var cheapest_offer := {}
				for o in shop["offers"]:
					var price := int(o["price"])
					if price > purse:
						continue
					affordable += 1
					if cheapest_offer.is_empty() or price < int(cheapest_offer.get("price", 0)):
						cheapest_offer = o
				if affordable >= 1:
					shops_with_1 += 1
				if affordable >= 3:
					shops_with_3 += 1
				if cautious:
					if not cheapest_offer.is_empty():
						purse -= int(cheapest_offer["price"])
						purchases += 1
						_bump(stacks, str(cheapest_offer["id"]))
				else:
					for o in shop["offers"]:
						var price := int(o["price"])
						if price <= purse:
							purse -= price
							purchases += 1
							_bump(stacks, str(o["id"]))
						else:
							break
	var mean := float(purchases) / RUNS
	if not cautious:
		if float(shops_with_1) / maxf(1.0, float(shops)) < BAND_ONE:
			failures.append("afford >=1 band missed: %.1f%% < %.0f%%"
					% [100.0 * shops_with_1 / maxf(1.0, shops), BAND_ONE * 100.0])
		if float(shops_with_3) / maxf(1.0, float(shops)) > BAND_ALL:
			failures.append("afford all-3 band missed: %.1f%% > %.0f%%"
					% [100.0 * shops_with_3 / maxf(1.0, shops), BAND_ALL * 100.0])
		if mean < BAND_PURCHASES_MIN or mean > BAND_PURCHASES_MAX:
			failures.append("purchases per run %.2f outside 18-24" % mean)
	else:
		if mean < BAND_CAUTIOUS_MIN or mean > BAND_CAUTIOUS_MAX:
			failures.append("cautious purchases per run %.2f outside 6-10" % mean)
	return {"shops": shops, "shops_with_1": shops_with_1, "shops_with_3": shops_with_3, "purchases": purchases}


## Marks the bought stack so max-stacked items stop being drawn.
func _bump(stacks: Dictionary, id: String) -> void:
	stacks[id] = int(stacks.get(id, 0)) + 1


## Total gold per level: the income model row (stipend + gold already inside), linearly
## interpolated between rows; cautious collects no gold, only the stipend.
func _income(api: RefCounted, level: int, cautious: bool) -> int:
	var rows: Array = api.data("economy").get("gold_phase", {}).get("income_model_average_player", {}).get("rows", [])
	if rows.is_empty():
		return 0
	var prev: Dictionary = rows[0]
	if level <= int(prev["level"]):
		return int(prev["stipend"]) if cautious else int(prev["total_per_level"])
	for i in range(1, rows.size()):
		var row: Dictionary = rows[i]
		var hi := int(row["level"])
		if level < hi:
			var t := float(level - int(prev["level"])) / float(hi - int(prev["level"]))
			var val: float
			if cautious:
				val = lerp(float(int(prev["stipend"])), float(int(row["stipend"])), t)
			else:
				val = lerp(float(int(prev["total_per_level"])), float(int(row["total_per_level"])), t)
			return int(floor(val))
		prev = row
	return int(prev["stipend"]) if cautious else int(prev["total_per_level"])
