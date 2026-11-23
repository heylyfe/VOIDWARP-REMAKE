extends RefCounted
#
# test_jump_pads.gd (D-JUMPPAD-1..5): JUMP PADS - not the launch pads.
#
# Legs (each with a negative control - a checker that cannot fail proves nothing):
#   1. placement over PLACE_SEEDS x PLACE_LEVELS real levels: every pad is a flat floor tile
#      on a walkway, 4-adjacent to a route (centre-lane) tile at its height, never ON the
#      route, never on / beside a gift slot or tripmine, never on the hub (beacon) piece, never
#      on a jump-stair / ramp walkway or a riser edge, never on / beside a launch pad or its
#      landing; pairwise spacing and count from data; placement is deterministic and does
#      not move the level hash. The checker is then run over deliberately bad pads (one per
#      rule) and must report each of them;
#   2. the refill list: jump_pad_launch() refills air jumps, dash + twin dash, glider energy
#      (base + bonus), the updraft, the ability lock - and leaves void charges, the beacon
#      shield, Last Light, invulnerability and the horizontal velocity alone; and the refilled
#      updraft is USABLE - a glider flung off a pad can actually fire the rise (D-JUMPPAD-3);
#   3. launch height: on a flat test floor the pad flings the player to ~v^2/(2g) (6.25 u at
#      20 u/s), far above a normal jump, with >= 1 s of air time, momentum kept;
#   4. re-arm: a pad does not re-fire inside rearm_ticks, does at rearm_ticks, and one pad
#      firing does not disarm another;
#   5. determinism: the JUMPPADS state-hash line, a recorded real-level run replayed twice
#      (identical hashes at every checkpoint) and a perturbed replay (diverges); on the launch
#      tick itself the hashed player row matches the controller (Terra finding 1); two levels
#      with one level hash and one pad count but moved pads hash apart (Terra finding 2);
#   6. collapse: a pad whose tile falls is lost, never fires again, and its view is hidden;
#      a temporarily removed tile also stops it and hides it without losing it;
#   7. view: the compress / rebound curve and the slab mesh.

const VoidGenScript := preload("res://terrain/voidgen.gd")
const PlaceScript := preload("res://terrain/jump_pads.gd")
const JumpPadsScript := preload("res://sim/jump_pads.gd")
const ControllerScript := preload("res://sim/controller.gd")
const CollisionScript := preload("res://sim/collision.gd")
const RunStateScript := preload("res://sim/run_state.gd")
const HashScript := preload("res://sim/state_hash.gd")
const ViewScript := preload("res://view/jump_pad_view.gd")

const PLACE_SEEDS := [1, 7, 42, 99, 123, 2024, 31337, 60717]
const PLACE_LEVELS := [1, 2, 3, 5, 8, 12, 20, 30]
const DT := 1.0 / 60.0
const NC_SEED := 1
const DETERMINISM_SEEDS := [1, 42]
const NC_LEVEL := 30


class Holder:
	extends RefCounted
	var jump_pads: RefCounted = null


func run() -> Array[String]:
	var f: Array[String] = []
	_placement(f)
	_refill(f)
	_updraft_usable(f)
	_launch_height(f)
	_rearm(f)
	_hash_and_replay(f)
	_launch_tick_row(f)
	_hash_positions(f)
	_collapse(f)
	_view(f)
	return f


# ---- 1. placement ----------------------------------------------------------------------

func _placement(f: Array[String]) -> void:
	var cfg: Dictionary = PlaceScript.load_config()
	var levels_with := 0
	var total := 0
	var bad_samples: Dictionary = {}
	for sd in PLACE_SEEDS:
		for lvn in PLACE_LEVELS:
			var L: Dictionary = VoidGenScript.generate(sd, lvn)
			var h0: String = VoidGenScript.level_hash(L)
			var pads: Array = PlaceScript.attach(L, cfg)
			if VoidGenScript.level_hash(L) != h0:
				f.append("placement: attach() moved the level hash (seed %d level %d)" % [sd, lvn])
			if VoidGenScript.to_text(L).find("jump") >= 0:
				f.append("placement: the canonical text mentions jump pads (seed %d level %d)" % [sd, lvn])
			# determinism from a FRESH generate (two seeds: a regenerate costs ~0.15 s)
			var again: Array = pads if not DETERMINISM_SEEDS.has(sd) 					else PlaceScript.place_jump_pads(VoidGenScript.generate(sd, lvn), cfg)
			if again != pads:
				f.append("placement: not deterministic (seed %d level %d): %s vs %s" % [sd, lvn, str(pads), str(again)])
			if pads.size() > PlaceScript.count_for_level(cfg, lvn):
				f.append("placement: %d pads > count_for_level %d" % [pads.size(), PlaceScript.count_for_level(cfg, lvn)])
			if not pads.is_empty():
				levels_with += 1
			total += pads.size()
			for v in _violations(L, pads, cfg):
				f.append("placement seed %d level %d: %s" % [sd, lvn, v])
	var n := PLACE_SEEDS.size() * PLACE_LEVELS.size()
	# the rule must not be vacuous: most levels carry a pad (measured 2026-11-22: 36/40 on a
	# 5-seed probe; 3/4 is the floor, a placement that found nothing would fail here)
	if levels_with * 4 < n * 3:
		f.append("placement: only %d of %d levels got a pad (want >= 3/4)" % [levels_with, n])
	if total == 0:
		f.append("placement: no pad placed anywhere")
	# negative controls: the checker over one deliberately bad pad per rule, on a late level
	# (jump stairs are legal from level 5, TERRAIN_SPEC section 11)
	var NL: Dictionary = VoidGenScript.generate(NC_SEED, NC_LEVEL)
	bad_samples = _bad_pads(NL, cfg)
	bad_samples["L"] = NL
	if bad_samples.is_empty():
		f.append("placement NC: could not build the bad-pad fixtures")
		return
	var L2: Dictionary = bad_samples["L"]
	for rule in ["route", "gift", "mine", "hub", "beacon", "stair", "launch_pad"]:
		if not bad_samples.has(rule):
			f.append("placement NC: no fixture tile for rule '%s' found" % rule)
			continue
		var bad: Array = [bad_samples[rule]]
		var v2 := _violations(L2, bad, cfg)
		var hit := false
		for msg in v2:
			if str(msg).begins_with(rule + ":"):
				hit = true
		if not hit:
			f.append("placement NC: a pad on a '%s' tile %s was not reported (got %s)" % [rule, str(bad[0]), str(v2)])
	# spacing NC: two pads 1 tile apart
	var p0: Array = bad_samples.get("route", [0, 0, 0])
	var v3 := _violations(L2, [p0, [int(p0[0]) + 1, int(p0[1]), int(p0[2])]], cfg)
	var sp_hit := false
	for msg in v3:
		if str(msg).begins_with("spacing:"):
			sp_hit = true
	if not sp_hit:
		f.append("placement NC: two pads 1 tile apart were not reported")


## Independent checker: every rule of D-JUMPPAD-1 against a pad list. Messages start "<rule>:".
func _violations(L: Dictionary, pads: Array, cfg: Dictionary) -> Array:
	var out: Array = []
	var tiles: Array = L["tiles"]
	var by_cell: Dictionary = {}
	for i in tiles.size():
		var t: Array = tiles[i]
		by_cell[Vector3i(int(t[0]), int(t[1]), int(t[2]))] = i
	var ix: Dictionary = PlaceScript._index(L)
	var sp: float = float(cfg["min_spacing_tiles"])
	for k in pads.size():
		var p: Array = pads[k]
		var x := int(p[0])
		var z := int(p[1])
		var y := int(p[2])
		var key := Vector3i(x, z, y)
		if not by_cell.has(key):
			out.append("tile: pad %s is not on a tile" % str(p))
			continue
		var i: int = by_cell[key]
		var t: Array = tiles[i]
		var pc: Dictionary = L["pieces"][int(t[4])]
		if _is_route(L, ix, i):
			out.append("route: pad %s is ON the route" % str(p))
		for g in L["gifts"]:
			if maxi(absi(int(g["x"]) - x), absi(int(g["z"]) - z)) <= 1:
				var rule := "mine" if int(g["occ"]) == 1 else "gift"
				out.append("%s: pad %s on / beside slot %d" % [rule, str(p), int(g["id"])])
		if int(pc["role"]) == VoidGenScript.ROLE_HUB:
			out.append("hub: pad %s on the hub piece" % str(p))
		var b: Array = L["beacon"]
		if maxi(absi(int(b[0]) - x), absi(int(b[1]) - z)) <= 1:
			out.append("beacon: pad %s on / beside the beacon" % str(p))
		if ["stair", "ramp"].has(str(pc["arch"])) or int(t[3]) != 0:
			out.append("stair: pad %s on a %s walkway / ramp tile" % [str(p), str(pc["arch"])])
		for lp in L["pads"]:
			for c in [[int(lp[0]), int(lp[1])], [int(lp[3]), int(lp[4])]]:
				if maxi(absi(int(c[0]) - x), absi(int(c[1]) - z)) <= 1:
					out.append("launch_pad: pad %s on / beside a launch pad cell %s" % [str(p), str(c)])
		if int(pc["kind"]) != 1:
			out.append("beside: pad %s is not on a walkway" % str(p))
		var beside := false
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nk := Vector3i(x + d.x, z + d.y, y)
			if by_cell.has(nk) and _is_route(L, ix, int(by_cell[nk])):
				beside = true
			for dy in [-11, -10, -9, -8, -7, -6, -5, -4, -3, -2, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]:
				var rk := Vector3i(x + d.x, z + d.y, y + dy)
				if by_cell.has(rk) and int(tiles[int(by_cell[rk])][4]) == int(t[4]):
					out.append("riser: pad %s beside a %d HU riser" % [str(p), dy])
		if not beside:
			out.append("beside: pad %s has no route tile beside it" % str(p))
		for k2 in range(k + 1, pads.size()):
			var q: Array = pads[k2]
			var dx := float(int(q[0]) - x)
			var dz := float(int(q[1]) - z)
			if dx * dx + dz * dz < sp * sp:
				out.append("spacing: pads %s and %s closer than %.0f" % [str(p), str(q), sp])
	return out


## Route = the generator's GEN 4 centre lane on a walkway, OR (independently of that code) the
## middle line of a straight 3-wide walkway read off its bbox when the bbox is unambiguous.
func _is_route(L: Dictionary, ix: Dictionary, i: int) -> bool:
	var t: Array = L["tiles"][i]
	var pc: Dictionary = L["pieces"][int(t[4])]
	if int(pc["kind"]) != 1:
		return false
	if PlaceScript.on_route(L, ix, i):
		return true
	var bb: Array = pc["bbox"]
	var ex := int(bb[2]) - int(bb[0]) + 1
	var ez := int(bb[3]) - int(bb[1]) + 1
	var w := int(pc["w"])
	if ex == w and ez != w:
		return int(t[0]) * 2 == int(bb[0]) + int(bb[2])
	if ez == w and ex != w:
		return int(t[1]) * 2 == int(bb[1]) + int(bb[3])
	return false


## One deliberately bad pad per rule, picked from the level's own tiles.
func _bad_pads(L: Dictionary, _cfg: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var ix: Dictionary = PlaceScript._index(L)
	for i in L["tiles"].size():
		var t: Array = L["tiles"][i]
		var pc: Dictionary = L["pieces"][int(t[4])]
		var cell := [int(t[0]), int(t[1]), int(t[2])]
		if not out.has("route") and _is_route(L, ix, i):
			out["route"] = cell
		if not out.has("hub") and int(pc["role"]) == VoidGenScript.ROLE_HUB and absi(int(t[0])) > 4:
			out["hub"] = cell
		if not out.has("stair") and str(pc["arch"]) == "stair":
			out["stair"] = cell
	out["beacon"] = [int(L["beacon"][0]), int(L["beacon"][1]), int(L["beacon"][2])]
	for g in L["gifts"]:
		var rule := "mine" if int(g["occ"]) == 1 else "gift"
		if not out.has(rule):
			out[rule] = [int(g["x"]), int(g["z"]), int(g["y"])]
	for lp in L["pads"]:
		out["launch_pad"] = [int(lp[0]), int(lp[1]), int(lp[2])]
		break
	# a level without a mine / launch pad / stair: borrow from other seeds' levels is not
	# possible on one L - fall back to a fabricated slot / pad on the route cell
	if not out.has("mine") and out.has("route"):
		var r: Array = out["route"]
		L["gifts"].append({"id": 999, "x": r[0], "z": r[1], "y": r[2], "piece": 0, "tier": 0, "occ": 1})
		out["mine"] = r
	if not out.has("launch_pad") and out.has("route"):
		var r2: Array = out["route"]
		L["pads"].append([r2[0], r2[1], r2[2], r2[0], r2[1], r2[2]])
		out["launch_pad"] = r2
	return out


# ---- 2. the refill list -----------------------------------------------------------------

func _drained(kit: String) -> RefCounted:
	var c = ControllerScript.new()
	c.setup(kit, ControllerScript.load_constants())
	c.apply_double_jump(1.0)
	c.apply_double_jump(1.0)
	if kit == "dasher":
		c.apply_twin_dash()
	if kit == "glider":
		c.apply_updraft()
	c.glide_energy_bonus = 1.5
	c.air_jumps = 0
	c.dash_ready = false
	c.dash_cd = 2.5
	c.bonus_dashes = 0
	c.bonus_cd = 2.0
	c.glide_energy = 0.1
	c.updraft_ready = false
	c.updraft_cd = 4.0
	c.updraft_used = true
	c.lock = 1.0
	c.charges = 1
	c.charge_cap = 2
	c.barrier_shield_cap = 1
	c.barrier_shields = 0
	c.last_light_spent = true
	c.invuln = 0.3
	c.field_dressing_uses = 0
	c.vx = 5.0
	c.vz = -3.0
	c.grounded = true
	return c


## Every refill + every untouched field; returns the failures (the NC counts them).
func _refill_failures(c, launched_vy: float) -> Array:
	var out: Array = []
	if c.air_jumps != c.air_jumps_max or c.air_jumps_max != 2:
		out.append("air_jumps %d / max %d" % [c.air_jumps, c.air_jumps_max])
	if not c.dash_ready or c.dash_cd != 0.0:
		out.append("dash not refilled (ready %s cd %.2f)" % [str(c.dash_ready), c.dash_cd])
	if c.bonus_dashes != c.bonus_dashes_max or c.bonus_cd != 0.0:
		out.append("bonus dash %d / %d cd %.2f" % [c.bonus_dashes, c.bonus_dashes_max, c.bonus_cd])
	var gmax: float = float(c.C["glide_energy"]) + 1.5
	if absf(c.glide_energy - gmax) > 1e-9:
		out.append("glide_energy %.3f, want full %.3f (base + bonus)" % [c.glide_energy, gmax])
	if c.updraft_ready != c.updraft_owned or c.updraft_cd != 0.0 or c.updraft_used:
		out.append("updraft ready %s owned %s cd %.2f used %s" % [str(c.updraft_ready), str(c.updraft_owned), c.updraft_cd, str(c.updraft_used)])
	if c.lock != 0.0:
		out.append("lock %.2f, want 0" % c.lock)
	if c.vy != launched_vy:
		out.append("vy %.3f, want %.3f" % [c.vy, launched_vy])
	if c.grounded:
		out.append("still grounded after the launch")
	# NOT refilled
	if c.charges != 1 or c.charge_cap != 2:
		out.append("void charges touched: %d / %d" % [c.charges, c.charge_cap])
	if c.barrier_shields != 0:
		out.append("beacon shield refilled: %d" % c.barrier_shields)
	if not c.last_light_spent:
		out.append("Last Light restored")
	if absf(c.invuln - 0.3) > 1e-9:
		out.append("invulnerability touched: %.2f" % c.invuln)
	if c.vx != 5.0 or c.vz != -3.0:
		out.append("horizontal momentum lost: (%.2f, %.2f)" % [c.vx, c.vz])
	return out


func _refill(f: Array[String]) -> void:
	for kit in ["dasher", "glider", "athletic"]:
		var c = _drained(kit)
		var ev: Array = []
		c.jump_pad_launch(20.0, ev)
		for msg in _refill_failures(c, 20.0):
			f.append("refill %s: %s" % [kit, msg])
		if ev.size() != 1 or str(ev[0].get("e", "")) != "jump_pad_launch":
			f.append("refill %s: event %s, want one jump_pad_launch" % [kit, str(ev)])
	# an UNOWNED rise stays unowned (D-T053-6: only apply_updraft grants it)
	var g = ControllerScript.new()
	g.setup("glider", ControllerScript.load_constants())
	g.jump_pad_launch(20.0)
	if g.updraft_ready:
		f.append("refill: the launch granted an updraft the glider does not own")
	# the documented list names exactly the fields the function writes
	for field in ControllerScript.JUMP_PAD_REFILLS:
		if not (field in g):
			f.append("refill: JUMP_PAD_REFILLS names '%s', which is not a controller field" % field)
	# negative control: a drained controller that was NOT launched fails every refill row
	# (air jumps, dash, bonus, glide, updraft, lock, vy, grounded = 8)
	var nc = _drained("glider")
	var ncf := _refill_failures(nc, 20.0)
	if ncf.size() != 8:
		f.append("refill NC: an un-launched controller reported %d failures, want 8: %s" % [ncf.size(), str(ncf)])
	# and a launch that ALSO refilled charges / shield is caught
	var nc2 = _drained("dasher")
	nc2.jump_pad_launch(20.0)
	nc2.charges = 2
	nc2.barrier_shields = 1
	if _refill_failures(nc2, 20.0).size() != 2:
		f.append("refill NC: a launch that refilled charges + shield was not caught twice")


## D-JUMPPAD-3 (Terra finding 3 declined): the refill must leave the rise USABLE, not just
## flagged. A drained glider that owns the updraft is flung off a pad on the flat floor, then
## presses jump on each falling tick (spending its refilled air jumps first, as a player
## would). Returns the number of updraft_rise events before it lands again (-1: no launch).
## spoil = put the rise back to its drained state right after the launch (the negative control).
func _rise_after_pad(owned: bool, spoil: bool) -> int:
	var wh := _flat_world([[4, 4, 0]])
	var w: Dictionary = wh[0]
	var h: Holder = wh[1]
	var c
	if owned:
		c = _drained("glider")
	else:
		c = ControllerScript.new()
		c.setup("glider", ControllerScript.load_constants())
	_on_tile(c, 4, 4, 0)
	c.vx = 0.0
	c.vz = 0.0
	var ev: Array = []
	JumpPadsScript.tick(h, [c], w, 1, ev)
	if ev.is_empty():
		return -1
	if spoil:
		# undo the rise's refill: not ready, spent, and a cooldown longer than any flight
		# (pressing on every other falling tick glides, so the flight outlasts a 6 s cooldown)
		c.updraft_ready = false
		c.updraft_cd = 1000.0
		c.updraft_used = true
	var rises := 0
	var held := false
	for t in 600:
		# a fresh press on every falling tick that follows a released one
		var press: bool = c.vy < 0.0 and not held
		held = press
		var out: Array = c.step(DT, {"move_x": 0, "move_z": 0,
				"buttons": ControllerScript.BTN_JUMP if press else 0}, w)
		for e in out:
			if str(e.get("e", "")) == "updraft_rise":
				rises += 1
		if c.grounded:
			break
	return rises


func _updraft_usable(f: Array[String]) -> void:
	var n := _rise_after_pad(true, false)
	if n < 0:
		f.append("updraft: the fixture pad did not fire")
	elif n != 1:
		f.append("updraft: a glider flung off a pad fired the rise %d times before landing, want 1" % n)
	# negative controls: the probe must see an unusable rise as unusable
	var nc := _rise_after_pad(true, true)
	if nc != 0:
		f.append("updraft NC: with the rise drained again after the launch it still fired %d times" % nc)
	var nu := _rise_after_pad(false, false)
	if nu != 0:
		f.append("updraft NC: an unowned glider fired the rise %d times after a pad" % nu)


# ---- 3. launch height ------------------------------------------------------------------

## A flat 9x9 floor at y = 0 HU, a jump pad at its centre (4, 4).
func _flat_world(pad_cells: Array) -> Array:
	var tiles: Array = []
	for x in 9:
		for z in 9:
			tiles.append([x, z, 0, 0, 1])
	var w: Dictionary = CollisionScript.make_world(tiles, [], [], {"dais": [1, 1, 0]})
	var L := {"jump_pads": pad_cells}
	var h := Holder.new()
	h.jump_pads = JumpPadsScript.create(L, {"launch_speed": 20.0, "rearm_s": 0.5})
	return [w, h]


func _on_tile(c, x: int, z: int, y_hu: int) -> void:
	c.x = float(x) + 0.5
	c.z = float(z) + 0.5
	c.y = float(y_hu) * 0.5
	c.vy = 0.0
	c.grounded = true
	c.cur_key = "%d,%d,%d" % [x, z, y_hu]


func _launch_height(f: Array[String]) -> void:
	var wh := _flat_world([[4, 4, 0]])
	var w: Dictionary = wh[0]
	var h: Holder = wh[1]
	var c = ControllerScript.new()
	c.setup("athletic", ControllerScript.load_constants())
	_on_tile(c, 4, 4, 0)
	var tick := 0
	var ev: Array = []
	tick += 1
	JumpPadsScript.tick(h, [c], w, tick, ev)
	if ev.is_empty() or c.vy != 20.0:
		f.append("launch: standing on an armed pad did not fire (vy %.2f, events %s)" % [c.vy, str(ev)])
		return
	var apex := 0.0
	var air := 0
	while tick < 600:
		c.step(DT, {"move_x": 0, "move_z": 0, "buttons": 0}, w)
		tick += 1
		apex = maxf(apex, c.y)
		if c.grounded:
			break
		air += 1
	var want := 20.0 * 20.0 / (2.0 * float(c.C["gravity"]))
	if absf(apex - want) > 0.25:
		f.append("launch: apex %.3f u, want %.2f +- 0.25 (v^2 / 2g)" % [apex, want])
	var jump_apex := pow(float(c.C["jump_velocity"]), 2.0) / (2.0 * float(c.C["gravity"]))
	if apex < 2.0 * jump_apex:
		f.append("launch: apex %.2f u is not above twice a normal jump's %.2f u" % [apex, jump_apex])
	if float(air) * DT < 1.0:
		f.append("launch: air time %.2f s < 1.0 s" % (float(air) * DT))
	# momentum kept: a running player keeps vx / vz through the fling
	var c2 = ControllerScript.new()
	c2.setup("dasher", ControllerScript.load_constants())
	_on_tile(c2, 1, 4, 0)
	for k in 60:
		c2.step(DT, {"move_x": 1, "move_z": 0, "buttons": 0}, w)
		if c2.vy > 1.0:
			break
		var e2: Array = []
		JumpPadsScript.tick(h, [c2], w, 100 + k, e2)
		if not e2.is_empty():
			if c2.vx < 5.0 or c2.vy != 20.0:
				f.append("launch: running fling lost momentum: vx %.2f vy %.2f" % [c2.vx, c2.vy])
			break
	if c2.vy != 20.0:
		f.append("launch: a player running across the pad was never flung (x %.2f vy %.2f)" % [c2.x, c2.vy])
	# negative control: a player one tile beside the pad is not flung
	var c3 = ControllerScript.new()
	c3.setup("dasher", ControllerScript.load_constants())
	_on_tile(c3, 5, 4, 0)
	var e3: Array = []
	JumpPadsScript.tick(h, [c3], w, 500, e3)
	if not e3.is_empty() or c3.vy != 0.0:
		f.append("launch NC: a player beside the pad was flung")
	# and an airborne player over the pad is not flung
	_on_tile(c3, 4, 4, 0)
	c3.grounded = false
	JumpPadsScript.tick(h, [c3], w, 501, e3)
	if not e3.is_empty():
		f.append("launch NC: an airborne player was flung")


# ---- 4. re-arm -------------------------------------------------------------------------

func _rearm(f: Array[String]) -> void:
	var wh := _flat_world([[4, 4, 0], [1, 1, 0]])
	var w: Dictionary = wh[0]
	var h: Holder = wh[1]
	var jp = h.jump_pads
	if jp.rearm_ticks != 30:
		f.append("rearm: rearm_ticks %d, want 30 (0.5 s at 60 Hz)" % jp.rearm_ticks)
	var c = ControllerScript.new()
	c.setup("dasher", ControllerScript.load_constants())
	var fired: Array = []
	for t in range(10, 10 + 61):
		_on_tile(c, 4, 4, 0)
		var ev: Array = []
		JumpPadsScript.tick(h, [c], w, t, ev)
		if not ev.is_empty():
			fired.append(t)
	# standing on it for 61 ticks: fires at 10, 40, 70 - never on the ticks between
	if fired != [10, 40, 70]:
		f.append("rearm: fired on ticks %s, want [10, 40, 70]" % str(fired))
	# per pad: pad 0 is inert at tick 41..69, pad 1 still fires
	var c2 = ControllerScript.new()
	c2.setup("dasher", ControllerScript.load_constants())
	_on_tile(c2, 1, 1, 0)
	var ev2: Array = []
	JumpPadsScript.tick(h, [c2], w, 45, ev2)
	if ev2.size() != 1 or int(ev2[0]["pad"]) != 1:
		f.append("rearm: pad 1 did not fire while pad 0 was re-arming: %s" % str(ev2))
	# negative control: with rearm 1 tick the same stand-still fires every tick
	var wh2 := _flat_world([[4, 4, 0]])
	var h2: Holder = wh2[1]
	h2.jump_pads.rearm_ticks = 1
	var n := 0
	for t in range(1, 11):
		_on_tile(c, 4, 4, 0)
		var ev3: Array = []
		JumpPadsScript.tick(h2, [c], wh2[0], t, ev3)
		n += ev3.size()
	if n != 10:
		f.append("rearm NC: a 1-tick re-arm fired %d times in 10 ticks, want 10" % n)


# ---- 5. hash + replay ------------------------------------------------------------------

func _hash_and_replay(f: Array[String]) -> void:
	var sd := 7
	var lvn := 1
	var L: Dictionary = VoidGenScript.generate(sd, lvn)
	var rs0 = RunStateScript.new_run(sd, 1, [])
	rs0.load_level(L, lvn)
	if "JUMPPADS" in "\n".join(HashScript.dump(rs0)):
		f.append("hash: a level without attach() dumps a JUMPPADS line (old dumps would move)")
	PlaceScript.attach(L)
	if (L["jump_pads"] as Array).is_empty():
		f.append("hash: fixture seed 7 level 1 has no jump pad")
		return
	var a := _record(L, sd, lvn, false)
	var b := _record(L, sd, lvn, false)
	var p := _record(L, sd, lvn, true)
	if int(a["fires"]) < 1:
		f.append("replay: the recorded run never fired the pad")
	if a["hashes"] != b["hashes"]:
		f.append("replay: two replays of one input stream hashed differently")
	if not str(a["dump"]).contains("JUMPPADS "):
		f.append("hash: the state dump carries no JUMPPADS line")
	var diverged := 0
	for i in (a["hashes"] as Array).size():
		if a["hashes"][i] != p["hashes"][i]:
			diverged += 1
	if diverged == 0:
		f.append("replay NC: a perturbed replay hashed identically at every checkpoint")
	# the hash sees the re-arm state alone: same positions, one ready tick moved
	var rs = RunStateScript.new_run(sd, 1, [])
	rs.load_level(L, lvn)
	var h1: String = HashScript.sha256(rs)
	rs.level.jump_pads.ready_tick[0] = 99
	if HashScript.sha256(rs) == h1:
		f.append("hash: a moved re-arm tick does not change the state hash")
	rs.level.jump_pads.ready_tick[0] = 0
	if HashScript.sha256(rs) != h1:
		f.append("hash: restoring the re-arm tick does not restore the hash")
	rs.level.jump_pads.sweep([rs.level.jump_pads.tile_key(0)])
	if HashScript.sha256(rs) == h1:
		f.append("hash: a lost pad does not change the state hash")


## 300 ticks from the pad tile: walk and jump on a fixed script, hash every 60 ticks.
## perturb = hold still on the first tick instead of walking (the pad fires a tick apart).
func _record(L: Dictionary, sd: int, lvn: int, perturb: bool) -> Dictionary:
	var rs = RunStateScript.new_run(sd, 1, [])
	rs.load_level(L, lvn)
	var lv = rs.level
	var w: Dictionary = CollisionScript.make_world(L["tiles"], L["props"], L["pads"], {"dais": L["beacon"]})
	var c = ControllerScript.new()
	c.setup("glider", ControllerScript.load_constants())
	c.place(w)
	var p: Array = L["jump_pads"][0]
	c.x = float(int(p[0])) + 0.5
	c.z = float(int(p[1])) + 0.5
	c.y = float(int(p[2])) * 0.5 + (0.0 if not perturb else 0.25)
	c.grounded = not perturb
	var hashes: Array = []
	var fires := 0
	for t in 300:
		var mx := 1 if (t / 40) % 2 == 0 else -1
		var btn := 1 if t >= 120 and (t % 50) < 20 else 0   # no jump before the pad fires
		var a_in := {"move_x": mx, "move_z": 0, "buttons": btn}
		var ev: Array = c.step(DT, a_in, w)
		var p0: Dictionary = lv.players[0]
		p0["x"] = c.x
		p0["y"] = c.y
		p0["z"] = c.z
		p0["vx"] = c.vx
		p0["vy"] = c.vy
		p0["vz"] = c.vz
		p0["grounded"] = c.grounded
		p0["prev_buttons"] = btn
		lv.tick += 1
		JumpPadsScript.tick(lv, [c], w, lv.tick, ev)
		for e in ev:
			if str(e.get("e", "")) == "jump_pad_launch":
				fires += 1
		if lv.tick % 60 == 0:
			hashes.append(HashScript.sha256(rs))
	return {"hashes": hashes, "fires": fires, "dump": "\n".join(HashScript.dump(rs))}


## Terra finding 1: the world / bot order is step -> copy the controller into
## lv.players[0] -> tick += 1 -> gifts / mines -> JumpPadsScript.tick. On the tick a pad
## fires, the hashed row must already show the launch (vy = launch speed, airborne): the hash
## must equal the hash of a row freshly copied from the controller. Fails if the row is
## synced only before the pad fires.
func _launch_tick_row(f: Array[String]) -> void:
	var sd := 7
	var lvn := 1
	var L: Dictionary = VoidGenScript.generate(sd, lvn)
	PlaceScript.attach(L)
	if (L["jump_pads"] as Array).is_empty():
		f.append("launch row: fixture seed 7 level 1 has no jump pad")
		return
	var rs = RunStateScript.new_run(sd, 1, [])
	rs.load_level(L, lvn)
	var lv = rs.level
	var w: Dictionary = CollisionScript.make_world(L["tiles"], L["props"], L["pads"], {"dais": L["beacon"]})
	var c = ControllerScript.new()
	c.setup("dasher", ControllerScript.load_constants())
	c.place(w)
	var p: Array = L["jump_pads"][0]
	_on_tile(c, int(p[0]), int(p[1]), int(p[2]))
	var fired := false
	for t in 10:
		var ev: Array = c.step(DT, {"move_x": 0, "move_z": 0, "buttons": 0}, w)
		var p0: Dictionary = lv.players[0]
		p0["x"] = c.x
		p0["y"] = c.y
		p0["z"] = c.z
		p0["vx"] = c.vx
		p0["vy"] = c.vy
		p0["vz"] = c.vz
		p0["grounded"] = c.grounded
		p0["prev_buttons"] = 0
		lv.tick += 1
		var pev: Array = []
		JumpPadsScript.tick(lv, [c], w, lv.tick, pev)
		if pev.is_empty():
			continue
		fired = true
		var got: String = HashScript.sha256(rs)
		var row: Dictionary = lv.players[0]
		if float(row["vy"]) != c.vy or bool(row["grounded"]) != c.grounded:
			f.append("launch row: on the launch tick the row has vy %.3f grounded %s, the controller vy %.3f grounded %s" % [
					float(row["vy"]), str(row["grounded"]), c.vy, str(c.grounded)])
		# the truth: the row copied from the controller after the launch
		var truth: Dictionary = row.duplicate()
		truth["vx"] = c.vx
		truth["vy"] = c.vy
		truth["vz"] = c.vz
		truth["grounded"] = c.grounded
		lv.players[0] = truth
		var want: String = HashScript.sha256(rs)
		if got != want:
			f.append("launch row: the launch-tick hash differs from the hash of a controller-synced row")
		# negative control: a row left at its pre-launch state (grounded, vy 0) must hash
		# differently from the truth, or the comparison above proves nothing
		var stale: Dictionary = truth.duplicate()
		stale["vy"] = 0.0
		stale["grounded"] = true
		lv.players[0] = stale
		if HashScript.sha256(rs) == want:
			f.append("launch row NC: a stale grounded row hashes like the launched one")
		lv.players[0] = truth
		break
	if not fired:
		f.append("launch row: standing on the fixture pad never fired it in 10 ticks")


## Terra finding 2: pad placement depends on data/jump_pads.json, which the level hash does
## not see. Same Level, same level hash, same pad count, one pad moved -> different hash.
func _hash_positions(f: Array[String]) -> void:
	var sd := 7
	var lvn := 3   # 2 pads (count_by_level from 3), so the order check below has two to swap
	var L: Dictionary = VoidGenScript.generate(sd, lvn)
	PlaceScript.attach(L)
	var pads: Array = L["jump_pads"]
	if pads.size() < 2:
		f.append("hash pos: fixture seed 7 level 3 has %d jump pads, want >= 2" % pads.size())
		return
	# a different floor tile for pad 0 (the first tile that is not already a pad)
	var taken := {}
	for q in pads:
		taken["%d,%d,%d" % [int(q[0]), int(q[1]), int(q[2])]] = true
	var moved: Array = []
	for t in L["tiles"]:
		if not taken.has("%d,%d,%d" % [int(t[0]), int(t[1]), int(t[2])]):
			moved = [int(t[0]), int(t[1]), int(t[2])]
			break
	var L2: Dictionary = L.duplicate(true)
	(L2["jump_pads"] as Array)[0] = moved
	var L3: Dictionary = L.duplicate(true)
	var hs: Array = []
	var lh: Array = []
	for lvl in [L, L2, L3]:
		var rs = RunStateScript.new_run(sd, 1, [])
		rs.load_level(lvl, lvn)
		hs.append(HashScript.sha256(rs))
		lh.append(str(rs.level.level_hash))
	if lh[0] != lh[1]:
		f.append("hash pos: fixture broken - moving a jump pad changed the level hash")
	if (L2["jump_pads"] as Array).size() != pads.size():
		f.append("hash pos: fixture broken - the pad count changed")
	if hs[0] == hs[1]:
		f.append("hash pos: two levels with one level hash and pad count but a moved pad hash alike")
	# negative control: an identical pad set hashes identically (the line is not just noise)
	if hs[0] != hs[2]:
		f.append("hash pos NC: an identical copy of the level hashed differently")
	# order matters too: the ready ticks and the lost bitset are indexed by placement order
	var L4: Dictionary = L.duplicate(true)
	var a: Array = L4["jump_pads"]
	var tmp = a[0]
	a[0] = a[1]
	a[1] = tmp
	var rs4 = RunStateScript.new_run(sd, 1, [])
	rs4.load_level(L4, lvn)
	if HashScript.sha256(rs4) == hs[0]:
		f.append("hash pos: swapping two pads' placement order does not change the hash")


# ---- 6. collapse -----------------------------------------------------------------------

func _collapse(f: Array[String]) -> void:
	var wh := _flat_world([[4, 4, 0], [1, 1, 0]])
	var w: Dictionary = wh[0]
	var h: Holder = wh[1]
	var jp = h.jump_pads
	var view = ViewScript.new()
	view.setup({}, jp)
	view.sync(jp, 1)
	if view.pad_count() != 2 or not view.slab(0).get_parent().visible:
		f.append("collapse: the view did not build two visible pads")
	# negative control first: an unrelated fallen key drops nothing
	if not jp.sweep(["7,7,0"]).is_empty() or jp.is_lost(0):
		f.append("collapse NC: an unrelated fallen tile dropped a pad")
	# the pad tile falls (collapse.gd removes it from collision; world.gd sweeps the keys)
	var key: String = jp.tile_key(0)
	w["removed"][key] = true
	if jp.sweep([key]) != [0] or not jp.is_lost(0) or jp.is_lost(1):
		f.append("collapse: sweeping pad 0's tile did not drop exactly pad 0")
	var c = ControllerScript.new()
	c.setup("dasher", ControllerScript.load_constants())
	_on_tile(c, 4, 4, 0)
	var ev: Array = []
	JumpPadsScript.tick(h, [c], w, 10, ev)
	if not ev.is_empty():
		f.append("collapse: a lost pad fired")
	w["removed"].erase(key)
	JumpPadsScript.tick(h, [c], w, 11, ev)
	if not ev.is_empty():
		f.append("collapse: a lost pad fired after its tile key left the removed set")
	view.sync(jp, 12)
	if view.slab(0).get_parent().visible or not view.slab(1).get_parent().visible:
		f.append("collapse: the view did not hide exactly the lost pad")
	# a temporarily removed tile (a tile-schedule curse): no fire, hidden, NOT lost
	var key1: String = jp.tile_key(1)
	w["removed"][key1] = true
	_on_tile(c, 1, 1, 0)
	JumpPadsScript.tick(h, [c], w, 13, ev)
	if not ev.is_empty() or jp.is_lost(1):
		f.append("collapse: a pad on a removed tile fired or was lost")
	view.set_removed(w["removed"])
	view.sync(jp, 13)
	if view.slab(1).get_parent().visible:
		f.append("collapse: a pad on a removed tile is still drawn")
	w["removed"].erase(key1)
	JumpPadsScript.tick(h, [c], w, 14, ev)
	if ev.size() != 1:
		f.append("collapse: the pad did not fire again once its tile came back")
	view.free()


# ---- 7. view ---------------------------------------------------------------------------

func _view(f: Array[String]) -> void:
	if ViewScript.squash_at(INF) != 1.0 or ViewScript.squash_at(-1.0) != 1.0:
		f.append("view: the slab is not at rest outside the animation")
	if absf(ViewScript.squash_at(ViewScript.SQUASH_T) - ViewScript.SQUASH_MIN) > 1e-6:
		f.append("view: no full compression at SQUASH_T")
	var peak := 0.0
	var t := 0.0
	while t < ViewScript.ANIM_S:
		peak = maxf(peak, ViewScript.squash_at(t))
		t += DT
	if peak < 1.1:
		f.append("view: the rebound never overshoots (peak %.3f)" % peak)
	if absf(ViewScript.squash_at(ViewScript.ANIM_S - 0.001) - 1.0) > 0.05:
		f.append("view: the rebound has not settled by ANIM_S")
	var m: ArrayMesh = ViewScript.build_slab_mesh()
	if m.get_surface_count() != 1 or m.get_aabb().size.y < ViewScript.HEIGHT - 1e-4:
		f.append("view: the slab mesh is empty or flat (aabb %s)" % str(m.get_aabb()))
	if m.get_aabb().size.x > 0.9:
		f.append("view: the slab overhangs its tile (%.3f u)" % m.get_aabb().size.x)
	# fired at tick 100 (ready 130): squashed + rippling at 102, at rest by 160
	var wh := _flat_world([[4, 4, 0]])
	var jp = wh[1].jump_pads
	var view = ViewScript.new()
	view.setup({}, jp)
	jp.ready_tick[0] = 100 + jp.rearm_ticks
	view.sync(jp, 102)
	if view.slab(0).scale.y > 0.8:
		f.append("view: the slab is not compressed 2 ticks after firing (%.3f)" % view.slab(0).scale.y)
	var ring: Node3D = view.slab(0).get_parent().get_node("Ripple0")
	if not ring.visible:
		f.append("view: no ripple right after firing")
	view.sync(jp, 160)
	if absf(view.slab(0).scale.y - 1.0) > 1e-6 or ring.visible:
		f.append("view: not at rest 1 s after firing")
	view.free()
