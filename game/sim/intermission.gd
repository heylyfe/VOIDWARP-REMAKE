extends RefCounted
#
# sim/intermission.gd - the lobby state machine (ticket T-023; DESIGN.md section 6 bays,
# section 11 The Antechamber, owner spec "INTERMISSION (canon)" / "VOTING RULES (canon)").
#
# One intermission = one visit to the Antechamber for the level just completed
# (level_completed 0 = the pre-run lobby: CLASS + E starter pool).
#
# The bay LAYOUT comes from data/offering_schedule.json - THE one tunable file:
# schedule levels, then the repeat block repeat_from..repeat_to forever (DESIGN.md
# section 6: "rows 25-30 repeat forever"). The enemy gate numbers (min_level / max_votes)
# and the starter pool live in the same file until the enemy wave writes enemy.json
# (sim/offers.gd enemy_gate). Changing one entry changes the lobby with no code edit.
#
# The draws come from sim/offers.gd (enemy / curse) and its draw_shop (upgrades). Every
# draw or ledger write bumps `stamp` so the view (view/lobby/antechamber.gd) can rebuild
# its altars; the view holds no draw logic of its own.
#
# Selections are SIM INPUTS: PlayerInput.select indexes altar_table() (DESIGN.md section 13
# rule 2: "plus lobby choices (Select {altar_index}) - votes ARE inputs"). Proximity, the
# 60-degree look cone and the 0.35 s F-hold are view-side gates: they choose WHEN a Select
# fires. This file re-validates WHAT it does against the state it owns (bay unresolved,
# vote left, gold in the purse) and silently refuses anything else.
#
# Pure sim: RefCounted only, deterministic, randomness only through the VoidRng stream.

const OffersScript := preload("res://sim/offers.gd")
const EventsScript := preload("res://sim/events.gd")
const VoidRngScript := preload("res://terrain/void_rng.gd")

## E / C / U draws show three altars each ("pick 1 of 3"; the E x2 bay re-draws between votes).
const ALTARS_PER_BAY := 3

## Convenience alias (PlayerInput.NO_SELECT).
const NO_SELECT := -1


var content: RefCounted = null    # the ContentApi instance (draws + data reads)
var level_completed: int = 0      # level just finished; 0 = the pre-run lobby
var bays: Array = []              # bay states in schedule order (see _build_bays)
# Run-scoped ledgers the selections write into (carried across intermissions by the caller):
var votes: Dictionary = {}        # {enemy_id: votes} - an enemy CAN be picked repeatedly
var curses_held: Dictionary = {}  # {curse_id: stacks}
var upgrade_stacks: Dictionary = {}  # {upgrade_id: stacks}
var class_chosen: String = ""     # "" until the CLASS bay resolves (pre-run)
var purse: int = 0                # whole gold; bounties add, tithe/purchases subtract
var tithes: int = 0               # tithes paid this run (the next tithe costs more)
var hunger: int = 0               # Hunger stacks: +5% enemy speed each, repeatable
var last_vote: String = ""        # the type of the run's previous vote (D-074: the
                                  # REPEAT slot never re-offers it, T-074)
var stamp: int = 0                # bumped on every draw change; the view rebuilds on it
var rng_s: int = 0                # the lobby draw stream's state (exposed for dumps/hashes)
var _rng: RefCounted = null
var _gate_announced: bool = false  # EV_GATE_OPENED fired once per intermission


## Builds one lobby. p_votes / p_curses / p_stacks carry the run's ledgers in
## (they are updated in place; keep the same dictionaries across intermissions).
static func create(p_api: RefCounted, p_level_completed: int, p_purse: int, p_seed: int,
		p_votes: Dictionary = {}, p_curses: Dictionary = {}, p_stacks: Dictionary = {},
		p_class: String = "", p_tithes: int = 0, p_hunger: int = 0,
		p_last_vote: String = "") -> RefCounted:
	var lb := new()
	lb.content = p_api
	lb.level_completed = p_level_completed
	lb.purse = p_purse
	lb.votes = p_votes.duplicate()
	lb.curses_held = p_curses.duplicate()
	lb.upgrade_stacks = p_stacks.duplicate()
	lb.class_chosen = p_class
	lb.tithes = p_tithes
	lb.hunger = p_hunger
	lb.last_vote = p_last_vote
	lb._rng = VoidRngScript.new(VoidRngScript.mix(p_seed, 0x10BE))
	lb.rng_s = int(lb._rng.s)
	lb._build_bays(p_api)
	return lb


## The schedule rows for p_level, copied bay by bay with defaults filled in
## (count 1 for E, pool "" = full). After repeat_to the repeat_from..repeat_to
## block repeats forever (DESIGN.md section 6: the 25-30 block).
static func bays_for_level(p_api: RefCounted, p_level: int) -> Array:
	var sched: Dictionary = p_api.data("offering_schedule")
	var levels: Dictionary = sched.get("levels", {})
	var key := str(p_level)
	if not levels.has(key):
		var rf := int(sched.get("repeat_from", 0))
		var rt := int(sched.get("repeat_to", -1))
		if p_level > rt and rt >= rf:
			key = str(rf + (p_level - rf) % (rt - rf + 1))
	var out: Array = []
	for raw in (levels.get(key, []) as Array):
		var b: Dictionary = raw
		var d: Dictionary = {"bay": str(b.get("bay", ""))}
		if b.has("count"):
			d["count"] = int(b["count"])
		if b.has("pool"):
			d["pool"] = str(b["pool"])
		if b.has("discount_pct"):
			d["discount_pct"] = int(b["discount_pct"])
		out.append(d)
	return out


func _build_bays(p_api: RefCounted) -> void:
	bays = []
	for spec in bays_for_level(p_api, level_completed):
		var bay: Dictionary = {"kind": str(spec["bay"]), "resolved": false}
		match str(spec["bay"]):
			"E":
				bay["count"] = int(spec.get("count", 1))
				bay["pool"] = str(spec.get("pool", ""))
				bay["cast"] = 0
				_redraw_enemy(bay, false)
			"C":
				bay["rerolls_used"] = 0
				_redraw_curse(bay, false)
			"U", "REST":
				bay["discount_pct"] = int(spec.get("discount_pct", 0))
				bay["rerolls_used"] = 0
				_redraw_shop(bay, p_api, false)
			"CLASS":
				bay["altars"] = _class_altars(p_api)
			_:
				pass
		bays.append(bay)


## Class altars from data/player.json's class table - no class id is named in sim/.
static func _class_altars(p_api: RefCounted) -> Array:
	var ids: Array = (p_api.data("player").get("classes", {}) as Dictionary).keys()
	ids.sort()
	var out: Array = []
	for id in ids:
		out.append({"kind": "class", "id": str(id), "name": str(id)})
	return out


func _bump() -> void:
	stamp += 1
	rng_s = int(_rng.s)


func _redraw_enemy(p_bay: Dictionary, p_bump: bool = true) -> void:
	# the enemy gate reads the NEXT level's numbers: min_level is the level the voted
	# enemy will appear in, so the pre-run lobby (level_completed 0) votes for level 1
	var drawn: Dictionary = OffersScript.draw_enemy_bay(
			content, level_completed + 1, str(p_bay.get("pool", "")), votes, _rng,
			last_vote, curses_held)
	p_bay["drawn_kind"] = str(drawn["kind"])
	p_bay["altars"] = drawn["altars"]
	if p_bump:
		_bump()


func _redraw_curse(p_bay: Dictionary, p_bump: bool = true) -> void:
	var drawn: Dictionary = OffersScript.draw_curse_bay(
			content, level_completed, votes, curses_held, _rng, tithes)
	p_bay["altars"] = drawn["altars"]
	p_bay["tithe"] = int(drawn["tithe"])
	if p_bump:
		_bump()


func _redraw_shop(p_bay: Dictionary, p_api: RefCounted, p_bump: bool = true) -> void:
	var discount_mul: float = (100.0 - float(int(p_bay.get("discount_pct", 0)))) / 100.0
	var drawn: Dictionary = OffersScript.draw_shop(
			p_api, level_completed, purse, upgrade_stacks, class_chosen, _rng, discount_mul)
	p_bay["altars"] = drawn["offers"]
	if p_bump:
		_bump()


# --------------------------------------------------------------------- select inputs --

## The flat altar table the Select input indexes. Bay order, then each bay's offers in
## draw order, then its extra plinths ("tithe", "reroll"). Rebuilt from live state on
## every call, so the view builds its prompts from the same table.
func altar_table() -> Array:
	var out: Array = []
	for bi in bays.size():
		var bay: Dictionary = bays[bi]
		var kind := str(bay["kind"])
		for ai in (bay["altars"] as Array).size():
			out.append({"bay_index": bi, "altar": ai, "kind": "offer", "bay": kind})
		if kind == "C":
			out.append({"bay_index": bi, "altar": -1, "kind": "tithe", "bay": kind})
		if (kind == "C" and int(bay.get("rerolls_used", 0)) == 0) \
				or kind == "U" or kind == "REST":
			out.append({"bay_index": bi, "altar": -1, "kind": "reroll", "bay": kind})
	return out


## One lobby tick: applies each input's Select (every other input field belongs to the
## level walk and means nothing here). Appends and returns events.
func step(p_inputs: Array) -> Array:
	var events: Array = []
	for pi in p_inputs.size():
		var inp: Variant = p_inputs[pi]
		if not (inp is RefCounted):
			continue
		var sel_v: Variant = inp.get("select")
		var sel: int = NO_SELECT if sel_v == null else int(sel_v)
		if sel != NO_SELECT:
			apply_select(pi, sel, events)
	# The gate transition fires exactly once per intermission.
	if not _gate_announced and gate_open():
		_gate_announced = true
		events.append(EventsScript.make(EventsScript.EV_GATE_OPENED, 0, -1))
	return events


## Applies one Select. Silently refuses anything the state rejects (a resolved bay, a
## spent plinth, a purse too small). Returns true when the state changed.
func apply_select(p_player: int, p_index: int, p_events: Array) -> bool:
	var table := altar_table()
	if p_index < NO_SELECT or p_index >= table.size():
		return false
	var entry: Dictionary = table[p_index]
	match str(entry["kind"]):
		"offer":
			match str(entry["bay"]):
				"CLASS":
					return _select_class(int(entry["bay_index"]), int(entry["altar"]),
							p_player, p_events)
				"E":
					return _select_enemy(int(entry["bay_index"]), int(entry["altar"]),
							p_player, p_events)
				"C":
					return _select_curse(int(entry["bay_index"]), int(entry["altar"]),
							p_player, p_events)
				"U", "REST":
					return _select_upgrade(int(entry["bay_index"]), int(entry["altar"]),
							p_player, p_events)
		"tithe":
			return _select_tithe(int(entry["bay_index"]), p_player, p_events)
		"reroll":
			return _select_reroll(int(entry["bay_index"]), p_player, p_events)
	return false


func _emit(p_events: Array, p_player: int, p_bay: Dictionary, p_kind: String,
		p_id: String, p_cost: int) -> void:
	var ev: Dictionary = EventsScript.make(EventsScript.EV_ALTAR_SELECTED, 0, p_player)
	ev["bay"] = str(p_bay.get("kind", ""))
	ev["kind"] = p_kind
	ev["id"] = p_id
	ev["cost"] = p_cost
	p_events.append(ev)


func _select_class(p_bay_index: int, p_altar: int, p_player: int, p_events: Array) -> bool:
	var bay: Dictionary = bays[p_bay_index]
	if bool(bay["resolved"]):
		return false
	var altar: Dictionary = (bay["altars"] as Array)[p_altar]
	class_chosen = str(altar["id"])
	bay["resolved"] = true
	_emit(p_events, p_player, bay, "class", class_chosen, 0)
	return true


func _select_enemy(p_bay_index: int, p_altar: int, p_player: int, p_events: Array) -> bool:
	var bay: Dictionary = bays[p_bay_index]
	if bool(bay["resolved"]) or int(bay["cast"]) >= int(bay["count"]):
		return false
	var altar: Dictionary = (bay["altars"] as Array)[p_altar]
	if str(altar["kind"]) == "hunger":
		# Hunger (DESIGN.md section 6): +5% enemy speed for all, repeatable.
		hunger += 1
		_emit(p_events, p_player, bay, "hunger", "hunger", 0)
	else:
		var eid := str(altar["id"])
		votes[eid] = int(votes.get(eid, 0)) + 1
		last_vote = eid      # the E x2 redraw (and the next lobby's REPEAT slot)
		                     # must not re-offer this type (D-074)
		_emit(p_events, p_player, bay, "enemy", eid, 0)
	bay["cast"] = int(bay["cast"]) + 1
	if int(bay["cast"]) >= int(bay["count"]):
		bay["resolved"] = true
	else:
		_redraw_enemy(bay)   # an E x2 bay re-draws between votes (DESIGN.md section 6)
	return true


func _select_curse(p_bay_index: int, p_altar: int, p_player: int, p_events: Array) -> bool:
	var bay: Dictionary = bays[p_bay_index]
	if bool(bay["resolved"]):
		return false
	var altar: Dictionary = (bay["altars"] as Array)[p_altar]
	var cid := str(altar["id"])
	curses_held[cid] = int(curses_held.get(cid, 0)) + 1
	# Bounty paid on pick (DESIGN.md section 7); negative cost = gold gained.
	var bounty := int(altar.get("bounty", 0))
	purse += bounty
	bay["resolved"] = true
	_emit(p_events, p_player, bay, "curse", cid, -bounty)
	return true


func _select_tithe(p_bay_index: int, p_player: int, p_events: Array) -> bool:
	var bay: Dictionary = bays[p_bay_index]
	if bool(bay["resolved"]):
		return false
	var cost := OffersScript.tithe_cost(tithes, content)
	if purse < cost:
		return false
	purse -= cost
	tithes += 1
	bay["resolved"] = true
	_emit(p_events, p_player, bay, "tithe", "tithe", cost)
	return true


func _select_reroll(p_bay_index: int, p_player: int, p_events: Array) -> bool:
	var bay: Dictionary = bays[p_bay_index]
	match str(bay["kind"]):
		"C":
			# One REROLL of the whole bay per C intermission, free (DESIGN.md section 7).
			if bool(bay["resolved"]) or int(bay.get("rerolls_used", 0)) > 0:
				return false
			bay["rerolls_used"] = 1
			_redraw_curse(bay)
		"U", "REST":
			var cost := OffersScript.reroll_cost(int(bay.get("rerolls_used", 0)), content)
			if purse < cost:
				return false
			purse -= cost
			bay["rerolls_used"] = int(bay.get("rerolls_used", 0)) + 1
			_redraw_shop(bay, content)
		_:
			return false
	_emit(p_events, p_player, bay, "reroll", "reroll", 0)
	return true


func _select_upgrade(p_bay_index: int, p_altar: int, p_player: int, p_events: Array) -> bool:
	var bay: Dictionary = bays[p_bay_index]
	var altar: Dictionary = (bay["altars"] as Array)[p_altar]
	var price := int(altar.get("price", 0))
	if purse < price:
		return false
	purse -= price
	var uid := str(altar["id"])
	upgrade_stacks[uid] = int(upgrade_stacks.get(uid, 0)) + 1
	# sold: the offer leaves this visit's shop (sales_per_altar_per_visit, economy.json).
	(bay["altars"] as Array).remove_at(p_altar)
	_bump()
	_emit(p_events, p_player, bay, "upgrade", uid, price)
	return true


# ---------------------------------------------------------------------------- queries --

## The Descent Gate opens only when every MANDATORY bay is resolved (DESIGN.md section 11):
## the E bay (all its votes cast, Hunger included), the C bay (curse picked or tithe paid)
## and, in the pre-run lobby, the CLASS bay (a run cannot start without a class - D-T023-1).
## U / REST are optional and never gate.
func gate_open() -> bool:
	for bay in bays:
		match str(bay["kind"]):
			"E", "C":
				if not bool(bay["resolved"]):
					return false
			"CLASS":
				if class_chosen == "":
					return false
	return true


## Enemies in play for the NEXT level (DESIGN.md section 6 table): the count of enemy
## votes so far - VOTING RULES canon, 5 votes of a cat = 5 cats.
func votes_sum() -> int:
	var n := 0
	for id in votes.keys():
		n += int(votes[id])
	return n
