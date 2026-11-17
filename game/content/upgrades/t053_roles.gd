extends RefCounted
# T-053 role aggregation (D-T053-1): the ONE place the batch's upgrade ids map onto
# sim roles. The app/shop wiring calls roles_for() when a level loads and hands the
# dict to RunState.upgrade_roles; sim never sees an id.

const RadarMines := preload("res://content/upgrades/radar_mines.gd")
const RadarBeacon := preload("res://content/upgrades/radar_beacon.gd")
const RadarGifts := preload("res://content/upgrades/radar_gifts.gd")
const RadarThreats := preload("res://content/upgrades/radar_threats.gd")
const Cartographer := preload("res://content/upgrades/cartographer.gd")
const SkeletonKey := preload("res://content/upgrades/skeleton_key.gd")
const PocketBeacon := preload("res://content/upgrades/pocket_beacon.gd")


## From the run's {upgrade id: stacks} ledger: the sim roles of every owned T-053
## scripted upgrade ({role: true} - the ranges live in the per-id scripts above).
static func roles_for(p_stacks: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	if int(p_stacks.get(RadarMines.UPGRADE_ID, 0)) >= 1:
		out[RadarMines.ROLE] = true
	if int(p_stacks.get(RadarBeacon.UPGRADE_ID, 0)) >= 1:
		out[RadarBeacon.ROLE] = true
	if int(p_stacks.get(RadarGifts.UPGRADE_ID, 0)) >= 1:
		out[RadarGifts.ROLE] = true
	if int(p_stacks.get(RadarThreats.UPGRADE_ID, 0)) >= 1:
		out[RadarThreats.ROLE] = true
	if int(p_stacks.get(Cartographer.UPGRADE_ID, 0)) >= 1:
		out[Cartographer.ROLE] = true
	if int(p_stacks.get(SkeletonKey.UPGRADE_ID, 0)) >= 1:
		out[SkeletonKey.ROLE] = true
	if int(p_stacks.get(PocketBeacon.UPGRADE_ID, 0)) >= 1:
		out[PocketBeacon.ROLE] = true
	return out
