extends RefCounted
#
# W12-E: DETERMINISM - same seed, same level, same input stream, same run.
#   Part A: build the same (seed, level) twice and assert the level dict is byte-identical
#           in its canonical text form (terrain/voidgen.gd to_text / level_hash).
#   Part B: step two worlds built from the same seed through the same scripted input stream
#           for 600 ticks; assert the enemy rows, the player row and the event stream are
#           identical every tick (concatenated canonical lines, hashed with sha256).
#   Part C: negative control - rebuild with ONE input tick changed (tick 100: move axes
#           shifted, jump bit flipped) and assert the streams DIVERGE, so Part B is not
#           trivially equal.
# 5 seeds x 3 levels = 15 combos; every combo prints its level hash and run hash.
# All three parts run with the presentation attached (world.build adds the views).

const VoidGenScript := preload("res://terrain/voidgen.gd")
const VoidRngScript := preload("res://terrain/void_rng.gd")
const WorldScript := preload("res://app/world.gd")
const DT := 1.0 / 60.0
const SEEDS := [101, 202, 303, 404, 505]
const LEVELS := [1, 10, 20]
const TICKS := 600
const PERTURB_TICK := 100

# Same (seed, level) -> same stream. Held headings would also work; fresh axes per tick
# exercises reversal and re-acceleration every frame.
func _stream(seed: int, level: int) -> Array:
	var rng := VoidRngScript.new(VoidRngScript.mix(seed, 90001 + level))
	var out: Array = []
	for t in TICKS:
		var btn := 0
		if rng.chance(1, 30):
			btn = btn | 1
		out.append({"move_x": rng.ri(-96, 96), "move_z": rng.ri(-96, 96),
				"buttons": btn, "aim_x": rng.ri(-127, 127) / 127.0,
				"aim_z": rng.ri(-127, 127) / 127.0, "app": 0})
	return out

func _perturbed(stream: Array) -> Array:
	var out: Array = []
	for t in stream.size():
		var src: Dictionary = stream[t]
		if t == PERTURB_TICK:
			var a := src.duplicate(true)
			a["move_x"] = int(a["move_x"]) + 100
			a["move_z"] = int(a["move_z"]) - 100
			a["buttons"] = int(a["buttons"]) ^ 1
			out.append(a)
		else:
			out.append(src)
	return out

class ScriptedWorld:
	extends WorldScript
	var stream: Array = []
	var i := 0
	var cur_tick := -1
	var tick_events: Array = []   # one str(ev) per _fx_events call, in call order
	func _capture_input():
		var a: Dictionary = stream[mini(i, stream.size() - 1)]
		i += 1
		cur_tick = i - 1
		return a
	func _fx_events(ev: Array) -> void:
		tick_events.append(str(ev))
		super(ev)

func _root() -> Node:
	var ml := Engine.get_main_loop()
	return (ml as SceneTree).root if ml is SceneTree else null

func _drop(world) -> void:
	world.teardown()
	if world.get_parent() != null:
		world.get_parent().remove_child(world)
	world.free()

# One tick of state, three components (player / events / rows) kept separate so the
# failure message can say which stream diverged. ev_str is this tick's captured events.
func _components(world, ev_str: String) -> Array:
	var c = world.ctl
	var player := "%s|%s|%s|%s|%s|%s|%s|%s|%s" % [
		str(c.x), str(c.y), str(c.z), str(c.vx), str(c.vy), str(c.vz),
		str(c.grounded), str(c.dead), str(c.charges)]
	var events: String = ev_str
	var rows: Array = []
	for e in world.rt.enemies:
		var keys: Array = e.keys()
		keys.sort()
		var kv: Array = []
		for k in keys:
			var v = e[k]
			var ty := typeof(v)
			if ty == TYPE_INT or ty == TYPE_FLOAT or ty == TYPE_BOOL or ty == TYPE_STRING:
				kv.append("%s=%s" % [k, str(v)])
		rows.append("{" + ",".join(kv) + "}")
	return [player, events, ";".join(rows)]

func _run_world(f: Array[String], tag: String, seed: int, level: int, stream: Array) -> Dictionary:
	var world = ScriptedWorld.new()
	world.stream = stream
	var root := _root()
	if root != null:
		root.add_child(world)
	if not world.build(seed, level):
		f.append("%s: build failed at level %d seed %d" % [tag, level, seed])
		_drop(world)
		return {}
	var lines: Array = []
	var p_lines: Array = []
	var e_lines: Array = []
	var r_lines: Array = []
	for t in TICKS:
		var n0: int = world.tick_events.size()
		world.step(DT)
		# this tick's events: whatever _fx_events appended during that step ([] if the run died)
		var ev_str := "[" + ",".join(world.tick_events.slice(n0)) + "]" if world.tick_events.size() > n0 else "[]"
		var comp: Array = _components(world, ev_str)
		p_lines.append(comp[0])
		e_lines.append(comp[1])
		r_lines.append(comp[2])
		lines.append("T %d P %s E %s R %s" % [t, comp[0], comp[1], comp[2]])
	var out := {
		"level_text": VoidGenScript.to_text(world.lv),
		"level_hash": VoidGenScript.level_hash(world.lv),
		"player": "\n".join(p_lines),
		"events": "\n".join(e_lines),
		"rows": "\n".join(r_lines),
	}
	out["log"] = "\n".join(lines)
	out["run_hash"] = (out["log"] as String).sha256_text()
	_drop(world)
	return out

func _diff_ticks(a_lines: String, b_lines: String) -> Array:
	var a: PackedStringArray = a_lines.split("\n")
	var b: PackedStringArray = b_lines.split("\n")
	var out: Array = []
	for i in range(mini(a.size(), b.size())):
		if a[i] != b[i]:
			out.append(i)
	return out

	if a.size() != b.size():
		out.append(mini(a.size(), b.size()))
	return out

func run() -> Array[String]:
	var f: Array[String] = []
	for level in LEVELS:
		for seed in SEEDS:
			_one(f, seed, level)
	return f

func _one(f: Array[String], seed: int, level: int) -> void:
	var stream := _stream(seed, level)
	var tag := "seed=%d level=%d" % [seed, level]
	var a := _run_world(f, "A(" + tag + ")", seed, level, stream)
	if a.is_empty():
		return
	var b := _run_world(f, "B(" + tag + ")", seed, level, stream)
	if b.is_empty():
		return

	# Part A: the level dict is byte-identical in canonical text.
	if str(a["level_text"]) != str(b["level_text"]):
		f.append("%s: level canonical text differs between identical builds" % tag)
	if str(a["level_hash"]) != str(b["level_hash"]):
		f.append("%s: level hash differs (%s vs %s)" % [tag, a["level_hash"], b["level_hash"]])

	# Part B: identical runs.
	var rows_diff := _diff_ticks(str(a["rows"]), str(b["rows"]))
	var player_diff := _diff_ticks(str(a["player"]), str(b["player"]))
	var events_diff := _diff_ticks(str(a["events"]), str(b["events"]))
	if not rows_diff.is_empty():
		f.append("%s: enemy rows diverge at tick %d (and %d more)" % [tag, rows_diff[0], rows_diff.size() - 1])
	if not player_diff.is_empty():
		f.append("%s: player row diverges at tick %d (and %d more)" % [tag, player_diff[0], player_diff.size() - 1])
	if not events_diff.is_empty():
		f.append("%s: event stream diverges at tick %d (and %d more)" % [tag, events_diff[0], events_diff.size() - 1])
	print("DET level seed=%d level=%d level_hash=%s" % [seed, level, a["level_hash"]])
	print("DET run   seed=%d level=%d run_hash=%s player_diff=%d events_diff=%d rows_diff=%d" % [
			seed, level, a["run_hash"], player_diff.size(), events_diff.size(), rows_diff.size()])
	# anti-vacuous: the 600-tick run must have spawned bodies (enemies always arrive by tick 360),
	# so an identical-logs outcome can never come from an empty simulation
	if str(a["events"]).find("enemy_spawn") == -1:
		f.append("%s: no enemy_spawn in 600 ticks - the run did not exercise the sim" % tag)

	# Part C: negative control - one input tick changed, streams must diverge.
	var c := _run_world(f, "C(" + tag + ")", seed, level, _perturbed(stream))
	if c.is_empty():
		return
	var log_c := str(c["log"])
	if log_c == str(a["log"]):
		f.append("%s: perturbed run produced the IDENTICAL stream (input change had no effect at tick %d)" % [tag, PERTURB_TICK])
		print("DET perturb seed=%d level=%d DIVERGES=no" % [seed, level])
		return
	var diffs := _diff_ticks(str(a["log"]), log_c)
	var first_diff: int = diffs[0] if not diffs.is_empty() else -1
	if first_diff < PERTURB_TICK:
		f.append("%s: perturbed stream diverged at tick %d, before the change at tick %d" % [tag, first_diff, PERTURB_TICK])
	print("DET perturb seed=%d level=%d run_hash=%s first_diff=%d diff_ticks=%d" % [
			seed, level, c["run_hash"], first_diff, diffs.size()])
