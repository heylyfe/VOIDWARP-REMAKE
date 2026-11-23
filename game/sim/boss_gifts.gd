extends RefCounted
## Player shot state. Only the recorded world-space aim and held fire enter this sim.

const InputScript := preload("res://sim/input.gd")

var next_fire_tick := 0
var shots: Array[Dictionary] = []


func tick(boss, sim_tick: int, command: Dictionary, eye: Vector3, target: Vector3,
		dt: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not boss.active or boss.bankai_active:
		return events
	var aim: Vector3 = command.get("gift_aim", Vector3.ZERO)
	if sim_tick >= next_fire_tick and aim.is_finite() and not aim.is_zero_approx() \
			and (int(command.get("buttons", 0)) & InputScript.BUTTON_FIRE) != 0:
		next_fire_tick = sim_tick + ceili(1.0 / (dt * float(boss.config["fire_rate_per_s"])))
		var crit: bool = boss.gift_is_crit(sim_tick)
		var shot := {"id": sim_tick, "position": eye, "velocity":
			aim.normalized() * float(boss.config["gift_speed_u_per_s"]), "is_crit": crit}
		shots.append(shot)
		events.append({"kind": "boss_gift_spawned", "id": sim_tick, "position": eye})
	var radius := float(boss.config["gift_hit_radius_u"])
	var extent := float(boss.config["arena"]["half_extent_tiles"]) + 1.0
	var floor_y := float(boss.config["arena"]["floor_height"]) * 0.5
	var live: Array[Dictionary] = []
	for shot in shots:
		var from: Vector3 = shot["position"]
		var to: Vector3 = from + shot["velocity"] * dt
		var nearest := Geometry3D.get_closest_point_to_segment(target, from, to)
		if boss.active and nearest.distance_squared_to(target) <= radius * radius:
			var crit: bool = shot["is_crit"]
			var amount := int(boss.config["crit_damage"] if crit else boss.config["gift_damage"])
			events.append_array(boss.damage(amount, crit))
		elif boss.active and to.y >= floor_y and absf(to.y - floor_y) <= extent \
				and absf(to.x) <= extent and absf(to.z) <= extent:
			shot["position"] = to
			live.append(shot)
			events.append({"kind": "boss_gift_moved", "id": shot["id"], "position": to})
			continue
		events.append({"kind": "boss_gift_removed", "id": shot["id"]})
	if not boss.active:
		live.clear()
	shots = live
	return events


func snapshot() -> Dictionary:
	return {"next_fire_tick": next_fire_tick, "shots": shots}
