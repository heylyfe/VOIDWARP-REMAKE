extends RefCounted
#
# stand_fast.gd - script upgrade (DESIGN.md section 8 row "stand_fast").
# Rule sentence: "the first chain-breaking event each level (void fall, defused or shielded
# tripmine, ben's eject) does not reset the chain".
# Dispatched by sim/upgrade_runtime.gd on void_fall, mine_defused and mine_shielded. Each
# of those events is raised together with a chain_reset entry in the same tick's list; the
# save marks that entry and the app's economy pass skips it. Once per level (the scratch
# upgrade_st is per level). A break while no chain is running (black phase, or the chain
# at x1.00) costs nothing, so it does not spend the save.
# NOT covered: the eject break - core/hooks.gd's closed list has no enemy-eject hook.

const UPGRADE_ID := "stand_fast"
const ST_USED := "stand_fast_used"


static func _try_save(state: Dictionary, api, why: String) -> void:
	if api == null or int(state.get("upgrades_held", {}).get(UPGRADE_ID, 0)) <= 0:
		return
	var st: Dictionary = state.get("upgrade_st", {})
	if bool(st.get(ST_USED, false)):
		return
	if not bool(api.chain_live()):
		return
	if bool(api.save_chain(why)):
		st[ST_USED] = true


static func on_void_fall(state: Dictionary, api) -> void:
	_try_save(state, api, "void_fall")


static func on_mine_defused(state: Dictionary, api) -> void:
	_try_save(state, api, "defused_mine")


static func on_barrier_absorbed(state: Dictionary, api) -> void:
	_try_save(state, api, "shielded_mine")
