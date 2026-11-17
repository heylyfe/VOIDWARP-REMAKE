extends RefCounted
#
# test_run_report.gd - T-081's proof: tools/run_report.gd parses a REAL T-080 run log
# (a file game/app/run_log.gd itself wrote) and prints all eight fun-risk blocks IN
# ORDER, the terrain-vs-enemy split first. The report is INFORMATION - the test also
# asserts the honest-fallback property: a block whose records cannot carry its numbers
# (2 restart time, 6 lobby time, 7's walkway widths) prints its
# "not measurable from the current records" line instead of an invented number.
#
# The fixture log is synthesized through run_log.gd's own public surface (the same
# events the sim and the app emit; test_run_log.gd's _chain_unit_pass idiom) because
# a bot cannot be trusted to survive three levels (D-T080-9). The three levels feed
# real counts for every measurable block: a terrain-caused void fall (no enemy within
# 10 u, no push in the 120-tick window), an unseen mine death behind the x1.50 chain
# line, level timings, a 2-level overtime, jump/step-up counters, and one curse pick.

const ReportScript := preload("res://tools/run_report.gd")
const LogScript := preload("res://app/run_log.gd")

const RUN_SEED := 4242


func run() -> Array[String]:
	var failures: Array[String] = []
	var lg := LogScript.new()
	lg.run_started(RUN_SEED, "dasher", 0)
	_write_fixture(lg)
	lg.run_finished(3, 530)
	lg.close()
	var text := ReportScript.report_text([lg.path])
	_clean(lg.path)
	_assert(text, failures)
	return failures


## Three levels of records, in the order the log really emits them.
func _write_fixture(lg) -> void:
	# ---- level 1: a clean clear with a terrain-caused pip --------------------------------
	lg.level_started(1, 3, 3, 0, 2)
	lg.feed_tick([{"type": "gift_collected", "player": 0, "slot": 0, "phase": "black"}])
	lg.feed_tick([{"e": "jump"}])
	lg.feed_tick([{"e": "step_up", "hu": 1}])
	lg.feed_tick([{"type": "gift_collected", "player": 0, "slot": 1, "phase": "black"}])
	# the terrain-caused pip: no enemy body within 30 u, no push in the 120-tick window
	lg.feed_tick([{"e": "void_fall", "charges": 1, "charges_before": 2, "tile": "3,0,2",
			"nearest_enemy_dist": 30.0}])
	lg.feed_tick([{"type": "beacon_opened", "player": -1}])
	lg.feed_tick([{"e": "overtime_tier", "tier": 1}])
	lg.feed_tick([{"type": "gift_collected", "player": 0, "slot": 0, "phase": "gold"}])
	lg.feed_tick([{"type": "beacon_enter", "player": 0, "charges": 2, "charges_before": 1}])
	lg.feed_tick([{"type": "level_complete", "player": 0}])
	# ---- the lobby after level 1: an E bay and a U bay, one enemy vote -------------------
	lg.lobby_entered(1)
	lg.offer_shown("E", ["coil", "kiwi_cat", "seal"])
	lg.offer_shown("U", ["sure_foot"])
	lg.feed_lobby([{"type": "altar_selected", "bay": "E", "id": "coil", "cost": 0}])
	lg.lobby_left()
	# ---- level 2: the curse lobby, mines on both sides of the chain split ----------------
	lg.level_started(2, 3, 2, 2, 1)
	lg.lobby_entered(1)
	lg.offer_shown("E", ["coil"])
	lg.offer_shown("C", ["brittle", "cold_start"])
	lg.feed_lobby([{"type": "altar_selected", "bay": "C", "id": "brittle", "cost": 45}])
	lg.lobby_left()
	lg.feed_tick([{"type": "mine_pass", "slot": 0, "closest": 1.2}])   # black phase: chain x1.00
	lg.feed_tick([{"type": "mine_pass", "slot": 1, "closest": 1.1}])
	lg.feed_tick([{"type": "gift_collected", "player": 0, "slot": 0, "phase": "black"}])
	lg.feed_tick([{"type": "beacon_opened", "player": -1}])
	for i in range(11):
		lg.feed_tick([{"type": "gift_collected", "player": 0, "slot": 0, "phase": "gold"}])
	lg.feed_tick([{"e": "overtime_tier", "tier": 2}])
	lg.feed_tick([{"type": "mine_pass", "slot": 2, "closest": 1.05}])   # chain now x1.55
	lg.feed_tick([{"type": "mine_contact", "slot": 2}])   # nothing else in tick: killed
	lg.feed_tick([{"e": "death", "killer": "gift Larper (Tripmine)", "code": "D-MINE",
			"on_screen": false, "charges": 0, "last_light": ""}])
	lg.feed_tick([{"type": "beacon_enter", "player": 0, "charges": 1, "charges_before": 1}])
	lg.feed_tick([{"type": "level_complete", "player": 0}])
	# ---- level 3: entered, immediately dead to the void at 0 charges (unseen) ------------
	lg.level_started(3, 2, 2, 0, 1)
	lg.feed_tick([{"e": "void_fall", "charges": 0, "charges_before": 0, "tile": "5,1,1",
			"nearest_enemy_dist": 24.0}])
	lg.feed_tick([{"e": "death", "killer": "void", "code": "D-VOID", "on_screen": false,
			"charges": 0, "last_light": ""}])


func _assert(text: String, failures: Array[String]) -> void:
	# the eight block headings, in the ticket's exact order, terrain first
	var headings := ["1. terrain vs enemy (risk 3)", "2. restart time (risk 1)",
			"3. unseen deaths (risk 2)", "4. level length and pressure (risk 4)",
			"5. stair rate (risk 5)", "6. lobby time (risk 7)",
			"7. mine margin (risk 8)", "8. content health (risk 10)"]
	var prev := -1
	for h in headings:
		var idx := text.find(str(h))
		if idx < 0:
			failures.append("the report never printed the block '%s'" % str(h))
		elif idx < prev:
			failures.append("the block '%s' printed out of order" % str(h))
		else:
			prev = idx
	if not text.contains("runs: 1"):
		failures.append("the report header does not read runs: 1")
	# block 1: the fixture's own terrain-caused pips (levels 1 and 3) and the D-VOID death
	if not text.contains("terrain-caused     2 (100.0%)"):
		failures.append("block 1: the terrain-caused charge count is not the fixture's 2")
	if not text.contains("killer on screen = no     2 (100.0%)"):
		failures.append("block 3: unseen deaths is not the fixture's 2")
	# block 5: the jump/step-up counters ride level_clear (D-T081-1)
	if not text.contains("step-ups/min"):
		failures.append("block 5: no step-up rate")
	# the honest-fallback property: the three not-measurable lines must be printed
	var honest := 0
	for line in text.split("\n"):
		if line.contains("not measurable from the current records"):
			honest += 1
	if honest < 3:
		failures.append("expected 3 not-measurable lines (blocks 2 / 6 / 7), got %d" % honest)


## Removes the fixture log (test_run_log.gd's own cleanup-idiom shape).
func _clean(p_path: String) -> void:
	var dir := DirAccess.open("user://runs")
	if dir != null and p_path.begins_with("user://runs/"):
		dir.remove(p_path.get_file())
