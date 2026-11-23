extends RefCounted
#
# CURSE ENEMY EFFECTS test (headless, W10-E): the 13 enemy-linked script curses that
# run every tick and had no world-level proof. 12 of the 46 curses already change the
# shipped game (game/tests/test_curse_dispatch.gd); these 13 are the rest of the enemy
# family: aftershock, bunker_buster, direct_shot, double_ring, egoist, long_toll,
# longer_speech, mirror_match, quarter_chimes, second_strike, spreading_rot,
# token_limit, twin_fangs.
#
# Every case builds two real worlds through app/world.gd build() - one with the curse
# held (its requires_enemy voted, exactly as the ledger would carry it) and one with
# curses {} (the negative control) - steps them with world.step(), and asserts ONE
# specific number or state that differs. This file never calls a curse module and
# never edits game code: the only variable between the two builds of a case is the
# ledger's curses dict. Each case also asserts its probe was valid (e.g. the nuke
# blast happened, the coil landed a shock, the ring was released) so a silent
# no-op can never pass vacuously.
#
# The 13 and the observable each case pins (through world.build()/world.step()):
#   aftershock   coil's landing -> second ring telegraph "aftershock_ring" appears (control: never)
#   bunker_buster a nuke blast deletes the prop column inside the blast radius (control: kept)
#   direct_shot  an Isagi ball one step from a tile face: swallowed by the tile (control: dies; held: vx mirrored, bounces_left 0)
#   double_ring  YOU?! releases ring 1; a pinned (airborne) player is missed by it, and the echo
#                ring 36 ticks later lands the Last Light spend (control: player never spent it)
#   egoist       an Isagi burst fires 4 balls (control: 3; the +1 per stack), egoist_stacks stamped on the row
#   long_toll    ben's arrival is followed by a SECOND arrival at the same point exactly 90 ticks later (control: none in the window)
#   longer_speech address me's stillness gate leaves after 150 true still ticks (control: 90)
#   mirror_match YOU?! (mirrored dasher kit) dashes 6 u in one tick at the 300-tick cadence (control: the 3.4 u/s float)
#   quarter_chimes ben begins his smoke at cycle_t 465 and lands ~ tick 900 (control: smoke at 1086, arrival at ~1161)
#   second_strike a nuke blast records the player's position; the second missile 60 ticks later kills there (control: survives)
#   spreading_rot the toucher's glitched tiles spread to an adjacent tile 360 ticks after the source appears (control: never)
#   token_limit  a clawd pickup leaves 1200 anger ticks (20 s) behind (control: 0, the canon calm)
#   twin_fangs   Gin adds a second sword to the same arrival (control: exactly one)
#
# Test-side placement (teleporting a row or the player a few u) is the same fixture
# pattern test_curse_dispatch.gd uses for its crowded dais body; no game file is touched.

const WorldScript := preload("res://app/world.gd")

const SEED := 1
const LEVEL := 5
const DT := 1.0 / 60.0


func run() -> Array[String]:
	var f: Array[String] = []
	_aftershock(f)
	_bunker_buster(f)
	_direct_shot(f)
	_double_ring(f)
	_egoist(f)
	_long_toll(f)
	_longer_speech(f)
	_mirror_match(f)
	_quarter_chimes(f)
	_second_strike(f)
	_spreading_rot(f)
	_token_limit(f)
	_twin_fangs(f)
	return f


# ---- helpers ---------------------------------------------------------------------------------

func _build(votes: Dictionary, curses: Dictionary, kit: String = "dasher"):
	var world = WorldScript.new()
	var ledger := {
		"class": kit, "votes": votes, "curses": curses, "stacks": {},
		"purse": 0, "tithes": 0, "hunger": 0, "last_vote": "",
	}
	if not world.build(SEED, LEVEL, ledger):
		world.free()
		return null
	return world


func _drop(world) -> void:
	if world != null:
		world.teardown()
		world.free()


func _first_row(world, id: String) -> Dictionary:
	for e in world.rt.enemies:
		if str(e.get("id", "")) == id:
			return e
	return {}


func _count_kind(world, kind: String) -> int:
	var n := 0
	for t in world.rt.telegraphs:
		if str(t.get("kind", "")) == kind:
			n += 1
	return n


func _place_player(world, x: float, y: float, z: float) -> void:
	var c = world.ctl
	c.x = x
	c.y = y
	c.z = z
	c.vx = 0.0
	c.vy = 0.0
	c.vz = 0.0


func _check(f: Array[String], ok: bool, msg: String) -> void:
	if not ok:
		f.append(msg)


# ---- on_tick: the coil pair --------------------------------------------------------------------

## aftershock: the landing shock summons a second ring 0.5 s later. coil's landing is the
## moment the row snaps onto its locked zone with row["shock"] set; the curse watches that
## and announces "aftershock_ring" 30 ticks later. The player is moved 2.5 u off the landing
## tile at cue start (the landing zone is the player's own tile, so a still player eats the
## landing kill at < 1.2 u) and y-pinned so the landing-plane rule holds: within the 6 u
## shock band, alive, and in range for the echo.
func _aftershock(f: Array[String]) -> void:
	for held in [false, true]:
		var curses := {"aftershock": 1} if held else {}
		var world = _build({"coil": 1}, curses)
		if world == null:
			f.append("aftershock: build failed (held=%s)" % str(held))
			continue
		var shock_seen := false
		var ring_found := false
		var cue_seen := false
		var pin_y := float(world.ctl.y)
		var pinning := false
		for _t in range(950):
			if pinning:
				world.ctl.y = pin_y
				world.ctl.vy = 0.0
			world.step(DT)
			var row := _first_row(world, "coil")
			if not row.is_empty():
				if str(row.get("state", "")) == "cue" and not cue_seen:
					cue_seen = true
					# after the cue starts the landing zone is locked to this tile;
					# slide the player 2.5 u out so the shock lands without killing
					world.ctl.x = float(world.ctl.x) + 2.5
					pin_y = float(world.ctl.y)
					pinning = true
					world.ctl.vy = 0.0
				var shock: Variant = row.get("shock", null)
				if shock is Dictionary:
					shock_seen = true
			for tg in world.rt.telegraphs:
				if str(tg.get("kind", "")) == "aftershock_ring":
					ring_found = true
		if held:
			_check(f, ring_found, "aftershock held: no aftershock_ring telegraph after the landing")
		else:
			_check(f, not ring_found,
					"aftershock control: an aftershock_ring telegraph appeared without the curse")
		_check(f, shock_seen,
				"aftershock (held=%s): coil never landed a shock (player not in the band?) - probe invalid" % str(held))
		_drop(world)


# ---- on_tick: the nuke pair ---------------------------------------------------------------------

## A floor tile directly beside the player's own tile that carries NO prop column yet -
## the one cell the injected prop is placed in. Returns {"key", "px", "py", "pz"} (the
## 'x,z' key the module erases). The player keeps its spawn position on purpose: the
## nuke's LOS held there in the probe, and the blast lands on the locked feet point.
func _free_neighbour_prop_spot(world) -> Dictionary:
	var prop_cols: Dictionary = (world.rt.world as Dictionary).get("prop_cols", {})
	var tiles_set := {}
	for t in world.lv["tiles"]:
		tiles_set["%d,%d" % [int(t[0]), int(t[1])]] = int(t[2])
	var px := int(floorf(float(world.ctl.x)))
	var pz := int(floorf(float(world.ctl.z)))
	for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
		var nx := px + int(d[0])
		var nz := pz + int(d[1])
		var k := "%d,%d" % [nx, nz]
		if tiles_set.has(k) and not prop_cols.has(k):
			return {"key": k, "px": float(nx) + 0.5, "py": float(tiles_set[k]) * 0.5,
					"pz": float(nz) + 0.5, "hu": int(tiles_set[k])}
	return {}


## bunker_buster: "explosions delete props within the blast for the rest of the level".
## The nuke's blast lands on the locked feet point (the standing player), so the test
## plants one real prop column (the collision world's own shape: key 'x,z',
## [{"y", "h"}]) on a floor tile 1 u from the player - no natural prop stands that
## close in this seed, so the fixture stands in for the scenery prop. On the blast tick
## the module erases every prop column inside the sphere; held: the key is gone;
## control: it survives.
func _bunker_buster(f: Array[String]) -> void:
	for held in [false, true]:
		var curses := {"bunker_buster": 1} if held else {}
		var world = _build({"nuke": 1}, curses)
		if world == null:
			f.append("bunker_buster: build failed (held=%s)" % str(held))
			continue
		var spot := _free_neighbour_prop_spot(world)
		if spot.is_empty():
			f.append("bunker_buster (held=%s): no free floor tile beside the player" % str(held))
			_drop(world)
			continue
		var doomed := str(spot["key"])
		# the fixture: a 1 u tall prop column (2 HU) on that tile, the same shape the
		# collision world makes for scenery props
		(world.rt.world as Dictionary)["prop_cols"][doomed] = [{"y": int(spot["hu"]), "h": 2}]
		var blast_seen := false
		for _t in range(800):
			world.step(DT)
			var row := _first_row(world, "nuke")
			if row.is_empty():
				continue
			if int(row.get("explosion_left", 0)) == 24 or str(row.get("paused_by", "")) == "blast":
				blast_seen = true
		var prop_cols: Dictionary = (world.rt.world as Dictionary).get("prop_cols", {})
		if held:
			_check(f, not prop_cols.has(doomed),
					"bunker_buster held: the prop column %s survived the blast" % doomed)
		else:
			_check(f, prop_cols.has(doomed),
					"bunker_buster control: the prop column %s was deleted without the curse" % doomed)
		_check(f, blast_seen,
				"bunker_buster (held=%s): no nuke blast within 800 ticks - probe invalid" % str(held))
		_drop(world)


# ---- on_tick: the Isagi pair ---------------------------------------------------------------------

## A solid tile at least min_dist u from the player whose five tiles to the -x side carry no
## column (so an injected ball runs unimpeded into this face and retreats cleanly after the
## ricochet). Returns {"tx", "tz", "top"} or {}.
func _find_wall_tile(world, min_dist: float) -> Dictionary:
	var tiles_set := {}
	for t in world.lv["tiles"]:
		var cx := float(t[0]) + 0.5
		var cz := float(t[1]) + 0.5
		var dx: float = cx - float(world.ctl.x)
		var dz: float = cz - float(world.ctl.z)
		tiles_set["%d,%d" % [int(t[0]), int(t[1])]] = float(t[2]) * 0.5
	for t in world.lv["tiles"]:
		var top := float(t[2]) * 0.5
		if top < 1.0:
			continue
		var tx := int(t[0])
		var tz := int(t[1])
		var dx := float(tx) + 0.5 - float(world.ctl.x)
		var dz := float(tz) + 0.5 - float(world.ctl.z)
		if sqrt(dx * dx + dz * dz) < min_dist:
			continue
		var clear := true
		for k in range(1, 7):
			if tiles_set.has("%d,%d" % [tx - k, tz]):
				clear = false
				break
		if clear:
			return {"tx": tx, "tz": tz, "top": top}
	return {}


## direct_shot: "balls ricochet once off tiles/props". A ball (the runtime's own
## spawn_projectile, the name the curse matches) is injected 2.2 u in front of a solid tile
## face, moving into it at 12 u/s. The curse mirrors the offending axis one tick before the
## impact; the runtime sweeps projectiles before the curse runs, so a ball the curse does
## NOT save dies on the tile slab exactly as 5.4 reads. Held: the ball survives with vx
## mirrored and bounces_left == 0. Control: the projectiles list is empty 30 ticks later.
func _direct_shot(f: Array[String]) -> void:
	for held in [false, true]:
		var curses := {"direct_shot": 1} if held else {}
		var world = _build({"isagi": 1}, curses)
		if world == null:
			f.append("direct_shot: build failed (held=%s)" % str(held))
			continue
		var wall := _find_wall_tile(world, 12.0)
		if wall.is_empty():
			f.append("direct_shot (held=%s): no isolated solid tile beyond 12 u from the player" % str(held))
			_drop(world)
			continue
		var tx := int(wall["tx"])
		var tz := int(wall["tz"])
		var top := float(wall["top"])
		world.rt.spawn_projectile({"name": "Isagi"},
				{"name": "Isagi", "x": float(tx) - 2.2, "y": top - 0.25, "z": float(tz) + 0.5,
				"vx": 12.0, "vy": 0.0, "vz": 0.0, "r": 0.5, "life_ticks": 300})
		for _t in range(30):
			world.step(DT)
		var alive := 0
		var vx_seen := 12.0
		var bounces := -1
		for p in world.rt.projectiles:
			if str(p.get("name", "")).to_lower().contains("isagi"):
				alive += 1
				vx_seen = float(p.get("vx", 0.0))
				bounces = int(p.get("bounces_left", -1))
		if held:
			_check(f, alive == 1,
					"direct_shot held: %d Isagi balls alive after 30 ticks, want 1 (the one ricochet)" % alive)
			if alive == 1:
				_check(f, vx_seen < 0.0,
						"direct_shot held: the bounced ball kept vx %.2f, want a mirrored axis (ricochet once)" % vx_seen)
				_check(f, bounces == 0,
						"direct_shot held: bounces_left %d after the ricochet, want 0 (once only)" % bounces)
		else:
			_check(f, alive == 0,
					"direct_shot control: %d Isagi balls alive after 30 ticks, want 0 (the ball died on the tile)" % alive)
		_drop(world)


## egoist: "+1 ball per burst per stack". Isagi is on a perch with LOS on the standing
## player, so the wind-up completes and the burst begins; the burst size is the row's
## `balls` field at the attack tick: volley_balls + balls_per_stack * egoist_stacks.
func _egoist(f: Array[String]) -> void:
	for held in [false, true]:
		var curses := {"egoist": 1} if held else {}
		var world = _build({"isagi": 1}, curses)
		if world == null:
			f.append("egoist: build failed (held=%s)" % str(held))
			continue
		var seen := false
		var balls := -1
		var stacks := -1
		for _t in range(1400):
			world.step(DT)
			var row := _first_row(world, "isagi")
			if row.is_empty():
				continue
			if str(row.get("st", "")) == "attack":
				balls = int(row.get("balls", 0))
				var cfg: Dictionary = row.get("cfg", {})
				var st: Variant = cfg.get("stats", null)
				if st is Dictionary:
					stacks = int((st as Dictionary).get("egoist_stacks", 0))
				seen = true
				break
		if not seen:
			f.append("egoist (held=%s): Isagi never reached the attack state within 1400 ticks" % str(held))
		elif held:
			_check(f, balls == 4,
					"egoist held: the burst fires %d balls, want 4 (3 + 1 per stack)" % balls)
			_check(f, stacks == 1,
					"egoist held: egoist_stacks %d on the row stats, want 1" % stacks)
		else:
			_check(f, balls == 3,
					"egoist control: the burst fires %d balls, want 3 (the canon)" % balls)
			_check(f, stacks == 0,
					"egoist control: egoist_stacks %d on the row stats, want 0/absent" % stacks)
		_drop(world)


# ---- on_tick: YOU?! (double_ring) ----------------------------------------------------------------

## double_ring: "every shockwave is followed by a second ring 0.6 s later". The row is moved
## to 9.9 u in front of the standing player at spawn (test-side placement, the crowded_dais
## fixture pattern), so it closes into the 10 u trigger and rumbles for 90 ticks; the ring
## releases at d0 ~= 4.9 u. The player stands still; for the ticks the ring's edge is on
## them, their feet are pinned +2.0 u in the air (ring feet window is
## (ry - 1.5, ry + 1.0)) so ring 1 misses - the control proves the pin did its job without
## the curse. The echo ring starts 36 ticks later; grounded feet are back in the band, for
## the held run it lands the Last Light spend (charges >= 1, unspent, one per run).
## Once ring 1 has passed, the row is teleported far away so its body-contact kill cannot
## spend Last Light inside the observation window (a contact kill is not the ring, and it
## would spend the budget this case measures).
func _double_ring(f: Array[String]) -> void:
	for held in [false, true]:
		var curses := {"double_ring": 1} if held else {}
		var world = _build({"you": 1}, curses)
		if world == null:
			f.append("double_ring: build failed (held=%s)" % str(held))
			continue
		world.ctl.charges = 2   # Last Light armed (unspent), for both runs
		var ly := float(world.ctl.y)
		var origin_x := float(world.ctl.x)
		var origin_z := float(world.ctl.z)
		var placed := false
		var release_seen := false
		var release_tick := -1
		var d0 := 0.0
		var pin_lo := -1
		var pin_hi := -1
		var obs_end := 950
		var banished := false
		for _t in range(950):
			var tick_now := int(world.lstate.tick)
			if pin_lo >= 0 and tick_now >= pin_lo and tick_now <= pin_hi:
				world.ctl.y = ly + 2.0
				world.ctl.vy = 0.0
			elif pin_lo >= 0 and tick_now == pin_hi + 1:
				world.ctl.y = ly
				world.ctl.vy = 0.0
				pin_lo = -2   # sentinel: the pin is spent
			world.step(DT)
			var row := _first_row(world, "you")
			if not row.is_empty():
				if not placed:
					placed = true
					row["x"] = origin_x + 9.9
					row["y"] = ly
					row["z"] = origin_z
					world.rt.sync_body_mirror(row)
				var lrt := int(row.get("last_ring_tick", -1))
				if lrt >= 0 and not release_seen:
					release_seen = true
					release_tick = int(world.lstate.tick)
					var dx := float(row["x"]) - float(world.ctl.x)
					var dz := float(row["z"]) - float(world.ctl.z)
					d0 = sqrt(dx * dx + dz * dz)
					pin_lo = release_tick + int(floor((d0 - 0.7) / 0.15)) - 2
					pin_hi = release_tick + int(ceil((d0 + 0.7) / 0.15)) + 2
					obs_end = release_tick + int(ceil((d0 + 0.7) / 0.15)) + 42
			if not banished and release_tick >= 0 and int(world.lstate.tick) >= release_tick + 40:
				banished = true
				# ring 1 has passed; move the pursuer far away so its touch kill cannot
				# spend the Last Light this case measures (the echo ring releases from the
				# ORIGIN, which is frozen at the release tick - it does not chase)
				for e in world.rt.enemies:
					if str(e.get("id", "")) == "you":
						e["x"] = origin_x + 25.0
						e["z"] = origin_z + 25.0
						world.rt.sync_body_mirror(e)
			if release_seen and int(world.lstate.tick) >= obs_end:
				break
		if not release_seen:
			f.append("double_ring (held=%s): YOU?! never released a ring within 950 ticks" % str(held))
		else:
			# the pin kept ring 1 off the player in BOTH runs (a Last Light teleport to
			# the dais would land them far from the pin origin)
			_check(f, absf(float(world.ctl.x) - origin_x) < 1.0 and absf(float(world.ctl.z) - origin_z) < 1.0,
					"double_ring (held=%s): the player was displaced - Last Light was spent on ring 1; probe invalid" % str(held))
			_check(f, not bool(world.ctl.dead),
					"double_ring (held=%s): the player died - this case proves the echo ring's save, not a death" % str(held))
			if held:
				_check(f, bool(world.ctl.last_light_spent),
						"double_ring held: Last Light was never spent - the echo ring did not land")
			else:
				_check(f, not bool(world.ctl.last_light_spent),
						"double_ring control: Last Light was spent without the curse (ring 1 reached the pinned player?)")
		_drop(world)


# ---- on_tick: the ben pair ------------------------------------------------------------------------

## Ben's arrivals read off the row's phase edge (telegraph -> idle). Level 5 seed 1: ben
## spawns at tick 360, the canon cycle telegraphs at 1086 and lands at ~1161; the next
## arrival lands at ~1962. long_toll parks the fresh cycle so the second arrival lands at
## exactly +90 ticks on the SAME locked point.
func _long_toll(f: Array[String]) -> void:
	for held in [false, true]:
		var curses := {"long_toll": 1} if held else {}
		var world = _build({"thicc_ben": 1}, curses)
		if world == null:
			f.append("long_toll: build failed (held=%s)" % str(held))
			continue
		var arrivals: Array = []
		var pos_x: Array = []
		var pos_z: Array = []
		var prev_phase := "idle"
		for _t in range(1350):
			world.step(DT)
			var row := _first_row(world, "thicc_ben")
			if row.is_empty():
				continue
			var phase := str(row.get("phase", "idle"))
			if prev_phase == "telegraph" and phase == "idle":
				arrivals.append(int(world.lstate.tick))
				pos_x.append(float(row["x"]))
				pos_z.append(float(row["z"]))
			prev_phase = phase
		if held:
			_check(f, arrivals.size() == 2,
					"long_toll held: %d ben arrivals within 1350 ticks, want 2 (the toll)" % arrivals.size())
			if arrivals.size() == 2:
				_check(f, absi(int(arrivals[1]) - (int(arrivals[0]) + 90)) <= 2,
						"long_toll held: the second arrival came %d ticks after the first, want ~90 (1.5 s)" % (int(arrivals[1]) - int(arrivals[0])))
				var ddx := float(pos_x[1]) - float(pos_x[0])
				var ddz := float(pos_z[1]) - float(pos_z[0])
				_check(f, sqrt(ddx * ddx + ddz * ddz) < 0.01,
						"long_toll held: the second arrival landed %.3f u from the first locked point, want the same point" % sqrt(ddx * ddx + ddz * ddz))
		else:
			_check(f, arrivals.size() == 1,
					"long_toll control: %d ben arrivals within 1350 ticks, want 1 (the canon cycle)" % arrivals.size())
		_drop(world)


## quarter_chimes: "ben's teleport interval 13.35 -> 9 s". The curse itself starts ben's
## smoke once his idle has run 465 ticks, so the first arrival lands ~ tick 900
## (360 + 465 + 75) instead of ~ tick 1161 (360 + 801).
func _quarter_chimes(f: Array[String]) -> void:
	for held in [false, true]:
		var curses := {"quarter_chimes": 1} if held else {}
		var world = _build({"thicc_ben": 1}, curses)
		if world == null:
			f.append("quarter_chimes: build failed (held=%s)" % str(held))
			continue
		var telegraph_seen := false
		var arrivals: Array = []
		var prev_phase := "idle"
		for _t in range(1000):
			world.step(DT)
			var row := _first_row(world, "thicc_ben")
			if row.is_empty():
				continue
			var phase := str(row.get("phase", "idle"))
			if phase == "telegraph":
				telegraph_seen = true
			if prev_phase == "telegraph" and phase == "idle":
				arrivals.append(int(world.lstate.tick))
			prev_phase = phase
		if held:
			_check(f, telegraph_seen,
					"quarter_chimes held: ben never began his smoke within 1000 ticks")
			_check(f, arrivals.size() == 1,
					"quarter_chimes held: %d arrivals within 1000 ticks, want 1 (the 9 s cycle lands ~ tick 900)" % arrivals.size())
		else:
			_check(f, not telegraph_seen,
					"quarter_chimes control: ben's smoke began within 1000 ticks - the canon smoke starts at tick ~1086")
			_check(f, arrivals.is_empty(),
					"quarter_chimes control: %d arrival(s) within 1000 ticks, want none (the canon first arrival lands ~ tick 1161)" % arrivals.size())
		_drop(world)


# ---- on_tick: address me (longer_speech) ---------------------------------------------------------

## longer_speech: "you must hold still 2.5 s instead of 1.5 s". address me appears once the
## SR-4 gate opens (first allowed tick 600) and parks 6 u in front of the player; the
## stationary player is by definition still, so the gate is the only clock. The behavior's
## own gate is STILL_TICKS 90; the curse absorbs 60 of the +1 climb, so the visible arc
## runs 150 true still ticks before the episode's leaves state fires.
func _longer_speech(f: Array[String]) -> void:
	for held in [false, true]:
		var curses := {"longer_speech": 1} if held else {}
		var world = _build({"address_me": 1}, curses)
		if world == null:
			f.append("longer_speech: build failed (held=%s)" % str(held))
			continue
		var telegraph_tick := -1
		var leaves_tick := -1
		for _t in range(1400):
			world.step(DT)
			var row := _first_row(world, "address_me")
			if row.is_empty():
				continue
			var st := str(row.get("anim_state", ""))
			if st == "telegraph" and telegraph_tick < 0:
				telegraph_tick = int(world.lstate.tick)
			elif st == "leaves":
				leaves_tick = int(world.lstate.tick)
				break
		if telegraph_tick < 0:
			f.append("longer_speech (held=%s): address me never appeared within 1400 ticks (the SR-4 gate never opened)" % str(held))
		elif leaves_tick < 0:
			f.append("longer_speech (held=%s): the episode never reached the leaves state" % str(held))
		else:
			var span := leaves_tick - telegraph_tick
			var want := 150 if held else 90
			_check(f, absi(span - want) <= 1,
					"longer_speech %s: the gate broke after %d ticks of stillness, want ~%d (%.1f s)"
					% ["held" if held else "control", span, want, float(want) / 60.0])
		_drop(world)


# ---- on_tick: YOU?! (mirror_match) ---------------------------------------------------------------

## mirror_match: "YOU?! uses your class kit". The dasher clause: a 6 u transit every
## 300 ticks. The row appears at tick ~360 with the dash already due (the cadence clock
## starts at tick 300), and again at ~660 mid-rumble; the test measures the largest
## single-tick horizontal leap the row ever makes. The canon float is 3.4 u/s = 0.057 u
## per tick; a dash is ~6 u in one tick. invuln keeps an unrelated contact kill from
## ending the run before the measurement; the dash is the assertion, not a death.
func _mirror_match(f: Array[String]) -> void:
	for held in [false, true]:
		var curses := {"mirror_match": 1} if held else {}
		var world = _build({"you": 1}, curses)
		if world == null:
			f.append("mirror_match: build failed (held=%s)" % str(held))
			continue
		world.ctl.invuln = 100000.0   # the mirror's fist is not this case's subject
		var max_jump := 0.0
		var prev_x := 0.0
		var prev_z := 0.0
		var have_prev := false
		var mode := ""
		for _t in range(720):
			world.step(DT)
			var row := _first_row(world, "you")
			if row.is_empty():
				continue
			if mode == "" and str(row.get("mirror_mode", "")) != "":
				mode = str(row.get("mirror_mode", ""))
			var rx := float(row["x"])
			var rz := float(row["z"])
			if have_prev:
				var j: float = sqrt(pow(rx - prev_x, 2.0) + pow(rz - prev_z, 2.0))
				max_jump = maxf(max_jump, j)
			prev_x = rx
			prev_z = rz
			have_prev = true
		if held:
			_check(f, max_jump >= 5.0,
					"mirror_match held: max single-tick leap %.2f u, want ~6 u (the dasher dash)" % max_jump)
			_check(f, mode == "dash",
					"mirror_match held: mirror_mode %s on the row, want dash (the dasher kit)" % mode)
		else:
			_check(f, max_jump < 1.0,
					"mirror_match control: max single-tick leap %.3f u, want the plain float (< 1 u)" % max_jump)
			_check(f, mode == "",
					"mirror_match control: mirror_mode %s stamped without the curse, want unset" % mode)
		_drop(world)


# ---- on_tick: the nuke pair (second_strike) -------------------------------------------------------

## second_strike: "a second missile lands 1.0 s after the first on your new position".
## The nuke's own blast releases at the locked ring centre; at the LOCK boundary the
## player is moved 8.5 u diagonally (out of the 5 u sphere) and y-pinned, so the first
## blast misses. The curse records the player's position AT THE BLAST TICK - the new
## position, exactly the rule sentence - and 60 ticks later the second detonation lands
## there. charges == 0 (no Last Light to save it), so the held run dies with the
## curse's own code D-NUKE (the first blast, had it hit, would die with an empty code).
func _second_strike(f: Array[String]) -> void:
	for held in [false, true]:
		var curses := {"second_strike": 1} if held else {}
		var world = _build({"nuke": 1}, curses)
		if world == null:
			f.append("second_strike: build failed (held=%s)" % str(held))
			continue
		world.ctl.charges = 0   # no Last Light anywhere in this case
		var teleported := false
		var blast_seen := false
		var pin_y := float(world.ctl.y)
		for _t in range(1100):
			if teleported:
				world.ctl.y = pin_y
				world.ctl.vy = 0.0
			world.step(DT)
			var row := _first_row(world, "nuke")
			if row.is_empty():
				continue
			var phase := str(row.get("phase", ""))
			if phase == "lock" and not teleported:
				teleported = true
				world.ctl.x = float(world.ctl.x) + 6.0
				world.ctl.z = float(world.ctl.z) + 6.0
				world.ctl.vx = 0.0
				world.ctl.vz = 0.0
				pin_y = float(world.ctl.y)
			if int(row.get("explosion_left", 0)) == 24 or str(row.get("paused_by", "")) == "blast":
				blast_seen = true
		_check(f, teleported, "second_strike (held=%s): the nuke never entered the lock phase - probe invalid" % str(held))
		_check(f, blast_seen, "second_strike (held=%s): no nuke blast within 1100 ticks - probe invalid" % str(held))
		if held:
			_check(f, bool(world.ctl.dead),
					"second_strike held: the player survived both blasts - the second missile never landed")
			if bool(world.ctl.dead):
				_check(f, str(world.ctl.dead_code) == "D-NUKE",
						"second_strike held: death code %s, want D-NUKE (the second missile's own code)" % str(world.ctl.dead_code))
		else:
			_check(f, not bool(world.ctl.dead),
					"second_strike control: the player died without the curse - the first blast should have missed")
		_drop(world)


# ---- on_tick: the toucher (spreading_rot) -----------------------------------------------------------

## spreading_rot: "each glitched tile infects one adjacent tile after 6 s (max 2 generations)".
## The toucher infects tiles around itself on its own cadence; the curse watches
## world["glitched"] and 360 ticks after a source appears it flips the first of +x, -x,
## +z, -z that exists and is free. The two runs share a seed and a standing player, so the
## toucher's own tiles land identically; the count difference at tick 1500 is the spread.
func _spreading_rot(f: Array[String]) -> void:
	var sizes := [0, 0]
	var held_gl := {}
	var ctrl_gl := {}
	for k in 2:
		var held := k == 1
		var curses := {"spreading_rot": 1} if held else {}
		var world = _build({"toucher": 1}, curses)
		if world == null:
			f.append("spreading_rot: build failed (held=%s)" % str(held))
			continue
		world.ctl.invuln = 100000.0   # the toucher's contact kill is not this case's subject
		for _t in range(1500):
			world.step(DT)
		var gl: Dictionary = (world.rt.world as Dictionary).get("glitched", {})
		sizes[k] = gl.size()
		if held:
			held_gl = gl.duplicate()
		else:
			ctrl_gl = gl.duplicate()
		_drop(world)
	_check(f, ctrl_gl.size() > 0,
			"spreading_rot: the toucher glitched no tile within 1500 ticks - probe invalid")
	_check(f, sizes[1] > sizes[0],
			"spreading_rot: %d glitched tiles held vs %d control at tick 1500, want more when held" % [sizes[1], sizes[0]])
	var extra := 0
	for key in held_gl.keys():
		if not ctrl_gl.has(key):
			extra += 1
	_check(f, extra >= 1,
			"spreading_rot held: every held glitched key also exists in the control - the spread never happened (%d extra found)" % extra)


# ---- on_tick: claude (token_limit) ------------------------------------------------------------------

## token_limit: "a clawd leaves 20 s of anger instead of calming Claude completely" (D-T4-7). The
## pickup is real: the player is teleported onto a clawd's own centre (the gift pickup's 0.9 u
## test point), and the anger the pickup leaves behind is read off the sim. The canon calm is 0;
## the curse leaves 1200 ticks (20 s).
func _token_limit(f: Array[String]) -> void:
	var anger_pair := [-1, -1]
	var consumed := [false, false]
	for k in 2:
		var held := k == 1
		var curses := {"token_limit": 1} if held else {}
		var world = _build({"claude": 1}, curses)
		if world == null:
			f.append("token_limit: build failed (held=%s)" % str(held))
			continue
		var cl = world.lstate.clawds
		if cl == null or cl.count() < 1:
			f.append("token_limit: the level carries no clawd swarm (held=%s)" % str(held))
			_drop(world)
			continue
		world.ctl.invuln = 100000.0   # claude's body is not this case's subject
		for _t in range(200):
			world.step(DT)
		var before := int(cl.remaining())
		var p: Vector3 = cl.spot_pos(0)
		_place_player(world, p.x, p.y - 0.9, p.z)
		world.step(DT)
		anger_pair[k] = int(cl.anger_ticks)
		consumed[k] = int(cl.remaining()) < before
		_drop(world)
	_check(f, consumed[0] and consumed[1],
			"token_limit: the clawd pickup was not consumed in at least one run (control=%s held=%s)"
					% [str(consumed[0]), str(consumed[1])])
	_check(f, anger_pair[0] == 0,
			"token_limit control: the pickup left %d anger ticks, want 0 (the canon calm)" % anger_pair[0])
	_check(f, anger_pair[1] == 1200,
			"token_limit held: the pickup left %d anger ticks, want 1200 (20 s)" % anger_pair[1])


# ---- on_tick: gin (twin_fangs) ---------------------------------------------------------------------

## The curse adds a second converging sword without splitting the jump timing.
func _twin_fangs(f: Array[String]) -> void:
	for held in [false, true]:
		var curses := {"twin_fangs": 1} if held else {}
		var world = _build({"gin": 1}, curses)
		if world == null:
			f.append("twin_fangs: build failed (held=%s)" % str(held))
			continue
		world.ctl.invuln = 100000.0
		var twin_seen := false
		var sword_seen := false
		for _t in range(600):
			world.step(DT)
			var row := _first_row(world, "gin")
			if row.get("phase") != "sword":
				continue
			sword_seen = true
			twin_seen = row.has("gin_second_pos")
			if twin_seen:
				var first: Vector3 = row["gin_sword_pos"]
				var second: Vector3 = row["gin_second_pos"]
				_check(f, Vector2(first.x, first.z).distance_to(Vector2(second.x, second.z)) > 0.0,
						"twin_fangs: the two trajectories start at the same position")
			break
		_check(f, sword_seen, "twin_fangs: Gin never launched within 600 ticks")
		_check(f, twin_seen == held, "twin_fangs: second sword disagrees with held=%s" % held)
		_drop(world)
