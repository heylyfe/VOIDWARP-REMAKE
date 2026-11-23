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
	row["gin_target_ground"] = _ground_point(api.rt.world, feet).y
	var origin := Vector3(row["x"], feet.y, row["z"])
	var offset := origin - feet
	if offset.length() < float(cfg["min_launch_distance_u"]):
		var direction := offset.normalized() if not offset.is_zero_approx() else Vector3.RIGHT
		origin = feet + direction * float(cfg["min_launch_distance_u"])
	row["gin_flight_elapsed"] = 0
	row["gin_launch_tick"] = now
	row["gin_arrival_tick"] = now + int(cfg["flight_ticks"])
	row["gin_sword_pos"] = _ground_point(api.rt.world, origin)
	if bool(row.get("gin_twin_fangs", false)):
		row["gin_second_pos"] = _ground_point(api.rt.world, feet - (origin - feet))
	row["gin_outcome"] = ""
	row["phase"] = "sword"


static func _advance(row: Dictionary, api, cfg: Dictionary, now: int) -> void:
	var player = api.rt.controllers[int(row["gin_target"])]
	if player.dead:
		_finish(row, cfg, now, "target_lost")
		return
	var feet := Vector3(player.x, player.y, player.z)
	var support: float = Collision.support_at(api.rt.world, feet.x, feet.z, feet.y, 0.0)
	if player.grounded:
		row["gin_target_ground"] = feet.y
	elif is_finite(support):
		row["gin_target_ground"] = support
	var goal := Vector3(feet.x, row["gin_target_ground"], feet.z)
	row["gin_flight_elapsed"] = now - int(row["gin_launch_tick"])
	var remaining := maxi(1, int(row["gin_arrival_tick"]) - now + 1)
	for key in ["gin_sword_pos", "gin_second_pos"]:
		if row.has(key):
			var from: Vector3 = row[key]
			row[key] = goal if remaining == 1 else _ground_point(api.rt.world,
					from.lerp(goal, 1.0 / float(remaining)))
	if now < int(row["gin_arrival_tick"]):
		return
	var clearance := float(cfg["twin_clearance_u"] if row.has("gin_second_pos") else cfg["clearance_u"])
	var hit := feet.y < goal.y + clearance
	var outcome := "clear"
	if hit:
		var saved: bool = api.kill(player, str(row["id"]), str(row["cfg"]["death_code"]))
		if player.dead:
			outcome = "kill"
		else:
			outcome = "saved" if saved else "suppressed"
	_finish(row, cfg, now, outcome)


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

