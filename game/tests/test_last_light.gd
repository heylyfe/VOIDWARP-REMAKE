extends RefCounted
#
# Last Light (ticket T-012, DESIGN section 3.1, D-053, D-057, D-073): once per run,
# only while holding >= 1 void charge; saves a kill by an enemy, a tripmine or the
# nuke by teleporting to the beacon dais with the charges held and 2.0 s
# invulnerability; never triggers at 0 charges; never triggers on a void fall; the
# arrival pushes enemy bodies within 8 u out to exactly 8 u (through the controller's
# push_hook: the dais centre as the origin and exactly 8 u as the radius).
# HUD icon: lit while armed, dim at 0 charges, grey once spent.

const Util := preload("res://tests/sim_testutil.gd")


func run() -> Array[String]:
	var f: Array[String] = []
	_test_save_at_2(f)
	_test_save_at_1(f)
	_test_nothing_at_0(f)
	_test_void_fall_never_triggers(f)
	_test_second_hit_after_spent(f)
	_test_hud_and_push(f)
	return f


func _one_tile_world() -> Dictionary:
	var w := Util.world_from_tiles([[0, 0, 0]])
	w["dais"] = [0, 0, 0]
	return w


func _fresh(kit: String) -> RefCounted:
	var ctl = Util.ControllerScript.new()
	ctl.setup(kit, Util.consts())
	ctl.place(_one_tile_world())
	return ctl


func _test_save_at_2(f: Array[String]) -> void:
	var ctl = _fresh("dasher")
	var w := _one_tile_world()
	if ctl.hud_last_light() != "lit":
		f.append("lastlight: HUD %s at 2 charges unspent, want lit" % ctl.hud_last_light())
	var ev: Array = []
	var saved: bool = ctl.try_kill("D-KIWI", "kiwi cat", w, ev)
	if not saved:
		f.append("lastlight: lethal enemy hit at 2 charges was not saved")
	if ctl.dead:
		f.append("lastlight: player died despite the save")
	if ctl.charges != 2:
		f.append("lastlight: save spent a charge (%d held)" % ctl.charges)
	if not ctl.last_light_spent:
		f.append("lastlight: save did not spend the one per-run use")
	if absf(ctl.x - 0.5) > 1e-6 or absf(ctl.z - 0.5) > 1e-6 or absf(ctl.y) > 1e-6:
		f.append("lastlight: save did not teleport to the dais (%.2f %.2f %.2f)" % [ctl.x, ctl.y, ctl.z])
	if absf(ctl.invuln - 2.0) > 1e-6:
		f.append("lastlight: arrival invulnerability %.4f, want 2.0" % ctl.invuln)
	if not _has(ev, "last_light_save"):
		f.append("lastlight: no last_light_save event emitted")
	if ctl.hud_last_light() != "grey":
		f.append("lastlight: HUD %s once spent, want grey" % ctl.hud_last_light())


func _test_save_at_1(f: Array[String]) -> void:
	var ctl = _fresh("dasher")
	var w := _one_tile_world()
	ctl.charges = 1
	if ctl.hud_last_light() != "lit":
		f.append("lastlight: HUD %s at 1 charge unspent, want lit" % ctl.hud_last_light())
	var ev: Array = []
	if not ctl.try_kill("D-MINE", "gift Larper (Tripmine)", w, ev):
		f.append("lastlight: lethal tripmine hit at 1 charge was not saved")
	if ctl.charges != 1 or ctl.dead or not ctl.last_light_spent:
		f.append("lastlight: 1-charge save state wrong (charges=%d dead=%s spent=%s)" % [
			ctl.charges, str(ctl.dead), str(ctl.last_light_spent)])


func _test_nothing_at_0(f: Array[String]) -> void:
	var ctl = _fresh("dasher")
	var w := _one_tile_world()
	ctl.charges = 0
	if ctl.hud_last_light() != "dim":
		f.append("lastlight: HUD %s at 0 charges unspent, want dim" % ctl.hud_last_light())
	var ev: Array = []
	if ctl.try_kill("D-KIWI", "kiwi cat", w, ev):
		f.append("lastlight: Last Light fired at 0 charges")
	if not ctl.dead:
		f.append("lastlight: kill at 0 charges did not kill")
	if _last(ev, "death").is_empty() or _last(ev, "death")[0]["code"] != "D-KIWI":
		f.append("lastlight: death at 0 charges has wrong code")


func _test_void_fall_never_triggers(f: Array[String]) -> void:
	# a void fall with a charge spends the charge and keeps Last Light unspent
	var ctl = _fresh("dasher")
	var w := _one_tile_world()
	ctl.charges = 1
	ctl.x = 50.5
	ctl.y = 0.0
	ctl.grounded = false
	ctl.cur_key = ""
	var ev: Array = []
	for i in range(400):
		var e2 = ctl.step(Util.DT, Util.mk_in(), w)
		for e in e2:
			ev.append(e)
		if ctl.respawn_t >= 0.0:
			break
	if not _has(ev, "void_fall") or ctl.last_light_spent:
		f.append("lastlight: void fall consumed Last Light (spent=%s)" % str(ctl.last_light_spent))
	# a void fall at 0 charges is D-VOID even with Last Light unspent
	var ctl2 = _fresh("dasher")
	ctl2.charges = 0
	ctl2.x = 50.5
	ctl2.y = 0.0
	ctl2.grounded = false
	ctl2.cur_key = ""
	var ev2: Array = []
	for i in range(400):
		var e3 = ctl2.step(Util.DT, Util.mk_in(), w)
		for e in e3:
			ev2.append(e)
		if ctl2.dead:
			break
	if not ctl2.dead or ctl2.dead_code != "D-VOID" or ctl2.last_light_spent:
		f.append("lastlight: void fall at 0 charges (dead=%s code=%s spent=%s)" % [
			str(ctl2.dead), ctl2.dead_code, str(ctl2.last_light_spent)])


func _test_second_hit_after_spent(f: Array[String]) -> void:
	var ctl = _fresh("dasher")
	var w := _one_tile_world()
	ctl.charges = 2
	var ev: Array = []
	if not ctl.try_kill("D-KIWI", "kiwi cat", w, ev):
		f.append("lastlight: the first save failed")
	Util.run_ticks(ctl, w, 140, func(_c, _i): return Util.mk_in())
	var saved2: bool = ctl.try_kill("D-ISAGI", "Isagi", w, ev)
	if saved2 or not ctl.dead:
		f.append("lastlight: the second lethal hit after the save did not kill")
	if _last(ev, "death").is_empty() or _last(ev, "death")[0]["code"] != "D-ISAGI":
		f.append("lastlight: second-hit death code wrong")


func _test_hud_and_push(f: Array[String]) -> void:
	var ctl = _fresh("dasher")
	var w := _one_tile_world()
	# dais is [x, z, y] and deliberately asymmetric here: the push origin must follow the
	# teleport's own mapping (x = d[0] + 0.5, y = d[2] * 0.5, z = d[1] + 0.5).
	w["dais"] = [3, 2, 1]
	ctl.charges = 1
	# D-073's promise is the push the world's owner performs, so the test pins the CALL
	# (the dais centre and exactly 8 u), not arithmetic on dicts the test itself built.
	var calls: Array = []
	ctl.push_hook = func(origin, radius) -> void:
		calls.append({"origin": origin, "radius": radius})
	var mirror_row := {"x": 3.6, "y": 0.5, "z": 2.5}
	w["enemies"] = [mirror_row]
	var ev: Array = []
	if not ctl.try_kill("D-NUKE", "nuke", w, ev):
		f.append("lastlight: nuke kill was not saved at 1 charge")
	if absf(ctl.x - 3.5) > 1e-6 or absf(ctl.y - 0.5) > 1e-6 or absf(ctl.z - 2.5) > 1e-6:
		f.append("lastlight: save did not teleport to the dais (%.2f %.2f %.2f)" % [ctl.x, ctl.y, ctl.z])
	if calls.size() != 1:
		f.append("lastlight: the D-073 push ran %d time(s), want exactly 1" % calls.size())
	else:
		var origin: Variant = calls[0]["origin"]
		if not (origin is Vector3):
			f.append("lastlight: the D-073 push origin is not a Vector3")
		else:
			var o: Vector3 = origin
			if absf(o.x - 3.5) > 1e-6 or absf(o.y - 0.5) > 1e-6 or absf(o.z - 2.5) > 1e-6:
				f.append("lastlight: the D-073 push origin %s, want the dais centre (3.5, 0.5, 2.5)" % str(o))
		if absf(float(calls[0]["radius"]) - 8.0) > 1e-9:
			f.append("lastlight: the D-073 push radius %.4f, want exactly 8" % float(calls[0]["radius"]))
	if mirror_row["x"] != 3.6:
		f.append("lastlight: the hook and the mirror fallback both ran (row x=%s)" % str(mirror_row["x"]))
	if ctl.hud_last_light() != "grey":
		f.append("lastlight: HUD %s after the save, want grey" % ctl.hud_last_light())
	# no hook (a hand-made world with no runtime behind it): the fallback still pushes
	# the world dict's rows, which is the only body data such a world carries.
	var ctl2 = _fresh("dasher")
	var w2 := _one_tile_world()
	ctl2.charges = 1
	var near1 := {"x": 2.0, "y": 0.0, "z": 1.5}
	var near2 := {"x": -1.0, "y": 0.5, "z": 0.5}
	var far1 := {"x": -30.0, "y": 0.0, "z": 0.5}
	w2["enemies"] = [near1, near2, far1]
	var ev2: Array = []
	if not ctl2.try_kill("D-NUKE", "nuke", w2, ev2):
		f.append("lastlight: nuke kill was not saved at 1 charge (fallback path)")
	# pushed bodies sit at exactly 8 u (XZ) from the dais centre (0.5, 0.5), y untouched
	for e in [near1, near2]:
		var dx: float = float(e["x"]) - 0.5
		var dz: float = float(e["z"]) - 0.5
		var d: float = sqrt(dx * dx + dz * dz)
		if absf(d - 8.0) > 1e-9:
			f.append("lastlight: fallback body at %.9f u from the dais, want exactly 8" % d)
	if not float(near1["x"]) > 0.5:
		f.append("lastlight: fallback: pushed body did not move radially outward")
	if far1["x"] != -30.0:
		f.append("lastlight: a body beyond 8 u was moved")
	if near1["y"] != 0.0:
		f.append("lastlight: the push changed a body's height")


# ---- small event helpers ------------------------------------------------------------

static func _has(ev: Array, kind: String) -> bool:
	for e in ev:
		if e.get("e", "") == kind:
			return true
	return false


static func _last(ev: Array, kind: String) -> Array:
	var out: Array = []
	for e in ev:
		if e.get("e", "") == kind:
			out.append(e)
	return out
