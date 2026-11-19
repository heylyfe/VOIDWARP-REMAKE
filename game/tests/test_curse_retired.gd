extends RefCounted
#
# test_curse_retired.gd (W11-E): the retired-curse contract.
#
# One curse of the full set is marked "retired": true in its content file. It is retired
# BY DESIGN (DESIGN.md section 6 shows the burst it would grant does not apply to the kiwi
# cat, J6; the cat never dashes or lunges and its behavior cancels any active burst), so
# the curse can never be made to work and is not supposed to. The real player-facing risk
# this test pins down: can a retired curse still be OFFERED in a lobby - a spent curse slot
# for nothing - and does a retired curse held in the ledger disturb the run?
#
# The proof, all headless:
#   1. SEED SWEEP through the real offer path (Intermission.create -> the C bay altars, and
#      the free reroll plinth through apply_select): across 200 seeds x 17 levels whose C
#      bay exists (rows past 30 exercise the repeat block), with the enemy vote that makes
#      the retired entry fully eligible on data alone, the retired id must never appear on
#      an altar - not on the initial draw, not after the reroll.
#   2. NEGATIVE CONTROL: the same sweep against an eligibility oracle with only the
#      "retired" clause removed (RetiredBlindApi, below) MUST find the retired id, or the
#      sweep is not capable of seeing it and the green above means nothing.
#   3. FORCED-HELD WORLD (world.build() + world.step()): a ledger carrying the retired id
#      builds a level whose dispatcher holds no module for it; the run is step-for-step
#      identical to the un-cursed control; nothing errors and no hook fires.
#   4. COUNT HONESTY: every curse JSON with "script": true either has its module on disk
#      or is marked "retired": true - and the count of applicable script curses is exactly
#      the count of modules on disk. Both numbers are asserted here.
#
# This test fixes nothing; it only reports.

const ContentApiScript := preload("res://core/content_api.gd")
const RegistryScript := preload("res://core/registry.gd")
const Intermission := preload("res://sim/intermission.gd")
const WorldScript := preload("res://app/world.gd")

const CURSES_DIR := "res://content/curses"
const RETIRED_ID := "zoomies"
const KIWI_VOTE := {"kiwi_cat": 1}   # the vote that makes the retired entry eligible on data
const SEEDS := 200
const DT := 1.0 / 60.0
const LEVEL := 5
const WORLD_SEED := 1
const WORLD_TICKS := 300
# Levels whose lobby lights a C bay, all >= 3 so the retired entry passes min_level; the
# kiwi vote above covers its enemy gate. 34 / 36 / 38 land in repeat rows 28 / 30 / 26.
const C_LEVELS: Array[int] = [4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 34, 36, 38]


## Negative-control oracle: the shipped eligibility rule with ONLY the "retired" clause
## removed. Everything else (min_level, the enemy vote) is identical, so the sweep through
## this api passes/fails on exactly the clause under test.
class RetiredBlindApi extends ContentApiScript:
	func eligible_curses(p_level: int, votes: Dictionary) -> Array[String]:
		var out: Array[String] = []
		for id in curse_ids():
			var c: Dictionary = curse(id)
			if int(c.get("min_level", 1)) > p_level:
				continue
			var req: Variant = c.get("requires_enemy")
			if req != null and int(votes.get(str(req), 0)) < 1:
				continue
			out.append(id)
		return out


func run() -> Array[String]:
	var f: Array[String] = []
	var api := ContentApiScript.load()
	if not bool(api.is_ok()):
		f.append("content api boot failed: %s" % " / ".join(api.boot_errors()))
		return f
	_oracle(f, api)
	_sweep_main(f, api)
	_sweep_negative_control(f)
	_forced_held_world(f)
	_count_honesty(f)
	return f


## Direct oracle probe: the retired entry must not be eligible at any level, even at the
## ceiling row and even holding its enemy vote.
func _oracle(f: Array[String], api: RefCounted) -> void:
	for level in [0, 1, 2, 3, 8, 30, 38, 100]:
		var elig: Array[String] = api.eligible_curses(level, KIWI_VOTE)
		if elig.has(RETIRED_ID):
			f.append("eligible_curses(%d) offers the retired entry" % level)


## Sweep the real lobby path: every C bay in C_LEVELS, SEEDS seeds each; the initial draw
## plus one free reroll per lobby.
func _sweep_main(f: Array[String], api: RefCounted) -> void:
	var res := _sweep(api)
	for v in res["violations"]:
		f.append(v)
	if int(res["c_bays"]) != C_LEVELS.size() * SEEDS:
		f.append("sweep visited %d C bays, want %d - a C row is missing from the lobby" % [
				int(res["c_bays"]), C_LEVELS.size() * SEEDS])
	if int(res["draws"]) <= 0:
		f.append("sweep drew nothing - the offer path is broken")


## The negative control: with ONLY the retired clause removed, the identical sweep MUST
## surface the retired entry. If it does not, the sweep cannot see it and the main sweep
## proves nothing.
func _sweep_negative_control(f: Array[String]) -> void:
	var blind := RetiredBlindApi.new()
	blind._reg = RegistryScript.load_all()
	if not bool(blind.is_ok()):
		f.append("negative control api boot failed: %s" % " / ".join(blind.boot_errors()))
		return
	var elig: Array[String] = blind.eligible_curses(8, KIWI_VOTE)
	if not elig.has(RETIRED_ID):
		f.append("negative control oracle does not even list the retired entry at level 8 - it is not a valid control")
		return
	var res := _sweep(blind)
	if int(res["sightings"]) < 1:
		f.append("negative control: %d draws across %d seeds x %d levels and the retired entry never surfaced - the sweep is blind" % [
				int(res["draws"]), SEEDS, C_LEVELS.size()])


## {"c_bays": int, "draws": int, "sightings": int, "violations": Array[String]}
func _sweep(api: RefCounted) -> Dictionary:
	var counters := {"sightings": 0, "draws": 0}
	var c_bays := 0
	var violations: Array[String] = []
	for level in C_LEVELS:
		for seed_value in range(SEEDS):
			var p_seed := 1000 + seed_value
			var lb: RefCounted = Intermission.create(api, level, 0, p_seed, KIWI_VOTE)
			var c_bay := _c_bay(lb)
			if c_bay.is_empty():
				violations.append("level %d seed %d: no C bay in the lobby" % [level, p_seed])
				continue
			c_bays += 1
			_scan_bay("level %d seed %d (initial)" % [level, p_seed], c_bay, violations, counters)
			_reroll(lb, level, p_seed, violations, counters)
	return {"c_bays": c_bays, "draws": int(counters["draws"]),
			"sightings": int(counters["sightings"]), "violations": violations}


## The C bay of a created lobby ({} when the row lights none).
func _c_bay(lb: RefCounted) -> Dictionary:
	for bay in lb.bays:
		if str(bay.get("kind", "")) == "C":
			return bay
	return {}


## Scan one draw's altars: bump the counters, record any retired appearance.
func _scan_bay(label: String, c_bay: Dictionary, violations: Array[String],
		counters: Dictionary) -> void:
	counters["draws"] = int(counters["draws"]) + 1
	for a in c_bay["altars"]:
		if str(a.get("id", "")) == RETIRED_ID:
			counters["sightings"] = int(counters["sightings"]) + 1
			violations.append("%s: the retired entry was offered" % label)


## Spend the lobby's one free C reroll (the real path) and scan the fresh draw too.
func _reroll(lb: RefCounted, level: int, p_seed: int, violations: Array[String],
		counters: Dictionary) -> void:
	var table: Array = lb.altar_table()
	for i in table.size():
		var entry: Dictionary = table[i]
		if str(entry.get("kind", "")) == "reroll" and str(entry.get("bay", "")) == "C":
			var evs: Array = []
			if not lb.apply_select(0, i, evs):
				violations.append("level %d seed %d: the free C reroll was refused" % [level, p_seed])
				return
			_scan_bay("level %d seed %d (reroll)" % [level, p_seed], _c_bay(lb),
					violations, counters)
			return
	violations.append("level %d seed %d: no C reroll plinth in the altar table" % [level, p_seed])


## Forced-held world: the ledger carries the retired id into world.build(). The dispatcher
## finds no module for it (none on disk), so it is inert by construction; the run must
## match the un-cursed control step for step.
func _forced_held_world(f: Array[String]) -> void:
	var ledger_plain := _ledger({})
	var ledger_held := _ledger({RETIRED_ID: 1})
	var control = WorldScript.new()
	if not bool(control.build(WORLD_SEED, LEVEL, ledger_plain)):
		f.append("control world failed to build (seed %d level %d)" % [WORLD_SEED, LEVEL])
		_drop(control)
		return
	var held = WorldScript.new()
	if not bool(held.build(WORLD_SEED, LEVEL, ledger_held)):
		f.append("held world failed to build with the retired id in the ledger")
		_drop(held)
		_drop(control)
		return
	var held_curses: Dictionary = held._ledger.get("curses", {})
	if int(held_curses.get(RETIRED_ID, 0)) != 1:
		f.append("the held world's ledger lost the retired id on the way in: %s"
				% str(held_curses))
	if held._curses == null:
		f.append("the held world built no curse dispatcher at all")
	else:
		if not (held._curses.module_ids() as Array).is_empty():
			f.append("the dispatcher holds module(s) %s for a curse with none on disk"
					% str(held._curses.module_ids()))
		if bool(held._curses.active()):
			f.append("the dispatcher is active for a ledger whose only curse has no module")
		var shared: Dictionary = held._curses.state
		var carried: Dictionary = shared.get("curses_held", {})
		if int(carried.get(RETIRED_ID, 0)) != 1:
			f.append("the dispatcher never saw the held retired id (state.curses_held=%s)"
					% str(carried))
	# Step both worlds the same number of ticks; the runs must be indistinguishable.
	var mismatch := 0
	var count_mismatch := 0
	for _t in WORLD_TICKS:
		control.step(DT)
		held.step(DT)
		var a: Array = control.rt.enemies if control.rt != null else []
		var b: Array = held.rt.enemies if held.rt != null else []
		if a.size() != b.size():
			count_mismatch += 1
			continue
		for i in a.size():
			if not _rows_match(a[i], b[i]):
				mismatch += 1
	if count_mismatch > 0:
		f.append("held run had a different body count on %d of %d ticks" % [count_mismatch, WORLD_TICKS])
	if mismatch > 0:
		f.append("held run diverged in %d body row(s) over %d ticks" % [mismatch, WORLD_TICKS])
	_drop(held)
	_drop(control)


## One body row, compared on the fields a tick can change (id + kinematics).
func _rows_match(a: Dictionary, b: Dictionary) -> bool:
	if str(a.get("id", "")) != str(b.get("id", "")):
		return false
	for key in ["x", "y", "z"]:
		if not is_equal_approx(float(a.get(key, 0.0)), float(b.get(key, 0.0))):
			return false
	return true


func _ledger(curses: Dictionary) -> Dictionary:
	return {
		"class": "dasher", "votes": KIWI_VOTE.duplicate(), "curses": curses.duplicate(),
		"stacks": {}, "purse": 0, "tithes": 0, "hunger": 0, "last_vote": "",
	}


func _drop(world) -> void:
	if world != null:
		world.teardown()
		world.free()


## Count honesty: every "script": true JSON either has its module on disk or is marked
## "retired": true - and the applicable script count is exactly the module count.
func _count_honesty(f: Array[String]) -> void:
	var dir := DirAccess.open(CURSES_DIR)
	if dir == null:
		f.append("cannot open %s (error %d)" % [CURSES_DIR, DirAccess.get_open_error()])
		return
	var script_true: Array[String] = []
	var retired_script: Array[String] = []
	var applicable: Array[String] = []
	var modules: Array[String] = []
	for fn in dir.get_files():
		if fn.begins_with("."):
			continue
		if fn.ends_with(".gd"):
			modules.append(fn.trim_suffix(".gd"))
			continue
		if not fn.ends_with(".json"):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(
				"%s/%s" % [CURSES_DIR, fn]))
		if parsed == null or not (parsed is Dictionary):
			f.append("%s: not valid JSON / not an object" % fn)
			continue
		var data: Dictionary = parsed
		if not bool(data.get("script", false)):
			continue
		var stem := fn.trim_suffix(".json")
		script_true.append(stem)
		if bool(data.get("retired", false)):
			retired_script.append(stem)
		else:
			applicable.append(stem)
	applicable.sort()
	modules.sort()
	for stem in applicable:
		if not modules.has(stem):
			f.append("%s.json has \"script\": true, is not retired, but %s.gd is missing" % [
					stem, stem])
	for stem in modules:
		if not applicable.has(stem):
			f.append("%s.gd exists but its JSON is declarative or retired - not an applicable script curse" % stem)
	if applicable.size() != modules.size():
		f.append("applicable script curses (%d) != modules on disk (%d) - script_true=%d retired_script=%d" % [
				applicable.size(), modules.size(), script_true.size(), retired_script.size()])
	if applicable.is_empty():
		f.append("no applicable script curses found - the scan is broken")
