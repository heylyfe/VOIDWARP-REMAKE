extends RefCounted
#
# Declarative-upgrade proof (ticket T-052; DESIGN.md section 8 table; the R4 addendum).
#
# "Declarative" = every script:false upgrade in content/upgrades/. Each is proven here by
# applying its modifiers through the REAL modifier path (core/content_api.gd
# mods_for_stacks + apply_modifiers - the section 12 math: per stat
# (base + sum of adds) x product of muls, then `set` wins) and asserting the stat delta
# against the number its DESIGN.md section 8 table row states. The expected values below
# are literals written from the table - a flipped value or a changed op in content fails
# here instead of drifting silently.
#
# Scope (the split with T-053, running in parallel on the scripted half): the 25
# script:true upgrades are T-053's and this test does not touch them. The partition is
# pinned: the script:false set on disk must be exactly the 11 ids in ROWS, so a flipped
# script flag fails loudly instead of escaping the proof - or silently doubling T-053's
# scope.
#
# Also asserted: the Athletic class multipliers (speed x1.5, air-jump height x1.3), wired
# through the real Yearn for Speed card into the real controller; and the R4 addendum,
# verbatim:
#
#   "All gold arithmetic is in integer centi-gold and rounds DOWN. A stacked price is
#    `floor(price x 1.5^n)` in whole gold. A bounty is `floor(base x (20 + level) / 20)`
#    in whole gold."
#
# Stacked prices and bounties are checked against an EXACT integer oracle (3^n / 2^n is
# dyadic, so floor(price x 1.5^n) is exactly (price x 3^n) / 2^n in integer arithmetic;
# truncating division == flooring for non-negative values) - not a pow() re-derivation of
# the implementation under test.

const ContentApiScript := preload("res://core/content_api.gd")
const StatsScript := preload("res://core/stats.gd")
const OffersScript := preload("res://sim/offers.gd")
const EconomyScript := preload("res://sim/economy.gd")
const Util := preload("res://tests/sim_testutil.gd")

# The DESIGN.md section 8 table rows for the 11 script:false upgrades, as literals:
# id -> [tier, price, max_stacks, [[stat, expected at 1 stack, expected at max stacks], ...]]
# DESIGN.md section 8 rows (all [CANON]-adjacent where marked in the table):
#   paycheck +25 g on beacon entry per stack [CANON]; yearn_for_speed +10% run speed per
#   stack [CANON] (Athletic +15% - asserted separately through the controller); long_reach
#   pickup radius +40% per stack; ledge_grace/brace/field_dressing/etc. are script:true and
#   stay with T-053.
const ROWS := {
	"bargain": ["T2", 120, 2, [["shop_price_mul", 0.9, 0.81]]],            # -10% shop prices per stack
	"defuse_kit": ["T2", 200, 3, [["defuse_chance", 0.2, 0.6]]],           # +20% per stack, cap 60%
	"early_warning": ["T2", 180, 2, [["telegraph_mul", 1.15, 1.3225]]],    # telegraphs last 15% longer per stack
	"gilded_touch": ["T2", 150, 3, [["gold_value", 2.0, 4.0]]],            # gold gift base value +1.00 g per stack
	"high_ceiling": ["T3", 320, 1, [["chain_cap", 2.5, 2.5]]],             # chain cap x2.00 -> x2.50 (set)
	"hot_streak": ["T2", 140, 2, [["chain_window", 5.0, 6.0]]],            # chain window +1.0 s per stack
	"long_reach": ["T1", 60, 3, [["pickup_radius", 1.4, 2.744]]],          # pickup radius +40% per stack
	"paycheck": ["T1", 40, 3, [["stipend_flat", 25.0, 75.0]]],             # +25 g on beacon entry per stack [CANON]
	"subspacial_barrier": ["T3", 350, 1, [["barrier_shields", 1.0, 1.0]]], # 1 shield per level, restored on beacon entry
	"sure_foot": ["T1", 70, 2, [["respawn_delay", 0.4, 0.0], ["respawn_invuln", 2.0, 3.0]]], # -0.4 s / +1.0 s per stack
	"yearn_for_speed": ["T1", 60, 4, [["run_speed", 1.1, 1.4641]]],        # +10% run speed per stack [CANON]
}

# Section 8 table: every script:true upgrade (T-053). The union of ROWS and this set is the
# 36 on disk; the partition test fails on any id outside both, so the catalog cannot grow
# past this ticket's knowledge silently.
const SCRIPTED_IDS := [
	"bounty_hunter", "brace", "cartographer", "cold_blood", "featherfall", "field_dressing",
	"insulation", "last_call", "ledge_grace", "marathon", "more", "nest_egg", "pocket_beacon",
	"quick_recovery", "radar_beacon", "radar_gifts", "radar_mines", "radar_threats",
	"skeleton_key", "slipstream", "spring_heels", "stand_fast", "straggler_scope",
	"twin_dash", "updraft",
]


func run() -> Array[String]:
	var f: Array[String] = []
	var api: RefCounted = ContentApiScript.load()
	if not bool(api.call("is_ok")):
		f.append("content api boot failed: %s" % " / ".join(api.call("boot_errors")))
		return f
	_test_partition(f, api)
	_test_table_row_identity(f, api)
	_test_stat_deltas(f, api)
	_test_athletic_multipliers(f, api)
	_test_centi_gold(f, api)
	return f
# Every script:false upgrade on disk must be exactly ROWS' ids, and vice versa; every
# script:true id must be in SCRIPTED_IDS. A flipped script flag or a new file fails here
# loudly with the id in the message. Declarative also means modifiers only: no hooks.
func _test_partition(f: Array[String], api: RefCounted) -> void:
	var on_disk_decl: Array[String] = []
	var on_disk_scripted: Array[String] = []
	for raw in api.call("upgrade_ids"):
		var id: String = str(raw)
		if bool(api.call("upgrade", id).get("script", false)):
			on_disk_scripted.append(id)
		else:
			on_disk_decl.append(id)
	on_disk_decl.sort()
	var expected: Array = ROWS.keys()
	expected.sort()
	_check(f, str(on_disk_decl) == str(expected),
		"script:false set on disk is %s, expected exactly the 11 declarative rows %s - a script flag flipped or a file was added/removed; reconcile with DESIGN.md section 8, never silently" % [str(on_disk_decl), str(expected)])
	var scripted_sorted: Array = on_disk_scripted.duplicate()
	scripted_sorted.sort()
	var scripted_expected: Array = SCRIPTED_IDS.duplicate()
	scripted_expected.sort()
	_check(f, str(scripted_sorted) == str(scripted_expected),
		"script:true set on disk is %s, expected T-053's 25 %s" % [str(scripted_sorted), str(scripted_expected)])
	for id in ROWS.keys():
		var u: Dictionary = api.call("upgrade", id)
		_check(f, not (u.get("modifiers", []) as Array).is_empty(), "%s: declarative upgrade with empty modifiers" % id)
		_check(f, (u.get("hooks", []) as Array).is_empty(), "%s: declarative upgrade carries hooks %s" % [id, str(u.get("hooks", []))])


# Tier / price / max_stacks against the section 8 table row (the "st" column included).
func _test_table_row_identity(f: Array[String], api: RefCounted) -> void:
	for id in ROWS.keys():
		var u: Dictionary = api.call("upgrade", id)
		var row: Array = ROWS[id]
		_check(f, str(u.get("tier", "")) == str(row[0]), "%s: tier %s, DESIGN.md section 8 says %s" % [id, str(u.get("tier", "")), str(row[0])])
		_check(f, int(u.get("price", -1)) == int(row[1]), "%s: price %s, DESIGN.md section 8 says %d" % [id, str(u.get("price", "?")), int(row[1])])
		_check(f, int(u.get("max_stacks", -1)) == int(row[2]), "%s: max_stacks %s, DESIGN.md section 8 says %d" % [id, str(u.get("max_stacks", "?")), int(row[2])])


# The stat delta, through the real modifier path, at 1 stack and at max stacks.
# Zero stacks must yield nothing (mods_for_stacks), and a stat the path did not touch
# is a hard failure (it means the file names a stat the path dropped silently).
func _test_stat_deltas(f: Array[String], api: RefCounted) -> void:
	var ctx := {"phase": "", "class": ""}
	for id in ROWS.keys():
		var u: Dictionary = api.call("upgrade", id)
		var max_stacks := int(u.get("max_stacks", 1))
		var modifiers: Array = u.get("modifiers", [])
		for delta in ROWS[id][3]:
			var stat := str(delta[0])
			for pair in [[1, float(delta[1])], [max_stacks, float(delta[2])]]:
				var stacks: int = int(pair[0])
				var want: float = float(pair[1])
				var mods: Array = ContentApiScript.mods_for_stacks(modifiers, stacks)
				var out: Dictionary = ContentApiScript.apply_modifiers({}, mods, ctx)
				if not out.has(stat):
					f.append("%s x%d: the modifier path left stat '%s' untouched" % [id, stacks, stat])
					continue
				_check(f, absf(float(out[stat]) - want) <= 1e-9,
					"%s x%d: %s = %.6f, DESIGN.md section 8 row says %.6f" % [id, stacks, stat, float(out[stat]), want])
		# 0 stacks: the canon base, nothing applied (mods_for_stacks -> [] -> empty out)
		var none: Dictionary = ContentApiScript.apply_modifiers({}, ContentApiScript.mods_for_stacks(modifiers, 0), ctx)
		_check(f, none.is_empty(), "%s: 0 stacks still produced modifiers %s" % [id, str(none)])
	# The canon bases the rows start from (DESIGN.md sections 3.1/3.2/8, core/stats.gd DEFAULTS)
	_check(f, absf(float(StatsScript.DEFAULTS["chain_cap"]) - 2.0) <= 1e-9, "DEFAULTS chain_cap drifted from the section 3.2 x2.00 base")
	_check(f, absf(float(StatsScript.DEFAULTS["respawn_delay"]) - 0.8) <= 1e-9, "DEFAULTS respawn_delay drifted from the section 3.1 0.8 s base")
	_check(f, absf(float(StatsScript.DEFAULTS["defuse_chance"]) - 0.0) <= 1e-9, "DEFAULTS defuse_chance drifted from 0.0 (no Defuse Kit, no defuse)")
	# Defuse Kit cap 60% is structural: 3 stacks max x +0.2 = 0.6, asserted exactly
	var u: Dictionary = api.call("upgrade", "defuse_kit")
	var capped: Dictionary = ContentApiScript.apply_modifiers({}, ContentApiScript.mods_for_stacks(u.get("modifiers", []), 3), ctx)
	_check(f, absf(float(capped["defuse_chance"]) - 0.6) <= 1e-9, "defuse_kit at max stacks = %.6f, the section 8 cap is 0.60" % float(capped["defuse_chance"]))
# Athletic (DESIGN.md section 4 [CANON]): speed upgrades are x1.5 as strong; double-jump
# upgrades give x1.3 height. Values come from data/player.json's athletic block through the
# real load_constants() path, and the x1.5 half is wired end-to-end: the ACTUAL Yearn for
# Speed card through the modifier path into the actual controller.
func _test_athletic_multipliers(f: Array[String], api: RefCounted) -> void:
	var c: Dictionary = Util.consts()
	_check(f, absf(float(c["athletic_speed_upgrade_mult"]) - 1.5) <= 1e-9,
		"athletic_speed_upgrade_mult %.4f, want 1.5 (section 4 [CANON])" % float(c["athletic_speed_upgrade_mult"]))
	_check(f, absf(float(c["athletic_air_jump_mult"]) - 1.3) <= 1e-9,
		"athletic_air_jump_mult %.4f, want 1.3 (section 4 [CANON])" % float(c["athletic_air_jump_mult"]))
	_check(f, absf(float(c["athletic_run_mult"]) - 1.15) <= 1e-9,
		"athletic_run_mult %.4f, want 1.15 (section 4 [CANON])" % float(c["athletic_run_mult"]))
	# one Yearn for Speed card, through the modifier path: +10% raw, +15% on Athletic
	var u: Dictionary = api.call("upgrade", "yearn_for_speed")
	var out: Dictionary = ContentApiScript.apply_modifiers({}, ContentApiScript.mods_for_stacks(u.get("modifiers", []), 1), {"phase": "", "class": ""})
	var card: float = float(out["run_speed"]) - 1.0
	_check(f, absf(card - 0.1) <= 1e-9, "yearn_for_speed x1 through the modifier path gave +%.4f, want +0.1" % card)
	var w := _flat(40)
	var ctl = Util.ControllerScript.new()
	ctl.setup("athletic", c)
	ctl.place(w)
	ctl.apply_speed_upgrade(card)
	Util.run_ticks(ctl, w, 30, func(_c2, _i): return Util.mk_in(1, 0))
	_check(f, absf(ctl.vx - 11.70) <= 0.05,
		"athletic + one Yearn for Speed card: vx %.4f, want 11.70 (9.0 x (1.15 + 0.10 x 1.5))" % ctl.vx)
	# dasher control: the same card at x1.0 strength: 9.0 x 1.10 = 9.90
	var w2 := _flat(40)
	var dasher = Util.ControllerScript.new()
	dasher.setup("dasher", Util.consts())
	dasher.place(w2)
	dasher.apply_speed_upgrade(card)
	Util.run_ticks(dasher, w2, 30, func(_c2, _i): return Util.mk_in(1, 0))
	_check(f, absf(dasher.vx - 9.90) <= 0.05,
		"dasher + one Yearn for Speed card: vx %.4f, want 9.90 (9.0 x 1.10)" % dasher.vx)
	# air-jump height x1.3: athletic launches at 12 x 1.3 = 15.6 (read after one tick of gravity)
	var wa := _flat(6)
	var air = Util.ControllerScript.new()
	air.setup("athletic", c)
	air.place(wa)
	air.apply_double_jump(1.0)
	air.grounded = false
	air.vy = -5.0
	air.step(Util.DT, Util.mk_in(0, 0, Util.ControllerScript.BTN_JUMP), wa)
	var want_air: float = 12.0 * 1.3 - float(c["gravity"]) * Util.DT
	_check(f, absf(air.vy - want_air) <= 0.02,
		"athletic air-jump vy %.4f, want %.4f (12 x 1.3 - g*dt)" % [air.vy, want_air])
	# dasher control: no x1.3, launches at 12.0
	var wd := _flat(6)
	var da = Util.ControllerScript.new()
	da.setup("dasher", Util.consts())
	da.place(wd)
	da.apply_double_jump(1.0)
	da.grounded = false
	da.vy = -5.0
	da.step(Util.DT, Util.mk_in(0, 0, Util.ControllerScript.BTN_JUMP), wd)
	var want_dash: float = 12.0 - float(c["gravity"]) * Util.DT
	_check(f, absf(da.vy - want_dash) <= 0.02,
		"dasher air-jump vy %.4f, want %.4f (12.0 - g*dt)" % [da.vy, want_dash])


# R4 addendum: all gold arithmetic is integer centi-gold and rounds DOWN; a stacked
# price is floor(price x 1.5^n) in whole gold; a bounty is floor(base x (20 + level) / 20)
# in whole gold. data/economy.json gold_arithmetic declares the same rule; the formulas
# are pinned against an exact integer oracle over the whole catalog and all 46 curses.
func _test_centi_gold(f: Array[String], api: RefCounted) -> void:
	var ga: Dictionary = api.call("data", "economy").get("gold_arithmetic", {})
	_check(f, str(ga.get("unit", "")) == "centi_gold", "economy.json gold_arithmetic.unit = '%s', want centi_gold" % str(ga.get("unit", "")))
	_check(f, str(ga.get("rounding", "")) == "floor", "economy.json gold_arithmetic.rounding = '%s', want floor" % str(ga.get("rounding", "")))
	_check(f, str(ga.get("stacked_price", "")) == "floor(price * 1.5^stacks)",
		"economy.json stacked_price formula = '%s', want 'floor(price * 1.5^stacks)'" % str(ga.get("stacked_price", "")))
	_check(f, str(ga.get("bounty", "")) == "floor(base * (20 + level) / 20)",
		"economy.json bounty formula = '%s', want 'floor(base * (20 + level) / 20)'" % str(ga.get("bounty", "")))
	# to_centi rounds DOWN - the classic boundary: 2.675 * 100 is 267.49999... in binary
	# floating point, and a round-half-up would say 268. A negative fraction floors, too.
	_check(f, EconomyScript.to_centi(2.675) == 267,
		"to_centi(2.675) = %d, want 267 (rounds DOWN)" % EconomyScript.to_centi(2.675))
	_check(f, EconomyScript.to_centi(0.0) == 0, "to_centi(0.0) = %d, want 0" % EconomyScript.to_centi(0.0))
	_check(f, EconomyScript.to_centi(-0.01) == -1,
		"to_centi(-0.01) = %d, want -1 (floor, not truncate)" % EconomyScript.to_centi(-0.01))
	# stacked price, whole gold: floor(price x 1.5^n) - exact integer oracle (price x 3^n) / 2^n
	var checked := 0
	for raw in api.call("upgrade_ids"):
		var id: String = str(raw)
		var u: Dictionary = api.call("upgrade", id)
		var price := int(u.get("price", 0))
		var n_max := int(u.get("max_stacks", 1))
		for n in range(0, n_max + 1):
			var want: int = _dyadic_floor(price, n)
			var got := int(OffersScript.price_for(u, n))
			_check(f, got == want,
				"%s x%d: price %d, want floor(%d x 1.5^%d) = %d" % [id, n, got, price, n, want])
			checked += 1
	_check(f, checked > 36, "stacked-price oracle checked only %d (id, n) pairs" % checked)
	# pins from the section 8 table: the .5 boundary floors, never rounds
	for pin in [["gilded_touch", 3, 506], ["more", 3, 168], ["paycheck", 1, 60], ["paycheck", 3, 135], ["yearn_for_speed", 4, 303]]:
		var u: Dictionary = api.call("upgrade", str(pin[0]))
		var got := int(OffersScript.price_for(u, int(pin[1])))
		_check(f, got == int(pin[2]),
			"%s x%d: price %d, want %d (floor)" % [str(pin[0]), int(pin[1]), got, int(pin[2])])
	# bounty, whole gold: floor(base x (20 + level) / 20) - exact integer oracle over every
	# curse on disk, mixed levels (mild 20 / harsh 45 / brutal 90, data/economy.json)
	var bases := {"mild": 20, "harsh": 45, "brutal": 90}
	var levels := [0, 1, 4, 9, 17, 26, 30]
	var bchecked := 0
	for raw in api.call("curse_ids"):
		var id: String = str(raw)
		var severity := str(api.call("curse", id).get("severity", ""))
		var base: int = int(bases.get(severity, -1))
		if not _check(f, base >= 0, "%s: severity '%s' not in mild/harsh/brutal" % [id, severity]):
			continue
		for level in levels:
			var want: int = (base * (20 + int(level))) / 20   # non-negative int division == floor
			var got := int(api.call("curse_bounty", id, int(level)))
			_check(f, got == want,
				"%s bounty at level %d: %d, want floor(%d x %d / 20) = %d" % [id, int(level), got, base, 20 + int(level), want])
			bchecked += 1
	_check(f, bchecked == 46 * levels.size(),
		"bounty oracle checked %d (curse, level) pairs, want %d" % [bchecked, 46 * levels.size()])
	# pins from DESIGN.md section 7 / test_content.gd (harsh@1 = 47, mild@0 = 20)
	_check(f, int(api.call("curse_bounty", "hungry_void", 1)) == 47,
		"harsh bounty at level 1 is %d, want 47" % int(api.call("curse_bounty", "hungry_void", 1)))
	_check(f, int(api.call("curse_bounty", "unmarked", 0)) == 20,
		"mild bounty at level 0 is %d, want 20" % int(api.call("curse_bounty", "unmarked", 0)))


# floor(price * (3/2)^n) in whole gold by exact integer arithmetic: (price * 3^n) / 2^n.
# Non-negative numerator/denominator, so GDScript's truncating integer division == floor.
static func _dyadic_floor(price: int, n: int) -> int:
	var num: int = price
	var den: int = 1
	for _i in range(n):
		num *= 3
		den *= 2
	return num / den


func _flat(n: int) -> Dictionary:
	var tiles: Array = []
	for cx in range(-4, n):
		tiles.append([cx, 0, 0])
	return Util.world_from_tiles(tiles)


func _check(f: Array[String], ok: bool, msg: String) -> bool:
	if not ok:
		f.append(msg)
	return ok
