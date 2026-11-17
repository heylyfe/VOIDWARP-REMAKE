#
# coil (ticket T-031; ENEMIES.md § 🌀 Springer → coil; DESIGN.md §5.2, numbers binding
# within ±1 tick). The section 12 API, the D-056 spawn rule and the T-027 kill API are
# exercised through spawn_at() fixtures (the runtime's sanctioned fixture path).
# KILL TESTS RUN WITH LAST LIGHT ALREADY SPENT (D-057): every controller here has spent
# its one save, so no assertion can be masked by it.
#
# Timings (DESIGN.md §5.2 / the T-083 anim block, 60 Hz ticks):
#   spawn 30 (2.75 s flight included in the cycle) → idle 180 (3.0 s) → cue 36 (0.6 s,
#   the boing + red ring r = 3 u at the landing zone) → flight 165 (2.75 s) → landing →
#   recover 24 → idle.
# The landing zone is the player's LAST GROUNDED TILE when the cue starts (D-064 item 3);
# it never updates after the cue starts. Landing within 1.2 u = kill (D-COIL). The 6 u
# shockwave shoves at 8 u/s decaying linearly to 0 over 0.5 s, never kills, and locks
# class abilities for 2.0 s; a jump timed so the feet are off the landing plane at the
# landing tick avoids it.

extends RefCounted

const EnemyRuntime := preload("res://sim/enemy_runtime.gd")
const CoilEnemy := preload("res://content/enemies/coil/enemy.gd")
const CoilTelegraph := preload("res://view/vfx/coil_telegraph.gd")
const Billboard := preload("res://view/billboard.gd")
const Util := preload("res://tests/sim_testutil.gd")

const DT := 1.0 / 60.0

const SPAWN_T := 30
const IDLE_T := 180
const CUE_T := 36
const FLIGHT_T := 165
const RECOVER_T := 24
const CUE_TICK := SPAWN_T + IDLE_T          # 210 (state flips to cue on this tick)
const FLIGHT_TICK := CUE_TICK + CUE_T       # 246 (state flips to flight on this tick)
const LAND_TICK := FLIGHT_TICK + FLIGHT_T   # 411 (flight_i reaches 165 -> landing resolves)


func run() -> Array[String]:
	var f: Array[String] = []
	_enemy_json_data(f)
	_timings_and_landing_kill(f)
	_zone_locked_at_cue_start(f)
	_shockwave_ground_band(f)
	_airborne_avoids_shockwave(f)
	_kill_ring_boundary(f)
	_contact_kill_before_cue(f)
	_ring_ages_out_at_landing(f)
	_copy_stagger(f)
	_idle_s_is_data(f)
	_view_vfx(f)
	_lobby_exhibit_path(f)
	return f


# 11x11 flat arena anchored at the dais (0, 0, 0); tile tops at y = 0.
func _arena() -> Dictionary:
	var tiles: Array = []
	for x in range(-5, 6):
		for z in range(-5, 6):
			tiles.append([x, z, 0])
	var w := Util.world_from_tiles(tiles)
	w["dais"] = [0, 0, 0]
	return w


func _spent_ctl(w: Dictionary, f: Array[String]):
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	ctl.place(w)
	# spend the one Last Light for real, then clear the arrival state so the fixture is
	# exactly "alive, unshielded, Last Light spent" (D-057)
	if not ctl.try_kill("D-TEST", "test", w, []):
		f.append("coil: spending Last Light failed")
	ctl.invuln = 0.0
	ctl.dead = false
	ctl.place(w)
	return ctl


# cfg assembled from the REAL content files (enemy.json + sprites.json) - the test fails
# if the data drifts from what it asserts.
func _cfg() -> Dictionary:
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/enemies/coil/enemy.json"))
	var stats: Dictionary = doc.get("stats", {})
	var sheet: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/enemies/coil/sprites.json"))
	var anims: Array = sheet.get("animations", [])
	var br: Array = anims[0]["body_rect"][0] if anims.size() > 0 else [0, 0, 256, 256]
	return {
		"world_height": float(stats.get("world_height", 1.0)),
		"frame_w": 512, "frame_h": 512, "body_rect": br,
		"contact_kill": true, "preferred_kind": "lane",
		"cycle_s": float(stats.get("cycle_ticks", 405)) / 60.0,
		"cycle_ticks": int(stats.get("cycle_ticks", 405)),
		"idle_s": float(stats.get("idle_s", 3.0)),
	}


func _spawn(rt, ctl, pos: Vector3, copy_index: int = 0, copies: int = 1) -> Dictionary:
	return rt.spawn_at("coil", "coil", CoilEnemy.behavior(), _cfg(), pos, copy_index, copies)


# Steps rt + ctl together (the engine caller steps both; tests control the order).
# Returns the number of steps run. ctl_fn(tick, ctl) runs before ctl.step each tick.
func _run_ticks(rt, ctl, w: Dictionary, n: int, ev_all: Array, ctl_fn: Callable = Callable()) -> int:
	var steps := 0
	for i in range(n):
		for e in rt.step(DT):
			ev_all.append(e)
		if ctl_fn.is_valid():
			ctl_fn.call(i, ctl)
		ctl.step(DT, Util.mk_in(), w)
		steps += 1
	return steps


func _timings_and_landing_kill(f: Array[String]) -> void:
	# player parked on the dais; coil homes to the dais tile - the landing lands ON the
	# player (within 1.2 u) and kills. Last Light already spent (D-057).
	var w := _arena()
	var ctl = _spent_ctl(w, f)
	var rt = EnemyRuntime.new()
	rt.setup({}, w, [ctl], 1234)
	var row: Dictionary = _spawn(rt, ctl, Vector3(3.5, 0.0, 0.5))
	var ev_all: Array = []
	var cue_at := -1
	var flight_at := -1
	var land_at := -1
	var max_y := 0.0
	var ring_seen_at_cue := false
	var height_in_flight := -1.0
	for i in range(LAND_TICK + RECOVER_T + 2):
		var evs: Array = rt.step(DT)
		for e in evs:
			ev_all.append(e)
		if str(row["state"]) == "cue" and cue_at < 0:
			cue_at = i + 1
			for e in evs:
				if e.get("e", "") == "telegraph" and e.get("kind", "") == "coil_ring":
					ring_seen_at_cue = true
					var sh: Dictionary = e.get("shape", {})
					if str(sh.get("shape", "")) != "circle" or absf(float(sh.get("r", 0.0)) - 3.0) > 1e-9:
						f.append("coil: telegraph shape %s, want circle r = 3.0" % str(sh))
					if absf(float(sh.get("cx", -99.0)) - 0.5) > 1e-9 or absf(float(sh.get("cz", -99.0)) - 0.5) > 1e-9:
						f.append("coil: ring at (%s, %s), want the dais tile centre (0.5, 0.5)"
								% [str(sh.get("cx")), str(sh.get("cz"))])
					if absf(float(sh.get("y0", -99.0)) - float(sh.get("y1", 99.0))) > 1e-9:
						f.append("coil: ring missing the landing-plane y band (y0 == y1)")
					if int(e.get("ticks", 0)) != CUE_T + FLIGHT_T:
						f.append("coil: ring telegraph ticks %s, want %d (visible for the whole cue and the flight)"
								% [str(e.get("ticks")), CUE_T + FLIGHT_T])
		if str(row["state"]) == "flight" and flight_at < 0:
			flight_at = i + 1
		max_y = maxf(max_y, float(row["y"]))
		if str(row["state"]) == "flight":
			height_in_flight = float(row["height_u"])
		if str(row["state"]) == "recover" and land_at < 0:
			land_at = i + 1
		ctl.step(DT, Util.mk_in(), w)
	# timings within ±1 tick
	if absi(cue_at - CUE_TICK) > 1:
		f.append("coil: cue began at tick %d, want %d ± 1" % [cue_at, CUE_TICK])
	if absi(flight_at - (CUE_TICK + CUE_T)) > 1:
		f.append("coil: flight began at tick %d, want %d ± 1" % [flight_at, CUE_TICK + CUE_T])
	if absi(land_at - LAND_TICK) > 1:
		f.append("coil: landing resolved at tick %d, want %d ± 1" % [land_at, LAND_TICK])
	if not ring_seen_at_cue:
		f.append("coil: no coil_ring telegraph event fired at the cue")
	if max_y < 3.5:
		f.append("coil: flight apex %.2f u, want >= 3.5 u (arc over the chord, D-T-031-2)" % max_y)
	if absf(height_in_flight - 2.0) > 1e-9:
		f.append("coil: in-flight height_u %s, want 2.0 (extended, SR-2)" % str(height_in_flight))
	if absf(float(row["y"]) - 0.0) > 1e-9:
		f.append("coil: landing y %s, want the landing tile's top plane 0.0" % str(row["y"]))
	if absf(float(row["x"]) - 0.5) > 1e-9 or absf(float(row["z"]) - 0.5) > 1e-9:
		f.append("coil: landed at (%s, %s), want the locked dais tile centre (0.5, 0.5)"
				% [str(row["x"]), str(row["z"])])
	if absf(float(row["height_u"]) - 1.0) > 1e-9:
		f.append("coil: landing height_u %s, want 1.0 (compressed on landing)" % str(row["height_u"]))
	# the landing killed the parked player, through the enemy's own code (D-COIL)
	if not ctl.dead:
		f.append("coil: landing on the player (within 1.2 u) did not kill")
	if str(ctl.dead_code) != "D-COIL":
		f.append("coil: death code %s, want D-COIL" % str(ctl.dead_code))
	if str(ctl.dead_killer) != "coil":
		f.append("coil: dead_killer %s, want coil" % str(ctl.dead_killer))
	var coil_death := false
	for e in ev_all:
		if e.get("e", "") == "death" and str(e.get("code", "")) == "D-COIL":
			coil_death = true
	if not coil_death:
		f.append("coil: no death event with code D-COIL in the event stream")
	# the boing fired at the cue, the twang at the landing
	var boing := false
	var twang := false
	for e in ev_all:
		if e.get("e", "") == "audio" and str(e.get("cue", "")) == "coil_boing":
			boing = true
		if e.get("e", "") == "coil_land" and str(e.get("cue", "")) == "coil_landing_twang":
			twang = true
	if not boing:
		f.append("coil: the pre-jump boing audio hook never fired")
	if not twang:
		f.append("coil: the landing twang audio hook never fired")


# A player whose feet are off the landing plane at the landing tick (airborne) takes no
# push and no lock (the spec's jump answer to the shove).
func _airborne_avoids_shockwave(f: Array[String]) -> void:
	var w := _arena()
	var ctl = _spent_ctl(w, f)
	var rt = EnemyRuntime.new()
	rt.setup({}, w, [ctl], 555)
	var row: Dictionary = _spawn(rt, ctl, Vector3(3.5, 0.0, 0.5))
	var moved := false
	var vx_at_landing := 999.0
	var lock_at_landing := 999.0
	for i in range(LAND_TICK + 1):
		# hold the player up off the plane for the whole flight and the landing tick:
		# a jump timed so the player is airborne at landing avoids the shockwave
		ctl.y = 1.5
		ctl.grounded = false
		ctl.vy = 0.0
		rt.step(DT)
		if not moved and str(row["state"]) == "cue":
			ctl.x = 2.5   # d = sqrt(8) ~ 2.8 u (> 1.2 kill ring, < 6 u shockwave), off the chord
			ctl.z = 2.5
			moved = true
		if str(row["state"]) == "recover":
			vx_at_landing = float(ctl.vx)
			lock_at_landing = float(ctl.lock)
		ctl.step(DT, Util.mk_in(), w)
	if not moved:
		f.append("coil: internal - cue never began (airborne test vacuous)")
		return
	if ctl.dead:
		f.append("coil: the airborne player in the 6 u band died (the shockwave never kills)")
	if absf(vx_at_landing) > 1e-9:
		f.append("coil: airborne player was pushed (vx = %.3f); the spec: a timed jump avoids the shove" % vx_at_landing)
	if lock_at_landing > 1e-9:
		f.append("coil: airborne player was ability-locked (%.2f s); the spec: a timed jump avoids the shove" % lock_at_landing)


# The 1.2 u kill ring: d = 1.20 kills, d = 1.21 does not (shocked instead).
func _kill_ring_boundary(f: Array[String]) -> void:
	for pair in [[1.2, true], [1.21, false]]:
		var d: float = pair[0]
		var want_kill: bool = pair[1]
		var w := _arena()
		var ctl = _spent_ctl(w, f)
		var rt = EnemyRuntime.new()
		rt.setup({}, w, [ctl], 321)
		var row: Dictionary = _spawn(rt, ctl, Vector3(3.5, 0.0, 0.5))
		var placed := false
		var outcome := "none"
		for i in range(LAND_TICK + 1):
			rt.step(DT)
			if not placed and str(row["state"]) == "cue":
				# tile (0,1): feet on the plane, but perpendicular distance 1.2 / 1.21 u from
				# the locked zone; and OFF the takeoff chord so no descent contact fires.
				ctl.x = 0.5
				ctl.z = 0.5 + d
				placed = true
			if str(row["state"]) == "recover" and outcome == "none":
				outcome = "killed" if ctl.dead else "alive"
			ctl.step(DT, Util.mk_in(), w)
		if not placed:
			f.append("coil: internal - cue never began (boundary d = %.2f vacuous)" % d)
			continue
		if want_kill and outcome != "killed":
			f.append("coil: d = %.2f inside the 1.2 u ring, player not killed" % d)
		if not want_kill and outcome != "alive":
			f.append("coil: d = %.2f outside the 1.2 u ring, player killed" % d)


# Body contact kills before any cue can fire (the KILL RULE), with Last Light spent.
func _contact_kill_before_cue(f: Array[String]) -> void:
	var w := _arena()
	var ctl = _spent_ctl(w, f)
	var rt = EnemyRuntime.new()
	rt.setup({}, w, [ctl], 222)
	_spawn(rt, ctl, Vector3(0.5, 0.0, 0.5))   # on the player's tile, spawn state
	for i in range(3):
		rt.step(DT)
		ctl.step(DT, Util.mk_in(), w)
	if not ctl.dead:
		f.append("coil: body contact in the spawn/idle state did not kill")
	if str(ctl.dead_code) != "D-COIL":
		f.append("coil: body-contact death code %s, want D-COIL" % str(ctl.dead_code))


# The coil_ring telegraph ages exactly to 0 at the landing tick (D-T072-4): while the
# cue and the flight run Address me's gate is blocked; afterwards it is free.
func _ring_ages_out_at_landing(f: Array[String]) -> void:
	var w := _arena()
	var ctl = _spent_ctl(w, f)
	var rt = EnemyRuntime.new()
	rt.setup({}, w, [ctl], 4321)
	var row: Dictionary = _spawn(rt, ctl, Vector3(3.5, 0.0, 0.5))
	var during_flight := -1
	var at_landing := -1
	for i in range(LAND_TICK + 2):
		rt.step(DT)
		for t in rt.telegraphs:
			if str(t.get("kind", "")) == "coil_ring":
				if str(row["state"]) == "flight":
					during_flight = int(t["ticks"])
				elif str(row["state"]) == "recover":
					at_landing = int(t["ticks"])
		ctl.step(DT, Util.mk_in(), w)
	if during_flight <= 0:
		f.append("coil: coil_ring telegraph ticks %d mid-flight, want > 0" % during_flight)
	if at_landing != 0:
		f.append("coil: coil_ring telegraph ticks %d at the landing, want 0 (caller-aged, D-T072-4)" % at_landing)


# SR-3: copy k of n staggers its first cue; never a mid-cue spawn.
func _copy_stagger(f: Array[String]) -> void:
	var w := _arena()
	var ctl = _spent_ctl(w, f)
	var rt = EnemyRuntime.new()
	rt.setup({}, w, [ctl], 31337)
	var cfg: Dictionary = _cfg()
	var r0: Dictionary = rt.spawn_at("coil", "coil", CoilEnemy.behavior(), cfg,
			Vector3(30.5, 0.0, 0.5), 0, 2)
	var r1: Dictionary = rt.spawn_at("coil", "coil", CoilEnemy.behavior(), cfg,
			Vector3(60.5, 0.0, 5.5), 1, 2)
	if int(r0.get("first_cue_extra", -1)) != 0:
		f.append("coil: copy 0 first_cue_extra %s, want 0" % str(r0.get("first_cue_extra")))
	if int(r1.get("first_cue_extra", 0)) < 100:
		f.append("coil: copy 1 first_cue_extra %s, want ~half a cycle (>= 100)" % str(r1.get("first_cue_extra")))
	if str(r1.get("state")) != "spawn":
		f.append("coil: copy 1 spawned into state %s, want spawn (never mid-cue, D-T-031-9)" % str(r1.get("state")))


# The idle segment length is data (idle_s) so Overwound can shorten it (D-T-031-12).
func _idle_s_is_data(f: Array[String]) -> void:
	var w := _arena()
	var ctl = _spent_ctl(w, f)
	var rt = EnemyRuntime.new()
	rt.setup({}, w, [ctl], 8888)
	var cfg: Dictionary = _cfg()
	cfg["idle_s"] = 2.0   # Overwound stack 1
	var row: Dictionary = rt.spawn_at("coil", "coil", CoilEnemy.behavior(), cfg, Vector3(3.5, 0.0, 0.5))
	var cue_at := -1
	for i in range(SPAWN_T + 120 + CUE_T + 2):
		rt.step(DT)
		if str(row["state"]) == "cue" and cue_at < 0:
			cue_at = i + 1
		ctl.step(DT, Util.mk_in(), w)
	if absi(cue_at - (SPAWN_T + 120)) > 1:
		f.append("coil: cue at tick %d with idle_s = 2.0, want %d ± 1" % [cue_at, SPAWN_T + 120])


# The view VFX: the landing ring for each live coil_ring telegraph, freed when it
# expires; the expanding shockwave on impact; the anim-block constants.
func _view_vfx(f: Array[String]) -> void:
	if absf(CoilTelegraph.RING_RADIUS - 3.0) > 1e-9:
		f.append("coil view: RING_RADIUS %.3f, want 3.0 (T-083 telegraph red_ring)" % CoilTelegraph.RING_RADIUS)
	if absf(CoilTelegraph.SHOCKWAVE_RADIUS - 6.0) > 1e-9:
		f.append("coil view: SHOCKWAVE_RADIUS %.3f, want 6.0 (DESIGN.md section 5.2)" % CoilTelegraph.SHOCKWAVE_RADIUS)
	if CoilTelegraph.SHOCKWAVE_EXPAND_TICKS != 12:
		f.append("coil view: shockwave expands over %d ticks, want 12 (T-083 attack_landing)" % CoilTelegraph.SHOCKWAVE_EXPAND_TICKS)
	var vfx = CoilTelegraph.new()
	var tgr := [{"kind": "coil_ring", "source": "coil", "ticks": 201, "total": 201,
			"shape": {"shape": "circle", "cx": 0.5, "cz": 0.5, "r": 3.0, "y0": 0.0, "y1": 0.0}}]
	vfx.sync(tgr, 1)
	if vfx.ring_count() != 1:
		f.append("coil view: %d landing rings for one live coil_ring telegraph, want 1" % vfx.ring_count())
	vfx.sync([{"kind": "coil_ring", "source": "coil", "ticks": 0,
			"shape": {"shape": "circle", "cx": 0.5, "cz": 0.5, "r": 3.0, "y0": 0.0, "y1": 0.0}}], 1)
	if vfx.ring_count() != 0:
		f.append("coil view: landing ring survived its telegraph's expiry")
	vfx.impact(Vector3(0.5, 0.0, 0.5))
	if vfx.shock_count() != 1:
		f.append("coil view: impact() did not spawn a shockwave")
	for _i in range(18):
		vfx.sync([], 1)
	if vfx.shock_count() != 0:
		f.append("coil view: shockwave did not fade after 18 ticks")
	vfx.free()


# The landing zone must stay the cue-start LAST GROUNDED TILE even if the player
# re-grounds elsewhere mid-cue (D-064 item 3).
func _zone_locked_at_cue_start(f: Array[String]) -> void:
	var w := _arena()
	var ctl = _spent_ctl(w, f)
	var rt = EnemyRuntime.new()
	rt.setup({}, w, [ctl], 777)
	var row: Dictionary = _spawn(rt, ctl, Vector3(3.5, 0.0, 0.5))
	var moved := false
	for i in range(LAND_TICK + 1):
		rt.step(DT)
		if not moved and str(row["state"]) == "cue":
			# re-ground the player on a different tile, off the takeoff chord; the ring/landing must not move
			ctl.x = 2.5
			ctl.z = 2.5
			moved = true
		ctl.step(DT, Util.mk_in(), w)
	if not moved:
		f.append("coil: internal - cue never began (zone lock test vacuous)")
		return
	if absf(float(row["x"]) - 0.5) > 1e-9 or absf(float(row["z"]) - 0.5) > 1e-9:
		f.append("coil: zone moved to (%s, %s) after mid-cue re-grounding, want the cue-start tile (0.5, 0.5)"
				% [str(row["x"]), str(row["z"])])


# A player on the landing plane within 6 u (but outside the kill ring): shoved outward at
# 8 u/s decaying linearly to 0 over 0.5 s, ability-locked 2.0 s, never killed.
func _shockwave_ground_band(f: Array[String]) -> void:
	var w := _arena()
	var ctl = _spent_ctl(w, f)
	# d = sqrt(8) ~ 2.8 u from the dais tile centre: outside the 1.2 kill ring, inside the
	# 6 u shockwave, and OFF the takeoff/landing chord (the coil flies along z = 0.5).
	# (Also covers a genuine mid-cue re-grounding, same as the zone-lock test.)
	var rt = EnemyRuntime.new()
	rt.setup({}, w, [ctl], 999)
	var row: Dictionary = _spawn(rt, ctl, Vector3(3.5, 0.0, 0.5))
	var moved := false
	var locked_at_landing := -1.0
	var pre_x := 0.0
	var pre_z := 0.0
	var land_seen := false
	for i in range(LAND_TICK + 122):
		rt.step(DT)
		if not moved and str(row["state"]) == "cue":
			ctl.x = 2.5
			ctl.z = 2.5
			moved = true
		if not land_seen and str(row["state"]) == "recover":
			locked_at_landing = float(ctl.lock)   # decays only inside ctl.step: still ~2.0 here
			pre_x = ctl.x
			pre_z = ctl.z
			land_seen = true
		ctl.step(DT, Util.mk_in(), w)
	if not moved or not land_seen:
		f.append("coil: internal - cue/landing never happened (shockwave test vacuous)")
		return
	if ctl.dead:
		f.append("coil: shockwave killed the player (it never kills)")
	if locked_at_landing < 1.9:
		f.append("coil: ability lock at the landing tick was %.2f s, want ~2.0 s" % locked_at_landing)
	var pushed: float = sqrt(pow(ctl.x - pre_x, 2.0) + pow(ctl.z - pre_z, 2.0))
	if pushed < 0.9:
		f.append("coil: shockwave displaced the player %.2f u, want >= 0.9 u (the D-066 1-wide path floor)" % pushed)
	if pushed > 2.6:
		f.append("coil: shockwave displaced the player %.2f u, want <= 2.6 u (linear decay budget)" % pushed)
	if ctl.ability_locked(w):
		f.append("coil: ability lock still held 120 ticks after the landing")


func _enemy_json_data(f: Array[String]) -> void:
	var text: String = FileAccess.get_file_as_string("res://content/enemies/coil/enemy.json")
	var doc: Variant = JSON.parse_string(text)
	if doc == null or not (doc is Dictionary):
		f.append("coil: enemy.json does not parse")
		return
	if str(doc.get("id", "")) != "coil" or str(doc.get("name", "")) != "coil":
		f.append("coil: enemy.json id/name mismatch")
	if int(doc.get("min_level", -1)) != 1:
		f.append("coil: min_level %s, want 1 (starter pool)" % str(doc.get("min_level")))
	if int(doc.get("max_votes", -1)) != 3:
		f.append("coil: max_votes %s, want 3" % str(doc.get("max_votes")))
	if str(doc.get("vote_effect", "")) != "+1 coil":
		f.append("coil: vote_effect %s, want '+1 coil'" % str(doc.get("vote_effect")))
	var kinds: Array = doc.get("anchor_kinds", [])
	if kinds != ["lane"]:
		f.append("coil: anchor_kinds %s, want [lane] (DESIGN.md §5 preferred-kind table)" % str(kinds))
	var s: Dictionary = doc.get("stats", {})
	if absf(float(s.get("world_height", -1.0)) - 1.0) > 1e-9:
		f.append("coil: squashed world_height %s, want 1.0" % str(s.get("world_height")))
	if absf(float(s.get("extended_height_u", -1.0)) - 2.0) > 1e-9:
		f.append("coil: extended height %s, want 2.0" % str(s.get("extended_height_u")))
	if absf(float(s.get("hit_diameter_u", -1.0)) - 0.9) > 1e-9:
		f.append("coil: hit diameter %s, want 0.9 (SR-2)" % str(s.get("hit_diameter_u")))
	if str(s.get("death_code", "")) != "D-COIL":
		f.append("coil: death_code %s, want D-COIL" % str(s.get("death_code")))
	if str(s.get("counter_play_line", "")) == "" or str(s.get("tell_line", "")) == "":
		f.append("coil: counter_play_line / tell_line missing or empty")
	var audio: Dictionary = s.get("audio", {})
	if str(audio.get("jump_cue", "")) != "coil_boing" or str(audio.get("landing", "")) != "coil_landing_twang":
		f.append("coil: audio cues must be coil_boing / coil_landing_twang")
	if not bool(doc.get("script", false)):
		f.append("coil: script must be true")
	if str(doc.get("sprites", "")) != "res://content/enemies/coil/sprites.json":
		f.append("coil: sprites path wrong: %s" % str(doc.get("sprites")))
	# the arbiter block is deliberately absent (D-T-031-8)
	if s.has("arbiter") or doc.has("arbiter"):
		f.append("coil: no document gates coil's appearance; the arbiter block must be absent (D-T-031-8)")
# The lobby enemy exhibit path (view/lobby/antechamber.gd): parses the enemy's
# sprites.json and renders the REAL billboarded frames, scaled to 1.6 u. The exact
# data the exhibit dereferences must exist and load for coil - this fails if the
# frames move, the parse breaks, or the name is unreadable.
func _lobby_exhibit_path(f: Array[String]) -> void:
	var sheet_path := "res://content/enemies/coil/sprites.json"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(sheet_path))
	if not (parsed is Dictionary) or (parsed as Dictionary).is_empty():
		f.append("coil: the exhibit's parse_string failed on sprites.json")
		return
	var doc: Dictionary = parsed
	var bb = Billboard.new()
	bb.setup_from_sheet(doc, "res://content/enemies/coil")
	if str(doc.get("name", "")) != "coil":
		f.append("coil: sheet name %s, want 'coil' (the exhibit renders the name)" % str(doc.get("name")))
	if absf(bb.world_height - 2.0) > 1e-9:
		f.append("coil: sheet world_height %.2f, want 2.0 (the exhibit scales to it)" % bb.world_height)
	var cycle: Dictionary = bb.anims.get("cycle", {})
	if cycle.is_empty():
		f.append("coil: no 'cycle' animation in the sheet (the exhibit's frames come from it)")
		return
	var frames: Array = cycle["frames"]
	if frames.size() != 5:
		f.append("coil: %d cycle frames, want 5" % frames.size())
	for i in range(frames.size()):
		if frames[i] == null:
			f.append("coil: cycle frame %d failed to load" % i)
	bb.free()