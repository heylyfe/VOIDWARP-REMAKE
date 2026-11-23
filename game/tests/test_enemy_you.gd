extends RefCounted
#
# YOU?! tests (ticket T-035). DESIGN.md section 5.6 is the spec; every timing and
# number of the paragraph is asserted within +/-1 tick. Kill tests run with the
# player's LAST LIGHT already spent (D-057) - otherwise the save masks the kill
# and the assertion is worthless.
#
# Readings under test (DECISIONS D-T-035-1..13, D-YOU-C7-1..3):
# - ring kill window: player feet strictly inside (ring_feet - 1.5, ring_feet + 1.0);
# - radial window: |dist - r| <= 0.7 u;
# - the rumble holds the body in place; the release hold is 18 ticks; recover 240;
# - cycle 7 (owner: "you?!" smaller range + slower strike): the ring's reach is 8 u
#   (<= 60% of the old 14 u), the tell is 180 ticks (2x the old 90), and the jump
#   window that clears the band is still there - asserted against the real controller.

const EnemyRuntime := preload("res://sim/enemy_runtime.gd")
const Util := preload("res://tests/sim_testutil.gd")
const YouEnemy := preload("res://content/enemies/you/enemy.gd")
const DeathScript := preload("res://sim/death.gd")
const ContentApiScript := preload("res://core/content_api.gd")
const BillboardScript := preload("res://view/billboard.gd")
const YouViewScript := preload("res://view/you_view.gd")
const OffersScript := preload("res://sim/offers.gd")

const DT := 1.0 / 60.0


func run() -> Array[String]:
	var f: Array[String] = []
	_pursuit_speed_and_ceiling(f)
	_trigger_distance(f)
	_rumble_release_and_recover_timing(f)
	_ring_expansion_and_cap(f)
	_ring_expires_and_never_accumulates(f)
	_ring_vertical_windows(f)
	_ring_kills_and_death_code(f)
	_jump_window_clears_the_ring(f)
	_cooldown_blocks_retrigger(f)
	_contact_kills(f)
	_echo_ring_row_hooks(f)
	_anim_block_wiring(f)
	_roster_data(f)
	_lobby_exhibit(f)
	return f


# ---- fixtures ----------------------------------------------------------------

func _tiles_full() -> Array:
	var tiles: Array = []
	for x in range(-10, 11):
		for z in range(-10, 11):
			tiles.append([x, z, 0, 0, 0])
	return tiles


func _level() -> Dictionary:
	return {"beacon": [0, 0, 0], "spawns": [[0, 0, 0]], "anchors": [],
			"tiles": _tiles_full(), "props": [], "pads": []}


func _arena() -> Dictionary:
	var flat: Array = []
	for t in _tiles_full():
		flat.append([t[0], t[1], t[2]])
	var w := Util.world_from_tiles(flat)
	w["dais"] = [0, 0, 0]
	return w


# Last Light spent for real, then the arrival state cleared: the fixture is
# exactly "alive, unshielded, Last Light spent" (D-057).
func _spent_ctl(w: Dictionary):
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	ctl.place(w)
	ctl.try_kill("D-TEST", "test", w, [])
	ctl.invuln = 0.0
	ctl.dead = false
	ctl.place(w)
	return ctl


func _cfg(base_speed: float = 3.4) -> Dictionary:
	return {"world_height": 1.8, "frame_w": 256, "frame_h": 256,
			"body_rect": [16, 16, 224, 224], "contact_kill": true,
			"cycle_s": 0.625, "preferred_kind": "open",
			"base_speed": base_speed, "pursuit_ceiling": 0.55, "burst_ceiling": 1.0,
			"trigger_distance": YouEnemy.TRIGGER_DISTANCE,
			"rumble_ticks": YouEnemy.RUMBLE_TICKS,
			"ring_speed_u_per_s": YouEnemy.RING_SPEED,
			"ring_max_radius": YouEnemy.RING_MAX,
			"ring_thickness": YouEnemy.RING_THICK,
			"ring_height": YouEnemy.RING_HEIGHT,
			"ring_below_feet": YouEnemy.RING_BELOW,
			"ring_cooldown_ticks": YouEnemy.RING_COOLDOWN,
			"attack_hold_ticks": YouEnemy.ATTACK_HOLD,
			"recover_ticks": YouEnemy.RECOVER_TICKS}


# [rt, row, ctl]; the controller sits on the spawn tile and never moves.
func _spawn(pos: Vector3, display_name: String = "YOU?!", base_speed: float = 3.4) -> Array:
	var w := _arena()
	var ctl = _spent_ctl(w)
	var rt = EnemyRuntime.new()
	rt.setup(_level(), w, [ctl], 4242)
	var row: Dictionary = rt.spawn_at("you", display_name, YouEnemy.new(), _cfg(base_speed), pos)
	return [rt, row, ctl]


func _death_events(rt) -> Array:
	var out: Array = []
	for e in rt.events:
		if e.get("e", "") == "death":
			out.append(e)
	return out


func _telegraph_events(rt) -> Array:
	var out: Array = []
	for e in rt.events:
		if e.get("e", "") == "telegraph":
			out.append(e)
	return out


# ---- SR-5 pursuit (section 5.6: 3.4 u/s, ceiling 0.55 -> 4.95 u/s) -----------

func _pursuit_speed_and_ceiling(f: Array[String]) -> void:
	var spawned := _spawn(Vector3(12.5, 0.0, 0.5))
	var rt = spawned[0]
	var row = spawned[1]
	rt.step(DT)
	var fb = row["float"]
	if fb == null or absf(float(fb.h_speed) - 3.4) > 1e-9:
		f.append("pursuit: base h_speed %s, want 3.4" % str(fb.h_speed if fb != null else "missing"))
	# the full SR-5 stack: overtime tier 8 (x1.48) x curse 1.08^3 (Rush Hour)
	rt.overtime_running = true
	rt.add_overtime_tier(8)
	rt.curse_speed_mul = 1.08 * 1.08 * 1.08
	for i in range(180):
		rt.step(DT)
		if absf(float(fb.h_speed) - 4.95) > 1e-9:
			f.append("pursuit: ceiling broken at tick %d: h_speed %.6f, want 4.95" % [i, float(fb.h_speed)])
			break
	var raw: float = 3.4 * 1.48 * 1.08 * 1.08 * 1.08
	if absf(float(fb.tempo_mul) - raw / 4.95) > 1e-6:
		f.append("pursuit: tempo_mul %.6f, want %.6f (raw/clamped)" % [float(fb.tempo_mul), raw / 4.95])


# ---- the 8 u rumble trigger --------------------------------------------------

func _trigger_distance(f: Array[String]) -> void:
	# 12.5 u away: 25 ticks closes 1.4 u - still beyond 8 u, nothing fires
	var far := _spawn(Vector3(12.5, 0.0, 0.5))
	var rt = far[0]
	for i in range(25):
		rt.step(DT)
	if str(far[1]["anim_state"]) == "telegraph":
		f.append("trigger: rumble started from beyond 8 u")
	if not _telegraph_events(rt).is_empty():
		f.append("trigger: a telegraph fired from beyond 8 u")
	# exactly 8.0 u: triggers ("within 8 u" is inclusive)
	var edge := _spawn(Vector3(8.5, 0.0, 0.5))
	rt = edge[0]
	rt.step(DT)
	if str(edge[1]["anim_state"]) != "telegraph":
		f.append("trigger: no rumble at exactly 8.0 u (anim_state %s)" % str(edge[1]["anim_state"]))
	else:
		var tele := _telegraph_events(rt)
		if tele.is_empty() or int(tele[0]["ticks"]) != 180:
			f.append("trigger: telegraph ticks %s, want 180" % str(tele))
	# 7.5 u: triggers as well
	var near := _spawn(Vector3(8.0, 0.0, 0.5))
	rt = near[0]
	rt.step(DT)
	if str(near[1]["anim_state"]) != "telegraph":
		f.append("trigger: no rumble at 7.5 u")


# ---- rumble (180 ticks) -> attack (18) -> recover (240) -> chase -------------

func _rumble_release_and_recover_timing(f: Array[String]) -> void:
	var spawned := _spawn(Vector3(5.0, 0.0, 0.5), "YOU?!", 0.0)
	var rt = spawned[0]
	var row = spawned[1]
	var t_trig := -1
	for i in range(400):
		rt.step(DT)
		if str(row["anim_state"]) == "telegraph":
			t_trig = int(rt.tick)
			break
	if t_trig < 0:
		f.append("timing: rumble never started from 5 u")
		return
	var t_attack := -1
	for i in range(400):
		rt.step(DT)
		if str(row["anim_state"]) == "attack":
			t_attack = int(rt.tick)
			break
	if t_attack < 0:
		f.append("timing: the ring never released")
		return
	var rumble_ticks := t_attack - t_trig
	if absi(rumble_ticks - 180) > 1:
		f.append("timing: rumble lasted %d ticks, want 180 +/-1" % rumble_ticks)
	if (row["rings"] as Array).is_empty():
		f.append("timing: no ring at the attack tick")
	var t_recover := -1
	for i in range(400):
		rt.step(DT)
		if str(row["anim_state"]) == "recover":
			t_recover = int(rt.tick)
			break
	if t_recover < 0:
		f.append("timing: recover never started")
		return
	if absi(t_recover - t_attack - 18) > 1:
		f.append("timing: attack hold %d ticks, want 18 +/-1" % (t_recover - t_attack))
	var t_chase := -1
	for i in range(600):
		rt.step(DT)
		if str(row["anim_state"]) == "idle_chase":
			t_chase = int(rt.tick)
			break
	if t_chase < 0:
		f.append("timing: idle_chase never resumed")
		return
	if absi(t_chase - t_recover - 240) > 1:
		f.append("timing: recover lasted %d ticks, want 240 +/-1" % (t_chase - t_recover))

# ---- ring: 9 u/s expansion, 8 u cap -----------------------------------------

func _release_ring_now(spawned: Array) -> int:
	var rt = spawned[0]
	var row = spawned[1]
	for i in range(400):
		rt.step(DT)
		if str(row["anim_state"]) == "attack":
			return int(rt.tick)
	return -1


func _ring_expansion_and_cap(f: Array[String]) -> void:
	var spawned := _spawn(Vector3(5.0, 0.0, 0.5), "YOU?!", 0.0)
	var rt = spawned[0]
	var row = spawned[1]
	var t_rel := _release_ring_now(spawned)
	if t_rel < 0:
		f.append("ring: never released")
		return
	var rings: Array = row["rings"]
	if rings.is_empty():
		f.append("ring: no live ring on the release tick")
		return
	# one tick after release: r ~= 0.15 (9 u/s)
	rt.step(DT)
	rings = row["rings"]
	var r1 := float(rings[0]["r"]) if not rings.is_empty() else -1.0
	if absf(r1 - 0.15) > 0.001:
		f.append("ring: r after 1 tick %.4f, want 0.15" % r1)
	# ten ticks in: r ~= 1.5
	for i in range(9):
		rt.step(DT)
	rings = row["rings"]
	var r10 := float(rings[0]["r"]) if not rings.is_empty() else -1.0
	if absf(r10 - 1.5) > 0.02:
		f.append("ring: r after 10 ticks %.4f, want 1.5 +/-0.02" % r10)
	# cap: the band expands to 8 u and then vanishes (never past 8)
	var saw_cap := false
	for i in range(120):
		rt.step(DT)
		rings = row["rings"]
		if rings.is_empty():
			break
		var r := float(rings[0]["r"])
		if r > 8.0 + 1e-9:
			f.append("ring: radius %.4f exceeded the 8 u cap" % r)
			break
		if absf(r - 8.0) < 1e-9:
			saw_cap = true
	if not saw_cap:
		f.append("ring: never reached the 8 u cap")


# A ring lives exactly through the tick it reaches 8 u (its last kill check, marked done)
# and is gone from row["rings"] on the next tick, so the view - which draws the newest
# ring with no `done` check of its own - never holds a spent 8 u band through the 4.0 s
# recover. Across several release cycles row["rings"] never holds more than the one live
# ring (the list does not grow for the level). The player is kept unkillable so the
# behavior keeps re-triggering.
func _ring_expires_and_never_accumulates(f: Array[String]) -> void:
	var spawned := _spawn(Vector3(5.0, 0.0, 0.5), "YOU?!", 0.0)
	var rt = spawned[0]
	var row = spawned[1]
	var ctl = spawned[2]
	ctl.invuln = 1.0e9
	if _release_ring_now(spawned) < 0:
		f.append("ring expiry: never released")
		return
	var capped: Variant = null
	for i in range(200):
		rt.step(DT)
		var rings: Array = row["rings"]
		if rings.size() == 1 and float(rings[0]["r"]) >= YouEnemy.RING_MAX:
			capped = rings[0]
			break
	if capped == null:
		f.append("ring expiry: the ring never reached the 8 u cap")
		return
	if not bool((capped as Dictionary).get("done", false)):
		f.append("ring expiry: the ring at 8 u is not marked done on its cap tick")
	rt.step(DT)
	if not (row["rings"] as Array).is_empty():
		f.append("ring expiry: %d ring(s) still on the row one tick after the cap, want 0"
				% (row["rings"] as Array).size())
	if str(row["anim_state"]) != "recover":
		f.append("ring expiry: state %s one tick after the cap, want recover (the window the stale band would show in)"
				% str(row["anim_state"]))
	var v = YouViewScript.new()
	v.setup("res://content/enemies/you/sprites.json", "res://content/enemies/you")
	v.sync(row, DT)
	if v.band != null and v.band.visible:
		f.append("ring expiry: the view still draws the band (scale %.2f) after the ring expired"
				% float(v.band.scale.x))
	v.free()
	# three more full cycles (rumble 180 + attack 18 + recover 240 = 438 ticks each)
	var seq0 := int(row["ring_seq"])
	var most := 0
	for i in range(3 * 450):
		rt.step(DT)
		most = maxi(most, (row["rings"] as Array).size())
		for ring in row["rings"]:
			if bool(ring.get("done", false)) and float(ring["r"]) < YouEnemy.RING_MAX:
				f.append("ring expiry: a done ring below the cap (r %.3f)" % float(ring["r"]))
				return
	if int(row["ring_seq"]) - seq0 < 2:
		f.append("ring expiry: only %d further release(s) in %d ticks, want >= 2"
				% [int(row["ring_seq"]) - seq0, 3 * 450])
	if most > 1:
		f.append("ring expiry: row[\"rings\"] held %d rings at once, want <= 1 (it must not grow)" % most)


# ---- vertical escape windows (jump / above / below) ---------------------------

func _ring_vertical_windows(f: Array[String]) -> void:
	# The ring freezes its plane at release (its own feet), so teleporting the
	# player relative to the released ring tests the exact kill rule:
	# feet strictly inside (ring_feet - 1.5, ring_feet + 1.0) = hit; on or outside = safe.
	var cases: Array = [
		[0.99, true], [1.0, false], [1.5, false], [2.25, false],
		[-0.1, true], [-1.4, true], [-1.5, false], [-1.6, false],
	]
	for c in cases:
		var spawned := _spawn(Vector3(6.0, 0.0, 0.5), "YOU?!", 0.0)
		var rt = spawned[0]
		var row = spawned[1]
		var ctl = spawned[2]
		var t_rel := _release_ring_now(spawned)
		if t_rel < 0:
			f.append("vertical %+.2f: never released" % float(c[0]))
			continue
		var rings: Array = row["rings"]
		if rings.is_empty():
			f.append("vertical %+.2f: no live ring at release" % float(c[0]))
			continue
		var ry := float(rings[0]["y"])
		ctl.y = ry + float(c[0])
		for i in range(200):
			rt.step(DT)
			if ctl.dead or (row["rings"] as Array).is_empty():
				break
		var want_hit := bool(c[1])
		if ctl.dead != want_hit:
			f.append("vertical %+.2f: dead=%s, want %s" % [float(c[0]), str(ctl.dead), str(want_hit)])

# ---- the ring kill's death code ----------------------------------------------

func _ring_kills_and_death_code(f: Array[String]) -> void:
	var spawned := _spawn(Vector3(11.0, 0.0, 0.5))
	var rt = spawned[0]
	var ctl = spawned[2]
	var t_rel := _release_ring_now(spawned)
	if t_rel < 0:
		f.append("kill: never released")
		return
	for i in range(200):
		rt.step(DT)
		if ctl.dead:
			break
	if not ctl.dead:
		f.append("kill: the ring never killed the grounded player")
		return
	var deaths := _death_events(rt)
	var found := false
	for d in deaths:
		if str(d["code"]) == "D-YOU" and str(d["killer"]) == "YOU":
			found = true
	if not found:
		f.append("kill: death event %s, want code D-YOU killer YOU" % str(deaths))
	if str(DeathScript.killer_for("D-YOU")) != "YOU?!":
		f.append("kill: death.gd maps D-YOU to %s, want YOU?!" % str(DeathScript.killer_for("D-YOU")))


# ---- the jump window still clears the smaller ring (cycle 7) -------------------
#
# The band's crossing time is 2 x RING_RADIAL_WINDOW / RING_SPEED = 0.156 s whatever
# the radius is, so shrinking the ring does NOT shrink the jump window - it only
# shortens how long the band lives (8 u / 9 u/s = 0.89 s instead of 1.56 s). This
# runs the REAL controller against the REAL ring: the tell holds position, so the
# band is released at the trigger distance and reaches a standing player at
# (d - window) / speed .. min(d + window, RING_MAX) / speed. A jump pressed inside
# the window that keeps the feet above the 1.0 u band top for that whole span
# survives; no jump, and a jump pressed on the release tick (landed before the band
# arrives), both die. The airborne window comes from the shared kit, not a literal.

func _jump_arm(d: float, press_s: float) -> bool:
	var w := _arena()
	var ctl = _spent_ctl(w)
	var rt = EnemyRuntime.new()
	rt.setup(_level(), w, [ctl], 4242)
	var row: Dictionary = rt.spawn_at("you", "YOU?!", YouEnemy.new(), _cfg(0.0),
			Vector3(0.5 + d, 0.0, 0.5))
	var release_tick := -1
	var press_tick := -1
	# the button is HELD through the rise: releasing it while vy > 0 applies the
	# shared kit's jump cut (x0.5) and the feet never reach the 1.0 u band top
	var hold_ticks := 30
	for i in range(600):
		var buttons := 0
		if release_tick >= 0 and press_s >= 0.0 and press_tick < 0 \
				and float(i - release_tick) >= press_s * 60.0:
			press_tick = i
		if press_tick >= 0 and i - press_tick < hold_ticks:
			buttons = 1                      # BTN_JUMP
		ctl.step(DT, Util.mk_in(0, 0, buttons), w)
		rt.step(DT)
		if release_tick < 0 and str(row["anim_state"]) == "attack":
			release_tick = i
		if ctl.dead:
			return false
		if release_tick >= 0 and (row["rings"] as Array).is_empty():
			break
	return not ctl.dead


func _jump_window_clears_the_ring(f: Array[String]) -> void:
	var d := YouEnemy.TRIGGER_DISTANCE
	var win := YouEnemy.RING_RADIAL_WINDOW
	var spd := YouEnemy.RING_SPEED
	var t_hit_lo := maxf(d - win, 0.0) / spd
	var t_hit_hi := minf(d + win, YouEnemy.RING_MAX) / spd
	# the shared kit's airborne window above the band top (v0 12, g 32, h 1.0 u)
	var C: Dictionary = Util.consts()
	var v0 := float(C["jump_velocity"])
	var g := float(C["gravity"])
	var h := YouEnemy.RING_HEIGHT
	var disc := v0 * v0 - 2.0 * g * h
	if disc <= 0.0:
		f.append("jump: the shared kit cannot clear a %.2f u band at all" % h)
		return
	var t_up := (v0 - sqrt(disc)) / g
	var t_down := (v0 + sqrt(disc)) / g
	var press_lo := t_hit_hi - t_down
	var press_hi := t_hit_lo - t_up
	if press_hi <= press_lo:
		f.append("jump: no jump window at all (press %.3f..%.3f s after the release)" % [press_lo, press_hi])
		return
	var press_s := (press_lo + press_hi) * 0.5
	if not _jump_arm(d, press_s):
		f.append("jump: a jump %.3f s after the release did not clear the ring (window %.3f..%.3f s)"
				% [press_s, press_lo, press_hi])
	if _jump_arm(d, -1.0):
		f.append("jump: the grounded player survived the ring - the ring must still kill")
	if _jump_arm(d, 0.0):
		f.append("jump: a jump on the release tick survived - the window is not a window")


# ---- the roster data vs the behavior's mirror (cycle 7) ------------------------

func _roster_data(f: Array[String]) -> void:
	var txt := FileAccess.get_file_as_string("res://content/enemies/you/enemy.json")
	var doc = JSON.parse_string(txt)
	if not (doc is Dictionary):
		f.append("data: enemy.json does not parse")
		return
	var st: Dictionary = (doc as Dictionary).get("stats", {})
	if st.is_empty():
		f.append("data: enemy.json has no stats block")
		return
	# the owner's cycle-7 ask, as thresholds: "you?!" smaller range + slower strike
	var radius := float(st.get("ring_max_radius", 0.0))
	if radius > 8.4 + 1e-9:
		f.append("data: ring_max_radius %.2f, want <= 8.4 (60%% of the old 14 u)" % radius)
	var rumble := int(st.get("rumble_ticks", 0))
	if rumble < 180:
		f.append("data: rumble_ticks %d, want >= 180 (2x the old 90)" % rumble)
	var trig := float(st.get("trigger_distance", 0.0))
	if trig > radius + 1e-9:
		f.append("data: trigger_distance %.2f is outside the ring's own reach %.2f" % [trig, radius])
	# the mirror in the behavior agrees with the json (kiwi/claude cfg-mirror convention)
	var mirror: Dictionary = YouEnemy.cfg()
	for k in mirror.keys():
		if not st.has(k):
			f.append("mirror: enemy.json stats has no '%s' (the behavior mirrors it)" % str(k))
			continue
		if not _vals_agree(st[k], mirror[k]):
			f.append("mirror: stats.%s = %s, behavior cfg says %s" % [str(k), str(st[k]), str(mirror[k])])
	# the audio timing mirrors the tell: the binding cue ends on the release tick
	var cue: Dictionary = (st.get("audio_cue_timing", {}) as Dictionary).get("you_corrupted_rumble", {})
	if int(cue.get("attack_offset_ticks", -1)) != rumble:
		f.append("data: cue attack_offset_ticks %s, want the tell's %d"
				% [str(cue.get("attack_offset_ticks")), rumble])
	if int(cue.get("binding_cue_ticks", -1)) != rumble:
		f.append("data: cue binding_cue_ticks %s, want the tell's %d"
				% [str(cue.get("binding_cue_ticks")), rumble])
	var atk: Dictionary = ((st.get("lethal_attacks", []) as Array)[0] as Dictionary)
	if int(atk.get("attack_offset_ticks", -1)) != rumble:
		f.append("data: ring_kill attack_offset_ticks %s, want the tell's %d"
				% [str(atk.get("attack_offset_ticks")), rumble])


## Numeric-tolerant value agreement: scalars compare as numbers, strings as strings.
func _vals_agree(jv: Variant, cv: Variant) -> bool:
	if jv is String or cv is String:
		return str(jv) == str(cv)
	if (jv is float or jv is int) and (cv is float or cv is int):
		return absf(float(jv) - float(cv)) <= 0.000001
	return str(jv) == str(cv)


# ---- ring cooldown 4.0 s: no re-telegraph before attack+recover elapse ---------

func _cooldown_blocks_retrigger(f: Array[String]) -> void:
	var spawned := _spawn(Vector3(3.0, 0.0, 0.5), "YOU?!", 0.0)
	var rt = spawned[0]
	var row = spawned[1]
	var t_rel := _release_ring_now(spawned)
	if t_rel < 0:
		f.append("cooldown: never released")
		return
	var base: int = _telegraph_events(rt).size()   # the first rumble's event
	var t_tel2 := -1
	for i in range(t_rel + 1, t_rel + 700):
		rt.step(DT)
		if _telegraph_events(rt).size() > base:
			t_tel2 = i
			break
	if t_tel2 < 0:
		f.append("cooldown: a second rumble never came")
		return
	# the earliest legal second rumble is after attack (18) + recover (240)
	if t_tel2 < t_rel + 18 + 240 - 1:
		f.append("cooldown: second rumble at %d, before attack 18 + recover 240 elapsed (earliest %d)"
			% [t_tel2, t_rel + 18 + 240])


# ---- body contact kills ---------------------------------------------------------

func _contact_kills(f: Array[String]) -> void:
	# overlapping bodies: one tick is enough
	var spawned := _spawn(Vector3(0.9, 0.0, 0.5))
	var rt = spawned[0]
	var ctl = spawned[2]
	rt.step(DT)
	if not ctl.dead:
		f.append("contact: body overlap did not kill")
	# the framework derives the code from the row name: "you" -> D-YOU
	var low := _spawn(Vector3(0.9, 0.0, 0.5), "you")
	rt = low[0]
	var ctl2 = low[2]
	rt.step(DT)
	var found := false
	for d in _death_events(rt):
		if str(d["code"]) == "D-YOU":
			found = true
	if not found:
		f.append("contact: death events %s, want D-YOU (row name 'you')" % str(_death_events(rt)))
	# no contact possible from across the void: still alive
	var far := _spawn(Vector3(9.0, 0.0, 0.5))
	rt = far[0]
	rt.step(DT)
	if far[2].dead:
		f.append("contact: a distant body killed the player")


# ---- row hooks T-051's Echo Ring can read --------------------------------------

func _echo_ring_row_hooks(f: Array[String]) -> void:
	var spawned := _spawn(Vector3(4.0, 0.0, 0.5), "YOU?!", 0.0)
	var row = spawned[1]
	var t_rel := _release_ring_now(spawned)
	if t_rel < 0:
		f.append("echo: never released")
		return
	if int(row["ring_seq"]) != 1:
		f.append("echo: ring_seq %d, want 1" % int(row["ring_seq"]))
	if int(row["last_ring_tick"]) < 0:
		f.append("echo: last_ring_tick never set")


# ---- the anim block wiring (the view reads sprites.json's section 1.6 block) ----

func _anim_block_wiring(f: Array[String]) -> void:
	var v = YouViewScript.new()
	v.setup("res://content/enemies/you/sprites.json", "res://content/enemies/you")
	for state_id in ["spawn", "idle_chase", "telegraph", "attack", "recover"]:
		if not (v.anim_state_ids() as Array).has(state_id):
			f.append("view: anim block is missing state '%s'" % state_id)
	if v.billboard == null:
		f.append("view: billboard was not built")
		v.free()
		return
	v.position = Vector3(5.0, 0.0, 0.5)
	var cycle = v.billboard.anims.get("cycle", null)
	if cycle == null:
		f.append("view: no cycle animation loaded from sprites.json")
	else:
		for tex in cycle["frames"]:
			if tex == null:
				f.append("view: a cycle frame texture failed to load")
	# telegraph state drives 16 fps + the feet ring + the split ramp
	var row := {"anim_state": "telegraph", "anim_state_t": 45, "rings": [],
			"x": 5.0, "y": 0.0, "z": 0.5, "ticks": 45}
	v.sync(row, DT)
	if v.feet_ring == null or not v.feet_ring.visible:
		f.append("view: feet_ring hidden during the rumble")
	if cycle != null and absf(float(cycle["fps"]) - 16.0) > 0.001:
		f.append("view: telegraph fps %.2f, want 16 (the anim block rate)" % float(cycle["fps"]))
	if v._split_mat != null:
		var split := float(v._split_mat.get_shader_parameter("split_px"))
		if split <= 0.0:
			f.append("view: rgb split is not growing during the rumble")
	# attack state: you_04 held + the band at the ring's radius
	var row2 := {"anim_state": "attack", "anim_state_t": 5, "ticks": 100,
			"rings": [{"x": 5.0, "y": 0.0, "z": 0.5, "r": 2.0}],
			"x": 5.0, "y": 0.0, "z": 0.5}
	v.sync(row2, DT)
	if v.band == null or not v.band.visible:
		f.append("view: shockwave band hidden during the release")
	else:
		if absf(float(v.band.scale.x) - 2.0) > 0.001:
			f.append("view: band scale %.3f, want 2.0 (the ring radius)" % float(v.band.scale.x))
		if absf(band_top(v.band) - 1.0) > 0.001:
			f.append("view: band is not 1.0 u tall")
	if cycle != null and absf(float(cycle["fps"]) - 8.0) > 0.001:
		f.append("view: chase/recover fps %.2f, want 8 (the anim block rate)" % float(cycle["fps"]))
	v.free()


static func band_top(band) -> float:
	# unit open cylinder, y in [0, 1], scaled by node y (identity here)
	for i in range(band.mesh.get_surface_count()):
		var arrays: Array = band.mesh.surface_get_arrays(i)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var top := 0.0
		for vt in verts:
			top = maxf(top, float(vt.y) * float(band.scale.y))
		return top
	return -1.0


# ---- the lobby exhibit path (antechamber's _exhibit_enemy, headless) ----------

func _lobby_exhibit(f: Array[String]) -> void:
	var api: RefCounted = ContentApiScript.load()
	if not api.call("is_ok"):
		f.append("lobby: content boot failed: %s" % " / ".join(api.call("boot_errors")))
		return
	if not (api.call("enemy_ids") as Array).has("you"):
		f.append("lobby: 'you' is not registered as an enemy")
		return
	# the E-bay draw path: offered at level 3 (its min_level), absent at level 2
	var gate: Dictionary = OffersScript.enemy_gate(api)
	var l3: Array = OffersScript.enemy_candidates(api, 3, "general", {}, gate)
	var l2: Array = OffersScript.enemy_candidates(api, 2, "general", {}, gate)
	if not l3.has("you"):
		f.append("lobby: 'you' is not a candidate enemy at level 3")
	if l2.has("you"):
		f.append("lobby: 'you' offered below its min_level (2)")
	var doc: Dictionary = api.call("enemy", "you")
	if str(doc.get("name", "")) != "YOU?!":
		f.append("lobby: name %s, want YOU?!" % str(doc.get("name", "")))
	if int(doc.get("min_level", 0)) != 3:
		f.append("lobby: min_level %d, want 3" % int(doc.get("min_level", 0)))
	if int(doc.get("max_votes", 0)) != 2:
		f.append("lobby: max_votes %d, want 2" % int(doc.get("max_votes", 0)))
	# the antechamber's exact path: parse sprites.json, build the billboard,
	# scale the body to ENEMY_BODY_H (1.6 u)
	var f2 := FileAccess.open("res://content/enemies/you/sprites.json", FileAccess.READ)
	var parsed = JSON.parse_string(f2.get_as_text())
	f2.close()
	if not (parsed is Dictionary):
		f.append("lobby: sprites.json does not parse")
		return
	var bb = BillboardScript.new()
	bb.setup_from_sheet(parsed, "res://content/enemies/you")
	var doc_h: float = float(parsed.get("world_height", 1.0))
	bb.scale = bb.scale * (1.6 / maxf(doc_h, 0.01))
	bb.world_height = 1.6
	if bb.texture == null:
		f.append("lobby: the exhibit billboard has no texture (frames missing)")
	var anims: Dictionary = bb.anims
	if not anims.has("cycle"):
		f.append("lobby: the exhibit billboard has no animation")
	else:
		for tex in anims["cycle"]["frames"]:
			if tex == null:
				f.append("lobby: an exhibit frame texture failed to load")
	bb.free()
