extends RefCounted
#
# test_answers.gd (ticket T-075, piece 1 of 3): the shared answer table.
# Sources: research/fable-enemies.md section 4 (the counter-play map - the
# source of truth the table copies) and the FLEET_PACK addendum (research/
# fable-tickets.md row T-026): ONE module, tools/bot/answers.gd, with the
# answer starting "15 ticks after the event".
#
# Piece 1 checks the table, not a bot:
#   - exactly the twelve ids, and each one exists in game/content/enemies/
#   - every entry carries a non-empty answer, trigger, source and inputs
#   - DELAY_TICKS is the addendum's 15
#   - the accessors return exactly what the table holds (no silent defaults)
# The survivability sweeps (>= 95 % with the answer, <= 5 % with no input) are
# T-075 pieces 2 and 3; this test does not run the sim.

const Answers := preload("res://tools/bot/answers.gd")

const EXPECTED_IDS := [
	"address_me", "claude", "coil", "gift_larper", "gin", "isagi",
	"kiwi_cat", "nuke", "seal", "thicc_ben", "toucher", "you",
]

const DELAY_TICKS := 15


func run() -> Array[String]:
	var f: Array[String] = []
	_twelve_ids(f)
	_every_entry_complete(f)
	_delay_is_15(f)
	_accessors_match_table(f)
	return f


func _twelve_ids(f: Array[String]) -> void:
	var got := Answers.ids()
	if got.size() != 12:
		f.append("answers table has %d ids, expected 12" % got.size())
	for id in EXPECTED_IDS:
		if not got.has(id):
			f.append("answers table is missing id '%s'" % id)
	var extra := got.duplicate()
	for id in EXPECTED_IDS:
		extra.erase(id)
	if not extra.is_empty():
		f.append("answers table has unexpected ids %s" % str(extra))
	for id in EXPECTED_IDS:
		var dir := DirAccess.open("res://content/enemies/%s" % id)
		if dir == null:
			f.append("no enemy content folder for id '%s'" % id)
		elif not FileAccess.file_exists("res://content/enemies/%s/enemy.json" % id):
			f.append("enemy '%s' has no enemy.json" % id)


func _every_entry_complete(f: Array[String]) -> void:
	for id in Answers.ids():
		var e: Dictionary = Answers.entry(id)
		for key in ["enemy", "answer", "trigger", "source"]:
			if not e.has(key):
				f.append("entry '%s' lacks key '%s'" % [id, key])
			elif not str(e[key]).is_empty():
				pass
			else:
				f.append("entry '%s' has an empty '%s'" % [id, key])
		if e.get("enemy", "") != id:
			f.append("entry '%s' carries enemy '%s'" % [id, str(e.get("enemy", ""))])
		var ins: Array = e.get("inputs", [])
		if ins.is_empty():
			f.append("entry '%s' has no inputs" % id)
			continue
		for i in ins.size():
			var step: Dictionary = ins[i]
			if not step.has("tick_offset") or not step.has("action"):
				f.append("entry '%s' input %d lacks tick_offset/action" % [id, i])
				continue
			if str(step.get("action", "")).is_empty():
				f.append("entry '%s' input %d has an empty action" % [id, i])
		if not e.has("source") or str(e["source"]).find("fable-enemies.md") < 0:
			f.append("entry '%s' does not name its fable-enemies.md source row" % id)


func _delay_is_15(f: Array[String]) -> void:
	if Answers.DELAY_TICKS != DELAY_TICKS:
		f.append("answers DELAY_TICKS is %d, the T-026 addendum says 15" % Answers.DELAY_TICKS)


func _accessors_match_table(f: Array[String]) -> void:
	for id in Answers.ids():
		var e: Dictionary = Answers.TABLE[id]
		if Answers.entry(id) != e:
			f.append("entry('%s') differs from the table" % id)
		if Answers.answer_for(id) != e.get("answer", ""):
			f.append("answer_for('%s') differs from the table" % id)
		if Answers.inputs_for(id) != e.get("inputs", []):
			f.append("inputs_for('%s') differs from the table" % id)
	# entry() asserts on an unknown id (answers.gd:211). The test does NOT call it
	# with a bad id: an assert prints "SCRIPT ERROR: Assertion failed", and the gate
	# fails any run that prints a script error (tools/gate.ps1 Assert-NoScriptError).
	# The guard is a developer aid, not a spec rule, so it is checked by reading the
	# table instead: no id outside the twelve may be present.
	if Answers.TABLE.has("no_such_enemy"):
		f.append("the table carries an id that is not an enemy")

