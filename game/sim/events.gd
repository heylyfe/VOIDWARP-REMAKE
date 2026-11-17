extends RefCounted
#
# Event list (DESIGN.md section 13: step(state, inputs) -> events; ticket T-010).
# Events are derived data returned by sim.gd step(), never stored in state (D-T010-5) and never
# hashed. Every event is {"type": String, "tick": int, "player": int} plus type-specific
# int/float fields; new tickets append kinds here, not new shapes.

const EV_SPAWN := "spawn"
const EV_JUMP := "jump"
const EV_LAND := "land"
const EV_FALL := "fall"


static func make(p_type: String, p_tick: int, p_player: int) -> Dictionary:
	return {"type": p_type, "tick": p_tick, "player": p_player}
