extends RefCounted
#
# featherfall.gd - script upgrade (DESIGN.md section 8 row "featherfall").
# Rule sentence: "hold jump to cap fall speed at 6 u/s (Glider: +1.5 s glide energy instead)".
#
# The class split is the rule sentence's own: the Glider already falls slowly, so the same
# purchase buys it glide energy instead of a fall cap. The module declares both knobs and the
# world applies whichever one the run's class selects, which keeps the upgrade id out of app/.

const UPGRADE_ID := "featherfall"
const GLIDER_BONUS := 1.5   # +1.5 s glide energy for the Glider


## The controller knobs this upgrade sets, for the given owned stacks and class.
static func knobs(stacks: Dictionary, kit: String) -> Dictionary:
	if int(stacks.get(UPGRADE_ID, 0)) <= 0:
		return {}
	if kit == "glider":
		return {"glide_energy_bonus": GLIDER_BONUS}
	return {"feather_fall": true}
