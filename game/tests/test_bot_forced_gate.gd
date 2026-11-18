extends RefCounted
#
# test_bot_forced_gate.gd (audit A12). The bot's lobby pass (tools/bot_run.gd
# _resolve_lobby) can leave a lobby with the Descent Gate still CLOSED: a C bay whose
# draw is empty (every eligible curse already held at max stacks) and a tithe the purse
# cannot pay (DESIGN.md section 7: pick a curse or pay the tithe). The bot does not stall
# there - play_run goes on into the next level - so that level must be labelled, not
# passed off as an ordinary one. Proves:
#   - _resolve_lobby returns false for exactly that lobby, true when the purse can pay;
#   - _note_forced_gate records the level in the row's list;
#   - summarize() counts the run and format_report() prints the count line, while the
#     three band rows stay exactly as test_bot_run.gd parses them.

const BotRun := preload("res://tools/bot_run.gd")
const ContentApiScript := preload("res://core/content_api.gd")

const C_LEVEL := 2      # data/offering_schedule.json: after level 2 the only bay is C


func run() -> Array[String]:
	var f: Array[String] = []
	var api := ContentApiScript.load()
	if not bool(api.is_ok()):
		f.append("content api boot failed: %s" % " / ".join(api.boot_errors()))
		return f
	_lobby_reports_closed_gate(f, api)
	_row_and_report(f)
	return f


## Every curse held at its max stacks: the C draw is empty whatever the level and votes.
func _all_curses_maxed(api: RefCounted) -> Dictionary:
	var held: Dictionary = {}
	for cid in api.curse_ids():
		held[str(cid)] = int((api.curse(str(cid)) as Dictionary).get("max_stacks", 1))
	return held


func _ledger(api: RefCounted, purse: int) -> Dictionary:
	return {
		"votes": {"thicc_ben": 1}, "curses": _all_curses_maxed(api), "stacks": {},
		"purse": purse, "tithes": 0, "hunger": 0, "last_vote": "thicc_ben",
		"class": "dasher",
	}


func _lobby_reports_closed_gate(f: Array[String], api: RefCounted) -> void:
	# broke: the empty C bay cannot be picked and the 100 g tithe cannot be paid
	var broke: Dictionary = _ledger(api, 0)
	if bool(BotRun._resolve_lobby(api, broke, C_LEVEL, 4242)):
		f.append("empty C bay + unaffordable tithe: _resolve_lobby reported an open gate")
	if int(broke["purse"]) != 0 or int(broke["tithes"]) != 0:
		f.append("the broke lobby charged something: purse %d tithes %d"
				% [int(broke["purse"]), int(broke["tithes"])])
	# rich: the same empty bay, tithe paid, gate open - the ordinary path stays ordinary
	var rich: Dictionary = _ledger(api, 500)
	if not bool(BotRun._resolve_lobby(api, rich, C_LEVEL, 4242)):
		f.append("empty C bay + affordable tithe: _resolve_lobby reported a closed gate")
	if int(rich["tithes"]) != 1 or int(rich["purse"]) != 400:
		f.append("the tithe was not paid once at 100 g: purse %d tithes %d"
				% [int(rich["purse"]), int(rich["tithes"])])


func _row_and_report(f: Array[String]) -> void:
	var forced: Array = []
	BotRun._note_forced_gate(forced, 4242, C_LEVEL)
	if forced != [C_LEVEL]:
		f.append("_note_forced_gate did not record level %d: %s" % [C_LEVEL, str(forced)])
	var rows := [
		{"reached_6": false, "reached_12": false, "reached_18": false, "outcome": "dead",
			"entered": 3, "class": "dasher", "forced_gate": forced},
		{"reached_6": true, "reached_12": false, "reached_18": false, "outcome": "dead",
			"entered": 7, "class": "glider", "forced_gate": []},
		{"reached_6": false, "reached_12": false, "reached_18": false, "outcome": "stuck",
			"entered": 2, "class": "athletic"},   # a row from before A12: no key at all
	]
	var agg: Dictionary = BotRun.summarize(rows)
	if int(agg.get("forced_gate", -1)) != 1:
		f.append("summarize counted %s forced-gate runs, want 1" % str(agg.get("forced_gate")))
	agg["seed_base"] = 1
	var report: String = BotRun.format_report(agg)
	if report.find("forced open-gate runs: 1") < 0:
		f.append("format_report has no forced open-gate count line:\n%s" % report)
	var band_re := RegEx.create_from_string("^level (6|12|18):")
	var bands := 0
	for line in report.split("\n"):
		if band_re.search(line):
			bands += 1
	if bands != 3:
		f.append("format_report has %d band rows, want 3:\n%s" % [bands, report])
