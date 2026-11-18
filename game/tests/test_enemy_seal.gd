extends RefCounted
#
# T-038 seal - DESIGN.md section 5.9 (every number, +/-1 tick), the contact-kill rule and
# its death code, and the cfg/enemy.json coherence of the section 5 vote/anchor table.
# ENEMIES.md (Behavior 1:1): "small, fast, kills instantly on contact; ~1s high-pitched cry
# before it attacks. VOIDWRAP_RUN: the cry is replaced by a real seal bark when it dashes -
# it opens its mouth and flaps."
#
#   - 4.0 u/s flap (pursuit ceiling 0.60 -> never above 5.4 u/s while flapping after ALL
#     multipliers, SR-5; tested under overtime tier 8 + Rush Hour x3 + Hunger x2);
#   - body 0.6 u tall, hit diameter 0.6 u (SR-2; the cfg hit_diameter pin wins over the
#     TBD-art derivation, D-T030-2);
#   - feet ease toward the target's feet at 2.0 u/s (SR-1, never multiplied);
#   - a telegraph starts ONLY between 4 u and 12 u from the target - closer than 4 u it keeps
#     flapping, farther than 12 u it closes in;
#   - the dash line is fixed at telegraph start: seal body centre -> player centre (0.9 u
#     above the feet), extended to 20 u; no re-aim during the 45-tick telegraph or the
#     60-tick dash (D-069);
#   - telegraph 0.75 s (45 ticks) -> bark on tick 0 of the dash -> dash 20 u in 1.0 s
#     (60 ticks) along the fixed line -> recover 0.75 s (45 ticks);
#   - contact at ANY time = kill, death code D-SEAL (DESIGN.md section 3.1 FINAL) - Last
#     Light spent first or the save masks the kill (D-057);
#   - the jump answer window: feet > 1.2 u above telegraph-start height from 0.12 s to
#     0.63 s after take-off (a 0.51 s window) for its 0.07 s body crossing - jump on the bark;
#   - 3 HU step (1.5 u) also clears; sidestep >= 0.7 u on a 2-wide path/platform;
#   - spawns at lane anchors, min level 3, max 3 votes, seal.idle_flap is two frames
#     (seal_02/03, 9 ticks per frame) and the attack is one frame (seal_01) with the flap as
#     overlay at 4 ticks per frame (T-083, binding).

const EnemyRuntime := preload("res://sim/enemy_runtime.gd")
const Util := preload("res://tests/sim_testutil.gd")
const SealScript := preload("res://content/enemies/seal/enemy.gd")

const DT := 1.0 / 60.0
var SEAL_CFG: Dictionary = SealScript.cfg()


# Two walkable rows (z = 0 and z = 5) bridged at x = 0 - the same shape the T-027/T-071
# tests use, so round-trip reachability (D-056 step c) is known good.
func _level(anchors: Array) -> Dictionary:
	var tiles: Array = []
	for x in range(0, 100):
		tiles.append([x, 0, 0, 0, 0])
		tiles.append([x, 5, 0, 0, 1])
	tiles.append([0, 1, 0, 0, 2])
	tiles.append([0, 2, 0, 0, 2])
	tiles.append([0, 3, 0, 0, 2])
	tiles.append([0, 4, 0, 0, 2])
	return {"beacon": [0, 0, 0], "spawns": [[0, 0, 0]], "anchors": anchors,
			"tiles": tiles, "props": [], "pads": []}


func _world() -> Dictionary:
	return {"cols": {}, "prop_cols": {}, "pads": {}, "dais": [0, 0, 0], "glitched": {},
			"slippery": {}, "removed": {}, "kill_y": -40.0, "enemies": [], "projectiles": [],
			"hazards": []}


# [runtime, controller]; controller sits at (0.5, 0.0, 0.5), Last Light already spent (D-057).
func _runtime(lv: Dictionary) -> Array:
	var w := _world()
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	ctl.place(w)
	ctl.last_light_spent = true
	var rt = EnemyRuntime.new()
	rt.setup(lv, w, [ctl], 7)
	return [rt, ctl]


# Behavior from the shipped content script (the drop-in shape a caller uses).
func _spawn_seal(rt, pos: Vector3) -> Dictionary:
	return rt.spawn_at("seal", "seal", SealScript.SealBehavior.new(),
			SEAL_CFG.duplicate(true), pos)


func _cfg_coherence(f: Array[String]) -> void:
	var text := FileAccess.get_file_as_string("res://content/enemies/seal/enemy.json")
	var doc: Variant = JSON.parse_string(text)
	if not (doc is Dictionary):
		f.append("cfg: enemy.json unreadable")
		return
	var d := doc as Dictionary
	var stats: Dictionary = d.get("stats", {})
	_eq(f, "enemy.json id", str(d.get("id")), "seal")
	_eq(f, "enemy.json name", str(d.get("name")), "seal")
	_eq(f, "min_level", int(d.get("min_level")), 3)
	_eq(f, "max_votes", int(d.get("max_votes")), 3)
	_eq(f, "vote_effect", str(d.get("vote_effect")), "+1 seal")
	_eq(f, "anchor_kinds", str(d.get("anchor_kinds")), str(["lane"]))
	_eq(f, "base_speed", float(stats.get("base_speed")), 4.0)
	_eq(f, "pursuit_ceiling", float(stats.get("pursuit_ceiling")), 0.6)
	_eq(f, "burst_ceiling", float(stats.get("burst_ceiling")), 1.0)
	_eq(f, "body_height", float(stats.get("body_height")), 0.6)
	_eq(f, "hit_diameter", float(stats.get("hit_diameter")), 0.6)
	_eq(f, "telegraph_range_min_u", float(stats.get("telegraph_range_min_u")), 4.0)
	_eq(f, "telegraph_range_max_u", float(stats.get("telegraph_range_max_u")), 12.0)
	_eq(f, "telegraph_ticks", int(stats.get("telegraph_ticks")), 45)
	_eq(f, "dash_ticks", int(stats.get("dash_ticks")), 60)
	_eq(f, "dash_length_u", float(stats.get("dash_length_u")), 20.0)
	_eq(f, "recover_ticks", int(stats.get("recover_ticks")), 45)
	_eq(f, "death_code", str(stats.get("death_code")), "D-SEAL")
	_eq(f, "audio cues", str(stats.get("audio_cues")), str(["bark", "flipper_flap"]))
	_eq(f, "behavior cfg base_speed", float(SEAL_CFG["base_speed"]), 4.0)
	_eq(f, "behavior cfg pursuit_ceiling", float(SEAL_CFG["pursuit_ceiling"]), 0.6)
	_eq(f, "behavior cfg hit_diameter", float(SEAL_CFG["hit_diameter"]), 0.6)
	_eq(f, "behavior cfg death_code", str(SEAL_CFG["death_code"]), "D-SEAL")
	_eq(f, "behavior cfg preferred_kind", str(SEAL_CFG["preferred_kind"]), "lane")
	_eq(f, "behavior cfg telegraph_ticks", int(SEAL_CFG["telegraph_ticks"]), 45)
	_eq(f, "behavior cfg dash_ticks", int(SEAL_CFG["dash_ticks"]), 60)
	# sprites: world height 0.6, the T-083 anim block carries the binding timings
	var stext := FileAccess.get_file_as_string("res://content/enemies/seal/sprites.json")
	var sdoc: Variant = JSON.parse_string(stext)
	if not (sdoc is Dictionary):
		f.append("sprites: sprites.json unreadable")
		return
	var s := sdoc as Dictionary
	_eq(f, "world_height", float(s.get("world_height")), 0.6)
	var anim_states: Dictionary = ((s.get("anim", {})) as Dictionary).get("states", {})
	_eq(f, "spawn total_ticks", int((anim_states.get("spawn", {}) as Dictionary).get("total_ticks", 0)), 30)
	_eq(f, "idle_flap ticks_per_frame",
			float((anim_states.get("idle_flap", {}) as Dictionary).get("ticks_per_frame", 0.0)), 9.0)
	var idle_frames: Array = (anim_states.get("idle_flap", {}) as Dictionary).get("spec_frames", [])
	_eq(f, "idle_flap spec frames", str(idle_frames), str(["seal_02", "seal_03"]))
	_eq(f, "telegraph total_ticks", int((anim_states.get("telegraph", {}) as Dictionary).get("total_ticks", 0)), 45)
	_eq(f, "attack total_ticks", int((anim_states.get("attack", {}) as Dictionary).get("total_ticks", 0)), 60)
	_eq(f, "attack ticks_per_frame", float((anim_states.get("attack", {}) as Dictionary).get("ticks_per_frame", 0.0)), 4.0)
	var attack_frames: Array = (anim_states.get("attack", {}) as Dictionary).get("spec_frames", [])
	_eq(f, "attack spec frames (mouth-open held)", str(attack_frames), str(["seal_01"]))
	_eq(f, "recover total_ticks", int((anim_states.get("recover", {}) as Dictionary).get("total_ticks", 0)), 45)


func _eq(f: Array[String], what: String, got, want) -> void:
	if str(got) != str(want):
		f.append("%s: got %s, want %s" % [what, str(got), str(want)])


func run() -> Array[String]:
	var f: Array[String] = []
	_cfg_coherence(f)
	_body_and_contact_kill(f)
	_dash_contact_kill(f)
	_flap_speed(f)
	_pursuit_ceiling_stack(f)
	_feet_ease(f)
	_telegraph_range_gate(f)
	_telegraph_line_fixed(f)
	_bark_timing_and_dash_distance(f)
	_dash_mirror_settles(f)
	_recover_then_flap(f)
	_spawns_at_6_s_lane(f)
	_jump_answer_window(f)
	_jump_on_the_bark_survives(f)
	_crossing_arithmetic(f)
	return f


# SR-2 (FINAL): 0.6 u tall, 0.6 u hit diameter (the cfg pin, D-T030-2), and the framework
# kills on contact - with the player's feet at the seal's and Last Light already spent.
func _body_and_contact_kill(f: Array[String]) -> void:
	var pair := _runtime(_level([]))
	var rt = pair[0]
	var ctl = pair[1]
	var row := _spawn_seal(rt, Vector3(0.5, 0.0, 0.5))
	_eq(f, "body height", float(row["height_u"]), 0.6)
	_eq(f, "hit diameter", float(row["diameter_u"]), 0.6)
	rt.step(DT)
	if not bool(ctl.dead):
		f.append("contact: the seal's body contact did not kill (Last Light spent)")
		return
	var deaths: Array = []
	for e in rt.events:
		if e.get("e", "") == "death":
			deaths.append(e)
	if deaths.is_empty():
		f.append("contact: no death event after the contact kill")
	else:
		_eq(f, "death code", str(deaths[0].get("code")), "D-SEAL")
		_eq(f, "death killer", str(deaths[0].get("killer")), "seal")


# Contact at ANY time = kill - including mid-dash. Last Light spent (D-057). The seal
# telegraphs at 8 u and dashes THROUGH the player's tile: the crossing tick kills.
func _dash_contact_kill(f: Array[String]) -> void:
	var pair := _runtime(_level([]))
	var rt = pair[0]
	var ctl = pair[1]
	ctl.x = 8.5
	ctl.z = 0.5
	var row := _spawn_seal(rt, Vector3(0.5, 0.0, 0.5))
	var dead_tick := -1
	for i in range(240):
		for e in rt.step(DT):
			if e.get("e", "") == "death":
				dead_tick = i
		if dead_tick >= 0:
			break
	_eq(f, "dash kill happened", "yes" if dead_tick >= 0 else "no", "yes")
	if dead_tick >= 0:
		var deaths: Array = []
		for e in rt.events:
			if e.get("e", "") == "death":
				deaths.append(e)
		if not deaths.is_empty():
			_eq(f, "dash death code", str(deaths[0].get("code")), "D-SEAL")


# 4.0 u/s flat out while flapping, no multipliers running: one tick covers 4.0/60 u.
func _flap_speed(f: Array[String]) -> void:
	var pair := _runtime(_level([]))
	var rt = pair[0]
	var row := _spawn_seal(rt, Vector3(25.5, 0.0, 0.5))
	rt.step(DT)
	var fb = row["float"]
	if absf(fb.h_speed - 4.0) > 1e-9:
		f.append("flap: h_speed %.6f, want 4.0" % fb.h_speed)
	var d25: float = Vector3(float(row["x"]) - 25.5, 0.0, 0.0).length()
	if absf(d25 - 4.0 / 60.0) > 1e-6:
		f.append("flap: covered %.6f u in one tick, want %.6f (4.0/60)" % [d25, 4.0 / 60.0])


# SR-5: the full stack (overtime tier 8 = +48%, Rush Hour x3, Hunger x2) clamps the flap
# to exactly 5.4 u/s - the 0.60 ceiling applies AFTER every multiplier; never above.
func _pursuit_ceiling_stack(f: Array[String]) -> void:
	var pair := _runtime(_level([]))
	var rt = pair[0]
	rt.overtime_running = true
	rt.add_overtime_tier(8)
	rt.curse_speed_mul = 1.08 * 1.08 * 1.08 * 1.05 * 1.05
	var row := _spawn_seal(rt, Vector3(60.5, 0.0, 0.5))
	var fb = row["float"]
	for i in range(180):
		# keep it out of telegraph range so the ceiling is what is measured; park the
		# player 50 u below the seal's approach lane instead of teleporting mid-flight
		rt.step(DT)
		if fb.h_speed > 5.4 + 1e-9:
			f.append("ceiling: tick %d h_speed %.6f exceeds 5.4" % [i, fb.h_speed])
			return
	if absf(fb.h_speed - 5.4) > 1e-9:
		f.append("ceiling: settled at %.6f, want exactly 5.4 under the full stack" % fb.h_speed)


# SR-1: feet ease toward the target's feet at 2.0 u/s, NEVER multiplied (D-068) - not by
# overtime, not by curses. A 4 HU climb closes in ~60 ticks (+/-1).
func _feet_ease(f: Array[String]) -> void:
	for overtime in [false, true]:
		var pair := _runtime(_level([]))
		var rt = pair[0]
		var ctl = pair[1]
		ctl.x = 20.0
		ctl.y = 2.0
		ctl.z = 20.0
		if overtime:
			rt.overtime_running = true
			rt.add_overtime_tier(8)
			rt.curse_speed_mul = 1.48 * 1.08 * 1.08 * 1.08
		var row := _spawn_seal(rt, Vector3(40.0, 0.0, 20.0))   # out of telegraph range for 60 ticks
		var ticks := 0
		while ticks < 600 and float(row["y"]) < 2.0 - 1e-6:
			rt.step(DT)
			ticks += 1
			# the easing cap per tick (2.0/60) is what binds - overtime never multiplies it
			if float(row["y"]) > float(ticks) * (2.0 / 60.0) + 1e-6:
				f.append("climb: tick %d y=%.4f exceeds the 2.0 u/s easing cap (overtime=%s)"
						% [ticks, float(row["y"]), str(overtime)])
				return
		if ticks < 59 or ticks > 61:
			f.append("climb: the 2.0 u climb took %d ticks, want ~60 (+/-1) (overtime=%s)"
					% [ticks, str(overtime)])
			return


# DESIGN.md section 5.9: a telegraph starts ONLY between 4 u and 12 u from the target.
# At 13 u and at 3 u the seal keeps flapping (no dash_line telegraph, phase stays "flap");
# at exactly 4.0 u and exactly 12.0 u it telegraphs at once.
func _telegraph_range_gate(f: Array[String]) -> void:
	for spot in [Vector3(13.5, 0.0, 0.5), Vector3(3.5, 0.0, 0.5)]:
		var pair := _runtime(_level([]))
		var rt = pair[0]
		var row := _spawn_seal(rt, spot)
		for i in range(3):
			rt.step(DT)
		if str(row.get("phase", "")) != "flap":
			f.append("range: seal telegraphed from %.1f u (want flap, telegraph only in 4..12 u)"
					% spot.distance_to(Vector3(0.5, 0.0, 0.5)))
			return
	for spot in [Vector3(4.5, 0.0, 0.5), Vector3(12.5, 0.0, 0.5)]:
		var pair2 := _runtime(_level([]))
		var rt2 = pair2[0]
		var row2 := _spawn_seal(rt2, spot)
		var telegraph_seen := false
		for i in range(3):
			for e in rt2.step(DT):
				if e.get("e", "") == "telegraph" and e.get("kind", "") == "dash_line":
					telegraph_seen = true
		if str(row2.get("phase", "")) != "telegraph" or not telegraph_seen:
			f.append("range: no telegraph from %.1f u (phase=%s), want the wind-up to begin"
					% [spot.distance_to(Vector3(0.5, 0.0, 0.5)), str(row2.get("phase", ""))])
			return


# The dash line is FIXED at telegraph start: from the seal's body centre through the
# player's centre (0.9 u above the feet), extended to 20 u; no re-aim during the telegraph
# or the dash. The player can (and does) move after telegraph start - the line must not.
func _telegraph_line_fixed(f: Array[String]) -> void:
	var pair := _runtime(_level([]))
	var rt = pair[0]
	var ctl = pair[1]
	ctl.x = 8.5
	ctl.z = 0.5
	var row := _spawn_seal(rt, Vector3(0.5, 0.0, 0.5))
	var line := []
	for i in range(10):
		for e in rt.step(DT):
			if e.get("e", "") == "telegraph" and e.get("kind", "") == "dash_line":
				line = (e.get("shape", {}) as Dictionary).get("dash_line", [])
		if not line.is_empty():
			break
	if line.size() != 6:
		f.append("line: dash_line telegraph missing or malformed")
		return
	var start := Vector3(float(line[0]), float(line[1]), float(line[2]))
	var end := Vector3(float(line[3]), float(line[4]), float(line[5]))
	# start = seal body centre at telegraph start - one flap tick's step from spawn
	if absf(start.y - 0.3) > 1e-6 or absf(start.z - 0.5) > 1e-6:
		f.append("line: start %s, want the seal body centre (y 0.3, z 0.5)" % str(start))
		return
	if start.x < 0.5 - 1e-6 or start.x > 0.5 + 4.0 / 60.0 + 1e-6:
		f.append("line: start.x %.4f outside one flap tick of spawn (0.5..0.5667)" % start.x)
		return
	# length = exactly 20 u along the fixed direction
	if absf((end - start).length() - 20.0) > 1e-4:
		f.append("line: length %.4f u, want exactly 20 u" % (end - start).length())
		return
	# passes through the player's centre at telegraph start (0.9 u above the feet)
	var p1 := Vector3(8.5, 0.9, 0.5)
	var to_p := p1 - start
	var along := to_p.dot((end - start).normalized())
	var on := start + (end - start).normalized() * along
	if on.distance_to(p1) > 1e-4:
		f.append("line: the line does not pass through the player's centre (miss by %.4f u)" % on.distance_to(p1))
		return
	# the line (and its origin) are fixed: direction unchanged since telegraph start
	var dx0 := float(row["dash_dx"])
	var dy0 := float(row["dash_dy"])
	var dz0 := float(row["dash_dz"])
	# teleport the player far off the line; the line must NOT bend toward the new position
	ctl.x = 40.0
	ctl.z = 20.0
	for i in range(150):
		rt.step(DT)
	if absf(float(row["dash_dx"]) - dx0) > 1e-9 or absf(float(row["dash_dy"]) - dy0) > 1e-9 \
			or absf(float(row["dash_dz"]) - dz0) > 1e-9:
		f.append("line: the dash line re-aimed after the telegraph started")
		return
	# and the body actually travelled along the OLD line: its end point is near
	# start + dir * 20 u, not near the teleported player
	var line_end := Vector3(float(row["line_x0"]), float(row["line_y0"]), float(row["line_z0"])) \
			+ Vector3(dx0, dy0, dz0) * 20.0
	var centre := Vector3(float(row["x"]), float(row["y"]) + 0.3, float(row["z"]))
	if centre.distance_to(line_end) > 0.75:
		f.append("line: the seal ended at %s, want near the fixed line end %s" % [str(centre), str(line_end)])
		return


# DESIGN.md section 5.9: telegraph 0.75 s (45 ticks, +/-1) -> bark on tick 0 of the dash ->
# dash 20 u in 1.0 s (60 ticks, +/-1) along the fixed line. Measured off the sim events.
func _bark_timing_and_dash_distance(f: Array[String]) -> void:
	var pair := _runtime(_level([]))
	var rt = pair[0]
	var ctl = pair[1]
	ctl.x = 8.5
	ctl.z = 0.5
	var row := _spawn_seal(rt, Vector3(0.5, 0.0, 0.5))
	var telegraph_tick := -1
	var bark_tick := -1
	for i in range(140):
		for e in rt.step(DT):
			if e.get("e", "") == "telegraph":
				if e.get("kind", "") == "dash_line" and telegraph_tick < 0:
					telegraph_tick = int(e.get("tick", -1))
				elif e.get("kind", "") == "bark" and bark_tick < 0:
					bark_tick = int(e.get("tick", -1))
	if telegraph_tick < 0:
		f.append("bark: no dash_line telegraph in 140 ticks")
		return
	if bark_tick < 0:
		f.append("bark: no bark telegraph in 140 ticks")
		return
	# telegraph -> bark: 45 ticks (+/-1), binding (T-083 attack block)
	if absi(bark_tick - telegraph_tick - 45) > 1:
		f.append("bark: fired %d ticks after telegraph start, want 45 (+/-1)" % (bark_tick - telegraph_tick))
		return
	# the dash advance is exactly 1/3 u per tick along the fixed direction; the row stores
	# the FEET (centre - body_height/2), so compare the BODY CENTRE's advance
	var dir := Vector3(float(row["dash_dx"]), float(row["dash_dy"]), float(row["dash_dz"]))
	var start := Vector3(float(row["line_x0"]), float(row["line_y0"]), float(row["line_z0"]))
	var centre := Vector3(float(row["x"]), float(row["y"]) + 0.3, float(row["z"]))
	var advanced := (centre - start).dot(dir)
	if absf(float(row["dash_done_u"]) - advanced) > 1e-6:
		f.append("dash: dash_done_u %.4f does not match the advance along the line %.4f"
				% [float(row["dash_done_u"]), advanced])
		return


# PARKED row 27: the dash is the seal's instant reposition (20 u down the fixed line), so
# the body mirror - the world["enemies"] entry no_enemy_body_within and the D-059 safe tile
# read - must follow it at the settle. Driven through the behavior alone, no rt.step(): the
# runtime's own per-tick refresh would otherwise hide a missing sync in this file.
func _dash_mirror_settles(f: Array[String]) -> void:
	var pair := _runtime(_level([]))
	var rt = pair[0]
	var ctl = pair[1]
	ctl.x = 8.5
	ctl.z = 0.5
	var row := _spawn_seal(rt, Vector3(0.5, 0.0, 0.5))
	var api = EnemyRuntime.Api.new()
	api.rt = rt
	api.row = row
	var beh = row["behavior"]
	var spawned_at := Vector3(float(row["x"]), float(row["y"]), float(row["z"]))
	for i in range(140):
		beh.tick(row, api, 1)
		if str(row.get("phase", "")) == "recover":
			break
	if str(row.get("phase", "")) != "recover":
		f.append("mirror: the dash never settled in 140 ticks")
		return
	var mirror: Dictionary = row.get("body_mirror", {})
	if mirror.is_empty():
		f.append("mirror: the row carries no body mirror (no world[enemies] entry)")
		return
	var at := Vector3(float(mirror["x"]), float(mirror["y"]), float(mirror["z"]))
	var body := Vector3(float(row["x"]), float(row["y"]), float(row["z"]))
	if at.distance_to(body) > 1e-9:
		f.append("mirror: the body mirror sits at %s after the dash, the row is at %s"
				% [str(at), str(body)])
	# and it really moved: the dash carried the body 20 u off the spawn point
	if at.distance_to(spawned_at) < 1.0:
		f.append("mirror: the body mirror never left the spawn point %s (dash end %s)"
				% [str(spawned_at), str(at)])


# DESIGN.md section 5.9: after the dash the seal idles 0.75 s (45 ticks, +/-1), then flaps
# again. Observed via the row phase machine.
func _recover_then_flap(f: Array[String]) -> void:
	var pair := _runtime(_level([]))
	var rt = pair[0]
	var ctl = pair[1]
	ctl.x = 8.5
	ctl.z = 0.5
	var row := _spawn_seal(rt, Vector3(0.5, 0.0, 0.5))
	var bark_tick := -1
	var recover_start := -1
	var flap_again := -1
	for i in range(220):
		for e in rt.step(DT):
			if e.get("e", "") == "telegraph" and e.get("kind", "") == "bark" and bark_tick < 0:
				bark_tick = int(e.get("tick", -1))
		if recover_start < 0 and str(row.get("phase")) == "recover":
			recover_start = i
			# park the player out of the way so the dash's end position never re-telegraphs
			ctl.x = 90.0
			ctl.z = 0.5
		if flap_again < 0 and recover_start >= 0 and str(row.get("phase")) == "flap":
			flap_again = i
	if bark_tick < 0:
		f.append("recover: no bark in 220 ticks")
		return
	if recover_start < 0:
		f.append("recover: never entered the recover phase")
		return
	# bark -> recover start: exactly 60 ticks of dash (+/-1)
	if absi(recover_start - bark_tick - 60) > 1:
		f.append("recover: entered recover %d ticks after the bark, want 60 (+/-1)" % (recover_start - bark_tick))
		return
	if flap_again < 0:
		f.append("recover: never returned to flap in 220 ticks")
		return
	# recover -> flap: exactly 45 ticks of idle (+/-1) with no multipliers running
	if absi(flap_again - recover_start - 45) > 1:
		f.append("recover: %d ticks of recover, want 45 (+/-1)" % (flap_again - recover_start))
		return


# The diegetic spawn text carries the enemy's own name; the plan spawns on tick 360
# (6.0 s, D-056); a lane anchor is preferred (DESIGN.md section 5 anchor table).
func _spawns_at_6_s_lane(f: Array[String]) -> void:
	var pair := _runtime(_level([
		[2, 45, 5, 0, 1],   # a lane anchor, far side of the bridge
	]))
	var rt = pair[0]
	rt.plan("seal", "seal", SealScript.SealBehavior.new(),
			SEAL_CFG.duplicate(true), 1)
	var spawn_tick := -1
	var spawn_text := ""
	var spawn_pos := Vector3.ZERO
	for i in range(400):
		for e in rt.step(DT):
			if e.get("e", "") == "enemy_spawn":
				spawn_tick = int(e.get("tick", -1))
				spawn_text = str(e.get("text", ""))
				spawn_pos = Vector3(float(e.get("x", 0.0)), float(e.get("y", 0.0)), float(e.get("z", 0.0)))
	if spawn_tick < 0:
		f.append("spawn: no enemy_spawn event in 400 ticks")
	else:
		if absi(spawn_tick - 360) > 1:
			f.append("spawn: spawned at tick %d, want 360 (+/-1)" % spawn_tick)
		_eq(f, "spawn text", str(spawn_text), "seal")
	if spawn_tick >= 0:
		if absf(spawn_pos.x - 45.5) > 1e-9 or absf(spawn_pos.z - 5.5) > 1e-9:
			f.append("spawn: lane anchor not preferred (x=%.1f z=%.1f, want 45.5/5.5)"
					% [spawn_pos.x, spawn_pos.z])


# The answer window (FLEET_PACK T-038): the spec's jump (v 12.0, g 32.0) holds the feet more
# than 1.2 u above their telegraph-start height from 0.12 s to 0.63 s after take-off - a
# 0.51 s window for its 0.07 s body crossing. The ENGINE integrates the arc at 60 Hz with
# semi-implicit Euler (gravity applied before the position update), so the REALIZED window
# sits a tick or two inside the continuous bounds - measured, not derived (D-T030-8).
# Asserts the realized window +/-1 tick, the ~0.51 s window length +/-1 tick, the apex.
func _jump_answer_window(f: Array[String]) -> void:
	var tiles: Array = []
	for x in range(-2, 40):
		for z in range(-2, 8):
			tiles.append([x, z, 0])
	var w := Util.world_from_tiles(tiles)
	w["dais"] = [0, 0, 0]
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	ctl.place(w)
	ctl.last_light_spent = true
	var airborne_from := -1
	var airborne_to := -1
	var apex := 0.0
	for i in range(0, 45):
		ctl.step(DT, Util.mk_in(0, 0, Util.ControllerScript.BTN_JUMP), w)
		var y := float(ctl.y)
		apex = maxf(apex, y)
		if y > 1.2:
			if airborne_from < 0:
				airborne_from = i
			airborne_to = i
	if airborne_from < 0:
		f.append("jump: the jump never cleared 1.2 u")
		return
	if airborne_from < 6 or airborne_from > 8:
		f.append("jump: feet first cleared 1.2 u on tick %d (%.3f s), want 0.12 s (+/-1 tick)"
				% [airborne_from, float(airborne_from + 1) * DT])
	if airborne_to < 34 or airborne_to > 36:
		f.append("jump: feet last cleared 1.2 u on tick %d (%.3f s), want 0.63 s (+/-1 tick)"
				% [airborne_to, float(airborne_to + 1) * DT])
	var window_ticks := airborne_to - airborne_from + 1
	if absi(window_ticks - 29) > 1:
		f.append("jump: the 1.2 u-clear window is %d ticks, want ~29 (0.48 s, the discrete twin of the spec's 0.51 s)" % window_ticks)
	if absf(apex - 2.25) > 0.15:
		f.append("jump: jump apex %.3f u, want ~2.25 u within the discretization (realized 2.15)" % apex)


# The bark answer, end to end (FLEET_PACK T-038): the seal telegraphs, the player jumps on
# the bark, and the dash passes UNDER them - no kill. Last Light spent (D-057); a save
# masking the kill would void the assertion. The seal dashes from 8 u away; the crossing
# lands ~24 ticks (0.4 s) after the bark, deep inside the 1.2 u-clear window (7..35).
func _jump_on_the_bark_survives(f: Array[String]) -> void:
	var pair := _runtime(_level([]))
	var rt = pair[0]
	var ctl = pair[1]
	var w: Dictionary = rt.world
	ctl.x = 8.5
	ctl.z = 0.5
	var row := _spawn_seal(rt, Vector3(0.5, 0.0, 0.5))
	var bark_tick := -1
	var jumped := false
	for i in range(160):
		var button = 0
		if bark_tick >= 0:
			# hold the jump through the crossing - holding never re-fires (edge-triggered),
			# a tap would trip the variable-height jump cut (DESIGN.md section 2.1)
			button = Util.ControllerScript.BTN_JUMP
			jumped = true
		ctl.step(DT, Util.mk_in(0, 0, button), w)
		for e in rt.step(DT):
			if e.get("e", "") == "telegraph" and e.get("kind", "") == "bark" and bark_tick < 0:
				bark_tick = int(e.get("tick", -1))
	if bark_tick < 0:
		f.append("jump: the seal never barked in 160 ticks")
		return
	if not jumped:
		f.append("jump: jump was never injected on the bark tick")
		return
	if bool(ctl.dead):
		f.append("jump: the seal killed a player who jumped on the bark (Last Light spent) - the dash hit through the >1.2 u clear window")
		return


# Spec arithmetic, pinned against the shipped data: the body crossing at the dash's 20 u/s
# is (0.6 body + 2 x 0.4 player half-width) / 20 = 0.07 s; a jump > 1.2 u feet window of
# 0.51 s covers it with ~7x margin; a 3 HU step (1.5 u) beats the 1.2 u threshold; a
# sidestep of exactly 0.7 u is the horizontal miss distance (0.3 hit radius + 0.4 half-width).
func _crossing_arithmetic(f: Array[String]) -> void:
	var crossing := (0.6 + 2.0 * 0.4) / 20.0
	if absf(crossing - 0.07) > 1e-9:
		f.append("crossing: %.4f s, want 0.07 s (1.4 u at 20 u/s)" % crossing)
	if not (1.5 > 1.2):
		f.append("step: a 3 HU step (1.5 u) must beat the 1.2 u miss threshold")
	var sidestep := 0.3 + 0.4
	if absf(sidestep - 0.7) > 1e-9:
		f.append("sidestep: miss distance %.2f u, want 0.7 u (0.3 radius + 0.4 half-width)" % sidestep)
