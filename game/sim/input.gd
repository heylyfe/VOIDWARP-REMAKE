extends RefCounted
#
# PlayerInput (DESIGN.md section 13, rule 2; ticket T-010).
# The ONLY per-tick player inputs the sim accepts. World-space already: the client pre-rotates by
# its camera, the sim never sees a camera. Axis scale: -127..127 = -1..+1 of RUN_SPEED, clamped on
# construction (D-T010-2). Buttons is a bitmask: BUTTON_JUMP=1, BUTTON_ABILITY=2, BUTTON_INTERACT=4.
#
# A RefCounted instance is a value: sim/ treats inputs as immutable (nobody mutates one after it is
# handed to step()), so a recorded input array can be replayed as-is.

const BUTTON_JUMP := 1
const BUTTON_ABILITY := 2
const BUTTON_INTERACT := 4

## int8 signed range, but the axis contract (D-T010-2) caps the usable magnitude at 127.
const AXIS_MIN := -127
const AXIS_MAX := 127


var move_x: int = 0
var move_z: int = 0
var buttons: int = 0


func _init(p_move_x: int = 0, p_move_z: int = 0, p_buttons: int = 0) -> void:
	move_x = clampi(p_move_x, AXIS_MIN, AXIS_MAX)
	move_z = clampi(p_move_z, AXIS_MIN, AXIS_MAX)
	buttons = p_buttons


## Neutral input: standing still, no buttons. The sim substitutes this when an input is missing.
static func neutral() -> RefCounted:
	return new(0, 0, 0)


## True when the button bit is held this tick.
func is_down(bit: int) -> bool:
	return (buttons & bit) != 0


## True when bit is held now but was NOT held on the previous tick (edge detect needs the caller's
## previous input; see sim.gd, which keeps prev_buttons in state for exactly this).
func pressed(bit: int, prev_buttons: int) -> bool:
	return (buttons & bit) != 0 and (prev_buttons & bit) == 0
