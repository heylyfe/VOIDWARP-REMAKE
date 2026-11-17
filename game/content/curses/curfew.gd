extends RefCounted
#
# curfew.gd — the Curfew script curse (DESIGN.md section 7.2, GENERAL family;
# ticket T-051).
#
# Rule: "60 s after the beacon opens, overtime jumps +2 tiers".
#
# The open tick is recorded once by the on_beacon_open hook (the same tick sim/gifts.gd
# flips the phase, so 60 s of open beacon == 3600 whole ticks). on_tick fires the jump
# EXACTLY once per level at that tick: +2 tiers on the economy's overtime (sim/economy.gd),
# clamped at the economy's own overtime_max_tier — the cap is the game rule that was
# already there (curfew cannot push past it; the shortfall is the event's "tiers" value).
# One-shot: max_stacks is 1 and the rule names a single jump.
#
# 3600 = 60 s x 60 Hz; whole ticks only, no float clock.

const CURSE_ID := "curfew"
const JUMP_DELAY_TICKS := 3600  # 60 s after the beacon opens
const JUMP_TIERS := 2


## Stacks the run holds; >= 1 while the curse is picked (the sim's {curse_id: stacks}).
static func held_stacks(state: Dictionary) -> int:
	return int(state.get("curses_held", {}).get(CURSE_ID, 0))


## on_beacon_open(state, api): record the open tick.
static func on_beacon_open(state: Dictionary, _api) -> void:
	if held_stacks(state) <= 0:
		return
	var slot := _slot(state)
	slot["open_tick"] = int(state.get("tick", 0))
	slot["fired"] = false


## on_tick(state, api): the one-shot jump, once, at 3600 ticks past the open tick.
## Not held (or no open tick recorded): never fires.
static func on_tick(state: Dictionary, api) -> void:
	var slot := _slot(state)
	if not slot.has("open_tick") or bool(slot.get("fired", false)):
		return
	if held_stacks(state) <= 0:
		return
	if int(state.get("tick", 0)) - int(slot["open_tick"]) < JUMP_DELAY_TICKS:
		return
	var econ = state.get("economy", null)
	if econ == null:
		return
	var before := int(econ.overtime_tier)
	var limit := int(econ.overtime_max_tier)
	var after := mini(before + JUMP_TIERS, limit)
	econ.overtime_tier = after
	slot["fired"] = true
	var evs: Variant = state.get("events", null)
	if evs is Array:
		evs.append({"e": "curfew_jump", "tiers": after - before, "tick": int(state.get("tick", 0))})


# ---- per-curse state (the D-T051-1 shape: state["curse_st"][CURSE_ID]) ----------------

static func _slot(state: Dictionary) -> Dictionary:
	var root_v: Variant = state.get("curse_st", {})
	var root: Dictionary = {}
	if root_v is Dictionary:
		root = root_v
	if not root.has(CURSE_ID):
		root[CURSE_ID] = {}
	state["curse_st"] = root
	return root[CURSE_ID]

