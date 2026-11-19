extends RefCounted
#
# Field Dressing + the D-073 arrival push, on the controller (this wave's two defects).
#
# Field Dressing (DESIGN.md section 8, D-052, D-086's PARKED row): once per level per
# stack, a void fall costs no charge. Asserted here, through the real fall path:
#   - without the upgrade a fall spends 1 charge (and the event says free = false);
#   - with one stack the fall spends NOTHING, respawns exactly as a paid fall would,
#     and the event carries free = true for the app layer's void_pips.pip_free_fall();
#   - the free fall still rescues at 0 held charges (a free fall is not a death);
#   - the budget is per level per stack: 1 stack = 1 free fall, 2 stacks = 2, and the
#     level-start re-grant (apply_field_dressing again) restores the used budget;
#   - a fall past the budget pays again.
#
# Last Light (PARKED.md row 25 / D-073): a killing blow while the player holds a charge
# teleports to the dais and the enemy INSIDE 8 u is ACTUALLY displaced - through the
# controller's push_hook into a REAL enemy runtime's live rows, not a mirror copy.

const Util := preload("res://tests/sim_testutil.gd")
const EnemyRuntime := preload("res://sim/enemy_runtime.gd")

const DT := 1.0 / 60.0


func run() -> Array[String]:
	var f: Array[String] = []
	_test_without_upgrade(f)
	_test_one_stack(f)
	_test_two_stacks(f)
	_test_free_fall_at_zero_charges(f)
	_test_level_reset(f)
	_test_last_light_push_moves_live_enemy(f)
	return f


# ---- fixtures -----------------------------------------------------------------

func _void_world() -> Dictionary:
	var w := Util.world_from_tiles([[0, 0, 0]])
	w["dais"] = [0, 0, 0]
	return w


func _fresh() -> RefCounted:
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	ctl.place(_void_world())
	return ctl


# Drops the controller into the void and runs until a `kind` event lands.
static func _fall_to_void(ctl, w: Dictionary, ev_out: Array, kind: String) -> void:
	ctl.x = 100.5
	ctl.y = 0.0
	ctl.z = 0.5
	ctl.vx = 0.0
	ctl.vy = 0.0
	ctl.vz = 0.0
	for i in range(400):
		var ev = ctl.step(Util.DT, Util.mk_in(), w)
		for e in ev:
			ev_out.append(e)
		if _last(ev, kind).has("e"):
			return


static func _step_until(ctl, w: Dictionary, ev_out: Array, want: String, max_ticks: int) -> void:
	for i in range(max_ticks):
		var ev = ctl.step(Util.DT, Util.mk_in(), w)
		for e in ev:
			ev_out.append(e)
			if e["e"] == want:
				return


static func _last(ev: Array, kind: String) -> Dictionary:
	for i in range(ev.size() - 1, -1, -1):
		if ev[i].get("e", "") == kind:
			return ev[i]
	return {}


# ---- Field Dressing: without the upgrade, a fall pays -------------------------------

func _test_without_upgrade(f: Array[String]) -> void:
	var ctl = _fresh()
	var w := _void_world()
	var ev: Array = []
	if ctl.field_dressing_stacks != 0 or ctl.field_dressing_uses != 0:
		f.append("field_dressing: a fresh controller holds %d stacks / %d uses, want 0/0" % [
				ctl.field_dressing_stacks, ctl.field_dressing_uses])
	_fall_to_void(ctl, w, ev, "void_fall")
	var vf := _last(ev, "void_fall")
	if ctl.charges != 1:
		f.append("field_dressing: fall without the upgrade left charges=%d, want 1" % ctl.charges)
	if vf.is_empty() or vf.get("free", true) or vf.get("charges", -1) != 1 \
			or vf.get("charges_before", -1) != 2:
		f.append("field_dressing: unpaid fall event not free=false 2->1: %s" % str(vf))
	_step_until(ctl, w, ev, "respawn", 120)
	if ctl.charges != 1:
		f.append("field_dressing: respawn after the paid fall left charges=%d, want 1" % ctl.charges)


# ---- one stack: the first fall is free, the second pays ------------------------------

func _test_one_stack(f: Array[String]) -> void:
	var ctl = _fresh()
	var w := _void_world()
	ctl.apply_field_dressing(1)
	if ctl.field_dressing_stacks != 1 or ctl.field_dressing_uses != 1:
		f.append("field_dressing: apply_field_dressing(1) left %d stacks / %d uses, want 1/1" % [
				ctl.field_dressing_stacks, ctl.field_dressing_uses])
	var ev: Array = []
	_fall_to_void(ctl, w, ev, "void_fall")
	var vf := _last(ev, "void_fall")
	if ctl.charges != 2:
		f.append("field_dressing: a free fall spent a charge (charges=%d, want 2)" % ctl.charges)
	if ctl.field_dressing_uses != 0:
		f.append("field_dressing: the free fall left %d uses, want 0" % ctl.field_dressing_uses)
	if vf.is_empty() or not vf.get("free", false) or vf.get("charges", -1) != 2 \
			or vf.get("charges_before", -1) != 2:
		f.append("field_dressing: free fall event not free=true 2->2: %s" % str(vf))
	# the free fall still respawns: the same wait, the dais, invulnerability
	_step_until(ctl, w, ev, "respawn", 120)
	if not ctl.grounded or absf(ctl.x - 0.5) > 1e-6 or absf(ctl.z - 0.5) > 1e-6:
		f.append("field_dressing: a free fall did not respawn on the dais (%.2f, %.2f)" % [
				ctl.x, ctl.z])
	if ctl.invuln < 1.0 or ctl.respawn_t >= 0.0:
		f.append("field_dressing: a free fall respawned without its invulnerability window")
	# the free fall was a chain break like any void fall
	if _last(ev, "chain_reset").is_empty():
		f.append("field_dressing: the free fall did not emit chain_reset")
	# past the budget, the next fall pays again
	_fall_to_void(ctl, w, ev, "void_fall")
	vf = _last(ev, "void_fall")
	if ctl.charges != 1 or vf.get("free", true):
		f.append("field_dressing: the fall after the budget was spent charged=%d free=%s" % [
				ctl.charges, str(vf.get("free", "?"))])


# ---- two stacks: two free falls, then the third pays ---------------------------------

func _test_two_stacks(f: Array[String]) -> void:
	var ctl = _fresh()
	var w := _void_world()
	ctl.apply_field_dressing(2)
	var ev: Array = []
	for i in range(2):
		_fall_to_void(ctl, w, ev, "void_fall")
		_step_until(ctl, w, ev, "respawn", 120)
		if ctl.charges != 2:
			f.append("field_dressing: free fall %d of 2 spent a charge (charges=%d)" % [
					i + 1, ctl.charges])
			return
	_fall_to_void(ctl, w, ev, "void_fall")
	var vf := _last(ev, "void_fall")
	if ctl.charges != 1 or vf.get("free", true):
		f.append("field_dressing: the third fall of a 2-stack budget was not paid "
				+ "(charges=%d free=%s)" % [ctl.charges, str(vf.get("free", "?"))])


# ---- a free fall rescues at 0 held charges: it is not a death ------------------------

func _test_free_fall_at_zero_charges(f: Array[String]) -> void:
	var ctl = _fresh()
	var w := _void_world()
	ctl.apply_field_dressing(1)
	ctl.charges = 0
	var ev: Array = []
	_fall_to_void(ctl, w, ev, "void_fall")
	var vf := _last(ev, "void_fall")
	if ctl.dead:
		f.append("field_dressing: a free fall at 0 charges killed (D-VOID must not fire)")
	if ctl.charges != 0 or ctl.field_dressing_uses != 0:
		f.append("field_dressing: fall at 0 charges left %d charges / %d uses, want 0/0" % [
				ctl.charges, ctl.field_dressing_uses])
	if vf.is_empty() or not vf.get("free", false):
		f.append("field_dressing: the 0-charge rescue event was not free=true: %s" % str(vf))
	_step_until(ctl, w, ev, "respawn", 120)
	if not ctl.grounded:
		f.append("field_dressing: the 0-charge rescue did not respawn the player")
	# past the budget at 0 charges, the next fall really kills
	_fall_to_void(ctl, w, ev, "death")
	if not ctl.dead or _last(ev, "death").get("code", "") != "D-VOID":
		f.append("field_dressing: a 0-charge fall past the budget did not kill D-VOID")


# ---- the budget is per level: the level-start re-grant restores it --------------------

func _test_level_reset(f: Array[String]) -> void:
	var ctl = _fresh()
	var w := _void_world()
	ctl.apply_field_dressing(1)
	var ev: Array = []
	_fall_to_void(ctl, w, ev, "void_fall")
	_step_until(ctl, w, ev, "respawn", 120)
	if ctl.field_dressing_uses != 0:
		f.append("field_dressing: the stack's use was not consumed (%d left)" % ctl.field_dressing_uses)
	# the content layer's on_level_start handler calls apply_field_dressing with the
	# owned stack total again each level start - the budget is back, charges untouched
	ctl.apply_field_dressing(1)
	if ctl.field_dressing_stacks != 1 or ctl.field_dressing_uses != 1:
		f.append("field_dressing: the level-start re-grant left %d stacks / %d uses, want 1/1" % [
				ctl.field_dressing_stacks, ctl.field_dressing_uses])
	ev = []
	_fall_to_void(ctl, w, ev, "void_fall")
	if ctl.charges != 2 or _last(ev, "void_fall").get("free", true) != true:
		f.append("field_dressing: the new level's first fall was not free (charges=%d)" % ctl.charges)


# ---- PARKED row 25 / D-073: the save's push displaces a LIVE enemy row ---------------

func _push_cfg() -> Dictionary:
	return {"world_height": 1.0, "frame_w": 256, "frame_h": 256,
			"body_rect": [0, 0, 256, 256], "contact_kill": false, "cycle_ticks": 0}


func _push_level() -> Dictionary:
	var tiles: Array = []
	for x in range(-16, 17):
		for z in range(-4, 5):
			tiles.append([x, z, 0, 0, 0])
	return {"beacon": [0, 0, 0], "spawns": [[0, 0, 0]], "anchors": [], "tiles": tiles,
			"props": [], "pads": []}


func _test_last_light_push_moves_live_enemy(f: Array[String]) -> void:
	var w := Util.world_from_tiles([[0, 0, 0]])
	w["dais"] = [0, 0, 0]
	var ctl = _fresh()
	var rt = EnemyRuntime.new()
	# setup() hands the controller its push_hook, the call the Last Light save makes
	rt.setup(_push_level(), w, [ctl], 4242)
	var row: Dictionary = rt.spawn_at("near", "near", EnemyRuntime.FixtureBehavior.new(),
			_push_cfg(), Vector3(5.5, 0.0, 0.5))   # 5 u east of the dais centre (0.5, 0.5)
	ctl.charges = 1
	var ev: Array = []
	var saved: bool = ctl.try_kill("D-KIWI", "kiwi cat", w, ev)
	if not saved:
		f.append("last_light: try_kill did not save with 1 charge held")
		return
	if not ctl.last_light_spent or absf(ctl.x - 0.5) > 1e-6 or absf(ctl.z - 0.5) > 1e-6:
		f.append("last_light: the save did not teleport to the dais")
	# the LIVE row sits at exactly 8 u on its own bearing (y untouched): 0.5 + 8 = 8.5
	if absf(float(row["x"]) - 8.5) > 1e-6 or absf(float(row["z"]) - 0.5) > 1e-6 \
			or absf(float(row["y"])) > 1e-6:
		f.append("last_light: the live row inside 8 u was not displaced: (%.4f, %.4f, %.4f)"
				% [float(row["x"]), float(row["y"]), float(row["z"])])
	# its world mirror agrees with the moved row (nothing left claiming the old point)
	if w["enemies"].is_empty():
		f.append("last_light: the spawn never published the row's mirror to the world")
	elif absf(float(w["enemies"][0]["x"]) - 8.5) > 1e-6:
		f.append("last_light: the world mirror stayed at %.4f, want 8.5" % [
				float(w["enemies"][0]["x"])])
	if _last(ev, "last_light_save").is_empty():
		f.append("last_light: the save emitted no last_light_save event")
