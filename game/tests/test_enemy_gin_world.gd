extends RefCounted

const Controller := preload("res://sim/controller.gd")
const RunState := preload("res://sim/run_state.gd")
const StateHash := preload("res://sim/state_hash.gd")
const EnemyRuntime := preload("res://sim/enemy_runtime.gd")
const Gin := preload("res://content/enemies/gin/enemy.gd")
const Util := preload("res://tests/sim_testutil.gd")

const SEED := 1
const LEVEL := 17
const DT := 1.0 / 60.0
const KILL_MAX := 900


class BotWorld extends "res://app/world.gd":
	var input_frame: Dictionary

	func _capture_input() -> Dictionary:
		return input_frame


func run() -> Array[String]:
	var failures: Array[String] = []
	var still := _play(false, true)
	var jump := _play(true, true)
	var absent := _play(false, false)
	var replay := _play(false, true, jump.get("inputs", []))
	for trace in [still, jump, absent, replay]:
		if trace.is_empty():
			failures.append("Gin world failed to build")
			return failures
	if not still["dead"] or still["outcome"] != "kill" or still["code"] != "D-GIN" or still["killer"] != "gin":
		failures.append("a grounded player must die to Gin's sword")
	if jump["dead"] or jump["outcome"] != "clear" or not jump["jump_seen"]:
		failures.append("a bot's normal jump must clear the sword at arrival")
	if absent["dead"] or absent["launch"] >= 0 or absent["voice"] >= 0:
		failures.append("the no-vote control produced a Gin attack")
	if jump["hashes"] != replay["hashes"] or not replay["jump_seen"] or replay["dead"]:
		failures.append("replayed controller inputs diverged across Gin checkpoints")
	if not jump["hash_sensitive"]:
		failures.append("the sword's live position is missing from the state hash")
	for trace in [still, jump]:
		var launch: int = trace["launch"]
		var arrival: int = trace["arrival"]
		var ms := float(arrival - launch) * DT * 1000.0
		if launch < 0 or ms < 500.0 or ms > 750.0 or arrival - launch != 39:
			failures.append("throw-to-arrival window was %.1f ms, expected 650 ms" % ms)
		if trace["voice"] < 0 or trace["voice"] >= launch:
			failures.append("Gin's voice must precede the launch")
	if jump["contact"] > 0.001:
		failures.append("the unobstructed sword missed its fixed release endpoint")
	if still["impact"] < still["launch"] + 30 or still["impact"] > still["arrival"]:
		failures.append("standing at the aim point must be dangerous inside the trigger window")
	if not jump["pending_sensitive"]:
		failures.append("the pending Gin tick or placement target is missing from the hash")
	_moving_crossing(failures)
	return failures


func _play(jump: bool, gin: bool, playback: Array = []) -> Dictionary:
	var world := BotWorld.new()
	var votes := {"gin": 1} if gin else {}
	var ledger := {"class": "dasher", "votes": votes, "curses": {}, "stacks": {},
			"purse": 0, "tithes": 0, "hunger": 0, "last_vote": ""}
	if not world.build(SEED, LEVEL, ledger):
		world.free()
		return {}
	world.ctl.last_light_spent = true
	var rs := RunState.new_run(SEED, 1, [])
	rs.load_level(world.lv, LEVEL)
	rs.level = world.lstate
	rs.run_votes = votes
	var pending_sensitive := false
	if gin and not world.rt.planned.is_empty():
		var before := StateHash.sha256(rs)
		world.rt.spawn_delay_ticks += 1
		var tick_sensitive := StateHash.sha256(rs) != before
		world.rt.spawn_delay_ticks -= 1
		var entry: Dictionary = world.rt.planned[0]
		entry["spawn_target"] = 1
		pending_sensitive = tick_sensitive and StateHash.sha256(rs) != before
		entry["spawn_target"] = 0
	var inputs: Array = []
	var hashes: Array[String] = []
	var launch := -1
	var voice := -1
	var arrival := -1
	var impact := -1
	var outcome := ""
	var contact := INF
	var jump_seen := false
	var hash_sensitive := false
	for i in range(KILL_MAX if playback.is_empty() else playback.size()):
		var buttons := 0
		# Wait until roughly the apex will coincide with the sword's arrival.
		if jump and launch >= 0 and world.rt.tick >= launch + 17:
			buttons = Controller.BTN_JUMP
		var frame := {"move_x": 0, "move_z": 0, "buttons": buttons, "aim_x": 0.0, "aim_z": 1.0}
		world.input_frame = frame if playback.is_empty() else playback[i]
		inputs.append(world.input_frame)
		world.step(DT)
		for event in world.last_events:
			jump_seen = jump_seen or event.get("e") == "jump"
		if world.rt.enemies.is_empty():
			continue
		var row: Dictionary = world.rt.enemies[0]
		voice = int(row.get("gin_voice_tick", -1))
		launch = int(row.get("gin_launch_tick", -1))
		if launch < 0:
			continue
		var checkpoint := StateHash.sha256(rs)
		hashes.append(checkpoint)
		if not hash_sensitive:
			var pos: Vector3 = row["gin_sword_pos"]
			row["gin_sword_pos"] = pos + Vector3.RIGHT
			hash_sensitive = StateHash.sha256(rs) != checkpoint
			row["gin_sword_pos"] = pos
		if row["phase"] == "cooldown":
			arrival = int(row["gin_arrival_tick"])
			impact = int(world.rt.tick) - 1
			outcome = str(row["gin_outcome"])
			var pos: Vector3 = row["gin_sword_pos"]
			contact = Vector2(pos.x, pos.z).distance_to(Vector2(world.ctl.x, world.ctl.z))
			break
	var result := {"inputs": inputs, "hashes": hashes, "voice": voice, "launch": launch,
			"arrival": arrival, "impact": impact, "dead": world.ctl.dead, "code": world.ctl.dead_code,
			"killer": world.ctl.dead_killer, "outcome": outcome, "contact": contact,
			"jump_seen": jump_seen, "hash_sensitive": hash_sensitive,
			"pending_sensitive": pending_sensitive}
	world.teardown()
	world.free()
	return result


func _moving_crossing(failures: Array[String]) -> void:
	var doc: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string("res://content/enemies/gin/enemy.json"))
	var cfg: Dictionary = doc["stats"]
	var floor_tiles: Array = []
	for x in range(-2, 12):
		for z in range(-2, 3):
			floor_tiles.append([x, z, 0])
	for jump in [false, true]:
		var w := Util.world_from_tiles(floor_tiles)
		w["dais"] = [0, 0, 0]
		var player := Controller.new()
		player.setup("dasher", Util.consts())
		player.place(w)
		player.last_light_spent = true
		var rt := EnemyRuntime.new()
		rt.setup({}, w, [player], SEED)
		var row := rt.spawn_at("gin", "gin ichimaru", Gin.new(), cfg, Vector3(8.5, 0.0, 0.5))
		var jump_seen := false
		var traveled := false
		for _i in range(KILL_MAX):
			var flying: bool = row["phase"] == "sword"
			var events := player.step(DT, {"move_x": 127 if flying else 0, "move_z": 0,
					"buttons": Controller.BTN_JUMP if flying and jump else 0}, w)
			for event in events:
				jump_seen = jump_seen or event.get("e") == "jump"
			rt.step(DT)
			traveled = traveled or player.x > 1.5
			if row["phase"] == "cooldown":
				break
		if not traveled:
			failures.append("moving Gin fixture failed to travel toward the sword")
		if jump:
			if not jump_seen or player.dead or row["gin_outcome"] != "clear":
				failures.append("moving jump must cross the projectile and survive")
			elif (row["gin_sword_pos"] as Vector3).distance_to(row["gin_goal"]) > 0.001:
				failures.append("the sword followed a moving player away from its release endpoint")
		elif not player.dead or player.dead_code != "D-GIN" or rt.tick - 1 >= int(row["gin_arrival_tick"]):
			failures.append("moving ground player must die before the sword reaches its endpoint")
