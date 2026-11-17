extends RefCounted
#
# crowded_dais.gd — the Crowded Dais script curse (DESIGN.md section 7.2, GENERAL family;
# ticket T-051).
#
# Rule: "the beacon cannot be entered while any enemy is within 8 u of it".
#
# Pure gate over the live sim state: the entry caller (the beacon's try_enter path in
# sim/beacon.gd) consults entry_blocked() before the entry is accepted. Distances are 3D
# from the enemy row origin to the beacon's axis point (cx, base_y, cz) — the same 3D
# reading the arbiter's no_enemy_body_within and Last Light's arrival push use
# (D-T072-1, D-073). "Within 8 u" is inclusive (exactly 8.000 u still blocks).
# Read-only: no world write happens here at all.

const CURSE_ID := "crowded_dais"
const BLOCK_RADIUS_U := 8.0  # DESIGN.md section 7.2, verbatim: "within 8 u of it"


## Stacks the run holds; >= 1 while the curse is picked (the sim's {curse_id: stacks}).
static func held_stacks(state: Dictionary) -> int:
	return int(state.get("curses_held", {}).get(CURSE_ID, 0))


## The entry gate. NOT held: never blocks (the beacon's own entry rules stand). Held:
## blocks while ANY enemy body sits within BLOCK_RADIUS_U of the beacon. state needs
## "beacon" (the sim/beacon.gd instance: cx / base_y / cz) and "enemies" (rows with
## x/y/z — the world mirror's shape). A missing beacon is never an entry gate.
static func entry_blocked(state: Dictionary) -> bool:
	if held_stacks(state) <= 0:
		return false
	var b = state.get("beacon", null)
	if b == null:
		return false
	var bx := float(b.cx)
	var by := float(b.base_y)
	var bz := float(b.cz)
	for e_v in state.get("enemies", []):
		var e = e_v
		if e == null or not e.has("x"):
			continue
		var dx: float = float(e["x"]) - bx
		var dy: float = float(e.get("y", 0.0)) - by
		var dz: float = float(e.get("z", 0.0)) - bz
		if dx * dx + dy * dy + dz * dz <= BLOCK_RADIUS_U * BLOCK_RADIUS_U + 1e-9:
			return true
	return false

