#
# The telegraph list does not grow without bound over a long run, and the
# bound never retires a footprint that is still live.
#
# SR-4 expiry (pinned by test_telegraph_expiry.gd, unchanged): a footprint
# expires at start + max(total, 1) and a LIVE footprint still blocks the
# scheduling gate. On top of that, step() prunes rows TELEGRAPH_RETENTION_TICKS
# past their own window so the list stays bounded at the telegraph rate x
# (window + retention) instead of walking the whole history of a long run.
#
# Negative control for the growth proof: the asserted bound (< 1400) sits far
# below the number of rows fired across the run (2400), so with the prune
# removed the list reaches the number fired and the growth check fails.

extends RefCounted

const EnemyRuntime := preload("res://sim/enemy_runtime.gd")
const Util := preload("res://tests/sim_testutil.gd")

const DT := 1.0 / 60.0
# far above rate x (window + retention + one prune interval), far below fired
const GROWTH_BOUND := 1400
const TOTAL_FIRED := 2400
const FIRE_TICKS := 30


func run() -> Array[String]:
	var f: Array[String] = []
	_list_stays_bounded(f)
	_live_footprint_blocks_after_bound(f)
	_expired_footprint_free_after_bound(f)
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


func _fire(rt, ticks: int) -> void:
	rt.telegraph({"id": "probe"}, "probe_patch",
			{"shape": "circle", "cx": 0.5, "cz": 0.5, "r": 2.0}, ticks)


func _mk_rt() -> Array:
	var w := _arena()
	var ctl = _spent_ctl(w)
	var rt = EnemyRuntime.new()
	rt.setup(_level(), w, [ctl], 1234)
	return [rt, ctl]


# One short telegraph fired EVERY tick for TOTAL_FIRED ticks: without a bound
# the list reaches TOTAL_FIRED rows; with the prune it must settle far below.
func _list_stays_bounded(f: Array[String]) -> void:
	var pair := _mk_rt()
	var rt = pair[0]
	for i in range(TOTAL_FIRED):
		_fire(rt, FIRE_TICKS)
		rt.step(DT)
	var n: int = rt.telegraphs.size()
	if n >= GROWTH_BOUND:
		f.append("bound: %d telegraph rows retained after %d ticks, want < %d"
				% [n, TOTAL_FIRED, GROWTH_BOUND])
	if n >= TOTAL_FIRED:
		f.append("bound: the list grew without bound (%d rows for %d fired)"
				% [n, TOTAL_FIRED])


# A footprint that is still live (fired long ago, total far ahead of the tick)
# must keep blocking the gate even after the prune retired many other rows.
func _live_footprint_blocks_after_bound(f: Array[String]) -> void:
	var pair := _mk_rt()
	var rt = pair[0]
	_fire(rt, 10000)   # the long-lived footprint covering the player
	var saw_the_row := false
	for i in range(TOTAL_FIRED):
		_fire(rt, FIRE_TICKS)   # short rows exercise the prune
		rt.step(DT)
	for t in rt.telegraphs:
		if int(t.get("total", 0)) == 10000:
			saw_the_row = true
	if not saw_the_row:
		f.append("bound: the live 10000-tick row was pruned while still live")
	var live_rows := 0
	for t in rt._live_telegraphs():
		if int(t.get("total", 0)) == 10000:
			live_rows += 1
	if live_rows != 1:
		f.append("bound: the live 10000-tick row appears %d times in the live set, want 1"
				% live_rows)
	var gate: Dictionary = rt.arbiter_evaluate(_gate_cfg(), 0)
	if bool(gate.get("may_appear", false)):
		f.append("bound: a live footprint stopped blocking the gate after the prune")


# An expired footprint stops blocking the gate, and its row is retired once
# it ages TELEGRAPH_RETENTION_TICKS past the end of its own window.
func _expired_footprint_free_after_bound(f: Array[String]) -> void:
	var pair := _mk_rt()
	var rt = pair[0]
	_fire(rt, FIRE_TICKS)
	for i in range(300):
		rt.step(DT)
	var gate: Dictionary = rt.arbiter_evaluate(_gate_cfg(), 0)
	if not bool(gate.get("may_appear", false)):
		f.append("expiry: a telegraph that ended 300 ticks in still vetoes the gate")
	for i in range(EnemyRuntime.TELEGRAPH_RETENTION_TICKS + 120):
		rt.step(DT)
	var found := false
	for t in rt.telegraphs:
		if int(t.get("total", 0)) == FIRE_TICKS and int(t.get("tick", -1)) == 0:
			found = true
	if found:
		f.append("bound: a row fired at tick 0 survived %d ticks past its window"
				% (EnemyRuntime.TELEGRAPH_RETENTION_TICKS + 120))
