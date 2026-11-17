extends RefCounted
#
# Declarative curse proof (ticket T-050; DESIGN.md section 7 rows + section 12 modifier
# math, through the real modifier path in core/content_api.gd).
#
# A curse is DECLARATIVE when its JSON has "script" absent or false (the schema default;
# same convention as test_enemy_coil.gd). Every declarative curse must work through
# modifiers only: this test loads the real content, applies each declarative curse's
# modifiers (repeated per stack via mods_for_stacks) through apply_modifiers, and asserts
# the stat delta against its DESIGN.md section 7 table row:
#
#   brittle      respawn_delay 0.8 -> 1.6 (2 stacks: 2.4); respawn_invuln 1.0 -> 0.5 (2: 0.0)
#   hasty        telegraph_mul x0.85 per stack                (DESIGN.md 7.2, brutal, min 9, st 2)
#   hungry_void  void_charges_max set 1                       (7.2, harsh, min 1, st 1)
#   inflation    shop_price_mul x1.15 per stack                (7.2, mild, min 3, st 3)
#   lights_out   fill_light_range 18 -> 11                     (7.2, mild, min 2, st 1)
#   long_night   overtime_period 20 -> 14                      (7.2, harsh, min 6, st 1)
#   rush_hour    enemy_speed_mul x1.08 per stack               (7.2, harsh, min 4, st 3)
#   short_chain  chain_window 4.0 -> 3.0                       (7.2, mild, min 4, st 1)
#   tarnish      gold_value x0.8 per stack                     (7.2, mild, min 2, st 2)
#   thick_fog    fog_density 0.012 -> 0.018 (-> 0.024)         (7.2, mild, min 1, st 2)
#   weighed_down run_speed x0.9 in the gold phase only         (7.2, harsh, min 5, st 1)
#
# Every declarative curse is general-pool (requires_enemy null); the enemy-linked 24
# section-7.1 curses are all script:true (T-051's) and are only named here by the
# cross-cutting safety assertions, which run over ALL 46 curses:
#   1. no curse changes jump velocity or gravity (neither stat is in the closed list,
#      core/stats.gd, and none appears in any curse modifier);
#   2. the TOTAL run-speed reduction across every curse applied at max stacks stays
#      <= 10% in every phase (>= 0.90 multiplier). The glitched floor's -20% is the
#      toucher's enemy effect (glitch_slow_mul, D-075), NOT a curse, and is excluded
#      from that budget; asserted explicitly (no curse names glitch_slow_mul, the
#      closed default stays 0.8);
#   3. no curse touches void_charges_max except Hungry Void (op set, value 1).
#
# The declarative set is exact: a curse whose JSON gains or loses "script" (or a new
# declarative curse lands without a row here) fails the set check with instructions —
# that failure is deliberate; add the table row in the same change.

const ContentApiScript := preload("res://core/content_api.gd")
const StatsScript := preload("res://core/stats.gd")

const DECL_ROWS: Array[String] = [
	"brittle", "hasty", "hungry_void", "inflation", "lights_out", "long_night",
	"rush_hour", "short_chain", "tarnish", "thick_fog", "weighed_down",
]

# DESIGN.md section 7.2: severity / min_level / max_stacks / requires_enemy per row.
const DECL_META: Dictionary = {
	"brittle": {"severity": "harsh", "min_level": 2, "max_stacks": 2, "requires_enemy": null},
	"hasty": {"severity": "brutal", "min_level": 9, "max_stacks": 2, "requires_enemy": null},
	"hungry_void": {"severity": "harsh", "min_level": 1, "max_stacks": 1, "requires_enemy": null},
	"inflation": {"severity": "mild", "min_level": 3, "max_stacks": 3, "requires_enemy": null},
	"lights_out": {"severity": "mild", "min_level": 2, "max_stacks": 1, "requires_enemy": null},
	"long_night": {"severity": "harsh", "min_level": 6, "max_stacks": 1, "requires_enemy": null},
	"rush_hour": {"severity": "harsh", "min_level": 4, "max_stacks": 3, "requires_enemy": null},
	"short_chain": {"severity": "mild", "min_level": 4, "max_stacks": 1, "requires_enemy": null},
	"tarnish": {"severity": "mild", "min_level": 2, "max_stacks": 2, "requires_enemy": null},
	"thick_fog": {"severity": "mild", "min_level": 1, "max_stacks": 2, "requires_enemy": null},
	"weighed_down": {"severity": "harsh", "min_level": 5, "max_stacks": 1, "requires_enemy": null},
}


func run() -> Array[String]:
	var failures: Array[String] = []
	var api: RefCounted = ContentApiScript.load()
	if not _check(failures, bool(api.call("is_ok")), "content api boot failed: %s" % " / ".join(api.call("boot_errors"))):
		return failures
	_declarative_set(failures, api)
	_table_rows(failures, api)
	_safety_jump_gravity(failures, api)
	_safety_run_speed_budget(failures, api)
	_safety_void_charges(failures, api)
	return failures


## The declarative set is exactly DECL_ROWS, and each works through modifiers only.
func _declarative_set(failures: Array[String], api: RefCounted) -> void:
	var decl: Array[String] = []
	for raw in api.call("curse_ids"):
		var id := str(raw)
		var c: Dictionary = api.call("curse", id)
		if not bool(c.get("script", false)):
			decl.append(id)
	decl.sort()
	_check(failures, decl == DECL_ROWS, "declarative curse set is %s, expected %s - a curse gained/lost \"script\": false, or a new declarative curse landed without a DECL_ROWS + table row in this test" % [str(decl), str(DECL_ROWS)])
	for id in decl:
		var c: Dictionary = api.call("curse", id)
		_check(failures, int((c.get("modifiers", []) as Array).size()) >= 1, "%s: declarative curse has no modifiers - it cannot work through modifiers only" % id)
		_check(failures, (c.get("hooks", []) as Array).is_empty(), "%s: declarative curse declares hooks - a script:false curse must work through modifiers only" % id)
	for id in decl:
		if not DECL_META.has(id):
			failures.append("%s: declarative curse has no DECL_META/table row in this test - add one (and a 7.2 check of its semantics) in the same change" % id)
			continue
		var c: Dictionary = api.call("curse", id)
		var row: Dictionary = DECL_META[id]
		if str(c.get("severity", "")) != str(row["severity"]):
			failures.append("%s: severity is %s, DESIGN.md 7.2 says %s" % [id, str(c.get("severity", "")), str(row["severity"])])
		if int(c.get("min_level", -1)) != int(row["min_level"]):
			failures.append("%s: min_level is %s, DESIGN.md 7.2 says %d" % [id, str(c.get("min_level", "")), int(row["min_level"])])
		if int(c.get("max_stacks", -1)) != int(row["max_stacks"]):
			failures.append("%s: max_stacks is %s, DESIGN.md 7.2 says %d" % [id, str(c.get("max_stacks", "")), int(row["max_stacks"])])
		var req: Variant = c.get("requires_enemy")
		if req != row["requires_enemy"]:
			failures.append("%s: requires_enemy is %s, DESIGN.md 7.2 says null (general pool)" % [id, str(req)])


## Expected stat values after applying `stacks` hangs of `id`'s modifiers, per its
## DESIGN.md section 7 row. Base values come from StatsScript.DEFAULTS (run through the
## real apply_modifiers path: base {} -> DEFAULTS lookup). weighed_down is gold-phase only.
func _expected_stats(id: String, stacks: int) -> Dictionary:
	match id:
		"brittle":  # 7.2 row: respawn delay 1.6 / 2.4 s; invuln 0.5 / 0.0 s (base 0.8 / 1.0)
			return {"respawn_delay": 0.8 + 0.8 * float(stacks), "respawn_invuln": 1.0 - 0.5 * float(stacks)}
		"hasty":  # 7.2 row: telegraph 15% shorter per stack (multiplicative, x0.85^n)
			return {"telegraph_mul": pow(0.85, float(stacks))}
		"hungry_void":  # 7.2 row: charge cap becomes 1
			return {"void_charges_max": 1.0}
		"inflation":  # 7.2 row: shop prices +15% per stack (multiplicative, x1.15^n)
			return {"shop_price_mul": pow(1.15, float(stacks))}
		"lights_out":  # 7.2 row: fill light 18 -> 11 u
			return {"fill_light_range": 11.0}
		"long_night":  # 7.2 row: overtime tier every 14 s (was 20)
			return {"overtime_period": 14.0}
		"rush_hour":  # 7.2 row: enemies +8% movement speed per stack (x1.08^n)
			return {"enemy_speed_mul": pow(1.08, float(stacks))}
		"short_chain":  # 7.2 row: chain window 4.0 -> 3.0 s
			return {"chain_window": 3.0}
		"tarnish":  # 7.2 row: gold gift value -20% per stack (x0.8^n)
			return {"gold_value": pow(0.8, float(stacks))}
		"thick_fog":  # 7.2 row: fog density 0.012 -> 0.018 (-> 0.024); +0.006 per stack
			return {"fog_density": 0.012 + 0.006 * float(stacks)}
		"weighed_down":  # 7.2 row: -10% run speed during the gold phase
			return {"run_speed": 0.9}
	return {}


func _ctx_for(id: String) -> Dictionary:
	return {"phase": "gold_phase"} if id == "weighed_down" else {}


## Apply each declarative curse at 1..max_stacks through the real modifier path and
## assert the table-row delta; also pin the no-stack and off-phase behaviours.
func _table_rows(failures: Array[String], api: RefCounted) -> void:
	for id in DECL_ROWS:
		var c: Dictionary = api.call("curse", id)
		var mods: Array = c.get("modifiers", [])
		var max_stacks := int(c.get("max_stacks", 1))
		var ctx := _ctx_for(id)
		for stacks in range(1, max_stacks + 1):
			var applied: Array = ContentApiScript.mods_for_stacks(mods, stacks)
			_check(failures, applied.size() == mods.size() * stacks, "%s: mods_for_stacks(%d) gave %d mods, expected %d" % [id, stacks, applied.size(), mods.size() * stacks])
			var out: Dictionary = ContentApiScript.apply_modifiers({}, applied, ctx)
			var expected := _expected_stats(id, stacks)
			for stat in expected:
				_check(failures, out.has(stat), "%s (%d stack, %s): stat %s absent after apply_modifiers" % [id, stacks, _phase_label(ctx), stat])
				if out.has(stat):
					_check(failures, is_equal_approx(float(out[stat]), float(expected[stat])), "%s (%d stack, %s): %s is %s, DESIGN.md 7.2 row says %s" % [id, stacks, _phase_label(ctx), stat, str(float(out[stat])), str(float(expected[stat]))])
			for stat in out:
				_check(failures, expected.has(stat), "%s (%d stack, %s): unexpected stat %s in modifier output (the 7.2 row names only %s)" % [id, stacks, _phase_label(ctx), stat, str(expected.keys())])
	# Stacks are 1-indexed in effect: zero stacks apply nothing.
	_check(failures, (ContentApiScript.mods_for_stacks([{"stat": "fog_density", "op": "add", "value": 0.006}], 0) as Array).is_empty(), "mods_for_stacks(mods, 0) must be empty")
	# weighed_down must NOT leak out of the gold phase (the 7.2 row scopes it there).
	var wd: Dictionary = api.call("curse", "weighed_down")
	for ctx_name in ["", "black_phase"]:
		var out: Dictionary = ContentApiScript.apply_modifiers({}, wd.get("modifiers", []), {"phase": ctx_name})
		_check(failures, not out.has("run_speed"), "weighed_down applied its -10%% outside the gold phase (phase '%s')" % ctx_name)
	# Hungry Void's set wins over a higher inherited cap (2), and caps at 1.
	var hv: Dictionary = api.call("curse", "hungry_void")
	var out_hv: Dictionary = ContentApiScript.apply_modifiers({"void_charges_max": 2}, hv.get("modifiers", []), {})
	_check(failures, is_equal_approx(float(out_hv.get("void_charges_max", -1.0)), 1.0), "hungry_void must set void_charges_max to 1 (got %s)" % str(out_hv.get("void_charges_max", -1.0)))


## Safety rule 1 (DESIGN.md section 7): no curse changes jump velocity or gravity. Both
## stats are absent from the closed list (core/stats.gd), so no modifier can name them;
## assert that, and that no curse names them anyway.
func _safety_jump_gravity(failures: Array[String], api: RefCounted) -> void:
	_check(failures, not StatsScript.STATS.has("jump_velocity"), "jump_velocity entered the closed stat list - section 7 forbids any curse touching it")
	_check(failures, not StatsScript.STATS.has("gravity"), "gravity entered the closed stat list - section 7 forbids any curse touching it")
	for raw in api.call("curse_ids"):
		var id := str(raw)
		var c: Dictionary = api.call("curse", id)
		for m in c.get("modifiers", []):
			var stat := str(m.get("stat", ""))
			_check(failures, stat != "jump_velocity" and stat != "gravity", "%s: modifier names %s - no curse may change jump velocity or gravity (DESIGN.md section 7 safety rule)" % [id, stat])


## Safety rule 2 (DESIGN.md section 7): total run-speed reduction <= 10% in every phase.
## Every curse's run_speed modifiers are applied together at max stacks; the result must
## stay >= 0.90x. The glitched floor's -20% is the toucher's enemy effect (glitch_slow_mul,
## D-075 / section 7), is NOT a curse, and is excluded from this budget - asserted
## explicitly below: no curse names glitch_slow_mul, and the closed default stays 0.8.
func _safety_run_speed_budget(failures: Array[String], api: RefCounted) -> void:
	var all_mods: Array = []
	for raw in api.call("curse_ids"):
		var id := str(raw)
		var c: Dictionary = api.call("curse", id)
		var mods: Array = c.get("modifiers", [])
		var names_run_speed := false
		for m in mods:
			if str(m.get("stat", "")) == "run_speed":
				names_run_speed = true
			if str(m.get("stat", "")) == "glitch_slow_mul":
				failures.append("%s: modifier names glitch_slow_mul - the glitched floor's -20%% is the toucher's enemy effect (D-075), never a curse; it must stay out of the curse run-speed budget" % id)
		if names_run_speed:
			all_mods.append_array(ContentApiScript.mods_for_stacks(mods, int(c.get("max_stacks", 1))))
	_check(failures, is_equal_approx(float(StatsScript.DEFAULTS.get("glitch_slow_mul", -1.0)), 0.8), "glitch_slow_mul default is %s, expected 0.8 (the toucher's -20%% enemy effect, D-075)" % str(StatsScript.DEFAULTS.get("glitch_slow_mul", -1.0)))
	for ctx_name in ["", "black_phase", "gold_phase"]:
		var out: Dictionary = ContentApiScript.apply_modifiers({}, all_mods, {"phase": ctx_name})
		var speed := float(out.get("run_speed", StatsScript.DEFAULTS.get("run_speed", 1.0)))
		_check(failures, speed >= 0.9, "total run-speed reduction across ALL curses at max stacks (phase '%s') is %d%% - the section 7 safety budget is 10%% (glitched floor excluded; weighed_down -10%% gold-phase is the only curse consuming it)" % [ctx_name, int(round((1.0 - speed) * 100.0))])


## Safety rule 3 (done-when): no curse touches void_charges_max except Hungry Void (cap 1).
func _safety_void_charges(failures: Array[String], api: RefCounted) -> void:
	var touchers: Array[String] = []
	for raw in api.call("curse_ids"):
		var id := str(raw)
		var c: Dictionary = api.call("curse", id)
		for m in c.get("modifiers", []):
			if str(m.get("stat", "")) == "void_charges_max":
				touchers.append(id)
				_check(failures, id == "hungry_void", "%s: touches void_charges_max - only Hungry Void may (op set, value 1)" % id)
				if id == "hungry_void":
					_check(failures, str(m.get("op", "")) == "set" and is_equal_approx(float(m.get("value", 0.0)), 1.0), "hungry_void: void_charges_max modifier must be op set value 1 (got %s %s)" % [str(m.get("op", "")), str(m.get("value", ""))])
	_check(failures, touchers.has("hungry_void"), "hungry_void lost its void_charges_max set 1 modifier - the beacon restores 1 capped at 1 (DESIGN.md 7.2)")


func _phase_label(ctx: Dictionary) -> String:
	var phase := str(ctx.get("phase", ""))
	return phase if phase != "" else "always"


func _check(failures: Array[String], ok: bool, msg: String) -> bool:
	if not ok:
		failures.append(msg)
	return ok
