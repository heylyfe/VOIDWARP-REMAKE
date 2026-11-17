extends RefCounted
#
# T-071 addition (research/fable-tickets.md section 5): ranged-attack system rules, generic
# in sim/ (no content id - the Wave-3 behaviors adopt these helpers):
#   - D-064 volley gap: a 7-ball burst arrives as 3 + 3 + 1, balls inside a volley 0.15 s
#     (9 ticks) apart, consecutive volleys 0.75 s (45 ticks) apart start to start;
#   - D-064 salvo life limit: one salvo - tracking including EVERY restart after a broken
#     lock, plus the descent - never outlives 360 ticks from its first tracking tick;
#   - D-064 blocking: a descending missile over a tall pad detonates ON the pad (the tile
#     slab stops it), not at the ground below.

const EnemyRuntime := preload("res://sim/enemy_runtime.gd")

const DT := 1.0 / 60.0


# Fires one volley-clock burst through the real runtime: on its first tick it starts a
# 7-ball burst; every tick it releases whatever the clock schedules as projectiles.
class RangedBehavior:
	extends EnemyRuntime.EnemyBehavior

	func on_spawn(row: Dictionary, _api) -> void:
		row["age"] = 0
		row["vc"] = EnemyRuntime.VolleyClock.new()

	func tick(row: Dictionary, api, dt_ticks: int) -> void:
		row["age"] = int(row["age"]) + dt_ticks
		var vc = row["vc"]
		if int(row["age"]) == 1:
			vc.start(7)
		if vc.tick(dt_ticks) > 0:
			api.spawn_projectile({"name": "ball", "x": float(row["x"]), "y": float(row["y"]) + 1.0,
					"z": float(row["z"]), "vx": -22.0, "r": 0.5, "life_ticks": 180})


# One salvo, broken and restarted mid-tracking (a lock break): every 60 ticks while the
# salvo lives it launches a projectile, so the test can see where the salvo stops.
class SalvoBehavior:
	extends EnemyRuntime.EnemyBehavior

	func on_spawn(row: Dictionary, _api) -> void:
		row["age"] = 0
		row["salvo"] = EnemyRuntime.SalvoClock.new()
		row["launched"] = 0

	func tick(row: Dictionary, api, dt_ticks: int) -> void:
		row["age"] = int(row["age"]) + dt_ticks
		var salvo = row["salvo"]
		if int(row["age"]) == 1:
			salvo.start()
		if int(row["age"]) == 101:
			salvo.start()  # the restart after a broken lock: must NOT reset the budget
		var alive: bool = salvo.tick(dt_ticks)
		row["alive"] = alive
		if alive and int(row["age"]) % 60 == 0:
			row["launched"] = int(row["launched"]) + 1
			api.spawn_projectile({"name": "missile", "x": float(row["x"]), "y": float(row["y"]) + 12.0,
					"z": float(row["z"]), "vy": -8.0, "r": 0.4, "life_ticks": 600})


func run() -> Array[String]:
	var f: Array[String] = []
	_volley_plan(f)
	_volley_timing(f)
	_salvo_life_limit(f)
	_missile_on_spire_pad(f)
	return f


# [runtime, controller] over a flat ground strip plus one tall pad column at (10, 5)
# (8 HU tall: top at 4.0 u - the stand-in for a spire pad's top plate).
func _runtime(tiles: Array) -> Array:
	var Util := preload("res://tests/sim_testutil.gd")
	var w = Util.CollisionScript.make_world(tiles, [], [])
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	ctl.place(w)
	ctl.last_light_spent = true
	var lv := {"beacon": [0, 0, 0], "spawns": [[0, 0, 0]], "anchors": [],
			"tiles": tiles, "props": [], "pads": []}
	var rt = EnemyRuntime.new()
	rt.setup(lv, w, [ctl], 7)
	return [rt, ctl]


func _flat_tiles() -> Array:
	var tiles: Array = []
	for x in range(0, 24):
		tiles.append([x, 0, 0, 0, 0])
		tiles.append([x, 5, 0, 0, 0])
	return tiles


func _events(rt, ticks: int) -> Array:
	var out: Array = []
	for i in range(ticks):
		for e in rt.step(DT):
			out.append(e)
	return out


func _of(events: Array, kind: String) -> Array:
	var out: Array = []
	for e in events:
		if e.get("e", "") == kind:
			out.append(e)
	return out


func _volley_plan(f: Array[String]) -> void:
	var cases := [[3, [3]], [4, [3, 1]], [5, [3, 2]], [6, [3, 3]], [7, [3, 3, 1]],
			[2, [2]], [0, []]]
	for c in cases:
		var got: Array = EnemyRuntime.volley_plan(int(c[0]))
		if str(got) != str(c[1]):
			f.append("ranged: volley_plan(%s) = %s, want %s" % [str(c[0]), str(got), str(c[1])])
	# the whole plan fits in one volley-sum
	for n in range(0, 13):
		var sum := 0
		for v in EnemyRuntime.volley_plan(n):
			sum += int(v)
			if int(v) > EnemyRuntime.VOLLEY_MAX:
				f.append("ranged: volley_plan(%d) has a %d-ball volley" % [n, int(v)])
		if sum != n:
			f.append("ranged: volley_plan(%d) sums to %d" % [n, sum])


func _volley_timing(f: Array[String]) -> void:
	# 7 balls through the real runtime: releases at 0, 9, 18 | 45, 54, 63 | 90 - the
	# 3 + 3 + 1 pattern with 45-tick gaps between volleys, 9 inside a volley
	var tiles := _flat_tiles()
	var pair := _runtime(tiles)
	var rt = pair[0]
	rt.spawn_at("tbd", "TBD", RangedBehavior.new(), {"contact_kill": false},
			Vector3(14.5, 0.0, 2.5))
	var events := _events(rt, 400)
	var shots: Array = []
	for e in _of(events, "projectile_spawn"):
		if e["name"] == "ball":
			shots.append(int(e["tick"]))
	if shots.size() != 7:
		f.append("ranged: %d balls fired, want the 7-ball burst" % shots.size())
		return
	var t0: int = shots[0]
	var rel: Array = []
	for t in shots:
		rel.append(int(t) - t0)
	if str(rel) != "[0, 9, 18, 45, 54, 63, 90]":
		f.append("ranged: the 7-ball burst fired at %s, want [0, 9, 18, 45, 54, 63, 90]" % str(rel))
		return
	# group into volleys by the 9-tick in-volley spacing: 3 + 3 + 1, gaps of exactly 45
	var volleys: Array = []
	var cur: Array = [rel[0]]
	for i in range(1, rel.size()):
		if rel[i] - rel[i - 1] <= EnemyRuntime.VOLLEY_TICKS:
			cur.append(rel[i])
		else:
			volleys.append(cur)
			cur = [rel[i]]
	volleys.append(cur)
	var sizes: Array = []
	for v in volleys:
		sizes.append(v.size())
	if str(sizes) != "[3, 3, 1]":
		f.append("ranged: volley sizes %s, want [3, 3, 1]" % str(sizes))
		return
	for i in range(1, volleys.size()):
		var gap: int = int(volleys[i][0]) - int(volleys[i - 1][0])
		if gap != EnemyRuntime.VOLLEY_GAP_TICKS:
			f.append("ranged: volley %d starts %d ticks after volley %d, want 45"
					% [i, gap, i - 1])


func _salvo_life_limit(f: Array[String]) -> void:
	# D-064: tracking + every restart + descent, at most 360 ticks from the FIRST tracking
	# tick; a restart never resets the budget; expiry is harmless (nothing launches after)
	var pair := _runtime(_flat_tiles())
	var rt = pair[0]
	rt.spawn_at("tbd", "TBD", SalvoBehavior.new(), {"contact_kill": false},
			Vector3(0.5, 0.0, 2.5))
	var row: Dictionary = rt.enemies[0]
	var spawn_tick: int = rt.tick
	var events := _events(rt, 420)
	# the clock is alive for exactly the ages 1..359 (its first tracking tick is age 1):
	# launches land every 60 ticks while alive, and none after the 360-tick budget
	var last_launch := -1
	var launches := 0
	for e in _of(events, "projectile_spawn"):
		if e["name"] == "missile":
			launches += 1
			last_launch = int(e["tick"]) - spawn_tick
	if launches != 5 or last_launch < 0:
		f.append("ranged: %d launches (last at rel %s), want 5 (ages 60..300 while alive)"
				% [str(launches), str(last_launch)])
	if last_launch > 359:
		f.append("ranged: a launch happened at rel %d, past the 360-tick budget" % last_launch)
	# age at death: the clock expired exactly 360 ticks after its first tracking tick
	if bool(row.get("alive", true)):
		f.append("ranged: the salvo is still alive past its 360-tick budget")
	var clock = row["salvo"]
	if not bool(clock.expired) or int(clock.ticks) != 360:
		f.append("ranged: salvo clock at %s ticks (expired %s), want 360/true"
				% [str(clock.ticks), str(clock.expired)])
	# direct clock semantics: restart does not reset, expiry lands on the 360th tick total
	# (the clock acts for ticks 1..359 and expires ON tick 360)
	var c = EnemyRuntime.SalvoClock.new()
	if c.tick():
		f.append("ranged: SalvoClock.tick() true before start()")
	c.start()
	var alive_ticks := 0
	while c.tick():
		alive_ticks += 1
		if alive_ticks > 1000:
			break
	if alive_ticks != 359:
		f.append("ranged: salvo acted for %d ticks, want 359 (expires on tick 360)" % alive_ticks)
	if not bool(c.expired) or int(c.ticks) != 360:
		f.append("ranged: salvo clock at %s ticks (expired %s), want 360/true"
				% [str(c.ticks), str(c.expired)])
	var r2 = EnemyRuntime.SalvoClock.new()
	r2.start()
	for i in range(100):
		if not r2.tick():
			f.append("ranged: salvo died at tick %d before the restart" % [i + 1])
			break
	r2.start()  # the restart after a broken lock
	var alive2 := 0
	while r2.tick():
		alive2 += 1
		if alive2 > 1000:
			break
	if alive2 != 259 or not bool(r2.expired):
		f.append("ranged: restarted salvo lived %d more ticks (want 259, 360 total), expired %s"
				% [alive2, str(r2.expired)])


func _missile_on_spire_pad(f: Array[String]) -> void:
	# D-064 blocking: the descending missile meets the pad's slab (top at 4.0 u) and
	# detonates there - never at the ground below, never after expiry
	var tiles := _flat_tiles()
	tiles.append([10, 5, 8, 0, 0])   # the tall pad column, top = 4.0 u, slab [3.0, 4.0]
	var pair := _runtime(tiles)
	var rt = pair[0]
	var row: Dictionary = rt.spawn_at("tbd", "TBD", EnemyRuntime.FixtureBehavior.new(),
			{"contact_kill": false}, Vector3(0.5, 0.0, 0.5))
	var spawned := []
	for h in [[10.5, 5.5], [4.5, 0.5]]:
		rt.spawn_projectile(row, {"name": "missile", "x": float(h[0]), "y": 6.0,
				"z": float(h[1]), "vy": -6.0, "r": 0.4, "life_ticks": 600})
		spawned.append(str(h[0]))
	var events := _events(rt, 120)
	var ends := _of(events, "projectile_end")
	if ends.size() != 2:
		f.append("ranged: %d projectile_end events, want 2" % ends.size())
		return
	var pads := []
	for e in ends:
		if e["name"] == "missile":
			pads.append(e)
	if pads.size() != 2:
		f.append("ranged: projectile_end rows lost their names")
		return
	var on_pad: Variant = null
	var on_ground: Variant = null
	for e in pads:
		if e["x"] > 6.0:
			on_pad = e
		else:
			on_ground = e
	if on_pad == null or on_ground == null:
		f.append("ranged: could not tell the pad missile from the ground missile")
		return
	if str(on_pad["cause"]) != "solid":
		f.append("ranged: the pad missile ended by '%s', want 'solid'" % str(on_pad["cause"]))
	if float(on_pad["y"]) < 2.9 or float(on_pad["y"]) > 4.1:
		f.append("ranged: the pad missile detonated at y %.3f, want on the pad slab [3, 4]"
				% float(on_pad["y"]))
	if str(on_ground["cause"]) != "solid":
		f.append("ranged: the ground missile ended by '%s', want 'solid'" % str(on_ground["cause"]))
	if float(on_ground["y"]) > 0.1 or float(on_ground["y"]) < -1.1:
		f.append("ranged: the ground missile detonated at y %.3f, want the ground slab [-1, 0]"
				% float(on_ground["y"]))
	if float(on_pad["y"]) <= float(on_ground["y"]) + 2.0:
		f.append("ranged: the pad did not stop the missile high (pad y %.3f vs ground y %.3f)"
				% [float(on_pad["y"]), float(on_ground["y"])])
