extends RefCounted

const Controller := preload("res://sim/controller.gd")
const RunState := preload("res://sim/run_state.gd")
const StateHash := preload("res://sim/state_hash.gd")

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
	if not still["dead"] or still["code"] != "D-GIN" or still["killer"] != "gin":
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
		if trace["contact"] > 0.001:
			failures.append("the sword endpoint did not reach the player's feet")
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
	var inputs: Array = []
	var hashes: Array[String] = []
	var launch := -1
	var voice := -1
	var arrival := -1
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
			arrival = int(world.rt.tick) - 1
			outcome = str(row["gin_outcome"])
			var pos: Vector3 = row["gin_sword_pos"]
			contact = Vector2(pos.x, pos.z).distance_to(Vector2(world.ctl.x, world.ctl.z))
			break
	var result := {"inputs": inputs, "hashes": hashes, "voice": voice, "launch": launch,
			"arrival": arrival, "dead": world.ctl.dead, "code": world.ctl.dead_code,
			"killer": world.ctl.dead_killer, "outcome": outcome, "contact": contact,
			"jump_seen": jump_seen, "hash_sensitive": hash_sensitive}
	world.teardown()
	world.free()
	return result
