extends RefCounted
#
# test_shop_price_mul.gd - shop_price_mul has a real consumer: the lobby's U /
# REST altars price off the stats dict the world computes (Bargain drops,
# Inflation raises, neither leaves the data file's price). The mul values are
# read from the declared content files through the api; the stats dict under
# test is built by the same apply_modifiers the world runs at level build.
# No hardcoded numbers anywhere: the negative control compares against the
# price in upgrades/<id>.json via price_for's own contract.

const ContentApiScript := preload("res://core/content_api.gd")
const Intermission := preload("res://sim/intermission.gd")

# Level 1's schedule row is [E, U]: the U bay is the subject here.
const U_LEVEL := 1
const U_SEED := 77
const PURSE := 10000


func run() -> Array[String]:
	var f: Array[String] = []
	var api := ContentApiScript.load()
	if not bool(api.is_ok()):
		f.append("content api boot failed: %s" % " / ".join(api.boot_errors()))
		return f
	_test_declared_muls_read_from_files(f, api)
	_test_bargain_owned_discounts(f, api)
	_test_inflation_held_inflates(f, api)
	_test_neither_is_base_price(f, api)
	_test_setter_reprices_drawn_altars(f, api)
	_test_rng_stream_unchanged_by_setter(f, api)
	return f


## The declared modifier values, read from the content files through the api -
## every expectation below is a product of these, never a literal.
func _declared_mul(entry: Dictionary) -> float:
	var mul := 1.0
	for m in (entry.get("modifiers", []) as Array):
		var mod: Dictionary = m
		if str(mod.get("stat", "")) == "shop_price_mul":
			mul *= float(mod.get("value", 1.0))
	return mul


## The same math world.gd runs at build (content_api.apply_modifiers over the
## run's stacks and curses), so the stats dict under test is the real one.
func _stats_for(api: RefCounted, stacks: Dictionary, curses: Dictionary) -> Dictionary:
	var mods: Array = []
	var stack_ids: Array = stacks.keys()
	stack_ids.sort()
	for id in stack_ids:
		mods.append_array(ContentApiScript.mods_for_stacks(
				api.upgrade(str(id)).get("modifiers", []), int(stacks[id])))
	var curse_ids: Array = curses.keys()
	curse_ids.sort()
	for id in curse_ids:
		mods.append_array(ContentApiScript.mods_for_stacks(
				api.curse(str(id)).get("modifiers", []), int(curses[id])))
	return ContentApiScript.apply_modifiers({}, mods, {"phase": "", "class": ""})


func _u_bay(lb: RefCounted) -> Variant:
	for bay in lb.bays:
		if str(bay["kind"]) == "U":
			return bay
	return null


## floor(base x 1.5^stacks x mul) mirroring price_for's operation order
## (IEEE floats). Callers pass the bay's actual discount_mul.
func _expected_price(api: RefCounted, altar: Dictionary, mul: float,
		discount_mul: float = 1.0) -> int:
	var u: Dictionary = api.upgrade(str(altar["id"]))
	var raw := float(int(u.get("price", 0)))
	raw *= pow(1.5, float(int(altar.get("stacks", 0))))
	raw *= mul * discount_mul
	return int(floor(raw))


func _check_offered_prices(f: Array[String], api: RefCounted, lb: RefCounted,
		mul: float, label: String) -> void:
	var bay = _u_bay(lb)
	if bay == null:
		f.append("%s: no U bay in the level-%d lobby" % [label, U_LEVEL])
		return
	var disc := (100.0 - float(int(bay.get("discount_pct", 0)))) / 100.0
	var altars: Array = bay["altars"]
	if altars.is_empty():
		f.append("%s: U bay drew no offers" % label)
		return
	for altar in altars:
		var want := _expected_price(api, altar, mul, disc)
		var got := int(altar["price"])
		if got != want:
			f.append("%s: %s priced %d, want floor(base x 1.5^stacks x mul=%s) = %d"
					% [label, str(altar["id"]), got, str(mul), want])


func _test_declared_muls_read_from_files(f: Array[String], api: RefCounted) -> void:
	var bargain: Dictionary = api.upgrade("bargain")
	var inflation: Dictionary = api.curse("inflation")
	if bargain.is_empty():
		f.append("content: upgrade 'bargain' unreadable")
	if inflation.is_empty():
		f.append("content: curse 'inflation' unreadable")
	if _declared_mul(bargain) == 1.0:
		f.append("content: bargain carries no shop_price_mul - the fixture is not exercising the declaration")
	if _declared_mul(inflation) == 1.0:
		f.append("content: inflation carries no shop_price_mul - the fixture is not exercising the declaration")


## With Bargain owned (1 stack), every U offer is discounted by the declared
## per-stack percentage, computed from his modifiers in the file.
func _test_bargain_owned_discounts(f: Array[String], api: RefCounted) -> void:
	var stacks := {"bargain": 1}
	var stats := _stats_for(api, stacks, {})
	var bargain_mul := _declared_mul(api.upgrade("bargain"))
	if absf(float(stats.get("shop_price_mul", 1.0)) - bargain_mul) > 1e-6:
		f.append("bargain: stats carry shop_price_mul %s, want %s (the declared file value)"
				% [str(stats.get("shop_price_mul", 1.0)), str(bargain_mul)])
	var lb: RefCounted = Intermission.create(api, U_LEVEL, PURSE, U_SEED,
			{}, {}, stacks, "", 0, 0, "", stats)
	_check_offered_prices(f, api, lb, bargain_mul, "bargain")
	# buying must deduct the discounted price, not the base price
	var bay = _u_bay(lb)
	if bay != null and not (bay["altars"] as Array).is_empty():
		var altar: Dictionary = (bay["altars"] as Array)[0]
		var price := int(altar["price"])
		var purse_before := int(lb.purse)
		var table: Array = lb.altar_table()
		var bought := false
		for i in table.size():
			if str(table[i]["kind"]) == "offer" and str(table[i]["bay"]) == "U" \
					and int(table[i]["altar"]) == 0:
				var evs: Array = []
				if lb.apply_select(0, i, evs):
					bought = true
				break
		if not bought:
			f.append("bargain: could not buy the first U offer to check the purse deduction")
		else:
			if int(lb.purse) != purse_before - price:
				f.append("bargain: purse %d after buying at %d, want %d" % [int(lb.purse), price, purse_before - price])


## With inflation held (1 stack), every U offer rises by the declared percentage.
func _test_inflation_held_inflates(f: Array[String], api: RefCounted) -> void:
	var curses := {"inflation": 1}
	var stats := _stats_for(api, {}, curses)
	var inflation_mul := _declared_mul(api.curse("inflation"))
	if absf(float(stats.get("shop_price_mul", 1.0)) - inflation_mul) > 1e-6:
		f.append("inflation: stats carry shop_price_mul %s, want %s (the declared file value)"
				% [str(stats.get("shop_price_mul", 1.0)), str(inflation_mul)])
	var lb: RefCounted = Intermission.create(api, U_LEVEL, PURSE, U_SEED,
			{}, curses, {}, "", 0, 0, "", stats)
	_check_offered_prices(f, api, lb, inflation_mul, "inflation")


## Negative control: neither modifier held -> the price is the data file's value
## (floor(base x 1.5^stacks)), i.e. exactly the file's base price at 0 stacks.
func _test_neither_is_base_price(f: Array[String], api: RefCounted) -> void:
	var lb: RefCounted = Intermission.create(api, U_LEVEL, PURSE, U_SEED,
			{}, {}, {}, "", 0, 0, "", {})
	var bay = _u_bay(lb)
	if bay == null:
		f.append("neither: no U bay in the level-%d lobby" % U_LEVEL)
		return
	for altar in (bay["altars"] as Array):
		var u: Dictionary = api.upgrade(str(altar["id"]))
		var want := int(floor(float(int(u.get("price", 0)))
				* pow(1.5, float(int(altar.get("stacks", 0))))))
		if int(altar["price"]) != want:
			f.append("neither: %s priced %d, want the data file's %d"
					% [str(altar["id"]), int(altar["price"]), want])
		if int(altar.get("stacks", 0)) == 0 and int(altar["price"]) != int(u.get("price", 0)):
			f.append("neither: %s priced %d at 0 stacks, want the file's base price %d"
					% [str(altar["id"]), int(altar["price"]), int(u.get("price", 0))])


## The setter path (the one-line wiring the lead adds per this task): a lobby
## built WITHOUT stats gets them later, and the already-drawn altars re-price
## in place - same offers, same order, prices now reflect the mul.
func _test_setter_reprices_drawn_altars(f: Array[String], api: RefCounted) -> void:
	var lb: RefCounted = Intermission.create(api, U_LEVEL, PURSE, U_SEED,
			{}, {}, {"bargain": 1}, "", 0, 0, "")   # no p_stats: built before stats exist
	var bay = _u_bay(lb)
	if bay == null:
		f.append("setter: no U bay in the level-%d lobby" % U_LEVEL)
		return
	var ids_before: Array = []
	var prices_before: Dictionary = {}
	for altar in (bay["altars"] as Array):
		ids_before.append(str(altar["id"]))
		prices_before[str(altar["id"])] = int(altar["price"])
	var stats := _stats_for(api, {"bargain": 1}, {})
	lb.set_stats(stats)
	var ids_after: Array = []
	var mul := _declared_mul(api.upgrade("bargain"))
	for altar in (bay["altars"] as Array):
		ids_after.append(str(altar["id"]))
	if ids_before != ids_after:
		f.append("setter: the offers changed on set_stats (%s -> %s); only prices may move"
				% [str(ids_before), str(ids_after)])
	_check_offered_prices(f, api, lb, mul, "setter")


## The setter must not churn the draw stream: a reroll after set_stats draws
## exactly the shop a lobby created WITH the stats would have drawn.
func _test_rng_stream_unchanged_by_setter(f: Array[String], api: RefCounted) -> void:
	var stats := _stats_for(api, {"bargain": 1}, {})
	var with_stats: RefCounted = Intermission.create(api, U_LEVEL, PURSE, U_SEED,
			{}, {}, {"bargain": 1}, "", 0, 0, "", stats)
	var without: RefCounted = Intermission.create(api, U_LEVEL, PURSE, U_SEED,
			{}, {}, {"bargain": 1}, "", 0, 0, "")
	without.set_stats(stats)
	var bay_a = _u_bay(with_stats)
	var bay_b = _u_bay(without)
	if bay_a == null or bay_b == null:
		f.append("rng: a U bay is missing; cannot compare streams")
		return
	var ids_a: Array = []
	var ids_b: Array = []
	for altar in (bay_a["altars"] as Array):
		ids_a.append(str(altar["id"]))
	for altar in (bay_b["altars"] as Array):
		ids_b.append(str(altar["id"]))
	if ids_a != ids_b:
		f.append("rng: set_stats re-drew the shop (%s -> %s)" % [str(ids_a), str(ids_b)])
	var evs: Array = []
	var table: Array = without.altar_table()
	for i in table.size():
		if str(table[i]["kind"]) == "reroll" and str(table[i]["bay"]) == "U":
			without.apply_select(0, i, evs)
			break
	var evs2: Array = []
	var table2: Array = with_stats.altar_table()
	for i in table2.size():
		if str(table2[i]["kind"]) == "reroll" and str(table2[i]["bay"]) == "U":
			with_stats.apply_select(0, i, evs2)
			break
	var after_a: Variant = _u_bay(with_stats)
	var after_b: Variant = _u_bay(without)
	var ids_a2: Array = []
	var ids_b2: Array = []
	for altar in (after_a["altars"] as Array):
		ids_a2.append(str(altar["id"]))
	for altar in (after_b["altars"] as Array):
		ids_b2.append(str(altar["id"]))
	if ids_a2 != ids_b2:
		f.append("rng: reroll after set_stats diverged (%s vs %s)" % [str(ids_a2), str(ids_b2)])

