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

const SEED_BASE := 60717
const RUNS := 3


func run() -> Array[String]:
	var f: Array[String] = []
	_tool_exists(f)
	_report_shape_and_determinism(f)
	_policy_pins(f)
	_route_honours_menace(f)
	_replan_keeps_goal_markers(f)
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


class _StubBeacon:
	func is_open() -> bool:
		return false


class _StubGifts:
	var slots: Array = [0]

	func is_real(_i: int) -> bool:
		return true

	func collected(_i: int) -> bool:
		return false

	func slot_pos(_i: int) -> Vector3:
		return Vector3(0.0, 1.0, 0.0)


class _StubLevel:
	var tick := 10
	var beacon: RefCounted
	var gifts: RefCounted