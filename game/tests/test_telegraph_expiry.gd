#
# SR-4: a telegraph footprint expires when its telegraph ends. The scheduling gate
# (no_targeted_telegraph) must not stay vetoed by a telegraph that fired long ago
# and already landed - the runtime filters footprints by the same clock the view
# uses to stop drawing a telegraph (start tick + total vs the runtime tick).
# A LIVE telegraph must still block the gate (the rule is not a no-op).

extends RefCounted

const EnemyRuntime := preload("res://sim/enemy_runtime.gd")
const Util := preload("res://tests/sim_testutil.gd")
const AddressMeEnemy := preload("res://content/enemies/address_me/enemy.gd")

const DT := 1.0 / 60.0


func run() -> Array[String]:
	var f: Array[String] = []
	_expired_footprint_no_longer_blocks(f)
	_live_footprint_still_blocks(f)
	return f


func _tiles_full() -> Array:
	var tiles: Array = []
	for x in range(-10, 11):
		for z in range(-10, 11):
			tiles.append([x, z, 0, 0, 0])
	return tiles


func _level() -> Dictionary:
	return {"beacon": [0, 0, 0], "spawns": [[0, 0, 0]], "anchors": [],
			"tiles": _tiles_full(), "props": [], "pads": []}


func _arena() -> Dictionary:
	var flat: Array = []
	for t in _tiles_full():
		flat.append([t[0], t[1], t[2]])
	var w := Util.world_from_tiles(flat)
	w["dais"] = [0, 0, 0]
	return w


func _spent_ctl(w: Dictionary):
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	ctl.place(w)
	ctl.try_kill("D-TEST", "test", w, [])
	ctl.invuln = 0.0
	ctl.dead = false
	ctl.place(w)
	return ctl


func _gate_cfg() -> Dictionary:
	return {"arbiter": {"appear_requires": [{"no_targeted_telegraph": true}],
			"yields_to": []}}


# [rt, row, ctl]; the controller sits on the dais tile and never moves.
func _spawn() -> Array:
	var w := _arena()
	var ctl = _spent_ctl(w)
	var rt = EnemyRuntime.new()
	rt.setup(_level(), w, [ctl], 4242)
	var row: Dictionary = rt.spawn_at("address_me", "address me", AddressMeEnemy.new(),
			_gate_cfg(), Vector3(9.5, 0.0, 0.5))
	return [rt, row, ctl]

# Fire a telegraph near the player through the real api path, step past its end,
# and the placement rule (no_targeted_telegraph) must no longer be blocked.
func _expired_footprint_no_longer_blocks(f: Array[String]) -> void:
	var spawned := _spawn()
	var rt = spawned[0]
	var row = spawned[1]
	# the real fire path: stamps tick = now, total = ticks = 30
	rt.telegraph(row, "test_patch",
			{"shape": "circle", "cx": 0.5, "cz": 0.5, "r": 2.0}, 30)
	var gate: Dictionary = rt.arbiter_evaluate(_gate_cfg(), 0)
	if bool(gate.get("may_appear", false)):
		f.append("expiry: the live telegraph did not block the gate at fire time")
	for i in range(45):
		rt.step(DT)
	gate = rt.arbiter_evaluate(_gate_cfg(), 0)
	if not bool(gate.get("may_appear", false)):
		f.append("expiry: the telegraph ended 15+ ticks ago yet still vetoes the gate")


# A live telegraph footprint on the player blocks the placement rule; the rule
# must not become a no-op.
func _live_footprint_still_blocks(f: Array[String]) -> void:
	var spawned := _spawn()
	var rt = spawned[0]
	var row = spawned[1]
	rt.telegraph(row, "test_patch",
			{"shape": "circle", "cx": 0.5, "cz": 0.5, "r": 2.0}, 10000)
	for i in range(120):
		rt.step(DT)
	var gate: Dictionary = rt.arbiter_evaluate(_gate_cfg(), 0)
	if bool(gate.get("may_appear", false)):
		f.append("live: a footprint covering the player did not block the gate")
