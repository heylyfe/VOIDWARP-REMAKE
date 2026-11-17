extends RefCounted
#
# test_lobby.gd (A9, ticket T-023): the lobby is a physical scene with altars
# selectable through the F-hold (0.35 s), the schedule read from
# data/offering_schedule.json, and mandatory bays gating the Descent Gate.
#
# Drives INPUTS: the antechamber's tick() emits Select {altar_index} (the view-side
# proximity + 60-degree-look + hold gates), and the choice only takes effect when the
# caller feeds it into IntermissionScript.step() as a PlayerInput - votes ARE inputs.
#
# Headless, outside the scene tree, like test_billboard.gd: nodes built with
# build_all(), no _ready, no viewport.

const ContentApiScript := preload("res://core/content_api.gd")
const Intermission := preload("res://sim/intermission.gd")
const InputScript := preload("res://sim/input.gd")
const Antechamber := preload("res://view/lobby/antechamber.gd")
const OffersScript := preload("res://sim/offers.gd")

const Events := preload("res://sim/events.gd")


func run() -> Array[String]:
	var f: Array[String] = []
	var api := ContentApiScript.load()
	if not bool(api.is_ok()):
		f.append("content api boot failed: %s" % " / ".join(api.boot_errors()))
		return f
	_prerun_hall(f, api)
	_hold_and_select(f, api)
	_gate_gating(f, api)
	_curse_bay(f, api)
	_tithe(f, api)
	_shop_purchase(f, api)
	_reroll(f, api)
	_hunger(f, api)
	return f


## The pre-run lobby (CLASS + E starter) as a physical hall: dimensions, two lit
## bays at left + right, gate in the north wall, the About plaque present.
func _prerun_hall(f: Array[String], api: RefCounted) -> void:
	var lb: RefCounted = Intermission.create(api, 0, 0, 99)
	var kind_seen := {}
	for bay in lb.bays:
		kind_seen[str(bay["kind"])] = true
	if not (kind_seen.has("CLASS") and kind_seen.has("E")):
		f.append("prerun: lobby bays are %s, want CLASS + E" % str(kind_seen.keys()))
	var hall = Antechamber.new()
	hall.build_all(api, lb, "deepwater", 0)
	if not is_instance_valid(hall):
		f.append("prerun: the hall did not build")
	if absf(float(Antechamber.HALL_X) - 28.0) > 1e-9 or absf(float(Antechamber.HALL_Z) - 20.0) > 1e-9:
		f.append("prerun: hall is %sx%s, want 28x20" % [str(Antechamber.HALL_X), str(Antechamber.HALL_Z)])
	if absf(float(Antechamber.CEIL) - 8.0) > 1e-9:
		f.append("prerun: ceiling %s, want 8" % str(Antechamber.CEIL))
	var gate := hall.get_node_or_null(NodePath("DescentGate"))
	if gate == null:
		f.append("prerun: no DescentGate node at (0, -9.5)")
	elif (gate as Node3D).position.distance_to(Antechamber.GATE_POS + Vector3(0.0, 0.0, -0.6)) > 1e-6:
		f.append("prerun: gate stands at %s, want ~(0, -9.5)" % str((gate as Node3D).position))
	# two bays -> LEFT and RIGHT slots; banners for exactly those bays
	var banner_x := {}
	for child in hall.get_children():
		if child is Label3D and (child as Label3D).has_meta("bay_banner"):
			banner_x[roundf((child as Node3D).position.x)] = true
	if not banner_x.has(-9.0) or not banner_x.has(9.0):
		f.append("prerun: banners at %s, want left (-9) + right (+9)" % str(banner_x.keys()))
	# selectable altars: 3 class + 3 enemy offers; no curse plinths in the pre-run
	if (hall._altars as Array).size() != 6:
		f.append("prerun: %d selectable altars, want 6 (3 class + 3 enemy)"
				% (hall._altars as Array).size())
	# dark empty centre slot: a bay plinth area with nothing lit is expressed by the
	# absence of a centre banner
	if banner_x.has(0.0):
		f.append("prerun: centre banner exists but the centre bay is unscheduled")
	# prompt line: player near the LEFT bay's middle altar, looking at it
	var res: Dictionary = hall.tick(0.016, Vector3(-9.0, 0.0, -1.6), Vector3(0.0, 0.0, -1.0), false)
	if not str(res["prompt"]).begins_with("[F] Choose"):
		f.append("prerun: prompt is '%s', want '[F] Choose - <name>'" % str(res["prompt"]))
	if int(res["select"]) != -1:
		f.append("prerun: a select fired without F held")
	hall.free()


## Walk up to an altar, hold F: nothing under 0.35 s, exactly one Select at the hold,
## and the choice lands only through Intermission.step().
func _hold_and_select(f: Array[String], api: RefCounted) -> void:
	var lb: RefCounted = Intermission.create(api, 0, 0, 5)
	var hall = Antechamber.new()
	hall.build_all(api, lb, "deepwater", 0)
	# find the E bay's middle altar world position (2 bays -> E is at the RIGHT slot)
	var e_altar: Vector3 = Vector3.ZERO
	for a in hall._altars:
		if a["name"] != "" and (a["root"] as Node3D).position.x > 0.0:
			e_altar = (a["root"] as Node3D).position
	if e_altar == Vector3.ZERO:
		f.append("hold: no E-bay altar found on the right side")
		hall.free()
		return
	var at := Vector3(e_altar.x, 0.0, e_altar.z + 2.0)   # 2 u south of it, inside 2.5 u
	# wrong look direction: no prompt, no select
	var res: Dictionary = hall.tick(0.1, at, Vector3(0.0, 0.0, 1.0), true)
	if int(res["select"]) != -1:
		f.append("hold: selected while facing away from the altar")
	# face it; partial holds must NOT confirm
	for _i in 3:   # 3 x 0.1 s = 0.30 s < 0.35 s
		res = hall.tick(0.1, at, Vector3(0.0, 0.0, -1.0), true)
		if int(res["select"]) != -1:
			f.append("hold: confirmed after only %.1f s" % (0.1 * (_i + 1)))
	# the fourth tick (0.40 s total) confirms exactly once
	res = hall.tick(0.1, at, Vector3(0.0, 0.0, -1.0), true)
	if int(res["select"]) == -1:
		f.append("hold: no confirm after 0.40 s of holding")
		hall.free()
		return
	var chosen: int = int(res["select"])
	# a further hold does not double-fire into the same state
	var again: Dictionary = hall.tick(0.5, at, Vector3(0.0, 0.0, -1.0), true)
	if int(again["select"]) == chosen:
		f.append("hold: the same altar confirmed twice on one hold")
	# that Select lands as a SIM INPUT - ONLY through step(), the sim re-validates
	if lb.gate_open():
		f.append("hold: the gate opened before any Select input was applied")
	var events: Array = lb.step([InputScript.new(0, 0, 0, chosen)])
	var e_resolved := false
	for bay in lb.bays:
		if str(bay["kind"]) == "E" and bool(bay["resolved"]):
			e_resolved = true
	if not e_resolved:
		f.append("hold: the faced E bay did not resolve from the Select input")
	if lb.votes_sum() != 1:
		f.append("hold: votes after one enemy pick = %d, want 1" % lb.votes_sum())
	# the pre-run gate still waits for CLASS: resolve it through the same input path
	if lb.gate_open():
		f.append("hold: gate opened with CLASS unresolved")
	var events2: Array = _select_class_by_input(lb)
	for bay in lb.bays:
		if str(bay["kind"]) == "CLASS" and not bool(bay["resolved"]):
			f.append("hold: CLASS bay still unresolved after its Select")
	var gate_ev := false
	for ev in events2:
		if str(ev.get("type")) == Events.EV_GATE_OPENED:
			gate_ev = true
	if not gate_ev or not lb.gate_open():
		f.append("hold: gate_opened event missing / gate still closed after CLASS resolved")
	if (events as Array).size() < 1:
		f.append("hold: the enemy Select produced no altar_selected event")
	hall.free()


## Selects the first CLASS offer through lb.step() with a real PlayerInput.
func _select_class_by_input(lb: RefCounted) -> Array:
	var table: Array = lb.altar_table()
	for i in table.size():
		var entry: Dictionary = table[i]
		if str(entry["kind"]) != "offer":
			continue
		var bay: Dictionary = lb.bays[int(entry["bay_index"])]
		if str(bay["kind"]) == "CLASS" and not bool(bay["resolved"]):
			return lb.step([InputScript.new(0, 0, 0, i)])
	return []


## The C bay (DESIGN.md section 7): 3 altars, at least one Mild, bounty on pick,
## pool removal for non-stacking curses, stacks leave only at max.
func _curse_bay(f: Array[String], api: RefCounted) -> void:
	# >= 1 Mild per draw while any Mild is eligible (C bays sit after levels 2, 4, 8, ...)
	for seed_value in range(20):
		var lb: RefCounted = Intermission.create(api, 8, 0, 500 + seed_value)
		var c_bay: Dictionary = {}
		for bay in lb.bays:
			if str(bay["kind"]) == "C":
				c_bay = bay
		if c_bay.is_empty():
			f.append("curse: level 8 lobby has no C bay")
			return
		var altars: Array = c_bay["altars"]
		if (altars as Array).size() != 3:
			f.append("curse: %d altars, want 3" % (altars as Array).size())
			return
		var mild := false
		for a in altars:
			if str(a.get("severity", "")) == "mild":
				mild = true
			if int(a.get("bounty", -1)) <= 0:
				f.append("curse: %s shows bounty %d" % [str(a.get("id")), int(a.get("bounty", -1))])
		if not mild:
			f.append("curse: seed %d drew no Mild altar although Milds are eligible" % seed_value)
	# bounty scale: floor(base x (20 + level) / 20)
	var zoom_bounty: int = api.curse_bounty("zoomies", 4)
	var want_b: int = int(20 * 24 / 20)   # mild 20 base at level 4 -> 24
	if zoom_bounty != want_b:
		f.append("curse: zoomies bounty %d at level 4, want %d" % [zoom_bounty, want_b])
	# pool removal: a held NON-STACKING curse never re-offers (unmarked: max 1);
	# it is gone on every seed, no matter the draw.
	var held_hit := ""
	for seed_value in range(60):
		var lb2: RefCounted = Intermission.create(api, 8, 0, 900 + seed_value,
				{}, {"unmarked": 1}, {})
		for bay2 in lb2.bays:
			if str(bay2["kind"]) != "C":
				continue
			for a2 in bay2["altars"]:
				if str(a2["id"]) == "unmarked":
					held_hit = "unmarked re-offered after pick (seed %d)" % seed_value
	# stackable curses stay offerable below max and leave the pool exactly at max
	# (zoomies: 2 stacks; enemy-linked -> needs its kiwi cat vote; min_level 3).
	var stacked_seen := false
	var maxed_seen := false
	for seed_value in range(60):
		var lo: RefCounted = Intermission.create(api, 8, 0, 900 + seed_value,
				{"kiwi_cat": 1}, {"zoomies": 1}, {})
		var hi: RefCounted = Intermission.create(api, 8, 0, 900 + seed_value,
				{"kiwi_cat": 1}, {"zoomies": 2}, {})
		for bay2 in lo.bays:
			if str(bay2["kind"]) == "C":
				for a2 in bay2["altars"]:
					if str(a2["id"]) == "zoomies":
						stacked_seen = true
		for bay2 in hi.bays:
			if str(bay2["kind"]) == "C":
				for a2 in bay2["altars"]:
					if str(a2["id"]) == "zoomies":
						maxed_seen = true
	if held_hit != "":
		f.append("curse: " + held_hit)
	if not stacked_seen:
		f.append("curse: Zoomies at 1/2 stacks never re-offered in 60 draws")
	if maxed_seen:
		f.append("curse: Zoomies at max stacks was re-offered")
	# pick a curse through the Select input: the bounty lands in the purse
	var lb5: RefCounted = Intermission.create(api, 9, 100, 31)
	var events: Array = []
	var table: Array = lb5.altar_table()
	for i in table.size():
		if str(table[i]["kind"]) == "offer" and str(table[i]["bay"]) == "C":
			lb5.apply_select(0, i, events)
			break
## The C bay's free reroll: it redraws, spends its single free use, and is then gone
## (DESIGN.md section 7: one reroll of the whole bay per C intermission).
func _reroll(f: Array[String], api: RefCounted) -> void:
	var lb: RefCounted = Intermission.create(api, 2, 0, 12)
	var c_bay: Dictionary = {}
	for bay in lb.bays:
		if str(bay["kind"]) == "C":
			c_bay = bay
	if c_bay.is_empty() or (c_bay["altars"] as Array).size() != 3:
		f.append("reroll: the C lobby opened without 3 curse altars")
		return
	var pre_first := str((c_bay["altars"] as Array)[0]["id"])
	var ti := -1
	var tab: Array = lb.altar_table()
	for i in tab.size():
		if str(tab[i]["kind"]) == "reroll":
			ti = i
	if ti < 0:
		f.append("reroll: no reroll plinth in a C lobby")
		return
	lb.apply_select(0, ti, [])
	if int(c_bay.get("rerolls_used", 0)) != 1:
		f.append("reroll: rerolls_used %d after the first reroll, want 1"
				% int(c_bay.get("rerolls_used", 0)))
	# the free use is spent: the plinth is gone from the table and a second
	# reroll is refused (apply does no more than return false)
	var second := -1
	tab = lb.altar_table()
	for i in tab.size():
		if str(tab[i]["kind"]) == "reroll":
			second = i
	if second >= 0:
		f.append("reroll: a second reroll plinth is still offered after the free one")
	# distinctness of one draw
	var ids := {}
	for a in (c_bay["altars"] as Array):
		ids[str(a["id"])] = true
	if ids.size() != (c_bay["altars"] as Array).size():
		f.append("reroll: duplicate ids inside one C draw")
	if pre_first == "":
		f.append("reroll: drew an id-less altar")


## The Hunger fallback (DESIGN.md section 6): every eligible enemy maxed out -> the
## E bay offers Hunger instead; selecting it stacks +5% enemy speed.
func _hunger(f: Array[String], api: RefCounted) -> void:
	var gate: Dictionary = OffersScript.enemy_gate(api)
	var maxed: Dictionary = {}
	for id in gate.keys():
		maxed[str(id)] = int(gate[str(id)]["max_votes"])
	var drawn: Dictionary = OffersScript.draw_enemy_bay(api, 1, "starter", maxed,
			VoidRngFor(1))
	if str(drawn.get("kind", "")) != "hunger":
		f.append("hunger: a fully exhausted pool drew %s, want hunger"
				% str(drawn.get("kind")))
	var lb: RefCounted = Intermission.create(api, 1, 0, 9, maxed)
	var e_bay: Dictionary = {}
	for bay in lb.bays:
		if str(bay["kind"]) == "E":
			e_bay = bay
	if (e_bay["altars"] as Array).size() != 1 \
			or str((e_bay["altars"] as Array)[0].get("kind", "")) != "hunger":
		f.append("hunger: the lobby E bay did not become a Hunger altar")
		return
	# select it through a Select input
	var tab: Array = lb.altar_table()
	for i in tab.size():
		if str(tab[i]["kind"]) == "offer" and str(tab[i]["bay"]) == "E":
			lb.apply_select(0, i, [])
			break
	if int(lb.hunger) != 1:
		f.append("hunger: hunger stacks %d after the pick, want 1" % int(lb.hunger))
	if not bool(e_bay["resolved"]):
		f.append("hunger: the E bay did not resolve on Hunger")


func VoidRngFor(p_seed: int) -> RefCounted:
	return preload("res://terrain/void_rng.gd").new(p_seed)


## Mandatory bays gate the Descent Gate; optional ones never do (DESIGN.md section 11).
func _gate_gating(f: Array[String], api: RefCounted) -> void:
	# level 4 = [C, U]: the gate waits for the CURSE, a shop visit never opens it
	var lb: RefCounted = Intermission.create(api, 4, 10000, 61)
	if lb.gate_open():
		f.append("gating: level 4 lobby opened with the C bay unresolved")
	var table: Array = lb.altar_table()
	for i in table.size():
		var entry: Dictionary = table[i]
		if str(entry["kind"]) == "offer" and str(entry["bay"]) == "U":
			lb.apply_select(0, i, [])
			break
	table = lb.altar_table()
	for i in table.size():
		var entry: Dictionary = table[i]
		if str(entry["kind"]) == "offer" and str(entry["bay"]) == "C":
			lb.apply_select(0, i, [])
			break
	if not lb.gate_open():
		f.append("gating: level 4 gate still closed after the C pick")
	# an unresolved E bay blocks too: level 6 = [C, E]
	var lb2: RefCounted = Intermission.create(api, 6, 10000, 62)
	var c_done := false
	for bay in lb2.bays:
		if str(bay["kind"]) == "C":
			var t: Array = lb2.altar_table()
			for i in t.size():
				var e2: Dictionary = t[i]
				if str(e2["kind"]) == "offer" and int(e2["bay_index"]) == lb2.bays.find(bay):
					lb2.apply_select(0, i, [])
					c_done = true
					break
	if not c_done:
		f.append("gating: level 6 C bay could not be resolved")
	if lb2.gate_open():
		f.append("gating: level 6 gate opened while the E vote was still open")
	# and an E x2 bay needs BOTH votes (level 18)
	var lb3: RefCounted = Intermission.create(api, 18, 10000, 63)
	for bay in lb3.bays:
		if str(bay["kind"]) == "C":
			lb3.apply_select(0, 0, [])
	if lb3.gate_open():
		f.append("gating: E x2 gate opened after one vote")
	var t3: Array = lb3.altar_table()
	var casts := 0
	while not lb3.gate_open() and casts < 4:
		var acted := false
		for i in (lb3.altar_table() as Array).size():
			var e3: Dictionary = (lb3.altar_table() as Array)[i]
			if str(e3["kind"]) == "offer" and str(e3["bay"]) == "E" \
					and not bool(lb3.bays[int(e3["bay_index"])]["resolved"]):
				lb3.apply_select(0, i, [])
				acted = true
				break
		if not acted:
			break
		casts += 1
	if not lb3.gate_open():
		f.append("gating: E x2 gate closed after both votes")
	# a REST-only lobby (level 5) opens immediately: no mandatory bay exists
	var lb4: RefCounted = Intermission.create(api, 5, 0, 64)
	if not lb4.gate_open():
		f.append("gating: the REST lobby gate did not open (REST is optional)")


## The U bay: buying deducts the purse and consumes the offer; the rest bay discounts.
func _shop_purchase(f: Array[String], api: RefCounted) -> void:
	var lb: RefCounted = Intermission.create(api, 4, 10000, 77)   # U bay, rich
	var u_found := false
	for bay in lb.bays:
		if str(bay["kind"]) != "U":
			continue
		u_found = true
		if (bay["altars"] as Array).is_empty():
			f.append("shop: U bay drew no offers")
	# buy the first offer
	var table: Array = lb.altar_table()
	for i in table.size():
		if str(table[i]["kind"]) == "offer" and str(table[i]["bay"]) == "U":
			var before_gold := int(lb.purse)
			lb.apply_select(0, i, [])
			# measurable: the purse went down and the bought offer is gone
			if int(lb.purse) >= before_gold:
				f.append("shop: buying did not spend gold")
			break
	# a REST bay is a discounted shop, not a free one - the price shows the discount
	var lb2: RefCounted = Intermission.create(api, 5, 0, 88)
	var rest_seen := false
	for bay in lb2.bays:
		if str(bay["kind"]) == "REST":
			rest_seen = true
	if not rest_seen:
		f.append("shop: the rest-bay lobby built without the REST bay")


## The tithe: 100 + 75 per tithe paid; it resolves the C bay without a curse.
func _tithe(f: Array[String], api: RefCounted) -> void:
	var lb: RefCounted = Intermission.create(api, 2, 0, 44)   # broke: cannot tithe
	var ti := -1
	var table: Array = lb.altar_table()
	for i in table.size():
		if str(table[i]["kind"]) == "tithe":
			ti = i
	if ti < 0:
		f.append("tithe: no tithe plinth in a C lobby")
		return
	var evs: Array = []
	if lb.apply_select(0, ti, evs):
		f.append("tithe: paid with an empty purse (tithe 100 g)")
	var lb2: RefCounted = Intermission.create(api, 2, 500, 45)
	var evs2: Array = []
	lb2.apply_select(0, ti, evs2)   # same table shape: bay 0 is C here
	if int(lb2.purse) != int(500 - 100):
		f.append("tithe: purse %d after paying, want 400" % int(lb2.purse))
	if int(lb2.tithes) != 1:
		f.append("tithe: tithes %d, want 1" % int(lb2.tithes))
	for bay in lb2.bays:
		if str(bay["kind"]) == "C" and not bool(bay["resolved"]):
			f.append("tithe: C bay unresolved after paying")
	# the NEXT tithe costs 175 (data: base + 75 x tithes)
	if int(OffersScript.tithe_cost(1, api)) != 175:
		f.append("tithe: second tithe costs %d, want 175" % int(OffersScript.tithe_cost(1, api)))

