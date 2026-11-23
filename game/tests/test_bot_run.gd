extends RefCounted
#
# test_bot_run.gd (ticket T-060): the bot tool exists and its report format parses.
#   - the tool runs a 3-run smoke probe twice with the same seed set
#     (is determinism of the numbers);
#   - its band table has exactly the DESIGN.md section 9 rows for levels 6 / 12 / 18,
#     each with a reach-rate, the band label, and PASS / FAIL;
#   - the probe never prints "SKIP" and every run line prints its seed.
#   - the router's own promises hold: the ban-lift re-routes keep the chaser cost
#     (D-FIX-A3-2, _route over a diamond), a replan that finds nothing keeps the goal
#     markers instead of clearing them (_replan over a stubbed level), and the two
#     source contracts the band numbers rest on are still in place (_jump_arc refuses a
#     clipped candidate, not the scan; the in-place hurdle holds JUMP).
#
# The 200-run sweep is NOT in the gate; this test runs 3, twice, and asserts
# byte-identical reports.

const BotRun := preload("res://tools/bot_run.gd")
const ClawdsScript := preload("res://sim/clawds.gd")
const ClaudeEnemy := preload("res://content/enemies/claude/enemy.gd")
const ContentApiScript := preload("res://core/content_api.gd")

const SEED_BASE := 60717
const RUNS := 3


func run() -> Array[String]:
	var f: Array[String] = []
	_tool_exists(f)
	_report_shape_and_determinism(f)
	_policy_pins(f)
	_route_honours_menace(f)
	_replan_keeps_goal_markers(f)
	_goal_stale_reads_present(f)
	_clawd_routing(f)
	_threats_skip_out_of_play(f)
	_chaser_survival_pins(f)
	return f


func _tool_exists(f: Array[String]) -> void:
	var path := "res://tools/bot_run.gd"
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		f.append("bot_run.gd is missing or unreadable at %s" % path)
		return
	for needle in ["bot_run.gd", "DESIGN.md section 9", "REACT_TICKS", "_jump_arc",
			"run_probe", "format_report", "SEED_BASE"]:
		if text.find(needle) < 0:
			f.append("bot_run.gd does not carry %s" % needle)


func _report_shape_and_determinism(f: Array[String]) -> void:
	var agg1: Dictionary = BotRun.run_probe(RUNS, SEED_BASE, 18)
	var agg2: Dictionary = BotRun.run_probe(RUNS, SEED_BASE, 18)
	if not bool(agg1.get("ok", false)):
		f.append("content boot refused: %s" % " / ".join(agg1.get("boot_errors", [])))
		return
	if bool(agg1.get("ok", false)) != bool(agg2.get("ok", false)):
		f.append("second probe refused while first passed")
	for i in range(RUNS):
		var r1: Dictionary = agg1["rows"][i]
		var r2: Dictionary = agg2["rows"][i]
		for key in ["reached_6", "reached_12", "reached_18", "outcome", "entered", "class",
				"seed"]:
			if str(r1.get(key, "")) != str(r2.get(key, "")):
				f.append("run %d seed mismatch on %s: %s vs %s (not deterministic)"
						% [i, key, str(r1.get(key, "")), str(r2.get(key, ""))])
	var report: String = BotRun.format_report(agg1)
	var rows := report.split("\n")
	var want_lv := [6, 12, 18]
	var row_re := RegEx.create_from_string(
			"^level (6|12|18):\\s+[0-9.]+%\\s+\\(\\d+/3\\)\\s+band .*\\s+(PASS|FAIL)$")
	var row_idx := 0
	for line in rows:
		var m := row_re.search(line)
		if m:
			if int(m.get_string(1)) != int(want_lv[row_idx]):
				f.append("band row %d is level %s, want level %d" % [row_idx, m.get_string(1), want_lv[row_idx]])
			row_idx += 1
	if row_idx != 3:
		f.append("expected exactly 3 band rows, saw %d:\n%s" % [row_idx, report])
	if report.find("SKIP") >= 0:
		f.append("report leaked a SKIP row")
	for row in agg1["rows"]:
		var rd: Dictionary = row
		if str(rd.get("seed", "")) == "":
			f.append("a run row printed no seed")
	var report2: String = BotRun.format_report(agg2)
	if report != report2:
		f.append("same seed set produced different reports (not deterministic)")


## PARKED.md row 28 (findings w1-19-bot BUG-bot-1/2/3): the bot-policy contracts the
## 82/100 level-1 number rests on. _jump_arc and _bot_input need a live level and a
## collision world, which this gate has no engine for, so the two that cannot be called
## are pinned on their source shape; _route and _replan are exercised for real below.
func _policy_pins(f: Array[String]) -> void:
	var text := FileAccess.get_file_as_string("res://tools/bot_run.gd")
	if text.is_empty():
		f.append("bot_run.gd is unreadable, cannot pin the router policies")
		return
	# BUG-bot-1: one clipped candidate must refuse THAT candidate, not the scan (7 hold
	# values x 5 speeds). The function body carries exactly two empty returns: the
	# degenerate-direction guard and the final "nothing landed". A third one used to sit
	# inside the enemy clip, so one body in flight read as "no arc lands on a tile" and
	# banned a good edge for 300 ticks (_routing's lift cooldown).
	var arc_body: String = _func_body(text, "static func _jump_arc(")
	if arc_body.is_empty():
		f.append("bot_run.gd has no _jump_arc to pin")
	else:
		if arc_body.find("clipped = true") < 0:
			f.append("_jump_arc has no per-candidate clip refusal: a clipped arc abandons the whole candidate scan")
		var empty_returns := arc_body.count("return {}")
		if empty_returns != 2:
			f.append("_jump_arc returns an empty dict at %d sites, want 2 (the degenerate direction and the final no-arc): a clipped candidate must not end the scan" % empty_returns)
	# BUG-bot-2: both ban-lift re-routes must keep the +30/tile chaser cost (D-FIX-A3-2).
	# The lift is the cornered state, so re-picking the route without it walks into the
	# chaser that caused the ban in the first place.
	if text.find("_route(adj, gtiles, cur, {}, rm)") < 0:
		f.append("the ban-lift re-route passes no menace dict to _route: the lifted route ignores every chaser (D-FIX-A3-2)")
	if text.find("_route(adj, gtiles, cur, {})") >= 0:
		f.append("a _replan re-route is called without the menace dict: the route it picks does not pay the chaser cost")
	# BUG-bot-3: the in-place hurdle must be a HELD jump. A one-tick press is jump-cut
	# (jump_cut_mul 0.5) to a ~0.51 u apex, which never opens DESIGN.md section 5.1's
	# 1.5 u hurdle window and never lifts the feet above the body's height_u.
	if text.count("HURDLE_HOLD") < 2:
		f.append("the in-place hurdle presses JUMP for a single tick: jump_cut_mul 0.5 makes that a ~0.51 u apex, and DESIGN.md section 5.1's window needs a held jump")


## The source of one top-level function: from its signature line to the next one.
func _func_body(text: String, sig: String) -> String:
	var from := text.find(sig)
	if from < 0:
		return ""
	var to := text.find("\nstatic func ", from + sig.length())
	if to < 0:
		to = text.find("\nfunc ", from + sig.length())
	if to < 0:
		to = text.length()
	return text.substr(from, to - from)


## _route is pure over (adj, tiles), so the chaser cost is measurable with no engine: a
## diamond whose two walks both cost 2, and the menace on the near tile has to move the
## parent choice to the far one. Without the dict the router cannot see a chaser at all.
func _route_honours_menace(f: Array[String]) -> void:
	var tiles: Array = [[0, 0, 0], [1, 0, 0], [0, 1, 0], [1, 1, 0]]
	var adj: Array = [[1, 2], [0, 3], [0, 3], [1, 2]]
	var wanted: Dictionary = BotRun._route(adj, tiles, 0, {})
	var feared: Dictionary = BotRun._route(adj, tiles, 0, {}, {1: 30})
	var plain_dist := int((wanted["dist"] as PackedInt32Array)[3])
	var plain_parent := int((wanted["parent"] as PackedInt32Array)[3])
	if plain_dist != 2 or plain_parent != 1:
		f.append("route fixture drifted: the unmenaced diamond should reach 3 in 2 via tile 1, got dist %d parent %d" % [plain_dist, plain_parent])
	var feared_parent := int((feared["parent"] as PackedInt32Array)[3])
	var feared_dist := int((feared["dist"] as PackedInt32Array)[3])
	if feared_parent != 2:
		f.append("_route ignores the menace cost: the route still runs through the chaser's tile (parent %d, want 2)" % feared_parent)
	if feared_dist != 2:
		f.append("_route charged the menaced tile even on the detour: dist %d, want 2" % feared_dist)


## BUG-bot-4: "keep the goal markers" cleared them. A gift replan that found nothing
## reachable wrote goal_slot = -1, _goal_stale reads slot < 0 as stale for ever, so the
## router re-ran the whole Dijkstra every tick instead of every REPLAN_TICKS and the
## follower refused to move until the 300-tick lift. _replan is pure over
## (mem, lv, adj, tiles) once the level is stubbed, so this runs here with no engine.
func _replan_keeps_goal_markers(f: Array[String]) -> void:
	var mem: Dictionary = {
		"path": [0, 1], "path_i": 1, "goal_kind": "gift", "goal_tile": 1, "goal_slot": 0,
		"banned": {"0>1": true}, "lift_at": 1000, "menace": {}, "air_released": {},
		"slot_tiles": [1],
	}
	var lv := _StubLevel.new()
	lv.beacon = _StubBeacon.new()
	lv.gifts = _StubGifts.new()
	var adj: Array = [[1], [0]]
	var gtiles: Array = [[0, 0, 0], [1, 0, 0]]
	# the only gift sits behind a banned edge and the lift cooldown is still running, so
	# the scan finds nothing reachable
	BotRun._replan(mem, lv, null, 0, null, gtiles, adj, {})
	if int(mem["goal_slot"]) != 0 or int(mem["goal_tile"]) != 1:
		f.append("a replan with nothing reachable cleared the goal markers (%d/%d): the router then re-routes every tick and the follower stands still" % [int(mem["goal_tile"]), int(mem["goal_slot"])])
	if not (mem["path"] as Array).is_empty():
		f.append("a replan with nothing reachable kept a path it cannot walk")
	# the same replan, but the gift the caller was walking is GONE (the collapse took its
	# platform). Restoring the markers there is the ghost-chase again: the goal must clear.
	var mem2: Dictionary = {
		"path": [0, 1], "path_i": 1, "goal_kind": "gift", "goal_tile": 1, "goal_slot": 0,
		"banned": {"0>1": true}, "lift_at": 1000, "menace": {}, "air_released": {},
		"slot_tiles": [1],
	}
	var lv2 := _StubLevel.new()
	lv2.beacon = _StubBeacon.new()
	var g2 := _StubGifts.new()
	g2.lost = true
	lv2.gifts = g2
	BotRun._replan(mem2, lv2, null, 0, null, gtiles, adj, {})
	if int(mem2["goal_slot"]) == 0:
		f.append("a replan restored the goal markers for a LOST gift: the bot walks to a gift the collapse took")


## The collapse starts on the beacon-open tick, so the gold phase is exactly when a gift's
## platform can fall out from under it. A lost gift is NOT a collected one, so a staleness
## test that asks collected() alone leaves the bot routing to a ghost for the rest of the
## level - the same defect _nearest_gift had, in the staleness test instead of the chooser.
## _goal_stale is pure over (mem, lv) once the level is stubbed, so this runs with no engine.
func _goal_stale_reads_present(f: Array[String]) -> void:
	var lv := _StubLevel.new()
	lv.beacon = _StubBeacon.new()
	var g := _StubGifts.new()
	lv.gifts = g
	var mem: Dictionary = {"goal_kind": "gift", "goal_slot": 0}
	if BotRun._goal_stale(mem, lv):
		f.append("a live gift goal reads stale: the bot would replan every tick")
	g.lost = true
	if not BotRun._goal_stale(mem, lv):
		f.append("a LOST gift goal does not read stale: the bot keeps routing to a gift the collapse took out of the level")
	g.lost = false
	g.taken = true
	if not BotRun._goal_stale(mem, lv):
		f.append("a collected gift goal does not read stale")
	# the control that stops the leg passing by calling everything stale: a beacon goal is
	# never stale while the beacon is shut, whatever the gift state says
	var bmem: Dictionary = {"goal_kind": "beacon", "goal_slot": -1}
	if BotRun._goal_stale(bmem, lv):
		f.append("a beacon goal reads stale while the beacon is shut")


## T4 (review round 1): the bot answers Claude's anger clock. The routing decision is a pure function of the
## sim's own clawd runtime, so it is asserted directly - urgency starts at the DATA's first warning tick, the
## nearest reachable uncollected clawd wins, a collected or released clawd is skipped, the goal point is the
## clawd's own hover point - and one integration run pins that a Claude-voting level no longer ends in the
## anger kill.
func _clawd_routing(f: Array[String]) -> void:
	var cfg: Dictionary = ClaudeEnemy.clawd_cfg()
	var L := {"seed": 5, "level": 1, "gen_version": 1, "attempt": 0,
		"beacon": [0, 0, 0], "spawns": [[0, 0, 0]], "tiles": [], "props": [], "pads": [],
		"gifts": [], "pieces": []}
	for x in range(-8, 9):
		for z in range(-8, 9):
			(L["tiles"] as Array).append([x, z, 0, 0, 0])
	ClawdsScript.attach(L, cfg)
	var cl = ClawdsScript.create(L)
	if cl == null or cl.count() < 3:
		f.append("clawd routing: the fixture swarm has %d clawds, want >= 3"
			% (0 if cl == null else cl.count()))
		return
	var lv := _StubClawdLevel.new()
	lv.clawds = cl
	lv.beacon = _StubBeacon.new()
	# calm is not urgent
	if BotRun._clawd_urgent(cl, lv):
		f.append("clawd routing: the timer is urgent at anger 0")
	# urgent from the DATA's first warning tick on, not one tick before
	var w0 := int((cl.warning_ticks as Array)[0])
	cl.anger_ticks = w0 - 1
	if BotRun._clawd_urgent(cl, lv):
		f.append("clawd routing: urgent one tick before the first warning (%d)" % (w0 - 1))
	cl.anger_ticks = w0
	if not BotRun._clawd_urgent(cl, lv):
		f.append("clawd routing: not urgent at the first warning tick (%d)" % w0)
	# a frozen timer (the beacon is open) is not urgent
	lv.beacon = _StubOpenBeacon.new()
	if BotRun._clawd_urgent(cl, lv):
		f.append("clawd routing: urgent while the beacon is open (the timer is frozen)")
	lv.beacon = _StubBeacon.new()
	# the nearest reachable uncollected clawd wins; a collected or released one is skipped
	var dist := PackedInt32Array()
	dist.resize(400)
	dist.fill(-1)
	var mem := {"clawd_tiles": [], "clawd_released": {}}
	for i in cl.count():
		var gi: int = i * 3
		(mem["clawd_tiles"] as Array).append(gi)
		dist[gi] = 10 + i * 10          # clawd 0 is the nearest
	var pick: Array = BotRun._nearest_clawd(cl, dist, mem)
	if int(pick[1]) != 0:
		f.append("clawd routing: picked clawd %d, want 0 (the nearest)" % int(pick[1]))
	cl.taken[0] |= 1                                  # clawd 0 collected
	pick = BotRun._nearest_clawd(cl, dist, mem)
	if int(pick[1]) != 1:
		f.append("clawd routing: picked clawd %d after 0 was collected, want 1" % int(pick[1]))
	(mem["clawd_released"] as Dictionary)[1] = true    # clawd 1 given up as unreachable
	pick = BotRun._nearest_clawd(cl, dist, mem)
	if int(pick[1]) != 2:
		f.append("clawd routing: picked clawd %d after 1 was released, want 2" % int(pick[1]))
	# the goal point is the clawd's own hover point (the pickup centre)
	var gp: Vector3 = BotRun._goal_point({"goal_kind": "clawd", "goal_slot": 2}, lv)
	if gp.distance_to(cl.spot_pos(2)) > 0.0001:
		f.append("clawd routing: the goal point %s is not the clawd's spot %s"
			% [str(gp), str(cl.spot_pos(2))])
	# a live clawd goal is not stale; a collected one is
	var gmem := {"goal_kind": "clawd", "goal_slot": 2}
	if BotRun._goal_stale(gmem, lv):
		f.append("clawd routing: a live clawd goal reads stale")
	cl.taken[0] |= 4                                  # clawd 2 collected
	if not BotRun._goal_stale(gmem, lv):
		f.append("clawd routing: a collected clawd goal does not read stale")
	# the integration control: a level-15 run that votes Claude must not end in the anger kill
	var api := ContentApiScript.load()
	if not bool(api.is_ok()):
		f.append("clawd routing: content boot refused: %s" % " / ".join(api.boot_errors()))
		return
	var ledger := {"votes": {"claude": 1}, "curses": {}, "stacks": {}, "purse": 0,
		"tithes": 0, "hunger": 0, "last_vote": "claude", "class": "dasher",
		"charges": 0, "last_light_spent": false}
	var r: Dictionary = BotRun._play_level(api, ledger, 20, 15)
	if str(r.get("death_code", "")) == "D-CLAUDE":
		f.append("clawd routing: a bot run that votes Claude still died to the anger timer at tick %s"
			% str(r.get("death_tick", -1)))


## A body that is out of play cannot kill - sim/enemy_runtime.gd skips it in _contact_kills
## by is_out_of_play() - so the bot must not route around it either. The collapse starts on
## the beacon-open tick, so a fallen body is exactly what the gold phase is full of. Both
## threat readers (_enemy_points for the menace cost and the landing avoid set, _enemy_reach
## for the D-B5B-1 corridor) must agree with the sim's own predicate.
func _threats_skip_out_of_play(f: Array[String]) -> void:
	var rt := _StubRuntime.new()
	rt.enemies = [
		{"x": 10.0, "z": 0.0, "diameter_u": 1.0, "contact_kill": true},
		{"x": 20.0, "z": 0.0, "diameter_u": 1.0, "contact_kill": true, "falling": true},
		{"x": 30.0, "z": 0.0, "diameter_u": 1.0, "contact_kill": true, "gone": true},
	]
	var pts: Array = BotRun._enemy_points(rt)
	if pts.size() != 1:
		f.append("_enemy_points returned %d points, want 1: a falling or gone body cannot kill, so routing around it is routing around nothing" % pts.size())
	elif (pts[0] as Vector2).x != 10.0:
		f.append("_enemy_points kept the wrong body (x=%s, want 10.0)" % str((pts[0] as Vector2).x))
	# the reach is the widest LIVE contact radius: 1.0 * 0.5 + 0.4 = 0.9. A gone body with a
	# huge diameter must not widen it, or the landing pick refuses columns for nothing.
	rt.enemies.append({"x": 40.0, "z": 0.0, "diameter_u": 20.0, "contact_kill": true, "gone": true})
	var reach: float = BotRun._enemy_reach(rt)
	if not is_equal_approx(reach, 0.9):
		f.append("_enemy_reach %.3f, want 0.9: an out-of-play body widened the landing corridor" % reach)
	# the control that stops the leg passing by returning nothing: a live body IS a threat
	rt.enemies = [{"x": 5.0, "z": 5.0, "diameter_u": 1.0, "contact_kill": true}]
	if (BotRun._enemy_points(rt) as Array).size() != 1:
		f.append("_enemy_points dropped a LIVE body: the filter is too wide")
	if not is_equal_approx(BotRun._enemy_reach(rt), 0.9):
		f.append("_enemy_reach dropped a LIVE body's radius")


## D-B9-1: the two chaser deaths the pinned sweep kept producing, pinned as pure functions.
## Both are policy bugs, not game bugs - the sim was right and the bot read it wrong.
func _chaser_survival_pins(f: Array[String]) -> void:
	# (a) a DEGENERATE y band is a plane marker, not a volume. The coil's landing ring is
	# drawn on the landing plane (y0 == y1) and its kill is a height-blind 1.2 u circle
	# (D-T-031-4), so a bot that reads the zero-height band as a volume stops dodging the
	# moment it steps up 0.5 u, jumps or drops.
	var ring := {"shape": "circle", "cx": 0.0, "cz": 0.0, "r": 1.2, "y0": 0.0, "y1": 0.0}
	if not BotRun._inside_footprint(ring, 0.0, 0.5, 0.0):
		f.append("coil ring: feet 0.5 u above the landing plane read as OUTSIDE the strike - the landing kill is height-blind (D-T-031-4)")
	if not BotRun._inside_footprint(ring, 0.0, 2.0, 0.0):
		f.append("coil ring: feet 2.0 u above the landing plane read as OUTSIDE the strike")
	# the control that stops the fix being "ignore y entirely": a band with REAL height bounds
	var slab := {"shape": "circle", "cx": 0.0, "cz": 0.0, "r": 1.2, "y0": 0.0, "y1": 1.0}
	if not BotRun._inside_footprint(slab, 0.0, 0.5, 0.0):
		f.append("slab: feet inside a 1.0 u band read as OUTSIDE it")
	if BotRun._inside_footprint(slab, 0.0, 3.0, 0.0):
		f.append("slab: feet 3.0 u above a 1.0 u band read as INSIDE it - the y test was dropped, not narrowed")
	# ...and the horizontal test still bounds a degenerate band
	if BotRun._inside_footprint(ring, 5.0, 0.0, 0.0):
		f.append("coil ring: feet 5 u away read as INSIDE a 1.2 u circle")
	# (b) a body the hop cannot lift the feet over is not hurdled. body_contact clears only
	# on py0 > row.y + height_u, so a body whose top is at the apex is never cleared at all.
	var ctl := _StubCtl.new()
	var apex: float = BotRun._hop_apex(ctl)
	if not is_equal_approx(apex, 2.25):
		f.append("hop apex %.3f, want 2.25 (jump_velocity 12, gravity 32)" % apex)
	if not BotRun._hop_clears(0.0, {"y": 0.0, "height_u": 1.0}, apex):
		f.append("hop: a 1.0 u body on the floor read as unclearable")
	# the kiwi cat hovers, so its top sits 2.0-2.4 u above the feet
	if BotRun._hop_clears(0.0, {"y": 1.4, "height_u": 1.0}, apex):
		f.append("hop: a body whose top is 2.4 u up read as clearable - the hop keeps the feet inside its span")
	# a coil in flight is 2.0 u tall
	if BotRun._hop_clears(0.0, {"y": 2.0, "height_u": 1.0}, apex):
		f.append("hop: a 2.0 u body at 2.0 u read as clearable")
	# the control that stops the rule being "never hop": a low body IS clearable
	if not BotRun._hop_clears(0.0, {"y": 0.0, "height_u": 0.5}, apex):
		f.append("hop: a 0.5 u body read as unclearable - the rule is too wide")
	# (c) D-B9-2: the steering guard looks further ahead while AIRBORNE. Mine contact is
	# height-blind (DESIGN.md 3.3), so a mine 2.5 u ahead is one an airborne arc can still
	# come down on, while a 1.2 u ground step cannot reach it. The planned-jump scan
	# already refuses an arc within MINE_ARC_SAFE; this is the same rule for the arcs the
	# bot did not plan (the emergency dodge jump).
	var ahead: Array = [Vector2(2.5, 0.0)]
	if not BotRun._mine_clear(0.0, 0.0, Vector2(1.0, 0.0), ahead, 1.2):
		f.append("mine guard: a mine 2.5 u ahead read as blocking a 1.2 u ground step")
	if BotRun._mine_clear(0.0, 0.0, Vector2(1.0, 0.0), ahead, BotRun.AIR_MINE_REACH):
		f.append("mine guard: a mine 2.5 u ahead read as clear of a 3.0 u airborne arc")
	# the control that stops the rule being "always block": a mine off the heading is clear
	var aside: Array = [Vector2(2.5, 2.5)]
	if not BotRun._mine_clear(0.0, 0.0, Vector2(1.0, 0.0), aside, BotRun.AIR_MINE_REACH):
		f.append("mine guard: a mine 2.5 u off the heading read as blocking it")
	# ...and the ground reach still blocks a mine the step actually reaches
	var near: Array = [Vector2(0.8, 0.0)]
	if BotRun._mine_clear(0.0, 0.0, Vector2(1.0, 0.0), near, 1.2):
		f.append("mine guard: a mine 0.8 u ahead read as clear of a 1.2 u ground step")


class _StubCtl:
	var C := {"jump_velocity": 12.0, "gravity": 32.0}


class _StubRuntime:
	var enemies: Array = []


class _StubBeacon:
	func is_open() -> bool:
		return false


class _StubGifts:
	var slots: Array = [0]
	var lost := false
	var taken := false

	func is_real(_i: int) -> bool:
		return true

	func collected(_i: int) -> bool:
		return taken

	# the router asks present() (real, not collected, not lost) since the platform
	# collapse can take a gift out of the level without collecting it
	func present(_i: int) -> bool:
		return not taken and not lost

	func slot_pos(_i: int) -> Vector3:
		return Vector3(0.0, 1.0, 0.0)


class _StubLevel:
	var tick := 10
	var beacon: RefCounted
	var gifts: RefCounted


class _StubClawdLevel:
	var tick := 10
	var beacon: RefCounted
	var clawds: RefCounted


class _StubOpenBeacon:
	func is_open() -> bool:
		return true
