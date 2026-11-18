extends RefCounted
#
# Class kits + ability lock + friction + launch pads (ticket T-012, DESIGN section 4,
# addenda R4, D-070, D-075, TERRAIN_SPEC section 4).

const Util := preload("res://tests/sim_testutil.gd")
const CollisionScript := preload("res://sim/collision.gd")


func run() -> Array[String]:
	var f: Array[String] = []
	_test_dasher(f)
	_test_glider(f)
	_test_athletic(f)
	_test_locks(f)
	_test_friction(f)
	_test_pads(f)
	_test_ramps(f)
	_test_ramp_kinds(f)
	_test_prop_top(f)
	_test_constants(f)
	return f


# load_constants() maps main's nested data/player.json (T-014c schema) onto the flat
# keys; spot-check a value from each block.
func _test_constants(f: Array[String]) -> void:
	var c := Util.consts()
	if absf(float(c["run_speed"]) - 9.0) > 1e-9:
		f.append("constants: run_speed %.3f, want 9.0 from shared_kit" % float(c["run_speed"]))
	if absf(float(c["jump_cut"]) - 0.5) > 1e-9:
		f.append("constants: jump_cut %.3f, want 0.5 from shared_kit.jump_cut_mul" % float(c["jump_cut"]))
	if absf(float(c["athletic_run_mult"]) - 1.15) > 1e-9:
		f.append("constants: athletic_run_mult %.3f, want 1.15" % float(c["athletic_run_mult"]))
	if absf(float(c["glide_fall_cap"]) - 2.0) > 1e-9:
		f.append("constants: glide_fall_cap %.3f, want 2.0" % float(c["glide_fall_cap"]))
	if int(c["void_charges"]) != 2 or int(c["charge_cap"]) != 2:
		f.append("constants: charges %d cap %d, want 2/2" % [int(c["void_charges"]), int(c["charge_cap"])])
	if absf(float(c["safe_enemy_dist"]) - 6.0) > 1e-9:
		f.append("constants: safe_enemy_dist %.3f, want 6.0" % float(c["safe_enemy_dist"]))
	if absf(float(c["last_light_invuln"]) - 2.0) > 1e-9:
		f.append("constants: last_light_invuln %.3f, want 2.0" % float(c["last_light_invuln"]))


# A ramp strip: flat (y 0) -> ramp ascending +x (kind 1) -> flat (y +1 HU); walking
# across climbs exactly 0.5 u, and walking back down returns to 0.
func _test_ramps(f: Array[String]) -> void:
	var tiles: Array = []
	for cx in range(-8, 0):
		tiles.append([cx, 0, 0, 0, 0])
	tiles.append([0, 0, 0, 1, 0])   # ramp cell, low edge y 0, ascending toward +x
	for cx in range(1, 9):
		tiles.append([cx, 0, 1, 0, 0])
	for specs in [[1, -3.5, 0.0, 0.5], [-1, 3.5, 0.5, 0.0]]:
		var dir: int = specs[0]
		var start: float = specs[1]
		var sy: float = specs[2]
		var want_y: float = specs[3]
		var ramp_w := Util.CollisionScript.make_world(tiles, [], [])
		var ctl = Util.ControllerScript.new()
		ctl.setup("dasher", Util.consts())
		ctl.place(ramp_w)
		ctl.x = start
		ctl.y = sy
		ctl.z = 0.5
		Util.run_ticks(ctl, ramp_w, 75, func(_c, _i): return Util.mk_in(dir, 0))
		if not ctl.grounded or absf(ctl.y - want_y) > 0.02:
			f.append("ramp: walking dir=%d from x=%.1f ended at y=%.4f grounded=%s, want %.1f" % [
				dir, start, ctl.y, str(ctl.grounded), want_y])


# Kinds 3 and 4 ascend toward -x and -z (TERRAIN_SPEC section 4): flat at y+1 HU on the high
# (-x / -z) side, flat at y HU on the low side, and the mesher draws that wedge, so collision
# must slope the same way. A body's footprint fits inside the ramp cell whole from local 0.4
# to 0.6, and a -x / -z ramp is lower at 0.6 than at 0.4.
func _test_ramp_kinds(f: Array[String]) -> void:
	for d in range(2, 4):
		var on_x: bool = d % 2 == 0
		var tiles: Array = []
		if on_x:
			for cx in range(-8, 0):
				tiles.append([cx, 0, 1, 0, 0])
			tiles.append([0, 0, 0, 1 + d, 0])
			for cx in range(1, 9):
				tiles.append([cx, 0, 0, 0, 0])
		else:
			for cz in range(-8, 0):
				tiles.append([0, cz, 1, 0, 0])
			tiles.append([0, 0, 0, 1 + d, 0])
			for cz in range(1, 9):
				tiles.append([0, cz, 0, 0, 0])
		var w := Util.CollisionScript.make_world(tiles, [], [])
		for probe in [[0.4, 0.5], [0.6, 0.4]]:
			var at: float = probe[0]
			var want: float = probe[1]
			var px: float = at if on_x else 0.5
			var pz: float = 0.5 if on_x else at
			var s: float = Util.CollisionScript.support_at(w, px, pz, 5.0, 0.5)
			if absf(s - want) > 1e-6:
				var axis: String = "x" if on_x else "z"
				f.append("ramp kind %d: surface %.4f at local %.1f, want %.1f (ascends toward -%s)" % [
					1 + d, s, at, want, axis])
		# the strip still walks: off the high side down 0.5 u, and back up again
		for specs in [[1, -3.5, 0.5, 0.0], [-1, 3.5, 0.0, 0.5]]:
			var ctl = Util.ControllerScript.new()
			ctl.setup("dasher", Util.consts())
			ctl.place(w)
			if on_x:
				ctl.x = float(specs[1])
				ctl.z = 0.5
			else:
				ctl.x = 0.5
				ctl.z = float(specs[1])
			ctl.y = float(specs[2])
			var mx: int = int(specs[0]) if on_x else 0
			var mz: int = 0 if on_x else int(specs[0])
			Util.run_ticks(ctl, w, 60, func(_c, _i): return Util.mk_in(mx, mz))
			if not ctl.grounded or absf(ctl.y - float(specs[3])) > 0.02:
				f.append("ramp kind %d: walking from %.1f ended at y=%.4f grounded=%s, want %.1f" % [
					1 + d, float(specs[1]), ctl.y, str(ctl.grounded), float(specs[3])])


# A prop is a horizontal blocker with no walkable top in the tile sense, but a body that
# comes down on a prop cell lands on the prop, not inside its box (and then keeps standing
# there). support_at itself stays tile-only, so the safe-tile ring keeps its tile identity.
func _test_prop_top(f: Array[String]) -> void:
	var tiles: Array = []
	for cx in range(-2, 6):
		tiles.append([cx, 0, 0, 0, 0])
	var props: Array = [[2, 0, 0, 4, 1, 0]]   # wall on cell (2, 0): solid 0.0 .. 2.0 u
	var w := Util.CollisionScript.make_world(tiles, props, [])
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	ctl.place(w)
	ctl.x = 2.5
	ctl.y = 5.0
	ctl.z = 0.5
	ctl.grounded = false
	var guard := 0
	while not ctl.grounded and guard < 120:
		Util.run_ticks(ctl, w, 1, func(_c, _i): return Util.mk_in(0, 0))
		guard += 1
	if not ctl.grounded or absf(ctl.y - 2.0) > 0.02:
		f.append("prop: a fall onto the wall ended at y=%.4f grounded=%s, want its top 2.0" % [
			ctl.y, str(ctl.grounded)])
	Util.run_ticks(ctl, w, 10, func(_c, _i): return Util.mk_in(0, 0))
	if not ctl.grounded or absf(ctl.y - 2.0) > 0.02:
		f.append("prop: standing on the wall top slid to y=%.4f grounded=%s, want 2.0" % [
			ctl.y, str(ctl.grounded)])
	# the box still blocks horizontally at tile level (the top is not a way through)
	ctl.x = 1.5
	ctl.y = 0.0
	Util.run_ticks(ctl, w, 20, func(_c, _i): return Util.mk_in(1, 0))
	if ctl.x > 1.65:
		f.append("prop: walking into the wall from tile level reached x=%.4f" % ctl.x)
	# support_at reports the tile under the prop from the prop top, as before
	var sup: Variant = Util.CollisionScript.support_at(w, 2.5, 0.5, 2.0,
			Util.CollisionScript.SKIN, true)
	if sup["tile"] == null or absf(float(sup["s"]) - 0.0) > 1e-6:
		f.append("prop: support_at from the prop top returned %s, want the tile top 0.0" % str(sup["s"]))


func _flat(n: int) -> Dictionary:
	var tiles: Array = []
	for cx in range(-4, n):
		tiles.append([cx, 0, 0])
	return Util.world_from_tiles(tiles)


func _test_dasher(f: Array[String]) -> void:
	# 6 u in 0.20 s (dash overrides velocity; grounded start, no input interference)
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	var w := _flat(30)
	ctl.place(w)
	ctl.x = 4.5
	Util.run_ticks(ctl, w, 5, func(_c, _i): return Util.mk_in(0, 0))
	var sx: float = ctl.x
	Util.run_ticks(ctl, w, 1, func(_c, _i): return Util.mk_in(0, 0, Util.ControllerScript.BTN_ABILITY, 1.0, 0.0))
	Util.run_ticks(ctl, w, 13, func(_c, _i): return Util.mk_in(0, 0))
	var dist: float = ctl.x - sx
	if absf(dist - 6.0) > 0.05:
		f.append("dasher: dash moved %.4f u, expected 6.0" % dist)
	# one charge, regenerates in 3 s; quick re-press does nothing
	Util.run_ticks(ctl, w, 30, func(_c, _i): return Util.mk_in(0, 0))
	Util.run_ticks(ctl, w, 1, func(_c, _i): return Util.mk_in(0, 0, Util.ControllerScript.BTN_ABILITY, 1.0, 0.0))
	if ctl.dash_ticks > 0:
		f.append("dasher: dash restarted while regenerating")
	# direction follows the move input
	Util.run_ticks(ctl, w, 200, func(_c, _i): return Util.mk_in(0, 0))  # full regen past 3 s
	if not ctl.dash_ready:
		f.append("dasher: dash not ready after 3 s of regen")
	var s2x: float = ctl.x
	Util.run_ticks(ctl, w, 1, func(_c, _i): return Util.mk_in(-1, 0, Util.ControllerScript.BTN_ABILITY))
	Util.run_ticks(ctl, w, 12, func(_c, _i): return Util.mk_in(-1, 0))
	if absf((s2x - ctl.x) - 6.0) > 0.05:
		f.append("dasher: dash along input moved %.4f u, expected 6.0" % (s2x - ctl.x))
	# vertical speed held at 0 during a dash started in the air
	var cv = Util.ControllerScript.new()
	cv.setup("dasher", Util.consts())
	var wv := _flat(30)
	cv.place(wv)
	cv.x = 4.5
	cv.y = 5.0
	cv.vy = -6.0
	cv.grounded = false
	cv.cur_key = ""
	Util.run_ticks(cv, wv, 1, func(_c, _i): return Util.mk_in(0, 0, Util.ControllerScript.BTN_ABILITY, 1.0, 0.0))
	var slot_y: float = cv.y
	Util.run_ticks(cv, wv, 11, func(_c, _i): return Util.mk_in(0, 0))
	if absf(cv.y - slot_y) > 1e-6:
		f.append("dasher: y changed by %.4f during an airborne dash, want 0" % absf(cv.y - slot_y))


func _test_glider(f: Array[String]) -> void:
	# falling capped at 2.0 u/s while energy lasts, energy 3.0 s, refill on landing
	var ctl = Util.ControllerScript.new()
	ctl.setup("glider", Util.consts())
	var tiles: Array = [[0, 0, 0]]
	var w := Util.world_from_tiles(tiles)
	ctl.place(w)
	ctl.x = 50.5
	ctl.y = 20.0
	ctl.z = 0.5
	ctl.grounded = false
	ctl.cur_key = ""
	var saw_cap := false
	var respawned := false
	var min_energy := 99.0
	for i in range(420):
		var ev = ctl.step(Util.DT, Util.mk_in(0, 0, Util.ControllerScript.BTN_JUMP), w)
		for e in ev:
			if e["e"] == "respawn":
				respawned = true
		if ctl.glide_energy < min_energy:
			min_energy = ctl.glide_energy
		if ctl.gliding and absf(ctl.vy - (-2.0)) < 0.001 and ctl.glide_energy > 2.0:
			saw_cap = true
	if not saw_cap:
		f.append("glider: fall speed never capped at 2.0 u/s")
	if not respawned:
		f.append("glider: never finished falling after 4 s of glide + free fall")
	if min_energy > 0.3:
		f.append("glider: 3.0 s of glide did not drain the energy pool (min %.3f)" % min_energy)
	# energy refills on landing
	ctl2_refill_check(f)
	# horizontal cap 10 u/s while gliding
	var cg = Util.ControllerScript.new()
	cg.setup("glider", Util.consts())
	var wg := Util.world_from_tiles([[0, 0, 0]])
	cg.place(wg)
	cg.x = 50.5
	cg.y = 10.0
	cg.grounded = false
	cg.cur_key = ""
	cg.vx = 30.0
	cg.vz = -30.0
	cg.vy = -4.0
	cg.step(Util.DT, Util.mk_in(0, 0, Util.ControllerScript.BTN_JUMP), wg)
	var h_mag: float = sqrt(cg.vx * cg.vx + cg.vz * cg.vz)
	if absf(h_mag - 10.0) > 0.01:
		f.append("glider: horizontal speed %.3f while gliding, want capped at 10" % h_mag)


func ctl2_refill_check(f: Array[String]) -> void:
	var ctl = Util.ControllerScript.new()
	ctl.setup("glider", Util.consts())
	var w := Util.world_from_tiles([[0, 0, 0]])
	ctl.place(w)
	ctl.x = 0.5
	ctl.y = 3.0
	ctl.z = 0.5
	ctl.grounded = false
	ctl.cur_key = ""
	ctl.glide_energy = 1.0
	ctl.step(Util.DT, Util.mk_in(0, 0, Util.ControllerScript.BTN_JUMP), w)
	var guard := 0
	while not ctl.grounded and guard < 300:
		ctl.step(Util.DT, Util.mk_in(0, 0, Util.ControllerScript.BTN_JUMP), w)
		guard += 1
	if absf(ctl.glide_energy - 3.0) > 1e-6:
		f.append("glider: energy %.3f after landing, expected refill to 3.0" % ctl.glide_energy)


func _test_athletic(f: Array[String]) -> void:
	# built-in +15%: 10.35 u/s
	var ctl = Util.ControllerScript.new()
	ctl.setup("athletic", Util.consts())
	var w := _flat(40)
	ctl.place(w)
	Util.run_ticks(ctl, w, 30, func(_c, _i): return Util.mk_in(1, 0))
	if absf(ctl.vx - 10.35) > 0.02:
		f.append("athletic: run speed %.4f, expected 10.35" % ctl.vx)
	# speed upgrade x1.5: a +10% card is +15% on Athletic
	ctl.apply_speed_upgrade(0.10)
	Util.run_ticks(ctl, w, 30, func(_c, _i): return Util.mk_in(1, 0))
	if absf(ctl.vx - 11.70) > 0.05:
		f.append("athletic: upgraded run speed %.4f, expected 11.70" % ctl.vx)
	# double-jump upgrade x1.3 height: launch 15.6, read after one tick of gravity
	ctl.apply_double_jump(1.0)
	ctl.grounded = false
	ctl.vy = -5.0
	ctl.step(Util.DT, Util.mk_in(0, 0, Util.ControllerScript.BTN_JUMP), w)
	if absf(ctl.vy - (15.6 - 32.0 / 60.0)) > 0.02:
		f.append("athletic: air-jump velocity %.4f, expected 15.5667 (12 x 1.3 - g*dt)" % ctl.vy)
	if ctl.air_jumps != 0:
		f.append("athletic: air jump not consumed")
	# non-athletic air jump stays at base 12
	var cd = Util.ControllerScript.new()
	cd.setup("dasher", Util.consts())
	cd.apply_double_jump(1.0)
	cd.grounded = false
	cd.vy = -5.0
	var w2 := _flat(6)
	cd.step(Util.DT, Util.mk_in(0, 0, Util.ControllerScript.BTN_JUMP), w2)
	if absf(cd.vy - (12.0 - 32.0 / 60.0)) > 0.02:
		f.append("dasher: air-jump velocity %.4f, expected 11.4667 (12 - g*dt)" % cd.vy)


func _test_locks(f: Array[String]) -> void:
	# Dasher under lock: no dash starts, the cooldown does not tick
	var cd = Util.ControllerScript.new()
	cd.setup("dasher", Util.consts())
	var w := _flat(20)
	cd.place(w)
	cd.dash_ready = false
	cd.dash_cd = 2.0
	cd.apply_lock(0.5)
	for i in range(20):
		var b: int = Util.ControllerScript.BTN_ABILITY if i == 0 else 0
		cd.step(Util.DT, Util.mk_in(0, 0, b), w)
	if cd.dash_ticks > 0:
		f.append("dasher: dash started while ability-locked")
	if absf(cd.dash_cd - 2.0) > 1e-6:
		f.append("dasher: dash cooldown ticked during lock (%.4f left, want 2.0)" % cd.dash_cd)
	# Glider under lock: active glide ends, new glide cannot start
	var cg = Util.ControllerScript.new()
	cg.setup("glider", Util.consts())
	var wg := Util.world_from_tiles([[0, 0, 0]])
	cg.place(wg)
	cg.x = 0.5
	cg.y = 10.0
	cg.grounded = false
	cg.cur_key = ""
	cg.vy = -4.0
	cg.step(Util.DT, Util.mk_in(0, 0, Util.ControllerScript.BTN_JUMP), wg)
	if not cg.gliding:
		f.append("glider: glide did not engage in open air")
	cg.apply_lock(0.5)
	cg.step(Util.DT, Util.mk_in(0, 0, Util.ControllerScript.BTN_JUMP), wg)
	if cg.gliding:
		f.append("glider: glide survived an ability lock")
	# Athletic under lock: +15% suspended, x1.5/x1.3 multipliers become x1.0
	var ca = Util.ControllerScript.new()
	ca.setup("athletic", Util.consts())
	var wa := _flat(20)
	ca.place(wa)
	ca.apply_speed_upgrade(0.10)   # raw +10%; Athletic buys at +15%
	Util.run_ticks(ca, wa, 60, func(_c, _i): return Util.mk_in(1, 0))
	if absf(ca.vx - 11.70) > 0.05:
		f.append("athletic: pre-lock run speed %.4f, expected 11.70" % ca.vx)
	ca.apply_lock(0.30)
	Util.run_ticks(ca, wa, 15, func(_c, _i): return Util.mk_in(1, 0))
	if absf(ca.vx - 9.90) > 0.05:
		f.append("athletic: locked run speed %.4f, expected 9.90 (upgrades at normal strength)" % ca.vx)
	if not ca.ability_locked(wa):
		f.append("athletic: ability_locked false while the lock holds")


func _test_friction(f: Array[String]) -> void:
	# addendum R4: acceleration is 90 u/s^2 x friction; glitched floor: x0.4 and -20% speed
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	var w := _flat(20)
	ctl.place(w)
	ctl.step(Util.DT, Util.mk_in(1, 0), w)
	if absf(ctl.vx - 1.5) > 1e-6:
		f.append("friction: tick-1 speed on normal floor %.4f, expected 1.5" % ctl.vx)
	var wg = Util.ControllerScript.new()
	wg.setup("dasher", Util.consts())
	var w2 := _flat(20)
	wg.place(w2)
	wg.cur_key = "5,0,0"   # simulate standing on a glitched tile
	w2["glitched"]["5,0,0"] = true
	wg.step(Util.DT, Util.mk_in(1, 0), w2)
	if absf(wg.vx - 0.6) > 1e-6:
		f.append("friction: tick-1 speed on glitched floor %.4f, expected 0.6 (90 x 0.4 x dt)" % wg.vx)


func _test_pads(f: Array[String]) -> void:
	# landing on a pad throws the player ballistically onto the pad's target tile
	var tiles: Array = []
	for cx in range(-6, 12):
		tiles.append([cx, 0, 0])
	tiles.append([4, 0, 6])            # the target tile, 6 HU (3.0 u) above
	var pads: Array = [[0, 0, 0, 4, 0, 6]]
	var w := Util.world_from_tiles(tiles, pads)
	var ctl = Util.ControllerScript.new()
	ctl.setup("athletic", Util.consts())
	ctl.place(w)
	ctl.x = -3.5
	ctl.y = 0.0
	ctl.z = 0.5
	var launched := false
	var landed_on_target := false
	for i in range(180):
		var ev = ctl.step(Util.DT, Util.mk_in(1, 0), w)
		for e in ev:
			if e["e"] == "pad_launch":
				launched = true
		if ctl.grounded and absf(ctl.y - 3.0) < 0.02 and absf(ctl.x - 4.5) < 0.35 \
				and int(floor(ctl.z)) == 0:
			landed_on_target = true
			break
	if not launched:
		f.append("pad: walking onto the pad never launched")
	if not landed_on_target:
		f.append("pad: did not land on the target tile (x=%.3f y=%.3f)" % [ctl.x, ctl.y])
