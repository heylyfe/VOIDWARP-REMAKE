extends RefCounted
#
# sim/gifts.gd - gift slots, pickup and the straggler rule (ticket T-020;
# TERRAIN_SPEC.md section 6.7, DESIGN.md sections 3 / 3.2 / 3.3).
#
# A gift slot is a stable, identified position owned by the TERRAIN GENERATOR:
# every position here is read from Level.gifts ({id, x, z, y, piece, tier, occ}).
# No code outside game/terrain/ places a gift or invents a position; the only
# mapping applied outside terrain is section 6.7's world position of whatever
# occupies a slot, (x + 0.5, y*0.5 + 1.0, z + 0.5), and it lives ONLY in
# slot_pos() below.
#
# State = two bitsets by slot id (black collected, gold collected) + the phase:
#   black phase: every slot with occ == 0 carries one black gift.
#   gold phase:  entered exactly when the last black gift is collected; a gold
#                gift then exists at every slot that held a black gift - same
#                slot id, same position (TERRAIN_SPEC 6.7: zero placement logic).
#   occ == 1 slots hold a tripmine (T-021): never a gift, never collected, never
#   counted in remaining-gift totals, never highlighted (DESIGN.md section 3.3).
#
# Pure sim: no engine types beyond Array/Dictionary/Vector3/PackedByteArray, no
# RNG (the state is a pure function of the inputs), fixed 60 Hz tick via sim.gd.

const EventsScript := preload("res://sim/events.gd")

## Pickup radius at pickup_radius stat 1.0 (TERRAIN_SPEC.md section 6.7: 0.4 u).
const PICKUP_RADIUS := 0.4
## The pickup test point is the player's centre, feet + half the 1.8 u body
## (D-T020-2): the gift hovers 1.0 u over the tile top, so a feet-anchored
## radius could never reach it.
const BODY_CENTER := 0.9

## Straggler beam threshold (DESIGN.md section 3.3): the beam marks a gift when
## remaining_real * STRAGGLER_DEN <= total_real, i.e. at most the last 20% of
## REAL gifts. Hazards are excluded by construction (only occ == 0 slots count).
const STRAGGLER_DEN := 5

const PHASE_BLACK := "black"
const PHASE_GOLD := "gold"

## The slot array exactly as the generator wrote it (read-only shared data).
var slots: Array = []
## Number of REAL gift slots (occ == 0): the only denominator that counts.
var total_real: int = 0
var phase: String = PHASE_BLACK
## Bitsets indexed by slot id, one byte per 8 slots.
var black_taken := PackedByteArray()
var gold_taken := PackedByteArray()
## Skeleton Key's collection quota (T-053, D-T053-4): the beacon opens when at least
## this many REAL black gifts are collected instead of all of them; the uncollected
## ones enter the gold phase by the same flip (gold gifts at every black slot - the
## "rest turn gold in place" reading needs no second conversion). -1 = the default
## exact rule (every black gift collected); set only when the upgrade is owned.
var black_quota: int = -1
## Multiplier on the pickup radius, fed from the pickup_radius stat (core/stats.gd)
## by the content layer; 1.0 until the shop wiring (T-022) sets it.
var pickup_mult: float = 1.0


static func create(level: Dictionary) -> RefCounted:
	var g := new()
	g.slots = level.get("gifts", [])
	var n: int = g.slots.size()
	g.black_taken.resize((n + 7) >> 3)
	g.gold_taken.resize((n + 7) >> 3)
	var real: int = 0
	for s in g.slots:
		if int(s["occ"]) == 0:
			real += 1
	g.total_real = real
	return g


# ---- bitset helpers (PackedByteArray, bit per slot id) -------------------------

static func bit_set(bits: PackedByteArray, id: int) -> void:
	bits[id >> 3] |= 1 << (id & 7)


static func bit_get(bits: PackedByteArray, id: int) -> bool:
	return id >= 0 and (bits[id >> 3] & (1 << (id & 7))) != 0


# ---- geometry (the single section 6.7 mapping outside terrain/) ----------------

## World position of whatever occupies slot i: (x + 0.5, y*0.5 + 1.0, z + 0.5).
func slot_pos(i: int) -> Vector3:
	var s: Dictionary = slots[i]
	return Vector3(float(int(s["x"])) + 0.5, float(int(s["y"])) * 0.5 + 1.0, float(int(s["z"])) + 0.5)


## The T-053 readers' name for the same mapping (the radar queries / the
## cartographer read positions through this wrapper; the slot_pos confinement
## scan keeps the section 6.7 formula in this file only).
func position_of(i: int) -> Vector3:
	return slot_pos(i)


func is_real(i: int) -> bool:
	return int(slots[i]["occ"]) == 0


## Effective pickup radius for the current pickup_radius stat multiplier.
func pickup_radius() -> float:
	return PICKUP_RADIUS * pickup_mult


func collected(i: int) -> bool:
	if phase == PHASE_BLACK:
		return bit_get(black_taken, i)
	return bit_get(gold_taken, i)


func remaining() -> int:
	var n := 0
	for i in slots.size():
		if is_real(i) and not collected(i):
			n += 1
	return n


## True when the beacon-open condition holds: no real black gift left - or, with
## the Skeleton Key's quota (T-053, D-T053-4), at least black_quota of the REAL
## black gifts collected. The uncollected remainder goes gold by the same phase
## flip (gold gifts at every black slot, "the rest turn gold in place").
func all_black_collected() -> bool:
	if phase != PHASE_BLACK:
		return true
	var rem := 0
	for i in slots.size():
		if is_real(i) and not bit_get(black_taken, i):
			rem += 1
	if rem == 0:
		return true
	if black_quota >= 0:
		return (total_real - rem) >= black_quota
	return false


## The straggler rule (DESIGN.md section 3.3): when at most 20% of the REAL
## gifts of the current phase remain, those remainers light up; otherwise an
## empty list. Never contains an occ == 1 slot.
func straggler_ids() -> Array:
	var out: Array = []
	var rem := remaining()
	if rem * STRAGGLER_DEN > total_real:
		return out
	for i in slots.size():
		if is_real(i) and not collected(i):
			out.append(i)
	return out


# ---- per-tick pickup (called from sim.gd for every player, every tick) --------

static func tick(lv: RefCounted, player_index: int, events: Array) -> void:
	var g: RefCounted = lv.gifts
	if g == null or g.slots.is_empty():
		return
	var p: Dictionary = lv.players[player_index]
	var px: float = float(p["x"])
	var py: float = float(p["y"]) + BODY_CENTER
	var pz: float = float(p["z"])
	var r: float = g.pickup_radius()
	var r2: float = r * r
	var opened := false
	for i in g.slots.size():
		if not g.is_real(i) or g.collected(i):
			continue
		var pos: Vector3 = g.slot_pos(i)
		var dx: float = px - pos.x
		var dy: float = py - pos.y
		var dz: float = pz - pos.z
		if dx * dx + dy * dy + dz * dz <= r2:
			g.collect(i, lv.tick, player_index, events)
			if g.phase == PHASE_GOLD and not opened:
				opened = true
	if opened:
		# The last real black gift opens the beacon on the same tick
		# (DESIGN.md section 3 step 3); the beacon owns its state machine.
		var b: RefCounted = lv.beacon
		if b != null and not b.is_open():
			events.append(b.open(lv.tick))


func collect(i: int, tick: int, player_index: int, events: Array) -> void:
	if not is_real(i) or collected(i):
		return
	var was_black := phase == PHASE_BLACK
	if was_black:
		bit_set(black_taken, i)
		if all_black_collected():
			phase = PHASE_GOLD  # gold appears at the same slots, same tick
	else:
		bit_set(gold_taken, i)
	var ev := EventsScript.make(EventsScript.EV_GIFT_COLLECTED, tick, player_index)
	ev["slot"] = i
	ev["phase"] = "black" if was_black else PHASE_GOLD
	events.append(ev)
