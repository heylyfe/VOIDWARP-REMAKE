extends RefCounted
#
# quick_recovery.gd - script upgrade (DESIGN.md section 8 row "quick_recovery").
# Rule sentence: "class ability cooldown -20% per stack (Athletic: +5% speed instead)".
#
# The upgrade has no modifier and no hook: its whole effect is a controller knob, and the
# controller never reads a ledger. So the module declares the knob and the world applies it,
# which keeps the upgrade id out of app/ (the boundary scan forbids a content id there).
#
# The Athletic branch is NOT wired: the Athletic has no class cooldown, so the rule sentence
# gives it +5% run speed instead, and the controller exposes no separate run-speed knob for a
# single upgrade to add to (run_speed_mul is owned by the stat pipeline). Returning {} for the
# Athletic is therefore the same live behaviour as before this module existed - the purchase is
# inert for that one class, and that is recorded rather than faked.

const UPGRADE_ID := "quick_recovery"
const COOLDOWN_PER_STACK := 0.2   # -20% per stack (max_stacks 2)


## The controller knobs this upgrade sets, for the given owned stacks and class.
static func knobs(stacks: Dictionary, kit: String) -> Dictionary:
	var n := maxi(0, int(stacks.get(UPGRADE_ID, 0)))
	if n <= 0 or kit == "athletic":
		return {}
	return {"cooldown_mul": maxf(0.0, 1.0 - COOLDOWN_PER_STACK * float(n))}
