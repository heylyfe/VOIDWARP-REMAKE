extends RefCounted
# Last Call (T-053; last_call.json, DESIGN.md section 8).
# "the final 20% of gold gifts in a level are worth double"
# The doubling itself is sim/economy.gd collect_gold_gift(final_band) - the CALLER decides
# the band and passes it in, because sim/ may not name a content id. What the band IS is
# content, so it lives here: the last ceil(0.2 x total) gold gifts of the level. The caller
# needs only two ints - the level's gold gift total and how many are already collected - so
# this file is pure arithmetic with no sim state. Until app/world.gd arms it, final_band
# is never true and the purchase still pays nothing.

const UPGRADE_ID := "last_call"
const BAND_PCT := 0.2


## How many of a level's gold gifts pay double: the last 20%, rounded up, so every level
## with at least one gold gift has at least one doubled gift. 0 for an empty level.
static func band_size(gold_total: int) -> int:
	if gold_total <= 0:
		return 0
	return int(ceil(float(gold_total) * BAND_PCT))


## True when the gold gift about to be collected is inside the final band.
## p_collected: how many of the level's p_gold_total gold gifts were already taken.
static func is_final_band(p_collected: int, p_gold_total: int) -> bool:
	var band := band_size(p_gold_total)
	if band <= 0:
		return false
	return p_collected >= p_gold_total - band
