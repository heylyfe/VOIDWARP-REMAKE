extends RefCounted
#
# sim/beacon.gd - the beacon state machine (ticket T-020; TERRAIN_SPEC.md
# section 6.1, DESIGN.md sections 3 and 3.1).
#
# CLOSED at level start -> OPEN exactly when the last real black gift is
# collected (sim/gifts.gd flips the phase and calls open() on the same tick).
# Entering the OPEN beacon's trigger cylinder:
#   - restores exactly 1 void charge, capped at the player's charge cap
#     (2, or 1 under Hungry Void) - via controller.beacon_enter, the tested
#     T-012 API (the charge never comes from anywhere else);
#   - restores the Subspacial Barrier shield (one per level, D-051; T-021
#     consumes it on tripmine contact - until that ticket wires consumption,
#     the shield state lives here as a per-player flag);
#   - completes the level: the level_complete event fires exactly once, on the
#     first entry tick. A level is complete ONLY by entering the open beacon
#     (DESIGN.md section 3); no timer ends a level.
#
# The trigger is a cylinder of radius 1.5 u, height 3 u, centred on the beacon
# tile; it never blocks movement (collision never sees it).
#
# Pure sim: no engine types beyond Array/Dictionary, no RNG.

const EventsScript := preload("res://sim/events.gd")

const RADIUS := 1.5
const HEIGHT := 3.0

var opened := false
var completed := false
## World centre of the beacon tile (x + 0.5, z + 0.5) and its floor height
## (y * 0.5) - read from Level.beacon [x, z, y] once, in create().
var cx := 0.5
var cz := 0.5
var base_y := 0.5
## Subspacial Barrier shields held, per player index (D-T051: 1 per level,
## restored on beacon entry). Default false until the content layer grants one.
var barriers := {}


static func create(level: Dictionary) -> RefCounted:
	var b := new()
	var bp: Array = level.get("beacon", [0, 0, 1])
	b.cx = float(int(bp[0])) + 0.5
	b.cz = float(int(bp[1])) + 0.5
	b.base_y = float(int(bp[2])) * 0.5
	return b


func is_open() -> bool:
	return opened


func is_closed() -> bool:
	return not opened


## Flips to OPEN; returns the beacon_opened event (player -1: a world event).
func open(tick: int) -> Dictionary:
	if opened:
		return {}
	opened = true
	var ev := EventsScript.make(EventsScript.EV_BEACON_OPENED, tick, -1)
	return ev


## Inside the trigger cylinder: horizontal distance from the beacon axis
## <= 1.5 u and the feet between the beacon floor and floor + 3 u.
func contains(px: float, py: float, pz: float) -> bool:
	var dx: float = px - cx
	var dz: float = pz - cz
	if dx * dx + dz * dz > RADIUS * RADIUS:
		return false
	return py >= base_y and py <= base_y + HEIGHT


# ---- Subspacial Barrier shield (storage; T-021 consumes on mine contact) ------

func has_barrier(player_index: int) -> bool:
	return barriers.get(player_index, false)


## True when a shield was held and is now consumed (the T-021 contact ladder).
func consume_barrier(player_index: int) -> bool:
	if not has_barrier(player_index):
		return false
	barriers[player_index] = false
	return true


# ---- entry ---------------------------------------------------------------------

## Controller-driven entry (the real play path; the caller runs this every tick
## after the controller's step). Restores exactly 1 charge via the controller's
## own beacon_enter, restores the shield, completes the level once.
func try_enter(ctl, tick: int, player_index: int, events: Array) -> bool:
	if not opened or completed or ctl == null or bool(ctl.dead):
		return false
	if not contains(ctl.x, ctl.y, ctl.z):
		return false
	# T-080: the before/after pair the charge_restored record needs (the restore is
	# capped at the charge cap, so before may equal after at a full pip bar).
	var before: int = int(ctl.charges)
	ctl.beacon_enter()
	var ev := EventsScript.make(EventsScript.EV_BEACON_ENTER, tick, player_index)
	ev["charges"] = int(ctl.charges)
	ev["charges_before"] = before
	events.append(ev)
	barriers[player_index] = true
	completed = true
	events.append(EventsScript.make(EventsScript.EV_LEVEL_COMPLETE, tick, player_index))
	return true
