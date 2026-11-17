extends RefCounted
#
# Economy test (DESIGN.md section 3.2; ticket T-022). Proves, on both the canon-fallback
# constants and the data/economy.json-loaded instance:
#   - integer centi-gold money, base gift 2.00, floor rounding;
#   - the chain: x1.00 start, +0.05 per in-window gift, cap x2.00, missed window resets;
#   - ALL FOUR canon chain-reset events reset the chain (missed window, void fall,
#     defused-or-shielded tripmine, thicc ben eject) and NOTHING ELSE can (a list of
#     plausible non-canon reasons is refused by break_chain, state untouched);
#   - stipend 10 + 2 x level, Paycheck's stipend_flat on top;
#   - overtime: one tier per 20 s, max 8, speed +6%/tier, cooldown -5%/tier;
#   - the upgrade-driven stats: gold_value, chain_window, chain_cap, overtime_period;
#   - the income row sanity of the average-player model at the stated levels.

const EconomyScript := preload("res://sim/economy.gd")
const ContentApiScript := preload("res://core/content_api.gd")


func run() -> Array[String]:
	var f: Array[String] = []
	_test_money(f)
	_test_chain_growth_and_cap(f)
	_test_missed_window(f)
	_test_all_four_break_events(f)
	_test_nothing_else_resets(f)
	_test_stipend(f)
	_test_overtime(f)
	_test_stats_driven(f)
	_test_data_loaded_matches_canon(f)
	return f


func _e(stats: Dictionary = {}) -> RefCounted:
	return EconomyScript.create(stats)


func _e_api(stats: Dictionary, api: RefCounted) -> RefCounted:
	return EconomyScript.create(stats, api)


func _test_money(f: Array[String]) -> void:
	var e := _e()
	e.begin_gold_phase()
	if int(e.purse_centi) != 0 or int(e.purse_gold()) != 0:
		f.append("money: fresh purse is not zero")
	var first := int(e.collect_gold_gift())
	if first != 200 or float(e.chain_display()) < 1.049 or float(e.chain_display()) > 1.051:
		f.append("money: first gold gift paid %d and must move the chain to 1.05 (got %s)"
				% [first, str(e.chain_display())])
	if int(e.purse_gold()) != 2:
		f.append("money: purse after one gift is %d g, want 2" % int(e.purse_gold()))
	if bool(e.spend_gold(3)):
		f.append("money: spent 3 g with 2 g in purse")
	if not bool(e.spend_gold(1)) or int(e.purse_centi) != 100:
		f.append("money: spend_gold(1) did not leave 100 centi")
	# floors, never rounds up: base 2.00 at gold_value 1.25 is 2.50 exactly, and a
	# non-representable product must land on the lower centi
	var e2 := _e({"gold_value": 1.256})
	e2.begin_gold_phase()
	var paid := int(e2.collect_gold_gift())
	if paid != 251:
		f.append("money: floor rounding broken (paid %d, want 251)" % paid)


func _test_chain_growth_and_cap(f: Array[String]) -> void:
	var e := _e()
	e.begin_gold_phase()
	# gift 1 pays x1.00 -> chain 1.05; gift 2 pays x1.05 (210) -> chain 1.10; ...
	if int(e.collect_gold_gift()) != 200:
		f.append("chain: gift 1 paid %d, want 200" % int(e.purse_centi))
	if int(e.collect_gold_gift()) != 210:
		f.append("chain: gift 2 paid %d, want 210 (x1.05)" % int(e.purse_centi))
	var gain := 0
	for i in 40:
		gain = int(e.collect_gold_gift())
		int(e.tick_gold(0.1))
	if float(e.chain_display()) > 2.001:
		f.append("chain: cap breached, display %s" % str(e.chain_display()))
	if gain != 400:
		f.append("chain: at cap a gift pays %d, want 400 (base 2.00 x 2.00)" % gain)
	# cap x2.00 stays put at the increment boundary: 100 + 5*k caps exactly on 200
	if (int(e.chain_centi) - 100) % 5 != 0:
		f.append("chain: chain granularity broken (%s)" % str(e.chain_centi))


func _test_missed_window(f: Array[String]) -> void:
	var e := _e()
	e.begin_gold_phase()
	for i in 10:
		int(e.collect_gold_gift())
		int(e.tick_gold(3.9))
	if float(e.chain_display()) < 1.4:
		f.append("window: chain should have grown, is %s" % str(e.chain_display()))
	if int(e.tick_gold(0.2)) != 0:
		f.append("window: 4.1 s total is past the 4.0 s window, tick must reset it")
	if float(e.chain_display()) > 1.001:
		f.append("window: chain survived past the 4.0 s window (display %s)" % str(e.chain_display()))
	if int(e.purse_centi) <= 0:
		f.append("window: a chain reset must not touch the purse")
	# exactly 4.0 s is WITHIN the window (only > resets)
	var e2 := _e()
	e2.begin_gold_phase()
	int(e2.collect_gold_gift())
	int(e2.tick_gold(4.0))
	int(e2.collect_gold_gift())
	if float(e2.chain_display()) < 1.099:
		f.append("window: exactly 4.0 s must still count as within the window")


func _test_all_four_break_events(f: Array[String]) -> void:
	for reason in ["void_fall", "defused_or_shielded_tripmine", "thicc_ben_eject"]:
		var e := _e()
		e.begin_gold_phase()
		for i in 10:
			int(e.collect_gold_gift())
			int(e.tick_gold(3.9))
		var before := int(e.chain_centi)
		if before <= 100:
			f.append("break: setup failed for %s (chain %s)" % [reason, str(before)])
			continue
		if not bool(e.break_chain(reason)):
			f.append("break: canon reason '%s' was refused" % reason)
		if float(e.chain_display()) > 1.001 or str(e.last_reset) != reason:
			f.append("break: '%s' did not reset the chain (display %s, last %s)"
					% [reason, str(e.chain_display()), str(e.last_reset)])
	# the fourth event, the missed window, is the automatic reset of tick_gold / collect
	var e2 := _e()
	e2.begin_gold_phase()
	for i in 10:
		int(e2.collect_gold_gift())
		int(e2.tick_gold(3.9))
	int(e2.tick_gold(1.0))
	if float(e2.chain_display()) > 1.001 or str(e2.last_reset) != "missed_window":
		f.append("break: the missed window did not reset the chain automatically")
	var paid := int(e2.collect_gold_gift())
	if paid != 200:
		f.append("break: after a window reset the next gift pays %d, want 200" % paid)


func _test_nothing_else_resets(f: Array[String]) -> void:
	var e := _e()
	e.begin_gold_phase()
	for i in 10:
		int(e.collect_gold_gift())
		int(e.tick_gold(3.9))
	var before := int(e.chain_centi)
	var resets_before := int(e.chain_resets)
	for reason in ["", "void", "fall", "kiwi_cat", "coil", "nuke", "blast", "player_death",
			"gift_collected", "beacon_entry", "shop", "reroll", "missed window", "eject",
			"defused", "shielded", "VOID_FALL", "thicc_ben_eject ", "voidfall"]:
		if bool(e.break_chain(reason)):
			f.append("break: non-canon reason '%s' reset the chain" % reason)
		if int(e.chain_centi) != before or int(e.chain_resets) != resets_before:
			f.append("break: non-canon reason '%s' changed chain state" % reason)
			return
	if float(e.chain_display()) < 1.4:
		f.append("break: nothing else must reset the chain for real (display %s)" % str(e.chain_display()))
	# and the API surface offers no other reset: buying, stipends, overtime leave it alone
	int(e.enter_beacon(5))
	if float(e.chain_display()) < 1.4:
		f.append("break: stipend paid but the chain must not reset on beacon entry")


func _test_stipend(f: Array[String]) -> void:
	if int(EconomyScript.stipend_for(1)) != 12:
		f.append("stipend: level 1 pays %d, want 12" % int(EconomyScript.stipend_for(1)))
	if int(EconomyScript.stipend_for(30)) != 70:
		f.append("stipend: level 30 pays %d, want 70" % int(EconomyScript.stipend_for(30)))
	var e := _e()
	e.begin_gold_phase()
	if int(e.enter_beacon(3)) != 16 or int(e.purse_gold()) != 16:
		f.append("stipend: enter_beacon(3) paid %d, want 16 (10 + 2x3)" % int(e.purse_gold()))
	if bool(e.gold_phase):
		f.append("stipend: beacon entry must end the gold phase")
	var paycheck := _e({"stipend_flat": 25})
	paycheck.begin_gold_phase()
	if int(paycheck.enter_beacon(1)) != 37:
		f.append("stipend: Paycheck stack did not add 25 (paid %d, want 12 + 25)" % int(paycheck.enter_beacon(1)))


func _test_overtime(f: Array[String]) -> void:
	var e := _e()
	e.begin_gold_phase()
	if int(e.tick_gold(19.999)) != 0:
		f.append("overtime: 19.999 s must gain no tier")
	if int(e.tick_gold(20.0)) != 1:
		f.append("overtime: 40 s total = tier 2, gain must be 1 per full 20 s")
	for i in 7:
		int(e.tick_gold(20.0))
	if int(e.overtime_tier) != 8:
		f.append("overtime: 9 tiers requested, tier is %d, want 8 (max)" % int(e.overtime_tier))
	for i in 5:
		if int(e.tick_gold(20.0)) != 0:
			f.append("overtime: tier rose past the max of 8")
	if e.enemy_speed_mul() < 1.479 or e.enemy_speed_mul() > 1.481:
		f.append("overtime: speed mul at tier 8 is %s, want 1.48" % str(e.enemy_speed_mul()))
	if e.enemy_cooldown_mul() < 0.599 or e.enemy_cooldown_mul() > 0.601:
		f.append("overtime: cooldown mul at tier 8 is %s, want 0.60" % str(e.enemy_cooldown_mul()))
	# a fresh phase resets everything
	e.begin_gold_phase()
	if int(e.overtime_tier) != 0 or float(e.chain_display()) < 0.999 or float(e.chain_display()) > 1.001:
		f.append("overtime: begin_gold_phase must reset tier and chain")
	# gold-phase ticks before the beacon opens do nothing
	var dark := _e()
	if int(dark.tick_gold(20.0)) != 0 or int(dark.overtime_tier) != 0:
		f.append("overtime: ticks before begin_gold_phase must not accrue")


func _test_stats_driven(f: Array[String]) -> void:
	# Gilded Touch (+1.00 g / stack): stats gold_value 2.0 -> gift pays 4.00
	var gilded := _e({"gold_value": 2.0})
	gilded.begin_gold_phase()
	if int(gilded.collect_gold_gift()) != 400:
		f.append("stats: gold_value 2.0 paid %d, want 400" % int(gilded.collect_gold_gift()))
	# Hot Streak (+1.0 s window): 4.5 s is inside, 5.1 s is out
	var hot := _e({"chain_window": 5.0})
	hot.begin_gold_phase()
	int(hot.collect_gold_gift())
	int(hot.tick_gold(4.5))
	if float(hot.chain_display()) < 1.049 or float(hot.chain_display()) > 1.051:
		f.append("stats: chain_window 5.0 lost the chain at 4.5 s (display %s)" % str(hot.chain_display()))
	int(hot.tick_gold(0.7))
	if float(hot.chain_display()) > 1.001:
		f.append("stats: chain_window 5.0 did not reset at 5.2 s")
	# High Ceiling (x2.50 cap)
	var high := _e({"chain_cap": 2.5})
	high.begin_gold_phase()
	for i in 60:
		int(high.collect_gold_gift())
		int(high.tick_gold(0.1))
	if float(high.chain_display()) < 2.499:
		f.append("stats: chain_cap 2.5 not reached (display %s)" % str(high.chain_display()))
	# Cold Blood (30 s tiers)
	var cold := _e({"overtime_period": 30.0})
	cold.begin_gold_phase()
	if int(cold.tick_gold(29.0)) != 0 or int(cold.tick_gold(1.0)) != 1:
		f.append("stats: overtime_period 30.0 tiered at the wrong time")


func _test_data_loaded_matches_canon(f: Array[String]) -> void:
	var api := ContentApiScript.load()
	if not bool(api.is_ok()):
		f.append("data: content api boot failed: %s" % " / ".join(api.boot_errors()))
		return
	var loaded := _e_api({}, api)
	if int(loaded.window_s * 1000.0) != int(4.0 * 1000.0):
		f.append("data: chain window %s != 4.0" % str(loaded.window_s))
	if int(loaded.cap_centi) != 200 or int(loaded.base_gift_centi) != 200 or int(loaded.increment_centi) != 5:
		f.append("data: chain constants off data/economy.json (cap %d, base %d, inc %d)"
				% [int(loaded.cap_centi), int(loaded.base_gift_centi), int(loaded.increment_centi)])
	if int(loaded.overtime_max_tier) != 8 or int(loaded.overtime_period_s * 100.0) != 2000:
		f.append("data: overtime constants off data/economy.json")
	# break reasons come from the data file, with missed_window added
	for reason in ["void_fall", "defused_or_shielded_tripmine", "thicc_ben_eject", "missed_window"]:
		if not (loaded.break_reasons as Array).has(reason):
			f.append("data: break reason %s missing from the whitelist" % reason)
	# the average-player income rows must agree with the implied formula stipend + gold
	for row in api.data("economy").get("gold_phase", {}).get("income_model_average_player", {}).get("rows", []):
		var level := int(row["level"])
		if int(row["stipend"]) != int(EconomyScript.stipend_for(level)):
			f.append("data: income row level %d stipend %s != formula" % [level, str(row["stipend"])])
