extends RefCounted
# Marathon (T-053; marathon.json, DESIGN.md section 8, D-T053-7).
# "Athletic only: +2 max stacks of Yearn for Speed"
# The pairing is the content layer's anchor: whoever draws the shop aggregates
# this script's max_bonus() into offers.draw_shop's p_max_stacks_bonus dict.

const UPGRADE_ID := "marathon"
const BONUS_STACKS := 2
const BOOSTED_ID := "yearn_for_speed"
const REQUIRED_CLASS := "athletic"


## The max-stacks bonus this purchase grants the shop draw: {} unless the current
## class is Athletic AND Marathon is owned.
static func max_bonus(p_class: String, p_stacks: Dictionary) -> Dictionary:
	if p_class != REQUIRED_CLASS or int(p_stacks.get(UPGRADE_ID, 0)) < 1:
		return {}
	return {BOOSTED_ID: BONUS_STACKS}
