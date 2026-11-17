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
# T-020 (gifts, beacon, straggler beam):
const EV_GIFT_COLLECTED := "gift_collected"  # + slot: int, phase: "black"|"gold"
const EV_BEACON_OPENED := "beacon_opened"    # player -1: a world event
const EV_BEACON_ENTER := "beacon_enter"      # + charges: int (after the restore)
const EV_LEVEL_COMPLETE := "level_complete"
# T-023 (the intermission lobby):
const EV_ALTAR_SELECTED := "altar_selected"  # + bay: String ("E"|"C"|"U"|"REST"|"CLASS"),
                                             #   kind: String ("enemy"|"curse"|"upgrade"|"class"|
                                             #   "hunger"|"tithe"|"reroll"), id: String,
                                             #   cost: int (gold spent; bounty = negative cost)
const EV_GATE_OPENED := "gate_opened"        # player -1: every mandatory bay is resolved


static func make(p_type: String, p_tick: int, p_player: int) -> Dictionary:
	return {"type": p_type, "tick": p_tick, "player": p_player}
