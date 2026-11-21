extends SceneTree
#
# collapse_reach.gd - the collapse winnability probe (cycle 4 item 10, D-B11-1).
#
#   <godot> --headless --path game --script res://tools/collapse_reach.gd
#
# Answers the owner's question - "can the sequential collapse make a level unwinnable?" -
# over seeds 1/7/42 x levels 1-30 (90 levels), using the REAL generator, the REAL collapse
# schedule (sim/collapse.gd) and the REAL gift slots. Nothing here re-implements the
# schedule: every fall time comes from CollapseScript.key_fall_tick().
#
# WIN rule. The beacon opens on the last black gift collected, so the player chooses which
# gift is last. The level is winnable if AT LEAST ONE real gift slot g satisfies
#     straight-line XZ distance(g, dais) / RUN_SPEED  <=  fall_time(g's own tile)
# - the player can stand on g, take it, and reach the dais before g's ring falls. A gift on
# the hub never falls (key_fall_tick returns -1), so it always satisfies the rule.
#
# This is a BOUND, not a proof (tickets/C4.review.md finding 3): it ignores routes, height,
# gaps, jump timing and hazards. A level it calls UNWINNABLE is unwinnable; a level it calls
# WIN still has to be played. The STRAND rule (every tile the player could be standing on
# when the beacon opens) is NOT reproduced here - it is O(tiles^2) per level and lives in
# the B10 report only.
#
# Prints one LEVEL line per level, then a SUMMARY line. Exit 1 if any level is UNWINNABLE.

const WorldScript := preload("res://app/world.gd")
const CollapseScript := preload("res://sim/collapse.gd")

const RUN_SPEED := 9.0          # u/s, the straight-line bound's speed (B10's own figure)
const TICK_HZ := 60.0
const SEEDS := [1, 7, 42]
const LEVELS := 30


func _build(seed_value: int, level: int):
	var world = WorldScript.new()
	var ledger := {
		"class": "dasher", "votes": {}, "curses": {}, "stacks": {},
		"purse": 0, "tithes": 0, "hunger": 0, "last_vote": "",
	}
	if not world.build(seed_value, level, ledger):
		world.free()
		return null
	return world


## One level's verdict. Returns {verdict, best_slack, worst_gift, zones, collapse_s, gifts}.
func _measure(world) -> Dictionary:
	var lstate = world.lstate
	var st: Dictionary = lstate.collapse
	var gifts = lstate.gifts
	var lv: Dictionary = lstate.level_dict
	if st.is_empty() or gifts == null:
		return {"verdict": "NO-COLLAPSE", "best_slack": 0.0, "worst_gift": -1,
				"zones": 0, "collapse_s": 0.0, "gifts": 0}
	# the schedule starts on the tick the beacon opens; tick 0 here means "beacon just opened"
	CollapseScript.start(st, 0)
	var beacon: Array = lv.get("beacon", [0, 0, 1])
	var dais := Vector2(float(int(beacon[0])) + 0.5, float(int(beacon[1])) + 0.5)
	var best_slack := -1e30
	var best_gift := -1
	var real := 0
	for i in gifts.slots.size():
		if not gifts.is_real(i):
			continue
		real += 1
		var p: Vector3 = gifts.slot_pos(i)
		var dist := Vector2(p.x, p.z).distance_to(dais)
		var fall_tick: int = CollapseScript.key_fall_tick(st, gifts.slot_tile_key(i))
		# a hub tile never falls: infinite time to walk home
		var fall_s := 1e30 if fall_tick < 0 else float(fall_tick) / TICK_HZ
		var slack := fall_s - dist / RUN_SPEED
		if slack > best_slack:
			best_slack = slack
			best_gift = i
	return {
		"verdict": "WIN" if best_slack >= 0.0 else "UNWINNABLE",
		"best_slack": best_slack,
		"worst_gift": best_gift,
		"zones": CollapseScript.zone_count(st),
		"collapse_s": float(CollapseScript.total_ticks(st)) / TICK_HZ,
		"gifts": real,
	}


func _process(_d: float) -> bool:
	var unwinnable := 0
	var total := 0
	var worst_slack := 1e30
	var worst_at := ""
	var zone_lo := 1 << 30
	var zone_hi := 0
	var zone_sum := 0
	var col_lo := 1e30
	var col_hi := 0.0
	var col_sum := 0.0
	for seed_value in SEEDS:
		for level in range(1, LEVELS + 1):
			var world = _build(seed_value, level)
			if world == null:
				print("LEVEL seed=%d level=%d BUILD-FAILED" % [seed_value, level])
				unwinnable += 1
				total += 1
				continue
			var m: Dictionary = _measure(world)
			world.free()
			total += 1
			var verdict := str(m["verdict"])
			if verdict != "WIN":
				unwinnable += 1
			var slack := float(m["best_slack"])
			if slack < worst_slack:
				worst_slack = slack
				worst_at = "seed %d level %d" % [seed_value, level]
			var z := int(m["zones"])
			zone_lo = mini(zone_lo, z)
			zone_hi = maxi(zone_hi, z)
			zone_sum += z
			var cs := float(m["collapse_s"])
			col_lo = minf(col_lo, cs)
			col_hi = maxf(col_hi, cs)
			col_sum += cs
			print("LEVEL seed=%d level=%d %s zones=%d collapse_s=%.1f gifts=%d best_slack=%.1f"
					% [seed_value, level, verdict, z, cs, int(m["gifts"]), slack])
	print("SUMMARY levels=%d unwinnable=%d worst_slack=%.1f at=%s zones=%d..%d mean=%.1f collapse_s=%.0f..%.0f mean=%.0f"
			% [total, unwinnable, worst_slack, worst_at, zone_lo, zone_hi,
			float(zone_sum) / float(maxi(total, 1)), col_lo, col_hi,
			col_sum / float(maxi(total, 1))])
	quit(1 if unwinnable > 0 else 0)
	return true
