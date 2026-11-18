extends SceneTree
#
# tools/run_report.gd - the T-081 fun-risk report (research/fable-funrisks.md; the
# owner's spec: "the eight cheap signals named there; priority is terrain-caused vs
# enemy-caused deaths").
#
#   <godot> --headless --path game --script res://tools/run_report.gd -- <folder>
#
# <folder> holds T-080 run logs (game/app/run_log.gd's one JSON object per line;
# user://runs is the default when the folder is omitted). Prints, per level bucket
# (1-5, 6-10, 11-15, 16-20, 21-25, 26-30) and overall, these eight signals IN ORDER:
#   1. terrain vs enemy (risk 3)     5. stair rate (risk 5)
#   2. restart time (risk 1)         6. lobby time (risk 7)
#   3. unseen deaths (risk 2)        7. mine margin (risk 8)
#   4. level length and pressure     8. content health (risk 10)
# INFORMATION ONLY: no pass/fail, no threshold, nothing tuned (the fun-risk document:
# signals are not gates). Every field the report reads is a T-080 record field; a
# signal the records cannot measure keeps its block and prints
# "not measurable from the current records: <what is missing>" - never an invented
# number, never a silent drop.
#
# Pure at heart: collect() / aggregate() / render() / report_text() are static so
# game/tests/test_run_report.gd can drive them on a fixture log.

const BUCKETS: Array = [[1, 5], [6, 10], [11, 15], [16, 20], [21, 25], [26, 30]]
const TICKS_PER_SEC := 60.0
const ENEMY_NEAR_U := 10.0        # risk 3: "no enemy within 10 u"
const CHAIN_SPLIT := 1.5          # risk 8: below / at-or-above x1.50
const WINDOW_TICKS := 240         # run_log.gd's 4.0 s chain window (mirrored, D-T081-5)
const CHAIN_CAP := 2.0            # economy.gd's x2.00 cap
const VOID_CODE := "D-VOID"       # sim/death.gd VOID_CODE

# ------------------------------------------------------------------------------ entry --

func _init() -> void:
	var folder := "user://runs"
	var user := OS.get_cmdline_user_args()
	if user.size() > 0:
		folder = str(user[0]).replace("\\", "/")
	var paths := _list_logs(folder)
	if paths.is_empty():
		print("RUN REPORT: no .jsonl run logs under %s" % folder)
		quit(1)
		return
	print(report_text(paths))
	quit(0)


static func _list_logs(folder: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(folder)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".jsonl"):
			out.append(folder.path_join(name))
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


## The whole report as text. static: the test drives it on a fixture log.
## p_severity: {curse id: severity}; loaded from game/content/curses when null.
static func report_text(paths: Array, p_severity: Variant = null) -> String:
	var runs := collect(paths)
	var sev: Dictionary = {}
	if p_severity == null:
		sev = _load_severities()
	else:
		sev = p_severity
	var agg := aggregate(runs, sev)
	return render(agg, sev)


static func collect(log_paths: Array) -> Array:
	var runs: Array = []
	for p in log_paths:
		var rows := _parse_file(str(p))
		if not rows.is_empty():
			runs.append(_one_run(rows))
	return runs


static func _parse_file(p_path: String) -> Array:
	var out: Array = []
	var f := FileAccess.open(p_path, FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var line := f.get_line()
		if line.strip_edges() == "":
			continue
		var parsed: Variant = JSON.parse_string(line)
		if parsed is Dictionary:
			out.append(parsed)
	f.close()
	return out
# ---------------------------------------------------------------------------- one run --

## Walks one run's records in order and returns its derived events. The pairing rules
## (D-T081-4): a charge_spent is paired with the newest void_fall record at or before
## it (run_log.gd emits the two back-to-back at the same tick); a D-VOID death pairs
## the same way - the void fall IS the death's killer (death.gd).
static func _one_run(rows: Array) -> Dictionary:
	var run := {"deaths": [], "charges": [], "clears": [], "enters": [], "lobbies": [],
			"picks": [], "offers": [], "passes": [], "contacts": [],
			"levels_reached": -1, "seed": -1}
	var last_void: Variant = null
	var last_enter_t := -1
	var gold_t := -1000000          # the newest gold gift record's tick
	var gold_chain := 1.0           # the chain IN EFFECT after that gift (+increment)
	var lobby: Variant = null
	for r in rows:
		var rec: Dictionary = r
		var ty := str(rec.get("type", ""))
		var t := int(rec.get("t", 0))
		var lvn := int(rec.get("level", 0))
		var pl: Dictionary = rec.get("payload", {})
		if ty == "run_start":
			run["seed"] = int(pl.get("seed", -1))
		elif ty == "level_start":
			if lobby != null:
				lobby["next_t"] = t
		elif ty == "void_fall":
			last_void = {"t": t, "dist": float(pl.get("nearest_enemy_dist", -1.0)),
					"pushed": bool(pl.get("pushed_120", false))}
		elif ty == "charge_spent":
			var en := false
			var pu := false
			var paired := false
			if last_void != null and int(last_void["t"]) <= t:
				paired = true
				var d: float = float(last_void["dist"])
				en = d >= 0.0 and d <= ENEMY_NEAR_U
				pu = bool(last_void["pushed"])
			run["charges"].append({"t": t, "level": lvn, "enemy_near": en,
					"pushed": pu, "paired": paired})
		elif ty == "death":
			var en2 := false
			if str(pl.get("code", "")) == VOID_CODE and last_void != null \
					and int(last_void["t"]) <= t:
				en2 = float(last_void["dist"]) >= 0.0 and float(last_void["dist"]) <= ENEMY_NEAR_U
			run["deaths"].append({"t": t, "level": lvn, "code": str(pl.get("code", "")),
					"unseen": not bool(pl.get("on_screen", false)), "e_near": en2})
		elif ty == "level_clear":
			run["clears"].append({"level": lvn,
					"black_s": float(int(pl.get("black_ticks", 0))) / TICKS_PER_SEC,
					"gold_s": float(int(pl.get("gold_ticks", 0))) / TICKS_PER_SEC,
					"total_ticks": int(pl.get("total_ticks", 0)),
					"jumps": int(pl.get("jumps", -1)),
					"stepups": int(pl.get("stepups", -1))})
		elif ty == "beacon_enter":
			last_enter_t = t
			run["enters"].append({"t": t, "level": lvn,
					"tier": int(pl.get("overtime_tier", 0))})
		elif ty == "gift":
			if str(pl.get("phase", "")) == "gold":
				gold_t = t
				gold_chain = minf(float(int(round(float(pl.get("chain", 1.0)) * 100.0))
						+ 5) / 100.0, CHAIN_CAP)
		elif ty == "beacon_open":
			gold_t = -1000000      # the gold phase (and its chain) restart at x1.00
			gold_chain = 1.0
		elif ty == "mine_pass":
			run["passes"].append({"t": t, "level": lvn, "chain": _chain_at(t, gold_t, gold_chain)})
		elif ty == "mine_contact":
			run["contacts"].append({"t": t, "level": lvn, "outcome": str(pl.get("outcome", "")),
					"chain": _chain_at(t, gold_t, gold_chain)})
		elif ty == "lobby_enter":
			lobby = {"after": lvn, "kinds": [], "picks": [], "next_t": -1,
					"beacon_t": last_enter_t}
		elif ty == "offer":
			run["offers"].append({"level": lvn, "bay": str(pl.get("bay", "")),
					"ids": pl.get("ids", [])})
			if lobby != null and str(pl.get("bay", "")) != "CLASS":
				lobby["kinds"].append(str(pl.get("bay", "")))
		elif ty == "pick":
			var pick := {"level": lvn, "bay": str(pl.get("bay", "")),
					"id": str(pl.get("id", ""))}
			run["picks"].append(pick)
			if lobby != null:
				lobby["picks"].append(pick)
		elif ty == "lobby_exit" and lobby != null:
			run["lobbies"].append(lobby)
			lobby = null
		elif ty == "run_end":
			run["levels_reached"] = int(pl.get("level_reached", -1))
	return run


## The chain in effect at tick t (D-T081-5): the last gold gift's recorded chain
## (pre-increment) plus its increment, capped x2.00, while the 240-tick window holds;
## x1.00 otherwise (black phase, or the window was missed by the gift that would
## have advanced it). Approximation: chain_reset events are invisible in the
## records, so a curse/spend mid-window cannot be seen here.
static func _chain_at(t: int, gold_t: int, gold_chain: float) -> float:
	if gold_t >= 0 and t - gold_t <= WINDOW_TICKS:
		return gold_chain
	return 1.0


static func _bucket(level: int) -> int:
	for i in BUCKETS.size():
		var b: Array = BUCKETS[i]
		if level >= int(b[0]) and level <= int(b[1]):
			return i
	if level < 1:
		return 0
	return BUCKETS.size() - 1


static func _bucket_label(i: int) -> String:
	if i >= BUCKETS.size():
		return "overall  "
	return "%d-%d" % [int(BUCKETS[i][0]), int(BUCKETS[i][1])]


static func _new_stat() -> Dictionary:
	return {"charges": 0, "charges_terrain": 0, "charges_unpaired": 0,
			"deaths": 0, "deaths_terrain": 0, "deaths_unseen": 0, "run_deaths": 0,
			"black": [], "gold": [], "tiers": [], "clears": 0,
			"jump_rates": [], "step_rates": [], "jumps": 0, "stepups": 0,
			"mines_pass": 0, "mines_contact": 0, "mines_killed": 0,
			"m_low_events": 0, "m_low_deaths": 0, "m_high_events": 0, "m_high_deaths": 0,
			"lobbies": {}}



# ------------------------------------------------------------------------ aggregation --

## Folds a run into the bucket stats. Bucket index == the level's bucket; the last
## slot of the returned "buckets" array is the overall stat.
static func aggregate(runs: Array, p_sev: Dictionary = {}) -> Dictionary:
	var nb := BUCKETS.size() + 1
	var buckets: Array = []
	for i in nb:
		buckets.append(_new_stat())
	var curse_offers: Dictionary = {}
	var curse_picks: Dictionary = {}
	var up_offers: Dictionary = {}
	var up_picks: Dictionary = {}
	var brutal_runs := 0
	var levels: Array = []
	for r in runs:
		var run: Dictionary = r
		# block 8 bookkeeping first (needs the run's own end level)
		var reached := int(run["levels_reached"])
		if reached >= 0:
			levels.append(reached)
		var brutal_hit := false
		for p in run["picks"]:
			var pick: Dictionary = p
			var bay := str(pick["bay"])
			var id := str(pick["id"])
			if bay == "U":
				up_picks[id] = int(up_picks.get(id, 0)) + 1
			elif bay == "C":
				curse_picks[id] = int(curse_picks.get(id, 0)) + 1
				if not brutal_hit and str(p_sev.get(id, "")) == "brutal" \
						and reached >= 0 and reached <= int(pick["level"]) + 2:
					brutal_hit = true
					brutal_runs += 1
		for o in run["offers"]:
			var off: Dictionary = o
			var bay2 := str(off["bay"])
			var ids: Array = off["ids"]
			if bay2 == "U" or bay2 == "C":
				var target: Dictionary = up_offers if bay2 == "U" else curse_offers
				for raw in ids:
					target[str(raw)] = int(target.get(str(raw), 0)) + 1
		for c in run["charges"]:
			var ch: Dictionary = c
			for b in _into(buckets, int(ch["level"])):
				b["charges"] = int(b["charges"]) + 1
				if not bool(ch["paired"]):
					b["charges_unpaired"] = int(b["charges_unpaired"]) + 1
				if not bool(ch["enemy_near"]) and not bool(ch["pushed"]):
					b["charges_terrain"] = int(b["charges_terrain"]) + 1
		for d in run["deaths"]:
			var dd: Dictionary = d
			var terrain := str(dd["code"]) == VOID_CODE and not bool(dd["e_near"])
			for b2 in _into(buckets, int(dd["level"])):
				b2["deaths"] = int(b2["deaths"]) + 1
				b2["run_deaths"] = int(b2["run_deaths"]) + 1
				if terrain:
					b2["deaths_terrain"] = int(b2["deaths_terrain"]) + 1
				if bool(dd["unseen"]):
					b2["deaths_unseen"] = int(b2["deaths_unseen"]) + 1
		for c2 in run["clears"]:
			var cl: Dictionary = c2
			for b3 in _into(buckets, int(cl["level"])):
				b3["black"].append(float(cl["black_s"]))
				b3["gold"].append(float(cl["gold_s"]))
				b3["clears"] = int(b3["clears"]) + 1
				if int(cl["jumps"]) >= 0 and int(cl["total_ticks"]) > 0:
					var mins := float(int(cl["total_ticks"])) / 3600.0
					b3["jumps"] = int(b3["jumps"]) + int(cl["jumps"])
					b3["jump_rates"].append(float(int(cl["jumps"])) / mins)
					if int(cl["stepups"]) >= 0:
						b3["stepups"] = int(b3["stepups"]) + int(cl["stepups"])
						b3["step_rates"].append(float(int(cl["stepups"])) / mins)
		for e in run["enters"]:
			var be: Dictionary = e
			for b5 in _into(buckets, int(be["level"])):
				b5["tiers"].append(int(be["tier"]))
		for l in run["lobbies"]:
			var lb: Dictionary = l
			var b4: Dictionary = buckets[_bucket(int(lb["after"]) + 1)]
			var combo := "+".join(lb["kinds"])
			if combo == "":
				combo = "none"
			var m: Dictionary = b4["lobbies"]
			m[combo] = int(m.get(combo, 0)) + 1
			var m7: Dictionary = buckets[BUCKETS.size()]["lobbies"]
			m7[combo] = int(m7.get(combo, 0)) + 1
		for mp in run["passes"]:
			var mpd: Dictionary = mp
			for b8 in _into(buckets, int(mpd["level"])):
				_mine_event(b8, true, false, float(mpd["chain"]))
		for mc in run["contacts"]:
			var mc2: Dictionary = mc
			var killed := str(mc2["outcome"]) == "killed"
			for b9 in _into(buckets, int(mc2["level"])):
				_mine_event(b9, false, killed, float(mc2["chain"]))
	return {"buckets": buckets, "overall": buckets[BUCKETS.size()], "runs": runs.size(),
			"levels": levels, "curse_offers": curse_offers, "curse_picks": curse_picks,
			"up_offers": up_offers, "up_picks": up_picks, "brutal_runs": brutal_runs}


## The two stat buckets a record accumulates into: its level's bucket AND the overall
## (the array's last slot). Every accumulation site writes both - the overall row is
## the sum of the buckets, never a separate pass.
static func _into(buckets: Array, level: int) -> Array:
	return [buckets[_bucket(level)], buckets[BUCKETS.size()]]


static func _mine_event(b: Dictionary, p_pass: bool, killed: bool, chain: float) -> void:
	if p_pass:
		b["mines_pass"] = int(b["mines_pass"]) + 1
	else:
		b["mines_contact"] = int(b["mines_contact"]) + 1
	var low := chain < CHAIN_SPLIT
	if low:
		b["m_low_events"] = int(b["m_low_events"]) + 1
		if killed:
			b["m_low_deaths"] = int(b["m_low_deaths"]) + 1
	else:
		b["m_high_events"] = int(b["m_high_events"]) + 1
		if killed:
			b["m_high_deaths"] = int(b["m_high_deaths"]) + 1
	if killed:
		b["mines_killed"] = int(b["mines_killed"]) + 1


static func _median(vals: Array) -> float:
	if vals.is_empty():
		return 0.0
	var s := vals.duplicate()
	s.sort()
	var n := int(s.size())
	if n % 2 == 1:
		return float(s[n / 2])
	return (float(s[n / 2 - 1]) + float(s[n / 2])) / 2.0


static func _pct(part: int, whole: int) -> float:
	if whole <= 0:
		return 0.0
	return 100.0 * float(part) / float(whole)


static func _load_severities() -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open("res://content/curses")
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.ends_with(".json"):
			var f := FileAccess.open("res://content/curses".path_join(name), FileAccess.READ)
			if f != null:
				var parsed: Variant = JSON.parse_string(f.get_as_text())
				f.close()
				if parsed is Dictionary:
					out[str((parsed as Dictionary).get("id", ""))] = \
							str((parsed as Dictionary).get("severity", ""))
		name = dir.get_next()
	dir.list_dir_end()
	return out


# ---------------------------------------------------------------------------- render --

static func render(agg: Dictionary, p_sev: Dictionary = {}) -> String:
	var L: Array[String] = []
	var buckets: Array = agg["buckets"]
	var runs_n := int(agg["runs"])
	L.append("FUN-RISK REPORT (T-081, research/fable-funrisks.md; INFORMATION ONLY - no pass/fail, no threshold)")
	L.append("runs: %d" % runs_n)
	# 1. terrain vs enemy (risk 3)
	L.append("1. terrain vs enemy (risk 3)")
	for i in buckets.size():
		var b: Dictionary = buckets[i]
		var ch := int(b["charges"])
		var ctn := int(b["charges_terrain"])
		var de := int(b["deaths"])
		var dtn := int(b["deaths_terrain"])
		L.append("  %-9s charges spent %6d | terrain-caused %5d (%5.1f%%) | enemy-caused %5d (%5.1f%%)"
				% [_row_label(i), ch, ctn, _pct(ctn, ch), ch - ctn, 100.0 - _pct(ctn, ch)])
		L.append("  %-9s deaths       %6d | terrain-caused %5d (%5.1f%%) | every other code %5d (%5.1f%%)"
				% [_row_label(i), de, dtn, _pct(dtn, de), de - dtn, 100.0 - _pct(dtn, de)])
	var unpaired := int(agg["overall"]["charges_unpaired"])
	if unpaired > 0:
		L.append("  note: %d charge_spent had no prior void_fall to pair with (counted terrain-caused)" % unpaired)
	# 2. restart time (risk 1)
	L.append("2. restart time (risk 1)")
	for i in buckets.size():
		var b2: Dictionary = buckets[i]
		L.append("  %-9s deaths ending a run %d" % [_row_label(i), int(b2["run_deaths"])])
	L.append("  not measurable from the current records: death.t and the next run's first controllable")
	L.append("  level-1 tick live in two different run clocks; T-080 records carry sim ticks only (no")
	L.append("  wall-clock time) and the loading screen + lobby walk consume no sim ticks")
	# 3. unseen deaths (risk 2)
	L.append("3. unseen deaths (risk 2)")
	for i in buckets.size():
		var b3: Dictionary = buckets[i]
		var de3 := int(b3["deaths"])
		var un := int(b3["deaths_unseen"])
		L.append("  %-9s deaths %6d | killer on screen = no %5d (%5.1f%%)"
				% [_row_label(i), de3, un, _pct(un, de3)])
	# 4. level length and pressure (risk 4)
	L.append("4. level length and pressure (risk 4)")
	for i in buckets.size():
		var b4: Dictionary = buckets[i]
		L.append("  %-9s black-phase median %6.1f s (n=%d) | gold-phase median %6.1f s (n=%d) | overtime tier at beacon entry median %d (n=%d)"
				% [_row_label(i), _median(b4["black"]), (b4["black"] as Array).size(),
				_median(b4["gold"]), (b4["gold"] as Array).size(),
				_median_i(b4["tiers"]), (b4["tiers"] as Array).size()])
	# 5. stair rate (risk 5)
	L.append("5. stair rate (risk 5)")
	for i in buckets.size():
		var b5: Dictionary = buckets[i]
		L.append("  %-9s median jumps/min %6.1f (n=%d levels, %d jumps) | median step-ups/min %6.1f (n=%d, %d step-ups)"
				% [_row_label(i), _median(b5["jump_rates"]), (b5["jump_rates"] as Array).size(),
				int(b5["jumps"]), _median(b5["step_rates"]), (b5["step_rates"] as Array).size(),
				int(b5["stepups"])])
	# 6. lobby time (risk 7)
	L.append("6. lobby time (risk 7)")
	for i in buckets.size():
		var b6: Dictionary = buckets[i]
		var parts: Array[String] = []
		var total_lb := 0
		var m6: Dictionary = b6["lobbies"]
		for k in m6.keys():
			total_lb += int(m6[k])
		var keys: Array = m6.keys()
		keys.sort()
		for k2 in keys:
			parts.append("%s %d" % [str(k2), int(m6[k2])])
		var tail := "none offered" if parts.is_empty() else ", ".join(parts)
		L.append("  %-9s lobbies %4d | by offered bays: %s" % [_row_label(i), total_lb, tail])
	L.append("  not measurable from the current records: the lobby consumes no sim ticks (the hall")
	L.append("  walk and the hold-F confirm are real time, never simulated), so beacon_enter ->")
	L.append("  level_start carries only the 0-2 gold-phase tail ticks")
	# 7. mine margin (risk 8)
	L.append("7. mine margin (risk 8)")
	for i in buckets.size():
		var b7: Dictionary = buckets[i]
		var ev7 := int(b7["mines_pass"]) + int(b7["mines_contact"])
		var kd := int(b7["mines_killed"])
		var evl := int(b7["m_low_events"]) + int(b7["m_high_events"])
		var kdl := int(b7["m_low_deaths"]) + int(b7["m_high_deaths"])
		L.append("  %-9s mine_pass %4d + mine_contact %3d = %4d | mine deaths %3d | deaths per 100 (pass+contact) %5.1f"
				% [_row_label(i), int(b7["mines_pass"]), int(b7["mines_contact"]), ev7, kd, _per100(kd, ev7)])
		L.append("  %-9s chain <  x%.2f: events %4d, deaths %3d, deaths per 100 (pass+contact) %5.1f | at-or-above: events %4d, deaths %3d, %5.1f"
				% [_row_label(i), CHAIN_SPLIT, int(b7["m_low_events"]), int(b7["m_low_deaths"]),
				_per100(int(b7["m_low_deaths"]), int(b7["m_low_events"])),
				int(b7["m_high_events"]), int(b7["m_high_deaths"]),
				_per100(int(b7["m_high_deaths"]), int(b7["m_high_events"]))])
	L.append("  not measurable from the current records: walkway width 1 / 2 / platform (no slot width")
	L.append("  in the records - level_start would need the mine slots' widths)")
	# 8. content health (risk 10)
	L.append("8. content health (risk 10)")
	L.append("  runs %d | level reached: median %.0f, maximum %d" % [runs_n,
			_median(agg["levels"]), _arr_max(agg["levels"])])
	L.append("  curse picks (picks / offers shown, all lobbies; rate = picks / offers):")
	_content_rows(L, agg["curse_offers"], agg["curse_picks"], p_sev)
	L.append("  upgrade purchases (picks / offers shown; the T-060 bot buys nothing - zeros expected):")
	_content_rows(L, agg["up_offers"], agg["up_picks"], {})
	var br := int(agg["brutal_runs"])
	L.append("  runs ending within two levels of a Brutal pick: %d/%d (%.1f%%)" % [br, runs_n, _pct(br, runs_n)])
	return "\n".join(L) + "\n"


static func _row_label(i: int) -> String:
	if i >= BUCKETS.size():
		return "overall"
	var b: Array = BUCKETS[i]
	return "%d-%d" % [int(b[0]), int(b[1])]


static func _median_i(vals: Array) -> int:
	return int(round(_median(vals)))


static func _per100(dead: int, events: int) -> float:
	if events <= 0:
		return 0.0
	return 100.0 * float(dead) / float(events)


static func _arr_max(vals: Array) -> int:
	if vals.is_empty():
		return 0
	var best := int(vals[0])
	for v in vals:
		if int(v) > best:
			best = int(v)
	return best


static func _content_rows(L: Array[String], offers: Dictionary, picks: Dictionary,
		p_sev: Dictionary) -> void:
	var ids: Array = []
	for k in offers.keys():
		ids.append(str(k))
	for k2 in picks.keys():
		if not ids.has(str(k2)):
			ids.append(str(k2))
	ids.sort()
	if ids.is_empty():
		L.append("      (none recorded)")
		return
	for id in ids:
		var sid := str(id)
		var o := int(offers.get(sid, 0))
		var p := int(picks.get(sid, 0))
		var sev: String = str(p_sev.get(sid, ""))
		var sev_txt := " [%s]" % sev if sev != "" else ""
		L.append("      %s%s: %d picks / %d offers (%.1f%%)" % [sid, sev_txt, p, o, _pct(p, o)])


