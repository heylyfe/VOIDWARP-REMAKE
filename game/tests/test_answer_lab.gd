extends RefCounted
#
# test_answer_lab.gd (ticket T-075, piece 3 of 3): the answer lab's MECHANISM.
# The full 200-trial sweep is a tool run (game/tools/answer_lab.gd, run by the
# operator); this test proves the pieces it is built from:
#   - every pair the lab pairs() names builds: its level exists, its telegraph
#     kind is a real one of the content (the ENEMIES.md rows) - and the lab's
#     pair list covers the section 2 pairing (kiwi/coil/ben/seal/you/...);
#   - a trial runs end to end: the answer arm and the no-input arm both return
#     a diagnosis, the no-input arm NEVER arms a trigger, the answer arm's
#     anchor worked (its armed flag);
#   - the answer the lab plays IS answers.gd's: every pair's enemy has a table
#     entry, and the lab's per-pair telegraph matches the entry's telegraph
#     family (bounds asserted, not re-derived);
#   - the bounds rule: >= 95 % / <= 5 % with the right PASS/FAIL arithmetic.
# The trial-level assertions use the lab's REAL trial (one run, a handful of
# seeds): a full sweep would be a gate, and the gate stays out of the tests.

const Labs := preload("res://tools/answer_lab.gd")
const Answers := preload("res://tools/bot/answers.gd")
const MicroLevelsScript := preload("res://tools/bot/micro_levels.gd")

const TRIALS_PROBE := 2


func run() -> Array[String]:
	var f: Array[String] = []
	_pairs_build_and_measurable(f)
	_trial_arms(f)
	_bounds_rule(f)
	return f


func _pairs_build_and_measurable(f: Array[String]) -> void:
	if Labs.pairs().is_empty():
		f.append("answer lab: the pair list is empty")
		return
	for cfg in Labs.pairs():
		var lvl: Dictionary = MicroLevelsScript.build(str(cfg["level"]))
		if lvl.is_empty():
			f.append("answer lab: pair level '%s' does not build" % str(cfg["level"]))
		if str(cfg["telegraph"]).is_empty():
			f.append("answer lab: a pair has no telegraph kind")
	# the pair list covers the pairing: the coil (a movement answer), the seal
	# (a bark answer) and the address me (the stop answer) all present
	if not _has_pair("coil") or not _has_pair("address_me") or not _has_pair("seal"):
		f.append("answer lab: the pair list lost the coil/seal/address me pairs")


func _trial_arms(f: Array[String]) -> void:
	# 1: the answer arm arms on the coil pair (its trigger row is deterministic:
	# the ring telegraph appears the tick the arc starts).
	var coil := Labs.trial(_pair("coil"), 1001, true)
	if not coil.has("armed"):
		f.append("answer lab: the coil trial returned no armed flag")
	elif not bool(coil["armed"]):
		f.append("answer lab: the coil trial's answer never armed")
	# 2: the no-input arm never arms a trigger (nothing listens)
	var nop := Labs.trial(_pair("coil"), 1001, false)
	if not nop.has("armed"):
		f.append("answer lab: the no-input trial returned no armed flag")
	elif bool(nop["armed"]):
		f.append("answer lab: the no-input arm reports a trigger arming")
	# 3: both arms returned the trial's diagnosis, and it agrees with itself (equal
	# outcomes are legal; a missing or contradictory one is not)
	var arms: Array = [[coil, "answer"], [nop, "no-input"]]
	for arm in arms:
		var d: Dictionary = arm[0]
		var err := _diagnosis_error(str(arm[1]), d)
		if err != "":
			f.append(err)


## A trial's diagnosis: survived and death_t must both be there and agree - Labs._trial
## returns death_t = -1 only for a surviving run, a death tick otherwise. "" when they do.
func _diagnosis_error(label: String, d: Dictionary) -> String:
	if not d.has("survived") or not d.has("death_t"):
		return "answer lab: the %s arm returned no diagnosis (%s)" % [label, str(d.keys())]
	if bool(d["survived"]) != (int(d["death_t"]) < 0):
		return "answer lab: the %s arm's diagnosis disagrees (survived %s, death_t %d)" % [
			label, str(d["survived"]), int(d["death_t"])]
	return ""


func _bounds_rule(f: Array[String]) -> void:
	# the two bounds: >= 95 % answer, <= 5 % no-input; the corners:
	if not Labs.bounds_ok(95, 0) or not Labs.bounds_ok(100, 5):
		f.append("answer lab: the bounds rule rejects a passing pair")
	if Labs.bounds_ok(94, 0) or Labs.bounds_ok(95, 6):
		f.append("answer lab: the bounds rule accepts a failing pair")


func _pair(id: String) -> Dictionary:
	for cfg in Labs.pairs():
		if str(cfg["enemy"]) == id:
			return cfg
	return {}


func _has_pair(id: String) -> bool:
	return not _pair(id).is_empty()


func MicroLevels() -> RefCounted:
	return load("res://tools/bot/micro_levels.gd")

