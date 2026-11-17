extends RefCounted
# Radar Module: Gifts (T-053; radar_gifts.json, DESIGN.md section 8, D-T053-1).
# "arrow to the nearest real gift within 40 u (80 u at 2)"

const UPGRADE_ID := "radar_gifts"
const ROLE := "gift_radar"


## The radar range this stack count reaches (1 stack 40 u, 2 stacks 80 u, cap 2).
static func range_u(stacks: int) -> float:
	return 80.0 if int(stacks) >= 2 else 40.0
