extends RefCounted
#
# quick_recovery.gd - script upgrade (DESIGN.md section 8 row "quick_recovery").
# Rule sentence: "class ability cooldown -20% per stack (Athletic: +5% speed instead)".
#
# The upgrade has no JSON modifier and no hook: its whole effect is declared here and applied
# by the world, which keeps the upgrade id out of app/ (the boundary scan forbids a content id
# there). Two halves, one per class family:
#
#   - the cooldown knob (static knobs) for the classes that HAVE a class cooldown: the dasher's
#     dash regen and the glider's rise. The controller never reads a ledger, so the module
#     declares the knob and the world applies it.
#   - the Athletic half (static stat_mods): the Athletic has no class cooldown, so the rule
#     sentence gives it +5% run speed per stack instead. That is a run_speed contribution, and
#     it goes through the stat pipeline as an ordinary modifier dict - the same arithmetic a
#     JSON "modifiers" row gets - so run_speed stays the pipeline's to own and this module owns
#     only the number. The world repeats it per owned stack (D-B5A-1, which closes D-C2-5).

const UPGRADE_ID := "quick_recovery"
const COOLDOWN_PER_STACK := 0.2   # -20% per stack (max_stacks 2)
const SPEED_PER_STACK := 0.05     # Athletic: +5% run speed per stack (max_stacks 2)


## The controller knobs this upgrade sets, for the given owned stacks and class. The Athletic
## has no class cooldown, so it gets no cooldown knob - its half is stat_mods below.
static func knobs(stacks: Dictionary, kit: String) -> Dictionary:
	var n := maxi(0, int(stacks.get(UPGRADE_ID, 0)))
	if n <= 0 or kit == "athletic":
		return {}
	return {"cooldown_mul": maxf(0.0, 1.0 - COOLDOWN_PER_STACK * float(n))}


## The stat contribution ONE stack makes, as core/content_api.gd modifier dicts (the shape a
## JSON "modifiers" row has). The world repeats it per owned stack and hands the list to
## apply_modifiers(), so the pipeline multiplies it into run_speed for the classes it applies
## to. Athletic only: every other class's half is the cooldown knob above.
static func stat_mods(kit: String) -> Array:
	if kit != "athletic":
		return []
	return [{"stat": "run_speed", "op": "add", "value": SPEED_PER_STACK}]
