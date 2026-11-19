extends RefCounted
#
# W12-E: PERFORMANCE HEADROOM on the biggest level the generator can produce.
#   Part A: generate (seed x level) across levels 20 / 25 / 30 and report tiles, gifts,
#           mines, pieces and the resolved enemy plan size; find the largest on each axis.
#   Part B: build the largest level with app/world.gd and time 600 world.step(dt) calls
#           (Time.get_ticks_usec around each step): mean, worst single step, and the tick
#           the worst step landed on. The 60 Hz frame budget is 16.67 ms.
#   Part C: the same timing with the presentation passes disabled (a subclass that no-ops
#           the view passes, rig nulled) - the delta is the presentation overhead.
# Numbers are printed, never asserted: wall-clock assertions flake on shared machines.
# Correctness checks (build succeeds, all 600 steps run) are asserted.
#
# Level choice note: which fight is measured. The largest tile count wins part B; the
# largest-mines combo is measured too when it differs from the largest-tiles combo.

const VoidGenScript := preload("res://terrain/voidgen.gd")
const WorldScript := preload("res://app/world.gd")
const ContentApiScript := preload("res://core/content_api.gd")
const DT := 1.0 / 60.0
const LEVELS := [20, 25, 30]
const SEEDS := [7, 77, 777, 1234, 98765, 31337]
const STEPS := 600

# Same scripted input every arm: run forward with a hop every 90 ticks for 12 ticks.
func _stream() -> Array:
	var out: Array = []
	for t in STEPS:
		out.append({"move_x": 96, "move_z": 24,
				"buttons": (1 if t % 90 < 12 else 0),
				"aim_x": 0.0, "aim_z": 1.0, "app": 0})
	return out

class ScriptedWorld:
	extends WorldScript
	var stream: Array = []
	var i := 0
	func _capture_input():
		var a: Dictionary = stream[mini(i, stream.size() - 1)]
		i += 1
		return a

# Sim-only arm: every presentation pass is a no-op and the rig is nulled after build,
# so step() pays only the sim plus the always-on stat feeds.
class SimOnlyWorld:
	extends ScriptedWorld
	func _player_pass() -> void:
		pass
	func _billboard_pass(_dt: float, _ev: Array = []) -> void:
		pass
	func _view_pass() -> void:
		pass
	func _fx_events(_ev: Array) -> void:
		pass
	func _sync_hud() -> void:
		pass

func _root() -> Node:
	var ml := Engine.get_main_loop()
	return (ml as SceneTree).root if ml is SceneTree else null

func _drop(world) -> void:
	world.teardown()
	if world.get_parent() != null:
		world.get_parent().remove_child(world)
	world.free()

func _planned_enemies(seed: int, level: int) -> int:
	var w = WorldScript.new()
	w._api = ContentApiScript.load()
	var plan: Dictionary = w._resolve_run(seed, level, {})
	w.free()
	if plan.is_empty():
		return -1
	var n := 0
	for id in (plan.get("votes", {}) as Dictionary).keys():
		n += int(plan["votes"][id])
	return n

func run() -> Array[String]:
	var f: Array[String] = []
	var best_tiles := {"level": 0, "seed": 0, "tiles": -1}
	var best_mines := {"level": 0, "seed": 0, "mines": -1}
	var best_enemies := {"level": 0, "seed": 0, "enemies": -1}
	for level in LEVELS:
		for seed in SEEDS:
			var t0 := Time.get_ticks_usec()
			var lv: Dictionary = VoidGenScript.generate(seed, level, 1, 0)
			var gen_ms := float(Time.get_ticks_usec() - t0) / 1000.0
			if lv.is_empty():
				f.append("generate returned {} at level %d seed %d" % [level, seed])
				continue
			var mines := 0
			for g in lv["gifts"]:
				if int(g["occ"]) == 1:
					mines += 1
			var planned := _planned_enemies(seed, level)
			var tiles: int = (lv["tiles"] as Array).size()
			print("SWEEP level=%d seed=%d tiles=%d gifts=%d mines=%d pieces=%d plan_enemies=%d gen_ms=%.1f hash=%s" % [
					level, seed, tiles, (lv["gifts"] as Array).size(), mines,
					(lv["pieces"] as Array).size(), planned, gen_ms,
					VoidGenScript.level_hash(lv).substr(0, 12)])
			if tiles > int(best_tiles["tiles"]):
				best_tiles = {"level": level, "seed": seed, "tiles": tiles}
			if mines > int(best_mines["mines"]):
				best_mines = {"level": level, "seed": seed, "mines": mines}
			if planned > int(best_enemies["enemies"]):
				best_enemies = {"level": level, "seed": seed, "enemies": planned}
	print("SWEEP-BEST tiles level=%d seed=%d tiles=%d" % [best_tiles["level"], best_tiles["seed"], best_tiles["tiles"]])
	print("SWEEP-BEST mines level=%d seed=%d mines=%d" % [best_mines["level"], best_mines["seed"], best_mines["mines"]])
	print("SWEEP-BEST enemies level=%d seed=%d plan_enemies=%d" % [best_enemies["level"], best_enemies["seed"], best_enemies["enemies"]])

	# Part B: the largest level, timed with the full presentation attached.
	var full := _time_arm(f, "FULL", int(best_tiles["seed"]), int(best_tiles["level"]), false)
	# Part C: the same level, sim passes only.
	var sim_only := _time_arm(f, "SIMONLY", int(best_tiles["seed"]), int(best_tiles["level"]), true)
	if not full.is_empty() and not sim_only.is_empty():
		print("PERF view_overhead mean_ms=%.4f worst_ms=%.4f (FULL - SIMONLY)" % [
				float(full["mean"]) - float(sim_only["mean"]),
				float(full["worst"]) - float(sim_only["worst"])])

	# The most-mines combo, when it differs - the mines path is the per-tick O(mines) arm.
	if int(best_mines["level"]) != int(best_tiles["level"]) or int(best_mines["seed"]) != int(best_tiles["seed"]):
		_time_arm(f, "FULL-MINES", int(best_mines["seed"]), int(best_mines["level"]), false)
	return f

func _time_arm(f: Array[String], tag: String, seed: int, level: int, sim_only: bool) -> Dictionary:
	var world = (SimOnlyWorld.new() if sim_only else ScriptedWorld.new())
	world.stream = _stream()
	var root := _root()
	if root != null:
		root.add_child(world)
	var b0 := Time.get_ticks_usec()
	var ok: bool = world.build(seed, level)
	var build_ms := float(Time.get_ticks_usec() - b0) / 1000.0
	if not ok:
		f.append("%s: build failed at level %d seed %d" % [tag, level, seed])
		_drop(world)
		return {}
	if sim_only:
		world.rig = null
	var worst := 0.0
	var worst_tick := -1
	var total := 0.0
	var alive_total := 0.0
	var alive_worst := 0.0
	var alive_n := 0
	var death_tick := -1
	for t in STEPS:
		var s0 := Time.get_ticks_usec()
		world.step(DT)
		var ms := float(Time.get_ticks_usec() - s0) / 1000.0
		total += ms
		if ms > worst:
			worst = ms
			worst_tick = t
		if bool(world._run_over_emitted):
			if death_tick < 0:
				death_tick = t
		else:
			alive_total += ms
			alive_n += 1
			if ms > alive_worst:
				alive_worst = ms
	var roster_n := 0
	for r in world._roster:
		roster_n += int(r["count"])
	print("PERF %s seed=%d level=%d build_ms=%.1f tiles=%d mines=%d gifts=%d planned_enemies=%d" % [
			tag, seed, level, build_ms, (world.lv["tiles"] as Array).size(),
			int(world.lstate.mines.ids.size()), int(world.lstate.gifts.total_real), roster_n])
	print("PERF %s mean_ms=%.4f worst_ms=%.4f worst_tick=%d budget_ms=16.67 steps=%d" % [
			tag, total / float(STEPS), worst, worst_tick, STEPS])
	print("PERF %s alive_n=%d alive_mean_ms=%.4f alive_worst_ms=%.4f death_tick=%d" % [
			tag, alive_n, alive_total / maxf(float(alive_n), 1.0), alive_worst, death_tick])
	_drop(world)
	return {"mean": total / float(STEPS), "worst": worst, "alive_mean": alive_total / maxf(float(alive_n), 1.0)}
