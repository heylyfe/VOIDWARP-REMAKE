extends RefCounted
#
# Void charges (ticket T-012, DESIGN section 3.1, D-050, D-052, D-059, D-063):
# 2 held, cap 2; a fall costs 1 and respawns on the last safe tile after 0.8 s with
# 1.0 s invulnerability; a fall at 0 charges is a real death (D-VOID); beacon restores
# exactly 1, capped; Hungry Void caps at 1; the 8-tile ring, re-validation, the
# enemy-clearing rule (6 u) and the dais fallback.

const Util := preload("res://tests/sim_testutil.gd")
const CollisionScript := preload("res://sim/collision.gd")

# 9 separated standing tiles (dais at (0,0) plus 8 ring tiles); 8 u spacing so the
# 6 u safe radius of one parked enemy invalidates at most the tile it sits on.
const RING_TILES := [
	[10, 0, 0], [20, 0, 2], [30, 0, 0], [40, 0, 2],
	[50, 0, 0], [60, 0, 2], [70, 0, 0], [80, 0, 2],
]


func run() -> Array[String]:
	var f: Array[String] = []
	_test_three_falls(f)
	_test_beacon(f)
	_test_hungry_void(f)
	_test_ring_and_revalidation(f)
	_test_charges_carry_over(f)
	return f


func _void_world() -> Dictionary:
	# dais tile (0,0,1) + the ring tiles; everything else is open void
	var tiles: Array = [[0, 0, 0]]
	for t in RING_TILES:
		tiles.append(t)
	var w := Util.world_from_tiles(tiles)
	w["dais"] = [0, 0, 0]
	return w


func _fresh() -> RefCounted:
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	ctl.place(_void_world())
	return ctl


# Drops the controller into the void (no tile underfoot) and runs until the fall is
# handled; returns the events of that window.
static func _fall_to_void(ctl, w: Dictionary, ev_out: Array = []) -> void:
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
			if e["e"] == "death" or e["e"] == "respawn" or e["e"] == "void_fall":
				done = true
		if done:
			break


func _step_until(ctl, w: Dictionary, ev_out: Array, want: String, max_ticks: int) -> void:
	for i in range(max_ticks):
		var ev = ctl.step(Util.DT, Util.mk_in(), w)
		for e in ev:
			ev_out.append(e)
			if e["e"] == want:
				return


func _test_three_falls(f: Array[String]) -> void:
	var ctl = _fresh()
	var w := Util.world_from_tiles([[0, 0, 0]])
	w["dais"] = [0, 0, 0]
	var ev: Array = []
	# fall 1: 2 -> 1, respawn after 0.8 s with 1.0 s invuln, chain reset
	_fall_to_void(ctl, w, ev)
	if _count(ev, "void_fall") != 1 or _count(ev, "chain_reset") != 1:
		f.append("charges: fall 1 did not emit void_fall + chain_reset")
	_step_until(ctl, w, ev, "respawn", 120)
	if ctl.charges != 1:
		f.append("charges: after fall 1 charges=%d, want 1" % ctl.charges)
	if absf(ctl.invuln - 1.0) > 1e-6:
		f.append("charges: respawn invulnerability %.4f, want 1.0" % ctl.invuln)
	if not ctl.grounded or int(ctl.x) != 0:
		f.append("charges: respawn not on the dais (%.2f, %.2f)" % [ctl.x, ctl.y])
	# respawn invulnerability suppresses a kill without spending anything
	var pre_charges: int = ctl.charges
	var saved: bool = ctl.try_kill("D-KIWI", "kiwi cat", w, ev)
	if saved or ctl.dead or ctl.charges != pre_charges:
		f.append("charges: respawn invulnerability did not suppress the kill")
	# fall 2: 1 -> 0
	_fall_to_void(ctl, w, ev)
	_step_until(ctl, w, ev, "respawn", 120)
	if ctl.charges != 0:
		f.append("charges: after fall 2 charges=%d, want 0" % ctl.charges)
	# fall 3: real death, D-VOID, no respawn
	_fall_to_void(ctl, w, ev)
	var deaths := _last(ev, "death")
	if ctl.charges != 0 or deaths.is_empty():
		f.append("charges: fall 3 did not kill (charges=%d deaths=%d)" % [ctl.charges, deaths.size()])
	elif deaths[deaths.size() - 1]["code"] != "D-VOID":
		f.append("charges: fall 3 death code %s, want D-VOID" % deaths[deaths.size() - 1]["code"])
	var respawns := _count(ev, "respawn")
	if respawns != 2:
		f.append("charges: %d respawns across 3 falls, want 2" % respawns)
	Util.run_ticks(ctl, w, 90, func(_c, _i): return Util.mk_in())
	if ctl.respawn_t >= 0.0:
		f.append("charges: a respawn was scheduled after a real death")


func _test_beacon(f: Array[String]) -> void:
	var ctl = _fresh()
	var w := Util.world_from_tiles([[0, 0, 0]])
	var ev: Array = []
	ctl.charges = 2
	if ctl.beacon_enter(ev) or ctl.charges != 2:
		f.append("beacon: entry at 2 charges changed charges to %d" % ctl.charges)
	ctl.charges = 1
	ctl.beacon_enter(ev)
	if ctl.charges != 2:
		f.append("beacon: entry at 1 charge gave %d, want 2" % ctl.charges)
	ctl.charges = 0
	ctl.beacon_enter(ev)
	if ctl.charges != 1:
		f.append("beacon: entry at 0 charges gave %d, want exactly 1" % ctl.charges)


func _test_hungry_void(f: Array[String]) -> void:
	var ctl = _fresh()
	var w := Util.world_from_tiles([[0, 0, 0]])
	ctl.set_charge_cap(1)
	if ctl.charges != 1:
		f.append("hungry void: cap 1 with 2 held left %d held, want 1" % ctl.charges)
	if not ctl.beacon_enter():
		pass
	if ctl.charges != 1:
		f.append("hungry void: beacon restored past the cap (%d)" % ctl.charges)
	ctl.charges = 0
	ctl.beacon_enter()
	if ctl.charges != 1:
		f.append("hungry void: beacon entry at 0 gave %d, want 1" % ctl.charges)


func _test_ring_and_revalidation(f: Array[String]) -> void:
	var ctl = _fresh()
	var w := _void_world()
	# stand on each ring tile for 0.5 s (they enter newest-last, capped at 8)
	for t in RING_TILES:
		var key: String = "%d,%d,%d" % [t[0], t[1], t[2]]
		_ctl_stand_on(ctl, w, t)
		if not ctl.ring.is_empty() and ctl.ring[ctl.ring.size() - 1]["key"] != key:
			f.append("ring: newest entry is %s, want %s" % [
				ctl.ring[ctl.ring.size() - 1]["key"], key])
	if ctl.ring.size() != 8:
		f.append("ring: %d entries after 8 tiles, want 8" % ctl.ring.size())
	# fall with an enemy parked on the newest ring tile -> next valid entry
	var ev: Array = []
	var newest: Array = RING_TILES[RING_TILES.size() - 1]
	var newest_top: float = float(newest[2]) * 0.5
	_fall_to_void(ctl, w, ev)
	w["enemies"] = [{"x": float(newest[0]) + 0.5, "y": newest_top, "z": 0.5}]
	_step_until(ctl, w, ev, "respawn", 120)
	var want_prev: String = "%d,%d,%d" % [
		RING_TILES[RING_TILES.size() - 2][0], RING_TILES[RING_TILES.size() - 2][1],
		RING_TILES[RING_TILES.size() - 2][2]]
	if ctl.cur_key != want_prev:
		f.append("ring: parked enemy on the newest tile respawned on %s, want %s" % [
			ctl.cur_key, want_prev])
	# all 8 invalid -> dais spawn tile
	ctl = _fresh()
	for t in RING_TILES:
		_ctl_stand_on(ctl, w, t)
	ev = []
	_fall_to_void(ctl, w, ev)
	w["enemies"] = []
	for t in RING_TILES:
		w["enemies"].append({"x": float(t[0]) + 0.5, "y": float(t[2]) * 0.5,
				"z": float(t[1]) + 0.5})
	_step_until(ctl, w, ev, "respawn", 120)
	if ctl.cur_key != "0,0,0" or absf(ctl.y) > 1e-6:
		f.append("ring: all 8 invalid respawned on %s, want the dais 0,0,0" % ctl.cur_key)


func _ctl_stand_on(ctl, w: Dictionary, t: Array) -> void:
	ctl.x = float(t[0]) + 0.5
	ctl.y = float(t[2]) * 0.5
	ctl.z = float(t[1]) + 0.5
	ctl.vx = 0.0
	ctl.vy = 0.0
	ctl.vz = 0.0
	ctl.grounded = true
	ctl.cur_key = "%d,%d,%d" % [t[0], t[1], t[2]]
	ctl.dwell = 0.0
	for i in range(34):
		ctl.step(Util.DT, Util.mk_in(), w)


# D-063: charges carry over between levels; no reset at a level boundary.
func _test_charges_carry_over(f: Array[String]) -> void:
	var ctl = _fresh()
	var w := _void_world()
	ctl.charges = 1
	var w2 := Util.world_from_tiles([[0, 0, 0]])
	w2["dais"] = [0, 0, 0]
	ctl.place(w2)
	if ctl.charges != 1:
		f.append("carry-over: charges reset across a level boundary (%d, want 1)" % ctl.charges)


# ---- small event helpers ------------------------------------------------------------

static func _count(ev: Array, kind: String) -> int:
	var n: int = 0
	for e in ev:
		if e.get("e", "") == kind:
			n += 1
	return n


static func _last(ev: Array, kind: String) -> Array:
	var out: Array = []
	for e in ev:
		if e.get("e", "") == kind:
			out.append(e)
	return out
