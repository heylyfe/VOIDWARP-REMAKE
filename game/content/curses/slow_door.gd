extends RefCounted
#
# slow_door.gd — the Slow Door script curse (DESIGN.md section 7.2, GENERAL family;
# ticket T-051).
#
# Rule: "entering the beacon takes 3.0 s of standing in it".
#
# The dwell clock runs ONLY while the beacon is OPEN and the player's feet are inside
# its trigger cylinder (sim/beacon.gd contains(): radius 1.5 u, height 3 u); any tick
# outside (or before the open) resets that player's dwell to zero — "standing in it"
# is continuous presence. The beacon's own try_enter is the caller: it consults
# entry_ready() before accepting the entry (the dispatcher wires the call; the gate
# itself is fully built and tested here). 3.0 s = 180 whole 60 Hz ticks.

const CURSE_ID := "slow_door"
const DWELL_S := 3.0           # the rule sentence's 3.0 s of standing in it
const ENTRY_TICKS := 180       # DWELL_S at 60 Hz, whole ticks


## on_level_start(state, api): fresh dwell clocks (one per player index).
static func on_level_start(state: Dictionary, _api) -> void:
	_slot(state)  # creates {"dwell": {}}


## on_tick(state, api): advance/reset the dwell clocks. One call per 60 Hz tick; each
## tick inside the cylinder adds exactly 1/60 s. Not held: the clocks stay zeroed
## (the door opens instantly, exactly the no-curse beacon).
static func on_tick(state: Dictionary, _api) -> void:
	var slot := _slot(state)
	var dwell: Dictionary = slot["dwell"]
	if held_stacks(state) <= 0:
		for k in dwell.keys():
			dwell[k] = 0.0
		return
	var b = state.get("beacon", null)
	if b == null or not b.is_open():
		return  # a closed (or missing) beacon dwells nothing; clocks stay as they were
	for i in state.get("players", []).size():
		var ctl = state["players"][i]
		if ctl == null:
			continue
		if b.contains(float(ctl.x), float(ctl.y), float(ctl.z)):
			dwell[i] = minf(float(dwell.get(i, 0.0)) + 1.0 / 60.0, float(DWELL_S))
		else:
			dwell[i] = 0.0


## Stacks the run holds; >= 1 while the curse is picked (the sim's {curse_id: stacks}).
static func held_stacks(state: Dictionary) -> int:
	return int(state.get("curses_held", {}).get(CURSE_ID, 0))


## The gate the entry caller asks. NOT held: the door is instant (true — the no-curse
## beacon). Held: ready only after the full 3.0 s of continuous standing inside the
## OPEN beacon's trigger cylinder; exact equality at 180 ticks is already ready.
static func entry_ready(state: Dictionary, player_index: int) -> bool:
	if held_stacks(state) <= 0:
		return true
	var slot := _slot(state)
	return float(slot["dwell"].get(player_index, 0.0)) >= float(DWELL_S) - 1e-9


## Read helper for HUD/tests: the player's current dwell in seconds (0..3.0).
static func dwell_s(state: Dictionary, player_index: int) -> float:
	return float(_slot(state)["dwell"].get(player_index, 0.0))


# ---- per-curse state (the D-T051-1 shape: state["curse_st"][CURSE_ID]) ----------------

static func _slot(state: Dictionary) -> Dictionary:
	var root_v: Variant = state.get("curse_st", {})
	var root: Dictionary = {}
	if root_v is Dictionary:
		root = root_v
	if not root.has(CURSE_ID):
		root[CURSE_ID] = {"dwell": {}}
	state["curse_st"] = root
	return root[CURSE_ID]

