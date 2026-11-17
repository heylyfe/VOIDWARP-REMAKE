extends RefCounted
# Skeleton Key (T-053; skeleton_key.json, DESIGN.md section 8, D-T053-4).
# "the beacon opens at 90% of real black gifts; the rest turn gold in place"
# The quota lands on sim/gifts.gd black_quota at level build (level_state.gd); the
# remainder goes gold by the merged phase flip - no second conversion exists.

const UPGRADE_ID := "skeleton_key"
const ROLE := "skeleton_quota"
const OPEN_PCT := 0.9


## The collection count that opens the beacon at this level's real black total.
static func threshold(total_real: int) -> int:
	return int(ceil(float(total_real) * OPEN_PCT))
