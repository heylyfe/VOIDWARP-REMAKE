extends RefCounted
#
# test_enemy_stacking.gd: voted enemies STACK for the rest of the run (DESIGN.md section 6,
# the "enemies in play next level" column rises monotonically; D-074's REPEAT altar raises a
# type already in play, below its cap). Driven through the shipped path: world.build ->
# run_ledger -> the real lobby scene's Intermission -> ledger() -> world.build next level.
#
#   leg carry   levels 1..LEVELS: every E vote is tallied by THIS test (its own oracle, read
#               from the picked altar's id), preferring a type already in play so repeat
#               votes happen. At every level the world's plan, the live spawned bodies and
#               the HUD counter must equal the tally; at least one repeat must have raised a
#               count; no type may exceed its enemy.json max_votes.
#   leg cap     a type at max_votes is never offered again (D-074 "below its cap").
#   leg hud     the counter: one row per type with count > 0, the right badge, sprite art
#               for a shipped enemy, the placeholder for an id with no art, no stale cells.
#   leg hash    the carried set is in the state hash: different votes -> different hash,
#               same votes in another insertion order -> same hash, no votes -> no VOTES
#               line (older dumps unchanged); a bot record/replay stays identical.
#   leg negctl  the SAME carry assertion run against the bug's shape (each level's votes
#               rebuilt from the previous lobby's picks only) must fail exactly
#               NEGCTL_WANT times; a hash with the VOTES line stripped must collide.

const WorldScript := preload("res://app/world.gd")
const LobbySceneScript := preload("res://view/lobby/lobby_scene.gd")
const IntermissionScript := preload("res://sim/intermission.gd")
const ContentApiScript := preload("res://core/content_api.gd")
const VoidRngScript := preload("res://terrain/void_rng.gd")
const VoidGenScript := preload("res://terrain/voidgen.gd")
const RunStateScript := preload("res://sim/run_state.gd")
const HashScript := preload("res://sim/state_hash.gd")
const EnemyRosterScript := preload("res://view/hud/enemy_roster.gd")
const BotRunScript := preload("res://tools/bot_run.gd")
const InputScript := preload("res://sim/input.gd")

const SEED := 1
const LEVELS := 8          # lobbies 1..7 hold E votes after levels 1, 3, 6, 7 (section 6)
const DT := 1.0 / 60.0
const SPAWN_GUARD := 900   # ticks: far past spawn_complete_tick() for any plan here
# The negative control's exact failure count (stated, not ranged): see _leg_negctl. Seed 1's
# run votes kiwi_cat pre-run, kiwi_cat (lobby 1), coil (3), kiwi_cat (6), coil (7). Carrying
# only the previous lobby's picks, per level (wrong types + 1 HUD line when any is wrong):
# L1 0 (pre-run picks ARE the tally) / L2 kiwi x1 of 2 -> 2 / L3 {} -> 2 / L4 coil only -> 2 /
# L5 {} -> 3 / L6 {} -> 3 / L7 kiwi x1 of 3, no coil -> 3 / L8 coil x1 of 2, no kiwi -> 3.
const NEGCTL_WANT := 18


func run() -> Array[String]:
	var f: Array[String] = []
	var api: RefCounted = ContentApiScript.load()
	if api == null or not api.is_ok():
		f.append("content api boot failed")
		return f
	var chain := _leg_carry(f, api)
	_leg_cap(f, api)
	_leg_hud(f)
	_leg_hash(f, api)
	_leg_negctl(f, chain)
	return f


# ---- leg carry ---------------------------------------------------------------------------

## Returns {"tallies": [level -> tally], "picks": [level -> {id: n} voted in lobby level-1]}
## for the negative control.
func _leg_carry(f: Array[String], api: RefCounted) -> Dictionary:
	var tally := {}
	var tallies := {}
	var picks := {}
	var repeats := 0
	var ledger := {}
	for level in range(1, LEVELS + 1):
		var w = WorldScript.new()
		if not w.build(SEED, level, ledger):
			f.append("carry: world.build(%d) failed" % level)
			w.free()
			return {}
		if level == 1:
			# the pre-run lobby's votes (the replay's own picks) seed the oracle
			tally = (w._ledger.get("votes", {}) as Dictionary).duplicate()
			picks[1] = tally.duplicate()
		tallies[level] = tally.duplicate()
		for msg in _carry_failures(w, tally, level, true):
			f.append(msg)
		for id in tally.keys():
			var cap := int(api.enemy(str(id)).get("max_votes", 1))
			if int(tally[id]) > cap:
				f.append("carry: %s at %d votes, over its max_votes %d" % [id, tally[id], cap])
		ledger = w.run_ledger()
		w.teardown()
		w.free()
		if level == LEVELS:
			break
		# the lobby after this level: the real scene, its Intermission, its ledger()
		var scene = LobbySceneScript.new()
		if not scene.build(SEED, level, ledger):
			f.append("carry: lobby %d failed to build" % level)
			scene.free()
			return {}
		var voted := {}
		for _i in 40:
			var lb: RefCounted = scene.lobby
			if bool(lb.gate_open()):
				break
			var pick := _choose(lb, tally)
			if pick.is_empty():
				break
			var bay: Dictionary = lb.bays[int(pick["bay_index"])]
			if str(bay["kind"]) == "E" and str(pick["id"]) != "":
				var eid := str(pick["id"])
				if int(tally.get(eid, 0)) > 0:
					repeats += 1
				tally[eid] = int(tally.get(eid, 0)) + 1
				voted[eid] = int(voted.get(eid, 0)) + 1
			lb.step([InputScript.new(0, 0, 0, int(pick["index"]))])
		if not bool(scene.lobby.gate_open()):
			f.append("carry: lobby %d never opened its gate" % level)
		ledger = scene.ledger()
		picks[level + 1] = voted
		scene.free()
		if (ledger.get("votes", {}) as Dictionary) != tally:
			f.append("carry: lobby %d ledger votes %s, the test's tally %s"
					% [level, str(ledger.get("votes")), str(tally)])
	if repeats < 1:
		f.append("carry: no repeat vote happened in %d levels - the raise is unproven" % LEVELS)
	print("STACKING carry: %d levels, %d repeat votes, final %s" % [LEVELS, repeats, str(tally)])
	return {"tallies": tallies, "picks": picks}


## The pick for one lobby step: an E offer for a type already in play (a repeat) first,
## else the first E offer, else the first C offer, else a C tithe. Hunger counts as an E
## offer with id "". Returns {index, bay_index, id} or {} when nothing is pickable.
func _choose(lb: RefCounted, tally: Dictionary) -> Dictionary:
	var table: Array = lb.altar_table()
	var first_e := {}
	var first_c := {}
	for i in table.size():
		var entry: Dictionary = table[i]
		var bi := int(entry["bay_index"])
		var bay: Dictionary = lb.bays[bi]
		if bool(bay.get("resolved", false)):
			continue
		var bk := str(bay["kind"])
		var kind := str(entry["kind"])
		if bk == "E" and kind == "offer":
			var altar: Dictionary = (bay["altars"] as Array)[int(entry["altar"])]
			var id := "" if str(altar.get("kind", "")) == "hunger" else str(altar.get("id", ""))
			var row := {"index": i, "bay_index": bi, "id": id}
			if id != "" and int(tally.get(id, 0)) > 0:
				return row
			if first_e.is_empty():
				first_e = row
		elif bk == "C" and (kind == "offer" or kind == "tithe") and first_c.is_empty():
			first_c = {"index": i, "bay_index": bi, "id": ""}
	return first_e if not first_e.is_empty() else first_c


## THE carry assertion (shared by leg carry and the negative control): one failure line per
## enemy type whose planned count differs from the tally (missing types included, extra
## types too), plus one line when the HUD counter's rows differ from the tally. With p_live
## the level is stepped past spawn completion and the spawned bodies are counted as well.
func _carry_failures(w, tally: Dictionary, level: int, p_live: bool) -> Array[String]:
	var out: Array[String] = []
	var plan := {}
	for row in w._roster:
		plan[str(row["id"])] = int(row["count"])
	var ids := {}
	for id in tally.keys():
		ids[str(id)] = true
	for id in plan.keys():
		ids[str(id)] = true
	for id in ids.keys():
		var want := int(tally.get(id, 0))
		var got := int(plan.get(id, 0))
		if want != got:
			out.append("level %d: %s planned x%d, the run voted x%d" % [level, id, got, want])
	w._sync_hud()
	var hud_rows := {}
	if w.hud != null:
		for r in w.hud.enemy_roster.rows():
			hud_rows[str(r["id"])] = int(r["count"])
	var want_rows := {}
	for id in tally.keys():
		if int(tally[id]) > 0:
			want_rows[str(id)] = int(tally[id])
	if hud_rows != want_rows:
		out.append("level %d: the HUD counter shows %s, the run voted %s"
				% [level, str(hud_rows), str(want_rows)])
	if p_live:
		var guard := 0
		while guard < SPAWN_GUARD and (not w.rt.planned.is_empty()
				or int(w.rt.tick) <= int(w.rt.spawn_complete_tick())):
			w.step(DT)
			guard += 1
		var bodies := {}
		for e in w.rt.enemies:
			bodies[str(e["id"])] = int(bodies.get(str(e["id"]), 0)) + 1
		if bodies != want_rows:
			out.append("level %d: spawned bodies %s, the run voted %s"
					% [level, str(bodies), str(want_rows)])
	return out


# ---- leg cap -----------------------------------------------------------------------------

## D-074: REPEAT offers a type in play BELOW its cap. With kiwi_cat the only type in play,
## the REPEAT altar must be kiwi_cat while it is below max_votes, and no altar may offer it
## once it sits at max_votes. Both twins over the same lobbies.
func _leg_cap(f: Array[String], api: RefCounted) -> void:
	var id := "kiwi_cat"
	var cap := int(api.enemy(id).get("max_votes", 0))
	if cap < 2:
		f.append("cap: %s max_votes %d - the fixture needs a stackable type" % [id, cap])
		return
	var below_seen := 0
	var at_seen := 0
	var bays_n := 0
	for completed in [1, 3, 7, 9, 13]:
		for s in range(1, 5):
			var below: RefCounted = IntermissionScript.create(api, completed, 0,
					VoidRngScript.mix(s, 5000 + completed), {id: cap - 1})
			var at: RefCounted = IntermissionScript.create(api, completed, 0,
					VoidRngScript.mix(s, 5000 + completed), {id: cap})
			for bay in below.bays:
				if str(bay["kind"]) == "E":
					bays_n += 1
					if _offers(bay, id):
						below_seen += 1
			for bay in at.bays:
				if str(bay["kind"]) == "E" and _offers(bay, id):
					at_seen += 1
	if bays_n == 0:
		f.append("cap: no E bay drawn over the fixture lobbies")
	if below_seen != bays_n:
		f.append("cap: %s below its cap offered in %d of %d E bays, want all (REPEAT)"
				% [id, below_seen, bays_n])
	if at_seen != 0:
		f.append("cap: %s at max_votes %d still offered in %d E bays" % [id, cap, at_seen])


func _offers(bay: Dictionary, id: String) -> bool:
	for a in (bay.get("altars", []) as Array):
		if str((a as Dictionary).get("id", "")) == id:
			return true
	return false


# ---- leg hud -----------------------------------------------------------------------------

func _leg_hud(f: Array[String]) -> void:
	var r = EnemyRosterScript.new()
	r.set_roster([{"id": "kiwi_cat", "name": "kiwi cat", "count": 3},
			{"id": "coil", "count": 1}, {"id": "seal", "count": 0},
			{"id": "no_such_enemy", "count": 2}])
	var rows: Array = r.rows()
	var want := [{"id": "kiwi_cat", "count": 3}, {"id": "coil", "count": 1},
			{"id": "no_such_enemy", "count": 2}]
	if rows != want:
		f.append("hud: rows %s, want %s (one per type, count 0 hidden)" % [str(rows), str(want)])
	if r._row.get_child_count() != 3:
		f.append("hud: %d cells for 3 rows" % r._row.get_child_count())
	if r.badge_for("kiwi_cat") != "x3" or r.badge_for("coil") != "x1":
		f.append("hud: badges '%s' / '%s', want x3 / x1" % [r.badge_for("kiwi_cat"),
				r.badge_for("coil")])
	if r.icon_kind_for("kiwi_cat") != "sprite" or r.icon_kind_for("coil") != "sprite":
		f.append("hud: shipped enemies draw '%s' / '%s', want sprite art"
				% [r.icon_kind_for("kiwi_cat"), r.icon_kind_for("coil")])
	if r.icon_kind_for("no_such_enemy") != "placeholder":
		f.append("hud: an id with no art draws '%s', want placeholder"
				% r.icon_kind_for("no_such_enemy"))
	# a repeat vote raises the badge in place; the per-frame re-send adds no cells
	r.set_roster([{"id": "kiwi_cat", "count": 4}, {"id": "coil", "count": 1}])
	r.set_roster([{"id": "kiwi_cat", "count": 4}, {"id": "coil", "count": 1}])
	if r._row.get_child_count() != 2 or r.badge_for("kiwi_cat") != "x4":
		f.append("hud: after a repeat vote %d cells, kiwi badge '%s' (want 2, x4)"
				% [r._row.get_child_count(), r.badge_for("kiwi_cat")])
	# the whole 12-type roster fits the corner block: 4 columns, 3 rows, never wider
	var all: Array = []
	for id in ["address_me", "claude", "coil", "gift_larper", "gin", "isagi", "kiwi_cat",
			"nuke", "seal", "thicc_ben", "toucher", "you"]:
		all.append({"id": id, "count": 1})
	r.set_roster(all)
	var sprites := 0
	for row in all:
		if r.icon_kind_for(str(row["id"])) == "sprite":
			sprites += 1
	if sprites != 12:
		f.append("hud: %d of the 12 shipped enemies draw sprite art" % sprites)
	var box_w: float = r.offset_right - r.offset_left
	var box_h: float = r.offset_bottom - r.offset_top
	if r._row.columns != 4 or box_w > 200.0 or box_h > 140.0:
		f.append("hud: the counter block is %d cols, %.0f x %.0f px - want 4 cols within 200 x 140"
				% [r._row.columns, box_w, box_h])
	r.free()


# ---- leg hash ----------------------------------------------------------------------------

func _rs(api: RefCounted, votes: Dictionary, hunger: int = 0) -> RefCounted:
	var rs = RunStateScript.new_run(SEED, 1, api.content_ids())
	rs.run_votes = votes
	rs.run_hunger = hunger
	rs.load_level(VoidGenScript.generate(SEED, 1, 1, 0), 1)
	return rs


func _leg_hash(f: Array[String], api: RefCounted) -> void:
	var h0 := HashScript.sha256(_rs(api, {}))
	var h1 := HashScript.sha256(_rs(api, {"kiwi_cat": 1}))
	var h2 := HashScript.sha256(_rs(api, {"kiwi_cat": 2}))
	var h3 := HashScript.sha256(_rs(api, {"kiwi_cat": 1, "coil": 1}))
	var h3b := HashScript.sha256(_rs(api, {"coil": 1, "kiwi_cat": 1}))
	var h1h := HashScript.sha256(_rs(api, {"kiwi_cat": 1}, 1))
	var distinct := {h0: true, h1: true, h2: true, h3: true, h1h: true}
	if distinct.size() != 5:
		f.append("hash: votes {} / kiwi x1 / kiwi x2 / kiwi+coil / kiwi x1 + hunger hash to %d distinct values, want 5"
				% distinct.size())
	if h3 != h3b:
		f.append("hash: the same votes in another insertion order hash differently")
	if HashScript.sha256(_rs(api, {"kiwi_cat": 2})) != h2:
		f.append("hash: the same carried set hashed twice differs")
	var d0: PackedStringArray = HashScript.dump(_rs(api, {}))
	for line in d0:
		if line.begins_with("VOTES") or line.begins_with("HUNGER"):
			f.append("hash: a run with no votes dumps '%s' - older dumps must be unchanged" % line)
	var d3: PackedStringArray = HashScript.dump(_rs(api, {"kiwi_cat": 1, "coil": 2, "gin": 0}))
	if not d3.has("VOTES coil:2 kiwi_cat:1"):
		f.append("hash: the dump carries no 'VOTES coil:2 kiwi_cat:1' line: %s" % str(d3))
	# the bot path: votes ride the RunState, and record vs replay stays identical
	var rec := {"record": true, "inputs": [], "hashes": [], "total_ticks": 0, "max_ticks": 600}
	BotRunScript.play_run(api, 101, 1, null, rec)
	var rep := {"playback": rec["inputs"], "playback_cursor": 0, "hashes": [],
			"total_ticks": 0, "max_ticks": 600}
	BotRunScript.play_run(api, 101, 1, null, rep)
	if (rec["hashes"] as Array).is_empty():
		f.append("hash: the bot recording reached no checkpoint")
	elif rec["hashes"] != rep["hashes"]:
		f.append("hash: bot record/replay hashes differ with the carried set in the hash")


# ---- leg negctl --------------------------------------------------------------------------

## The bug's shape: each level carries ONLY the votes cast in the lobby just before it (the
## pre-run votes for level 1). The SAME _carry_failures assertion must fail, and exactly
## NEGCTL_WANT times for this seed (one line per wrong type, one per wrong HUD counter, per
## level). Then the hash control: with the VOTES / HUNGER lines stripped, two runs that voted
## differently must collide - so the distinction leg hash sees is the carried set's own line.
func _leg_negctl(f: Array[String], chain: Dictionary) -> void:
	if chain.is_empty():
		f.append("negctl: leg carry produced no chain")
		return
	var n := 0
	var lines: Array = []
	for level in range(1, LEVELS + 1):
		var picks: Dictionary = (chain["picks"] as Dictionary).get(level, {})
		var buggy := {"class": "", "votes": picks.duplicate(), "curses": {}, "stacks": {},
				"purse": 0, "tithes": 0, "hunger": 0, "last_vote": ""}
		var w = WorldScript.new()
		if not w.build(SEED, level, buggy):
			f.append("negctl: buggy world.build(%d) failed" % level)
			w.free()
			return
		var got := _carry_failures(w, (chain["tallies"] as Dictionary)[level], level, false)
		n += got.size()
		lines.append_array(got)
		w.teardown()
		w.free()
	print("STACKING negctl: the rebuilt-per-level carry fails %d times (want %d)" % [n, NEGCTL_WANT])
	if n != NEGCTL_WANT:
		f.append("negctl: the rebuilt-per-level carry failed %d times, want exactly %d: %s"
				% [n, NEGCTL_WANT, str(lines)])
	var api: RefCounted = ContentApiScript.load()
	var a := _strip(HashScript.dump(_rs(api, {"kiwi_cat": 1})))
	var b := _strip(HashScript.dump(_rs(api, {"kiwi_cat": 2, "coil": 1})))
	if a != b:
		f.append("negctl: dumps without the VOTES line still differ - leg hash proves nothing")


func _strip(d: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for line in d:
		if not (line.begins_with("VOTES") or line.begins_with("HUNGER")):
			out.append(line)
	return out