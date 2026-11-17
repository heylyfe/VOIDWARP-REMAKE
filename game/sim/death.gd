extends RefCounted
#
# sim/death.gd - death attribution (ticket T-021; DESIGN.md section 3.1).
#
# "Every death records its killer and a death code, shown on the run-over
# screen: D-KIWI D-COIL D-ISAGI D-NUKE D-YOU D-MINE D-TOUCH D-SEAL D-ADDR
# D-CLAUDE D-GIN D-VOID plus D-CURSE:<curse id> when a curse caused the death."
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
# Killer names shown are the ROSTER names (DESIGN.md 3.1), e.g.
# "gift Larper (Tripmine)"; thicc ben has no death code because ben cannot kill.
# blame() maps a stored killer string or code to the display name; screen_data()
# builds the run-over screen row (killer, death code, level, purse) that the
# HUD (T-025) renders.
#
# Pure data + reads of the controller's stored fields: no engine types beyond
# Array/Dictionary, no RNG.

## The closed death-code -> killer display-name map (DESIGN.md section 3.1).
const CODES: Dictionary = {
	"D-KIWI": "kiwi cat",
	"D-COIL": "coil",
	"D-ISAGI": "Isagi",
	"D-NUKE": "nuke",
	"D-YOU": "YOU?!",
	"D-MINE": "gift Larper (Tripmine)",
	"D-TOUCH": "toucher",
	"D-SEAL": "seal",
	"D-ADDR": "address me",
	"D-CLAUDE": "Claude",
	"D-GIN": "gin ichimaru",
	"D-VOID": "the void",
}

## The tripmine's code + killer string (the contact ladder in sim/mines.gd).
const MINE_CODE := "D-MINE"
## A void fall is its own killer (D-VOID); the controller stores killer "void".
const VOID_CODE := "D-VOID"
## The killer string the controller stores for a void fall.
const VOID_KILLER := "void"


## The code a curse death carries (DESIGN.md section 3.1): "D-CURSE:<curse id>".
static func curse_code(curse_id: String) -> String:
	return "D-CURSE:%s" % curse_id


## Killer display name for a code - roster names; D-CURSE:<id> named after the
## curse; an unknown code shows the code itself (never an empty screen).
static func killer_for(code: String) -> String:
	if CODES.has(code):
		return str(CODES[code])
	if code.begins_with("D-CURSE:"):
		return "curse %s" % code.substr(8)
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
##   code   the death code (e.g. "D-MINE", "D-VOID", "D-CURSE:hungry_void")
##   killer the roster killer name (e.g. "gift Larper (Tripmine)")
##   level  the level number the run died on
##   purse  the gold held at death (owned by T-022's economy state; the caller
##          passes the live purse - the default marks "not tracked yet")
static func screen_data(ctl, p_level_number: int, purse: int = -1) -> Dictionary:
	var a := attribute(ctl)
	a["level"] = p_level_number
	a["purse"] = purse
	return a
