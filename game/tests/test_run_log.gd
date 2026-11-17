extends RefCounted
#
# test_run_log.gd - ticket T-080's done-when: a scripted bot run of 2 levels produces a
# user://runs/<seed>_<start_tick>.jsonl whose records cover every type the run can
# produce; every death carries a killer and a DESIGN.md section 3.1 code; charge_spent
# minus charge_restored gains equals the pip change; per level, level_clear.total_ticks
# equals level_start.t to beacon_enter.t; and the replay determinism hashes are
# IDENTICAL with logging on and off (the proof the log never perturbs the sim).
#
# Types a 2-level bot run cannot produce (owner's fallback: direct units, not fake bot
# output): levels 1-2 roll ZERO mines (DESIGN section 9: mine chance 0 below level 5),
# so mine_pass / mine_contact / last_light / death are covered by the synthetic-mine
# unit below; void_fall + charge_spent by the walk-off unit; the push window by a
# direct correlation check plus an rt-level emission check.

const VoidGenScript := preload("res://terrain/voidgen.gd")
const VoidRngScript := preload("res://terrain/void_rng.gd")
const CollisionScript := preload("res://sim/collision.gd")
const ControllerScript := preload("res://sim/controller.gd")
const LevelStateScript := preload("res://sim/level_state.gd")
const MinesScript := preload("res://sim/mines.gd")
const DeathScript := preload("res://sim/death.gd")
const RunStateScript := preload("res://sim/run_state.gd")
const SimScript := preload("res://sim/sim.gd")
const HashScript := preload("res://sim/state_hash.gd")
const InputScript := preload("res://sim/input.gd")
const EnemyRuntimeScript := preload("res://sim/enemy_runtime.gd")
const BotScript := preload("res://tools/bot_run.gd")
const LogScript := preload("res://app/run_log.gd")
const ContentApiScript := preload("res://core/content_api.gd")

# T-060's probe seed: clears level 2 with the dasher class (verified in this checkout).
const RUN_SEED := 60717
const REPLAY_SEED := 20260101
const INPUT_SEED := 777
const REPLAY_TICKS := 3600
const CHECK_EVERY := 60


func run() -> Array[String]:
	var failures: Array[String] = []
	failures.append_array(_bot_run_pass())
	failures.append_array(_mine_unit_pass())
	failures.append_array(_voidfall_and_push_pass())
	failures.append_array(_chain_unit_pass())
	failures.append_array(_replay_hash_pass())
	return failures


# ---- part 1: the scripted 2-level bot run ---------------------------------------------------

func _bot_run_pass() -> Array[String]:
	var failures: Array[String] = []
	var api := ContentApiScript.load()
	if not bool(api.is_ok()):
		return ["content api failed to boot"]
	var lg := LogScript.new()
	lg.run_started(RUN_SEED, "dasher", 0)
	var res: Dictionary = BotScript.play_run(api, RUN_SEED, 2, lg)
	lg.close()
	if str(res.get("outcome", "")) != "complete" or int(res.get("entered", 0)) < 2:
		failures.append("the fixed seed must CLEAR both levels for this test: outcome=%s entered=%s"
				% [str(res.get("outcome", "?")), str(res.get("entered", "?"))])
	var records: Array = _parse(lg.path, failures)

	# type coverage (the types a 2-level run can produce) + record shape + order
	var seen := {}
	var prev_t := -1
	for r in records:
		var rec: Dictionary = r
		for k in ["t", "level", "phase", "type", "payload"]:
			if not rec.has(k):
				failures.append("record missing key %s: %s" % [k, str(rec)])
		if not ["black", "gold", "lobby"].has(str(rec.get("phase", ""))):
			failures.append("bad phase in record: %s" % str(rec))
		if int(rec.get("t", -1)) < prev_t:
			failures.append("t went backwards at %s" % str(rec))
		prev_t = int(rec.get("t", prev_t))
		seen[str(rec.get("type", ""))] = int(seen.get(str(rec.get("type", "")), 0)) + 1
	for ty in ["run_start", "level_start", "gift", "beacon_open", "beacon_enter",
			"level_clear", "offer", "pick", "lobby_enter", "lobby_exit", "run_end",
			"charge_restored"]:
		if not seen.has(ty):
			failures.append("2-level bot run produced NO %s record" % ty)
	if records.is_empty() or str(records[0].get("type", "")) != "run_start":
		failures.append("the first record is not run_start")
	if str(records[records.size() - 1].get("type", "")) != "run_end":
		failures.append("the last record is not run_end")

	# every death: killer + a closed DESIGN.md 3.1 code, on_screen / charges / last_light present
	for r in records:
		var rec: Dictionary = r
		if str(rec.get("type", "")) != "death":
			continue
		var pl: Dictionary = rec.get("payload", {})
		var code := str(pl.get("code", ""))
		if str(pl.get("killer", "")) == "":
			failures.append("a death record without a killer: %s" % str(rec))
		if not DeathScript.CODES.has(code) and not code.begins_with("D-CURSE:"):
			failures.append("a death code outside the DESIGN.md 3.1 list: %s" % code)
		for k in ["on_screen", "charges", "last_light"]:
			if not pl.has(k):
				failures.append("death record missing %s: %s" % [k, str(rec)])

	# the pip equation (owner's done-when, read as the DROP the two record types explain):
	# (charge_spent count) - (restored gains) == pips lost = charges started - charges final
	var spent := int(seen.get("charge_spent", 0))
	var restored_gains := 0
	for r in records:
		var rec: Dictionary = r
		if str(rec.get("type", "")) == "charge_restored":
			var pl2: Dictionary = rec.get("payload", {})
			restored_gains += int(pl2.get("after", 0)) - int(pl2.get("before", 0))
	var pips_lost := 2 - int(res.get("charges", 0))   # DESIGN.md 3.1: a new run holds 2
	if spent - restored_gains != pips_lost:
		failures.append("pip equation failed: %d spent - %d restored != %d pips lost"
				% [spent, restored_gains, pips_lost])

	# per level: level_clear.total == level_start.t .. beacon_enter.t; black + gold = total
	var start_t := {}
	for r in records:
		var rec: Dictionary = r
		if str(rec.get("type", "")) == "level_start":
			start_t[int(rec.get("level", 0))] = int(rec.get("t", 0))
	var open_t := {}
	var enter_t := {}
	for r in records:
		var rec: Dictionary = r
		var lvn := int(rec.get("level", 0))
		if str(rec.get("type", "")) == "beacon_open":
			open_t[lvn] = int(rec.get("t", 0))
		if str(rec.get("type", "")) == "beacon_enter":
			enter_t[lvn] = int(rec.get("t", 0))
		if str(rec.get("type", "")) == "level_clear":
			var pl3: Dictionary = rec.get("payload", {})
			var lvn2 := int(rec.get("level", 0))
			if int(pl3.get("total_ticks", -1)) != int(enter_t.get(lvn2, -1)) - int(start_t.get(lvn2, -1)):
				failures.append("level %d: level_clear.total_ticks != level_start.t..beacon_enter.t" % lvn2)
			if int(pl3.get("black_ticks", -1)) != int(open_t.get(lvn2, -1)) - int(start_t.get(lvn2, -1)):
				failures.append("level %d: level_clear.black_ticks != level_start.t..beacon_open.t" % lvn2)
			if int(pl3.get("black_ticks", 0)) + int(pl3.get("gold_ticks", 0)) != int(pl3.get("total_ticks", -1)):
				failures.append("level %d: black + gold != total" % lvn2)
	# the lobby sits between the two level_clears and carries the level just finished
	for ty in ["level_start", "level_clear"]:
		var n := 0
		for r in records:
			if str(r.get("type", "")) == ty:
				n += 1
		if n != 2:
			failures.append("expected 2 %s records, got %d" % [ty, n])
	if records.size() > 0:
		print("RUNLOG %d records, %d types, ledger charges %s"
				% [records.size(), seen.size(), str(res.get("charges", "?"))])
	_clean(lg.path)
	return failures


func _parse(p_path: String, failures: Array[String]) -> Array:
	var out: Array = []
	var f := FileAccess.open(p_path, FileAccess.READ)
	if f == null:
		failures.append("run log file missing: %s" % p_path)
		return out
	while not f.eof_reached():
		var line := f.get_line()
		if line.strip_edges() == "":
			continue
		var parsed: Variant = JSON.parse_string(line)
		if not (parsed is Dictionary):
			failures.append("unparseable log line: %s" % line)
		else:
			out.append(parsed)
	f.close()
	return out


func _clean(p_path: String) -> void:
	var dir := DirAccess.open("user://runs")
	if dir != null and p_path.begins_with("user://runs/"):
		dir.remove(p_path.get_file())


# ---- part 2: synthetic units for the types levels 1-2 cannot produce -----------------------

## A REAL generated level with extra_mines forced (levels 1-2 roll none naturally);
## the returned {level, world, mines[]} triple drives the mine unit. mines[] are the
## slot ids whose Level.gifts row has occ == 1.
func _real_level(p_seed: int, p_extra_mines: int) -> Dictionary:
	var L: Dictionary = VoidGenScript.generate(p_seed, 1, 1, p_extra_mines)
	var w := CollisionScript.make_world(L["tiles"], L["props"], L["pads"], {"dais": L["beacon"]})
	var mines: Array[int] = []
	for i in (L["gifts"] as Array).size():
		if int((L["gifts"][i] as Dictionary)["occ"]) == 1:
			mines.append(i)
	return {"L": L, "w": w, "mines": mines}


## mine_pass, mine_contact (last_light AND killed outcomes), death, last_light records -
## all from the REAL mines ladder over a real generated level, fed to the log per tick.
func _mine_unit_pass() -> Array[String]:
	var failures: Array[String] = []
	var rl := _real_level(919, 3)
	if rl["mines"].size() < 2:
		return ["the mine fixture expected >= 2 mines at extra=3, got %d" % (rl["mines"] as Array).size()]
	var lv = LevelStateScript.build(rl["L"], 1, 1, 919)
	var w: Dictionary = rl["w"]
	var mines: Array = rl["mines"]
	var m0: Vector3 = lv.mines.point(mines[0])
	var m1: Vector3 = lv.mines.point(mines[1])
	var ctl = ControllerScript.new()
	ctl.setup("dasher")
	ctl.place(w)
	var lg := LogScript.new()
	lg.run_started(919, "dasher", 0)
	lg.level_started(1, 3, 1, 2, 1)

	# phase A: teleport-position a line 1.05 u beside mine 0: inside its 1.4 u bypass
	# zone, outside the 0.9 u contact cylinder, then out again -> one mine_pass record.
	var saw_pass := false
	for i in range(60):
		ctl.x = m0.x + 3.0 - float(i) * 0.1
		ctl.z = m0.z + 1.05
		ctl.y = 1.0
		var ev: Array = []
		MinesScript.tick(lv, [ctl], w, [0], i, ev)
		lg.feed_tick(ev)
		for e2 in ev:
			if str((e2 as Dictionary).get("type", "")) == "mine_pass":
				saw_pass = true
	if not saw_pass:
		failures.append("the 1.05 u bypass walk produced no mine_pass event (sim side)")
	# phase B: straight onto mine 0's centre with 1 charge held and Last Light armed ->
	# the ladder saves (last_light outcome + last_light record), the mine is consumed.
	ctl.charges = 1
	ctl.last_light_spent = false
	ctl.x = m0.x
	ctl.z = m0.z
	ctl.y = 1.0
	for i in range(3):
		var ev: Array = []
		MinesScript.tick(lv, [ctl], w, [0], 70 + i, ev)
		lg.feed_tick(ev)

	# phase C: onto mine 1's centre; Last Light is spent now -> a real D-MINE death.
	# Phase B's save granted 2.0 s of Last Light invulnerability; only step() decays it,
	# so the harness clears the timer to exercise ladder step 4.
	ctl.last_light_spent = true
	ctl.invuln = 0.0
	ctl.x = m1.x
	ctl.z = m1.z
	ctl.y = 1.0
	for i in range(3):
		var ev: Array = []
		MinesScript.tick(lv, [ctl], w, [0], 80 + i, ev)
		lg.feed_tick(ev)
	lg.run_finished(1, 0)
	lg.close()

	var records: Array = _parse(lg.path, failures)
	var contact_outcomes := {}
	var types := {}
	for r in records:
		var rec: Dictionary = r
		var ty := str(rec.get("type", ""))
		types[ty] = int(types.get(ty, 0)) + 1
		if ty == "mine_contact":
			contact_outcomes[str((rec.get("payload", {}) as Dictionary).get("outcome", ""))] = true
	if not types.has("mine_pass"):
		failures.append("no mine_pass record from the 1.05 u bypass walk")
	for r in records:
		var rec: Dictionary = r
		if str(rec.get("type", "")) != "mine_pass":
			continue
		var clos: float = float((rec.get("payload", {}) as Dictionary).get("closest", 0.0))
		if clos <= 0.9 or clos > 1.4:
			failures.append("mine_pass.closest %f outside (0.9, 1.4]" % clos)
	if not contact_outcomes.has("last_light"):
		failures.append("no mine_contact last_light outcome (ladder step 3 not exercised)")
	if not contact_outcomes.has("killed"):
		failures.append("no mine_contact killed outcome (ladder step 4 not exercised)")
	if not types.has("last_light"):
		failures.append("no last_light record from the armed save")
	if not types.has("death"):
		failures.append("no death record from the second mine")
	for r in records:
		var rec: Dictionary = r
		if str(rec.get("type", "")) == "death":
			var pl: Dictionary = rec.get("payload", {})
			if str(pl.get("code", "")) != DeathScript.MINE_CODE:
				failures.append("mine death carried %s, expected D-MINE" % str(pl.get("code", "")))
			if not bool(pl.get("on_screen", false)):
				failures.append("a mine kill must be on screen by construction")
	_clean(lg.path)
	return failures


## void_fall + charge_spent from a real controller walk-off (a real generated level);
## the pushed-120 correlation from push events (the sim's api.push emission checked on
## a real runtime); the pip equation exercised at the record level.
func _voidfall_and_push_pass() -> Array[String]:
	var failures: Array[String] = []
	var rl := _real_level(920, 0)
	var L: Dictionary = rl["L"]
	var w: Dictionary = rl["w"]
	var lg := LogScript.new()
	lg.run_started(920, "dasher", 0)
	lg.level_started(1, 1, 1, 0, 2)

	# the sim's own push emission, through the Api surface: rt.events carries a push row
	var ctl = ControllerScript.new()
	ctl.setup("dasher")
	ctl.place(w)
	var rt = EnemyRuntimeScript.new()
	rt.setup(L, w, [ctl], 0, {})
	var push_events: Array = []
	rt.push(ctl, Vector3(0.0, 1.0, 0.0), 3.0, {"id": "coil"})
	for e in rt.events:
		if str((e as Dictionary).get("e", "")) == "push":
			push_events.append(e)
	if push_events.is_empty() or str((push_events[0] as Dictionary).get("by", "")) != "coil":
		failures.append("api.push emitted no push event tagged coil")

	# the REAL fall: below the kill plane, 2 charges -> 1 (the controller answers)
	ctl.y = -1000.0
	var ev: Array = ctl.step(1.0 / 60.0, {"move_x": 0, "move_z": 0, "buttons": 0}, w)
	lg.feed_tick(push_events)
	lg.feed_tick(ev)
	# 100 ticks later: still inside the 120-tick push window
	for i in range(100):
		lg.feed_tick([])
	var evf: Array = [{"e": "void_fall", "charges": 0, "charges_before": 1,
			"tile": "3,0,2", "nearest_enemy_dist": 4.5}]
	lg.feed_tick(evf)
	# 200 more ticks: the push is now far outside the window
	for i in range(200):
		lg.feed_tick([])
	var evf2: Array = [{"e": "void_fall", "charges": 0, "charges_before": 1,
			"tile": "3,0,2", "nearest_enemy_dist": 4.5}]
	lg.feed_tick(evf2)
	lg.run_finished(1, 0)
	lg.close()

	var records: Array = _parse(lg.path, failures)
	var falls: Array = []
	var spends: Array = []
	for r in records:
		var rec: Dictionary = r
		var ty := str(rec.get("type", ""))
		var pl: Dictionary = rec.get("payload", {})
		if ty == "void_fall":
			falls.append(pl)
		if ty == "charge_spent":
			spends.append(pl)
			if str(pl.get("cause", "")) != "fall":
				failures.append("charge_spent.cause %s != fall" % str(pl.get("cause", "")))
			if bool(pl.get("free", true)):
				failures.append("a plain fall must not be free until Field Dressing exists")
	if falls.size() != 3:
		failures.append("expected 3 void_fall records (1 real + 2 synthetic), got %d" % falls.size())
		return failures
	# order: [0] the REAL walk-off, fed one tick after the push event -> INSIDE the 120-tick
	# window (that is what the correlation means); [1] the +100 synthetic (inside); [2] the
	# +302 one (stale).
	if not bool(falls[0].get("pushed_120", false)) or str(falls[0].get("pushed_by", "")) != "coil":
		failures.append("a push 1 tick before a fall must read pushed_120/coil: %s" % str(falls[0]))
	if not bool(falls[1].get("pushed_120", false)) or str(falls[1].get("pushed_by", "")) != "coil":
		failures.append("a push 100 ticks before a fall must read pushed_120/coil: %s" % str(falls[1]))
	if bool(falls[2].get("pushed_120", true)):
		failures.append("a push 300+ ticks before a fall must NOT read pushed_120: %s" % str(falls[2]))
	# the real fall + both synthetic falls also spent their pips: 3 charge_spent records
	if spends.size() != 3:
		failures.append("expected 3 charge_spent records, got %d" % spends.size())
	_clean(lg.path)
	return failures


## The chain replica from events alone: x1.00, +0.05 within the window, reset when the
## window is missed (mirrors sim/economy.gd's collect_gold_gift arithmetic).
func _chain_unit_pass() -> Array[String]:
	var failures: Array[String] = []
	var lg := LogScript.new()
	lg.run_started(921, "dasher", 0)
	lg.level_started(1, 4, 4, 0, 2)
	# a black gift keeps the chain at x1.00 (the gold phase begins at the beacon_opened)
	lg.feed_tick([{"type": "gift_collected", "tick": 0, "player": 0, "slot": 0,
			"phase": "black"}])
	var gift0: Dictionary = JSON.parse_string(_last_line(lg))
	lg.feed_tick([{"type": "beacon_opened", "tick": 0, "player": -1}])
	lg.feed_tick([{"type": "gift_collected", "tick": 1, "player": 0, "slot": 1,
			"phase": "gold"}])   # t=1: first gold -> recorded x1.00, chain -> x1.05
	var g1: Dictionary = JSON.parse_string(_last_line(lg))
	lg.feed_tick([])   # t=2..102: 101 total ticks
	for i in range(100):
		lg.feed_tick([])
	lg.feed_tick([{"type": "gift_collected", "tick": 102, "player": 0, "slot": 2,
			"phase": "gold"}])  # t=102, 101 ticks since the last gold (<= 240): x1.05
	var g2: Dictionary = JSON.parse_string(_last_line(lg))
	lg.feed_tick([])   # 400 empty ticks: far past the 240-tick window
	for i in range(400):
		lg.feed_tick([])
	lg.feed_tick([{"type": "gift_collected", "tick": 345, "player": 0, "slot": 3,
			"phase": "gold"}])  # past the window: reset to x1.00 before the value
	var g3: Dictionary = JSON.parse_string(_last_line(lg))
	lg.run_finished(1, 0)
	lg.close()
	for pair in [[g1, 1.0], [g2, 1.05], [g3, 1.0]]:
		var rec: Dictionary = pair[0]
		var expect: float = pair[1]
		var got: float = float((rec.get("payload", {}) as Dictionary).get("chain", -1.0))
		if absf(got - expect) > 1e-6:
			failures.append("gift chain %.3f != %.3f (%s)" % [got, expect, str(rec)])
	if absf(float((gift0.get("payload", {}) as Dictionary).get("chain", -1.0)) - 1.0) > 1e-6:
		failures.append("a black gift must carry the x1.00 chain")
	_clean(lg.path)
	return failures


func _last_line(lg) -> String:
	var f := FileAccess.open(lg.path, FileAccess.READ)
	if f == null:
		return ""
	var last := ""
	while not f.eof_reached():
		var line := f.get_line()
		if line.strip_edges() != "":
			last = line
	f.close()
	return last


# ---- part 3: the replay proof - identical hashes with the log on and off -------------------

## The test_replay.gd input generator (same deterministic recipe): seed-pinned holds.
func _record_inputs(seed: int) -> Array:
	var rng := VoidRngScript.new(seed)
	var inputs: Array = []
	var mx := 0
	var mz := 0
	var btn := 0
	var hold := 0
	var jhold := 0
	for t in REPLAY_TICKS:
		if jhold > 0:
			jhold -= 1
			if jhold == 0:
				btn = btn & ~InputScript.BUTTON_JUMP
		if hold <= 0:
			mx = rng.ri(-96, 96)
			mz = rng.ri(-96, 96)
			hold = rng.ri(15, 45)
		hold -= 1
		if jhold <= 0 and rng.chance(1, 30):
			btn = btn | InputScript.BUTTON_JUMP
			jhold = rng.ri(10, 25)
		inputs.append(InputScript.new(mx, mz, btn))
	return inputs


func _replay(run_seed: int, inputs: Array, with_log: bool) -> Array[String]:
	var rs := RunStateScript.new_run(run_seed, 1, ["core"])
	rs.load_level(VoidGenScript.generate(run_seed, 1, 1, 0), 1)
	var lg := LogScript.new()
	if with_log:
		lg.run_started(run_seed, "dasher", 0)
		lg.level_started(1, 40, 40, 0, 0)
	var hashes: Array[String] = []
	for t in REPLAY_TICKS:
		var events: Array = SimScript.step(rs, [inputs[t]]) as Array
		if with_log:
			lg.feed_tick(events)
		if (t + 1) % CHECK_EVERY == 0:
			hashes.append(HashScript.sha256(rs))
	lg.close()
	if with_log:
		_clean(lg.path)
	return hashes


func _replay_hash_pass() -> Array[String]:
	var failures: Array[String] = []
	var inputs := _record_inputs(INPUT_SEED)
	var off := _replay(REPLAY_SEED, inputs, false)
	var on := _replay(REPLAY_SEED, inputs, true)
	if off.size() != on.size():
		failures.append("checkpoint counts differ: %d (off) vs %d (log on)" % [off.size(), on.size()])
		return failures
	for c in off.size():
		if off[c] != on[c]:
			failures.append("replay hash %d differs with logging ON (%s vs %s) - the log perturbed the sim"
					% [c, off[c], on[c]])
	if failures.is_empty():
		print("RUNLOG %d checkpoints identical with the log on and off" % off.size())
	return failures
