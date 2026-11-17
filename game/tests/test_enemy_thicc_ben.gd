extends RefCounted
#
# thicc ben (ticket T-032; DESIGN.md section 5.3, ENEMIES.md "Bell"). Every number of the
# section 5.3 paragraph is asserted within +/-1 tick (binding):
#
#   - teleport every 13.35 s (801 ticks); telegraph = black smoke at the destination
#     for 1.25 s (75 ticks); Westminster chime during the final 0.5 s (30 ticks);
#     destination locked at smoke start = player position + velocity x 0.5 s;
#     >= 4.0 u from the locked point at arrival = lock broken (ben appears at the
#     locked point regardless);
#   - touch: blur 3.0 s (180 ticks), launch upward 18 u/s (apex ~5 u), bell rings;
#     ben NEVER kills (KILL RULE - his touch is a listed non-killing effect) and
#     he has NO death code;
#   - on top of that: the ring cleanses glitched tiles within 8 u (DESIGN.md 5.8),
#     a launch into the void is reported as D-VOID by the controller's own fall path
#     (asserted via the void-fall code map, not re-implemented here).
#
# KILL TESTS RUN WITH LAST LIGHT ALREADY SPENT (D-057). ben never kills at all, so the
# assertions are inverted on purpose: any death event from a ben touch fails the test.

const EnemyRuntime := preload("res://sim/enemy_runtime.gd")
const BehaviorScript := preload("res://content/enemies/thicc_ben/enemy.gd")
const DeathScript := preload("res://sim/death.gd")
const ScreenBlurScript := preload("res://view/hud/screen_blur.gd")
const AntechamberScript := preload("res://view/lobby/antechamber.gd")
const ContentApiScript := preload("res://core/content_api.gd")
const IntermissionScript := preload("res://sim/intermission.gd")
const BillboardScript := preload("res://view/billboard.gd")
const ViewScript := preload("res://view/thicc_ben_view.gd")
const AudioScript := preload("res://view/audio/thicc_ben_audio.gd")
const Util := preload("res://tests/sim_testutil.gd")

const DT := 1.0 / 60.0
const TOL := 1


func run() -> Array[String]:
	var f: Array[String] = []
	_roster_and_scene_data(f)
	_spawn_fallback_c(f)
	_cadence_and_telegraph(f)
	_lock_prediction_and_break(f)
	_touch_never_kills(f)
	_touch_effects(f)
	_ring_cleanse(f)
	_view_and_audio_hooks(f)
	_lobby_exhibit(f)
	return f


# ---- fixtures -----------------------------------------------------------------

# A two-row walkable line (z = 0 and z = 5) linked by a bridge column at x = 0 -
# the same synthetic level shape the spawn-rule tests use.
func _level() -> Dictionary:
	var tiles: Array = []
	for x in range(0, 100):
		tiles.append([x, 0, 0, 0, 0])
		tiles.append([x, 5, 0, 0, 1])
	tiles.append([0, 1, 0, 0, 2])
	tiles.append([0, 2, 0, 0, 2])
	tiles.append([0, 3, 0, 0, 2])
	tiles.append([0, 4, 0, 0, 2])
	return {"beacon": [0, 0, 0], "spawns": [[0, 0, 0]], "anchors": [
			[2, 45, 5, 0, 1],   # a lane anchor: DESIGN.md says ben's initial position is (c) anyway
		],
			"tiles": tiles, "props": [], "pads": []}


func _arena() -> Dictionary:
	var tiles: Array = []
	for x in range(-5, 6):
		for z in range(-5, 6):
			tiles.append([x, z, 0])
	var w := Util.world_from_tiles(tiles)
	w["dais"] = [0, 0, 0]
	return w


# Last Light ALREADY SPENT (D-057): spend it for real, then clear the arrival
# state - the fixture is exactly "alive, unshielded, Last Light spent".
func _spent_ctl(w: Dictionary, f: Array[String]) -> RefCounted:
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	ctl.place(w)
	if not ctl.try_kill("D-TEST", "test", w, []):
		f.append("ben: spending Last Light failed")
	ctl.invuln = 0.0
	ctl.dead = false
	ctl.place(w)
	return ctl


# cfg = the REAL enemy.json from disk, plus the sprite-derived runtime keys.
# This is the contract the engine loader feeds the runtime (T-073 pattern).
func _cfg_from_disk() -> Dictionary:
	var out := {}
	var f := FileAccess.open("res://content/enemies/thicc_ben/enemy.json", FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Dictionary:
			out = parsed
	var sheet_file := FileAccess.open("res://content/enemies/thicc_ben/sprites.json", FileAccess.READ)
	if sheet_file != null:
		var sheet: Variant = JSON.parse_string(sheet_file.get_as_text())
		sheet_file.close()
		if sheet is Dictionary:
			out["world_height"] = float((sheet as Dictionary).get("world_height", 4.0))
			var anims: Variant = (sheet as Dictionary).get("animations", [])
			if anims is Array and not (anims as Array).is_empty():
				var a: Dictionary = (anims as Array)[0]
				out["frame_w"] = 256
				out["frame_h"] = 256
				out["body_rect"] = (a.get("body_rect", [[0, 0, 256, 256]]) as Array)[0]
	return out


func _spawn(w: Dictionary, ctl, pos: Vector3, f: Array[String], opts: Dictionary = {}) -> Array:
	var rt = EnemyRuntime.new()
	rt.setup({}, w, [ctl], 4242, opts)
	var cfg := _cfg_from_disk()
	cfg["preferred_kind"] = "none"
	cfg["contact_kill"] = false
	var row: Dictionary = rt.spawn_at("thicc_ben", "thicc ben", BehaviorScript.new_behavior(), cfg, pos)
	if row.is_empty():
		f.append("ben: spawn_at returned no row")
	return [rt, row]


func _ben_ticks(rt, w: Dictionary, ctl, n: int) -> Array:
	var ev_all: Array = []
	for i in range(n):
		for e in rt.step(DT):
			ev_all.append(e)
	return ev_all


# ---- 1. roster data + schema + death-code absence ----------------------------

func _roster_and_scene_data(f: Array[String]) -> void:
	var path := "res://content/enemies/thicc_ben/enemy.json"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		f.append("ben: enemy.json is missing")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		f.append("ben: enemy.json does not parse")
		return
	var d: Dictionary = parsed
	if str(d.get("id", "")) != "thicc_ben" or str(d.get("name", "")) != "thicc ben":
		f.append("ben: id/name wrong: %s / %s" % [str(d.get("id")), str(d.get("name"))])
	if int(d.get("min_level", -1)) != 1:
		f.append("ben: first-shown level %s, want 1" % str(d.get("min_level")))
	if int(d.get("max_votes", -1)) != 2:
		f.append("ben: max_votes %s, want 2" % str(d.get("max_votes")))
	if str(d.get("vote_effect", "")) != "+1 ben":
		f.append("ben: vote_effect %s, want '+1 ben'" % str(d.get("vote_effect")))
	if not (d.get("anchor_kinds", null) is Array) or not (d["anchor_kinds"] as Array).is_empty():
		f.append("ben: anchor_kinds %s, want [] (teleports; initial position fallback (c))" % str(d.get("anchor_kinds")))
	if bool(d.get("contact_kill", true)):
		f.append("ben: contact_kill must be false - ben never kills")
	if str(d.get("preferred_kind", "")) != "none":
		f.append("ben: preferred_kind %s, want 'none' (fallback (c) initial position)" % str(d.get("preferred_kind")))
	var stats: Dictionary = d.get("stats", {})
	var expect: Dictionary = {"world_height": 4.0, "hit_diameter": 1.2, "pursuit_ceiling": 0.0,
		"burst_ceiling": 0.0, "teleport_interval_s": 13.35, "teleport_interval_ticks": 801,
		"telegraph_ticks": 75, "chime_tail_ticks": 30, "lock_lead_s": 0.5,
		"lock_break_dist": 4.0, "blur_ticks": 180, "blur_tail_ticks": 60,
		"eject_speed": 18.0, "ring_ticks": 18, "cleanse_radius": 8.0, "touch_cooldown_ticks": 30}
	for k in expect.keys():
		if absf(float(stats.get(k, -999.0)) - float(expect[k])) > 1e-6:
			f.append("ben: stats.%s = %s, want %s" % [k, str(stats.get(k)), str(expect[k])])
	# the registry boots and the entry validates against the schema
	var reg := preload("res://core/registry.gd")
	var res: Dictionary = reg.load_all()
	if not bool(res.get("ok", false)):
		f.append("ben: registry refuses boot: %s" % str(res.get("errors", []).slice(0, 2)))
	elif not (res.get("enemies", {}) as Dictionary).has("thicc_ben"):
		f.append("ben: thicc_ben missing from the registry after boot")
	# DESIGN.md 3.1: thicc ben has NO death code
	if (DeathScript.CODES as Dictionary).keys().any(func(c: String) -> bool: return "BEN" in c or "THICC" in c):
		f.append("ben: a death code named after ben exists - he cannot kill")
	# the chain-break reason is the data whitelist string
	var eco := FileAccess.open("res://data/economy.json", FileAccess.READ)
	var eco_text := eco.get_as_text()
	eco.close()
	if not eco_text.contains("thicc_ben_eject"):
		f.append("ben: economy.json break_events does not carry thicc_ben_eject")


# ---- 2. spawn rule: initial position is fallback (c) ---------------------------

func _spawn_fallback_c(f: Array[String]) -> void:
	var lv := _level()
	var tiles: Array = lv["tiles"]
	var file_tiles: Array = []
	for t in tiles:
		file_tiles.append([int(t[0]), int(t[1]), int(t[2]), int(t[3]), int(t[4])])
	var w := Util.world_from_tiles(file_tiles)
	w["dais"] = [0, 0, 0]
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	ctl.place(w)
	var rt = EnemyRuntime.new()
	rt.setup(lv, w, [ctl], 7, {"spawn_delay_ticks": 120})
	var cfg := _cfg_from_disk()
	cfg["preferred_kind"] = "none"
	cfg["contact_kill"] = false
	rt.plan("thicc_ben", "thicc ben", BehaviorScript.new_behavior(), cfg, 1)
	var spawns: Array = []
	for i in range(121):
		for e in rt.step(DT):
			if e.get("e", "") == "enemy_spawn":
				spawns.append(e)
	if spawns.size() != 1:
		f.append("ben: %d spawn events, want 1" % spawns.size())
		return
	# fallback (c) = the farthest round-trip tile (99.5, 5.5) - NOT the lane anchor
	if absf(float(spawns[0]["x"]) - 99.5) > TOL * 0.1 or absf(float(spawns[0]["z"]) - 5.5) > TOL * 0.1:
		f.append("ben: spawned at (%s, %s), want the farthest round-trip tile (99.5, 5.5) - not the lane (45.5, 5.5)"
				% [str(spawns[0]["x"]), str(spawns[0]["z"])])


# ---- 3. cycle cadence: telegraph tick, arrival tick ---------------------------

func _cadence_and_telegraph(f: Array[String]) -> void:
	var w := _arena()
	var ctl = _spent_ctl(w, f)
	ctl.x = 10.5
	ctl.y = 0.0
	ctl.z = 0.5
	ctl.vx = 0.0
	ctl.vy = 0.0
	ctl.vz = 0.0
	var pair: Array = _spawn(w, ctl, Vector3(80.5, 0.0, 0.5), f)
	var rt = pair[0]
	var row: Dictionary = pair[1]
	var spawn_tick := int(row["spawn_tick"])
	var tele: Dictionary = {}
	var tele_seen := false
	var arrival_tick := -1
	for i in range(850):
		var ev: Array = rt.step(DT)
		for e in ev:
			if e.get("e", "") == "telegraph" and e.get("kind", "") == "teleport" and not tele_seen:
				tele_seen = true
				tele = e
			if tele_seen and arrival_tick < 0 and str(row["phase"]) == "idle" \
					and absf(float(row["x"]) - float(tele["shape"]["cx"])) < 1e-6:
				arrival_tick = int(rt.tick) - 1
		if arrival_tick >= 0:
			break
	if tele.is_empty():
		f.append("ben: no telegraph event in 850 ticks")
		return
	if absi(int(tele["tick"]) - (spawn_tick + 725)) > TOL:
		f.append("ben: telegraph at tick %d, want %d +/- %d" % [int(tele["tick"]), spawn_tick + 725, TOL])
	if int(tele.get("ticks", -1)) != 75:
		f.append("ben: telegraph ticks %s, want 75 (1.25 s, binding)" % str(tele.get("ticks")))
	var shape: Dictionary = tele.get("shape", {})
	if str(shape.get("shape", "")) != "circle" or absf(float(shape.get("r", -1.0)) - 1.2) > 1e-6:
		f.append("ben: telegraph shape %s, want circle r 1.2 (the smoke column)" % str(shape))
	# locked destination = player position + velocity x 0.5 s (velocity is 0 here)
	if absf(float(shape.get("cx", -1.0)) - 10.5) > 1e-6 or absf(float(shape.get("cz", -1.0)) - 0.5) > 1e-6:
		f.append("ben: locked destination (%s, %s), want the player's position (10.5, 0.5)" % [str(shape.get("cx")), str(shape.get("cz"))])
	if arrival_tick < 0:
		f.append("ben: no arrival detected (ben never reached the locked point)")
	elif absi(arrival_tick - (spawn_tick + 800)) > TOL:
		f.append("ben: arrival at tick %d, want %d +/- %d" % [arrival_tick, spawn_tick + 800, TOL])
	if absf(float(row["x"]) - 10.5) > 1e-6 or absf(float(row["z"]) - 0.5) > 1e-6:
		f.append("ben: after arrival at (%s, %s), want (10.5, 0.5)" % [str(row["x"]), str(row["z"])])
	# ben has no body contact kill: the KILL RULE opt-out is honoured by the framework
	if bool(row.get("contact_kill", true)):
		f.append("ben: contact_kill true on the row - the framework would kill on touch")
	# the cadence restarts: the next telegraph lands 801 ticks after the first
	var ev2 := _ben_ticks(rt, w, ctl, 830)
	var tele2: Dictionary = {}
	for e in ev2:
		if e.get("e", "") == "telegraph" and e.get("kind", "") == "teleport":
			tele2 = e
			break
	if tele2.is_empty():
		f.append("ben: no second telegraph within 830 ticks of the arrival")
	elif absi(int(tele2["tick"]) - (int(tele["tick"]) + 801)) > TOL:
		f.append("ben: second telegraph at %d, want %d (801-tick cycle)" % [int(tele2["tick"]), int(tele["tick"]) + 801])


# ---- 4. the lock: prediction + the 4 u break ---------------------------------

func _lock_prediction_and_break(f: Array[String]) -> void:
	# prediction: the destination is player position + velocity x 0.5 s at smoke start
	var w := _arena()
	var ctl = _spent_ctl(w, f)
	ctl.x = 40.5
	ctl.y = 0.0
	ctl.z = 0.5
	ctl.vx = 9.0   # full run speed; nothing decays it (the controller is not stepped here)
	ctl.vz = 0.0
	var pair: Array = _spawn(w, ctl, Vector3(80.5, 0.0, 0.5), f)
	var rt = pair[0]
	var row: Dictionary = pair[1]
	for e in _ben_ticks(rt, w, ctl, 810):
		if e.get("e", "") == "telegraph":
			var shape: Dictionary = e.get("shape", {})
			# lock = (40.5 + 9.0 * 0.5, y, 0.5) = (45.0, 0, 0.5)
			if absf(float(shape.get("cx", -1.0)) - 45.0) > 1e-6:
				f.append("ben: lock at x %s, want 45.0 (position + velocity x 0.5 s)" % str(shape.get("cx")))
			if absi(int(e["tick"]) - 725) > TOL:
				f.append("ben: telegraph at tick %d, want 725 +/- %d" % [int(e["tick"]), TOL])
	# arrival: position is the LOCKED point, never re-aimed; the player (frozen at
	# 40.5, never stepped) sits 4.5 u from the locked 45.0 -> lock broken by the
	# 4.0 u rule (DESIGN.md 5.3, D-T-032-11)
	if absf(float(row["x"]) - 45.0) > 1e-6:
		f.append("ben: after arrival at x %s, want the locked 45.0" % str(row["x"]))
	if not bool(row.get("lock_broken", false)):
		f.append("ben: lock not reported broken with the player 4.5 u from the locked point")
	# the rarest case: lock NOT broken - a standing player, locked at his own position
	var w0 := _arena()
	var ctl0 = _spent_ctl(w0, f)
	ctl0.x = 40.5
	ctl0.y = 0.0
	ctl0.z = 0.5
	ctl0.vx = 0.0
	ctl0.vz = 0.0
	var pair0: Array = _spawn(w0, ctl0, Vector3(80.5, 0.0, 0.5), f)
	var rt0 = pair0[0]
	var row0: Dictionary = pair0[1]
	for e in _ben_ticks(rt0, w0, ctl0, 810):
		pass
	if absf(float(row0["x"]) - 40.5) > 1e-6 or absf(float(row0["z"]) - 0.5) > 1e-6:
		f.append("ben: after arrival at (%s, %s), want (40.5, 0.5)" % [str(row0["x"]), str(row0["z"])])
	if bool(row0.get("lock_broken", true)):
		f.append("ben: lock broken with the player standing on the locked point")
	# the break: the player teleports > 4 u away mid-cue; ben still appears at the lock
	var w2 := _arena()
	var ctl2 = _spent_ctl(w2, f)
	ctl2.x = 40.5
	ctl2.y = 0.0
	ctl2.z = 0.5
	ctl2.vx = 0.0
	ctl2.vz = 0.0
	var pair2: Array = _spawn(w2, ctl2, Vector3(80.5, 0.0, 0.5), f)
	var rt2 = pair2[0]
	var row2: Dictionary = pair2[1]
	var saw_tele = false
	for i in range(810):
		var ev: Array = rt2.step(DT)
		for e in ev:
			if e.get("e", "") == "telegraph":
				saw_tele = true
				ctl2.x = 60.0   # break the lock mid-cue: > 4 u away at arrival
				ctl2.z = 30.0
	if not saw_tele:
		f.append("ben: no telegraph event in the break scenario")
		return
	if absf(float(row2["x"]) - 40.5) > 1e-6 or absf(float(row2["z"]) - 0.5) > 1e-6:
		f.append("ben: after arrival at (%s, %s), want the locked (40.5, 0.5) - never re-aimed"
				% [str(row2["x"]), str(row2["z"])])
	if not bool(row2.get("lock_broken", false)):
		f.append("ben: lock not reported broken with the player > 4 u away at arrival")


# ---- 5. touch: ben NEVER kills (Last Light already spent, D-057) ---------------

func _touch_never_kills(f: Array[String]) -> void:
	var w := _arena()
	var ctl = _spent_ctl(w, f)
	ctl.x = 0.5
	ctl.y = 0.0
	ctl.z = 0.5
	ctl.vx = 0.0
	ctl.vy = 0.0
	ctl.vz = 0.0
	var pair: Array = _spawn(w, ctl, Vector3(0.5, 0.0, 0.5), f)   # ben ON the player
	var rt = pair[0]
	var ev_all := _ben_ticks(rt, w, ctl, 240)
	if ctl.dead:
		f.append("ben: the player DIED to a ben touch - ben can never kill")
	for e in ev_all:
		if e.get("e", "") == "death":
			f.append("ben: a death event fired from a ben touch (code %s)" % str(e.get("code")))
			break
	# a long overlap soak: never a kill, never a suppressed-kill (it is not a kill at all)
	ctl.invuln = 0.0
	ctl.dead = false
	for i in range(300):
		rt.step(DT)
		if ctl.dead:
			f.append("ben: the player died on tick %d of the overlap soak" % (240 + i))
			break
	# the void owns the only fatal read of a ben launch: D-VOID is the controller's own code
	if (DeathScript.CODES as Dictionary).has("D-THICC_BEN") or (DeathScript.CODES as Dictionary).has("D-BEN"):
		f.append("ben: a ben death code exists in death.gd - he cannot kill")


# ---- 6. touch effects: launch, blur, bell, chain_reset -------------------------

func _touch_effects(f: Array[String]) -> void:
	var w := _arena()
	var ctl = _spent_ctl(w, f)
	ctl.x = 0.5
	ctl.y = 0.0
	ctl.z = 0.5
	ctl.vx = 0.0
	ctl.vy = 0.0
	ctl.vz = 0.0
	var pair: Array = _spawn(w, ctl, Vector3(0.5, 0.0, 0.5), f)
	var rt = pair[0]
	var row: Dictionary = pair[1]
	# spawn fade: no touch in the first 30 ticks (anim block spawn, common fade)
	var ev0 := _ben_ticks(rt, w, ctl, 29)
	if ctl.vy != 0.0 or int(row["blur_ticks_left"]) > 0:
		f.append("ben: the touch fired during the 30-tick spawn fade")
	# tick 30+: the launch lands, vy is exactly 18.0, the player leaves the ground
	var ev1 := _ben_ticks(rt, w, ctl, 1)
	if absf(ctl.vy - 18.0) > 1e-6:
		f.append("ben: vy after touch = %s, want 18.0 (the eject, binding)" % str(ctl.vy))
	if ctl.grounded:
		f.append("ben: the player stayed grounded after the eject")
	var saw_reset := false
	var saw_blur := false
	for e in ev1:
		if e.get("e", "") == "chain_reset" and str(e.get("why", "")) == "thicc_ben_eject":
			saw_reset = true
		if e.get("e", "") == "screen_blur" and int(e.get("ticks", -1)) == 180:
			saw_blur = true
	if not saw_reset:
		f.append("ben: no chain_reset thicc_ben_eject event on the touch")
	if not saw_blur:
		f.append("ben: no screen_blur 180-tick event on the touch")
	if int(row["blur_ticks_left"]) != 180:
		f.append("ben: blur_ticks_left = %d, want 180" % int(row["blur_ticks_left"]))
	if int(row["ring_ticks_left"]) != 18:
		f.append("ben: ring_ticks_left = %d, want 18" % int(row["ring_ticks_left"]))
	if int(row["touch_cooldown"]) != 30:
		f.append("ben: touch cooldown = %d, want 30 (D-T-032-1)" % int(row["touch_cooldown"]))
	# the 30-tick cooldown rate-limits the re-eject (no 60 Hz spam)
	ctl.vy = 0.0
	_ben_ticks(rt, w, ctl, 5)
	if ctl.vy != 0.0:
		f.append("ben: the touch re-fired inside its 30-tick cooldown")
	# apex ~5 u: 18 u/s under the controller's 32 u/s^2 gravity -> 5.0625 u
	var ctl2 = Util.ControllerScript.new()
	ctl2.setup("dasher", Util.consts())
	ctl2.place(w)
	ctl2.vy = 18.0
	ctl2.grounded = false
	var y0 := float(ctl2.y)
	var apex := y0
	for i in range(80):
		ctl2.step(DT, Util.mk_in(), w)
		apex = maxf(apex, float(ctl2.y))
	if absf((apex - y0) - 5.0625) > 0.15:
		f.append("ben: eject apex %.3f u, want ~5.06 u (18 u/s, gravity 32)" % (apex - y0))
	# blur strength curve (view-side, binding from the T-083 anim block)
	if absf(ScreenBlurScript.strength_for(0.0) - 1.0) > 1e-9:
		f.append("blur: strength at tick 0 != 1.0")
	if absf(ScreenBlurScript.strength_for(120.0) - 1.0) > 1e-9:
		f.append("blur: strength at tick 120 != 1.0 (fade starts after 120)")
	if absf(ScreenBlurScript.strength_for(150.0) - 0.5) > 1e-9:
		f.append("blur: strength at tick 150 = %.3f, want 0.5 (linear over the last 60)" % ScreenBlurScript.strength_for(150.0))
	if absf(ScreenBlurScript.strength_for(180.0)) > 1e-9:
		f.append("blur: strength at tick 180 != 0.0")


# ---- 7. the ring cleanses glitched tiles within 8 u (inclusive) ----------------

func _ring_cleanse(f: Array[String]) -> void:
	var w := _arena()
	var ctl = _spent_ctl(w, f)
	ctl.x = 0.5
	ctl.y = 0.0
	ctl.z = 0.5
	# ben at the origin: distance from ben's (0.5, 0.5) XZ to tile centres
	w["glitched"] = {
		"0,0,0": true,     # dist 0.0            -> cleansed
		"6,5,0": true,     # dist sqrt(36+25)=7.81 -> cleansed
		"8,0,0": true,     # dist exactly 8.0     -> cleansed (inclusive)
		"1,8,0": true,     # dist sqrt(1+64)=8.06 -> kept
		"12,0,0": true,    # dist 12.0            -> kept
	}
	var pair: Array = _spawn(w, ctl, Vector3(0.5, 0.0, 0.5), f)
	var rt = pair[0]
	_ben_ticks(rt, w, ctl, 31)   # spawn fade 30 ticks; the touch lands on tick 31
	var g: Dictionary = (rt.world as Dictionary).get("glitched", {})
	if g.has("0,0,0") or g.has("6,5,0") or g.has("8,0,0"):
		f.append("ben: the 8 u ring left glitched tiles in range (remaining: %s)" % str(g.keys()))
	if not g.has("1,8,0") or not g.has("12,0,0"):
		f.append("ben: the ring cleansed glitched tiles at > 8 u (remaining: %s)" % str(g.keys()))


# ---- 8. view wiring + placeholder audio hooks ----------------------------------

func _view_and_audio_hooks(f: Array[String]) -> void:
	var v = ViewScript.new()
	var ok: bool = v.setup()
	if not ok:
		f.append("ben view: the sheet/anim block failed to load")
	if v.billboard == null:
		f.append("ben view: no billboard was built")
	# the anim block wiring: the smoke toggles from the sim's telegraph event
	var shape := {"shape": "circle", "cx": 60.0, "cz": 0.5, "r": 1.2}
	v.on_events([{"e": "telegraph", "kind": "teleport", "source": "thicc_ben", "shape": shape, "ticks": 75, "tick": 60}])
	if not v._smoke_on:
		f.append("ben view: the smoke did not start on the teleport cue")
	v.advance(75)
	if v._smoke_on:
		f.append("ben view: the smoke is still emitting after the 75-tick cue")
	# the audio hooks: names per the ENEMIES.md "New sound" line; streams are non-empty
	if AudioScript.cue_names() != ["teleport_chime", "touch_bell"]:
		f.append("ben audio: cue names %s, want [teleport_chime, touch_bell]" % str(AudioScript.cue_names()))
	if AudioScript.file_name_for("teleport_chime") != "thicc_ben_chime":
		f.append("ben audio: teleport_chime file name %s, want thicc_ben_chime" % AudioScript.file_name_for("teleport_chime"))
	if AudioScript.file_name_for("touch_bell") != "thicc_ben_bell":
		f.append("ben audio: touch_bell file name %s, want thicc_ben_bell" % AudioScript.file_name_for("touch_bell"))
	var chime: AudioStreamWAV = AudioScript.stream_for("teleport_chime")
	var bell: AudioStreamWAV = AudioScript.stream_for("touch_bell")
	if chime == null or chime.data.size() == 0:
		f.append("ben audio: the teleport_chime placeholder stream is empty")
	if bell == null or bell.data.size() == 0:
		f.append("ben audio: the touch_bell placeholder stream is empty")

# ---- 9. the lobby exhibit shows it ----------------------------------------------------

func _lobby_exhibit(f: Array[String]) -> void:
	var api = ContentApiScript.load()
	if not bool(api.is_ok()):
		f.append("ben exhibit: content api boot failed: %s" % " / ".join(api.boot_errors()))
		return
	var hall = AntechamberScript.new()
	var lb = IntermissionScript.create(api, 0, 0, 99)
	hall.lobby = lb
	var anchor = Node3D.new()
	var shown: String = hall._exhibit_enemy(anchor, {"id": "thicc_ben", "name": "thicc ben", "votes": 0})
	if shown != "thicc ben":
		f.append("ben exhibit: exhibit shows %s, want 'thicc ben'" % shown)
	if anchor.get_child_count() != 1:
		f.append("ben exhibit: %d children on the anchor, want 1 (the billboard)" % anchor.get_child_count())
	else:
		var child = anchor.get_child(0)
		if not (child is BillboardScript):
			f.append("ben exhibit: the exhibit child is %s, want the billboarded PNG sprite" % child.get_class())
	var doc: Dictionary = hall._enemy_doc("thicc_ben")
	if not str(doc.get("behavior", "")).contains("teleports"):
		f.append("ben exhibit: the lobby panel would show behavior %s" % str(doc.get("behavior", "")))
	if not str(doc.get("counter_play", "")).contains("smoke"):
		f.append("ben exhibit: the lobby panel would show counter_play %s" % str(doc.get("counter_play", "")))
	if not str(doc.get("tell", "")).contains("Westminster"):
		f.append("ben exhibit: the lobby panel would show tell %s" % str(doc.get("tell", "")))
	anchor.free()
	hall.free()
