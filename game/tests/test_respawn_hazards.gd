extends RefCounted
#
# Void-fall respawn vs the live mine set (D-059, DESIGN sections 3.1 and 3.3).
# The safe-tile search (controller.gd valid_safe_tile) refuses a tile whose top
# centre is inside w["hazards"]; that list was never populated, so a respawn
# could land on a mined tile and kill the player again. This pins the fix end to
# end: the footprints the search reads are built from the live mine set
# (level_state.gd hazard_footprints), then the search runs through the real
# controller step and must pick a different tile.
#   - a mine on the only candidate respawn tile -> the previous ring tile is picked;
#   - no mines (the slots are gifts) -> the newest (nearest) safe tile is still picked;
#   - a consumed mine no longer blocks its tile -> the newest safe tile is picked.
# The hazards assignments below stand in for the integrator wiring (assign the
# footprints to w["hazards"] before the controller's step); they are the
# contract the fix produces, not a re-test of a manual list.

const MinesScript := preload("res://sim/mines.gd")
const LevelStateScript := preload("res://sim/level_state.gd")
const WorldScript := preload("res://app/world.gd")
const Util := preload("res://tests/sim_testutil.gd")

const DAIS := [0, 0, 0]
const TILE_A := [10, 0, 0]   # older ring entry
const TILE_B := [20, 0, 0]   # newest ring entry - the tile the search prefers


func run() -> Array[String]:
	var f: Array[String] = []
	_test_mine_blocks_candidate(f)
	_test_no_hazards_picks_nearest(f)
	_test_consumed_mine_does_not_block(f)
	_test_world_publishes_hazards(f)
	return f


## The integrator wiring. The three legs above assign w["hazards"] by hand, so on their own they
## prove the producer and the search but NOT that the shipped game ever publishes the list - and a
## producer nothing calls is exactly the defect this ticket exists to fix.
##
## The assertion is ARRAY IDENTITY, not emptiness: collision.gd seeds w["hazards"] with [] when the
## world dict is built, so `w.has("hazards")` is true whether or not anything publishes it, and on a
## mine-free level both the wired and unwired lists are empty. The producer builds a NEW array every
## step, so is_same() tells the two apart. Proven by negative control: commenting out world.gd's
## publish line makes this leg fail.
func _test_world_publishes_hazards(f: Array[String]) -> void:
	var world = WorldScript.new()
	if not world.build(1, 1):
		f.append("wiring: world.build(1, 1) failed")
		world.free()
		return
	var seeded = world.w.get("hazards")
	world.step(1.0 / 60.0)
	var published = world.w.get("hazards")
	if not (published is Array):
		f.append("wiring: w[\"hazards\"] is not an Array after step")
	elif is_same(seeded, published):
		f.append("wiring: world.step did not publish w[\"hazards\"] - the respawn search is blind")
	else:
		# When the level does carry mines, every live one must have a footprint.
		var live := 0
		if world.lstate != null and world.lstate.mines != null:
			for slot_id in world.lstate.mines.ids:
				if not world.lstate.mines.is_consumed(slot_id):
					live += 1
		if (published as Array).size() < live:
			f.append("wiring: %d live mines but only %d hazard footprints published"
					% [live, (published as Array).size()])
	world.teardown()
	world.free()


# Dais + two separated standing tiles; everything else is open void.
func _world() -> Dictionary:
	var w := Util.world_from_tiles([DAIS, TILE_A, TILE_B])
	w["dais"] = [DAIS[0], DAIS[1], DAIS[2]]
	return w


func _fresh(w: Dictionary) -> RefCounted:
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	ctl.place(w)
	return ctl


# The gift slot table the mine set derives from: slot 0 sits on tile A (an ordinary
# gift, occ 0), slot 1 sits on tile B (occ 1 -> a tripmine, when mine_on_b).
static func _level(mine_on_b: bool) -> Dictionary:
	var occ_b := 1 if mine_on_b else 0
	var slots: Array = [
		{"id": 0, "x": TILE_A[0], "z": TILE_A[1], "y": TILE_A[2], "piece": 0, "tier": 0, "occ": 0},
		{"id": 1, "x": TILE_B[0], "z": TILE_B[1], "y": TILE_B[2], "piece": 0, "tier": 0, "occ": occ_b},
	]
	return {"gifts": slots}


static func _key(t: Array) -> String:
	return "%d,%d,%d" % [t[0], t[1], t[2]]

# Parks the controller on tile t for long enough for the safe-tile ring dwell (0.5 s)
# to bank the tile; ring entries then read oldest-first, newest last.
func _stand_on(ctl, w: Dictionary, t: Array) -> void:
	ctl.x = float(t[0]) + 0.5
	ctl.y = float(t[2]) * 0.5
	ctl.z = float(t[1]) + 0.5
	ctl.vx = 0.0
	ctl.vy = 0.0
	ctl.vz = 0.0
	ctl.grounded = true
	ctl.cur_key = _key(t)
	ctl.dwell = 0.0
	for i in range(34):
		ctl.step(Util.DT, Util.mk_in(), w)


# Drops the controller into the void (no tile underfoot) and runs until the fall is
# handled; returns the events of that window.
func _fall_to_void(ctl, w: Dictionary, ev_out: Array = []) -> void:
	ctl.x = 100.5
	ctl.y = 0.0
	ctl.z = 0.5
	ctl.vx = 0.0
	ctl.vy = 0.0
	ctl.vz = 0.0
	var done := false
	for i in range(400):
		var ev = ctl.step(Util.DT, Util.mk_in(), w)
		for e in ev:
			ev_out.append(e)
			var k := str(e.get("e", ""))
			if k == "death" or k == "respawn" or k == "void_fall":
				done = true
		if done:
			break


func _step_until(ctl, w: Dictionary, ev_out: Array, want: String, max_ticks: int) -> void:
	for i in range(max_ticks):
		var ev = ctl.step(Util.DT, Util.mk_in(), w)
		for e in ev:
			ev_out.append(e)
			if str(e.get("e", "")) == want:
				return


# Stands on A then B (so B is the newest ring entry), falls into the void, publishes
# the footprints the way the integrator must, and runs out the respawn. Returns
# [ctl, footprints].
func _respawn_after_fall(mine_on_b: bool, consume_it: bool) -> Array:
	var w := _world()
	var ctl := _fresh(w)
	_stand_on(ctl, w, TILE_A)
	_stand_on(ctl, w, TILE_B)
	var m: RefCounted = MinesScript.create(_level(mine_on_b), 7, 11)
	if consume_it:
		m.consume(1)
	var ev: Array = []
	_fall_to_void(ctl, w, ev)
	var hazards: Array = LevelStateScript.hazard_footprints(m)
	w["hazards"] = hazards
	_step_until(ctl, w, ev, "respawn", 120)
	return [ctl, hazards]


# A mine on the only candidate respawn tile (tile B, the newest ring entry): the
# search must refuse B and pick the previous safe tile (A), not fall back to the dais.
func _test_mine_blocks_candidate(f: Array[String]) -> void:
	var out: Array = _respawn_after_fall(true, false)
	var ctl = out[0]
	var hazards: Array = out[1]
	if hazards.size() != 1:
		f.append("mine: %d hazard footprints from one live mine, want 1" % hazards.size())
	elif str(hazards[0].get("shape", "")) != "circle":
		f.append("mine: footprint shape %s, want circle" % str(hazards[0].get("shape", "")))
	if ctl.cur_key != _key(TILE_A):
		f.append("mine: respawned on %s, want %s (the candidate behind the mined tile)" % [
			ctl.cur_key, _key(TILE_A)])


# Negative control: no mines (the occ slots are ordinary gifts) - the search still
# picks the newest safe tile (B), the same choice it makes with an empty hazard list.
func _test_no_hazards_picks_nearest(f: Array[String]) -> void:
	var out: Array = _respawn_after_fall(false, false)
	var ctl = out[0]
	var hazards: Array = out[1]
	if not hazards.is_empty():
		f.append("no hazards: %d footprints from a level with no mined slots, want 0" % [
			hazards.size()])
	if ctl.cur_key != _key(TILE_B):
		f.append("no hazards: respawned on %s, want %s (the newest safe tile)" % [
			ctl.cur_key, _key(TILE_B)])


# A consumed tripmine is not a hazard: with the only mined slot defused/spent, the
# search picks B again.
func _test_consumed_mine_does_not_block(f: Array[String]) -> void:
	var out: Array = _respawn_after_fall(true, true)
	var ctl = out[0]
	var hazards: Array = out[1]
	if not hazards.is_empty():
		f.append("consumed: %d footprints from a consumed mine, want 0" % hazards.size())
	if ctl.cur_key != _key(TILE_B):
		f.append("consumed: respawned on %s, want %s (the newest safe tile)" % [
			ctl.cur_key, _key(TILE_B)])
