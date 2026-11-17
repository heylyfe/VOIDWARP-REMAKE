extends RefCounted
#
# sim/mines.gd - the tripmine entity (ticket T-021; DESIGN.md section 3.3 with
# D-058, the D-051 counter-play ruling, TERRAIN_SPEC.md section 6.8).
#
# HAZARD SPAWN RULE (owner spec, verbatim): hazards that replace gifts inherit
# validated gift spawn positions - never their own placement logic. The mine set
# is EXACTLY the Level.gifts slots with occ == 1: the terrain generator rolled
# them (stream MINE, TERRAIN_SPEC 6.8, with the D-026 walkable-bypass guarantee
# and the 20% hard cap). There is no placement code here and no own position:
# every mine point below is read straight from the slot dict - the tile centre
# (x + 0.5, z + 0.5), and the box point lifts that centre to the section 6.7
# occupancy height (y*0.5 + 1.0). (D-T020-1: consumers read Level.gifts directly
# or through sim/gifts.gd; no second placement source exists.)
#
# CONTACT (D-058, verbatim rule): the player's CENTRE within 0.9 u HORIZONTAL
# distance of the box at ANY height - jumping over a mine does not avoid
# contact. A tripmine is a wall on its tile: the walkable bypass (a route that
# stays outside the 0.9 u trigger cylinder, TERRAIN_SPEC 6.8.1-6.8.2) is the
# only way past. The test is height-blind on purpose: dx*dx + dz*dz <= 0.81.
# No collision prop is added - the trigger cylinder IS the wall (D-T021-2).
#
# CONTACT LADDER (DESIGN.md section 3.3, fixed order, D-058):
#   1. defuse roll (Defuse Kit, D-051): roll = mix(mix(run_seed, level), slot_id)
#      mod 100; pass when roll < 20 x stacks (cap 60). PASS: the mine is
#      consumed, there is no blast and no death, the chain resets. 0 stacks can
#      never pass. The roll is a pure function of (run_seed, level, slot_id,
#      stacks) - every client computes the same outcome.
#   2. Subspacial Barrier (D-051): a held shield is consumed, the mine is
#      consumed with no blast, the chain resets. Tripmines only - nothing
#      absorbs the blast.
#   3. Last Light (DESIGN.md 3.1): unspent + >= 1 charge held -> spent as the
#      final save (teleport to the beacon dais); the mine is consumed.
#   4. otherwise killed D-MINE. The blast (radius 3 u, KILLS) then hits every
#      OTHER player whose centre is within 3 u of the mine point; each victim
#      runs shield -> Last Light -> death (the defuse roll already failed for
#      this mine; victims re-roll nothing - D-T021-4).
#
# Killed/suppressed handling: while respawn invulnerability or Last Light
# invulnerability holds, tripmines do not kill (DESIGN.md 3.1), so an invulnerable
# player neither triggers the ladder nor consumes the mine (D-T021-5).
#
# Pure sim: no engine types beyond Array/Dictionary/PackedByteArray, no RNG
# instance (the defuse roll calls the terrain mix function directly), fixed
# 60 Hz tick. Contact runs controller-driven (the same pattern as beacon entry,
# D-T020-4): the owner of the controller calls tick() after the controller's
# step; the T-010 placeholder path in sim.gd does not.

const VoidRngScript := preload("res://terrain/void_rng.gd")
const EventsScript := preload("res://sim/events.gd")
const DeathScript := preload("res://sim/death.gd")
const GiftsScript := preload("res://sim/gifts.gd")

## Contact trigger cylinder radius (DESIGN.md 3.3): 0.9 u horizontal, any height.
const CONTACT_R := 0.9
## CONTACT_R squared (0.81) so the test stays in * and <=.
const CONTACT_R2 := 0.81
## Tell distance (DESIGN.md 3.3): beyond 12 u the mine shows a black gift's rim
## glow; inside 12 u the pink particles and the six-pointed star are the tell.
const TELL_DISTANCE := 12.0
## Blast radius (DESIGN.md 3.3): kills what it reaches.
const BLAST_RADIUS := 3.0
## Defuse Kit (D-051): 20 % per stack, cap 60 %.
const DEFUSE_PCT := 20
const DEFUSE_CAP := 60
## T-080 bypass detection (the owner's "bypass passed within 0.5 u of a mine"):
## the player's centre inside 0.9 + 0.5 = 1.4 u of a live mine's centre (horizontal)
## and out again without contact -> one mine_pass record (payload: slot, closest).
const PASS_R := 1.4

## The slot dict it occupies: read-only shared data (the Level.gifts rows).
var slots: Array = []
## The slot ids that carry a mine (occ == 1), ascending - the generator's set.
var ids: Array = []
## Consumed mines by slot id (defused / shielded / saved / detonated): a bitset
## like the gift bitsets; joins the state hash (D-T021-3).
var consumed := PackedByteArray()
var run_seed: int = 0
var level_number: int = 0
## T-080: the per-player bypass tracker, {"in": bool, "slot": int, "closest": float} —
## live state of ONE level (reset by create() per level); deterministic, controller-driven.
var pass_state: Dictionary = {}


static func create(level: Dictionary, p_level_number: int, p_run_seed: int) -> RefCounted:
	var m := new()
	m.slots = level.get("gifts", [])
	m.level_number = p_level_number
	m.run_seed = p_run_seed & VoidRngScript.M32
	var n: int = m.slots.size()
	m.consumed.resize((n + 7) >> 3)
	var id: int = 0
	for s in m.slots:
		if int(s["occ"]) == 1:
			m.ids.append(id)
		id += 1
	return m


func count() -> int:
	return ids.size()


func is_consumed(slot_id: int) -> bool:
	return slot_id >= 0 and (consumed[slot_id >> 3] & (1 << (slot_id & 7))) != 0


func consume(slot_id: int) -> void:
	consumed[slot_id >> 3] |= 1 << (slot_id & 7)


## The mine's world point: the slot's tile centre lifted to the section 6.7
## occupancy height (x + 0.5, y*0.5 + 1.0, z + 0.5) - the point the view renders
## and the blast measures from. Contact itself only uses the x/z of it.
func point(slot_id: int) -> Vector3:
	var s: Dictionary = slots[slot_id]
	return Vector3(float(int(s["x"])) + 0.5, float(int(s["y"])) * 0.5 + 1.0, float(int(s["z"])) + 0.5)


## The first (lowest slot id) live mine whose trigger cylinder contains the
## horizontal point (px, pz) at any height; -1 when none. Height never enters.
func contact_at(px: float, pz: float) -> int:
	for slot_id in ids:
		if is_consumed(slot_id):
			continue
		var c: Vector3 = point(slot_id)
		var dx: float = px - c.x
		var dz: float = pz - c.z
		if dx * dx + dz * dz <= CONTACT_R2:
			return slot_id
	return -1


## The defuse roll (D-051), verbatim: mix(mix(run_seed, level), slot_id) mod 100
## < 20 x stacks, capped at 60. stacks <= 0 -> the roll can never pass.
static func defuse_roll(p_run_seed: int, p_level: int, slot_id: int, stacks: int) -> bool:
	if stacks <= 0:
		return false
	var roll: int = VoidRngScript.mix(VoidRngScript.mix(p_run_seed & VoidRngScript.M32, p_level), slot_id) % 100
	return roll < mini(DEFUSE_PCT * stacks, DEFUSE_CAP)


## Nearest (horizontal) live mine to (px, pz): Vector2(distance, slot id); distance -1.0
## when no live mine exists (T-080, the bypass tracker's probe).
func nearest_dist(px: float, pz: float) -> Vector2:
	var best := -1.0
	var best_slot := -1
	for slot_id in ids:
		if is_consumed(slot_id):			continue
		var c: Vector3 = point(slot_id)
		var dx: float = px - c.x
		var dz: float = pz - c.z
		var d: float = sqrt(dx * dx + dz * dz)
		if best < 0.0 or d < best:
			best = d
			best_slot = slot_id
	return Vector2(best, best_slot)


## One 60 Hz pass over every player (call after the controllers' step).
##   ctls:   one controller per player index (or a null entry to skip that
##           player - the T-010 placeholder rows pass nulls);
##   stacks: defuse stacks per player index (the Defuse Kit purchase count).
static func tick(lv, ctls: Array, w: Dictionary, stacks: Array, tick: int,
		events: Array) -> void:
	var mines: RefCounted = lv.mines
	if mines == null or mines.count() == 0:
		return
	for i in lv.players.size():
		if i >= ctls.size() or ctls[i] == null:
			continue
		var ctl = ctls[i]
		if bool(ctl.dead) or ctl.respawn_t >= 0.0 or ctl.invuln > 0.0:
			continue
		var near: Vector2 = mines.nearest_dist(float(ctl.x), float(ctl.z))
		var slot: int = int(mines.contact_at(float(ctl.x), float(ctl.z)))
		if slot < 0:
			_pass_track(mines, i, near, tick, events)
			continue
		# a contact ends any open bypass approach for this player: the mine's fate was
		# the ladder below (defused / shielded / saved / killed), never a clean pass
		mines.pass_state[i] = {"in": false, "slot": -1, "closest": 0.0}
		var stacks_i: int = int(stacks[i]) if i < stacks.size() else 0
		_contact(lv, ctls, w, i, ctl, slot, stacks_i, tick, events)
	# T-080: a mine kill is its own proximity proof - the contact (and the blast) happen
	# at the player's centre, so the killer is on screen by construction. This array
	# carries only this tick's mine events (the caller passes a per-tick list).
	for ev in events:
		if str(ev.get("e", "")) == "death" and not (ev as Dictionary).has("on_screen"):
			ev["on_screen"] = true


## The T-080 bypass tracker (owner spec: "logged when the player's centre comes within
## 0.9 u + 0.5 u = 1.4 u of a live mine centre and leaves again without contact").
## Enter/track/leave all from the horizontal distance only; a pass is emitted once,
## on leaving, unless the mine was consumed in the meantime (a contact happened).
static func _pass_track(mines, i: int, near: Vector2, tick: int, events: Array) -> void:
	var lv_pass: Dictionary = mines.pass_state
	if near.x < 0.0 or near.x > PASS_R:
		var st: Dictionary = lv_pass.get(i, {})
		if bool(st.get("in", false)):
			var slot: int = int(st["slot"])
			if not mines.is_consumed(slot):
				var ev := EventsScript.make(EV_MINE, tick, i)
				ev["slot"] = slot
				ev["closest"] = float(st["closest"])
				events.append(ev)
			lv_pass[i] = {"in": false, "slot": -1, "closest": 0.0}
		return
	var prev: Dictionary = lv_pass.get(i, {})
	if bool(prev.get("in", false)) and int(prev.get("slot", -1)) == int(near.y):
		prev["closest"] = minf(float(prev["closest"]), near.x)
		return
	lv_pass[i] = {"in": true, "slot": int(near.y), "closest": near.x}


## The mine_pass event kind (T-080; the ladder's kinds are unchanged).
const EV_MINE := "mine_pass"


## The contact ladder for player i on mine slot (the fixed order of D-058).
static func _contact(lv, ctls: Array, w: Dictionary, i: int, ctl,
		slot: int, stacks: int, tick: int, events: Array) -> String:
	var mines: RefCounted = lv.mines
	# the contact itself (radar / HUD surface; the ladder decides the outcome)
	var evc := EventsScript.make(EV_MINE_CONTACT, tick, i)
	evc["slot"] = slot
	events.append(evc)
	# the mine is consumed by every non-invulnerable contact outcome below
	mines.consume(slot)
	# 1. defuse roll (D-051): consumed, no blast, no death, chain resets.
	if defuse_roll(mines.run_seed, mines.level_number, slot, stacks):
		var ev1 := EventsScript.make(EV_MINE_DEFUSED, tick, i)
		ev1["slot"] = slot
		ev1["stacks"] = stacks
		events.append(ev1)
		_chain_reset(events, tick, i, "defused_mine")
		return "defused"
	# 2. Subspacial Barrier (D-051): shield consumed, no blast, chain resets.
	var beacon: RefCounted = lv.beacon
	if beacon != null and bool(beacon.consume_barrier(i)):
		var ev2 := EventsScript.make(EV_MINE_SHIELDED, tick, i)
		ev2["slot"] = slot
		events.append(ev2)
		_chain_reset(events, tick, i, "shielded_mine")
		return "shielded"
	# 3.+4. Last Light, else death - both live inside controller.try_kill
	# (D-057): it spends the save when armed (teleport to the dais) and kills
	# D-MINE otherwise. The mine is consumed in both branches (section 3.3).
	var saved: bool = ctl.try_kill(DeathScript.MINE_CODE, DeathScript.killer_for(DeathScript.MINE_CODE),
			w, events)
	var ev3 := EventsScript.make(EV_MINE_DETONATED, tick, i)
	ev3["slot"] = slot
	ev3["blast_radius"] = BLAST_RADIUS
	if saved:
		ev3["result"] = "last_light"
		events.append(ev3)
		return "last_light"
	ev3["result"] = "death"
	events.append(ev3)
	# the blast kills every OTHER player within 3 u of the mine point; each
	# victim runs shield -> Last Light -> death, no defuse re-roll (D-T021-4)
	var mp: Vector3 = mines.point(slot)
	for j in lv.players.size():
		if j == i or j >= ctls.size() or ctls[j] == null:
			continue
		var other = ctls[j]
		if bool(other.dead) or other.respawn_t >= 0.0 or other.invuln > 0.0:
			continue
		var pp: Dictionary = lv.players[j]
		var dx: float = float(pp["x"]) - mp.x
		var dy: float = float(pp["y"]) + GiftsScript.BODY_CENTER - mp.y
		var dz: float = float(pp["z"]) - mp.z
		if dx * dx + dy * dy + dz * dz > BLAST_RADIUS * BLAST_RADIUS:
			continue
		_blast_victim(lv, w, j, other, tick, events)
	return "death"


## Steps 2..4 of the ladder for a blast victim (no defuse re-roll, D-T021-4).
static func _blast_victim(lv, w: Dictionary, j: int, ctl, tick: int,
		events: Array) -> void:
	var beacon: RefCounted = lv.beacon
	if beacon != null and bool(beacon.consume_barrier(j)):
		var ev2 := EventsScript.make(EV_MINE_SHIELDED, tick, j)
		ev2["slot"] = -1
		events.append(ev2)
		_chain_reset(events, tick, j, "shielded_mine")
		return
	ctl.try_kill(DeathScript.MINE_CODE, DeathScript.killer_for(DeathScript.MINE_CODE), w, events)


## The chain-breaking events of DESIGN.md section 3.2 (T-022 consumes them).
static func _chain_reset(events: Array, tick: int, player_index: int, why: String) -> void:
	events.append({"e": "chain_reset", "why": why, "tick": tick, "player": player_index})


# Contact / outcome event kinds ("e" values; controller-layer events like the
# chain_reset raw dicts above - the typed sim events of events.gd carry the
# same strings for the sim-level path).
const EV_MINE_CONTACT := "mine_contact"
const EV_MINE_DEFUSED := "mine_defused"
const EV_MINE_SHIELDED := "mine_shielded"
const EV_MINE_DETONATED := "mine_detonated"
