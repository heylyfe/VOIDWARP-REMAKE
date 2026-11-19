extends RefCounted
#
# T-030 kiwi cat - DESIGN.md section 5.1 (every number, +/-1 tick), the contact-kill rule
# and its death code, and the cfg/enemy.json coherence of the section 5 vote/anchor table.
# ENEMIES.md (Behavior 1:1): "slowly follow the player, death on contact."
#
#   - 1.5 u/s pursuit (17% of run speed, J6 owner ruling 2026-11-18), pursuit ceiling 0.20 ->
#     never above 1.8 u/s after ALL multipliers (SR-5; tested under overtime tier 8 + Rush Hour
#     x3 + Hunger x2);
#   - body 1.0 u tall, hit diameter 0.9 u (SR-2) - the cfg hit_diameter pin wins over the
#     TBD-art derivation (D-T030-2);
#   - feet ease toward the target's feet at 2.0 u/s (SR-1, never multiplied);
#   - Contact = kill, death code D-KIWI (DESIGN.md section 3.1 FINAL) - Last Light spent
#     first or the save masks the kill (D-057);
#   - meow every 3.0 s (180 ticks +/-1) while within 14 u - and never outside it;
#   - the Zoomies burst does not exist for the cat (J6): begin_burst never raises it above
#     the pursuit ceiling; it may not dash or lunge;
#   - spawns at tick 360 (6.0 s, D-056 fallback order; nook preferred);
#   - the hurdle answer window: a jump clears its 1.5 u reach from 0.16 s to 0.59 s (+/-1 tick);
#   - 1 PNG (ENEMIES.md: 1 base PNG); the anim block's meow telegraph is 12 ticks every 180.

const EnemyRuntime := preload("res://sim/enemy_runtime.gd")
const Util := preload("res://tests/sim_testutil.gd")
const KiwiCatScript := preload("res://content/enemies/kiwi_cat/enemy.gd")

const DT := 1.0 / 60.0
var KIWI_CFG: Dictionary = KiwiCatScript.cfg()


# Two walkable rows (z = 0 and z = 5) bridged at x = 0 - the same shape the T-027/T-071
# tests use, so round-trip reachability (D-056 step c) is known good.
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


func _world() -> Dictionary:
	return {"cols": {}, "prop_cols": {}, "pads": {}, "dais": [0, 0, 0], "glitched": {},
			"slippery": {}, "removed": {}, "kill_y": -40.0, "enemies": [], "projectiles": [],
			"hazards": []}


# [runtime, controller]; controller sits at (0.5, 0.0, 0.5), Last Light already spent (D-057).
func _runtime(lv: Dictionary) -> Array:
	var w := _world()
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	ctl.place(w)
	ctl.last_light_spent = true
	var rt = EnemyRuntime.new()
	rt.setup(lv, w, [ctl], 7)
	return [rt, ctl]


# Behavior from the shipped content script (the drop-in shape a caller uses).
func _spawn_kiwi(rt, pos: Vector3) -> Dictionary:
	return rt.spawn_at("kiwi_cat", "kiwi cat", KiwiCatScript.KiwiCatBehavior.new(),
			KIWI_CFG.duplicate(true), pos)


func _cfg_coherence(f: Array[String]) -> void:
	var text := FileAccess.get_file_as_string("res://content/enemies/kiwi_cat/enemy.json")
	var doc: Variant = JSON.parse_string(text)
	if not (doc is Dictionary):
		f.append("cfg: enemy.json unreadable")
		return
	var d := doc as Dictionary
	var stats: Dictionary = d.get("stats", {})
	_eq(f, "enemy.json id", str(d.get("id")), "kiwi_cat")
	_eq(f, "enemy.json name", str(d.get("name")), "kiwi cat")
	_eq(f, "min_level", int(d.get("min_level")), 1)
	_eq(f, "max_votes", int(d.get("max_votes")), 4)
	_eq(f, "vote_effect", str(d.get("vote_effect")), "+1 cat")
	_eq(f, "anchor_kinds", str(d.get("anchor_kinds")), str(["nook"]))
	_eq(f, "base_speed", float(stats.get("base_speed")), 1.5)
	_eq(f, "pursuit_ceiling", float(stats.get("pursuit_ceiling")), 0.2)
	_eq(f, "burst_ceiling", float(stats.get("burst_ceiling")), 0.2)
	# J6 absolute u/s (SR-5 fractions of the 9.0 u/s base run)
	_eq(f, "pursuit ceiling in u/s", float(stats.get("pursuit_ceiling")) * 9.0, 1.8)
	_eq(f, "burst ceiling in u/s", float(stats.get("burst_ceiling")) * 9.0, 1.8)
	_check_lt(f, "base_speed 1.5 u/s is clearly slower than the 9.0 u/s run",
			float(stats.get("base_speed")), 9.0)
	_eq(f, "body_height", float(stats.get("body_height")), 1.0)
	_eq(f, "hit_diameter", float(stats.get("hit_diameter")), 0.9)
	_eq(f, "meow_period_ticks", int(stats.get("meow_period_ticks")), 180)
	_eq(f, "meow_range_u", float(stats.get("meow_range_u")), 14.0)
	_eq(f, "death_code", str(stats.get("death_code")), "D-KIWI")
	_eq(f, "audio cues", str(stats.get("audio_cues")), str(["meow", "meow_double"]))
	_eq(f, "behavior cfg base_speed", float(KIWI_CFG["base_speed"]), 1.5)
	_eq(f, "behavior cfg pursuit_ceiling", float(KIWI_CFG["pursuit_ceiling"]), 0.2)
	_eq(f, "behavior cfg burst_ceiling", float(KIWI_CFG["burst_ceiling"]), 0.2)
	_eq(f, "behavior cfg pursuit ceiling in u/s", float(KIWI_CFG["pursuit_ceiling"]) * 9.0, 1.8)
	_eq(f, "behavior cfg burst ceiling in u/s", float(KIWI_CFG["burst_ceiling"]) * 9.0, 1.8)
	_eq(f, "behavior cfg hit_diameter", float(KIWI_CFG["hit_diameter"]), 0.9)
	_eq(f, "behavior cfg death_code", str(KIWI_CFG["death_code"]), "D-KIWI")
	_eq(f, "behavior cfg preferred_kind", str(KIWI_CFG["preferred_kind"]), "nook")
	# sprites: 1 PNG (ENEMIES.md), the T-083 anim block carries the binding meow timings
	var stext := FileAccess.get_file_as_string("res://content/enemies/kiwi_cat/sprites.json")
	var sdoc: Variant = JSON.parse_string(stext)
	if not (sdoc is Dictionary):
		f.append("sprites: sprites.json unreadable")
		return
	var s := sdoc as Dictionary
	_eq(f, "world_height", float(s.get("world_height")), 1.0)
	var frames: Array = ((s.get("animations", []) as Array)[0] as Dictionary).get("frames", [])
	_eq(f, "frame count", frames.size(), 1)
	var states: Dictionary = ((s.get("anim", {})) as Dictionary).get("states", {})
	_eq(f, "telegraph total_ticks", int((states.get("telegraph", {}) as Dictionary).get("total_ticks", 0)), 12)
	_eq(f, "telegraph repeat_every_ticks",
			int((states.get("telegraph", {}) as Dictionary).get("repeat_every_ticks", 0)), 180)
	_eq(f, "spawn total_ticks", int((states.get("spawn", {}) as Dictionary).get("total_ticks", 0)), 30)


func _eq(f: Array[String], what: String, got, want) -> void:
	if str(got) != str(want):
		f.append("%s: got %s, want %s" % [what, str(got), str(want)])


func _check_lt(f: Array[String], what: String, got: float, bound: float) -> void:
	if not (got < bound):
		f.append("%s: got %.3f, want < %.3f" % [what, got, bound])


func run() -> Array[String]:
	var f: Array[String] = []
	_cfg_coherence(f)
	_body_and_contact_kill(f)
	_chase_speed(f)
	_pursuit_ceiling_stack(f)
	_feet_ease(f)
	_zoomies_burst_ignored(f)
	_meow_every_3_s_within_14_u(f)
	_spawns_at_6_s(f)
	_hurdle_window(f)
	_closing_speed_arithmetic(f)
	return f


# SR-2 (FINAL): 1.0 u tall, 0.9 u hit diameter (the cfg pin, D-T030-2), and the framework
# kills on contact - with the player's feet at the cat's and Last Light already spent.
func _body_and_contact_kill(f: Array[String]) -> void:
	var pair := _runtime(_level([]))
	var rt = pair[0]
	var ctl = pair[1]
	var row := _spawn_kiwi(rt, Vector3(0.5, 0.0, 0.5))
	_eq(f, "body height", float(row["height_u"]), 1.0)
	_eq(f, "hit diameter", float(row["diameter_u"]), 0.9)
	rt.step(DT)
	if not bool(ctl.dead):
		f.append("contact: the kiwi cat's body contact did not kill (Last Light spent)")
		return
	var deaths: Array = []
	for e in rt.events:
		if e.get("e", "") == "death":
			deaths.append(e)
	if deaths.is_empty():
		f.append("contact: no death event after the contact kill")
	else:
		_eq(f, "death code", str(deaths[0].get("code")), "D-KIWI")
		_eq(f, "death killer", str(deaths[0].get("killer")), "kiwi cat")


# 1.5 u/s flat out, no multipliers running: the step covers exactly 1.5/60 u per tick.
func _chase_speed(f: Array[String]) -> void:
	var pair := _runtime(_level([]))
	var rt = pair[0]
	var row := _spawn_kiwi(rt, Vector3(25.5, 0.0, 0.5))
	rt.step(DT)
	var fb = row["float"]
	if absf(fb.h_speed - 1.5) > 1e-9:
		f.append("chase: h_speed %.6f, want 1.5" % fb.h_speed)
	var d25: float = Vector3(float(row["x"]) - 25.5, 0.0, 0.0).length()
	if absf(d25 - 1.5 / 60.0) > 1e-6:
		f.append("chase: covered %.6f u in one tick, want %.6f (1.5/60)" % [d25, 1.5 / 60.0])
	# it floats straight at the nearest player across the void (no collision on the line);
	# 25 u at 1.5 u/s takes ~1000 ticks - budget 1100
	for i in range(1100):
		rt.step(DT)
	if absf(float(row["x"]) - 0.5) > 0.1:
		f.append("chase: cat did not reach the player's tile (x=%.3f)" % row["x"])


# SR-5: the full stack (overtime tier 8 = +48%, Rush Hour x3, Hunger x2) clamps to exactly
# 1.8 u/s - the 0.20 ceiling is applied AFTER every multiplier; never above, on any tick.
func _pursuit_ceiling_stack(f: Array[String]) -> void:
	var pair := _runtime(_level([]))
	var rt = pair[0]
	rt.overtime_running = true
	rt.add_overtime_tier(8)
	rt.curse_speed_mul = 1.08 * 1.08 * 1.08 * 1.05 * 1.05
	var row := _spawn_kiwi(rt, Vector3(60.5, 0.0, 0.5))
	var fb = row["float"]
	for i in range(180):
		rt.step(DT)
		if fb.h_speed > 1.8 + 1e-9:
			f.append("ceiling: tick %d h_speed %.6f exceeds 1.8" % [i, fb.h_speed])
			return
	if absf(fb.h_speed - 1.8) > 1e-9:
		f.append("ceiling: settled at %.6f, want exactly 1.8 under the full stack" % fb.h_speed)


# SR-1: feet ease toward the target's feet at 2.0 u/s, NEVER multiplied (D-068) - not by
# overtime, not by curses. A 4 HU climb closes in ~60 ticks (+/-1).
func _feet_ease(f: Array[String]) -> void:
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
			rt.curse_speed_mul = 1.48 * 1.08 * 1.08 * 1.08
		var row := _spawn_kiwi(rt, Vector3(30.0, 0.0, 20.0))
		var ticks := 0
		while ticks < 600 and float(row["y"]) < 2.0 - 1e-6:
			rt.step(DT)
			ticks += 1
			# the easing cap per tick (2.0/60) is what binds - overtime never multiplies it
			if float(row["y"]) > float(ticks) * (2.0 / 60.0) + 1e-6:
				f.append("climb: tick %d y=%.4f exceeds the 2.0 u/s easing cap (overtime=%s)"
						% [ticks, float(row["y"]), str(overtime)])
				return
		if ticks < 59 or ticks > 61:
			f.append("climb: the 2.0 u climb took %d ticks, want ~60 (+/-1) (overtime=%s)"
					% [ticks, str(overtime)])
			return


# J6: the Zoomies burst does not exist for the cat. The behavior cancels any active burst
# on the FloatBody every tick, so begin_burst(1.6, 300) never raises it above the pursuit
# ceiling - it may not dash or lunge at any point, under any stack.
func _zoomies_burst_ignored(f: Array[String]) -> void:
	var pair := _runtime(_level([]))
	var rt = pair[0]
	var row := _spawn_kiwi(rt, Vector3(60.5, 0.0, 0.5))
	var fb = row["float"]
	fb.begin_burst(1.6, 300)
	var max_speed := 0.0
	var burst_ticks := 0
	for i in range(400):
		rt.step(DT)
		max_speed = maxf(max_speed, fb.h_speed)
		if fb.h_speed > 1.8 + 1e-9:
			burst_ticks += 1
	if burst_ticks != 0:
		f.append("burst: %d ticks above the pursuit ceiling, want 0 (J6: the cat never dashes)" % burst_ticks)
	if absf(max_speed - 1.5) > 1e-6:
		f.append("burst: peak %.6f, want exactly 1.5 (the Zoomies burst does not move the cat)" % max_speed)
	if fb.bursting() or int(fb.burst_ticks_left) != 0:
		f.append("burst: the burst state survived the behavior's cancel")
	# under the full overtime stack the pursuit clamp still holds the line at exactly 1.8
	var pair2 := _runtime(_level([]))
	var rt2 = pair2[0]
	rt2.overtime_running = true
	rt2.add_overtime_tier(8)
	rt2.curse_speed_mul = 1.08 * 1.08 * 1.08 * 1.05 * 1.05
	var row2 := _spawn_kiwi(rt2, Vector3(60.5, 0.0, 0.5))
	var fb2 = row2["float"]
	fb2.begin_burst(1.6, 180)
	var max2 := 0.0
	for i in range(200):
		rt2.step(DT)
		max2 = maxf(max2, fb2.h_speed)
	if max2 > 1.8 + 1e-9:
		f.append("burst: peak under overtime %.6f exceeds 1.8 (pursuit ceiling 0.20)" % max2)
	if absf(max2 - 1.8) > 1e-9:
		f.append("burst: peak under overtime %.6f, want exactly 1.8 (the pursuit clamp)" % max2)


# DESIGN.md section 5.1: "Meows every 3 s while within 14 u." One meow on entering the
# radius, then one every 180 ticks (+/-1) while it holds; never a meow outside the radius;
# each meow is a 12-tick "meow" telegraph (the T-083 cue).
func _meow_every_3_s_within_14_u(f: Array[String]) -> void:
	var pair := _runtime(_level([]))
	var rt = pair[0]
	var ctl = pair[1]
	ctl.x = 30.0
	ctl.z = 0.5
	var row := _spawn_kiwi(rt, Vector3(65.5, 0.0, 0.5))   # 35 u away: out of range at spawn
	var meows: Array = []
	var dist_at: Dictionary = {}
	var first_in_range := -1
	for i in range(1600):   # 1.5 u/s: in range ~tick 860, contact ~tick 1420
		var events: Array = rt.step(DT)
		var dx := float(row["x"]) - float(ctl.x)
		var dy := float(row["y"]) - float(ctl.y)
		var dz := float(row["z"]) - float(ctl.z)
		var dist := sqrt(dx * dx + dy * dy + dz * dz)
		if first_in_range < 0 and dist <= 14.0:
			first_in_range = i
		for e in events:
			if e.get("e", "") == "telegraph" and e.get("kind", "") == "meow":
				meows.append(int(e.get("tick", -1)))
				dist_at[int(e.get("tick", -1))] = dist
	if meows.is_empty():
		f.append("meow: no meow telegraph emitted in 1600 ticks (cat closes to contact)")
		return
	for t in meows:
		if float(dist_at[t]) > 14.0 + 1e-6:
			f.append("meow: meow at tick %d fired from %.3f u, want within 14 u" % [t, float(dist_at[t])])
			return
	# spacing: one meow per 180 ticks (+/-1) once inside the radius
	for i in range(1, meows.size()):
		var d: int = int(meows[i]) - int(meows[i - 1])
		if absi(d - 180) > 1:
			f.append("meow: meows %d ticks apart (ticks %d -> %d), want 180 (+/-1)"
					% [d, int(meows[i - 1]), int(meows[i])])
			return
	# D-T030-5: the first meow is the entry tick (+/-1), not one period late
	if first_in_range >= 0 and absi(int(meows[0]) - first_in_range) > 1:
		f.append("meow: first meow at tick %d, in-range since tick %d (want +/-1)"
				% [int(meows[0]), first_in_range])


# Common spawn rule (DESIGN.md section 5): the plan spawns on tick 360 (6.0 s, Early
# Bird passes 120 via opts). The diegetic spawn text carries the enemy's own name.
func _spawns_at_6_s(f: Array[String]) -> void:
	var pair := _runtime(_level([
		[4, 45, 5, 0, 1],   # a nook anchor, far side of the bridge
	]))
	var rt = pair[0]
	rt.plan("kiwi_cat", "kiwi cat", KiwiCatScript.KiwiCatBehavior.new(),
			KIWI_CFG.duplicate(true), 1)
	var spawn_tick := -1
	var spawn_text := ""
	var spawn_pos := Vector3.ZERO
	for i in range(400):
		for e in rt.step(DT):
			if e.get("e", "") == "enemy_spawn":
				spawn_tick = int(e.get("tick", -1))
				spawn_text = str(e.get("text", ""))
				spawn_pos = Vector3(float(e.get("x", 0.0)), float(e.get("y", 0.0)), float(e.get("z", 0.0)))
	if spawn_tick < 0:
		f.append("spawn: no enemy_spawn event in 400 ticks")
	else:
		if absi(spawn_tick - 360) > 1:
			f.append("spawn: spawned at tick %d, want 360 (+/-1)" % spawn_tick)
		spawn_text = str(spawn_text)
		_eq(f, "spawn text", spawn_text, "kiwi cat")
	# the spawn took the nook anchor (preferred kind), not the round-trip fallback
	if spawn_tick >= 0:
		if absf(spawn_pos.x - 45.5) > 1e-9 or absf(spawn_pos.z - 5.5) > 1e-9:
			f.append("spawn: nook not preferred (x=%.1f z=%.1f, want 45.5/5.5)"
					% [spawn_pos.x, spawn_pos.z])


# The hurdle answer window (FLEET_PACK/T-030): the spec's jump (v 12.0, g 32.0) clears the
# cat's 1.5 u reach from 0.16 s to 0.59 s of the jump - a 0.43 s window. The ENGINE integrates
# the arc at 60 Hz with semi-implicit Euler (gravity applied before the position update), so
# the realized window is ticks 9..33 (apex 2.15 u vs the continuous 2.25) - measured, not
# derived (D-T030-8). Asserts the realized window +/-1 tick, the window length ~0.43 s
# +/-1 tick, and the apex within the discretization of 2.25 u.
func _hurdle_window(f: Array[String]) -> void:
	var tiles: Array = []
	for x in range(-2, 40):
		for z in range(-2, 8):
			tiles.append([x, z, 0])
	var w := Util.world_from_tiles(tiles)
	w["dais"] = [0, 0, 0]
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	ctl.place(w)
	ctl.last_light_spent = true
	var airborne_from := -1
	var airborne_to := -1
	var apex := 0.0
	for i in range(0, 45):
		ctl.step(DT, Util.mk_in(0, 0, Util.ControllerScript.BTN_JUMP), w)
		var y := float(ctl.y)
		apex = maxf(apex, y)
		if y > 1.5:
			if airborne_from < 0:
				airborne_from = i
			airborne_to = i
	# realized window: ticks 9..33 (measured from the running controller, D-T030-8)
	if airborne_from < 0:
		f.append("hurdle: the jump never cleared 1.5 u")
		return
	if airborne_from < 8 or airborne_from > 10:
		f.append("hurdle: jump first cleared 1.5 u on tick %d (%.3f s), want 0.16 s (+/-1 tick)"
				% [airborne_from, float(airborne_from + 1) * DT])
	if airborne_to < 32 or airborne_to > 34:
		f.append("hurdle: jump last cleared 1.5 u on tick %d (%.3f s), want 0.59 s (+/-1 tick)"
				% [airborne_to, float(airborne_to + 1) * DT])
	var window_ticks := airborne_to - airborne_from + 1
	if absi(window_ticks - 25) > 1:
		f.append("hurdle: the 1.5 u-clear window is %d ticks, want ~25 (0.42 s, the discrete twin of the spec's 0.43 s)" % window_ticks)
	if absf(apex - 2.25) > 0.15:
		f.append("hurdle: jump apex %.3f u, want ~2.25 u within the discretization (realized 2.15)" % apex)


# Spec arithmetic, pinned against the shipped data: base run 9.0 + cat 1.5 = 10.5 u/s closing;
# the body overlap window is (0.9 body + 2 x 0.4 player half-width) / 10.5 u/s = ~0.16 s.
func _closing_speed_arithmetic(f: Array[String]) -> void:
	var consts: Dictionary = Util.consts()
	var run_speed := float(consts.get("run_speed", 9.0))
	var closing := run_speed + 1.5
	if absf(closing - 10.5) > 1e-9:
		f.append("closing: %.3f u/s, want 10.5 (run 9.0 + cat 1.5)" % closing)
	var window := (0.9 + 2.0 * 0.4) / closing
	if absf(window - 0.16) > 0.005:
		f.append("overlap: %.3f s, want ~0.16 s (1.7 u at 10.5 u/s)" % window)





