extends RefCounted
#
# T-071 floater kinematics (DESIGN.md section 5; SR-1, SR-3, SR-5). The "toucher" and
# "kiwi cat" here are GENERIC floater configs carrying the SR-5 table's numbers - sim code
# and tests name no content id:
#   - at overtime tier 8 + Rush Hour x 3 a 6.75 u/s floater (ceiling 0.75) moves at exactly
#     6.75 u/s - the clamp is applied AFTER all multipliers - and its 2.0 s cycle is
#     shortened to at most 1.2 s by the tempo overflow (floor 0.6 of the base cycle);
#   - a 3.0 u/s floater (ceiling 0.40) never exceeds 3.6 u/s under the same stack;
#   - a Zoomies-style burst never exceeds 4.95 u/s (burst ceiling 0.55) and lasts at most
#     3.0 s, then falls back under the pursuit ceiling;
#   - a 4 HU climb (2.0 u) opens at least 1.0 s of vertical separation, at 2.0 u/s however
#     hard the horizontal multipliers stack (the vertical easing is NEVER multiplied);
#   - two stacked copies of one 380-tick cycle land exactly half a cycle apart, and copies
#     spawn >= 30 u apart through the D-056 fallback order (nook -> lane -> round-trip).

const EnemyRuntime := preload("res://sim/enemy_runtime.gd")

const DT := 1.0 / 60.0


# Drives the row's FloatBody straight at the nearest player, once per tick - the shape
# everyWave-3 floater behavior takes (the runtime attaches row["float"] when the cfg
# carries "base_speed").
class FloaterBehavior:
	extends EnemyRuntime.EnemyBehavior

	func tick(row: Dictionary, api, dt_ticks: int) -> void:
		var near: Dictionary = api.nearest_player(Vector3(float(row["x"]), float(row["y"]), float(row["z"])))
		if near.is_empty():
			return
		var fb: Variant = row.get("float", null)
		if fb == null:
			fb = EnemyRuntime.FloatBody.from_cfg(row["cfg"])
			row["float"] = fb
		fb.step(row, api, dt_ticks, float(near["x"]), float(near["z"]))


# A 380-ticks-cycle stalker that telegraphs "land" once per cycle - two copies must land
# half a cycle apart (SR-3 via stack_phase).
class CoilStub:
	extends EnemyRuntime.EnemyBehavior

	const CYCLE := 380.0

	func on_spawn(row: Dictionary, _api) -> void:
		var off: float = EnemyRuntime.stack_phase(CYCLE, int(row["copy_index"]), int(row["copies"]))
		row["left"] = int(off) if int(off) > 0 else int(CYCLE)

	func tick(row: Dictionary, api, dt_ticks: int) -> void:
		row["left"] = int(row["left"]) - dt_ticks
		if int(row["left"]) <= 0:
			api.telegraph("land", {"shape": "circle", "x": float(row["x"]), "z": float(row["z"]),
					"r": 3.0}, 0)
			row["left"] = int(CYCLE)


func run() -> Array[String]:
	var f: Array[String] = []
	_pursuit_ceiling_after_all_multipliers(f)
	_tempo_overflow_and_interval(f)
	_kiwi_ceiling(f)
	_burst_bounds(f)
	_vertical_separation(f)
	_stack_phase(f)
	_coils_half_cycle_apart(f)
	_spawn_separation(f)
	return f


# A two-row walkable line (z = 0 and z = 5), bridge column at x = 0 - same shape as the
# T-027 spawn-rule level, so round-trip reachability is known good.
func _level(anchors: Array) -> Dictionary:
	var tiles: Array = []
	for x in range(0, 100):
		tiles.append([x, 0, 0, 0, 0])
		tiles.append([x, 5, 0, 0, 1])
	tiles.append([0, 1, 0, 0, 2])
	tiles.append([0, 2, 0, 0, 2])
	tiles.append([0, 3, 0, 0, 2])
	tiles.append([0, 4, 0, 0, 2])
	return {"beacon": [0, 0, 0], "spawns": [[0, 0, 0]], "anchors": anchors,
			"tiles": tiles, "props": [], "pads": []}


# [runtime, controller]; the controller sits on the spawn tile and never moves.
func _runtime(lv: Dictionary) -> Array:
	var Util := preload("res://tests/sim_testutil.gd")
	var w := {"cols": {}, "prop_cols": {}, "pads": {}, "dais": [0, 0, 0], "glitched": {},
			"slippery": {}, "removed": {}, "kill_y": -40.0, "enemies": [], "projectiles": [],
			"hazards": []}
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	ctl.place(w)
	ctl.last_light_spent = true
	var rt = EnemyRuntime.new()
	rt.setup(lv, w, [ctl], 7)
	return [rt, ctl]


func _max_stacks() -> float:
	# overtime tier 8 (+48%) x Rush Hour x3 (1.08^3) - the exact stack of the spec sentence
	return 1.08 * 1.08 * 1.08


func _pursuit_ceiling_after_all_multipliers(f: Array[String]) -> void:
	var pair := _runtime(_level([]))
	var rt = pair[0]
	var ctl = pair[1]
	rt.overtime_running = true
	rt.add_overtime_tier(8)
	rt.curse_speed_mul = _max_stacks()
	var cfg := {"base_speed": 6.75, "pursuit_ceiling": 0.75, "burst_ceiling": 1.0,
			"contact_kill": false}
	var row: Dictionary = rt.spawn_at("tbd", "TBD", FloaterBehavior.new(), cfg,
			Vector3(40.5, 0.0, 0.5))
	var fb = row["float"]
	for i in range(120):
		rt.step(DT)
		# raw would be 6.75 * 1.48 * 1.259712 = 12.58 u/s; the ceiling holds it at exactly 6.75
		if absf(fb.h_speed - 6.75) > 1e-9:
			f.append("floater: tick %d speed %.6f, want exactly 6.75 after all multipliers"
					% [i, fb.h_speed])
			return
	# the player's own position is irrelevant to the ceiling: moving the controller does not
	# change the clamp (base run speed 9.0, never the player's current speed)
	ctl.x = 20.0
	rt.step(DT)
	if absf(fb.h_speed - 6.75) > 1e-9:
		f.append("floater: speed %.6f after the player moved, want 6.75 still" % fb.h_speed)


func _tempo_overflow_and_interval(f: Array[String]) -> void:
	var pair := _runtime(_level([]))
	var rt = pair[0]
	rt.overtime_running = true
	rt.add_overtime_tier(8)
	rt.curse_speed_mul = _max_stacks()
	var cfg := {"base_speed": 6.75, "pursuit_ceiling": 0.75, "burst_ceiling": 1.0,
			"contact_kill": false}
	var row: Dictionary = rt.spawn_at("tbd", "TBD", FloaterBehavior.new(), cfg,
			Vector3(40.5, 0.0, 0.5))
	var fb = row["float"]
	rt.step(DT)
	# SR-5: the whole multiplier the ceiling removes becomes tempo, floored at 1/0.6
	if absf(fb.tempo_mul - 1.0 / 0.6) > 1e-9:
		f.append("floater: tempo_mul %.6f, want the 1/0.6 cap (1.864 raw overflow)" % fb.tempo_mul)
	var api = EnemyRuntime.Api.new()
	api.rt = rt
	api.row = row
	# the 2.0 s glitch interval: 120 ticks / 1.667 = 72 ticks, and the 0.6 floor holds it
	# there: 72 ticks = 1.2 s exactly
	var ticks: int = api.tempo_ticks(120)
	if ticks != 72:
		f.append("floater: tempo_ticks(120) = %d, want 72 (1.2 s floor)" % ticks)
	if absf(float(ticks) / 60.0 - 1.2) > 1e-9:
		f.append("floater: tempo interval %d ticks is not 1.2 s" % ticks)
	# below the ceiling there is no overflow: a mild overtime leaves tempo at 1.0
	var pair2 := _runtime(_level([]))
	var rt2 = pair2[0]
	rt2.overtime_running = true
	rt2.add_overtime_tier(2)
	var row2: Dictionary = rt2.spawn_at("tbd", "TBD", FloaterBehavior.new(),
			{"base_speed": 3.0, "pursuit_ceiling": 0.4, "contact_kill": false},
			Vector3(40.5, 0.0, 0.5))
	rt2.step(DT)
	var fb2 = row2["float"]
	if absf(fb2.tempo_mul - 1.0) > 1e-9:
		f.append("floater: tempo_mul %.6f with no overflow, want 1.0" % fb2.tempo_mul)
	if absf(fb2.h_speed - 3.0 * 1.12) > 1e-9:
		f.append("floater: speed %.6f under mild overtime, want the raw 3.36" % fb2.h_speed)


func _kiwi_ceiling(f: Array[String]) -> void:
	# overtime 8 + Rush Hour x3 + Hunger x2: raw 3.0 * 1.48 * 1.259712 * 1.1025 = 6.17 u/s,
	# the 0.40 ceiling holds the line at 3.6 - never above, at every tick
	var pair := _runtime(_level([]))
	var rt = pair[0]
	rt.overtime_running = true
	rt.add_overtime_tier(8)
	rt.curse_speed_mul = _max_stacks() * 1.05 * 1.05
	var cfg := {"base_speed": 3.0, "pursuit_ceiling": 0.4, "burst_ceiling": 0.55,
			"contact_kill": false}
	var row: Dictionary = rt.spawn_at("tbd", "TBD", FloaterBehavior.new(), cfg,
			Vector3(60.5, 0.0, 0.5))
	var fb = row["float"]
	for i in range(180):
		rt.step(DT)
		if fb.h_speed > 3.6 + 1e-9:
			f.append("floater: tick %d speed %.6f exceeds the 3.6 ceiling" % [i, fb.h_speed])
			return
	if absf(fb.h_speed - 3.6) > 1e-9:
		f.append("floater: settled speed %.6f, want exactly 3.6 under the full stack" % fb.h_speed)


func _burst_bounds(f: Array[String]) -> void:
	# Zoomies: every 12 s the body sprints at +60% for "3 s" - bounded to 0.55 x base run
	# (4.95 u/s) and 3.0 s (180 ticks), then back under the pursuit ceiling (SR-5)
	var pair := _runtime(_level([]))
	var rt = pair[0]
	var cfg := {"base_speed": 3.0, "pursuit_ceiling": 0.4, "burst_ceiling": 0.55,
			"contact_kill": false}
	var row: Dictionary = rt.spawn_at("tbd", "TBD", FloaterBehavior.new(), cfg,
			Vector3(60.5, 0.0, 0.5))
	var fb = row["float"]
	# drive the burst directly: the Zoomies script curse calls begin_burst on its tick
	fb.begin_burst(1.6, 300)
	var burst_ticks := 0
	var max_speed := 0.0
	for i in range(400):
		rt.step(DT)
		max_speed = maxf(max_speed, fb.h_speed)
		if fb.h_speed > 3.6 + 1e-9:
			burst_ticks += 1
	if max_speed > 4.95 + 1e-9:
		f.append("floater: burst speed %.6f exceeds 4.95 (burst ceiling 0.55)" % max_speed)
	if absf(max_speed - 4.8) > 1e-6:
		f.append("floater: burst speed %.6f, want 3.0 * 1.6 = 4.8 under the cap" % max_speed)
	if burst_ticks != 180:
		f.append("floater: burst lasted %d ticks above the ceiling, want 180 (3.0 s)" % burst_ticks)
	# with the full overtime stack the burst is clamped to exactly 4.95 - never above
	var pair2 := _runtime(_level([]))
	var rt2 = pair2[0]
	rt2.overtime_running = true
	rt2.add_overtime_tier(8)
	rt2.curse_speed_mul = _max_stacks()
	var row2: Dictionary = rt2.spawn_at("tbd", "TBD", FloaterBehavior.new(), cfg,
			Vector3(60.5, 0.0, 0.5))
	var fb2 = row2["float"]
	fb2.begin_burst(1.6, 180)
	var max2 := 0.0
	for i in range(200):
		rt2.step(DT)
		max2 = maxf(max2, fb2.h_speed)
	if max2 > 4.95 + 1e-9:
		f.append("floater: burst under overtime hit %.6f, over the 4.95 bound" % max2)
	if absf(max2 - 4.95) > 1e-9:
		f.append("floater: burst under overtime peaked at %.6f, want the 4.95 cap" % max2)
	if fb2.burst_ticks_left != 0 or fb2.bursting():
		f.append("floater: burst still running after its 180-tick cap")


func _vertical_separation(f: Array[String]) -> void:
	# a 4 HU climb = 2.0 u; at 2.0 u/s it buys exactly 1.0 s of vertical separation - the
	# same 60 ticks however hard the horizontal multipliers stack (D-068: never multiplied)
	for overtime in [false, true]:
		var pair := _runtime(_level([]))
		var rt = pair[0]
		var ctl = pair[1]
		ctl.x = 20.0
		ctl.y = 2.0
		ctl.z = 20.0
		if overtime:
			rt.overtime_running = true
			rt.add_overtime_tier(8)
			rt.curse_speed_mul = _max_stacks()
		var cfg := {"base_speed": 6.75, "pursuit_ceiling": 0.75, "burst_ceiling": 1.0,
				"contact_kill": false}
		var row: Dictionary = rt.spawn_at("tbd", "TBD", FloaterBehavior.new(), cfg,
				Vector3(30.0, 0.0, 20.0))
		var fb = row["float"]
		var ticks := 0
		while ticks < 600 and float(row["y"]) < 2.0 - 1e-6:
			rt.step(DT)
			ticks += 1
			if fb.h_speed > 6.75 + 1e-9 or (not overtime and absf(fb.h_speed - 6.75) > 1e-9):
				f.append("floater: horizontal speed %.6f during the climb, want 6.75"
						% fb.h_speed)
				return
		if ticks < 60:
			f.append("floater: the 4 HU climb closed in %d ticks, want >= 60 (1.0 s)" % ticks)
			return
		if ticks > 61:
			f.append("floater: the 4 HU climb took %d ticks, want ~60 (2.0 u at 2.0 u/s)" % ticks)
			return
		# the horizontal chase never paused for the climb: 6.75 u covered in the same second
		var left: float = 30.0 - float(row["x"])
		if absf(left - 6.75) > 1e-3:
			f.append("floater: covered %.4f u horizontally while climbing, want ~6.75" % left)
			return


func _stack_phase(f: Array[String]) -> void:
	# SR-3 / F7: copy k of n starts its cycle offset by k/n of the cycle length
	if absf(EnemyRuntime.stack_phase(6.35, 1, 2) - 3.175) > 1e-12:
		f.append("floater: stack_phase(6.35, 1, 2) != 3.175")
	if absf(EnemyRuntime.stack_phase(381.0, 1, 2) - 190.5) > 1e-12:
		f.append("floater: stack_phase(381, 1, 2) != 190.5")
	if absf(EnemyRuntime.stack_phase(381.0, 2, 3) - 254.0) > 1e-12:
		f.append("floater: stack_phase(381, 2, 3) != 254")
	for k in range(3):
		if absf(EnemyRuntime.stack_phase(100.0, k, 3) - 100.0 * float(k) / 3.0) > 1e-12:
			f.append("floater: stack_phase(100, %d, 3) wrong" % k)
	if EnemyRuntime.stack_phase(100.0, 1, 0) != 0.0:
		f.append("floater: stack_phase with n = 0 must be 0, not a divide by zero")


func _coils_half_cycle_apart(f: Array[String]) -> void:
	# two copies of one 380-ticks cycle: their first landings sit exactly 190 ticks apart
	var pair := _runtime(_level([
		[4, 45, 5, 0, 1],
	]))
	var rt = pair[0]
	rt.plan("tbd", "TBD", CoilStub.new(),
			{"preferred_kind": "nook", "contact_kill": false, "cycle_s": 380.0 / 60.0}, 2)
	var lands: Array = []
	for i in range(361 + 400):
		for e in rt.step(DT):
			if e.get("e", "") == "telegraph" and e.get("kind", "") == "land":
				lands.append(int(e["tick"]))
			if lands.size() >= 2:
				break
		if lands.size() >= 2:
			break
	if lands.size() < 2:
		f.append("floater: %d landings recorded, want 2 (one per copy)" % lands.size())
		return
	var delta: int = absi(lands[1] - lands[0])
	if delta != 190:
		f.append("floater: the two copies landed %d ticks apart, want 190 (half of 380)" % delta)


func _spawn_separation(f: Array[String]) -> void:
	# SR-3 through the D-056 fallback order: copy 1 takes the farthest eligible nook, copy 2
	# falls through to the lane (>= 30 u from copy 1), copy 3 to the farthest round-trip tile
	var pair := _runtime(_level([
		[4, 26, 5, 0, 1],   # nook: 26.5 u from the player, in the 25..60 window
		[2, 58, 0, 0, 1],   # lane: 58 u from the player, 32 u from the nook
	]))
	var rt = pair[0]
	rt.plan("tbd", "TBD", FloaterBehavior.new(),
			{"preferred_kind": "nook", "base_speed": 3.0, "pursuit_ceiling": 0.4,
			"contact_kill": false}, 3)
	var spawns: Array = []
	var ev_all: Array = []
	for i in range(361):
		for e in rt.step(DT):
			ev_all.append(e)
	for e in ev_all:
		if e.get("e", "") == "enemy_spawn":
			spawns.append(e)
	if spawns.size() != 3:
		f.append("floater: %d spawn events, want 3 copies" % spawns.size())
		return
	if float(spawns[0]["x"]) != 26.5 or float(spawns[0]["z"]) != 5.5:
		f.append("floater: copy 1 at (%s, %s), want the nook (26.5, 5.5)"
				% [str(spawns[0]["x"]), str(spawns[0]["z"])])
	if float(spawns[1]["x"]) != 58.5 or float(spawns[1]["z"]) != 0.5:
		f.append("floater: copy 2 at (%s, %s), want the lane (58.5, 0.5)"
				% [str(spawns[1]["x"]), str(spawns[1]["z"])])
	if float(spawns[2]["x"]) != 99.5 or float(spawns[2]["z"]) != 5.5:
		f.append("floater: copy 3 at (%s, %s), want the farthest round-trip tile (99.5, 5.5)"
				% [str(spawns[2]["x"]), str(spawns[2]["z"])])
	for i in range(3):
		for j in range(i + 1, 3):
			var d: float = Vector3(float(spawns[i]["x"]) - float(spawns[j]["x"]), 0.0,
					float(spawns[i]["z"]) - float(spawns[j]["z"])).length()
			if d < 30.0 - 1e-6:
				f.append("floater: copies %d and %d are %.3f u apart, want >= 30" % [i, j, d])
	# no anchors at all: both copies ride step (c) - the farthest tile, then the farthest
	# tile >= 30 u from it (this is the case T-027's step (c) got wrong: it kept the
	# separation check against the player, so both copies landed 5 u apart at the far end)
	var pair2 := _runtime(_level([]))
	var rt2 = pair2[0]
	rt2.plan("tbd", "TBD", FloaterBehavior.new(),
			{"base_speed": 3.0, "pursuit_ceiling": 0.4, "contact_kill": false}, 2)
	var spawns2: Array = []
	for i in range(361):
		for e in rt2.step(DT):
			if e.get("e", "") == "enemy_spawn":
				spawns2.append(e)
	if spawns2.size() != 2:
		f.append("floater: %d spawn events without anchors, want 2" % spawns2.size())
		return
	if float(spawns2[0]["x"]) != 99.5 or float(spawns2[0]["z"]) != 5.5:
		f.append("floater: copy 1 at (%s, %s), want the farthest tile (99.5, 5.5)"
				% [str(spawns2[0]["x"]), str(spawns2[0]["z"])])
	if float(spawns2[1]["x"]) != 69.5 or float(spawns2[1]["z"]) != 5.5:
		f.append("floater: copy 2 at (%s, %s), want the farthest tile >= 30 u away (69.5, 5.5)"
				% [str(spawns2[1]["x"]), str(spawns2[1]["z"])])
