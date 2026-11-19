extends RefCounted
#
# nest_egg.gd - script upgrade (DESIGN.md section 8 row "nest_egg").
# Rule sentence: "on beacon entry gain 5% of unspent gold, max 30 g, per stack".
# Dispatched by sim/upgrade_runtime.gd on the beacon_enter event, BEFORE the app's economy
# pass pays the clear stipend: the interest is on the gold carried into the beacon, not on
# the stipend. Integer centi-gold, rounded down (the economy's rule); the 30 g cap is per
# stack, so 2 stacks pay 10% capped at 60 g.

const UPGRADE_ID := "nest_egg"
const PCT := 5               # % of the unspent purse, per stack
const CAP_CENTI := 3000      # 30 g per stack


static func held_stacks(state: Dictionary) -> int:
	return int(state.get("upgrades_held", {}).get(UPGRADE_ID, 0))


## The interest for a purse (centi), all stacks summed.
static func interest_centi(purse_centi: int, stacks: int) -> int:
	if purse_centi <= 0 or stacks <= 0:
		return 0
	var per := mini(purse_centi * PCT / 100, CAP_CENTI)
	return per * stacks


static func on_beacon_enter(state: Dictionary, api) -> void:
	if api == null:
		return
	api.add_centi(interest_centi(int(api.purse_centi()), held_stacks(state)))
