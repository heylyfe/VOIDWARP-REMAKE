extends RefCounted
#
# brace.gd - script upgrade (DESIGN.md section 8 row "brace").
# Rule sentence: "coil's shockwave push and ben's eject -30% per stack".
#
# The upgrade has no modifier and no hook: its whole effect is a controller knob, and the
# controller never reads a ledger. So the module declares the knob and the world applies it,
# which keeps the upgrade id out of app/ (the boundary scan forbids a content id there) and
# keeps the number next to the rule sentence that states it.

const UPGRADE_ID := "brace"
const PUSH_PER_STACK := 0.3   # -30% per stack (max_stacks 3)


## The controller knobs this upgrade sets, for the given owned stacks.
## push_mul scales coil's shockwave push and ben's eject; the launch super-jump shrinks
## with it, which is the rule sentence's own consequence.
static func knobs(stacks: Dictionary, _kit: String) -> Dictionary:
	var n := maxi(0, int(stacks.get(UPGRADE_ID, 0)))
	if n <= 0:
		return {}
	return {"push_mul": maxf(0.0, 1.0 - PUSH_PER_STACK * float(n))}
