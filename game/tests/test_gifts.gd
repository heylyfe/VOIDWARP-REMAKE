extends RefCounted
#
# A5 (FLEET_PACK.md section 5, ticket T-020): "black->gold: after the last real
# black gift, gold gifts exist at exactly the same slot ids/positions (asserted
# on 100 seeds); beacon CLOSED->OPEN exactly then" - game/tests/test_gifts.gd.
#
# Also proves, with the same commands the response file quotes:
#   - the beacon entry restores exactly 1 void charge (0->1, 1->2, 2->2) and
#     never more (controller-driven, via sim/beacon.gd try_enter);
#   - the straggler rule marks only REAL gifts (occ == 0) and only the last 20%;
#   - the pickup radius comes from the pickup_radius stat multiplier;
#   - gift positions are only ever read from Level.gifts (slot_pos confinement
#     scan: no file under sim/ or core/ other than sim/gifts.gd mentions it);
#   - the three view scripts load and sync against a real synthetic state.
#
# Levels 5..25 exercise mine occupancy (occ == 1 appears from level 5); one
# level-1 seed covers the zero-mine case.

const VoidGenScript := preload("res://terrain/voidgen.gd")
const RunStateScript := preload("res://sim/run_state.gd")
const LevelStateScript := preload("res://sim/level_state.gd")
const SimScript := preload("res://sim/sim.gd")
const InputScript := preload("res://sim/input.gd")
const GiftsScript := preload("res://sim/gifts.gd")
const BeaconScript := preload("res://sim/beacon.gd")
const EventsScript := preload("res://sim/events.gd")
const ControllerScript := preload("res://sim/controller.gd")
const MinesScript := preload("res://sim/mines.gd")
const HashScript := preload("res://sim/state_hash.gd")

const SEED_COUNT := 100
const FIRST_SEED := 9900
const MINE_LEVEL_LO := 5   # mine occupancy starts at level 5 (TERRAIN_SPEC 6.8)


func run() -> Array[String]:
	var f: Array[String] = []
	_test_a5_100_seeds(f)
	_test_beacon_entry_charges(f)
	_test_pickup_radius_stat(f)
	_test_hash_pins_pickup_radius(f)
	_test_hash_pins_lost_gifts(f)
	_test_other_volumes(f)
	_test_straggler_threshold(f)
	_test_slot_pos_confinement(f)
	_test_views(f)
	return f


# ---- helpers -------------------------------------------------------------------

static func _count(ev: Array, kind: String) -> int:
	var n := 0
	for e in ev:
		if str(e.get("type", "")) == kind:
			n += 1
	return n


static func _last(ev: Array, kind: String) -> Dictionary:
	for i in range(ev.size() - 1, -1, -1):
		if str(ev[i].get("type", "")) == kind:
			return ev[i]
	return {}


## A minimal synthetic level: one 1x1 tile per gift slot, all at y 0. The slots
## sit on the column x = 3 (world x 3.5) with z spacing 3 so the 0.4 u radius
## never overlaps. The dict carries every field to_text() reads.
static func _synthetic(occs: Array) -> Dictionary:
	var gifts: Array = []
	var tiles: Array = []
	for i in occs.size():
		var z: int = i * 3
		gifts.append({"id": i, "x": 3, "z": z, "y": 0, "piece": 0, "tier": 0, "occ": occs[i]})
		tiles.append([3, z, 0, 0, 0])
	return {
		"gen_version": 0, "seed": 0, "level": 1, "players": 1, "extra_mines": 0, "attempt": 0,
		"beacon": [0, 0, 1], "spawns": [[0, 0, 1]], "arms": [], "pieces": [],
		"tiles": tiles, "props": [], "edges": [], "gifts": gifts, "anchors": [], "pads": [],
	}


# ---- A5: 100 seeds ---------------------------------------------------------------

func _test_a5_100_seeds(f: Array[String]) -> void:
	var seeds_with_mines := 0
	for k in SEED_COUNT:
		var seed: int = FIRST_SEED + k
		var level: int = 1 if k == SEED_COUNT - 1 else MINE_LEVEL_LO + (k % 21)
		_a5_one(f, seed, level)
		var L := VoidGenScript.generate(seed, level)
		if not L.is_empty():
			for s in L["gifts"]:
				if int(s["occ"]) != 0:
					seeds_with_mines += 1
					break
	if seeds_with_mines < 10:
		f.append("A5: only %d of %d seeds carried occ == 1 slots; the mine exclusion is under-tested"
				% [seeds_with_mines, SEED_COUNT])
	print("A5 %d seeds (%d with mines) checks done" % [SEED_COUNT, seeds_with_mines])


## One seed of the A5 loop. Collects every real black gift through the real sim
## (SimScript.step), asserting CLOSED->OPEN exactly at the last one, then the
## gold phase: same slot ids, same positions, none collected, full count.
func _a5_one(f: Array[String], seed: int, level: int) -> void:
	var L := VoidGenScript.generate(seed, level)
	if L.is_empty():
		f.append("seed %d level %d: generator returned an empty level" % [seed, level])
		return
	var rs: RefCounted = RunStateScript.new_run(seed, 1, [])
	rs.load_level(L, level)
	var lv: RefCounted = rs.level
	var g: RefCounted = lv.gifts
	var b: RefCounted = lv.beacon

	# sanity: state mirrored straight from Level.gifts
	if g.slots.size() != L["gifts"].size():
		f.append("seed %d level %d: gift state holds %d slots, Level.gifts has %d"
				% [seed, level, g.slots.size(), L["gifts"].size()])
		return
	var real: int = 0
	for s in L["gifts"]:
		if int(s["occ"]) == 0:
			real += 1
	if g.total_real != real:
		f.append("seed %d level %d: total_real %d != %d real slots" % [seed, level, g.total_real, real])
		return
	if g.total_real <= 0:
		f.append("seed %d level %d: no real gifts" % [seed, level])
		return

	# snapshot the positions (from Level.gifts via slot_pos, the only mapping)
	var pos_before := {}
	var real_ids: Array = []
	for i in g.slots.size():
		pos_before[i] = g.slot_pos(i)
		if g.is_real(i):
			real_ids.append(i)

	# level start: beacon CLOSED, black phase, no gold collected
	if not b.is_closed():
		f.append("seed %d level %d: beacon not CLOSED at level start" % [seed, level])
	if g.phase != GiftsScript.PHASE_BLACK:
		f.append("seed %d level %d: phase %s at level start" % [seed, level, g.phase])

	# collect every real black gift, one sim tick each
	var black_events := 0
	for idx in real_ids.size():
		var i: int = real_ids[idx]
		var pos: Vector3 = g.slot_pos(i)
		var p: Dictionary = lv.players[0]
		p["x"] = pos.x
		p["y"] = pos.y - 1.0   # feet on the slot's tile top; pickup centre 0.9 u up
		p["z"] = pos.z
		p["vy"] = 0.0
		p["grounded"] = true
		var ev: Array = SimScript.step(rs, [InputScript.neutral()])
		black_events += _count(ev, EventsScript.EV_GIFT_COLLECTED)
		# the event names exactly this slot in the black phase
		var ge := _last(ev, EventsScript.EV_GIFT_COLLECTED)
		if ge.is_empty():
			f.append("seed %d level %d: slot %d pickup produced no gift_collected event" % [seed, level, i])
		elif int(ge.get("slot", -1)) != i or str(ge.get("phase", "")) != GiftsScript.PHASE_BLACK:
			f.append("seed %d level %d: pickup event %s for slot %d" % [seed, level, str(ge), i])
		# hazards never highlighted, never counted (invariant checked every tick)
		for s_id in g.straggler_ids():
			if not g.is_real(int(s_id)):
				f.append("seed %d level %d: straggler beam on non-real slot %d" % [seed, level, int(s_id)])
		if idx < real_ids.size() - 1:
			# NOT the last gift: beacon still closed, still black phase
			if b.is_open() or _count(ev, EventsScript.EV_BEACON_OPENED) != 0:
				f.append("seed %d level %d: beacon opened before the last real black gift (slot %d of %d)"
						% [seed, level, i, real_ids.size()])
			if g.phase != GiftsScript.PHASE_BLACK:
				f.append("seed %d level %d: phase flipped to %s before the last black gift"
						% [seed, level, g.phase])

	# after the last gift: the beacon opens exactly then, on the same tick
	if not b.is_open():
		f.append("seed %d level %d: beacon still CLOSED after the last real black gift" % [seed, level])
	if g.phase != GiftsScript.PHASE_GOLD:
		f.append("seed %d level %d: phase %s after the last black gift, want gold" % [seed, level, g.phase])
	if black_events != real:
		f.append("seed %d level %d: %d black gift events for %d real slots" % [seed, level, black_events, real])

	# A5 core: gold gifts exist at EXACTLY the same slot ids / positions, uncollected
	for i in g.slots.size():
		if g.slot_pos(i) != pos_before[i]:
			f.append("seed %d level %d: slot %d position moved in the gold phase" % [seed, level, i])
		if not g.is_real(i):
			if GiftsScript.bit_get(g.gold_taken, i):
				f.append("seed %d level %d: mine slot %d has gold state" % [seed, level, i])
			continue
		if g.collected(i):
			f.append("seed %d level %d: gold gift at slot %d already collected at beacon open" % [seed, level, i])
	if g.remaining() != g.total_real:
		f.append("seed %d level %d: gold remaining %d != %d" % [seed, level, g.remaining(), g.total_real])



# ---- beacon entry: exactly 1 charge, capped, never more -------------------------

func _test_beacon_entry_charges(f: Array[String]) -> void:
	var got: Array = []
	for start in [0, 1, 2]:
		var ctl = ControllerScript.new()
		ctl.setup("dasher", ControllerScript.load_constants())
		ctl.charges = start
		var beacon: RefCounted = BeaconScript.create({"beacon": [0, 0, 1]})
		beacon.open(0)
		ctl.x = 0.5
		ctl.y = 0.5
		ctl.z = 0.5   # the beacon tile centre: inside the cylinder
		var ev: Array = []
		if not beacon.try_enter(ctl, 1, 0, ev):
			f.append("beacon: entry refused at %d charges" % start)
		var want: int = mini(start + 1, 2)
		if ctl.charges != want:
			f.append("beacon: entry at %d charges gave %d, want exactly %d" % [start, ctl.charges, want])
		if _count(ev, EventsScript.EV_LEVEL_COMPLETE) != 1:
			f.append("beacon: %d level_complete events on entry, want 1" % _count(ev, EventsScript.EV_LEVEL_COMPLETE))
		var ee := _last(ev, EventsScript.EV_BEACON_ENTER)
		if ee.is_empty() or int(ee.get("charges", -1)) != want:
			f.append("beacon: beacon_enter event %s, want charges %d" % [str(ee), want])
		if not beacon.has_barrier(0):
			f.append("beacon: entry did not restore the Subspacial Barrier shield")
		got.append("%d->%d" % [start, ctl.charges])
		# latched: further ticks inside the cylinder change nothing
		for j in range(5):
			beacon.try_enter(ctl, 2 + j, 0, ev)
		if ctl.charges != want or _count(ev, EventsScript.EV_LEVEL_COMPLETE) != 1:
			f.append("beacon: repeated entry changed state (charges %d, %d completes)"
					% [ctl.charges, _count(ev, EventsScript.EV_LEVEL_COMPLETE)])
	print("BEACON entry restores exactly 1 charge: %s, capped, latched" % " ".join(got))
	# never more: ten entries on fresh beacons from a full purse stay at 2
	var ctl2 = ControllerScript.new()
	ctl2.setup("dasher", ControllerScript.load_constants())
	ctl2.charges = 2
	ctl2.x = 0.5
	ctl2.y = 0.5
	ctl2.z = 0.5
	for j in range(10):
		var beacon2: RefCounted = BeaconScript.create({"beacon": [0, 0, 1]})
		beacon2.open(0)
		beacon2.try_enter(ctl2, j, 0, [])
		if ctl2.charges > 2:
			f.append("beacon: charges exceeded the cap (%d)" % ctl2.charges)
	if ctl2.charges != 2:
		f.append("beacon: entry at a full purse gave %d, want 2" % ctl2.charges)
	# Hungry Void: cap 1 (D-052)
	var ctl3 = ControllerScript.new()
	ctl3.setup("dasher", ControllerScript.load_constants())
	ctl3.set_charge_cap(1)
	ctl3.charges = 0
	ctl3.x = 0.5
	ctl3.y = 0.5
	ctl3.z = 0.5
	var beacon3: RefCounted = BeaconScript.create({"beacon": [0, 0, 1]})
	beacon3.open(0)
	beacon3.try_enter(ctl3, 0, 0, [])
	if ctl3.charges != 1:
		f.append("beacon: Hungry Void entry at 0 gave %d, want 1" % ctl3.charges)
	# refused: closed beacon, outside the cylinder, above the cylinder
	var ctl4 = ControllerScript.new()
	ctl4.setup("dasher", ControllerScript.load_constants())
	ctl4.charges = 1
	ctl4.x = 0.5
	ctl4.y = 0.5
	ctl4.z = 0.5
	var beacon4: RefCounted = BeaconScript.create({"beacon": [0, 0, 1]})
	var out: Array = []
	if beacon4.try_enter(ctl4, 0, 0, out) or ctl4.charges != 1 or not out.is_empty():
		f.append("beacon: a CLOSED beacon accepted entry")
	beacon4.open(0)
	ctl4.x = 3.7   # horizontal distance 3.2 > 1.5
	ctl4.y = 0.5
	ctl4.z = 0.5
	if beacon4.try_enter(ctl4, 0, 0, out) or ctl4.charges != 1:
		f.append("beacon: entry accepted outside the 1.5 u cylinder")
	ctl4.x = 0.5
	ctl4.y = 0.5 + 3.5   # above the 3 u trigger height
	if beacon4.try_enter(ctl4, 0, 0, out) or ctl4.charges != 1:
		f.append("beacon: entry accepted above the 3 u trigger height")
	ctl4.y = 0.5 + 3.0   # the boundary is inside
	if not beacon4.try_enter(ctl4, 0, 0, out):
		f.append("beacon: entry refused at the cylinder boundary (y = floor + 3)")


# ---- pickup radius from stats ----------------------------------------------------

func _test_other_volumes(f: Array[String]) -> void:
	var c := ControllerScript.load_constants()
	if float(c["half_width"]) != 0.4 or float(c["height"]) != 1.8:
		f.append("body collision dimensions changed")
	if float(c["kill_plane_y"]) != -40.0:
		f.append("kill plane changed")
	if MinesScript.CONTACT_R != 0.9 or MinesScript.CONTACT_R2 != 0.81:
		f.append("mine contact changed")
	if BeaconScript.RADIUS != 1.5 or BeaconScript.HEIGHT != 3.0:
		f.append("beacon cylinder changed")

func _test_pickup_radius_stat(f: Array[String]) -> void:
	var level := _synthetic([0])
	level["gifts"][0]["x"] = 3   # slot at (3, 0): world (3.5, 1.0, 0.5)
	var lv: RefCounted = LevelStateScript.build(level, 1, 1)
	var g: RefCounted = lv.gifts
	if absf(g.pickup_radius() - 0.7) > 1e-9:
		f.append("pickup radius: base %.4f, want 0.7" % g.pickup_radius())
	# 0.806 u away: outside the base radius, inside the doubled radius.
	var p: Dictionary = lv.players[0]
	p["x"] = 2.7
	p["y"] = 0.0
	p["z"] = 0.5
	var ev: Array = []
	GiftsScript.tick(lv, 0, ev)
	if g.collected(0):
		f.append("pickup radius: collected from beyond the base radius")
	# the pickup_radius stat multiplier widens the ring (Long Reach is +40%/stack)
	var lv2: RefCounted = LevelStateScript.build(level, 1, 1)
	lv2.gifts.pickup_mult = 2.0
	var p2: Dictionary = lv2.players[0]
	p2["x"] = 2.7
	p2["y"] = 0.0
	p2["z"] = 0.5
	GiftsScript.tick(lv2, 0, ev)
	# the pickup flips the phase (single real gift); check the black bitset
	if not GiftsScript.bit_get(lv2.gifts.black_taken, 0) or lv2.gifts.phase != GiftsScript.PHASE_GOLD:
		f.append("pickup radius: stat multiplier 2.0 did not widen the pickup")
	# the base radius boundary, bracketed tightly around the shipped 0.7 u (the body centre
	# sits 0.1 u below the gift, so the distance is sqrt(dx^2 + 0.01)):
	#   inside:  0.69 u horizontal -> 0.6972 u <= 0.7
	#   outside: 0.70 u horizontal -> 0.7071 u >  0.7
	var lv3: RefCounted = LevelStateScript.build(level, 1, 1)
	var p3: Dictionary = lv3.players[0]
	p3["x"] = 3.5 - 0.69
	p3["y"] = 0.0
	p3["z"] = 0.5
	GiftsScript.tick(lv3, 0, ev)
	if not GiftsScript.bit_get(lv3.gifts.black_taken, 0):
		f.append("pickup radius: 0.6972 u (just inside the 0.7 u ring) not collected")
	var lv3b: RefCounted = LevelStateScript.build(level, 1, 1)
	var p3b: Dictionary = lv3b.players[0]
	p3b["x"] = 3.5 - 0.70
	p3b["y"] = 0.0
	p3b["z"] = 0.5
	GiftsScript.tick(lv3b, 0, ev)
	if GiftsScript.bit_get(lv3b.gifts.black_taken, 0):
		f.append("pickup radius: 0.7071 u (just outside the 0.7 u ring) was collected")
	# The old 0.4 radius misses this point; the new radius collects it.
	var lv4: RefCounted = LevelStateScript.build(level, 1, 1)
	lv4.players[0]["x"] = 2.95
	lv4.players[0]["y"] = 0.0
	lv4.players[0]["z"] = 0.5
	lv4.gifts.pickup_mult = 0.4 / 0.7
	GiftsScript.tick(lv4, 0, [])
	if GiftsScript.bit_get(lv4.gifts.black_taken, 0):
		f.append("pickup radius: old-radius control collected outside 0.4")
	lv4.gifts.pickup_mult = 1.0
	GiftsScript.tick(lv4, 0, [])
	if not GiftsScript.bit_get(lv4.gifts.black_taken, 0):
		f.append("pickup radius: expanded radius missed at 0.559")


# ---- the state hash pins the pickup ring (C4 review finding 1) ------------------

## The dump's GIFTS line and the hash of a fresh level-1 RunState whose gift ring is
## `base` x `mult`. Everything else is identical, so only the ring can move the hash.
func _ring_hash(base: float, mult: float) -> Array:
	var lvl: Dictionary = VoidGenScript.generate(1, 1, 1, 0)
	var rs = RunStateScript.new_run(1, 1, [])
	rs.load_level(lvl, 1)
	if base >= 0.0:
		rs.level.gifts.base_pickup_radius = base
	rs.level.gifts.pickup_mult = mult
	var gline := ""
	for line in HashScript.dump(rs):
		if line.begins_with("GIFTS "):
			gline = line
	return [HashScript.sha256(rs), gline]


## Item 6 moved the base radius from a constant to economy.json, but the GIFTS line carried
## only phase and bitsets: two states with base radii 0.4 and 0.7 hashed the same while the
## same input between those radii collected in only one. Same bug class as the B10 collapse
## collision - the hash must pin the configuration, not just the live schedule.
func _test_hash_pins_pickup_radius(f: Array[String]) -> void:
	var shipped := _ring_hash(-1.0, 1.0)   # -1: keep the radius create() read from the data
	var a := _ring_hash(0.4, 1.0)
	var b := _ring_hash(0.7, 1.0)
	if str(shipped[1]) == "":
		f.append("ring hash: no GIFTS line in the dump")
		return
	if a[0] == b[0]:
		f.append("ring hash: base radii 0.4 and 0.7 hash the same (the review collision)")
	if _ring_hash(0.7, 1.4)[0] == b[0]:
		f.append("ring hash: stat multipliers 1.4 and 1.0 hash the same")
	if _ring_hash(0.7, 1.0)[0] != b[0]:
		f.append("ring hash: the same ring hashed differently twice")
	# the shipped value is what is hashed: the economy.json number, as float bits
	var econ: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GiftsScript.ECONOMY_DATA))
	var want := float(econ["gold_phase"]["gift_pickup_radius"])
	var parts := str(shipped[1]).split(" ")
	if parts.size() != 9:
		f.append("ring hash: GIFTS line has %d fields, want 9: %s" % [parts.size(), shipped[1]])
	elif parts[4] != HashScript.bits(want) or parts[5] != HashScript.bits(1.0):
		f.append("ring hash: GIFTS line %s does not carry the shipped radius %s x 1.0"
				% [shipped[1], HashScript.bits(want)])
	if absf(want - 0.7) > 1e-9:
		f.append("ring hash: shipped gift_pickup_radius %.4f, want 0.7" % want)
	if shipped[0] != b[0]:
		f.append("ring hash: the shipped state and an explicit 0.7 ring hash differently")


## The collapse drops a gift whose tile fell (world.gd _collapse_sweep -> gifts.lose()), which
## moves remaining(), all_black_collected() and the pickup loop - but the GIFTS line carried
## only the taken bitsets, so a run that lost a gift hashed the same as one that did not.
## Same hole the pickup ring had; found by the C4 review-fixes worker and left for this leg.
func _test_hash_pins_lost_gifts(f: Array[String]) -> void:
	var lvl: Dictionary = VoidGenScript.generate(1, 1, 1, 0)
	var rs = RunStateScript.new_run(1, 1, [])
	rs.load_level(lvl, 1)
	var before: String = HashScript.sha256(rs)
	var gline_before := ""
	for line in HashScript.dump(rs):
		if line.begins_with("GIFTS "):
			gline_before = line
	# lose the first real slot, exactly as the collapse sweep does
	var lost_one := -1
	for i in rs.level.gifts.slots.size():
		if rs.level.gifts.is_real(i):
			lost_one = i
			break
	if lost_one < 0:
		f.append("lost hash: the level has no real gift slot to lose")
		return
	if not rs.level.gifts.lose(lost_one):
		f.append("lost hash: lose(%d) refused a real slot" % lost_one)
		return
	var after: String = HashScript.sha256(rs)
	var gline_after := ""
	for line in HashScript.dump(rs):
		if line.begins_with("GIFTS "):
			gline_after = line
	if before == after:
		f.append("lost hash: losing gift slot %d did not move the state hash" % lost_one)
	if gline_before == gline_after:
		f.append("lost hash: the GIFTS line is identical after a loss: %s" % gline_before)
	# the lost bitset is the field that moved, and it is the 7th (index 6)
	var pb := gline_before.split(" ")
	var pa := gline_after.split(" ")
	if pb.size() == 9 and pa.size() == 9:
		if pb[6] == pa[6]:
			f.append("lost hash: the lost bitset field did not change (%s)" % pb[6])
		if pb[1] != pa[1] or pb[2] != pa[2]:
			f.append("lost hash: a loss changed the taken bitsets, which it must not")
	# and the same loss twice hashes the same
	var again: String = HashScript.sha256(rs)
	if again != after:
		f.append("lost hash: the same lost state hashed differently twice")


# ---- straggler rule: the last 20% of REAL gifts, hazards never ------------------

func _test_straggler_threshold(f: Array[String]) -> void:
	# 10 slots, 8 real (ids 0..3, 5..8) + 2 mines (ids 4 and 9, occ == 1)
	var occs: Array = [0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
	var level := _synthetic(occs)
	var lv: RefCounted = LevelStateScript.build(level, 1, 1)
	var g: RefCounted = lv.gifts
	if g.total_real != 8:
		f.append("straggler: total_real %d, want 8 (mines excluded)" % g.total_real)
		return
	# total 8 -> the beam starts when remaining * 5 <= 8, i.e. exactly 1 remains
	var real_ids: Array = [0, 1, 2, 3, 5, 6, 7, 8]
	for idx in range(real_ids.size() - 1):
		var i: int = real_ids[idx]
		g.collect(i, idx, 0, [])
		var rem: int = g.remaining()
		var ids: Array = g.straggler_ids()
		if rem * GiftsScript.STRAGGLER_DEN <= g.total_real:
			if ids.size() != rem:
				f.append("straggler: %d remaining but %d beams" % [rem, ids.size()])
			for s_id in ids:
				if not g.is_real(int(s_id)) or g.collected(int(s_id)):
					f.append("straggler: slot %d must never be highlighted" % int(s_id))
		elif not ids.is_empty():
			f.append("straggler: %d remaining (%.0f%%) already lit %d beams" % [rem, 100.0 * rem / 8.0, ids.size()])
	if g.remaining() != 1 or g.straggler_ids() != [8]:
		f.append("straggler: 1 remaining should light exactly slot 8 (got %s)" % str(g.straggler_ids()))
	# hazards are never collectible and never counted
	for m in [4, 9]:
		if g.collected(m):
			f.append("straggler: mine slot %d counted as collectible" % m)
	g.collect(4, 99, 0, [])
	if g.remaining() != 1 or g.straggler_ids() != [8]:
		f.append("straggler: collecting a mine slot changed the straggler state (%d, %s)"
				% [g.remaining(), str(g.straggler_ids())])
	# the last black gift flips to gold: 8 gold at the 8 slots, none lit (8 > 20% of 8)
	g.collect(8, 100, 0, [])
	if g.phase != GiftsScript.PHASE_GOLD or g.remaining() != 8:
		f.append("straggler: gold phase remaining %d, want 8 at the same slots" % g.remaining())
	if not g.straggler_ids().is_empty():
		f.append("straggler: gold beams at %d remaining > 20%%" % g.remaining())


# ---- slot_pos confinement: no other sim/core file computes gift positions -------

func _test_slot_pos_confinement(f: Array[String]) -> void:
	for dir_path in ["res://sim", "res://core"]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			f.append("confinement: cannot open %s" % dir_path)
			continue
		for fn in dir.get_files():
			if not fn.ends_with(".gd") or fn == "gifts.gd":
				continue
			var text := FileAccess.get_file_as_string(dir_path + "/" + fn)
			if text.contains("slot_pos"):
				f.append("confinement: %s/%s computes gift positions (slot_pos outside sim/gifts.gd)" % [dir_path, fn])


# ---- the three view scripts load and sync ---------------------------------------

func _test_views(f: Array[String]) -> void:
	var occs: Array = [0, 0, 1, 0]
	var level := _synthetic(occs)
	var lv: RefCounted = LevelStateScript.build(level, 1, 1)
	var gv = load("res://view/gifts_view.gd")
	if gv == null:
		f.append("views: gifts_view.gd failed to load")
	else:
		var v = gv.new()
		v.setup(level, lv.gifts)
		v.sync()
		v.free()
	var bv = load("res://view/beacon_view.gd")
	if bv == null:
		f.append("views: beacon_view.gd failed to load")
	else:
		var v2 = bv.new()
		v2.setup(level)
		v2.set_progress(3, 3)
		v2.set_open(true)
		v2.sync_from(lv.beacon, lv.gifts)
		v2.free()
	var sb = load("res://view/straggler_beam.gd")
	if sb == null:
		f.append("views: straggler_beam.gd failed to load")
	else:
		var v3 = sb.new()
		v3.setup(lv.gifts)
		lv.gifts.collect(0, 0, 0, [])
		lv.gifts.collect(1, 1, 0, [])
		v3.sync()
		v3.free()
