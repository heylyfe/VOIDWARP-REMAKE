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
## the footprint map read positions through this wrapper; the slot_pos confinement
## scan keeps the section 6.7 formula in this file only).
func position_of(i: int) -> Vector3:
	return slot_pos(i)


func is_real(i: int) -> bool:
	return int(slots[i]["occ"]) == 0


## Effective pickup radius for the current pickup_radius stat multiplier.
func pickup_radius() -> float:
	return PICKUP_RADIUS * pickup_mult


## Feed the run's stats dict (the same dict the controller consumes via its own
## apply_stats; core/stats.gd semantics). The pickup_radius stat is a MULTIPLIER
## on the base radius (Long Reach: x1.4 per stack; the drop-in curse fixture:
## x1.1). A dict without the key (or no stats at all) leaves the canon 0.4 u
## ring. The value is clamped at 0: a negative radius reads as "never picks up",
## never as a bigger ring.
func apply_stats(p_stats: Dictionary) -> void:
	pickup_mult = maxf(0.0, float(p_stats.get("pickup_radius", 1.0)))


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

# ---- the vote ledger (FULL_GAME_PLAN.md gap 9) ---------------------------------
#
# The vote ledger is SIM STATE: which roster row holds how many collected votes
# for the NEXT level. One row per roster entry, keyed by whatever row id the
# lobby wrote into the ledger; sim stores and reads the counts, nothing else.
# The COUNT -> MINES arithmetic is the roster module's own job (each enemy row
# under res://content/enemies/ declares its per-vote weight and vote cap next
# to its other roster numbers): app/ reads the ledger here, the row weight in
# the roster module, and hands the result to terrain's generate() as its
# extra_mines argument (TERRAIN_SPEC section 6.8 clamps the applied count).
# sim names no roster entry and never loads content data - that separation is
# the boundary test's whole point (FLEET_PACK.md section 3).
#
# Pure: one dict in, one count out. An absent key, an empty key or a count
# below zero all read as no votes; sim never invents a vote.
## The run's whole vote ledger, read-only (gap 9): every collected count, keyed
## by whatever roster entry the lobby voted for. A ledger without a "votes"
## entry, or votes that are not a Dictionary, reads as no votes at all. Callers
## never mutate the returned copy.
static func run_votes(ledger: Dictionary) -> Dictionary:
	var votes: Variant = ledger.get("votes", {})
	return (votes as Dictionary).duplicate(true) if votes is Dictionary else {}


## One entry's collected-vote count, read from the ledger by the entry's own
## id-string (the ledger's keys are data; sim names none of them). Absent key,
## empty key or a count below zero read as no votes.
static func run_votes_for(ledger: Dictionary, gift_id: String) -> int:
	if gift_id.is_empty():
		return 0
	return maxi(0, int(run_votes(ledger).get(gift_id, 0)))
