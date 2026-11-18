extends RefCounted
#
# The enemy body mirror (T-032: world["enemies"]) is the list SR-4's no_enemy_body_within,
# the D-059 safe-tile check and the threat radar read; the LIVE rows in EnemyRuntime.enemies
# are what behaviors move and what the contact kill reads. The two only agreed at spawn
# before this test: a mover wrote the row and left the mirror on its spawn tile (so a
# respawn tile was "clear" of a body standing on it, and the 12 u requirement was satisfied
# by the 25 u spawn rule alone), and D-073's arrival push moved the mirror, not the body.
#
# Asserted here, on the runtime only:
#   - a row that moves has its mirror follow on that runtime step;
#   - push_bodies() moves the LIVE row to exactly the radius and re-syncs its mirror
#     (inside the radius only, y untouched, a body on the origin pushed to +x);
#   - setup() hands each controller `push_hook` = this runtime's push_bodies, the call the
#     Last Light save makes, and tolerates a controller row that carries no hook.

const EnemyRuntime := preload("res://sim/enemy_runtime.gd")
const Util := preload("res://tests/sim_testutil.gd")

const DT := 1.0 / 60.0


func run() -> Array[String]:
	var f: Array[String] = []
	_mirror_follows_the_row(f)
	_push_moves_the_live_row(f)
	_push_hook_is_wired(f)
	return f


# A controller row with exactly the cross-file D-073 contract and nothing else: the runtime
# must set its push_hook, and the hook must be callable as push_hook.call(Vector3, float).
class HookStub:
	extends RefCounted
	var push_hook: Callable = Callable()


# ---- fixtures ---------------------------------------------------------------

func _cfg() -> Dictionary:
	return {"world_height": 1.0, "frame_w": 256, "frame_h": 256,
			"body_rect": [0, 0, 256, 256], "contact_kill": false, "cycle_ticks": 0}


func _tiles() -> Array:
	var tiles: Array = []
	for x in range(-16, 17):
		for z in range(-4, 5):
			tiles.append([x, z, 0])
	return tiles


func _level() -> Dictionary:
	var tiles: Array = []
	for t in _tiles():
		tiles.append([t[0], t[1], t[2], 0, 0])
	return {"beacon": [0, 0, 0], "spawns": [[0, 0, 0]], "anchors": [], "tiles": tiles,
			"props": [], "pads": []}


func _world() -> Dictionary:
	return Util.world_from_tiles(_tiles())


func _spawn(rt, id: String, pos: Vector3) -> Dictionary:
	return rt.spawn_at(id, id, EnemyRuntime.FixtureBehavior.new(), _cfg(), pos)


func _expect_row(f: Array[String], row: Dictionary, what: String,
		x: float, y: float, z: float) -> void:
	if absf(float(row["x"]) - x) > 1e-6 or absf(float(row["z"]) - z) > 1e-6:
		f.append("%s: at (%.4f, %.4f), want (%.4f, %.4f)" % [what, float(row["x"]),
				float(row["z"]), x, z])
	if absf(float(row["y"]) - y) > 1e-6:
		f.append("%s: y %.4f, want %.4f (nothing here changes y)" % [what, float(row["y"]), y])


# The mirror of `row` must read exactly the live row.
func _expect_mirror(f: Array[String], row: Dictionary, what: String) -> void:
	var m: Variant = row.get("body_mirror", null)
	if not (m is Dictionary):
		f.append("%s: row %s carries no body_mirror" % [what, str(row.get("id", "?"))])
		return
	var md: Dictionary = m
	if absf(float(md["x"]) - float(row["x"])) > 1e-6 \
			or absf(float(md["y"]) - float(row["y"])) > 1e-6 \
			or absf(float(md["z"]) - float(row["z"])) > 1e-6:
		f.append("%s: mirror (%.4f, %.4f, %.4f) != live row (%.4f, %.4f, %.4f)" % [what,
				float(md["x"]), float(md["y"]), float(md["z"]),
				float(row["x"]), float(row["y"]), float(row["z"])])
	var want_r: float = float(row["diameter_u"]) * 0.5
	if absf(float(md["r"]) - want_r) > 1e-6:
		f.append("%s: mirror r %.4f, want %.4f" % [what, float(md["r"]), want_r])


# ---- the mirror follows a mover ---------------------------------------------

func _mirror_follows_the_row(f: Array[String]) -> void:
	var w := _world()
	var rt = EnemyRuntime.new()
	rt.setup(_level(), w, [], 4242)
	var row: Dictionary = _spawn(rt, "mover", Vector3(20.5, 0.0, 0.5))
	var mirror: Variant = row.get("body_mirror", null)
	if not (mirror is Dictionary):
		f.append("mirror: the spawn wrote no body_mirror on the row")
		return
	# the same object, so a mirror write is visible to everything reading the world
	if w["enemies"].size() != 1 or not is_same(w["enemies"][0], mirror):
		f.append("mirror: the spawn did not append the row's own mirror to world[\"enemies\"]")
	_expect_mirror(f, row, "mirror: at spawn")
	# a mover writes the ROW only - the path every floater takes
	# (Api.move_toward -> rt.move_toward): 120 u/s over one tick = 2.0 u
	rt.move_toward(row, 22.5, 0.5, 120.0, 0.0)
	_expect_row(f, row, "mirror: the fixture move", 22.5, 0.0, 0.5)
	rt.step(DT)
	_expect_mirror(f, row, "mirror: after one step")
	# the readers' question in the safe-tile check's own terms: no ghost at the spawn point
	if absf(float(w["enemies"][0]["x"]) - float(row["x"])) > 1e-6:
		f.append("mirror: world[\"enemies\"][0].x %.4f after the step, want %.4f" % [
				float(w["enemies"][0]["x"]), float(row["x"])])


# ---- D-073: the arrival push moves the LIVE rows ----------------------------

func _push_moves_the_live_row(f: Array[String]) -> void:
	var w := _world()
	var rt = EnemyRuntime.new()
	rt.setup(_level(), w, [], 4242)
	var centre := Vector3(20.5, 0.0, 0.5)
	var near: Dictionary = _spawn(rt, "near", Vector3(25.5, 1.0, 0.5))
	var on: Dictionary = _spawn(rt, "on", centre)
	var diag: Dictionary = _spawn(rt, "diag", Vector3(23.5, 0.0, 4.5))
	var far: Dictionary = _spawn(rt, "far", Vector3(40.5, 0.0, 0.5))
	rt.push_bodies(centre, 8.0)
	# 5 u east of the centre: out to exactly 8 u on its own bearing, y untouched
	_expect_row(f, near, "push: a body 5 u east", 28.5, 1.0, 0.5)
	# exactly on the centre: no bearing to keep, so it goes to +x
	_expect_row(f, on, "push: a body on the centre", 28.5, 0.0, 0.5)
	# the 3-4-5 bearing scaled to 8 u: (3/5, 4/5) * 8 = (4.8, 6.4) from the centre
	_expect_row(f, diag, "push: a body on a diagonal", 25.3, 0.0, 6.9)
	# outside the radius: untouched (the bound is strictly inside)
	_expect_row(f, far, "push: a body outside", 40.5, 0.0, 0.5)
	# every mirror agrees with its live row: nothing left claiming the old point
	for e in rt.enemies:
		_expect_mirror(f, e, "push: %s" % str(e["id"]))


# ---- the cross-file contract: the controller's push hook --------------------

func _push_hook_is_wired(f: Array[String]) -> void:
	var w := _world()
	# the contract's own shape: a controller row with `push_hook` receives this runtime's push
	var stub := HookStub.new()
	var rt = EnemyRuntime.new()
	rt.setup(_level(), w, [stub], 4242)
	if not stub.push_hook.is_valid():
		f.append("hook: setup() did not hand the controller a push hook")
		return
	var row: Dictionary = _spawn(rt, "near", Vector3(25.5, 0.0, 0.5))
	# the Last Light save's call: push_hook.call(Vector3(x, y, z), 8.0)
	stub.push_hook.call(Vector3(20.5, 0.0, 0.5), 8.0)
	_expect_row(f, row, "hook: the save's push", 28.5, 0.0, 0.5)
	_expect_mirror(f, row, "hook: the save's push")
	# the shipped controller row is wired by the same setup(); the property is probed so a
	# controller without it (an older row) fails nothing here
	var ctl = Util.ControllerScript.new()
	var rt2 = EnemyRuntime.new()
	rt2.setup(_level(), w, [ctl], 4242)
	if rt2.controllers.size() != 1:
		f.append("hook: setup() dropped the controller row it was given")
	for prop in ctl.get_property_list():
		if str(prop.get("name", "")) == "push_hook":
			var hook: Variant = ctl.get("push_hook")
			if not (hook is Callable) or not (hook as Callable).is_valid():
				f.append("hook: the shipped controller row's push_hook was left unset")
			break
