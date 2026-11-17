extends RefCounted
#
# test_bot_run.gd (ticket T-060): the bot tool exists and its report format parses.
#   - the tool runs a 3-run smoke probe twice with the same seed set
#     (is determinism of the numbers);
#   - its band table has exactly the DESIGN.md section 9 rows for levels 6 / 12 / 18,
#     each with a reach-rate, the band label, and PASS / FAIL;
#   - the probe never prints "SKIP" and every run line prints its seed.
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