extends RefCounted
#
# T-033 - the isagi enemy. Proves every timing and number of DESIGN.md section 5.4
# within +/-1 tick, that his body contact kills, and his death code.
#
# D-057 (STANDING): every KILL test here sets last_light_spent BEFORE the kill window -
# otherwise the save masks the kill and the assertion is worthless.
#
# The burst data comes from the REAL enemy.json (loaded through the registry), so the
# stats file - not the test - is what stays glued to section 5.4.

const RT := preload("res://sim/enemy_runtime.gd")
const Isagi := preload("res://content/enemies/isagi/enemy.gd")
const IsagiView := preload("res://view/isagi_view.gd")
const RegistryScript := preload("res://core/registry.gd")
const Util := preload("res://tests/sim_testutil.gd")

const TICK_TOL := 1            # the ticket's +/-1 tick on every section 5.4 number
const SPAWN_LATE := 360 + 2    # step past the D-056 spawn delay


func run() -> Array[String]:
	var f: Array[String] = []
	var stats: Dictionary = _real_stats(f)
	if stats.is_empty():
		return f
	_data(f, stats)
	_volley_clock(f, stats)
	_flash_thirds(f)
	_burst_timing(f, stats)
	_cooldown_repeat(f, stats)
	_ball_flight_and_fixed_line(f, stats)
	_step_clears_line(f, stats)
	_ball_stops_on_tile(f, stats)
	_ball_life_cap(f, stats)
	_body_contact_kills(f, stats)
	_perch_relocation(f, stats)
	_lane_dwell_and_suppression(f, stats)
	_view_anim_block(f, stats)
	return f


# ---- the real enemy.json through the registry ----------------------------------------------

func _real_stats(f: Array[String]) -> Dictionary:
	var res: Dictionary = RegistryScript.load_all()
	if not bool(res.get("ok", false)):
		f.append("isagi: registry refuses boot: %s" % str(res.get("errors", []).slice(0, 4)))
		return {}
	var e: Dictionary = res.get("enemies", {}).get("isagi", {})
	if e.is_empty():
		f.append("isagi: enemy.json did not load")
		return {}
	return e["stats"]


# ---- section 5 numbers in the data file (the roster row: level 11, 2 votes) ----------------

func _data(f: Array[String], stats: Dictionary) -> void:
	var res: Dictionary = RegistryScript.load_all()
	var e: Dictionary = res["enemies"]["isagi"]
	var want := {"min_level": 11, "max_votes": 2, "vote_effect": "+1 Isagi"}
	for k in want.keys():
		if e.get(k, "") != want[k]:
			f.append("isagi: %s = %s, want %s" % [k, str(e.get(k)), str(want[k])])
	if e.get("anchor_kinds", []) != ["perch"]:
		f.append("isagi: anchor_kinds = %s, want [perch] (section 5.4)" % str(e.get("anchor_kinds")))
	# SR-2 body + section 5.4 burst numbers
	var num := {
		"world_height": 1.8, "hit_diameter": 0.7, "relocate_s": 12.0, "lane_dwell_s": 4.0,
		"windup_s": 1.2, "cooldown_s": 2.5, "volley_balls": 3, "volley_in_s": 0.15,
		"volley_gap_s": 0.75, "ball_speed": 22.0, "ball_radius": 0.5, "ball_life_s": 3.0,
		"muzzle_up": 1.0, "target_centre_up": 0.9, "step_clears_hu": 2.0,
	}
	for k in num.keys():
		if absf(float(stats.get(k, -1.0))) - float(num[k]) > 1e-6:
			f.append("isagi: stats %s = %s, want %s (DESIGN.md section 5.4)"
					% [k, str(stats.get(k)), str(num[k])])
	if str(stats.get("death_code", "")) != "D-ISAGI":
		f.append("isagi: death_code %s, want D-ISAGI" % str(stats.get("death_code")))


# ---- D-064 volley shapes: 3 / 4 / 5 / 7 ball bursts ----------------------------------------

func _volley_clock(f: Array[String], stats: Dictionary) -> void:
	var vc := IsagiView.release_ticks(3)
	if str(vc) != str([0, 9, 18]):
		f.append("isagi: 3-ball releases %s, want 0/9/18 (0.15 s apart)" % str(vc))
	var r4: Array = IsagiView.release_ticks(4)
	var r5: Array = IsagiView.release_ticks(5)
	var r7: Array = IsagiView.release_ticks(7)
	if str(r7) != str([0, 9, 18, 45, 54, 63, 90]):
		f.append("isagi: 7-ball releases %s, want the 3+3+1 pattern 0/9/18/45/54/63/90" % str(r7))
	for r in [r4, r5, r7]:
		for i in range(1, r.size()):
			var gap: int = int(r[i]) - int(r[i - 1])
			var in_volley: bool = gap == RT.VOLLEY_TICKS
			var past_volley: bool = int(r[i]) % RT.VOLLEY_GAP_TICKS == 0
			if not (in_volley or past_volley):
				f.append("isagi: release gap %d at %d breaks the D-064 shape %s" % [gap, int(r[i]), str(r)])
	# at most 3 balls per volley, start-to-start 45 ticks (one full jump)
	var plan: Array = RT.volley_plan(7)
	if str(plan) != str([3, 3, 1]):
		f.append("isagi: plan(7) = %s, want 3+3+1" % str(plan))


# ---- the anim block's accelerating wind-up flash: 24 -> 12 -> 6 ------------------------------

func _flash_thirds(f: Array[String]) -> void:
	var thirds := [[0, 24], [10, 24], [23, 24], [24, 12], [30, 12], [47, 12],
			[48, 6], [60, 6], [71, 6]]
	for c in thirds:
		var got: int = IsagiView.flash_period(int(c[0]))
		if got != int(c[1]):
			f.append("isagi: flash period at t=%d is %d, want %d" % [int(c[0]), got, int(c[1])])


# ---- burst timing through the real runtime (wind-up 72, releases, cooldown 150) --------------

func _los_scene(stats: Dictionary) -> Array:
	# floor x 0..34 at z 0; a perch platform at z 4 (y 2.0 u) x 30..34; clear LOS.
	var tiles: Array = []
	for x in range(0, 35):
		tiles.append([x, 0, 0, 0, 0])
	for x in range(30, 35):
		tiles.append([x, 4, 4, 0, 0])
	var anchors: Array = [[0, 30, 4, 4]]   # perch kind, (30, 4), 2.0 u
	var pair := _mk(tiles, anchors)
	var ctl = pair[1]
	ctl.x = 5.5
	ctl.y = 0.0
	ctl.z = 0.5
	ctl.vy = 0.0
	return [pair[0], ctl]


func _plan_isagi(rt, stats: Dictionary, override: Dictionary = {}) -> void:
	var st: Dictionary = stats.duplicate(true)
	for k in override.keys():
		st[k] = override[k]
	var cfg := {"id": "isagi", "name": "Isagi", "preferred_kind": "perch", "stats": st}
	rt.plan("isagi", "Isagi", Isagi.Behavior.new(), cfg, 1)


func _events(rt) -> Array:
	var out: Array = []
	for e in rt.step(Util.DT):
		out.append(e)
	return out


# runs n ticks, returns all events of kind `kind`
func _of_kind(rt, ticks: int, kind: String) -> Array:
	var out: Array = []
	for i in range(ticks):
		for e in _events(rt):
			if e.get("e", "") == kind:
				out.append(e)
	return out


func _ticks_of(rt, ticks: int, pred: Callable) -> Array:
	var out: Array = []
	for i in range(ticks):
		var evs := _events(rt)
		for e in evs:
			if pred.call(e):
				out.append(i)
				break
	return out


func _burst(f: Array[String], stats: Dictionary, override: Dictionary,
		want_balls: int, want_releases: Array) -> void:
	var scene := _los_scene(stats)
	var rt = scene[0]
	_plan_isagi(rt, stats, override)
	var t0 := -1
	var shots: Array = []
	for i in range(30 + 260 + 260):
		for e in _events(rt):
			if e.get("e", "") == "telegraph" and t0 < 0:
				t0 = i
			if e.get("e", "") == "projectile_spawn" and e.get("name", "") == "Isagi" and t0 >= 0:
				shots.append(i - t0)
		if t0 >= 0 and shots.size() >= want_balls:
			break
	if t0 < 0:
		f.append("isagi: no wind-up telegraph started with clear LOS")
		return
	if shots.size() < want_balls:
		f.append("isagi: burst released %d balls, want %d" % [shots.size(), want_balls])
		return
	for j in range(want_releases.size()):
		var want_off: int = int(want_releases[j])
		var got: int = int(shots[j])
		if absi(got - want_off) > TICK_TOL:
			f.append("isagi: ball %d at wind-up+%d, want +%d (+/-1)" % [j, got, want_off])


func _burst_timing(f: Array[String], stats: Dictionary) -> void:
	# 3 balls: releases at wind-up end (72), 81, 90; attack pose held to 102
	_burst(f, stats, {}, 3, [Isagi.WINDUP_TICKS, 81, 90])


func _cooldown_repeat(f: Array[String], stats: Dictionary) -> void:
	var scene := _los_scene(stats)
	var rt = scene[0]
	_plan_isagi(rt, stats)
	var tgs: Array = _ticks_of(rt, 900, func(e) -> bool:
		return e.get("e", "") == "telegraph")
	if tgs.size() < 2:
		f.append("isagi: cooldown repeat sent %d telegraphs in 900 ticks, want >= 2" % tgs.size())
		return
	# cycle: 72 wind-up + 30 attack + 150 recover = 252 ticks between telegraph starts
	var gap: int = int(tgs[1]) - int(tgs[0])
	if absi(gap - 252) > TICK_TOL:
		f.append("isagi: telegraph gap %d ticks, want 252 +/-1 (72 + 30 + 150)" % gap)


# ---- ball flight: muzzle 1.0 u above his tile, straight 3D at 22 u/s, fixed at release -----

func _run_until_spawn(rt, ticks: int) -> void:
	for i in range(ticks):
		_events(rt)


func _ball_flight_and_fixed_line(f: Array[String], stats: Dictionary) -> void:
	# short, exact geometry: the man spawned on the LOS perch; the first live ball's
	# flight line is checked against the release-time centre (feet + 0.9).
	var scene := _los_scene(stats)
	var rt = scene[0]
	_plan_isagi(rt, stats)
	var b := {}
	for i in range(700):
		_events(rt)
		for p in rt.projectiles:
			if str(p.get("name", "")) == "Isagi":
				b = p
				break
		if not b.is_empty():
			break
	if b.is_empty():
		f.append("isagi: no ball spawned out of the LOS scene within 700 ticks")
		return
	# the spawn event carries the muzzle position at release: (30.5, 3.0, 4.5)
	var ev := {}
	for e in rt.events:
		if e.get("e", "") == "projectile_spawn" and e.get("name", "") == "Isagi":
			ev = e
	if ev.is_empty():
		f.append("isagi: no projectile_spawn event for the first ball")
		return
	if absf(float(ev["y"]) - 3.0) > 1e-6:
		f.append("isagi: ball muzzle y %.3f, want 3.0 (his tile 2.0 + 1.0)" % float(ev["y"]))
	var d := Vector3(float(b["vx"]), float(b["vy"]), float(b["vz"]))
	if absf(d.length() - 22.0) > 0.5:
		f.append("isagi: ball speed %.2f u/s, want 22.0" % d.length())
	# the line aims at the player's centre at release: (5.5, 0.9, 0.5)
	var dir := d.normalized()
	var to_centre := (Vector3(5.5, 0.9, 0.5)
			- Vector3(float(ev["x"]), float(ev["y"]), float(ev["z"]))).normalized()
	if dir.angle_to(to_centre) > 0.02:
		f.append("isagi: ball line leaves the release centre by %.4f rad (must not home)" % dir.angle_to(to_centre))


func _step_clears_line(f: Array[String], stats: Dictionary) -> void:
	# The line is fixed AT RELEASE: on that release tick the player is ON the line
	# (centre 0.9 u); from the NEXT tick they are airborne (centre > 1.5 u) and the
	# ball passes under them - a jump clears the volley (section 5.4'S answer).
	# D-057: the save was already spent in _mk, so a hit would be a death here.
	var scene := _los_scene(stats)
	var rt = scene[0]
	var ctl = scene[1]
	_plan_isagi(rt, stats)
	_run_until_spawn(rt, 300)
	var first_ball := false
	for i in range(260 + 120):
		if first_ball:
			ctl.y = 2.0          # airborne after the release: a centre over 1.5 u
			ctl.vy = 0.0
			ctl.grounded = false
		for e in _events(rt):
			if e.get("e", "") == "death" and e.get("code", "") == "D-ISAGI":
				f.append("isagi: a jump (centre raised after release) was hit by the fixed release line")
				return
			if e.get("e", "") == "projectile_spawn" and e.get("name", "") == "Isagi":
				first_ball = true


func _ball_stops_on_tile(f: Array[String], stats: Dictionary) -> void:
	# The tile stop: the dead player stands UP a 2 HU step so the flat in-line
	# suppression does NOT apply (exactly 2 HU of height change is not "< 2"); the
	# ball's release line rises to their centre at release (5.5, 2.9, 0.5) and must
	# end ON the wall column at x 8 (tops to 5.0 u).
	var tiles: Array = []
	for x in range(0, 45):
		tiles.append([x, 0, 0, 0, 0])
	tiles.append([5, 0, 4, 0, 0])           # the player's 2 HU step
	for yhu in range(0, 11):
		tiles.append([8, 0, yhu, 0, 0])     # the wall column at x 8 (top 5.0 u)
	var pair := _mk(tiles, [[2, 2, 0, 0]])
	var rt = pair[0]
	var ctl = pair[1]
	ctl.x = 5.5
	ctl.y = 2.0
	ctl.z = 0.5
	ctl.vy = 0.0
	ctl.invuln = 0.0
	var cfg := {"id": "isagi", "name": "Isagi", "preferred_kind": "lane", "stats": stats}
	rt.spawn_at("isagi", "Isagi", Isagi.Behavior.new(), cfg, Vector3(2.5, 0.0, 0.5))
	# the player dies first: projectiles pass through a dead controller, so the ball
	# must reach the wall and stop there (the tile stop, not a player hit)
	var kill_ev: Array = []
	if not ctl.try_kill("D-TEST", "setup", rt.world, kill_ev) and not ctl.dead:
		f.append("isagi: setup - direct kill did not take (invuln=%s)" % str(ctl.invuln))
		return
	# the player is dead: projectiles pass through - the ball must die on the wall
	for i in range(60 + 260):
		for e in _events(rt):
			if e.get("e", "") == "projectile_end" and e.get("name", "") == "Isagi":
				if str(e.get("cause", "")) != "solid":
					f.append("isagi: ball ended cause %s, want solid (stopped by any tile)" % str(e.get("cause")))
				var bx: float = float(e.get("x", -99.0))
				if bx < 6.0 or bx > 9.5:
					f.append("isagi: ball ended at x %.2f, want on the wall column at 8" % bx)
				return
	f.append("isagi: the ball neither ended nor stopped - no tile/prop stop and no life cap")


func _ball_life_cap(f: Array[String], stats: Dictionary) -> void:
	# Over the void with the player dead: the ball survives to its 3.0 s (180 ticks)
	# cap - his tile is at x 0.5, the floor ends at x 4; the ball flies east, passes
	# the dead player, and the only death left is the life cap.
	var tiles: Array = []
	for x in range(0, 4):
		tiles.append([x, 0, 0, 0, 0])
	var pair := _mk(tiles, [])
	var rt = pair[0]
	var ctl = pair[1]
	ctl.x = 2.5
	ctl.y = 0.0
	ctl.z = 0.5
	ctl.invuln = 0.0
	var cfg := {"id": "isagi", "name": "Isagi", "preferred_kind": "lane", "stats": stats}
	rt.spawn_at("isagi", "Isagi", Isagi.Behavior.new(), cfg, Vector3(0.5, 0.0, 0.5))
	if not ctl.try_kill("D-TEST", "setup", rt.world, []) and not ctl.dead:
		f.append("isagi: setup - direct kill did not take (invuln=%s)" % str(ctl.invuln))
		return
	for i in range(40 + 260):
		for e in _events(rt):
			if e.get("e", "") == "projectile_end" and e.get("name", "") == "Isagi":
				if str(e.get("cause", "")) != "life":
					f.append("isagi: ball ended cause %s over the void, want life (the 3.0 s cap)" % str(e.get("cause")))
				var bx: float = float(e.get("x", 0.0))
				if bx < 4.0:
					f.append("isagi: life-cap ball ended at x %.2f - it never left over the void" % bx)
				return
	f.append("isagi: no projectile_end at all - the ball never ended (want the 180-tick life cap)")


func _body_contact_kills(f: Array[String], stats: Dictionary) -> void:
	# D-057: Last Light already spent - the save cannot mask the kill. Body contact
	# kills (the KILL RULE default) with the death code D-ISAGI (D-T027-5: the code
	# names the killer, never a damage number).
	var scene := _los_scene(stats)
	var rt = scene[0]
	var ctl = scene[1]
	var cfg := {"id": "isagi", "name": "Isagi", "preferred_kind": "perch", "stats": stats}
	rt.spawn_at("isagi", "Isagi", Isagi.Behavior.new(), cfg, Vector3(5.9, 0.0, 0.5))
	for i in range(4):
		for e in _events(rt):
			if e.get("e", "") == "death":
				if str(e.get("code", "")) != "D-ISAGI":
					f.append("isagi: death code %s, want D-ISAGI" % str(e.get("code")))
				return
	f.append("isagi: body contact did not kill (D-057: last_light_spent=%s)" % str(ctl.last_light_spent))


func _perch_relocation(f: Array[String], stats: Dictionary) -> void:
	# two perches both >= 25 u from the player with clear LOS: the one NEAREST the
	# player wins; a third perch's line is walled off and must lose the pick.
	var tiles: Array = []
	for x in range(0, 40):
		tiles.append([x, 0, 0, 0, 0])
	for x in range(28, 33):
		tiles.append([x, 4, 4, 0, 0])       # perch A's platform (anchor [0,30,4])
	for yhu in range(0, 10):
		tiles.append([33, 0, yhu, 0, 0])    # the wall between the player and perch C
	var anchors: Array = [[0, 30, 4, 4], [0, 36, 0, 4]]
	var pair := _mk(tiles, anchors)
	var rt = pair[0]
	var ctl = pair[1]
	ctl.x = 5.5
	ctl.y = 0.0
	ctl.z = 0.5
	_plan_isagi(rt, stats)
	var row = null
	for i in range(360 + 30 + 30 + 720 + 6):
		for e in _events(rt):
			pass
		for en in rt.enemies:
			if str(en["id"]) == "isagi":
				row = en
				break
	if row == null:
		f.append("isagi: relocation test lost the row")
		return
	# the first relocate lands ~spawn_tick + 720; both later ticks settle there
	if absf(float(row["x"]) - 30.5) > 0.1:
		f.append("isagi: relocated to (%.1f, %.1f), want the nearest clear-LOS perch at 30.5 (not 36.5, LOS-walled)"
				% [float(row["x"]), float(row["z"])])


func _lane_dwell_and_suppression(f: Array[String], stats: Dictionary) -> void:
	# a `lane` anchor walkway (no perch anywhere): the flat in-line axis to the player
	# suppresses the wind-up, and the dwell limit moves him off within 240 ticks.
	var tiles: Array = []
	for x in range(0, 70):
		tiles.append([x, 0, 0, 0, 0])
	var anchors: Array = [[2, 10, 0, 0], [2, 50, 0, 0]]
	var pair := _mk(tiles, anchors)
	var rt = pair[0]
	var ctl = pair[1]
	ctl.x = 12.5
	ctl.y = 0.0
	ctl.z = 0.5
	var cfg := {"id": "isagi", "name": "Isagi", "preferred_kind": "perch", "stats": stats}
	var row = rt.spawn_at("isagi", "Isagi", Isagi.Behavior.new(), cfg,
			Vector3(10.5, 0.0, 0.5))
	# the walkway is the long flat run on x (1 wide, z 0): the player sits DOWN that
	# run on the walkway axis with 0 HU of height change - flat in-line lane (T-070 item 10)
	var telegraphs := 0
	var moved_tick := -1
	for i in range(245):
		for e in _events(rt):
			if e.get("e", "") == "telegraph":
				telegraphs += 1
		if moved_tick < 0 and absf(float(row["x"]) - 10.5) > 0.1:
			moved_tick = i
	if telegraphs > 0:
		f.append("isagi: wind-up began on a flat in-line lane within 245 ticks (%d)" % telegraphs)
	if moved_tick < 0:
		f.append("isagi: did not relocate off the lane anchor within the 240-tick dwell limit")
	elif moved_tick > 240 + TICK_TOL:
		f.append("isagi: relocated at tick %d, past the 240-tick dwell limit" % moved_tick)

	# the same strip with the player up a 2 HU step: the suppression is OFF - wind-up
	# begins (the burst still fires down onto them; the step only answers the BALL line)
	var tiles2: Array = []
	for x in range(0, 70):
		tiles2.append([x, 0, 0, 0, 0])
	tiles2.append([20, 0, 4, 0, 0])   # the 2 HU step at x 20
	var pair2 := _mk(tiles2, [[2, 10, 0, 0]])
	var rt2 = pair2[0]
	var ctl2 = pair2[1]
	ctl2.x = 20.5
	ctl2.y = 2.0
	ctl2.z = 0.5
	rt2.spawn_at("isagi", "Isagi", Isagi.Behavior.new(), cfg, Vector3(10.5, 0.0, 0.5))
	var saw_telegraph := false
	for i in range(45 + 90):
		for e in _events(rt2):
			if e.get("e", "") == "telegraph":
				saw_telegraph = true
	if not saw_telegraph:
		f.append("isagi: no wind-up with the player up a 2 HU step - the suppression must NOT apply")


func _view_anim_block(f: Array[String], stats: Dictionary) -> void:
	var res: Dictionary = RegistryScript.load_all()
	var doc: Dictionary = res.get("sprites", {}).get("isagi", {})
	if doc.is_empty():
		var raw := FileAccess.get_file_as_string("res://content/enemies/isagi/sprites.json")
		var parsed: Variant = JSON.parse_string(raw)
		if parsed is Dictionary:
			doc = parsed
	var view := IsagiView.new()
	view.setup(doc)
	for st in ["spawn", "idle", "telegraph", "attack", "recover"]:
		var a: Dictionary = view.anim_state(st)
		if a.is_empty():
			f.append("isagi: anim block lacks the %s state (T-083 table 1.4)" % st)
	if view.SFX_HOOKS["telegraph"].size() == 0:
		f.append("isagi: the wind-up carries no voice cue hook (ENEMIES.md 'New sound')")
	if view.SFX_HOOKS["attack"].size() < 2:
		f.append("isagi: the release carries no shoot line + gunshot hooks")


# ---- shared scene builder -------------------------------------------------------------------

func _mk(tiles: Array, anchors: Array) -> Array:
	var props: Array = []
	var pads: Array = []
	var w = Util.CollisionScript.make_world(tiles, props, pads)
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	ctl.place(w)
	ctl.last_light_spent = true   # D-057: the save must never mask a kill here
	var lv := {"beacon": [0, 0, 0], "spawns": [[0, 0, 0]], "anchors": anchors,
			"tiles": tiles, "props": props, "pads": pads}
	var rt = RT.new()
	rt.setup(lv, w, [ctl], 7)
	return [rt, ctl]

