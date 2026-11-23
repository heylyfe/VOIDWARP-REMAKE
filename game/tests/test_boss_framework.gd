extends RefCounted

const World := preload("res://app/world.gd")
const Boss := preload("res://sim/boss.gd")
const InputScript := preload("res://sim/input.gd")
const RunState := preload("res://sim/run_state.gd")
const StateHash := preload("res://sim/state_hash.gd")

const DT := 1.0 / 60.0
const SEED := 17
const IDLE := {"buttons": 0}


class HitBoss extends Boss:
	func tick(_state, _ctx: Dictionary) -> Array[Dictionary]:
		return [{"kind": "boss_projectile_hit_player", "attack": "bowling_ball"}]


func run() -> Array[String]:
	var failures: Array[String] = []
	_rolls_and_damage(failures)
	var trace := _fight(failures, false)
	if trace.is_empty():
		return failures
	if trace != _fight(failures, false):
		failures.append("same level, seed and commands diverged in the arena replay")
	var perturbed := _fight(failures, true)
	if perturbed.is_empty() or trace[0] == perturbed[0]:
		failures.append("withholding initial held fire left the state hash unchanged")
	_hit_is_lethal(failures)
	return failures


func _rolls_and_damage(failures: Array[String]) -> void:
	var crits := 0
	var selected := 0
	var cfg := Boss.load_config()
	for seed_value in 4096:
		var boss := Boss.new()
		var replay := Boss.new()
		boss.start(seed_value, 10)
		replay.start(seed_value, 10)
		var crit := boss.gift_is_crit(314)
		if not boss.bankai_rolled or boss.bankai_selected != replay.bankai_selected \
				or crit != replay.gift_is_crit(314):
			failures.append("seed %d changed its Bankai or crit roll in replay" % seed_value)
			return
		selected += int(boss.bankai_selected)
		crits += int(crit)
		var events := boss.damage(int(cfg["crit_damage"] if crit else cfg["gift_damage"]), crit)
		if boss.hp != (245 if crit else 249) or events[0]["is_crit"] != crit:
			failures.append("wrong damage or crit event at seed %d" % seed_value)
			return
		if not boss.start(seed_value + 1, 10).is_empty():
			failures.append("start accepted a second roll")
			return
	if crits < 160 or crits > 250 or selected < 1 or selected > 12:
		failures.append("unexpected crit/Bankai counts across 4096 seeds: %d/%d" % [crits, selected])


func _enter(failures: Array[String]) -> Node3D:
	var world := World.new()
	world.atmosphere = false
	if not world.build(SEED, 10, {"class": "dasher", "votes": {}, "curses": {},
			"stacks": {}, "purse": 35}):
		failures.append("level 10 failed to build")
		world.free()
		return null
	var gifts: RefCounted = world.lstate.gifts
	var slots: Array[int] = []
	for i in gifts.slots.size():
		if gifts.is_real(i):
			slots.append(i)
	var final_id: int = slots.pop_back()
	for i in slots:
		gifts.collect(i, 0, 0, [])
	world.step(DT, IDLE)
	if world.lstate.boss.arena_entered or world.lstate.beacon.is_open():
		failures.append("level 10 opened before the last black gift")
	var slot: Vector3 = gifts.slot_pos(final_id)
	world.ctl.x = slot.x
	world.ctl.y = slot.y - 1.0
	world.ctl.z = slot.z
	world.ctl.vy = 0.0
	world.step(DT, IDLE)
	if not world.lstate.boss.arena_entered or not _has(world.last_events, "arena_entered"):
		failures.append("last black gift failed to enter the boss arena")
		world.free()
		return null
	if world.lstate.beacon.is_open() or world.beacon_view.visible or not world.lstate.collapse.is_empty() \
			or not world.lv["gifts"].is_empty() or not world.w["pads"].is_empty():
		failures.append("arena entered with a beacon, collapse, pads or gifts")
	if world.rig.position.distance_to(world._boss_eye(Vector3(world.ctl.x, world.ctl.y, world.ctl.z))) > 0.0001:
		failures.append("arena camera is away from eye height")
	return world

func _fight(failures: Array[String], perturb: bool) -> Array[String]:
	var trace: Array[String] = []
	var world := _enter(failures)
	if world == null:
		return trace
	var state := RunState.new_run(SEED, 1, [])
	state.level_number = 10
	state.level = world.lstate
	var purse: int = world._economy.purse_gold()
	var feet := Vector3(world.ctl.x, world.ctl.y, world.ctl.z)
	var aim: Vector3 = (world._boss_target_position() - world._boss_eye(feet)).normalized()
	var fire := {"buttons": InputScript.BUTTON_FIRE, "gift_aim": aim}
	var last_shot := -1
	var shot_count := 0
	for i in 2700:
		world.step(DT, IDLE if perturb and i == 0 else fire)
		if i % 60 == 0:
			trace.append(StateHash.sha256(state))
		if _has(world.last_events, "boss_gift_spawned"):
			if last_shot >= 0 and i - last_shot != 10:
				failures.append("held fire departed from the 6 shots/s cadence")
				break
			last_shot = i
			shot_count += 1
		if world.lstate.boss.dead:
			break
	if shot_count < 50 or not world.lstate.boss.dead or world.lstate.boss.hp != 0:
		failures.append("aimed gifts failed to wear down all 250 boss HP")
	if world._economy.purse_gold() != purse + 300 or not world.lstate.beacon.opened \
			or not world.beacon_view.visible or world.is_complete():
		failures.append("defeat must award 300 gold and open an unentered beacon")
	for i in 5:
		world.step(DT, IDLE)
	if world._economy.purse_gold() != purse + 300:
		failures.append("reward repeated on a later tick")
	world.ctl.x = world.lstate.beacon.cx
	world.ctl.y = world.lstate.beacon.base_y
	world.ctl.z = world.lstate.beacon.cz
	world.step(DT, IDLE)
	if not world.is_complete() or not _has(world.last_events, "arena_exited"):
		failures.append("arena beacon did not complete level 10")
	trace.append(StateHash.sha256(state))
	world.free()
	return trace


func _hit_is_lethal(failures: Array[String]) -> void:
	var world := _enter(failures)
	if world == null:
		return
	var boss := HitBoss.new()
	boss.start(SEED, 10)
	world.lstate.boss = boss
	var charges: int = world.ctl.charges
	world.ctl.invuln = 1.0
	var deaths: Array[Dictionary] = []
	world.run_over.connect(func(info: Dictionary) -> void: deaths.append(info))
	world.step(DT, IDLE)
	world.step(DT, IDLE)
	if not world.ctl.dead or world.ctl.charges != charges or deaths.size() != 1:
		failures.append("boss hit did not immediately kill once with charges intact")
	elif deaths[0]["killer"] != "Peter Griffin":
		failures.append("boss hit produced incorrect death attribution")
	world.free()


static func _has(events: Array, name: String) -> bool:
	for event in events:
		if event.get("kind") == name:
			return true
	return false
