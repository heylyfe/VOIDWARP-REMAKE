extends RefCounted
##
## view/player_gait.gd - the ONE gait the Antechamber's walker and the level's figure play
## (D-ANIM-15).
##
## The owner's ruling (U1): in-game idle/walk/run must be IDENTICAL to the lobby animation.
## The lobby's whole gait is four rigid limb nodes rotated about their joints, so it lives
## here as a pure function of (phase, amplitude) and BOTH call sites read it - the lobby's
## walker (view/lobby/lobby_player.gd) and the level's figure (app/world.gd). There is no
## second copy of these numbers anywhere, and the lobby is the reference: it must keep
## looking exactly as it does now.
##
## The gait: the phase advances at RATE rad/s scaled by the amplitude, and the four limbs
## take [swing, -swing, -swing, swing] - the arms counter the same-side leg. A limb hanging
## along -Y swings its tip BACKWARD for a positive X rotation, so ArmL and LegR go back
## together while ArmR and LegL come forward.
##
## Pure view: no sim state, no nodes, no clock of its own. The caller owns the phase.

const RATE := 10.5            # rad/s at full speed
const SWING := 0.9            # rad, limb swing amplitude at full speed
const LIMB_NAMES := ["ArmL", "ArmR", "LegL", "LegR"]


## 0..1: how much of the gait a ground speed plays. `run_speed` is the level's run speed
## (data/player.json shared_kit.run_speed), which the lobby uses too.
static func amplitude(speed: float, run_speed: float) -> float:
	return clampf(speed / maxf(run_speed, 0.001), 0.0, 1.0)


## The next phase: RATE scaled by the amplitude, wrapped to one cycle.
static func advance(phase: float, amp: float, delta: float) -> float:
	return fposmod(phase + RATE * amp * delta, TAU)


## The four limb angles (rad) at a phase and amplitude, in LIMB_NAMES order.
static func limb_angles(phase: float, amp: float) -> Array[float]:
	var swing := sin(phase) * SWING * amp
	return [swing, -swing, -swing, swing]
