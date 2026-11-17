extends RefCounted
# Radar Module: Mines (T-053; radar_mines.json, addendum R4, D-T053-1, D-T053-8).
# "disguised tripmines within 14 u get a pink outline through fog [CANON]"
# Sim role + range; the pink outline itself is the mine view's outline pass fed by
# sim/upgrades.gd mine_outline_ids() (the HUD wiring reads sim level upgrades.roles).

const UPGRADE_ID := "radar_mines"
const ROLE := "mine_radar"
const RANGE_U := 14.0
