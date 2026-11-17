extends RefCounted
#
# dull_gifts.gd — the Dull Gifts script curse (DESIGN.md section 7.2, GENERAL family;
# ticket T-051).
#
# Rule: "black gift rim glow visible only within 20 u".
#
# The black gift's rim glow is a view-layer tell: the gift no longer radiates when the
# player is farther than 20 u (DESIGN.md section 3.2's camo rule, D-075 in DECISIONS).
# The glow never affects WHAT the sim announces (dull_gifts.json carries no such key) —
# the sim still counts every real gift in its own tally. Pure state, no engine surface.

const CURSE_ID := "dull_gifts"
const GLOW_RADIUS_U := 20.0  # DESIGN.md section 3.2 camo rule (D-075): 20 u


## Stacks the run holds; >= 1 while the curse is picked (the sim's {curse_id: stacks}).
static func stacks(state: Dictionary) -> int:
	return int(state.get("curses_held", {}).get(CURSE_ID, 0))


## True when the rim glow shows for this gift from this viewpoint. No stacks: the
## sim's own always-glow. One or more stacks: the glow is visible only within
## GLOW_RADIUS_U (20 u, D-T051-2).
## px/py/pz is the player's feet point, gx/gy/gz the black gift's body centre.
static func rim_glow_visible(state: Dictionary, px: float, py: float, pz: float,
		gx: float, gy: float, gz: float) -> bool:
	if stacks(state) <= 0:
		return true
	var dx: float = gx - px
	var dy: float = gy - py
	var dz: float = gz - pz
	var d2: float = dx * dx + dy * dy + dz * dz
	return d2 <= GLOW_RADIUS_U * GLOW_RADIUS_U + 1e-9

