extends RefCounted
#
# Regression test for the Api.arbiter_gate wrapper (the T-072 surface as reached by an
# enemy behavior, not the arbiter itself - test_arbiter.gd covers the arbiter).
#
# Why this file exists: T-032 found that Api.arbiter_gate(pending) forwarded THREE
# arguments to EnemyRuntime.arbiter_evaluate(cfg, player_index), which took two. GDScript
# raises "Too many arguments" at the call, so the first enemy to call the gate would have
# crashed at runtime. Nothing caught it because no test and no enemy called the wrapper -
# test_arbiter.gd exercises ArbiterScript directly. The wrapper also passed a
# pre-computed busy_sources() list in the `pending` slot, so a caller's own countdown ids
# were dropped and the telegraphs were counted twice.
#
# Both halves are pinned here: the call must not raise, and `pending` must reach the
# deferral answer.

const EnemyRuntime := preload("res://sim/enemy_runtime.gd")
const Util := preload("res://tests/sim_testutil.gd")

const YIELD_ID := "address_me"


func run() -> Array[String]:
	var f: Array[String] = []
	_gate_callable(f)
	_gate_honours_pending(f)
	_gate_ignores_unrelated_pending(f)
	return f


func _arena() -> Dictionary:
	var tiles: Array = []
	for x in range(-5, 6):
		for z in range(-5, 6):
			tiles.append([x, z, 0])
	var w := Util.world_from_tiles(tiles)
	w["dais"] = [0, 0, 0]
	return w


# A runtime with one row whose cfg carries an arbiter block yielding to YIELD_ID, plus the
# Api bound to that row exactly as a behavior would hold it.
func _fixture() -> Array:
	var w := _arena()
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	ctl.place(w)
	var rt = EnemyRuntime.new()
	rt.setup({}, w, [ctl], 4242)
	var cfg := {"world_height": 1.8, "frame_w": 256, "frame_h": 256,
			"body_rect": [0, 0, 256, 256], "contact_kill": true, "cycle_s": 0.0,
			"preferred_kind": "", "cycle_ticks": 0,
			"arbiter": {"appear_requires": [], "yields_to": [YIELD_ID]}}
	rt.spawn_at("tbd", "TBD", EnemyRuntime.FixtureBehavior.new(), cfg, Vector3(2.1, 0.0, 0.5))
	var api = EnemyRuntime.Api.new()
	api.rt = rt
	api.row = rt.enemies[0]
	return [rt, api]


# The crash case: a zero-argument call must return a Dictionary, not raise.
func _gate_callable(f: Array[String]) -> void:
	var fx := _fixture()
	var api = fx[1]
	var got: Variant = api.arbiter_gate()
	if not (got is Dictionary):
		f.append("arbiterapi: arbiter_gate() returned %s, want a Dictionary" % str(got))
		return
	if not got.has("may_appear") or not got.has("deferred"):
		f.append("arbiterapi: arbiter_gate() keys %s, want may_appear + deferred" % str(got.keys()))


# The caller's own countdown id must reach the deferral answer.
func _gate_honours_pending(f: Array[String]) -> void:
	var fx := _fixture()
	var api = fx[1]
	var got: Dictionary = api.arbiter_gate([YIELD_ID])
	if not bool(got.get("deferred", false)):
		f.append("arbiterapi: pending [%s] did not defer, want deferred true" % YIELD_ID)


# ... and an id the row does not yield to must not defer it.
func _gate_ignores_unrelated_pending(f: Array[String]) -> void:
	var fx := _fixture()
	var api = fx[1]
	var got: Dictionary = api.arbiter_gate(["gin"])
	if bool(got.get("deferred", false)):
		f.append("arbiterapi: pending [gin] deferred a row yielding to %s" % YIELD_ID)
