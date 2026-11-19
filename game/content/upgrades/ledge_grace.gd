extends RefCounted
#
# ledge_grace.gd - script upgrade (DESIGN.md section 8 row "ledge_grace").
# Rule sentence: "coyote time +0.08 s per stack".
#
# The upgrade has no modifier and no hook: its whole effect is a controller knob, and the
# controller never reads a ledger. So the module declares the knob and the world applies it,
# which keeps the upgrade id out of app/ (the boundary scan forbids a content id there).

const UPGRADE_ID := "ledge_grace"
const COYOTE_PER_STACK := 0.08   # +0.08 s per stack (max_stacks 2)


## The controller knobs this upgrade sets, for the given owned stacks.
static func knobs(stacks: Dictionary, _kit: String) -> Dictionary:
	var n := maxi(0, int(stacks.get(UPGRADE_ID, 0)))
	if n <= 0:
		return {}
	return {"coyote_add": COYOTE_PER_STACK * float(n)}
