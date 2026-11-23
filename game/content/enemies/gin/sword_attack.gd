extends RefCounted
## Cycle 7 Gin. The same tick-parametrized ground path drives the hit and the view.

const Collision := preload("res://sim/collision.gd")


static func tick(row: Dictionary, api) -> void:
	var cfg: Dictionary = row["cfg"]["sword_attack"]
	var now: int = api.rt.tick
	match row["phase"]:
		"waiting", "cooldown":
			if now >= int(row["gin_next_tick"]):
				_warn(row, api, cfg, now)
		"voice":
			if now >= int(row["gin_voice_tick"]) + int(cfg["voice_ticks"]):
				_release(row, api, cfg, now)
		"sword":
			_advance(row, api, cfg, now)


static func _warn(row: Dictionary, api, cfg: Dictionary, now: int) -> void:
	# Serialize copies and preserve the address me arbitration rule.
	for other in api.rt.enemies:
		if other.get("phase") in ["voice", "sword"] and other.get("id") == row["id"]:
			return
	var pending: Array = []
	for other in api.rt.enemies:
		if other.get("id") == "address_me" and int(other.get("countdown_left", 0)) > 0:
			pending.append("address_me")
			break
	var gate: Dictionary = api.arbiter_gate(pending)
	if not bool(gate.get("may_appear", false)) or bool(gate.get("deferred", false)):
		return
	var target: Dictionary = api.nearest_player(Vector3(row["x"], row["y"], row["z"]))
	if target.is_empty() or api.rt.controllers[int(target["index"])].dead:
		return
	row["gin_target"] = int(target["index"])
	row["gin_voice_tick"] = now
	row["phase"] = "voice"


static func _release(row: Dictionary, api, cfg: Dictionary, now: int) -> void:
	var player = api.rt.controllers[int(row["gin_target"])]
	if player.dead:
		_finish(row, cfg, now, "target_lost")
		return
	var feet := Vector3(player.x, player.y, player.z)
	var goal := feet if player.grounded else _ground_point(api.rt.world, feet)
	var origin := Vector3(row["x"], feet.y, row["z"])
	var offset := origin - feet
	if offset.length() < float(cfg["min_launch_distance_u"]):
		var direction := offset.normalized() if not offset.is_zero_approx() else Vector3.RIGHT
		origin = feet + direction * float(cfg["min_launch_distance_u"])
	row["gin_flight_elapsed"] = 0
	row["gin_launch_tick"] = now
	row["gin_arrival_tick"] = now + int(cfg["flight_ticks"])
	row["gin_goal"] = goal
	row["gin_origin"] = _ground_point(api.rt.world, origin)
	row["gin_sword_pos"] = row["gin_origin"]
	row["gin_previous_feet"] = _player_feet(api.rt.controllers)
	row.erase("gin_second_origin")
	row.erase("gin_second_pos")
	if bool(row.get("gin_twin_fangs", false)):
		row["gin_second_origin"] = _ground_point(api.rt.world, feet - (origin - feet))
		row["gin_second_pos"] = row["gin_second_origin"]
	row["gin_outcome"] = ""
	row["phase"] = "sword"
	_advance(row, api, cfg, now)


static func _advance(row: Dictionary, api, cfg: Dictionary, now: int) -> void:
	var elapsed := now - int(row["gin_launch_tick"])
	row["gin_flight_elapsed"] = elapsed
	var progress := float(elapsed) / float(cfg["flight_ticks"])
	var goal: Vector3 = row["gin_goal"]
	var feet := _player_feet(api.rt.controllers)
	var clearance := float(cfg["twin_clearance_u"] if row.has("gin_second_pos") else cfg["clearance_u"])
	for path in [["gin_origin", "gin_sword_pos"], ["gin_second_origin", "gin_second_pos"]]:
		if not row.has(path[0]):
			continue
		var origin: Vector3 = row[path[0]]
		var previous: Vector3 = row[path[1]]
		var current := origin
		if elapsed > 0:
			current = goal if now == int(row["gin_arrival_tick"]) else _ground_point(
					api.rt.world, origin.lerp(goal, progress))
		row[path[1]] = current
		for i in feet.size():
			var player = api.rt.controllers[i]
			if player == null or player.dead or player.respawn_t >= 0.0:
				continue
			if not _swept_hit(previous - row["gin_previous_feet"][i], current - feet[i],
					float(player.C["half_width"]), float(player.C["height"]),
					float(cfg["sword_radius_u"]), clearance):
				continue
			var saved: bool = api.kill(player, str(row["id"]), str(row["cfg"]["death_code"]))
			_finish(row, cfg, now, "kill" if player.dead else ("saved" if saved else "suppressed"))
			return
	row["gin_previous_feet"] = feet
	if now >= int(row["gin_arrival_tick"]):
		_finish(row, cfg, now, "clear")


static func _player_feet(controllers: Array) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for player in controllers:
		points.append(Vector3.ZERO if player == null else Vector3(player.x, player.y, player.z))
	return points


## Sweep in the player's frame, so either the blade or the moving player can cross
## the other within one tick. The closest points are on the blade's swept
## centerline and the capsule's vertical axis.
static func _swept_hit(from: Vector3, to: Vector3, body_radius: float, height: float,
		sword_radius: float, clearance: float) -> bool:
	var lift := Vector3.UP * (clearance - sword_radius)
	var axis_low := Vector3.UP * body_radius
	var axis_high := Vector3.UP * (height - body_radius)
	var points := Geometry3D.get_closest_points_between_segments(
			from + lift, to + lift, axis_low, axis_high)
	var combined_radius := body_radius + sword_radius
	return points[0].distance_squared_to(points[1]) <= combined_radius * combined_radius


static func _ground_point(world: Dictionary, p: Vector3) -> Vector3:
	var ground: float = Collision.support_at(world, p.x, p.z, p.y, 0.0)
	return Vector3(p.x, ground if is_finite(ground) else p.y, p.z)


static func _finish(row: Dictionary, cfg: Dictionary, now: int, outcome: String) -> void:
	var extra := maxi(0, int(row["copies"]) - 1)
	var delay := maxi(int(cfg["cooldown_min_ticks"]),
			int(cfg["cooldown_ticks"]) - extra * int(cfg["cooldown_vote_discount_ticks"]))
	row["gin_outcome"] = outcome
	row["gin_next_tick"] = now + delay
	row["phase"] = "cooldown"
