extends RefCounted
#
# sim/death.gd - death attribution (ticket T-021; DESIGN.md section 3.1).
#
# "Every death records its killer and a death code, shown on the run-over
# screen: D-<ENEMY> codes for each lethal enemy, D-VOID for a void fall plus
# D-CURSE:<curse id> when a curse caused the death."
#
# THE KILLER IS THE LAST THING THAT KILLED THE PLAYER: the controller (T-012)
# overwrites dead_code / dead_killer on every killing blow, so the stored pair
# is always the last one; attribute() reads exactly that pair. A kill that
# Last Light saved is not a death - the killer of a later real death is the
# later hazard. A void fall is its own killer (D-VOID): the controller's own
# void-fall path already stores code "D-VOID", killer "void" - no other killer
# is ever attributed to a fall, and a knockback or launch that does not kill is
# never the killer.
#
# The death code -> display-name table is NOT here: it is read from the content
# tree through core/roster.gd (each lethal enemy's stats.death_code and its
# death_name, D-FIX-A14-2), so a new enemy lands its own code and label in
# content with zero sim edits. An unknown code shows the code itself (never an
# empty screen). screen_data() builds the run-over screen row (killer, death
# code, level, purse) that the HUD (T-025) renders.
#
# Pure data + reads of the controller's stored fields: no engine types beyond
# Array/Dictionary, no RNG.

const RosterScript := preload("res://core/roster.gd")

## The tripmine's code (the contact ladder in sim/mines.gd).
const MINE_CODE := "D-MINE"
## A void fall is its own killer (D-VOID); the controller stores killer "void".
const VOID_CODE := "D-VOID"
## The killer string the controller stores for a void fall.
const VOID_KILLER := "void"
## The void's display name (the only killer no content owns).
const VOID_NAME := "the void"


## The code a curse death carries (DESIGN.md section 3.1): "D-CURSE:<curse id>".
static func curse_code(curse_id: String) -> String:
	return "D-CURSE:%s" % curse_id


## Killer display name for a code - the content roster's death names; D-CURSE:<id>
## named after the curse; an unknown code shows the code itself (never an empty screen).
static func killer_for(code: String) -> String:
	if code.begins_with("D-CURSE:"):
		return "curse %s" % code.substr(8)
	if code == VOID_CODE:
		return VOID_NAME
	var name := RosterScript.name_for_code(code)
	if name != "":
		return name
	return code


## The last thing that killed the player: {"code", "killer"} from the
## controller's stored pair (overwritten on every killing blow). An alive
## controller attributes nothing ({}).
static func attribute(ctl) -> Dictionary:
	if ctl == null or not bool(ctl.dead):
		return {}
	var code := str(ctl.dead_code)
	return {"code": code, "killer": killer_for(code)}


## The run-over screen row (DESIGN.md 3.1; rendered by the HUD, T-025).
##   code   the death code (e.g. "D-MINE", "D-VOID", "D-CURSE:<curse id>")
##   killer the roster killer name (e.g. the tripmine carrier's death_name)
##   level  the level number the run died on
##   purse  the gold held at death (owned by T-022's economy state; the caller
##          passes the live purse - the default marks "not tracked yet")
static func screen_data(ctl, p_level_number: int, purse: int = -1) -> Dictionary:
	var a := attribute(ctl)
	a["level"] = p_level_number
	a["purse"] = purse
	return a
