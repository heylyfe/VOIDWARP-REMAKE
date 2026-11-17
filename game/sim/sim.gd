extends RefCounted
#
# sim.gd — deterministic simulation core (DESIGN.md section 13; ticket T-010).
#   step(run_state, inputs) -> Array[Dictionary] events
#
# One fixed 60 Hz tick per call. Pure sim layer per the boundary scan: no scene-tree types, no
# engine physics, no clock, no engine random: the only inputs are the run seed + content set
# (held in RunState) and the per-tick PlayerInput
# array (one per player, index = player index). Missing inputs are replaced by the neutral input
# so replaying a shorter recorded list stays deterministic.
#
# KINEMATICS SCOPE (D-T010-4): this is the T-010 PLACEHOLDER integration — per-tick velocity from
# the move axes, gravity, jump on the JUMP press edge while grounded, and a column-lookup ground
# snap. sim/collision.gd + sim/controller.gd (ticket T-012) supersede it; the replay test keeps
# passing unchanged.

const InputScript := preload("res://sim/input.gd")
const EventsScript := preload("res://sim/events.gd")
# T-020: gift-slot pickup + the beacon open flip (beacon ENTRY is controller-
# driven via sim/beacon.gd try_enter - the T-010 placeholder rows carry no
# charge state, D-T020-4).
const GiftsScript := preload("res://sim/gifts.gd")

## D-012 movement constants (carried over from v1 unchanged).
const DT := 1.0 / 60.0
const GRAVITY := 32.0
const JUMP_VELOCITY := 12.0
const RUN_SPEED := 9.0
## Auto step-up 0.5 u = 1 HU (TERRAIN_SPEC.md section 5).
const STEP_UP := 0.5


static func step(rs: RefCounted, inputs: Array) -> Array:
	var lv: RefCounted = rs.level
	if lv == null:
		return []
	var events: Array = []
	for i in lv.players.size():
		_step_player(events, lv, i, _effective_input(i, inputs))
	lv.tick += 1
	return events


static func _effective_input(player_index: int, inputs: Array) -> RefCounted:
	if player_index < inputs.size() and inputs[player_index] is RefCounted:
		return inputs[player_index]
	return InputScript.neutral()


static func _step_player(events: Array, lv: RefCounted, i: int, inp: RefCounted) -> void:
	var p: Dictionary = lv.players[i]
	var prev_buttons: int = int(p["prev_buttons"])
	p["prev_buttons"] = int(inp.buttons)

	var was_grounded: bool = bool(p["grounded"])
	if inp.pressed(InputScript.BUTTON_JUMP, prev_buttons) and was_grounded:
		p["vy"] = JUMP_VELOCITY
		p["grounded"] = false
		events.append(EventsScript.make(EventsScript.EV_JUMP, lv.tick, i))

	if not bool(p["grounded"]):
		p["vy"] = float(p["vy"]) - GRAVITY * DT

	# Target velocity straight from the axes (D-T010-2): axis/127 x RUN_SPEED.
	p["vx"] = (float(inp.move_x) / 127.0) * RUN_SPEED
	p["vz"] = (float(inp.move_z) / 127.0) * RUN_SPEED

	# Integrate the proposal.
	var nx: float = float(p["x"]) + float(p["vx"]) * DT
	var ny: float = float(p["y"]) + float(p["vy"]) * DT
	var nz: float = float(p["z"]) + float(p["vz"]) * DT

	# Resolve against the target column (D-T010-4: column lookup, no swept collision).
	var gh: Variant = lv.ground_at(nx, nz)
	if gh != null:
		var g: float = float(gh)
		if was_grounded and g - float(p["y"]) > STEP_UP:
			# Wall higher than the step: cancel the horizontal move, stay in the old cell.
			nx = float(p["x"])
			nz = float(p["z"])
		elif was_grounded and g > float(p["y"]):
			# Auto step-up within 0.5 u: snap up, stay grounded.
			ny = g
			p["grounded"] = true

	var ground2: Variant = lv.ground_at(nx, nz)
	if ground2 != null:
		var g2: float = float(ground2)
		# Land only when crossing the surface from above this tick; never snap up out of a fall.
		if float(p["y"]) >= g2 and ny <= g2 and float(p["vy"]) <= 0.0:
			ny = g2
			if not was_grounded:
				events.append(EventsScript.make(EventsScript.EV_LAND, lv.tick, i))
			p["grounded"] = true
			p["vy"] = 0.0
		elif ny > g2 and was_grounded:
			# Walked off an edge (or the ground dropped below us): become airborne.
			p["grounded"] = false
			events.append(EventsScript.make(EventsScript.EV_FALL, lv.tick, i))

	p["x"] = nx
	p["y"] = ny
	p["z"] = nz

	# T-020: gift pickup from the settled position; the last real black gift
	# opens the beacon on the same tick (sim/beacon.gd owns the state machine).
	GiftsScript.tick(lv, i, events)
