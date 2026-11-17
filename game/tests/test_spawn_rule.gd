extends RefCounted
#
# The D-056 spawn rule (ticket T-027; DESIGN.md section 5): 6.0 s after level start; fallback
# order preferred kind -> lane -> any round-trip tile >= 25 u from the spawn point; never
# within 25 u of the player; farthest-but-within 60 u at steps (a)/(b), the preference dropped
# at (c); tie-break farthest from the player, then the lowest anchor/tile index. Deterministic.

const EnemyRuntime := preload("res://sim/enemy_runtime.gd")


# A synthetic level: a walkable line of tiles x = 0..99 at z = 0, plus anchor tiles at
# (30, 5) = perch, (45, 5) = perch, (55, 5) = lane, (70, 5) = perch (too far: > 60 u).
# Tiles: two rows (z = 0 and z = 5) linked by a bridge column at x = 0 so anchors are
# round-trip reachable too. y = 0 (tile top at 0.0 u).
func _level() -> Dictionary:
	var tiles: Array = []
	for x in range(0, 100):
		tiles.append([x, 0, 0, 0, 0])
		tiles.append([x, 5, 0, 0, 1])
	tiles.append([0, 1, 0, 0, 2])
	tiles.append([0, 2, 0, 0, 2])
	tiles.append([0, 3, 0, 0, 2])
	tiles.append([0, 4, 0, 0, 2])
	return {"beacon": [0, 0, 0], "spawns": [[0, 0, 0]],
			"anchors": [
				[0, 30, 5, 0, 1],   # perch, 30 u from the player at the spawn point
				[0, 45, 5, 0, 1],   # perch, 45 u - the farthest within 60 u
				[2, 55, 5, 0, 1],   # lane
				[2, 70, 5, 0, 1],   # lane, 70 u - beyond the 60 u preference
			],
			"tiles": tiles, "props": [], "pads": []}


func _player_at(x: float, z: float) -> Vector3:
	return Vector3(x, 0.0, z)


func run() -> Array[String]:
	var f: Array[String] = []
	_order_and_distances(f)
	_tie_break_and_determinism(f)
	_separation_and_round_trip(f)
	return f


func _order_and_distances(f: Array[String]) -> void:
	var lv := _level()
	var player := _player_at(0.5, 0.5)
	# (a) preferred kind: the farthest perch within 60 u (45.3 u), not the 30.4 u one
	var s: Variant = EnemyRuntime.pick_spawn_tile(lv, "perch", player)
	if s == null or int(s["anchor_index"]) != 1:
		f.append("spawn: expected the 45 u perch (anchor index 1), got %s" % str(s))
	# ("") skips (a): the lane step picks the farthest lane within 60 u (55.2 u), and the
	# 70.2 u lane stays out of the preference window
	var s2: Variant = EnemyRuntime.pick_spawn_tile(lv, "", player)
	if s2 == null or int(s2["anchor_index"]) != 2:
		f.append("spawn: expected the 55 u lane (anchor index 2), got %s" % str(s2))
	# never within 25 u of the player: a lone 20 u perch is illegal - the rule falls through
	# (b) has no lane anchor in lv2, so (c) round-trip tiles answer
	var lv2 := _level()
	lv2["anchors"] = [[0, 20, 5, 0, 1]]
	var s3: Variant = EnemyRuntime.pick_spawn_tile(lv2, "perch", player)
	if s3 == null or s3.get("kind", "") != "round_trip":
		f.append("spawn: a 20 u perch was used or (c) was not reached: %s" % str(s3))
	# step (c): no anchors at all - the farthest round-trip tile (no 60 u cap); the (99,5)
	# tile centre sits sqrt(99^2 + 5^2) = 99.13 u away, farther than (99,0)'s 99.0
	var lv3 := _level()
	lv3["anchors"] = []
	var s4: Variant = EnemyRuntime.pick_spawn_tile(lv3, "", player)
	if s4 == null or int(s4["tile_index"]) < 0:
		f.append("spawn: no round-trip fallback tile: %s" % str(s4))
	if s4 != null and (float(s4["x"]) != 99.5 or float(s4["z"]) != 5.5):
		f.append("spawn: step (c) picked (%s,%s), want the farthest tile (99,5)"
				% [str(float(s4["x"]) - 0.5), str(float(s4["z"]) - 0.5)])
	var d: float = Vector3(float(s4["x"]) - player.x, 0.0, float(s4["z"]) - player.z).length()
	if d < 25.0:
		f.append("spawn: step (c) tile %.1f u from the player (< 25)" % d)
	d = Vector3(float(s4["x"]) - 0.5, 0.0, float(s4["z"]) - 0.5).length()
	if d < 25.0:
		f.append("spawn: step (c) tile %.1f u from the spawn point (< 25)" % d)


func _tie_break_and_determinism(f: Array[String]) -> void:
	# two lanes at the exact same distance from the player: the lowest anchor index wins
	var lv_tie := _level()
	lv_tie["anchors"] = [[2, 55, 3, 0, 1], [2, 55, -3, 0, 1]]
	var player := _player_at(30.0, 0.0)   # both: sqrt(25^2 + 3^2) = 25.18 u, >= 25 u
	var a: Variant = EnemyRuntime.pick_spawn_tile(lv_tie, "lane", player)
	var b: Variant = EnemyRuntime.pick_spawn_tile(lv_tie, "lane", player)
	if a == null or int(a["anchor_index"]) != 0:
		f.append("spawn: exact distance tie went to anchor %s, want index 0" % str(a))
	if a == null or (b != null and str(a) != str(b)):
		f.append("spawn: pick_spawn_tile is not deterministic on identical inputs")


func _separation_and_round_trip(f: Array[String]) -> void:
	# the full runtime path: 6 s delay, votes, copies >= 30 u apart (SR-3), diegetic text
	var lv := _level()
	lv["anchors"] = [
		[4, 45, 5, 0, 1],   # nook: the preferred kind, 45.3 u from the player - the pick
		[4, 30, 5, 0, 1],   # nook: 30.4 u, farther-from-player loses to the 45 u nook
	]
	var w := {"cols": {}, "prop_cols": {}, "pads": {}, "dais": [0, 0, 0], "glitched": {},
			"slippery": {}, "removed": {}, "kill_y": -40.0, "enemies": [], "projectiles": [],
			"hazards": []}
	var Util := preload("res://tests/sim_testutil.gd")
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	ctl.place(w)
	ctl.last_light_spent = true
	var rt = EnemyRuntime.new()
	rt.setup(lv, w, [ctl], 99)
	var votes: int = rt.add_vote("tbd", 4)
	if votes != 1 or rt.add_vote("tbd", 4) != 2:
		f.append("spawn: vote counts wrong")
	if rt.votes["tbd"] != 2:
		f.append("spawn: votes dict wrong")
	rt.plan("tbd", "TBD", EnemyRuntime.FixtureBehavior.new(),
			{"preferred_kind": "nook", "contact_kill": true, "cycle_s": 0.0}, 2)
	for i in range(361):
		rt.step(Util.DT)
	var spawns: Array = []
	for e in rt.events:
		if e.get("e", "") == "enemy_spawn":
			spawns.append(e)
	if spawns.size() != 2:
		f.append("spawn: %d enemy_spawn events, want 2 (copies)" % spawns.size())
	if not spawns.is_empty() and str(spawns[0]["text"]) != "TBD":
		f.append("spawn: diegetic text %s, want the TBD name" % str(spawns[0]["text"]))
	# copy 1 took the farthest-within-60 nook; copy 2 took the next D-056 candidate >= 30 u away
	if spawns.size() == 2 and (float(spawns[0]["x"]) != 45.5 or float(spawns[0]["z"]) != 5.5):
		f.append("spawn: copy 1 at (%s,%s), want the 45 u nook (45.5, 5.5)"
				% [str(spawns[0]["x"]), str(spawns[0]["z"])])
	if spawns.size() != 2:
		return
	var d: float = Vector3(float(spawns[1]["x"]) - float(spawns[0]["x"]),
			0.0, float(spawns[1]["z"]) - float(spawns[0]["z"])).length()
	if d < 30.0:
		f.append("spawn: copies %.1f u apart, want >= 30 (SR-3)" % d)
	for s in spawns:
		var dp: float = Vector3(float(s["x"]) - ctl.x, float(s["y"]) - ctl.y,
				float(s["z"]) - ctl.z).length()
		if dp < 25.0:
			f.append("spawn: copy at %.1f u from the player (< 25)" % dp)
	# rng streams: two enemies draw from different streams with the same seed base
	if rt.enemies.size() == 2 and rt.enemies[0]["rng"].s == rt.enemies[1]["rng"].s:
		f.append("spawn: the two enemies share one rng stream state")
